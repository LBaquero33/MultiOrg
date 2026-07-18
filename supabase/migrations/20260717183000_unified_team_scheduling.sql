-- Phase 12B: canonical organization -> season -> team scheduling.
--
-- This migration is additive. Program assignments, BP sessions, and facility
-- bookings remain intact as compatibility calendar sources. Facility bookings
-- participate in conflict detection, but are not silently reclassified as team
-- events because their historical team/season meaning is not authoritative.

create table if not exists public.sd_team_event_series (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  organization_id uuid not null references public.sd_orgs(id) on delete cascade,
  season_id uuid not null references public.sd_seasons(id) on delete restrict,
  team_id uuid not null references public.sd_teams(id) on delete restrict,
  frequency text not null check (frequency in ('daily','weekly')),
  interval_count integer not null default 1 check (interval_count between 1 and 52),
  weekdays smallint[] not null default '{}'::smallint[],
  ends_on date,
  occurrence_count integer check (occurrence_count between 1 and 366),
  timezone text not null,
  starts_at timestamptz not null,
  duration_minutes integer not null check (duration_minutes between 1 and 10080),
  status text not null default 'active' check (status in ('active','cancelled')),
  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default pg_catalog.now(),
  updated_at timestamptz not null default pg_catalog.now(),
  cancelled_at timestamptz,
  cancellation_reason text,
  check (pg_catalog.cardinality(weekdays) <= 7),
  check (not (ends_on is not null and occurrence_count is not null))
);

create table if not exists public.sd_team_events (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  organization_id uuid not null references public.sd_orgs(id) on delete cascade,
  season_id uuid not null references public.sd_seasons(id) on delete restrict,
  team_id uuid not null references public.sd_teams(id) on delete restrict,
  series_id uuid references public.sd_team_event_series(id) on delete restrict,
  occurrence_index integer check (occurrence_index is null or occurrence_index >= 0),
  event_type text not null check (event_type in (
    'practice','game','tournament','meeting','travel','custom'
  )),
  title text not null check (pg_catalog.char_length(pg_catalog.btrim(title)) between 1 and 160),
  description text,
  status text not null default 'draft' check (status in (
    'draft','scheduled','confirmed','cancelled','completed','postponed'
  )),
  start_at timestamptz not null,
  end_at timestamptz not null,
  arrival_at timestamptz,
  original_start_at timestamptz not null,
  timezone text not null,
  all_day boolean not null default false,
  location_name text,
  address text,
  facility_id uuid references public.sd_facilities(id) on delete restrict,
  visibility text not null default 'team' check (visibility in ('team','staff_only')),
  notes text,
  metadata jsonb not null default '{}'::jsonb check (pg_catalog.jsonb_typeof(metadata) = 'object'),
  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default pg_catalog.now(),
  updated_at timestamptz not null default pg_catalog.now(),
  cancelled_at timestamptz,
  cancellation_reason text,
  check (end_at > start_at),
  check (arrival_at is null or arrival_at <= start_at),
  check ((status = 'cancelled') = (cancelled_at is not null))
);

create table if not exists public.sd_team_event_practices (
  event_id uuid primary key references public.sd_team_events(id) on delete cascade,
  objectives text[] not null default '{}'::text[],
  dress_code text,
  equipment_notes text,
  practice_plan_status text not null default 'not_started' check (
    practice_plan_status in ('not_started','draft','ready','completed')
  ),
  facility_resource_label text
);

create table if not exists public.sd_team_event_games (
  event_id uuid primary key references public.sd_team_events(id) on delete cascade,
  opponent text not null check (pg_catalog.char_length(pg_catalog.btrim(opponent)) between 1 and 160),
  venue_side text not null default 'home' check (venue_side in ('home','away','neutral')),
  game_status text not null default 'scheduled' check (
    game_status in ('scheduled','warmup','in_progress','final','suspended','forfeit')
  ),
  uniform text,
  home_score integer check (home_score is null or home_score >= 0),
  away_score integer check (away_score is null or away_score >= 0),
  field_details text
);

create table if not exists public.sd_team_event_tournaments (
  event_id uuid primary key references public.sd_team_events(id) on delete cascade,
  tournament_name text not null,
  host text,
  tournament_start_date date not null,
  tournament_end_date date not null,
  parent_tournament_event_id uuid references public.sd_team_events(id) on delete set null,
  check (tournament_end_date >= tournament_start_date)
);

