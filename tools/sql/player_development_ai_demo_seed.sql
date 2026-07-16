-- Home Plate Phase 11A controlled live-validation seed.
-- SYNTHETIC DATA ONLY. NOT VERIFIED RECRUITING DATA.
-- Run manually in the Supabase SQL Editor. This is not a migration.

do $$
declare
  -- Replace only these two placeholders.
  v_org_id uuid := '<ORG_ID>'::uuid;
  v_player_id uuid := '<PLAYER_ID>'::uuid;

  v_confirmation constant text := 'HOME_PLATE_PHASE_11A_DEMO';
  v_required_confirmation constant text := 'HOME_PLATE_PHASE_11A_DEMO';
  v_source constant text := 'home_plate_demo_seed';
  v_version constant text := 'phase_11a.v1';
  v_verification constant text := 'synthetic_unverified';
  v_note constant text :=
    'home_plate_demo_seed | phase_11a.v1 | synthetic_unverified | NOT VERIFIED RECRUITING DATA';
  v_anchor_date date := current_date;
  v_staff_id uuid;
  v_exit_velocity_metric_id uuid;
  v_sprint_metric_id uuid;
  v_squat_metric_id uuid;

  v_template_id constant uuid := '11a00000-0000-4000-8000-000000000001'::uuid;
  v_assignment_id constant uuid := '11a00000-0000-4000-8000-000000000002'::uuid;
  v_testing_ids constant uuid[] := array[
    '11a00000-0000-4100-8100-000000000001'::uuid,
    '11a00000-0000-4100-8100-000000000002'::uuid,
    '11a00000-0000-4100-8100-000000000003'::uuid,
    '11a00000-0000-4100-8100-000000000004'::uuid
  ];
  v_daily_ids constant uuid[] := array[
    '11a00000-0000-4200-8200-000000000001'::uuid,
    '11a00000-0000-4200-8200-000000000002'::uuid,
    '11a00000-0000-4200-8200-000000000003'::uuid,
    '11a00000-0000-4200-8200-000000000004'::uuid,
    '11a00000-0000-4200-8200-000000000005'::uuid,
    '11a00000-0000-4200-8200-000000000006'::uuid,
    '11a00000-0000-4200-8200-000000000007'::uuid,
    '11a00000-0000-4200-8200-000000000008'::uuid
  ];
  v_bp_session_ids constant uuid[] := array[
    '11a00000-0000-4300-8300-000000000001'::uuid,
    '11a00000-0000-4300-8300-000000000002'::uuid,
    '11a00000-0000-4300-8300-000000000003'::uuid
  ];
  v_bp_event_ids constant uuid[] := array[
    '11a00000-0000-4310-8310-000000000001'::uuid,
    '11a00000-0000-4310-8310-000000000002'::uuid,
    '11a00000-0000-4310-8310-000000000003'::uuid,
    '11a00000-0000-4310-8310-000000000004'::uuid,
    '11a00000-0000-4310-8310-000000000005'::uuid,
    '11a00000-0000-4310-8310-000000000006'::uuid,
    '11a00000-0000-4310-8310-000000000007'::uuid,
    '11a00000-0000-4310-8310-000000000008'::uuid,
    '11a00000-0000-4310-8310-000000000009'::uuid,
    '11a00000-0000-4310-8310-000000000010'::uuid,
    '11a00000-0000-4310-8310-000000000011'::uuid,
    '11a00000-0000-4310-8310-000000000012'::uuid,
    '11a00000-0000-4310-8310-000000000013'::uuid,
    '11a00000-0000-4310-8310-000000000014'::uuid,
    '11a00000-0000-4310-8310-000000000015'::uuid
  ];
  v_observation_ids constant uuid[] := array[
    '11a00000-0000-4400-8400-000000000001'::uuid,
    '11a00000-0000-4400-8400-000000000002'::uuid,
    '11a00000-0000-4400-8400-000000000003'::uuid,
    '11a00000-0000-4400-8400-000000000004'::uuid,
    '11a00000-0000-4400-8400-000000000005'::uuid,
    '11a00000-0000-4400-8400-000000000006'::uuid,
    '11a00000-0000-4400-8400-000000000007'::uuid,
    '11a00000-0000-4400-8400-000000000008'::uuid,
    '11a00000-0000-4400-8400-000000000009'::uuid,
    '11a00000-0000-4400-8400-000000000010'::uuid,
    '11a00000-0000-4400-8400-000000000011'::uuid,
    '11a00000-0000-4400-8400-000000000012'::uuid
  ];
