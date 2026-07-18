-- Phase 12D: complete team-scoped Practice Planner.
-- Additive only. Phase 12B owns canonical events and conflicts; Phase 12C owns
-- attendance, availability, general notes, and event-operation lifecycle.
-- Rollback: remove the grants/functions/constraints below, then drop only the
-- sd_practice_* tables after confirming no published or execution history is needed.

create table if not exists public.sd_practice_plans (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  organization_id uuid not null references public.sd_orgs(id) on delete cascade,
  season_id uuid not null references public.sd_seasons(id) on delete restrict,
  team_id uuid not null references public.sd_teams(id) on delete restrict,
  event_id uuid not null references public.sd_team_events(id) on delete restrict,
  event_operation_id uuid references public.sd_event_operations(id) on delete restrict,
  source_template_id uuid,
  source_plan_id uuid references public.sd_practice_plans(id) on delete set null,
  title text not null check (pg_catalog.char_length(pg_catalog.btrim(title)) between 1 and 160),
  objectives text[] not null default '{}'::text[],
  coach_notes text,
  status text not null default 'draft' check (status in ('draft','ready','published','active','completed','archived')),
  is_primary boolean not null default true,
  version integer not null default 1 check (version > 0),
  published_version integer,
  published_at timestamptz,
  published_by uuid references auth.users(id) on delete set null,
  current_snapshot_id uuid,
  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default pg_catalog.now(),
  updated_at timestamptz not null default pg_catalog.now(),
  archived_at timestamptz,
  check ((status = 'archived') = (archived_at is not null)),
  check (published_version is null or published_version <= version)
);

create unique index if not exists uq_sd_practice_plans_primary_event
  on public.sd_practice_plans(event_id) where is_primary and archived_at is null;

alter table public.sd_practice_plans
  add constraint sd_practice_plans_event_scope_fk
  foreign key (event_id, organization_id, season_id, team_id)
  references public.sd_team_events(id, organization_id, season_id, team_id)
  on delete restrict;

create table if not exists public.sd_practice_plan_blocks (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  practice_plan_id uuid not null references public.sd_practice_plans(id) on delete cascade,
  organization_id uuid not null references public.sd_orgs(id) on delete cascade,
  parent_block_id uuid references public.sd_practice_plan_blocks(id) on delete restrict,
  title text not null check (pg_catalog.char_length(pg_catalog.btrim(title)) between 1 and 160),
  block_type text not null check (block_type in (
    'arrival','meeting','warmup','movement_prep','throwing','arm_care','defense','infield','outfield',
    'catching','pitching','hitting','baserunning','strength','conditioning','competition','recovery','cooldown','custom'
  )),
  sequence_index integer not null check (sequence_index >= 0),
  start_offset_minutes integer not null default 0 check (start_offset_minutes >= 0),
  duration_minutes integer not null check (duration_minutes >= 0),
  parallel_group_key text,
  station_name text,
  facility_id uuid references public.sd_facilities(id) on delete restrict,
  location_area text,
  objectives text[] not null default '{}'::text[],
  instructions text,
  coaching_points text,
  equipment_notes text,
  source_entity_type text check (source_entity_type is null or source_entity_type in ('exercise','program_day','practice_block')),
  source_entity_id uuid,
  visibility text not null default 'staff_only' check (visibility in ('staff_only','team_visible','player_visible')),
  required boolean not null default true,
  version integer not null default 1 check (version > 0),
  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default pg_catalog.now(),
  updated_at timestamptz not null default pg_catalog.now(),
  archived_at timestamptz,
  check (duration_minutes > 0 or block_type = 'arrival'),
  check ((parent_block_id is null and parallel_group_key is null) or parent_block_id is not null)
);

create table if not exists public.sd_practice_plan_groups (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  practice_plan_id uuid not null references public.sd_practice_plans(id) on delete cascade,
  organization_id uuid not null references public.sd_orgs(id) on delete cascade,
  name text not null check (pg_catalog.char_length(pg_catalog.btrim(name)) between 1 and 100),
  description text,
  sort_order integer not null default 0,
  color_token text,
  active boolean not null default true,
  version integer not null default 1,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default pg_catalog.now(),
  updated_at timestamptz not null default pg_catalog.now(),
  unique (practice_plan_id, name)
);

create table if not exists public.sd_practice_plan_assignments (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  practice_plan_id uuid not null references public.sd_practice_plans(id) on delete cascade,
  organization_id uuid not null references public.sd_orgs(id) on delete cascade,
  assignment_type text not null check (assignment_type in ('player','coach','group')),
  user_id uuid references auth.users(id) on delete restrict,
  group_id uuid references public.sd_practice_plan_groups(id) on delete restrict,
  block_id uuid references public.sd_practice_plan_blocks(id) on delete restrict,
  assignment_role text,
  is_lead boolean not null default false,
  version integer not null default 1,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default pg_catalog.now(),
  updated_at timestamptz not null default pg_catalog.now(),
  check (
    (assignment_type in ('player','coach') and user_id is not null) or
    (assignment_type = 'group' and group_id is not null)
  ),
  unique nulls not distinct (practice_plan_id, assignment_type, user_id, group_id, block_id)
);

create table if not exists public.sd_practice_plan_equipment (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  practice_plan_id uuid not null references public.sd_practice_plans(id) on delete cascade,
  organization_id uuid not null references public.sd_orgs(id) on delete cascade,
  block_id uuid references public.sd_practice_plan_blocks(id) on delete restrict,
  name text not null check (pg_catalog.char_length(pg_catalog.btrim(name)) between 1 and 120),
  quantity integer not null default 1 check (quantity > 0),
  required boolean not null default true,
  prepared boolean not null default false,
  prepared_by uuid references auth.users(id) on delete set null,
  notes text,
  visibility text not null default 'staff_only' check (visibility in ('staff_only','team_visible','player_visible')),
  version integer not null default 1,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default pg_catalog.now(),
  updated_at timestamptz not null default pg_catalog.now()
);

create table if not exists public.sd_practice_plan_templates (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  organization_id uuid not null references public.sd_orgs(id) on delete cascade,
  season_id uuid references public.sd_seasons(id) on delete restrict,
  team_id uuid references public.sd_teams(id) on delete restrict,
  name text not null check (pg_catalog.char_length(pg_catalog.btrim(name)) between 1 and 160),
  description text,
  objectives text[] not null default '{}'::text[],
  snapshot jsonb not null default '{}'::jsonb check (pg_catalog.jsonb_typeof(snapshot) = 'object'),
  active boolean not null default true,
  version integer not null default 1,
  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default pg_catalog.now(),
  updated_at timestamptz not null default pg_catalog.now(),
  archived_at timestamptz,
  check ((active and archived_at is null) or (not active and archived_at is not null))
);

alter table public.sd_practice_plans
  add constraint sd_practice_plans_source_template_fk foreign key (source_template_id)
  references public.sd_practice_plan_templates(id) on delete set null;

create table if not exists public.sd_practice_plan_snapshots (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  practice_plan_id uuid not null references public.sd_practice_plans(id) on delete restrict,
  organization_id uuid not null references public.sd_orgs(id) on delete cascade,
  event_operation_id uuid references public.sd_event_operations(id) on delete restrict,
  snapshot_type text not null check (snapshot_type in ('version','published','started','completed')),
  plan_version integer not null check (plan_version > 0),
  snapshot jsonb not null check (pg_catalog.jsonb_typeof(snapshot) = 'object'),
  reason text,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default pg_catalog.now(),
  unique (practice_plan_id, snapshot_type, plan_version)
);

alter table public.sd_practice_plans
  add constraint sd_practice_plans_current_snapshot_fk foreign key (current_snapshot_id)
  references public.sd_practice_plan_snapshots(id) on delete set null;

create table if not exists public.sd_practice_block_executions (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  practice_plan_id uuid not null references public.sd_practice_plans(id) on delete restrict,
  started_snapshot_id uuid not null references public.sd_practice_plan_snapshots(id) on delete restrict,
  source_block_id uuid not null,
  parent_block_id uuid,
  title text not null,
  sequence_index integer not null,
  planned_duration_minutes integer not null,
  actual_duration_minutes integer,
  status text not null default 'pending' check (status in ('pending','active','completed','skipped','adjusted')),
  actual_started_at timestamptz,
  actual_completed_at timestamptz,
  adjustment_reason text,
  version integer not null default 1,
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default pg_catalog.now(),
  updated_at timestamptz not null default pg_catalog.now(),
  unique (started_snapshot_id, source_block_id)
);

