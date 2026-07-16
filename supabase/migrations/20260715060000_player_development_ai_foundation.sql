-- Home Plate Phase 11A: Player Development AI foundation.
--
-- Purpose
-- - Add provider-neutral metric observations, evidence-backed reports, and
--   deterministic development alerts without changing existing source data.
-- - Keep all player-development intelligence organization/player scoped and
--   staff reviewed. Parent/player delivery is intentionally deferred.
-- - Preserve historical evidence and review events; no lifecycle RPC hard-deletes.
--
-- Assumptions
-- - public.sd_is_org_staff(uuid) and public.sd_can_manage_team_player(uuid, uuid)
--   are the hardened helpers installed by 20260714150000.
-- - The Edge Function verifies the JWT and transfers that actor UUID only to
--   service-role-only lifecycle RPCs. Authenticated clients cannot execute them.
-- - Lifecycle RPCs repeat organization/player authorization for the transferred
--   actor before mutating any row.
--
-- Rollback guidance (manual, only after exporting audit data)
-- 1. Revoke/drop the four Phase 11A RPCs and their triggers/policies.
-- 2. Drop alert event/evidence/alert tables, then report review/evidence/report
--    tables, then observations/import jobs/metric definitions.
-- 3. This is intentionally not automated because reports and evidence are audit
--    records. Existing testing, program, daily-log, and BP tables are untouched.

