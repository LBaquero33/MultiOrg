# HOME PLATE — DESIGN SYSTEM

**Status:** Design Bible — **direction approved 2026-07-15**. Production SwiftUI still gated (Finance pilot not yet approved for implementation).
**Companion docs:** `HOME_PLATE_MANIFESTO.md`, `HOME_PLATE_OS.md`, `HOME_PLATE_UI_AUDIT.md`, `HOME_PLATE_COMPONENT_LIBRARY.md`, `HOME_PLATE_WORKSPACES.md`, `HOME_PLATE_MOTION_SYSTEM.md`, `HOME_PLATE_DESIGN_QA.md`, `HOME_PLATE_STAGE3_PLAN.md`.
**Absolute path:** `/Users/lb33/Documents/DHD-Self-Development-iOS-multiorg/Docs/design/HOME_PLATE_DESIGN_SYSTEM.md`
**Derived from:** the live website `homeplateapps.com` (source of truth) and the current app's centralized `DHDTheme` / `DHDUIComponents`, `FinanceDashboardView`, `NotificationCenterView`, `ExpenseManagementView`, `BPAnalysisComponents`.

## Approved decisions locked into this system (2026-07-15)

1. **Org branding = identity chrome only** (org headers, avatars, badges, limited org accents). HP owns green, gold, danger, success, focus, finance, and all semantic colors. *(§2.3)*
2. **iPhone tab structures approved** (per `HOME_PLATE_OS.md` §2); **≤5 primary tabs per role**, hard limit; branded **workspace directory** replaces the system "More". *(§14)*
3. **macOS player/parent parity deferred.** Phase 10 focuses on the shared design system, existing coach/admin macOS surfaces, and responsive iPhone/iPad. No net‑new macOS functionality in the pilot. *(§35)*
4. **Dark‑first; no light mode** in the initial redesign. *(§38)*
5. **Archivo + Instrument Sans provisionally approved**, pending licensing/resource/rendering/accessibility/Dynamic‑Type validation. **High‑quality SF Pro fallback maintained.** *(§3)*
6. **Finance Overview = approved first production pilot**; implementation not yet approved. *(§43, `HOME_PLATE_STAGE3_PLAN.md`)*

---

## 1. Brand philosophy

Home Plate looks like **premium software built for baseball**: *leather + grass + night.* Deep green‑charcoal canvas, baseball field‑green as primary intent, warm gold as value/CTA/focus, cream for readable warmth. Baseball identity comes from data and a *restrained* diamond/grid texture — never clip art. See `HOME_PLATE_MANIFESTO.md`.

## 2. Color

Source: website OKLCH tokens (see `HOME_PLATE_UI_AUDIT.md` §2). Hex values are **approximate conversions from OKLCH — verify against the live site at implementation, and prefer Display‑P3** for green/gold so chroma survives.

### 2.1 Core roles (dark‑first — the default and, per decision 4, the only mode)

| Token | Approx hex | Role |
| --- | --- | --- |
| `hp.bg` | `#121410` | App background (green‑charcoal, near‑black) |
| `hp.surface` | `#191C16` | Card / popover surface |
| `hp.surfaceRaised` | `#212420` | Raised controls, elevated cards |
| `hp.surfaceMuted` | `#1F221E` | Muted fills |
| `hp.border` | `#282B24` | Hairline borders |
| `hp.input` | `#2C2F27` | Field border/fill |
| `hp.text` | `#ECE8DD` | Primary text (cream) |
| `hp.textMuted` | `#A6A394` | Secondary text |
| `hp.primary` | `#2E7D57` | Field green — primary intent |
| `hp.primaryGlow` | `#46B07C` | Brighter green — emphasis/gradients |
| `hp.accent` | `#D6B370` | Gold — CTA, value, focus ring |
| `hp.accentText` | `#2B2A1E` | Text on gold |
| `hp.focusRing` | `#D6B370` | Focus ring = gold |
| `hp.danger` | `#D0453E` | Destructive / error / overdue |
| `hp.success` | `#46B07C` | Success / positive delta |
| `hp.warning` | `#E0A33E` | Warning (distinct amber; not gold, to avoid CTA confusion) |
| `hp.info` | `#5A9BD6` | Neutral info only (not an accent) |

### 2.2 Semantic usage rules

