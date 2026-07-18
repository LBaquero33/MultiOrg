# Phase 12Y Today architecture

## Inspection and reuse

Today remains an interpretation layer. It does not persist missions, attention
items, summary cards, or workflow state.

| Today concern | Authoritative Phase 12 source | Integration |
| --- | --- | --- |
| Organization role and scope | `sd_org_memberships`, `AppState.activeOrgMembership` | Reused; the requested role is never trusted |
| Season and selected team | Phase 12A team context and capability resolver | Reused; one-team coaches resolve automatically and multi-team selection is validated |
| Schedule and conflicts | Phase 12B `sd_team_events` / `team-scheduling` | Aggregated and linked to the existing Schedule and Event Operations views |
| Availability and attendance | Phase 12C event operations | Aggregated; mutations continue through the idempotent event-operations commands |
| Practice readiness | Phase 12D practice plans | Aggregated; editing, publishing, and execution remain in Practice Planner |
| Game readiness and assignments | Phase 12E game plans | Aggregated; Player/Parent receive only their assignment, while team EH counts stay staff-only |
| Communication | Phase 12F announcements, recipients, and delivery receipts | Aggregated; authoring and acknowledgment remain in Communication |
| Registration | Phase 12G applications and requirements | Aggregated; applications and review remain in Registration |
| Finance | Phase 12H/I invoices and finance dashboard | Aggregated only for authorized payer or owner/admin scope; detailed work remains in Finance |
| Analytics | Phase 12J organization analytics | Intentionally kept separate from Today except truthful `as_of` summaries |
| Player program work | Existing Player Today assignment, strength, BP, and daily-log services | Intentionally kept separate because it is personal program execution, not baseball operations aggregation |

The legacy Coach Today performed sequential schedule, operation, practice, and
game calls and derived priority in the view. Player and Parent independently
reconstructed similar mission rules. Phase 12Y centralizes role filtering,
ordering, attention, and primary-action resolution in one authenticated
`today` Edge Function plus shared Swift domain types. Existing detail calls are
retained only to open the established workflow views and perform existing
mutations.

## Aggregate contract

Request context includes organization, optional season/team/child, local date,
IANA timezone, and a client context token. The function authenticates the user,
derives the active organization role, validates team/child scope, obtains team
capabilities from the existing resolver, and returns:

- role-redacted context;
- deterministic missions and attention;
- truthful summaries with `as_of`;
- a capability-aware primary action;
- independent scheduling, operations, practice, game, communication,
  registration, finance, and analytics service states;
- `generated_at`, `as_of`, and the authoritative context token.

No migration or duplicate Today table is introduced. The function must be
deployed after the existing Phase 12A–12J migrations and functions. Until it is
deployed, the shared client error classifier presents the controlled temporary
unavailability state; cancellation and superseded context responses remain
silent.

## Deterministic behavior

Mission order is active, arrival window, next today, later today, completed
requiring review, then completed without required action. Arrival time wins
within a tier, then start time, then stable ID. Cancelled/postponed events never
become active or startable.

Attention order is urgent, important, informational, then due time and stable
ID. Each item is filtered by organization, season, team/household, role, and
required capability. Ordinary coaches never receive organization financial
attention.

The primary-action resolver checks event and operation completion first,
unresolved attendance/availability next, then practice/game plan readiness,
and finally check-in. Player and Parent actions are separately redacted and
never include staff operational controls. Owner/Admin actions link to existing
Event Operations, Registration/Organization, Finance, and Communication
workspaces.

## Context and availability

Swift request guards bind publication to organization authorization, season,
team/child, local date, timezone, and request token. Cancellation, older tokens,
or a changed context cannot publish data or alerts. Returning successful
sections stay usable when another section is stale or unavailable; an
unavailable schedule never renders as an authoritative empty schedule.

Approved navigation is unchanged: Player has Today / Calendar / Trends / Chat /
More; Coach iPhone has Today / Team / Schedule / More; Owner has Overview /
Finance / Chat / Organization / More. Owner Overview now explicitly uses
organization-wide Today content, while Coach Today remains selected-team
operational.
