begin;
-- Legacy native games use schema 1. Never append these commands to a v2
-- projection: those games must use the v2 envelope/permit contract.
create function public.sd_append_native_scoring_command(
  p_game_id uuid, p_canonical_event_id uuid, p_expected_version bigint,
  p_actor_device_id uuid, p_control_token text, p_command_id uuid, p_events jsonb
) returns setof public.sd_game_scoring_events
language plpgsql security definer set search_path = '' as $$
declare
  v_game public.sd_games;
  v_row jsonb;
  v_existing public.sd_game_scoring_events;
  v_index integer := 0;
  v_count integer;
  v_key text;
begin
  if auth.uid() is null or not public.sd_can_score_game(p_game_id) then
    raise exception 'scorekeeping_not_authorized' using errcode='42501';
  end if;
  if p_command_id is null or p_actor_device_id is null or
    jsonb_typeof(p_events) is distinct from 'array' or jsonb_array_length(p_events) not between 1 and 2 then
    raise exception 'invalid_native_scoring_command';
  end if;
  select * into v_game from public.sd_games where id=p_game_id for update;
  if not found or v_game.event_id is distinct from p_canonical_event_id then raise exception 'game_not_found'; end if;
  if v_game.scoring_schema_version <> 1 then raise exception 'native_scoring_schema_unsupported'; end if;
  if jsonb_array_length(p_events)=2 and
    ((p_events->0->>'event_type') is distinct from 'pitch_thrown' or
     (p_events->1->>'event_type') not in ('pitch_result_recorded','ball_put_in_play')) then
    raise exception 'invalid_compound_pitch';
  end if;
  select count(*) into v_count from public.sd_game_scoring_events
    where game_id=p_game_id and idempotency_key like 'native:'||p_command_id||':%';
  if v_count > 0 and v_count <> jsonb_array_length(p_events) then raise exception 'partial_command_requires_review'; end if;
  for v_row in select value from jsonb_array_elements(p_events) loop
    v_key := 'native:'||p_command_id||':'||v_index;
    if v_count > 0 then
      select * into v_existing from public.sd_game_scoring_events where game_id=p_game_id and idempotency_key=v_key;
      if not found or v_existing.actor_user_id<>auth.uid() or v_existing.actor_device_id<>p_actor_device_id
        or v_existing.id is distinct from (v_row->>'id')::uuid
        or v_existing.event_type is distinct from v_row->>'event_type'
        or v_existing.payload is distinct from v_row->'payload'
        or v_existing.game_version<>p_expected_version+v_index+1 then
        raise exception 'scoring_command_retry_changed';
      end if;
      return next v_existing;
    else
      return next public.sd_append_game_scoring_event(
        p_game_id,p_canonical_event_id,(v_row->>'id')::uuid,p_expected_version+v_index,
        v_row->>'event_type',p_actor_device_id,p_control_token,v_row->'payload',v_key
      );
    end if;
    v_index:=v_index+1;
  end loop;
end; $$;
revoke all on function public.sd_append_native_scoring_command(uuid,uuid,bigint,uuid,text,uuid,jsonb) from public,anon;
grant execute on function public.sd_append_native_scoring_command(uuid,uuid,bigint,uuid,text,uuid,jsonb) to authenticated;
commit;
