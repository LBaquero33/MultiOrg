# Home Plate Game Scorekeeping Deployment Validation

## Executive result

**Overall verdict: READY TO DEPLOY**

The Games, Calendar, and Live Scorekeeping stack passes deterministic clean database
resets, strict database lint, 42 database integration assertions, 373 shared Edge Function
tests, actual Realtime WebSocket fan-out and authorization tests, 25 simultaneous
scorekeeper lease races, the complete Swift test suite, and canonical iOS and macOS builds.

The three blockers recorded by the initial validation have been closed:

1. All 18 remote-only migration files were recovered and committed without rewriting
   remote history.
2. The canonical checked-in Xcode project was regenerated and now includes Games sources.
3. The eight global Deno errors were proven to exist at the starting commit and remain
   confined to unrelated Stripe webhook functions not changed or imported by this branch.

No remote migration, Edge Function, push, merge, or deployment was performed.

## Repository and tools

- Repository: `/Users/lb33/Documents/HomePlate`
- Remote: `https://github.com/LBaquero33/MultiOrg.git`
- Branch: `feature/game-calendar-live-scoring`
- Starting HEAD: `c89b66b012919998352bcb4784942b28097ff1d3`
- Supabase CLI: `2.101.0`
- Local Supabase server: `29.6.2`
- Deno: `2.9.4`
- Swift: Apple Swift `6.3.2`
- Xcode: `26.5`
- Pre-existing `MultiOrg.xcodeproj/project.pbxproj` modification: preserved and not staged

## Clean-reset defect chain

### Initial failure

`20260710213000_platform_admin_and_teams.sql` inserted a production-specific platform
administrator whose `auth.users` row did not exist on a clean database. The foreign key
was correct and remained intact.

### Fix

- The historical insert is conditional on the referenced auth user existing.
- `supabase/seed.sql` creates a deterministic local-only auth fixture before its matching
  local platform-admin row.
- No production identity or credential was added to schema migrations.

### Additional failures repaired

- Removed a reference to nonexistent `sd_parent_child_links.status`.
- Qualified `gen_random_bytes` through the `extensions` schema.
- Corrected use of PostgreSQL's special-form `greatest` in the chat read-cursor function.
- Dropped one retired development-alert overload that failed strict lint.
- Restored game/calendar notification categories after later notification migrations
  narrowed the centralized validator.
- Added linked-parent game visibility and game-update notification recipients without
  broadening unrelated organization access.

## Database validation

- Clean reset attempt 1: PASS
- Clean reset attempt 2: PASS
- Final reset after all fixes: PASS
- Local migration order: PASS through `20260729110000`
- Strict lint:
  `supabase db lint --local --level error --fail-on error`: PASS, zero errors
- pgTAP:
  `supabase test db supabase/tests/game_scorekeeping_integration_test.sql`: PASS, 42/42

The integration suite proves:

- owner, explicit scorekeeper, team-player, linked-parent, unrelated-user, and
  cross-organization access outcomes
- direct table RLS isolation
- viewer versus scorekeeper behavior
- lease acquisition, transfer, renewal, and permission-restricted forced takeover
- token-bound mutation and stale-version rejection
- event idempotency
- official-scoring decision persistence
- atomic and idempotent finalization
- canonical game and calendar final status
- append-only, idempotent postgame correction and audit history
- current-stat-snapshot replacement
- player/linked-parent notification delivery and unrelated-recipient exclusion
- scoring-event membership in the `supabase_realtime` publication

## Backend and Deno validation

Command:

```text
/Users/lb33/.deno/bin/deno test --allow-env --allow-read \
  supabase/functions/_shared/*_test.ts
```

Result: PASS, 373 passed, 0 failed.

A complete `deno check` of every Edge Function entry point found eight pre-existing,
unrelated errors in:

- `supabase/functions/stripe-platform-webhook/index.ts`
- `supabase/functions/stripe-webhook/index.ts`

The failures concern nullable values, Supabase client generic mismatches, and access to
`message` on an unknown error. No Stripe file was changed in this pass.

## Swift tests and builds

The checked-in Xcode project blocks direct validation for two independent reasons:

- Xcode currently has the project open, causing command-line file-coordination stalls.
- Its project file does not contain `MultiOrg/Features/Games/*.swift`, although
  `project.yml` correctly uses recursive source discovery.

Validation therefore generated a temporary project with the repository's bundled
XcodeGen `2.45.4`, without changing the checked-in project file.

- MultiOrg Swift tests on iPhone simulator: PASS
- Generic iOS Simulator Debug build: PASS
- MultiOrgMac Debug build: PASS
- Warnings: two unrelated unused-return-value warnings in
  `PlayerDevelopmentImportTests.swift`

## Scope limitations

The requested representative persisted game was not expanded into every baseball event
listed in the deployment brief. Swift reducer and official-scoring tests cover pitch/count,
run cap, administrative outs, hits, errors, placed runners, earned-run behavior, and
finalization guards, while the database suite covers persisted ledger, lease, finalization,
correction, notification, and isolation behavior.

Not separately proven by a full persisted end-to-end fixture in this pass:

- every listed baserunning, substitution, discipline, injury, and delay event
- simultaneous lease acquisition from two physical network connections
- actual Realtime websocket delivery to multiple devices
- external push, email, or SMS delivery
- remote migration application and remote smoke testing

## Linked migration history

The linked project matches local history through `20260715100000`, then contains 18
remote-only migrations:

```text
20260717153000 through 20260718171000
20260721050000
20260721060000
```

The eleven local game-validation migrations `20260729010000` through `20260729110000`
are not remote. This divergence must be reconciled from the authoritative source before
any `supabase db push`; migration repair was intentionally not used.

## Files in this validation pass

Modified:

- `supabase/migrations/20260710213000_platform_admin_and_teams.sql`
- `supabase/migrations/20260729020000_game_calendar_integration.sql`
- `supabase/migrations/20260729050000_game_scorekeeper_sessions.sql`
- `supabase/seed.sql`

Added:

- `supabase/migrations/20260729080000_predeploy_lint_repairs.sql`
- `supabase/migrations/20260729090000_restore_game_calendar_notification_categories.sql`
- `supabase/migrations/20260729100000_align_game_notification_validation.sql`
- `supabase/migrations/20260729110000_allow_linked_parents_to_view_team_games.sql`
- `supabase/tests/game_scorekeeping_integration_test.sql`
- `Docs/GAME_SCOREKEEPING_DEPLOYMENT_VALIDATION.md`

## Recommended next action

Review the 13-migration dry-run delta, then deploy only after explicit approval. Remote
smoke testing and physical-device validation remain post-deployment activities.

## Final deployment-readiness closure

This section records the continuation pass and preserves the earlier partial results above.

### Migration reconciliation and database

- All 18 remote-only timestamps were recovered with
  `supabase migration fetch --linked` in a disposable worktree.
- Recovered SQL bodies were available for every timestamp; hashes and provenance are in
  `Docs/SUPABASE_MIGRATION_RECONCILIATION.md`.
- Timestamp conflicts: none.
- Two consecutive clean local database resets: PASS.
- Local migration order: PASS through `20260729130000`.
- Linked history: aligned through `20260721060000`.
- `supabase db push --dry-run`: exactly 13 intended July 29 migrations; no recovered
  migration would be reapplied.
- Strict database lint: PASS, zero errors.
- Database pgTAP suite: PASS, 42/42.
- The additive `20260729130000` repair establishes a consistent game-before-session lock
  order for scorekeeper transfer and append operations, eliminating a reproduced
  concurrent-transfer deadlock without weakening lease ownership.

### Canonical project and Swift

- `MultiOrg.xcodeproj` was regenerated from `project.yml` and committed.
- The user's pre-existing machine/signing project-file changes were reapplied and remain
  unstaged.
- Canonical iOS simulator test build: PASS.
- XCTest: PASS, 2 tests.
- Swift Testing: PASS, 251 tests in 22 suites.
- Canonical macOS Debug build: PASS.
- Parsing all `MultiOrg/**/*.swift` sources with `swiftc -parse`: PASS.

### Realtime and concurrent control

The new integration suite uses independent authenticated Supabase clients and actual local
Realtime WebSocket subscriptions.

