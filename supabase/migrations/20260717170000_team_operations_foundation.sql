-- Phase 12A: season-aware, historical, team-scoped baseball operations.
-- Additive only. Existing sd_teams and sd_team_members remain available as a
-- compatibility projection while new workflows use the normalized tables.

create table if not exists public.sd_seasons (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.sd_orgs(id) on delete cascade,
  name text not null check (length(btrim(name)) between 1 and 120),
  start_date date,
  end_date date,
  status text not null default 'planning' check (status in (
    'planning', 'registration_open', 'roster_building', 'active',
    'playoffs', 'completed', 'archived'
  )),
  is_default boolean not null default false,
  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (end_date is null or start_date is null or end_date >= start_date),
  unique (organization_id, name)
);

create unique index if not exists uq_sd_seasons_default_per_org
  on public.sd_seasons(organization_id) where is_default;
create index if not exists idx_sd_seasons_org_status
  on public.sd_seasons(organization_id, status, start_date desc nulls last);

alter table public.sd_teams
  add column if not exists season_id uuid references public.sd_seasons(id) on delete restrict;
create index if not exists idx_sd_teams_org_season
  on public.sd_teams(org_id, season_id, is_active, sort_order, name);

-- Existing organizations receive a neutral default season. Dates remain null
-- because the legacy schema did not record authoritative season boundaries.
insert into public.sd_seasons (organization_id, name, status, is_default)
select distinct t.org_id, 'Current Season', 'active', true
from public.sd_teams t
where not exists (
  select 1 from public.sd_seasons s where s.organization_id = t.org_id
)
on conflict (organization_id, name) do nothing;

update public.sd_teams t
set season_id = s.id
from public.sd_seasons s
where t.season_id is null
  and s.organization_id = t.org_id
  and s.is_default;

create table if not exists public.sd_player_team_memberships (
  id uuid primary key default gen_random_uuid(),
  player_id uuid not null references auth.users(id) on delete cascade,
  organization_id uuid not null references public.sd_orgs(id) on delete cascade,
  season_id uuid not null references public.sd_seasons(id) on delete restrict,
  team_id uuid not null references public.sd_teams(id) on delete restrict,
  started_at timestamptz not null default now(),
  ended_at timestamptz,
  active boolean not null default true,
  assignment_reason text,
  transfer_metadata jsonb not null default '{}'::jsonb,
  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check ((active and ended_at is null) or (not active and ended_at is not null)),
  check (ended_at is null or ended_at >= started_at)
);

create unique index if not exists uq_sd_player_one_active_team_per_org
  on public.sd_player_team_memberships(organization_id, player_id)
  where active and ended_at is null;
create index if not exists idx_sd_player_team_memberships_team_active
  on public.sd_player_team_memberships(organization_id, season_id, team_id, active);
create index if not exists idx_sd_player_team_memberships_player_history
  on public.sd_player_team_memberships(organization_id, player_id, started_at desc);

create table if not exists public.sd_coach_team_assignments (
  id uuid primary key default gen_random_uuid(),
  coach_id uuid not null references auth.users(id) on delete cascade,
  organization_id uuid not null references public.sd_orgs(id) on delete cascade,
  season_id uuid not null references public.sd_seasons(id) on delete restrict,
  team_id uuid not null references public.sd_teams(id) on delete restrict,
  is_primary boolean not null default false,
  organization_wide_access boolean not null default false,
  started_at timestamptz not null default now(),
  ended_at timestamptz,
  active boolean not null default true,
  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check ((active and ended_at is null) or (not active and ended_at is not null)),
  check (ended_at is null or ended_at >= started_at)
);

create unique index if not exists uq_sd_coach_active_team_assignment
  on public.sd_coach_team_assignments(organization_id, season_id, team_id, coach_id)
  where active and ended_at is null;
create unique index if not exists uq_sd_coach_primary_team_per_org
  on public.sd_coach_team_assignments(organization_id, coach_id)
  where active and ended_at is null and is_primary;
create index if not exists idx_sd_coach_team_assignments_lookup
  on public.sd_coach_team_assignments(organization_id, coach_id, season_id, active);
create index if not exists idx_sd_coach_team_assignments_staff
  on public.sd_coach_team_assignments(organization_id, season_id, team_id, active);

