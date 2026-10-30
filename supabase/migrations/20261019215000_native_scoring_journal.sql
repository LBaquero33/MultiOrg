-- Prerequisite: 20260908001300_native_atomic_scoring.sql.
-- Add the minimal compatible columns for native migration histories that do not
-- contain the web v2 migration. Existing v2 columns and permit semantics remain.
begin;

alter table public.sd_games
  add column if not exists scoring_schema_version integer not null default 1
    check (scoring_schema_version in (1, 2));
alter table public.sd_game_scorekeeper_sessions
  add column if not exists authority_epoch bigint not null default 1
    check (authority_epoch > 0);

create or replace function public.sd_track_native_scoring_authority()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if exists (select 1 from public.sd_games g
    where g.id = new.game_id and g.scoring_schema_version = 1)
    and (new.active_user_id is distinct from old.active_user_id
      or new.active_device_id is distinct from old.active_device_id) then
    new.authority_epoch := greatest(old.authority_epoch + 1, new.authority_epoch);
  end if;
  return new;
end;
$$;
revoke all on function public.sd_track_native_scoring_authority() from public, anon, authenticated;

create trigger trg_native_scoring_authority_epoch
before update on public.sd_game_scorekeeper_sessions
for each row execute function public.sd_track_native_scoring_authority();

create or replace function public.sd_acquire_native_scorekeeping_control(
  p_game_id uuid,
  p_device_id uuid,
  p_authenticated_session_id text,
  p_expected_authority_epoch bigint default null
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_game public.sd_games;
  v_session public.sd_game_scorekeeper_sessions;
  v_result jsonb;
begin
  if auth.uid() is null or p_device_id is null
    or coalesce(length(p_authenticated_session_id), 0) not between 1 and 256
    or p_authenticated_session_id is distinct from (auth.jwt() ->> 'session_id')
    or not public.sd_can_score_game(p_game_id) then
    raise exception using errcode = '42501', message = 'scorekeeping_not_authorized';
  end if;
  select * into v_game from public.sd_games where id = p_game_id for update;
  if not found then raise exception 'game_not_found'; end if;
  if v_game.scoring_schema_version <> 1 then
    raise exception 'native_scoring_schema_unsupported';
  end if;
  select * into v_session from public.sd_game_scorekeeper_sessions
    where game_id = p_game_id for update;
  if p_expected_authority_epoch is not null and (
    v_session.game_id is null
    or v_session.authority_epoch is distinct from p_expected_authority_epoch
    or v_session.active_user_id is distinct from auth.uid()
    or v_session.active_device_id is distinct from p_device_id
  ) then
    return jsonb_build_object('state', 'reconciliationRequired',
      'game_version', v_game.game_version,
      'authority_epoch', v_session.authority_epoch);
  end if;
  v_result := public.sd_acquire_scorekeeping_control(
    p_game_id, p_device_id, p_authenticated_session_id
  );
  select * into v_session from public.sd_game_scorekeeper_sessions where game_id = p_game_id;
  return v_result || jsonb_build_object(
    'authority_epoch', v_session.authority_epoch,
    'active_user_id', v_session.active_user_id,
    'active_device_id', v_session.active_device_id,
    'schema_version', 1
  );
end;
$$;

create or replace function public.sd_append_native_journal_command(
  p_game_id uuid,
  p_canonical_event_id uuid,
  p_expected_version bigint,
  p_actor_device_id uuid,
  p_control_token text,
  p_command_id uuid,
  p_expected_authority_epoch bigint,
  p_events jsonb
) returns setof public.sd_game_scoring_events
language plpgsql security definer set search_path = '' as $$
declare
  v_game public.sd_games;
  v_session public.sd_game_scorekeeper_sessions;
begin
  if auth.uid() is null or not public.sd_can_score_game(p_game_id) then
    raise exception using errcode = '42501', message = 'scorekeeping_not_authorized';
  end if;
  select * into v_game from public.sd_games where id = p_game_id for update;
  if not found or v_game.event_id is distinct from p_canonical_event_id then
    raise exception 'game_not_found';
  end if;
  if v_game.scoring_schema_version <> 1 then raise exception 'native_scoring_schema_unsupported'; end if;
  select * into v_session from public.sd_game_scorekeeper_sessions
    where game_id = p_game_id for update;
  if not found or p_expected_authority_epoch is null
    or v_session.authority_epoch is distinct from p_expected_authority_epoch
    or v_session.active_user_id is distinct from auth.uid()
    or v_session.active_device_id is distinct from p_actor_device_id
    or v_session.session_status is distinct from 'active'
    or v_session.lease_expires_at is null
    or v_session.lease_expires_at <= now()
    or p_control_token is null
    or v_session.control_token_hash is distinct from
      encode(extensions.digest(p_control_token, 'sha256'), 'hex') then
    raise exception using errcode = '42501', message = 'native_authority_requires_reconciliation';
  end if;
  return query select * from public.sd_append_native_scoring_command(
    p_game_id, p_canonical_event_id, p_expected_version,
    p_actor_device_id, p_control_token, p_command_id, p_events
  );
end;
$$;

revoke all on function public.sd_acquire_native_scorekeeping_control(uuid,uuid,text,bigint)
  from public, anon;
revoke all on function public.sd_append_native_journal_command(uuid,uuid,bigint,uuid,text,uuid,bigint,jsonb)
  from public, anon;
grant execute on function public.sd_acquire_native_scorekeeping_control(uuid,uuid,text,bigint)
  to authenticated;
grant execute on function public.sd_append_native_journal_command(uuid,uuid,bigint,uuid,text,uuid,bigint,jsonb)
  to authenticated;

commit;