- **Gold (`hp.accent`) = primary CTA, focus, "value/money" emphasis.** Exactly one gold CTA per screen.
- **Green (`hp.primary`) = brand/intent, positive state, progress.**
- **Cream on green‑charcoal**; never pure‑white on pure‑black.
- **Finance color discipline:** `hp.success` positive, `hp.danger` negative/overdue, gold reserved for the primary action. Replaces today's raw `.blue/.green/.orange/.red/.mint` in `FinanceMetricCard` (audit finding) with tokens.
- **AI** uses a distinct controlled accent (indigo `#7C6BD6` family) layered on HP, with explicit evidence/confidence separation (§33).

### 2.3 Org white‑label reconciliation — **APPROVED (decision 1)**

`DHDOrgBranding` injects per‑org `primary/secondary/accent` hex via `DHDTheme.color(hex:fallback:)`. Binding rule:

- **Org brand color drives identity chrome only:** `HPWorkspaceHeader`/sidebar header gradient, `HPAvatar`, org badges, and clearly org‑specific accents.
- **HP system colors own all semantics:** CTAs, focus, finance signals, status, success/danger. An org's brand color (e.g. "Marist Red Foxes" blue) must **not** repaint gold CTAs, focus rings, or finance deltas.
- **Fallback branding becomes Home Plate green/gold** — replacing today's navy `DHDOrgBranding.fallback` and the on‑screen "HomePlate" string.
- Implementation note: introduce a separate `hp.identity` channel so org color and HP semantic color never alias.

## 3. Typography — **provisional (decision 5)**

Website: **Archivo** (display, 700, tight tracking) + **Instrument Sans** (body/UI).

- **Primary plan:** bundle Archivo + Instrument Sans. Blockers to clear before production: (a) license permits app embedding; (b) `project.yml` resource + `UIAppFonts`/`ATSApplicationFontsPath` setup; (c) rendering quality on device vs. simulator; (d) accessibility contrast at all weights; (e) **Dynamic Type** scaling behaves (use `UIFontMetrics`/`.custom(_, size:relativeTo:)`).
- **Fallback (must always ship):** **SF Pro** — SF Pro Display with tightened tracking for `display`/`title`, SF Pro Text for body. `HPFont` must resolve to SF Pro cleanly if custom fonts are absent/failed.

### Type scale (`HPFont`) — relative, Dynamic‑Type‑aware

| Token | Role | Size / weight / tracking | Custom → SF fallback |
| --- | --- | --- | --- |
| `display` | Hero / workspace title | 32–34 / 700 / −0.5 | Archivo → SF Pro Display |
| `title` | Section/card title | 22 / 700 / −0.3 | Archivo → SF Pro Display |
| `headline` | Emphasis | 17 / 600 | Instrument Sans → SF Pro Text |
| `body` | Default | 16 / 400 | Instrument Sans → SF Pro Text |
| `callout` | Secondary | 15 / 400–600 | Instrument Sans → SF Pro Text |
| `caption` | Meta | 13 / 500 | Instrument Sans → SF Pro Text |
| `eyebrow` | Uppercase section label | 12 / 600 / +0.6 tracked, gold/muted | Instrument Sans → SF Pro Text |
| `number` | Stats, money | **tabular figures** | tabular variant |

Replaces ad‑hoc `.title3/.headline/.caption` calls. **Money/stat components must use tabular figures.**

## 4. Spacing

4‑pt scale: `hp.space.xs=8`, `sm=12`, `md=16`, `lg=24`, `xl=32` (raw `2/4` for hairline nudges). Standardizes today's mixed 10/14/16.

## 5. Layout
Page padding 16 (compact) / 24 (regular). Desktop reading‑max ~1120–1200 centered; data workspaces full‑bleed grids. Vertical rhythm: header → attention → core cards → detail (`HOME_PLATE_OS.md` §3).

## 6. Grid
Adaptive `LazyVGrid(minimum:)` — cards 1/2/2–4 col by class (min ~320); metric rows 2‑up compact / 4–5‑up regular (Finance already uses `.adaptive(minimum:145)`).

## 7. Radius
`sm=8`, `md=12` (base), `lg=16` (cards), `xl=18` (modals). Adds the 12 base + 8/18 steps to today's flat 16.

## 8. Borders
Hairline 1px `hp.border`; inputs `hp.input`; focus 2px `hp.focusRing` (gold). Retune `DHDCard`'s `separator.opacity(0.35)` → `hp.border`.

## 9. Shadows
| Token | Value | Use |
| --- | --- | --- |
| `hp.shadow.card` | `y12 blur40 spread-18 @ ~0.5 black` | Elevated cards (matches site) |
| `hp.shadow.modal` | `y14 blur24 @ ~0.45 black` | Floating modals (≈ current `dhdFloatingModal`) |
| `hp.shadow.subtle` | `y3 blur10 @ ~0.06` | iOS inline |

