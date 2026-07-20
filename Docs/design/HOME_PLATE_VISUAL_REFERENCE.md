# HOME PLATE — VISUAL REFERENCE

**Status:** Universal Implementation Kit — Stage 6 (approved).
**Repository path:** `Docs/design/HOME_PLATE_VISUAL_REFERENCE.md`
**Companions:** `Docs/design/HOME_PLATE_AI_UI_IMPLEMENTATION_GUIDE.md` (binding) · `Docs/design/HOME_PLATE_SCREEN_TEMPLATES.md` · `Docs/design/HOME_PLATE_SCREEN_MIGRATION_MAP.md` · `Docs/design/HOME_PLATE_UI_CONTRACT.yaml` · `Docs/design/HOME_PLATE_DESIGN_SYSTEM.md`.

> **This document is backed by real renders, not mockups.** Every image below was produced by `HomePlateTests/HPTemplateRenderTests.swift` from the actual approved components. **If your screen doesn't look like these, your screen is wrong.**
>
> All image paths are **repository-relative** and live in `Docs/design/visuals/` — they travel with the repo and depend on no external directory.

---

## 0. The visual contract — curated canonical renders

`Docs/design/visuals/` holds a **curated 15-image contract set**, not the full sweep. The complete matrix (44 = 11 templates × 4 viewports) is **regeneratable at any time**:

```bash
xcodebuild test-without-building -project HomePlate.xcodeproj -scheme HomePlate \
  -destination "platform=iOS Simulator,id=<UDID>" -derivedDataPath <derived-data> \
  -only-testing:HomePlateTests/HPTemplateRenderTests
```

Naming: `tmpl-<template_id>-<viewport>.png` · viewports: `iphone` (393 @ `.large`), `iphone-ax3` (393 @ `.accessibility3`), `ipad` (834), `macos` (1200).

### 0.1 Baseline — one normal-iPhone render per buildable template

These 11 images are the **baseline every screen must match at iPhone width**. They cover all **13 buildable templates** (§0.3 explains the two intentional aliases).

| Template id | Viewport | Image (repository-relative) | What future AI agents must match |
| --- | --- | --- | --- |
| `workspace_dashboard` | iPhone 393 `.large` | `Docs/design/visuals/tmpl-workspace_dashboard-iphone.png` | Org identity mark + eyebrow → title → context; **one gold** header action; attention rows capped at 3 (icon + label + `HPStatusBadge`); 2-col metric grid with semantic `valueColor` + trend arrows; `HPStatTile` list. |
| `list_search_filter` | iPhone 393 `.large` | `Docs/design/visuals/tmpl-list_search_filter-iphone.png` | `HPSearchBar` → horizontally-scrolling `HPFilterBar` (active = gold tint + gold outline) → **visible result count** → `HPTable` stacked rows with status badges. |
| `record_detail` | iPhone 393 `.large` | `Docs/design/visuals/tmpl-record_detail-iphone.png` | Identity header (`HPAvatar` lg + name in `HP.Font.title` + status badges) → 2-col metrics → `HPStatTile` details → related table → **one** gold primary in its own bottom card. |
| `form_editor` | iPhone 393 `.large` | `Docs/design/visuals/tmpl-form_editor-iphone.png` | **Single column**; UPPERCASE eyebrow labels above fields; `HPMoneyField` for money (integer cents); `HPSegmentedControl` for ≤4 options; gold submit + `.secondary` Cancel. |
| `program_execution` | iPhone 393 `.large` | `Docs/design/visuals/tmpl-program_execution-iphone.png` | Header + `Scheduled`/`Not logged` badges → program card + gold completion ring → `HPCard(.flat)` logger with **gold-eyebrow read-only coach instructions on `surfaceRaised`** → **one** gold full-width "Submit day". |
| `calendar_scheduling` | iPhone 393 `.large` | `Docs/design/visuals/tmpl-calendar_scheduling-iphone.png` | Scope `HPSegmentedControl` → month grid (gold selected day, event dots + accessibility labels) → day timeline with an explicit conflict badge. |
| `analytics` | iPhone 393 `.large` | `Docs/design/visuals/tmpl-analytics-iphone.png` | Range control → 2-col metrics → `HPChart` **labeled with range + units** → **table equivalent always present**; no primary action. |
| `communication_split` | iPhone 393 `.large` | `Docs/design/visuals/tmpl-communication_split-iphone.png` | List-only on compact; unread = **badge *and* heavier name weight**; `HPAvatar` + 2-line preview. |
| `settings_account` | iPhone 393 `.large` | `Docs/design/visuals/tmpl-settings_account-iphone.png` | Single column; identity card; grouped sections; subscription is **presentation only**; **destructive Sign out last and alone**. |
| `admin_console` | iPhone 393 `.large` | `Docs/design/visuals/tmpl-admin_console-iphone.png` | **Explicit gold `Read-only` platform-support banner**; section `HPSegmentedControl`; staff table; feature toggles; isolated danger zone. |
| `state_screen` (= `billing_paywall`) | iPhone 393 `.large` | `Docs/design/visuals/tmpl-state_screen-iphone.png` | Icon → title → one-sentence reason → benefit list → price (`HP.Font.number`) → **one** gold Subscribe → `.tertiary` Restore → honest "Apple confirms the purchase" fine print. |