create table if not exists public.sd_practice_plan_adjustments (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  practice_plan_id uuid not null references public.sd_practice_plans(id) on delete restrict,
  execution_id uuid references public.sd_practice_block_executions(id) on delete restrict,
  adjustment_type text not null check (adjustment_type in ('duration','order','substitution','emergency_block','reopen')),
  previous_value jsonb,
  new_value jsonb not null default '{}'::jsonb,
  reason text not null check (pg_catalog.char_length(pg_catalog.btrim(reason)) > 0),
  actor_id uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default pg_catalog.now()
);

create table if not exists public.sd_practice_plan_audit_logs (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  organization_id uuid not null references public.sd_orgs(id) on delete cascade,
  season_id uuid not null references public.sd_seasons(id) on delete restrict,
  team_id uuid not null references public.sd_teams(id) on delete restrict,
  event_id uuid not null references public.sd_team_events(id) on delete restrict,
  practice_plan_id uuid references public.sd_practice_plans(id) on delete restrict,
  actor_id uuid references auth.users(id) on delete set null,
  action text not null,
  request_id uuid not null,
  target_id uuid,
  previous_value jsonb,
  new_value jsonb,
  reason text,
  created_at timestamptz not null default pg_catalog.now(),
  unique (organization_id, request_id, action)
);

create table if not exists public.sd_practice_plan_mutations (
  organization_id uuid not null references public.sd_orgs(id) on delete cascade,
  request_id uuid not null,
  actor_id uuid not null references auth.users(id) on delete cascade,
  event_id uuid not null references public.sd_team_events(id) on delete cascade,
  action text not null,
  request_fingerprint text not null,
  status text not null default 'processing' check (status in ('processing','completed')),
  response jsonb,
  created_at timestamptz not null default pg_catalog.now(),
  completed_at timestamptz,
  primary key (organization_id, request_id)
);

create index if not exists idx_sd_practice_plans_scope on public.sd_practice_plans(organization_id, season_id, team_id, event_id);
create index if not exists idx_sd_practice_plans_status on public.sd_practice_plans(team_id, status, updated_at desc);
create index if not exists idx_sd_practice_blocks_order on public.sd_practice_plan_blocks(practice_plan_id, parent_block_id, sequence_index) where archived_at is null;
create index if not exists idx_sd_practice_groups_plan on public.sd_practice_plan_groups(practice_plan_id, sort_order);
create index if not exists idx_sd_practice_assignments_user on public.sd_practice_plan_assignments(practice_plan_id, assignment_type, user_id);
create index if not exists idx_sd_practice_assignments_block on public.sd_practice_plan_assignments(block_id, group_id);
create index if not exists idx_sd_practice_equipment_plan on public.sd_practice_plan_equipment(practice_plan_id, prepared);
create index if not exists idx_sd_practice_templates_scope on public.sd_practice_plan_templates(organization_id, season_id, team_id, active);
create index if not exists idx_sd_practice_snapshots_version on public.sd_practice_plan_snapshots(practice_plan_id, plan_version desc);
create unique index if not exists uq_sd_practice_started_snapshot_operation on public.sd_practice_plan_snapshots(event_operation_id) where snapshot_type = 'started';
create index if not exists idx_sd_practice_execution_current on public.sd_practice_block_executions(practice_plan_id, status, sequence_index);
create index if not exists idx_sd_practice_audit_scope on public.sd_practice_plan_audit_logs(organization_id, season_id, team_id, event_id, created_at desc);

