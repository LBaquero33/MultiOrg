-- Make compat views writable for Shiny (bridge-both mode).
--
-- Approach:
-- - Add INSTEAD OF triggers on the compat views.
-- - Map legacy integer user_id <-> auth UUID via legacy_auth_links.
-- - Locate rows by comparing the deterministic uuid_to_bigint(uuid) exposed by the views.
--
-- Notes:
-- - This is designed for server-side Shiny usage (DB password / service role).
-- - It does not expose legacy_auth_links to clients; trigger functions are SECURITY DEFINER.

create or replace function public.legacy_user_id_to_auth_uuid(_legacy_user_id bigint)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  out uuid;
begin
  select l.auth_user_id into out
  from public.legacy_auth_links l
  where l.legacy_user_id = _legacy_user_id
  limit 1;

  if out is null then
    raise exception 'No auth_user_id mapping for legacy_user_id=%', _legacy_user_id;
  end if;
  return out;
end;
$$;

revoke all on function public.legacy_user_id_to_auth_uuid(bigint) from public;
grant execute on function public.legacy_user_id_to_auth_uuid(bigint) to anon, authenticated;

-- ------------------------------------------------------------
-- dev_entries (view) -> sd_testing_entries (table)
-- ------------------------------------------------------------
create or replace function public.trg_dev_entries_iou()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  pid uuid;
  target uuid;
begin
  if tg_op = 'INSERT' then
    pid := public.legacy_user_id_to_auth_uuid(new.user_id);
    insert into public.sd_testing_entries (
      player_id,
      entry_date,
      height_in,
      weight_lb,
      squat_1rm,
      bench_1rm,
      deadlift_1rm,
      max_exit_velo,
      avg_exit_velo,
      hip_er_diff,
      hip_ir_diff,
      shoulder_ir_diff,
      shoulder_er_diff,
      notes
    ) values (
      pid,
      new.entry_date::date,
      new.height_in,
      new.weight_lb,
      new.squat_1rm,
      new.bench_1rm,
      new.deadlift_1rm,
      new.max_exit_velo,
      new.avg_exit_velo,
      new.hip_er_diff,
      new.hip_ir_diff,
      new.shoulder_ir_diff,
      new.shoulder_er_diff,
      nullif(coalesce(new.notes, ''), '')
    )
    on conflict (player_id, entry_date) do update set
      height_in = excluded.height_in,
      weight_lb = excluded.weight_lb,
      squat_1rm = excluded.squat_1rm,
      bench_1rm = excluded.bench_1rm,
      deadlift_1rm = excluded.deadlift_1rm,
      max_exit_velo = excluded.max_exit_velo,
      avg_exit_velo = excluded.avg_exit_velo,
      hip_er_diff = excluded.hip_er_diff,
      hip_ir_diff = excluded.hip_ir_diff,
      shoulder_ir_diff = excluded.shoulder_ir_diff,
      shoulder_er_diff = excluded.shoulder_er_diff,
      notes = excluded.notes,
      updated_at = now();
    return null;
  elsif tg_op = 'UPDATE' then
    pid := public.legacy_user_id_to_auth_uuid(old.user_id);
    select e.id into target
    from public.sd_testing_entries e
    where e.player_id = pid
      and public.uuid_to_bigint(e.id) = old.id
    limit 1;
    if target is null then
      -- Fall back to natural key if id mapping doesn't find a row.
      select e.id into target
      from public.sd_testing_entries e
      where e.player_id = pid
        and e.entry_date::text = old.entry_date
      limit 1;
    end if;
    if target is null then
      raise exception 'dev_entries update could not locate row for legacy user %', old.user_id;
    end if;

    update public.sd_testing_entries set
      entry_date = (new.entry_date::date),
      height_in = new.height_in,
      weight_lb = new.weight_lb,
      squat_1rm = new.squat_1rm,
      bench_1rm = new.bench_1rm,
      deadlift_1rm = new.deadlift_1rm,
      max_exit_velo = new.max_exit_velo,
      avg_exit_velo = new.avg_exit_velo,
      hip_er_diff = new.hip_er_diff,
      hip_ir_diff = new.hip_ir_diff,
      shoulder_ir_diff = new.shoulder_ir_diff,
      shoulder_er_diff = new.shoulder_er_diff,
      notes = nullif(coalesce(new.notes, ''), ''),
      updated_at = now()
    where id = target;
    return null;
  elsif tg_op = 'DELETE' then
    pid := public.legacy_user_id_to_auth_uuid(old.user_id);
    delete from public.sd_testing_entries e
    where e.player_id = pid
      and public.uuid_to_bigint(e.id) = old.id;
    return null;
  end if;
  return null;
