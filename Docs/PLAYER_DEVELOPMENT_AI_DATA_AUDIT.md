# Player Development AI data audit

Audit date: 2026-07-15. Source of truth: repository migrations through `20260715050000_notification_direct_messages_integration.sql` and the current Swift source. This document describes what exists; it does not imply that the Phase 11A migration has been applied.

## Existing identity and organization model

- `profiles`: application profile keyed by the authenticated user UUID. The Swift `Profile` model reads `id`, `role`, `full_name`, and `avatar_path`. The profile role is legacy/global context and is not organization authorization.
- `sd_orgs`: organization identity (`id`, `slug`, `name`, status/plan/billing metadata added later).
- `sd_org_memberships`: authoritative organization/user relationship. Current supported roles are owner, admin, coach, player, and parent; staff access requires status `active` and role owner/admin/coach.
- `sd_teams`: organization-scoped team metadata.
- `sd_team_members`: one organization/team assignment per `player_id`. Existing authorization also uses this column for the coach's team lookup.
- `sd_org_settings.team_policy.restrictCoachActionsToTeam`: controls whether coaches are restricted to their team. `sd_can_manage_team_player(org, player)` is the final current helper.
- `sd_parent_child_links`: parent/player relationship. It is deliberately not used to grant Phase 11A access.

Platform administration is separate. `sd_platform_admins` and platform-support payment access do not create a staff membership and do not authorize Phase 11A.

## Existing longitudinal sources

| Source | Important columns | Current unit/shape | Organization/player link | Phase 11A use |
|---|---|---|---|---|
| `sd_testing_entries` | `entry_date`, height/weight, squat/bench/deadlift 1RM, max/average exit velocity, hip/shoulder differences, notes | Numeric columns; inches, pounds, mph, degrees by app convention | `org_id`, `player_id` | Direct adapter; notes are not copied into generated content |
| `sd_daily_logs` | `log_date`, `feel`, goal/process booleans, comments and reflection text | Integer 1–10, booleans, text | `org_id`, `player_id` | Only process-adherence counts in 11A; missing logs are not treated as failures |
| `sd_program_templates` / `sd_program_days` | template name/kind/weeks/weekdays; exercise JSON | Mixed relational/JSON | template `org_id`; days through template | Context only |
| `sd_program_assignments` | template, start/end, coach, notes | Dates/timestamps/text | `org_id`, `player_id` | Assignment coverage/context only |
| `sd_strength_logs` | exercise, sets completed, per-set weight JSON, notes | Exercise name plus JSON weights | `org_id`, `player_id` | Audited, but not normalized into trends in 11A because exercise/protocol/unit equivalence is not authoritative |
| `sd_bp_sessions` | date, source, reps type | source is Rapsodo, HitTrax, or TrackMan | `org_id`, `player_id` | Session context plus event aggregation |
| `sd_bp_events` | exit velocity, distance, launch angle, strike coordinates, raw JSON | Numeric event columns plus provider payload | player/org through `session_id` | Session maximum and average exit velocity only |
| `sd_player_onboarding` | improve focus/plan/daily goals | free text | player; later org scoped | Not interpreted by 11A; it may become approved player context later |
| facilities/bookings/calendar | times, status, facility/player | scheduling records | organization/player | Not attendance. A booking is not proof of attendance. |

Swift reads these through `SupabaseService`: `listDailyLogs`, `listTestingEntries`, `listBPSessions`/`fetchBPEvents`, assignment/template methods, roster methods, and coach testing/program screens. Existing analysis views calculate client-side charts from testing/BP data; there was no persisted report or evidence object.

## Existing import paths

- `MultiOrg/Core/CSV.swift` maps Rapsodo, HitTrax, and TrackMan CSV columns into BP session/event fields.
- `supabase/functions/coach_import_bp/index.ts` is a legacy importer. It checks a global profile coach role rather than current organization staff/player scope, does not accept authoritative `org_id`, and references a pre-multiorg conflict key. Phase 11A does not extend or invoke it.
- Writable compatibility views bridge older Shiny names such as `dev_entries` and `bp_sessions` to current tables. They overlap the canonical source tables and must not be treated as independent evidence.

## Authorization and RLS discovered

The hardened helpers in `20260714150000_org_ownership_and_admin_authorization.sql` are:

- `sd_is_org_member`: active organization membership.
- `sd_is_org_admin`: active owner/admin.
- `sd_is_org_staff`: active owner/admin/coach.
- `sd_can_manage_team_player`: owner/admin have organization scope; a coach follows the organization team policy.

They are `SECURITY DEFINER`, use an empty search path, schema-qualify sensitive objects, and are executable only by `authenticated`. Existing source RLS also permits players and linked parents to read some raw data for current product screens. Phase 11A does not broaden those source policies; its new report/alert/observation objects are staff-only.

## Data quality and freshness concerns

- Testing units are app conventions, not stored alongside each value. The adapter assigns documented units and the normalized observation layer retains explicit units.
- Device/provider semantics can differ. Device names are source metadata, never canonical metric identity.
- `sd_testing_entries` has one row per organization/player/date, so multiple protocols on the same day cannot be distinguished.
- BP events may contain sparse/null values and imported raw JSON. Only finite supported numeric values are used.
- Daily-log absence is unknown, not a missed session.
- Program assignment is not program completion. There is no authoritative completion ledger.
- Booking is not attendance. There is no authoritative attendance table.
- No dedicated coach-note, coach-interaction, player-tag, game-statistics, pitching-observation, workload, film, recruiting, or CommandIQ ledger was found.
- No source record has a common metric-definition foreign key today.
- Free-text notes can contain private content. Phase 11A does not fetch them for evidence generation.
- Existing source tables are not bitemporal. The cutoff excludes records created after it, but cannot reconstruct a pre-cutoff value after an older row is edited. Persisted report evidence solves forward auditability; full source revision history is a future data-foundation need.

## Reuse versus additive schema

Reused directly: profiles, organizations, memberships, teams/team policy, testing, daily logs, program assignments, BP sessions/events, existing hardened authorization helpers, authenticated Edge Function conventions, and current Swift coach navigation/components.

Additive objects are required for:

- provider-neutral metric definitions;
- future import-job audit records;
- normalized observations for future providers;
- persisted reports with queryable lifecycle fields;
- historical evidence snapshots linked to reports;
- immutable report review history;
- deduplicated alerts, alert evidence, and alert lifecycle history.

No existing source table is redesigned or bulk-copied. Existing testing and BP records are adapted at evidence-build time.
