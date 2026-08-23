-- Home Plate calendar integrations: encrypted per-user connections, durable
-- source links, and a service-only sync queue. Google credentials are written
-- only by the calendar-integrations Edge Function after OAuth state validation.

create table if not exists public.sd_calendar_connections (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  organization_id uuid not null references public.sd_orgs(id) on delete cascade,
  provider text not null check (provider in ('google')),
  provider_account_email text,
  calendar_id text not null default 'primary',
  access_token_ciphertext text not null,
  refresh_token_ciphertext text,
  token_expires_at timestamptz,
  sync_token_ciphertext text,
  channel_id text,
  channel_resource_id text,
  channel_token_hash text,
  channel_expires_at timestamptz,
  status text not null default 'active' check (
    status in ('active','needs_reauthorization','disconnected')
  ),
  last_synced_at timestamptz,
  last_error_code text,
  created_at timestamptz not null default pg_catalog.now(),
  updated_at timestamptz not null default pg_catalog.now(),
  unique (user_id, organization_id, provider, calendar_id),
  check (pg_catalog.char_length(calendar_id) between 1 and 512),
  check (last_error_code is null or pg_catalog.char_length(last_error_code) <= 80)
);

create table if not exists public.sd_calendar_oauth_states (
  state_hash text primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  organization_id uuid not null references public.sd_orgs(id) on delete cascade,
  code_verifier_ciphertext text not null,
  return_url text not null,
  expires_at timestamptz not null,
  consumed_at timestamptz,
  created_at timestamptz not null default pg_catalog.now(),
  check (pg_catalog.char_length(state_hash) = 64),
  check (expires_at <= created_at + interval '15 minutes')
);

create table if not exists public.sd_calendar_event_links (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  connection_id uuid not null references public.sd_calendar_connections(id) on delete cascade,
  organization_id uuid not null references public.sd_orgs(id) on delete cascade,
  source_kind text not null check (
    source_kind in ('sd_events','sd_team_events','sd_facility_bookings')
  ),
  source_id uuid not null,
  provider_event_id text not null,
  provider_etag text,
  last_source text not null default 'home_plate' check (
    last_source in ('home_plate','google')
  ),
  last_provider_updated_at timestamptz,
  last_home_plate_updated_at timestamptz,
  created_at timestamptz not null default pg_catalog.now(),
  updated_at timestamptz not null default pg_catalog.now(),
  unique (connection_id, source_kind, source_id),
  unique (connection_id, provider_event_id)
);

create table if not exists public.sd_calendar_sync_jobs (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  connection_id uuid not null references public.sd_calendar_connections(id) on delete cascade,
  organization_id uuid not null references public.sd_orgs(id) on delete cascade,
  source_kind text not null check (
    source_kind in ('sd_events','sd_team_events','sd_facility_bookings','connection')
  ),
  source_id uuid,
  operation text not null check (operation in ('upsert','cancel','pull','renew_watch')),
  status text not null default 'pending' check (
    status in ('pending','processing','completed','retryable','failed','skipped')
  ),
  attempt_count integer not null default 0 check (attempt_count between 0 and 20),
  next_attempt_at timestamptz not null default pg_catalog.now(),
  claimed_at timestamptz,
  completed_at timestamptz,
  last_error_code text,
  created_at timestamptz not null default pg_catalog.now(),
  updated_at timestamptz not null default pg_catalog.now(),
  check ((source_kind = 'connection') = (source_id is null)),
  check (last_error_code is null or pg_catalog.char_length(last_error_code) <= 80)
);

create index if not exists idx_sd_calendar_jobs_claim
  on public.sd_calendar_sync_jobs(status, next_attempt_at, created_at);
create index if not exists idx_sd_calendar_links_source
  on public.sd_calendar_event_links(source_kind, source_id);
create index if not exists idx_sd_calendar_connections_channel
  on public.sd_calendar_connections(channel_id)
  where channel_id is not null and status = 'active';

alter table public.sd_calendar_connections enable row level security;
alter table public.sd_calendar_oauth_states enable row level security;
alter table public.sd_calendar_event_links enable row level security;
alter table public.sd_calendar_sync_jobs enable row level security;

revoke all on public.sd_calendar_connections from public, anon, authenticated, service_role;
revoke all on public.sd_calendar_oauth_states from public, anon, authenticated, service_role;
revoke all on public.sd_calendar_event_links from public, anon, authenticated, service_role;
revoke all on public.sd_calendar_sync_jobs from public, anon, authenticated, service_role;
grant select, insert, update, delete on public.sd_calendar_connections to service_role;
grant select, insert, update, delete on public.sd_calendar_oauth_states to service_role;
grant select, insert, update, delete on public.sd_calendar_event_links to service_role;
grant select, insert, update, delete on public.sd_calendar_sync_jobs to service_role;

create or replace function public.sd_request_calendar_sync_worker()
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_url text;
  v_secret text;
  v_request_id bigint;
