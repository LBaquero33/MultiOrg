begin;

create extension if not exists pgtap with schema extensions;

select plan(47);

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
  confirmation_token, recovery_token, email_change_token_new, email_change
)
select
  '00000000-0000-0000-0000-000000000000'::uuid,
  fixture.id,
  'authenticated',
  'authenticated',
  fixture.email,
  crypt('local-test-only', gen_salt('bf')),
  now(),
  '{"provider":"email","providers":["email"]}'::jsonb,
  jsonb_build_object('full_name', fixture.full_name, 'role', fixture.profile_role),
  now(),
  now(),
  '',
  '',
  '',
  ''
from (
  values
    ('10000000-0000-4000-8000-000000000001'::uuid, 'owner@test.local', 'Owner', 'coach'),
    ('10000000-0000-4000-8000-000000000002'::uuid, 'coach@test.local', 'Coach', 'coach'),
    ('10000000-0000-4000-8000-000000000003'::uuid, 'player@test.local', 'Player', 'player'),
    ('10000000-0000-4000-8000-000000000004'::uuid, 'parent@test.local', 'Parent', 'parent'),
    ('10000000-0000-4000-8000-000000000005'::uuid, 'outsider@test.local', 'Outsider', 'player'),
    ('20000000-0000-4000-8000-000000000001'::uuid, 'other-owner@test.local', 'Other Owner', 'coach')
) as fixture(id, email, full_name, profile_role)
on conflict (id) do nothing;

insert into public.sd_orgs (id, slug, name)
values
  ('10000000-0000-4000-9000-000000000001', 'game-test-org', 'Game Test Org'),
  ('20000000-0000-4000-9000-000000000001', 'other-test-org', 'Other Test Org');

insert into public.sd_org_memberships (org_id, user_id, role, status)
values
  ('10000000-0000-4000-9000-000000000001', '10000000-0000-4000-8000-000000000001', 'owner', 'active'),
  ('10000000-0000-4000-9000-000000000001', '10000000-0000-4000-8000-000000000002', 'coach', 'active'),
  ('10000000-0000-4000-9000-000000000001', '10000000-0000-4000-8000-000000000003', 'player', 'active'),
  ('10000000-0000-4000-9000-000000000001', '10000000-0000-4000-8000-000000000004', 'parent', 'active'),
  ('20000000-0000-4000-9000-000000000001', '20000000-0000-4000-8000-000000000001', 'owner', 'active');

select lives_ok(
  $$insert into public.sd_notifications (
    id, org_id, recipient_user_id, category, title, body,
    deduplication_key, created_by, source
  ) values (
    '10000000-0000-4000-9000-000000000099',
    '10000000-0000-4000-9000-000000000001',
    '10000000-0000-4000-8000-000000000003',
    'schedule_change',
    'Existing schedule',
    'This row predates the game migration.',
    'legacy-schedule-change',
    '10000000-0000-4000-8000-000000000001',
    'event_operation'
  )$$,
  'legacy schedule-change notification exists before the constraint upgrade'
);

create temporary table legacy_notification_snapshot as
select to_jsonb(notification) as row_data
from public.sd_notifications notification
where id = '10000000-0000-4000-9000-000000000099';

select lives_ok(
  $$alter table public.sd_notifications
      drop constraint if exists sd_notifications_category_check;
    alter table public.sd_notifications
      add constraint sd_notifications_category_check check (category in (
        'payment_request_created', 'payment_received', 'booking_created',
        'booking_updated', 'program_assigned', 'program_updated',
        'message_received', 'testing_result_added', 'organization_announcement',
        'team_announcement', 'event_announcement', 'schedule_change',
        'event_reminder', 'attendance', 'availability', 'practice_plan',
        'game_plan', 'lineup_assignment', 'registration', 'payment_notice',
        'result_recap', 'event_created', 'event_updated', 'event_canceled',
        'event_postponed', 'event_rescheduled', 'availability_requested',
        'game_starting', 'game_live', 'game_final', 'game_update', 'system'
      )) not valid;
    alter table public.sd_notifications
      validate constraint sd_notifications_category_check$$,
  'canonical game constraint validates with an existing schedule-change row'
);