create table if not exists public.sd_development_metric_definitions (
  id uuid primary key default gen_random_uuid(),
  canonical_key text not null unique
    check (canonical_key ~ '^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$'),
  display_name text not null,
  category text not null,
  data_type text not null default 'number'
    check (data_type in ('number', 'integer', 'boolean', 'text', 'duration')),
  canonical_unit text,
  preferred_direction text not null default 'informational'
    check (preferred_direction in (
      'higher_is_better', 'lower_is_better', 'target_range',
      'informational', 'context_dependent'
    )),
  target_min numeric,
  target_max numeric,
  valid_aggregations text[] not null default array['latest', 'average', 'best']::text[],
  minimum_sample_size integer not null default 2 check (minimum_sample_size > 0),
  context_notes text,
  status text not null default 'active' check (status in ('active', 'deprecated')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint sd_development_metric_target_range_check
    check (
      (preferred_direction = 'target_range' and target_min is not null and target_max is not null and target_min <= target_max)
      or
      (preferred_direction <> 'target_range' and (target_min is null or target_max is null or target_min <= target_max))
    ),
  constraint sd_development_metric_aggregations_check
    check (
      cardinality(valid_aggregations) > 0
      and valid_aggregations <@ array['latest', 'average', 'best', 'rolling_average', 'distribution']::text[]
    )
);

create table if not exists public.sd_development_import_jobs (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.sd_orgs(id) on delete restrict,
  player_id uuid references public.profiles(id) on delete restrict,
  requested_by uuid not null references public.profiles(id) on delete restrict,
  import_source text not null,
  provider text,
  file_name text,
  status text not null default 'pending'
    check (status in ('pending', 'processing', 'completed', 'completed_with_errors', 'failed', 'canceled', 'archived')),
  row_count integer not null default 0 check (row_count >= 0),
  accepted_rows integer not null default 0 check (accepted_rows >= 0),
  rejected_rows integer not null default 0 check (rejected_rows >= 0),
  safe_error_summary text,
  started_at timestamptz,
  completed_at timestamptz,
  archived_at timestamptz,
  idempotency_key uuid not null,
  import_version text not null default 'development-import.v1',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (org_id, requested_by, idempotency_key),
  unique (id, org_id),
  unique (id, org_id, player_id),
  constraint sd_development_import_row_counts_check
    check (accepted_rows + rejected_rows <= row_count),
  constraint sd_development_import_timestamps_check
    check (
      (completed_at is null or started_at is null or completed_at >= started_at)
      and (status not in ('completed', 'completed_with_errors', 'archived') or completed_at is not null)
      and ((status = 'archived') = (archived_at is not null))
    )
);

create table if not exists public.sd_player_metric_observations (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.sd_orgs(id) on delete restrict,
  player_id uuid not null references public.profiles(id) on delete restrict,
  metric_definition_id uuid not null references public.sd_development_metric_definitions(id) on delete restrict,
  observed_value text,
  normalized_value numeric,
  unit text,
  observed_at timestamptz not null,
  source_system text not null,
  source_entity_type text not null,
  source_record_id uuid not null,
  import_job_id uuid,
  context_metadata jsonb not null default '{}'::jsonb,
  quality_status text not null default 'sufficient'
    check (quality_status in ('sufficient', 'limited', 'stale', 'conflicting', 'unavailable')),
  sample_size integer check (sample_size is null or sample_size > 0),
  notes text,
  correction_of_id uuid,
  corrected_at timestamptz,
  corrected_by uuid references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (org_id, player_id, metric_definition_id, source_system, source_entity_type, source_record_id, observed_at),
  unique (id, org_id, player_id),
  constraint sd_player_metric_observation_import_job_fk
    foreign key (import_job_id, org_id)
    references public.sd_development_import_jobs(id, org_id) on delete restrict,
  constraint sd_player_metric_observation_correction_fk
    foreign key (correction_of_id, org_id, player_id)
    references public.sd_player_metric_observations(id, org_id, player_id) on delete restrict,
  constraint sd_player_metric_observation_correction_audit_check
    check (
      (correction_of_id is null and corrected_at is null and corrected_by is null)
      or
      (correction_of_id is not null and correction_of_id <> id and corrected_at is not null and corrected_by is not null)
    ),
  constraint sd_player_metric_observation_value_check
    check (observed_value is not null or normalized_value is not null)
);

create table if not exists public.sd_development_reports (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.sd_orgs(id) on delete restrict,
  player_id uuid references public.profiles(id) on delete restrict,
  team_id uuid references public.sd_teams(id) on delete restrict,
  report_type text not null check (report_type in (
    'player_development_summary', 'coach_copilot', 'parent_update_draft',
    'roster_attention_report', 'development_alert_review'
  )),
  requested_by uuid not null references public.profiles(id) on delete restrict,
  intended_audience text not null default 'coach'
    check (intended_audience in ('coach', 'staff', 'parent_draft', 'internal')),
  reporting_window_start date not null,
  reporting_window_end date not null,
  status text not null default 'requested'
    check (status in ('requested', 'generating', 'draft', 'reviewed', 'approved', 'failed', 'rejected', 'archived')),
  quality_status text not null default 'unavailable'
    check (quality_status in ('sufficient', 'limited', 'stale', 'conflicting', 'unavailable')),
  structured_content jsonb not null default '{}'::jsonb,
  rendered_text text not null default '',
  generation_mode text not null check (generation_mode in ('deterministic', 'model', 'hybrid')),
  provider text not null,
  model_identifier text,
  generator_version text not null,
  prompt_version text not null,
  input_cutoff timestamptz not null,
  generated_at timestamptz,
  reviewed_at timestamptz,
  reviewed_by uuid references public.profiles(id) on delete restrict,
  approved_at timestamptz,
  rejected_at timestamptz,
  archived_at timestamptz,
  coach_edits jsonb not null default '{}'::jsonb,
  review_notes text,
  confidence numeric check (confidence is null or (confidence >= 0 and confidence <= 1)),
  data_freshness text not null default 'unavailable',
  missing_data_warnings text[] not null default '{}'::text[],
  idempotency_key uuid not null,
  request_fingerprint text not null,
  evidence_fingerprint text not null check (evidence_fingerprint ~ '^[0-9a-f]{64}$'),
  generation_error_code text,
  safe_generation_error_metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint sd_development_report_window_check
    check (reporting_window_start <= reporting_window_end),
  unique (org_id, requested_by, idempotency_key),
  unique (id, org_id),
  unique (id, org_id, player_id)
);

create table if not exists public.sd_development_report_evidence (
  id uuid primary key default gen_random_uuid(),
  report_id uuid not null,
  org_id uuid not null references public.sd_orgs(id) on delete restrict,
  player_id uuid not null references public.profiles(id) on delete restrict,
  evidence_key text not null,
  section_key text not null,
  source_entity_type text not null,
  source_record_id text not null,
  canonical_metric_key text references public.sd_development_metric_definitions(canonical_key) on delete restrict,
  raw_observed_value text,
  normalized_numeric_value numeric,
  unit text,
  observation_date timestamptz,
  comparison_value numeric,
  comparison_period text,
  direction text,
  sample_size integer check (sample_size is null or sample_size > 0),
  freshness text not null,
  quality text not null check (quality in ('sufficient', 'limited', 'stale', 'conflicting', 'unavailable')),
  deterministic_rule_id text,
  display_label text not null,
  explanation text not null,
  source_metadata jsonb not null default '{}'::jsonb,
  evidence_snapshot jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  unique (report_id, evidence_key),
  constraint sd_development_report_evidence_report_fk
    foreign key (report_id, org_id, player_id)
    references public.sd_development_reports(id, org_id, player_id) on delete restrict
);

create table if not exists public.sd_development_report_review_events (
  id uuid primary key default gen_random_uuid(),
  report_id uuid not null,
  org_id uuid not null references public.sd_orgs(id) on delete restrict,
  actor_id uuid not null references public.profiles(id) on delete restrict,
  event_type text not null check (event_type in (
    'generated', 'reviewed', 'edited', 'approved', 'rejected', 'archived', 'generation_failed'
  )),
  from_status text,
  to_status text not null,
  review_notes text,
  coach_edits_snapshot jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint sd_development_report_review_event_report_fk
    foreign key (report_id, org_id)
    references public.sd_development_reports(id, org_id) on delete restrict
);

create table if not exists public.sd_development_alerts (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.sd_orgs(id) on delete restrict,
  player_id uuid not null references public.profiles(id) on delete restrict,
  report_id uuid,
  alert_type text not null,
  severity text not null check (severity in ('info', 'attention', 'high')),
  status text not null default 'active'
    check (status in ('active', 'acknowledged', 'dismissed', 'resolved', 'archived')),
  first_detected_at timestamptz not null default now(),
  last_detected_at timestamptz not null default now(),
  evidence_window_start date not null,
  evidence_window_end date not null,
  rule_version text not null,
  explanation text not null,
  recommended_human_action text not null,
  data_freshness text not null,
  evidence_quality text not null
    check (evidence_quality in ('sufficient', 'limited', 'stale', 'conflicting', 'unavailable')),
  deduplication_key text not null,
  acknowledged_at timestamptz,
  acknowledged_by uuid references public.profiles(id) on delete restrict,
  dismissed_at timestamptz,
  dismissed_by uuid references public.profiles(id) on delete restrict,
  resolved_at timestamptz,
  resolved_by uuid references public.profiles(id) on delete restrict,
  archived_at timestamptz,
  archived_by uuid references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint sd_development_alert_window_check check (evidence_window_start <= evidence_window_end),
  unique (org_id, player_id, deduplication_key),
  unique (id, org_id),
  unique (id, org_id, player_id),
  constraint sd_development_alert_report_fk
    foreign key (report_id, org_id, player_id)
    references public.sd_development_reports(id, org_id, player_id) on delete restrict
);

create table if not exists public.sd_development_alert_evidence (
  id uuid primary key default gen_random_uuid(),
  alert_id uuid not null,
  org_id uuid not null references public.sd_orgs(id) on delete restrict,
  player_id uuid not null references public.profiles(id) on delete restrict,
  evidence_key text not null,
  source_entity_type text not null,
  source_record_id text not null,
  canonical_metric_key text references public.sd_development_metric_definitions(canonical_key) on delete restrict,
  observation_date timestamptz,
  display_label text not null,
  explanation text not null,
  evidence_snapshot jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  unique (alert_id, evidence_key),
  constraint sd_development_alert_evidence_alert_fk
    foreign key (alert_id, org_id, player_id)
    references public.sd_development_alerts(id, org_id, player_id) on delete restrict
);

create table if not exists public.sd_development_alert_events (
  id uuid primary key default gen_random_uuid(),
  alert_id uuid not null,
  org_id uuid not null references public.sd_orgs(id) on delete restrict,
  actor_id uuid not null references public.profiles(id) on delete restrict,
  event_type text not null check (event_type in ('detected', 'redetected', 'acknowledged', 'dismissed', 'resolved', 'archived')),
  from_status text,
  to_status text not null,
  notes text,
  created_at timestamptz not null default now(),
  constraint sd_development_alert_event_alert_fk
    foreign key (alert_id, org_id)
    references public.sd_development_alerts(id, org_id) on delete restrict
);

-- Defense-in-depth scope checks run on insert and only when scope-defining
-- columns change. Historical lifecycle updates remain usable if a player is
-- later disabled or removed.
create or replace function public.sd_validate_development_player_scope()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.player_id is not null and not exists (
    select 1 from public.sd_org_memberships m
    where m.org_id = new.org_id and m.user_id = new.player_id
      and m.role = 'player' and m.status = 'active'
  ) then
    raise exception 'development_active_player_membership_required';
  end if;
  return new;
end;
$$;

create or replace function public.sd_validate_development_report_evidence_scope()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (
    select 1 from public.sd_development_reports r
    where r.id = new.report_id and r.org_id = new.org_id and r.player_id = new.player_id
  ) then raise exception 'development_report_evidence_scope_mismatch'; end if;
  return new;
end;
$$;

create or replace function public.sd_validate_development_import_actor_scope()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (
    select 1 from public.sd_org_memberships m
    where m.org_id = new.org_id and m.user_id = new.requested_by
      and m.status = 'active' and m.role in ('owner', 'admin', 'coach')
  ) then
    raise exception 'development_import_staff_membership_required';
  end if;
  return new;
end;
$$;

create or replace function public.sd_validate_development_observation_import_scope()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.import_job_id is not null and not exists (
    select 1 from public.sd_development_import_jobs j
    where j.id = new.import_job_id and j.org_id = new.org_id
      and (j.player_id is null or j.player_id = new.player_id)
  ) then
    raise exception 'development_observation_import_scope_mismatch';
  end if;
  return new;
end;
$$;

create or replace function public.sd_validate_development_report_team_scope()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.team_id is not null and not exists (
    select 1 from public.sd_teams t
    where t.id = new.team_id and t.org_id = new.org_id
  ) then
    raise exception 'development_report_team_scope_mismatch';
  end if;
  return new;
end;
$$;

create or replace function public.sd_validate_development_report_event_scope()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (
    select 1 from public.sd_development_reports r
    where r.id = new.report_id and r.org_id = new.org_id
  ) then raise exception 'development_report_event_scope_mismatch'; end if;
  return new;
end;
$$;

create or replace function public.sd_validate_development_alert_evidence_scope()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (
    select 1 from public.sd_development_alerts a
    where a.id = new.alert_id and a.org_id = new.org_id and a.player_id = new.player_id
  ) then raise exception 'development_alert_evidence_scope_mismatch'; end if;
  return new;
end;
$$;

create or replace function public.sd_validate_development_alert_event_scope()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (
    select 1 from public.sd_development_alerts a
    where a.id = new.alert_id and a.org_id = new.org_id
  ) then raise exception 'development_alert_event_scope_mismatch'; end if;
  return new;
end;
$$;

drop trigger if exists trg_sd_development_import_jobs_player_scope on public.sd_development_import_jobs;
create trigger trg_sd_development_import_jobs_player_scope
before insert or update of org_id, player_id on public.sd_development_import_jobs
for each row execute function public.sd_validate_development_player_scope();
drop trigger if exists trg_sd_development_import_jobs_actor_scope on public.sd_development_import_jobs;
create trigger trg_sd_development_import_jobs_actor_scope
before insert or update of org_id, requested_by on public.sd_development_import_jobs
for each row execute function public.sd_validate_development_import_actor_scope();
drop trigger if exists trg_sd_player_metric_observations_player_scope on public.sd_player_metric_observations;
create trigger trg_sd_player_metric_observations_player_scope
before insert or update of org_id, player_id on public.sd_player_metric_observations
for each row execute function public.sd_validate_development_player_scope();
drop trigger if exists trg_sd_player_metric_observations_import_scope on public.sd_player_metric_observations;
create trigger trg_sd_player_metric_observations_import_scope
before insert or update of import_job_id, org_id, player_id on public.sd_player_metric_observations
for each row execute function public.sd_validate_development_observation_import_scope();
drop trigger if exists trg_sd_development_reports_player_scope on public.sd_development_reports;
create trigger trg_sd_development_reports_player_scope
before insert or update of org_id, player_id on public.sd_development_reports
for each row execute function public.sd_validate_development_player_scope();
drop trigger if exists trg_sd_development_reports_team_scope on public.sd_development_reports;
create trigger trg_sd_development_reports_team_scope
before insert or update of team_id, org_id on public.sd_development_reports
for each row execute function public.sd_validate_development_report_team_scope();
drop trigger if exists trg_sd_development_alerts_player_scope on public.sd_development_alerts;
create trigger trg_sd_development_alerts_player_scope
before insert or update of org_id, player_id on public.sd_development_alerts
for each row execute function public.sd_validate_development_player_scope();
drop trigger if exists trg_sd_development_report_evidence_scope on public.sd_development_report_evidence;
create trigger trg_sd_development_report_evidence_scope
before insert or update of report_id, org_id, player_id on public.sd_development_report_evidence
for each row execute function public.sd_validate_development_report_evidence_scope();
drop trigger if exists trg_sd_development_report_event_scope on public.sd_development_report_review_events;
create trigger trg_sd_development_report_event_scope
before insert or update of report_id, org_id on public.sd_development_report_review_events
for each row execute function public.sd_validate_development_report_event_scope();
drop trigger if exists trg_sd_development_alert_evidence_scope on public.sd_development_alert_evidence;
create trigger trg_sd_development_alert_evidence_scope
before insert or update of alert_id, org_id, player_id on public.sd_development_alert_evidence
for each row execute function public.sd_validate_development_alert_evidence_scope();
drop trigger if exists trg_sd_development_alert_event_scope on public.sd_development_alert_events;
create trigger trg_sd_development_alert_event_scope
before insert or update of alert_id, org_id on public.sd_development_alert_events
for each row execute function public.sd_validate_development_alert_event_scope();

revoke all on function public.sd_validate_development_player_scope()
from public, anon, authenticated, service_role;
revoke all on function public.sd_validate_development_report_evidence_scope()
from public, anon, authenticated, service_role;
revoke all on function public.sd_validate_development_import_actor_scope()
from public, anon, authenticated, service_role;
revoke all on function public.sd_validate_development_observation_import_scope()
from public, anon, authenticated, service_role;
revoke all on function public.sd_validate_development_report_team_scope()
from public, anon, authenticated, service_role;
revoke all on function public.sd_validate_development_report_event_scope()
from public, anon, authenticated, service_role;
revoke all on function public.sd_validate_development_alert_evidence_scope()
from public, anon, authenticated, service_role;
revoke all on function public.sd_validate_development_alert_event_scope()
from public, anon, authenticated, service_role;

create index if not exists idx_sd_development_import_jobs_org_status
  on public.sd_development_import_jobs (org_id, status, created_at desc);
create index if not exists idx_sd_player_metric_observations_player_metric_date
  on public.sd_player_metric_observations (org_id, player_id, metric_definition_id, observed_at desc);
create index if not exists idx_sd_player_metric_observations_import_job
  on public.sd_player_metric_observations (import_job_id)
  where import_job_id is not null;
create index if not exists idx_sd_player_metric_observations_correction
  on public.sd_player_metric_observations (correction_of_id)
  where correction_of_id is not null;
create index if not exists idx_sd_development_reports_player_created
  on public.sd_development_reports (org_id, player_id, created_at desc);
create index if not exists idx_sd_development_reports_org_status
  on public.sd_development_reports (org_id, status, created_at desc);
create index if not exists idx_sd_development_report_evidence_report_section
  on public.sd_development_report_evidence (report_id, section_key, observation_date desc);
create index if not exists idx_sd_development_report_review_events_report
  on public.sd_development_report_review_events (report_id, created_at);
create index if not exists idx_sd_development_alerts_org_status_severity
  on public.sd_development_alerts (org_id, status, severity, last_detected_at desc);
create index if not exists idx_sd_development_alerts_player_status
  on public.sd_development_alerts (org_id, player_id, status, last_detected_at desc);
create index if not exists idx_sd_development_alerts_report
  on public.sd_development_alerts (report_id)
  where report_id is not null;
create index if not exists idx_sd_development_alert_events_alert
  on public.sd_development_alert_events (alert_id, created_at);

drop trigger if exists trg_sd_development_metric_definitions_updated_at on public.sd_development_metric_definitions;
create trigger trg_sd_development_metric_definitions_updated_at before update on public.sd_development_metric_definitions
for each row execute function public.sd_set_updated_at();
drop trigger if exists trg_sd_development_import_jobs_updated_at on public.sd_development_import_jobs;
create trigger trg_sd_development_import_jobs_updated_at before update on public.sd_development_import_jobs
for each row execute function public.sd_set_updated_at();
drop trigger if exists trg_sd_player_metric_observations_updated_at on public.sd_player_metric_observations;
create trigger trg_sd_player_metric_observations_updated_at before update on public.sd_player_metric_observations
for each row execute function public.sd_set_updated_at();
drop trigger if exists trg_sd_development_reports_updated_at on public.sd_development_reports;
create trigger trg_sd_development_reports_updated_at before update on public.sd_development_reports
for each row execute function public.sd_set_updated_at();
drop trigger if exists trg_sd_development_alerts_updated_at on public.sd_development_alerts;
create trigger trg_sd_development_alerts_updated_at before update on public.sd_development_alerts
for each row execute function public.sd_set_updated_at();

-- Phase-specific staff scope mirrors the established organization/team policy
-- while refusing inactive teams. The actor-parameterized helper is internal to
-- service-role-only lifecycle RPCs; authenticated RLS uses only auth.uid().
create or replace function public.sd_development_actor_can_manage_player(
  p_actor_id uuid,
  p_org_id uuid,
  p_player_id uuid
)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  actor_role text;
  restrict_actions boolean := true;
begin
  if not exists (
    select 1 from public.sd_orgs o
    where o.id = p_org_id and o.status = 'active'
  ) then return false; end if;

  select m.role into actor_role
  from public.sd_org_memberships m
  where m.org_id = p_org_id and m.user_id = p_actor_id and m.status = 'active'
  limit 1;

  if actor_role in ('owner', 'admin') then return true; end if;
  if actor_role <> 'coach' then return false; end if;

  select coalesce((s.team_policy ->> 'restrictCoachActionsToTeam')::boolean, true)
  into restrict_actions
  from public.sd_org_settings s
  where s.org_id = p_org_id;
  if coalesce(restrict_actions, true) = false then
    return exists (
      select 1 from public.sd_org_memberships p
      where p.org_id = p_org_id and p.user_id = p_player_id
        and p.role = 'player' and p.status = 'active'
    );
  end if;

  return exists (
    select 1
    from public.sd_team_members actor_team
    join public.sd_team_members player_team
      on player_team.org_id = actor_team.org_id
     and player_team.team_id = actor_team.team_id
    join public.sd_teams team
      on team.id = actor_team.team_id and team.org_id = actor_team.org_id
    join public.sd_org_memberships player_membership
      on player_membership.org_id = player_team.org_id
     and player_membership.user_id = player_team.player_id
     and player_membership.role = 'player'
     and player_membership.status = 'active'
    where actor_team.org_id = p_org_id
      and actor_team.player_id = p_actor_id
      and player_team.player_id = p_player_id
      and team.is_active = true
  );
end;
$$;

create or replace function public.sd_development_is_org_staff(p_org_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.sd_org_memberships m
    join public.sd_orgs o on o.id = m.org_id and o.status = 'active'
    where m.org_id = p_org_id and m.user_id = auth.uid()
      and m.status = 'active' and m.role in ('owner', 'admin', 'coach')
  );
$$;

create or replace function public.sd_development_can_manage_player(p_org_id uuid, p_player_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select public.sd_development_actor_can_manage_player(auth.uid(), p_org_id, p_player_id);
$$;

revoke all on function public.sd_development_actor_can_manage_player(uuid, uuid, uuid)
from public, anon, authenticated, service_role;
revoke all on function public.sd_development_is_org_staff(uuid)
from public, anon, authenticated, service_role;
grant execute on function public.sd_development_is_org_staff(uuid) to authenticated;
revoke all on function public.sd_development_can_manage_player(uuid, uuid)
from public, anon, authenticated, service_role;
grant execute on function public.sd_development_can_manage_player(uuid, uuid) to authenticated;

alter table public.sd_development_metric_definitions enable row level security;
alter table public.sd_development_import_jobs enable row level security;
alter table public.sd_player_metric_observations enable row level security;
alter table public.sd_development_reports enable row level security;
alter table public.sd_development_report_evidence enable row level security;
alter table public.sd_development_report_review_events enable row level security;
alter table public.sd_development_alerts enable row level security;
alter table public.sd_development_alert_evidence enable row level security;
alter table public.sd_development_alert_events enable row level security;

-- The registry contains no player records, but remains staff-only in Phase 11A.
create policy "sd_development_metric_definitions_staff_read"
on public.sd_development_metric_definitions for select to authenticated
using (exists (
  select 1 from public.sd_org_memberships m
  where m.user_id = auth.uid() and m.status = 'active' and m.role in ('owner', 'admin', 'coach')
));

create policy "sd_development_import_jobs_staff_read"
on public.sd_development_import_jobs for select to authenticated
using (public.sd_development_is_org_staff(org_id) and (player_id is null or public.sd_development_can_manage_player(org_id, player_id)));

create policy "sd_player_metric_observations_staff_read"
on public.sd_player_metric_observations for select to authenticated
using (public.sd_development_is_org_staff(org_id) and public.sd_development_can_manage_player(org_id, player_id));

create policy "sd_development_reports_staff_read"
on public.sd_development_reports for select to authenticated
using (public.sd_development_is_org_staff(org_id) and (player_id is null or public.sd_development_can_manage_player(org_id, player_id)));

create policy "sd_development_report_evidence_staff_read"
on public.sd_development_report_evidence for select to authenticated
using (public.sd_development_is_org_staff(org_id) and public.sd_development_can_manage_player(org_id, player_id));

create policy "sd_development_report_review_events_staff_read"
on public.sd_development_report_review_events for select to authenticated
using (public.sd_development_is_org_staff(org_id) and exists (
  select 1 from public.sd_development_reports r
  where r.id = report_id and (r.player_id is null or public.sd_development_can_manage_player(r.org_id, r.player_id))
));

create policy "sd_development_alerts_staff_read"
on public.sd_development_alerts for select to authenticated
using (public.sd_development_is_org_staff(org_id) and public.sd_development_can_manage_player(org_id, player_id));

create policy "sd_development_alert_evidence_staff_read"
on public.sd_development_alert_evidence for select to authenticated
using (public.sd_development_is_org_staff(org_id) and public.sd_development_can_manage_player(org_id, player_id));

create policy "sd_development_alert_events_staff_read"
on public.sd_development_alert_events for select to authenticated
using (public.sd_development_is_org_staff(org_id) and exists (
  select 1 from public.sd_development_alerts a
  where a.id = alert_id and public.sd_development_can_manage_player(a.org_id, a.player_id)
));

-- No authenticated INSERT/UPDATE/DELETE table policies are created. Mutations
-- are limited to the verified-actor, service-role-only RPCs below.

create or replace function public.sd_create_development_report(
  p_actor_id uuid,
  p_org_id uuid,
  p_player_id uuid,
  p_report_type text,
  p_intended_audience text,
  p_window_start date,
  p_window_end date,
  p_input_cutoff timestamptz,
  p_idempotency_key uuid,
  p_request_fingerprint text,
  p_evidence_fingerprint text,
  p_quality_status text,
  p_structured_content jsonb,
  p_rendered_text text,
  p_confidence numeric,
  p_data_freshness text,
  p_missing_data_warnings text[],
  p_evidence jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor uuid := p_actor_id;
  existing_report public.sd_development_reports;
  created_report public.sd_development_reports;
  evidence_item jsonb;
begin
  if actor is null or not public.sd_development_actor_can_manage_player(actor, p_org_id, p_player_id) then
    raise exception 'development_staff_access_required';
  end if;
  if p_window_start > p_window_end or p_window_end - p_window_start > 730
     or p_input_cutoff::date < p_window_end or p_input_cutoff > now() + interval '5 minutes'
     or p_request_fingerprint is null or length(p_request_fingerprint) < 8
     or p_evidence_fingerprint is null or p_evidence_fingerprint !~ '^[0-9a-f]{64}$'
     or jsonb_typeof(coalesce(p_evidence, '[]'::jsonb)) <> 'array'
     or jsonb_array_length(coalesce(p_evidence, '[]'::jsonb)) > 5000 then
    raise exception 'invalid_development_report_request';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_org_id::text || ':' || actor::text || ':' || p_idempotency_key::text, 0));
  select * into existing_report
  from public.sd_development_reports
  where org_id = p_org_id and requested_by = actor and idempotency_key = p_idempotency_key;
  if found then
    if existing_report.request_fingerprint <> p_request_fingerprint then
      raise exception 'development_report_idempotency_conflict';
    end if;
    return pg_catalog.jsonb_build_object(
      'report', pg_catalog.to_jsonb(existing_report),
      'reused', true
    );
  end if;

  insert into public.sd_development_reports (
    org_id, player_id, report_type, requested_by, intended_audience,
    reporting_window_start, reporting_window_end, status, quality_status,
    structured_content, rendered_text, generation_mode, provider,
    model_identifier, generator_version, prompt_version, input_cutoff,
    generated_at, confidence, data_freshness, missing_data_warnings,
    idempotency_key, request_fingerprint, evidence_fingerprint
  ) values (
    p_org_id, p_player_id, p_report_type, actor, p_intended_audience,
    p_window_start, p_window_end, 'draft', p_quality_status,
    coalesce(p_structured_content, '{}'::jsonb), coalesce(p_rendered_text, ''),
    'deterministic', 'deterministic_template', null,
    'deterministic-template.v1', 'none.deterministic.v1', p_input_cutoff,
    now(), p_confidence, p_data_freshness, coalesce(p_missing_data_warnings, '{}'::text[]),
    p_idempotency_key, p_request_fingerprint, p_evidence_fingerprint
  ) returning * into created_report;

  for evidence_item in select value from jsonb_array_elements(coalesce(p_evidence, '[]'::jsonb))
  loop
    if evidence_item->>'evidence_key' is null or evidence_item->>'source_entity_type' is null
       or evidence_item->>'source_record_id' is null then
      raise exception 'invalid_development_evidence';
    end if;
    insert into public.sd_development_report_evidence (
      report_id, org_id, player_id, evidence_key, section_key,
      source_entity_type, source_record_id, canonical_metric_key,
      raw_observed_value, normalized_numeric_value, unit, observation_date,
      comparison_value, comparison_period, direction, sample_size, freshness,
      quality, deterministic_rule_id, display_label, explanation,
      source_metadata, evidence_snapshot
    ) values (
      created_report.id, p_org_id, p_player_id,
      evidence_item->>'evidence_key', coalesce(evidence_item->>'section_key', 'metrics'),
      evidence_item->>'source_entity_type', evidence_item->>'source_record_id',
      evidence_item->>'canonical_metric_key', evidence_item->>'raw_observed_value',
      nullif(evidence_item->>'normalized_numeric_value', '')::numeric,
      evidence_item->>'unit', nullif(evidence_item->>'observation_date', '')::timestamptz,
      nullif(evidence_item->>'comparison_value', '')::numeric,
      evidence_item->>'comparison_period', evidence_item->>'direction',
      nullif(evidence_item->>'sample_size', '')::integer,
      coalesce(evidence_item->>'freshness', 'unavailable'),
      coalesce(evidence_item->>'quality', 'unavailable'),
      evidence_item->>'deterministic_rule_id',
      coalesce(evidence_item->>'display_label', 'Evidence'),
      coalesce(evidence_item->>'explanation', 'Recorded evidence.'),
      coalesce(evidence_item->'source_metadata', '{}'::jsonb),
      coalesce(evidence_item->'evidence_snapshot', '{}'::jsonb)
    ) on conflict (report_id, evidence_key) do nothing;
  end loop;

  insert into public.sd_development_report_review_events (
    report_id, org_id, actor_id, event_type, from_status, to_status
  ) values (created_report.id, p_org_id, actor, 'generated', 'generating', 'draft');
  return pg_catalog.jsonb_build_object(
    'report', pg_catalog.to_jsonb(created_report),
    'reused', false
  );
end;
$$;

create or replace function public.sd_review_development_report(
  p_actor_id uuid,
  p_org_id uuid,
  p_report_id uuid,
  p_action text,
  p_review_notes text default null,
  p_coach_edits jsonb default '{}'::jsonb
)
returns public.sd_development_reports
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor uuid := p_actor_id;
  current_report public.sd_development_reports;
  prior_status text;
  next_status text;
  event_name text;
begin
  select * into current_report from public.sd_development_reports
  where id = p_report_id and org_id = p_org_id for update;
  if not found then raise exception 'report_not_found'; end if;
  if actor is null or current_report.player_id is null
     or not public.sd_development_actor_can_manage_player(actor, p_org_id, current_report.player_id) then
    raise exception 'development_staff_access_required';
  end if;
  prior_status := current_report.status;

  next_status := case p_action
    when 'review' then 'reviewed'
    when 'edit' then 'reviewed'
    when 'approve' then 'approved'
    when 'reject' then 'rejected'
    when 'archive' then 'archived'
    else null
  end;
  event_name := case p_action when 'review' then 'reviewed' when 'edit' then 'edited' else p_action || 'd' end;
  if next_status is null
     or (current_report.status = 'draft' and next_status not in ('reviewed', 'approved', 'rejected', 'archived'))
     or (current_report.status = 'reviewed' and next_status not in ('reviewed', 'approved', 'rejected', 'archived'))
     or (current_report.status = 'approved' and next_status <> 'archived')
     or current_report.status in ('failed', 'rejected', 'archived') then
    raise exception 'invalid_report_transition';
  end if;

  update public.sd_development_reports set
    status = next_status,
    reviewed_at = case when next_status in ('reviewed', 'approved', 'rejected') then now() else reviewed_at end,
    reviewed_by = case when next_status in ('reviewed', 'approved', 'rejected') then actor else reviewed_by end,
    approved_at = case when next_status = 'approved' then now() else approved_at end,
    rejected_at = case when next_status = 'rejected' then now() else rejected_at end,
    archived_at = case when next_status = 'archived' then now() else archived_at end,
    coach_edits = case when p_action = 'edit' then coalesce(p_coach_edits, '{}'::jsonb) else coach_edits end,
    review_notes = coalesce(nullif(pg_catalog.btrim(p_review_notes), ''), review_notes)
  where id = p_report_id returning * into current_report;

  insert into public.sd_development_report_review_events (
    report_id, org_id, actor_id, event_type, from_status, to_status,
    review_notes, coach_edits_snapshot
  ) values (
    p_report_id, p_org_id, actor, event_name,
    prior_status,
    next_status, nullif(pg_catalog.btrim(p_review_notes), ''), coalesce(p_coach_edits, '{}'::jsonb)
  );
  return current_report;
end;
$$;

create or replace function public.sd_upsert_development_alerts(
  p_actor_id uuid,
  p_org_id uuid,
  p_alerts jsonb
)
returns setof public.sd_development_alerts
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor uuid := p_actor_id;
  item jsonb;
  evidence_item jsonb;
  target_player uuid;
  saved_alert public.sd_development_alerts;
  prior_status text;
begin
  if actor is null then
    raise exception 'development_staff_access_required';
  end if;
  if jsonb_typeof(coalesce(p_alerts, '[]'::jsonb)) <> 'array' or jsonb_array_length(coalesce(p_alerts, '[]'::jsonb)) > 250 then
    raise exception 'invalid_development_alert_request';
  end if;

  for item in select value from jsonb_array_elements(coalesce(p_alerts, '[]'::jsonb))
  loop
    target_player := (item->>'player_id')::uuid;
    if not public.sd_development_actor_can_manage_player(actor, p_org_id, target_player) then
      raise exception 'development_player_access_denied';
    end if;
    perform pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtextextended(
        p_org_id::text || ':' || target_player::text || ':' || (item->>'deduplication_key'),
        0
      )
    );
    select status into prior_status from public.sd_development_alerts
    where org_id = p_org_id and player_id = target_player
      and deduplication_key = item->>'deduplication_key';

    insert into public.sd_development_alerts (
      org_id, player_id, report_id, alert_type, severity, status,
      first_detected_at, last_detected_at, evidence_window_start,
      evidence_window_end, rule_version, explanation,
      recommended_human_action, data_freshness, evidence_quality,
      deduplication_key
    ) values (
      p_org_id, target_player, nullif(item->>'report_id', '')::uuid,
      item->>'alert_type', item->>'severity', 'active', now(), now(),
      (item->>'evidence_window_start')::date,
      (item->>'evidence_window_end')::date,
      item->>'rule_version', item->>'explanation',
      item->>'recommended_human_action', item->>'data_freshness',
      item->>'evidence_quality', item->>'deduplication_key'
    ) on conflict (org_id, player_id, deduplication_key) do update set
      last_detected_at = now(),
      severity = excluded.severity,
      explanation = excluded.explanation,
      recommended_human_action = excluded.recommended_human_action,
      data_freshness = excluded.data_freshness,
      evidence_quality = excluded.evidence_quality,
      evidence_window_start = excluded.evidence_window_start,
      evidence_window_end = excluded.evidence_window_end
    returning * into saved_alert;

    for evidence_item in select value from jsonb_array_elements(coalesce(item->'evidence', '[]'::jsonb))
    loop
      insert into public.sd_development_alert_evidence (
        alert_id, org_id, player_id, evidence_key, source_entity_type,
        source_record_id, canonical_metric_key, observation_date,
        display_label, explanation, evidence_snapshot
      ) values (
        saved_alert.id, p_org_id, target_player, evidence_item->>'evidence_key',
        evidence_item->>'source_entity_type', evidence_item->>'source_record_id',
        evidence_item->>'canonical_metric_key',
        nullif(evidence_item->>'observation_date', '')::timestamptz,
        coalesce(evidence_item->>'display_label', 'Evidence'),
        coalesce(evidence_item->>'explanation', 'Recorded evidence.'),
        coalesce(evidence_item->'evidence_snapshot', '{}'::jsonb)
      ) on conflict (alert_id, evidence_key) do update set
        evidence_snapshot = excluded.evidence_snapshot,
        explanation = excluded.explanation;
    end loop;

    insert into public.sd_development_alert_events (
      alert_id, org_id, actor_id, event_type, from_status, to_status
    ) values (
      saved_alert.id, p_org_id, actor,
      case when prior_status is null then 'detected' else 'redetected' end,
      prior_status, saved_alert.status
    );
    return next saved_alert;
  end loop;