create table if not exists public.sd_coach_team_responsibilities (
  assignment_id uuid not null references public.sd_coach_team_assignments(id) on delete cascade,
  responsibility text not null check (responsibility in (
    'head_coach', 'assistant_coach', 'hitting_coach', 'pitching_coach',
    'catching_coach', 'strength_coach', 'team_manager', 'evaluator', 'read_only'
  )),
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  primary key (assignment_id, responsibility)
);

create table if not exists public.sd_team_operations_audit_logs (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.sd_orgs(id) on delete cascade,
  actor_id uuid references auth.users(id) on delete set null,
  action text not null,
  target_type text not null,
  target_id uuid,
  request_id uuid,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create unique index if not exists uq_sd_team_operations_audit_request
  on public.sd_team_operations_audit_logs(organization_id, request_id, action)
  where request_id is not null;
create index if not exists idx_sd_team_operations_audit_org_created
  on public.sd_team_operations_audit_logs(organization_id, created_at desc);

-- Backfill only player rows into historical membership. Coaches are migrated
-- separately with a safe read-only responsibility and may then be refined by
-- an organization administrator.
insert into public.sd_player_team_memberships (
  player_id, organization_id, season_id, team_id, started_at,
  assignment_reason, created_by
)
select tm.player_id, tm.org_id, t.season_id, tm.team_id,
       coalesce(tm.assigned_at, now()), 'legacy_team_assignment', tm.assigned_by
from public.sd_team_members tm
join public.sd_teams t on t.id = tm.team_id and t.org_id = tm.org_id
join public.sd_org_memberships om
  on om.org_id = tm.org_id and om.user_id = tm.player_id
where om.role = 'player' and om.status = 'active' and t.season_id is not null
  and not exists (
    select 1 from public.sd_player_team_memberships pm
    where pm.organization_id = tm.org_id and pm.player_id = tm.player_id
      and pm.active and pm.ended_at is null
  );

insert into public.sd_coach_team_assignments (
  coach_id, organization_id, season_id, team_id, is_primary, started_at, created_by
)
select tm.player_id, tm.org_id, t.season_id, tm.team_id, true,
       coalesce(tm.assigned_at, now()), tm.assigned_by
from public.sd_team_members tm
join public.sd_teams t on t.id = tm.team_id and t.org_id = tm.org_id
join public.sd_org_memberships om
  on om.org_id = tm.org_id and om.user_id = tm.player_id
where om.role in ('owner', 'admin', 'coach') and om.status = 'active'
  and t.season_id is not null
  and not exists (
    select 1 from public.sd_coach_team_assignments ca
    where ca.organization_id = tm.org_id and ca.coach_id = tm.player_id
      and ca.team_id = tm.team_id and ca.active and ca.ended_at is null
  );

insert into public.sd_coach_team_responsibilities (assignment_id, responsibility)
select ca.id, 'read_only'
from public.sd_coach_team_assignments ca
where not exists (
  select 1 from public.sd_coach_team_responsibilities cr
  where cr.assignment_id = ca.id
);

drop trigger if exists trg_sd_seasons_updated_at on public.sd_seasons;
create trigger trg_sd_seasons_updated_at before update on public.sd_seasons
for each row execute function public.sd_set_updated_at();
drop trigger if exists trg_sd_player_team_memberships_updated_at on public.sd_player_team_memberships;
create trigger trg_sd_player_team_memberships_updated_at before update on public.sd_player_team_memberships
for each row execute function public.sd_set_updated_at();
drop trigger if exists trg_sd_coach_team_assignments_updated_at on public.sd_coach_team_assignments;
create trigger trg_sd_coach_team_assignments_updated_at before update on public.sd_coach_team_assignments
for each row execute function public.sd_set_updated_at();

create or replace function public.sd_resolve_team_capabilities(
  target_organization uuid,
  target_team uuid,
  target_actor uuid default auth.uid()
)
returns text[]
language sql
stable
security definer
set search_path = ''
as $$
  with actor_membership as (
    select role
    from public.sd_org_memberships
    where org_id = target_organization and user_id = target_actor and status = 'active'
  ), responsibilities as (
    select distinct r.responsibility
    from public.sd_coach_team_assignments a
    join public.sd_coach_team_responsibilities r on r.assignment_id = a.id
    where a.organization_id = target_organization
      and (a.team_id = target_team or a.organization_wide_access)
      and a.coach_id = target_actor
      and a.active and a.ended_at is null
  ), resolved(capability) as (
    select unnest(array[
      'view_team','manage_roster','manage_schedule','manage_attendance',
      'manage_practice','manage_game','message_team','view_development',
      'edit_development','manage_staff','view_documents','manage_documents'
    ]) where exists (select 1 from actor_membership where role in ('owner','admin'))
    union
    select unnest(array[
      'view_team','manage_roster','manage_schedule','manage_attendance',
      'manage_practice','manage_game','message_team','view_development',
      'edit_development','manage_staff','view_documents','manage_documents'
    ]) where exists (select 1 from responsibilities where responsibility in ('head_coach','team_manager'))
    union
    select unnest(array[
      'view_team','manage_roster','manage_schedule','manage_attendance',
      'manage_practice','manage_game','message_team','view_development',
      'edit_development','view_documents'
    ]) where exists (select 1 from responsibilities where responsibility = 'assistant_coach')
    union
    select unnest(array['view_team','manage_practice','view_development','edit_development','view_documents'])
      where exists (select 1 from responsibilities where responsibility in (
        'hitting_coach','pitching_coach','catching_coach','strength_coach'
      ))
    union
    select unnest(array['view_team','view_development','edit_development','view_documents'])
      where exists (select 1 from responsibilities where responsibility = 'evaluator')
    union
    select unnest(array['view_team','view_development','view_documents'])
      where exists (select 1 from responsibilities where responsibility = 'read_only')
  )
  select coalesce(array_agg(capability order by capability), '{}'::text[]) from resolved;
$$;

create or replace function public.sd_can_access_team(target_organization uuid, target_team uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select public.sd_is_org_admin(target_organization)
    or exists (
      select 1 from public.sd_coach_team_assignments a
      where a.organization_id = target_organization and a.team_id = target_team
        and a.coach_id = auth.uid() and a.active and a.ended_at is null
    )
    or exists (
      select 1 from public.sd_player_team_memberships m
      where m.organization_id = target_organization and m.team_id = target_team
        and m.player_id = auth.uid() and m.active and m.ended_at is null
    );
$$;

create or replace function public.sd_assign_player_team(
  p_actor_id uuid,
  p_organization_id uuid,
  p_player_id uuid,
  p_team_id uuid,
  p_assignment_reason text,
  p_transfer_metadata jsonb,
  p_request_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_season_id uuid;
  v_membership public.sd_player_team_memberships%rowtype;
begin
  if not exists (
    select 1 from public.sd_org_memberships
    where org_id = p_organization_id and user_id = p_actor_id
      and role in ('owner','admin') and status = 'active'
  ) then
    raise exception 'org_admin_required' using errcode = '42501';
  end if;
  if not exists (
    select 1 from public.sd_org_memberships
    where org_id = p_organization_id and user_id = p_player_id
      and role = 'player' and status = 'active'
  ) then
    raise exception 'player_not_in_organization' using errcode = '23503';
  end if;

  select season_id into v_season_id
  from public.sd_teams
  where id = p_team_id and org_id = p_organization_id and is_active
  for update;
  if v_season_id is null then
    raise exception 'team_or_season_not_found' using errcode = '23503';
  end if;

  if p_request_id is not null and exists (
    select 1 from public.sd_team_operations_audit_logs
    where organization_id = p_organization_id and request_id = p_request_id
      and action = 'assign_player_team'
  ) then
    select * into v_membership from public.sd_player_team_memberships
    where organization_id = p_organization_id and player_id = p_player_id
      and active and ended_at is null limit 1;
    return pg_catalog.to_jsonb(v_membership);
  end if;

  update public.sd_player_team_memberships
  set active = false, ended_at = now(), updated_by = p_actor_id
  where organization_id = p_organization_id and player_id = p_player_id
    and active and ended_at is null;

  insert into public.sd_player_team_memberships (
    player_id, organization_id, season_id, team_id, assignment_reason,
    transfer_metadata, created_by, updated_by
  ) values (
    p_player_id, p_organization_id, v_season_id, p_team_id,
    nullif(btrim(p_assignment_reason), ''), coalesce(p_transfer_metadata, '{}'::jsonb),
    p_actor_id, p_actor_id
  ) returning * into v_membership;

  insert into public.sd_team_members (org_id, team_id, player_id, assigned_by, assigned_at)
  values (p_organization_id, p_team_id, p_player_id, p_actor_id, now())
  on conflict (org_id, player_id) do update
  set team_id = excluded.team_id, assigned_by = excluded.assigned_by,
      assigned_at = excluded.assigned_at;

  insert into public.sd_team_operations_audit_logs (
    organization_id, actor_id, action, target_type, target_id, request_id, details
  ) values (
    p_organization_id, p_actor_id, 'assign_player_team',
    'player_team_membership', v_membership.id, p_request_id,
    pg_catalog.jsonb_build_object('player_id', p_player_id, 'team_id', p_team_id)
  );
  return pg_catalog.to_jsonb(v_membership);
end;
$$;

create or replace function public.sd_assign_coach_team(
  p_actor_id uuid,
  p_organization_id uuid,
  p_coach_id uuid,
  p_team_id uuid,
  p_responsibilities text[],
  p_is_primary boolean,
  p_organization_wide_access boolean,
  p_request_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_season_id uuid;
  v_assignment public.sd_coach_team_assignments%rowtype;
begin
  if not exists (
    select 1 from public.sd_org_memberships
    where org_id = p_organization_id and user_id = p_actor_id
      and role in ('owner','admin') and status = 'active'
  ) then
    raise exception 'org_admin_required' using errcode = '42501';
  end if;
  if not exists (
    select 1 from public.sd_org_memberships
    where org_id = p_organization_id and user_id = p_coach_id
      and role in ('owner','admin','coach') and status = 'active'
  ) then
    raise exception 'coach_not_in_organization' using errcode = '23503';
  end if;
  if coalesce(pg_catalog.array_length(p_responsibilities, 1), 0) = 0
     or exists (
       select 1 from pg_catalog.unnest(p_responsibilities) responsibility
       where responsibility not in (
         'head_coach','assistant_coach','hitting_coach','pitching_coach',
         'catching_coach','strength_coach','team_manager','evaluator','read_only'
       )
     ) then
    raise exception 'invalid_responsibilities' using errcode = '23514';
  end if;

  select season_id into v_season_id
  from public.sd_teams
  where id = p_team_id and org_id = p_organization_id and is_active
  for update;
  if v_season_id is null then
    raise exception 'team_or_season_not_found' using errcode = '23503';
  end if;

  if p_request_id is not null and exists (
    select 1 from public.sd_team_operations_audit_logs
    where organization_id = p_organization_id and request_id = p_request_id
      and action = 'assign_coach_team'
  ) then
    select * into v_assignment from public.sd_coach_team_assignments
    where organization_id = p_organization_id and coach_id = p_coach_id
      and team_id = p_team_id and active and ended_at is null limit 1;
    return pg_catalog.to_jsonb(v_assignment) || pg_catalog.jsonb_build_object(
      'responsibilities', p_responsibilities,
      'capabilities', public.sd_resolve_team_capabilities(p_organization_id, p_team_id, p_coach_id)
    );
  end if;

  if coalesce(p_is_primary, false) then
    update public.sd_coach_team_assignments
    set is_primary = false, updated_by = p_actor_id
    where organization_id = p_organization_id and coach_id = p_coach_id
      and active and ended_at is null and is_primary;
  end if;

  select * into v_assignment from public.sd_coach_team_assignments
  where organization_id = p_organization_id and season_id = v_season_id
    and team_id = p_team_id and coach_id = p_coach_id
    and active and ended_at is null
  for update;

  if found then
    update public.sd_coach_team_assignments
    set is_primary = coalesce(p_is_primary, false),
        organization_wide_access = coalesce(p_organization_wide_access, false),
        updated_by = p_actor_id
    where id = v_assignment.id returning * into v_assignment;
  else
    insert into public.sd_coach_team_assignments (
      coach_id, organization_id, season_id, team_id, is_primary,
      organization_wide_access, created_by, updated_by
    ) values (
      p_coach_id, p_organization_id, v_season_id, p_team_id,
      coalesce(p_is_primary, false), coalesce(p_organization_wide_access, false),
      p_actor_id, p_actor_id
    ) returning * into v_assignment;
  end if;

  delete from public.sd_coach_team_responsibilities where assignment_id = v_assignment.id;
  insert into public.sd_coach_team_responsibilities (assignment_id, responsibility, created_by)
  select v_assignment.id, responsibility, p_actor_id
  from (select distinct pg_catalog.unnest(p_responsibilities) as responsibility) normalized;

  insert into public.sd_team_operations_audit_logs (
    organization_id, actor_id, action, target_type, target_id, request_id, details
  ) values (
    p_organization_id, p_actor_id, 'assign_coach_team',
    'coach_team_assignment', v_assignment.id, p_request_id,
    pg_catalog.jsonb_build_object(
      'coach_id', p_coach_id, 'team_id', p_team_id,
      'responsibilities', p_responsibilities,
      'is_primary', coalesce(p_is_primary, false),
      'organization_wide_access', coalesce(p_organization_wide_access, false)
    )
  );
  return pg_catalog.to_jsonb(v_assignment) || pg_catalog.jsonb_build_object(
    'responsibilities', p_responsibilities,
    'capabilities', public.sd_resolve_team_capabilities(p_organization_id, p_team_id, p_coach_id)
  );
end;
$$;

revoke all on function public.sd_resolve_team_capabilities(uuid, uuid, uuid) from public, anon;
grant execute on function public.sd_resolve_team_capabilities(uuid, uuid, uuid) to authenticated, service_role;
revoke all on function public.sd_can_access_team(uuid, uuid) from public, anon;
grant execute on function public.sd_can_access_team(uuid, uuid) to authenticated, service_role;
revoke all on function public.sd_assign_player_team(uuid, uuid, uuid, uuid, text, jsonb, uuid)
from public, anon, authenticated;
grant execute on function public.sd_assign_player_team(uuid, uuid, uuid, uuid, text, jsonb, uuid)
to service_role;
revoke all on function public.sd_assign_coach_team(uuid, uuid, uuid, uuid, text[], boolean, boolean, uuid)
from public, anon, authenticated;
grant execute on function public.sd_assign_coach_team(uuid, uuid, uuid, uuid, text[], boolean, boolean, uuid)
to service_role;

alter table public.sd_seasons enable row level security;
alter table public.sd_player_team_memberships enable row level security;
alter table public.sd_coach_team_assignments enable row level security;
alter table public.sd_coach_team_responsibilities enable row level security;
alter table public.sd_team_operations_audit_logs enable row level security;

create policy "sd_seasons_select_member" on public.sd_seasons for select to authenticated
using (public.sd_is_org_member(organization_id));
create policy "sd_player_team_memberships_select_authorized" on public.sd_player_team_memberships
for select to authenticated using (
  player_id = auth.uid() or public.sd_can_access_team(organization_id, team_id)
);
create policy "sd_coach_team_assignments_select_authorized" on public.sd_coach_team_assignments
for select to authenticated using (
  coach_id = auth.uid() or public.sd_is_org_admin(organization_id)
);
create policy "sd_coach_team_responsibilities_select_authorized"
on public.sd_coach_team_responsibilities for select to authenticated using (
  exists (
    select 1 from public.sd_coach_team_assignments a
    where a.id = assignment_id
      and (a.coach_id = auth.uid() or public.sd_is_org_admin(a.organization_id))
  )
);
create policy "sd_team_operations_audit_select_admin"
on public.sd_team_operations_audit_logs for select to authenticated
using (public.sd_is_org_admin(organization_id));

grant select on public.sd_seasons, public.sd_player_team_memberships,
  public.sd_coach_team_assignments, public.sd_coach_team_responsibilities,
  public.sd_team_operations_audit_logs to authenticated;
grant all on public.sd_seasons, public.sd_player_team_memberships,
  public.sd_coach_team_assignments, public.sd_coach_team_responsibilities,
  public.sd_team_operations_audit_logs to service_role;

-- Existing team reads now follow assignment authority. Organization-wide team
-- access is explicit for owners/admins or an active coach assignment carrying
-- organization_wide_access.
drop policy if exists "sd_teams_select_member" on public.sd_teams;
create policy "sd_teams_select_authorized" on public.sd_teams for select to authenticated
using (
  public.sd_is_org_admin(org_id)
  or public.sd_can_access_team(org_id, id)
  or exists (
    select 1 from public.sd_coach_team_assignments a
    where a.organization_id = sd_teams.org_id and a.coach_id = auth.uid()
      and a.organization_wide_access and a.active and a.ended_at is null
  )
);

-- Rollback is operationally reversible before clients adopt the new schema:
-- restore sd_teams_select_member, drop the added season_id column, then drop
-- the five Phase 12A tables and helper functions. No legacy row is deleted or
-- rewritten by this migration.
