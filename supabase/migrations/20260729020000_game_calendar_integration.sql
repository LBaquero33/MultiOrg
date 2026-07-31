-- Home Plate Games Phase 2: calendar notifications and transactional facility
-- reconciliation. Rollback: remove the two triggers/functions, restore the
-- previous notification constraints, then remove event-created booking rows.

alter table public.sd_notifications
  drop constraint if exists sd_notifications_category_check;
alter table public.sd_notifications
  add constraint sd_notifications_category_check check (category in (
    'payment_request_created', 'payment_received', 'booking_created',
    'booking_updated', 'program_assigned', 'program_updated',
    'message_received', 'testing_result_added', 'organization_announcement',
    'team_announcement', 'event_announcement', 'schedule_change',
    'event_reminder', 'attendance', 'availability', 'practice_plan',
    'game_plan', 'lineup_assignment', 'registration', 'payment_notice',
    'result_recap',
    'event_created', 'event_updated', 'event_canceled', 'event_postponed',
    'event_rescheduled', 'availability_requested', 'game_starting',
    'game_live', 'game_final', 'system'
  )) not valid;
alter table public.sd_notifications
  validate constraint sd_notifications_category_check;

alter table public.sd_notifications
  drop constraint if exists sd_notifications_source_check;
alter table public.sd_notifications
  add constraint sd_notifications_source_check
  check (source in (
    'payment_request', 'payment_webhook', 'announcement', 'chat', 'schedule',
    'event_operation', 'practice_plan', 'game_plan', 'registration',
    'organization_finance', 'event', 'system'
  )) not valid;
alter table public.sd_notifications
  validate constraint sd_notifications_source_check;

create or replace function public.sd_reconcile_event_facility_booking()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_game public.sd_games;
  v_booking_id uuid;
begin
  if pg_trigger_depth() > 1 or new.event_type <> 'game' then
    return new;
  end if;

  select * into v_game
  from public.sd_games
  where event_id = new.id and org_id = new.org_id;

  if not found then
    return new;
  end if;

  if new.status in ('canceled', 'no_contest')
     or new.facility_id is null
     or v_game.site <> 'home' then
    if new.facility_booking_id is not null then
      delete from public.sd_facility_bookings
      where id = new.facility_booking_id and org_id = new.org_id and is_block;
      update public.sd_events
      set facility_booking_id = null
      where id = new.id and facility_booking_id is not null;
    end if;
    return new;
  end if;

  if new.facility_booking_id is null then
    insert into public.sd_facility_bookings (
      org_id, facility_id, player_id, created_by, status, activity_type,
      start_at, end_at, approved_by, approved_at, title, notes, is_block
    ) values (
      new.org_id, new.facility_id, null, new.created_by, 'approved', 'other',
      new.scheduled_start, new.scheduled_end, new.created_by, now(),
      new.title, 'Canonical Home Plate game reservation', true
    )
    returning id into v_booking_id;

    update public.sd_events
    set facility_booking_id = v_booking_id
    where id = new.id and facility_booking_id is null;
  else
    update public.sd_facility_bookings
    set facility_id = new.facility_id,
        start_at = new.scheduled_start,
        end_at = new.scheduled_end,
        title = new.title,
        status = 'approved'
    where id = new.facility_booking_id
      and org_id = new.org_id
      and is_block;
  end if;
  return new;
end;
$$;

revoke all on function public.sd_reconcile_event_facility_booking()
from public, anon, authenticated;

drop trigger if exists trg_sd_reconcile_event_facility_booking on public.sd_events;
create trigger trg_sd_reconcile_event_facility_booking
after insert or update of facility_id, scheduled_start, scheduled_end, status, title
on public.sd_events
for each row execute function public.sd_reconcile_event_facility_booking();

create or replace function public.sd_reconcile_new_game_facility_booking()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- The event is inserted before its game specialization. Touching the
  -- facility column after the game exists runs the canonical reconciliation.
  update public.sd_events
  set facility_id = facility_id
  where id = new.event_id and org_id = new.org_id;
  return new;
end;
$$;

revoke all on function public.sd_reconcile_new_game_facility_booking()
from public, anon, authenticated;

drop trigger if exists trg_sd_reconcile_new_game_facility_booking on public.sd_games;
create trigger trg_sd_reconcile_new_game_facility_booking
after insert or update of site on public.sd_games
for each row execute function public.sd_reconcile_new_game_facility_booking();

create or replace function public.sd_event_notification_recipients(p_event_id uuid)
returns uuid[]
language sql
stable
security definer
set search_path = ''
as $$
  with event_scope as (
    select id, org_id, team_id from public.sd_events where id = p_event_id
  ),
  recipients as (
    select participant.user_id
    from public.sd_event_participants participant
    join event_scope scope on scope.id = participant.event_id
    where participant.can_view and participant.user_id is not null
    union
    select member.player_id
    from public.sd_team_members member
    join event_scope scope
      on scope.org_id = member.org_id and scope.team_id = member.team_id
    union
    select link.parent_id
    from public.sd_parent_child_links link
    join event_scope scope on scope.org_id = link.org_id
    join public.sd_team_members member
      on member.org_id = scope.org_id
     and member.team_id = scope.team_id
     and member.player_id = link.child_id
  )
  select coalesce(array_agg(distinct user_id), array[]::uuid[])
  from recipients
  where user_id is not null;
$$;

revoke all on function public.sd_event_notification_recipients(uuid)
from public, anon, authenticated;

create or replace function public.sd_notify_event_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_category text;
  v_title text;
  v_body text;
  v_recipients uuid[];
  v_game_id uuid;
  v_material_version text;