select is(
  (
    select to_jsonb(notification)
    from public.sd_notifications notification
    where id = '10000000-0000-4000-9000-000000000099'
  ),
  (select row_data from legacy_notification_snapshot),
  'constraint upgrade leaves the existing notification row unchanged'
);

select lives_ok(
  $$insert into public.sd_notifications (
      org_id, recipient_user_id, category, title, body,
      deduplication_key, created_by, source
    )
    select
      '10000000-0000-4000-9000-000000000001',
      '10000000-0000-4000-8000-000000000003',
      category,
      'Category contract',
      'Canonical category remains accepted.',
      'canonical-category-' || category,
      '10000000-0000-4000-8000-000000000001',
      'system'
    from unnest(array[
      'payment_request_created', 'payment_received', 'booking_created',
      'booking_updated', 'program_assigned', 'program_updated',
      'message_received', 'testing_result_added', 'organization_announcement',
      'team_announcement', 'event_announcement', 'schedule_change',
      'event_reminder', 'attendance', 'availability', 'practice_plan',
      'game_plan', 'lineup_assignment', 'registration', 'payment_notice',
      'result_recap', 'event_created', 'event_updated', 'event_canceled',
      'event_postponed', 'event_rescheduled', 'availability_requested',
      'game_starting', 'game_live', 'game_final', 'game_update', 'system'
    ]) category$$,
  'all canonical legacy and game notification categories are accepted'
);

select throws_ok(
  $$insert into public.sd_notifications (
      org_id, recipient_user_id, category, title, body,
      deduplication_key, created_by, source
    ) values (
      '10000000-0000-4000-9000-000000000001',
      '10000000-0000-4000-8000-000000000003',
      'not_a_real_category',
      'Invalid category',
      'This insert must fail.',
      'invalid-category',
      '10000000-0000-4000-8000-000000000001',
      'system'
    )$$,
  '23514',
  null,
  'unknown notification categories remain rejected'
);

delete from public.sd_notifications
where deduplication_key = 'legacy-schedule-change'
   or deduplication_key like 'canonical-category-%';

insert into public.sd_teams (id, org_id, name, created_by)
values (
  '10000000-0000-4000-9000-000000000010',
  '10000000-0000-4000-9000-000000000001',
  'Varsity',
  '10000000-0000-4000-8000-000000000001'
);

insert into public.sd_team_members (org_id, team_id, player_id, assigned_by)
values (
  '10000000-0000-4000-9000-000000000001',
  '10000000-0000-4000-9000-000000000010',
  '10000000-0000-4000-8000-000000000003',
  '10000000-0000-4000-8000-000000000001'
);

insert into public.sd_parent_child_links (
  org_id, parent_id, child_id, relationship, created_by
)
values (
  '10000000-0000-4000-9000-000000000001',
  '10000000-0000-4000-8000-000000000004',
  '10000000-0000-4000-8000-000000000003',
  'parent',
  '10000000-0000-4000-8000-000000000001'
);

create temporary table game_test_context (
  game_id uuid,
  event_id uuid,
  active_token text,
  request_id uuid,
  request_token text,
  decision_id uuid,
  finalization_id uuid,
  correction_id uuid
) on commit drop;

select set_config(
  'request.jwt.claim.sub',
  '10000000-0000-4000-8000-000000000001',
  true
);

insert into game_test_context (game_id, event_id)
select game.id, game.event_id
from public.sd_create_game(
  '10000000-0000-4000-9000-000000000001',
  '10000000-0000-4000-9000-000000000010',
  'Game Test Org vs Visitors',
  'Visitors',
  now() + interval '1 day',
  now() + interval '1 day 3 hours',
  now() + interval '1 day' - interval '45 minutes',
  'America/New_York',
  'home',
  'Test Field',
  null,
  7,
  'team'
) game;

insert into public.sd_event_participants (
  org_id, event_id, participant_type, user_id, role,
  can_view, can_edit, can_score, invited_by
)
select
  '10000000-0000-4000-9000-000000000001',
  event_id,
  'scorekeeper',
  '10000000-0000-4000-8000-000000000002',
  'scorekeeper',
  true,
  true,
  true,
  '10000000-0000-4000-8000-000000000001'
from game_test_context;

