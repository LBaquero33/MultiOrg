-- Home Plate Phase 11A controlled live-validation cleanup.
-- Removes only exact home_plate_demo_seed source rows.
-- Phase 11A reports, evidence, review history, alerts, and alert history are preserved.
-- Run manually in the Supabase SQL Editor. This is not a migration.

do $$
declare
  -- Replace only these two placeholders with the same values used for the seed.
  v_org_id uuid := '<ORG_ID>'::uuid;
  v_player_id uuid := '<PLAYER_ID>'::uuid;

  v_confirmation constant text := 'HOME_PLATE_PHASE_11A_DEMO';
  v_required_confirmation constant text := 'HOME_PLATE_PHASE_11A_DEMO';
  v_source constant text := 'home_plate_demo_seed';
  v_version constant text := 'phase_11a.v1';
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
  v_count integer;
begin
  if v_confirmation <> v_required_confirmation then
    raise exception 'Confirmation guard failed.';
  end if;
  if not exists (select 1 from public.sd_orgs o where o.id = v_org_id) then
    raise exception 'The selected organization does not exist.';
  end if;
  if not exists (select 1 from public.profiles p where p.id = v_player_id) then
    raise exception 'The selected player does not exist in public.profiles.';
  end if;
  if not exists (
    select 1 from public.sd_org_memberships m
    where m.org_id = v_org_id and m.user_id = v_player_id and m.role = 'player'
  ) then
    raise exception 'The selected player is not scoped to this organization.';
  end if;

  delete from public.sd_player_metric_observations o
  where o.id = any(v_observation_ids)
    and o.org_id = v_org_id and o.player_id = v_player_id
    and o.source_system = v_source
    and o.context_metadata @> jsonb_build_object(
      'demo_seed', true,
      'demo_version', v_version,
      'verification_status', 'synthetic_unverified'
    );
  get diagnostics v_count = row_count;
  raise notice 'Deleted % synthetic normalized observations.', v_count;

  delete from public.sd_testing_entries t
  where t.id = any(v_testing_ids)
    and t.org_id = v_org_id and t.player_id = v_player_id
    and coalesce(t.notes, '') like v_source || ' | ' || v_version || '%';
  get diagnostics v_count = row_count;
  raise notice 'Deleted % synthetic testing entries.', v_count;

  delete from public.sd_daily_logs l
  where l.id = any(v_daily_ids)
    and l.org_id = v_org_id and l.player_id = v_player_id
    and coalesce(l.notes, '') like v_source || ' | ' || v_version || '%';
  get diagnostics v_count = row_count;
  raise notice 'Deleted % synthetic daily logs.', v_count;

  -- Events must go first. The session is removed only when no event remains,
  -- so an unexpected non-demo event causes the cleanup to preserve its session.
  delete from public.sd_bp_events e
  using public.sd_bp_sessions s
  where e.id = any(v_bp_event_ids)
    and e.session_id = s.id and s.id = any(v_bp_session_ids)
    and s.org_id = v_org_id and s.player_id = v_player_id
    and e.raw @> jsonb_build_object(
      'demo_seed', true,
      'demo_version', v_version,
      'verification_status', 'synthetic_unverified'
    );
  get diagnostics v_count = row_count;
  raise notice 'Deleted % synthetic BP events.', v_count;

  delete from public.sd_bp_sessions s
  where s.id = any(v_bp_session_ids)
    and s.org_id = v_org_id and s.player_id = v_player_id
    and s.source = 'trackman' and s.reps_type = 'practice'
    and not exists (
      select 1 from public.sd_bp_events e where e.session_id = s.id
    );
  get diagnostics v_count = row_count;
  raise notice 'Deleted % empty synthetic BP sessions.', v_count;

  delete from public.sd_program_assignments a
  where a.id = v_assignment_id
    and a.org_id = v_org_id and a.player_id = v_player_id
    and a.template_id = v_template_id
    and coalesce(a.notes, '') like v_source || ' | ' || v_version || '%';
  get diagnostics v_count = row_count;
  raise notice 'Deleted % synthetic program assignments.', v_count;

  delete from public.sd_program_templates t
  where t.id = v_template_id
    and t.org_id = v_org_id
    and t.name = 'AI Demo Validation Program'
    and not exists (
      select 1 from public.sd_program_assignments a where a.template_id = t.id
    );
  get diagnostics v_count = row_count;
  raise notice 'Deleted % unused synthetic program templates.', v_count;

  raise notice 'Cleanup complete. Development reports/alerts and all audit evidence/events were preserved.';
end
$$;
