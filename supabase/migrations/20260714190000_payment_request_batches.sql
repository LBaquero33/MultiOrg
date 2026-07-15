-- Stripe Payments Phase 1B-1 follow-up: transactional multi-player batches.
--
-- Rollback: stop callers first, drop sd_create_payment_request_batch, remove
-- request_batch_id from sd_payment_requests, and drop sd_payment_request_batches.
-- Recreate ux_sd_payment_requests_create_idempotency only after proving no
-- multi-row batch shares an idempotency key. Existing legacy requests are not
-- rewritten by this migration and may retain a null request_batch_id.

create table if not exists public.sd_payment_request_batches (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.sd_orgs(id) on delete cascade,
  created_by uuid not null references auth.users(id) on delete restrict,
  idempotency_operation text not null default 'create',
  idempotency_key uuid not null,
  player_ids uuid[] not null,
  title text not null,
  description text,
  amount_cents integer not null,
  currency text not null,
  due_date date,
  created_at timestamptz not null default now(),
  constraint sd_payment_request_batches_operation_check
    check (idempotency_operation = 'create'),
  constraint sd_payment_request_batches_players_check
    check (cardinality(player_ids) between 1 and 100),
  constraint sd_payment_request_batches_title_check
    check (char_length(btrim(title)) between 1 and 120),
  constraint sd_payment_request_batches_description_check
    check (description is null or char_length(description) <= 1000),
  constraint sd_payment_request_batches_amount_check
    check (amount_cents between 1 and 10000000),
  constraint sd_payment_request_batches_currency_check
    check (currency = 'usd'),
  constraint sd_payment_request_batches_idempotency_unique
    unique (org_id, created_by, idempotency_operation, idempotency_key)
);

alter table public.sd_payment_request_batches enable row level security;
revoke all on table public.sd_payment_request_batches
from public, anon, authenticated, service_role;

alter table public.sd_payment_requests
  add column if not exists request_batch_id uuid
  references public.sd_payment_request_batches(id) on delete restrict;

-- Batch-level idempotency replaces the single-row uniqueness rule. Every new
-- row still carries the operation key for auditability, but the batch record is
-- the sole uniqueness and material-binding authority.
drop index if exists public.ux_sd_payment_requests_create_idempotency;
create index if not exists idx_sd_payment_requests_create_idempotency_lookup
on public.sd_payment_requests(org_id, created_by, idempotency_operation, idempotency_key)
where idempotency_key is not null;

create unique index if not exists ux_sd_payment_requests_batch_player
on public.sd_payment_requests(request_batch_id, child_id)
where request_batch_id is not null;

create index if not exists idx_sd_payment_requests_batch
on public.sd_payment_requests(request_batch_id, created_at)
where request_batch_id is not null;

grant select (request_batch_id)
on table public.sd_payment_requests to authenticated;

-- New requests must belong to a batch. Legacy rows remain valid with a null
-- batch ID. Business fields and batch identity remain immutable after insert.
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
      or new.request_batch_id is null
      or new.idempotency_key is null
      or new.idempotency_operation <> 'create' then
      raise exception 'payment_request_server_fields_required' using errcode = '23514';
    end if;
    return new;
  end if;

  if new.org_id is distinct from old.org_id
    or new.child_id is distinct from old.child_id
    or new.created_by is distinct from old.created_by
    or new.request_batch_id is distinct from old.request_batch_id
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
          detail = pg_catalog.format(
            'Payment request cannot transition from %s to %s.',
            old.status,
            new.status
          );
end;
$$;

revoke all on function public.sd_payment_requests_enforce_state()
from public, anon, authenticated;

