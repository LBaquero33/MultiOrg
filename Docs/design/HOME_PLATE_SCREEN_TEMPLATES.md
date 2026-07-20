# HOME PLATE — UNIVERSAL SCREEN TEMPLATES

**Status:** Universal Implementation Kit — Stage 6.
**Absolute path:** `/Users/lb33/Documents/HomePlate-design/Docs/design/HOME_PLATE_SCREEN_TEMPLATES.md`
**Binding companion:** `HOME_PLATE_AI_UI_IMPLEMENTATION_GUIDE.md` (read it first) · machine-readable mirror: `HOME_PLATE_UI_CONTRACT.yaml`.

Every Home Plate screen is one of these 16 templates. **Do not invent a 17th.** If nothing fits, stop and report.

**Legend:** ✅ = buildable today (preview shell exists in `HomePlate/DesignSystem/Templates/`, rendered in `HOME_PLATE_VISUAL_REFERENCE.md`). 🚧 = **spec-only** — the workspace is future and its components do **not** exist yet; building it requires a component stage first.

| # | Template | id | Shell | Status |
| --- | --- | --- | --- | --- |
| 1 | Workspace dashboard | `workspace_dashboard` | `HPWorkspaceScreenTemplate.swift` | ✅ |
| 2 | List / search / filter | `list_search_filter` | `HPListScreenTemplate.swift` | ✅ |
| 3 | Record detail | `record_detail` | `HPDetailScreenTemplate.swift` | ✅ |
| 4 | Form / editor | `form_editor` | `HPFormScreenTemplate.swift` | ✅ |
| 5 | Program execution | `program_execution` | `HPProgramExecutionTemplate.swift` | ✅ |
| 6 | Calendar / scheduling | `calendar_scheduling` | `HPCalendarScreenTemplate.swift` | ✅ |
| 7 | Analytics | `analytics` | `HPAnalyticsScreenTemplate.swift` | ✅ |
| 8 | Communication split | `communication_split` | `HPCommunicationScreenTemplate.swift` | ✅ |
| 9 | Finance | `finance` | `HPWorkspaceScreenTemplate` + `HPAnalyticsScreenTemplate` | ✅ (composed) |
| 10 | Settings / account | `settings_account` | `HPSettingsScreenTemplate.swift` | ✅ |
| 11 | Billing / paywall | `billing_paywall` | `HPStateScreenTemplate(kind: .paywall)` | ✅ |
| 12 | Admin console | `admin_console` | `HPAdminScreenTemplate.swift` | ✅ |
| 13 | Permission / locked / upgrade | `state_screen` | `HPStateScreenTemplate.swift` | ✅ |
| 14 | Game Day | `game_day` | — | 🚧 spec-only |
| 15 | AI evidence | `ai_evidence` | — | 🚧 spec-only |
| 16 | Recruiting profile | `recruiting_profile` | — | 🚧 spec-only |

**Universal rules for all templates:** exactly one `HPButton(.primary)` · HP tokens only · no horizontal overflow at 393/834/1200 · AX3 relayouts (never shrinks) · loading/empty/error are designed states · presentation only.

---

## 1. Workspace dashboard — `workspace_dashboard` ✅

