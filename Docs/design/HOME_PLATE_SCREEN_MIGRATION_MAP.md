# HOME PLATE — SCREEN MIGRATION MAP

**Status:** Universal UI migration implemented through Layer E `a588cb7`; Layer F acceptance is complete on 2026-07-17.
**Worktree:** `/Users/lb33/Documents/HomePlate-ui-integration`
**Branch:** `integration/universal-ui`
**Companions:** `HOME_PLATE_AI_UI_IMPLEMENTATION_GUIDE.md` · `HOME_PLATE_SCREEN_TEMPLATES.md` · `HOME_PLATE_UI_CONTRACT.yaml` · `HOME_PLATE_DESIGN_QA.md`

This document is the coverage ledger for the Universal UI migration. It distinguishes routed roots/screens/sheets from embedded panes, reusable components, shells/routers, and preserved dead source so that unlike categories are not added into one denominator.

## Denominators and coverage

| Measure | Definition | Count | Coverage at `a588cb7` |
| --- | --- | ---: | ---: |
| Historical source files | Swift files under `HomePlate/App/**` and `HomePlate/Features/**` at `b97c1b4` | **62** | n/a |
| Historical role-table rows | Rows actually present in the original role tables | **54** | n/a |
| Original-map contract | 54 rows, excluding component-only `AppleSignInButtonView`, `ParentRequestPanels`, and `PaymentRequestCard`; `RootView` and `HomeView` were already rows and are not added again | **51** | **51/51** |
| Live original subset | Original-map contract minus six now-unreachable source types | **45** | **45/45** |
| Current source files | Swift files under `HomePlate/App/**` and `HomePlate/Features/**` at `a588cb7` | **67** | n/a |
| Strict live current | Independently routed production roots, screens, and sheets | **79** | **79/79** |
| Map-compatible current | Strict live current plus three historically mapped embedded targets | **82** | **82/82** |

The old summary overstated the baseline file count by two; the baseline contains 62. Its 51-screen denominator is still a valid historical contract only when derived from the 54 role-table rows as shown above. Layer F independently confirmed all three coverage ratios with clean iOS/macOS builds, 296 logical Swift tests, 310 Swift invocations, 373 shared backend tests, and inspected render evidence.

## Implemented layers

| Layer | Commit | Scope |
| --- | --- | --- |
| A | `6984417` | Universal Home Plate tokens and foundation |
| B | `a98a772` | Adaptive application/navigation shells |
| C | `b651477` | Shared screen templates |
| D1 | `3d3bbae` | Player experiences |
| D2 | `ef52cbb` | Parent experiences |
| D3 | `7de2267` | Coach experiences, including Phase 11 coach AI/import/Copilot |
| D4 | `4bd8262` | Owner, organization-admin, platform-admin, and account experiences |
| D5 | `9d45f65` | Auth/access, subscription, notifications, chat, and remaining shared presentation |
| E | `a588cb7` | Cross-role consistency, state recovery, accessibility, modal/sidebar interaction, and focused regression coverage |

Layer F is the documentation and acceptance closeout for the exact Layer E tree. It does not add another production migration layer.

## Strict live current inventory — 79

The lists below are exhaustive for the strict denominator. Names are Swift production types, not file counts.

### Shells and routers — 6

These are counted because they are live application roots or role routers, but they are not screen-template consumers in the same sense as a detail screen.

`RootView`, `HomeView`, `PlatformRootView`, `PlayerHomeView`, `ParentRootView`, `CoachRootView`

### Routed screens and sheets — 73

| Ownership | Count | Exact types |
| --- | ---: | --- |
| Pre-map pilots | 2 | `FinanceDashboardView`, `ExpenseEditorSheet` |
| D1 — Player | 13 | `SDPlayerTodayView`, `SDPlayerTrendsView`, `SDPlayerTestingView`, `AddTestingEntrySheet`, `SDPlayerCalendarView`, `SDPlayerDayDetailView`, `SDPlayerAnalysisView`, `SDPlayerFacilitiesView`, `PlayerRequestBookingSheet`, `CoachPlayerAnalysisView`, `PlayerDevelopmentPlayerWorkspaceView`, `PlayerDevelopmentPlayerReportDetailView`, `PlayerDevelopmentPlayerAlertDetailView` |
| D2 — Parent | 11 | `ParentHomeView`, `ParentInviteAcceptanceSheet`, `ParentChildProfileView`, `ParentChildCalendarView`, `ParentChildDayDetailView`, `ParentChildProgramView`, `SDParentFacilitiesView`, `ParentRequestBookingSheet`, `SDParentBillingView`, `PaymentCheckoutConfirmationSheet`, `CoachPlayerOverviewView` |
| D3 — Coach | 27 | `CoachHomeView`, `CoachPlayerProfileView`, `CoachPlayerProgramAssignerView`, `CoachPlayerCalendarView`, `CoachPlayerDayDetailView`, `CoachPlayerTestingCRUDView`, `TestingEntryFormSheet`, `CoachTeamsView`, `CoachProgramsView`, `CreateProgramTemplateSheet`, `ProgramTemplateEditorView`, `ProgramDayEditorSheet`, `ProgramCopySheet`, `ProgramClearSheet`, `CoachFacilitiesView`, `FacilityDaySheet`, `NewFacilityBookingSheet`, `EditFacilityBookingSheet`, `PlayerDevelopmentAIWorkspaceView`, `DevelopmentReportDetailView`, `DevelopmentAlertDetailView`, `DevelopmentRosterAttentionView`, `PlayerDevelopmentImportWorkspaceView`, `PlayerDevelopmentCopilotWorkspaceView`, `PlayerDevelopmentCopilotConversationView`, `EvidenceCitationDetailView`, `ParentUpdateDraftDetailView` |
| D4 — Owner/admin | 10 | `OrgAdminConsoleView`, `PaymentRequestCreateSheet`, `FacilityAdminEditorSheet`, `CreateOrgMemberSheet`, `EditOrgMemberSheet`, `PlatformAdminDashboardView`, `PlatformMembershipEditor`, `PlatformOrganizationCreateEditor`, `PlatformOrganizationEditor`, `AccountView` |
| D5 — Shared/auth/communication | 10 | `LoginView`, `AccessRequiredView`, `ConfigErrorView`, `PlayerSubscriptionPaywall`, `NotificationCenterView`, `NotificationDestinationView`, `AnnouncementComposerView`, `ChatChannelListView`, `ChatThreadView`, `ChatCreateView` |
| **Total routed screens and sheets** | **73** | Together with the six shells/routers: **79** |

