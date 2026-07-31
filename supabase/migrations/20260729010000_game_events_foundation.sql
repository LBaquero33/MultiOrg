-- Home Plate Games Phase 1: canonical events, games, participants, attendance,
-- lifecycle, and organization-safe authorization.
-- Rollback guidance: remove client use first, then drop the four tables in
-- reverse dependency order and the helper/RPC functions created below.

create table if not exists public.sd_events (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.sd_orgs(id) on delete cascade,
  title text not null check (char_length(btrim(title)) between 1 and 160),
  event_type text not null check (event_type in (
    'practice', 'game', 'training', 'facility_booking', 'testing',
    'meeting', 'organization_event', 'other'
  )),
  description text,
  scheduled_start timestamptz not null,
  scheduled_end timestamptz not null,
  arrival_time timestamptz,
  timezone text not null default 'America/New_York',
  location_name text,
  venue_address text,
  facility_id uuid references public.sd_facilities(id) on delete set null,
  facility_booking_id uuid references public.sd_facility_bookings(id) on delete set null,
  team_id uuid references public.sd_teams(id) on delete set null,
  visibility text not null default 'participants' check (visibility in (
    'organization', 'team', 'participants', 'staff_only', 'private'
  )),
  status text not null default 'draft' check (status in (
    'draft', 'scheduled', 'pregame', 'live', 'delayed', 'suspended',
    'postponed', 'canceled', 'final', 'forfeit', 'no_contest'
  )),
  recurrence jsonb not null default '{}'::jsonb check (jsonb_typeof(recurrence) = 'object'),
  private_notes text,
  created_by uuid not null references auth.users(id) on delete restrict,
  updated_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  canceled_at timestamptz,
  postponed_at timestamptz,
  check (scheduled_end > scheduled_start),
  check (arrival_time is null or arrival_time <= scheduled_start)
);