begin
  select secret.decrypted_secret into v_url
  from vault.decrypted_secrets secret
  where secret.name = 'calendar_sync_worker_url'
  limit 1;
  select secret.decrypted_secret into v_secret
  from vault.decrypted_secrets secret
  where secret.name = 'calendar_sync_worker_secret'
  limit 1;
  if nullif(pg_catalog.btrim(v_url), '') is null
    or nullif(pg_catalog.btrim(v_secret), '') is null then
    raise warning 'calendar_sync_worker_not_configured';
    return null;
  end if;
  select net.http_post(
    url := pg_catalog.btrim(v_url),
    headers := pg_catalog.jsonb_build_object(
      'content-type', 'application/json',
      'x-home-plate-calendar-worker-secret', v_secret
    ),
    body := '{}'::jsonb,
    timeout_milliseconds := 10000
  ) into v_request_id;
  return v_request_id;
exception when others then
  raise warning 'calendar_sync_worker_wakeup_failed';
  return null;
end;
$$;

revoke all on function public.sd_request_calendar_sync_worker()
from public, anon, authenticated, service_role;

create or replace function public.sd_claim_calendar_sync_jobs(p_limit integer default 20)
returns setof public.sd_calendar_sync_jobs
language plpgsql
security definer
set search_path = ''
as $$
begin
  return query
  with claimable as (
    select job.id
    from public.sd_calendar_sync_jobs job
    where job.status in ('pending','retryable')
      and job.next_attempt_at <= pg_catalog.now()
    order by job.created_at
    for update skip locked
    limit pg_catalog.least(pg_catalog.greatest(p_limit, 1), 50)
  )
  update public.sd_calendar_sync_jobs job
  set status = 'processing',
      claimed_at = pg_catalog.now(),
      attempt_count = job.attempt_count + 1,
      updated_at = pg_catalog.now()
  from claimable
  where job.id = claimable.id
  returning job.*;
end;
$$;

revoke all on function public.sd_claim_calendar_sync_jobs(integer)
from public, anon, authenticated;
grant execute on function public.sd_claim_calendar_sync_jobs(integer) to service_role;

create or replace function public.sd_queue_calendar_source_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org_id uuid;
  v_status text;
  v_operation text;
begin
  v_org_id := case tg_table_name
    when 'sd_events' then coalesce(new.org_id, old.org_id)
    when 'sd_team_events' then coalesce(new.organization_id, old.organization_id)
    when 'sd_facility_bookings' then coalesce(new.org_id, old.org_id)
  end;
  v_status := case
    when tg_op = 'DELETE' then 'deleted'
    when tg_table_name = 'sd_events' then coalesce(new.status, '')
    when tg_table_name = 'sd_team_events' then coalesce(new.status, '')
    when tg_table_name = 'sd_facility_bookings' then coalesce(new.status, '')
  end;
  v_operation := case
    when v_status in ('canceled','cancelled','denied','deleted') then 'cancel'
    else 'upsert'
  end;

  insert into public.sd_calendar_sync_jobs (
    connection_id, organization_id, source_kind, source_id, operation
  )
  select connection.id, v_org_id, tg_table_name, coalesce(new.id, old.id), v_operation
  from public.sd_calendar_connections connection
  where connection.organization_id = v_org_id
    and connection.status = 'active';
  perform public.sd_request_calendar_sync_worker();
  return new;
end;
$$;

revoke all on function public.sd_queue_calendar_source_change()
from public, anon, authenticated, service_role;

drop trigger if exists trg_sd_events_calendar_sync on public.sd_events;
create trigger trg_sd_events_calendar_sync
after insert or delete or update of title,description,scheduled_start,scheduled_end,location_name,venue_address,status
on public.sd_events for each row execute function public.sd_queue_calendar_source_change();

drop trigger if exists trg_sd_team_events_calendar_sync on public.sd_team_events;
create trigger trg_sd_team_events_calendar_sync
after insert or delete or update of title,description,start_at,end_at,location_name,address,status
on public.sd_team_events for each row execute function public.sd_queue_calendar_source_change();

drop trigger if exists trg_sd_facility_bookings_calendar_sync on public.sd_facility_bookings;
create trigger trg_sd_facility_bookings_calendar_sync
after insert or delete or update of title,start_at,end_at,status,notes
on public.sd_facility_bookings for each row execute function public.sd_queue_calendar_source_change();

comment on table public.sd_calendar_connections is
  'Service-only encrypted Google Calendar connections. OAuth tokens never enter client-readable tables.';
comment on table public.sd_calendar_event_links is
  'Opaque provider event mappings. Bookings synchronize outward only; provider edits never approve or deny bookings.';
comment on table public.sd_calendar_sync_jobs is
  'Durable per-connection calendar outbox processed by calendar-integrations.';

do $$
declare
  v_job_id bigint;
begin
  for v_job_id in
    select job.jobid from cron.job job
    where job.jobname = 'home-plate-calendar-sync-worker'
  loop
    perform cron.unschedule(v_job_id);
  end loop;
  perform cron.schedule(
    'home-plate-calendar-sync-worker',
    '* * * * *',
    'select public.sd_request_calendar_sync_worker();'
  );
end;
$$;
