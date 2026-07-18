-- Phase 12E: complete team-scoped Game Operations.
-- Additive only. Phase 12B remains authoritative for canonical game events,
-- opponent, time, arrival, facility and status. Phase 12C remains authoritative
-- for participants, availability, attendance, shared checklists/notes and the
-- event-operation lifecycle. This migration links those systems; it does not
-- duplicate them.
-- Rollback: revoke the functions/grants below, then drop only sd_game_* tables
-- after exporting snapshots, results and audit history. The compatibility score
-- projection in sd_team_event_games may be cleared independently if required.

create table if not exists public.sd_game_rule_profiles (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  organization_id uuid not null references public.sd_orgs(id) on delete cascade,
  season_id uuid references public.sd_seasons(id) on delete restrict,
  team_id uuid references public.sd_teams(id) on delete restrict,
  tournament_event_id uuid references public.sd_team_events(id) on delete restrict,
  event_id uuid references public.sd_team_events(id) on delete restrict,
  name text not null check (pg_catalog.char_length(pg_catalog.btrim(name)) between 1 and 160),
  innings integer check (innings is null or innings > 0),
  minimum_batting_slots integer check (minimum_batting_slots is null or minimum_batting_slots > 0),
  maximum_batting_slots integer check (maximum_batting_slots is null or maximum_batting_slots > 0),
  continuous_batting_order_allowed boolean,
  bat_entire_roster_allowed boolean,
  dh_allowed boolean,
  eh_allowed boolean,
  maximum_eh integer check (maximum_eh is null or maximum_eh >= 0),
  defensive_only_players_allowed boolean,
  offensive_only_players_allowed boolean,
  reentry_policy text,
  courtesy_runner_policy text,
  pitcher_reentry_policy text,
  defensive_player_count integer check (defensive_player_count is null or defensive_player_count > 0),
  required_positions text[] not null default '{}'::text[],
  custom_position_labels text[] not null default '{}'::text[],
  notes text,
  active boolean not null default true,
  version integer not null default 1 check (version > 0),
  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default pg_catalog.now(),
  updated_at timestamptz not null default pg_catalog.now(),
  archived_at timestamptz,
  check (maximum_batting_slots is null or minimum_batting_slots is null or maximum_batting_slots >= minimum_batting_slots),
  check ((active and archived_at is null) or (not active and archived_at is not null))
);

create table if not exists public.sd_game_plans (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  organization_id uuid not null references public.sd_orgs(id) on delete cascade,
  season_id uuid not null references public.sd_seasons(id) on delete restrict,
  team_id uuid not null references public.sd_teams(id) on delete restrict,
  event_id uuid not null references public.sd_team_events(id) on delete restrict,
  event_operation_id uuid references public.sd_event_operations(id) on delete restrict,
  title text not null check (pg_catalog.char_length(pg_catalog.btrim(title)) between 1 and 160),
  status text not null default 'draft' check (status in ('draft','ready','published','active','completed','archived')),
  lineup_mode text not null default 'custom' check (lineup_mode in (
    'standard_nine','standard_nine_with_dh','standard_nine_with_one_eh',
    'standard_nine_with_multiple_eh','continuous_batting_order',
    'bat_entire_available_roster','custom'
  )),
  rule_profile_id uuid references public.sd_game_rule_profiles(id) on delete set null,
  scheduled_innings integer check (scheduled_innings is null or scheduled_innings > 0),
  batting_order_locked boolean not null default false,
  defense_plan_locked boolean not null default false,
  is_primary boolean not null default true,
  published_version integer,
  published_at timestamptz,
  published_by uuid references auth.users(id) on delete set null,
  current_snapshot_id uuid,
  internal_strategy_notes text,
  player_reminders text,
  parent_reminders text,
  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default pg_catalog.now(),
  updated_at timestamptz not null default pg_catalog.now(),
  archived_at timestamptz,
  version integer not null default 1 check (version > 0),
  check ((status = 'archived') = (archived_at is not null)),
  check (published_version is null or published_version <= version)
);

create unique index if not exists uq_sd_game_plans_primary_event
  on public.sd_game_plans(event_id) where is_primary and archived_at is null;

alter table public.sd_game_plans
  add constraint sd_game_plans_event_scope_fk
  foreign key (event_id, organization_id, season_id, team_id)
  references public.sd_team_events(id, organization_id, season_id, team_id)
  on delete restrict;

create table if not exists public.sd_game_plan_eligibility (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  game_plan_id uuid not null references public.sd_game_plans(id) on delete cascade,
  organization_id uuid not null references public.sd_orgs(id) on delete cascade,
  player_id uuid not null references auth.users(id) on delete restrict,
  status text not null default 'eligible' check (status in (
    'eligible','unavailable','tentative','injured','suspended','absent','late',
    'leaving_early','coach_excluded','pending_confirmation','rostered_not_dressing','custom'
  )),
  exclusion_reason text,
  source_participant_version integer,
  version integer not null default 1 check (version > 0),
  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default pg_catalog.now(),
  updated_at timestamptz not null default pg_catalog.now(),
  unique (game_plan_id, player_id),
  check (status not in ('coach_excluded','rostered_not_dressing') or pg_catalog.char_length(pg_catalog.btrim(pg_catalog.coalesce(exclusion_reason,''))) > 0)
);

create table if not exists public.sd_game_batting_entries (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  game_plan_id uuid not null references public.sd_game_plans(id) on delete cascade,
  organization_id uuid not null references public.sd_orgs(id) on delete cascade,
  player_id uuid not null references auth.users(id) on delete restrict,
  batting_slot integer check (batting_slot is null or batting_slot > 0),
  offensive_role text not null default 'hitter' check (offensive_role in (
    'hitter','eh','dh','pitcher_batting','offensive_only','substitute','courtesy_runner','bench','custom'
  )),
  role_label text,
  active boolean not null default true,
  starter boolean not null default true,
  eligible boolean not null default true,
  source text not null default 'manual' check (source in ('manual','roster','prior_plan','reconciliation','active_adjustment')),
  notes text,
  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default pg_catalog.now(),
  updated_at timestamptz not null default pg_catalog.now(),
  archived_at timestamptz,
  version integer not null default 1 check (version > 0),
  check ((active and archived_at is null) or (not active and archived_at is not null)),
  check ((offensive_role = 'bench' and batting_slot is null) or offensive_role <> 'bench')
);

create unique index if not exists uq_sd_game_batting_active_player
  on public.sd_game_batting_entries(game_plan_id, player_id) where active;
create unique index if not exists uq_sd_game_batting_active_slot
  on public.sd_game_batting_entries(game_plan_id, batting_slot) where active and batting_slot is not null;

create table if not exists public.sd_game_defensive_assignments (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  game_plan_id uuid not null references public.sd_game_plans(id) on delete cascade,
  organization_id uuid not null references public.sd_orgs(id) on delete cascade,
  player_id uuid not null references auth.users(id) on delete restrict,
  inning_number integer not null check (inning_number >= 0),
  inning_half text not null default 'defense' check (inning_half in ('defense','top','bottom','starting')),
  position_code text not null check (pg_catalog.upper(position_code) not in ('EH','DH')),
  position_label text,
  assignment_type text not null default 'planned' check (assignment_type in ('starter','planned','bench','defensive_only','replacement','custom')),
  starter boolean not null default false,
  planned boolean not null default true,
  active boolean not null default true,
  notes text,
  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default pg_catalog.now(),
  updated_at timestamptz not null default pg_catalog.now(),
  archived_at timestamptz,
  version integer not null default 1 check (version > 0),
  check ((active and archived_at is null) or (not active and archived_at is not null))
);

create index if not exists idx_sd_game_defense_position
  on public.sd_game_defensive_assignments(game_plan_id, inning_number, inning_half, position_code) where active and pg_catalog.upper(position_code) <> 'BENCH';
create index if not exists idx_sd_game_defense_player
  on public.sd_game_defensive_assignments(game_plan_id, inning_number, inning_half, player_id) where active and pg_catalog.upper(position_code) <> 'BENCH';

create table if not exists public.sd_game_pitcher_catcher_plans (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  game_plan_id uuid not null references public.sd_game_plans(id) on delete cascade,
  organization_id uuid not null references public.sd_orgs(id) on delete cascade,
  player_id uuid not null references auth.users(id) on delete restrict,
  role_type text not null check (role_type in (
    'starting_pitcher','relief_pitcher','emergency_pitcher','starting_catcher','backup_catcher','bullpen_catcher'
  )),
  sequence_index integer not null default 0 check (sequence_index >= 0),
  planned_start_inning integer check (planned_start_inning is null or planned_start_inning > 0),
  planned_end_inning integer check (planned_end_inning is null or planned_end_inning > 0),
  manual_pitch_limit integer check (manual_pitch_limit is null or manual_pitch_limit > 0),
  pairing_player_id uuid references auth.users(id) on delete restrict,
  notes text,
  status text not null default 'planned' check (status in ('planned','ready','unavailable','scratched','completed')),
  version integer not null default 1 check (version > 0),
  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default pg_catalog.now(),
  updated_at timestamptz not null default pg_catalog.now(),
  archived_at timestamptz,
  check (planned_end_inning is null or planned_start_inning is null or planned_end_inning >= planned_start_inning)
);

create table if not exists public.sd_game_staff_assignments (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  game_plan_id uuid not null references public.sd_game_plans(id) on delete cascade,
  organization_id uuid not null references public.sd_orgs(id) on delete cascade,
  staff_user_id uuid not null references auth.users(id) on delete restrict,
  responsibility_code text not null,
  responsibility_label text,
  notes text,
  active boolean not null default true,
  version integer not null default 1 check (version > 0),
  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default pg_catalog.now(),
  updated_at timestamptz not null default pg_catalog.now(),
  archived_at timestamptz,
  unique nulls not distinct (game_plan_id, staff_user_id, responsibility_code, archived_at)
);

create table if not exists public.sd_game_plan_snapshots (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  game_plan_id uuid not null references public.sd_game_plans(id) on delete restrict,
  organization_id uuid not null references public.sd_orgs(id) on delete cascade,
  event_operation_id uuid references public.sd_event_operations(id) on delete restrict,
  snapshot_type text not null check (snapshot_type in ('version','published','started','completed')),
  plan_version integer not null check (plan_version > 0),
  snapshot jsonb not null check (pg_catalog.jsonb_typeof(snapshot) = 'object'),
  reason text,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default pg_catalog.now(),
  unique (game_plan_id, snapshot_type, plan_version)
);

alter table public.sd_game_plans
  add constraint sd_game_plans_current_snapshot_fk foreign key (current_snapshot_id)
  references public.sd_game_plan_snapshots(id) on delete set null;

create table if not exists public.sd_game_active_adjustments (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  game_plan_id uuid not null references public.sd_game_plans(id) on delete restrict,
  started_snapshot_id uuid not null references public.sd_game_plan_snapshots(id) on delete restrict,
  adjustment_type text not null check (adjustment_type in ('lineup','defense','pitcher_catcher','eligibility')),
  target_id uuid,
  previous_value jsonb,
  new_value jsonb not null default '{}'::jsonb,
  reason text not null check (pg_catalog.char_length(pg_catalog.btrim(reason)) > 0),
  actor_id uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default pg_catalog.now()
);

