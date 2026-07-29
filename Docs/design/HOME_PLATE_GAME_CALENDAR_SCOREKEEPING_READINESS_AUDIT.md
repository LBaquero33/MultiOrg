# Home Plate Game, Calendar, and Scorekeeping Readiness Audit

## 1. Executive summary

**Audit verdict: NOT READY.**

Home Plate has useful building blocks for a future game system: organization-scoped
memberships, teams, facility reservations, per-player program calendars, notification
delivery, Postgres Realtime, and platform audit conventions. It does not yet have the
foundational domain required to add safe game scheduling or live scorekeeping.

The repository has no canonical event model, game model, event participant/roster model,
attendance or availability ledger, game lifecycle, game-detail workspace, score event
ledger, scorer lease, device identity, versioned score mutation API, or game notification
routes. Current calendar surfaces independently combine program assignments and BP
sessions. A BP session whose `reps_type` is `game` is a recorded batting session, not a
scheduled game.

The most important blockers are:

1. **BLOCKER — no canonical event or game identity.** Games cannot be created, updated,
   postponed, suspended, resumed, canceled, or finalized as one authoritative record.
2. **BLOCKER — no server-authoritative single-scorekeeper protocol.** There is no lease,
   control token, expected game version, device binding, or stale-write rejection.
3. **BLOCKER — no immutable scoring ledger or transactional derived state.**
4. **HIGH — current calendars are separate player-centric projections, not a shared
   organization/team event feed.**
5. **HIGH — role visibility is not appropriate for games.** Staff policies are broad,
   parents cannot read program assignments used by their calendar, and facility booking
   visibility exposes every organization booking to every active organization member.
6. **HIGH — no game-aware notification, deep-link, facility reconciliation, attendance,
   or audit behavior exists.**
7. **MEDIUM — dates are stored safely as `timestamptz` for bookings, but calendar display
   uses a fixed `America/New_York` timezone rather than an organization/event timezone.**

The minimum path to readiness is to establish a canonical event/game domain and
role-safe calendar projection before any live-scoring UI is built.

## 2. Repository and branch state

| Item | Value |
|---|---|
| Audited checkout | `/Users/lb33/Documents/HomePlate` |
| Remote | `https://github.com/LBaquero33/MultiOrg.git` |
| Branch | `docs/hpms` |
| HEAD | `d109326e7b3e55be85db506c0a8ea9594f6ece9d` |
| Product | Home Plate |
| Historical repository name | MultiOrg |

The working tree was already dirty before this audit. Existing user changes were not
modified, staged, reverted, or included in this audit. This document is the only file
created by the audit.

## 3. Audit methodology

The audit used direct code and schema tracing:

- Enumerated all migrations and searched for event, game, schedule, attendance,
  availability, realtime, notification, team, facility, and audit structures.
- Traced every visible calendar from its Swift root to its Supabase queries and final RLS.
- Traced current organization selection and role helpers.
- Traced facility booking writes, overlap controls, and realtime subscriptions.
- Traced notification categories, destinations, deep-link ownership checks, and producers.
- Searched Swift and Deno tests for the required calendar/game/concurrency scenarios.
- Inspected design documents to distinguish implemented features from future direction.

Evidence labels used below:

- **Validated by automated test**
- **Validated by direct code trace**
- **Validated manually**
- **Inferred but not validated**
- **Missing**

No production system, external account, or customer data was accessed.

## 4. Existing event architecture

### Finding

There is no first-class event table, Swift event model, event service, or event RLS
policy. The product design explicitly treats Game Day as future work:

- `Docs/design/HOME_PLATE_WORKSPACES.md:40` — `Game Day (future)`.
- `Docs/design/HOME_PLATE_OS.md:21` — future Game Day workspace.
- `Docs/design/HOME_PLATE_COMPONENT_LIBRARY.md:99` — future `HPGameCard`,
  `HPScoreboard`, `HPBaseDiamond`, play-by-play, box score, and pitch-count components.
