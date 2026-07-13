-- Atomically persist a StoreKit-verified Apple player subscription and its
-- application entitlement. The Edge Function performs JWT and relationship
-- authorization before calling this service-role-only function.

create or replace function public.sd_authorize_apple_player_purchase(
  p_org_id uuid,
  p_player_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_actor_id uuid := auth.uid();
  v_actor_role text;
  v_actor_status text;
  v_target_role text;
  v_target_status text;
  v_parent_can_pay boolean;
begin
  if v_actor_id is null then
    raise exception using errcode = '42501', message = 'invalid_auth';
  end if;
  if not exists (select 1 from public.profiles where id = v_actor_id) then
    raise exception using errcode = 'P0001', message = 'actor_profile_missing';
  end if;
  if not exists (select 1 from public.profiles where id = p_player_id) then
    raise exception using errcode = 'P0001', message = 'target_profile_missing';
  end if;

  select role, status into v_actor_role, v_actor_status
  from public.sd_org_memberships
  where org_id = p_org_id and user_id = v_actor_id;
  if v_actor_role is null then
    raise exception using errcode = 'P0001', message = 'actor_membership_missing';
  end if;
  if lower(v_actor_status) <> 'active' then
    raise exception using errcode = 'P0001', message = 'actor_membership_not_active';
  end if;

  select role, status into v_target_role, v_target_status
  from public.sd_org_memberships
  where org_id = p_org_id and user_id = p_player_id;
  if v_target_role is null then
    raise exception using errcode = 'P0001', message = 'target_membership_missing';
  end if;
  if lower(v_target_status) <> 'active' then
    raise exception using errcode = 'P0001', message = 'target_membership_not_active';
  end if;
  if lower(v_target_role) <> 'player' then
    raise exception using errcode = 'P0001', message = 'target_role_not_player';
  end if;

  if v_actor_id = p_player_id then
    if lower(v_actor_role) <> 'player' then
      raise exception using errcode = 'P0001', message = 'actor_role_not_allowed';
    end if;
    return jsonb_build_object(
      'billing_user_id', v_actor_id,
      'actor_scope', 'player'
    );
  end if;

  if lower(v_actor_role) <> 'parent' then
    raise exception using errcode = 'P0001', message = 'actor_role_not_allowed';
  end if;

  select can_pay into v_parent_can_pay
  from public.sd_parent_child_links
  where org_id = p_org_id
    and parent_id = v_actor_id
    and child_id = p_player_id;
  if v_parent_can_pay is null then
    raise exception using errcode = 'P0001', message = 'parent_link_missing';
  end if;
  if v_parent_can_pay is not true then
    raise exception using errcode = 'P0001', message = 'parent_can_pay_false';
  end if;

  return jsonb_build_object(
    'billing_user_id', v_actor_id,
    'actor_scope', 'parent'
  );
end;
$$;

revoke all on function public.sd_authorize_apple_player_purchase(uuid, uuid)
  from public, anon;
grant execute on function public.sd_authorize_apple_player_purchase(uuid, uuid)
  to authenticated;

create or replace function public.sd_sync_apple_player_subscription(
  p_org_id uuid,
  p_player_id uuid,
  p_billing_user_id uuid,
  p_product_id text,
  p_transaction_id text,
  p_original_transaction_id text,
  p_environment text,
  p_status text,
  p_period_start timestamptz,
  p_period_end timestamptz,
  p_app_account_token uuid,
  p_revocation_date timestamptz default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_by_transaction public.sd_player_subscriptions%rowtype;
  v_by_original public.sd_player_subscriptions%rowtype;
  v_existing public.sd_player_subscriptions%rowtype;
  v_conflicting public.sd_player_subscriptions%rowtype;
  v_entitlement public.sd_access_entitlements%rowtype;
  v_active boolean;
  v_access_active boolean := false;
  v_idempotent boolean := false;
begin
  if auth.role() is distinct from 'service_role' then
    raise exception using errcode = '42501', message = 'service_role_required';
  end if;

  if p_product_id is distinct from 'com.homeplate.player.monthly' then
    raise exception using errcode = 'P0001', message = 'product_id_mismatch';
  end if;
  if p_environment not in ('sandbox', 'production') then
    raise exception using errcode = 'P0001', message = 'environment_mismatch';
  end if;
  if p_status not in (
    'active', 'expired', 'revoked', 'grace_period', 'billing_retry',
    'canceled_at_period_end'
  ) then
    raise exception using errcode = 'P0001', message = 'apple_transaction_invalid';
  end if;
  if p_transaction_id !~ '^[0-9]{1,32}$'
     or p_original_transaction_id !~ '^[0-9]{1,32}$'
     or p_period_start is null
     or p_period_end is null
     or p_period_end <= p_period_start
     or p_app_account_token is null then
    raise exception using errcode = 'P0001', message = 'apple_transaction_invalid';
  end if;

  -- Serialize all writes for this Apple lineage and player. The unique indexes
  -- from 20260714010000 remain the final cross-request replay guard.
  perform pg_advisory_xact_lock(
    hashtextextended('apple-lineage:' || p_original_transaction_id, 0)
  );
  perform pg_advisory_xact_lock(
    hashtextextended('apple-player:' || p_org_id::text || ':' || p_player_id::text, 0)
  );

  select * into v_by_transaction
  from public.sd_player_subscriptions
  where provider = 'apple'
    and provider_transaction_id = p_transaction_id
  for update;

  if found and (
    v_by_transaction.org_id <> p_org_id
    or v_by_transaction.player_id <> p_player_id
    or v_by_transaction.billing_user_id is distinct from p_billing_user_id
  ) then
    raise exception using errcode = 'P0001', message = 'apple_transaction_reassigned';
  end if;

  select * into v_by_original
  from public.sd_player_subscriptions
  where provider = 'apple'
    and original_transaction_id = p_original_transaction_id
  for update;

  if found and (
    v_by_original.org_id <> p_org_id
    or v_by_original.player_id <> p_player_id
    or v_by_original.billing_user_id is distinct from p_billing_user_id
  ) then
    raise exception using errcode = 'P0001', message = 'apple_original_transaction_reassigned';
  end if;

  if v_by_transaction.id is not null
     and v_by_original.id is not null
     and v_by_transaction.id <> v_by_original.id then
    raise exception using errcode = 'P0001', message = 'apple_transaction_lineage_conflict';
  end if;

  if v_by_transaction.id is not null then
    v_existing := v_by_transaction;
  elsif v_by_original.id is not null then
    v_existing := v_by_original;
  end if;

  if v_existing.id is not null then
    if v_existing.provider_product_id is distinct from p_product_id
       or lower(coalesce(v_existing.environment, '')) <> p_environment then
      raise exception using errcode = 'P0001', message = 'apple_transaction_context_mismatch';
    end if;

    v_idempotent := v_existing.provider_transaction_id = p_transaction_id;
    if not v_idempotent and (
      p_period_start <= coalesce(v_existing.current_period_start, '-infinity'::timestamptz)
      or p_period_end < coalesce(v_existing.current_period_end, '-infinity'::timestamptz)
    ) then
      raise exception using errcode = 'P0001', message = 'apple_transaction_replay';
    end if;

    update public.sd_player_subscriptions
    set provider_subscription_id = p_original_transaction_id,
        provider_transaction_id = p_transaction_id,
        original_transaction_id = p_original_transaction_id,
        provider_product_id = p_product_id,
        status = p_status,
        current_period_start = p_period_start,
        current_period_end = p_period_end,
        cancel_at_period_end = p_status = 'canceled_at_period_end',
        environment = p_environment,
        provider_state = jsonb_build_object(
          'app_account_token', p_app_account_token,
          'revocation_date', p_revocation_date
        ),
        updated_at = now()
    where id = v_existing.id;
  else
    select * into v_conflicting
    from public.sd_player_subscriptions
    where org_id = p_org_id
      and player_id = p_player_id
      and status in (
        'active', 'trialing', 'grace', 'past_due', 'grace_period',
        'billing_retry', 'canceled_at_period_end'
      )
    for update;

    if found then
      raise exception using errcode = 'P0001', message = 'player_subscription_context_conflict';
    end if;

    insert into public.sd_player_subscriptions (
      org_id,
      player_id,
      billing_user_id,
      provider,
      provider_subscription_id,
      provider_transaction_id,
      original_transaction_id,
      provider_product_id,
      status,
      current_period_start,
      current_period_end,
      cancel_at_period_end,
      environment,
      provider_state
    ) values (
      p_org_id,
      p_player_id,
      p_billing_user_id,
      'apple',
      p_original_transaction_id,
      p_transaction_id,
      p_original_transaction_id,
      p_product_id,
      p_status,
      p_period_start,
      p_period_end,
      p_status = 'canceled_at_period_end',
      p_environment,
      jsonb_build_object(
        'app_account_token', p_app_account_token,
        'revocation_date', p_revocation_date
      )
    );
  end if;

  v_active := p_status in (
    'active', 'grace_period', 'billing_retry', 'canceled_at_period_end'
  ) and p_period_end > now() and p_revocation_date is null;

  select * into v_entitlement
  from public.sd_access_entitlements
  where user_id = p_player_id
  for update;

  if v_active then
    -- A valid entitlement from another source wins. Apple repairs or creates
    -- only an inactive/missing row or a row already owned by Apple.
    if v_entitlement.user_id is null
       or v_entitlement.is_active is not true
       or v_entitlement.source = 'apple' then
      insert into public.sd_access_entitlements (
        user_id, org_id, is_active, source, current_period_end
      ) values (
        p_player_id, p_org_id, true, 'apple', p_period_end
      )
      on conflict (user_id) do update
      set org_id = excluded.org_id,
          is_active = excluded.is_active,
          source = excluded.source,
          current_period_end = excluded.current_period_end,
          updated_at = now();
    end if;
  elsif v_entitlement.user_id is not null and v_entitlement.source = 'apple' then
    update public.sd_access_entitlements
    set org_id = p_org_id,
        is_active = false,
        current_period_end = p_period_end,
        updated_at = now()
    where user_id = p_player_id;
  end if;

  select coalesce(is_active, false) into v_access_active
  from public.sd_access_entitlements
  where user_id = p_player_id;

  return jsonb_build_object(
    'status', p_status,
    'current_period_end', p_period_end,
    'persisted', true,
    'entitlement_synchronized', true,
    'access_is_active', coalesce(v_access_active, false),
    'idempotent', v_idempotent
  );
exception
  when unique_violation then
    raise exception using errcode = 'P0001', message = 'apple_transaction_replay_conflict';
end;
$$;

revoke all on function public.sd_sync_apple_player_subscription(
  uuid, uuid, uuid, text, text, text, text, text, timestamptz,
  timestamptz, uuid, timestamptz
) from public, anon, authenticated;

grant execute on function public.sd_sync_apple_player_subscription(
  uuid, uuid, uuid, text, text, text, text, text, timestamptz,
  timestamptz, uuid, timestamptz
) to service_role;