create table if not exists public.sd_game_results (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  game_plan_id uuid not null unique references public.sd_game_plans(id) on delete restrict,
  organization_id uuid not null references public.sd_orgs(id) on delete cascade,
  team_score integer check (team_score is null or team_score >= 0),
  opponent_score integer check (opponent_score is null or opponent_score >= 0),
  outcome text not null default 'unknown' check (outcome in ('win','loss','tie','no_contest','cancelled','postponed','incomplete','unknown')),
  innings_played integer check (innings_played is null or innings_played >= 0),
  ended_early boolean not null default false,
  end_reason text,
  result_status text not null default 'draft' check (result_status in ('draft','recorded','verified','corrected')),
  result_notes text,
  recorded_by uuid references auth.users(id) on delete set null,
  recorded_at timestamptz,
  verified_by uuid references auth.users(id) on delete set null,
  verified_at timestamptz,
  version integer not null default 1 check (version > 0),
  updated_at timestamptz not null default pg_catalog.now(),
  check ((team_score is null and opponent_score is null) or (team_score is not null and opponent_score is not null))
);

create table if not exists public.sd_game_recaps (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  game_plan_id uuid not null references public.sd_game_plans(id) on delete restrict,
  organization_id uuid not null references public.sd_orgs(id) on delete cascade,
  visibility text not null check (visibility in ('staff','team','player','parent')),
  subject_player_id uuid references auth.users(id) on delete restrict,
  body text not null check (pg_catalog.char_length(pg_catalog.btrim(body)) > 0),
  follow_up_items text[] not null default '{}'::text[],
  published_at timestamptz,
  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default pg_catalog.now(),
  updated_at timestamptz not null default pg_catalog.now(),
  version integer not null default 1 check (version > 0)
);

create table if not exists public.sd_game_plan_audit_logs (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  organization_id uuid not null references public.sd_orgs(id) on delete cascade,
  season_id uuid not null references public.sd_seasons(id) on delete restrict,
  team_id uuid not null references public.sd_teams(id) on delete restrict,
  event_id uuid not null references public.sd_team_events(id) on delete restrict,
  game_plan_id uuid references public.sd_game_plans(id) on delete restrict,
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

create table if not exists public.sd_game_plan_mutations (
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

create index if not exists idx_sd_game_rule_profiles_scope on public.sd_game_rule_profiles(organization_id, season_id, team_id, tournament_event_id, event_id, active);
create index if not exists idx_sd_game_plans_scope on public.sd_game_plans(organization_id, season_id, team_id, event_id, status);
create index if not exists idx_sd_game_plans_version on public.sd_game_plans(id, version, published_version);
create index if not exists idx_sd_game_eligibility_status on public.sd_game_plan_eligibility(game_plan_id, status, player_id);
create index if not exists idx_sd_game_batting_order on public.sd_game_batting_entries(game_plan_id, batting_slot) where active;
create index if not exists idx_sd_game_batting_role on public.sd_game_batting_entries(game_plan_id, offensive_role) where active;
create index if not exists idx_sd_game_defense_inning on public.sd_game_defensive_assignments(game_plan_id, inning_number, inning_half, position_code) where active;
create index if not exists idx_sd_game_pitcher_catcher_sequence on public.sd_game_pitcher_catcher_plans(game_plan_id, role_type, sequence_index) where archived_at is null;
create index if not exists idx_sd_game_staff_role on public.sd_game_staff_assignments(game_plan_id, responsibility_code) where active;
create index if not exists idx_sd_game_snapshots_lookup on public.sd_game_plan_snapshots(game_plan_id, snapshot_type, plan_version desc);
create index if not exists idx_sd_game_adjustments_history on public.sd_game_active_adjustments(game_plan_id, created_at);
create index if not exists idx_sd_game_results_status on public.sd_game_results(organization_id, result_status, updated_at);
create index if not exists idx_sd_game_audit_history on public.sd_game_plan_audit_logs(game_plan_id, created_at);

create or replace function public.sd_game_plan_snapshot(p_plan_id uuid)
returns jsonb language sql stable security definer set search_path='' as $$
  select pg_catalog.jsonb_build_object(
    'plan', pg_catalog.to_jsonb(plan),
    'rule_profile', pg_catalog.to_jsonb(rule_profile),
    'eligibility', (select pg_catalog.coalesce(pg_catalog.jsonb_agg(pg_catalog.to_jsonb(x) order by x.player_id), '[]'::jsonb) from public.sd_game_plan_eligibility x where x.game_plan_id=plan.id),
    'batting_order', (select pg_catalog.coalesce(pg_catalog.jsonb_agg(pg_catalog.to_jsonb(x) order by x.batting_slot nulls last, x.created_at), '[]'::jsonb) from public.sd_game_batting_entries x where x.game_plan_id=plan.id and x.active),
    'defense', (select pg_catalog.coalesce(pg_catalog.jsonb_agg(pg_catalog.to_jsonb(x) order by x.inning_number, x.position_code), '[]'::jsonb) from public.sd_game_defensive_assignments x where x.game_plan_id=plan.id and x.active),
    'pitcher_catcher', (select pg_catalog.coalesce(pg_catalog.jsonb_agg(pg_catalog.to_jsonb(x) order by x.role_type, x.sequence_index), '[]'::jsonb) from public.sd_game_pitcher_catcher_plans x where x.game_plan_id=plan.id and x.archived_at is null),
    'staff', (select pg_catalog.coalesce(pg_catalog.jsonb_agg(pg_catalog.to_jsonb(x) order by x.responsibility_code), '[]'::jsonb) from public.sd_game_staff_assignments x where x.game_plan_id=plan.id and x.active),
    'result', pg_catalog.to_jsonb(result),
    'recaps', (select pg_catalog.coalesce(pg_catalog.jsonb_agg(pg_catalog.to_jsonb(x) order by x.created_at), '[]'::jsonb) from public.sd_game_recaps x where x.game_plan_id=plan.id)
  ) from public.sd_game_plans plan
  left join public.sd_game_rule_profiles rule_profile on rule_profile.id=plan.rule_profile_id
  left join public.sd_game_results result on result.game_plan_id=plan.id
  where plan.id=p_plan_id;
$$;

create or replace function public.sd_validate_game_plan(p_plan_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare plan public.sd_game_plans%rowtype; rules public.sd_game_rule_profiles%rowtype;
  blockers jsonb := '[]'::jsonb; warnings jsonb := '[]'::jsonb; notices jsonb := '[]'::jsonb;
  hitter_count integer; eh_count integer; defense_count integer;
begin
  select * into plan from public.sd_game_plans where id=p_plan_id;
  if not found then raise exception using errcode='P0001',message='game_plan_not_found'; end if;
  if plan.rule_profile_id is not null then select * into rules from public.sd_game_rule_profiles where id=plan.rule_profile_id and active; end if;
  select pg_catalog.count(*),pg_catalog.count(*) filter(where offensive_role='eh') into hitter_count,eh_count from public.sd_game_batting_entries where game_plan_id=plan.id and active and batting_slot is not null;
  if hitter_count=0 then blockers:=blockers||pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('code','no_batting_order','severity','blocking_error')); end if;
  if exists(select 1 from (select batting_slot from public.sd_game_batting_entries where game_plan_id=plan.id and active and batting_slot is not null group by batting_slot having pg_catalog.count(*)>1) d) then blockers:=blockers||pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('code','duplicate_batting_slot','severity','blocking_error')); end if;
  if exists(select 1 from (select player_id from public.sd_game_batting_entries where game_plan_id=plan.id and active and batting_slot is not null group by player_id having pg_catalog.count(*)>1) d) then blockers:=blockers||pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('code','duplicate_active_hitter','severity','blocking_error')); end if;
  if hitter_count>0 and exists(select 1 from pg_catalog.generate_series(1,hitter_count) slot where not exists(select 1 from public.sd_game_batting_entries b where b.game_plan_id=plan.id and b.active and b.batting_slot=slot)) then blockers:=blockers||pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('code','missing_batting_slot','severity','blocking_error')); end if;
  if rules.id is null then warnings:=warnings||pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('code','missing_rule_profile','severity','readiness_warning')); notices:=notices||pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('code','rule_profile_uncertainty','severity','informational_notice')); end if;
  if rules.minimum_batting_slots is not null and hitter_count<rules.minimum_batting_slots then blockers:=blockers||pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('code','batting_order_below_minimum','severity','blocking_error','actual',hitter_count,'expected',rules.minimum_batting_slots)); end if;
  if rules.maximum_batting_slots is not null and hitter_count>rules.maximum_batting_slots then blockers:=blockers||pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('code','batting_order_above_maximum','severity','blocking_error','actual',hitter_count,'expected',rules.maximum_batting_slots)); end if;
  if rules.id is not null and rules.eh_allowed=false and eh_count>0 then blockers:=blockers||pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('code','eh_disallowed','severity','blocking_error')); end if;
  if rules.maximum_eh is not null and eh_count>rules.maximum_eh then blockers:=blockers||pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('code','eh_limit_exceeded','severity','blocking_error','actual',eh_count,'expected',rules.maximum_eh)); end if;
  if rules.id is not null and rules.dh_allowed=false and exists(select 1 from public.sd_game_batting_entries where game_plan_id=plan.id and active and offensive_role='dh') then blockers:=blockers||pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('code','dh_disallowed','severity','blocking_error')); end if;
  if rules.continuous_batting_order_allowed=false and plan.lineup_mode='continuous_batting_order' then blockers:=blockers||pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('code','continuous_order_disallowed','severity','blocking_error')); end if;
  if rules.bat_entire_roster_allowed=false and plan.lineup_mode='bat_entire_available_roster' then blockers:=blockers||pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('code','bat_entire_roster_disallowed','severity','blocking_error')); end if;
  if plan.lineup_mode='bat_entire_available_roster' and exists(select 1 from public.sd_game_plan_eligibility e where e.game_plan_id=plan.id and e.status in ('eligible','tentative','late','leaving_early','pending_confirmation') and not exists(select 1 from public.sd_game_batting_entries b where b.game_plan_id=plan.id and b.player_id=e.player_id and b.active and b.batting_slot is not null) and pg_catalog.char_length(pg_catalog.btrim(pg_catalog.coalesce(e.exclusion_reason,'')))=0) then warnings:=warnings||pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('code','bat_entire_roster_omission','severity','readiness_warning')); end if;
  if exists(select 1 from public.sd_game_batting_entries b join public.sd_game_plan_eligibility e on e.game_plan_id=b.game_plan_id and e.player_id=b.player_id where b.game_plan_id=plan.id and b.active and e.status in ('unavailable','injured','suspended','absent','rostered_not_dressing')) then warnings:=warnings||pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('code','unavailable_player_in_lineup','severity','readiness_warning')); end if;
  if exists(select 1 from public.sd_game_batting_entries b join public.sd_game_plan_eligibility e on e.game_plan_id=b.game_plan_id and e.player_id=b.player_id where b.game_plan_id=plan.id and b.active and e.status='late') then warnings:=warnings||pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('code','late_player_scheduled_before_arrival_review','severity','readiness_warning')); end if;
  if exists(select 1 from public.sd_game_defensive_assignments d join public.sd_game_batting_entries b on b.game_plan_id=d.game_plan_id and b.player_id=d.player_id where d.game_plan_id=plan.id and d.active and b.active and b.offensive_role='offensive_only') and rules.offensive_only_players_allowed=false then blockers:=blockers||pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('code','offensive_only_defense_disallowed','severity','blocking_error')); end if;
  if rules.defensive_only_players_allowed=false and exists(select 1 from public.sd_game_defensive_assignments d where d.game_plan_id=plan.id and d.active and not exists(select 1 from public.sd_game_batting_entries b where b.game_plan_id=plan.id and b.player_id=d.player_id and b.active and b.batting_slot is not null)) then blockers:=blockers||pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('code','defensive_only_disallowed','severity','blocking_error')); end if;
  if exists(select 1 from (select inning_number,inning_half,player_id from public.sd_game_defensive_assignments where game_plan_id=plan.id and active and pg_catalog.upper(position_code)<>'BENCH' group by inning_number,inning_half,player_id having pg_catalog.count(*)>1) d) then blockers:=blockers||pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('code','duplicate_simultaneous_defender','severity','blocking_error')); end if;
  if rules.defensive_player_count is not null then select pg_catalog.count(*) into defense_count from public.sd_game_defensive_assignments where game_plan_id=plan.id and active and inning_number=0 and pg_catalog.upper(position_code)<>'BENCH'; if defense_count<>rules.defensive_player_count then warnings:=warnings||pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('code','defensive_player_count_mismatch','severity','readiness_warning','actual',defense_count,'expected',rules.defensive_player_count)); end if; end if;
  if rules.id is not null and exists(select 1 from pg_catalog.unnest(rules.required_positions) p where not exists(select 1 from public.sd_game_defensive_assignments d where d.game_plan_id=plan.id and d.active and d.inning_number=0 and pg_catalog.upper(d.position_code)=pg_catalog.upper(p))) then warnings:=warnings||pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('code','required_defensive_position_unfilled','severity','readiness_warning')); end if;
  if not exists(select 1 from public.sd_game_pitcher_catcher_plans where game_plan_id=plan.id and role_type='starting_pitcher' and archived_at is null) then warnings:=warnings||pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('code','starting_pitcher_missing','severity','readiness_warning')); end if;
  if not exists(select 1 from public.sd_game_pitcher_catcher_plans where game_plan_id=plan.id and role_type='starting_catcher' and archived_at is null) then warnings:=warnings||pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('code','starting_catcher_missing','severity','readiness_warning')); end if;
  if exists(select 1 from public.sd_game_pitcher_catcher_plans p join public.sd_game_plan_eligibility e on e.game_plan_id=p.game_plan_id and e.player_id=p.player_id where p.game_plan_id=plan.id and p.archived_at is null and p.role_type like '%pitcher' and e.status in ('unavailable','injured','suspended','absent')) then warnings:=warnings||pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('code','pitcher_ineligible','severity','readiness_warning')); end if;
  if exists(select 1 from public.sd_game_pitcher_catcher_plans p join public.sd_game_plan_eligibility e on e.game_plan_id=p.game_plan_id and e.player_id=p.player_id where p.game_plan_id=plan.id and p.archived_at is null and p.role_type like '%catcher' and e.status in ('unavailable','injured','suspended','absent')) then warnings:=warnings||pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('code','catcher_ineligible','severity','readiness_warning')); end if;
  if exists(select 1 from public.sd_game_pitcher_catcher_plans p where p.game_plan_id=plan.id and p.archived_at is null and p.pairing_player_id=p.player_id) then warnings:=warnings||pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('code','pitcher_catcher_pair_conflict','severity','readiness_warning')); end if;
  if exists(select 1 from public.sd_event_operations operation join public.sd_event_operation_participants participant on participant.event_operation_id=operation.id where operation.event_id=plan.event_id and participant.participant_type='player' and participant.expected and (not exists(select 1 from public.sd_game_plan_eligibility e where e.game_plan_id=plan.id and e.player_id=participant.user_id) or exists(select 1 from public.sd_game_plan_eligibility e where e.game_plan_id=plan.id and e.player_id=participant.user_id and e.source_participant_version is distinct from participant.version))) then warnings:=warnings||pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('code','roster_drift','severity','readiness_warning')); end if;
  if exists(select 1 from pg_catalog.jsonb_array_elements(public.sd_team_event_conflicts(plan.organization_id,plan.team_id,(select start_at from public.sd_team_events where id=plan.event_id),(select end_at from public.sd_team_events where id=plan.event_id),null,(select pg_catalog.coalesce(pg_catalog.array_agg(staff_user_id),'{}'::uuid[]) from public.sd_game_staff_assignments where game_plan_id=plan.id and active),plan.event_id)) conflict where conflict->>'type'='coach') then warnings:=warnings||pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('code','coach_assignment_conflict','severity','readiness_warning')); end if;
  if plan.status in ('draft','ready') and exists(select 1 from public.sd_team_events e where e.id=plan.event_id and e.start_at<=pg_catalog.now()+interval '2 hours') then warnings:=warnings||pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('code','unpublished_plan_near_game_start','severity','readiness_warning')); end if;
  return pg_catalog.jsonb_build_object('blocking_errors',blockers,'readiness_warnings',warnings,'notices',notices,'valid',pg_catalog.jsonb_array_length(blockers)=0,'batting_count',hitter_count,'eh_count',eh_count);