- `Docs/design/HOME_PLATE_DESIGN_SYSTEM.md:242` — future Game Day components.

Existing records that contain dates are not canonical events:

| Record | Purpose | Why it is not an event |
|---|---|---|
| `sd_facility_bookings` | Facility reservation/request | No team, opponent, roster, arrival time, event lifecycle, recurrence, or game identity |
| `sd_program_assignments` | Player program assignment | Defines a program period, not one scheduled event |
| `sd_daily_logs` / strength logs | Completed player work | Completion records, not shared schedule records |
| `sd_bp_sessions` | Batting session/import grouping | Player analysis session; `reps_type='game'` means game reps, not a scheduled game |
| Testing entries | Player assessment data | Measurement history, not a scheduled event |

`supabase/migrations/20260515134500_sd_tables.sql:112-121` defines
`sd_bp_sessions` with `session_date`, `source`, and `reps_type` constrained to
`practice` or `game`. `MultiOrg/Features/Player/SDPlayerCalendarView.swift:112-113`
turns those session types into practice/game date dots. That is presentation metadata,
not a canonical event.

**Evidence: Validated by direct code trace.**

### Required future event foundation

A canonical `sd_events` record should own:

- `id`, `org_id`, optional `team_id`
- event type (`game`, practice, workout, assessment, meeting, facility session)
- title and description with visibility classification
- `starts_at`, `ends_at`, `arrival_at`, and IANA `timezone`
- location and optional linked `facility_booking_id`
- recurrence series identity and occurrence identity
- lifecycle state and lifecycle version
- creator/editor and timestamps

Event participants should be separate records so visibility is not inferred from broad
organization membership.

## 5. Existing game support

There is no `sd_games` table, `Game` Swift model, game query, game-detail screen, game
roster, opponent model, score state, ruleset, lineup, play ledger, or finalization API.

The word `game` in the implemented player calendar comes from BP `reps_type`; it does not
provide:

- home/away designation
- opponent
- scheduled first pitch or arrival time
- venue/facility coordination
- team roster or availability
- status (`scheduled`, `postponed`, `suspended`, `final`)
- score or inning state
- persistent identity across schedule changes

**Evidence: Missing.**

Games should reference canonical events rather than duplicate their schedule and location.
A future `sd_games` record should add game-specific fields such as season/team/opponent,
home/away, ruleset, scoring status, current authoritative version, and finalized metadata.

## 6. Calendar surface inventory

| Surface | Entry point | Data source | Organization scope | Current limitations |
|---|---|---|---|---|
| Player calendar | `MultiOrg/Features/Player/SDPlayerCalendarView.swift:3` | `fetchActiveAssignments`, template schedule, `listBPSessions` | Mostly indirect through player and RLS | No shared event feed; BP “game” dots are analysis sessions |
| Coach player calendar | `MultiOrg/Features/Coach/CoachPlayerCalendarView.swift:5` | Selected player assignments, logs, strength, BP/import sessions | Selected player plus broad staff RLS | One player at a time; not team schedule |
| Parent child calendar | `MultiOrg/Features/Parent/ParentChildCalendarView.swift:4` | Child assignments and BP sessions | Child ID plus RLS | Assignment query is denied to parent by final assignment RLS |
| Shared month widget | `MultiOrg/Features/Shared/DHDMonthGridView.swift:3` | Caller-provided date sets | None by itself | Rendering primitive only |
| Coach facilities | `MultiOrg/Features/Coach/CoachFacilitiesView.swift:4` | Facilities and facility bookings | `org_id` on service calls/RLS | Reservation timeline, not event calendar |
| Player facilities | `MultiOrg/Features/Player/SDPlayerFacilitiesView.swift:6` | Facilities/bookings | Active organization and own player | Booking workflow only |
| Parent facilities | `MultiOrg/Features/Parent/SDParentFacilitiesView.swift:5` | Facilities/bookings for linked child | Active organization/child checks | Booking workflow only |

