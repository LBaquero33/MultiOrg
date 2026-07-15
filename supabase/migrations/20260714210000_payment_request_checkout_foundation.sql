-- Stripe Payments Phase 1B-2: connected-account Checkout foundation.
--
-- This additive migration records server-created Checkout attempts, links a
-- verified provider payment to one internal payment request, and supplies
-- short service-role-only transactions for reservation/finalization and
-- webhook reconciliation. No RPC performs a network request.
--
-- Rollback strategy (only before production payment data exists): drop the
-- four RPCs below, the checkout-session table and its policies/indexes/trigger,
-- the payment-request/payment indexes, then remove sd_payments.payment_request_id
-- and sd_payment_requests.paid_at. Restore the prior
-- sd_payment_requests_enforce_state() definition before removing paid_at.

alter table public.sd_payment_requests
  add column if not exists paid_at timestamptz;

-- Preserve existing terminal rows without guessing a provider completion time.
update public.sd_payment_requests
set paid_at = coalesce(paid_at, updated_at, created_at)
where status = 'paid'
  and paid_at is null;

alter table public.sd_payments
  add column if not exists payment_request_id uuid
    references public.sd_payment_requests(id) on delete restrict;

create unique index if not exists ux_sd_payments_successful_payment_request
on public.sd_payments(payment_request_id)
where payment_request_id is not null and status in ('succeeded', 'paid');

create table if not exists public.sd_payment_checkout_sessions (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  org_id uuid not null references public.sd_orgs(id) on delete restrict,
  payment_request_id uuid not null references public.sd_payment_requests(id) on delete restrict,
  payer_user_id uuid not null references auth.users(id) on delete restrict,
  child_id uuid not null references auth.users(id) on delete restrict,
  authorization_source text not null,
  stripe_account_id text not null
    references public.sd_connected_payment_accounts(provider_account_id) on delete restrict,
  stripe_checkout_session_id text,
  stripe_payment_intent_id text,
  status text not null default 'creating',
  stripe_idempotency_key text not null,
  amount_cents integer not null,
  currency text not null,
  application_fee_amount_cents integer not null default 0,
  fee_policy_version text not null,
  expires_at timestamptz not null,
  error_code text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  completed_at timestamptz,
  constraint sd_payment_checkout_sessions_authorization_check
    check (authorization_source in ('player_self', 'linked_parent')),
  constraint sd_payment_checkout_sessions_status_check
    check (status in ('creating', 'open', 'complete', 'expired', 'failed', 'anomaly')),
  constraint sd_payment_checkout_sessions_amount_check
    check (amount_cents > 0 and amount_cents <= 10000000),
  constraint sd_payment_checkout_sessions_currency_check
    check (currency = lower(currency) and currency ~ '^[a-z]{3}$'),
  constraint sd_payment_checkout_sessions_fee_check
    check (application_fee_amount_cents >= 0 and application_fee_amount_cents < amount_cents),
  constraint sd_payment_checkout_sessions_idempotency_check
    check (char_length(stripe_idempotency_key) between 16 and 255),
  constraint sd_payment_checkout_sessions_provider_state_check
    check (
      (status = 'creating' and stripe_checkout_session_id is null)
      or (status = 'failed' and stripe_checkout_session_id is null)
      or status in ('open', 'complete', 'expired', 'anomaly')
    )
);

comment on table public.sd_payment_checkout_sessions is
  'Server-only Stripe Checkout attempts for organization payment requests.';
comment on column public.sd_payment_checkout_sessions.authorization_source is
  'Authoritative payer path: player_self or linked_parent.';
comment on column public.sd_payment_checkout_sessions.stripe_idempotency_key is
  'Stable server-generated key reused across ambiguous Stripe API retries.';
comment on column public.sd_payment_checkout_sessions.fee_policy_version is
  'Server fee policy identifier; the initial policy defaults to zero basis points.';

create unique index if not exists ux_sd_payment_checkout_sessions_stripe_idempotency
on public.sd_payment_checkout_sessions(stripe_idempotency_key);

