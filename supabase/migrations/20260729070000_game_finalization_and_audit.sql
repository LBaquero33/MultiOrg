-- Phase 9: atomic game finalization, append-only corrections, and game audit.
-- Rollback: retain game ledgers, then drop the RPCs, triggers, and Phase 9 tables.

alter table public.sd_notifications
  drop constraint if exists sd_notifications_category_check;
alter table public.sd_notifications
  add constraint sd_notifications_category_check check (category in (
    'payment_request_created', 'payment_received', 'booking_created',
    'booking_updated', 'program_assigned', 'program_updated', 'message_received',
    'testing_result_added', 'organization_announcement', 'team_announcement',
    'event_announcement', 'schedule_change', 'event_reminder', 'attendance',
    'availability', 'practice_plan', 'game_plan', 'lineup_assignment',
    'registration', 'payment_notice', 'result_recap', 'event_created',
    'event_updated', 'event_canceled', 'event_postponed', 'event_rescheduled',
    'availability_requested', 'game_starting', 'game_live', 'game_final',
    'game_update', 'system'
  )) not valid;
alter table public.sd_notifications
  validate constraint sd_notifications_category_check;

create table if not exists public.sd_game_audit_log (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.sd_orgs(id) on delete cascade,
  game_id uuid not null references public.sd_games(id) on delete cascade,
  action text not null,
  actor_user_id uuid references auth.users(id) on delete set null,
  actor_device_id uuid,
  game_version bigint,
  details jsonb not null default '{}'::jsonb check (jsonb_typeof(details) = 'object'),
  created_at timestamptz not null default now()
);

create table if not exists public.sd_game_finalizations (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.sd_orgs(id) on delete cascade,
  game_id uuid not null unique references public.sd_games(id) on delete cascade,
  final_game_version bigint not null,
  final_scoring_event_id uuid not null references public.sd_game_scoring_events(id),
  finalized_by uuid not null references auth.users(id),
  actor_device_id uuid not null,
  idempotency_key text not null,
  validation jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  unique (game_id, idempotency_key)
);

create table if not exists public.sd_game_corrections (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.sd_orgs(id) on delete cascade,
  game_id uuid not null references public.sd_games(id) on delete cascade,
  decision_id uuid not null references public.sd_game_scoring_decisions(id),
  superseded_decision_id uuid not null references public.sd_game_scoring_decisions(id),
  corrected_by uuid not null references auth.users(id),
  reason text not null check (char_length(btrim(reason)) between 3 and 1000),
  idempotency_key text not null,
  created_at timestamptz not null default now(),
  unique (game_id, idempotency_key)
);

create index if not exists sd_game_audit_log_game_created_idx
  on public.sd_game_audit_log(game_id, created_at, id);
create index if not exists sd_game_corrections_game_created_idx
  on public.sd_game_corrections(game_id, created_at, id);

alter table public.sd_game_audit_log enable row level security;
alter table public.sd_game_finalizations enable row level security;
alter table public.sd_game_corrections enable row level security;

create policy sd_game_audit_log_select on public.sd_game_audit_log
for select using (
  exists (
    select 1 from public.sd_games game
    where game.id = game_id and public.sd_can_view_event(game.event_id)
  )
);
create policy sd_game_finalizations_select on public.sd_game_finalizations
for select using (
  exists (
    select 1 from public.sd_games game
    where game.id = game_id and public.sd_can_view_event(game.event_id)
  )
);
create policy sd_game_corrections_select on public.sd_game_corrections
for select using (
  exists (
    select 1 from public.sd_games game
    where game.id = game_id and public.sd_can_view_event(game.event_id)
  )
);
grant select on public.sd_game_audit_log, public.sd_game_finalizations,
  public.sd_game_corrections to authenticated;

create or replace function public.sd_reject_game_history_mutation()
returns trigger language plpgsql set search_path = '' as $$
begin
  raise exception 'game_history_is_immutable';
end;
$$;
create trigger trg_sd_game_audit_log_immutable
before update or delete on public.sd_game_audit_log
for each row execute function public.sd_reject_game_history_mutation();
create trigger trg_sd_game_finalizations_immutable
before update or delete on public.sd_game_finalizations
for each row execute function public.sd_reject_game_history_mutation();
create trigger trg_sd_game_corrections_immutable
before update or delete on public.sd_game_corrections
for each row execute function public.sd_reject_game_history_mutation();

