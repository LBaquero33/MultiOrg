-- Close organization-authorization gaps without changing platform-admin,
-- Stripe Connect, StoreKit, or organization SaaS-billing authority.
-- Organization administration comes exclusively from an active owner/admin
-- membership in the selected organization. During temporary manual
-- provisioning, the authenticated platform-admin creator receives an explicit
-- active owner membership; platform-admin status by itself grants no org role.

-- Live-data preflight. Fail before replacing either constraint if production
-- contains a role or status outside the values confirmed for this migration.
-- This deliberately reports unexpected values instead of silently remapping
-- them. The approved live platform-admin owner membership is already valid and
-- is not modified by this migration.
do $$
declare
  unexpected_roles text;
  unexpected_statuses text;
begin
  select string_agg(format('%s (%s rows)', role, row_count), ', ' order by role)
  into unexpected_roles
  from (
    select role, count(*) as row_count
    from public.sd_org_memberships
    where role not in ('owner', 'admin', 'coach', 'player', 'parent')
    group by role
  ) invalid_roles;

  select string_agg(format('%s (%s rows)', status, row_count), ', ' order by status)
  into unexpected_statuses
  from (
    select status, count(*) as row_count
    from public.sd_org_memberships
    where status not in ('active', 'invited', 'disabled', 'suspended')
    group by status
  ) invalid_statuses;

  if unexpected_roles is not null then
    raise exception 'unexpected_sd_org_membership_roles: %', unexpected_roles
      using errcode = '23514';
  end if;
  if unexpected_statuses is not null then
    raise exception 'unexpected_sd_org_membership_statuses: %', unexpected_statuses
      using errcode = '23514';
  end if;
end;
$$;

alter table public.sd_org_memberships
  drop constraint if exists sd_org_memberships_role_check;

alter table public.sd_org_memberships
  add constraint sd_org_memberships_role_check
  check (role in ('owner', 'admin', 'coach', 'player', 'parent'));

alter table public.sd_org_memberships
  drop constraint if exists sd_org_memberships_status_check;

alter table public.sd_org_memberships
  add constraint sd_org_memberships_status_check
  check (status in ('active', 'invited', 'disabled', 'suspended'));

