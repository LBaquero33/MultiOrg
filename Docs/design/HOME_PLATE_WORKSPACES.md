# HOME PLATE — WORKSPACES

**Status:** Stage 2 spec — approved direction, pre‑implementation.
**Absolute path:** `/Users/lb33/Documents/DHD-Self-Development-iOS-multiorg/Docs/design/HOME_PLATE_WORKSPACES.md`
**Companions:** `HOME_PLATE_OS.md` (nav model), `HOME_PLATE_DESIGN_SYSTEM.md`, `HOME_PLATE_COMPONENT_LIBRARY.md`.

Each workspace is specified as: **Purpose · Target roles · Navigation · Primary questions · Core cards · Key actions · iPhone · iPad · macOS.** Present‑tense = maps to existing screens; *(future)* = adopts the system from first build. Visibility is always role‑ and entitlement‑gated (reuse `activeOrgSettings.feature()`, `canAdminActiveOrg`, `isPlatformAdmin`, `needsAccess`). Layout is presentation only — **routing/permissions unchanged**.

---

## Overview
- **Purpose:** orient; surface urgent items; fast actions.
- **Roles:** all. **Nav:** primary sidebar item / first tab (owner/admin).
- **Primary questions:** What needs me now? What's happening today? What changed?
- **Core cards:** Attention row (0–3), Today/Upcoming, Messages, Notifications, Payments (role‑relevant), Player progress (player/parent), Org status (owner/admin).
- **Key actions:** jump to the flagged item; one contextual primary action.
- **iPhone:** stacked cards under `HPWorkspaceHeader`. **iPad:** 2‑col. **macOS:** dashboard grid.
- Today it's implicit (role home screens); Overview formalizes it.

## Development
- **Purpose:** develop players. **Roles:** player, coach, parent(view).
- **Maps to:** `SDPlayerTodayView`, `SDPlayerTrendsView`, `SDPlayerTestingView`, `CoachProgramsView`, `ProgramTemplateEditorView`, coach player views.
- **Primary questions:** What do I do today? Am I improving? What's assigned?
- **Core cards:** Today's program (`HPProgramDayCard`), Strength logger (`HPExerciseLogger`), Improvement (`HPMetricCard` w/ deltas), Trends (`HPTrendChart`), Testing (`HPTestingEntryRow`), Self‑assessment, Coach notes, *(future)* AI summary.
- **Key actions (player):** log today → **Submit day** (single gold primary). **(coach):** assign/edit program, add testing.
- **iPhone:** "Today" tab, drill‑in; progressive disclosure (disclosure groups today → cards). **iPad:** program left / logger right. **macOS:** coach‑centric roster→program detail.

## Analytics
- **Purpose:** understand performance + business. **Roles:** coach, owner/admin.
- **Maps to:** analysis views + business analytics (website parity: program profitability, revenue by service/team).
- **Primary questions:** What's trending? What's profitable? Where's engagement?
- **Core cards:** trend charts (`HPChart`), distributions (histograms — exit velo), program profitability, retention/utilization tiles.
- **Key actions:** change range (`HPDateRangeControl`), filter, export *(future)*.

## AI *(future)*
- **Purpose:** evidence‑backed development intelligence. **Roles:** coach, player.
- **Core cards:** `HPAICard` (facts/interpretation/recommendation/confidence/missing‑data), `HPEvidenceList`, `HPConfidenceMeter`, coach‑approval banner.
- **Accent:** controlled indigo. **Rule:** never magical; always shows evidence; coach approval required.

## Game Day *(future)*
- **Purpose:** live scoring + box score + film + CommandIQ. **Roles:** coach(score), player/parent(view).
- **Core cards:** `HPScoreboard`, `HPBaseDiamond`, `HPLineupList`, `HPPlayByPlayRow`, `HPBoxScoreTable`, film/CommandIQ links.
- **Tone:** broadcast contrast, large numerals. **Arch:** offline‑first event ledger (immediate local echo → later sync).

## Recruiting *(future)*
- **Purpose:** college‑ready profile + verified metrics + film. **Roles:** player, parent, coach.
- **Core cards:** `HPRecruitingProfileHeader`, `HPVerifiedMetric` + `HPMetricSourceLabel`, `HPFilmReel`, `HPCoachEvaluationCard`, `HPRecruitingSnapshotCard` (consented/revocable), SportsForce connection.
- **Tone:** portfolio‑grade, credible.