create or replace function public.sd_insert_game_notification(
  p_org_id uuid,
  p_event_id uuid,
  p_game_id uuid,
  p_title text,
  p_body text,
  p_deduplication_key text
) returns void language plpgsql security definer set search_path = '' as $$
begin
  insert into public.sd_notifications(
    org_id, recipient_user_id, category, title, body, related_entity_type,
    related_entity_id, action_route, action_payload, deduplication_key,
    created_by, source
  )
  select distinct
    p_org_id, recipient.user_id, 'game_update', p_title, p_body, 'game',
    p_game_id::text, 'game_detail',
    jsonb_build_object('game_id', p_game_id::text, 'event_id', p_event_id::text),
    p_deduplication_key, auth.uid(), 'system'
  from (
    select participant.user_id
    from public.sd_event_participants participant
    where participant.event_id = p_event_id
      and participant.user_id is not null
      and participant.can_view
    union
    select team_member.player_id
    from public.sd_events event
    join public.sd_team_members team_member
      on team_member.org_id = event.org_id and team_member.team_id = event.team_id
    where event.id = p_event_id
    union
    select parent_link.parent_id
    from public.sd_event_participants participant
    join public.sd_parent_child_links parent_link
      on parent_link.org_id = participant.org_id
     and parent_link.child_id = participant.user_id
    where participant.event_id = p_event_id
      and participant.participant_type = 'player'
      and participant.can_view
  ) recipient
  where recipient.user_id is not null
  on conflict (org_id, recipient_user_id, category, deduplication_key) do nothing;
end;
$$;
revoke all on function public.sd_insert_game_notification(
  uuid,uuid,uuid,text,text,text
) from public, anon, authenticated;

create or replace function public.sd_finalize_game(
  p_game_id uuid,
  p_expected_version bigint,
  p_actor_device_id uuid,
  p_control_token text,
  p_idempotency_key text,
  p_statistics jsonb,
  p_validation jsonb
) returns public.sd_game_finalizations
language plpgsql security definer set search_path = '' as $$
declare
  v_game public.sd_games;
  v_existing public.sd_game_finalizations;
  v_event public.sd_game_scoring_events;
  v_finalization public.sd_game_finalizations;
  v_unresolved integer;
  v_event_id uuid := gen_random_uuid();