Relevant service methods:

- `MultiOrg/Core/SupabaseService.swift:2927` —
  `fetchActiveAssignments(playerId:)` filters by player and active assignment state.
- `MultiOrg/Core/SupabaseService.swift:2938` — `fetchTemplate(id:)`.
- `MultiOrg/Core/SupabaseService.swift:3236` — `listBPSessions(playerId:limit:)`.

The player root exposes a Calendar tab, while the coach root exposes Players, Facilities,
Teams, Programs, Chat, administration, and Account. There is no organization/team calendar
workspace. The parent calendar is nested under a selected child rather than being a
family event feed.

**Evidence: Validated by direct code trace.**

### Calendar unification assessment

The month-grid component is reusable, but the data architecture is not. A future calendar
must query one authorized event projection and then optionally overlay program work,
facility reservations, and analysis sessions. Combining the current independent queries
in Swift would preserve duplicate identity and authorization problems.

## 7. Role visibility matrix

This matrix describes current enforceable behavior, not desired game behavior.

| Role | Program assignment | Player logs/BP | Facility bookings | Team records | Game/live score |
|---|---|---|---|---|---|
| Owner/admin | Broad organization staff access | Broad organization staff access | All organization bookings | All active-org team records | Missing |
| Coach | Broad organization staff access; team management is separately constrained for some writes | Broad organization staff access | All organization bookings | All active-org teams/members readable | Missing |
| Player | Own assignments | Own records | All org bookings readable; own requests writable | All active-org teams/members readable | Missing |
| Parent | Assignment read is not included in final assignment policy | Linked-child logs/BP | All org bookings readable plus linked-child behavior | All active-org teams/members readable | Missing |
| Platform admin | Separate platform administration | Not implicitly an org owner | Not implicitly an org owner | Not implicitly an org owner | Missing |

Final organization role helpers are in
`supabase/migrations/20260714150000_org_ownership_and_admin_authorization.sql`:

- `sd_is_org_member` at line 61
- `sd_is_org_admin` at line 77
- `sd_is_org_staff` at line 111
- `sd_can_manage_team_player` at line 157

`sd_is_org_staff` includes active owner/admin/coach. This is a useful administrative
primitive, but it is too broad to express “coach sees assigned-team games only.”

Program assignment select policy at
`supabase/migrations/20260616000200_sd_core_org_scope.sql:264-271` permits the player or
organization staff. It does not include a linked parent. Daily logs, strength logs, tests,
and BP sessions include linked-parent paths in lines 286-324. The parent calendar therefore
has an internally inconsistent source set.

Team tables are created in
`supabase/migrations/20260710213000_platform_admin_and_teams.sql:34-76`.
`sd_team_members` uses `(org_id, player_id)` as its primary key and stores both coaches and
players through the same user-id-shaped field. That enforces at most one team membership
per user per organization and is insufficient for seasons, multiple squads, event rosters,
or game-specific roles.

**Evidence: Validated by direct code trace.**

## 8. Multi-organization isolation findings

### Strengths

- `MultiOrg/Core/AppState.swift:250` refreshes memberships and selected organization
  context.
- Organization switching refreshes context and clears organization-sensitive chat state
  around `MultiOrg/Core/AppState.swift:324-355`.
- Core database records increasingly carry `org_id` and final RLS helpers require active
  membership.
- Notification detail loading uses backend ownership checks rather than trusting push
  payload data.

### Gaps

1. **HIGH — no event isolation exists because no event domain exists.**
2. **HIGH — facility realtime is not filtered to the selected organization.**
   `MultiOrg/Core/SupabaseService.swift:76` subscribes to inserts on
   `sd_facility_bookings` without a Postgres `org_id` filter. RLS can authorize rows from
   every organization in which the user is active, so a user with two organizations can
   receive a pending booking callback from the non-selected organization.
3. **HIGH — facility booking reads are broader than player/parent privacy needs.**
   `supabase/migrations/20260616000100_sd_org_customization_admin.sql:169-177` allows every
   active organization member to read every organization booking, including title/notes.