### 0.2 Canonical viewport exemplars

| Template id | Viewport | Image (repository-relative) | What future AI agents must match |
| --- | --- | --- | --- |
| `program_execution` | **iPhone AX3** 393 `.accessibility3` | `Docs/design/visuals/tmpl-program_execution-iphone-ax3.png` | **The AX3 contract.** Everything single-column; Add/Remove-set stack full-width via `ViewThatFits`; the ring's inner `%` pinned to `.large` (chrome only); **nothing shrinks, nothing truncates**. The render is extremely tall — correct, not a bug. |
| `form_editor` | **iPhone AX3** 393 `.accessibility3` | `Docs/design/visuals/tmpl-form_editor-iphone-ax3.png` | Labels above fields; `HPSegmentedControl` becomes a **vertical checklist**; submit/cancel stack full-width; helper/error text wraps (never truncates). |
| `workspace_dashboard` | **iPad** 834 `.large` | `Docs/design/visuals/tmpl-workspace_dashboard-ipad.png` | Regular width: metric grid widens (2–3 col); header stays one row with the single gold action; cards keep the surface ladder — **denser, not different**. |
| `analytics` | **macOS** 1200 `.large` | `Docs/design/visuals/tmpl-analytics-macos.png` | Wide width: 3-col metrics, full-width charts, dense `HPTable` columns; same tokens and rhythm as iPhone — **scale, don't redesign**. |

### 0.3 Templates without a standalone render (intentional)

| Template id | Why | Match instead |
| --- | --- | --- |
| `billing_paywall` | It **is** `HPStateScreenTemplate(kind: .paywall)` — the canonical `state_screen` example renders the paywall, so the image is shared. | `Docs/design/visuals/tmpl-state_screen-iphone.png` |
| `finance` | A **composition**, not a new layout: `workspace_dashboard` + `list_search_filter` + `analytics` + `form_editor`. | Those four baselines, plus the approved Finance pilot (regenerate via `HomePlateTests/FinanceRenderTests.swift`). |

### 0.4 Approved production pilots (canonical, regeneratable)

| Pilot | Producing harness | Status |
| --- | --- | --- |
| Player Program Day (`SDPlayerTodayView`) | `HomePlateTests/PlayerTodayRenderTests.swift` | **approved** — canonical `program_execution` production example (all states × iPhone/AX3/iPad + live editable controls). |
| Finance Overview (`FinanceDashboardView`) | `HomePlateTests/FinanceRenderTests.swift` | **approved** — canonical `finance` production example. |
| Component gallery | `HomePlateTests/HPGalleryRenderTests.swift` (source: `HomePlate/DesignSystem/Preview/HPComponentGallery.swift`) | approved foundation. |