## 10. Surfaces
`hp.bg → hp.surface → hp.surfaceRaised` ladder. No pure black/white. Replaces hardcoded `Color(.systemBackground)`/`cardSurface.opacity` tiles inside dark cards.

## 11. Icons
SF Symbols, `regular`/`semibold`, sized to text. Custom line icons only where SF lacks coverage. No oversized decorative icons. Baseball texture via `DHDDiamondPattern` (sparingly).

## 12. Motion
See `HOME_PLATE_MOTION_SYSTEM.md`. Calm, purposeful, reduced‑motion aware.

## 13. Accessibility
Contrast ≥ 4.5:1 (verify text‑on‑gold and gold‑text‑on‑dark separately); Dynamic Type via relative fonts; VoiceOver (extend existing `accessibilityElement(children:.combine)`, `accessibilityLabel/Value` — already good on `NotificationBellButton`, `DHDOrgMenuHeader`); Reduce Motion + Reduce Transparency honored; visible gold focus on macOS/iPad. Full gate in `HOME_PLATE_DESIGN_QA.md`.

---

## 14. Navigation
Per `HOME_PLATE_OS.md`. iPhone = ≤5 tabs (**hard cap, decision 2**) + `HPWorkspaceDirectory` (branded, replaces system "More"). iPad/macOS = `HPSidebar` + detail. One `HPWorkspaceHeader` per workspace. Component contracts in `HOME_PLATE_COMPONENT_LIBRARY.md`.

## 15. Cards
`HPCard` (flat/elevated) from `DHDCard`. Radius `lg=16`, `hp.surface`/`surfaceRaised`, `hp.border` hairline, `hp.shadow.card` when elevated. Composition slots: header (`HPSectionHeader`) / body / footer actions.

## 16. Buttons — **expanded**
`HPButton` replaces scattered `.borderedProminent`/`.bordered`/`.plain`.

| Variant | Fill / border | Text | Use |
| --- | --- | --- | --- |
| `primary` | `hp.accent` (gold) fill | `hp.accentText` | The one dominant action per screen |
| `secondary` | transparent, 1px `hp.border` | `hp.text` | Alternative action |
| `tertiary` | none | `hp.textMuted`→`hp.text` on hover | Low‑emphasis inline |
| `destructive` | `hp.danger` fill (or danger‑outline) | white/cream | Delete/cancel; always via `HPConfirmationDialog` |
| `primaryOnGreen` | `hp.surface` on gradient header | `hp.text` | Actions inside gradient headers |

- **Sizes:** `sm` (28h), `md` (36h, default), `lg` (44h touch primary). Radius `md=12`, padding 10×20 (matches site).
- **States:** default / hover (macOS/iPad, +4% lightness) / pressed (−6%) / focused (gold ring) / disabled (40% opacity) / loading (inline `HPProgressIndicator`, label preserved, non‑layout‑shifting).
- **Icon+label:** leading SF Symbol, 6pt gap. Icon‑only requires `accessibilityLabel`.
- **Anti‑patterns:** two gold buttons on one screen; gold used for a non‑primary action; destructive without confirmation.

## 17. Forms — **expanded**
`HPFormField` unifies today's `.roundedBorder` fields + `DHDFormRow`.

- **Anatomy:** label (`caption`/`eyebrow`) · control · helper/error line · optional trailing accessory.
- **Field types:** `text`, `secure`, `multiline` (axis `.vertical`), `HPDateField` (native `DatePicker`, styled), `HPSelectField` (menu/segmented), `HPMoneyField` (integer‑cent, currency‑aware — matches `ExpenseManagementView` integer‑cent validation), `HPStepper`, `HPToggle`, `HPSlider`.
- **Surfaces:** fill `hp.input`, 1px border → 2px `hp.focusRing` on focus, radius `md=12`.
- **Validation:** inline error text `hp.danger` under field; error border; `HPFormField` exposes `isValid`/`errorText`. Preserve existing validation *logic* (e.g. money integer‑cent) — presentation only.
- **Layout:** single column on compact; label‑left rows acceptable on regular width. Group related fields in `HPCard` sections.
- **Anti‑patterns:** raw `.roundedBorder` (reads iOS‑stock), placeholder‑as‑label, silent validation failures.

