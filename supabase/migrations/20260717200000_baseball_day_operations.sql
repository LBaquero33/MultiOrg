-- Phase 12C: canonical baseball day operations.
--
-- Additive compatibility: Phase 12B events remain the schedule authority. Existing
-- program assignments, BP sessions, daily logs, and facility bookings are retained.
-- Home Plate previously had no authoritative attendance ledger, so no legacy rows
-- are silently promoted into attendance. Rollback before client adoption consists
-- of dropping these new tables and restoring the Phase 12B capability resolver and
-- notification-intent constraint; no existing user or baseball records are rewritten.
-- Rollback must first drop the notification-intent operation-scope foreign key
-- and event_operation_id column, then drop these tables/function, and finally
-- restore the Phase 12B intent constraint and capability resolver.

alter table public.sd_team_events
  add constraint sd_team_events_operation_scope_key
  unique (id, organization_id, season_id, team_id);

create table if not exists public.sd_event_operations (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  organization_id uuid not null references public.sd_orgs(id) on delete cascade,
  season_id uuid not null references public.sd_seasons(id) on delete restrict,
  team_id uuid not null references public.sd_teams(id) on delete restrict,
  event_id uuid not null references public.sd_team_events(id) on delete restrict,
  operation_type text not null check (operation_type in (
    'practice_day','game_day','tournament_day','meeting_day','travel_day','general_event_day'
  )),
  status text not null default 'not_started' check (status in (
    'not_started','ready','in_progress','paused','completed','cancelled'
  )),
  scheduled_start_at timestamptz not null,
  started_at timestamptz,
  started_by uuid references auth.users(id) on delete set null,
  completed_at timestamptz,
  completed_by uuid references auth.users(id) on delete set null,
  reopened_at timestamptz,
  reopened_by uuid references auth.users(id) on delete set null,
  cancelled_at timestamptz,
  operational_summary text,
  internal_notes text,
  attendance_finalized_at timestamptz,
  attendance_finalized_by uuid references auth.users(id) on delete set null,
  version integer not null default 1 check (version > 0),
  created_at timestamptz not null default pg_catalog.now(),
  updated_at timestamptz not null default pg_catalog.now(),
  check (status <> 'completed' or completed_at is not null),
  check (status <> 'cancelled' or cancelled_at is not null),
  unique (event_id),
  unique (id, organization_id),
  unique (id, organization_id, season_id, team_id, event_id),
  foreign key (event_id, organization_id, season_id, team_id)
    references public.sd_team_events(id, organization_id, season_id, team_id)
    on delete restrict
);

create table if not exists public.sd_event_operation_participants (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  event_operation_id uuid not null references public.sd_event_operations(id) on delete cascade,
  organization_id uuid not null references public.sd_orgs(id) on delete cascade,
  season_id uuid not null references public.sd_seasons(id) on delete restrict,
  team_id uuid not null references public.sd_teams(id) on delete restrict,
  event_id uuid not null references public.sd_team_events(id) on delete restrict,
  user_id uuid not null references auth.users(id) on delete restrict,
  participant_type text not null check (participant_type in ('player','coach','staff')),
  expected boolean not null default true,
  availability_status text not null default 'unknown' check (availability_status in (
    'unknown','available','unavailable','tentative','late','leaving_early'
  )),
  availability_reason text,
  expected_arrival_at timestamptz,
  expected_departure_at timestamptz,
  availability_submitted_by uuid references auth.users(id) on delete set null,
  availability_submitted_at timestamptz,
  availability_last_changed_at timestamptz,
  attendance_status text not null default 'not_recorded' check (attendance_status in (
    'not_recorded','present','absent','late','excused','injured','partial'
  )),
  arrival_at timestamptz,
  departure_at timestamptz,
  checked_in_by uuid references auth.users(id) on delete set null,
  attendance_notes text,
  private_notes text,
  version integer not null default 1 check (version > 0),
  created_at timestamptz not null default pg_catalog.now(),
  updated_at timestamptz not null default pg_catalog.now(),
  unique (event_operation_id, user_id),
  foreign key (event_operation_id, organization_id, season_id, team_id, event_id)
    references public.sd_event_operations(id, organization_id, season_id, team_id, event_id)
    on delete cascade
);

create table if not exists public.sd_event_operation_checklist_items (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  event_operation_id uuid not null references public.sd_event_operations(id) on delete cascade,
  organization_id uuid not null references public.sd_orgs(id) on delete cascade,
  phase text not null check (phase in ('pre_event','active_event','post_event')),
  title text not null check (pg_catalog.char_length(pg_catalog.btrim(title)) between 1 and 160),
  details text,
  assigned_user_id uuid references auth.users(id) on delete set null,
  due_at timestamptz,
  completed_at timestamptz,
  completed_by uuid references auth.users(id) on delete set null,
  overridden_at timestamptz,
  overridden_by uuid references auth.users(id) on delete set null,
  override_reason text,
  sort_order integer not null default 0,
  source text not null default 'system' check (source in ('system','event','organization_template','coach')),
  required boolean not null default false,
  visibility text not null default 'staff' check (visibility in ('staff','team')),
  version integer not null default 1 check (version > 0),
  created_at timestamptz not null default pg_catalog.now(),
  updated_at timestamptz not null default pg_catalog.now(),
  unique (event_operation_id, source, title),
  foreign key (event_operation_id, organization_id)
    references public.sd_event_operations(id, organization_id) on delete cascade
);

create table if not exists public.sd_event_operation_notes (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  event_operation_id uuid not null references public.sd_event_operations(id) on delete cascade,
  organization_id uuid not null references public.sd_orgs(id) on delete cascade,
  note_type text not null check (note_type in (
    'team_coach_note','internal_staff_note','player_coach_note','post_event_recap'
  )),
  visibility text not null check (visibility in ('staff','team','player')),
  subject_player_id uuid references auth.users(id) on delete restrict,
  body text not null check (pg_catalog.char_length(pg_catalog.btrim(body)) between 1 and 8000),
  published_at timestamptz,
  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  version integer not null default 1 check (version > 0),
  created_at timestamptz not null default pg_catalog.now(),
  updated_at timestamptz not null default pg_catalog.now(),
  check (
    (note_type = 'internal_staff_note' and visibility = 'staff' and subject_player_id is null) or
    (note_type = 'player_coach_note' and visibility in ('staff','player') and subject_player_id is not null) or
    (note_type = 'team_coach_note' and visibility in ('staff','team') and subject_player_id is null) or
    (note_type = 'post_event_recap' and visibility = 'team' and subject_player_id is null)
  ),
  foreign key (event_operation_id, organization_id)
    references public.sd_event_operations(id, organization_id) on delete cascade
);