create unique index if not exists ux_sd_payment_checkout_sessions_provider_session
on public.sd_payment_checkout_sessions(stripe_checkout_session_id)
where stripe_checkout_session_id is not null;

create unique index if not exists ux_sd_payment_checkout_sessions_provider_intent
on public.sd_payment_checkout_sessions(stripe_payment_intent_id)
where stripe_payment_intent_id is not null;

create unique index if not exists ux_sd_payment_checkout_sessions_active_request
on public.sd_payment_checkout_sessions(payment_request_id)
where status in ('creating', 'open');

create index if not exists idx_sd_payment_checkout_sessions_request_created
on public.sd_payment_checkout_sessions(payment_request_id, created_at desc);

create index if not exists idx_sd_payment_checkout_sessions_org_status
on public.sd_payment_checkout_sessions(org_id, status, created_at desc);

create index if not exists idx_sd_payment_checkout_sessions_payer
on public.sd_payment_checkout_sessions(payer_user_id, created_at desc);

drop trigger if exists trg_sd_payment_checkout_sessions_updated_at
on public.sd_payment_checkout_sessions;
create trigger trg_sd_payment_checkout_sessions_updated_at
before update on public.sd_payment_checkout_sessions
for each row execute function public.sd_set_updated_at();

alter table public.sd_payment_checkout_sessions enable row level security;
revoke all on table public.sd_payment_checkout_sessions from public, anon, authenticated;
grant select, insert, update on table public.sd_payment_checkout_sessions to service_role;

-- Preserve immutable request business data while making a verified webhook the
-- only supported route to a non-null paid_at value.
create or replace function public.sd_payment_requests_enforce_state()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    if new.status <> 'open' then
      raise exception 'payment_request_must_start_open' using errcode = '23514';
    end if;
    if new.created_by is null
      or new.idempotency_key is null
      or new.idempotency_operation <> 'create' then
      raise exception 'payment_request_server_fields_required' using errcode = '23514';
    end if;
    if new.paid_at is not null then
      raise exception 'payment_request_paid_at_server_controlled' using errcode = '23514';
    end if;
    return new;
  end if;

  if new.org_id is distinct from old.org_id
    or new.child_id is distinct from old.child_id
    or new.created_by is distinct from old.created_by
    or new.title is distinct from old.title
    or new.notes is distinct from old.notes
    or new.amount_cents is distinct from old.amount_cents
    or new.currency is distinct from old.currency
    or new.due_date is distinct from old.due_date
    or new.payer_id is distinct from old.payer_id
    or new.idempotency_key is distinct from old.idempotency_key
    or new.idempotency_operation is distinct from old.idempotency_operation then
    raise exception 'payment_request_fields_are_immutable' using errcode = '23514';
  end if;

  if new.status = old.status then
    if new.paid_at is distinct from old.paid_at then
      raise exception 'payment_request_paid_at_server_controlled' using errcode = '23514';
    end if;
    return new;
  end if;

  if old.status = 'open' and new.status = 'canceled' and new.paid_at is null then
    return new;
  end if;
  if old.status = 'open' and new.status = 'paid' and new.paid_at is not null then
    return new;
  end if;

  raise exception 'invalid_payment_request_transition'
    using errcode = '23514',
          detail = pg_catalog.format(
            'Payment request cannot transition from %s to %s.',
            old.status,
            new.status
          );
end;
$$;

revoke all on function public.sd_payment_requests_enforce_state()
from public, anon, authenticated;