end;
$$;

create or replace function public.sd_review_development_alert(
  p_actor_id uuid,
  p_org_id uuid,
  p_alert_id uuid,
  p_action text,
  p_notes text default null
)
returns public.sd_development_alerts
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor uuid := p_actor_id;
  current_alert public.sd_development_alerts;
  prior_status text;
  next_status text;
begin
  select * into current_alert from public.sd_development_alerts
  where id = p_alert_id and org_id = p_org_id for update;
  if not found then raise exception 'alert_not_found'; end if;
  if actor is null
     or not public.sd_development_actor_can_manage_player(actor, p_org_id, current_alert.player_id) then
    raise exception 'development_staff_access_required';
  end if;
  prior_status := current_alert.status;
  next_status := case p_action
    when 'acknowledge' then 'acknowledged'
    when 'dismiss' then 'dismissed'
    when 'resolve' then 'resolved'
    when 'archive' then 'archived'
    else null
  end;
  if next_status is null or prior_status in ('dismissed', 'resolved', 'archived')
     or (prior_status = 'acknowledged' and next_status = 'acknowledged') then
    raise exception 'invalid_alert_transition';
  end if;
  update public.sd_development_alerts set
    status = next_status,
    acknowledged_at = case when next_status = 'acknowledged' then now() else acknowledged_at end,
    acknowledged_by = case when next_status = 'acknowledged' then actor else acknowledged_by end,
    dismissed_at = case when next_status = 'dismissed' then now() else dismissed_at end,
    dismissed_by = case when next_status = 'dismissed' then actor else dismissed_by end,
    resolved_at = case when next_status = 'resolved' then now() else resolved_at end,
    resolved_by = case when next_status = 'resolved' then actor else resolved_by end,
    archived_at = case when next_status = 'archived' then now() else archived_at end,
    archived_by = case when next_status = 'archived' then actor else archived_by end
  where id = p_alert_id returning * into current_alert;
  insert into public.sd_development_alert_events (
    alert_id, org_id, actor_id, event_type, from_status, to_status, notes
  ) values (p_alert_id, p_org_id, actor, next_status, prior_status, next_status, nullif(pg_catalog.btrim(p_notes), ''));
  return current_alert;