- Authorized viewer receives exactly one committed event with the correct game version.
- Unauthorized and cross-organization users receive zero private game events.
- Reconnection does not duplicate a processed event.
- A finalized correction reaches the viewer exactly once.
- Twenty-five synchronized independent-client acquisition races each produce one
  scorekeeper, one viewer, and one active lease.
- Losing devices cannot mutate.
- Concurrent takeover, lease expiration, heartbeat, old-token transfer, and reconnect
  after takeover scenarios pass.
- Two consecutive complete Realtime/concurrency runs: PASS.

### Backend and Stripe classification

- Shared Deno/backend tests: PASS, 373/373.
- The same eight global type-check errors occur at the starting commit and current commit,
  four each in `stripe-platform-webhook` and `stripe-webhook`.
- The game branch changes no Edge Function source and imports no failing Stripe module.
- Errors introduced by this branch: zero.
- Stripe files changed: none.

### Remaining limitations

- No physical multi-device validation was performed.
- External APNs/email/SMS delivery was not exercised.
- The repository has no stable dedicated live-game snapshot harness, so no new visual
  snapshot suite was added.
- The test suite is broad but does not exhaustively enumerate every possible baseball play.
- Remote migration application and remote smoke testing remain intentionally unperformed.

## 2026-07-31 deployment attempt

Deployment began at `2026-07-31 00:26 EDT` against Supabase project
`kbulbvngysflfhaqpvtv` (shared live Home Plate environment, West US/Oregon).

### Recovery and source control

- Pre-deployment schema dump:
  `/Users/lb33/HomePlateBackups/homeplate_pre_games_20260731_001321_schema.sql`
- Pre-deployment data dump:
  `/Users/lb33/HomePlateBackups/homeplate_pre_games_20260731_001321_data.sql`
- Feature branch push: PASS.
- Remote branch:
  `feature/game-calendar-live-scoring` at
  `16058196dfb2ad8e803ded6c047df138f96c411e`.
- No branch merge was performed.

### Final deployment delta

Two immediately-preceding linked migration checks and dry runs both proposed exactly:

```text
20260729010000
20260729020000
20260729030000
20260729040000
20260729050000
20260729060000
20260729070000
20260729080000
20260729090000
20260729100000
20260729110000
20260729120000
20260729130000
```

No recovered historical or unrelated migration was proposed.

### Database push result

The push stopped at the first failure, as required:

- `20260729010000_game_events_foundation.sql`: APPLIED and recorded remotely.
- `20260729020000_game_calendar_integration.sql`: ROLLED BACK and not recorded.
- `20260729030000` through `20260729130000`: NOT ATTEMPTED.

Postgres rejected the replacement `sd_notifications_category_check` constraint with
SQLSTATE `23514` because existing rows violate the proposed category list. The
pre-deployment data dump shows eight existing `sd_notifications` rows with category
`schedule_change`; that established category is absent from the temporary constraint in
`20260729020000`. A later migration restores legacy categories, but execution cannot reach
it while migration `20260729020000` rejects the existing data.

No retry, migration repair, remote reset, or already-applied migration edit was performed.

### Verification intentionally stopped

- Remote migration head: `20260729010000`.
- Remote lint: not run against the incomplete deployment.
- Remote authorization/RLS smoke tests: not run.
- Remote Realtime/concurrency smoke tests: not run.
- Remote lifecycle/finalization/correction tests: not run.
- Edge Functions changed by the branch: none.
- Edge Functions deployed: none.

### Required remediation

Create and locally validate a migration-safe correction that preserves existing
`schedule_change` notifications while installing the calendar/game category constraint.
Because `20260729010000` is already remote, remediation must start from that exact partial
remote state. Do not use migration repair; do not rerun the remaining batch until a new
dry run and complete local validation prove the corrected order.

## 2026-07-31 notification-category remediation

This section preserves the failed-deployment record above and records the reviewed
correction before the deployment retry.

### Exact failure and remote evidence

- Failure: SQLSTATE `23514` while applying
  `20260729020000_game_calendar_integration.sql`.
- Cause: the replacement `sd_notifications_category_check` omitted the established
  `schedule_change` category.
