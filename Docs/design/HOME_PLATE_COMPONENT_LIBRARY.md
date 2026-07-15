# HOME PLATE — COMPONENT LIBRARY

**Status:** Stage 2 spec — approved direction, pre‑implementation. Component APIs are proposals to validate in Stage 3 previews.
**Absolute path:** `/Users/lb33/Documents/DHD-Self-Development-iOS-multiorg/Docs/design/HOME_PLATE_COMPONENT_LIBRARY.md`
**Companions:** `HOME_PLATE_DESIGN_SYSTEM.md` (tokens), `HOME_PLATE_WORKSPACES.md`, `HOME_PLATE_STAGE3_PLAN.md`.

## Conventions

- Prefix **`HP`**. SwiftUI value‑type views; theme via the `HP` token namespace (not literals).
- Every component defines: **Purpose · Anatomy · Variants · Sizes · States · Interaction · Keyboard · Accessibility · Platform · Proper usage · Anti‑patterns.** Below, common defaults are stated once and only notable deviations are called out per component to keep this readable.
- **Global defaults:** radius from `HP.Radius`; focus = 2px gold ring (macOS/iPad); disabled = 40% opacity + no hit‑testing; all interactive elements have an `accessibilityLabel`; all honor Dynamic Type + Reduce Motion.
- Column "From" = the existing code each component evolves from (see `HOME_PLATE_UI_AUDIT.md`).

---

## Tier 1 — Stage 3 build set (first 20 + 3)

### 1. `HPButton` — From: `.borderedProminent`/`.bordered`/`.plain`
- **Purpose:** the one action affordance. **Variants:** `primary` (gold), `secondary` (outline), `tertiary` (text), `destructive`, `primaryOnGreen`. **Sizes:** `sm/md/lg`. **States:** default/hover/pressed/focused/disabled/loading (inline spinner, label kept, no layout shift). **Interaction:** min 44pt touch target on iOS. **Keyboard:** default button = Return; ⌘‑Return for screen primary where apt. **A11y:** icon‑only requires label; loading sets `accessibilityValue("Loading")`. **Proper:** exactly one `primary` per screen. **Anti:** two golds; gold for non‑primary; destructive without `HPConfirmationDialog`.

### 2. `HPCard` — From: `DHDCard`
- **Purpose:** surface container. **Variants:** `flat`/`elevated`. **Anatomy:** optional `HPSectionHeader` · body · optional footer actions. **States:** static; `elevated` gains `hp.shadow.card`; optional selectable (macOS hover/selected). **Proper:** group related content. **Anti:** nesting cards >2 deep; card‑in‑card with competing borders.

### 3. `HPMetricCard` — From: `ImprovementTile`, `FinanceMetricCard`
- **Purpose:** a metric **with context** (Manifesto principle 3). **Anatomy:** label · value (`number`, tabular) · delta (sign+unit, `hp.success`/`hp.danger`) · context line · optional sparkline. **Variants:** `player`(mph/lb) / `finance`(money) / `count`. **A11y:** combines to "Max EV, 88.4 mph, up 3.2 over 30 days". **Anti:** value with no context when context exists; raw system colors.

### 4. `HPStatTile` — From: inline stat tiles / `FinanceCompactMetric`
- **Purpose:** compact label+value row/tile for dense metric grids. **Variants:** `row`/`tile`. **Anti:** using where a full `HPMetricCard` (with trend) belongs.

### 5. `HPWorkspaceHeader` — From: `DHDHeaderCard` + `DHDOrgMenuHeader`
- **Purpose:** top of every workspace. **Anatomy:** title (`display`) · context (org/date/filter) · **one** primary action · overflow menu · optional org gradient/diamond texture (identity chrome, org color). **Variants:** `compact`(iPhone) / `regular`(iPad) / `desktop`(macOS toolbar‑integrated). **A11y:** header is a landmark; title is an `.isHeader` trait. **Anti:** multiple primary actions; org color bleeding into semantic controls.

### 6. `HPSectionHeader` — From: `DHDSectionHeader`
- Title + trailing accessory (button/badge). Adopt everywhere in place of ad‑hoc `HStack{Text;Spacer;…}`.

### 7. `HPStatusBadge` — From: `DHDStatusPill` + `DHDStatusBadge` (unify)
- Capsule; `neutral/success/warning/danger/info/gold`. Tint `color@0.18` + `color@0.25` border + `color` text. **A11y/Proper:** always word + color (never color alone).

### 8. `HPAvatar` — new
- Image→initials→symbol. Sizes `xs/sm/md/lg`. Org avatar may use **org brand color** (identity chrome). Optional status ring. **A11y:** name label.

### 9. `HPTable` / `HPDataRow` — From: `RecentPaymentsView`, expense/request lists
- Compact = stacked rows + hairline dividers; regular = columns, right‑aligned tabular numerics, sortable headers (macOS), hover/select. States: skeleton/empty/error/row‑status. **Anti:** dense dev grids; non‑tabular numbers.

### 10. `HPChart` — From: `BPAnalysisComponents` (Swift Charts)
- Tokenized wrapper: line/bar/histogram/area/sparkline/stacked. Empty via `HPEmptyState`(`ContentUnavailableView`). Follow `dataviz` skill. **Retire `PlotlyChartView`.** **Anti:** >5 unexplained series; decorative/3D.

