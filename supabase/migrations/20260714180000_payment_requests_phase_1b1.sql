-- Stripe Payments Phase 1B-1: internal, organization-scoped payment requests.
--
-- This migration adapts the existing legacy sd_payment_requests table without
-- creating invoices, provider payments, Checkout Sessions, or Stripe objects.
-- Existing org_id, child_id, amount_cents, currency, notes, and timestamp
-- columns remain authoritative. New client workflows use an authenticated Edge
-- Function; authenticated clients retain read-only table access through RLS.
--
-- Rollback: drop the two read helpers, the state trigger/function, the new RLS
-- policy and indexes, then remove created_by, title, due_date, idempotency_key,
-- and idempotency_operation. Recreate the legacy policies/paid trigger only if
-- intentionally restoring the former parent-created manual-access workflow.

-- Fail before changing data if legacy rows cannot be mapped without guessing.
do $$
declare
  unexpected_statuses text;
begin
  if exists (select 1 from public.sd_payment_requests where org_id is null) then
    raise exception 'payment_request_org_preflight_failed'
      using errcode = '23514',
            detail = 'Every existing payment request must have an organization before Phase 1B-1.';
  end if;

  if exists (
    select 1
    from public.sd_payment_requests
    where amount_cents is not null
      and (amount_cents <= 0 or amount_cents > 10000000)
  ) then
    raise exception 'payment_request_amount_preflight_failed'
      using errcode = '23514',
            detail = 'Existing non-null amounts must be between 1 and 10,000,000 minor units.';
  end if;

  if exists (
    select 1
    from public.sd_payment_requests
    where plan_name is not null
      and char_length(btrim(plan_name)) > 120
  ) then
    raise exception 'payment_request_title_preflight_failed'
      using errcode = '23514',
            detail = 'An existing plan_name is longer than the 120-character request title limit.';
  end if;

  if exists (
    select 1
    from public.sd_payment_requests
    where lower(btrim(currency)) !~ '^[a-z]{3}$'
  ) then
    raise exception 'payment_request_currency_preflight_failed'
      using errcode = '23514',
            detail = 'Existing currencies must be three-letter ISO-style codes.';
  end if;

  select string_agg(format('%s (%s rows)', status, row_count), ', ' order by status)
  into unexpected_statuses
  from (
    select status, count(*) as row_count
    from public.sd_payment_requests
    where status not in ('requested', 'approved', 'open', 'cancelled', 'canceled', 'paid')
    group by status
  ) invalid_statuses;

  if unexpected_statuses is not null then
    raise exception 'payment_request_status_preflight_failed: %', unexpected_statuses
      using errcode = '23514';
  end if;
end;
$$;

alter table public.sd_payment_requests
  add column if not exists created_by uuid references auth.users(id) on delete restrict,
  add column if not exists title text,
  add column if not exists due_date date,
  add column if not exists idempotency_key uuid,
  add column if not exists idempotency_operation text;

-- A payer is not known until the future Checkout phase. Preserve legacy payer
-- values but do not invent one for newly created internal requests.
alter table public.sd_payment_requests
  alter column payer_id drop not null;

update public.sd_payment_requests
set created_by = payer_id
where created_by is null;

update public.sd_payment_requests
set title = coalesce(nullif(btrim(plan_name), ''), 'Payment request')
where title is null;

-- Legacy requested/approved rows are still unpaid and therefore open. Normalize
-- the former British spelling while retaining paid as a terminal state.
update public.sd_payment_requests
set status = case
  when status in ('requested', 'approved') then 'open'
  when status = 'cancelled' then 'canceled'
  else status
end;

update public.sd_payment_requests
set currency = lower(btrim(currency));

alter table public.sd_payment_requests
  alter column org_id set not null,
  alter column created_by set not null,
  alter column title set not null,
  alter column status set default 'open',
  alter column currency set default 'usd';

alter table public.sd_payment_requests
  drop constraint if exists sd_payment_requests_status_check;
alter table public.sd_payment_requests
  add constraint sd_payment_requests_status_check
  check (status in ('open', 'canceled', 'paid'));

alter table public.sd_payment_requests
  drop constraint if exists sd_payment_requests_amount_check;
alter table public.sd_payment_requests
  add constraint sd_payment_requests_amount_check
  check (amount_cents is null or (amount_cents > 0 and amount_cents <= 10000000));

alter table public.sd_payment_requests
  drop constraint if exists sd_payment_requests_currency_check;
alter table public.sd_payment_requests
  add constraint sd_payment_requests_currency_check
  check (currency = lower(currency) and currency ~ '^[a-z]{3}$');

alter table public.sd_payment_requests
  drop constraint if exists sd_payment_requests_title_check;
alter table public.sd_payment_requests
  add constraint sd_payment_requests_title_check
  check (char_length(btrim(title)) between 1 and 120);

alter table public.sd_payment_requests
  drop constraint if exists sd_payment_requests_notes_check;
alter table public.sd_payment_requests
  add constraint sd_payment_requests_notes_check
  check (notes is null or char_length(notes) <= 1000);

alter table public.sd_payment_requests
  drop constraint if exists sd_payment_requests_idempotency_check;
alter table public.sd_payment_requests
  add constraint sd_payment_requests_idempotency_check
  check (
    (idempotency_key is null and idempotency_operation is null)
    or (idempotency_key is not null and idempotency_operation = 'create')
  );

