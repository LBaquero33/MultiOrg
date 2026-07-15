-- Home Plate Phase 9B: APNs device registration and delivery queue.
--
-- Phase 9A sd_notifications remains the source of truth. This migration adds
-- device registrations, durable delivery attempts, service-role-only queue
-- RPCs, an after-commit pg_net wakeup, and a one-minute retry fallback. It
-- never calls APNs from PostgreSQL and never changes notification ownership or
-- financial state.
--
-- Before deployment, create database Vault secrets named
-- notification_delivery_worker_url and notification_delivery_worker_secret.
-- The latter must match the Edge Function secret of the same purpose.
--
-- Rollback: stop/unschedule home-plate-notification-delivery-worker, remove the
-- queue trigger and RPCs, then drop sd_notification_deliveries and
-- sd_push_devices. Keep sd_notifications as the canonical in-app history.

create extension if not exists supabase_vault with schema vault;
create extension if not exists pg_net with schema extensions;
create extension if not exists pg_cron with schema pg_catalog;

create table if not exists public.sd_push_devices (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  device_token text not null,
  platform text not null,
  environment text not null,
  app_bundle_id text not null,
  app_version text,
  os_version text,
  notifications_authorized boolean not null default true,
  last_registered_at timestamptz not null default pg_catalog.now(),
  last_seen_at timestamptz not null default pg_catalog.now(),
  disabled_at timestamptz,
  disable_reason text,
  created_at timestamptz not null default pg_catalog.now(),
  updated_at timestamptz not null default pg_catalog.now(),
  constraint sd_push_devices_token_check check (
    device_token = pg_catalog.lower(device_token)
    and device_token ~ '^[0-9a-f]+$'
    and pg_catalog.char_length(device_token) between 64 and 400
    and pg_catalog.char_length(device_token) % 2 = 0
  ),
  constraint sd_push_devices_platform_check
    check (platform in ('ios', 'macos')),
  constraint sd_push_devices_environment_check
    check (environment in ('sandbox', 'production')),
  constraint sd_push_devices_bundle_check check (
    pg_catalog.char_length(app_bundle_id) between 3 and 255
    and app_bundle_id ~ '^[A-Za-z0-9][A-Za-z0-9.-]+$'
  ),
  constraint sd_push_devices_app_version_check
    check (app_version is null or pg_catalog.char_length(app_version) <= 80),
  constraint sd_push_devices_os_version_check
    check (os_version is null or pg_catalog.char_length(os_version) <= 80),
  constraint sd_push_devices_disable_reason_check
    check (disable_reason is null or pg_catalog.char_length(disable_reason) <= 120),
  constraint sd_push_devices_disable_state_check check (
    (disabled_at is null and disable_reason is null)
    or disabled_at is not null
  ),
  unique (device_token, environment, app_bundle_id)
);

comment on table public.sd_push_devices is
  'Actor-owned APNs device registrations; never stores Apple credentials or user-readable device names.';
comment on column public.sd_push_devices.device_token is
  'Canonical lowercase hexadecimal APNs token. Full values must not be logged.';

create index if not exists idx_sd_push_devices_user_active
  on public.sd_push_devices(user_id, platform, environment, last_registered_at desc)
  where disabled_at is null and notifications_authorized;
create index if not exists idx_sd_push_devices_active_token
  on public.sd_push_devices(environment, app_bundle_id, last_seen_at desc)
  where disabled_at is null and notifications_authorized;

alter table public.sd_push_devices enable row level security;
revoke all on table public.sd_push_devices from public, anon, authenticated;
grant select on table public.sd_push_devices to authenticated;
grant select, insert, update on table public.sd_push_devices to service_role;

drop policy if exists "sd_push_devices_select_own" on public.sd_push_devices;
create policy "sd_push_devices_select_own"
  on public.sd_push_devices
  for select
  to authenticated
  using (user_id = (select auth.uid()));