end;
$$;

-- Central capability resolver extension. Swift consumes this result and does not
-- infer game permissions from role names.
create or replace function public.sd_resolve_team_capabilities(target_organization uuid,target_team uuid,target_actor uuid default auth.uid())
returns text[] language sql stable security definer set search_path='' as $$
  with actor_membership as (select role from public.sd_org_memberships where org_id=target_organization and user_id=target_actor and status='active'),
  responsibilities as (select distinct r.responsibility from public.sd_coach_team_assignments a join public.sd_coach_team_responsibilities r on r.assignment_id=a.id where a.organization_id=target_organization and (a.team_id=target_team or a.organization_wide_access) and a.coach_id=target_actor and a.active and a.ended_at is null),
  base(capability) as (
    select pg_catalog.unnest(array['view_team','manage_roster','manage_schedule','manage_attendance','manage_practice','manage_game','message_team','view_development','edit_development','manage_staff','view_documents','manage_documents','view_team_schedule','create_team_event','edit_team_event','cancel_team_event','manage_practice_event','manage_game_event','manage_tournament_event','manage_meeting_event','manage_travel_event','view_event_operation','start_event_operation','manage_event_attendance','manage_event_availability','manage_event_checklist','add_team_event_notes','add_private_player_notes','complete_event_operation','reopen_event_operation']) where exists(select 1 from actor_membership where role in ('owner','admin')) or exists(select 1 from responsibilities where responsibility in ('head_coach','team_manager'))
    union select pg_catalog.unnest(array['view_team','manage_roster','manage_schedule','manage_attendance','manage_practice','manage_game','message_team','view_development','edit_development','view_documents','view_team_schedule','create_team_event','edit_team_event','cancel_team_event','manage_practice_event','manage_game_event','manage_tournament_event','manage_meeting_event','manage_travel_event','view_event_operation','start_event_operation','manage_event_attendance','manage_event_availability','manage_event_checklist','add_team_event_notes','add_private_player_notes','complete_event_operation']) where exists(select 1 from responsibilities where responsibility='assistant_coach')
    union select pg_catalog.unnest(array['view_team','manage_practice','manage_game','view_development','edit_development','view_documents','view_team_schedule','view_event_operation','start_event_operation','manage_event_attendance','add_team_event_notes','add_private_player_notes']) where exists(select 1 from responsibilities where responsibility in ('hitting_coach','pitching_coach','catching_coach','strength_coach'))
    union select pg_catalog.unnest(array['view_team','view_development','edit_development','view_documents','view_team_schedule','view_event_operation','add_private_player_notes']) where exists(select 1 from responsibilities where responsibility='evaluator')
    union select pg_catalog.unnest(array['view_team','view_development','view_documents','view_team_schedule','view_event_operation']) where exists(select 1 from responsibilities where responsibility='read_only')
  ),
  practice(capability) as (
    select pg_catalog.unnest(array['view_practice_plan','create_practice_plan','edit_practice_plan','publish_practice_plan','archive_practice_plan','manage_practice_templates','assign_practice_players','assign_practice_coaches','assign_practice_groups','manage_practice_equipment','view_started_practice_snapshot','modify_active_practice_plan','execute_practice_blocks','complete_practice_plan','reopen_practice_plan']) where exists(select 1 from actor_membership where role in ('owner','admin')) or exists(select 1 from responsibilities where responsibility in ('head_coach','team_manager'))
    union select pg_catalog.unnest(array['view_practice_plan','create_practice_plan','edit_practice_plan','publish_practice_plan','archive_practice_plan','assign_practice_players','assign_practice_coaches','assign_practice_groups','manage_practice_equipment','view_started_practice_snapshot','modify_active_practice_plan','execute_practice_blocks','complete_practice_plan']) where exists(select 1 from responsibilities where responsibility='assistant_coach')
    union select pg_catalog.unnest(array['view_practice_plan','edit_practice_plan','view_started_practice_snapshot','modify_active_practice_plan','execute_practice_blocks']) where exists(select 1 from responsibilities where responsibility in ('hitting_coach','pitching_coach','catching_coach','strength_coach'))
    union select pg_catalog.unnest(array['view_practice_plan','view_started_practice_snapshot']) where exists(select 1 from responsibilities where responsibility in ('evaluator','read_only'))
  ),
  game(capability) as (
    select pg_catalog.unnest(array['view_game_plan','create_game_plan','edit_game_plan','publish_game_plan','archive_game_plan','configure_game_rules','manage_batting_order','manage_defensive_plan','manage_pitcher_catcher_plan','manage_game_staff','manage_game_checklist','view_started_game_snapshot','modify_active_game_plan','record_game_result','complete_game_operation','reopen_game_operation']) where exists(select 1 from actor_membership where role in ('owner','admin')) or exists(select 1 from responsibilities where responsibility in ('head_coach','team_manager'))
    union select pg_catalog.unnest(array['view_game_plan','create_game_plan','edit_game_plan','publish_game_plan','archive_game_plan','manage_batting_order','manage_defensive_plan','manage_pitcher_catcher_plan','manage_game_staff','manage_game_checklist','view_started_game_snapshot','modify_active_game_plan','record_game_result','complete_game_operation']) where exists(select 1 from responsibilities where responsibility='assistant_coach')
    union select pg_catalog.unnest(array['view_game_plan','view_started_game_snapshot','modify_active_game_plan','manage_batting_order']) where exists(select 1 from responsibilities where responsibility='hitting_coach')
    union select pg_catalog.unnest(array['view_game_plan','view_started_game_snapshot','modify_active_game_plan','manage_pitcher_catcher_plan']) where exists(select 1 from responsibilities where responsibility in ('pitching_coach','catching_coach'))
    union select pg_catalog.unnest(array['view_game_plan','view_started_game_snapshot']) where exists(select 1 from responsibilities where responsibility in ('strength_coach','evaluator','read_only'))
  ) select pg_catalog.coalesce(pg_catalog.array_agg(capability order by capability),'{}'::text[]) from (select capability from base union select capability from practice union select capability from game) all_caps;
$$;

alter table public.sd_team_event_notification_intents drop constraint if exists sd_team_event_notification_intents_intent_type_check;
alter table public.sd_team_event_notification_intents add constraint sd_team_event_notification_intents_intent_type_check check (intent_type in (
  'new_event','time_change','location_change','cancellation','postponement','availability_changed','player_unavailable','operation_started','arrival_reminder','event_completed','recap_published','late_schedule_change','attendance_correction',
  'practice_plan_published','practice_plan_major_change','practice_group_changed','practice_coach_assignment_changed','practice_equipment_reminder','practice_plan_ready','practice_completed','practice_recap_published',
  'game_plan_published','game_lineup_major_change','game_player_added','game_player_removed','game_assignment_changed','game_uniform_reminder','game_day_started','game_completed','game_result_published','game_recap_published'
));

alter table public.sd_game_rule_profiles enable row level security;
alter table public.sd_game_plans enable row level security;
alter table public.sd_game_plan_eligibility enable row level security;
alter table public.sd_game_batting_entries enable row level security;
alter table public.sd_game_defensive_assignments enable row level security;
alter table public.sd_game_pitcher_catcher_plans enable row level security;
alter table public.sd_game_staff_assignments enable row level security;
alter table public.sd_game_plan_snapshots enable row level security;
alter table public.sd_game_active_adjustments enable row level security;
alter table public.sd_game_results enable row level security;
alter table public.sd_game_recaps enable row level security;
alter table public.sd_game_plan_audit_logs enable row level security;
alter table public.sd_game_plan_mutations enable row level security;