create table if not exists public.sd_event_operation_versions (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  event_operation_id uuid not null references public.sd_event_operations(id) on delete restrict,
  organization_id uuid not null references public.sd_orgs(id) on delete cascade,
  operation_version integer not null,
  snapshot jsonb not null check (pg_catalog.jsonb_typeof(snapshot) = 'object'),
  reason text,
  captured_by uuid references auth.users(id) on delete set null,
  captured_at timestamptz not null default pg_catalog.now(),
  unique (event_operation_id, operation_version),
  foreign key (event_operation_id, organization_id)
    references public.sd_event_operations(id, organization_id) on delete restrict
);

create table if not exists public.sd_event_operation_audit_logs (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  organization_id uuid not null references public.sd_orgs(id) on delete cascade,
  season_id uuid not null references public.sd_seasons(id) on delete restrict,
  team_id uuid not null references public.sd_teams(id) on delete restrict,
  event_id uuid not null references public.sd_team_events(id) on delete restrict,
  event_operation_id uuid not null references public.sd_event_operations(id) on delete restrict,
  actor_id uuid references auth.users(id) on delete set null,
  action text not null check (action in (
    'initialized','prepared','started','paused','resumed','completed','reopened',
    'attendance_changed','attendance_bulk_changed','attendance_corrected','attendance_finalized',
    'availability_declared','availability_overridden','participants_reconciled',
    'checklist_completed','checklist_uncompleted','checklist_overridden','note_created','note_edited',
    'visibility_changed','recap_published'
  )),
  request_id uuid not null,
  target_id uuid,
  previous_value jsonb,
  new_value jsonb,
  reason text,
  details jsonb not null default '{}'::jsonb check (pg_catalog.jsonb_typeof(details) = 'object'),
  created_at timestamptz not null default pg_catalog.now(),
  unique (organization_id, request_id, action),
  foreign key (event_operation_id, organization_id, season_id, team_id, event_id)
    references public.sd_event_operations(id, organization_id, season_id, team_id, event_id)
    on delete restrict
);

create table if not exists public.sd_event_operation_mutations (
  organization_id uuid not null references public.sd_orgs(id) on delete cascade,
  request_id uuid not null,
  action text not null,
  actor_id uuid not null references auth.users(id) on delete restrict,
  event_id uuid not null references public.sd_team_events(id) on delete restrict,
  event_operation_id uuid,
  request_fingerprint text not null,
  status text not null default 'processing' check (status in ('processing','completed')),
  response jsonb,
  created_at timestamptz not null default pg_catalog.now(),
  completed_at timestamptz,
  primary key (organization_id, request_id),
  foreign key (event_operation_id, organization_id)
    references public.sd_event_operations(id, organization_id) on delete restrict
);

create index if not exists idx_sd_event_operations_scope
  on public.sd_event_operations(organization_id, season_id, team_id, scheduled_start_at, status);
create index if not exists idx_sd_event_operations_event
  on public.sd_event_operations(event_id, status);
create index if not exists idx_sd_event_operation_participants_scope
  on public.sd_event_operation_participants(organization_id, team_id, event_id, participant_type);
create index if not exists idx_sd_event_operation_participants_attendance
  on public.sd_event_operation_participants(event_operation_id, attendance_status, expected);
create index if not exists idx_sd_event_operation_participants_availability
  on public.sd_event_operation_participants(event_operation_id, availability_status, expected);
create index if not exists idx_sd_event_operation_checklist_progress
  on public.sd_event_operation_checklist_items(event_operation_id, phase, required, completed_at);
create index if not exists idx_sd_event_operation_notes_visibility
  on public.sd_event_operation_notes(event_operation_id, visibility, subject_player_id);
create index if not exists idx_sd_event_operation_audit_scope
  on public.sd_event_operation_audit_logs(organization_id, team_id, event_id, created_at desc);

drop trigger if exists trg_sd_event_operations_updated_at on public.sd_event_operations;
create trigger trg_sd_event_operations_updated_at before update on public.sd_event_operations
for each row execute function public.sd_set_updated_at();
drop trigger if exists trg_sd_event_operation_participants_updated_at on public.sd_event_operation_participants;
create trigger trg_sd_event_operation_participants_updated_at before update on public.sd_event_operation_participants
for each row execute function public.sd_set_updated_at();
drop trigger if exists trg_sd_event_operation_checklist_updated_at on public.sd_event_operation_checklist_items;
create trigger trg_sd_event_operation_checklist_updated_at before update on public.sd_event_operation_checklist_items
for each row execute function public.sd_set_updated_at();
drop trigger if exists trg_sd_event_operation_notes_updated_at on public.sd_event_operation_notes;
create trigger trg_sd_event_operation_notes_updated_at before update on public.sd_event_operation_notes
for each row execute function public.sd_set_updated_at();

-- Continue using the Phase 12B deterministic intent outbox. Nothing here sends
-- APNs, email, SMS, or inbox notifications.
alter table public.sd_team_event_notification_intents
  add column if not exists event_operation_id uuid;
alter table public.sd_team_event_notification_intents
  add constraint sd_team_event_notification_intents_operation_scope_fk
  foreign key (event_operation_id, organization_id)
  references public.sd_event_operations(id, organization_id) on delete cascade;
alter table public.sd_team_event_notification_intents
  drop constraint if exists sd_team_event_notification_intents_intent_type_check;
alter table public.sd_team_event_notification_intents
  add constraint sd_team_event_notification_intents_intent_type_check check (intent_type in (
    'new_event','time_change','location_change','cancellation','postponement',
    'availability_changed','player_unavailable','operation_started','arrival_reminder',
    'event_completed','recap_published','late_schedule_change','attendance_correction'
  ));