create or replace function public.sd_prepare_payment_request_checkout(
  p_actor_id uuid,
  p_payment_request_id uuid,
  p_fee_bps integer
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_request public.sd_payment_requests%rowtype;
  v_attempt public.sd_payment_checkout_sessions%rowtype;
  v_account public.sd_connected_payment_accounts%rowtype;
  v_authorization_source text;
  v_fee_amount integer;
begin
  if p_actor_id is null or p_payment_request_id is null then
    raise exception 'invalid_request' using errcode = '22023';
  end if;
  if p_fee_bps is null or p_fee_bps not between 0 and 1000 then
    raise exception 'invalid_fee_policy' using errcode = '22023';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_payment_request_id::text, 0)
  );

  select request.*
  into v_request
  from public.sd_payment_requests request
  where request.id = p_payment_request_id
  for update;

  if v_request.id is null then
    raise exception 'payment_request_not_found' using errcode = 'P0001';
  end if;
  if v_request.status = 'paid' then
    raise exception 'payment_already_completed' using errcode = 'P0001';
  end if;
  if v_request.status <> 'open' then
    raise exception 'payment_request_not_open' using errcode = 'P0001';
  end if;
  if v_request.amount_cents is null or v_request.amount_cents <= 0 then
    raise exception 'payment_request_not_payable' using errcode = 'P0001';
  end if;

  if not exists (
    select 1
    from public.sd_orgs organization
    where organization.id = v_request.org_id
      and organization.status = 'active'
  ) then
    raise exception 'organization_inactive' using errcode = 'P0001';
  end if;

  if not exists (
    select 1
    from public.sd_org_memberships player
    where player.org_id = v_request.org_id
      and player.user_id = v_request.child_id
      and player.role = 'player'
      and player.status = 'active'
  ) then
    raise exception 'active_player_required' using errcode = 'P0001';
  end if;

  if p_actor_id = v_request.child_id and exists (
    select 1
    from public.sd_org_memberships actor
    where actor.org_id = v_request.org_id
      and actor.user_id = p_actor_id
      and actor.role = 'player'
      and actor.status = 'active'
  ) then
    v_authorization_source := 'player_self';
  elsif exists (
    select 1
    from public.sd_org_memberships actor
    join public.sd_parent_child_links link
      on link.org_id = actor.org_id
     and link.parent_id = actor.user_id
     and link.child_id = v_request.child_id
     and link.can_pay = true
    where actor.org_id = v_request.org_id
      and actor.user_id = p_actor_id
      and actor.role = 'parent'
      and actor.status = 'active'
  ) then
    v_authorization_source := 'linked_parent';
  else
    raise exception 'payer_not_authorized' using errcode = 'P0001';
  end if;

  select account.*
  into v_account
  from public.sd_connected_payment_accounts account
  where account.org_id = v_request.org_id
    and account.provider = 'stripe';

  if v_account.org_id is null or v_account.provider_account_id is null then
    raise exception 'connected_account_missing' using errcode = 'P0001';
  end if;
  if v_account.onboarding_status <> 'ready'
    or not v_account.details_submitted
    or not v_account.charges_enabled
    or not v_account.payouts_enabled
    or v_account.disabled_reason is not null
    or pg_catalog.jsonb_array_length(v_account.requirements_past_due) > 0 then
    raise exception 'connected_account_not_ready' using errcode = 'P0001';
  end if;

  update public.sd_payment_checkout_sessions attempt
  set status = 'expired', error_code = 'checkout_expired'
  where attempt.payment_request_id = v_request.id
    and attempt.status in ('creating', 'open')
    and attempt.expires_at <= pg_catalog.now();

  select attempt.*
  into v_attempt
  from public.sd_payment_checkout_sessions attempt
  where attempt.payment_request_id = v_request.id
    and attempt.status in ('creating', 'open')
  order by attempt.created_at desc
  limit 1
  for update;

  if v_attempt.id is not null then
    return pg_catalog.jsonb_build_object(
      'attempt_id', v_attempt.id,
      'org_id', v_attempt.org_id,
      'payment_request_id', v_attempt.payment_request_id,
      'payer_user_id', v_attempt.payer_user_id,
      'child_id', v_attempt.child_id,
      'authorization_source', v_attempt.authorization_source,
      'stripe_account_id', v_attempt.stripe_account_id,
      'stripe_checkout_session_id', v_attempt.stripe_checkout_session_id,
      'stripe_idempotency_key', v_attempt.stripe_idempotency_key,
      'amount_cents', v_attempt.amount_cents,
      'currency', v_attempt.currency,
      'application_fee_amount_cents', v_attempt.application_fee_amount_cents,
      'fee_policy_version', v_attempt.fee_policy_version,
      'expires_at', v_attempt.expires_at,
      'reused', true
    );
  end if;

  v_fee_amount := (v_request.amount_cents::bigint * p_fee_bps / 10000)::integer;
  if v_fee_amount >= v_request.amount_cents then
    raise exception 'invalid_fee_policy' using errcode = '22023';
  end if;

  insert into public.sd_payment_checkout_sessions (
    org_id,
    payment_request_id,
    payer_user_id,
    child_id,
    authorization_source,
    stripe_account_id,
    status,
    stripe_idempotency_key,
    amount_cents,
    currency,
    application_fee_amount_cents,
    fee_policy_version,
    expires_at
  ) values (
    v_request.org_id,
    v_request.id,
    p_actor_id,
    v_request.child_id,
    v_authorization_source,
    v_account.provider_account_id,
    'creating',
    'homeplate_checkout_v1_' || pg_catalog.replace(pg_catalog.gen_random_uuid()::text, '-', ''),
    v_request.amount_cents,
    v_request.currency,
    v_fee_amount,
    'home_plate_fee_bps_v1:' || p_fee_bps::text,
    pg_catalog.now() + interval '60 minutes'
  )
  returning * into v_attempt;

  return pg_catalog.jsonb_build_object(
    'attempt_id', v_attempt.id,
    'org_id', v_attempt.org_id,
    'payment_request_id', v_attempt.payment_request_id,
    'payer_user_id', v_attempt.payer_user_id,
    'child_id', v_attempt.child_id,
    'authorization_source', v_attempt.authorization_source,
    'stripe_account_id', v_attempt.stripe_account_id,
    'stripe_checkout_session_id', v_attempt.stripe_checkout_session_id,
    'stripe_idempotency_key', v_attempt.stripe_idempotency_key,
    'amount_cents', v_attempt.amount_cents,
    'currency', v_attempt.currency,
    'application_fee_amount_cents', v_attempt.application_fee_amount_cents,
    'fee_policy_version', v_attempt.fee_policy_version,
    'expires_at', v_attempt.expires_at,
    'reused', false
  );