create or replace function public.sd_practice_plan_snapshot(target_plan uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  select pg_catalog.jsonb_build_object(
    'plan', pg_catalog.to_jsonb(plan),
    'blocks', pg_catalog.coalesce((select pg_catalog.jsonb_agg(pg_catalog.to_jsonb(block) order by block.sequence_index, block.created_at)
      from public.sd_practice_plan_blocks block where block.practice_plan_id = plan.id and block.archived_at is null), '[]'::jsonb),
    'groups', pg_catalog.coalesce((select pg_catalog.jsonb_agg(pg_catalog.to_jsonb(grp) order by grp.sort_order, grp.created_at)
      from public.sd_practice_plan_groups grp where grp.practice_plan_id = plan.id and grp.active), '[]'::jsonb),
    'assignments', pg_catalog.coalesce((select pg_catalog.jsonb_agg(pg_catalog.to_jsonb(a) order by a.created_at)
      from public.sd_practice_plan_assignments a where a.practice_plan_id = plan.id), '[]'::jsonb),
    'equipment', pg_catalog.coalesce((select pg_catalog.jsonb_agg(pg_catalog.to_jsonb(e) order by e.created_at)
      from public.sd_practice_plan_equipment e where e.practice_plan_id = plan.id), '[]'::jsonb)
  ) from public.sd_practice_plans plan where plan.id = target_plan;
$$;

create or replace function public.sd_materialize_practice_snapshot(target_plan uuid,target_organization uuid,source_snapshot jsonb,target_actor uuid)
returns void language plpgsql security definer set search_path='' as $$
declare
  item jsonb;
  new_id uuid;
  group_map jsonb := '{}'::jsonb;
  block_map jsonb := '{}'::jsonb;
begin
  for item in select value from pg_catalog.jsonb_array_elements(pg_catalog.coalesce(source_snapshot->'groups','[]'::jsonb)) loop
    insert into public.sd_practice_plan_groups(practice_plan_id,organization_id,name,description,sort_order,color_token,created_by)
      values(target_plan,target_organization,item->>'name',item->>'description',pg_catalog.coalesce((item->>'sort_order')::integer,0),item->>'color_token',target_actor) returning id into new_id;
    group_map:=pg_catalog.jsonb_set(group_map,array[item->>'id'],pg_catalog.to_jsonb(new_id::text),true);
  end loop;
  for item in select value from pg_catalog.jsonb_array_elements(pg_catalog.coalesce(source_snapshot->'blocks','[]'::jsonb)) where value->>'parent_block_id' is null loop
    insert into public.sd_practice_plan_blocks(practice_plan_id,organization_id,title,block_type,sequence_index,start_offset_minutes,duration_minutes,location_area,objectives,instructions,coaching_points,equipment_notes,source_entity_type,source_entity_id,visibility,required,created_by,updated_by)
      values(target_plan,target_organization,item->>'title',item->>'block_type',(item->>'sequence_index')::integer,(item->>'start_offset_minutes')::integer,(item->>'duration_minutes')::integer,item->>'location_area',
        pg_catalog.coalesce(array(select pg_catalog.jsonb_array_elements_text(item->'objectives')),'{}'::text[]),item->>'instructions',item->>'coaching_points',item->>'equipment_notes',item->>'source_entity_type',nullif(item->>'source_entity_id','')::uuid,item->>'visibility',pg_catalog.coalesce((item->>'required')::boolean,true),target_actor,target_actor) returning id into new_id;
    block_map:=pg_catalog.jsonb_set(block_map,array[item->>'id'],pg_catalog.to_jsonb(new_id::text),true);
  end loop;
  for item in select value from pg_catalog.jsonb_array_elements(pg_catalog.coalesce(source_snapshot->'blocks','[]'::jsonb)) where value->>'parent_block_id' is not null loop
    insert into public.sd_practice_plan_blocks(practice_plan_id,organization_id,parent_block_id,title,block_type,sequence_index,start_offset_minutes,duration_minutes,parallel_group_key,station_name,location_area,objectives,instructions,coaching_points,equipment_notes,visibility,required,created_by,updated_by)
      values(target_plan,target_organization,(block_map->>(item->>'parent_block_id'))::uuid,item->>'title',item->>'block_type',(item->>'sequence_index')::integer,(item->>'start_offset_minutes')::integer,(item->>'duration_minutes')::integer,item->>'parallel_group_key',item->>'station_name',item->>'location_area',
        pg_catalog.coalesce(array(select pg_catalog.jsonb_array_elements_text(item->'objectives')),'{}'::text[]),item->>'instructions',item->>'coaching_points',item->>'equipment_notes',item->>'visibility',pg_catalog.coalesce((item->>'required')::boolean,true),target_actor,target_actor) returning id into new_id;
    block_map:=pg_catalog.jsonb_set(block_map,array[item->>'id'],pg_catalog.to_jsonb(new_id::text),true);
  end loop;
  for item in select value from pg_catalog.jsonb_array_elements(pg_catalog.coalesce(source_snapshot->'assignments','[]'::jsonb)) where value->>'assignment_type'='group' loop
    insert into public.sd_practice_plan_assignments(practice_plan_id,organization_id,assignment_type,group_id,block_id,assignment_role,created_by)
      values(target_plan,target_organization,'group',(group_map->>(item->>'group_id'))::uuid,(block_map->>(item->>'block_id'))::uuid,item->>'assignment_role',target_actor) on conflict do nothing;
  end loop;
  for item in select value from pg_catalog.jsonb_array_elements(pg_catalog.coalesce(source_snapshot->'equipment','[]'::jsonb)) loop
    insert into public.sd_practice_plan_equipment(practice_plan_id,organization_id,block_id,name,quantity,required,prepared,notes,visibility,created_by)
      values(target_plan,target_organization,case when item->>'block_id' is null then null else (block_map->>(item->>'block_id'))::uuid end,item->>'name',(item->>'quantity')::integer,pg_catalog.coalesce((item->>'required')::boolean,true),false,item->>'notes',item->>'visibility',target_actor);
  end loop;
end;
$$;

create or replace function public.sd_validate_practice_plan(target_plan uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  p public.sd_practice_plans%rowtype;
  e public.sd_team_events%rowtype;
  errors jsonb := '[]'::jsonb;
  warnings jsonb := '[]'::jsonb;
  notices jsonb := '[]'::jsonb;
  total_minutes integer := 0;
  event_minutes integer := 0;
begin
  select * into p from public.sd_practice_plans where id = target_plan;
  if not found then raise exception using errcode = 'P0001', message = 'plan_not_found'; end if;
  select * into e from public.sd_team_events where id = p.event_id;
  select pg_catalog.coalesce(pg_catalog.sum(duration_minutes),0)::integer into total_minutes
    from public.sd_practice_plan_blocks where practice_plan_id = p.id and parent_block_id is null and archived_at is null;
  event_minutes := pg_catalog.greatest(1, pg_catalog.extract(epoch from (e.end_at-e.start_at))/60)::integer;
  if pg_catalog.btrim(p.title) = '' then errors := errors || '[{"code":"missing_title"}]'::jsonb; end if;
  if not exists (select 1 from public.sd_practice_plan_blocks where practice_plan_id=p.id and archived_at is null)
    then errors := errors || '[{"code":"no_blocks"}]'::jsonb; end if;
  if exists (select 1 from public.sd_practice_plan_blocks where practice_plan_id=p.id and duration_minutes=0 and block_type<>'arrival' and archived_at is null)
    then errors := errors || '[{"code":"invalid_duration"}]'::jsonb; end if;
  if exists (
    select 1 from public.sd_practice_plan_blocks a join public.sd_practice_plan_blocks b
      on a.practice_plan_id=b.practice_plan_id and a.id<b.id and a.parent_block_id is null and b.parent_block_id is null
      and a.archived_at is null and b.archived_at is null
      and a.start_offset_minutes < b.start_offset_minutes+b.duration_minutes
      and b.start_offset_minutes < a.start_offset_minutes+a.duration_minutes
    where a.practice_plan_id=p.id
  ) then errors := errors || '[{"code":"accidental_overlap"}]'::jsonb; end if;
  if exists (select 1 from public.sd_practice_plan_blocks where practice_plan_id=p.id and parent_block_id is not null and parallel_group_key is null)
    then errors := errors || '[{"code":"invalid_parallel_station"}]'::jsonb; end if;
  if total_minutes > event_minutes then warnings := warnings || pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('code','plan_longer_than_event','planned_minutes',total_minutes,'event_minutes',event_minutes));
  elsif total_minutes*4 < event_minutes*3 then warnings := warnings || pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('code','plan_significantly_shorter','planned_minutes',total_minutes,'event_minutes',event_minutes)); end if;
  if exists (select 1 from public.sd_practice_plan_blocks where practice_plan_id=p.id and start_offset_minutes+duration_minutes>event_minutes and archived_at is null)
    then warnings := warnings || '[{"code":"block_outside_event_window"}]'::jsonb; end if;
  if exists (select 1 from public.sd_event_operation_participants participant
    join public.sd_event_operations operation on operation.id=participant.event_operation_id
    where operation.event_id=p.event_id and participant.participant_type='player' and participant.expected
      and not exists (select 1 from public.sd_practice_plan_assignments a where a.practice_plan_id=p.id and a.assignment_type='player' and a.user_id=participant.user_id))
    then warnings := warnings || '[{"code":"unassigned_expected_players"}]'::jsonb; end if;
  if exists (select 1 from public.sd_practice_plan_equipment where practice_plan_id=p.id and required and not prepared)
    then warnings := warnings || '[{"code":"required_equipment_not_prepared"}]'::jsonb; end if;
  if not exists (select 1 from public.sd_practice_plan_assignments where practice_plan_id=p.id and assignment_type='coach')
    then warnings := warnings || '[{"code":"missing_coach_assignment"}]'::jsonb; end if;
  if exists (select 1 from public.sd_practice_plan_groups grp where grp.practice_plan_id=p.id and grp.active and not exists(select 1 from public.sd_practice_plan_assignments a where a.practice_plan_id=p.id and a.group_id=grp.id))
    then warnings := warnings || '[{"code":"missing_group_assignment"}]'::jsonb; end if;
  if exists (select 1 from public.sd_practice_plan_assignments a where a.practice_plan_id=p.id and a.assignment_type='player' and not exists(select 1 from public.sd_player_team_memberships m where m.organization_id=p.organization_id and m.team_id=p.team_id and m.player_id=a.user_id and m.active and m.ended_at is null))
    then warnings := warnings || '[{"code":"player_no_longer_on_roster"}]'::jsonb; end if;
  if exists (select 1 from public.sd_practice_plan_assignments a where a.practice_plan_id=p.id and a.assignment_type='coach' and not exists(select 1 from public.sd_coach_team_assignments c where c.organization_id=p.organization_id and c.team_id=p.team_id and c.coach_id=a.user_id and c.active and c.ended_at is null))
    then warnings := warnings || '[{"code":"coach_no_longer_assigned"}]'::jsonb; end if;
  if exists (select 1 from public.sd_practice_plan_blocks b join public.sd_facility_bookings booking on booking.facility_id=b.facility_id and booking.status in ('pending','approved') and booking.start_at<e.end_at and booking.end_at>e.start_at where b.practice_plan_id=p.id and b.archived_at is null)
    then warnings := warnings || '[{"code":"facility_area_conflict"}]'::jsonb; end if;
  if p.published_version is not null and p.version>p.published_version
    then warnings := warnings || '[{"code":"draft_changes_after_publication"}]'::jsonb; end if;
  if p.status in ('draft','ready') and e.start_at < pg_catalog.now()+interval '24 hours'
    then warnings := warnings || '[{"code":"unpublished_plan_near_event_start"}]'::jsonb; end if;
  if p.status='active' and p.published_version is distinct from (select plan_version from public.sd_practice_plan_snapshots where practice_plan_id=p.id and snapshot_type='started' order by created_at desc limit 1)
    then notices := notices || '[{"code":"active_uses_preserved_published_version"}]'::jsonb; end if;
  return pg_catalog.jsonb_build_object('blocking_errors',errors,'readiness_warnings',warnings,'notices',notices,'total_duration_minutes',total_minutes,'event_duration_minutes',event_minutes,'valid',pg_catalog.jsonb_array_length(errors)=0);
end;
$$;

