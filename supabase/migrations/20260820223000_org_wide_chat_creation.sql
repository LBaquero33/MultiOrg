-- Allow every active organization member to discover other active members and
-- create direct or group conversations without weakening organization scope.

create or replace function public.sd_chat_directory(target_org_id uuid)
returns table (
  user_id uuid,
  role text,
  display_name text,
  avatar_path text
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
    where membership.org_id = target_org_id
      and membership.user_id = auth.uid()
      and membership.status = 'active'
  ) then
    raise exception 'not_authorized' using errcode = '42501';
  end if;

  return query
  select
    membership.user_id,
    membership.role,
    coalesce(nullif(pg_catalog.btrim(profile.full_name), ''), 'Member') as display_name,
    profile.avatar_path
  from public.sd_org_memberships membership
  left join public.profiles profile on profile.id = membership.user_id
  where membership.org_id = target_org_id
    and membership.status = 'active'
  order by coalesce(nullif(pg_catalog.btrim(profile.full_name), ''), 'Member'), membership.user_id;
end;
$$;
revoke all on function public.sd_chat_directory(uuid) from public, anon, authenticated;
grant execute on function public.sd_chat_directory(uuid) to authenticated;
create or replace function public.sd_create_group_chat(
  p_org_id uuid,
  p_title text,
  p_member_ids uuid[]
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid := auth.uid();
  v_channel_id uuid;
  v_member_ids uuid[];
  v_title text;
begin
  if v_actor_id is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  if not exists (
    select 1
    from public.sd_org_memberships membership
    where membership.org_id = p_org_id
      and membership.user_id = v_actor_id
      and membership.status = 'active'
  ) then
    raise exception 'not_authorized' using errcode = '42501';
  end if;

  select coalesce(pg_catalog.array_agg(candidate.user_id order by candidate.user_id), '{}'::uuid[])
  into v_member_ids
  from (
    select distinct requested.user_id
    from pg_catalog.unnest(coalesce(p_member_ids, '{}'::uuid[])) as requested(user_id)
    where requested.user_id is not null
      and requested.user_id <> v_actor_id
  ) candidate;

  if pg_catalog.cardinality(v_member_ids) < 2 then
    raise exception 'group_requires_two_other_members' using errcode = '22023';
  end if;
  if pg_catalog.cardinality(v_member_ids) > 100 then
    raise exception 'group_member_limit_exceeded' using errcode = '22023';
  end if;

  if exists (
    select 1
    from pg_catalog.unnest(v_member_ids) as requested(user_id)
    where not exists (
      select 1
      from public.sd_org_memberships membership
      where membership.org_id = p_org_id
        and membership.user_id = requested.user_id
        and membership.status = 'active'
    )
  ) then
    raise exception 'group_member_not_in_org' using errcode = '42501';
  end if;

  v_title := nullif(pg_catalog.btrim(coalesce(p_title, '')), '');
  if v_title is not null and pg_catalog.char_length(v_title) > 120 then
    raise exception 'group_title_too_long' using errcode = '22023';
  end if;

  insert into public.sd_chat_channels(org_id, channel_type, title, created_by)
  values (p_org_id, 'group', coalesce(v_title, 'Group conversation'), v_actor_id)
  returning id into v_channel_id;

  insert into public.sd_chat_memberships(
    org_id,
    channel_id,
    user_id,
    member_role,
    last_read_at
  )
  values (p_org_id, v_channel_id, v_actor_id, 'admin', pg_catalog.now());

  insert into public.sd_chat_memberships(org_id, channel_id, user_id, member_role)
  select p_org_id, v_channel_id, requested.user_id, 'member'
  from pg_catalog.unnest(v_member_ids) as requested(user_id);

  return v_channel_id;
end;
$$;
revoke all on function public.sd_create_group_chat(uuid, text, uuid[]) from public, anon, authenticated;
grant execute on function public.sd_create_group_chat(uuid, text, uuid[]) to authenticated;
-- Staff-only roster view for game RSVP tracking. The expected roster combines
-- active team assignments and explicit player participants, then left joins
-- responses so unanswered players remain visible.
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
      and event.event_type = 'game'
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