create table if not exists public.sd_team_event_meetings (
  event_id uuid primary key references public.sd_team_events(id) on delete cascade,
  meeting_type text not null default 'team' check (
    meeting_type in ('team','staff','player','parent','video','other')
  ),
  virtual_link text
);

create table if not exists public.sd_team_event_travel (
  event_id uuid primary key references public.sd_team_events(id) on delete cascade,
  departure_at timestamptz,
  destination text not null,
  transportation_notes text,
  lodging_notes text
);

create table if not exists public.sd_team_event_coaches (
  event_id uuid not null references public.sd_team_events(id) on delete cascade,
  coach_id uuid not null references auth.users(id) on delete cascade,
  assignment_role text not null default 'assigned',
  created_at timestamptz not null default pg_catalog.now(),
  primary key (event_id, coach_id)
);

create table if not exists public.sd_team_event_audit_logs (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  organization_id uuid not null references public.sd_orgs(id) on delete cascade,
  season_id uuid not null references public.sd_seasons(id) on delete restrict,
  team_id uuid not null references public.sd_teams(id) on delete restrict,
  event_id uuid,
  series_id uuid,
  actor_id uuid references auth.users(id) on delete set null,
  action text not null check (action in (
    'created','published','edited','rescheduled','cancelled','draft_deleted',
    'recurrence_changed','series_cancelled','conflict_override','visibility_changed','duplicated','postponed'
  )),
  request_id uuid not null,
  reason text,
  details jsonb not null default '{}'::jsonb check (pg_catalog.jsonb_typeof(details) = 'object'),
  created_at timestamptz not null default pg_catalog.now(),
  unique (organization_id, request_id, action)
);

create table if not exists public.sd_team_event_notification_intents (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  organization_id uuid not null references public.sd_orgs(id) on delete cascade,
  team_id uuid not null references public.sd_teams(id) on delete restrict,
  event_id uuid not null references public.sd_team_events(id) on delete cascade,
  intent_type text not null check (intent_type in (
    'new_event','time_change','location_change','cancellation','postponement'
  )),
  deduplication_key text not null,
  payload jsonb not null default '{}'::jsonb check (pg_catalog.jsonb_typeof(payload) = 'object'),
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default pg_catalog.now(),
  consumed_at timestamptz,
  unique (organization_id, deduplication_key)
);

-- Composite foreign keys make organization/season/team isolation structural,
-- including for series rows that never pass through the event trigger.
create unique index if not exists uq_sd_seasons_id_organization
  on public.sd_seasons(id, organization_id);
create unique index if not exists uq_sd_teams_id_organization_season
  on public.sd_teams(id, org_id, season_id);
alter table public.sd_team_event_series
  add constraint sd_team_event_series_season_scope_fk
  foreign key (season_id, organization_id)
  references public.sd_seasons(id, organization_id) on delete restrict;
alter table public.sd_team_event_series
  add constraint sd_team_event_series_team_scope_fk
  foreign key (team_id, organization_id, season_id)
  references public.sd_teams(id, org_id, season_id) on delete restrict;
alter table public.sd_team_events
  add constraint sd_team_events_season_scope_fk
  foreign key (season_id, organization_id)
  references public.sd_seasons(id, organization_id) on delete restrict;
alter table public.sd_team_events
  add constraint sd_team_events_team_scope_fk
  foreign key (team_id, organization_id, season_id)
  references public.sd_teams(id, org_id, season_id) on delete restrict;

create index if not exists idx_sd_team_events_scope_start
  on public.sd_team_events(organization_id, season_id, team_id, start_at, end_at);
create index if not exists idx_sd_team_events_active_conflicts
  on public.sd_team_events(team_id, start_at, end_at)
  where status <> 'cancelled';
create index if not exists idx_sd_team_events_facility_conflicts
  on public.sd_team_events(facility_id, start_at, end_at)
  where facility_id is not null and status <> 'cancelled';
create index if not exists idx_sd_team_events_series
  on public.sd_team_events(series_id, occurrence_index);
create unique index if not exists uq_sd_team_events_series_occurrence
  on public.sd_team_events(series_id, occurrence_index)
  where series_id is not null;
create index if not exists idx_sd_team_event_coaches_conflicts
  on public.sd_team_event_coaches(coach_id, event_id);
create index if not exists idx_sd_team_event_series_scope
  on public.sd_team_event_series(organization_id, season_id, team_id, status, starts_at);
create index if not exists idx_sd_team_event_audit_scope
  on public.sd_team_event_audit_logs(organization_id, team_id, created_at desc);