## 18. Tables — **expanded**
`HPTable` / `HPDataRow` for list‑of‑records surfaces (Recent Payments, Expenses, Payment Requests, roster).

- **Row anatomy:** primary value (money/name, `headline`, tabular) · secondary meta (`caption` muted) · trailing `HPStatusBadge` / disclosure / action.
- **Compact (iPhone):** stacked rows in an `HPCard`, hairline `Divider` `hp.border@0.3` (matches current `RecentPaymentsView`). **Regular (iPad/macOS):** true columns with header row, right‑aligned numeric columns (tabular), sortable headers (macOS), row hover/selection.
- **States:** loading (skeleton rows), empty (`HPEmptyState`), error (`HPErrorState`), row‑level (paid/overdue via `HPStatusBadge`).
- **Anti‑patterns:** dense developer grids; non‑tabular numbers; color‑only status (pair with text/icon).

## 19. Charts — **expanded**
`HPChart` = a thin, tokenized wrapper over **native Swift Charts** (already used in `BPAnalysisComponents`: `Chart`/`BarMark`/`AxisMarks`). **Retire the dead `PlotlyChartView` placeholder.**

- **Types:** line (trends), bar/histogram (distributions, e.g. exit‑velo), area (revenue snapshot), sparkline (in `HPMetricCard`), stacked bar (program profitability / revenue by service, per website analytics).
- **Style tokens:** series color `hp.primary`/`hp.primaryGlow`; secondary series gold; gridlines `hp.border@0.4`; axis labels `hp.textMuted`; fills use `.gradient` (already: `DHDTheme.accent.gradient`); tabular axis numbers.
- **Empty state:** `ContentUnavailableView` is already used — standardize under `HPEmptyState` styling.
- **Motion:** subtle draw‑in on appear, reduced‑motion aware (`HOME_PLATE_MOTION_SYSTEM.md`).
- **Follow the `dataviz` skill** for palette/mark/legend/axis rules at build time.
- **Anti‑patterns:** more than ~5 series without a reason; 3D/decorative charts; rainbow categorical palettes.

## 20–21. Search & Filters — **expanded**
`HPSearchBar` + `HPFilterBar`. Grounded in `ExpenseManagementView` (search text + category filter) and `FinanceDateRangePicker` (preset + custom range).

- **`HPSearchBar`:** leading magnifier, clear button, debounce, `hp.input` fill, focus ring. Placed at top of list workspaces.
- **`HPFilterBar`:** horizontal scroll of `HPDataPill` filters + a menu/segmented control for presets; a date‑range control (`HPDateRangeControl` from `FinanceDateRangePicker`). Active filters shown as removable gold‑outlined pills.
- **Rules:** filters never hidden behind more than one tap on compact; selected state obvious; "clear all" when >1 active.

## 22. Badges
`HPStatusBadge` unifies `DHDStatusPill` + `DHDStatusBadge`. Variants: `neutral/success/warning/danger/info/gold`. Capsule, 12px text, tinted fill `color@0.18` + `color@0.25` border + `color` text (matches current). Always pair color with a word.

## 23. Avatars
`HPAvatar` — player/coach/org identity. Sizes `xs/sm/md/lg`. Image (`AsyncImage`) → initials fallback → SF Symbol. Org avatar may use **org brand color** (identity chrome, decision 1). Optional status ring.

## 24. Modals & sheets
`HPModal` (sheet on iOS, `dhdFloatingModal` click‑out on macOS) + `HPConfirmationDialog`. Radius `xl=18`, `hp.shadow.modal`. Sheets get grabber + title + one primary action. macOS sizes preserved (e.g. 620–860 wide as today).

## 25. Empty states
`HPEmptyState` — icon (SF), title, one‑line explanation, optional single CTA. Replaces ad‑hoc empties and standardizes `ContentUnavailableView`. Copy is specific and encouraging ("Add your first Testing entry to see trends"), never a dead end.

## 26. Loading states
`HPLoadingState` — inline `HPProgressIndicator` (from `ProgressRing`) or **skeleton** for cards/tables/metrics (preferred over spinners for layout stability). Never block the whole screen if partial data exists.

## 27. Error states
`HPErrorState` — icon, human message, retry action (matches Finance `FinanceErrorState(onRefresh:)`). Distinguish *recoverable* (retry) from *permission* (see §29e). Never surface raw `error.localizedDescription` as the whole UI.

## 28. Notifications — **expanded**
Grounded in `NotificationBellButton` / `NotificationCenterView` / `NotificationBadge` (do not change producers/routing — presentation only; handoff §6).