begin
  if auth.uid() is null then raise exception 'authentication_required'; end if;
  select * into v_existing from public.sd_game_finalizations
    where game_id = p_game_id and idempotency_key = p_idempotency_key;
  if found then return v_existing; end if;

  select * into v_game from public.sd_games where id = p_game_id for update;
  if not found then raise exception 'game_not_found'; end if;
  if v_game.finalized_at is not null or v_game.status = 'final' then
    raise exception 'game_already_finalized';
  end if;
  if v_game.game_version <> p_expected_version then raise exception 'stale_game_version'; end if;
  if not exists (
    select 1 from public.sd_game_scorekeeper_sessions session
    where session.game_id = p_game_id
      and session.active_user_id = auth.uid()
      and session.active_device_id = p_actor_device_id
      and session.session_status = 'active'
      and session.lease_expires_at > now()
      and session.control_token_hash =
        encode(extensions.digest(p_control_token, 'sha256'), 'hex')
  ) then raise exception 'finalization_authority_invalid'; end if;
  if jsonb_typeof(coalesce(p_validation, '{}'::jsonb)) <> 'object'
     or jsonb_typeof(coalesce(p_validation->'issues', '[]'::jsonb)) <> 'array'
     or jsonb_array_length(coalesce(p_validation->'issues', '[]'::jsonb)) > 0
  then raise exception 'game_validation_failed'; end if;
  if jsonb_typeof(coalesce(p_statistics, '{}'::jsonb)) <> 'object' then
    raise exception 'statistics_payload_invalid';
  end if;
  select count(*) into v_unresolved
  from (
    select distinct on (root_decision_id) decision_status
    from public.sd_game_scoring_decisions
    where game_id = p_game_id
    order by root_decision_id, created_at desc, id desc
  ) latest
  where latest.decision_status not in ('final', 'superseded');
  if v_unresolved > 0 then raise exception 'unresolved_scoring_decisions'; end if;
  if not exists (
    select 1 from public.sd_game_scoring_events
    where game_id = p_game_id and event_type = 'game_ended'
  ) then raise exception 'game_end_not_recorded'; end if;

  insert into public.sd_game_scoring_events(
    id, org_id, game_id, game_version, sequence, event_type,
    actor_user_id, actor_device_id, payload, ruleset_version, idempotency_key
  ) values (
    v_event_id, v_game.org_id, p_game_id, p_expected_version + 1,
    p_expected_version + 1, 'game_finalized', auth.uid(), p_actor_device_id,
    jsonb_build_object('validation_passed', true), v_game.ruleset_version,
    'finalize:' || p_idempotency_key
  ) returning * into v_event;

  update public.sd_games set
    status = 'final', live_status = 'final',
    game_version = p_expected_version + 1, finalized_at = now()
  where id = p_game_id;
  update public.sd_events set status = 'final', updated_by = auth.uid()
  where id = v_game.event_id;

  insert into public.sd_game_stat_snapshots(
    game_id, org_id, game_version, decision_version, batting, pitching,
    fielding, team_totals, validation, generated_at
  ) values (
    p_game_id, v_game.org_id, p_expected_version + 1,
    (select count(*) from public.sd_game_scoring_decisions where game_id = p_game_id),
    coalesce(p_statistics->'batting', '{}'::jsonb),
    coalesce(p_statistics->'pitching', '{}'::jsonb),
    coalesce(p_statistics->'fielding', '{}'::jsonb),
    coalesce(p_statistics->'team_totals', '{}'::jsonb),
    p_validation, now()
  ) on conflict (game_id) do update set
    game_version = excluded.game_version,
    decision_version = excluded.decision_version,
    batting = excluded.batting,
    pitching = excluded.pitching,
    fielding = excluded.fielding,
    team_totals = excluded.team_totals,
    validation = excluded.validation,
    generated_at = excluded.generated_at,
    updated_at = now();

  insert into public.sd_game_finalizations(
    org_id, game_id, final_game_version, final_scoring_event_id,
    finalized_by, actor_device_id, idempotency_key, validation
  ) values (
    v_game.org_id, p_game_id, p_expected_version + 1, v_event.id,
    auth.uid(), p_actor_device_id, p_idempotency_key, p_validation
  ) returning * into v_finalization;

  update public.sd_game_scorekeeper_sessions set
    session_status = 'released', lease_expires_at = now(), updated_at = now()
  where game_id = p_game_id;
  update public.sd_game_live_devices set state = 'liveViewer', updated_at = now()
  where game_id = p_game_id;
  insert into public.sd_game_audit_log(
    org_id, game_id, action, actor_user_id, actor_device_id, game_version, details
  ) values (
    v_game.org_id, p_game_id, 'game_finalized', auth.uid(), p_actor_device_id,
    p_expected_version + 1, jsonb_build_object('idempotency_key', p_idempotency_key)
  );
  perform public.sd_insert_game_notification(
    v_game.org_id, v_game.event_id, p_game_id, 'Final score available',
    v_game.away_team_name || ' at ' || v_game.home_team_name || ' is final.',
    'game-final:' || p_game_id::text
  );
  return v_finalization;
end;
$$;
grant execute on function public.sd_finalize_game(
  uuid,bigint,uuid,text,text,jsonb,jsonb
) to authenticated;

create or replace function public.sd_correct_final_game_decision(
  p_game_id uuid,
  p_superseded_decision_id uuid,
  p_replacement_value text,
  p_reason text,
  p_idempotency_key text,
  p_statistics jsonb,
  p_validation jsonb
) returns public.sd_game_corrections
language plpgsql security definer set search_path = '' as $$
declare
  v_game public.sd_games;
  v_previous public.sd_game_scoring_decisions;
  v_new public.sd_game_scoring_decisions;
  v_existing public.sd_game_corrections;
  v_correction public.sd_game_corrections;