revoke all on public.sd_game_rule_profiles,public.sd_game_plans,public.sd_game_plan_eligibility,public.sd_game_batting_entries,public.sd_game_defensive_assignments,public.sd_game_pitcher_catcher_plans,public.sd_game_staff_assignments,public.sd_game_plan_snapshots,public.sd_game_active_adjustments,public.sd_game_results,public.sd_game_recaps,public.sd_game_plan_audit_logs,public.sd_game_plan_mutations from anon,authenticated;
grant select,insert,update,delete on public.sd_game_rule_profiles,public.sd_game_plans,public.sd_game_plan_eligibility,public.sd_game_batting_entries,public.sd_game_defensive_assignments,public.sd_game_pitcher_catcher_plans,public.sd_game_staff_assignments,public.sd_game_plan_snapshots,public.sd_game_active_adjustments,public.sd_game_results,public.sd_game_recaps,public.sd_game_plan_audit_logs,public.sd_game_plan_mutations to service_role;
revoke all on function public.sd_game_plan_snapshot(uuid),public.sd_validate_game_plan(uuid) from public,anon,authenticated;
grant execute on function public.sd_game_plan_snapshot(uuid),public.sd_validate_game_plan(uuid) to service_role;

comment on table public.sd_game_plans is 'Phase 12E current primary game plan linked one-to-one with a canonical Phase 12B game event; history lives in immutable snapshots.';
comment on table public.sd_game_batting_entries is 'Flexible ordered offensive participation. Slots have no hard maximum and are independent from defensive assignments.';
comment on table public.sd_game_defensive_assignments is 'Starting and inning defense, independent from batting participation. EH and DH are intentionally prohibited as positions.';
comment on table public.sd_game_plan_eligibility is 'Game-specific eligibility layered over, but not replacing, Phase 12C availability and participant snapshots.';
comment on table public.sd_game_results is 'Simple auditable game outcome only; not a scorebook, box score, standings, or player statistics system.';

-- Retry-safe, version-aware mutation boundary. Authorization is resolved by the
-- authenticated Edge Function; only service_role may execute this transaction.
create or replace function public.sd_apply_game_plan_mutation(
  p_organization_id uuid,
  p_event_id uuid,
  p_actor_id uuid,
  p_action text,
  p_request_id uuid,
  p_payload jsonb
) returns jsonb language plpgsql security definer set search_path='' as $$
declare evt public.sd_team_events%rowtype; plan public.sd_game_plans%rowtype;
  receipt public.sd_game_plan_mutations%rowtype; snap public.sd_game_plan_snapshots%rowtype;
  result_row public.sd_game_results%rowtype; target uuid; expected integer; claimed integer:=0;
  fingerprint text; response jsonb; previous jsonb; reason text; audit_action text:=p_action;
  v_lineup_mode text; started_id uuid; item jsonb; slot integer; operation_id uuid;