end;
$$;

create or replace function public.sd_finalize_payment_request_checkout(
  p_attempt_id uuid,
  p_stripe_checkout_session_id text,
  p_stripe_payment_intent_id text,
  p_expires_at timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_attempt public.sd_payment_checkout_sessions%rowtype;
begin
  if p_attempt_id is null
    or nullif(pg_catalog.btrim(p_stripe_checkout_session_id), '') is null
    or p_expires_at is null then
    raise exception 'invalid_checkout_finalize_input' using errcode = '22023';
  end if;

  select attempt.*
  into v_attempt
  from public.sd_payment_checkout_sessions attempt
  where attempt.id = p_attempt_id
  for update;

  if v_attempt.id is null then
    raise exception 'checkout_attempt_not_found' using errcode = 'P0001';
  end if;
  if v_attempt.stripe_payment_intent_id is not null
    and v_attempt.stripe_payment_intent_id <> p_stripe_payment_intent_id then
    raise exception 'payment_intent_mismatch' using errcode = 'P0001';
  end if;
  if v_attempt.status not in ('creating', 'open') then
    raise exception 'checkout_state_conflict' using errcode = 'P0001';
  end if;
  if v_attempt.stripe_checkout_session_id is not null
    and v_attempt.stripe_checkout_session_id <> p_stripe_checkout_session_id then
    raise exception 'checkout_state_conflict' using errcode = 'P0001';
  end if;
  if not exists (
    select 1
    from public.sd_payment_requests request
    where request.id = v_attempt.payment_request_id
      and request.org_id = v_attempt.org_id
      and request.status = 'open'
  ) then
    raise exception 'payment_request_not_open' using errcode = 'P0001';
  end if;

  update public.sd_payment_checkout_sessions attempt
  set stripe_checkout_session_id = p_stripe_checkout_session_id,
      stripe_payment_intent_id = coalesce(p_stripe_payment_intent_id, attempt.stripe_payment_intent_id),
      status = 'open',
      expires_at = p_expires_at,
      error_code = null
  where attempt.id = p_attempt_id
  returning * into v_attempt;

  return pg_catalog.to_jsonb(v_attempt);
end;
$$;

create or replace function public.sd_finish_payment_request_checkout_attempt(
  p_attempt_id uuid,
  p_status text,
  p_error_code text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if p_attempt_id is null or p_status not in ('expired', 'failed') then
    raise exception 'invalid_checkout_attempt_transition' using errcode = '22023';
  end if;

  update public.sd_payment_checkout_sessions attempt
  set status = p_status,
      error_code = nullif(pg_catalog.left(pg_catalog.btrim(p_error_code), 120), '')
  where attempt.id = p_attempt_id
    and attempt.status in ('creating', 'open');
end;
$$;

create or replace function public.sd_reconcile_payment_request_payment(
  p_attempt_id uuid,
  p_org_id uuid,
  p_payment_request_id uuid,
  p_child_id uuid,
  p_stripe_account_id text,
  p_stripe_checkout_session_id text,
  p_stripe_payment_intent_id text,
  p_stripe_charge_id text,
  p_amount_cents integer,
  p_currency text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_attempt public.sd_payment_checkout_sessions%rowtype;
  v_request public.sd_payment_requests%rowtype;
  v_existing_payment public.sd_payments%rowtype;
  v_payment public.sd_payments%rowtype;
begin
  if p_attempt_id is null
    or p_org_id is null
    or p_payment_request_id is null
    or p_child_id is null
    or nullif(pg_catalog.btrim(p_stripe_account_id), '') is null
    or nullif(pg_catalog.btrim(p_stripe_payment_intent_id), '') is null
    or p_amount_cents is null
    or nullif(pg_catalog.btrim(p_currency), '') is null then
    raise exception 'invalid_payment_event' using errcode = '22023';
  end if;

  select attempt.*
  into v_attempt
  from public.sd_payment_checkout_sessions attempt
  where attempt.id = p_attempt_id
    and attempt.org_id = p_org_id
    and attempt.payment_request_id = p_payment_request_id
    and attempt.child_id = p_child_id
    and attempt.stripe_account_id = p_stripe_account_id
    and (
      (p_stripe_checkout_session_id is not null
        and attempt.stripe_checkout_session_id = p_stripe_checkout_session_id)
      or attempt.stripe_payment_intent_id = p_stripe_payment_intent_id
      or attempt.stripe_payment_intent_id is null
    )
  order by attempt.created_at desc
  limit 1
  for update;

  if v_attempt.id is null then
    raise exception 'checkout_attempt_not_found' using errcode = 'P0001';
  end if;
  if v_attempt.stripe_payment_intent_id is not null
    and v_attempt.stripe_payment_intent_id <> p_stripe_payment_intent_id then
    raise exception 'payment_intent_mismatch' using errcode = 'P0001';
  end if;
  if v_attempt.amount_cents <> p_amount_cents then
    raise exception 'payment_amount_mismatch' using errcode = 'P0001';
  end if;
  if v_attempt.currency <> pg_catalog.lower(pg_catalog.btrim(p_currency)) then
    raise exception 'payment_currency_mismatch' using errcode = 'P0001';
  end if;

  select request.*
  into v_request
  from public.sd_payment_requests request
  where request.id = v_attempt.payment_request_id
    and request.org_id = v_attempt.org_id
  for update;

  if v_request.id is null then
    raise exception 'payment_request_not_found' using errcode = 'P0001';
  end if;

  select payment.*
  into v_existing_payment
  from public.sd_payments payment
  where payment.payment_request_id = v_request.id
    and payment.status in ('succeeded', 'paid')
  order by payment.created_at
  limit 1;

  if v_request.status = 'canceled' then
    update public.sd_payment_checkout_sessions
    set status = 'anomaly',
        stripe_payment_intent_id = coalesce(stripe_payment_intent_id, p_stripe_payment_intent_id),
        error_code = 'payment_succeeded_after_request_canceled'
    where id = v_attempt.id;
    return pg_catalog.jsonb_build_object(
      'kind', 'canceled_request_anomaly',
      'payment_request_id', v_request.id,
      'attempt_id', v_attempt.id
    );
  end if;

  if v_request.status = 'paid' or v_existing_payment.id is not null then
    if v_existing_payment.provider_payment_intent_id = p_stripe_payment_intent_id then
      return pg_catalog.jsonb_build_object(
        'kind', 'duplicate',
        'payment_request_id', v_request.id,
        'payment_id', v_existing_payment.id
      );
    end if;
    update public.sd_payment_checkout_sessions
    set status = 'anomaly',
        error_code = 'duplicate_successful_payment'
    where id = v_attempt.id;
    return pg_catalog.jsonb_build_object(
      'kind', 'duplicate_payment_anomaly',
      'payment_request_id', v_request.id,
      'attempt_id', v_attempt.id
    );
  end if;

  if v_request.status <> 'open' then
    raise exception 'payment_request_not_open' using errcode = 'P0001';
  end if;

  insert into public.sd_payments (
    org_id,
    payment_request_id,
    payer_id,
    provider,
    connected_account_id,
    provider_payment_intent_id,
    provider_charge_id,
    amount_cents,
    currency,
    status,
    platform_fee_cents,
    net_to_organization_cents,
    paid_at
  ) values (
    v_attempt.org_id,
    v_request.id,
    v_attempt.payer_user_id,
    'stripe',
    v_attempt.stripe_account_id,
    p_stripe_payment_intent_id,
    nullif(pg_catalog.btrim(p_stripe_charge_id), ''),
    v_attempt.amount_cents,
    v_attempt.currency,
    'succeeded',
    v_attempt.application_fee_amount_cents,
    v_attempt.amount_cents - v_attempt.application_fee_amount_cents,
    pg_catalog.now()
  )
  returning * into v_payment;

  update public.sd_payment_requests request
  set status = 'paid',
      paid_at = v_payment.paid_at
  where request.id = v_request.id
    and request.status = 'open';

  if not found then
    raise exception 'payment_request_state_conflict' using errcode = 'P0001';
  end if;

  update public.sd_payment_checkout_sessions attempt
  set status = 'complete',
      stripe_checkout_session_id = coalesce(
        attempt.stripe_checkout_session_id,
        nullif(pg_catalog.btrim(p_stripe_checkout_session_id), '')
      ),
      stripe_payment_intent_id = p_stripe_payment_intent_id,
      completed_at = v_payment.paid_at,
      error_code = null
  where attempt.id = v_attempt.id;

  return pg_catalog.jsonb_build_object(
    'kind', 'paid',
    'payment_request_id', v_request.id,
    'payment_id', v_payment.id,
    'attempt_id', v_attempt.id
  );
end;
$$;

revoke all on function public.sd_prepare_payment_request_checkout(uuid, uuid, integer)
from public, anon, authenticated;
grant execute on function public.sd_prepare_payment_request_checkout(uuid, uuid, integer)
to service_role;

revoke all on function public.sd_finalize_payment_request_checkout(uuid, text, text, timestamptz)
from public, anon, authenticated;
grant execute on function public.sd_finalize_payment_request_checkout(uuid, text, text, timestamptz)
to service_role;

revoke all on function public.sd_finish_payment_request_checkout_attempt(uuid, text, text)
from public, anon, authenticated;
grant execute on function public.sd_finish_payment_request_checkout_attempt(uuid, text, text)
to service_role;

revoke all on function public.sd_reconcile_payment_request_payment(
  uuid, uuid, uuid, uuid, text, text, text, text, integer, text
)
from public, anon, authenticated;
grant execute on function public.sd_reconcile_payment_request_payment(
  uuid, uuid, uuid, uuid, text, text, text, text, integer, text
)
to service_role;