create table if not exists public.sd_games (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null unique references public.sd_events(id) on delete cascade,
  org_id uuid not null references public.sd_orgs(id) on delete cascade,
  season_id uuid,
  team_id uuid not null references public.sd_teams(id) on delete restrict,
  opponent_name text not null check (char_length(btrim(opponent_name)) between 1 and 160),
  opponent_org_id uuid references public.sd_orgs(id) on delete set null,
  opponent_team_id uuid references public.sd_teams(id) on delete set null,
  site text not null default 'home' check (site in ('home', 'away', 'neutral')),
  venue_name text,
  scheduled_innings integer not null default 7 check (scheduled_innings between 1 and 20),
  ruleset_id uuid,
  ruleset_version integer,
  ruleset_snapshot jsonb not null default '{}'::jsonb check (jsonb_typeof(ruleset_snapshot) = 'object'),
  assigned_scorekeeper_id uuid references auth.users(id) on delete set null,
  status text not null default 'draft' check (status in (
    'draft', 'scheduled', 'pregame', 'live', 'delayed', 'suspended',
    'postponed', 'canceled', 'final', 'forfeit', 'no_contest'
  )),
  live_status text not null default 'not_started' check (live_status in (
    'not_started', 'pregame', 'live', 'paused', 'suspended', 'final'
  )),
  home_team_name text not null,
  away_team_name text not null,
  lineup_ready boolean not null default false,
  game_version bigint not null default 0 check (game_version >= 0),
  finalized_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.sd_event_participants (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.sd_orgs(id) on delete cascade,
  event_id uuid not null references public.sd_events(id) on delete cascade,
  participant_type text not null check (participant_type in (
    'team', 'player', 'coach', 'scorekeeper', 'organization', 'explicit_invite'
  )),
  user_id uuid references auth.users(id) on delete cascade,
  team_id uuid references public.sd_teams(id) on delete cascade,
  player_id uuid references auth.users(id) on delete cascade,
  role text,
  can_view boolean not null default true,
  can_edit boolean not null default false,
  can_score boolean not null default false,
  invited_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (
    (participant_type = 'team' and team_id is not null)
    or (participant_type in ('player', 'coach', 'scorekeeper', 'explicit_invite') and user_id is not null)
    or participant_type = 'organization'
  )
);

create unique index if not exists ux_sd_event_participants_identity
  on public.sd_event_participants (
    event_id, participant_type,
    coalesce(user_id, '00000000-0000-0000-0000-000000000000'::uuid),
    coalesce(team_id, '00000000-0000-0000-0000-000000000000'::uuid)
  );

create table if not exists public.sd_event_attendance (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.sd_orgs(id) on delete cascade,
  event_id uuid not null references public.sd_events(id) on delete cascade,
  player_id uuid not null references auth.users(id) on delete cascade,
  availability text not null default 'unknown' check (availability in (
    'unknown', 'available', 'unavailable', 'tentative'
  )),
  expected_attendance boolean,
  actual_attendance text check (actual_attendance is null or actual_attendance in (
    'present', 'late', 'excused', 'absent', 'did_not_play'
  )),
  response_author_id uuid references auth.users(id) on delete set null,
  notes text,
  responded_at timestamptz,
  recorded_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (event_id, player_id)
);

create index if not exists idx_sd_events_org_start
  on public.sd_events(org_id, scheduled_start, id);
create index if not exists idx_sd_events_team_start
  on public.sd_events(org_id, team_id, scheduled_start);
create index if not exists idx_sd_events_facility_time
  on public.sd_events(org_id, facility_id, scheduled_start, scheduled_end)
  where facility_id is not null and status not in ('canceled', 'no_contest');
create index if not exists idx_sd_games_org_team
  on public.sd_games(org_id, team_id, status);
create index if not exists idx_sd_event_participants_event
  on public.sd_event_participants(org_id, event_id);
create index if not exists idx_sd_event_participants_user
  on public.sd_event_participants(org_id, user_id, event_id) where user_id is not null;
create index if not exists idx_sd_event_attendance_event
  on public.sd_event_attendance(org_id, event_id, player_id);

drop trigger if exists sd_events_touch on public.sd_events;
create trigger sd_events_touch before update on public.sd_events
for each row execute function public.sd_touch_updated_at();
drop trigger if exists sd_games_touch on public.sd_games;
create trigger sd_games_touch before update on public.sd_games
for each row execute function public.sd_touch_updated_at();
drop trigger if exists sd_event_participants_touch on public.sd_event_participants;
create trigger sd_event_participants_touch before update on public.sd_event_participants
for each row execute function public.sd_touch_updated_at();
drop trigger if exists sd_event_attendance_touch on public.sd_event_attendance;
create trigger sd_event_attendance_touch before update on public.sd_event_attendance
for each row execute function public.sd_touch_updated_at();

create or replace function public.sd_is_platform_admin_game_support()
returns boolean language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.sd_platform_admins a where a.user_id = auth.uid()
  );
$$;

create or replace function public.sd_can_view_event(p_event_id uuid)
returns boolean language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1
    from public.sd_events e
    where e.id = p_event_id
      and (
        public.sd_is_platform_admin_game_support()
        or public.sd_is_org_admin(e.org_id)
        or (
          e.visibility = 'organization'
          and public.sd_is_org_member(e.org_id)
        )
        or (
          e.visibility in ('team', 'participants')
          and e.team_id is not null
          and exists (
            select 1 from public.sd_team_members tm
            where tm.org_id = e.org_id
              and tm.team_id = e.team_id
              and tm.player_id = auth.uid()
          )
        )
        or exists (
          select 1 from public.sd_event_participants p
          where p.event_id = e.id
            and p.org_id = e.org_id
            and p.can_view
            and (
              p.user_id = auth.uid()
              or (
                p.team_id is not null and exists (
                  select 1 from public.sd_team_members tm
                  where tm.org_id = e.org_id
                    and tm.team_id = p.team_id
                    and tm.player_id = auth.uid()
                )
              )
              or (
                p.player_id is not null
                and public.sd_is_linked_parent_in_org(auth.uid(), p.player_id, e.org_id)
              )
            )
        )
        or exists (
          select 1
          from public.sd_event_participants child_participant
          join public.sd_parent_child_links link
            on link.org_id = e.org_id
           and link.child_id = child_participant.user_id
           and link.parent_id = auth.uid()
          where child_participant.event_id = e.id
            and child_participant.participant_type = 'player'
            and child_participant.can_view
        )
      )
  );