4. **MEDIUM — player-centric service calls often rely on RLS rather than passing an
   explicit selected `org_id`.** This is safe only if identifiers are globally unique and
   all final policies are correct; it is not an adequate event-query contract.

**Evidence: Validated by direct code trace.**

Future event queries must require both selected `org_id` and an authorized event projection.
Realtime channels must use the same selected organization and game authorization.

## 9. Event lifecycle findings

No event lifecycle exists. The nearest comparison is facility booking:

- `pending`
- `approved`
- `denied`
- `cancelled`

Defined by `supabase/migrations/20260518001000_sd_facilities_booking.sql:25-42`.
Updates mutate the same booking record, which preserves booking identity, but there is no
status-history ledger, recurrence exception model, postponement, suspension, resumption,
completion/finalization, or reminder reconciliation.

Required future lifecycle:

```text
draft -> scheduled -> in_progress -> final
                   -> delayed
                   -> postponed -> scheduled
                   -> suspended -> in_progress -> final
                   -> cancelled
```

The event identity must remain stable through reschedule, postpone, suspension, and resume.
Lifecycle transitions should be server-side commands with expected-version checks and
append-only history.

**Evidence: Missing.**

## 10. Attendance and availability findings

There is no attendance, RSVP, player availability, arrival confirmation, or event roster
ledger. The schema itself acknowledges the gap:

`supabase/migrations/20260715060000_player_development_ai_foundation.sql:1133` marks
`consistency.attendance_rate` unavailable until an authoritative attendance ledger exists.

Team membership cannot substitute for event participation because a game roster may differ
from the team roster and must preserve historical membership after team changes.

Recommended records:

- `sd_event_participants` — event-scoped roster and visibility role
- `sd_event_availability` — invited/available/unavailable/tentative plus responder
- `sd_event_attendance` — arrived/late/absent/excused and recorder

**Evidence: Missing.**

## 11. Notification and deep-link findings

`MultiOrg/Core/NotificationCenterModels.swift` defines booking, program, message, testing,
announcement, and system categories. It has no event/game category. Its
`NotificationDestination` and route resolver at lines 456-501 have no event or game-detail
destination.

The notification system provides reusable foundations:

- server-created recipient rows
- APNs delivery
- idempotent delivery records
- organization membership checks
- authenticated notification detail retrieval
- safe routing after ownership resolution

Existing notification tests are extensive in
`supabase/functions/_shared/notification_center_test.ts`, but they validate current
categories and routes, not game behavior.

Missing game producers:

- game created/changed/canceled
- arrival/reminder
- availability request
- live game started
- control requested/transferred
- game suspended/resumed/final

A future deep link must resolve an opaque notification/event identifier on the backend,
recheck current organization, roster/team, parent-child, and event visibility, and only
then open the game workspace. Payload-provided `org_id` or `game_id` must not authorize it.

**Evidence: Current notification ownership pattern validated by direct code trace and
automated tests; game behavior missing.**

## 12. Facility integration findings

### Existing support

- Facilities: `supabase/migrations/20260518001000_sd_facilities_booking.sql:6-13`.
- Bookings: same migration lines 25-42.
- Organization backfill/index/policies:
  `supabase/migrations/20260616000100_sd_org_customization_admin.sql:153-215`.
- Approved overlap exclusion:
  `supabase/migrations/20260519000100_sd_facility_bookings_public_select.sql:25-29`.
- Cage 3 span overlap trigger:
  `supabase/migrations/20260520090000_sd_facility_cage3_split_and_span.sql:37-76`.
- Realtime publication:
  `supabase/migrations/20260519003000_sd_facility_bookings_realtime.sql`.

The database does have meaningful facility conflict protection for approved reservations,
including the split/full-cage special case. That is reusable.

### Gaps

