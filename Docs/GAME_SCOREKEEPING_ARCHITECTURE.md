# Home Plate Games, Calendar, and Live Scorekeeping

## Production vertical path

Home Plate uses one canonical `sd_events` identity for schedule, visibility, attendance,
and lifecycle. `sd_games` adds baseball-specific configuration and points back to that
event. Every calendar and role opens the same game workspace.

Live scoring is server authoritative:

1. An authorized scorer acquires a short database lease bound to user and device.
2. Every accepted action appends one immutable `sd_game_scoring_events` row.
3. The append RPC checks the lease token, expected game version, canonical event, and
   idempotency key while holding the game row lock.
4. Clients derive state by replaying the ordered ledger with the stored ruleset version.
5. Realtime wakes viewers; a fresh authorized query remains the source of truth.
6. Official scorer judgments are versioned decisions. Revisions supersede, never mutate.
7. Finalization replays and validates the ledger, derives statistics, requires the active
   scoring lease, and atomically writes the final snapshot and lifecycle.
8. Postgame corrections append a new decision, refresh the snapshot, notify viewers, and
   record the actor and reason in the audit ledger.

## Domain tables

- Calendar: `sd_events`, `sd_event_participants`, `sd_event_attendance`
- Game: `sd_games`
- Rules: `sd_game_rulesets`, `sd_game_ruleset_versions`
- Ledger: `sd_game_scoring_events`, `sd_game_state_snapshots`
- Control: `sd_game_scorekeeper_sessions`, `sd_game_control_requests`,
  `sd_game_live_devices`
- Official record: `sd_game_scoring_decisions`, `sd_game_stat_snapshots`,
  `sd_game_finalizations`, `sd_game_corrections`, `sd_game_audit_log`

## Authorization

All reads and mutations are organization scoped under RLS. Calendar visibility is
participant/team/role aware. Scoring requires an active organization context plus either
organization administration or explicit event scoring permission. Only one valid
user-device lease can mutate a live game. Finalization requires that same lease.
Postgame correction is restricted to organization administrators, the assigned
scorekeeper, or explicitly audited platform support.

Parents and players receive view-only game projections. Hidden staff notes and control
tokens are never included in those projections. Control tokens are stored only as hashes.

## Lifecycle and recovery

Supported lifecycle values include draft, scheduled, pregame, live, delayed, suspended,
postponed, canceled, final, forfeit, and no contest. A scorer can record delay, suspension,
resume, game end, and finalization without replacing game identity.

After disconnect, the scorer reloads the immutable ledger and reacquires an expired lease.
Stale expected versions are rejected. Duplicate idempotency keys return the previously
accepted event. Another device remains a viewer until control is released, transferred,
or force-taken by an organization administrator.

## Statistics and earned runs

Batting, pitching, and fielding lines derive from physical ledger events plus the latest
non-superseded official decision. Administrative outs do not create fabricated player
statistics. Earned-run reconstruction replays virtual outs and excludes placed runners.
Finalization is blocked by unresolved decisions, invalid state, pending regulation
actions, ledger/version disagreement, or non-reconciling statistics.

## Realtime and notifications

Realtime publication includes canonical events, games, scoring events, live devices,
control requests, official decisions, and audit entries. Realtime is an invalidation
signal, not an authorization or state source.

Game updates use the `game_update` notification category and the `game_detail` route.
Finalization and correction deduplicate notifications per game/correction.

## Migration order

Apply in timestamp order:

1. `20260729010000_game_events_foundation.sql`
2. `20260729020000_game_calendar_integration.sql`
3. `20260729030000_game_rulesets.sql`
4. `20260729040000_game_scoring_ledger.sql`
5. `20260729050000_game_scorekeeper_sessions.sql`
6. `20260729060000_game_official_scoring.sql`
7. `20260729070000_game_finalization_and_audit.sql`

These migrations are additive. Do not deploy a later migration without all predecessors.
Before production, run them against a staging clone and exercise every role.

## Rollback

Preserve ledger and audit data first. Disable game creation/scoring in clients, then revoke
mutation RPC grants. If schema rollback is unavoidable, remove Phase 9 triggers/functions
before its tables and walk backward in reverse migration order. Never delete scoring or
audit history as an operational rollback.

## Validation matrix

- Owner/admin/assigned scorer/coach/player/parent/platform-support visibility
- Cross-organization query and deep-link denial
- Schedule, postpone, cancel, delay, suspend, resume, forfeit, no-contest, and final
- Concurrent scorer acquisition, stale lease, transfer, force takeover, and reconnect
- Duplicate event idempotency and stale expected-version rejection
- Ball/strike/outs, runner movement, substitutions, ruleset overrides, and game end
- Preliminary/final/revised decisions and unresolved-decision blocking
- Earned-run reconstruction, batting/pitching/fielding reconciliation, and snapshots
- Atomic finalization failure rollback and idempotent retry
- Final correction audit/notification and immutable history
- iPhone, iPad, and macOS workspace behavior