---

## 1. Palette

Dark-first. **No light mode in Phase 10.** Display-P3 approximations of the site's OKLCH tokens — source of truth: `HomePlate/DesignSystem/Tokens/HPColor.swift`.

### Surfaces (the ladder)
| Token | Hex | Use |
| --- | --- | --- |
| `HP.Color.bg` | `#0F110C` | App background. The page is always this. |
| `HP.Color.surface` | `#1A1E16` | Flat card / popover / workspace header. |
| `HP.Color.surfaceRaised` | `#262B21` | Elevated card, coach-instruction callout, toast, segmented track. |
| `HP.Color.surfaceMuted` | `#20241A` | Muted fills. |
| `HP.Color.input` | `#2E3327` | Field fill. |
| `HP.Color.border` | `#333829` | Hairline. |
| `HP.Color.borderStrong` | `#474D3B` | Section containers, secondary button outline. |

### Text
| Token | Hex | Use |
| --- | --- | --- |
| `HP.Color.text` | `#ECE8DD` | Cream — primary text, metric values. |
| `HP.Color.textMuted` | `#A6A394` | Secondary, captions, eyebrows. |
| `HP.Color.textTertiary` | `#C8C4B4` | Tertiary controls (brighter than muted). |

### Brand / semantic (**HP-owned — never overridden by org branding**)
| Token | Hex | Use |
| --- | --- | --- |
| `HP.Color.primary` | `#2E7D57` | Field green — identity/brand surfaces. |
| `HP.Color.primaryGlow` | `#46B07C` | Brighter green. |
| `HP.Color.accent` | `#D6B370` | **Gold — the single primary CTA, focus ring, value emphasis.** |
| `HP.Color.accentText` | `#2B2A1E` | Text on gold. |
| `HP.Color.success` | `#46B07C` | Positive / verified / paid. |
| `HP.Color.warning` | `#E0A33E` | Outstanding / stale / conflict. |
| `HP.Color.danger` | `#D0453E` | Failed / overdue / destructive. |
| `HP.Color.info` | `#5A9BD6` | Informational only. |

### Organization brand (**chrome only**)
`HPIdentity.primary/secondary` may tint: the workspace-header gradient mark, `HPAvatar`, directory tiles. The example org is crimson `#B02638` → `#7A1A28` — see the header mark in `Docs/design/visuals/tmpl-workspace_dashboard-iphone.png`.
**Never** as: a button fill, a status color, a focus ring, a chart series, or any semantic meaning.

**Do / Don't:** ✅ gold = the one action. ❌ gold for decoration, or two gold buttons on one screen. ❌ `Color.blue`/`.red`/`Color(.systemBackground)`/hex literals anywhere.

---

## 2. Typography hierarchy

Source: `HomePlate/DesignSystem/Tokens/HPFont.swift`. SF Pro today; `displayFamily`/`textFamily` hooks switch every call site to Archivo / Instrument Sans later **without any API change**. All tokens are Dynamic-Type relative.

| Token | Size / weight | Relative to | Use |
| --- | --- | --- | --- |
| `HP.Font.display` | 34 bold, tracking −0.5 | `.largeTitle` | Hero numerals only. |
| `HP.Font.title` | 22 bold, tracking −0.3 | `.title2` | Workspace / record title. |
| `HP.Font.headline` | 17 semibold | `.headline` | Section headers, card titles, exercise names. |
| `HP.Font.body` | 16 regular | `.body` | Field text. |
| `HP.Font.callout` | 15 regular | `.callout` | Primary reading text, list rows. |
| `HP.Font.caption` | 13 medium | `.caption` | Secondary / context / help. |
| `HP.Font.eyebrow` | 12 semibold, tracking +0.6, **UPPERCASED** | `.caption` | Metric titles, field labels, section eyebrows. |
| `HP.Font.badge` | 12 bold | `.caption` | `HPStatusBadge`. |
| `HP.Font.number(_:weight:)` | monospaced digits | any | **All money / stats** — tabular figures so columns align. |