- **`HPNotificationBell`:** SF `bell.fill` on `.ultraThinMaterial` circle + `HPBadge` count; `accessibilityValue` unread count (already present).
- **`HPBadge`:** gold or danger dot/count; ≥1 unread → filled; caps at "99+".
- **`HPNotificationRow`:** icon by type (payment / announcement / DM), title, snippet, timestamp, unread indicator (leading gold dot), swipe/mark‑read. Deep‑link routing unchanged.
- **`HPNotificationCenter`:** sheet (iOS) / sized panel (macOS), grouped by day, "Mark all read", empty/loading/error states. Deterministic dedupe preserved.
- Foreground/tap behavior and `.dhdRemoteNotificationReceived` handling untouched.

---

## 29. Extended states — **expanded (offline, stale, permission‑denied, success, locked/upgrade)**

Every view designs all applicable states (Manifesto principle 5). Beyond loading/empty/error:

| State | Component | Behavior |
| --- | --- | --- |
| a. Offline | `HPOfflineBanner` | Non‑blocking top banner; show cached data marked stale; disable mutations that require network with clear reason. |
| b. Stale | `HPStaleIndicator` | "Updated 5m ago" + refresh affordance; subtle, not alarming. |
| c. Permission‑denied | `HPPermissionState` | Explains the missing role/entitlement calmly; **no raw authorization errors**. Uses `appState` gates (`canAdminActiveOrg`, `isPlatformAdmin`, `needsAccess`). |
| d. Success | `HPToast` + inline confirm | Brief, non‑bouncy (see Motion); one `HPToast` implementation (removes the duplicate inline `.thinMaterial` toast in `SDPlayerTodayView`). |
| e. Locked / upgrade | `HPLockedState` / `HPUpgradeCard` | Polished locked‑feature presentation for future entitlements (`finance_dashboard`, `game_day`, `command_iq`, `player_ai`, `recruiting`, …). Shows value + a single upgrade CTA. **Renders state only — no plan checks hardcoded** (handoff §15–16); backend stays authoritative. Preview‑drivable with mock entitlement. |

## 30. Finance components — **expanded**
Reskin the existing `FinanceDashboardView` tree (keep ViewModel + data flow):

- `HPFinanceCard` ← `FinanceMetricCard`: title (`caption` muted) + money (`title`, tabular) + **semantic color from tokens** (positive `hp.success`, negative/overdue `hp.danger`) — replaces raw `.blue/.green/.orange/.red/.mint`. Optional trend/sparkline slot.
- `HPMoneyText` — currency + tabular formatting from `SDMoney.formatted()`.
- `HPFinanceMetricGrid` ← the two `LazyVGrid`s (headline metrics + compact metrics).
- `HPDateRangeControl` ← `FinanceDateRangePicker` (preset menu/segmented + custom range + validity error).
- `HPPaymentRow` ← `RecentPaymentsView` row (`HPTable` row + `HPStatusBadge`).
- Platform‑support banner (`FinanceDashboardView` support‑mode `DHDCard`) → `HPSupportModeBanner` (persistent, explicit; decision to keep support ≠ ownership visible).
- Discipline: precise, stable, no decoration (Manifesto principle 6 / handoff §12.10).

## 31. Player‑development components — **expanded**
- `HPMetricCard` / `HPStatTile` ← `ImprovementTile`: value + **delta with sign/unit** + context ("Personal best", "↑3.2 mph / 30 days") — encodes "context over numbers".
- `HPProgressIndicator` (ring/bar) ← `ProgressRing`.
- `HPProgramDayCard`, `HPExerciseLogger` ← `StrengthExerciseLogger` (generic `HPCard` + `HPFormField`s).
- `HPTrendChart` ← Swift Charts trends.
- `HPTestingEntryRow`, `HPDailyLogCard`, `HPSelfAssessment`.
- `HPImportSourceLabel` — metric provenance badges for future imports (Rapsodo/HitTrax/TrackMan/Blast, etc.), aligning with recruiting metric‑source labels (§34).

## 32. Game Day components — **future, expanded direction**
Broadcast‑inspired, higher contrast, larger numerals; still unmistakably Home Plate. `HPGameCard`, `HPScoreboard` (count/outs/bases/inning), `HPLineupList`, `HPPlayByPlayRow`, `HPBoxScoreTable`, `HPBaseDiamond` (live), `HPPitchCountMeter`. Offline‑first ledger UI (immediate local echo, later sync) per handoff §18. Adopts the system from first implementation.