## Communication
- **Purpose:** DMs, announcements, notifications. **Roles:** all.
- **Maps to:** `ChatChannelListView`/`ChatThreadView`/`ChatCreateView`, `NotificationCenterView`, announcements.
- **Core cards:** conversations (`HPConversationRow`), announcements, notification center (`HPNotificationCenter`), unread state, audience tools (owner/admin).
- **Key actions:** new message, new announcement (gated). **Rule:** do not rebuild DMs — integrate presentation only; no duplicate local/remote alerts (handoff §9C, §6).
- **iPhone:** "Chat" tab + bell. **iPad/macOS:** list + thread split.

## Scheduling
- **Purpose:** lessons, bookings, team events, calendar. **Roles:** all.
- **Maps to:** `SDPlayerCalendarView`, `CoachFacilitiesView`/`FacilitiesDayTimelineView`, booking sheets, `ParentChildCalendarView`, `DHDMonthGridView`.
- **Core cards:** calendar (month/day), bookings, availability, approvals (coach/admin), conflicts.
- **Key actions:** new booking, approve/deny. **iPad/macOS:** month grid + day timeline split.

## Finance — **pilot workspace**
- **Purpose:** run the business (Stripe‑level). **Roles:** owner/admin (+ platform support, explicit).
- **Maps to:** `FinanceDashboardView` (+ `FinanceOverviewView`, `RecentPaymentsView`, `FinancePaymentRequestsView`, `ExpenseManagementView`, `FinanceRefundsView`, `FinanceDateRangePicker`).
- **Primary questions:** How much are we making/keeping? Who owes us? What did we spend?
- **Core cards:** `HPSupportModeBanner` (when support), `HPDateRangeControl`, overview metric grid (gross/net/outstanding/expenses/profit — token colors), recent payments (`HPPaymentRow`), payment requests (filterable), expenses (search+filter+editor), refunds.
- **Key actions:** change range; create expense; (support: read/limited create per authorization). **Discipline:** precise, stable, no decoration.
- **iPhone:** stacked cards. **iPad:** 2‑col metric grid + lists. **macOS:** dense grid + tables.
- **Do not change backend/reconciliation/authorization** — reskin only.

## Facilities
- **Purpose:** locations/cages/fields/availability. **Roles:** coach, owner/admin.
- **Maps to:** `CoachFacilitiesView`, `SDPlayerFacilitiesView`, `SDParentFacilitiesView`, booking sheets, `FacilityDaySheet`.
- **Core cards:** locations, resources, availability timeline, bookings.
- **iPad/macOS:** resource list + day timeline.

## Organization
- **Purpose:** org management/staff/branding/memberships. **Roles:** owner/admin, platform admin.
- **Maps to:** `OrgAdminConsoleView`, `PlatformAdminDashboardView`.
- **Core cards:** org settings/branding, staff & roles, memberships, features/terminology, announcements; platform: org creation + explicit support workflows.
- **Rule:** platform‑admin support stays visually explicit (support ≠ ownership); no implicit Stripe authority.

## Settings
- **Purpose:** account/preferences/subscription. **Roles:** all.
- **Maps to:** `AccountView`, `PlayerSubscriptionPaywall`, `SDParentBillingView`, `ParentRequestPanels`.
- **Core cards:** profile, org switcher, subscription/billing (StoreKit — presentation only), notifications prefs, sign out.
- **Rule:** do not alter StoreKit/subscription verification — reskin the paywall/billing surfaces only.

---

## Role → workspace visibility (default)

| Workspace | Player | Parent | Coach | Owner/Admin | Platform admin |
| --- | :--: | :--: | :--: | :--: | :--: |
| Overview | ● | ● | ● | ● | ● |
| Development | ● | view | ● | ● | – |
| Analytics | – | – | ● | ● | – |
| Communication | ● | ● | ● | ● | support |
| Scheduling | ● | ● | ● | ● | – |
| Finance | – | – | – | ● | support |
| Facilities | view | view | ● | ● | – |
| Organization | – | – | admin | ● | ● |
| Settings | ● | ● | ● | ● | ● |
| Game Day / AI / Recruiting *(future)* | preview | preview | preview | preview | – |

● full · view = read · support = explicit platform‑support mode · – hidden. Gating reuses existing `appState` authorization + `feature()` flags; **inaccessible/unpreviewed workspaces are not shown** (handoff §13).

## iPhone tab mapping (approved, ≤5 hard cap — decision 2)

| Role | Tabs (≤5) | Directory (`HPWorkspaceDirectory`) |
| --- | --- | --- |
| Player | Today · Calendar · Trends · Chat · More | Testing, Analysis, Facilities, Account |
| Coach | Players · Schedule · Chat · Analytics · More | Teams, Programs, Facilities, Org Admin, Platform, Account |
| Parent | Children · Schedule · Chat · More | Payments, Account |
| Owner/Admin | Overview · Finance · Communication · Organization · More | Facilities, Scheduling, Account |