-- A single RPC statement is one PostgreSQL transaction: authorization,
-- validation, batch idempotency, and all per-player inserts commit or roll back
-- together. The actor UUID is supplied only by the JWT-verifying Edge Function;
-- execution is restricted to service_role.
create or replace function public.sd_create_payment_request_batch(
  p_org_id uuid,
  p_actor_id uuid,
  p_player_ids uuid[],
  p_title text,
  p_description text,
  p_amount_cents integer,
  p_currency text,
  p_due_date date,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_player_ids uuid[];
  v_title text := pg_catalog.btrim(p_title);
  v_description text := nullif(pg_catalog.btrim(p_description), '');
  v_batch public.sd_payment_request_batches%rowtype;
  v_legacy public.sd_payment_requests%rowtype;
  v_requests jsonb;
  v_created boolean := false;
  v_created_count integer := 0;
begin
  if p_org_id is null or p_actor_id is null or p_idempotency_key is null then
    raise exception 'invalid_payment_request_batch_input' using errcode = '22023';
  end if;

  if p_player_ids is null or pg_catalog.array_position(p_player_ids, null) is not null then
    raise exception 'invalid_payment_request_players' using errcode = '22023';
  end if;

  select coalesce(
    pg_catalog.array_agg(normalized.player_id order by normalized.player_id),
    array[]::uuid[]
  )
  into v_player_ids
  from (
    select distinct supplied.player_id
    from pg_catalog.unnest(p_player_ids) as supplied(player_id)
  ) normalized;

  if pg_catalog.cardinality(v_player_ids) = 0 then
    raise exception 'invalid_payment_request_players' using errcode = '22023';
  end if;
  if pg_catalog.cardinality(v_player_ids) > 100 then
    raise exception 'payment_request_batch_too_large' using errcode = '22023';
  end if;
  if v_title is null or pg_catalog.char_length(v_title) not between 1 and 120 then
    raise exception 'invalid_payment_request_title' using errcode = '22023';
  end if;
  if v_description is not null and pg_catalog.char_length(v_description) > 1000 then
    raise exception 'invalid_payment_request_description' using errcode = '22023';
  end if;
  if p_amount_cents is null or p_amount_cents not between 1 and 10000000 then
    raise exception 'invalid_payment_request_amount' using errcode = '22023';
  end if;
  if p_currency is distinct from 'usd' then
    raise exception 'unsupported_payment_request_currency' using errcode = '22023';
  end if;

  if not exists (
    select 1
    from public.sd_orgs organization
    where organization.id = p_org_id
      and organization.status = 'active'
  ) then
    raise exception 'organization_inactive_or_missing' using errcode = 'P0001';
  end if;

  if not exists (
    select 1
    from public.sd_org_memberships actor
    where actor.org_id = p_org_id
      and actor.user_id = p_actor_id
      and actor.role in ('owner', 'admin')
      and actor.status = 'active'
  ) then
    raise exception 'organization_admin_required' using errcode = 'P0001';
  end if;

  if (
    select pg_catalog.count(*)
    from public.sd_org_memberships player
    where player.org_id = p_org_id
      and player.user_id = any(v_player_ids)
      and player.role = 'player'
      and player.status = 'active'
  ) <> pg_catalog.cardinality(v_player_ids) then
    raise exception 'active_player_membership_required' using errcode = 'P0001';
  end if;

  -- Preserve ambiguous retries from the deployed single-player implementation
  -- without modifying those legacy rows. A matching legacy key is returned;
  -- changed material fails closed.
  select request.*
  into v_legacy
  from public.sd_payment_requests request
  where request.org_id = p_org_id
    and request.created_by = p_actor_id
    and request.idempotency_operation = 'create'
    and request.idempotency_key = p_idempotency_key
    and request.request_batch_id is null
  order by request.created_at
  limit 1;

  if v_legacy.id is not null then
    if v_player_ids <> array[v_legacy.child_id]
      or v_legacy.title is distinct from v_title
      or v_legacy.notes is distinct from v_description
      or v_legacy.amount_cents is distinct from p_amount_cents
      or v_legacy.currency is distinct from p_currency
      or v_legacy.due_date is distinct from p_due_date then
      raise exception 'payment_request_idempotency_conflict' using errcode = 'P0001';
    end if;

    return pg_catalog.jsonb_build_object(
      'requests', pg_catalog.jsonb_build_array(pg_catalog.to_jsonb(v_legacy)),
      'created_count', 0,
      'reused', true
    );
  end if;

  insert into public.sd_payment_request_batches (
    org_id,
    created_by,
    idempotency_operation,
    idempotency_key,
    player_ids,
    title,
    description,
    amount_cents,
    currency,
    due_date
  ) values (
    p_org_id,
    p_actor_id,
    'create',
    p_idempotency_key,
    v_player_ids,
    v_title,
    v_description,
    p_amount_cents,
    p_currency,
    p_due_date
  )
  on conflict on constraint sd_payment_request_batches_idempotency_unique
  do nothing
  returning * into v_batch;

  if v_batch.id is null then
    select batch.*
    into v_batch
    from public.sd_payment_request_batches batch
    where batch.org_id = p_org_id
      and batch.created_by = p_actor_id
      and batch.idempotency_operation = 'create'
      and batch.idempotency_key = p_idempotency_key
    for update;

    if v_batch.id is null then
      raise exception 'payment_request_batch_lookup_failed' using errcode = 'P0001';
    end if;
    if v_batch.player_ids is distinct from v_player_ids
      or v_batch.title is distinct from v_title
      or v_batch.description is distinct from v_description
      or v_batch.amount_cents is distinct from p_amount_cents
      or v_batch.currency is distinct from p_currency
      or v_batch.due_date is distinct from p_due_date then
      raise exception 'payment_request_idempotency_conflict' using errcode = 'P0001';
    end if;
  else
    v_created := true;
    insert into public.sd_payment_requests (
      request_batch_id,
      org_id,
      child_id,
      created_by,
      title,
      notes,
      amount_cents,
      currency,
      due_date,
      status,
      idempotency_key,
      idempotency_operation
    )
    select
      v_batch.id,
      p_org_id,
      player.player_id,
      p_actor_id,
      v_title,
      v_description,
      p_amount_cents,
      p_currency,
      p_due_date,
      'open',
      p_idempotency_key,
      'create'
    from pg_catalog.unnest(v_player_ids) as player(player_id);
    v_created_count := pg_catalog.cardinality(v_player_ids);
  end if;

  select coalesce(
    pg_catalog.jsonb_agg(pg_catalog.to_jsonb(request) order by request.child_id),
    '[]'::jsonb
  )
  into v_requests
  from public.sd_payment_requests request
  where request.request_batch_id = v_batch.id;

  if pg_catalog.jsonb_array_length(v_requests) <> pg_catalog.cardinality(v_player_ids) then
    raise exception 'payment_request_batch_incomplete' using errcode = 'P0001';
  end if;

  return pg_catalog.jsonb_build_object(
    'requests', v_requests,
    'created_count', v_created_count,
    'reused', not v_created
  );
end;
$$;

revoke all on function public.sd_create_payment_request_batch(
  uuid, uuid, uuid[], text, text, integer, text, date, uuid
) from public, anon, authenticated;
grant execute on function public.sd_create_payment_request_batch(
  uuid, uuid, uuid[], text, text, integer, text, date, uuid
) to service_role;