$$;

create or replace function public.sd_can_manage_event(p_event_id uuid)
returns boolean language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1
    from public.sd_events e
    where e.id = p_event_id
      and (
        public.sd_is_org_admin(e.org_id)
        or exists (
          select 1 from public.sd_event_participants p
          where p.event_id = e.id
            and p.user_id = auth.uid()
            and p.can_edit
            and public.sd_is_org_staff(e.org_id)
        )
      )
  );
$$;

revoke all on function public.sd_is_platform_admin_game_support() from public, anon;
revoke all on function public.sd_can_view_event(uuid) from public, anon;
revoke all on function public.sd_can_manage_event(uuid) from public, anon;
grant execute on function public.sd_is_platform_admin_game_support() to authenticated;
grant execute on function public.sd_can_view_event(uuid) to authenticated;
grant execute on function public.sd_can_manage_event(uuid) to authenticated;

alter table public.sd_events enable row level security;
alter table public.sd_games enable row level security;
alter table public.sd_event_participants enable row level security;
alter table public.sd_event_attendance enable row level security;

create policy "sd_events_select_authorized" on public.sd_events
for select to authenticated using (public.sd_can_view_event(id));
create policy "sd_events_insert_admin" on public.sd_events
for insert to authenticated with check (
  public.sd_is_org_admin(org_id)
  and created_by = auth.uid() and updated_by = auth.uid()
);
create policy "sd_events_update_manager" on public.sd_events
for update to authenticated using (public.sd_can_manage_event(id))
with check (public.sd_can_manage_event(id) and updated_by = auth.uid());
create policy "sd_events_delete_draft_admin" on public.sd_events
for delete to authenticated using (
  status = 'draft' and public.sd_is_org_admin(org_id)
);

create policy "sd_games_select_authorized" on public.sd_games
for select to authenticated using (public.sd_can_view_event(event_id));
create policy "sd_games_insert_admin" on public.sd_games
for insert to authenticated with check (
  public.sd_is_org_admin(org_id)
  and exists (
    select 1 from public.sd_events e
    where e.id = event_id and e.org_id = sd_games.org_id and e.event_type = 'game'
  )
);
create policy "sd_games_update_manager" on public.sd_games
for update to authenticated using (public.sd_can_manage_event(event_id))
with check (public.sd_can_manage_event(event_id));

create policy "sd_event_participants_select_authorized" on public.sd_event_participants
for select to authenticated using (public.sd_can_view_event(event_id));
create policy "sd_event_participants_manage" on public.sd_event_participants
for all to authenticated using (public.sd_can_manage_event(event_id))
with check (
  public.sd_can_manage_event(event_id)
  and exists (
    select 1 from public.sd_events e
    where e.id = event_id and e.org_id = sd_event_participants.org_id
  )
);

create policy "sd_event_attendance_select_authorized" on public.sd_event_attendance
for select to authenticated using (public.sd_can_view_event(event_id));
create policy "sd_event_attendance_respond" on public.sd_event_attendance
for insert to authenticated with check (
  public.sd_can_view_event(event_id)
  and response_author_id = auth.uid()
  and (
    player_id = auth.uid()
    or public.sd_is_linked_parent_in_org(auth.uid(), player_id, org_id)
    or public.sd_can_manage_event(event_id)
  )
);
create policy "sd_event_attendance_update" on public.sd_event_attendance
for update to authenticated using (
  player_id = auth.uid()
  or public.sd_is_linked_parent_in_org(auth.uid(), player_id, org_id)
  or public.sd_can_manage_event(event_id)
)
with check (
  response_author_id = auth.uid()
  or public.sd_can_manage_event(event_id)
);