-- All Phase 12C mutations, their audits, deterministic outbox intents, and the
-- idempotency receipt commit in this single PostgreSQL transaction. The function
-- is service-role-only; the Edge Function remains the authenticated authorization
-- and response-redaction boundary.
create or replace function public.sd_apply_event_operation_mutation(
  p_organization_id uuid,
  p_event_id uuid,
  p_actor_id uuid,
  p_action text,
  p_request_id uuid,
  p_staff boolean,
  p_payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_event public.sd_team_events%rowtype;
  v_operation public.sd_event_operations%rowtype;
  v_participant public.sd_event_operation_participants%rowtype;
  v_item public.sd_event_operation_checklist_items%rowtype;
  v_note public.sd_event_operation_notes%rowtype;
  v_receipt public.sd_event_operation_mutations%rowtype;
  v_created boolean := false;
  v_claimed integer := 0;
  v_expected integer;
  v_count integer := 0;
  v_changed integer := 0;
  v_now timestamptz := pg_catalog.now();
  v_status text;
  v_prior_operation_status text;
  v_reason text;
  v_fingerprint text;
  v_previous jsonb;
  v_rows jsonb := '[]'::jsonb;
  v_response jsonb;
  v_prior_event_status text;
begin
  if p_payload is null or pg_catalog.jsonb_typeof(p_payload) <> 'object' then
    raise exception using errcode = 'P0001', message = 'invalid_mutation_payload';
  end if;

  v_fingerprint := pg_catalog.encode(
    extensions.digest(
      pg_catalog.convert_to(
        pg_catalog.jsonb_build_object(
          'event_id', p_event_id,
          'action', p_action,
          'staff', p_staff,
          'payload', p_payload
        )::text,
        'UTF8'
      ),
      'sha256'
    ),
    'hex'
  );

  insert into public.sd_event_operation_mutations (
    organization_id, request_id, action, actor_id, event_id, request_fingerprint
  ) values (
    p_organization_id, p_request_id, p_action, p_actor_id, p_event_id, v_fingerprint
  ) on conflict (organization_id, request_id) do nothing;
  get diagnostics v_claimed = row_count;

  if v_claimed = 0 then
    select * into v_receipt
    from public.sd_event_operation_mutations
    where organization_id = p_organization_id and request_id = p_request_id
    for update;
    if v_receipt.actor_id <> p_actor_id
      or v_receipt.event_id <> p_event_id
      or v_receipt.action <> p_action
      or v_receipt.request_fingerprint <> v_fingerprint then
      raise exception using errcode = 'P0001', message = 'idempotency_mismatch';
    end if;
    if v_receipt.status = 'completed' and v_receipt.response is not null then
      return v_receipt.response || pg_catalog.jsonb_build_object('replayed', true);
    end if;
    raise exception using errcode = 'P0001', message = 'mutation_in_progress';
  end if;

  select * into v_event
  from public.sd_team_events
  where id = p_event_id and organization_id = p_organization_id
  for update;
  if not found then
    raise exception using errcode = 'P0001', message = 'event_not_found';
  end if;

  select * into v_operation
  from public.sd_event_operations
  where event_id = p_event_id and organization_id = p_organization_id
  for update;

  if not found and p_action in ('initialize', 'availability') then
    insert into public.sd_event_operations (
      organization_id, season_id, team_id, event_id, operation_type,
      status, scheduled_start_at
    ) values (
      p_organization_id,
      v_event.season_id,
      v_event.team_id,
      v_event.id,
      case v_event.event_type
        when 'practice' then 'practice_day'
        when 'game' then 'game_day'
        when 'tournament' then 'tournament_day'
        when 'meeting' then 'meeting_day'
        when 'travel' then 'travel_day'
        else 'general_event_day'
      end,
      'not_started',
      v_event.start_at
    ) returning * into v_operation;
    v_created := true;

    insert into public.sd_event_operation_participants (
      event_operation_id, organization_id, season_id, team_id, event_id,
      user_id, participant_type, expected
    )
    select v_operation.id, p_organization_id, v_event.season_id,
      v_event.team_id, v_event.id, membership.player_id, 'player', true
    from public.sd_player_team_memberships membership
    where membership.organization_id = p_organization_id
      and membership.season_id = v_event.season_id
      and membership.team_id = v_event.team_id
      and membership.active and membership.ended_at is null
    on conflict (event_operation_id, user_id) do nothing;

    insert into public.sd_event_operation_participants (
      event_operation_id, organization_id, season_id, team_id, event_id,
      user_id, participant_type, expected
    )
    select distinct v_operation.id, p_organization_id, v_event.season_id,
      v_event.team_id, v_event.id, coaches.coach_id, 'coach', true
    from (
      select event_coach.coach_id
      from public.sd_team_event_coaches event_coach
      where event_coach.event_id = v_event.id
      union
      select assignment.coach_id
      from public.sd_coach_team_assignments assignment
      where assignment.organization_id = p_organization_id
        and assignment.season_id = v_event.season_id
        and assignment.team_id = v_event.team_id
        and assignment.active and assignment.ended_at is null
        and not exists (
          select 1 from public.sd_team_event_coaches assigned
          where assigned.event_id = v_event.id
        )
    ) coaches
    on conflict (event_operation_id, user_id) do nothing;

    insert into public.sd_event_operation_checklist_items (
      event_operation_id, organization_id, phase, title, details,
      sort_order, source, required, visibility
    ) values (
      v_operation.id, p_organization_id, 'pre_event',
      'Review expected participants and attendance', null,
      10, 'system', true, 'staff'
    );

    if v_event.arrival_at is not null or v_event.location_name is not null then
      insert into public.sd_event_operation_checklist_items (
        event_operation_id, organization_id, phase, title, details,
        sort_order, source, required, visibility
      ) values (
        v_operation.id, p_organization_id, 'pre_event',
        'Confirm configured arrival and location details',
        pg_catalog.concat_ws(' • ', v_event.arrival_at::text, v_event.location_name),
        20, 'event', false, 'team'
      );
    end if;

    if v_event.event_type = 'game' and exists (
      select 1 from public.sd_team_event_games game
      where game.event_id = v_event.id and nullif(pg_catalog.btrim(game.uniform), '') is not null
    ) then
      insert into public.sd_event_operation_checklist_items (
        event_operation_id, organization_id, phase, title, details,
        sort_order, source, required, visibility
      )
      select v_operation.id, p_organization_id, 'pre_event',
        'Confirm configured uniform', game.uniform,
        30, 'event', true, 'team'
      from public.sd_team_event_games game where game.event_id = v_event.id;
    end if;

    if v_event.arrival_at is not null and v_event.arrival_at > v_now then
      insert into public.sd_team_event_notification_intents (
        organization_id, team_id, event_id, event_operation_id, intent_type,
        deduplication_key, payload, created_by
      ) values (
        p_organization_id, v_event.team_id, v_event.id, v_operation.id,
        'arrival_reminder',
        v_event.id::text || ':' || v_event.arrival_at::text || ':arrival-reminder',
        pg_catalog.jsonb_build_object('arrival_at', v_event.arrival_at), p_actor_id
      ) on conflict (organization_id, deduplication_key) do nothing;
    end if;

    insert into public.sd_event_operation_audit_logs (
      organization_id, season_id, team_id, event_id, event_operation_id,
      actor_id, action, request_id, details
    ) values (
      p_organization_id, v_event.season_id, v_event.team_id, v_event.id,
      v_operation.id, p_actor_id, 'initialized', p_request_id,
      pg_catalog.jsonb_build_object(
        'participant_count', (
          select pg_catalog.count(*) from public.sd_event_operation_participants
          where event_operation_id = v_operation.id
        )
      )
    );
  elsif not found then
    raise exception using errcode = 'P0001', message = 'operation_not_initialized';
  end if;

  update public.sd_event_operation_mutations
  set event_operation_id = v_operation.id
  where organization_id = p_organization_id and request_id = p_request_id;

  if p_action = 'initialize' then
    v_response := pg_catalog.jsonb_build_object(
      'operation_id', v_operation.id,
      'operation', pg_catalog.to_jsonb(v_operation),
      'initialized', v_created
    );

  elsif p_action = 'availability' then
    if v_event.status in ('draft', 'cancelled', 'completed', 'postponed') then
      raise exception using errcode = 'P0001', message = 'availability_closed';
    end if;
    select * into v_participant
    from public.sd_event_operation_participants
    where event_operation_id = v_operation.id
      and user_id = (p_payload->>'player_id')::uuid
      and participant_type = 'player'
    for update;
    if not found then
      raise exception using errcode = 'P0001', message = 'participant_not_found';
    end if;
    if p_payload->>'participant_version' is null then
      if v_created then v_expected := v_participant.version;
      else raise exception using errcode = 'P0001', message = 'missing_expected_version';
      end if;
    else
      v_expected := (p_payload->>'participant_version')::integer;
    end if;
    if v_participant.version <> v_expected then
      raise exception using errcode = 'P0001', message = 'stale_version';
    end if;
    v_previous := pg_catalog.jsonb_build_object(
      'status', v_participant.availability_status,
      'reason', v_participant.availability_reason,
      'expected_arrival_at', v_participant.expected_arrival_at,
      'expected_departure_at', v_participant.expected_departure_at,
      'version', v_participant.version
    );
    update public.sd_event_operation_participants
    set availability_status = p_payload->>'availability_status',
      availability_reason = nullif(pg_catalog.btrim(p_payload->>'reason'), ''),
      expected_arrival_at = nullif(p_payload->>'expected_arrival_at', '')::timestamptz,
      expected_departure_at = nullif(p_payload->>'expected_departure_at', '')::timestamptz,
      availability_submitted_by = p_actor_id,
      availability_submitted_at = pg_catalog.coalesce(availability_submitted_at, v_now),
      availability_last_changed_at = v_now,
      version = version + 1
    where id = v_participant.id
    returning * into v_participant;
    insert into public.sd_event_operation_audit_logs (
      organization_id, season_id, team_id, event_id, event_operation_id,
      actor_id, action, request_id, target_id, previous_value, new_value, reason
    ) values (
      p_organization_id, v_event.season_id, v_event.team_id, v_event.id,
      v_operation.id, p_actor_id,
      case when p_staff then 'availability_overridden' else 'availability_declared' end,
      p_request_id, v_participant.id, v_previous,
      pg_catalog.jsonb_build_object(
        'status', v_participant.availability_status,
        'reason', v_participant.availability_reason,
        'expected_arrival_at', v_participant.expected_arrival_at,
        'expected_departure_at', v_participant.expected_departure_at,
        'version', v_participant.version
      ),
      case when p_staff then nullif(pg_catalog.btrim(p_payload->>'override_reason'), '') else null end
    );
    insert into public.sd_team_event_notification_intents (
      organization_id, team_id, event_id, event_operation_id, intent_type,
      deduplication_key, payload, created_by
    ) values (
      p_organization_id, v_event.team_id, v_event.id, v_operation.id,
      'availability_changed', p_request_id::text || ':' || v_operation.id::text || ':availability',
      pg_catalog.jsonb_build_object('player_id', v_participant.user_id, 'status', v_participant.availability_status),
      p_actor_id
    );
    if v_participant.availability_status = 'unavailable' then
      insert into public.sd_team_event_notification_intents (
        organization_id, team_id, event_id, event_operation_id, intent_type,
        deduplication_key, payload, created_by
      ) values (
        p_organization_id, v_event.team_id, v_event.id, v_operation.id,
        'player_unavailable', p_request_id::text || ':' || v_operation.id::text || ':unavailable',
        pg_catalog.jsonb_build_object('player_id', v_participant.user_id), p_actor_id
      );
    end if;
    v_response := pg_catalog.jsonb_build_object(
      'operation_id', v_operation.id, 'participant', pg_catalog.to_jsonb(v_participant),
      'attention', v_event.start_at between v_now - interval '6 hours' and v_now + interval '24 hours'
    );

  elsif p_action = 'transition' then
    if v_event.status in ('draft', 'cancelled', 'postponed') then
      raise exception using errcode = 'P0001', message = 'event_not_operable';
    end if;
    if p_payload->>'expected_version' is null then
      raise exception using errcode = 'P0001', message = 'missing_expected_version';
    end if;
    v_expected := (p_payload->>'expected_version')::integer;
    if v_operation.version <> v_expected then
      raise exception using errcode = 'P0001', message = 'stale_version';
    end if;
    v_status := p_payload->>'status';
    v_prior_operation_status := v_operation.status;
    v_reason := nullif(pg_catalog.btrim(p_payload->>'reason'), '');
    if not (
      (v_operation.status = 'not_started' and v_status in ('ready','in_progress')) or
      (v_operation.status = 'ready' and v_status in ('in_progress','completed')) or
      (v_operation.status = 'in_progress' and v_status in ('paused','completed')) or
      (v_operation.status = 'paused' and v_status in ('in_progress','completed')) or
      (v_operation.status = 'completed' and v_status = 'ready')
    ) then
      raise exception using errcode = 'P0001', message = 'invalid_operation_transition';
    end if;
    if v_operation.status = 'completed' and v_reason is null then
      raise exception using errcode = 'P0001', message = 'reopen_reason_required';
    end if;
    if v_operation.status = 'ready' and v_status = 'completed' and v_reason is null then
      raise exception using errcode = 'P0001', message = 'ready_completion_reason_required';
    end if;
    if v_status = 'completed' then
      select pg_catalog.count(*) into v_count
      from public.sd_event_operation_participants
      where event_operation_id = v_operation.id and participant_type = 'player'
        and expected and attendance_status = 'not_recorded';
      select v_count + pg_catalog.count(*) into v_count
      from public.sd_event_operation_checklist_items
      where event_operation_id = v_operation.id and required
        and completed_at is null and overridden_at is null;
      if v_count > 0 and v_reason is null then
        raise exception using errcode = 'P0001', message = 'completion_override_required';
      end if;
      insert into public.sd_event_operation_versions (
        event_operation_id, organization_id, operation_version, snapshot,
        reason, captured_by
      ) values (
        v_operation.id, p_organization_id, v_expected + 1,
        pg_catalog.jsonb_build_object(
          'operation', pg_catalog.to_jsonb(v_operation),
          'participants', (select pg_catalog.coalesce(pg_catalog.jsonb_agg(pg_catalog.to_jsonb(p)), '[]'::jsonb) from public.sd_event_operation_participants p where p.event_operation_id = v_operation.id),
          'checklist', (select pg_catalog.coalesce(pg_catalog.jsonb_agg(pg_catalog.to_jsonb(c)), '[]'::jsonb) from public.sd_event_operation_checklist_items c where c.event_operation_id = v_operation.id),
          'prior_event_status', v_event.status
        ),
        v_reason, p_actor_id
      );
    end if;
    if v_operation.status = 'completed' and v_status = 'ready' then
      select snapshot->>'prior_event_status' into v_prior_event_status
      from public.sd_event_operation_versions
      where event_operation_id = v_operation.id
      order by operation_version desc
      limit 1;
    end if;
    update public.sd_event_operations
    set status = v_status,
      started_at = case when v_status = 'in_progress' then pg_catalog.coalesce(started_at, v_now) else started_at end,
      started_by = case when v_status = 'in_progress' then pg_catalog.coalesce(started_by, p_actor_id) else started_by end,
      completed_at = case when v_status = 'completed' then v_now when v_operation.status = 'completed' then null else completed_at end,
      completed_by = case when v_status = 'completed' then p_actor_id when v_operation.status = 'completed' then null else completed_by end,
      reopened_at = case when v_operation.status = 'completed' then v_now else reopened_at end,
      reopened_by = case when v_operation.status = 'completed' then p_actor_id else reopened_by end,
      operational_summary = case when v_status = 'completed' then nullif(pg_catalog.btrim(p_payload->>'operational_summary'), '') else operational_summary end,
      version = version + 1
    where id = v_operation.id and version = v_expected
    returning * into v_operation;
    if not found then raise exception using errcode = 'P0001', message = 'stale_version'; end if;
    if v_status = 'completed' then
      update public.sd_team_events set status = 'completed', updated_by = p_actor_id
      where id = v_event.id and organization_id = p_organization_id;
    elsif v_operation.status = 'ready' and v_prior_event_status is not null then
      update public.sd_team_events set status = v_prior_event_status, updated_by = p_actor_id
      where id = v_event.id and organization_id = p_organization_id;
    end if;
    insert into public.sd_event_operation_audit_logs (
      organization_id, season_id, team_id, event_id, event_operation_id,
      actor_id, action, request_id, previous_value, new_value, reason
    ) values (
      p_organization_id, v_event.season_id, v_event.team_id, v_event.id,
      v_operation.id, p_actor_id,
      case
        when v_status = 'completed' then 'completed'
        when v_status = 'paused' then 'paused'
        when v_status = 'ready' and v_prior_operation_status = 'completed' then 'reopened'
        when v_status = 'ready' then 'prepared'
        when v_status = 'in_progress' and v_prior_operation_status = 'paused' then 'resumed'
        when v_status = 'in_progress' then 'started'
        else 'resumed'
      end,
      p_request_id,
      pg_catalog.jsonb_build_object('status', v_prior_operation_status, 'version', v_expected),
      pg_catalog.jsonb_build_object('status', v_operation.status, 'version', v_operation.version),
      v_reason
    );
    if v_status = 'in_progress' and v_prior_operation_status <> 'paused' then
      insert into public.sd_team_event_notification_intents (
        organization_id, team_id, event_id, event_operation_id, intent_type,
        deduplication_key, payload, created_by
      ) values (
        p_organization_id, v_event.team_id, v_event.id, v_operation.id,
        'operation_started', p_request_id::text || ':' || v_operation.id::text || ':started',
        '{}'::jsonb, p_actor_id
      );
    elsif v_operation.status = 'completed' then
      insert into public.sd_team_event_notification_intents (
        organization_id, team_id, event_id, event_operation_id, intent_type,
        deduplication_key, payload, created_by
      ) values (
        p_organization_id, v_event.team_id, v_event.id, v_operation.id,
        'event_completed', p_request_id::text || ':' || v_operation.id::text || ':completed',
        '{}'::jsonb, p_actor_id
      );
    end if;
    v_response := pg_catalog.jsonb_build_object('operation_id', v_operation.id, 'operation', pg_catalog.to_jsonb(v_operation));

  elsif p_action in ('attendance', 'attendance_bulk') then
    if pg_catalog.jsonb_typeof(p_payload->'participants') <> 'array'
      or pg_catalog.jsonb_array_length(p_payload->'participants') = 0 then
      raise exception using errcode = 'P0001', message = 'missing_participants';
    end if;
    if (select pg_catalog.count(*) from pg_catalog.jsonb_to_recordset(p_payload->'participants') as x(participant_id uuid, expected_version integer))
      <> (select pg_catalog.count(distinct participant_id) from pg_catalog.jsonb_to_recordset(p_payload->'participants') as x(participant_id uuid, expected_version integer)) then
      raise exception using errcode = 'P0001', message = 'duplicate_participant';
    end if;
    perform 1
    from public.sd_event_operation_participants participant
    join pg_catalog.jsonb_to_recordset(p_payload->'participants') as input(participant_id uuid, expected_version integer)
      on input.participant_id = participant.id
    where participant.event_operation_id = v_operation.id
    for update of participant;
    select pg_catalog.count(*) into v_count
    from public.sd_event_operation_participants participant
    join pg_catalog.jsonb_to_recordset(p_payload->'participants') as input(participant_id uuid, expected_version integer)
      on input.participant_id = participant.id and input.expected_version = participant.version
    where participant.event_operation_id = v_operation.id;
    if v_count <> pg_catalog.jsonb_array_length(p_payload->'participants') then
      raise exception using errcode = 'P0001', message = 'stale_version';
    end if;
    if (v_operation.status = 'completed' or v_operation.attendance_finalized_at is not null)
      and nullif(pg_catalog.btrim(p_payload->>'correction_reason'), '') is null then
      raise exception using errcode = 'P0001', message = 'attendance_correction_reason_required';
    end if;
    select pg_catalog.jsonb_agg(pg_catalog.to_jsonb(participant)) into v_previous
    from public.sd_event_operation_participants participant
    join pg_catalog.jsonb_to_recordset(p_payload->'participants') as input(participant_id uuid, expected_version integer)
      on input.participant_id = participant.id
    where participant.event_operation_id = v_operation.id;
    with input as (
      select * from pg_catalog.jsonb_to_recordset(p_payload->'participants')
        as row(participant_id uuid, expected_version integer)
    ), changed as (
      update public.sd_event_operation_participants participant
      set attendance_status = p_payload->>'attendance_status',
        arrival_at = case
          when p_payload->>'attendance_status' in ('absent','excused','injured') then null
          when p_payload ? 'arrival_at' then nullif(p_payload->>'arrival_at', '')::timestamptz
          when p_payload->>'attendance_status' in ('present','late') then pg_catalog.coalesce(participant.arrival_at, v_now)
          else participant.arrival_at
        end,
        departure_at = case
          when p_payload->>'attendance_status' in ('absent','excused','injured') then null
          when p_payload ? 'departure_at' then nullif(p_payload->>'departure_at', '')::timestamptz
          else participant.departure_at
        end,
        checked_in_by = p_actor_id,
        attendance_notes = case when p_payload ? 'attendance_notes' then nullif(pg_catalog.btrim(p_payload->>'attendance_notes'), '') else participant.attendance_notes end,
        private_notes = case when p_payload ? 'private_notes' then nullif(pg_catalog.btrim(p_payload->>'private_notes'), '') else participant.private_notes end,
        version = participant.version + 1
      from input
      where participant.id = input.participant_id
        and participant.event_operation_id = v_operation.id
        and participant.version = input.expected_version
      returning participant.*
    ) select pg_catalog.coalesce(pg_catalog.jsonb_agg(pg_catalog.to_jsonb(changed)), '[]'::jsonb) into v_rows from changed;
    insert into public.sd_event_operation_audit_logs (
      organization_id, season_id, team_id, event_id, event_operation_id,
      actor_id, action, request_id, previous_value, new_value, reason
    ) values (
      p_organization_id, v_event.season_id, v_event.team_id, v_event.id,
      v_operation.id, p_actor_id,
      case
        when v_operation.status = 'completed' or v_operation.attendance_finalized_at is not null then 'attendance_corrected'
        when p_action = 'attendance_bulk' then 'attendance_bulk_changed'
        else 'attendance_changed'
      end,
      p_request_id, pg_catalog.jsonb_build_object('participants', v_previous),
      pg_catalog.jsonb_build_object('participants', v_rows),
      nullif(pg_catalog.btrim(p_payload->>'correction_reason'), '')
    );
    if v_operation.status = 'completed' or v_operation.attendance_finalized_at is not null then
      insert into public.sd_team_event_notification_intents (
        organization_id, team_id, event_id, event_operation_id, intent_type,
        deduplication_key, payload, created_by
      ) values (
        p_organization_id, v_event.team_id, v_event.id, v_operation.id,
        'attendance_correction', p_request_id::text || ':' || v_operation.id::text || ':attendance-correction',
        '{}'::jsonb, p_actor_id
      );
    end if;
    v_response := pg_catalog.jsonb_build_object('operation_id', v_operation.id, 'participants', v_rows);

  elsif p_action = 'finalize_attendance' then
    if v_operation.status = 'completed' then
      raise exception using errcode = 'P0001', message = 'attendance_locked';
    end if;
    if p_payload->>'expected_version' is null then
      raise exception using errcode = 'P0001', message = 'missing_expected_version';
    end if;
    v_expected := (p_payload->>'expected_version')::integer;
    if v_operation.version <> v_expected then
      raise exception using errcode = 'P0001', message = 'stale_version';
    end if;
    select pg_catalog.count(*) into v_count
    from public.sd_event_operation_participants
    where event_operation_id = v_operation.id and participant_type = 'player'
      and expected and attendance_status = 'not_recorded';
    if v_count > 0 and nullif(pg_catalog.btrim(p_payload->>'reason'), '') is null then
      raise exception using errcode = 'P0001', message = 'attendance_review_required';
    end if;
    update public.sd_event_operations
    set attendance_finalized_at = v_now, attendance_finalized_by = p_actor_id,
      version = version + 1
    where id = v_operation.id and version = v_expected returning * into v_operation;
    insert into public.sd_event_operation_audit_logs (
      organization_id, season_id, team_id, event_id, event_operation_id,
      actor_id, action, request_id, new_value, reason
    ) values (
      p_organization_id, v_event.season_id, v_event.team_id, v_event.id,
      v_operation.id, p_actor_id, 'attendance_finalized', p_request_id,
      pg_catalog.jsonb_build_object('attendance_finalized_at', v_operation.attendance_finalized_at, 'version', v_operation.version),
      nullif(pg_catalog.btrim(p_payload->>'reason'), '')
    );
    v_response := pg_catalog.jsonb_build_object('operation_id', v_operation.id, 'operation', pg_catalog.to_jsonb(v_operation));

  elsif p_action = 'checklist' then
    select * into v_item from public.sd_event_operation_checklist_items
    where id = (p_payload->>'item_id')::uuid and event_operation_id = v_operation.id
    for update;
    if not found then raise exception using errcode = 'P0001', message = 'checklist_item_not_found'; end if;
    v_expected := (p_payload->>'item_version')::integer;
    if v_item.version <> v_expected then raise exception using errcode = 'P0001', message = 'stale_version'; end if;
    v_previous := pg_catalog.to_jsonb(v_item);
    v_reason := nullif(pg_catalog.btrim(p_payload->>'override_reason'), '');
    update public.sd_event_operation_checklist_items
    set completed_at = case when v_reason is not null then null when (p_payload->>'completed')::boolean then v_now else null end,
      completed_by = case when v_reason is not null then null when (p_payload->>'completed')::boolean then p_actor_id else null end,
      overridden_at = case when v_reason is not null then v_now else null end,
      overridden_by = case when v_reason is not null then p_actor_id else null end,
      override_reason = v_reason,
      version = version + 1
    where id = v_item.id and version = v_expected returning * into v_item;
    insert into public.sd_event_operation_audit_logs (
      organization_id, season_id, team_id, event_id, event_operation_id,
      actor_id, action, request_id, target_id, previous_value, new_value, reason
    ) values (
      p_organization_id, v_event.season_id, v_event.team_id, v_event.id,
      v_operation.id, p_actor_id,
      case when v_reason is not null then 'checklist_overridden'
        when (p_payload->>'completed')::boolean then 'checklist_completed'
        else 'checklist_uncompleted' end,
      p_request_id, v_item.id, v_previous, pg_catalog.to_jsonb(v_item), v_reason
    );
    v_response := pg_catalog.jsonb_build_object('operation_id', v_operation.id, 'checklist_item', pg_catalog.to_jsonb(v_item));

  elsif p_action = 'note' then
    v_status := p_payload->>'note_type';
    v_reason := p_payload->>'visibility';
    if not (
      (v_status = 'internal_staff_note' and v_reason = 'staff' and p_payload->>'player_id' is null) or
      (v_status = 'player_coach_note' and v_reason in ('staff','player') and p_payload->>'player_id' is not null) or
      (v_status = 'team_coach_note' and v_reason in ('staff','team') and p_payload->>'player_id' is null) or
      (v_status = 'post_event_recap' and v_reason = 'team' and p_payload->>'player_id' is null)
    ) then
      raise exception using errcode = 'P0001', message = 'invalid_note_visibility';
    end if;
    if v_status = 'player_coach_note' and not exists (
      select 1 from public.sd_event_operation_participants
      where event_operation_id = v_operation.id
        and user_id = (p_payload->>'player_id')::uuid and participant_type = 'player'
    ) then
      raise exception using errcode = 'P0001', message = 'participant_not_found';
    end if;
    insert into public.sd_event_operation_notes (
      event_operation_id, organization_id, note_type, visibility,
      subject_player_id, body, published_at, created_by, updated_by
    ) values (
      v_operation.id, p_organization_id, v_status, v_reason,
      nullif(p_payload->>'player_id', '')::uuid,
      nullif(pg_catalog.btrim(p_payload->>'body'), ''),
      case when v_status = 'post_event_recap' then v_now else null end,
      p_actor_id, p_actor_id
    ) returning * into v_note;
    insert into public.sd_event_operation_audit_logs (
      organization_id, season_id, team_id, event_id, event_operation_id,
      actor_id, action, request_id, target_id, new_value
    ) values (
      p_organization_id, v_event.season_id, v_event.team_id, v_event.id,
      v_operation.id, p_actor_id,
      case when v_status = 'post_event_recap' then 'recap_published' else 'note_created' end,
      p_request_id, v_note.id,
      pg_catalog.jsonb_build_object('note_type', v_note.note_type, 'visibility', v_note.visibility)
    );
    if v_status = 'post_event_recap' then
      insert into public.sd_team_event_notification_intents (
        organization_id, team_id, event_id, event_operation_id, intent_type,
        deduplication_key, payload, created_by
      ) values (
        p_organization_id, v_event.team_id, v_event.id, v_operation.id,
        'recap_published', p_request_id::text || ':' || v_operation.id::text || ':recap',
        '{}'::jsonb, p_actor_id
      );
    end if;
    v_response := pg_catalog.jsonb_build_object('operation_id', v_operation.id, 'note', pg_catalog.to_jsonb(v_note));

  elsif p_action = 'note_update' then
    select * into v_note from public.sd_event_operation_notes
    where id = (p_payload->>'note_id')::uuid
      and event_operation_id = v_operation.id
    for update;
    if not found then raise exception using errcode = 'P0001', message = 'note_not_found'; end if;
    v_expected := (p_payload->>'note_version')::integer;
    if v_note.version <> v_expected then raise exception using errcode = 'P0001', message = 'stale_version'; end if;
    if v_note.note_type <> p_payload->>'note_type' then
      raise exception using errcode = 'P0001', message = 'note_type_immutable';
    end if;
    v_reason := p_payload->>'visibility';
    if not (
      (v_note.note_type = 'internal_staff_note' and v_reason = 'staff') or
      (v_note.note_type = 'player_coach_note' and v_reason in ('staff','player')) or
      (v_note.note_type = 'team_coach_note' and v_reason in ('staff','team')) or
      (v_note.note_type = 'post_event_recap' and v_reason = 'team')
    ) then
      raise exception using errcode = 'P0001', message = 'invalid_note_visibility';
    end if;
    v_previous := pg_catalog.to_jsonb(v_note);
    update public.sd_event_operation_notes
    set body = nullif(pg_catalog.btrim(p_payload->>'body'), ''),
      visibility = v_reason,
      updated_by = p_actor_id,
      version = version + 1
    where id = v_note.id and version = v_expected returning * into v_note;
    insert into public.sd_event_operation_audit_logs (
      organization_id, season_id, team_id, event_id, event_operation_id,
      actor_id, action, request_id, target_id, previous_value, new_value
    ) values (
      p_organization_id, v_event.season_id, v_event.team_id, v_event.id,
      v_operation.id, p_actor_id,
      case when v_previous->>'visibility' <> v_note.visibility then 'visibility_changed' else 'note_edited' end,
      p_request_id, v_note.id, v_previous, pg_catalog.to_jsonb(v_note)
    );
    v_response := pg_catalog.jsonb_build_object('operation_id', v_operation.id, 'note', pg_catalog.to_jsonb(v_note));

  elsif p_action = 'reconcile_participants' then
    if p_payload->>'expected_version' is null then
      raise exception using errcode = 'P0001', message = 'missing_expected_version';
    end if;
    v_expected := (p_payload->>'expected_version')::integer;
    if v_operation.version <> v_expected then raise exception using errcode = 'P0001', message = 'stale_version'; end if;
    with added as (
      insert into public.sd_event_operation_participants (
        event_operation_id, organization_id, season_id, team_id, event_id,
        user_id, participant_type, expected
      )
      select v_operation.id, p_organization_id, v_event.season_id,
        v_event.team_id, v_event.id, membership.player_id, 'player', true
      from public.sd_player_team_memberships membership
      where membership.organization_id = p_organization_id
        and membership.season_id = v_event.season_id
        and membership.team_id = v_event.team_id
        and membership.active and membership.ended_at is null
        and not exists (
          select 1 from public.sd_event_operation_participants snapshot
          where snapshot.event_operation_id = v_operation.id
            and snapshot.user_id = membership.player_id
        )
      returning user_id
    ) select pg_catalog.coalesce(pg_catalog.jsonb_agg(user_id), '[]'::jsonb) into v_rows from added;
    update public.sd_event_operations set version = version + 1
    where id = v_operation.id and version = v_expected returning * into v_operation;
    insert into public.sd_event_operation_audit_logs (
      organization_id, season_id, team_id, event_id, event_operation_id,
      actor_id, action, request_id, reason, details
    ) values (
      p_organization_id, v_event.season_id, v_event.team_id, v_event.id,
      v_operation.id, p_actor_id, 'participants_reconciled', p_request_id,
      nullif(pg_catalog.btrim(p_payload->>'reason'), ''),
      pg_catalog.jsonb_build_object('additions', v_rows, 'snapshot_preserved', true)
    );
    v_response := pg_catalog.jsonb_build_object('operation_id', v_operation.id, 'operation', pg_catalog.to_jsonb(v_operation), 'additions', v_rows);

  else
    raise exception using errcode = 'P0001', message = 'unsupported_action';
  end if;

  update public.sd_event_operation_mutations
  set status = 'completed', response = v_response, completed_at = pg_catalog.now()
  where organization_id = p_organization_id and request_id = p_request_id;
  return v_response;
end;
$$;

revoke all on function public.sd_apply_event_operation_mutation(uuid, uuid, uuid, text, uuid, boolean, jsonb)
  from public, anon, authenticated;
grant execute on function public.sd_apply_event_operation_mutation(uuid, uuid, uuid, text, uuid, boolean, jsonb)
  to service_role;

-- Extend the existing responsibility-to-capability resolver. Swift receives the
-- resolved values and never recreates this responsibility mapping.
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
      'manage_game_event','manage_tournament_event','manage_meeting_event','manage_travel_event',
      'view_event_operation','start_event_operation','manage_event_attendance','manage_event_availability',
      'manage_event_checklist','add_team_event_notes','add_private_player_notes','complete_event_operation',
      'reopen_event_operation'
    ]) where exists (select 1 from actor_membership where role in ('owner','admin'))
    union
    select pg_catalog.unnest(array[
      'view_team','manage_roster','manage_schedule','manage_attendance','manage_practice','manage_game',
      'message_team','view_development','edit_development','manage_staff','view_documents','manage_documents',
      'view_team_schedule','create_team_event','edit_team_event','cancel_team_event','manage_practice_event',
      'manage_game_event','manage_tournament_event','manage_meeting_event','manage_travel_event',
      'view_event_operation','start_event_operation','manage_event_attendance','manage_event_availability',
      'manage_event_checklist','add_team_event_notes','add_private_player_notes','complete_event_operation',
      'reopen_event_operation'
    ]) where exists (select 1 from responsibilities where responsibility in ('head_coach','team_manager'))
    union
    select pg_catalog.unnest(array[
      'view_team','manage_roster','manage_schedule','manage_attendance','manage_practice','manage_game',
      'message_team','view_development','edit_development','view_documents','view_team_schedule',
      'create_team_event','edit_team_event','cancel_team_event','manage_practice_event','manage_game_event',
      'manage_tournament_event','manage_meeting_event','manage_travel_event',
      'view_event_operation','start_event_operation','manage_event_attendance','manage_event_availability',
      'manage_event_checklist','add_team_event_notes','add_private_player_notes','complete_event_operation'
    ]) where exists (select 1 from responsibilities where responsibility = 'assistant_coach')
    union
    select pg_catalog.unnest(array[
      'view_team','manage_practice','view_development','edit_development','view_documents','view_team_schedule',
      'view_event_operation','start_event_operation','manage_event_attendance','add_team_event_notes',
      'add_private_player_notes'
    ]) where exists (select 1 from responsibilities where responsibility in (
      'hitting_coach','pitching_coach','catching_coach','strength_coach'
    ))
    union
    select pg_catalog.unnest(array[
      'view_team','view_development','edit_development','view_documents','view_team_schedule',
      'view_event_operation','add_private_player_notes'
    ]) where exists (select 1 from responsibilities where responsibility = 'evaluator')
    union
    select pg_catalog.unnest(array[
      'view_team','view_development','view_documents','view_team_schedule','view_event_operation'
    ]) where exists (select 1 from responsibilities where responsibility = 'read_only')
  )
  select pg_catalog.coalesce(pg_catalog.array_agg(capability order by capability), '{}'::text[]) from resolved;