- No canonical one-to-one or controlled one-to-many link from an event to a reservation.
- Canceling/rescheduling a conceptual game would not atomically reconcile a booking.
- A game and booking can be independently created for the same activity, producing duplicate
  calendar items.
- Booking visibility is organization-wide.
- Facility reservation status does not drive an event lifecycle.

The future server command that creates or reschedules a home game should update the event
and its reservation in one transaction. A conflict must reject the whole operation.

**Evidence: Validated by direct code trace.**

## 13. Canonical game-detail readiness

There is no canonical game-detail route or workspace. Existing selected-player detail tabs
do not establish a game identity and cannot become the authority for ten-device live state.

The future route should be conceptually:

```text
organization/{org_id}/game/{game_id}
```

but authorization must come from a backend lookup, not from trusting route parameters.
One game-detail workspace should host:

- schedule/opponent/location
- roster, availability, and attendance
- lineup and pitching plan
- live score/viewer state
- play-by-play
- facility status
- film/attachments
- postgame finalization and corrections

**Evidence: Missing.**

## 14. Existing realtime architecture

Supabase Realtime is already used for:

- facility booking inserts in `MultiOrg/Core/SupabaseService.swift:67-135`
- organization-filtered chat changes in `MultiOrg/Core/SupabaseService.swift:158-211`

This proves the client can subscribe to Postgres changes, but it does not provide a live
game protocol. Missing pieces include:

- game-scoped authorization and subscription
- ordered authoritative game versions
- idempotent score event IDs
- scorer presence/lease state
- reconnect catch-up
- snapshot plus event replay
- stale-write rejection
- correction/finalization semantics

Realtime presence alone must not decide who may score. Presence is advisory and can split
during network partitions.

**Evidence: Existing transport validated by direct code trace; scorekeeping behavior
missing.**

## 15. Single-scorekeeper lease feasibility

The existing stack can support a secure lease, but no implementation currently exists.
The lease must be a server-authoritative database record, not a Swift boolean or Realtime
presence flag.

Recommended `sd_game_scorekeeping_leases` shape:

```text
game_id primary key
active_user_id
active_device_id
control_token_hash
acquired_at
heartbeat_at
expires_at
lease_version
status
```

Every mutation should include:

```text
game_id
device_id
control_token
expected_game_version
event_id
```

The server must reject when the device/user/token does not own a live lease, the lease
expired, permission is missing, game version is stale, event ID was committed, game is
suspended/final, or another device acquired control.

**Evidence: Missing, but feasible with current Postgres/Supabase foundation.**

## 16. Recommended multi-device architecture

### Write path

1. Client constructs a score command with a random `event_id`, expected game version, device
   ID, and lease token.
2. A security-definer RPC authenticates the actor and derives selected organization access.
3. The transaction locks the game and lease rows using `SELECT ... FOR UPDATE`.
4. It verifies event/game organization, role/team/game permission, device binding, token
   hash, lease expiration, game lifecycle, and expected version.
5. It checks a unique `(game_id, event_id)` constraint for idempotency.
6. It appends one immutable scoring event.
7. It derives and writes the new game snapshot and increments `game_version`.
8. It appends a scoring audit record.
9. It commits; Realtime then publishes committed rows.

The entire validation and write must occur in one database transaction. Client-side
prechecks improve UX but provide no authority.

### Read path

Viewers load an authorized snapshot and the latest version, subscribe to committed game
events/snapshot/lease changes, and reload if a version gap is observed.

```text
Scorer submits event
-> server validates lease and expected version
-> event and snapshot commit
-> version increments
-> subscribed viewers update
```

Incomplete play construction, pointer movement, and local pending actions must not be
broadcast as official state.

### Offline behavior

The active scorer may queue local commands during a brief disconnect, but cannot treat them
as committed. On reconnect, each command must pass the same lease and version transaction.
If the lease expired or another device took over, queued commands are rejected and require
explicit reconciliation; they must never overwrite newer state.

## 17. Authorization model

Recommended event/game permissions:

