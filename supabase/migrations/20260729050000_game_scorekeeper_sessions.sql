-- Phase 6: server-authoritative scorekeeper lease and live viewers.
-- Rollback: stop live games, then drop RPCs, policies, and session tables.

create table if not exists public.sd_game_scorekeeper_sessions (
  game_id uuid primary key references public.sd_games(id) on delete cascade,
  org_id uuid not null references public.sd_orgs(id) on delete cascade,
  active_user_id uuid not null references auth.users(id),
  active_device_id uuid not null,
  control_token_hash text not null,
  authenticated_session_id text not null,
  acquired_at timestamptz not null default now(),
  heartbeat_at timestamptz not null default now(),
  lease_expires_at timestamptz not null,
  session_status text not null default 'active'
    check (session_status in ('active','released','transferred','expired')),
  current_game_version bigint not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.sd_game_control_requests (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.sd_orgs(id) on delete cascade,
  game_id uuid not null references public.sd_games(id) on delete cascade,
  requesting_user_id uuid not null references auth.users(id),
  requesting_device_id uuid not null,
  requested_token_hash text not null,
  status text not null default 'pending'
    check (status in ('pending','approved','declined','canceled')),
  requested_at timestamptz not null default now(),
  resolved_at timestamptz,
  resolved_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.sd_game_live_devices (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.sd_orgs(id) on delete cascade,
  game_id uuid not null references public.sd_games(id) on delete cascade,
  user_id uuid not null references auth.users(id),
  device_id uuid not null,
  state text not null check (state in ('liveScorekeeper','liveViewer','requestingControl','disconnected')),
  last_seen_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (game_id, user_id, device_id)
);

create index if not exists sd_game_control_requests_pending_idx
  on public.sd_game_control_requests(game_id, status) where status = 'pending';
create index if not exists sd_game_live_devices_game_seen_idx
  on public.sd_game_live_devices(game_id, last_seen_at desc);

alter table public.sd_game_scorekeeper_sessions enable row level security;
alter table public.sd_game_control_requests enable row level security;
alter table public.sd_game_live_devices enable row level security;
create policy sd_game_scorekeeper_sessions_select on public.sd_game_scorekeeper_sessions
for select using (exists (
  select 1 from public.sd_games g where g.id = game_id and public.sd_can_view_event(g.event_id)
));
create policy sd_game_control_requests_select on public.sd_game_control_requests
for select using (requesting_user_id = auth.uid() or public.sd_can_score_game(game_id));
create policy sd_game_live_devices_select on public.sd_game_live_devices
for select using (exists (
  select 1 from public.sd_games g where g.id = game_id and public.sd_can_view_event(g.event_id)
));
grant select on public.sd_game_scorekeeper_sessions, public.sd_game_control_requests,
  public.sd_game_live_devices to authenticated;

create or replace function public.sd_acquire_scorekeeping_control(
  p_game_id uuid, p_device_id uuid, p_authenticated_session_id text
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_game public.sd_games;
  v_session public.sd_game_scorekeeper_sessions;
  v_token text := encode(extensions.gen_random_bytes(32), 'hex');
begin
  select * into v_game from public.sd_games where id = p_game_id for update;
  if not found or not public.sd_can_score_game(p_game_id) then raise exception 'scorekeeping_not_authorized'; end if;
  select * into v_session from public.sd_game_scorekeeper_sessions where game_id = p_game_id for update;
  if found and v_session.session_status = 'active' and v_session.lease_expires_at > now()
     and not (v_session.active_user_id = auth.uid() and v_session.active_device_id = p_device_id) then
    return jsonb_build_object('state','liveViewer','game_version',v_game.game_version);
  end if;
  insert into public.sd_game_scorekeeper_sessions (
    game_id, org_id, active_user_id, active_device_id, control_token_hash,
    authenticated_session_id, lease_expires_at, current_game_version
  ) values (
    v_game.id, v_game.org_id, auth.uid(), p_device_id,
    encode(extensions.digest(v_token, 'sha256'), 'hex'),
    p_authenticated_session_id, now() + interval '45 seconds', v_game.game_version
  ) on conflict (game_id) do update set
    active_user_id = excluded.active_user_id, active_device_id = excluded.active_device_id,
    control_token_hash = excluded.control_token_hash,
    authenticated_session_id = excluded.authenticated_session_id,
    acquired_at = now(), heartbeat_at = now(), lease_expires_at = excluded.lease_expires_at,
    session_status = 'active', current_game_version = excluded.current_game_version,
    updated_at = now();
  return jsonb_build_object(
    'state','liveScorekeeper','control_token',v_token,
    'lease_expires_at',now() + interval '45 seconds','game_version',v_game.game_version
  );
end;
$$;

create or replace function public.sd_renew_scorekeeping_control(
  p_game_id uuid, p_device_id uuid, p_control_token text
) returns boolean language plpgsql security definer set search_path = '' as $$
begin
  update public.sd_game_scorekeeper_sessions set
    heartbeat_at = now(), lease_expires_at = now() + interval '45 seconds', updated_at = now()
  where game_id = p_game_id and active_user_id = auth.uid()
    and active_device_id = p_device_id and session_status = 'active'
    and lease_expires_at > now()
    and control_token_hash = encode(extensions.digest(p_control_token, 'sha256'), 'hex');
  return found;
end;
$$;

create or replace function public.sd_release_scorekeeping_control(
  p_game_id uuid, p_device_id uuid, p_control_token text
) returns boolean language plpgsql security definer set search_path = '' as $$
begin
  update public.sd_game_scorekeeper_sessions set session_status = 'released',
    lease_expires_at = now(), updated_at = now()
  where game_id = p_game_id and active_user_id = auth.uid()
    and active_device_id = p_device_id
    and control_token_hash = encode(extensions.digest(p_control_token, 'sha256'), 'hex');
  return found;
end;
$$;

create or replace function public.sd_request_scorekeeping_control(
  p_game_id uuid, p_device_id uuid
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_game public.sd_games;
  v_request public.sd_game_control_requests;
  v_token text := encode(extensions.gen_random_bytes(32), 'hex');
begin
  select * into v_game from public.sd_games where id = p_game_id;
  if not found or not public.sd_can_score_game(p_game_id) then raise exception 'scorekeeping_not_authorized'; end if;
  update public.sd_game_control_requests
    set status = 'canceled', resolved_at = now(), updated_at = now()
    where game_id = p_game_id and requesting_user_id = auth.uid()
      and requesting_device_id = p_device_id and status = 'pending';
  insert into public.sd_game_control_requests(
    org_id, game_id, requesting_user_id, requesting_device_id, requested_token_hash
  ) values(
    v_game.org_id, p_game_id, auth.uid(), p_device_id,
    encode(extensions.digest(v_token, 'sha256'), 'hex')
  ) returning * into v_request;
  return jsonb_build_object(
    'request_id', v_request.id, 'state', 'requestingControl', 'control_token', v_token
  );
end;
$$;

create or replace function public.sd_resolve_scorekeeping_control_request(
  p_request_id uuid, p_approve boolean, p_active_device_id uuid, p_control_token text
) returns boolean language plpgsql security definer set search_path = '' as $$
declare
  v_request public.sd_game_control_requests;
  v_session public.sd_game_scorekeeper_sessions;
  v_game public.sd_games;
begin
  select * into v_request from public.sd_game_control_requests
    where id = p_request_id and status = 'pending' for update;
  if not found then raise exception 'control_request_not_pending'; end if;
  select * into v_session from public.sd_game_scorekeeper_sessions
    where game_id = v_request.game_id for update;
  if not found or v_session.active_user_id <> auth.uid()
     or v_session.active_device_id <> p_active_device_id
     or v_session.session_status <> 'active'
     or v_session.lease_expires_at <= now()
     or v_session.control_token_hash <> encode(extensions.digest(p_control_token, 'sha256'), 'hex')
  then
    raise exception 'active_scorekeeper_proof_invalid';
  end if;
  if not p_approve then
    update public.sd_game_control_requests set
      status = 'declined', resolved_at = now(), resolved_by = auth.uid(), updated_at = now()
      where id = p_request_id;
    return false;
  end if;
  select * into v_game from public.sd_games where id = v_request.game_id for update;
  update public.sd_game_scorekeeper_sessions set
    active_user_id = v_request.requesting_user_id,
    active_device_id = v_request.requesting_device_id,
    control_token_hash = v_request.requested_token_hash,
    authenticated_session_id = 'approved-transfer',
    acquired_at = now(), heartbeat_at = now(),
    lease_expires_at = now() + interval '45 seconds',
    session_status = 'active', current_game_version = v_game.game_version, updated_at = now()
    where game_id = v_request.game_id;
  update public.sd_game_control_requests set
    status = 'approved', resolved_at = now(), resolved_by = auth.uid(), updated_at = now()
    where id = p_request_id;
  update public.sd_game_live_devices set state = 'liveViewer', updated_at = now()
    where game_id = v_request.game_id and user_id = auth.uid() and device_id = p_active_device_id;
  insert into public.sd_game_live_devices(org_id, game_id, user_id, device_id, state)
    values(v_request.org_id, v_request.game_id, v_request.requesting_user_id,
      v_request.requesting_device_id, 'liveScorekeeper')
    on conflict(game_id,user_id,device_id) do update set
      state = excluded.state, last_seen_at = now(), updated_at = now();
  return true;
end;
$$;

create or replace function public.sd_mark_game_live_device(
  p_game_id uuid, p_device_id uuid, p_state text
) returns void language plpgsql security definer set search_path = '' as $$
declare v_org uuid;
begin
  if p_state not in ('liveScorekeeper','liveViewer','requestingControl','disconnected') then
    raise exception 'invalid_live_device_state';
  end if;
  select org_id into v_org from public.sd_games g
    where g.id = p_game_id and public.sd_can_view_event(g.event_id);
  if v_org is null then raise exception 'game_not_visible'; end if;
  insert into public.sd_game_live_devices(org_id,game_id,user_id,device_id,state)
    values(v_org,p_game_id,auth.uid(),p_device_id,p_state)
  on conflict(game_id,user_id,device_id) do update set
    state=excluded.state,last_seen_at=now(),updated_at=now();
end;
$$;

create or replace function public.sd_force_scorekeeping_takeover(
  p_game_id uuid, p_device_id uuid, p_authenticated_session_id text
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_org uuid;
begin
  select org_id into v_org from public.sd_games where id = p_game_id;
  if not public.sd_is_org_admin(v_org) then raise exception 'force_takeover_not_authorized'; end if;
  update public.sd_game_scorekeeper_sessions set session_status = 'expired', lease_expires_at = now()
  where game_id = p_game_id;
  return public.sd_acquire_scorekeeping_control(p_game_id, p_device_id, p_authenticated_session_id);
end;
$$;

grant execute on function public.sd_acquire_scorekeeping_control(uuid,uuid,text) to authenticated;
grant execute on function public.sd_renew_scorekeeping_control(uuid,uuid,text) to authenticated;
grant execute on function public.sd_release_scorekeeping_control(uuid,uuid,text) to authenticated;
grant execute on function public.sd_request_scorekeeping_control(uuid,uuid) to authenticated;
grant execute on function public.sd_resolve_scorekeeping_control_request(uuid,boolean,uuid,text) to authenticated;
grant execute on function public.sd_mark_game_live_device(uuid,uuid,text) to authenticated;
grant execute on function public.sd_force_scorekeeping_takeover(uuid,uuid,text) to authenticated;

-- Add lease proof to every mutation. Core event validation remains unchanged.
drop function if exists public.sd_append_game_scoring_event(
  uuid, uuid, uuid, bigint, text, uuid, jsonb, text, uuid, uuid
);
create or replace function public.sd_append_game_scoring_event(
  p_game_id uuid, p_canonical_event_id uuid, p_scoring_event_id uuid,
  p_expected_version bigint, p_event_type text, p_actor_device_id uuid,
  p_control_token text, p_payload jsonb, p_idempotency_key text,
  p_correction_of_event_id uuid default null, p_supersedes_event_id uuid default null
) returns public.sd_game_scoring_events
language plpgsql security definer set search_path = '' as $$
declare v_game public.sd_games; v_existing public.sd_game_scoring_events; v_inserted public.sd_game_scoring_events;
begin
  select * into v_existing from public.sd_game_scoring_events
  where game_id = p_game_id and idempotency_key = p_idempotency_key;
  if found then return v_existing; end if;
  select * into v_game from public.sd_games where id = p_game_id for update;
  if not found or v_game.event_id <> p_canonical_event_id then raise exception 'game_not_found'; end if;
  if not exists (
    select 1 from public.sd_game_scorekeeper_sessions s
    where s.game_id = p_game_id and s.active_user_id = auth.uid()
      and s.active_device_id = p_actor_device_id and s.session_status = 'active'
      and s.lease_expires_at > now()
      and s.control_token_hash = encode(extensions.digest(p_control_token, 'sha256'), 'hex')
  ) then raise exception 'scorekeeper_lease_invalid'; end if;
  if v_game.status in ('final','forfeit','no_contest','canceled') then raise exception 'game_not_mutable'; end if;
  if v_game.game_version <> p_expected_version then raise exception 'stale_game_version'; end if;
  insert into public.sd_game_scoring_events(
    id,org_id,game_id,game_version,sequence,event_type,actor_user_id,actor_device_id,
    payload,ruleset_version,idempotency_key,correction_of_event_id,supersedes_event_id
  ) values (
    p_scoring_event_id,v_game.org_id,p_game_id,p_expected_version+1,p_expected_version+1,
    p_event_type,auth.uid(),p_actor_device_id,coalesce(p_payload,'{}'),v_game.ruleset_version,
    p_idempotency_key,p_correction_of_event_id,p_supersedes_event_id
  ) returning * into v_inserted;
  update public.sd_games set game_version=p_expected_version+1 where id=p_game_id;
  update public.sd_game_scorekeeper_sessions set current_game_version=p_expected_version+1 where game_id=p_game_id;
  insert into public.sd_game_state_snapshots(game_id,org_id,game_version,state,last_event_id)
  values(p_game_id,v_game.org_id,p_expected_version+1,jsonb_build_object('requires_replay',true),p_scoring_event_id)
  on conflict(game_id) do update set game_version=excluded.game_version,state=excluded.state,
    last_event_id=excluded.last_event_id,updated_at=now();
  return v_inserted;
end;
$$;
grant execute on function public.sd_append_game_scoring_event(
  uuid,uuid,uuid,bigint,text,uuid,text,jsonb,text,uuid,uuid
) to authenticated;

do $$ begin
  if not exists (select 1 from pg_publication_tables where pubname='supabase_realtime'
    and schemaname='public' and tablename='sd_game_scoring_events') then
    alter publication supabase_realtime add table public.sd_game_scoring_events;
  end if;
end $$;