create or replace function public.sd_is_org_member(org uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists(
    select 1
    from public.sd_org_memberships m
    where m.org_id = org
      and m.user_id = auth.uid()
      and m.status = 'active'
  );
$$;

create or replace function public.sd_is_org_admin(org uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists(
    select 1
    from public.sd_org_memberships m
    where m.org_id = org
      and m.user_id = auth.uid()
      and m.status = 'active'
      and m.role in ('owner', 'admin')
  );
$$;

create or replace function public.sd_is_org_coach(org uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists(
    select 1
    from public.sd_org_memberships m
    where m.org_id = org
      and m.user_id = auth.uid()
      and m.status = 'active'
      and m.role in ('owner', 'admin', 'coach')
  );
$$;

create or replace function public.sd_is_org_staff(org uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists(
    select 1
    from public.sd_org_memberships m
    where m.org_id = org
      and m.user_id = auth.uid()
      and m.status = 'active'
      and m.role in ('owner', 'admin', 'coach')
  );
$$;

revoke all on function public.sd_is_org_member(uuid)
from public, anon, authenticated;
grant execute on function public.sd_is_org_member(uuid)
to authenticated;

revoke all on function public.sd_is_org_admin(uuid)
from public, anon, authenticated;
grant execute on function public.sd_is_org_admin(uuid)
to authenticated;

revoke all on function public.sd_is_org_coach(uuid)
from public, anon, authenticated;
grant execute on function public.sd_is_org_coach(uuid)
to authenticated;

revoke all on function public.sd_is_org_staff(uuid)
from public, anon, authenticated;
grant execute on function public.sd_is_org_staff(uuid)
to authenticated;

drop policy if exists "sd_org_memberships_manage_by_coach" on public.sd_org_memberships;
drop policy if exists "sd_org_memberships_manage_by_admin" on public.sd_org_memberships;
create policy "sd_org_memberships_manage_by_admin"
on public.sd_org_memberships
for all
to authenticated
using (public.sd_is_org_admin(org_id))
with check (public.sd_is_org_admin(org_id));

create or replace function public.sd_can_manage_team_player(target_org uuid, target_player uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  actor_role text;
  restrict_actions boolean := true;
  actor_team uuid;
  player_team uuid;
begin
  select role into actor_role
  from public.sd_org_memberships
  where org_id = target_org
    and user_id = auth.uid()
    and status = 'active'
  limit 1;

  if actor_role in ('owner', 'admin') then
    return true;
  end if;
  if actor_role <> 'coach' then
    return false;
  end if;

  select coalesce((team_policy ->> 'restrictCoachActionsToTeam')::boolean, true)
  into restrict_actions
  from public.sd_org_settings
  where org_id = target_org;

  if coalesce(restrict_actions, true) = false then
    return true;
  end if;

  select team_id into actor_team
  from public.sd_team_members
  where org_id = target_org and player_id = auth.uid()
  limit 1;

  select team_id into player_team
  from public.sd_team_members
  where org_id = target_org and player_id = target_player
  limit 1;

  return actor_team is not null and actor_team = player_team;
end;
$$;

revoke all on function public.sd_can_manage_team_player(uuid, uuid)
from public, anon, authenticated;
grant execute on function public.sd_can_manage_team_player(uuid, uuid)
to authenticated;

-- Once an organization has an active owner, an update or delete may not leave
-- it without one. The deferred check allows a replacement active owner to be
-- added earlier in the same transaction. Active admins intentionally do not
-- satisfy this invariant. Existing ownerless organizations remain visible to
-- platform diagnostics and are not auto-promoted.
create or replace function public.sd_enforce_last_active_owner()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.role <> 'owner' or old.status <> 'active' then
    if tg_op = 'DELETE' then
      return old;
    end if;
    return new;
  end if;

  if tg_op = 'UPDATE'
    and new.org_id = old.org_id
    and new.role = 'owner'
    and new.status = 'active' then
    return new;
  end if;

  -- Serialize owner-removal checks for the same organization so concurrent
  -- demotions cannot each observe the other owner and both commit. If the
  -- organization row itself was deleted, its cascading membership deletes do
  -- not need to preserve an owner.
  perform 1
  from public.sd_orgs o
  where o.id = old.org_id
  for update;

  if not found then
    if tg_op = 'DELETE' then
      return old;
    end if;
    return new;
  end if;

  if not exists (
    select 1
    from public.sd_org_memberships m
    where m.org_id = old.org_id
      and m.role = 'owner'
      and m.status = 'active'
  ) then
    raise exception 'last_active_owner_required'
      using
        errcode = '23514',
        detail = format('Organization %s must retain at least one active owner.', old.org_id),
        hint = 'Add another active owner before removing, demoting, disabling, or suspending this owner.';
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

revoke all on function public.sd_enforce_last_active_owner()
from public, anon, authenticated;

drop trigger if exists trg_sd_org_memberships_last_active_owner
on public.sd_org_memberships;
create constraint trigger trg_sd_org_memberships_last_active_owner
after update or delete on public.sd_org_memberships
deferrable initially deferred
for each row
execute function public.sd_enforce_last_active_owner();

-- Temporary manual platform provisioning is a single PostgreSQL transaction.
-- The authenticated actor is resolved by the Edge Function and this RPC
-- confirms that actor is a platform admin before assigning the explicit
-- provisional owner membership. Any exception rolls back the organization,
-- owner membership, and settings together.
create or replace function public.sd_platform_create_organization(
  p_actor_id uuid,
  p_name text,
  p_slug text,
  p_plan text default 'starter',
  p_billing_email text default null,
  p_max_members integer default null
)
returns table (
  id uuid,
  slug text,
  name text,
  status text,
  plan text,
  billing_email text,
  max_members integer
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  created_org_id uuid;
  normalized_name text := nullif(btrim(p_name), '');
  normalized_slug text := lower(nullif(btrim(p_slug), ''));
  normalized_plan text := lower(coalesce(nullif(btrim(p_plan), ''), 'starter'));
begin
  if not exists (
    select 1 from public.sd_platform_admins a where a.user_id = p_actor_id
  ) then
    raise exception 'not_platform_admin' using errcode = '42501';
  end if;

  if normalized_name is null then
    raise exception 'missing_organization_name' using errcode = '22023';
  end if;
  if normalized_slug is null or normalized_slug !~ '^[a-z0-9][a-z0-9-]{1,62}$' then
    raise exception 'invalid_organization_slug' using errcode = '22023';
  end if;
  if normalized_plan not in ('starter', 'professional', 'enterprise') then
    raise exception 'invalid_organization_plan' using errcode = '22023';
  end if;
  if p_max_members is not null and p_max_members <= 0 then
    raise exception 'invalid_member_limit' using errcode = '22023';
  end if;

  insert into public.sd_orgs as created_org (
    name, slug, status, plan, billing_email, max_members
  ) values (
    normalized_name,
    normalized_slug,
    'active',
    normalized_plan,
    nullif(lower(btrim(p_billing_email)), ''),
    p_max_members
  ) returning created_org.id into created_org_id;

  insert into public.sd_org_memberships (
    org_id, user_id, role, status, created_by
  ) values (
    created_org_id, p_actor_id, 'owner', 'active', p_actor_id
  );

  insert into public.sd_org_settings (
    org_id, display_name, short_name
  ) values (
    created_org_id, normalized_name, normalized_name
  );

  return query
  select o.id, o.slug, o.name, o.status, o.plan, o.billing_email, o.max_members
  from public.sd_orgs o
  where o.id = created_org_id;
end;
$$;

revoke all on function public.sd_platform_create_organization(
  uuid, text, text, text, text, integer
) from public, anon, authenticated;
grant execute on function public.sd_platform_create_organization(
  uuid, text, text, text, text, integer
) to service_role;

-- Explicit platform diagnostic for organizations with no active owner. It
-- never promotes a member or mutates an organization.
create or replace function public.sd_platform_list_ownerless_organizations(p_actor_id uuid)
returns table (
  id uuid,
  slug text,
  name text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not exists (
    select 1 from public.sd_platform_admins a where a.user_id = p_actor_id
  ) then
    raise exception 'not_platform_admin' using errcode = '42501';
  end if;

  return query
  select o.id, o.slug, o.name
  from public.sd_orgs o
  where not exists (
    select 1
    from public.sd_org_memberships m
    where m.org_id = o.id
      and m.status = 'active'
      and m.role = 'owner'
  )
  order by o.name;
end;
$$;

revoke all on function public.sd_platform_list_ownerless_organizations(uuid)
from public, anon, authenticated;
grant execute on function public.sd_platform_list_ownerless_organizations(uuid)
to service_role;

-- Separate diagnostic for organizations with neither an active owner nor an
-- active admin. This is intentionally distinct from the active-owner invariant.
create or replace function public.sd_platform_list_unmanaged_organizations(p_actor_id uuid)
returns table (
  id uuid,
  slug text,
  name text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not exists (
    select 1 from public.sd_platform_admins a where a.user_id = p_actor_id
  ) then
    raise exception 'not_platform_admin' using errcode = '42501';
  end if;

  return query
  select o.id, o.slug, o.name
  from public.sd_orgs o
  where not exists (
    select 1
    from public.sd_org_memberships m
    where m.org_id = o.id
      and m.status = 'active'
      and m.role in ('owner', 'admin')
  )
  order by o.name;
end;
$$;

revoke all on function public.sd_platform_list_unmanaged_organizations(uuid)
from public, anon, authenticated;
grant execute on function public.sd_platform_list_unmanaged_organizations(uuid)
to service_role;