grant select, insert, update, delete on public.sd_events to authenticated;
grant select, insert, update on public.sd_games to authenticated;
grant select, insert, update, delete on public.sd_event_participants to authenticated;
grant select, insert, update on public.sd_event_attendance to authenticated;

create or replace function public.sd_create_game(
  p_org_id uuid,
  p_team_id uuid,
  p_title text,
  p_opponent_name text,
  p_scheduled_start timestamptz,
  p_scheduled_end timestamptz,
  p_arrival_time timestamptz default null,
  p_timezone text default 'America/New_York',
  p_site text default 'home',
  p_venue_name text default null,
  p_facility_id uuid default null,
  p_scheduled_innings integer default 7,
  p_visibility text default 'team'
) returns public.sd_games
language plpgsql security definer set search_path = ''
as $$
declare
  v_event public.sd_events;
  v_game public.sd_games;
  v_org_name text;
  v_team_name text;
begin
  if not public.sd_is_org_admin(p_org_id) then
    raise exception 'game_create_forbidden' using errcode = '42501';
  end if;
  select name into v_team_name from public.sd_teams
  where id = p_team_id and org_id = p_org_id and is_active;
  if v_team_name is null then
    raise exception 'game_team_invalid' using errcode = '23503';
  end if;
  if p_facility_id is not null and p_site <> 'home' then
    raise exception 'away_game_internal_facility_not_allowed' using errcode = '23514';
  end if;
  if p_facility_id is not null and not exists (
    select 1 from public.sd_facilities f
    where f.id = p_facility_id and f.org_id = p_org_id and f.is_active
  ) then
    raise exception 'game_facility_invalid' using errcode = '23503';
  end if;
  select name into v_org_name from public.sd_orgs where id = p_org_id;

  insert into public.sd_events (
    org_id, title, event_type, scheduled_start, scheduled_end, arrival_time,
    timezone, location_name, facility_id, team_id, visibility, status,
    created_by, updated_by
  ) values (
    p_org_id, p_title, 'game', p_scheduled_start, p_scheduled_end, p_arrival_time,
    p_timezone, p_venue_name, p_facility_id, p_team_id, p_visibility, 'scheduled',
    auth.uid(), auth.uid()
  ) returning * into v_event;

  insert into public.sd_games (
    event_id, org_id, team_id, opponent_name, site, venue_name,
    scheduled_innings, status, home_team_name, away_team_name
  ) values (
    v_event.id, p_org_id, p_team_id, p_opponent_name, p_site, p_venue_name,
    p_scheduled_innings, 'scheduled',
    case when p_site = 'away' then p_opponent_name else coalesce(v_team_name, v_org_name) end,
    case when p_site = 'away' then coalesce(v_team_name, v_org_name) else p_opponent_name end
  ) returning * into v_game;

  insert into public.sd_event_participants (
    org_id, event_id, participant_type, team_id, role, can_view, can_edit, invited_by
  ) values (
    p_org_id, v_event.id, 'team', p_team_id, 'team', true, false, auth.uid()
  );
  return v_game;
end;
$$;

revoke all on function public.sd_create_game(
  uuid, uuid, text, text, timestamptz, timestamptz, timestamptz,
  text, text, text, uuid, integer, text
) from public, anon;
grant execute on function public.sd_create_game(
  uuid, uuid, text, text, timestamptz, timestamptz, timestamptz,
  text, text, text, uuid, integer, text
) to authenticated;

comment on table public.sd_events is 'Canonical organization calendar events.';
comment on table public.sd_games is 'First-class baseball game specialization of sd_events.';
comment on table public.sd_event_participants is 'Explicit event visibility and role assignments.';
comment on table public.sd_event_attendance is 'Availability, expected attendance, and actual attendance ledger.';