begin
  -- All validation precedes the first write. Any later failure rolls back the DO block.
  if v_confirmation <> v_required_confirmation then
    raise exception 'Confirmation guard failed.';
  end if;
  if not exists (
    select 1 from public.sd_orgs o
    where o.id = v_org_id and o.status = 'active'
  ) then
    raise exception 'The selected organization does not exist or is not active.';
  end if;
  if not exists (select 1 from public.profiles p where p.id = v_player_id) then
    raise exception 'The selected player does not exist in public.profiles.';
  end if;
  if not exists (
    select 1 from public.sd_org_memberships m
    where m.org_id = v_org_id and m.user_id = v_player_id
      and m.role = 'player' and m.status = 'active'
  ) then
    raise exception 'The selected user is not an active player in this exact organization.';
  end if;

  -- Program tables require a coach_id. Derive one inside the selected org so
  -- the user still replaces only ORG_ID and PLAYER_ID.
  select m.user_id into v_staff_id
  from public.sd_org_memberships m
  where m.org_id = v_org_id and m.status = 'active'
    and m.role in ('owner', 'admin', 'coach')
  order by case m.role when 'owner' then 1 when 'admin' then 2 else 3 end,
           m.created_at, m.user_id
  limit 1;
  if v_staff_id is null then
    raise exception 'The organization needs an active owner, admin, or coach for the demo assignment.';
  end if;

  select d.id into v_exit_velocity_metric_id
  from public.sd_development_metric_definitions d
  where d.canonical_key = 'hitting.max_exit_velocity'
    and d.canonical_unit = 'mph'
    and d.preferred_direction = 'higher_is_better'
    and d.status = 'active';
  select d.id into v_sprint_metric_id
  from public.sd_development_metric_definitions d
  where d.canonical_key = 'physical.sprint_time'
    and d.canonical_unit = 's'
    and d.preferred_direction = 'lower_is_better'
    and d.status = 'active';
  select d.id into v_squat_metric_id
  from public.sd_development_metric_definitions d
  where d.canonical_key = 'strength.squat_1rm'
    and d.canonical_unit = 'lb'
    and d.preferred_direction = 'higher_is_better'
    and d.status = 'active';
  if v_exit_velocity_metric_id is null or v_sprint_metric_id is null
     or v_squat_metric_id is null then
    raise exception 'Required active canonical metrics or units/directions are missing.';
  end if;
  if not exists (
    select 1 from public.sd_development_metric_definitions d
    where d.canonical_key = 'consistency.process_adherence_rate'
      and d.canonical_unit = 'percent'
      and d.preferred_direction = 'higher_is_better'
      and d.status = 'active'
  ) then
    raise exception 'Required consistency metric is missing or incompatible.';
  end if;

  -- Natural-key conflicts fail closed instead of overwriting real player data.
  if exists (
    select 1 from public.sd_testing_entries t
    where t.org_id = v_org_id and t.player_id = v_player_id
      and t.entry_date = any(array[
        v_anchor_date - 75, v_anchor_date - 50,
        v_anchor_date - 25, v_anchor_date - 5
      ]) and not (t.id = any(v_testing_ids))
  ) then raise exception 'A non-demo testing entry already occupies a demo date.'; end if;
  if exists (
    select 1 from public.sd_daily_logs l
    where l.org_id = v_org_id and l.player_id = v_player_id
      and l.log_date = any(array[
        v_anchor_date - 72, v_anchor_date - 62, v_anchor_date - 52, v_anchor_date - 42,
        v_anchor_date - 28, v_anchor_date - 18, v_anchor_date - 10, v_anchor_date - 3
      ]) and not (l.id = any(v_daily_ids))
  ) then raise exception 'A non-demo daily log already occupies a demo date.'; end if;
  if exists (
    select 1 from public.sd_bp_sessions s
    where s.org_id = v_org_id and s.player_id = v_player_id
      and s.session_date = any(array[v_anchor_date - 70, v_anchor_date - 45, v_anchor_date - 15])
      and s.source = 'trackman' and s.reps_type = 'practice'
      and not (s.id = any(v_bp_session_ids))
  ) then raise exception 'A non-demo BP session already occupies a demo natural key.'; end if;

  -- Reserved deterministic IDs may be reused only by this exact demo scope/provenance.
  if exists (
    select 1 from public.sd_program_templates t where t.id = v_template_id
      and (t.org_id is distinct from v_org_id or t.name <> 'AI Demo Validation Program')
  ) or exists (
    select 1 from public.sd_program_assignments a where a.id = v_assignment_id
      and (a.org_id is distinct from v_org_id or a.player_id <> v_player_id
        or coalesce(a.notes, '') not like v_source || '%')
  ) or exists (
    select 1 from public.sd_testing_entries t where t.id = any(v_testing_ids)
      and (t.org_id is distinct from v_org_id or t.player_id <> v_player_id
        or coalesce(t.notes, '') not like v_source || '%')
  ) or exists (
    select 1 from public.sd_daily_logs l where l.id = any(v_daily_ids)
      and (l.org_id is distinct from v_org_id or l.player_id <> v_player_id
        or coalesce(l.notes, '') not like v_source || '%')
  ) or exists (
    select 1 from public.sd_bp_sessions s where s.id = any(v_bp_session_ids)
      and (s.org_id is distinct from v_org_id or s.player_id <> v_player_id)
  ) or exists (
    select 1 from public.sd_bp_events e where e.id = any(v_bp_event_ids)
      and (coalesce(e.raw->>'demo_seed', 'false') <> 'true'
        or e.raw->>'demo_version' <> v_version)
  ) or exists (
    select 1 from public.sd_player_metric_observations o
    where o.id = any(v_observation_ids)
      and (o.org_id <> v_org_id or o.player_id <> v_player_id
        or o.source_system <> v_source
        or coalesce((o.context_metadata->>'demo_seed')::boolean, false) is not true)
  ) then
    raise exception 'A reserved demo UUID is already owned by unrelated data.';
  end if;

  insert into public.sd_program_templates
    (id, coach_id, name, weeks, lift_weekdays, program_kind, org_id)
  values
    (v_template_id, v_staff_id, 'AI Demo Validation Program', 4, array[1,3,5], 'strength', v_org_id)
  on conflict (id) do update set
    coach_id = excluded.coach_id, name = excluded.name, weeks = excluded.weeks,
    lift_weekdays = excluded.lift_weekdays, program_kind = excluded.program_kind,
    org_id = excluded.org_id, updated_at = now();

  insert into public.sd_program_assignments
    (id, player_id, coach_id, template_id, start_date, ended_at, notes, org_id)
  values
    (v_assignment_id, v_player_id, v_staff_id, v_template_id,
     v_anchor_date - 30, null, v_note, v_org_id)
  on conflict (id) do update set
    player_id = excluded.player_id, coach_id = excluded.coach_id,
    template_id = excluded.template_id, start_date = excluded.start_date,
    ended_at = excluded.ended_at, notes = excluded.notes, org_id = excluded.org_id,
    updated_at = now();

  insert into public.sd_testing_entries
    (id, org_id, player_id, entry_date, height_in, weight_lb, squat_1rm,
     bench_1rm, deadlift_1rm, max_exit_velo, avg_exit_velo,
     hip_er_diff, hip_ir_diff, shoulder_ir_diff, shoulder_er_diff, notes)
  values
    (v_testing_ids[1], v_org_id, v_player_id, v_anchor_date - 75, 70, 160, 180, 145, 235, 76, 67, 6, 5, 7, 6, v_note),
    (v_testing_ids[2], v_org_id, v_player_id, v_anchor_date - 50, 70, 161, 195, 150, 250, 79, 71, 6, 5, 7, 6, v_note),
    (v_testing_ids[3], v_org_id, v_player_id, v_anchor_date - 25, 70, 162, 210, 142, 270, 83, 76, 5, 4, 6, 5, v_note),
    (v_testing_ids[4], v_org_id, v_player_id, v_anchor_date - 5,  70, 163, 230, 132, 290, 87, 82, 5, 4, 6, 5, v_note)
  on conflict (id) do update set
    org_id = excluded.org_id, player_id = excluded.player_id,
    entry_date = excluded.entry_date, height_in = excluded.height_in,
    weight_lb = excluded.weight_lb, squat_1rm = excluded.squat_1rm,
    bench_1rm = excluded.bench_1rm, deadlift_1rm = excluded.deadlift_1rm,
    max_exit_velo = excluded.max_exit_velo, avg_exit_velo = excluded.avg_exit_velo,
    hip_er_diff = excluded.hip_er_diff, hip_ir_diff = excluded.hip_ir_diff,
    shoulder_ir_diff = excluded.shoulder_ir_diff,
    shoulder_er_diff = excluded.shoulder_er_diff,
    notes = excluded.notes, updated_at = now();

  insert into public.sd_daily_logs
    (id, org_id, player_id, log_date, comments, feel, got_video,
     ate_breakfast, hit_daily_goals, stuck_to_process, fell_short, excelled, notes)
  values
    (v_daily_ids[1], v_org_id, v_player_id, v_anchor_date - 72, null, 6, true,  true,  true,  true,  null, null, v_note),
    (v_daily_ids[2], v_org_id, v_player_id, v_anchor_date - 62, null, 7, false, true,  true,  true,  null, null, v_note),
    (v_daily_ids[3], v_org_id, v_player_id, v_anchor_date - 52, null, 5, true,  true,  false, false, null, null, v_note),
    (v_daily_ids[4], v_org_id, v_player_id, v_anchor_date - 42, null, 7, true,  true,  true,  true,  null, null, v_note),
    (v_daily_ids[5], v_org_id, v_player_id, v_anchor_date - 28, null, 8, true,  true,  true,  true,  null, null, v_note),
    (v_daily_ids[6], v_org_id, v_player_id, v_anchor_date - 18, null, 6, false, true,  false, false, null, null, v_note),
    (v_daily_ids[7], v_org_id, v_player_id, v_anchor_date - 10, null, 8, true,  true,  true,  true,  null, null, v_note),
    (v_daily_ids[8], v_org_id, v_player_id, v_anchor_date - 3,  null, 9, true,  true,  true,  true,  null, null, v_note)
  on conflict (id) do update set
    org_id = excluded.org_id, player_id = excluded.player_id,
    log_date = excluded.log_date, comments = excluded.comments, feel = excluded.feel,
    got_video = excluded.got_video, ate_breakfast = excluded.ate_breakfast,
    hit_daily_goals = excluded.hit_daily_goals,
    stuck_to_process = excluded.stuck_to_process,
    fell_short = excluded.fell_short, excelled = excluded.excelled,
    notes = excluded.notes, updated_at = now();

  insert into public.sd_bp_sessions
    (id, org_id, player_id, session_date, source, reps_type)
  values
    (v_bp_session_ids[1], v_org_id, v_player_id, v_anchor_date - 70, 'trackman', 'practice'),
    (v_bp_session_ids[2], v_org_id, v_player_id, v_anchor_date - 45, 'trackman', 'practice'),
    (v_bp_session_ids[3], v_org_id, v_player_id, v_anchor_date - 15, 'trackman', 'practice')
  on conflict (id) do update set
    org_id = excluded.org_id, player_id = excluded.player_id,
    session_date = excluded.session_date, source = excluded.source,
    reps_type = excluded.reps_type, updated_at = now();

  insert into public.sd_bp_events
    (id, session_id, pitch_num, exit_velo, distance, launch_angle, raw)
  values
    (v_bp_event_ids[1],  v_bp_session_ids[1], 1, 65, 240, 10, jsonb_build_object('demo_seed', true, 'demo_version', v_version, 'verification_status', v_verification)),
    (v_bp_event_ids[2],  v_bp_session_ids[1], 2, 67, 255, 13, jsonb_build_object('demo_seed', true, 'demo_version', v_version, 'verification_status', v_verification)),
    (v_bp_event_ids[3],  v_bp_session_ids[1], 3, 68, 262, 15, jsonb_build_object('demo_seed', true, 'demo_version', v_version, 'verification_status', v_verification)),
    (v_bp_event_ids[4],  v_bp_session_ids[1], 4, 70, 275, 18, jsonb_build_object('demo_seed', true, 'demo_version', v_version, 'verification_status', v_verification)),
    (v_bp_event_ids[5],  v_bp_session_ids[1], 5, 72, 286, 21, jsonb_build_object('demo_seed', true, 'demo_version', v_version, 'verification_status', v_verification)),
    (v_bp_event_ids[6],  v_bp_session_ids[2], 1, 70, 270, 11, jsonb_build_object('demo_seed', true, 'demo_version', v_version, 'verification_status', v_verification)),
    (v_bp_event_ids[7],  v_bp_session_ids[2], 2, 72, 282, 14, jsonb_build_object('demo_seed', true, 'demo_version', v_version, 'verification_status', v_verification)),
    (v_bp_event_ids[8],  v_bp_session_ids[2], 3, 74, 295, 16, jsonb_build_object('demo_seed', true, 'demo_version', v_version, 'verification_status', v_verification)),
    (v_bp_event_ids[9],  v_bp_session_ids[2], 4, 76, 308, 19, jsonb_build_object('demo_seed', true, 'demo_version', v_version, 'verification_status', v_verification)),
    (v_bp_event_ids[10], v_bp_session_ids[2], 5, 78, 320, 22, jsonb_build_object('demo_seed', true, 'demo_version', v_version, 'verification_status', v_verification)),
    (v_bp_event_ids[11], v_bp_session_ids[3], 1, 76, 310, 12, jsonb_build_object('demo_seed', true, 'demo_version', v_version, 'verification_status', v_verification)),
    (v_bp_event_ids[12], v_bp_session_ids[3], 2, 78, 325, 14, jsonb_build_object('demo_seed', true, 'demo_version', v_version, 'verification_status', v_verification)),
    (v_bp_event_ids[13], v_bp_session_ids[3], 3, 80, 338, 17, jsonb_build_object('demo_seed', true, 'demo_version', v_version, 'verification_status', v_verification)),
    (v_bp_event_ids[14], v_bp_session_ids[3], 4, 82, 352, 20, jsonb_build_object('demo_seed', true, 'demo_version', v_version, 'verification_status', v_verification)),
    (v_bp_event_ids[15], v_bp_session_ids[3], 5, 85, 371, 24, jsonb_build_object('demo_seed', true, 'demo_version', v_version, 'verification_status', v_verification))
  on conflict (id) do update set
    session_id = excluded.session_id, pitch_num = excluded.pitch_num,
    exit_velo = excluded.exit_velo, distance = excluded.distance,
    launch_angle = excluded.launch_angle, raw = excluded.raw;

  -- Four normalized samples per metric exceed each selected definition's
  -- minimum sample size and preserve original/canonical unit provenance.
  insert into public.sd_player_metric_observations
    (id, org_id, player_id, metric_definition_id, observed_value,
     normalized_value, unit, observed_at, source_system, source_entity_type,
     source_record_id, context_metadata, quality_status, sample_size, notes)
  values
    (v_observation_ids[1], v_org_id, v_player_id, v_exit_velocity_metric_id, '76.5', 76.5, 'mph', (v_anchor_date - 75)::timestamptz + interval '15 hours', v_source, 'home_plate_demo_seed.max_exit_velocity', '11a00000-0000-4410-8410-000000000001', jsonb_build_object('demo_seed', true, 'demo_version', v_version, 'verification_status', v_verification, 'original_unit', 'mph', 'canonical_unit', 'mph'), 'sufficient', 1, v_note),
    (v_observation_ids[2], v_org_id, v_player_id, v_exit_velocity_metric_id, '80.0', 80.0, 'mph', (v_anchor_date - 50)::timestamptz + interval '15 hours', v_source, 'home_plate_demo_seed.max_exit_velocity', '11a00000-0000-4410-8410-000000000002', jsonb_build_object('demo_seed', true, 'demo_version', v_version, 'verification_status', v_verification, 'original_unit', 'mph', 'canonical_unit', 'mph'), 'sufficient', 1, v_note),
    (v_observation_ids[3], v_org_id, v_player_id, v_exit_velocity_metric_id, '85.0', 85.0, 'mph', (v_anchor_date - 4)::timestamptz + interval '15 hours', v_source, 'home_plate_demo_seed.max_exit_velocity', '11a00000-0000-4410-8410-000000000003', jsonb_build_object('demo_seed', true, 'demo_version', v_version, 'verification_status', v_verification, 'original_unit', 'mph', 'canonical_unit', 'mph'), 'sufficient', 1, v_note),
    (v_observation_ids[4], v_org_id, v_player_id, v_exit_velocity_metric_id, '89.0', 89.0, 'mph', (v_anchor_date - 2)::timestamptz + interval '15 hours', v_source, 'home_plate_demo_seed.max_exit_velocity', '11a00000-0000-4410-8410-000000000004', jsonb_build_object('demo_seed', true, 'demo_version', v_version, 'verification_status', v_verification, 'original_unit', 'mph', 'canonical_unit', 'mph'), 'sufficient', 1, v_note),
    (v_observation_ids[5], v_org_id, v_player_id, v_sprint_metric_id, '7.40', 7.40, 's', (v_anchor_date - 75)::timestamptz + interval '16 hours', v_source, 'home_plate_demo_seed.sprint_time', '11a00000-0000-4410-8410-000000000005', jsonb_build_object('demo_seed', true, 'demo_version', v_version, 'verification_status', v_verification, 'original_unit', 's', 'canonical_unit', 's', 'distance_yards', 60), 'sufficient', 1, v_note),
    (v_observation_ids[6], v_org_id, v_player_id, v_sprint_metric_id, '7.25', 7.25, 's', (v_anchor_date - 50)::timestamptz + interval '16 hours', v_source, 'home_plate_demo_seed.sprint_time', '11a00000-0000-4410-8410-000000000006', jsonb_build_object('demo_seed', true, 'demo_version', v_version, 'verification_status', v_verification, 'original_unit', 's', 'canonical_unit', 's', 'distance_yards', 60), 'sufficient', 1, v_note),
    (v_observation_ids[7], v_org_id, v_player_id, v_sprint_metric_id, '7.10', 7.10, 's', (v_anchor_date - 4)::timestamptz + interval '16 hours', v_source, 'home_plate_demo_seed.sprint_time', '11a00000-0000-4410-8410-000000000007', jsonb_build_object('demo_seed', true, 'demo_version', v_version, 'verification_status', v_verification, 'original_unit', 's', 'canonical_unit', 's', 'distance_yards', 60), 'sufficient', 1, v_note),
    (v_observation_ids[8], v_org_id, v_player_id, v_sprint_metric_id, '6.85', 6.85, 's', (v_anchor_date - 2)::timestamptz + interval '16 hours', v_source, 'home_plate_demo_seed.sprint_time', '11a00000-0000-4410-8410-000000000008', jsonb_build_object('demo_seed', true, 'demo_version', v_version, 'verification_status', v_verification, 'original_unit', 's', 'canonical_unit', 's', 'distance_yards', 60), 'sufficient', 1, v_note),
    (v_observation_ids[9], v_org_id, v_player_id, v_squat_metric_id, '180', 180, 'lb', (v_anchor_date - 75)::timestamptz + interval '17 hours', v_source, 'home_plate_demo_seed.squat_1rm', '11a00000-0000-4410-8410-000000000009', jsonb_build_object('demo_seed', true, 'demo_version', v_version, 'verification_status', v_verification, 'original_unit', 'lb', 'canonical_unit', 'lb'), 'sufficient', 1, v_note),
    (v_observation_ids[10], v_org_id, v_player_id, v_squat_metric_id, '195', 195, 'lb', (v_anchor_date - 50)::timestamptz + interval '17 hours', v_source, 'home_plate_demo_seed.squat_1rm', '11a00000-0000-4410-8410-000000000010', jsonb_build_object('demo_seed', true, 'demo_version', v_version, 'verification_status', v_verification, 'original_unit', 'lb', 'canonical_unit', 'lb'), 'sufficient', 1, v_note),
    (v_observation_ids[11], v_org_id, v_player_id, v_squat_metric_id, '220', 220, 'lb', (v_anchor_date - 4)::timestamptz + interval '17 hours', v_source, 'home_plate_demo_seed.squat_1rm', '11a00000-0000-4410-8410-000000000011', jsonb_build_object('demo_seed', true, 'demo_version', v_version, 'verification_status', v_verification, 'original_unit', 'lb', 'canonical_unit', 'lb'), 'sufficient', 1, v_note),
    (v_observation_ids[12], v_org_id, v_player_id, v_squat_metric_id, '240', 240, 'lb', (v_anchor_date - 2)::timestamptz + interval '17 hours', v_source, 'home_plate_demo_seed.squat_1rm', '11a00000-0000-4410-8410-000000000012', jsonb_build_object('demo_seed', true, 'demo_version', v_version, 'verification_status', v_verification, 'original_unit', 'lb', 'canonical_unit', 'lb'), 'sufficient', 1, v_note)
  on conflict (id) do update set
    org_id = excluded.org_id, player_id = excluded.player_id,
    metric_definition_id = excluded.metric_definition_id,
    observed_value = excluded.observed_value,
    normalized_value = excluded.normalized_value, unit = excluded.unit,
    observed_at = excluded.observed_at, source_system = excluded.source_system,
    source_entity_type = excluded.source_entity_type,
    source_record_id = excluded.source_record_id,
    context_metadata = excluded.context_metadata,
    quality_status = excluded.quality_status, sample_size = excluded.sample_size,
    notes = excluded.notes, updated_at = now();

  raise notice 'Phase 11A synthetic seed complete: org %, player %, assigning staff %, anchor %.',
    v_org_id, v_player_id, v_staff_id, v_anchor_date;
  raise notice 'Rows: 1 template, 1 assignment, 4 testing, 8 daily logs, 3 BP sessions, 15 BP events, 12 normalized observations.';
  raise notice 'SYNTHETIC / UNVERIFIED: never use these values as recruiting evidence.';
end
$$;