```text
can_view_game
can_view_live_score
can_start_scorekeeping
can_request_scorekeeping_control
can_force_scorekeeping_takeover
can_edit_completed_game
can_finalize_game
```

They should be derived server-side from:

- authenticated user
- active membership in the game organization
- event participant/team assignment
- linked parent-child relationship
- organization team policy
- explicit game staff assignment
- game lifecycle

Suggested baseline:

| Actor | View game/live | Start/request control | Force takeover | Finalize/edit final |
|---|---|---|---|---|
| Owner/admin | Yes within org | Yes | Yes | Yes |
| Assigned coach/game staff | Yes | Yes | Policy-controlled | Policy-controlled |
| Unassigned coach | No unless org policy explicitly grants view | No | No | No |
| Rostered player | Yes | No | No | No |
| Linked parent | Child-safe view only | No | No | No |
| Platform admin | No implicit game access | No | No | No |

Current `sd_is_org_member`, `sd_is_org_admin`, `sd_is_org_staff`, and
`sd_can_manage_team_player` are reusable primitives, but a game-specific authorization
function is required. Broad `sd_is_org_staff` must not be the only game read/write gate.

## 18. Control transfer and recovery model

Connected device states:

```text
Live Scorekeeper
Live Viewer
Requesting Control
Disconnected
```

### Acquire

An eligible device calls a server RPC. The RPC locks the game/lease, verifies permission,
and creates or replaces only an expired lease. It returns the plaintext control token once;
the database stores only its hash.

### Explicit transfer

In one transaction:

1. Lock game and lease.
2. Confirm current token/device and no unresolved local play.
3. Verify the destination user/device is eligible and connected.
4. Save authoritative state.
5. Revoke the old token by replacing its hash and incrementing lease version.
6. Bind the new user/device and expiration.
7. Add an audit entry.
8. Commit and publish lease change.

The old device immediately becomes a viewer. Any stale command carries the old token or
version and is rejected.

### Heartbeat and stale recovery

A reasonable starting point is heartbeat every 5–10 seconds and lease expiry around
30 seconds, adjusted after background/network testing.

- Backgrounding should stop scoring controls and attempt a final heartbeat/release.
- Brief loss may retain UI locally, but no action is authoritative until accepted.
- App termination/device sleep eventually expires the lease.
- Reconnect before expiry may renew only with the same valid token/device.
- After takeover, the original device must reload as a viewer.
- Realtime disconnect does not itself grant or revoke authority; the database lease does.
- Network retries use the same `event_id`; unique constraints make accepted writes
  idempotent.

No two devices can both acquire control because acquisition and transfer lock one lease row
inside one transaction.

## 19. Audit-log requirements

`sd_platform_audit_logs` in
`supabase/migrations/20260710213000_platform_admin_and_teams.sql:19-32` provides a useful
administrative convention, and financial/notification code also uses append-only audit
patterns. It is not a scoring ledger.

Future audit records must include:

```text
organization
game
user
device
timestamp
game version
action
previous value
new value
reason
```

Required actions include scorekeeping start, acquire/request/transfer/takeover, disconnect,
lease expiry, accepted/rejected scoring actions, corrections, suspension, and finalization.

Use two related but distinct immutable structures:

1. **Scoring event ledger** — domain events needed to reconstruct game state.
2. **Security/operations audit** — control, rejection, permission, and administrative
   events.

**Evidence: Existing audit convention validated by direct code trace; game audit missing.**

## 20. Test and build results

### Coverage inventory

| Behavior | Evidence |
|---|---|
| Organization role selection/switching | Automated tests in `MultiOrgTests/OrganizationAuthorizationTests.swift` |
| Current notifications and delivery idempotency | Automated Deno tests in `supabase/functions/_shared/notification_center_test.ts` |
| Current chat notification organization checks | Automated Deno tests in the same suite |
| Event queries/creation/edit/cancel/reschedule | Missing |
| Parent event visibility | Missing |
| Facility-to-event reconciliation | Missing |
| Game deep links | Missing |
| Game realtime | Missing |
| Scorer lease/stale-write protection | Missing |
| Scoring event idempotency | Missing |
| Scoring audit | Missing |