select set_config('request.jwt.claim.sub', '10000000-0000-4000-8000-000000000001', true);
select ok(
  public.sd_can_view_event((select event_id from game_test_context)),
  'active owner can view the game'
);

select set_config('request.jwt.claim.sub', '10000000-0000-4000-8000-000000000002', true);
select ok(
  public.sd_can_view_event((select event_id from game_test_context)),
  'explicit scorekeeper can view the game'
);

select set_config('request.jwt.claim.sub', '10000000-0000-4000-8000-000000000003', true);
select ok(
  public.sd_can_view_event((select event_id from game_test_context)),
  'team player can view the game'
);

select set_config('request.jwt.claim.sub', '10000000-0000-4000-8000-000000000004', true);
select ok(
  public.sd_can_view_event((select event_id from game_test_context)),
  'linked parent can view the game'
);

select set_config('request.jwt.claim.sub', '10000000-0000-4000-8000-000000000005', true);
select ok(
  not public.sd_can_view_event((select event_id from game_test_context)),
  'unrelated user cannot view the game'
);

select set_config('request.jwt.claim.sub', '20000000-0000-4000-8000-000000000001', true);
select ok(
  not public.sd_can_view_event((select event_id from game_test_context)),
  'member of another organization cannot view the game'
);

select set_config('request.jwt.claim.sub', '10000000-0000-4000-8000-000000000003', true);
select ok(
  not public.sd_can_manage_event((select event_id from game_test_context)),
  'player cannot manage the game'
);

select set_config('request.jwt.claim.sub', '10000000-0000-4000-8000-000000000002', true);
select ok(
  public.sd_can_manage_event((select event_id from game_test_context)),
  'active staff scorekeeper with edit permission can manage the game'
);
select ok(
  public.sd_can_score_game((select game_id from game_test_context)),
  'explicit scorekeeper can score the game'
);
select ok(
  exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'sd_game_scoring_events'
  ),
  'scoring events are published for authorized realtime viewers'
);

select set_config('request.jwt.claim.sub', '10000000-0000-4000-8000-000000000003', true);
select ok(
  not public.sd_can_score_game((select game_id from game_test_context)),
  'player cannot score the game'
);

set local role authenticated;
select is(
  (select count(*)::bigint from public.sd_games),
  1::bigint,
  'team player sees the authorized game through RLS'
);
reset role;

select set_config('request.jwt.claim.sub', '10000000-0000-4000-8000-000000000005', true);
set local role authenticated;
select is(
  (select count(*)::bigint from public.sd_games),
  0::bigint,
  'unrelated user sees no games through RLS'
);
reset role;

select set_config('request.jwt.claim.sub', '20000000-0000-4000-8000-000000000001', true);
set local role authenticated;
select is(
  (select count(*)::bigint from public.sd_games),
  0::bigint,
  'other organization owner sees no games through RLS'
);
reset role;

select set_config('request.jwt.claim.sub', '10000000-0000-4000-8000-000000000002', true);
update game_test_context
set active_token = (
  public.sd_acquire_scorekeeping_control(
    game_id,
    '30000000-0000-4000-8000-000000000001',
    'coach-session'
  )->>'control_token'
);
select ok(
  (select active_token is not null from game_test_context),
  'scorekeeper acquires an expiring control token'
);

select set_config('request.jwt.claim.sub', '10000000-0000-4000-8000-000000000001', true);
select is(
  (
    public.sd_acquire_scorekeeping_control(
      (select game_id from game_test_context),
      '30000000-0000-4000-8000-000000000002',
      'owner-session'
    )->>'state'
  ),
  'liveViewer',
  'a second device becomes a live viewer while the lease is active'
);

with requested as (
  select public.sd_request_scorekeeping_control(
    (select game_id from game_test_context),
    '30000000-0000-4000-8000-000000000002'
  ) as result
)
update game_test_context
set
  request_id = (requested.result->>'request_id')::uuid,
  request_token = requested.result->>'control_token'
from requested;

select ok(
  (select request_id is not null and request_token is not null from game_test_context),
  'viewer can create a token-bound control request'
);

