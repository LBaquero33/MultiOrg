-- Recover Stripe webhook work after a worker is terminated mid-event.
-- Preconditions: sd_webhook_events and its provider/event/account unique index
-- already exist. Rollback: remove the RPC/lease columns only after all workers
-- stop calling it; existing ledger rows and provider events remain intact.

begin;

alter table public.sd_webhook_events
  add column if not exists processing_lease_until timestamptz,
  add column if not exists processing_lease_token uuid;

create or replace function public.sd_claim_webhook_event(
  p_provider text,
  p_provider_event_id text,
  p_provider_account_id text,
  p_event_type text,
  p_payload jsonb,
  p_lease_seconds integer default 180
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_event public.sd_webhook_events%rowtype;
  v_token uuid := gen_random_uuid();
  v_lease_seconds integer := least(greatest(coalesce(p_lease_seconds, 180), 30), 900);
begin
  if auth.role() is distinct from 'service_role' then
    raise exception using errcode = '42501', message = 'service_role_required';
  end if;
  if p_provider is distinct from 'stripe'
     or p_provider_event_id is null or length(p_provider_event_id) not between 1 and 255
     or p_event_type is null or length(p_event_type) not between 1 and 255
     or coalesce(jsonb_typeof(p_payload), 'object') <> 'object' then
    raise exception using errcode = '22023', message = 'webhook_event_identity_required';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(
    p_provider || ':' || coalesce(p_provider_account_id, '') || ':' || p_provider_event_id, 0
  ));
  select * into v_event
  from public.sd_webhook_events e
  where e.provider = p_provider
    and e.provider_event_id = p_provider_event_id
    and coalesce(e.provider_account_id, '') = coalesce(p_provider_account_id, '')
  for update;

  if not found then
    insert into public.sd_webhook_events (
      provider, provider_account_id, provider_event_id, event_type,
      processing_status, payload, attempt_count,
      processing_lease_until, processing_lease_token
    ) values (
      p_provider, p_provider_account_id, p_provider_event_id, p_event_type,
      'processing', coalesce(p_payload, '{}'::jsonb), 1,
      now() + make_interval(secs => v_lease_seconds), v_token
    ) returning * into v_event;
    return jsonb_build_object('claimed', true, 'state', 'claimed', 'id', v_event.id,
      'lease_token', v_token);
  end if;

  if v_event.processing_status = 'processed'
  then
    return jsonb_build_object('claimed', false, 'state', 'processed', 'id', v_event.id);
  end if;
  -- During rollout, an old worker may still own a recent processing row
  -- without lease metadata. Give that worker a bounded fifteen-minute grace
  -- from receipt before the new worker can reclaim it.
  if v_event.processing_status = 'processing' and coalesce(
    v_event.processing_lease_until,
    coalesce(v_event.received_at, now()) + interval '15 minutes'
  ) > now() then
    return jsonb_build_object('claimed', false, 'state', 'in_flight', 'id', v_event.id,
      'retry_after_seconds', greatest(30, least(900,
        ceil(extract(epoch from (coalesce(v_event.processing_lease_until,
          coalesce(v_event.received_at, now()) + interval '15 minutes') - now())))::integer)));
  end if;

  update public.sd_webhook_events
  set processing_status = 'processing',
      attempt_count = attempt_count + 1,
      error_message = null,
      processing_lease_until = now() + make_interval(secs => v_lease_seconds),
      processing_lease_token = v_token,
      payload = coalesce(p_payload, payload),
      event_type = p_event_type
  where id = v_event.id
  returning * into v_event;
  return jsonb_build_object('claimed', true, 'state', 'claimed', 'id', v_event.id, 'lease_token', v_token);
end;
$$;
revoke all on function public.sd_claim_webhook_event(text, text, text, text, jsonb, integer)
  from public, anon, authenticated;
grant execute on function public.sd_claim_webhook_event(text, text, text, text, jsonb, integer)
  to service_role;

commit;