end;
$$;

drop trigger if exists dev_entries_iou on public.dev_entries;
create trigger dev_entries_iou
instead of insert or update or delete on public.dev_entries
for each row execute function public.trg_dev_entries_iou();

-- ------------------------------------------------------------
-- daily_logs (view) -> sd_daily_logs (table)
-- ------------------------------------------------------------
create or replace function public.trg_daily_logs_iou()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  pid uuid;
begin
  if tg_op = 'INSERT' or tg_op = 'UPDATE' then
    pid := public.legacy_user_id_to_auth_uuid(coalesce(new.user_id, old.user_id));

    insert into public.sd_daily_logs (
      player_id,
      log_date,
      sc_followed_program,
      sc_lifts,
      sc_session_rpe,
      hit_did_bp,
      hit_bp_minutes,
      hit_feel_1_10,
      hit_feel_notes,
      hit_pitch_type,
      hit_environment_competitive,
      hit_avg_exit_velo,
      notes,
      got_video,
      ate_breakfast,
      hit_daily_goals,
      stuck_to_process,
      fell_short,
      excelled,
      sa_completed_at
    ) values (
      pid,
      (coalesce(new.log_date, old.log_date))::date,
      new.sc_followed_program,
      nullif(coalesce(new.sc_lifts, ''), ''),
      new.sc_session_rpe,
      new.hit_did_bp,
      new.hit_bp_minutes,
      new.hit_feel_1_10,
      new.hit_feel_notes,
      new.hit_pitch_type,
      new.hit_environment_competitive,
      new.hit_avg_exit_velo,
      nullif(coalesce(new.notes, ''), ''),
      coalesce(new.sa_got_video, 0) = 1,
      coalesce(new.sa_ate_breakfast, 0) = 1,
      coalesce(new.sa_hit_daily_goals, 0) = 1,
      coalesce(new.sa_stuck_to_process, 0) = 1,
      nullif(coalesce(new.sa_fall_short, ''), ''),
      nullif(coalesce(new.sa_excel, ''), ''),
      case when nullif(coalesce(new.sa_completed_at, ''), '') is null then null else new.sa_completed_at::timestamptz end
    )
    on conflict (player_id, log_date) do update set
      sc_followed_program = excluded.sc_followed_program,
      sc_lifts = excluded.sc_lifts,
      sc_session_rpe = excluded.sc_session_rpe,
      hit_did_bp = excluded.hit_did_bp,
      hit_bp_minutes = excluded.hit_bp_minutes,
      hit_feel_1_10 = excluded.hit_feel_1_10,
      hit_feel_notes = excluded.hit_feel_notes,
      hit_pitch_type = excluded.hit_pitch_type,
      hit_environment_competitive = excluded.hit_environment_competitive,
      hit_avg_exit_velo = excluded.hit_avg_exit_velo,
      notes = excluded.notes,
      got_video = excluded.got_video,
      ate_breakfast = excluded.ate_breakfast,
      hit_daily_goals = excluded.hit_daily_goals,
      stuck_to_process = excluded.stuck_to_process,
      fell_short = excluded.fell_short,
      excelled = excluded.excelled,
      sa_completed_at = coalesce(public.sd_daily_logs.sa_completed_at, excluded.sa_completed_at),
      updated_at = now();

    return null;
  elsif tg_op = 'DELETE' then
    pid := public.legacy_user_id_to_auth_uuid(old.user_id);
    delete from public.sd_daily_logs d
    where d.player_id = pid and d.log_date::text = old.log_date;
    return null;
  end if;
  return null;
end;
$$;

drop trigger if exists daily_logs_iou on public.daily_logs;
create trigger daily_logs_iou
instead of insert or update or delete on public.daily_logs
for each row execute function public.trg_daily_logs_iou();

