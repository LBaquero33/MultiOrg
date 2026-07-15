-- Home Plate Phase 9B automatic delivery wake-up reliability.
--
-- pg_net records HTTP requests transactionally and begins them only after the
-- surrounding transaction commits. This preserves the immediate queue trigger
-- while adding durable, secret-free diagnostics for configuration, request,
-- and worker response failures. The worker also performs one bounded follow-up
-- claim for queue-trigger invocations that initially see no committed work.
--
-- Rollback: unschedule home-plate-notification-delivery-wakeup-observer;
-- reschedule home-plate-notification-delivery-worker with the original no-arg
-- command; restore the prior no-arg wake-up function; then drop the overload,
-- observer function, and sd_notification_delivery_wakeups. Delivery and inbox
-- rows are independent and must not be removed during rollback.

create table if not exists public.sd_notification_delivery_wakeups (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  source text not null,
  state text not null,
  pending_delivery_count integer not null default 0,
  request_id bigint,
  response_status integer,
  response_error_code text,
  worker_claimed integer,
  worker_polls integer,
  requested_at timestamptz not null default pg_catalog.now(),
  response_observed_at timestamptz,
  created_at timestamptz not null default pg_catalog.now(),
  constraint sd_notification_delivery_wakeups_source_check check (
    source in ('queue_trigger', 'cron_fallback', 'unknown_internal')
  ),
  constraint sd_notification_delivery_wakeups_state_check check (
    state in (
      'configuration_missing', 'request_failed', 'queued', 'succeeded',
      'unauthorized', 'worker_failed', 'network_failed'
    )
  ),
  constraint sd_notification_delivery_wakeups_pending_check
    check (pending_delivery_count >= 0),
  constraint sd_notification_delivery_wakeups_response_check
    check (response_status is null or response_status between 100 and 599),
  constraint sd_notification_delivery_wakeups_error_check
    check (
      response_error_code is null
      or pg_catalog.char_length(response_error_code) between 1 and 80
    ),
  constraint sd_notification_delivery_wakeups_claimed_check
    check (worker_claimed is null or worker_claimed between 0 and 100),
  constraint sd_notification_delivery_wakeups_polls_check
    check (worker_polls is null or worker_polls between 1 and 2),
  unique (request_id)
);

comment on table public.sd_notification_delivery_wakeups is
  'Secret-free operational history for pg_net APNs worker wake-ups and responses.';
comment on column public.sd_notification_delivery_wakeups.response_error_code is
  'Normalized operational code only; never stores Vault values or response bodies.';

create index if not exists idx_sd_notification_delivery_wakeups_recent
  on public.sd_notification_delivery_wakeups(created_at desc);
create index if not exists idx_sd_notification_delivery_wakeups_unobserved
  on public.sd_notification_delivery_wakeups(request_id, requested_at)
  where state = 'queued' and response_observed_at is null;

alter table public.sd_notification_delivery_wakeups enable row level security;
revoke all on table public.sd_notification_delivery_wakeups
from public, anon, authenticated, service_role;
grant select on table public.sd_notification_delivery_wakeups to service_role;

-- Internal overload used by the queue-trigger wrapper and cron fallback. No
-- client role can execute it. It accepts only a diagnostic source, never a URL,
-- header, secret, recipient, or notification payload.
create or replace function public.sd_request_notification_delivery_worker(
  p_source text
)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_source text := case
    when p_source in ('queue_trigger', 'cron_fallback') then p_source
    else 'unknown_internal'
  end;
  v_url text;
  v_secret text;
  v_request_id bigint;
  v_pending_count integer := 0;
  v_missing_code text;
begin
  select pg_catalog.count(*)::integer into v_pending_count
  from public.sd_notification_deliveries delivery
  where (
    delivery.status in ('pending', 'retryable')
    and delivery.next_attempt_at <= pg_catalog.now()
  ) or (
    delivery.status = 'sending'
    and delivery.claimed_at < pg_catalog.now() - interval '5 minutes'
  );

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
    v_missing_code := case
      when nullif(pg_catalog.btrim(v_url), '') is null
        and nullif(pg_catalog.btrim(v_secret), '') is null
        then 'vault_url_and_secret_missing'
      when nullif(pg_catalog.btrim(v_url), '') is null
        then 'vault_url_missing'
      else 'vault_secret_missing'
    end;
    begin
      insert into public.sd_notification_delivery_wakeups (
        source, state, pending_delivery_count, response_error_code
      ) values (
        v_source, 'configuration_missing', v_pending_count, v_missing_code
      );
    exception when others then
      null;
    end;
    raise warning 'notification_delivery_worker_not_configured';
    return null;
  end if;

  begin
    select net.http_post(
      url := pg_catalog.btrim(v_url),
      headers := pg_catalog.jsonb_build_object(
        'content-type', 'application/json',
        'x-home-plate-worker-secret', v_secret
      ),
      body := pg_catalog.jsonb_build_object('source', v_source),
      timeout_milliseconds := 5000
    ) into v_request_id;

    if v_request_id is null then
      insert into public.sd_notification_delivery_wakeups (
        source, state, pending_delivery_count, response_error_code
      ) values (
        v_source, 'request_failed', v_pending_count, 'pg_net_request_id_missing'
      );
      return null;
    end if;

    insert into public.sd_notification_delivery_wakeups (
      source, state, pending_delivery_count, request_id
    ) values (
      v_source, 'queued', v_pending_count, v_request_id
    );
    return v_request_id;
  exception when others then
    begin
      insert into public.sd_notification_delivery_wakeups (
        source, state, pending_delivery_count, response_error_code
      ) values (
        v_source, 'request_failed', v_pending_count, 'pg_net_request_failed'
      );
    exception when others then
      null;
    end;
    raise warning 'notification_delivery_worker_wakeup_failed';
    return null;
  end;
