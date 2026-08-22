-- Allow active head coaches to create and cancel payment requests only for
-- active players on teams they currently lead. Organization owners/admins and
-- platform support continue using the existing RPCs unchanged.

create or replace function public.sd_head_coach_manages_player(
  p_org_id uuid,
  p_actor_id uuid,
  p_player_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.sd_org_memberships actor
    join public.sd_coach_team_assignments assignment
      on assignment.organization_id = actor.org_id
     and assignment.coach_id = actor.user_id
     and assignment.active
     and assignment.ended_at is null
    join public.sd_coach_team_responsibilities responsibility
      on responsibility.assignment_id = assignment.id
     and responsibility.responsibility = 'head_coach'
    join public.sd_player_team_memberships roster
      on roster.organization_id = assignment.organization_id
     and roster.team_id = assignment.team_id
     and roster.player_id = p_player_id
     and roster.active
     and roster.ended_at is null
    join public.sd_org_memberships player
      on player.org_id = roster.organization_id
     and player.user_id = roster.player_id
     and player.role = 'player'
     and player.status = 'active'
    where actor.org_id = p_org_id
      and actor.user_id = p_actor_id
      and actor.role = 'coach'
      and actor.status = 'active'
  );
$$;

revoke all on function public.sd_head_coach_manages_player(uuid, uuid, uuid)
from public, anon, authenticated;
grant execute on function public.sd_head_coach_manages_player(uuid, uuid, uuid)
to service_role;

create or replace function public.sd_create_head_coach_payment_request_batch(
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
  v_requests jsonb;
  v_created boolean := false;
begin
  if p_org_id is null or p_actor_id is null or p_idempotency_key is null
    or p_player_ids is null or pg_catalog.array_position(p_player_ids, null) is not null then
    raise exception 'invalid_payment_request_batch_input' using errcode = '22023';
  end if;

  select coalesce(pg_catalog.array_agg(item.player_id order by item.player_id), array[]::uuid[])
  into v_player_ids
  from (select distinct supplied.player_id from pg_catalog.unnest(p_player_ids) supplied(player_id)) item;

  if pg_catalog.cardinality(v_player_ids) not between 1 and 100 then
    raise exception 'invalid_payment_request_players' using errcode = '22023';
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
    select 1 from public.sd_orgs organization
    where organization.id = p_org_id and organization.status = 'active'
  ) then
    raise exception 'organization_inactive_or_missing' using errcode = 'P0001';
  end if;
  if exists (
    select 1 from pg_catalog.unnest(v_player_ids) selected(player_id)
    where not public.sd_head_coach_manages_player(p_org_id, p_actor_id, selected.player_id)
  ) then
    raise exception 'payment_request_access_denied' using errcode = 'P0001';
  end if;

  insert into public.sd_payment_request_batches (
    org_id, created_by, idempotency_operation, idempotency_key, player_ids,
    title, description, amount_cents, currency, due_date
  ) values (
    p_org_id, p_actor_id, 'create', p_idempotency_key, v_player_ids,
    v_title, v_description, p_amount_cents, p_currency, p_due_date
  )
  on conflict on constraint sd_payment_request_batches_idempotency_unique do nothing
  returning * into v_batch;

  if v_batch.id is null then
    select batch.* into v_batch
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
      request_batch_id, org_id, child_id, created_by, title, notes,
      amount_cents, currency, due_date, status, idempotency_key, idempotency_operation
    )
    select v_batch.id, p_org_id, selected.player_id, p_actor_id, v_title,
      v_description, p_amount_cents, p_currency, p_due_date, 'open',
      p_idempotency_key, 'create'
    from pg_catalog.unnest(v_player_ids) selected(player_id);
  end if;

  select coalesce(pg_catalog.jsonb_agg(pg_catalog.to_jsonb(request) order by request.child_id), '[]'::jsonb)
  into v_requests
  from public.sd_payment_requests request
  where request.request_batch_id = v_batch.id;

  if pg_catalog.jsonb_array_length(v_requests) <> pg_catalog.cardinality(v_player_ids) then
    raise exception 'payment_request_batch_incomplete' using errcode = 'P0001';
  end if;

  return pg_catalog.jsonb_build_object(
    'requests', v_requests,
    'created_count', case when v_created then pg_catalog.cardinality(v_player_ids) else 0 end,
    'reused', not v_created,
    'authorization_source', 'head_coach'
  );
end;
$$;

revoke all on function public.sd_create_head_coach_payment_request_batch(
  uuid, uuid, uuid[], text, text, integer, text, date, uuid
) from public, anon, authenticated;
grant execute on function public.sd_create_head_coach_payment_request_batch(
  uuid, uuid, uuid[], text, text, integer, text, date, uuid
) to service_role;

create or replace function public.sd_cancel_head_coach_payment_request(
  p_org_id uuid,
  p_actor_id uuid,
  p_request_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_request public.sd_payment_requests%rowtype;
begin
  if p_org_id is null or p_actor_id is null or p_request_id is null then
    raise exception 'invalid_payment_request' using errcode = '22023';
  end if;

  select request.* into v_request
  from public.sd_payment_requests request
  where request.org_id = p_org_id and request.id = p_request_id
  for update;

  if v_request.id is null
    or not public.sd_head_coach_manages_player(p_org_id, p_actor_id, v_request.child_id) then
    raise exception 'payment_request_not_found' using errcode = 'P0001';
  end if;
  if v_request.status = 'paid' then
    raise exception 'paid_request_cannot_be_canceled' using errcode = 'P0001';
  end if;
  if v_request.status = 'canceled' then
    raise exception 'payment_request_already_canceled' using errcode = 'P0001';
  end if;
  if v_request.status <> 'open' then
    raise exception 'payment_request_state_conflict' using errcode = 'P0001';
  end if;

  update public.sd_payment_requests request
  set status = 'canceled'
  where request.org_id = p_org_id and request.id = p_request_id and request.status = 'open'
  returning request.* into v_request;

  if v_request.id is null then
    raise exception 'payment_request_state_conflict' using errcode = 'P0001';
  end if;
  return pg_catalog.jsonb_build_object(
    'request', pg_catalog.to_jsonb(v_request),
    'authorization_source', 'head_coach'
  );
end;
$$;

revoke all on function public.sd_cancel_head_coach_payment_request(uuid, uuid, uuid)
from public, anon, authenticated;
grant execute on function public.sd_cancel_head_coach_payment_request(uuid, uuid, uuid)
to service_role;