### Commands/results

- Repository and schema/code searches: **completed**.
- `xcodebuild -project MultiOrg.xcodeproj -list`: **not completed**; Xcode remained blocked
  in project/package resolution and was interrupted after the bounded wait.
- `xcodebuild ... -showdestinations -disableAutomaticPackageResolution`: **not completed**
  for the same reason and was interrupted.
- Deno tests/type-check: **not run** because `deno` is unavailable in the environment.
- Simulator role flows: **not run**; they require a functioning build and authenticated
  organization data.
- `git diff --check`: run after report creation; result recorded in the completion response.

No behavior is marked validated merely because a type or policy exists.

## 21. Scenario-by-scenario readiness table

| # | Scenario | Current support | Evidence | Gap | Severity | Required future change |
|---:|---|---|---|---|---|---|
| 1 | Owner creates game; correct team calendars update | None | Missing | No event/game/create API/team calendar | BLOCKER | Canonical event/game transaction and authorized calendar projection |
| 2 | Coach sees assigned-team games only | None | Direct trace of broad `sd_is_org_staff` and team helpers | No game policy; current staff reads are broader | HIGH | Game permission function tied to active team/game assignment |
| 3 | Player sees game only when rostered/assigned/team member | None | Missing | No event participant or game roster | HIGH | Event participants plus player-safe RLS |
| 4 | Parent sees linked child game without unrelated details | None | Direct trace; parent assignment calendar already inconsistent | No event projection; current org booking reads are broad | BLOCKER | Child-safe event projection and field-level response |
| 5 | Multi-org switch has no calendar leakage | Partial foundation | Direct trace of `AppState` switch; facility realtime lacks selected-org filter | No canonical org-scoped feed; realtime context risk | HIGH | Explicit org query/filter and teardown/reload on switch |
| 6 | Direct event deep link cannot bypass auth | None | Current notification ownership pattern exists; no event route | No event resolver | BLOCKER | Backend opaque-ID resolution and current authorization check |
| 7 | Reschedule updates existing event | None | Missing | No persistent event identity/version/history | HIGH | Versioned lifecycle RPC updating one event |
| 8 | Cancel suppresses reminders | None | Missing | No event reminders or cancellation producer | HIGH | Transactional cancel plus notification cancellation ledger |
| 9 | Move/cancel home game updates facility reservation | None | Facility conflict primitives traced | No event-booking link/transaction | BLOCKER | Atomic event/reservation command |
| 10 | Postponed game preserves roster/attendance/identity | None | Missing | No lifecycle, roster, attendance | HIGH | Stable game ID and participant/attendance records |
| 11 | Suspended game resumes from same record | None | Missing | No suspended state or snapshot | BLOCKER | Game lifecycle plus immutable ledger/snapshot |
| 12 | Final game remains in history | None | Missing | No game/final state/history | HIGH | Finalization command and durable read model |
| 13 | Ten devices open; only one mutates | None | Realtime transport only | No lease/token/version/write RPC | BLOCKER | Transactional device-bound scorer lease |
| 14 | Viewers receive committed updates | None | Existing Postgres Realtime direct trace | No game publication/version catch-up | HIGH | Committed event/snapshot subscriptions |
| 15 | Scorekeeping transfers devices | None | Missing | No control state | BLOCKER | Atomic transfer RPC and audit |
| 16 | Original device immediately read-only | None | Missing | No token revocation/lease subscription | BLOCKER | Rotate token/hash and publish lease version |
| 17 | Original device stale write rejected | None | Missing | No expected version/device/token check | BLOCKER | Locked command RPC with stale rejection |
| 18 | Crashed scorer lease expires | None | Missing | No heartbeat/expiry | BLOCKER | Server-time lease and expiry recovery |
| 19 | Authorized device safely takes over | None | Missing | No eligibility/takeover transaction | BLOCKER | Expired/forced takeover RPC |
| 20 | Parent watches but cannot request control | None | Parent relationship helper exists for other domains | No game permissions/control UI | HIGH | Separate view and control permissions |
| 21 | Unauthorized coach cannot open other team live game | None | Current staff helper is broad | No assigned-team game RLS | BLOCKER | Game-specific read/control authorization |
| 22 | Correction reaches all viewers | None | Realtime transport only | No correction event or ordered snapshot | HIGH | Immutable correction event and versioned derived state |
| 23 | Duplicate finalization rejected | None | Missing | No finalization command/idempotency | BLOCKER | Locked lifecycle command and unique idempotency key |
| 24 | Suspended game resumes on another device | None | Missing | Neither lifecycle nor control transfer exists | BLOCKER | Resume command plus fresh authorized lease |