$$;

alter table public.sd_event_operations enable row level security;
alter table public.sd_event_operation_participants enable row level security;
alter table public.sd_event_operation_checklist_items enable row level security;
alter table public.sd_event_operation_notes enable row level security;
alter table public.sd_event_operation_versions enable row level security;
alter table public.sd_event_operation_audit_logs enable row level security;
alter table public.sd_event_operation_mutations enable row level security;

revoke all on table public.sd_event_operations, public.sd_event_operation_participants,
  public.sd_event_operation_checklist_items, public.sd_event_operation_notes,
  public.sd_event_operation_versions, public.sd_event_operation_audit_logs,
  public.sd_event_operation_mutations from public, anon, authenticated;
grant select, insert, update, delete on table public.sd_event_operations,
  public.sd_event_operation_participants, public.sd_event_operation_checklist_items,
  public.sd_event_operation_notes, public.sd_event_operation_versions,
  public.sd_event_operation_audit_logs, public.sd_event_operation_mutations to service_role;

comment on table public.sd_event_operations is
  'One versioned day-of operation per canonical team event. Schedule and operational states remain distinct.';
comment on table public.sd_event_operation_participants is
  'Immutable-at-initialization participant roster snapshot with separate availability and attendance facts.';
comment on table public.sd_event_operation_mutations is
  'Server-only retry receipt; request UUIDs make day-operation mutations deterministic and idempotent.';