## 33. AI components — **future, expanded direction**
Controlled indigo accent (`#7C6BD6`) on the HP system; **never magical or vague**. `HPAICard` must visually separate: **Observed facts · Interpretation · Recommendation · Confidence · Missing data** (handoff §12.9, §11D). `HPConfidenceMeter`, `HPEvidenceList` (links to source metrics/notes), `HPAIDraftBanner` ("Draft — coach approval required"). No autonomous changes; coach approval always shown.

## 34. Recruiting components — **future, expanded direction**
Portfolio‑grade, college‑ready, credible. `HPRecruitingProfileHeader`, `HPVerifiedMetric` + `HPMetricSourceLabel` (Self‑reported / Coach‑verified / Facility‑tested / Device‑imported / Game‑derived / CommandIQ‑derived), `HPFilmReel`, `HPCoachEvaluationCard`, `HPRecruitingSnapshotCard` (consented, revocable — shows share date/recipient/revocation). Resembles a modern professional profile/resume.

---

## 35. macOS rules — **parity deferred (decision 3)**
Sidebar + detail, `HPToolbar`, hover/focus, click‑out modals, denser grids. **Phase 10 scope: reskin existing coach/admin macOS surfaces only.** Player/parent macOS remain the current placeholder/bare states — **do not build net‑new macOS functionality in the pilot.** Not an enlarged iPhone.

## 36. iPad rules
Split view + `HPSidebar` on regular width; 2‑col grids; larger `HPWorkspaceHeader`; relax portrait‑lock/full‑screen for regular width. Not a stretched phone. **Responsive behavior is in Phase 10 scope** (presentation only; routing unchanged).

## 37. iPhone rules
≤5 focused tabs (**hard cap**) + branded `HPWorkspaceDirectory`; drill‑in `NavigationStack`. Not a compressed desktop.

## 38. Dark mode — **the only mode for Phase 10 (decision 4)**
Website is dark; app forces dark. Consolidate today's three enforcement mechanisms (`preferredColorScheme(.dark)` iOS, hardcoded AppKit palette, system colors) into the single `HP` token layer.

## 39. Light mode
**Out of scope for Phase 10.** If added later, define a parallel token set; keep `HP.Color` role‑based so a second palette can slot in.

## 40. Design QA checklist
See `HOME_PLATE_DESIGN_QA.md`.

---

## 41. Token system (implementation shape)
Additive `HP` namespace over `DHDTheme` (not a rewrite), so existing screens keep working during migration:

```
enum HP {
  enum Color  { /* Display-P3 role tokens from §2.1 (+ hp.identity org channel) */ }
  enum Font   { static func display/title/headline/body/callout/caption/eyebrow/number(...) } // custom→SF fallback
  enum Space  { xs=8 sm=12 md=16 lg=24 xl=32 }
  enum Radius { sm=8 md=12 lg=16 xl=18 }
  enum Shadow { card modal subtle }
}
```
Migration: `DHDTheme` becomes a thin alias mapping old → `HP` during rollout, deleted once screens migrate. **Stage‑3 deliverable** (`HOME_PLATE_STAGE3_PLAN.md`).

## 42. First components (Stage 3 roster)
See `HOME_PLATE_COMPONENT_LIBRARY.md` for full APIs. Stage‑3 build order in `HOME_PLATE_STAGE3_PLAN.md`.

## 43. Staged implementation plan
| Stage | Deliverable | Edits production code? |
| --- | --- | --- |
| 1 ✅ | `HOME_PLATE_UI_AUDIT.md` | No |
| 2 ✅ | Manifesto, OS, Design System | No |
| 2b ✅ | Component Library, Workspaces, Motion, Design QA (this pass) | No |
| 3 | `HP` tokens + first components as **isolated previews** (`HOME_PLATE_STAGE3_PLAN.md`) | New files only; no screen swaps — **needs approval** |
| 4 | **Pilot: Finance Overview** redesign; before/after | Yes (one workspace) — **needs approval** |
| 5 | Global shell + navigation | Yes — preserve routing/permissions |
| 6 | Workspace rollout (Finance → Notifications → Communication → Org Admin → Player Today → Parent → Coach → Facilities → Programs → Testing → Analysis → Platform Admin) | Yes, incremental |

**Hard gate:** no production SwiftUI (Stage 3+) until approved. All backend/payments/StoreKit/Supabase/auth/authorization/notification/business‑logic systems remain read‑only (handoff §6, §25).