### 11. `HPFormField` — From: `.roundedBorder` fields, `DHDFormRow`
- Types: `text/secure/multiline/date/select/stepper/toggle/slider`. Label · control · helper/error · accessory. Focus ring; inline `hp.danger` errors; exposes `isValid/errorText`. **Anti:** placeholder‑as‑label; silent validation.

### 12. `HPMoneyField` — From: expense/payment money inputs
- Integer‑cent, currency‑aware, tabular. **Preserves existing money validation logic** (presentation only). **Anti:** float money; locale‑unaware formatting.

### 13. `HPSearchBar` — new (grounds: `ExpenseManagementView` search)
- Magnifier + clear + debounce; `hp.input`. Top of list workspaces.

### 14. `HPFilterBar` + `HPDataPill` — From: `ExpenseManagementView` category filter, `FinanceDateRangePicker`
- Scrollable removable pills + preset menu/segmented + `HPDateRangeControl`. "Clear all" when >1 active.

### 15. `HPSegmentedControl` — From: default segmented (login)
- Styled segmented; gold selection indicator; ≤4 segments (else use menu). **Anti:** many segments on compact.

### 16. `HPToast` — From: `DHDToast` (+ remove inline duplicate)
- Single toast implementation. Auto‑dismiss ~1.6s; top placement; move+opacity transition; Reduce‑Motion → fade only. **Anti:** a second inline toast (delete `SDPlayerTodayView`'s `.thinMaterial` one).

### 17. `HPEmptyState` — From: ad‑hoc empties / `ContentUnavailableView`
- Icon · title · one‑line · optional single CTA. Specific, encouraging copy.

### 18. `HPLoadingState` + `HPSkeleton` — From: ad‑hoc `ProgressView`, `FinanceLoadingState`
- Prefer skeletons for cards/tables/metrics (layout‑stable). Partial data never fully blocked.

### 19. `HPErrorState` — From: `FinanceErrorState`
- Icon · human message · retry. Distinguish recoverable vs permission (→ `HPPermissionState`). **Anti:** raw `localizedDescription` as whole UI.

### 20. `HPSidebar` — From: `CoachRootView` `NavigationSplitView`
- Org header (`DHDOrgMenuHeader`) · grouped workspace links (Develop/Run/Manage) · role/entitlement gating (reuse `feature()`, `canAdminActiveOrg`, `isPlatformAdmin`). Keyboard navigable. **Anti:** showing inaccessible/unpreviewed workspaces.

### +21. `HPProgressIndicator` — From: `ProgressRing` (ring + bar + inline spinner).
### +22. `HPModal` / `HPConfirmationDialog` — From: `dhdFloatingModal` (macOS click‑out) + iOS sheet.
### +23. `HPWorkspaceDirectory` — new (branded iPhone "More" replacement; grid of workspace tiles, role‑gated).

---

## Tier 2 — Domain & near‑term

| Component | From / Purpose |
| --- | --- |
| `HPNotificationBell` / `HPBadge` / `HPNotificationRow` / `HPNotificationCenter` | `NotificationBellButton`/`NotificationCenterView` — presentation only |
| `HPSupportModeBanner` | Finance support‑mode `DHDCard` — persistent "support ≠ ownership" |
| `HPFinanceCard` / `HPMoneyText` / `HPFinanceMetricGrid` / `HPDateRangeControl` / `HPPaymentRow` | `FinanceDashboardView` tree (reskin, keep ViewModel) |
| `HPProgramDayCard` / `HPExerciseLogger` / `HPTestingEntryRow` / `HPDailyLogCard` / `HPTrendChart` / `HPSelfAssessment` | Player Today/Trends/Testing |
| `HPToolbar` | macOS toolbar |
| `HPOfflineBanner` / `HPStaleIndicator` / `HPPermissionState` / `HPLockedState` / `HPUpgradeCard` | Extended states (`HOME_PLATE_DESIGN_SYSTEM.md` §29) |
| `HPConversationRow` | Chat list rows |
| `HPTrendIndicator` | ↑/↓ delta glyph + value |

## Tier 3 — Future modules (adopt system from first build)

`HPGameCard`, `HPScoreboard`, `HPBaseDiamond`, `HPPlayByPlayRow`, `HPBoxScoreTable`, `HPPitchCountMeter` (Game Day) · `HPAICard`, `HPConfidenceMeter`, `HPEvidenceList` (AI) · `HPCommandTarget`, `HPMissVector`, `HPCommandHeatmap` (CommandIQ) · `HPRecruitingProfileHeader`, `HPVerifiedMetric`, `HPMetricSourceLabel`, `HPFilmReel`, `HPRecruitingSnapshotCard` (Recruiting). Specs in `HOME_PLATE_DESIGN_SYSTEM.md` §32–34; detailed when those phases begin.

## Preview & QA requirements (per component)

Each Tier‑1 component ships (Stage 3) with a `#Preview` matrix: all variants × states (default/hover/pressed/focused/disabled/loading/empty/error where applicable) × light‑stub sample data × Dynamic Type XL × iPhone/iPad/macOS size. No production screen is modified in Stage 3. Verification commands: `HOME_PLATE_STAGE3_PLAN.md`.
