-- Coaches need attendance visibility for every scheduled event, not games only.
-- Keep the established RPC signature so deployed clients remain compatible.
create or replace function public.sd_game_attendance_roster(
  p_org_id uuid,
  p_event_ids uuid[]
)
returns table (
  event_id uuid,
  player_id uuid,
  display_name text,
  expected_attendance boolean,
  responded_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  if not exists (
    select 1
    from public.sd_org_memberships membership
    where membership.org_id = p_org_id
      and membership.user_id = auth.uid()
      and membership.status = 'active'
      and membership.role in ('owner', 'admin', 'coach')
  ) then
    raise exception 'not_authorized' using errcode = '42501';
  end if;

  if pg_catalog.cardinality(coalesce(p_event_ids, '{}'::uuid[])) > 100 then
    raise exception 'event_limit_exceeded' using errcode = '22023';
  end if;

  return query
  with requested_events as (
    select event.id, event.team_id
    from public.sd_events event
    where event.org_id = p_org_id
      and event.id = any(coalesce(p_event_ids, '{}'::uuid[]))
  ),
  event_teams as (
    select event.id as event_id, event.team_id
    from requested_events event
    where event.team_id is not null
    union
    select participant.event_id, participant.team_id
    from public.sd_event_participants participant
    join requested_events event on event.id = participant.event_id
    where participant.org_id = p_org_id
      and participant.participant_type = 'team'
      and participant.team_id is not null
  ),
  expected_players as (
    select teams.event_id, membership.player_id
    from event_teams teams
    join public.sd_player_team_memberships membership
      on membership.organization_id = p_org_id
      and membership.team_id = teams.team_id
      and membership.active = true
      and membership.ended_at is null
    union
    select participant.event_id, coalesce(participant.player_id, participant.user_id)
    from public.sd_event_participants participant
    join requested_events event on event.id = participant.event_id
    where participant.org_id = p_org_id
      and (participant.participant_type = 'player' or participant.role = 'player')
      and coalesce(participant.player_id, participant.user_id) is not null
  )
  select
    expected.event_id,
    expected.player_id,
    coalesce(nullif(pg_catalog.btrim(profile.full_name), ''), 'Player') as display_name,
    attendance.expected_attendance,
    attendance.responded_at
  from expected_players expected
  left join public.profiles profile on profile.id = expected.player_id
  left join public.sd_event_attendance attendance
    on attendance.org_id = p_org_id
    and attendance.event_id = expected.event_id
    and attendance.player_id = expected.player_id
  order by expected.event_id, display_name, expected.player_id;
end;
$$;

revoke all on function public.sd_game_attendance_roster(uuid, uuid[]) from public, anon, authenticated;
grant execute on function public.sd_game_attendance_roster(uuid, uuid[]) to authenticated;
