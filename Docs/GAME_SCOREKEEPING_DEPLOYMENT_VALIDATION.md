# Home Plate Game Scorekeeping Deployment Validation

## Executive result

**Overall verdict: NOT READY TO DEPLOY**

The local Games, Calendar, and Live Scorekeeping stack now passes deterministic clean
database resets, strict database lint, 42 database integration assertions, 373 shared Edge
Function tests, the Swift test suite, and both iOS and macOS builds from a freshly generated
XcodeGen project.

Deployment remains blocked by repository/environment alignment rather than the validated
game database behavior:

1. The linked Supabase project contains 18 remote-only migrations from
   `20260717153000` through `20260721060000`.
2. The checked-in Xcode project is stale and does not include the new Games source files.
   `project.yml` is correct; a freshly generated project builds and tests successfully.
3. A full check of all Edge Function entry points reports eight pre-existing type errors in
   the unrelated Stripe webhook functions.

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

1. Restore the missing remote-only migration files from the authoritative branch/history
   and re-run both clean resets and all tests.
2. Close Xcode, regenerate `MultiOrg.xcodeproj` from `project.yml`, and review only the
   generated Games target-membership change alongside the user's unrelated project diff.
3. Repair the pre-existing Stripe webhook type-check errors or explicitly scope the
   deployment pipeline to type-check only the functions being deployed.
4. Add the remaining full-game and real multi-connection/websocket runtime scenarios.
5. Re-run this complete report before any push or deployment.