-- ------------------------------------------------------------
-- bp_sessions (view) -> sd_bp_sessions (table)
-- ------------------------------------------------------------
create or replace function public.trg_bp_sessions_iou()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  pid uuid;
  sid uuid;
  target uuid;
begin
  if tg_op = 'INSERT' then
    pid := public.legacy_user_id_to_auth_uuid(new.user_id);

    insert into public.sd_bp_sessions (player_id, session_date, source, reps_type)
    values (pid, new.log_date::date, coalesce(nullif(new.source, ''), 'rapsodo'), 'practice')
    on conflict (player_id, session_date, source, reps_type) do update set updated_at = now()
    returning id into sid;

    -- Allow Shiny's `RETURNING id` to work against the view.
    new.id := public.uuid_to_bigint(sid);
    return new;
  elsif tg_op = 'UPDATE' then
    pid := public.legacy_user_id_to_auth_uuid(old.user_id);
    select s.id into target
    from public.sd_bp_sessions s
    where s.player_id = pid
      and public.uuid_to_bigint(s.id) = old.id
    limit 1;
    if target is null then
      -- fallback: any session for that day+player
      select s.id into target
      from public.sd_bp_sessions s
      where s.player_id = pid
        and s.session_date::text = old.log_date
      order by s.created_at desc
      limit 1;
    end if;
    if target is null then
      raise exception 'bp_sessions update could not locate session for legacy user %', old.user_id;
    end if;

    update public.sd_bp_sessions set
      session_date = new.log_date::date,
      source = coalesce(nullif(new.source, ''), source),
      updated_at = now()
    where id = target;
    new.id := public.uuid_to_bigint(target);
    return new;
  elsif tg_op = 'DELETE' then
    pid := public.legacy_user_id_to_auth_uuid(old.user_id);
    delete from public.sd_bp_sessions s
    where s.player_id = pid
      and public.uuid_to_bigint(s.id) = old.id;
    return null;
  end if;
  return null;
end;
$$;

drop trigger if exists bp_sessions_iou on public.bp_sessions;
create trigger bp_sessions_iou
instead of insert or update or delete on public.bp_sessions
for each row execute function public.trg_bp_sessions_iou();

-- ------------------------------------------------------------
-- bp_pitch_events (view) -> sd_bp_events (table)
-- ------------------------------------------------------------
create or replace function public.trg_bp_pitch_events_iou()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  pid uuid;
  sid uuid;
begin
  if tg_op = 'INSERT' then
    -- Resolve session uuid from legacy session_id bigint by matching uuid_to_bigint
    select s.id into sid
    from public.sd_bp_sessions s
    where public.uuid_to_bigint(s.id) = new.session_id
    limit 1;
    if sid is null then
      -- fallback: locate by player+date if session id doesn't match
      pid := public.legacy_user_id_to_auth_uuid(new.user_id);
      select s.id into sid
      from public.sd_bp_sessions s
      where s.player_id = pid and s.session_date::text = new.log_date
      order by s.created_at desc
      limit 1;
    end if;
    if sid is null then
      raise exception 'bp_pitch_events insert could not resolve session_id=%', new.session_id;
    end if;

    insert into public.sd_bp_events (
      session_id,
      pitch_num,
      exit_velo,
      distance,
      launch_angle,
      raw
    ) values (
      sid,
      new.pitch_num,
      new.exit_velo,
      new.distance,
      new.launch_angle,
      case when nullif(coalesce(new.raw_json, ''), '') is null then null else (new.raw_json::jsonb) end
    );
    return null;
  elsif tg_op = 'UPDATE' then
    -- Shiny generally does not update pitch events; no-op.
    return null;
  elsif tg_op = 'DELETE' then
    -- Allow deletes by log_date+user or by id
    if old.id is not null then
      delete from public.sd_bp_events e where public.uuid_to_bigint(e.id) = old.id;
    end if;
    return null;
  end if;
  return null;
end;
$$;

drop trigger if exists bp_pitch_events_iou on public.bp_pitch_events;
create trigger bp_pitch_events_iou
instead of insert or update or delete on public.bp_pitch_events
for each row execute function public.trg_bp_pitch_events_iou();