Two cross-role types are intentionally recorded with the layer that migrated them: `CoachPlayerAnalysisView` in D1 and `CoachPlayerOverviewView` in D2. They are not duplicated in D3.

## Phase 11 AI, import, and Copilot surfaces — 12

Phase 11 exists in production source and is part of current coverage. The historical statement that `ai_evidence` had zero consumers is obsolete.

| Audience/capability | Exact live surfaces |
| --- | --- |
| Player visibility | `PlayerDevelopmentPlayerWorkspaceView`, `PlayerDevelopmentPlayerReportDetailView`, `PlayerDevelopmentPlayerAlertDetailView` |
| Coach AI evidence/review | `PlayerDevelopmentAIWorkspaceView`, `DevelopmentReportDetailView`, `DevelopmentAlertDetailView`, `DevelopmentRosterAttentionView` |
| Deterministic import | `PlayerDevelopmentImportWorkspaceView` |
| Coach/Player Copilot | `PlayerDevelopmentCopilotWorkspaceView`, `PlayerDevelopmentCopilotConversationView`, `EvidenceCitationDetailView`, `ParentUpdateDraftDetailView` |

These 12 surfaces use the applicable workspace, detail, list, form, communication, state, and AI-evidence compositions. A future template name is not used as a reason to omit a live screen.

## Embedded panes — 3

These production views are reachable and migrated, but are embedded within another screen rather than independently routed. They are excluded from the strict 79 and added only for the map-compatible 82 denominator.

| Embedded type | Host/purpose |
| --- | --- |
| `SDPlayerBPDaySection` | Batting-practice logging and CSV-import section inside Player Today |
| `FacilitiesDayTimelineView` | Facility schedule timeline pane |
| `ExpenseManagementView` | Finance expense-management pane; presents `ExpenseEditorSheet` |

## Components and wrappers — excluded from screen counts

Component-only views are migrated or intentionally platform-native, but do not inflate screen coverage. The three historical map exclusions are:

- `AppleSignInButtonView`: Apple-provided Sign in with Apple presentation; preserve platform/HIG semantics.
- `PlayerParentRequestsPanel` and `CoachParentRequestsPanel` in `ParentRequestPanels.swift`: embedded account panels.
- `PaymentRequestCard`: embedded payment row/card; `PaymentCheckoutConfirmationSheet` is the independently presented sheet and is counted.

Shared calendar, chart, status, form, card, toast, navigation, notification-row, chat-row, and other leaf views are likewise components. Examples include `DHDMonthGridView`, the views in `CalendarComponents.swift` and `BPAnalysisComponents.swift`, `NotificationBellButton`, `NotificationRow`, `ChatChannelRowView`, and `MessageRow`. `HomePlateApp` is the app entry point; ViewModels and helpers are non-presentation logic. None belongs in the 79 or 82 denominator.

## Preserved dead source — 6

The following original-map types are no longer reachable from current production navigation:

- `PlayerDetailView`
- `SDPlayerProgramView`
- `SDPlayerBPView`
- `CoachPlayerBPSessionsView` (transitively unreachable)
- `CoachPlayerDailyLogsView` (transitively unreachable)
- `CoachPlayerTestingEntriesView` (transitively unreachable)

They remain in source to avoid an unrelated deletion or behavior change. They are included in the historical 51/51 source-migration contract, excluded from the 45 live-original subset and all strict-live counts, and must not be represented as user-reachable QA coverage.

## Coverage rules going forward

1. Add a type to the strict denominator only when it is an independently routed root, screen, or presented sheet in production.
2. Record reachable embedded panes separately; do not mix them into strict screen counts.
3. Do not count components, row views, platform-control wrappers, app entry points, ViewModels, or helpers as screens.
4. Confirm reachability before removing source from the live denominator; preserve source unless deletion is separately authorized and proven safe.
5. Every new Phase 11 or later production destination must enter this ledger in the same change that makes it reachable.
6. A coverage ratio is complete only when the applicable QA evidence in `HOME_PLATE_DESIGN_QA.md` also passes.