select set_config('request.jwt.claim.sub', '10000000-0000-4000-8000-000000000002', true);
select ok(
  public.sd_resolve_scorekeeping_control_request(
    (select request_id from game_test_context),
    true,
    '30000000-0000-4000-8000-000000000001',
    (select active_token from game_test_context)
  ),
  'active scorekeeper can approve the control transfer'
);

select set_config('request.jwt.claim.sub', '10000000-0000-4000-8000-000000000001', true);
update game_test_context
set active_token = request_token;
select ok(
  public.sd_renew_scorekeeping_control(
    (select game_id from game_test_context),
    '30000000-0000-4000-8000-000000000002',
    (select active_token from game_test_context)
  ),
  'approved requester owns and can renew the transferred lease'
);

select set_config('request.jwt.claim.sub', '10000000-0000-4000-8000-000000000002', true);
select throws_ok(
  $$select public.sd_force_scorekeeping_takeover(
    (select game_id from game_test_context),
    '30000000-0000-4000-8000-000000000003',
    'coach-force'
  )$$,
  'P0001',
  'force_takeover_not_authorized',
  'coach cannot force a takeover'
);

select set_config('request.jwt.claim.sub', '10000000-0000-4000-8000-000000000001', true);
update game_test_context
set active_token = (
  public.sd_force_scorekeeping_takeover(
    game_id,
    '30000000-0000-4000-8000-000000000003',
    'owner-force'
  )->>'control_token'
);
select ok(
  (select active_token is not null from game_test_context),
  'organization owner can force a controlled takeover'
);

select lives_ok(
  $$select public.sd_append_game_scoring_event(
    (select game_id from game_test_context),
    (select event_id from game_test_context),
    '40000000-0000-4000-8000-000000000001',
    0,
    'game_started',
    '30000000-0000-4000-8000-000000000003',
    (select active_token from game_test_context),
    '{}'::jsonb,
    'event-1',
    null,
    null
  )$$,
  'valid lease appends the first scoring event'
);

select is(
  (
    select game_version
    from public.sd_append_game_scoring_event(
      (select game_id from game_test_context),
      (select event_id from game_test_context),
      '40000000-0000-4000-8000-000000000099',
      0,
      'ignored_duplicate',
      '30000000-0000-4000-8000-000000000003',
      'not-the-active-token',
      '{}'::jsonb,
      'event-1',
      null,
      null
    )
  ),
  1::bigint,
  'idempotent replay returns the original event before lease validation'
);

select throws_ok(
  $$select public.sd_append_game_scoring_event(
    (select game_id from game_test_context),
    (select event_id from game_test_context),
    '40000000-0000-4000-8000-000000000098',
    0,
    'stale_write',
    '30000000-0000-4000-8000-000000000003',
    (select active_token from game_test_context),
    '{}'::jsonb,
    'event-stale',
    null,
    null
  )$$,
  'P0001',
  'stale_game_version',
  'optimistic concurrency rejects a stale game version'
);

select lives_ok(
  $$select public.sd_append_game_scoring_event(
    (select game_id from game_test_context),
    (select event_id from game_test_context),
    '40000000-0000-4000-8000-000000000002',
    1,
    'plate_appearance',
    '30000000-0000-4000-8000-000000000003',
    (select active_token from game_test_context),
    '{"result":"single"}'::jsonb,
    'event-2',
    null,
    null
  )$$,
  'second scoring event appends at the current version'
);

update game_test_context
set decision_id = (
  public.sd_append_game_scoring_decision(
    game_id,
    '40000000-0000-4000-8000-000000000002',
    '50000000-0000-4000-8000-000000000001',
    null,
    'hit_type',
    null,
    'single',
    'final',
    'official-scoring',
    'Initial official ruling',
    false
  )
).id;

select ok(
  (select decision_id is not null from game_test_context),
  'official scoring decision is recorded against a physical event'
);

select lives_ok(
  $$select public.sd_append_game_scoring_event(
    (select game_id from game_test_context),
    (select event_id from game_test_context),
    '40000000-0000-4000-8000-000000000003',
    2,
    'game_ended',
    '30000000-0000-4000-8000-000000000003',
    (select active_token from game_test_context),
    '{"home_score":3,"away_score":2}'::jsonb,
    'event-3',
    null,
    null
  )$$,
  'game-ended event completes the mutable scoring ledger'
);