create index if not exists idx_sd_team_event_intents_pending
  on public.sd_team_event_notification_intents(organization_id, created_at)
  where consumed_at is null;

drop trigger if exists trg_sd_team_event_series_updated_at on public.sd_team_event_series;
create trigger trg_sd_team_event_series_updated_at before update on public.sd_team_event_series
for each row execute function public.sd_set_updated_at();
drop trigger if exists trg_sd_team_events_updated_at on public.sd_team_events;
create trigger trg_sd_team_events_updated_at before update on public.sd_team_events
for each row execute function public.sd_set_updated_at();

-- Extend the Phase 12A resolver; this remains the only responsibility mapping.
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
    select role from public.sd_org_memberships
    where org_id = target_organization and user_id = target_actor and status = 'active'
  ), responsibilities as (
    select distinct r.responsibility
    from public.sd_coach_team_assignments a
    join public.sd_coach_team_responsibilities r on r.assignment_id = a.id
    where a.organization_id = target_organization
      and (a.team_id = target_team or a.organization_wide_access)
      and a.coach_id = target_actor and a.active and a.ended_at is null
  ), resolved(capability) as (
    select pg_catalog.unnest(array[
      'view_team','manage_roster','manage_schedule','manage_attendance','manage_practice','manage_game',
      'message_team','view_development','edit_development','manage_staff','view_documents','manage_documents',
      'view_team_schedule','create_team_event','edit_team_event','cancel_team_event','manage_practice_event',
      'manage_game_event','manage_tournament_event','manage_meeting_event','manage_travel_event'
    ]) where exists (select 1 from actor_membership where role in ('owner','admin'))
    union
    select pg_catalog.unnest(array[
      'view_team','manage_roster','manage_schedule','manage_attendance','manage_practice','manage_game',
      'message_team','view_development','edit_development','manage_staff','view_documents','manage_documents',
      'view_team_schedule','create_team_event','edit_team_event','cancel_team_event','manage_practice_event',
      'manage_game_event','manage_tournament_event','manage_meeting_event','manage_travel_event'
    ]) where exists (select 1 from responsibilities where responsibility in ('head_coach','team_manager'))
    union
    select pg_catalog.unnest(array[
      'view_team','manage_roster','manage_schedule','manage_attendance','manage_practice','manage_game',
      'message_team','view_development','edit_development','view_documents','view_team_schedule',
      'create_team_event','edit_team_event','cancel_team_event','manage_practice_event','manage_game_event',
      'manage_tournament_event','manage_meeting_event','manage_travel_event'
    ]) where exists (select 1 from responsibilities where responsibility = 'assistant_coach')
    union
    select pg_catalog.unnest(array[
      'view_team','manage_practice','view_development','edit_development','view_documents','view_team_schedule'
    ]) where exists (select 1 from responsibilities where responsibility in (
      'hitting_coach','pitching_coach','catching_coach','strength_coach'
    ))
    union
    select pg_catalog.unnest(array['view_team','view_development','edit_development','view_documents','view_team_schedule'])
      where exists (select 1 from responsibilities where responsibility = 'evaluator')
    union
    select pg_catalog.unnest(array['view_team','view_development','view_documents','view_team_schedule'])
      where exists (select 1 from responsibilities where responsibility = 'read_only')
  )
  select coalesce(pg_catalog.array_agg(capability order by capability), '{}'::text[]) from resolved;
$$;

create or replace function public.sd_validate_team_event_scope()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (
    select 1 from public.sd_teams team
    join public.sd_seasons season on season.id = new.season_id
    where team.id = new.team_id and team.org_id = new.organization_id
      and team.season_id = new.season_id and season.organization_id = new.organization_id
  ) then
    raise exception 'team_event_scope_mismatch' using errcode = '23514';
  end if;
  if new.series_id is not null and not exists (
    select 1 from public.sd_team_event_series series
    where series.id = new.series_id and series.organization_id = new.organization_id
      and series.season_id = new.season_id and series.team_id = new.team_id
  ) then
    raise exception 'team_event_series_scope_mismatch' using errcode = '23514';
  end if;
  if new.facility_id is not null and not exists (
    select 1 from public.sd_facilities facility
    where facility.id = new.facility_id and facility.org_id = new.organization_id
  ) then
    raise exception 'team_event_facility_scope_mismatch' using errcode = '23514';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_sd_validate_team_event_scope on public.sd_team_events;
create trigger trg_sd_validate_team_event_scope before insert or update on public.sd_team_events
for each row execute function public.sd_validate_team_event_scope();

