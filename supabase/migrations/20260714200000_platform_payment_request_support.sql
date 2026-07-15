-- Explicit platform-support authorization for internal payment requests.
--
-- Platform administrators remain separate from organization membership. The
-- JWT-verifying Edge Function supplies p_actor_id, and these service-role-only
-- functions independently verify either active owner/admin membership or an
-- effective sd_platform_admins grant. Platform-admin mutations and their audit
-- entries are committed atomically.
--
-- Rollback: deploy an Edge Function that no longer requests platform-support
-- access, restore the prior sd_create_payment_request_batch definition, then
-- drop sd_cancel_payment_request(uuid, uuid, uuid). Audit rows are historical
-- records and should not be deleted during rollback.

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
  v_actor_is_platform_admin boolean := false;
  v_authorization_source text;
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

  select exists (
    select 1
    from public.sd_platform_admins platform_admin
    where platform_admin.user_id = p_actor_id
  ) into v_actor_is_platform_admin;

  if exists (
    select 1
    from public.sd_org_memberships actor
    where actor.org_id = p_org_id
      and actor.user_id = p_actor_id
      and actor.role in ('owner', 'admin')
      and actor.status = 'active'
  ) then
    v_authorization_source := 'organization_membership';
  elsif v_actor_is_platform_admin then
    v_authorization_source := 'platform_support';
  else
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
      'reused', true,
      'authorization_source', v_authorization_source
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

  if v_created and v_actor_is_platform_admin then
    insert into public.sd_platform_audit_logs (
      actor_id,
      action,
      target_type,
      target_id,
      org_id,
      details
    ) values (
      p_actor_id,
      'platform_payment_request_batch_created',
      'payment_request_batch',
      v_batch.id::text,
      p_org_id,
      pg_catalog.jsonb_build_object(
        'authorization_source', v_authorization_source,
        'request_count', v_created_count
      )
    );
  end if;

  return pg_catalog.jsonb_build_object(
    'requests', v_requests,
    'created_count', v_created_count,
    'reused', not v_created,
    'authorization_source', v_authorization_source
  );
end;
$$;

revoke all on function public.sd_create_payment_request_batch(
  uuid, uuid, uuid[], text, text, integer, text, date, uuid
) from public, anon, authenticated;
grant execute on function public.sd_create_payment_request_batch(
  uuid, uuid, uuid[], text, text, integer, text, date, uuid
) to service_role;

create or replace function public.sd_cancel_payment_request(
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
  v_actor_is_platform_admin boolean := false;
  v_authorization_source text;
begin
  if p_org_id is null or p_actor_id is null or p_request_id is null then
    raise exception 'invalid_payment_request' using errcode = '22023';
  end if;

  if not exists (
    select 1
    from public.sd_orgs organization
    where organization.id = p_org_id
      and organization.status = 'active'
  ) then
    raise exception 'organization_inactive_or_missing' using errcode = 'P0001';
  end if;

  select exists (
    select 1
    from public.sd_platform_admins platform_admin
    where platform_admin.user_id = p_actor_id
  ) into v_actor_is_platform_admin;

  if exists (
    select 1
    from public.sd_org_memberships actor
    where actor.org_id = p_org_id
      and actor.user_id = p_actor_id
      and actor.role in ('owner', 'admin')
      and actor.status = 'active'
  ) then
    v_authorization_source := 'organization_membership';
  elsif v_actor_is_platform_admin then
    v_authorization_source := 'platform_support';
  else
    raise exception 'organization_admin_required' using errcode = 'P0001';
  end if;

  select request.*
  into v_request
  from public.sd_payment_requests request
  where request.org_id = p_org_id
    and request.id = p_request_id
  for update;

  if v_request.id is null then
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
  where request.org_id = p_org_id
    and request.id = p_request_id
    and request.status = 'open'
  returning request.* into v_request;

  if v_request.id is null then
    raise exception 'payment_request_state_conflict' using errcode = 'P0001';
  end if;

  if v_actor_is_platform_admin then
    insert into public.sd_platform_audit_logs (
      actor_id,
      action,
      target_type,
      target_id,
      org_id,
      details
    ) values (
      p_actor_id,
      'platform_payment_request_canceled',
      'payment_request',
      p_request_id::text,
      p_org_id,
      pg_catalog.jsonb_build_object(
        'authorization_source', v_authorization_source
      )
    );
  end if;

  return pg_catalog.jsonb_build_object(
    'request', pg_catalog.to_jsonb(v_request),
    'authorization_source', v_authorization_source
  );
end;
$$;

revoke all on function public.sd_cancel_payment_request(uuid, uuid, uuid)
from public, anon, authenticated;
grant execute on function public.sd_cancel_payment_request(uuid, uuid, uuid)
to service_role;