exception when others then
  begin
    insert into public.sd_notification_delivery_wakeups (
      source, state, pending_delivery_count, response_error_code
    ) values (
      v_source, 'request_failed', v_pending_count, 'wakeup_function_failed'
    );
  exception when others then
    null;
  end;
  raise warning 'notification_delivery_worker_wakeup_failed';
  return null;
end;
$$;

revoke all on function public.sd_request_notification_delivery_worker(text)
from public, anon, authenticated, service_role;

-- Existing queue triggers call this signature. Keeping it as a wrapper avoids
-- rewriting the already-deployed queue trigger or any notification producer.
create or replace function public.sd_request_notification_delivery_worker()
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
begin
  return public.sd_request_notification_delivery_worker('queue_trigger');
end;
$$;

revoke all on function public.sd_request_notification_delivery_worker()
from public, anon, authenticated, service_role;

-- pg_net responses are asynchronous. This observer records only status,
-- normalized failure class, and the worker's bounded numeric counts. It never
-- copies response bodies, request headers, or Vault values into public tables.
create or replace function public.sd_observe_notification_delivery_wakeups()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_response record;
  v_observed integer := 0;
  v_claimed integer;
  v_polls integer;
begin
  for v_response in
    select
      wakeup.id as wakeup_id,
      response.status_code,
      response.timed_out,
      response.error_msg,
      response.content
    from public.sd_notification_delivery_wakeups wakeup
    join net._http_response response on response.id = wakeup.request_id
    where wakeup.state = 'queued'
      and wakeup.response_observed_at is null
    order by wakeup.requested_at
    limit 500
  loop
    v_claimed := null;
    v_polls := null;
    begin
      v_claimed := nullif(substring(
        coalesce(v_response.content, '')
        from '"claimed"[[:space:]]*:[[:space:]]*([0-9]+)'
      ), '')::integer;
      v_polls := nullif(substring(
        coalesce(v_response.content, '')
        from '"polls"[[:space:]]*:[[:space:]]*([0-9]+)'
      ), '')::integer;
    exception when others then
      v_claimed := null;
      v_polls := null;
    end;

    update public.sd_notification_delivery_wakeups wakeup
    set state = case
          when coalesce(v_response.timed_out, false)
            or nullif(v_response.error_msg, '') is not null then 'network_failed'
          when v_response.status_code = 200 then 'succeeded'
          when v_response.status_code = 401 then 'unauthorized'
          when v_response.status_code >= 500 then 'worker_failed'
          else 'request_failed'
        end,
        response_status = v_response.status_code,
        response_error_code = case
          when coalesce(v_response.timed_out, false) then 'pg_net_timeout'
          when nullif(v_response.error_msg, '') is not null then 'pg_net_error'
          when v_response.status_code = 401 then 'worker_unauthorized'
          when v_response.status_code >= 500 then 'worker_server_error'
          when v_response.status_code <> 200 then 'worker_unexpected_status'
          else null
        end,
        worker_claimed = case when v_claimed between 0 and 100 then v_claimed else null end,
        worker_polls = case when v_polls between 1 and 2 then v_polls else null end,
        response_observed_at = pg_catalog.now()
    where wakeup.id = v_response.wakeup_id;
    v_observed := v_observed + 1;
  end loop;

  delete from public.sd_notification_delivery_wakeups wakeup
  where wakeup.created_at < pg_catalog.now() - interval '14 days';
  return v_observed;
end;
$$;

revoke all on function public.sd_observe_notification_delivery_wakeups()
from public, anon, authenticated, service_role;

-- Deterministically replace, rather than duplicate, the one-minute fallback.
-- A second one-minute job observes pg_net outcomes for operational diagnosis.
do $$
declare
  v_job_id bigint;
begin
  for v_job_id in
    select job.jobid from cron.job job
    where job.jobname in (
      'home-plate-notification-delivery-worker',
      'home-plate-notification-delivery-wakeup-observer'
    )
  loop
    perform cron.unschedule(v_job_id);
  end loop;

  perform cron.schedule(
    'home-plate-notification-delivery-worker',
    '* * * * *',
    $command$select public.sd_request_notification_delivery_worker('cron_fallback');$command$
  );
  perform cron.schedule(
    'home-plate-notification-delivery-wakeup-observer',
    '* * * * *',
    $command$select public.sd_observe_notification_delivery_wakeups();$command$
  );
end;
$$;