create or replace function public.sd_team_event_conflicts(
  p_organization_id uuid,
  p_team_id uuid,
  p_start_at timestamptz,
  p_end_at timestamptz,
  p_facility_id uuid default null,
  p_coach_ids uuid[] default '{}'::uuid[],
  p_exclude_event_id uuid default null
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  with candidate as (
    select event.id, event.title, 'team'::text conflict_type
    from public.sd_team_events event
    where event.organization_id = p_organization_id and event.team_id = p_team_id
      and event.status <> 'cancelled' and event.id is distinct from p_exclude_event_id
      and pg_catalog.tstzrange(event.start_at,event.end_at,'[)') && pg_catalog.tstzrange(p_start_at,p_end_at,'[)')
    union all
    select event.id, event.title, 'facility'::text
    from public.sd_team_events event
    where p_facility_id is not null and event.organization_id = p_organization_id
      and event.facility_id = p_facility_id and event.status <> 'cancelled'
      and event.id is distinct from p_exclude_event_id
      and pg_catalog.tstzrange(event.start_at,event.end_at,'[)') && pg_catalog.tstzrange(p_start_at,p_end_at,'[)')
    union all
    select event.id, event.title, 'coach'::text
    from public.sd_team_events event
    join public.sd_team_event_coaches coach on coach.event_id = event.id
    where event.organization_id = p_organization_id and event.status <> 'cancelled'
      and event.id is distinct from p_exclude_event_id and coach.coach_id = any(p_coach_ids)
      and pg_catalog.tstzrange(event.start_at,event.end_at,'[)') && pg_catalog.tstzrange(p_start_at,p_end_at,'[)')
    union all
    select booking.id, coalesce(booking.title,'Facility booking'), 'facility_booking'::text
    from public.sd_facility_bookings booking
    join public.sd_facilities facility on facility.id = booking.facility_id
    where p_facility_id is not null and facility.org_id = p_organization_id
      and booking.facility_id = p_facility_id and booking.status = 'approved'
      and pg_catalog.tstzrange(booking.start_at,booking.end_at,'[)') && pg_catalog.tstzrange(p_start_at,p_end_at,'[)')
  )
  select coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
    'id', id, 'title', title, 'type', conflict_type
  ) order by conflict_type,title), '[]'::jsonb) from candidate;
$$;

-- Tables are server-mediated so public/player shapes can never expose notes.
alter table public.sd_team_event_series enable row level security;
alter table public.sd_team_events enable row level security;
alter table public.sd_team_event_practices enable row level security;
alter table public.sd_team_event_games enable row level security;
alter table public.sd_team_event_tournaments enable row level security;
alter table public.sd_team_event_meetings enable row level security;
alter table public.sd_team_event_travel enable row level security;
alter table public.sd_team_event_coaches enable row level security;
alter table public.sd_team_event_audit_logs enable row level security;
alter table public.sd_team_event_notification_intents enable row level security;

revoke all on table public.sd_team_event_series, public.sd_team_events,
  public.sd_team_event_practices, public.sd_team_event_games,
  public.sd_team_event_tournaments, public.sd_team_event_meetings,
  public.sd_team_event_travel, public.sd_team_event_coaches,
  public.sd_team_event_audit_logs, public.sd_team_event_notification_intents
from public, anon, authenticated;
grant select, insert, update, delete on table public.sd_team_event_series, public.sd_team_events,
  public.sd_team_event_practices, public.sd_team_event_games,
  public.sd_team_event_tournaments, public.sd_team_event_meetings,
  public.sd_team_event_travel, public.sd_team_event_coaches,
  public.sd_team_event_audit_logs, public.sd_team_event_notification_intents
to service_role;

revoke all on function public.sd_team_event_conflicts(uuid,uuid,timestamptz,timestamptz,uuid,uuid[],uuid)
  from public, anon, authenticated;
grant execute on function public.sd_team_event_conflicts(uuid,uuid,timestamptz,timestamptz,uuid,uuid[],uuid)
  to service_role;
revoke all on function public.sd_validate_team_event_scope() from public, anon, authenticated;

comment on table public.sd_team_events is
  'Canonical materialized team-event occurrences. Staff-private notes are returned only by the scheduling service.';
comment on table public.sd_team_event_notification_intents is
  'Deterministic scheduling notification intents only. Phase 12B does not dispatch APNs or create inbox notifications.';
comment on table public.sd_team_event_series is
  'Editable recurrence definition; occurrence rows retain deterministic index and original start.';