## 22. Blocking issues

Implementation must not begin with a scorekeeping UI layered over BP sessions or facility
bookings. Resolve these in order:

1. **Canonical event/game schema and identity.**
2. **Event participants, roster, availability, attendance, and privacy-safe projections.**
3. **Game-specific authorization based on selected organization and team/game assignment.**
4. **Unified calendar query and organization-filtered realtime.**
5. **Atomic event/facility lifecycle reconciliation.**
6. **Canonical game-detail route with backend authorization.**
7. **Immutable scoring event ledger and versioned derived snapshot.**
8. **Device-bound scorer lease and transactional mutation RPC.**
9. **Game notifications, deep links, audit, corrections, suspension, and finalization.**

## 23. Recommended implementation sequence

### Phase 1 — Canonical event and game lifecycle

Add events, games, lifecycle history, timezone semantics, recurrence identity, opponents,
seasons, and atomic create/update/cancel/postpone/suspend/finalize commands.

### Phase 2 — Participants and role-safe calendar integration

Add event roster, availability, attendance, parent-safe projection, assigned-team coach
rules, organization-filtered subscriptions, and one event feed used by role-specific views.

### Phase 3 — Facility and notification reconciliation

Atomically link home events to reservations. Add reminder scheduling/cancellation and safe
event deep-link resolution.

### Phase 4 — Canonical game-detail workspace

Build one game identity and detail surface before live scoring. Include schedule, roster,
availability, facility, lineup, and status.

### Phase 5 — Ruleset and immutable scoring ledger

Define baseball state invariants, command types, event schema, deterministic reducer,
versioned snapshot, corrections, suspension, and finalization.

### Phase 6 — Single-scorekeeper lease and realtime viewers

Add device registration, lease/heartbeat/acquire/transfer/takeover RPCs, stale-write and
idempotency controls, committed event publication, and version-gap recovery.

### Phase 7 — Live-scoring interface

Expose controls only after the server protocol is proven with concurrency and failure tests.

### Phase 8 — Statistics, film, and postgame workflows

Derive official statistics, link film, support review/correction, and publish final results.

### Phase 9 — Production validation

Run multi-device network-partition, backgrounding, crash, role, tenant, replay, correction,
and finalization test matrices before release.

## 24. Final readiness verdict

## NOT READY

Home Plate has reusable organization, team, facility, notification, realtime, and audit
primitives, but the foundations that make live scoring safe do not exist. The minimum work
required to become ready is:

1. Introduce a canonical event/game model with stable lifecycle identity.
2. Add event participants, attendance, and role-safe organization/team visibility.
3. Feed every calendar from an authorized canonical event projection.
4. Link game lifecycle and facility reservations transactionally.
5. Establish one authorized game-detail route.
6. Implement and test an immutable, versioned score ledger.
7. Implement a server-authoritative, device-bound scorer lease with locked, idempotent,
   stale-write-safe mutation RPCs.

Only after those foundations pass authorization, isolation, lifecycle, and concurrency
tests should the scorekeeping interface be implemented.
