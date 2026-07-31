-- Keep scorekeeping transfer and scoring mutations on the same game -> session
-- lock order so a live scoring event cannot deadlock an approved transfer.

create or replace function public.sd_resolve_scorekeeping_control_request(
  p_request_id uuid,
  p_approve boolean,
  p_active_device_id uuid,
  p_control_token text
) returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_request public.sd_game_control_requests;
  v_session public.sd_game_scorekeeper_sessions;
  v_game public.sd_games;
begin
  select * into v_request
  from public.sd_game_control_requests
  where id = p_request_id and status = 'pending'
  for update;

  if not found then
    raise exception 'control_request_not_pending';
  end if;

  select * into v_game
  from public.sd_games
  where id = v_request.game_id
  for update;

  if not found then
    raise exception 'game_not_found';
  end if;

  select * into v_session
  from public.sd_game_scorekeeper_sessions
  where game_id = v_request.game_id
  for update;

  if not found
     or v_session.active_user_id <> auth.uid()
     or v_session.active_device_id <> p_active_device_id
     or v_session.session_status <> 'active'
     or v_session.lease_expires_at <= now()
     or v_session.control_token_hash <> encode(
       extensions.digest(p_control_token, 'sha256'),
       'hex'
     )
  then
    raise exception 'active_scorekeeper_proof_invalid';
  end if;

  if not p_approve then
    update public.sd_game_control_requests
    set status = 'declined',
        resolved_at = now(),
        resolved_by = auth.uid(),
        updated_at = now()
    where id = p_request_id;
    return false;
  end if;

  update public.sd_game_scorekeeper_sessions
  set active_user_id = v_request.requesting_user_id,
      active_device_id = v_request.requesting_device_id,
      control_token_hash = v_request.requested_token_hash,
      authenticated_session_id = 'approved-transfer',
      acquired_at = now(),
      heartbeat_at = now(),
      lease_expires_at = now() + interval '45 seconds',
      session_status = 'active',
      current_game_version = v_game.game_version,
      updated_at = now()
  where game_id = v_request.game_id;

  update public.sd_game_control_requests
  set status = 'approved',
      resolved_at = now(),
      resolved_by = auth.uid(),
      updated_at = now()
  where id = p_request_id;

  update public.sd_game_live_devices
  set state = 'liveViewer',
      updated_at = now()
  where game_id = v_request.game_id
    and user_id = auth.uid()
    and device_id = p_active_device_id;

  insert into public.sd_game_live_devices(
    org_id,
    game_id,
    user_id,
    device_id,
    state
  ) values (
    v_request.org_id,
    v_request.game_id,
    v_request.requesting_user_id,
    v_request.requesting_device_id,
    'liveScorekeeper'
  )
  on conflict (game_id, user_id, device_id)
  do update set
    state = excluded.state,
    last_seen_at = now(),
    updated_at = now();

  return true;
end;
$$;

grant execute on function public.sd_resolve_scorekeeping_control_request(
  uuid,
  boolean,
  uuid,
  text
) to authenticated;
