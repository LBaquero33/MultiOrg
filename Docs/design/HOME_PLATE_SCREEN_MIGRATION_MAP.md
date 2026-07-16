# HOME PLATE — SCREEN MIGRATION MAP

**Status:** Universal Implementation Kit — Stage 6. Complete inventory of every production screen and its assigned universal template.
**Absolute path:** `/Users/lb33/Documents/HomePlate-design/Docs/design/HOME_PLATE_SCREEN_MIGRATION_MAP.md`
**Companions:** `HOME_PLATE_AI_UI_IMPLEMENTATION_GUIDE.md` (binding) · `HOME_PLATE_SCREEN_TEMPLATES.md` · `HOME_PLATE_UI_CONTRACT.yaml`.

Inventory taken from the real tree at commit `b97c1b4` (`design/home-plate-os`): **64 Swift files** under `MultiOrg/Features/**` + `MultiOrg/App/**` → **51 screens/sheets**, 6 shared presentation components, 3 non-UI helpers, 2 ViewModels, 2 app-shell files.

**Legend**
`st` = `@State` count · `sb` = Supabase/appState call sites · **Risk**: 🟢 low (<10 st, pure presentation) · 🟡 medium · 🔴 high (large + heavy logic — manifest discipline critical).
**Status**: `untouched` · `foundation-only` (gets HP look via Layer A alias, no template migration yet) · `pilot complete` · `migrated`.
**HP components** = the template's required set unless a screen needs extras.

---

## Summary