begin
  if new.status = 'draft' then
    return new;
  end if;

  select game.id into v_game_id
  from public.sd_games game
  where game.event_id = new.id and game.org_id = new.org_id;

  if tg_op = 'INSERT' then
    v_category := 'event_created';
    v_title := case when new.event_type = 'game' then 'Game scheduled' else 'Event scheduled' end;
    v_body := new.title || ' • ' || to_char(new.scheduled_start at time zone new.timezone, 'Mon FMDD, YYYY FMHH12:MI AM');
  elsif new.status = 'canceled' and old.status is distinct from new.status then
    v_category := 'event_canceled';
    v_title := 'Event canceled';
    v_body := new.title || ' has been canceled.';
  elsif new.status = 'postponed' and old.status is distinct from new.status then
    v_category := 'event_postponed';
    v_title := 'Event postponed';
    v_body := new.title || ' has been postponed.';
  elsif new.status = 'live' and old.status is distinct from new.status then
    v_category := 'game_live';
    v_title := 'Game is live';
    v_body := new.title || ' is now live.';
  elsif new.status = 'final' and old.status is distinct from new.status then
    v_category := 'game_final';
    v_title := 'Game final';
    v_body := new.title || ' is final.';
  elsif old.scheduled_start is distinct from new.scheduled_start
     or old.scheduled_end is distinct from new.scheduled_end then
    v_category := 'event_rescheduled';
    v_title := 'Schedule updated';
    v_body := new.title || ' • ' || to_char(new.scheduled_start at time zone new.timezone, 'Mon FMDD, YYYY FMHH12:MI AM');
  else
    v_category := 'event_updated';
    v_title := 'Event updated';
    v_body := new.title || ' has new details.';
  end if;

  update public.sd_notifications
  set archived_at = now()
  where org_id = new.org_id
    and related_entity_type = 'event'
    and related_entity_id = new.id::text
    and archived_at is null
    and category in (
      'event_created', 'event_updated', 'event_canceled', 'event_postponed',
      'event_rescheduled', 'availability_requested', 'game_starting'
    );

  v_recipients := public.sd_event_notification_recipients(new.id);
  if cardinality(v_recipients) = 0 then
    return new;
  end if;

  v_material_version := extract(epoch from new.updated_at)::bigint::text;
  perform public.sd_create_notifications(
    new.org_id,
    v_recipients,
    v_category,
    v_title,
    v_body,
    case when v_game_id is null then 'event' else 'game' end,
    coalesce(v_game_id, new.id)::text,
    case when v_game_id is null then 'event_detail' else 'game_detail' end,
    jsonb_build_object(
      'organization_id', new.org_id::text,
      'event_id', new.id::text,
      'game_id', v_game_id::text
    ),
    'event:' || new.id::text || ':' || v_category || ':' || v_material_version,
    new.updated_by,
    'event',
    jsonb_build_object('status', new.status, 'event_type', new.event_type)
  );
  return new;
end;
$$;

revoke all on function public.sd_notify_event_change()
from public, anon, authenticated;

drop trigger if exists trg_sd_notify_event_change on public.sd_events;
create trigger trg_sd_notify_event_change
after insert or update of title, scheduled_start, scheduled_end, status, location_name
on public.sd_events
for each row execute function public.sd_notify_event_change();

create or replace function public.sd_notify_event_participants_ready()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_event public.sd_events;
  v_game_id uuid;
  v_recipients uuid[];
begin
  select * into v_event from public.sd_events where id = new.event_id;
  if not found or v_event.status = 'draft' then
    return new;
  end if;
  select id into v_game_id from public.sd_games where event_id = v_event.id;
  v_recipients := public.sd_event_notification_recipients(v_event.id);
  if cardinality(v_recipients) = 0 then
    return new;
  end if;
  perform public.sd_create_notifications(
    v_event.org_id,
    v_recipients,
    'event_created',
    case when v_event.event_type = 'game' then 'Game scheduled' else 'Event scheduled' end,
    v_event.title || ' • ' ||
      to_char(v_event.scheduled_start at time zone v_event.timezone, 'Mon FMDD, YYYY FMHH12:MI AM'),
    case when v_game_id is null then 'event' else 'game' end,
    coalesce(v_game_id, v_event.id)::text,
    case when v_game_id is null then 'event_detail' else 'game_detail' end,
    jsonb_build_object(
      'organization_id', v_event.org_id::text,
      'event_id', v_event.id::text,
      'game_id', v_game_id::text
    ),
    'event:' || v_event.id::text || ':event_created',
    v_event.created_by,
    'event',
    jsonb_build_object('status', v_event.status, 'event_type', v_event.event_type)
  );
  return new;
end;
$$;

revoke all on function public.sd_notify_event_participants_ready()
from public, anon, authenticated;

drop trigger if exists trg_sd_notify_event_participants_ready
on public.sd_event_participants;
create trigger trg_sd_notify_event_participants_ready
after insert on public.sd_event_participants
for each row execute function public.sd_notify_event_participants_ready();

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public'
      and tablename = 'sd_events'
  ) then
    alter publication supabase_realtime add table public.sd_events;
  end if;
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public'
      and tablename = 'sd_games'
  ) then
    alter publication supabase_realtime add table public.sd_games;
  end if;
end
$$;

comment on function public.sd_reconcile_event_facility_booking() is
  'Keeps canonical home-game facility blocks synchronized transactionally.';
comment on function public.sd_notify_event_participants_ready() is
  'Creates the initial canonical event notification after recipients exist.';
