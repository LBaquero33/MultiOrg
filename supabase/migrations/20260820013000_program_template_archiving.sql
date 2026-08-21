alter table public.sd_program_templates
  add column if not exists archived_at timestamptz;
create index if not exists idx_sd_program_templates_org_active
  on public.sd_program_templates (org_id, created_at desc)
  where archived_at is null;
comment on column public.sd_program_templates.archived_at is
  'Soft-removes templates that have assignment history while preserving player records.';
alter table public.sd_program_templates
  drop constraint if exists sd_program_templates_program_kind_check;
alter table public.sd_program_templates
  add constraint sd_program_templates_program_kind_check
  check (program_kind in ('strength', 'hitting', 'pitching', 'general'));
alter table public.sd_program_templates
  drop constraint if exists sd_program_templates_weeks_check;
alter table public.sd_program_templates
  add constraint sd_program_templates_weeks_check
  check (weeks between 1 and 52);
create unique index if not exists ux_sd_player_subscriptions_stripe_subscription
  on public.sd_player_subscriptions (provider_subscription_id)
  where provider = 'stripe' and provider_subscription_id is not null;
create or replace function public.sd_sync_stripe_player_subscription(
  p_org_id uuid,
  p_player_id uuid,
  p_billing_user_id uuid,
  p_customer_id text,
  p_subscription_id text,
  p_product_id text,
  p_price_id text,
  p_status text,
  p_period_start timestamptz,
  p_period_end timestamptz,
  p_cancel_at_period_end boolean
) returns jsonb
language plpgsql
security definer
set search_path = 'public', 'pg_temp'
as $$
declare
  v_existing public.sd_player_subscriptions%rowtype;
  v_entitlement public.sd_access_entitlements%rowtype;
  v_active boolean;
begin
  if auth.role() is distinct from 'service_role' then
    raise exception using errcode = '42501', message = 'service_role_required';
  end if;
  if coalesce(btrim(p_customer_id), '') = ''
     or coalesce(btrim(p_subscription_id), '') = ''
     or coalesce(btrim(p_product_id), '') = ''
     or coalesce(btrim(p_price_id), '') = ''
     or p_status not in ('active','trialing','past_due','canceled','unpaid','incomplete','incomplete_expired','paused')
     or p_period_end is null
     or p_period_start is null
     or p_period_end <= p_period_start then
    raise exception using errcode = 'P0001', message = 'stripe_subscription_invalid';
  end if;
  if not exists (
    select 1 from public.sd_org_memberships
    where org_id = p_org_id and user_id = p_player_id
      and role = 'player' and status = 'active'
  ) then
    raise exception using errcode = '42501', message = 'player_membership_required';
  end if;
  if p_billing_user_id <> p_player_id and not exists (
    select 1
    from public.sd_org_memberships m
    join public.sd_parent_child_links l
      on l.org_id = m.org_id and l.parent_id = m.user_id
    where m.org_id = p_org_id
      and m.user_id = p_billing_user_id
      and m.role = 'parent'
      and m.status = 'active'
      and l.child_id = p_player_id
      and l.can_pay = true
  ) then
    raise exception using errcode = '42501', message = 'billing_actor_not_authorized';
  end if;

  perform pg_advisory_xact_lock(hashtextextended('stripe-sub:' || p_subscription_id, 0));
  perform pg_advisory_xact_lock(hashtextextended('stripe-player:' || p_org_id::text || ':' || p_player_id::text, 0));

  select * into v_existing
  from public.sd_player_subscriptions
  where provider = 'stripe' and provider_subscription_id = p_subscription_id
  for update;
  if found and (
    v_existing.org_id <> p_org_id
    or v_existing.player_id <> p_player_id
    or v_existing.billing_user_id is distinct from p_billing_user_id
  ) then
    raise exception using errcode = 'P0001', message = 'stripe_subscription_reassigned';
  end if;

  if v_existing.id is null then
    if exists (
      select 1 from public.sd_player_subscriptions
      where org_id = p_org_id and player_id = p_player_id
        and status in ('active','trialing','grace','past_due','grace_period','billing_retry','canceled_at_period_end')
    ) then
      raise exception using errcode = 'P0001', message = 'player_subscription_context_conflict';
    end if;
    insert into public.sd_player_subscriptions (
      org_id, player_id, billing_user_id, provider, provider_customer_id,
      provider_subscription_id, provider_product_id, status,
      current_period_start, current_period_end, cancel_at_period_end,
      environment, provider_state
    ) values (
      p_org_id, p_player_id, p_billing_user_id, 'stripe', p_customer_id,
      p_subscription_id, p_product_id, p_status,
      p_period_start, p_period_end, coalesce(p_cancel_at_period_end, false),
      'stripe', jsonb_build_object('price_id', p_price_id)
    );
  else
    update public.sd_player_subscriptions
    set provider_customer_id = p_customer_id,
        provider_product_id = p_product_id,
        status = p_status,
        current_period_start = p_period_start,
        current_period_end = p_period_end,
        cancel_at_period_end = coalesce(p_cancel_at_period_end, false),
        provider_state = jsonb_build_object('price_id', p_price_id),
        updated_at = now()
    where id = v_existing.id;
  end if;

  v_active := p_status in ('active','trialing','past_due') and p_period_end > now();
  select * into v_entitlement
  from public.sd_access_entitlements
  where user_id = p_player_id
  for update;

  if v_active then
    if v_entitlement.user_id is null
       or v_entitlement.is_active is not true
       or v_entitlement.source = 'stripe' then
      insert into public.sd_access_entitlements (
        user_id, org_id, is_active, source, stripe_customer_id,
        stripe_subscription_id, current_period_end
      ) values (
        p_player_id, p_org_id, true, 'stripe', p_customer_id,
        p_subscription_id, p_period_end
      ) on conflict (user_id) do update
      set org_id = excluded.org_id,
          is_active = true,
          source = 'stripe',
          stripe_customer_id = excluded.stripe_customer_id,
          stripe_subscription_id = excluded.stripe_subscription_id,
          current_period_end = excluded.current_period_end,
          updated_at = now();
    end if;
  elsif v_entitlement.user_id is not null
        and v_entitlement.source = 'stripe'
        and v_entitlement.stripe_subscription_id = p_subscription_id then
    update public.sd_access_entitlements
    set is_active = false,
        current_period_end = p_period_end,
        updated_at = now()
    where user_id = p_player_id;
  end if;

  return jsonb_build_object(
    'persisted', true,
    'status', p_status,
    'access_is_active', coalesce((select is_active from public.sd_access_entitlements where user_id = p_player_id), false)
  );
end;
$$;
revoke all on function public.sd_sync_stripe_player_subscription(
  uuid,uuid,uuid,text,text,text,text,text,timestamptz,timestamptz,boolean
) from public, anon, authenticated;
grant execute on function public.sd_sync_stripe_player_subscription(
  uuid,uuid,uuid,text,text,text,text,text,timestamptz,timestamptz,boolean
) to service_role;