end;
$$;

revoke all on function public.sd_create_development_report(uuid, uuid, uuid, text, text, date, date, timestamptz, uuid, text, text, text, jsonb, text, numeric, text, text[], jsonb)
from public, anon, authenticated, service_role;
grant execute on function public.sd_create_development_report(uuid, uuid, uuid, text, text, date, date, timestamptz, uuid, text, text, text, jsonb, text, numeric, text, text[], jsonb)
to service_role;

revoke all on function public.sd_review_development_report(uuid, uuid, uuid, text, text, jsonb)
from public, anon, authenticated, service_role;
grant execute on function public.sd_review_development_report(uuid, uuid, uuid, text, text, jsonb)
to service_role;

revoke all on function public.sd_upsert_development_alerts(uuid, uuid, jsonb)
from public, anon, authenticated, service_role;
grant execute on function public.sd_upsert_development_alerts(uuid, uuid, jsonb)
to service_role;

revoke all on function public.sd_review_development_alert(uuid, uuid, uuid, text, text)
from public, anon, authenticated, service_role;
grant execute on function public.sd_review_development_alert(uuid, uuid, uuid, text, text)
to service_role;

revoke all on table public.sd_development_metric_definitions,
  public.sd_development_import_jobs,
  public.sd_player_metric_observations,
  public.sd_development_reports,
  public.sd_development_report_evidence,
  public.sd_development_report_review_events,
  public.sd_development_alerts,
  public.sd_development_alert_evidence,
  public.sd_development_alert_events
