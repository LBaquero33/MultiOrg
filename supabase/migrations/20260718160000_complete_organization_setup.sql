-- Phase 12Z: resumable organization setup orchestration.
--
-- Business data remains authoritative in the existing organization, season,
-- team, roster, registration, facility, communication, and scheduling tables.
-- These tables store only wizard state, retry receipts, setup provenance, and
-- audit history. No provider sends or destructive production reset is added.

alter table public.sd_orgs
  add column if not exists organization_type text,
  add column if not exists timezone text,
  add column if not exists default_location text,
  add column if not exists phone text;

create table if not exists public.sd_organization_setup_sessions (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  organization_id uuid not null unique references public.sd_orgs(id) on delete cascade,
  status text not null default 'not_started' check (status in ('not_started','in_progress','dismissed','ready','completed')),
  current_step text not null default 'basics' check (current_step in ('basics','season','teams','staff','players_families','registration_fees','facilities','communication','first_baseball_action','review_launch')),
  schema_version integer not null default 1,
  version integer not null default 1,
  started_by uuid references auth.users(id) on delete set null,
  assisted_by uuid references auth.users(id) on delete set null,
  started_at timestamptz,
  dismissed_at timestamptz,
  completed_at timestamptz,
  updated_by uuid references auth.users(id) on delete set null,
  updated_at timestamptz not null default pg_catalog.now(),
  created_at timestamptz not null default pg_catalog.now()
);

create table if not exists public.sd_organization_setup_steps (
  organization_id uuid not null references public.sd_orgs(id) on delete cascade,
  step text not null check (step in ('basics','season','teams','staff','players_families','registration_fees','facilities','communication','first_baseball_action','review_launch')),
  state text not null default 'not_started' check (state in ('not_started','in_progress','complete','skipped','needs_attention')),
  data_version integer not null default 1,
  last_request_id uuid,
  completed_by uuid references auth.users(id) on delete set null,
  completed_at timestamptz,
  updated_at timestamptz not null default pg_catalog.now(),
  primary key (organization_id,step)
);

create table if not exists public.sd_organization_setup_drafts (
  organization_id uuid not null references public.sd_orgs(id) on delete cascade,
  step text not null,
  draft_key text not null default 'default',
  payload jsonb not null default '{}'::jsonb check (pg_catalog.jsonb_typeof(payload)='object'),
  version integer not null default 1,
  updated_by uuid references auth.users(id) on delete set null,
  updated_at timestamptz not null default pg_catalog.now(),
  primary key (organization_id,step,draft_key)
);

create table if not exists public.sd_organization_setup_mutations (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  organization_id uuid not null references public.sd_orgs(id) on delete cascade,
  request_id uuid not null,
  action text not null,
  response jsonb not null default '{}'::jsonb,
  actor_id uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default pg_catalog.now(),
  unique (organization_id,request_id)
);

create table if not exists public.sd_organization_setup_entities (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  organization_id uuid not null references public.sd_orgs(id) on delete cascade,
  session_id uuid references public.sd_organization_setup_sessions(id) on delete set null,
  entity_type text not null,
  entity_id uuid not null,
  setup_test_run_id uuid,
  created_via_setup boolean not null default true,
  setup_test_created boolean not null default false,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default pg_catalog.now(),
  unique (organization_id,entity_type,entity_id)
);

create table if not exists public.sd_organization_setup_audit_logs (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  organization_id uuid not null references public.sd_orgs(id) on delete cascade,
  actor_id uuid references auth.users(id) on delete set null,
  assisted boolean not null default false,
  action text not null,
  step text,
  request_id uuid,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default pg_catalog.now()
);

create index if not exists idx_sd_setup_audit_org_created
  on public.sd_organization_setup_audit_logs(organization_id,created_at desc);
create index if not exists idx_sd_setup_entities_test_run
  on public.sd_organization_setup_entities(organization_id,setup_test_run_id)
  where setup_test_created;

alter table public.sd_organization_setup_sessions enable row level security;
alter table public.sd_organization_setup_steps enable row level security;
alter table public.sd_organization_setup_drafts enable row level security;
alter table public.sd_organization_setup_mutations enable row level security;
alter table public.sd_organization_setup_entities enable row level security;
alter table public.sd_organization_setup_audit_logs enable row level security;