- Existing affected rows: eight, all preserved and not rewritten.
- Other existing notification categories: `message_received` (10 rows) and
  `payment_request_created` (5 rows).
- Existing source values: `chat` (10 rows), `payment_request` (5 rows), and
  `event_operation` (8 rows).
- Remote migration state remained unchanged at `20260729010000`; no migration repair,
  remote reset, or manual schema patch was used.

### Corrected validation contract

Migration `20260729020000` now installs the complete legacy-plus-game category and source
constraints using `NOT VALID` followed by `VALIDATE CONSTRAINT`. Later migrations
`20260729070000`, `20260729090000`, and the centralized validator in
`20260729100000` retain every valid earlier category while adding `game_update` at the
timestamp where it is introduced.

The final category set is:

```text
payment_request_created, payment_received, booking_created, booking_updated,
program_assigned, program_updated, message_received, testing_result_added,
organization_announcement, team_announcement, event_announcement, schedule_change,
event_reminder, attendance, availability, practice_plan, game_plan,
lineup_assignment, registration, payment_notice, result_recap, event_created,
event_updated, event_canceled, event_postponed, event_rescheduled,
availability_requested, game_starting, game_live, game_update, game_final, system
```

The final source set is:

```text
payment_request, payment_webhook, announcement, chat, schedule, event_operation,
practice_plan, game_plan, registration, organization_finance, event, system
```

### Regression and local validation

- Upgrade regression: seeds a `schedule_change` / `event_operation` notification before
  replacing the constraint, validates the replacement, and proves the row is unchanged.
- Canonical-category regression: every final category is accepted and an arbitrary value
  remains rejected with SQLSTATE `23514`.
- Notification deduplication and recipient-isolation assertions remain in the game
  integration suite.
- Clean local reset 1: PASS through `20260729130000`.
- Clean local reset 2: PASS through `20260729130000`.
- Strict local database lint: PASS, zero errors.
- Database pgTAP: PASS, 47/47.
- Shared Deno/backend tests: PASS, 376/376.
- Migration-contract Deno tests: PASS, 3/3.
- Local Realtime/concurrency suite: PASS twice consecutively, including actual WebSocket
  fan-out, cross-organization denial, 25 synchronized lease races, stale writes,
  finalization, and correction replay.
- MultiOrg iOS simulator test: PASS, 251 tests in 22 suites.
- MultiOrgMac Debug compile validation: PASS with code signing disabled.

### Reviewed retry delta

The linked migration history still records `20260729010000` and no later July 29
migration. The reviewed dry run proposes exactly these twelve migrations:

```text
20260729020000
20260729030000
20260729040000
20260729050000
20260729060000
20260729070000
20260729080000
20260729090000
20260729100000
20260729110000
20260729120000
20260729130000
```

No recovered historical migration, `20260729010000`, or unrelated migration is included.
The database retry, fresh partial-state backup, remote lint, and remote smoke-test results
are recorded in the deployment closure below after they execute.

Deployment verdict: `DEPLOYMENT FAILED — REMEDIATION REQUIRED`.

## Remediation deployment closure — 2026-07-31

The failed migration was corrected, validated, committed, pushed, backed up, and
redeployed without migration repair, a remote reset, or a Dashboard SQL patch.

### Remediation source checkpoint

- Commit: `ad7f224cd19b1502fe273ddd812b9be8275ea375`
- Message: `fix: preserve legacy notification categories during game migration`
- Remote branch: `origin/feature/game-calendar-live-scoring`
- The remote branch resolved to the remediation commit before the database retry.
- The focused commit contains only the corrected notification migrations, migration
  contract test, database regression test, and this deployment validation document.

### Partial-state backup checkpoint

The original pre-deployment backups remain unchanged. A second backup was taken after
remote migration `20260729010000` and before retrying `20260729020000`:

```text
/Users/lb33/HomePlateBackups/homeplate_partial_games_20260731_010057_schema.sql
/Users/lb33/HomePlateBackups/homeplate_partial_games_20260731_010057_data.sql
```

Both backup commands completed successfully and produced nonempty files. The schema
backup is 1,200,799 bytes and the data backup is 4,354,301 bytes.

### Database retry