create or replace function public.sd_apply_practice_plan_mutation(
  p_organization_id uuid, p_event_id uuid, p_actor_id uuid, p_action text,
  p_request_id uuid, p_payload jsonb default '{}'::jsonb
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  evt public.sd_team_events%rowtype;
  plan public.sd_practice_plans%rowtype;
  receipt public.sd_practice_plan_mutations%rowtype;
  block public.sd_practice_plan_blocks%rowtype;
  execution public.sd_practice_block_executions%rowtype;
  snap public.sd_practice_plan_snapshots%rowtype;
  result jsonb := '{}'::jsonb;
  validation jsonb;
  fingerprint text;
  expected integer;
  reason text;
  target uuid;
  audit_action text := p_action;
  old jsonb;
  source_snapshot jsonb;
begin
  fingerprint := pg_catalog.encode(extensions.digest(pg_catalog.convert_to(
    p_actor_id::text||'|'||p_event_id::text||'|'||p_action||'|'||p_payload::text,'UTF8'),'sha256'),'hex');
  insert into public.sd_practice_plan_mutations(organization_id,request_id,actor_id,event_id,action,request_fingerprint)
    values(p_organization_id,p_request_id,p_actor_id,p_event_id,p_action,fingerprint)
    on conflict do nothing;
  if not found then
    select * into receipt from public.sd_practice_plan_mutations where organization_id=p_organization_id and request_id=p_request_id for update;
    if receipt.request_fingerprint<>fingerprint then raise exception using errcode='P0001',message='idempotency_mismatch'; end if;
    if receipt.status='completed' then return receipt.response||pg_catalog.jsonb_build_object('replayed',true); end if;
    raise exception using errcode='P0001',message='mutation_in_progress';
  end if;
  select * into evt from public.sd_team_events where id=p_event_id and organization_id=p_organization_id for update;
  if not found or evt.event_type<>'practice' then raise exception using errcode='P0001',message='practice_event_not_found'; end if;
  select * into plan from public.sd_practice_plans where event_id=p_event_id and is_primary and archived_at is null for update;
  if not found and p_action='restore_plan' then
    select * into plan from public.sd_practice_plans where event_id=p_event_id and archived_at is not null order by archived_at desc limit 1 for update;
  end if;

  if p_action in ('initialize_blank_plan','initialize_from_template','duplicate_prior_plan') then
    if found then raise exception using errcode='P0001',message='primary_plan_exists'; end if;
    insert into public.sd_practice_plans(organization_id,season_id,team_id,event_id,source_template_id,source_plan_id,title,objectives,created_by,updated_by)
      values(p_organization_id,evt.season_id,evt.team_id,evt.id,nullif(p_payload->>'template_id','')::uuid,nullif(p_payload->>'source_plan_id','')::uuid,
        pg_catalog.coalesce(nullif(pg_catalog.btrim(p_payload->>'title'),''),evt.title),
        pg_catalog.coalesce(array(select pg_catalog.jsonb_array_elements_text(p_payload->'objectives')),'{}'::text[]),p_actor_id,p_actor_id)
      returning * into plan;
    if p_action='initialize_from_template' then
      select template.snapshot into source_snapshot from public.sd_practice_plan_templates template
        where template.id=(p_payload->>'template_id')::uuid and template.organization_id=p_organization_id and template.active
          and (template.team_id is null or template.team_id=evt.team_id) and (template.season_id is null or template.season_id=evt.season_id);
      if source_snapshot is null then raise exception using errcode='P0001',message='template_not_found'; end if;
      perform public.sd_materialize_practice_snapshot(plan.id,p_organization_id,source_snapshot,p_actor_id);
    elsif p_action='duplicate_prior_plan' then
      select public.sd_practice_plan_snapshot(source.id) into source_snapshot from public.sd_practice_plans source
        where source.id=(p_payload->>'source_plan_id')::uuid and source.organization_id=p_organization_id and source.team_id=evt.team_id;
      if source_snapshot is null then raise exception using errcode='P0001',message='source_plan_not_found'; end if;
      perform public.sd_materialize_practice_snapshot(plan.id,p_organization_id,source_snapshot,p_actor_id);
    end if;
    audit_action := case p_action when 'initialize_from_template' then 'created_from_template' when 'duplicate_prior_plan' then 'duplicated' else 'created' end;
    result := pg_catalog.jsonb_build_object('plan',pg_catalog.to_jsonb(plan));
  elsif not found and p_action not in ('create_template','duplicate_template','archive_template','restore_template','update_template') then
    raise exception using errcode='P0001',message='plan_not_found';
  elsif p_action='update_plan' then
    expected := (p_payload->>'expected_version')::integer;
    if expected is null or plan.version<>expected then raise exception using errcode='P0001',message='stale_version'; end if;
    old:=pg_catalog.to_jsonb(plan);
    update public.sd_practice_plans set title=pg_catalog.coalesce(nullif(pg_catalog.btrim(p_payload->>'title'),''),title),
      objectives=case when p_payload?'objectives' then array(select pg_catalog.jsonb_array_elements_text(p_payload->'objectives')) else objectives end,
      coach_notes=case when p_payload?'coach_notes' then nullif(p_payload->>'coach_notes','') else coach_notes end,
      status=case when status='published' then 'draft' else pg_catalog.coalesce(nullif(p_payload->>'status',''),status) end,
      version=version+1,updated_by=p_actor_id,updated_at=pg_catalog.now() where id=plan.id returning * into plan;
    result:=pg_catalog.jsonb_build_object('plan',pg_catalog.to_jsonb(plan));
  elsif p_action in ('add_block','add_station','add_active_block') then
    reason:=nullif(pg_catalog.btrim(p_payload->>'reason'),'');
    if p_action='add_active_block' and (plan.status<>'active' or reason is null) then raise exception using errcode='P0001',message='adjustment_reason_required'; end if;
    insert into public.sd_practice_plan_blocks(practice_plan_id,organization_id,parent_block_id,title,block_type,sequence_index,start_offset_minutes,duration_minutes,parallel_group_key,station_name,facility_id,location_area,objectives,instructions,coaching_points,equipment_notes,source_entity_type,source_entity_id,visibility,required,created_by,updated_by)
      values(plan.id,p_organization_id,nullif(p_payload->>'parent_block_id','')::uuid,pg_catalog.btrim(p_payload->>'title'),p_payload->>'block_type',(p_payload->>'sequence_index')::integer,
      pg_catalog.coalesce((p_payload->>'start_offset_minutes')::integer,0),(p_payload->>'duration_minutes')::integer,nullif(p_payload->>'parallel_group_key',''),nullif(p_payload->>'station_name',''),nullif(p_payload->>'facility_id','')::uuid,nullif(p_payload->>'location_area',''),
      pg_catalog.coalesce(array(select pg_catalog.jsonb_array_elements_text(p_payload->'objectives')),'{}'::text[]),nullif(p_payload->>'instructions',''),nullif(p_payload->>'coaching_points',''),nullif(p_payload->>'equipment_notes',''),nullif(p_payload->>'source_entity_type',''),nullif(p_payload->>'source_entity_id','')::uuid,pg_catalog.coalesce(nullif(p_payload->>'visibility',''),'staff_only'),pg_catalog.coalesce((p_payload->>'required')::boolean,true),p_actor_id,p_actor_id)
      returning * into block;
    update public.sd_practice_plans set version=version+1,status=case when status='published' then 'draft' else status end,updated_by=p_actor_id,updated_at=pg_catalog.now() where id=plan.id returning * into plan;
    if p_action='add_active_block' then
      select * into snap from public.sd_practice_plan_snapshots where practice_plan_id=plan.id and snapshot_type='started' order by created_at desc limit 1;
      insert into public.sd_practice_block_executions(practice_plan_id,started_snapshot_id,source_block_id,parent_block_id,title,sequence_index,planned_duration_minutes,updated_by)
        values(plan.id,snap.id,block.id,block.parent_block_id,block.title,block.sequence_index,block.duration_minutes,p_actor_id);
      insert into public.sd_practice_plan_adjustments(practice_plan_id,adjustment_type,new_value,reason,actor_id) values(plan.id,'emergency_block',pg_catalog.to_jsonb(block),reason,p_actor_id);
    end if;
    result:=pg_catalog.jsonb_build_object('plan',pg_catalog.to_jsonb(plan),'block',pg_catalog.to_jsonb(block));
  elsif p_action in ('update_block','update_station') then
    target:=(p_payload->>'block_id')::uuid; expected:=(p_payload->>'expected_version')::integer;
    select * into block from public.sd_practice_plan_blocks where id=target and practice_plan_id=plan.id for update;
    if not found then raise exception using errcode='P0001',message='block_not_found'; end if;
    if block.version<>expected then raise exception using errcode='P0001',message='stale_version'; end if;
    old:=pg_catalog.to_jsonb(block);
    update public.sd_practice_plan_blocks set title=pg_catalog.coalesce(nullif(pg_catalog.btrim(p_payload->>'title'),''),title),block_type=pg_catalog.coalesce(nullif(p_payload->>'block_type',''),block_type),
      start_offset_minutes=pg_catalog.coalesce((p_payload->>'start_offset_minutes')::integer,start_offset_minutes),duration_minutes=pg_catalog.coalesce((p_payload->>'duration_minutes')::integer,duration_minutes),
      location_area=case when p_payload?'location_area' then nullif(p_payload->>'location_area','') else location_area end,facility_id=case when p_payload?'facility_id' then nullif(p_payload->>'facility_id','')::uuid else facility_id end,
      instructions=case when p_payload?'instructions' then nullif(p_payload->>'instructions','') else instructions end,coaching_points=case when p_payload?'coaching_points' then nullif(p_payload->>'coaching_points','') else coaching_points end,
      visibility=pg_catalog.coalesce(nullif(p_payload->>'visibility',''),visibility),version=version+1,updated_by=p_actor_id,updated_at=pg_catalog.now() where id=block.id returning * into block;
    update public.sd_practice_plans set version=version+1,status=case when status='published' then 'draft' else status end,updated_by=p_actor_id,updated_at=pg_catalog.now() where id=plan.id returning * into plan;
    result:=pg_catalog.jsonb_build_object('plan',pg_catalog.to_jsonb(plan),'block',pg_catalog.to_jsonb(block));
  elsif p_action in ('remove_block','remove_station') then
    target:=(p_payload->>'block_id')::uuid; expected:=(p_payload->>'expected_version')::integer;
    update public.sd_practice_plan_blocks set archived_at=pg_catalog.now(),version=version+1,updated_by=p_actor_id,updated_at=pg_catalog.now()
      where id=target and practice_plan_id=plan.id and version=expected and archived_at is null returning * into block;
    if not found then raise exception using errcode='P0001',message='stale_or_missing_block'; end if;
    update public.sd_practice_plan_blocks set archived_at=pg_catalog.now(),version=version+1,updated_by=p_actor_id where parent_block_id=target and archived_at is null;
    update public.sd_practice_plans set version=version+1,status=case when status='published' then 'draft' else status end,updated_by=p_actor_id,updated_at=pg_catalog.now() where id=plan.id returning * into plan;
    result:=pg_catalog.jsonb_build_object('plan',pg_catalog.to_jsonb(plan));
  elsif p_action='reorder_blocks' then
    expected:=(p_payload->>'expected_version')::integer;
    if plan.version<>expected then raise exception using errcode='P0001',message='stale_version'; end if;
    if (select pg_catalog.count(*) from pg_catalog.jsonb_to_recordset(p_payload->'blocks') x(id uuid,sequence_index integer)) <>
       (select pg_catalog.count(*) from public.sd_practice_plan_blocks where practice_plan_id=plan.id and parent_block_id is null and archived_at is null)
      then raise exception using errcode='P0001',message='incomplete_block_order'; end if;
    update public.sd_practice_plan_blocks b set sequence_index=x.sequence_index,version=b.version+1,updated_by=p_actor_id,updated_at=pg_catalog.now()
      from pg_catalog.jsonb_to_recordset(p_payload->'blocks') x(id uuid,sequence_index integer) where b.id=x.id and b.practice_plan_id=plan.id;
    update public.sd_practice_plans set version=version+1,status=case when status='published' then 'draft' else status end,updated_by=p_actor_id,updated_at=pg_catalog.now() where id=plan.id returning * into plan;
    result:=pg_catalog.jsonb_build_object('plan',pg_catalog.to_jsonb(plan));
  elsif p_action in ('create_group','update_group','archive_group') then
    if p_action='create_group' then
      insert into public.sd_practice_plan_groups(practice_plan_id,organization_id,name,description,sort_order,created_by)
        values(plan.id,p_organization_id,pg_catalog.btrim(p_payload->>'name'),nullif(p_payload->>'description',''),pg_catalog.coalesce((p_payload->>'sort_order')::integer,0),p_actor_id) returning id into target;
    else
      target:=(p_payload->>'group_id')::uuid; expected:=(p_payload->>'expected_version')::integer;
      update public.sd_practice_plan_groups set name=case when p_action='update_group' then pg_catalog.coalesce(nullif(pg_catalog.btrim(p_payload->>'name'),''),name) else name end,
        description=case when p_action='update_group' and p_payload?'description' then nullif(p_payload->>'description','') else description end,
        active=case when p_action='archive_group' then false else active end,version=version+1,updated_at=pg_catalog.now()
        where id=target and practice_plan_id=plan.id and version=expected;
      if not found then raise exception using errcode='P0001',message='stale_or_missing_group'; end if;
    end if;
    update public.sd_practice_plans set version=version+1,updated_by=p_actor_id,updated_at=pg_catalog.now() where id=plan.id returning * into plan;
    result:=pg_catalog.jsonb_build_object('plan',pg_catalog.to_jsonb(plan),'group_id',target);
  elsif p_action in ('assign_player','assign_coach','assign_group_to_block','assign_player_to_station','assign_coach_to_station') then
    if p_action like 'assign_player%' and not exists (select 1 from public.sd_event_operation_participants participant join public.sd_event_operations operation on operation.id=participant.event_operation_id where operation.event_id=plan.event_id and participant.user_id=(p_payload->>'user_id')::uuid and participant.participant_type='player')
      and not exists (select 1 from public.sd_player_team_memberships where organization_id=p_organization_id and team_id=plan.team_id and player_id=(p_payload->>'user_id')::uuid and active and ended_at is null)
      then raise exception using errcode='P0001',message='cross_team_player'; end if;
    if p_action like 'assign_coach%' and not exists (select 1 from public.sd_coach_team_assignments where organization_id=p_organization_id and (team_id=plan.team_id or organization_wide_access) and coach_id=(p_payload->>'user_id')::uuid and active and ended_at is null)
      then raise exception using errcode='P0001',message='cross_team_coach'; end if;
    insert into public.sd_practice_plan_assignments(practice_plan_id,organization_id,assignment_type,user_id,group_id,block_id,assignment_role,is_lead,created_by)
      values(plan.id,p_organization_id,case when p_action like 'assign_player%' then 'player' when p_action like 'assign_coach%' then 'coach' else 'group' end,
        nullif(p_payload->>'user_id','')::uuid,nullif(p_payload->>'group_id','')::uuid,nullif(p_payload->>'block_id','')::uuid,nullif(p_payload->>'assignment_role',''),pg_catalog.coalesce((p_payload->>'is_lead')::boolean,false),p_actor_id)
      on conflict (practice_plan_id,assignment_type,user_id,group_id,block_id) do nothing returning id into target;
    update public.sd_practice_plans set version=version+1,updated_by=p_actor_id,updated_at=pg_catalog.now() where id=plan.id returning * into plan;
    result:=pg_catalog.jsonb_build_object('plan',pg_catalog.to_jsonb(plan),'assignment_id',target);
  elsif p_action in ('unassign_player','unassign_coach') then
    delete from public.sd_practice_plan_assignments where practice_plan_id=plan.id and id=(p_payload->>'assignment_id')::uuid;
    update public.sd_practice_plans set version=version+1,updated_by=p_actor_id,updated_at=pg_catalog.now() where id=plan.id returning * into plan;
    result:=pg_catalog.jsonb_build_object('plan',pg_catalog.to_jsonb(plan));
  elsif p_action='reconcile_roster' then
    reason:=nullif(pg_catalog.btrim(p_payload->>'reason'),'');
    if reason is null then raise exception using errcode='P0001',message='reconciliation_reason_required'; end if;
    insert into public.sd_practice_plan_assignments(practice_plan_id,organization_id,assignment_type,user_id,created_by)
      select plan.id,p_organization_id,'player',participant.user_id,p_actor_id from public.sd_event_operation_participants participant
      join public.sd_event_operations operation on operation.id=participant.event_operation_id
      where operation.event_id=plan.event_id and participant.participant_type='player' and participant.expected
      on conflict (practice_plan_id,assignment_type,user_id,group_id,block_id) do nothing;
    update public.sd_practice_plans set version=version+1,updated_by=p_actor_id,updated_at=pg_catalog.now() where id=plan.id returning * into plan;
    result:=pg_catalog.jsonb_build_object('plan',pg_catalog.to_jsonb(plan),'reconciled',true);
  elsif p_action in ('add_equipment_requirement','update_equipment_requirement','remove_equipment_requirement') then
    if p_action='add_equipment_requirement' then
      insert into public.sd_practice_plan_equipment(practice_plan_id,organization_id,block_id,name,quantity,required,prepared,prepared_by,notes,visibility,created_by)
        values(plan.id,p_organization_id,nullif(p_payload->>'block_id','')::uuid,pg_catalog.btrim(p_payload->>'name'),pg_catalog.coalesce((p_payload->>'quantity')::integer,1),pg_catalog.coalesce((p_payload->>'required')::boolean,true),pg_catalog.coalesce((p_payload->>'prepared')::boolean,false),case when (p_payload->>'prepared')::boolean then p_actor_id else null end,nullif(p_payload->>'notes',''),pg_catalog.coalesce(nullif(p_payload->>'visibility',''),'staff_only'),p_actor_id) returning id into target;
    elsif p_action='update_equipment_requirement' then
      target:=(p_payload->>'equipment_id')::uuid; expected:=(p_payload->>'expected_version')::integer;
      update public.sd_practice_plan_equipment set name=pg_catalog.coalesce(nullif(pg_catalog.btrim(p_payload->>'name'),''),name),quantity=pg_catalog.coalesce((p_payload->>'quantity')::integer,quantity),prepared=pg_catalog.coalesce((p_payload->>'prepared')::boolean,prepared),prepared_by=case when (p_payload->>'prepared')::boolean then p_actor_id else prepared_by end,notes=case when p_payload?'notes' then nullif(p_payload->>'notes','') else notes end,version=version+1,updated_at=pg_catalog.now() where id=target and practice_plan_id=plan.id and version=expected;
      if not found then raise exception using errcode='P0001',message='stale_or_missing_equipment'; end if;
    else delete from public.sd_practice_plan_equipment where id=(p_payload->>'equipment_id')::uuid and practice_plan_id=plan.id;
    end if;
    update public.sd_practice_plans set version=version+1,updated_by=p_actor_id,updated_at=pg_catalog.now() where id=plan.id returning * into plan;
    result:=pg_catalog.jsonb_build_object('plan',pg_catalog.to_jsonb(plan),'equipment_id',target);
  elsif p_action in ('publish_plan','republish_plan') then
    validation:=public.sd_validate_practice_plan(plan.id);
    if pg_catalog.jsonb_array_length(validation->'blocking_errors')>0 then raise exception using errcode='P0001',message='plan_validation_failed'; end if;
    insert into public.sd_practice_plan_snapshots(practice_plan_id,organization_id,snapshot_type,plan_version,snapshot,created_by)
      values(plan.id,p_organization_id,'published',plan.version,public.sd_practice_plan_snapshot(plan.id),p_actor_id)
      on conflict (practice_plan_id,snapshot_type,plan_version) do update set snapshot=excluded.snapshot returning * into snap;
    update public.sd_practice_plans set status='published',published_version=version,published_at=pg_catalog.now(),published_by=p_actor_id,current_snapshot_id=snap.id,updated_by=p_actor_id,updated_at=pg_catalog.now() where id=plan.id returning * into plan;
    insert into public.sd_team_event_notification_intents(organization_id,team_id,event_id,event_operation_id,intent_type,deduplication_key,payload,created_by)
      values(p_organization_id,plan.team_id,plan.event_id,plan.event_operation_id,'practice_plan_published',p_request_id::text||':'||plan.id::text||':published',pg_catalog.jsonb_build_object('plan_id',plan.id),p_actor_id);
    result:=pg_catalog.jsonb_build_object('plan',pg_catalog.to_jsonb(plan),'snapshot',pg_catalog.to_jsonb(snap),'validation',validation);
  elsif p_action='capture_started_snapshot' then
    if plan.status<>'published' then raise exception using errcode='P0001',message='published_plan_required'; end if;
    select id into target from public.sd_event_operations where event_id=plan.event_id and status in ('ready','in_progress','paused');
    if target is null then raise exception using errcode='P0001',message='event_operation_not_ready'; end if;
    insert into public.sd_practice_plan_snapshots(practice_plan_id,organization_id,event_operation_id,snapshot_type,plan_version,snapshot,created_by)
      select plan.id,p_organization_id,target,'started',published.plan_version,published.snapshot,p_actor_id from public.sd_practice_plan_snapshots published
      where published.practice_plan_id=plan.id and published.snapshot_type='published' and published.plan_version=plan.published_version returning * into snap;
    insert into public.sd_practice_block_executions(practice_plan_id,started_snapshot_id,source_block_id,parent_block_id,title,sequence_index,planned_duration_minutes,updated_by)
      select plan.id,snap.id,(b->>'id')::uuid,nullif(b->>'parent_block_id','')::uuid,b->>'title',(b->>'sequence_index')::integer,(b->>'duration_minutes')::integer,p_actor_id
      from pg_catalog.jsonb_array_elements(snap.snapshot->'blocks') b;
    update public.sd_practice_plans set status='active',event_operation_id=target,current_snapshot_id=snap.id,updated_by=p_actor_id,updated_at=pg_catalog.now() where id=plan.id returning * into plan;
    result:=pg_catalog.jsonb_build_object('plan',pg_catalog.to_jsonb(plan),'started_snapshot',pg_catalog.to_jsonb(snap));
  elsif p_action in ('start_block','complete_block','skip_block','reopen_block','adjust_active_block') then
    target:=(p_payload->>'execution_id')::uuid; expected:=(p_payload->>'expected_version')::integer; reason:=nullif(pg_catalog.btrim(p_payload->>'reason'),'');
    select * into execution from public.sd_practice_block_executions where id=target and practice_plan_id=plan.id for update;
    if not found then raise exception using errcode='P0001',message='execution_not_found'; end if;
    if execution.version<>expected then raise exception using errcode='P0001',message='stale_version'; end if;
    if p_action in ('skip_block','reopen_block','adjust_active_block') and reason is null then raise exception using errcode='P0001',message='adjustment_reason_required'; end if;
    if p_action='adjust_active_block' and not (p_payload?'duration_minutes' or p_payload?'sequence_index' or nullif(pg_catalog.btrim(p_payload->>'substitute_title'),'') is not null)
      then raise exception using errcode='P0001',message='invalid_active_adjustment'; end if;
    if p_action='adjust_active_block' and p_payload?'duration_minutes' and (p_payload->>'duration_minutes')::integer<=0
      then raise exception using errcode='P0001',message='invalid_duration'; end if;
    if p_action='adjust_active_block' and p_payload?'sequence_index' and (p_payload->>'sequence_index')::integer<0
      then raise exception using errcode='P0001',message='invalid_active_adjustment'; end if;
    if p_action='start_block' and execution.parent_block_id is null and exists(select 1 from public.sd_practice_block_executions where practice_plan_id=plan.id and status='active' and parent_block_id is null and id<>execution.id)
      then raise exception using errcode='P0001',message='sequential_block_already_active'; end if;
    old:=pg_catalog.to_jsonb(execution);
    update public.sd_practice_block_executions set
      status=case p_action when 'start_block' then 'active' when 'complete_block' then 'completed' when 'skip_block' then 'skipped' when 'reopen_block' then 'pending' else 'adjusted' end,
      actual_started_at=case when p_action='start_block' then pg_catalog.coalesce(actual_started_at,pg_catalog.now()) else actual_started_at end,
      actual_completed_at=case when p_action in ('complete_block','skip_block') then pg_catalog.now() when p_action='reopen_block' then null else actual_completed_at end,
      actual_duration_minutes=case when p_action='adjust_active_block' then pg_catalog.coalesce((p_payload->>'duration_minutes')::integer,actual_duration_minutes) else actual_duration_minutes end,
      sequence_index=case when p_action='adjust_active_block' then pg_catalog.coalesce((p_payload->>'sequence_index')::integer,sequence_index) else sequence_index end,
      title=case when p_action='adjust_active_block' then pg_catalog.coalesce(nullif(pg_catalog.btrim(p_payload->>'substitute_title'),''),title) else title end,
      adjustment_reason=case when reason is not null then reason else adjustment_reason end,version=version+1,updated_by=p_actor_id,updated_at=pg_catalog.now()
      where id=execution.id returning * into execution;
    if p_action in ('reopen_block','adjust_active_block') then insert into public.sd_practice_plan_adjustments(practice_plan_id,execution_id,adjustment_type,previous_value,new_value,reason,actor_id)
      values(plan.id,execution.id,case when p_action='reopen_block' then 'reopen' when nullif(pg_catalog.btrim(p_payload->>'substitute_title'),'') is not null then 'substitution' when p_payload?'sequence_index' then 'order' else 'duration' end,old,pg_catalog.to_jsonb(execution),reason,p_actor_id); end if;
    result:=pg_catalog.jsonb_build_object('plan',pg_catalog.to_jsonb(plan),'execution',pg_catalog.to_jsonb(execution));
  elsif p_action in ('capture_completion_snapshot','complete_practice_plan') then
    if exists(select 1 from public.sd_practice_block_executions where practice_plan_id=plan.id and status='active') then raise exception using errcode='P0001',message='active_blocks_remaining'; end if;
    if not exists(select 1 from public.sd_event_operations where id=plan.event_operation_id and attendance_finalized_at is not null) then raise exception using errcode='P0001',message='attendance_review_required'; end if;
    insert into public.sd_practice_plan_snapshots(practice_plan_id,organization_id,event_operation_id,snapshot_type,plan_version,snapshot,reason,created_by)
      values(plan.id,p_organization_id,plan.event_operation_id,'completed',plan.version,public.sd_practice_plan_snapshot(plan.id)||pg_catalog.jsonb_build_object('executions',(select pg_catalog.jsonb_agg(pg_catalog.to_jsonb(x) order by sequence_index) from public.sd_practice_block_executions x where x.practice_plan_id=plan.id)),nullif(p_payload->>'recap',''),p_actor_id)
      on conflict (practice_plan_id,snapshot_type,plan_version) do update set snapshot=excluded.snapshot returning * into snap;
    update public.sd_practice_plans set status='completed',current_snapshot_id=snap.id,updated_by=p_actor_id,updated_at=pg_catalog.now() where id=plan.id returning * into plan;
    insert into public.sd_team_event_notification_intents(organization_id,team_id,event_id,event_operation_id,intent_type,deduplication_key,payload,created_by)
      values(p_organization_id,plan.team_id,plan.event_id,plan.event_operation_id,'practice_completed',p_request_id::text||':'||plan.id::text||':completed','{}'::jsonb,p_actor_id);
    result:=pg_catalog.jsonb_build_object('plan',pg_catalog.to_jsonb(plan),'completion_snapshot',pg_catalog.to_jsonb(snap));
  elsif p_action='reopen_completed_practice' then
    reason:=nullif(pg_catalog.btrim(p_payload->>'reason'),''); if reason is null then raise exception using errcode='P0001',message='reopen_reason_required'; end if;
    if plan.status<>'completed' then raise exception using errcode='P0001',message='completed_plan_required'; end if;
    if exists(select 1 from public.sd_event_operations where id=plan.event_operation_id and status='completed') then raise exception using errcode='P0001',message='event_operation_reopen_required'; end if;
    update public.sd_practice_plans set status='active',version=version+1,updated_by=p_actor_id,updated_at=pg_catalog.now() where id=plan.id returning * into plan;
    insert into public.sd_practice_plan_adjustments(practice_plan_id,adjustment_type,new_value,reason,actor_id) values(plan.id,'reopen',pg_catalog.to_jsonb(plan),reason,p_actor_id);
    result:=pg_catalog.jsonb_build_object('plan',pg_catalog.to_jsonb(plan));
  elsif p_action in ('archive_plan','restore_plan','delete_draft_plan') then
    if p_action='delete_draft_plan' then
      if plan.status<>'draft' or plan.published_version is not null then raise exception using errcode='P0001',message='published_plan_delete_forbidden'; end if;
      update public.sd_practice_plans set status='archived',archived_at=pg_catalog.now(),is_primary=false,version=version+1,updated_by=p_actor_id,updated_at=pg_catalog.now() where id=plan.id returning * into plan;
      audit_action:='draft_deleted'; result:=pg_catalog.jsonb_build_object('deleted',true,'plan_id',plan.id);
    else
      if p_action='archive_plan' and plan.status in ('active','completed') then raise exception using errcode='P0001',message='historical_plan_archive_forbidden'; end if;
      update public.sd_practice_plans set status=case when p_action='archive_plan' then 'archived' else 'draft' end,archived_at=case when p_action='archive_plan' then pg_catalog.now() else null end,is_primary=case when p_action='archive_plan' then false else true end,version=version+1,updated_by=p_actor_id,updated_at=pg_catalog.now() where id=plan.id returning * into plan;
      result:=pg_catalog.jsonb_build_object('plan',pg_catalog.to_jsonb(plan));
    end if;
  elsif p_action in ('create_template','save_plan_as_template','update_template','duplicate_template','archive_template','restore_template') then
    if p_action in ('create_template','save_plan_as_template','duplicate_template') then
      insert into public.sd_practice_plan_templates(organization_id,season_id,team_id,name,description,objectives,snapshot,created_by,updated_by)
        values(p_organization_id,nullif(p_payload->>'season_id','')::uuid,nullif(p_payload->>'team_id','')::uuid,pg_catalog.btrim(p_payload->>'name'),nullif(p_payload->>'description',''),
          case when p_action='save_plan_as_template' then plan.objectives else pg_catalog.coalesce(array(select pg_catalog.jsonb_array_elements_text(p_payload->'objectives')),'{}'::text[]) end,
          case when p_action='save_plan_as_template' then public.sd_practice_plan_snapshot(plan.id) else pg_catalog.coalesce(p_payload->'snapshot','{}'::jsonb) end,p_actor_id,p_actor_id) returning id into target;
    else
      target:=(p_payload->>'template_id')::uuid; expected:=(p_payload->>'expected_version')::integer;
      update public.sd_practice_plan_templates set name=case when p_action='update_template' then pg_catalog.coalesce(nullif(pg_catalog.btrim(p_payload->>'name'),''),name) else name end,
        description=case when p_action='update_template' and p_payload?'description' then nullif(p_payload->>'description','') else description end,
        active=case when p_action='archive_template' then false when p_action='restore_template' then true else active end,
        archived_at=case when p_action='archive_template' then pg_catalog.now() when p_action='restore_template' then null else archived_at end,
        version=version+1,updated_by=p_actor_id,updated_at=pg_catalog.now() where id=target and organization_id=p_organization_id and version=expected;
      if not found then raise exception using errcode='P0001',message='stale_or_missing_template'; end if;
    end if;
    result:=pg_catalog.jsonb_build_object('template_id',target);
  else raise exception using errcode='P0001',message='unsupported_action';
  end if;

  if plan.id is not null then
    insert into public.sd_practice_plan_snapshots(practice_plan_id,organization_id,snapshot_type,plan_version,snapshot,reason,created_by)
      values(plan.id,p_organization_id,'version',plan.version,public.sd_practice_plan_snapshot(plan.id),reason,p_actor_id) on conflict do nothing;
    insert into public.sd_practice_plan_audit_logs(organization_id,season_id,team_id,event_id,practice_plan_id,actor_id,action,request_id,target_id,previous_value,new_value,reason)
      values(p_organization_id,evt.season_id,evt.team_id,evt.id,plan.id,p_actor_id,audit_action,p_request_id,target,old,result,reason);
    if plan.published_version is not null and plan.version>plan.published_version and p_action not in ('publish_plan','republish_plan','capture_started_snapshot','capture_completion_snapshot','complete_practice_plan') then
      insert into public.sd_team_event_notification_intents(organization_id,team_id,event_id,event_operation_id,intent_type,deduplication_key,payload,created_by)
        values(p_organization_id,plan.team_id,plan.event_id,plan.event_operation_id,'practice_plan_major_change',p_request_id::text||':'||plan.id::text||':major-change',pg_catalog.jsonb_build_object('plan_id',plan.id),p_actor_id);
    end if;
    if p_action like 'assign_player%' or p_action='assign_group_to_block' then
      insert into public.sd_team_event_notification_intents(organization_id,team_id,event_id,event_operation_id,intent_type,deduplication_key,payload,created_by)
        values(p_organization_id,plan.team_id,plan.event_id,plan.event_operation_id,'practice_group_changed',p_request_id::text||':'||plan.id::text||':group-change',pg_catalog.jsonb_build_object('plan_id',plan.id),p_actor_id);
    elsif p_action like 'assign_coach%' then
      insert into public.sd_team_event_notification_intents(organization_id,team_id,event_id,event_operation_id,intent_type,deduplication_key,payload,created_by)
        values(p_organization_id,plan.team_id,plan.event_id,plan.event_operation_id,'practice_coach_assignment_changed',p_request_id::text||':'||plan.id::text||':coach-change',pg_catalog.jsonb_build_object('plan_id',plan.id),p_actor_id);
    elsif p_action='add_equipment_requirement' then
      insert into public.sd_team_event_notification_intents(organization_id,team_id,event_id,event_operation_id,intent_type,deduplication_key,payload,created_by)
        values(p_organization_id,plan.team_id,plan.event_id,plan.event_operation_id,'practice_equipment_reminder',p_request_id::text||':'||plan.id::text||':equipment',pg_catalog.jsonb_build_object('plan_id',plan.id),p_actor_id);
    end if;
  elsif target is not null then
    insert into public.sd_practice_plan_audit_logs(organization_id,season_id,team_id,event_id,practice_plan_id,actor_id,action,request_id,target_id,previous_value,new_value,reason)
      values(p_organization_id,evt.season_id,evt.team_id,evt.id,null,p_actor_id,audit_action,p_request_id,target,old,result,reason);
  end if;
  update public.sd_practice_plan_mutations set status='completed',response=result,completed_at=pg_catalog.now() where organization_id=p_organization_id and request_id=p_request_id;
  return result;
exception when others then
  delete from public.sd_practice_plan_mutations where organization_id=p_organization_id and request_id=p_request_id and status='processing';
  raise;
end;
$$;

-- Extend the existing central resolver; Swift consumes this result and never maps roles itself.
create or replace function public.sd_resolve_team_capabilities(target_organization uuid,target_team uuid,target_actor uuid default auth.uid())
returns text[] language sql stable security definer set search_path='' as $$
  with actor_membership as (select role from public.sd_org_memberships where org_id=target_organization and user_id=target_actor and status='active'),
  responsibilities as (select distinct r.responsibility from public.sd_coach_team_assignments a join public.sd_coach_team_responsibilities r on r.assignment_id=a.id where a.organization_id=target_organization and (a.team_id=target_team or a.organization_wide_access) and a.coach_id=target_actor and a.active and a.ended_at is null),
  base(capability) as (
    select pg_catalog.unnest(array[
      'view_team','manage_roster','manage_schedule','manage_attendance','manage_practice','manage_game','message_team','view_development','edit_development','manage_staff','view_documents','manage_documents','view_team_schedule','create_team_event','edit_team_event','cancel_team_event','manage_practice_event','manage_game_event','manage_tournament_event','manage_meeting_event','manage_travel_event','view_event_operation','start_event_operation','manage_event_attendance','manage_event_availability','manage_event_checklist','add_team_event_notes','add_private_player_notes','complete_event_operation','reopen_event_operation'
    ]) where exists(select 1 from actor_membership where role in ('owner','admin')) or exists(select 1 from responsibilities where responsibility in ('head_coach','team_manager'))
    union select pg_catalog.unnest(array[
      'view_team','manage_roster','manage_schedule','manage_attendance','manage_practice','manage_game','message_team','view_development','edit_development','view_documents','view_team_schedule','create_team_event','edit_team_event','cancel_team_event','manage_practice_event','manage_game_event','manage_tournament_event','manage_meeting_event','manage_travel_event','view_event_operation','start_event_operation','manage_event_attendance','manage_event_availability','manage_event_checklist','add_team_event_notes','add_private_player_notes','complete_event_operation'
    ]) where exists(select 1 from responsibilities where responsibility='assistant_coach')
    union select pg_catalog.unnest(array[
      'view_team','manage_practice','view_development','edit_development','view_documents','view_team_schedule','view_event_operation','start_event_operation','manage_event_attendance','add_team_event_notes','add_private_player_notes'
    ]) where exists(select 1 from responsibilities where responsibility in ('hitting_coach','pitching_coach','catching_coach','strength_coach'))
    union select pg_catalog.unnest(array['view_team','view_development','edit_development','view_documents','view_team_schedule','view_event_operation','add_private_player_notes']) where exists(select 1 from responsibilities where responsibility='evaluator')
    union select pg_catalog.unnest(array['view_team','view_development','view_documents','view_team_schedule','view_event_operation']) where exists(select 1 from responsibilities where responsibility='read_only')
  ),
  practice(capability) as (
    select pg_catalog.unnest(array['view_practice_plan','create_practice_plan','edit_practice_plan','publish_practice_plan','archive_practice_plan','manage_practice_templates','assign_practice_players','assign_practice_coaches','assign_practice_groups','manage_practice_equipment','view_started_practice_snapshot','modify_active_practice_plan','execute_practice_blocks','complete_practice_plan','reopen_practice_plan']) where exists(select 1 from actor_membership where role in ('owner','admin')) or exists(select 1 from responsibilities where responsibility in ('head_coach','team_manager'))
    union select pg_catalog.unnest(array['view_practice_plan','create_practice_plan','edit_practice_plan','publish_practice_plan','archive_practice_plan','assign_practice_players','assign_practice_coaches','assign_practice_groups','manage_practice_equipment','view_started_practice_snapshot','modify_active_practice_plan','execute_practice_blocks','complete_practice_plan']) where exists(select 1 from responsibilities where responsibility='assistant_coach')
    union select pg_catalog.unnest(array['view_practice_plan','edit_practice_plan','view_started_practice_snapshot','modify_active_practice_plan','execute_practice_blocks']) where exists(select 1 from responsibilities where responsibility in ('hitting_coach','pitching_coach','catching_coach','strength_coach'))
    union select pg_catalog.unnest(array['view_practice_plan','view_started_practice_snapshot']) where exists(select 1 from responsibilities where responsibility in ('evaluator','read_only'))
  ) select pg_catalog.coalesce(pg_catalog.array_agg(capability order by capability),'{}'::text[]) from (select capability from base union select capability from practice) all_caps;
$$;

alter table public.sd_team_event_notification_intents drop constraint if exists sd_team_event_notification_intents_intent_type_check;
alter table public.sd_team_event_notification_intents add constraint sd_team_event_notification_intents_intent_type_check check (intent_type in (
  'new_event','time_change','location_change','cancellation','postponement','availability_changed','player_unavailable','operation_started','arrival_reminder','event_completed','recap_published','late_schedule_change','attendance_correction',
  'practice_plan_published','practice_plan_major_change','practice_group_changed','practice_coach_assignment_changed','practice_equipment_reminder','practice_plan_ready','practice_completed','practice_recap_published'
));

alter table public.sd_practice_plans enable row level security;
alter table public.sd_practice_plan_blocks enable row level security;
alter table public.sd_practice_plan_groups enable row level security;
alter table public.sd_practice_plan_assignments enable row level security;
alter table public.sd_practice_plan_equipment enable row level security;
alter table public.sd_practice_plan_templates enable row level security;
alter table public.sd_practice_plan_snapshots enable row level security;
alter table public.sd_practice_block_executions enable row level security;
alter table public.sd_practice_plan_adjustments enable row level security;
alter table public.sd_practice_plan_audit_logs enable row level security;
alter table public.sd_practice_plan_mutations enable row level security;

revoke all on public.sd_practice_plans,public.sd_practice_plan_blocks,public.sd_practice_plan_groups,public.sd_practice_plan_assignments,public.sd_practice_plan_equipment,public.sd_practice_plan_templates,public.sd_practice_plan_snapshots,public.sd_practice_block_executions,public.sd_practice_plan_adjustments,public.sd_practice_plan_audit_logs,public.sd_practice_plan_mutations from anon,authenticated;
grant select,insert,update,delete on public.sd_practice_plans,public.sd_practice_plan_blocks,public.sd_practice_plan_groups,public.sd_practice_plan_assignments,public.sd_practice_plan_equipment,public.sd_practice_plan_templates,public.sd_practice_plan_snapshots,public.sd_practice_block_executions,public.sd_practice_plan_adjustments,public.sd_practice_plan_audit_logs,public.sd_practice_plan_mutations to service_role;
revoke all on function public.sd_practice_plan_snapshot(uuid),public.sd_materialize_practice_snapshot(uuid,uuid,jsonb,uuid),public.sd_validate_practice_plan(uuid),public.sd_apply_practice_plan_mutation(uuid,uuid,uuid,text,uuid,jsonb) from public,anon,authenticated;
grant execute on function public.sd_practice_plan_snapshot(uuid),public.sd_materialize_practice_snapshot(uuid,uuid,jsonb,uuid),public.sd_validate_practice_plan(uuid),public.sd_apply_practice_plan_mutation(uuid,uuid,uuid,text,uuid,jsonb) to service_role;