update game_test_context
set finalization_id = (
  public.sd_finalize_game(
    game_id,
    3,
    '30000000-0000-4000-8000-000000000003',
    active_token,
    'final-1',
    '{"team_totals":{"home":3,"away":2}}'::jsonb,
    '{"issues":[]}'::jsonb
  )
).id;

select ok(
  (select finalization_id is not null from game_test_context),
  'valid completed game finalizes atomically'
);
select is(
  (select status from public.sd_games where id = (select game_id from game_test_context)),
  'final',
  'finalization marks the game final'
);
select is(
  (select status from public.sd_events where id = (select event_id from game_test_context)),
  'final',
  'finalization marks the canonical calendar event final'
);
select is(
  (
    select id
    from public.sd_finalize_game(
      (select game_id from game_test_context),
      3,
      '30000000-0000-4000-8000-000000000003',
      'already-released',
      'final-1',
      '{}'::jsonb,
      '{"issues":[]}'::jsonb
    )
  ),
  (select finalization_id from game_test_context),
  'finalization retry is idempotent after the lease is released'
);

select is(
  (
    select count(*)::bigint
    from public.sd_notifications
    where recipient_user_id = '10000000-0000-4000-8000-000000000003'
      and category = 'game_update'
  ),
  1::bigint,
  'team player receives one final-game update'
);
select is(
  (
    select count(*)::bigint
    from public.sd_notifications
    where recipient_user_id = '10000000-0000-4000-8000-000000000004'
      and category = 'game_update'
  ),
  1::bigint,
  'linked parent of a team player receives one final-game update'
);
select is(
  (
    select count(*)::bigint
    from public.sd_notifications
    where recipient_user_id = '10000000-0000-4000-8000-000000000005'
      and category = 'game_update'
  ),
  0::bigint,
  'unrelated user receives no game update'
);

update game_test_context
set correction_id = (
  public.sd_correct_final_game_decision(
    game_id,
    decision_id,
    'double',
    'Official postgame correction',
    'correction-1',
    '{"team_totals":{"home":3,"away":2}}'::jsonb,
    '{"issues":[]}'::jsonb
  )
).id;

select ok(
  (select correction_id is not null from game_test_context),
  'authorized owner records an append-only postgame correction'
);
select is(
  (
    select id
    from public.sd_correct_final_game_decision(
      (select game_id from game_test_context),
      (select decision_id from game_test_context),
      'double',
      'Official postgame correction',
      'correction-1',
      '{}'::jsonb,
      '{"issues":[]}'::jsonb
    )
  ),
  (select correction_id from game_test_context),
  'postgame correction retry is idempotent'
);
select is(
  (
    select decision_status
    from public.sd_game_scoring_decisions
    where id = (select decision_id from game_test_context)
  ),
  'superseded',
  'correction preserves and supersedes the original ruling'
);
select is(
  (
    select count(*)::bigint
    from public.sd_game_scoring_decisions
    where game_id = (select game_id from game_test_context)
      and decision_status = 'final'
      and final_value = 'double'
  ),
  1::bigint,
  'correction creates one current final ruling'
);
select is(
  (
    select count(*)::bigint
    from public.sd_game_audit_log
    where game_id = (select game_id from game_test_context)
      and action in ('game_finalized', 'final_game_corrected')
  ),
  2::bigint,
  'finalization and correction both produce audit entries'
);
select is(
  (
    select count(*)::bigint
    from public.sd_game_stat_snapshots
    where game_id = (select game_id from game_test_context)
  ),
  1::bigint,
  'finalization and correction maintain one current statistics snapshot'
);
select is(
  (
    select count(*)::bigint
    from public.sd_notifications
    where recipient_user_id = '10000000-0000-4000-8000-000000000003'
      and category = 'game_update'
  ),
  2::bigint,
  'player receives distinct final and corrected-game notifications'
);
select is(
  (
    select count(*)::bigint
    from public.sd_notifications
    where recipient_user_id = '10000000-0000-4000-8000-000000000004'
      and category = 'game_update'
  ),
  2::bigint,
  'parent receives distinct final and corrected-game notifications'
);

select * from finish();

rollback;
