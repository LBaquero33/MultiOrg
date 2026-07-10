-- Phase 3 (Bridge both): compat views so the Shiny app can read iOS `sd_*` tables
-- without changing Shiny query code, *when* Shiny runs against this Postgres DB.
--
-- Important:
-- - Shiny uses legacy integer user ids; iOS uses Supabase Auth UUIDs.
-- - We bridge through `public.legacy_auth_links` (legacy_user_id <-> auth_user_id).
-- - Only legacy-migrated users (have legacy_user_id) will appear in these views.

create or replace function public.uuid_to_bigint(_uuid uuid)
returns bigint
language sql
immutable
as $$
  -- Deterministic 60-bit bigint derived from md5(uuid).
  select ('x' || substr(md5(_uuid::text), 1, 15))::bit(60)::bigint;
$$;

revoke all on function public.uuid_to_bigint(uuid) from public;
grant execute on function public.uuid_to_bigint(uuid) to anon, authenticated;

-- dev_entries (Shiny) -> sd_testing_entries (iOS)
drop view if exists public.dev_entries;
create view public.dev_entries as
select
  public.uuid_to_bigint(e.id)                         as id,
  l.legacy_user_id                                    as user_id,
  e.entry_date::text                                  as entry_date,
  e.height_in::double precision                       as height_in,
  e.weight_lb::double precision                       as weight_lb,
  e.squat_1rm::double precision                       as squat_1rm,
  e.bench_1rm::double precision                       as bench_1rm,
  e.deadlift_1rm::double precision                    as deadlift_1rm,
  e.max_exit_velo::double precision                   as max_exit_velo,
  e.avg_exit_velo::double precision                   as avg_exit_velo,
  e.hip_er_diff::double precision                     as hip_er_diff,
  e.hip_ir_diff::double precision                     as hip_ir_diff,
  e.shoulder_ir_diff::double precision                as shoulder_ir_diff,
  e.shoulder_er_diff::double precision                as shoulder_er_diff,
  e.notes                                              as notes,
  null::bigint                                         as created_by_user_id,
  null::bigint                                         as updated_by_user_id,
  coalesce(e.created_at, now())::text                  as created_at,
  coalesce(e.updated_at, now())::text                  as updated_at
from public.sd_testing_entries e
join public.legacy_auth_links l on l.auth_user_id = e.player_id
where l.legacy_user_id is not null;

-- bp_sessions (Shiny) -> sd_bp_sessions (iOS)
drop view if exists public.bp_sessions;
create view public.bp_sessions as
select
  public.uuid_to_bigint(s.id)                          as id,
  l.legacy_user_id                                     as user_id,
  s.session_date::text                                 as log_date,
  s.source                                             as source,
  null::text                                           as original_filename,
  null::text                                           as file_sha256,
  (
    select count(1)
    from public.sd_bp_events e
    where e.session_id = s.id
  )::int                                               as row_count,
  null::bigint                                         as created_by_user_id,
  coalesce(s.created_at, now())::text                   as created_at
from public.sd_bp_sessions s
join public.legacy_auth_links l on l.auth_user_id = s.player_id
where l.legacy_user_id is not null;

-- bp_pitch_events (Shiny) -> sd_bp_events (iOS)
drop view if exists public.bp_pitch_events;
create view public.bp_pitch_events as
select
  public.uuid_to_bigint(e.id)                          as id,
  public.uuid_to_bigint(e.session_id)                  as session_id,
  l.legacy_user_id                                     as user_id,
  s.session_date::text                                 as log_date,
  e.pitch_num                                          as pitch_num,
  e.exit_velo::double precision                        as exit_velo,
  e.distance::double precision                         as distance,
  e.launch_angle::double precision                     as launch_angle,
  e.raw::text                                          as raw_json,
  coalesce(e.created_at, now())::text                  as created_at
from public.sd_bp_events e
join public.sd_bp_sessions s on s.id = e.session_id
join public.legacy_auth_links l on l.auth_user_id = s.player_id
where l.legacy_user_id is not null;

-- daily_logs (Shiny) -> sd_daily_logs (iOS)
-- Shiny expects many columns; we map what exists and leave the rest as NULL.
drop view if exists public.daily_logs;
create view public.daily_logs as
select
  l.legacy_user_id                                     as user_id,
  d.log_date::text                                     as log_date,
  -- Bridge columns get added in a later migration. Keep this compat view robust by
  -- filling Shiny-required fields with NULL until those columns exist.
  null::int                                            as sc_followed_program,
  null::text                                           as sc_lifts,
  null::double precision                               as sc_session_rpe,
  null::int                                            as hit_did_bp,
  null::double precision                               as hit_bp_minutes,
  null::double precision                               as hit_feel_1_10,
  null::text                                           as hit_feel_notes,
  null::text                                           as hit_pitch_type,
  null::int                                            as hit_environment_competitive,
  null::double precision                               as hit_avg_exit_velo,
  d.comments                                           as notes,
  null::bigint                                         as created_by_user_id,
  null::bigint                                         as updated_by_user_id,
  coalesce(d.created_at, now())::text                  as created_at,
  coalesce(d.updated_at, now())::text                  as updated_at,
  case when d.got_video then 1 else 0 end              as sa_got_video,
  case when d.ate_breakfast then 1 else 0 end          as sa_ate_breakfast,
  case when d.hit_daily_goals then 1 else 0 end        as sa_hit_daily_goals,
  case when d.stuck_to_process then 1 else 0 end       as sa_stuck_to_process,
  d.fell_short                                         as sa_fall_short,
  d.excelled                                           as sa_excel,
  coalesce(d.updated_at, now())::text                  as sa_completed_at
from public.sd_daily_logs d
join public.legacy_auth_links l on l.auth_user_id = d.player_id
where l.legacy_user_id is not null;