create unique index if not exists ux_sd_payment_requests_create_idempotency
on public.sd_payment_requests(org_id, created_by, idempotency_operation, idempotency_key)
where idempotency_key is not null;

create index if not exists idx_sd_payment_requests_org_created
on public.sd_payment_requests(org_id, created_at desc);

-- Remove the legacy path where parents inserted requests and coaches could set
-- arbitrary statuses, including paid. Payment completion is reserved for a
-- future verified provider webhook using the service role.
drop policy if exists "sd_payment_requests_parent_select" on public.sd_payment_requests;
drop policy if exists "sd_payment_requests_parent_insert" on public.sd_payment_requests;
drop policy if exists "sd_payment_requests_coach_select" on public.sd_payment_requests;
drop policy if exists "sd_payment_requests_coach_update" on public.sd_payment_requests;
drop trigger if exists trg_sd_payment_requests_paid on public.sd_payment_requests;

alter function public.sd_on_payment_request_paid() set search_path = '';
revoke all on function public.sd_on_payment_request_paid()
from public, anon, authenticated;

-- Only open -> canceled (admin action) and open -> paid (future verified
-- webhook) are legal. Request business fields are immutable after creation.
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
    return new;
  end if;

  if old.status = 'open' and new.status in ('canceled', 'paid') then
    return new;
  end if;

  raise exception 'invalid_payment_request_transition'
    using errcode = '23514',
          detail = format('Payment request cannot transition from %s to %s.', old.status, new.status);
end;
$$;

revoke all on function public.sd_payment_requests_enforce_state()
from public, anon, authenticated;

drop trigger if exists trg_sd_payment_requests_enforce_state
on public.sd_payment_requests;
create trigger trg_sd_payment_requests_enforce_state
before insert or update on public.sd_payment_requests
for each row execute function public.sd_payment_requests_enforce_state();

-- Read authorization deliberately excludes coaches and platform administrators.
-- Player and parent membership must be active in the request organization, and
-- a linked child's player membership must also be active in that organization.
create or replace function public.sd_payment_request_can_read(
  target_org_id uuid,
  target_player_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select
    exists (
      select 1
      from public.sd_org_memberships actor
      where actor.org_id = target_org_id
        and actor.user_id = auth.uid()
        and actor.user_id = target_player_id
        and actor.role = 'player'
        and actor.status = 'active'
    )
    or exists (
      select 1
      from public.sd_org_memberships parent_membership
      join public.sd_parent_child_links link
        on link.org_id = parent_membership.org_id
       and link.parent_id = parent_membership.user_id
       and link.child_id = target_player_id
      join public.sd_org_memberships player_membership
        on player_membership.org_id = parent_membership.org_id
       and player_membership.user_id = link.child_id
       and player_membership.role = 'player'
       and player_membership.status = 'active'
      where parent_membership.org_id = target_org_id
        and parent_membership.user_id = auth.uid()
        and parent_membership.role = 'parent'
        and parent_membership.status = 'active'
    );
$$;

create or replace function public.sd_payment_request_can_pay(
  target_org_id uuid,
  target_player_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select
    exists (
      select 1
      from public.sd_org_memberships player_membership
      where player_membership.org_id = target_org_id
        and player_membership.user_id = auth.uid()
        and player_membership.user_id = target_player_id
        and player_membership.role = 'player'
        and player_membership.status = 'active'
    )
    or exists (
      select 1
      from public.sd_org_memberships parent_membership
      join public.sd_parent_child_links link
        on link.org_id = parent_membership.org_id
       and link.parent_id = parent_membership.user_id
       and link.child_id = target_player_id
       and link.can_pay = true
      join public.sd_org_memberships player_membership
        on player_membership.org_id = parent_membership.org_id
       and player_membership.user_id = link.child_id
       and player_membership.role = 'player'
       and player_membership.status = 'active'
      where parent_membership.org_id = target_org_id
        and parent_membership.user_id = auth.uid()
        and parent_membership.role = 'parent'
        and parent_membership.status = 'active'
    );
$$;

revoke all on function public.sd_payment_request_can_read(uuid, uuid)
from public, anon, authenticated;
grant execute on function public.sd_payment_request_can_read(uuid, uuid)
to authenticated;

revoke all on function public.sd_payment_request_can_pay(uuid, uuid)
from public, anon, authenticated;
grant execute on function public.sd_payment_request_can_pay(uuid, uuid)
to authenticated;

drop policy if exists "sd_payment_requests_select_phase_1b1"
on public.sd_payment_requests;
create policy "sd_payment_requests_select_phase_1b1"
on public.sd_payment_requests
for select
to authenticated
using (
  public.sd_is_org_admin(org_id)
  or public.sd_payment_request_can_read(org_id, child_id)
);

revoke all on table public.sd_payment_requests from anon;
revoke select on table public.sd_payment_requests from authenticated;
revoke insert, update, delete on table public.sd_payment_requests from authenticated;
grant select (
  id, org_id, child_id, created_by, title, notes, amount_cents,
  currency, due_date, status, created_at, updated_at
) on table public.sd_payment_requests to authenticated;
grant select, insert, update on table public.sd_payment_requests to service_role;
