-- Make Apple In-App Purchase the only consumer purchase authority for Home
-- Plate player digital access. Organization-sponsored access remains a
-- separate, server-verified enterprise concept; no client or org-admin grant
-- path is introduced by this migration.

create table if not exists public.sd_access_entitlement_compliance_audit (
  id uuid primary key default gen_random_uuid(),
  migration_key text not null,
  user_id uuid not null,
  org_id uuid,
  prior_is_active boolean not null,
  prior_source text not null,
  prior_current_period_end timestamptz,
  action text not null check (action in (
    'reclassified_organization_sponsored',
    'deactivated_legacy_access'
  )),
  reason text not null,
  recorded_at timestamptz not null default now(),
  unique (migration_key, user_id)
);

alter table public.sd_access_entitlement_compliance_audit enable row level security;
revoke all on table public.sd_access_entitlement_compliance_audit from public, anon, authenticated;
grant select, insert on table public.sd_access_entitlement_compliance_audit to service_role;

-- Preserve access that is demonstrably part of an active organization-wide
-- agreement. Both the user's active membership and an active server-owned
-- organization subscription are required; the old manual label alone is not
-- trusted as evidence.
insert into public.sd_access_entitlement_compliance_audit (
  migration_key,
  user_id,
  org_id,
  prior_is_active,
  prior_source,
  prior_current_period_end,
  action,
  reason
)
select
  '20260903180000_app_store_commerce_compliance',
  entitlement.user_id,
  entitlement.org_id,
  entitlement.is_active,
  entitlement.source,
  entitlement.current_period_end,
  'reclassified_organization_sponsored',
  'Access is covered by an active organization membership and an active organization-wide subscription.'
from public.sd_access_entitlements entitlement
where entitlement.is_active is true
  and entitlement.source not in ('apple', 'organization_sponsored')
  and exists (
    select 1
    from public.sd_org_memberships membership
    where membership.org_id = entitlement.org_id
      and membership.user_id = entitlement.user_id
      and membership.status = 'active'
  )
  and exists (
    select 1
    from public.sd_org_subscriptions subscription
    where subscription.org_id = entitlement.org_id
      and subscription.status in ('active', 'trialing')
  )
on conflict (migration_key, user_id) do nothing;

update public.sd_access_entitlements entitlement
set source = 'organization_sponsored',
    updated_at = now()
where entitlement.is_active is true
  and entitlement.source not in ('apple', 'organization_sponsored')
  and exists (
    select 1
    from public.sd_org_memberships membership
    where membership.org_id = entitlement.org_id
      and membership.user_id = entitlement.user_id
      and membership.status = 'active'
  )
  and exists (
    select 1
    from public.sd_org_subscriptions subscription
    where subscription.org_id = entitlement.org_id
      and subscription.status in ('active', 'trialing')
  );

-- Anything still active after the organization-evidence pass is consumer or
-- otherwise unverified legacy access and must fail closed.
insert into public.sd_access_entitlement_compliance_audit (
  migration_key,
  user_id,
  org_id,
  prior_is_active,
  prior_source,
  prior_current_period_end,
  action,
  reason
)
select
  '20260903180000_app_store_commerce_compliance',
  user_id,
  org_id,
  is_active,
  source,
  current_period_end,
  'deactivated_legacy_access',
  'Consumer digital access must be activated by verified Apple IAP; legacy manual and Stripe grants require separate review.'
from public.sd_access_entitlements
where is_active is true
  and source not in ('apple', 'organization_sponsored')
on conflict (migration_key, user_id) do nothing;

update public.sd_access_entitlements
set is_active = false,
    source = case
      when source in ('pending_apple_purchase', 'legacy_inactive') then source
      else 'legacy_inactive'
    end,
    updated_at = now()
where source not in ('apple', 'organization_sponsored')
  and (
    is_active is true
    or source not in ('pending_apple_purchase', 'legacy_inactive')
  );

alter table public.sd_access_entitlements
  drop constraint if exists sd_access_entitlements_source_check;
alter table public.sd_access_entitlements
  alter column source set default 'pending_apple_purchase';
alter table public.sd_access_entitlements
  add constraint sd_access_entitlements_source_check
  check (source in (
    'apple',
    'pending_apple_purchase',
    'organization_sponsored',
    'legacy_inactive'
  ));

-- Paying an organization-issued request is payment for a real-world baseball
-- service. It must never unlock digital application access.
drop trigger if exists trg_sd_payment_requests_paid on public.sd_payment_requests;
drop function if exists public.sd_on_payment_request_paid();

-- Retire the legacy Stripe player-subscription mutation while preserving the
-- signature so an old worker fails closed instead of silently granting access.
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
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  raise exception using
    errcode = 'P0001',
    message = 'stripe_player_digital_access_disabled';
end;
$$;

revoke all on function public.sd_sync_stripe_player_subscription(
  uuid,uuid,uuid,text,text,text,text,text,timestamptz,timestamptz,boolean
) from public, anon, authenticated, service_role;

comment on table public.sd_access_entitlement_compliance_audit is
  'Immutable evidence of legacy player digital-access deactivation during App Store commerce remediation.';
comment on constraint sd_access_entitlements_source_check on public.sd_access_entitlements is
  'Player digital access is Apple-owned unless a separately verified organization sponsorship exists.';