from public, anon, authenticated, service_role;

grant select on public.sd_development_metric_definitions to authenticated;
grant select on public.sd_development_import_jobs to authenticated;
grant select on public.sd_player_metric_observations to authenticated;
grant select on public.sd_development_reports to authenticated;
grant select on public.sd_development_report_evidence to authenticated;
grant select on public.sd_development_report_review_events to authenticated;
grant select on public.sd_development_alerts to authenticated;
grant select on public.sd_development_alert_evidence to authenticated;
grant select on public.sd_development_alert_events to authenticated;

-- service_role is used only by the authenticated Phase 11A Edge Function. The
-- four mutation RPCs receive the actor derived from auth.getUser(), repeat staff
-- scope checks, and are not executable by ordinary authenticated clients.
grant select on public.sd_development_metric_definitions to service_role;
grant select on public.sd_player_metric_observations to service_role;
grant select on public.sd_development_reports to service_role;
grant select on public.sd_development_report_evidence to service_role;
grant select on public.sd_development_report_review_events to service_role;
grant select on public.sd_development_alerts to service_role;
grant select on public.sd_development_alert_evidence to service_role;
grant select on public.sd_development_alert_events to service_role;

insert into public.sd_development_metric_definitions (
  canonical_key, display_name, category, data_type, canonical_unit,
  preferred_direction, valid_aggregations, minimum_sample_size, context_notes
) values
  ('hitting.max_exit_velocity', 'Maximum Exit Velocity', 'hitting', 'number', 'mph', 'higher_is_better', array['latest','best','rolling_average'], 2, 'Interpret with sample size, measurement source, age, and competition context.'),
  ('hitting.average_exit_velocity', 'Average Exit Velocity', 'hitting', 'number', 'mph', 'higher_is_better', array['latest','average','rolling_average'], 3, 'Compare only compatible measurement contexts.'),
  ('hitting.launch_angle', 'Launch Angle', 'hitting', 'number', 'deg', 'context_dependent', array['latest','average','distribution'], 5, 'No universal target applies across all hitters and batted-ball intentions.'),
  ('hitting.hard_hit_rate', 'Hard-hit Rate', 'hitting', 'number', 'percent', 'higher_is_better', array['average','rolling_average'], 10, 'Requires an explicit provider/context definition of hard hit.'),
  ('hitting.contact_rate', 'Contact Rate', 'hitting', 'number', 'percent', 'higher_is_better', array['average','rolling_average'], 10, 'Interpret with pitch quality and competition context.'),
  ('hitting.bat_speed', 'Bat Speed', 'hitting', 'number', 'mph', 'context_dependent', array['latest','average','best'], 3, 'Do not infer mechanics or outcomes from bat speed alone.'),
  ('hitting.attack_angle', 'Attack Angle', 'hitting', 'number', 'deg', 'context_dependent', array['latest','average'], 5, 'Role and batted-ball intention are required for interpretation.'),
  ('hitting.time_to_contact', 'Time to Contact', 'hitting', 'duration', 'ms', 'context_dependent', array['latest','average'], 5, 'Measurement protocol must be comparable.'),
  ('pitching.velocity', 'Pitch Velocity', 'pitching', 'number', 'mph', 'context_dependent', array['latest','average','best'], 5, 'Pitch type, workload, age, and role are required context.'),
  ('pitching.spin_rate', 'Spin Rate', 'pitching', 'number', 'rpm', 'context_dependent', array['latest','average'], 5, 'Interpret with pitch type and movement context.'),
  ('pitching.spin_efficiency', 'Spin Efficiency', 'pitching', 'number', 'percent', 'context_dependent', array['latest','average'], 5, 'Device definitions may differ.'),
  ('pitching.induced_vertical_break', 'Induced Vertical Break', 'pitching', 'number', 'in', 'context_dependent', array['latest','average'], 5, 'Pitch type and release context are required.'),
  ('pitching.horizontal_break', 'Horizontal Break', 'pitching', 'number', 'in', 'context_dependent', array['latest','average'], 5, 'Sign conventions must be normalized by handedness/source.'),
  ('pitching.release_height', 'Release Height', 'pitching', 'number', 'ft', 'informational', array['latest','average'], 5, 'Used as context, not a quality score.'),
  ('pitching.release_side', 'Release Side', 'pitching', 'number', 'ft', 'informational', array['latest','average'], 5, 'Sign conventions must be normalized.'),
  ('pitching.extension', 'Extension', 'pitching', 'number', 'ft', 'context_dependent', array['latest','average'], 5, 'Interpret with delivery and measurement context.'),
  ('pitching.strike_rate', 'Strike Rate', 'pitching', 'number', 'percent', 'higher_is_better', array['average','rolling_average'], 10, 'Competition and pitch-intent context are required.'),
  ('pitching.zone_rate', 'Zone Rate', 'pitching', 'number', 'percent', 'context_dependent', array['average','rolling_average'], 10, 'Zone definitions and intent must be comparable.'),
  ('pitching.command_score', 'Command Score', 'pitching', 'number', null, 'higher_is_better', array['average','rolling_average'], 10, 'Provider scoring definition must be preserved in metadata.'),
  ('pitching.miss_distance', 'Miss Distance', 'pitching', 'number', 'in', 'lower_is_better', array['average','rolling_average'], 10, 'Only comparable target and device contexts should be combined.'),
  ('pitching.miss_direction', 'Miss Direction', 'pitching', 'text', null, 'informational', array['distribution'], 10, 'Direction/sign conventions and intended target must be preserved in metadata.'),
  ('pitching.pitch_usage', 'Pitch Usage', 'pitching', 'number', 'percent', 'context_dependent', array['average','distribution'], 10, 'Pitch type is a required context dimension; usage is not a universal quality score.'),
  ('physical.sprint_time', 'Sprint Time', 'physical_performance', 'duration', 's', 'lower_is_better', array['latest','best','rolling_average'], 2, 'Distance and timing protocol must be preserved.'),
  ('physical.jump_height', 'Jump Height', 'physical_performance', 'number', 'in', 'higher_is_better', array['latest','best','rolling_average'], 2, 'Testing protocol must be comparable.'),
  ('physical.broad_jump', 'Broad Jump', 'physical_performance', 'number', 'in', 'higher_is_better', array['latest','best','rolling_average'], 2, 'Testing protocol must be comparable.'),
  ('physical.height', 'Height', 'physical_performance', 'number', 'in', 'informational', array['latest'], 1, 'Context only; never a development quality judgment.'),
  ('physical.body_weight', 'Body Weight', 'physical_performance', 'number', 'lb', 'informational', array['latest','rolling_average'], 2, 'Sensitive context; do not make medical or body-composition claims.'),
  ('strength.squat_1rm', 'Squat 1RM', 'strength', 'number', 'lb', 'higher_is_better', array['latest','best','rolling_average'], 2, 'Technique, age, and program context are required.'),
  ('strength.bench_1rm', 'Bench Press 1RM', 'strength', 'number', 'lb', 'higher_is_better', array['latest','best','rolling_average'], 2, 'Technique, age, and program context are required.'),
  ('strength.deadlift_1rm', 'Deadlift 1RM', 'strength', 'number', 'lb', 'higher_is_better', array['latest','best','rolling_average'], 2, 'Technique, age, and program context are required.'),
  ('physical.workload', 'Workload', 'physical_performance', 'number', null, 'context_dependent', array['average','rolling_average'], 5, 'Source-specific workload definition must be preserved.'),
  ('consistency.attendance_rate', 'Attendance Rate', 'consistency', 'number', 'percent', 'higher_is_better', array['average','rolling_average'], 5, 'Unavailable until an authoritative attendance ledger exists.'),
  ('consistency.program_completion_rate', 'Program Completion Rate', 'consistency', 'number', 'percent', 'higher_is_better', array['average','rolling_average'], 5, 'Unavailable until an explicit completion ledger exists.'),
  ('consistency.process_adherence_rate', 'Process Adherence Rate', 'consistency', 'number', 'percent', 'higher_is_better', array['average','rolling_average'], 5, 'Adapted from daily-log process responses; missing logs are not failures.'),
  ('mobility.hip_external_rotation_difference', 'Hip External Rotation Difference', 'mobility', 'number', 'deg', 'context_dependent', array['latest','average'], 2, 'Do not infer injury or diagnosis.'),
  ('mobility.hip_internal_rotation_difference', 'Hip Internal Rotation Difference', 'mobility', 'number', 'deg', 'context_dependent', array['latest','average'], 2, 'Do not infer injury or diagnosis.'),
  ('mobility.shoulder_internal_rotation_difference', 'Shoulder Internal Rotation Difference', 'mobility', 'number', 'deg', 'context_dependent', array['latest','average'], 2, 'Do not infer injury or diagnosis.'),
  ('mobility.shoulder_external_rotation_difference', 'Shoulder External Rotation Difference', 'mobility', 'number', 'deg', 'context_dependent', array['latest','average'], 2, 'Do not infer injury or diagnosis.')
on conflict (canonical_key) do nothing;