**Rules:** metric values always `HP.Font.number()` · eyebrow labels are uppercased by the component (don't pre-uppercase) · never `.font(.headline)` directly in a screen.

---

## 3. Surface ladder in practice

```
HP.Color.bg               ← page
└─ HPCard(.elevated)      ← surfaceRaised + border + HP.Shadow.card   (default card)
   └─ HPCard(.flat)       ← surface + border, no shadow                (nested: exercise logger, price card)
      └─ surfaceRaised    ← callouts inside flat cards (coach instructions)
```
Radii: `HP.Radius.sm 8` (chips / day cells) · `md 12` (buttons / fields / toasts) · `lg 16` (cards / headers) · `xl 18` (modals). Spacing: `HP.Space.xs 8 / sm 12 / md 16 / lg 24 / xl 32`. **Never a magic number.**

---

## 4. Button hierarchy

| Variant | Look | Rule |
| --- | --- | --- |
| `.primary` | Gold fill, `accentText` label | **Exactly one per screen.** The verb you came for. |
| `.secondary` | Transparent + 1.5pt `borderStrong` outline | Everything else actionable. |
| `.tertiary` | Text-only, `textTertiary` | Low-emphasis (Restore purchases, View all). |
| `.destructive` | `danger` fill | Isolated, bottom, confirmed. |

Sizes: `.sm` 28pt · `.md` 36pt · `.lg` **44pt (min tap target)**. `fullWidth: true` for AX3 / stacked. Disabled = 32% opacity + 50% saturation. `isLoading` shows an in-button spinner and disables it.

**Canonical:** `Docs/design/visuals/tmpl-workspace_dashboard-iphone.png` (one gold "New request") · `Docs/design/visuals/tmpl-form_editor-iphone.png` (gold Send + secondary Cancel) · `Docs/design/visuals/tmpl-settings_account-iphone.png` (destructive Sign out, alone at the bottom).
**Don't:** two golds · `.borderedProminent` · destructive adjacent to primary.

---

## 5. Cards

`HPCard(style:)` — `.elevated` (default) or `.flat` (nested). Always `HP.Space.md` padding, `HP.Radius.lg`, 1pt `border`. Cards **contain** sections; they don't decorate. A card with one line of text is usually a mistake — use `HPStatTile`.

---

## 6. Metric layouts

`HPMetricCard` = **eyebrow title → value (+unit) → delta (+trend arrow) → context**. Value uses tabular figures; `ViewThatFits` keeps value+unit side by side, stacking rather than fragmenting (never `88.\n4`).

| Grid | iPhone | iPad | macOS | AX3 |
| --- | --- | --- | --- | --- |
| Columns | 2 | 2–3 | 3–4 | **1** |

Trend: `.up` success ↗ · `.down` danger ↘ · `.flat` muted →. Finance sets semantic `valueColor` (net = success, outstanding = warning, expenses = danger). **A number with no delta or context is a design smell.**
**Canonical:** `Docs/design/visuals/tmpl-workspace_dashboard-iphone.png` · `Docs/design/visuals/tmpl-analytics-iphone.png` · `Docs/design/visuals/tmpl-analytics-macos.png`.

---

## 7. Forms

`HPFormField` = UPPERCASE eyebrow label → field on `input` fill → helper **or** error line. Focus = 2pt gold ring. Error = 2pt `danger` + danger text.
`HPMoneyField` = **integer cents**, tabular figures — the only way to enter money.
Single column at every width; cap ~720pt centered on wide. Labels above fields (never leading labels — they break at AX3).
**Canonical:** `Docs/design/visuals/tmpl-form_editor-iphone.png` and `Docs/design/visuals/tmpl-form_editor-iphone-ax3.png`.
**Don't:** `.roundedBorder` · side-by-side fields · `Double` money · error only in an alert.

---

## 8. Tables

`HPTable(columns:rows:layout:)` — `.auto` (stacks when tight) · `.columns` (wide) · `.stacked` (**forced at AX3**). Numeric columns are trailing + tabular. Status is an `HPStatusBadge` in the row, never a bare colored cell. Wide tables scroll **inside** their card — the page never scrolls sideways.
**Canonical:** `Docs/design/visuals/tmpl-analytics-macos.png` (dense columns) vs `Docs/design/visuals/tmpl-list_search_filter-iphone.png` (stacked rows).

---

## 9. Charts

`HPChart(points:style:height:)` — native Swift Charts, `.line` or `.bar`, gold series on the surface ladder. Default height 180.
**Rules:** always label range + units (an `HPStatusBadge` like `mph · 12 weeks` beside the section header) · **always ship the table equivalent** (charts are not accessible alone) · never encode meaning by color alone · fixed readable height at AX3 (charts don't grow with type size).
**Canonical:** `Docs/design/visuals/tmpl-analytics-iphone.png` · `Docs/design/visuals/tmpl-analytics-macos.png`.

---

## 10. Filters

`HPSearchBar` (leading magnifier, clear button, gold focus ring) → `HPFilterBar` of `HPDataPill`s (active = gold tint + gold outline; inactive = `surfaceRaised` + muted) → **result count, always visible**. Pills scroll horizontally on compact, wrap at AX3.
**Canonical:** `Docs/design/visuals/tmpl-list_search_filter-iphone.png`.

---

## 11. Navigation

- **iPhone:** ≤5 tabs (hard cap) + `HPWorkspaceDirectory` for overflow. Player: Today · Calendar · Trends · Chat · More.
- **iPad / macOS:** `HPSidebar` (org identity mark + grouped workspaces + locked/preview markers) + content.
- `HPWorkspaceHeader` is the top of **every** workspace: identity mark → eyebrow org label → title → context line → one trailing action. At AX3 the trailing action drops below the title block, full width.
- Inaccessible workspaces are **not shown**; `locked`/`preview` items are explicitly marked, never silently broken.
**Canonical:** the header in every `Docs/design/visuals/tmpl-*.png`.

---

## 12. Status badges

`HPStatusBadge(text:kind:)` — capsule, 20% tint fill, 40% tint outline, bold 12pt label. Kinds: `neutral` (muted / `textTertiary` label) · `success` · `warning` · `danger` · `info` · `gold`.
**Always a color *and* a word.** `Scheduled`/`Off day`, `Saved`/`Not logged`, `Paid`/`Overdue`/`Failed`, `Read-only` (support), `2 unread`, `Stale`.
**Canonical:** `Docs/design/visuals/tmpl-workspace_dashboard-iphone.png` (Overdue / Conflict / Review) · `Docs/design/visuals/tmpl-admin_console-iphone.png` (gold `Read-only` support banner).
**Don't:** a colored dot with no word · a badge that restates the row verbatim.

---

## 13. Program execution (the canonical player surface)

Reference: `Docs/design/visuals/tmpl-program_execution-iphone.png` (+ AX3: `Docs/design/visuals/tmpl-program_execution-iphone-ax3.png`). Approved production equivalent: regenerate via `HomePlateTests/PlayerTodayRenderTests.swift`.

Anatomy, top to bottom: header (Today + date + `Scheduled` + `Not logged`) → date card → improvement metrics (2-col) → program card + completion ring → per-exercise `HPCard(.flat)` loggers → BP section → self-assessment → **one gold "Submit day"**.

Per-exercise logger detail:
- name (`headline`) + `3 x 5 • lb` (`caption`, muted)
- **Coach instructions** — gold `eyebrow` label + text on `surfaceRaised`, visually distinct and read-only
- `No weight` toggle (gold tint) + muted caption explaining it
- weight fields as `HPFormField` per set (label `SET 1 WEIGHT`) **or** a `Stepper` when `noWeight`
- `Add set` / `Remove set` — `.secondary`, `ViewThatFits` → stacked full-width at AX3
- `Notes (optional)` multiline

Ring: gold trim on `surfaceRaised`, inner `%` pinned to `.large` (chrome), `.accessibilityValue("N percent")`.
**Don't:** autosave · per-exercise save · a second gold button · coach text styled like player input.

---

## 14. Loading / empty / error states

| State | Look |
| --- | --- |
| Loading | `HPLoadingState` — small spinner + muted copy ("Loading today's program…"), centered. Prefer `HPSkeleton` blocks for cards/tables (layout-stable, pulse suppressed under Reduce Motion). |
| Empty | `HPEmptyState` — 30pt muted glyph → headline → muted one-liner → **optional single CTA**. Copy is specific and encouraging, never "No data". |
| Error | `HPErrorState` — 28pt `danger` triangle → "Something went wrong" → human message → gold Retry. **Never** a raw `localizedDescription` as the UI. |
| Offline / stale | `HPStatusBadge(.warning)` + "Last updated 12 min ago" + Refresh (`.secondary`). Never silently present stale as fresh. |
| Locked / paywall | `HPStateScreenTemplate` — icon → title → reason → one primary → honest fine print. |
| Success | `HPToast` via `.hpToast($text)` — `surfaceRaised` + border + modal shadow, top, ~1.3s, Reduce-Motion aware. |

**Canonical:** `Docs/design/visuals/tmpl-state_screen-iphone.png`. Per-state production examples regenerate via `HomePlateTests/PlayerTodayRenderTests.swift` (loading / error / no-program / submit-success).

---

## 15. Viewport behavior

### iPhone normal (393 @ `.large`)
Single column · 2-col metrics · stacked tables · horizontal filter pills · one pane · 44pt targets.
Reference: the 11 baseline images in §0.1.

### iPhone AX3 (393 @ `.accessibility3`) — **the hard case**
**Layout changes; type never shrinks.**
- Metric grids → **1 column**
- `HPTable` → **forced `.stacked`**
- `HPSegmentedControl` → **vertical checklist** (automatic)
- `HPWorkspaceHeader` trailing → **below** the title, full width
- Button pairs → stacked, `fullWidth`
- Calendar month grid → **dropped for an agenda list**
- Communication → **list only** (no split)
- Renders are very tall — correct, not a bug.
Reference: `Docs/design/visuals/tmpl-program_execution-iphone-ax3.png` · `Docs/design/visuals/tmpl-form_editor-iphone-ax3.png`.

### iPad (834)
2–3-col metrics · `HPTable` columns · month grid + day timeline split · list + thread split · forms capped 720pt centered.
Reference: `Docs/design/visuals/tmpl-workspace_dashboard-ipad.png`.

### macOS (1200)
3–4-col metrics · dense tables · `HPSidebar` + content · same tokens, tighter rhythm. Player/parent macOS parity is **deferred** — coach/owner surfaces first.
Reference: `Docs/design/visuals/tmpl-analytics-macos.png`.

---

## 16. Motion

`HP.Motion.instant .10` (press) · `quick .18` (toasts / segments) · `standard .25` · `emphasis` spring (modals). Always route through `HP.animation(_:reduceMotion:)` or use HP components (already Reduce-Motion aware). Never re-add motion on top of a component. Shadows only via `.hpShadow(HP.Shadow.card/modal/subtle)`.

---

## 17. Visual QA checklist

- [ ] Page is `HP.Color.bg`; cards climb the surface ladder
- [ ] Exactly one gold `.primary`
- [ ] Every metric has a delta or context; values tabular
- [ ] Every status = color **+** word
- [ ] Org brand only on avatar / header mark / directory tile
- [ ] Money = `HPMoneyField` / integer cents
- [ ] Charts labeled with range + units **and** have a table equivalent
- [ ] Loading / empty / error / offline / stale all designed
- [ ] AX3 relayouts (1-col, stacked, agenda) — nothing shrunk, nothing truncated
- [ ] No horizontal page scroll at 393 / 834 / 1200
- [ ] Matches the corresponding image in `Docs/design/visuals/`