create table if not exists public.sd_notification_deliveries (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  notification_id uuid not null references public.sd_notifications(id) on delete cascade,
  device_id uuid not null references public.sd_push_devices(id) on delete restrict,
  channel text not null default 'apns',
  status text not null default 'pending',
  attempt_count integer not null default 0,
  claim_token uuid,
  claimed_at timestamptz,
  apns_id text,
  apns_status integer,
  error_code text,
  next_attempt_at timestamptz not null default pg_catalog.now(),
  sent_at timestamptz,
  failed_at timestamptz,
  created_at timestamptz not null default pg_catalog.now(),
  updated_at timestamptz not null default pg_catalog.now(),
  constraint sd_notification_deliveries_channel_check check (channel = 'apns'),
  constraint sd_notification_deliveries_status_check check (
    status in ('pending', 'sending', 'sent', 'retryable', 'failed', 'skipped')
  ),
  constraint sd_notification_deliveries_attempt_check
    check (attempt_count between 0 and 5),
  constraint sd_notification_deliveries_apns_id_check
    check (apns_id is null or pg_catalog.char_length(apns_id) <= 80),
  constraint sd_notification_deliveries_apns_status_check
    check (apns_status is null or apns_status between 100 and 599),
  constraint sd_notification_deliveries_error_check
    check (error_code is null or pg_catalog.char_length(error_code) <= 120),
  unique (notification_id, device_id, channel)
);

comment on table public.sd_notification_deliveries is
  'Server-only durable APNs queue. Inbox rows remain valid regardless of delivery outcome.';

create index if not exists idx_sd_notification_deliveries_ready
  on public.sd_notification_deliveries(status, next_attempt_at, created_at)
  where status in ('pending', 'retryable');
create index if not exists idx_sd_notification_deliveries_stale_claim
  on public.sd_notification_deliveries(claimed_at)
  where status = 'sending';
create index if not exists idx_sd_notification_deliveries_notification
  on public.sd_notification_deliveries(notification_id, status);
create index if not exists idx_sd_notification_deliveries_device
  on public.sd_notification_deliveries(device_id, created_at desc);

alter table public.sd_notification_deliveries enable row level security;
revoke all on table public.sd_notification_deliveries
from public, anon, authenticated, service_role;
grant select, insert, update on table public.sd_notification_deliveries to service_role;

create or replace function public.sd_push_touch_updated_at()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  new.updated_at := pg_catalog.now();
  return new;
end;
$$;

revoke all on function public.sd_push_touch_updated_at()
from public, anon, authenticated;

drop trigger if exists trg_sd_push_devices_touch on public.sd_push_devices;
create trigger trg_sd_push_devices_touch
before update on public.sd_push_devices
for each row execute function public.sd_push_touch_updated_at();

drop trigger if exists trg_sd_notification_deliveries_touch
on public.sd_notification_deliveries;
create trigger trg_sd_notification_deliveries_touch
before update on public.sd_notification_deliveries
for each row execute function public.sd_push_touch_updated_at();