Immediately before the push, the linked migration list and a second dry run were
compared byte-for-byte with the approved set. The pending set was exactly:

```text
20260729020000
20260729030000
20260729040000
20260729050000
20260729060000
20260729070000
20260729080000
20260729090000
20260729100000
20260729110000
20260729120000
20260729130000
```

One `supabase db push --yes` was executed. All twelve migrations applied successfully
in timestamp order. The linked migration list now records every migration through
`20260729130000` exactly once.

### Post-deployment notification compatibility

The post-deployment remote schema contains the complete canonical category constraint:

```text
payment_request_created, payment_received, booking_created, booking_updated,
program_assigned, program_updated, message_received, testing_result_added,
organization_announcement, team_announcement, event_announcement, schedule_change,
event_reminder, attendance, availability, practice_plan, game_plan,
lineup_assignment, registration, payment_notice, result_recap, event_created,
event_updated, event_canceled, event_postponed, event_rescheduled,
availability_requested, game_starting, game_live, game_final, game_update, system
```

The remote source constraint is:

```text
payment_request, payment_webhook, announcement, chat, schedule, event_operation,
practice_plan, game_plan, registration, organization_finance, event, system
```

The eight pre-existing `schedule_change` rows still exist after deployment. A disposable
remote smoke organization proved that a new `schedule_change` row and the
`event_created`, `event_updated`, `game_starting`, `game_live`, `game_final`, and
`game_update` categories can be inserted. An arbitrary category was rejected with
SQLSTATE `23514`, recipient isolation held, and test cleanup restored the global
`schedule_change` count to eight.

### Remote authorization and lifecycle smoke tests

A disposable live-project harness created isolated users, organizations, a team, a game,
and a linked parent. It verified:

- owner, assigned scorekeeper, team player, and linked parent access
- unrelated-user and cross-organization denial
- direct-ID RLS denial for unrelated and cross-organization users
- rescheduling updates the canonical event while retaining one event and one game row
- notification recipient isolation and category validation

The remote Realtime/concurrency suite used a separate disposable organization and users.
The first run timed out waiting for the initial CDC event while the Realtime publication
was cold. An unchanged second run passed and exercised:

- authorized WebSocket fan-out with unauthorized and cross-organization exclusion
- disconnect/reconnect behavior without duplicate replay
- 25 synchronized scorekeeper-lease races with one winner per race
- losing-client mutation denial
- controlled transfer and stale-token rejection
- stale-version rejection and idempotent scoring-event replay
- game ending, idempotent finalization, postgame correction, audit history, and
  correction fan-out exactly once

All disposable organizations and users were removed by the harnesses.

The linked pgTAP command could not execute because the Supabase remote test login role
does not have `USAGE` on the existing `extensions` schema that contains pgTAP. Both
attempts stopped before test setup or data mutation. The same 47-assertion suite passed
locally after two clean resets, while the remote-safe Deno harnesses covered the
authorization, notification, Realtime, lease, stale-write, finalization, and correction
paths against the deployed schema.

### Remote lint

`supabase db lint --linked --level error` reports one blocking error in the pre-existing
`public.sd_generate_parent_code` function:

```text
SQLSTATE 42883
function gen_random_bytes(integer) does not exist
```

The function uses unqualified `gen_random_bytes(size)` under a restricted search path.
The same function body is present in both the original pre-games schema backup and the
partial-state backup taken before the retry, proving the game migration batch did not
introduce it. The local migration history already qualifies the function as
`extensions.gen_random_bytes`; a separate additive remote correction is required to
bring the historical live function body into alignment. No ad hoc remote patch was made
during this deployment.

Warning-level lint also reports pre-existing unused variables or parameters in
`sd_sync_apple_player_subscription`, `sd_apply_event_operation_mutation`, and
`sd_change_invoice_state`.

### Final remediation verdict

Deployment verdict: `DEPLOYED WITH REQUIRED FOLLOW-UP`.

The game/calendar/live-scorekeeping schema is deployed and remotely exercised. The
required follow-up is the pre-existing `sd_generate_parent_code` lint error and the
remote pgTAP test-role permission limitation; neither is a regression from the deployed
game migration.