begin
  select * into v_existing from public.sd_game_corrections
    where game_id = p_game_id and idempotency_key = p_idempotency_key;
  if found then return v_existing; end if;
  select * into v_game from public.sd_games where id = p_game_id for update;
  if not found or v_game.status <> 'final' then raise exception 'final_game_required'; end if;
  if not (
    public.sd_is_org_admin(v_game.org_id)
    or public.sd_is_platform_admin_game_support()
    or v_game.assigned_scorekeeper_id = auth.uid()
  ) then raise exception 'postgame_correction_not_authorized'; end if;
  if char_length(btrim(p_reason)) < 3 then raise exception 'correction_reason_required'; end if;
  if jsonb_typeof(coalesce(p_validation, '{}'::jsonb)) <> 'object'
     or jsonb_typeof(coalesce(p_validation->'issues', '[]'::jsonb)) <> 'array'
     or jsonb_array_length(coalesce(p_validation->'issues', '[]'::jsonb)) > 0
     or jsonb_typeof(coalesce(p_statistics, '{}'::jsonb)) <> 'object'
  then
    raise exception 'corrected_statistics_invalid';
  end if;
  select * into v_previous from public.sd_game_scoring_decisions
    where id = p_superseded_decision_id and game_id = p_game_id for update;
  if not found or v_previous.decision_status = 'superseded' then
    raise exception 'scoring_decision_not_current';
  end if;
  insert into public.sd_game_scoring_decisions(
    org_id, game_id, physical_event_id, root_decision_id,
    supersedes_decision_id, decision_type, preliminary_value, final_value,
    decision_status, rule_reference, reasoning_note, review_requested,
    decision_maker_id, finalized_at
  ) values (
    v_game.org_id, p_game_id, v_previous.physical_event_id,
    v_previous.root_decision_id, v_previous.id, v_previous.decision_type,
    null, p_replacement_value, 'final', v_previous.rule_reference,
    btrim(p_reason), false, auth.uid(), now()
  ) returning * into v_new;
  update public.sd_game_scoring_decisions set decision_status = 'superseded'
  where id = v_previous.id;

  insert into public.sd_game_corrections(
    org_id, game_id, decision_id, superseded_decision_id,
    corrected_by, reason, idempotency_key
  ) values (
    v_game.org_id, p_game_id, v_new.id, v_previous.id,
    auth.uid(), btrim(p_reason), p_idempotency_key
  ) returning * into v_correction;
  update public.sd_game_stat_snapshots set
    decision_version = (
      select count(*) from public.sd_game_scoring_decisions where game_id = p_game_id
    ),
    batting = coalesce(p_statistics->'batting', '{}'::jsonb),
    pitching = coalesce(p_statistics->'pitching', '{}'::jsonb),
    fielding = coalesce(p_statistics->'fielding', '{}'::jsonb),
    team_totals = coalesce(p_statistics->'team_totals', '{}'::jsonb),
    validation = p_validation, generated_at = now(), updated_at = now()
  where game_id = p_game_id;
  insert into public.sd_game_audit_log(
    org_id, game_id, action, actor_user_id, game_version, details
  ) values (
    v_game.org_id, p_game_id, 'final_game_corrected', auth.uid(),
    v_game.game_version, jsonb_build_object(
      'correction_id', v_correction.id::text,
      'superseded_decision_id', v_previous.id::text
    )
  );
  perform public.sd_insert_game_notification(
    v_game.org_id, v_game.event_id, p_game_id, 'Final game updated',
    'An authorized scoring correction updated the final game record.',
    'game-correction:' || v_correction.id::text
  );
  return v_correction;
end;
$$;
grant execute on function public.sd_correct_final_game_decision(
  uuid,uuid,text,text,text,jsonb,jsonb
) to authenticated;

create or replace function public.sd_audit_game_scoring_event()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.event_type = 'game_finalized' then
    return new;
  end if;
  insert into public.sd_game_audit_log(
    org_id, game_id, action, actor_user_id, actor_device_id, game_version, details
  ) values (
    new.org_id, new.game_id,
    case
      when new.event_type = 'game_delayed' then 'game_delayed'
      when new.event_type = 'game_suspended' then 'game_suspended'
      when new.event_type = 'game_resumed' then 'game_resumed'
      when new.correction_of_event_id is not null then 'play_corrected'
      else 'scoring_event_accepted'
    end,
    new.actor_user_id, new.actor_device_id, new.game_version,
    jsonb_build_object('event_id', new.id::text, 'event_type', new.event_type)
  );
  return new;
end;
$$;
create trigger trg_sd_audit_game_scoring_event
after insert on public.sd_game_scoring_events
for each row execute function public.sd_audit_game_scoring_event();

create or replace function public.sd_audit_game_control_request()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.sd_game_audit_log(
    org_id, game_id, action, actor_user_id, actor_device_id, details
  ) values (
    new.org_id, new.game_id,
    case when tg_op = 'INSERT' then 'control_requested' else 'control_' || new.status end,
    case when tg_op = 'INSERT' then new.requesting_user_id else new.resolved_by end,
    new.requesting_device_id, jsonb_build_object('request_id', new.id::text)
  );
  return new;
end;
$$;
create trigger trg_sd_audit_game_control_request_insert
after insert on public.sd_game_control_requests
for each row execute function public.sd_audit_game_control_request();
create trigger trg_sd_audit_game_control_request_update
after update of status on public.sd_game_control_requests
for each row when (old.status is distinct from new.status)
execute function public.sd_audit_game_control_request();

do $$ begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public'
      and tablename = 'sd_game_audit_log'
  ) then
    alter publication supabase_realtime add table public.sd_game_audit_log;
  end if;
end $$;