-- Registration is service-role-only because the authenticated Edge Function
-- transfers the verified JWT actor into p_actor_id. A token can have only one
-- current owner. Transferring it skips unsent work for the previous account.
create or replace function public.sd_register_push_device(
  p_actor_id uuid,
  p_device_token text,
  p_platform text,
  p_environment text,
  p_app_bundle_id text,
  p_app_version text,
  p_os_version text,
  p_notifications_authorized boolean
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_device public.sd_push_devices%rowtype;
  v_token text := pg_catalog.lower(pg_catalog.btrim(p_device_token));
  v_now timestamptz := pg_catalog.now();
begin
  if p_actor_id is null
    or v_token !~ '^[0-9a-f]+$'
    or pg_catalog.char_length(v_token) not between 64 and 400
    or pg_catalog.char_length(v_token) % 2 <> 0
    or p_platform not in ('ios', 'macos')
    or p_environment not in ('sandbox', 'production')
    or pg_catalog.char_length(pg_catalog.btrim(p_app_bundle_id)) not between 3 and 255
    or p_notifications_authorized is null
    or pg_catalog.char_length(coalesce(p_app_version, '')) > 80
    or pg_catalog.char_length(coalesce(p_os_version, '')) > 80 then
    raise exception 'invalid_push_device_input' using errcode = '22023';
  end if;

  select device.* into v_device
  from public.sd_push_devices device
  where device.device_token = v_token
    and device.environment = p_environment
    and device.app_bundle_id = pg_catalog.btrim(p_app_bundle_id)
  for update;

  if v_device.id is not null and v_device.user_id is distinct from p_actor_id then
    update public.sd_notification_deliveries delivery
    set status = 'skipped',
        error_code = 'token_transferred',
        failed_at = v_now,
        claim_token = null,
        claimed_at = null
    where delivery.device_id = v_device.id
      and delivery.status in ('pending', 'retryable', 'sending');
  end if;

  if v_device.id is null then
    insert into public.sd_push_devices (
      user_id, device_token, platform, environment, app_bundle_id,
      app_version, os_version, notifications_authorized,
      last_registered_at, last_seen_at, disabled_at, disable_reason
    ) values (
      p_actor_id, v_token, p_platform, p_environment,
      pg_catalog.btrim(p_app_bundle_id), nullif(pg_catalog.btrim(p_app_version), ''),
      nullif(pg_catalog.btrim(p_os_version), ''), p_notifications_authorized,
      v_now, v_now,
      case when p_notifications_authorized then null else v_now end,
      case when p_notifications_authorized then null else 'notifications_not_authorized' end
    ) returning * into v_device;
  else
    update public.sd_push_devices device
    set user_id = p_actor_id,
        platform = p_platform,
        app_version = nullif(pg_catalog.btrim(p_app_version), ''),
        os_version = nullif(pg_catalog.btrim(p_os_version), ''),
        notifications_authorized = p_notifications_authorized,
        last_registered_at = v_now,
        last_seen_at = v_now,
        disabled_at = case when p_notifications_authorized then null else v_now end,
        disable_reason = case when p_notifications_authorized then null else 'notifications_not_authorized' end
    where device.id = v_device.id
    returning * into v_device;
  end if;

  return pg_catalog.jsonb_build_object(
    'device', pg_catalog.jsonb_build_object(
      'id', v_device.id,
      'platform', v_device.platform,
      'environment', v_device.environment,
      'app_bundle_id', v_device.app_bundle_id,
      'notifications_authorized', v_device.notifications_authorized,
      'last_registered_at', v_device.last_registered_at,
      'disabled_at', v_device.disabled_at
    )
  );
end;
$$;

revoke all on function public.sd_register_push_device(
  uuid, text, text, text, text, text, text, boolean
) from public, anon, authenticated;
grant execute on function public.sd_register_push_device(
  uuid, text, text, text, text, text, text, boolean
) to service_role;

create or replace function public.sd_unregister_push_device(
  p_actor_id uuid,
  p_device_token text,
  p_environment text,
  p_app_bundle_id text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_device_id uuid;
  v_now timestamptz := pg_catalog.now();
begin
  update public.sd_push_devices device
  set notifications_authorized = false,
      disabled_at = v_now,
      disable_reason = 'user_unregistered',
      last_seen_at = v_now
  where device.user_id = p_actor_id
    and device.device_token = pg_catalog.lower(pg_catalog.btrim(p_device_token))
    and device.environment = p_environment
    and device.app_bundle_id = pg_catalog.btrim(p_app_bundle_id)
    and device.disabled_at is null
  returning device.id into v_device_id;

  if v_device_id is not null then
    update public.sd_notification_deliveries delivery
    set status = 'skipped',
        error_code = 'user_unregistered',
        failed_at = v_now,
        claim_token = null,
        claimed_at = null
    where delivery.device_id = v_device_id
      and delivery.status in ('pending', 'retryable', 'sending');
  end if;

  return pg_catalog.jsonb_build_object('unregistered', v_device_id is not null);
end;
$$;

revoke all on function public.sd_unregister_push_device(uuid, text, text, text)
from public, anon, authenticated;
grant execute on function public.sd_unregister_push_device(uuid, text, text, text)
to service_role;

-- The database stores only the worker URL and a dedicated internal secret in
-- Vault. pg_net performs the HTTPS request after commit; missing configuration
-- leaves delivery rows pending for the cron fallback and never rolls back the
-- source notification.
create or replace function public.sd_request_notification_delivery_worker()
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
  where secret.name = 'notification_delivery_worker_url'
  limit 1;
  select secret.decrypted_secret into v_secret
  from vault.decrypted_secrets secret
  where secret.name = 'notification_delivery_worker_secret'
  limit 1;
  if nullif(pg_catalog.btrim(v_url), '') is null
    or nullif(pg_catalog.btrim(v_secret), '') is null then
    raise warning 'notification_delivery_worker_not_configured';
    return null;
  end if;
  select net.http_post(
    url := v_url,
    headers := pg_catalog.jsonb_build_object(
      'content-type', 'application/json',
      'x-home-plate-worker-secret', v_secret
    ),
    body := '{"source":"database_queue"}'::jsonb,
    timeout_milliseconds := 5000
  ) into v_request_id;
  return v_request_id;
exception when others then
  raise warning 'notification_delivery_worker_wakeup_failed';
  return null;
end;
$$;

revoke all on function public.sd_request_notification_delivery_worker()
from public, anon, authenticated, service_role;

-- One statement-level trigger queues all active devices for the notification
-- rows created by a producer call. Unique(notification, device, channel) makes
-- producer retries harmless. It intentionally does nothing when no device is
-- registered; the in-app notification still exists.
create or replace function public.sd_queue_apns_deliveries()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_created_count integer := 0;
begin
  insert into public.sd_notification_deliveries (
    notification_id, device_id, channel, status, next_attempt_at
  )
  select notification.id, device.id, 'apns', 'pending', pg_catalog.now()
  from notification_rows notification
  join public.sd_push_devices device
    on device.user_id = notification.recipient_user_id
   and device.notifications_authorized
   and device.disabled_at is null
  where notification.category in (
    'payment_request_created', 'payment_received', 'organization_announcement'
  )
  on conflict (notification_id, device_id, channel) do nothing;
  get diagnostics v_created_count = row_count;
  if v_created_count > 0 then
    perform public.sd_request_notification_delivery_worker();
  end if;
  return null;
end;
$$;

revoke all on function public.sd_queue_apns_deliveries()
from public, anon, authenticated;
drop trigger if exists trg_sd_queue_apns_deliveries on public.sd_notifications;
create trigger trg_sd_queue_apns_deliveries
after insert on public.sd_notifications
referencing new table as notification_rows
for each statement execute function public.sd_queue_apns_deliveries();

-- Claims are bounded and concurrency-safe. Stale five-minute claims can be
-- recovered, with at most five total attempts. Device ownership is checked
-- again at claim time so a transferred token cannot receive the old user's
-- queued notification.
create or replace function public.sd_claim_notification_deliveries(
  p_limit integer,
  p_claim_token uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_result jsonb;
begin
  if p_limit is null or p_limit not between 1 and 100 or p_claim_token is null then
    raise exception 'invalid_delivery_claim' using errcode = '22023';
  end if;

  update public.sd_notification_deliveries delivery
  set status = 'skipped',
      error_code = 'device_no_longer_eligible',
      failed_at = pg_catalog.now(),
      claim_token = null,
      claimed_at = null
  where delivery.status in ('pending', 'retryable')
    and not exists (
      select 1
      from public.sd_push_devices device
      join public.sd_notifications notification
        on notification.id = delivery.notification_id
      where device.id = delivery.device_id
        and device.user_id = notification.recipient_user_id
        and device.notifications_authorized
        and device.disabled_at is null
        and notification.archived_at is null
    );

  with candidates as (
    select delivery.id
    from public.sd_notification_deliveries delivery
    join public.sd_push_devices device on device.id = delivery.device_id
    join public.sd_notifications notification on notification.id = delivery.notification_id
    where delivery.attempt_count < 5
      and notification.archived_at is null
      and device.disabled_at is null
      and device.notifications_authorized
      and device.user_id = notification.recipient_user_id
      and (
        (delivery.status in ('pending', 'retryable')
          and delivery.next_attempt_at <= pg_catalog.now())
        or (delivery.status = 'sending'
          and delivery.claimed_at < pg_catalog.now() - interval '5 minutes')
      )
    order by delivery.next_attempt_at, delivery.created_at, delivery.id
    for update of delivery skip locked
    limit p_limit
  ), claimed as (
    update public.sd_notification_deliveries delivery
    set status = 'sending',
        attempt_count = delivery.attempt_count + 1,
        claim_token = p_claim_token,
        claimed_at = pg_catalog.now(),
        error_code = null
    from candidates
    where delivery.id = candidates.id
    returning delivery.*
  )
  select coalesce(pg_catalog.jsonb_agg(
    pg_catalog.jsonb_build_object(
      'delivery_id', claimed.id,
      'attempt_count', claimed.attempt_count,
      'notification', pg_catalog.jsonb_build_object(
        'id', notification.id,
        'org_id', notification.org_id,
        'category', notification.category,
        'title', notification.title,
        'body', notification.body,
        'action_route', notification.action_route,
        'action_payload', notification.action_payload
      ),
      'device', pg_catalog.jsonb_build_object(
        'id', device.id,
        'platform', device.platform,
        'environment', device.environment,
        'app_bundle_id', device.app_bundle_id,
        'device_token', device.device_token
      ),
      'unread_count', (
        select pg_catalog.count(*)
        from public.sd_notifications unread
        where unread.recipient_user_id = notification.recipient_user_id
          and unread.read_at is null
          and unread.archived_at is null
      )
    ) order by claimed.created_at, claimed.id
  ), '[]'::jsonb)
  into v_result
  from claimed
  join public.sd_notifications notification on notification.id = claimed.notification_id
  join public.sd_push_devices device on device.id = claimed.device_id;

  return pg_catalog.jsonb_build_object(
    'claim_token', p_claim_token,
    'deliveries', v_result
  );
end;
$$;

revoke all on function public.sd_claim_notification_deliveries(integer, uuid)
from public, anon, authenticated;
grant execute on function public.sd_claim_notification_deliveries(integer, uuid)
to service_role;

create or replace function public.sd_finalize_notification_delivery(
  p_delivery_id uuid,
  p_claim_token uuid,
  p_outcome text,
  p_apns_id text,
  p_apns_status integer,
  p_error_code text,
  p_next_attempt_at timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_delivery public.sd_notification_deliveries%rowtype;
  v_status text;
  v_now timestamptz := pg_catalog.now();
begin
  if p_delivery_id is null or p_claim_token is null
    or p_outcome not in ('sent', 'retryable', 'failed', 'permanent_token', 'skipped')
    or pg_catalog.char_length(coalesce(p_apns_id, '')) > 80
    or (p_apns_status is not null and p_apns_status not between 100 and 599)
    or pg_catalog.char_length(coalesce(p_error_code, '')) > 120 then
    raise exception 'invalid_delivery_result' using errcode = '22023';
  end if;

  select delivery.* into v_delivery
  from public.sd_notification_deliveries delivery
  where delivery.id = p_delivery_id
  for update;
  if v_delivery.id is null
    or v_delivery.status <> 'sending'
    or v_delivery.claim_token is distinct from p_claim_token then
    raise exception 'delivery_claim_mismatch' using errcode = 'P0001';
  end if;

  v_status := case
    when p_outcome = 'sent' then 'sent'
    when p_outcome = 'retryable' and v_delivery.attempt_count < 5 then 'retryable'
    when p_outcome = 'skipped' then 'skipped'
    else 'failed'
  end;

  update public.sd_notification_deliveries delivery
  set status = v_status,
      apns_id = nullif(pg_catalog.btrim(p_apns_id), ''),
      apns_status = p_apns_status,
      error_code = nullif(pg_catalog.btrim(p_error_code), ''),
      next_attempt_at = case
        when v_status = 'retryable' then coalesce(p_next_attempt_at, v_now + interval '5 minutes')
        else delivery.next_attempt_at
      end,
      sent_at = case when v_status = 'sent' then v_now else delivery.sent_at end,
      failed_at = case when v_status in ('failed', 'skipped') then v_now else null end,
      claim_token = null,
      claimed_at = null
  where delivery.id = v_delivery.id
  returning * into v_delivery;

  if p_outcome = 'permanent_token' then
    update public.sd_push_devices device
    set notifications_authorized = false,
        disabled_at = v_now,
        disable_reason = coalesce(nullif(pg_catalog.btrim(p_error_code), ''), 'invalid_apns_token')
    where device.id = v_delivery.device_id;

    update public.sd_notification_deliveries delivery
    set status = 'skipped',
        error_code = 'device_disabled',
        failed_at = v_now,
        claim_token = null,
        claimed_at = null
    where delivery.device_id = v_delivery.device_id
      and delivery.id <> v_delivery.id
      and delivery.status in ('pending', 'retryable');
  end if;

  return pg_catalog.jsonb_build_object(
    'delivery_id', v_delivery.id,
    'status', v_delivery.status,
    'attempt_count', v_delivery.attempt_count
  );
end;
$$;

revoke all on function public.sd_finalize_notification_delivery(
  uuid, uuid, text, text, integer, text, timestamptz
) from public, anon, authenticated;
grant execute on function public.sd_finalize_notification_delivery(
  uuid, uuid, text, text, integer, text, timestamptz
) to service_role;

-- The insert trigger normally wakes the worker within seconds. This minute
-- fallback picks up transient retries and missed wakeups. It contains no URL or
-- credential; both are resolved from Vault only at execution time.
do $$
declare
  v_job_id bigint;
begin
  for v_job_id in
    select job.jobid from cron.job job
    where job.jobname = 'home-plate-notification-delivery-worker'
  loop
    perform cron.unschedule(v_job_id);
  end loop;
  perform cron.schedule(
    'home-plate-notification-delivery-worker',
    '* * * * *',
    'select public.sd_request_notification_delivery_worker();'
  );
end;
$$;
