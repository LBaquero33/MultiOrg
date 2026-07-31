-- Preserve every calendar category introduced in Phase 2 when adding the
-- scorekeeping-specific game update category from Phase 9.

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
    'game_live', 'game_final', 'game_update', 'system'
  )) not valid;
alter table public.sd_notifications
  validate constraint sd_notifications_category_check;

create or replace function public.sd_insert_game_notification(
  p_org_id uuid,
  p_event_id uuid,
  p_game_id uuid,
  p_title text,
  p_body text,
  p_deduplication_key text
) returns void
language plpgsql
security definer
set search_path = ''
as $$
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
      on team_member.org_id = event.org_id
     and team_member.team_id = event.team_id
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
    union
    select parent_link.parent_id
    from public.sd_events event
    join public.sd_team_members team_member
      on team_member.org_id = event.org_id
     and team_member.team_id = event.team_id
    join public.sd_parent_child_links parent_link
      on parent_link.org_id = team_member.org_id
     and parent_link.child_id = team_member.player_id
    where event.id = p_event_id
  ) recipient
  where recipient.user_id is not null
  on conflict (org_id, recipient_user_id, category, deduplication_key) do nothing;
end;
$$;

revoke all on function public.sd_insert_game_notification(
  uuid, uuid, uuid, text, text, text
) from public, anon, authenticated;