- **Purpose:** orient. Answer "what needs me now?" in one screen, then get out of the way.
- **Anatomy:** `HPWorkspaceHeader` → attention row (0–3) → metric grid → supporting cards.
- **Required:** `HPWorkspaceHeader`, `HPCard`, `HPMetricCard`, `HPSectionHeader`, `HPStatusBadge`.
- **Optional:** `HPStatTile`, `HPChart`, `HPEmptyState`, `HPButton(.secondary)`.
- **Primary action:** one, in the header `trailing` slot (the workspace's main verb).
- **iPhone:** single column; 2-col metric grid; attention rows stack.
- **iPad:** 2–3-col metric grid; cards may pair side by side.
- **macOS:** 3-col grid + sidebar; denser padding.
- **AX3:** metric grid → **1 column**; attention row label above badge.
- **States:** loading = `HPSkeleton` cards (layout-stable) · empty = "You're all caught up" · error = one page-level `HPErrorState` (never per-card error spam) · offline/stale = header badge + "Last updated…" · locked = `state_screen`.
- **Keyboard:** none (read-only surface). Cards are focusable in order.
- **Do:** cap attention at 3 · give every metric a delta or context.
  **Don't:** a wall of 10 equal metrics · two gold buttons · per-card spinners.

```swift
ScrollView {
  VStack(alignment: .leading, spacing: HP.Space.md) {
    HPWorkspaceHeader(title, orgLabel: org, context: range, identity: identity) {
      HPButton(title: "New request", variant: .primary, size: .sm) { … }
    }
    HPCard { HPSectionHeader("Needs attention"); ForEach(attention) { AttentionRow($0) } }
    LazyVGrid(columns: dts.isAccessibilitySize ? [one] : (isWide ? [three] : [two])) {
      ForEach(metrics) { HPMetricCard(title:value:unit:delta:trend:context:valueColor:) }
    }
    HPCard { HPSectionHeader("Today"); ForEach(items) { HPStatTile(label:value:) } }
  }
  .padding(HP.Space.md)
}
.background(HP.Color.bg)
```

---

## 2. List / search / filter — `list_search_filter` ✅

- **Purpose:** find one record among many.
- **Anatomy:** header → `HPSearchBar` → `HPFilterBar` → **result count** → rows → state.
- **Required:** `HPWorkspaceHeader`, `HPSearchBar`, `HPFilterBar`, `HPCard`, `HPTable` (or row cards), `HPEmptyState`.
- **Optional:** `HPStatusBadge`, `HPAvatar`, `HPSegmentedControl` (scope), `HPModalContainer` (row actions).
- **Primary action:** "New <thing>" in the header trailing slot. Row taps are navigation, not primary.
- **iPhone:** stacked row cards (`HPTable` `.auto` → stacked); filters scroll horizontally.
- **iPad:** `HPTable` `.columns`; may become list+detail (see `record_detail`).
- **macOS:** dense table, more columns, sidebar.
- **AX3:** `HPTable` forced `.stacked`; filter pills wrap into a column.
- **States:** loading = skeleton rows · **empty = distinguish "no data yet" from "no match"** (offer "Clear filters") · error = `HPErrorState` + retry · offline = stale badge + cached rows · locked = `state_screen`.
- **Keyboard:** search submits on return; Esc clears; ⌘F focuses search (macOS). Filtering/debounce is the caller's logic — **presentation only**.
- **Do:** always show the result count · keep filters single-purpose.
  **Don't:** hide the count · squeeze a table sideways · make a bare empty list.

```swift
HPCard {
  HPSearchBar(text: $query, placeholder: "Search player or title")
  HPFilterBar(pills: pills, active: $active)
  Text("\(rows.count) results").font(HP.Font.caption).foregroundStyle(HP.Color.textMuted)
}
HPCard {
  HPSectionHeader("Results")
  switch state {
  case .loading: HPLoadingState()
  case .empty:   HPEmptyState(title: "No payments match", actionTitle: "Clear filters", actionIsPrimary: false)
  case .error:   HPErrorState(message: …, onRetry: {})
  case .loaded:  HPTable(columns: cols, rows: rows, layout: dts.isAccessibilitySize ? .stacked : .auto)
  }
}
```

---

## 3. Record detail — `record_detail` ✅

- **Purpose:** everything about one record + its one main action.
- **Anatomy:** identity header (`HPAvatar` + name + status) → key metrics → detail sections → related records → primary action.
- **Required:** `HPCard`, `HPAvatar`, `HPStatusBadge`, `HPMetricCard`, `HPSectionHeader`, `HPStatTile`, `HPButton`.
- **Optional:** `HPTable` (related), `HPChart` (trend), `HPModalContainer` (edit).
- **Primary action:** one, at the bottom in its own card (or header trailing on wide).
- **iPhone:** stacked; 2-col metrics.
- **iPad:** 4-col metrics; related tables in columns.
- **macOS:** master list left + detail right.
- **AX3:** metrics 1-col; identity block stacks (avatar/name above badges).
- **States:** loading = skeleton identity + metrics · empty = "No testing yet" per section (never a blank card) · error = page-level · offline/stale = badge · locked = `state_screen`.
- **Keyboard:** Esc closes if presented modally; ⌘E edit (macOS).
- **Do:** lead with identity · pair every metric with context.
  **Don't:** bury the primary action among five equal buttons · truncate the record name.

```swift
HPCard {                                   // identity
  layout {                                  // HStack, or VStack at AX3
    HPAvatar(name: name, size: .lg)
    VStack(alignment: .leading) { Text(name).font(HP.Font.title); Text(sub).font(HP.Font.caption) }
    HStack { HPStatusBadge(text: "Active", kind: .success) }
  }
}
LazyVGrid(columns: cols) { ForEach(metrics) { HPMetricCard(...) } }
HPCard { HPSectionHeader("Details"); ForEach(fields) { HPStatTile(label:value:) } }
HPCard { HPButton(title: "Assign program", variant: .primary, size: .lg, fullWidth: true) }
```

---

## 4. Form / editor — `form_editor` ✅

- **Purpose:** create or edit exactly one record.
- **Anatomy:** header → grouped field sections → inline validation → action row (one primary).
- **Required:** `HPFormField`, `HPCard`, `HPSectionHeader`, `HPButton`.
- **Optional:** `HPMoneyField` (**mandatory for money**), `HPSegmentedControl` (≤4), HP-styled `Menu` (>4), `HPConfirmationDialog` (discard).
- **Primary action:** one submit; Cancel is `.secondary` beside it (stacked at AX3).
- **iPhone / iPad / macOS:** **single column always**; cap ~720pt and center on wide.
- **AX3:** action row stacks full-width; labels above fields (already the `HPFormField` default).
- **States:** loading = disabled fields + skeleton · empty = n/a · error = **inline on the field** (`error:`) + optional summary · offline = disable submit + explain · saving = `HPButton(isLoading:)`.
- **Keyboard:** Return moves to next field; ⌘Return submits (macOS); Esc = discard → `HPConfirmationDialog` if dirty. The keyboard must never cover the focused field (scroll it into view).
- **Do:** integer cents for money · validate inline · one submit.
  **Don't:** two-column forms · money as `Double` · errors only in an alert · silent validation failure.

```swift
HPCard {
  HPSectionHeader("Details")
  HPFormField(label: "Title", text: $title, helper: "Shown to the parent.")
  HPMoneyField(label: "Amount", cents: $cents, error: invalid ? "Amount must be greater than $0." : nil)
  HPSegmentedControl(options: [(“program”,"Program"), …], selection: $category)
  HPFormField(label: "Notes (optional)", text: $notes, kind: .multiline)
}
HPCard {
  layout {                                   // HStack; VStack at AX3
    HPButton(title: "Send request", variant: .primary, size: .lg, isLoading: isSaving, fullWidth: axl)
    HPButton(title: "Cancel", variant: .secondary, size: .lg, fullWidth: axl)
  }
}
```

---

## 5. Program execution — `program_execution` ✅  *(canonical: `SDPlayerTodayView`, approved)*

- **Purpose:** do today's assigned work with the fewest taps and least typing, standing in a cage.
- **Anatomy:** header (+ Scheduled/Off + Saved/Not-logged badges) → date context → improvement metrics → program + completion ring → per-exercise loggers → sub-activity (BP) → self-assessment → **one gold Submit day**.
- **Required:** `HPWorkspaceHeader`, `HPStatusBadge`, `HPCard`, `HPMetricCard`, `HPProgressIndicator(.ring)`, `HPFormField`, `HPButton(.primary)`, `HPToast`.
- **Optional:** `HPSegmentedControl` (reps type / source), `HPStatTile` (session stats), `HPLoadingState`/`HPEmptyState`/`HPErrorState`.
- **Primary action:** **Submit day** — single, gold, full-width, bottom. Import/Add set/Remove set are `.secondary`.
- **iPhone:** single column; large targets; steppers over keyboards.
- **iPad:** same stack (this is a phone-first task); may widen cards. **Do not** split program/logger unless a task explicitly asks.
- **macOS:** not a primary target (player parity deferred).
- **AX3:** everything single column; button pairs stack full-width via `ViewThatFits`; the ring's inner "%" pins to `.large` (chrome only).
- **States:** loading = `HPLoadingState` · empty = "No program assigned" + still allow self-assessment · error = `HPErrorState` (keep the original `.alert` trigger semantics) · offline = **unchanged behavior** — never invent queueing · success = `HPToast` on the existing trigger.
- **Keyboard:** numeric fields where free entry is needed; Done dismisses; the composer/field must stay visible.
- **Do:** coach instructions read-only and visually distinct (gold eyebrow on a raised surface) · persist **only** on Submit.
  **Don't:** autosave · per-exercise save · next/prev exercise nav · two primaries · retype logic.

```swift
HPWorkspaceHeader("Today", context: prettyDate) {
  HStack { HPStatusBadge(text: scheduled ? "Scheduled" : "Off day", kind: scheduled ? .success : .neutral)
           HPStatusBadge(text: saved ? "Saved" : "Not logged", kind: saved ? .success : .warning) }
}
HPCard { HPSectionHeader("Strength program") { HPProgressIndicator(value: fraction, style: .ring) } … }
HPCard {                                    // per exercise
  HPCard(style: .flat) {
    Text(ex.name).font(HP.Font.headline); Text(programLine).font(HP.Font.caption)
    CoachInstructions(ex.notes)             // read-only, gold eyebrow, surfaceRaised
    Toggle("No weight", isOn: $noWeight).tint(HP.Color.accent)
    if noWeight { Stepper(…) } else { ForEach(sets) { HPFormField(label: "Set \(i) weight", …) } }
    HPFormField(label: "Notes (optional)", text: $notes, kind: .multiline)
  }
}
HPCard { HPButton(title: "Submit day", variant: .primary, size: .lg, isLoading: isSaving, fullWidth: true) }
```

---

## 6. Calendar / scheduling — `calendar_scheduling` ✅

- **Purpose:** see what's scheduled; act on it.
- **Anatomy:** header → scope control (Month/Week/Day) → month grid → day timeline → conflicts/approvals.
- **Required:** `HPWorkspaceHeader`, `HPCard`, `HPSegmentedControl`, `HPSectionHeader`, `HPStatusBadge`.
- **Optional:** `HPEmptyState`, `HPModalContainer` (booking sheet → `form_editor`), `HPConfirmationDialog` (cancel booking).
- **Primary action:** "New booking" in header trailing.
- **iPhone:** grid **or** timeline (scope-switched) — never both at once.
- **iPad / macOS:** month grid left + day timeline right.
- **AX3:** **the 7-col grid is dropped entirely** and replaced by an agenda list. A scaled-down grid is unreadable — this is a relayout, not a shrink.
- **States:** loading = skeleton grid · empty = "Nothing scheduled" + New booking · error = `HPErrorState` · **conflict = `HPStatusBadge(.warning)` + explicit row** (never silently overlap) · offline = read-only + stale badge · locked = `state_screen`.
- **Keyboard:** ←/→ change day, ↑/↓ change week, Return opens the selected day (macOS/iPad).
- **Do:** mark event days with a dot **and** an accessibility label · surface conflicts loudly.
  **Don't:** rely on a colored dot alone · cram a timeline next to a grid on a phone.

```swift
HPCard { HPSegmentedControl(options: [("month","Month"),("week","Week"),("day","Day")], selection: $scope) }
if isWide && !axl { HStack(alignment: .top) { monthGrid; dayTimeline } }
else { if !axl { monthGrid }; dayTimeline }        // AX3 → agenda only
```

---

## 7. Analytics — `analytics` ✅

- **Purpose:** answer "what's trending / what's profitable" with evidence.
- **Anatomy:** header → range control → headline metrics → charts → breakdown table.
- **Required:** `HPWorkspaceHeader`, `HPSegmentedControl` (range), `HPMetricCard`, `HPChart`, `HPTable`, `HPCard`.
- **Optional:** `HPFilterBar`, `HPStatusBadge` (units/range), `HPButton(.secondary)` (export).
- **Primary action:** usually **none** (analysis is read-only). Export is `.secondary`. If there's no real primary verb, don't manufacture one.
- **iPhone:** 2-col metrics; full-width charts; stacked table.
- **iPad:** 3-col metrics; charts side by side.
- **macOS:** 3-col + dense tables.
- **AX3:** metrics 1-col; charts keep a **fixed readable height**; table stacked.
- **States:** loading = skeleton chart blocks · **empty = "Not enough data yet" + what to do** (e.g. "log two testing sessions") · error = `HPErrorState` · offline/stale = "Last updated" · locked = `state_screen` (entitlement-gated reports).
- **Keyboard:** range control is arrow-navigable; table rows focusable.
- **Do:** state units and range on every chart · always ship the table equivalent of a chart.
  **Don't:** chart-only answers · color-only series encoding · a chart with no range label.

```swift
HPCard { HPSegmentedControl(options: [("4W","4W"),("12W","12W"),("6M","6M"),("1Y","1Y")], selection: $range) }
LazyVGrid(columns: cols) { ForEach(metrics) { HPMetricCard(...) } }
HPCard { HPSectionHeader("Exit velocity trend") { HPStatusBadge(text: "mph · 12 weeks", kind: .neutral) }
         HPChart(points: points, style: .line, height: 180) }
HPCard { HPSectionHeader("Breakdown"); HPTable(columns: cols, rows: rows, layout: axl ? .stacked : .auto) }
```

---

## 8. Communication split — `communication_split` ✅

- **Purpose:** read and reply.
- **Anatomy:** conversation list (`HPAvatar` + name + preview + unread) ↔ thread (bubbles + composer).
- **Required:** `HPCard`, `HPAvatar`, `HPStatusBadge` (unread), `HPFormField` (composer), `HPButton(.primary)` (Send).
- **Optional:** `HPSearchBar`, `HPEmptyState`, `HPSectionHeader`, `HPModalContainer` (new chat → `form_editor`).
- **Primary action:** **Send** in the thread; **New** in the list header. Never both visible as gold in the same pane on compact.
- **iPhone:** list → push to thread (one pane at a time).
- **iPad / macOS:** list (≈320pt) left + thread right.
- **AX3:** list only, full width; composer stacks above a full-width Send.
- **States:** loading = skeleton rows · empty = "No conversations yet" + New message · error = `HPErrorState` · offline = composer disabled + "You're offline" · **failed send = explicit retry affordance** (never a silently dropped message).
- **Keyboard:** Return sends (macOS) / newline on iOS; ⇧Return newline; Esc leaves the thread; composer must stay above the keyboard.
- **Do:** unread = badge **and** heavier weight.
  **Don't:** rebuild DM transport or notification producers — presentation only (no duplicate local/remote alerts).

```swift
if isWide && !axl { HStack(alignment: .top) { conversationList.frame(width: 320); thread } }
else { showsThread ? thread : conversationList }
// row: HPAvatar + (name weight = unread ? headline : callout) + preview + HPStatusBadge("2 unread", .gold)
// composer: HPFormField(kind:.multiline) + HPButton("Send", .primary)
```

---

## 9. Finance — `finance` ✅  *(canonical: `FinanceDashboardView`, approved pilot)*

A **composition**, not a new layout: `workspace_dashboard` (overview + metric grid) + `list_search_filter` (payments/requests/refunds) + `analytics` (revenue charts) + `form_editor` (expense editor).

- **Purpose:** run the business at Stripe-level precision.
- **Anatomy:** header (+ **support banner** when platform support) → date-range control → overview metric grid (gross/net/outstanding/expenses/profit) → recent payments → payment requests (filterable) → expenses → refunds.
- **Required:** `HPWorkspaceHeader`, `HPMetricCard` (semantic `valueColor`), `HPCard`, `HPTable`, `HPFilterBar`, `HPStatusBadge`, `HPErrorState`.
- **Optional:** `HPChart`, `HPMoneyField` (expense editor), `HPSearchBar`, `HPModalContainer`.
- **Primary action:** one — "Create expense"/"New request" (support mode: per authorization only).
- **iPhone:** stacked cards. **iPad:** 2-col metric grid + lists. **macOS:** dense grid + tables. **AX3:** 1-col; tables stacked.
- **States:** loading = skeletons · empty = per-section empties · error = **one page-level error card** (not per-section spam) · offline/stale = "Last updated" · **support mode = explicit gold read-only banner**.
- **Keyboard:** range control arrow-navigable; ⌘F search (macOS).
- **Do:** semantic value colors (success/warning/danger) · **integer cents everywhere** · precise, undecorated.
  **Don't:** touch reconciliation/authorization/backend · imply Stripe authority in support mode · use `Double` for money.

---

## 10. Settings / account — `settings_account` ✅

- **Purpose:** identity, org switching, preferences, subscription, sign out.
- **Anatomy:** identity card → grouped sections → subscription → **destructive last**.
- **Required:** `HPCard`, `HPAvatar`, `HPSectionHeader`, `HPStatTile`, `HPButton`.
- **Optional:** `HPStatusBadge` (subscription state), `HPFormField` (profile edit), `HPConfirmationDialog` (sign out), `HPWorkspaceDirectory` (org switch).
- **Primary action:** usually none. Sign out is `.destructive`, isolated at the bottom.
- **iPhone / iPad / macOS:** single column always (cap ~720pt, centered on wide). macOS may use a settings sidebar.
- **AX3:** buttons full-width; rows stack.
- **States:** loading = skeleton identity · error = inline per section · offline = disable mutating rows · **subscription state is presentation only**.
- **Keyboard:** standard form traversal.
- **Do:** put destructive actions last and alone.
  **Don't:** a settings *grid* · alter StoreKit/entitlement verification · place Sign out next to a gold primary.

---

## 11. Billing / paywall — `billing_paywall` ✅

- **Purpose:** explain the value and offer exactly one way to buy.
- **Anatomy:** icon → headline → benefit list → price card → **Subscribe** → Restore → honest fine print.
- **Required:** `HPCard`, `HPButton(.primary)`, `HP.Font.number` (price), `HPStatusBadge` (current state).
- **Optional:** `HPEmptyState`, `HPStatTile` (plan/renewal), `HPErrorState` (purchase failure).
- **Primary action:** **Subscribe** — one, gold, full-width. Restore is `.tertiary`.
- **iPhone:** single column. **iPad/macOS:** capped ~560pt, centered. **AX3:** everything stacks; price never shrinks.
- **States:** loading = disabled button + spinner in the button · **purchase pending = `isLoading`** · error = `HPErrorState` with a real reason · **already subscribed = show state, never re-sell** · offline = disable + explain.
- **Keyboard:** n/a.
- **Do:** state that Apple confirms the purchase before access; 3–5 concrete benefits.
  **Don't:** touch StoreKit/entitlement verification · imply access before Apple confirms · dark-pattern the restore link.

---

## 12. Admin console — `admin_console` ✅

- **Purpose:** manage an organization (or, for platform admin, organizations).
- **Anatomy:** header (+ **support banner**) → section nav → managed lists → feature toggles → danger zone.
- **Required:** `HPWorkspaceHeader`, `HPSegmentedControl` (sections), `HPTable`, `HPCard`, `HPStatusBadge`, `HPButton`.
- **Optional:** `HPSearchBar`, `HPAvatar`, `HPModalContainer`, `HPConfirmationDialog` (**required** for destructive).
- **Primary action:** one — "Invite staff". Archive/delete are `.destructive` in an isolated danger zone.
- **iPhone:** stacked; tables stacked. **iPad:** columns. **macOS:** sidebar + dense tables. **AX3:** section nav becomes a vertical list (`HPSegmentedControl` does this automatically); tables stacked.
- **States:** loading = skeleton rows · empty = per-list empties · error = page-level · **support = explicit gold read-only banner** · locked = `state_screen`.
- **Keyboard:** ⌘F search; Esc closes modals.
- **Do:** keep support mode visually explicit (support ≠ ownership) · confirm destructive actions.
  **Don't:** change authorization logic · imply Stripe/owner authority · put the danger zone near the primary.

---

## 13. Permission / locked / upgrade — `state_screen` ✅

- **Purpose:** explain why the user can't proceed and give exactly one way forward.
- **Anatomy:** icon → title → one-sentence reason → single primary → optional escape → honest fine print.
- **Kinds:** `.locked` (no entitlement/feature), `.paywall` (→ template 11), `.offline`, `.stale`, `.configError`, `.signInRequired`.
- **Required:** `HPCard`, `HPEmptyState` **or** `HPErrorState`, `HPButton`.
- **Optional:** `HPStatusBadge` ("Last updated…"), `HPStatTile`.
- **Primary action:** exactly one (Retry / Subscribe / Sign in / Back).
- **iPhone:** full-bleed centered. **iPad/macOS:** capped ~560pt, centered. **AX3:** stacks; full-width button.
- **Keyboard:** Return triggers the primary.
- **Do:** say **who** can unlock it · say **how old** cached data is.
  **Don't:** dead-end the user · imply entitlement the app hasn't verified · show a raw error string.

---

## 14. Game Day — `game_day` 🚧 **spec-only**

- **Purpose:** live scoring, box score, film, CommandIQ.
- **Anatomy:** scoreboard → base/count state → lineup → play-by-play → box score.
- **Required (DO NOT EXIST YET):** `HPScoreboard`, `HPBaseDiamond`, `HPLineupList`, `HPPlayByPlayRow`, `HPBoxScoreTable`.
- **Tone:** broadcast contrast, very large numerals; readable at arm's length in sun.
- **Primary action:** the scoring verb (coach only); read-only for player/parent.
- **iPhone:** scoreboard pinned + scrolling play-by-play. **iPad/macOS:** scoreboard + lineup + play-by-play columns. **AX3:** scoreboard numerals stay large; play-by-play becomes a plain list.
- **States:** pre-game / live / final / **offline-first event ledger** (immediate local echo → later sync) — offline is a *first-class* state here, unlike every other template.
- **Blocked on:** a component stage for the five components above **and** an offline event-ledger architecture decision. **Do not build this screen from `workspace_dashboard`** — stop and report.

---

## 15. AI evidence — `ai_evidence` 🚧 **spec-only**

- **Purpose:** evidence-backed development intelligence that is never magical.
- **Anatomy:** claim → **facts used** → interpretation → recommendation → confidence → **missing data** → coach-approval banner.
- **Required (DO NOT EXIST YET):** `HPAICard`, `HPEvidenceList`, `HPConfidenceMeter`.
- **Accent:** controlled indigo (distinct from gold CTA) — **an accent token that does not exist yet**.
- **Primary action:** coach approval; players see approved output only.
- **AX3:** confidence must be a **number/word**, never a bar alone.
- **States:** insufficient-data (**a first-class state** — the AI must say what's missing) · pending coach approval · approved · error.
- **Rules:** always show evidence; never present inference as fact; coach approval required before player exposure.
- **Blocked on:** the three components + an indigo accent token + the AI evidence contract. Stop and report.

---

## 16. Recruiting profile — `recruiting_profile` 🚧 **spec-only**

- **Purpose:** a portfolio-grade, credible, college-ready profile.
- **Anatomy:** profile header → **verified** metrics (+ source label) → film reel → coach evaluation → shareable snapshot (consented, revocable).
- **Required (DO NOT EXIST YET):** `HPRecruitingProfileHeader`, `HPVerifiedMetric`, `HPMetricSourceLabel`, `HPFilmReel`, `HPCoachEvaluationCard`, `HPRecruitingSnapshotCard`.
- **Primary action:** share/generate snapshot (consent-gated).
- **AX3:** film reel becomes a titled list; verified badges stay text.
- **States:** unverified vs verified (**must be visually distinct — credibility is the product**) · no film · consent not granted · revoked.
- **Rules:** never present an unverified metric as verified; sharing is explicitly consented and revocable; media handling/consent needs a privacy decision before build.
- **Blocked on:** six components + verification model + consent/sharing decision (incl. SportsForce). Stop and report.

---

## Coverage gaps (report honestly, don't improvise)

| Gap | Impact |
| --- | --- |
| Templates 14–16 have **no components and no shells** | Game Day / AI / Recruiting cannot be built without a prior component stage. |
| No `HPStepper` / `HPToggle` | Program execution uses native `Stepper`/`Toggle` tinted with `HP.Color.accent`. Fine today; a component would standardize targets. |
| No `HPDateRangeControl` / `HPDatePicker` | Finance/Calendar use `HPSegmentedControl` + native `DatePicker` tinted gold. |
| No `HPSkeleton` variants for tables/metrics | `HPSkeleton` exists as a block; table/metric skeletons are hand-composed. |
| No indigo accent token | Blocks `ai_evidence`. |
| No `HPConversationRow` / `HPPaymentRow` / `HPNotificationCenter` | Composed by hand from `HPAvatar`/`HPStatTile`/`HPTable` today. |