begin
  if p_payload is null or pg_catalog.jsonb_typeof(p_payload)<>'object' then raise exception using errcode='P0001',message='invalid_mutation_payload'; end if;
  fingerprint:=pg_catalog.encode(extensions.digest(pg_catalog.convert_to(pg_catalog.jsonb_build_object('event_id',p_event_id,'action',p_action,'payload',p_payload)::text,'UTF8'),'sha256'),'hex');
  insert into public.sd_game_plan_mutations(organization_id,request_id,actor_id,event_id,action,request_fingerprint)
    values(p_organization_id,p_request_id,p_actor_id,p_event_id,p_action,fingerprint) on conflict do nothing;
  get diagnostics claimed=row_count;
  if claimed=0 then
    select * into receipt from public.sd_game_plan_mutations where organization_id=p_organization_id and request_id=p_request_id for update;
    if receipt.actor_id<>p_actor_id or receipt.event_id<>p_event_id or receipt.action<>p_action or receipt.request_fingerprint<>fingerprint then raise exception using errcode='P0001',message='idempotency_mismatch'; end if;
    if receipt.status='completed' and receipt.response is not null then return receipt.response||pg_catalog.jsonb_build_object('replayed',true); end if;
    raise exception using errcode='P0001',message='mutation_in_progress';
  end if;
  select * into evt from public.sd_team_events where id=p_event_id and organization_id=p_organization_id and event_type='game' for update;
  if not found then raise exception using errcode='P0001',message='game_event_not_found'; end if;
  select * into plan from public.sd_game_plans where event_id=evt.id and organization_id=p_organization_id and is_primary and archived_at is null for update;

  if p_action in ('initialize_game_plan','duplicate_prior_game_plan') then
    if plan.id is null then
      insert into public.sd_game_plans(organization_id,season_id,team_id,event_id,event_operation_id,title,lineup_mode,created_by,updated_by)
        values(p_organization_id,evt.season_id,evt.team_id,evt.id,(select id from public.sd_event_operations where event_id=evt.id),pg_catalog.coalesce(nullif(pg_catalog.btrim(p_payload->>'title'),''),evt.title||' Game Plan'),pg_catalog.coalesce(nullif(p_payload->>'lineup_mode',''),'custom'),p_actor_id,p_actor_id) returning * into plan;
      insert into public.sd_game_plan_eligibility(game_plan_id,organization_id,player_id,status,source_participant_version,created_by,updated_by)
        select plan.id,p_organization_id,participant.user_id,
          case participant.availability_status when 'unavailable' then 'unavailable' when 'tentative' then 'tentative' when 'late' then 'late' when 'leaving_early' then 'leaving_early' else 'eligible' end,
          participant.version,p_actor_id,p_actor_id
        from public.sd_event_operation_participants participant join public.sd_event_operations operation on operation.id=participant.event_operation_id
        where operation.event_id=evt.id and participant.participant_type='player' and participant.expected
        on conflict(game_plan_id,player_id) do nothing;
    end if;
    if p_action='duplicate_prior_game_plan' then
      if plan.status not in ('draft','ready') then raise exception using errcode='P0001',message='draft_or_ready_game_plan_required'; end if;
      target:=(p_payload->>'source_plan_id')::uuid;
      if not exists(select 1 from public.sd_game_plans source where source.id=target and source.organization_id=p_organization_id and source.team_id=evt.team_id and source.published_version is not null) then raise exception using errcode='P0001',message='authorized_prior_game_plan_required'; end if;
      update public.sd_game_batting_entries set active=false,archived_at=pg_catalog.now(),version=version+1,updated_by=p_actor_id,updated_at=pg_catalog.now() where game_plan_id=plan.id and active;
      update public.sd_game_defensive_assignments set active=false,archived_at=pg_catalog.now(),version=version+1,updated_by=p_actor_id,updated_at=pg_catalog.now() where game_plan_id=plan.id and active;
      update public.sd_game_pitcher_catcher_plans set archived_at=pg_catalog.now(),version=version+1,updated_by=p_actor_id,updated_at=pg_catalog.now() where game_plan_id=plan.id and archived_at is null;
      update public.sd_game_plans destination set lineup_mode=source.lineup_mode,rule_profile_id=case when exists(select 1 from public.sd_game_rule_profiles r where r.id=source.rule_profile_id and r.active and (r.season_id is null or r.season_id=destination.season_id) and (r.team_id is null or r.team_id=destination.team_id) and (r.tournament_event_id is null or r.tournament_event_id::text=evt.metadata->>'tournament_event_id') and (r.event_id is null or r.event_id=destination.event_id)) then source.rule_profile_id else null end,scheduled_innings=source.scheduled_innings,internal_strategy_notes=source.internal_strategy_notes,version=destination.version+1,updated_by=p_actor_id,updated_at=pg_catalog.now() from public.sd_game_plans source where destination.id=plan.id and source.id=target returning destination.* into plan;
      insert into public.sd_game_batting_entries(game_plan_id,organization_id,player_id,batting_slot,offensive_role,role_label,starter,eligible,source,notes,created_by,updated_by)
        select plan.id,p_organization_id,b.player_id,b.batting_slot,b.offensive_role,b.role_label,b.starter,b.eligible,'prior_plan',b.notes,p_actor_id,p_actor_id from public.sd_game_batting_entries b where b.game_plan_id=target and b.active and exists(select 1 from public.sd_game_plan_eligibility e where e.game_plan_id=plan.id and e.player_id=b.player_id);
      insert into public.sd_game_defensive_assignments(game_plan_id,organization_id,player_id,inning_number,inning_half,position_code,position_label,assignment_type,starter,planned,notes,created_by,updated_by)
        select plan.id,p_organization_id,d.player_id,d.inning_number,d.inning_half,d.position_code,d.position_label,d.assignment_type,d.starter,d.planned,d.notes,p_actor_id,p_actor_id from public.sd_game_defensive_assignments d where d.game_plan_id=target and d.active and exists(select 1 from public.sd_game_plan_eligibility e where e.game_plan_id=plan.id and e.player_id=d.player_id);
      insert into public.sd_game_pitcher_catcher_plans(game_plan_id,organization_id,player_id,role_type,sequence_index,planned_start_inning,planned_end_inning,manual_pitch_limit,pairing_player_id,notes,status,created_by,updated_by)
        select plan.id,p_organization_id,p.player_id,p.role_type,p.sequence_index,p.planned_start_inning,p.planned_end_inning,p.manual_pitch_limit,p.pairing_player_id,p.notes,'planned',p_actor_id,p_actor_id from public.sd_game_pitcher_catcher_plans p where p.game_plan_id=target and p.archived_at is null and exists(select 1 from public.sd_game_plan_eligibility e where e.game_plan_id=plan.id and e.player_id=p.player_id);
    end if;
    response:=pg_catalog.jsonb_build_object('plan',pg_catalog.to_jsonb(plan),'initialized',plan.version=1,'duplicated',p_action='duplicate_prior_game_plan');
  elsif p_action in ('create_rule_profile','duplicate_rule_profile') then
    if nullif(p_payload->>'season_id','') is not null and not exists(select 1 from public.sd_seasons where id=(p_payload->>'season_id')::uuid and organization_id=p_organization_id) then raise exception using errcode='P0001',message='rule_profile_season_scope_mismatch'; end if;
    if nullif(p_payload->>'team_id','') is not null and not exists(select 1 from public.sd_teams where id=(p_payload->>'team_id')::uuid and org_id=p_organization_id) then raise exception using errcode='P0001',message='rule_profile_team_scope_mismatch'; end if;
    if nullif(p_payload->>'tournament_event_id','') is not null and not exists(select 1 from public.sd_team_events where id=(p_payload->>'tournament_event_id')::uuid and organization_id=p_organization_id and event_type='tournament') then raise exception using errcode='P0001',message='rule_profile_tournament_scope_mismatch'; end if;
    if nullif(p_payload->>'event_id','') is not null and not exists(select 1 from public.sd_team_events where id=(p_payload->>'event_id')::uuid and organization_id=p_organization_id and event_type='game') then raise exception using errcode='P0001',message='rule_profile_event_scope_mismatch'; end if;
    if p_action='duplicate_rule_profile' then
      target:=pg_catalog.coalesce(nullif(p_payload->>'source_rule_profile_id',''),nullif(p_payload->>'rule_profile_id',''))::uuid;
      if not exists(select 1 from public.sd_game_rule_profiles source where source.id=target and source.organization_id=p_organization_id and source.active) then raise exception using errcode='P0001',message='authorized_rule_profile_required'; end if;
      insert into public.sd_game_rule_profiles(organization_id,season_id,team_id,tournament_event_id,event_id,name,innings,minimum_batting_slots,maximum_batting_slots,continuous_batting_order_allowed,bat_entire_roster_allowed,dh_allowed,eh_allowed,maximum_eh,defensive_only_players_allowed,offensive_only_players_allowed,reentry_policy,courtesy_runner_policy,pitcher_reentry_policy,defensive_player_count,required_positions,custom_position_labels,notes,created_by,updated_by)
        select p_organization_id,case when p_payload?'season_id' then nullif(p_payload->>'season_id','')::uuid else source.season_id end,case when p_payload?'team_id' then nullif(p_payload->>'team_id','')::uuid else source.team_id end,case when p_payload?'tournament_event_id' then nullif(p_payload->>'tournament_event_id','')::uuid else source.tournament_event_id end,case when p_payload?'event_id' then nullif(p_payload->>'event_id','')::uuid else source.event_id end,pg_catalog.coalesce(nullif(pg_catalog.btrim(p_payload->>'name'),''),source.name||' Copy'),source.innings,source.minimum_batting_slots,source.maximum_batting_slots,source.continuous_batting_order_allowed,source.bat_entire_roster_allowed,source.dh_allowed,source.eh_allowed,source.maximum_eh,source.defensive_only_players_allowed,source.offensive_only_players_allowed,source.reentry_policy,source.courtesy_runner_policy,source.pitcher_reentry_policy,source.defensive_player_count,source.required_positions,source.custom_position_labels,source.notes,p_actor_id,p_actor_id from public.sd_game_rule_profiles source where source.id=target returning id into target;
    else
      insert into public.sd_game_rule_profiles(organization_id,season_id,team_id,tournament_event_id,event_id,name,innings,minimum_batting_slots,maximum_batting_slots,continuous_batting_order_allowed,bat_entire_roster_allowed,dh_allowed,eh_allowed,maximum_eh,defensive_only_players_allowed,offensive_only_players_allowed,reentry_policy,courtesy_runner_policy,pitcher_reentry_policy,defensive_player_count,required_positions,custom_position_labels,notes,created_by,updated_by)
        values(p_organization_id,nullif(p_payload->>'season_id','')::uuid,nullif(p_payload->>'team_id','')::uuid,nullif(p_payload->>'tournament_event_id','')::uuid,nullif(p_payload->>'event_id','')::uuid,pg_catalog.btrim(p_payload->>'name'),(p_payload->>'innings')::integer,(p_payload->>'minimum_batting_slots')::integer,(p_payload->>'maximum_batting_slots')::integer,(p_payload->>'continuous_batting_order_allowed')::boolean,(p_payload->>'bat_entire_roster_allowed')::boolean,(p_payload->>'dh_allowed')::boolean,(p_payload->>'eh_allowed')::boolean,(p_payload->>'maximum_eh')::integer,(p_payload->>'defensive_only_players_allowed')::boolean,(p_payload->>'offensive_only_players_allowed')::boolean,nullif(p_payload->>'reentry_policy',''),nullif(p_payload->>'courtesy_runner_policy',''),nullif(p_payload->>'pitcher_reentry_policy',''),(p_payload->>'defensive_player_count')::integer,pg_catalog.coalesce(array(select pg_catalog.jsonb_array_elements_text(p_payload->'required_positions')),'{}'::text[]),pg_catalog.coalesce(array(select pg_catalog.jsonb_array_elements_text(p_payload->'custom_position_labels')),'{}'::text[]),nullif(p_payload->>'notes',''),p_actor_id,p_actor_id) returning id into target;
    end if;
    response:=pg_catalog.jsonb_build_object('rule_profile_id',target);
  elsif p_action in ('update_rule_profile','archive_rule_profile') then
    target:=(p_payload->>'rule_profile_id')::uuid; expected:=(p_payload->>'expected_version')::integer;
    select pg_catalog.to_jsonb(r) into previous from public.sd_game_rule_profiles r where id=target and organization_id=p_organization_id;
    update public.sd_game_rule_profiles set name=pg_catalog.coalesce(nullif(pg_catalog.btrim(p_payload->>'name'),''),name),innings=case when p_payload?'innings' then (p_payload->>'innings')::integer else innings end,minimum_batting_slots=case when p_payload?'minimum_batting_slots' then (p_payload->>'minimum_batting_slots')::integer else minimum_batting_slots end,maximum_batting_slots=case when p_payload?'maximum_batting_slots' then (p_payload->>'maximum_batting_slots')::integer else maximum_batting_slots end,continuous_batting_order_allowed=case when p_payload?'continuous_batting_order_allowed' then (p_payload->>'continuous_batting_order_allowed')::boolean else continuous_batting_order_allowed end,bat_entire_roster_allowed=case when p_payload?'bat_entire_roster_allowed' then (p_payload->>'bat_entire_roster_allowed')::boolean else bat_entire_roster_allowed end,dh_allowed=case when p_payload?'dh_allowed' then (p_payload->>'dh_allowed')::boolean else dh_allowed end,eh_allowed=case when p_payload?'eh_allowed' then (p_payload->>'eh_allowed')::boolean else eh_allowed end,maximum_eh=case when p_payload?'maximum_eh' then (p_payload->>'maximum_eh')::integer else maximum_eh end,defensive_only_players_allowed=case when p_payload?'defensive_only_players_allowed' then (p_payload->>'defensive_only_players_allowed')::boolean else defensive_only_players_allowed end,offensive_only_players_allowed=case when p_payload?'offensive_only_players_allowed' then (p_payload->>'offensive_only_players_allowed')::boolean else offensive_only_players_allowed end,defensive_player_count=case when p_payload?'defensive_player_count' then (p_payload->>'defensive_player_count')::integer else defensive_player_count end,required_positions=case when p_payload?'required_positions' then array(select pg_catalog.jsonb_array_elements_text(p_payload->'required_positions')) else required_positions end,custom_position_labels=case when p_payload?'custom_position_labels' then array(select pg_catalog.jsonb_array_elements_text(p_payload->'custom_position_labels')) else custom_position_labels end,notes=case when p_payload?'notes' then nullif(p_payload->>'notes','') else notes end,active=case when p_action='archive_rule_profile' then false else active end,archived_at=case when p_action='archive_rule_profile' then pg_catalog.now() else archived_at end,version=version+1,updated_by=p_actor_id,updated_at=pg_catalog.now() where id=target and organization_id=p_organization_id and version=expected;
    if not found then raise exception using errcode='P0001',message='stale_or_missing_rule_profile'; end if;
    response:=pg_catalog.jsonb_build_object('rule_profile_id',target);
  else
    if plan.id is null then raise exception using errcode='P0001',message='game_plan_not_found'; end if;
    if plan.status='active' and p_action in ('update_game_plan','apply_rule_profile','initialize_standard_nine','initialize_dh','initialize_one_eh','initialize_multiple_eh','initialize_continuous_order','initialize_bat_entire_roster','clear_batting_order','reconcile_batting_order','add_batting_entry','update_batting_entry','remove_batting_entry','reorder_batting_order','update_eligibility','assign_defensive_position','set_starting_defense','remove_defensive_assignment','copy_defensive_inning','apply_alignment_to_innings','clear_defensive_inning','reconcile_defensive_plan','assign_starting_pitcher','add_relief_pitcher','reorder_pitchers','assign_starting_catcher','assign_backup_catcher','assign_pitcher_catcher_pair','update_pitcher_catcher_plan','remove_pitcher_catcher_plan') then raise exception using errcode='P0001',message='active_adjustment_required'; end if;
    if p_action='update_game_plan' then
      expected:=(p_payload->>'expected_version')::integer; previous:=pg_catalog.to_jsonb(plan);
      update public.sd_game_plans set title=pg_catalog.coalesce(nullif(pg_catalog.btrim(p_payload->>'title'),''),title),lineup_mode=pg_catalog.coalesce(nullif(p_payload->>'lineup_mode',''),lineup_mode),rule_profile_id=case when p_payload?'rule_profile_id' then nullif(p_payload->>'rule_profile_id','')::uuid else rule_profile_id end,scheduled_innings=case when p_payload?'scheduled_innings' then (p_payload->>'scheduled_innings')::integer else scheduled_innings end,batting_order_locked=case when p_payload?'batting_order_locked' then (p_payload->>'batting_order_locked')::boolean else batting_order_locked end,defense_plan_locked=case when p_payload?'defense_plan_locked' then (p_payload->>'defense_plan_locked')::boolean else defense_plan_locked end,internal_strategy_notes=case when p_payload?'internal_strategy_notes' then nullif(p_payload->>'internal_strategy_notes','') else internal_strategy_notes end,player_reminders=case when p_payload?'player_reminders' then nullif(p_payload->>'player_reminders','') else player_reminders end,parent_reminders=case when p_payload?'parent_reminders' then nullif(p_payload->>'parent_reminders','') else parent_reminders end,status=case when p_payload->>'status'='ready' then 'ready' else status end,version=version+1,updated_by=p_actor_id,updated_at=pg_catalog.now() where id=plan.id and version=expected and status in ('draft','ready','published');
      if not found then raise exception using errcode='P0001',message='stale_or_locked_game_plan'; end if; select * into plan from public.sd_game_plans where id=plan.id; response:=pg_catalog.jsonb_build_object('plan',pg_catalog.to_jsonb(plan));
    elsif p_action='apply_rule_profile' then
      target:=(p_payload->>'rule_profile_id')::uuid; expected:=(p_payload->>'expected_version')::integer;
      if not exists(select 1 from public.sd_game_rule_profiles r where r.id=target and r.organization_id=p_organization_id and r.active and (r.season_id is null or r.season_id=plan.season_id) and (r.team_id is null or r.team_id=plan.team_id) and (r.tournament_event_id is null or r.tournament_event_id::text=evt.metadata->>'tournament_event_id') and (r.event_id is null or r.event_id=plan.event_id)) then raise exception using errcode='P0001',message='rule_profile_scope_mismatch'; end if;
      update public.sd_game_plans set rule_profile_id=target,version=version+1,updated_by=p_actor_id,updated_at=pg_catalog.now() where id=plan.id and version=expected returning * into plan; if not found then raise exception using errcode='P0001',message='stale_version'; end if; response:=pg_catalog.jsonb_build_object('plan',pg_catalog.to_jsonb(plan));
    elsif p_action in ('initialize_standard_nine','initialize_dh','initialize_one_eh','initialize_multiple_eh','initialize_continuous_order','initialize_bat_entire_roster','clear_batting_order','reconcile_batting_order') then
      expected:=(p_payload->>'expected_version')::integer; if plan.version<>expected then raise exception using errcode='P0001',message='stale_version'; end if;
      if plan.status='active' then raise exception using errcode='P0001',message='active_adjustment_required'; end if;
      update public.sd_game_batting_entries set active=false,archived_at=pg_catalog.now(),version=version+1,updated_by=p_actor_id,updated_at=pg_catalog.now() where game_plan_id=plan.id and active;
      v_lineup_mode:=case p_action when 'initialize_standard_nine' then 'standard_nine' when 'initialize_dh' then 'standard_nine_with_dh' when 'initialize_one_eh' then 'standard_nine_with_one_eh' when 'initialize_multiple_eh' then 'standard_nine_with_multiple_eh' when 'initialize_continuous_order' then 'continuous_batting_order' when 'initialize_bat_entire_roster' then 'bat_entire_available_roster' else plan.lineup_mode end;
      if p_action<>'clear_batting_order' then
        slot:=0;
        for item in select value from pg_catalog.jsonb_array_elements(pg_catalog.coalesce(p_payload->'entries','[]'::jsonb)) loop
          slot:=slot+1;
          insert into public.sd_game_batting_entries(game_plan_id,organization_id,player_id,batting_slot,offensive_role,role_label,source,notes,created_by,updated_by)
            values(plan.id,p_organization_id,(item->>'player_id')::uuid,pg_catalog.coalesce((item->>'batting_slot')::integer,slot),pg_catalog.coalesce(nullif(item->>'offensive_role',''),'hitter'),nullif(item->>'role_label',''),case when p_action='initialize_bat_entire_roster' then 'roster' else 'manual' end,nullif(item->>'notes',''),p_actor_id,p_actor_id);
        end loop;
        if p_action='initialize_bat_entire_roster' and slot=0 then
          insert into public.sd_game_batting_entries(game_plan_id,organization_id,player_id,batting_slot,offensive_role,source,created_by,updated_by)
            select plan.id,p_organization_id,e.player_id,(row_number() over(order by e.created_at,e.player_id))::integer,'hitter','roster',p_actor_id,p_actor_id from public.sd_game_plan_eligibility e where e.game_plan_id=plan.id and e.status in ('eligible','tentative','late','leaving_early','pending_confirmation') order by e.created_at,e.player_id;
        end if;
      end if;
      update public.sd_game_plans set lineup_mode=v_lineup_mode,version=version+1,updated_by=p_actor_id,updated_at=pg_catalog.now() where id=plan.id returning * into plan;
      response:=pg_catalog.jsonb_build_object('plan',pg_catalog.to_jsonb(plan),'batting_order',(select pg_catalog.coalesce(pg_catalog.jsonb_agg(pg_catalog.to_jsonb(b) order by batting_slot),'[]'::jsonb) from public.sd_game_batting_entries b where b.game_plan_id=plan.id and b.active));
    elsif p_action='add_batting_entry' then
      if plan.batting_order_locked and plan.status<>'active' then raise exception using errcode='P0001',message='batting_order_locked'; end if;
      insert into public.sd_game_batting_entries(game_plan_id,organization_id,player_id,batting_slot,offensive_role,role_label,starter,eligible,source,notes,created_by,updated_by)
        values(plan.id,p_organization_id,(p_payload->>'player_id')::uuid,(p_payload->>'batting_slot')::integer,pg_catalog.coalesce(nullif(p_payload->>'offensive_role',''),'hitter'),nullif(p_payload->>'role_label',''),pg_catalog.coalesce((p_payload->>'starter')::boolean,true),pg_catalog.coalesce((p_payload->>'eligible')::boolean,true),case when plan.status='active' then 'active_adjustment' else 'manual' end,nullif(p_payload->>'notes',''),p_actor_id,p_actor_id) returning id into target;
      update public.sd_game_plans set version=version+1,updated_by=p_actor_id,updated_at=pg_catalog.now() where id=plan.id returning * into plan; response:=pg_catalog.jsonb_build_object('plan',pg_catalog.to_jsonb(plan),'batting_entry_id',target);
    elsif p_action='update_batting_entry' then
      target:=(p_payload->>'entry_id')::uuid; expected:=(p_payload->>'entry_version')::integer; select pg_catalog.to_jsonb(b) into previous from public.sd_game_batting_entries b where id=target and game_plan_id=plan.id;
      update public.sd_game_batting_entries set batting_slot=case when p_payload?'batting_slot' then (p_payload->>'batting_slot')::integer else batting_slot end,offensive_role=pg_catalog.coalesce(nullif(p_payload->>'offensive_role',''),offensive_role),role_label=case when p_payload?'role_label' then nullif(p_payload->>'role_label','') else role_label end,starter=case when p_payload?'starter' then (p_payload->>'starter')::boolean else starter end,eligible=case when p_payload?'eligible' then (p_payload->>'eligible')::boolean else eligible end,notes=case when p_payload?'notes' then nullif(p_payload->>'notes','') else notes end,version=version+1,updated_by=p_actor_id,updated_at=pg_catalog.now() where id=target and game_plan_id=plan.id and version=expected and active;
      if not found then raise exception using errcode='P0001',message='stale_or_missing_batting_entry'; end if; update public.sd_game_plans set version=version+1,updated_by=p_actor_id,updated_at=pg_catalog.now() where id=plan.id returning * into plan; response:=pg_catalog.jsonb_build_object('plan',pg_catalog.to_jsonb(plan),'batting_entry_id',target);
    elsif p_action='remove_batting_entry' then
      target:=(p_payload->>'entry_id')::uuid; expected:=(p_payload->>'entry_version')::integer; select pg_catalog.to_jsonb(b) into previous from public.sd_game_batting_entries b where id=target and game_plan_id=plan.id;
      update public.sd_game_batting_entries set active=false,archived_at=pg_catalog.now(),version=version+1,updated_by=p_actor_id,updated_at=pg_catalog.now() where id=target and game_plan_id=plan.id and version=expected and active; if not found then raise exception using errcode='P0001',message='stale_or_missing_batting_entry'; end if;
      update public.sd_game_plans set version=version+1,updated_by=p_actor_id,updated_at=pg_catalog.now() where id=plan.id returning * into plan; response:=pg_catalog.jsonb_build_object('plan',pg_catalog.to_jsonb(plan),'removed_entry_id',target);
    elsif p_action='reorder_batting_order' then
      expected:=(p_payload->>'expected_version')::integer; if plan.version<>expected then raise exception using errcode='P0001',message='stale_version'; end if;
      for item in select value from pg_catalog.jsonb_array_elements(p_payload->'entries') loop update public.sd_game_batting_entries set batting_slot=(item->>'batting_slot')::integer,version=version+1,updated_by=p_actor_id,updated_at=pg_catalog.now() where id=(item->>'id')::uuid and game_plan_id=plan.id and active; end loop;
      update public.sd_game_plans set version=version+1,updated_by=p_actor_id,updated_at=pg_catalog.now() where id=plan.id returning * into plan; response:=pg_catalog.jsonb_build_object('plan',pg_catalog.to_jsonb(plan));
    elsif p_action='update_eligibility' then
      target:=(p_payload->>'player_id')::uuid; reason:=nullif(pg_catalog.btrim(p_payload->>'reason'),'');
      if p_payload->>'status' in ('coach_excluded','rostered_not_dressing') and reason is null then raise exception using errcode='P0001',message='exclusion_reason_required'; end if;
      insert into public.sd_game_plan_eligibility(game_plan_id,organization_id,player_id,status,exclusion_reason,created_by,updated_by) values(plan.id,p_organization_id,target,p_payload->>'status',reason,p_actor_id,p_actor_id)
        on conflict(game_plan_id,player_id) do update set status=excluded.status,exclusion_reason=excluded.exclusion_reason,version=sd_game_plan_eligibility.version+1,updated_by=p_actor_id,updated_at=pg_catalog.now();
      update public.sd_game_plans set version=version+1,updated_by=p_actor_id,updated_at=pg_catalog.now() where id=plan.id returning * into plan; response:=pg_catalog.jsonb_build_object('plan',pg_catalog.to_jsonb(plan),'player_id',target);
    elsif p_action in ('assign_defensive_position','set_starting_defense') then
      insert into public.sd_game_defensive_assignments(game_plan_id,organization_id,player_id,inning_number,inning_half,position_code,position_label,assignment_type,starter,notes,created_by,updated_by)
        values(plan.id,p_organization_id,(p_payload->>'player_id')::uuid,pg_catalog.coalesce((p_payload->>'inning_number')::integer,0),pg_catalog.coalesce(nullif(p_payload->>'inning_half',''),'defense'),pg_catalog.upper(p_payload->>'position_code'),nullif(p_payload->>'position_label',''),pg_catalog.coalesce(nullif(p_payload->>'assignment_type',''),case when pg_catalog.coalesce((p_payload->>'inning_number')::integer,0)=0 then 'starter' else 'planned' end),pg_catalog.coalesce((p_payload->>'starter')::boolean,pg_catalog.coalesce((p_payload->>'inning_number')::integer,0)=0),nullif(p_payload->>'notes',''),p_actor_id,p_actor_id) returning id into target;
      update public.sd_game_plans set version=version+1,updated_by=p_actor_id,updated_at=pg_catalog.now() where id=plan.id returning * into plan; response:=pg_catalog.jsonb_build_object('plan',pg_catalog.to_jsonb(plan),'defensive_assignment_id',target);
    elsif p_action='remove_defensive_assignment' then
      target:=(p_payload->>'assignment_id')::uuid; expected:=(p_payload->>'assignment_version')::integer; select pg_catalog.to_jsonb(d) into previous from public.sd_game_defensive_assignments d where id=target and game_plan_id=plan.id;
      update public.sd_game_defensive_assignments set active=false,archived_at=pg_catalog.now(),version=version+1,updated_by=p_actor_id,updated_at=pg_catalog.now() where id=target and game_plan_id=plan.id and version=expected and active; if not found then raise exception using errcode='P0001',message='stale_or_missing_defensive_assignment'; end if;
      update public.sd_game_plans set version=version+1,updated_by=p_actor_id,updated_at=pg_catalog.now() where id=plan.id returning * into plan; response:=pg_catalog.jsonb_build_object('plan',pg_catalog.to_jsonb(plan),'removed_assignment_id',target);
    elsif p_action in ('copy_defensive_inning','apply_alignment_to_innings') then
      expected:=(p_payload->>'expected_version')::integer; if plan.version<>expected then raise exception using errcode='P0001',message='stale_version'; end if;
      for slot in select value::integer from pg_catalog.jsonb_array_elements_text(p_payload->'target_innings') loop
        update public.sd_game_defensive_assignments set active=false,archived_at=pg_catalog.now(),version=version+1,updated_by=p_actor_id,updated_at=pg_catalog.now() where game_plan_id=plan.id and inning_number=slot and active;
        insert into public.sd_game_defensive_assignments(game_plan_id,organization_id,player_id,inning_number,inning_half,position_code,position_label,assignment_type,starter,planned,notes,created_by,updated_by)
          select plan.id,p_organization_id,d.player_id,slot,d.inning_half,d.position_code,d.position_label,'planned',false,true,d.notes,p_actor_id,p_actor_id from public.sd_game_defensive_assignments d where d.game_plan_id=plan.id and d.inning_number=(p_payload->>'source_inning')::integer and d.active;
      end loop;
      update public.sd_game_plans set version=version+1,updated_by=p_actor_id,updated_at=pg_catalog.now() where id=plan.id returning * into plan; response:=pg_catalog.jsonb_build_object('plan',pg_catalog.to_jsonb(plan));
    elsif p_action='clear_defensive_inning' then
      update public.sd_game_defensive_assignments set active=false,archived_at=pg_catalog.now(),version=version+1,updated_by=p_actor_id,updated_at=pg_catalog.now() where game_plan_id=plan.id and inning_number=(p_payload->>'inning_number')::integer and active;
      update public.sd_game_plans set version=version+1,updated_by=p_actor_id,updated_at=pg_catalog.now() where id=plan.id returning * into plan; response:=pg_catalog.jsonb_build_object('plan',pg_catalog.to_jsonb(plan));
    elsif p_action='reconcile_defensive_plan' then
      expected:=(p_payload->>'expected_version')::integer; if plan.version<>expected then raise exception using errcode='P0001',message='stale_version'; end if;
      update public.sd_game_defensive_assignments set active=false,archived_at=pg_catalog.now(),version=version+1,updated_by=p_actor_id,updated_at=pg_catalog.now() where game_plan_id=plan.id and active and not exists(select 1 from public.sd_game_plan_eligibility e where e.game_plan_id=plan.id and e.player_id=sd_game_defensive_assignments.player_id);
      update public.sd_game_plans set version=version+1,updated_by=p_actor_id,updated_at=pg_catalog.now() where id=plan.id returning * into plan; response:=pg_catalog.jsonb_build_object('plan',pg_catalog.to_jsonb(plan));
    elsif p_action='reorder_pitchers' then
      expected:=(p_payload->>'expected_version')::integer; if plan.version<>expected then raise exception using errcode='P0001',message='stale_version'; end if;
      for item in select value from pg_catalog.jsonb_array_elements(p_payload->'entries') loop update public.sd_game_pitcher_catcher_plans set sequence_index=(item->>'sequence_index')::integer,version=version+1,updated_by=p_actor_id,updated_at=pg_catalog.now() where id=(item->>'id')::uuid and game_plan_id=plan.id and role_type in ('starting_pitcher','relief_pitcher','emergency_pitcher') and archived_at is null; end loop;
      update public.sd_game_plans set version=version+1,updated_by=p_actor_id,updated_at=pg_catalog.now() where id=plan.id returning * into plan; response:=pg_catalog.jsonb_build_object('plan',pg_catalog.to_jsonb(plan));
    elsif p_action in ('assign_starting_pitcher','add_relief_pitcher','assign_starting_catcher','assign_backup_catcher','assign_pitcher_catcher_pair','update_pitcher_catcher_plan') then
      if p_action='update_pitcher_catcher_plan' then
        target:=(p_payload->>'plan_entry_id')::uuid; expected:=(p_payload->>'entry_version')::integer;
        update public.sd_game_pitcher_catcher_plans set player_id=case when p_payload?'player_id' then (p_payload->>'player_id')::uuid else player_id end,role_type=pg_catalog.coalesce(nullif(p_payload->>'role_type',''),role_type),sequence_index=case when p_payload?'sequence_index' then (p_payload->>'sequence_index')::integer else sequence_index end,planned_start_inning=case when p_payload?'planned_start_inning' then (p_payload->>'planned_start_inning')::integer else planned_start_inning end,planned_end_inning=case when p_payload?'planned_end_inning' then (p_payload->>'planned_end_inning')::integer else planned_end_inning end,manual_pitch_limit=case when p_payload?'manual_pitch_limit' then (p_payload->>'manual_pitch_limit')::integer else manual_pitch_limit end,pairing_player_id=case when p_payload?'pairing_player_id' then nullif(p_payload->>'pairing_player_id','')::uuid else pairing_player_id end,notes=case when p_payload?'notes' then nullif(p_payload->>'notes','') else notes end,status=pg_catalog.coalesce(nullif(p_payload->>'status',''),status),version=version+1,updated_by=p_actor_id,updated_at=pg_catalog.now() where id=target and game_plan_id=plan.id and version=expected and archived_at is null;
        if not found then raise exception using errcode='P0001',message='stale_or_missing_pitcher_catcher_plan'; end if;
      else
        insert into public.sd_game_pitcher_catcher_plans(game_plan_id,organization_id,player_id,role_type,sequence_index,planned_start_inning,planned_end_inning,manual_pitch_limit,pairing_player_id,notes,status,created_by,updated_by)
          values(plan.id,p_organization_id,(p_payload->>'player_id')::uuid,case p_action when 'assign_starting_pitcher' then 'starting_pitcher' when 'add_relief_pitcher' then 'relief_pitcher' when 'assign_starting_catcher' then 'starting_catcher' when 'assign_backup_catcher' then 'backup_catcher' else pg_catalog.coalesce(nullif(p_payload->>'role_type',''),'relief_pitcher') end,pg_catalog.coalesce((p_payload->>'sequence_index')::integer,0),(p_payload->>'planned_start_inning')::integer,(p_payload->>'planned_end_inning')::integer,(p_payload->>'manual_pitch_limit')::integer,nullif(p_payload->>'pairing_player_id','')::uuid,nullif(p_payload->>'notes',''),pg_catalog.coalesce(nullif(p_payload->>'status',''),'planned'),p_actor_id,p_actor_id) returning id into target;
      end if;
      update public.sd_game_plans set version=version+1,updated_by=p_actor_id,updated_at=pg_catalog.now() where id=plan.id returning * into plan; response:=pg_catalog.jsonb_build_object('plan',pg_catalog.to_jsonb(plan),'pitcher_catcher_id',target);
    elsif p_action='remove_pitcher_catcher_plan' then
      target:=(p_payload->>'plan_entry_id')::uuid; expected:=(p_payload->>'entry_version')::integer;
      update public.sd_game_pitcher_catcher_plans set archived_at=pg_catalog.now(),version=version+1,updated_by=p_actor_id,updated_at=pg_catalog.now() where id=target and game_plan_id=plan.id and version=expected and archived_at is null; if not found then raise exception using errcode='P0001',message='stale_or_missing_pitcher_catcher_plan'; end if;
      update public.sd_game_plans set version=version+1,updated_by=p_actor_id,updated_at=pg_catalog.now() where id=plan.id returning * into plan; response:=pg_catalog.jsonb_build_object('plan',pg_catalog.to_jsonb(plan));
    elsif p_action in ('assign_game_staff','update_game_staff') then
      if not exists(select 1 from public.sd_coach_team_assignments a where a.organization_id=p_organization_id and (a.team_id=plan.team_id or a.organization_wide_access) and a.coach_id=(p_payload->>'staff_user_id')::uuid and a.active and a.ended_at is null) then raise exception using errcode='P0001',message='authorized_team_staff_required'; end if;
      if p_action='update_game_staff' then
      target:=(p_payload->>'staff_assignment_id')::uuid; expected:=(p_payload->>'assignment_version')::integer;
      update public.sd_game_staff_assignments set staff_user_id=(p_payload->>'staff_user_id')::uuid,responsibility_code=pg_catalog.coalesce(nullif(p_payload->>'responsibility_code',''),responsibility_code),responsibility_label=case when p_payload?'responsibility_label' then nullif(p_payload->>'responsibility_label','') else responsibility_label end,notes=case when p_payload?'notes' then nullif(p_payload->>'notes','') else notes end,version=version+1,updated_by=p_actor_id,updated_at=pg_catalog.now() where id=target and game_plan_id=plan.id and version=expected and active;
      if not found then raise exception using errcode='P0001',message='stale_or_missing_staff_assignment'; end if;
      else
      insert into public.sd_game_staff_assignments(game_plan_id,organization_id,staff_user_id,responsibility_code,responsibility_label,notes,created_by,updated_by)
        values(plan.id,p_organization_id,(p_payload->>'staff_user_id')::uuid,p_payload->>'responsibility_code',nullif(p_payload->>'responsibility_label',''),nullif(p_payload->>'notes',''),p_actor_id,p_actor_id) returning id into target;
      end if;
      update public.sd_game_plans set version=version+1,updated_by=p_actor_id,updated_at=pg_catalog.now() where id=plan.id returning * into plan; response:=pg_catalog.jsonb_build_object('plan',pg_catalog.to_jsonb(plan),'staff_assignment_id',target);
    elsif p_action='remove_game_staff' then
      target:=(p_payload->>'staff_assignment_id')::uuid; expected:=(p_payload->>'assignment_version')::integer;
      update public.sd_game_staff_assignments set active=false,archived_at=pg_catalog.now(),version=version+1,updated_by=p_actor_id,updated_at=pg_catalog.now() where id=target and game_plan_id=plan.id and version=expected and active; if not found then raise exception using errcode='P0001',message='stale_or_missing_staff_assignment'; end if;
      update public.sd_game_plans set version=version+1,updated_by=p_actor_id,updated_at=pg_catalog.now() where id=plan.id returning * into plan; response:=pg_catalog.jsonb_build_object('plan',pg_catalog.to_jsonb(plan));
    elsif p_action='publish_game_plan' then
      if pg_catalog.jsonb_array_length(public.sd_validate_game_plan(plan.id)->'blocking_errors')>0 then raise exception using errcode='P0001',message='game_plan_validation_failed'; end if;
      insert into public.sd_game_plan_snapshots(game_plan_id,organization_id,event_operation_id,snapshot_type,plan_version,snapshot,reason,created_by)
        values(plan.id,p_organization_id,plan.event_operation_id,'published',plan.version,public.sd_game_plan_snapshot(plan.id),nullif(p_payload->>'warning_acknowledgement',''),p_actor_id)
        on conflict(game_plan_id,snapshot_type,plan_version) do update set snapshot=excluded.snapshot,reason=excluded.reason returning * into snap;
      update public.sd_game_plans set status='published',published_version=version,published_at=pg_catalog.now(),published_by=p_actor_id,current_snapshot_id=snap.id,updated_by=p_actor_id,updated_at=pg_catalog.now() where id=plan.id returning * into plan;
      insert into public.sd_team_event_notification_intents(organization_id,team_id,event_id,event_operation_id,intent_type,deduplication_key,payload,created_by) values(p_organization_id,plan.team_id,plan.event_id,plan.event_operation_id,'game_plan_published',p_request_id::text||':'||plan.id::text||':published',pg_catalog.jsonb_build_object('plan_id',plan.id,'version',plan.version),p_actor_id);
      response:=pg_catalog.jsonb_build_object('plan',pg_catalog.to_jsonb(plan),'snapshot',pg_catalog.to_jsonb(snap),'validation',public.sd_validate_game_plan(plan.id));
    elsif p_action='capture_started_game_snapshot' then
      if plan.status<>'published' then raise exception using errcode='P0001',message='published_game_plan_required'; end if;
      select id into operation_id from public.sd_event_operations where event_id=plan.event_id and status in ('ready','in_progress','paused'); if operation_id is null then raise exception using errcode='P0001',message='event_operation_not_ready'; end if;
      insert into public.sd_game_plan_snapshots(game_plan_id,organization_id,event_operation_id,snapshot_type,plan_version,snapshot,created_by)
        select plan.id,p_organization_id,operation_id,'started',published.plan_version,published.snapshot,p_actor_id from public.sd_game_plan_snapshots published where published.game_plan_id=plan.id and published.snapshot_type='published' and published.plan_version=plan.published_version returning * into snap;
      update public.sd_game_plans set status='active',event_operation_id=operation_id,current_snapshot_id=snap.id,updated_by=p_actor_id,updated_at=pg_catalog.now() where id=plan.id returning * into plan;
      insert into public.sd_team_event_notification_intents(organization_id,team_id,event_id,event_operation_id,intent_type,deduplication_key,payload,created_by) values(p_organization_id,plan.team_id,plan.event_id,operation_id,'game_day_started',p_request_id::text||':'||plan.id::text||':started','{}'::jsonb,p_actor_id);
      response:=pg_catalog.jsonb_build_object('plan',pg_catalog.to_jsonb(plan),'started_snapshot',pg_catalog.to_jsonb(snap));
    elsif p_action in ('apply_active_lineup_adjustment','apply_active_defense_adjustment','apply_active_pitcher_adjustment','apply_active_eligibility_adjustment') then
      reason:=nullif(pg_catalog.btrim(p_payload->>'reason'),''); if reason is null then raise exception using errcode='P0001',message='active_adjustment_reason_required'; end if; if plan.status<>'active' then raise exception using errcode='P0001',message='active_game_plan_required'; end if;
      select id into started_id from public.sd_game_plan_snapshots where game_plan_id=plan.id and snapshot_type='started' order by created_at desc limit 1;
      insert into public.sd_game_active_adjustments(game_plan_id,started_snapshot_id,adjustment_type,target_id,previous_value,new_value,reason,actor_id)
        values(plan.id,started_id,case p_action when 'apply_active_lineup_adjustment' then 'lineup' when 'apply_active_defense_adjustment' then 'defense' when 'apply_active_pitcher_adjustment' then 'pitcher_catcher' else 'eligibility' end,nullif(p_payload->>'target_id','')::uuid,p_payload->'previous_value',pg_catalog.coalesce(p_payload->'new_value','{}'::jsonb),reason,p_actor_id) returning id into target;
      update public.sd_game_plans set version=version+1,updated_by=p_actor_id,updated_at=pg_catalog.now() where id=plan.id returning * into plan; response:=pg_catalog.jsonb_build_object('plan',pg_catalog.to_jsonb(plan),'adjustment_id',target);
    elsif p_action='record_game_result' then
      reason:=nullif(pg_catalog.btrim(p_payload->>'correction_reason'),''); select * into result_row from public.sd_game_results where game_plan_id=plan.id for update; previous:=pg_catalog.to_jsonb(result_row);
      if result_row.id is not null and plan.status='completed' and reason is null then raise exception using errcode='P0001',message='result_correction_reason_required'; end if;
      insert into public.sd_game_results(game_plan_id,organization_id,team_score,opponent_score,outcome,innings_played,ended_early,end_reason,result_status,result_notes,recorded_by,recorded_at)
        values(plan.id,p_organization_id,(p_payload->>'team_score')::integer,(p_payload->>'opponent_score')::integer,pg_catalog.coalesce(nullif(p_payload->>'outcome',''),'unknown'),(p_payload->>'innings_played')::integer,pg_catalog.coalesce((p_payload->>'ended_early')::boolean,false),nullif(p_payload->>'end_reason',''),case when result_row.id is null then 'recorded' else 'corrected' end,nullif(p_payload->>'result_notes',''),p_actor_id,pg_catalog.now())
        on conflict(game_plan_id) do update set team_score=excluded.team_score,opponent_score=excluded.opponent_score,outcome=excluded.outcome,innings_played=excluded.innings_played,ended_early=excluded.ended_early,end_reason=excluded.end_reason,result_status='corrected',result_notes=excluded.result_notes,recorded_by=p_actor_id,recorded_at=pg_catalog.now(),version=sd_game_results.version+1,updated_at=pg_catalog.now() returning * into result_row;
      update public.sd_team_event_games set home_score=case when venue_side='home' then result_row.team_score else result_row.opponent_score end,away_score=case when venue_side='away' then result_row.team_score else result_row.opponent_score end where event_id=plan.event_id;
      update public.sd_game_plans set version=version+1,updated_by=p_actor_id,updated_at=pg_catalog.now() where id=plan.id returning * into plan;
      response:=pg_catalog.jsonb_build_object('plan',pg_catalog.to_jsonb(plan),'result',pg_catalog.to_jsonb(result_row));
    elsif p_action='add_game_recap' then
      insert into public.sd_game_recaps(game_plan_id,organization_id,visibility,subject_player_id,body,follow_up_items,published_at,created_by,updated_by)
        values(plan.id,p_organization_id,p_payload->>'visibility',nullif(p_payload->>'subject_player_id','')::uuid,pg_catalog.btrim(p_payload->>'body'),pg_catalog.coalesce(array(select pg_catalog.jsonb_array_elements_text(p_payload->'follow_up_items')),'{}'::text[]),case when (p_payload->>'publish')::boolean then pg_catalog.now() else null end,p_actor_id,p_actor_id) returning id into target;
      update public.sd_game_plans set version=version+1,updated_by=p_actor_id,updated_at=pg_catalog.now() where id=plan.id returning * into plan;
      response:=pg_catalog.jsonb_build_object('plan',pg_catalog.to_jsonb(plan),'recap_id',target);
    elsif p_action in ('capture_completion_snapshot','complete_game_operation') then
      select * into result_row from public.sd_game_results where game_plan_id=plan.id;
      insert into public.sd_game_plan_snapshots(game_plan_id,organization_id,event_operation_id,snapshot_type,plan_version,snapshot,reason,created_by)
        values(plan.id,p_organization_id,plan.event_operation_id,'completed',plan.version,public.sd_game_plan_snapshot(plan.id)||pg_catalog.jsonb_build_object('adjustments',(select pg_catalog.coalesce(pg_catalog.jsonb_agg(pg_catalog.to_jsonb(a) order by created_at),'[]'::jsonb) from public.sd_game_active_adjustments a where a.game_plan_id=plan.id)),nullif(p_payload->>'completion_notes',''),p_actor_id)
        on conflict(game_plan_id,snapshot_type,plan_version) do update set snapshot=excluded.snapshot,reason=excluded.reason returning * into snap;
      update public.sd_game_plans set status='completed',current_snapshot_id=snap.id,updated_by=p_actor_id,updated_at=pg_catalog.now() where id=plan.id returning * into plan;
      update public.sd_team_event_games set game_status='final' where event_id=plan.event_id;
      insert into public.sd_team_event_notification_intents(organization_id,team_id,event_id,event_operation_id,intent_type,deduplication_key,payload,created_by) values(p_organization_id,plan.team_id,plan.event_id,plan.event_operation_id,'game_completed',p_request_id::text||':'||plan.id::text||':completed',pg_catalog.jsonb_build_object('result_id',result_row.id),p_actor_id);
      response:=pg_catalog.jsonb_build_object('plan',pg_catalog.to_jsonb(plan),'completion_snapshot',pg_catalog.to_jsonb(snap));
    elsif p_action='reopen_completed_game' then
      reason:=nullif(pg_catalog.btrim(p_payload->>'reason'),''); if reason is null then raise exception using errcode='P0001',message='reopen_reason_required'; end if; if plan.status<>'completed' then raise exception using errcode='P0001',message='completed_game_required'; end if;
      if exists(select 1 from public.sd_event_operations where id=plan.event_operation_id and status='completed') then raise exception using errcode='P0001',message='event_operation_reopen_required'; end if;
      update public.sd_game_plans set status='active',version=version+1,updated_by=p_actor_id,updated_at=pg_catalog.now() where id=plan.id returning * into plan; response:=pg_catalog.jsonb_build_object('plan',pg_catalog.to_jsonb(plan));
    elsif p_action in ('archive_game_plan','restore_game_plan','delete_draft_game_plan') then
      if p_action='delete_draft_game_plan' and (plan.status<>'draft' or plan.published_version is not null) then raise exception using errcode='P0001',message='published_game_plan_delete_forbidden'; end if;
      if p_action='archive_game_plan' and plan.status in ('active','completed') then raise exception using errcode='P0001',message='historical_game_plan_archive_forbidden'; end if;
      update public.sd_game_plans set status=case when p_action in ('archive_game_plan','delete_draft_game_plan') then 'archived' else 'draft' end,archived_at=case when p_action in ('archive_game_plan','delete_draft_game_plan') then pg_catalog.now() else null end,is_primary=case when p_action in ('archive_game_plan','delete_draft_game_plan') then false else true end,version=version+1,updated_by=p_actor_id,updated_at=pg_catalog.now() where id=plan.id returning * into plan; response:=pg_catalog.jsonb_build_object('plan',pg_catalog.to_jsonb(plan),'deleted',p_action='delete_draft_game_plan');
    else raise exception using errcode='P0001',message='unsupported_game_action'; end if;
  end if;

  if plan.id is not null then
    insert into public.sd_game_plan_snapshots(game_plan_id,organization_id,event_operation_id,snapshot_type,plan_version,snapshot,reason,created_by)
      values(plan.id,p_organization_id,plan.event_operation_id,'version',plan.version,public.sd_game_plan_snapshot(plan.id),reason,p_actor_id) on conflict do nothing;
    insert into public.sd_game_plan_audit_logs(organization_id,season_id,team_id,event_id,game_plan_id,actor_id,action,request_id,target_id,previous_value,new_value,reason)
      values(p_organization_id,evt.season_id,evt.team_id,evt.id,plan.id,p_actor_id,audit_action,p_request_id,target,previous,response,reason);
    if plan.published_version is not null and plan.version>plan.published_version and p_action in ('initialize_standard_nine','initialize_dh','initialize_one_eh','initialize_multiple_eh','initialize_continuous_order','initialize_bat_entire_roster','clear_batting_order','reconcile_batting_order','add_batting_entry','update_batting_entry','remove_batting_entry','reorder_batting_order','update_eligibility') then
      insert into public.sd_team_event_notification_intents(organization_id,team_id,event_id,event_operation_id,intent_type,deduplication_key,payload,created_by) values(p_organization_id,plan.team_id,plan.event_id,plan.event_operation_id,'game_lineup_major_change',p_request_id::text||':'||plan.id::text||':major-change',pg_catalog.jsonb_build_object('plan_id',plan.id,'action',p_action),p_actor_id);
    end if;
    if plan.published_version is not null then
    if p_action='add_batting_entry' then
      insert into public.sd_team_event_notification_intents(organization_id,team_id,event_id,event_operation_id,intent_type,deduplication_key,payload,created_by) values(p_organization_id,plan.team_id,plan.event_id,plan.event_operation_id,'game_player_added',p_request_id::text||':'||plan.id::text||':player-added',pg_catalog.jsonb_build_object('plan_id',plan.id,'entry_id',target),p_actor_id);
    elsif p_action='remove_batting_entry' then
      insert into public.sd_team_event_notification_intents(organization_id,team_id,event_id,event_operation_id,intent_type,deduplication_key,payload,created_by) values(p_organization_id,plan.team_id,plan.event_id,plan.event_operation_id,'game_player_removed',p_request_id::text||':'||plan.id::text||':player-removed',pg_catalog.jsonb_build_object('plan_id',plan.id,'entry_id',target),p_actor_id);
    elsif p_action in ('assign_defensive_position','set_starting_defense','remove_defensive_assignment','assign_starting_pitcher','add_relief_pitcher','assign_starting_catcher','assign_backup_catcher','assign_pitcher_catcher_pair','update_pitcher_catcher_plan') then
      insert into public.sd_team_event_notification_intents(organization_id,team_id,event_id,event_operation_id,intent_type,deduplication_key,payload,created_by) values(p_organization_id,plan.team_id,plan.event_id,plan.event_operation_id,'game_assignment_changed',p_request_id::text||':'||plan.id::text||':assignment',pg_catalog.jsonb_build_object('plan_id',plan.id,'target_id',target),p_actor_id);
    elsif p_action='record_game_result' then
      insert into public.sd_team_event_notification_intents(organization_id,team_id,event_id,event_operation_id,intent_type,deduplication_key,payload,created_by) values(p_organization_id,plan.team_id,plan.event_id,plan.event_operation_id,'game_result_published',p_request_id::text||':'||plan.id::text||':result',pg_catalog.jsonb_build_object('plan_id',plan.id,'result_id',result_row.id),p_actor_id);
    elsif p_action='add_game_recap' and pg_catalog.coalesce((p_payload->>'publish')::boolean,false) then
      insert into public.sd_team_event_notification_intents(organization_id,team_id,event_id,event_operation_id,intent_type,deduplication_key,payload,created_by) values(p_organization_id,plan.team_id,plan.event_id,plan.event_operation_id,'game_recap_published',p_request_id::text||':'||plan.id::text||':recap',pg_catalog.jsonb_build_object('plan_id',plan.id,'recap_id',target,'visibility',p_payload->>'visibility'),p_actor_id);
    end if;
    end if;
  elsif target is not null then
    insert into public.sd_game_plan_audit_logs(organization_id,season_id,team_id,event_id,game_plan_id,actor_id,action,request_id,target_id,previous_value,new_value,reason)
      values(p_organization_id,evt.season_id,evt.team_id,evt.id,null,p_actor_id,audit_action,p_request_id,target,previous,response,reason);
  end if;
  update public.sd_game_plan_mutations set status='completed',response=response,completed_at=pg_catalog.now() where organization_id=p_organization_id and request_id=p_request_id;
  return response;
exception when others then
  delete from public.sd_game_plan_mutations where organization_id=p_organization_id and request_id=p_request_id and status='processing';
  raise;
end;
$$;

revoke all on function public.sd_apply_game_plan_mutation(uuid,uuid,uuid,text,uuid,jsonb) from public,anon,authenticated;
grant execute on function public.sd_apply_game_plan_mutation(uuid,uuid,uuid,text,uuid,jsonb) to service_role;