| Metric | Count |
| --- | --- |
| Total Swift files inventoried (Features + App) | 64 |
| Migratable screens / sheets | 51 |
| Shared presentation components (migrate once, benefit many) | 6 |
| ViewModels / helpers / app shell (**do not restyle**) | 7 |
| Pilot complete | 3 (`SDPlayerTodayView`, `SDPlayerBPDaySection`, `FinanceDashboardView` + finance subviews) |
| Files reached by Layer A alias (immediate HP look) | **36** |
| Screens blocked on missing components | 0 today (Game Day / AI / Recruiting don't exist yet) |

---

## PLAYER (iPhone-first — Priority 1)

| Screen · file | Purpose | Workspace | Template | HP components | Protected | Responsive | Risk | Pri | Status |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| **SDPlayerTodayView** `MultiOrg/Features/Player/SDPlayerTodayView.swift` | Today's program + logging + self-assessment | Development | `program_execution` | Header/Card/MetricCard/ProgressIndicator/FormField/Button/StatusBadge/Toast | 25 st · 19 sb · `.task`/`.onChange(date)`/`.alert` · submit-only persistence | iPhone stack; iPad same | 🔴 | — | **pilot complete** |
| **SDPlayerBPDaySection** `MultiOrg/Features/Player/SDPlayerBPDaySection.swift` | BP session + CSV import (embedded) | Development | `program_execution` (section) | Card/SegmentedControl/Button/StatTile/Toast | 10 st · 14 sb · `.task`/3×`.onChange`/`.fileImporter`/`.alert` | inherits parent | 🔴 | — | **pilot complete** |
| **PlayerHomeView** `MultiOrg/Features/Home/PlayerHomeView.swift` | Player tab shell (≤5 tabs) | — (shell) | *nav shell* — `HPWorkspaceDirectory` for overflow | — | 1 st · 0 sb · tab structure | tabs → sidebar on iPad | 🟢 | 1 | untouched |
| **SDPlayerTrendsView** `MultiOrg/Features/Player/SDPlayerTrendsView.swift` | Improvement trends | Analytics | `analytics` | Chart/MetricCard/SegmentedControl/Table | 3 st · 3 sb | 2→3-col metrics | 🟢 | 1 | untouched |
| **SDPlayerTestingView** `MultiOrg/Features/Player/SDPlayerTestingView.swift` | Testing entries + add | Development | `list_search_filter` + `form_editor` | Table/FormField/Button/EmptyState | 19 st · 6 sb | stacked→columns | 🟡 | 1 | untouched |
| **SDPlayerProgramView** `MultiOrg/Features/Player/SDPlayerProgramView.swift` | Assigned program overview | Development | `record_detail` | Card/StatTile/SectionHeader/StatusBadge | 7 st · 6 sb | stack | 🟢 | 1 | untouched |
| **SDPlayerCalendarView** `MultiOrg/Features/Player/SDPlayerCalendarView.swift` | Player calendar | Scheduling | `calendar_scheduling` | SegmentedControl/Card/StatusBadge | 11 st · 5 sb · `DHDMonthGridView` | grid→agenda @AX3 | 🟡 | 1 | untouched |
| **SDPlayerBPView** `MultiOrg/Features/Player/SDPlayerBPView.swift` | BP sessions list | Development | `list_search_filter` | Table/EmptyState/StatusBadge | 9 st · 9 sb | stacked | 🟡 | 1 | untouched |
| **SDPlayerAnalysisView** `MultiOrg/Features/Player/SDPlayerAnalysisView.swift` | BP analysis wrapper | Analytics | `analytics` | Chart/Card (+`BPAnalysisComponents`) | 2 st · 2 sb | chart height fixed @AX3 | 🟢 | 1 | untouched |
| **SDPlayerFacilitiesView** `MultiOrg/Features/Player/SDPlayerFacilitiesView.swift` | Request facility time | Facilities | `calendar_scheduling` + `form_editor` | MonthGrid/Card/Button/FormField | 21 st · 10 sb · `DHDMonthGridView` | grid→agenda @AX3 | 🔴 | 7 | untouched |
| **PlayerSubscriptionPaywall** `MultiOrg/Features/Home/PlayerSubscriptionPaywall.swift` | StoreKit paywall | Settings | `billing_paywall` | Card/Button(.primary)/StatusBadge/ErrorState | 5 st · 8 sb · **StoreKit — read-only** | capped 560pt | 🔴 | 2 | untouched |
| **PlayerDetailView** `MultiOrg/Features/Home/PlayerDetailView.swift` | Player detail (parent/coach view) | Development | `record_detail` | Avatar/MetricCard/StatTile/Table | 8 st · 8 sb | 2→4-col metrics | 🟡 | 3 | untouched |

## PARENT (Priority 3)

| Screen · file | Purpose | Workspace | Template | HP components | Protected | Responsive | Risk | Pri | Status |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| **ParentHomeView** `MultiOrg/Features/Home/ParentHomeView.swift` | Children list | Overview | `workspace_dashboard` | Header/Card/Avatar/StatTile | 6 st · 7 sb · `DHDAvatarView` | stack→2-col | 🟡 | 3 | untouched |
| **ParentRootView** `MultiOrg/Features/Home/ParentRootView.swift` | Parent tab shell | — (shell) | *nav shell* | — | 0 st · 0 sb | tabs→sidebar | 🟢 | 3 | untouched |
| **ParentChildProfileView** `MultiOrg/Features/Parent/ParentChildProfileView.swift` | Child profile | Development | `record_detail` | Avatar/MetricCard/StatTile | 5 st · 3 sb · `DHDFormRow` | 2→4-col | 🟢 | 3 | untouched |
| **ParentChildCalendarView** `MultiOrg/Features/Parent/ParentChildCalendarView.swift` | Child calendar | Scheduling | `calendar_scheduling` | SegmentedControl/Card/StatusBadge | 17 st · 9 sb · `DHDMonthGridView` | grid→agenda @AX3 | 🟡 | 3 | untouched |
| **SDParentBillingView** `MultiOrg/Features/Parent/SDParentBillingView.swift` | Parent billing | Finance | `finance` (read-only) | MetricCard/Table/StatusBadge | 5 st · 4 sb · **payments — read-only** | stack→2-col | 🟡 | 3 | untouched |
| **SDParentFacilitiesView** `MultiOrg/Features/Parent/SDParentFacilitiesView.swift` | Request facility time | Facilities | `calendar_scheduling` + `form_editor` | MonthGrid/Card/Button | 21 st · 9 sb | grid→agenda @AX3 | 🔴 | 7 | untouched |
| **ParentRequestPanels** `MultiOrg/Features/Account/ParentRequestPanels.swift` | Parent request panels | Settings | `list_search_filter` (embedded) | Card/StatusBadge/Button | 10 st · 12 sb | stack | 🟡 | 3 | untouched |
| **PaymentRequestCard** `MultiOrg/Features/Payments/PaymentRequestCard.swift` | Payment request row + Stripe checkout | Finance | *component* → `HPCard`+`HPStatusBadge` | Card/StatusBadge/Button | 0 st · 0 sb · **Stripe checkout — read-only** | stack | 🟢 | 3 | untouched |

## COACH (Priority 4)

| Screen · file | Purpose | Workspace | Template | HP components | Protected | Responsive | Risk | Pri | Status |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| **CoachHomeView** `MultiOrg/Features/Home/CoachHomeView.swift` | Coach roster/home | Overview | `workspace_dashboard` | Header/Card/Avatar/StatusBadge | 8 st · 7 sb | stack→2-col | 🟡 | 4 | untouched |
| **CoachRootView** `MultiOrg/Features/Home/CoachRootView.swift` | Coach tab shell | — (shell) | *nav shell* + `HPSidebar` | — | 1 st · `DHDOrgMenuHeader` | tabs→sidebar | 🟢 | 4 | untouched |
| **CoachTeamsView** `MultiOrg/Features/Coach/CoachTeamsView.swift` | Teams list | Development | `list_search_filter` | SearchBar/Table/Avatar/StatusBadge | 6 st · 6 sb | stacked→columns | 🟢 | 4 | untouched |
| **CoachProgramsView** `MultiOrg/Features/Coach/CoachProgramsView.swift` | Program templates list | Development | `list_search_filter` | SearchBar/Table/Button/EmptyState | 12 st · 4 sb | stacked→columns | 🟡 | 4 | untouched |
| **ProgramTemplateEditorView** `MultiOrg/Features/Coach/ProgramTemplateEditorView.swift` | Edit program template | Development | `form_editor` | FormField/SegmentedControl/Card/Button | 23 st · 13 sb | single column | 🔴 | 4 | untouched |
| **ProgramDayEditorSheet** `MultiOrg/Features/Coach/ProgramDayEditorSheet.swift` | Edit program day | Development | `form_editor` (modal) | ModalContainer/FormField/Button | 5 st · 5 sb | single column | 🟡 | 4 | untouched |
| **CoachPlayerProfileView** `MultiOrg/Features/Coach/CoachPlayerProfileView.swift` | Coach's player profile | Development | `record_detail` | Avatar/MetricCard/StatTile/Table | 17 st · 15 sb · `DHDFormRow` | 2→4-col | 🔴 | 4 | untouched |
| **CoachPlayerOverviewView** `MultiOrg/Features/Coach/CoachPlayerOverviewView.swift` | Player overview tab | Development | `record_detail` (section) | MetricCard/StatTile | 3 st · 2 sb | 2→4-col | 🟢 | 4 | untouched |
| **CoachPlayerAnalysisView** `MultiOrg/Features/Coach/CoachPlayerAnalysisView.swift` | Player analysis | Analytics | `analytics` | Chart/MetricCard/Table | 9 st · 3 sb | fixed chart @AX3 | 🟢 | 4 | untouched |
| **CoachPlayerBPSessionsView** `MultiOrg/Features/Coach/CoachPlayerBPSessionsView.swift` | Player BP sessions | Development | `list_search_filter` | Table/EmptyState | 6 st · 4 sb | stacked | 🟢 | 4 | untouched |
| **CoachPlayerDailyLogsView** `MultiOrg/Features/Coach/CoachPlayerDailyLogsView.swift` | Player daily logs | Development | `list_search_filter` | Table/StatusBadge/EmptyState | 7 st · 5 sb | stacked | 🟢 | 4 | untouched |
| **CoachPlayerTestingEntriesView** `MultiOrg/Features/Coach/CoachPlayerTestingEntriesView.swift` | Testing entries | Development | `list_search_filter` | Table/EmptyState | 3 st · 2 sb | stacked | 🟢 | 4 | untouched |
| **CoachPlayerTestingCRUDView** `MultiOrg/Features/Coach/CoachPlayerTestingCRUDView.swift` | Add/edit testing | Development | `form_editor` | FormField/Button/ConfirmationDialog | 20 st · 4 sb | single column | 🟡 | 4 | untouched |
| **CoachPlayerCalendarView** `MultiOrg/Features/Coach/CoachPlayerCalendarView.swift` | Player calendar (coach) | Scheduling | `calendar_scheduling` | SegmentedControl/Card/StatusBadge | 21 st · 11 sb · `DHDMonthGridView` | grid→agenda @AX3 | 🔴 | 4 | untouched |
| **CoachFacilitiesView** `MultiOrg/Features/Coach/CoachFacilitiesView.swift` | Facilities + bookings | Facilities | `calendar_scheduling` | MonthGrid/Card/StatusBadge/Button | 19 st · 12 sb | grid+timeline split | 🔴 | 7 | untouched |
| **FacilitiesDayTimelineView** `MultiOrg/Features/Coach/FacilitiesDayTimelineView.swift` | Day timeline | Facilities | `calendar_scheduling` (pane) | Card/StatusBadge | 2 st · **0 sb — pure presentation** | timeline list @AX3 | 🟢 | 7 | untouched |
| **FacilityDaySheet** `MultiOrg/Features/Coach/FacilityDaySheet.swift` | Day detail sheet | Facilities | `record_detail` (modal) | ModalContainer/Card/StatusBadge | 1 st · 0 sb | capped modal | 🟢 | 7 | untouched |
| **NewFacilityBookingSheet** `MultiOrg/Features/Coach/NewFacilityBookingSheet.swift` | New booking | Facilities | `form_editor` (modal) | ModalContainer/FormField/Button | 12 st · 2 sb | single column | 🟡 | 7 | untouched |
| **EditFacilityBookingSheet** `MultiOrg/Features/Coach/EditFacilityBookingSheet.swift` | Edit booking | Facilities | `form_editor` (modal) | ModalContainer/FormField/ConfirmationDialog | 11 st · 2 sb | single column | 🟡 | 7 | untouched |

## OWNER / ADMIN + PLATFORM ADMIN (Priority 5)

| Screen · file | Purpose | Workspace | Template | HP components | Protected | Responsive | Risk | Pri | Status |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| **OrgAdminConsoleView** `MultiOrg/Features/Admin/OrgAdminConsoleView.swift` | Org admin console (**2607 LOC**) | Organization | `admin_console` | SegmentedControl/Table/Card/StatusBadge/ConfirmationDialog | **71 st · 44 sb** · authorization — read-only | stacked→dense tables | 🔴🔴 | 5 | untouched |
| **PlatformAdminDashboardView** `MultiOrg/Features/Admin/PlatformAdminDashboardView.swift` | Platform admin + support | Organization | `admin_console` (+ **support banner**) | Card/Table/StatusBadge(.gold) | 10 st · 6 sb · **support ≠ ownership** | stacked→dense | 🔴 | 5 | untouched |
| **FinanceDashboardView** `MultiOrg/Features/Admin/FinanceDashboardView.swift` | Finance overview | Finance | `finance` | Header/MetricCard/Table/FilterBar/ErrorState | 1 st · 2 sb (**has ViewModel**) | 2-col grid + lists | 🟡 | — | **pilot complete** |
| **ExpenseManagementView** `MultiOrg/Features/Admin/ExpenseManagementView.swift` | Expenses + editor | Finance | `list_search_filter` + `form_editor` | SearchBar/Table/MoneyField/Button | 6 st · 0 sb · **integer cents** | stacked→columns | 🟡 | — | **pilot complete** |

## AUTHENTICATION & ACCESS (Priority 2)

| Screen · file | Purpose | Workspace | Template | HP components | Protected | Responsive | Risk | Pri | Status |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| **LoginView** `MultiOrg/Features/Login/LoginView.swift` | Sign in / sign up | — (pre-auth) | `form_editor` (auth variant) | Card/FormField(.secure)/Button(.primary)/ErrorState | 16 st · 2 sb · **auth — read-only** | capped 560pt | 🔴 | 2 | untouched |
| **AppleSignInButtonView** `MultiOrg/Features/Login/AppleSignInButtonView.swift` | Apple sign-in button | — (pre-auth) | *component* — **must keep Apple's button** | — (Apple-provided) | 2 st · **Apple HIG mandated** | n/a | 🟢 | 2 | **do not restyle** |
| **AccessRequiredView** `MultiOrg/Features/Home/AccessRequiredView.swift` | No entitlement | — | `state_screen(.locked)` | Card/EmptyState/Button | 0 st · 0 sb | capped 560pt | 🟢 | 2 | untouched |
| **ConfigErrorView** `MultiOrg/Features/Home/ConfigErrorView.swift` | Missing config | — | `state_screen(.configError)` | ErrorState | 0 st · 0 sb | capped 560pt | 🟢 | 2 | untouched |
| **HomeView** `MultiOrg/Features/Home/HomeView.swift` | Role router | — (shell) | *router — no template* | — | 0 st · 0 sb · **routing** | n/a | 🟢 | 2 | untouched |
| **RootView** `MultiOrg/App/RootView.swift` | App root + branding | — (shell) | *shell* | — | 0 st · 1 sb · `DHDTheme`/`DHDOrgBranding` | n/a | 🟢 | 2 | foundation-only |

## NOTIFICATIONS & CHAT (Priority 6)

| Screen · file | Purpose | Workspace | Template | HP components | Protected | Responsive | Risk | Pri | Status |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| **NotificationCenterView** `MultiOrg/Features/Notifications/NotificationCenterView.swift` | Notification center | Communication | `list_search_filter` | Table/StatusBadge/EmptyState/FilterBar | 7 st · 8 sb (**has ViewModel**) · **no duplicate alerts** | stacked | 🟡 | 6 | untouched |
| **ChatChannelListView** `MultiOrg/Features/Chat/ChatChannelListView.swift` | Conversation list | Communication | `communication_split` (list) | Avatar/StatusBadge/SearchBar/EmptyState | 13 st · 6 sb · **DM transport — read-only** | list→split | 🟡 | 6 | untouched |
| **ChatThreadView** `MultiOrg/Features/Chat/ChatThreadView.swift` | Thread + composer | Communication | `communication_split` (thread) | FormField/Button(.primary)/Avatar | 6 st · 9 sb · **send path — read-only** | thread→right pane | 🟡 | 6 | untouched |
| **ChatCreateView** `MultiOrg/Features/Chat/ChatCreateView.swift` | New chat | Communication | `form_editor` (modal) | ModalContainer/SearchBar/Avatar/Button | 8 st · 7 sb | single column | 🟢 | 6 | untouched |

## SETTINGS

| Screen · file | Purpose | Workspace | Template | HP components | Protected | Responsive | Risk | Pri | Status |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| **AccountView** `MultiOrg/Features/Account/AccountView.swift` | Account, org switch, prefs, sign out (**974 LOC**) | Settings | `settings_account` | Avatar/Card/StatTile/Toggle/Button(.destructive)/Toast | **34 st · 14 sb** · `DHDToast`/`DHDFormRow`/`DHDAvatarView` | single column ≤720pt | 🔴 | 5 | untouched |

## SHARED PRESENTATION COMPONENTS (migrate once → many screens benefit)

| File | Purpose | Target | Protected | Risk | Pri | Status |
| --- | --- | --- | --- | --- | --- | --- |
| `MultiOrg/Features/Shared/DHDMonthGridView.swift` | Month grid (**7 screens**) | → HP calendar grid (per `calendar_scheduling`) | 1 st · 0 sb | 🟡 | 1 | untouched |
| `MultiOrg/Features/Shared/CalendarComponents.swift` | Day cell + status dot | → HP calendar cell | 0 st · 0 sb | 🟢 | 1 | untouched |
| `MultiOrg/Features/Shared/BPAnalysisComponents.swift` | BP charts/analysis (349 LOC) | → `HPChart` + `HPTable` | 0 st · **0 sb — pure presentation** | 🟢 | 1 | untouched |
| `MultiOrg/Features/Shared/TwoAxisScrollView.swift` | 2-axis scroll helper | keep (utility) | 0 st · 0 sb | 🟢 | — | **not a screen** |
| `MultiOrg/Features/Shared/SDProgramSchedule.swift` | Schedule math | **do not touch — logic** | 0 st · 0 sb | — | — | **not a screen** |
| `MultiOrg/Features/Payments/PaymentRequestCard.swift` | Payment row | → `HPCard` + `HPStatusBadge` | 0 st · 0 sb | 🟢 | 3 | untouched |

## NON-UI / DO NOT RESTYLE

| File | Why |
| --- | --- |
| `MultiOrg/App/MultiOrgApp.swift` | App entry + notification delegates — **not a screen**. |
| `MultiOrg/Features/Admin/FinanceDashboardViewModel.swift` | ViewModel — logic. |
| `MultiOrg/Features/Notifications/NotificationCenterViewModel.swift` | ViewModel — logic. |
| `MultiOrg/Features/Login/AppleSignInButtonView.swift` | Apple-provided button — HIG mandates its appearance. |

---

## Template coverage check

| Template | Screens assigned |
| --- | --- |
| `workspace_dashboard` | 3 (ParentHome, CoachHome, + Overview *(future)*) |
| `list_search_filter` | 11 |
| `record_detail` | 6 |
| `form_editor` | 9 |
| `program_execution` | 2 ✅ done |
| `calendar_scheduling` | 7 |
| `analytics` | 4 |
| `communication_split` | 3 |
| `finance` | 3 (2 done) |
| `settings_account` | 1 |
| `billing_paywall` | 1 |
| `admin_console` | 2 |
| `state_screen` | 2 |
| `game_day` / `ai_evidence` / `recruiting_profile` | **0 — no screens exist yet** |
| *nav shells / routers* | 5 (no template — structure only) |

**No screen is left without a template.** Templates 14–16 have no production screens (future workspaces), and their components do not exist — see the gap list in `HOME_PLATE_SCREEN_TEMPLATES.md`.

---

## Rollout order (fastest safe path)

| Wave | Scope | Why |
| --- | --- | --- |
| **A** | **Layer A global foundation** (see below) | 36 files get HP look for ~1 day of work. Highest reach/effort ratio. |
| **1** | Player iPhone: Trends, Testing, Program, Calendar, BP, Analysis (+ shared `DHDMonthGridView`, `CalendarComponents`, `BPAnalysisComponents`) | Player is the core loop; the pilot proved the template. Shared components unlock 7 calendar screens. |
| **2** | Auth & access: LoginView, AccessRequired, ConfigError, PlayerSubscriptionPaywall | First impression + every user hits them; small and self-contained. |
| **3** | Parent mobile: ParentHome, ChildProfile, ChildCalendar, Billing, RequestPanels, PaymentRequestCard | Reuses wave-1 templates. |
| **4** | Coach mobile: Home, Teams, Programs, Player* views, editors | Largest count; reuses list/detail/form. |
| **5** | Org admin: OrgAdminConsole (🔴🔴 split over several sessions), PlatformAdmin, AccountView | Highest risk — do last on mobile, one section per session. |
| **6** | Notifications & chat | Presentation-only; must not disturb notification producers. |
| **7** | iPad adaptations: splits (list+detail, month+timeline), 2–3-col grids, facilities | Do after compact is settled. |
| **8** | macOS refinements: sidebar, dense tables | Player/parent macOS parity remains deferred. |

**Sequencing rules:** shared components before their consumers · one 🔴 screen per session · never two agents in this worktree · every screen ships with manifest + builds + tests + screenshots before the next starts.

---

## Layer A — global foundation migration (**proposed, NOT implemented**)

**Idea:** make the shared DHD presentation types thin wrappers/aliases over HP tokens & components, so all 36 untouched files instantly get Home Plate colors, surfaces, radii, borders, and button/card/status styling — **without touching a single screen**.

**Exact files that would change (3):**

| File | Change | Reach |
| --- | --- | --- |
| `MultiOrg/Core/DHDTheme.swift` | Repoint color/`pageBackground` to `HP.Color.*` (bg/surface/text/accent/danger…) | **36 files** |
| `MultiOrg/Core/DHDUIComponents.swift` | Re-implement `DHDCard`→`HPCard`, `DHDHeaderCard`→`HPWorkspaceHeader`, `DHDSectionHeader`→`HPSectionHeader`, `DHDStatusBadge`/`DHDStatusPill`→`HPStatusBadge`, `DHDAvatarView`→`HPAvatar`, `DHDFormRow`→`HPFormField`, `DHDToast`→`HPToast` — same public API, HP internals | Card 14 · HeaderCard 10 · StatusBadge 11 · SectionHeader 7 · Avatar 5 · FormRow 3 · Toast 1 |
| `MultiOrg/Features/Shared/CalendarComponents.swift` | `DHDCalendarDayCellView`/`DHDStatusDot` → HP tokens | 2 (+7 via `DHDMonthGridView`) |

**Expected visual reach: 36 of 51 screens (~71%)** get HP colors/surfaces/typography-where-safe/radii/borders/buttons/cards/status **immediately**, with **zero** screen edits and zero behavior change.

**🔴 BLOCKER — do not implement yet.** `DHDTheme.swift` and `DHDUIComponents.swift` are **actively owned by Codex** on `codex/apple-iap-rebuild-20260713` (recorded collision risk; Codex already collided with Stage 5B in this worktree). Implementing Layer A now would guarantee a merge conflict in the two highest-traffic files in the app.

**Risks**
| Risk | Mitigation |
| --- | --- |
| Codex conflict on the 2 core files | **Coordinate first**: get Codex to stop editing them, or land Layer A in a window when it is idle, or have Codex apply it. |
| Type changes ripple (e.g. `DHDStatusPill(color:)` takes a raw `Color`; HP takes `HPStatusKind`) | Keep the **old API signature** and map internally (`color` → nearest `HPStatusKind`). No call-site edits. |
| Typography shifts break dense layouts | Ship colors/surfaces/radii first; adopt `HP.Font` **only where it doesn't reflow** — the guide's "where safe". |
| Light-mode assumptions in untouched screens | HP is dark-first; verify the 36 files render legibly before/after with a screenshot sweep. |
| `DHDMonthGridView` is a *screen* component, not a token | Migrate it in wave 1, not Layer A. |

**Prerequisite:** an explicit go/no-go on Codex ownership of `DHDTheme.swift` / `DHDUIComponents.swift`.