revoke all on table public.sd_organization_setup_sessions,public.sd_organization_setup_steps,
  public.sd_organization_setup_drafts,public.sd_organization_setup_mutations,
  public.sd_organization_setup_entities,public.sd_organization_setup_audit_logs
  from public,anon,authenticated;
grant select,insert,update,delete on table public.sd_organization_setup_sessions,
  public.sd_organization_setup_steps,public.sd_organization_setup_drafts,
  public.sd_organization_setup_mutations,public.sd_organization_setup_entities,
  public.sd_organization_setup_audit_logs to service_role;

create policy sd_setup_sessions_admin_read on public.sd_organization_setup_sessions
  for select to authenticated using (public.sd_is_org_admin(organization_id));
create policy sd_setup_steps_admin_read on public.sd_organization_setup_steps
  for select to authenticated using (public.sd_is_org_admin(organization_id));
create policy sd_setup_drafts_admin_read on public.sd_organization_setup_drafts
  for select to authenticated using (public.sd_is_org_admin(organization_id));
create policy sd_setup_audit_admin_read on public.sd_organization_setup_audit_logs
  for select to authenticated using (public.sd_is_org_admin(organization_id));

create or replace function public.sd_resolve_setup_capabilities(
  target_organization uuid,
  target_actor uuid default auth.uid()
) returns text[] language sql stable security definer set search_path='' as $$
  with access as (
    select
      exists(select 1 from public.sd_org_memberships m where m.org_id=target_organization and m.user_id=target_actor and m.status='active' and m.role in ('owner','admin')) as org_admin,
      exists(select 1 from public.sd_platform_admins p where p.user_id=target_actor) as platform_admin
  )
  select case
    when org_admin then array['view_organization_setup','manage_organization_setup','complete_organization_setup']::text[]
    when platform_admin then array['view_organization_setup','manage_organization_setup','complete_organization_setup','assist_organization_setup']::text[]
    else '{}'::text[]
  end from access;
$$;
revoke all on function public.sd_resolve_setup_capabilities(uuid,uuid) from public,anon,authenticated;
grant execute on function public.sd_resolve_setup_capabilities(uuid,uuid) to service_role;

create or replace function public.sd_organization_setup_readiness(p_organization_id uuid)
returns jsonb language sql stable security definer set search_path='' as $$
  select pg_catalog.jsonb_build_object(
    'organization_active', coalesce((select o.status='active' from public.sd_orgs o where o.id=p_organization_id),false),
    'basics_complete', coalesce((select pg_catalog.length(pg_catalog.btrim(o.name))>0 and nullif(pg_catalog.btrim(o.timezone),'') is not null from public.sd_orgs o where o.id=p_organization_id),false),
    'active_or_default_season_count', (select pg_catalog.count(*) from public.sd_seasons s where s.organization_id=p_organization_id and (s.is_default or s.status='active')),
    'team_in_season_count', (select pg_catalog.count(*) from public.sd_teams t join public.sd_seasons s on s.id=t.season_id and s.organization_id=t.org_id where t.org_id=p_organization_id and t.is_active),
    'staff_assignment_count', (select pg_catalog.count(*) from public.sd_coach_team_assignments c where c.organization_id=p_organization_id and c.active and c.ended_at is null),
    'player_assignment_count', (select pg_catalog.count(*) from public.sd_player_team_memberships p where p.organization_id=p_organization_id and p.active and p.ended_at is null),
    'registration_offering_count', (select pg_catalog.count(*) from public.sd_registration_offerings r where r.organization_id=p_organization_id and r.state<>'archived'),
    'facility_count', (select pg_catalog.count(*) from public.sd_facilities f where f.org_id=p_organization_id and f.is_active),
    'communication_policy_configured', exists(select 1 from public.sd_communication_policies c where c.organization_id=p_organization_id),
    'first_event_count', (select pg_catalog.count(*) from public.sd_team_events e where e.organization_id=p_organization_id)
  );
$$;
revoke all on function public.sd_organization_setup_readiness(uuid) from public,anon,authenticated;
grant execute on function public.sd_organization_setup_readiness(uuid) to service_role;
