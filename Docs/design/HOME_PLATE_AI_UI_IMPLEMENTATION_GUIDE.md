# HOME PLATE — AI UI IMPLEMENTATION GUIDE

**Status:** Universal Implementation Kit — Stage 6. Authoritative instruction manual for **any** AI agent (Claude, Codex, other) building or redesigning a Home Plate screen.
**Absolute path:** `/Users/lb33/Documents/HomePlate-design/Docs/design/HOME_PLATE_AI_UI_IMPLEMENTATION_GUIDE.md`
**Companions:** `HOME_PLATE_SCREEN_TEMPLATES.md` · `HOME_PLATE_SCREEN_MIGRATION_MAP.md` · `HOME_PLATE_VISUAL_REFERENCE.md` · `HOME_PLATE_UI_CONTRACT.yaml` (machine-readable) · `HOME_PLATE_DESIGN_SYSTEM.md` · `HOME_PLATE_COMPONENT_LIBRARY.md` · `HOME_PLATE_OS.md` · `HOME_PLATE_WORKSPACES.md` · `HOME_PLATE_MANIFESTO.md`.

> **Read this before touching any screen.** If you follow this guide, your screen will look like Home Plate and behave exactly as it did before. If you improvise layout, you are doing it wrong — pick a template.

---

## 0. The one-paragraph version

Home Plate OS is a **presentation layer**. You are never allowed to change what a screen *does* — only what it *looks like*. Every screen maps to one of 16 universal templates. You inspect the screen, record a behavior manifest, pick its template from the migration map, replace only the view builders with HP components, verify the manifest is byte-for-byte unchanged, then build, test, and screenshot. One gold primary action per screen. No raw colors. No invented layouts.

---

## 1. Authoritative design principles

These come from `HOME_PLATE_MANIFESTO.md` and the two approved pilots (Finance Overview, Player Program Day). They are not negotiable.

1. **Presentation only.** Business logic, persistence, and authorization are read-only. A redesign that changes behavior is a bug, not a design.
2. **Context over raw numbers.** A number alone is not an answer. `88.4` is noise; `88.4 mph, +2.3 vs 30 days ago, personal best` is information. Use `HPMetricCard`.
3. **One dominant action per screen.** Exactly one `HPButton(.primary)` (gold). If two things look equally important, neither is.
4. **Calm, dark, dense-but-breathable.** Dark-first (no light mode in Phase 10). Field green + gold accent on green-charcoal. Decoration is not design.
5. **Honest states.** Loading, empty, error, offline, and stale are designed states with copy — never a spinner in a void, never a silent lie about freshness.
6. **Never color alone.** Every status pairs a color with a word (`HPStatusBadge`). Unread pairs a badge with a weight change.
7. **Org brand = identity chrome only.** An organization's color may tint an avatar, a header mark, or a directory tile. It may **never** become a semantic color (primary/accent/success/danger/focus). HP owns semantics.
8. **Accessibility is a layout, not a scale factor.** At AX sizes you *change the layout* (stack, single-column, agenda-instead-of-grid) — you do not shrink text.
9. **Minimize typing.** Steppers, toggles, and segmented controls beat keyboards on a phone in a cage.
10. **The pilots are canon.** When this guide is ambiguous, match `SDPlayerTodayView` (program execution) or `FinanceDashboardView` (dashboard/finance).

---

## 2. Protected business-logic boundaries — **READ-ONLY, ALWAYS**

You may **not** add, remove, reorder, rename, or alter any of the following, in any screen, for any reason:

| Protected | Meaning |
| --- | --- |
| `@State` / `@Binding` / `@EnvironmentObject` / `@Environment` / stored properties | Count **and** names must be identical before and after. |
| `async` functions | Same names, same signatures, same bodies. |
| `SupabaseService` calls | Same methods, same **call order**, same parameters, same call sites. |
| Lifecycle modifiers | `.task` / `.onAppear` / `.onChange` / `.refreshable` / `.onDisappear` / `.fileImporter` / `.alert` — same triggers. |
| Persistence timing | When data saves, and what a submit does. |
| Validation & completion rules | Any computation that decides "is this logged/valid/complete". |
| Offline behavior | What happens with no network. |

**Never touch these files/systems:** Supabase & `SupabaseService`, models (`SDModels.swift`), ViewModels, networking, authorization/permissions, StoreKit & entitlements, notifications/APNs, finance reconciliation logic, player-program persistence, backend, `MultiOrg/DesignSystem/**` (unless the task explicitly authorizes a component change), and the Codex checkout at `/Users/lb33/Documents/HomePlate`.

**Hard rules:**
- **Do not extract a ViewModel.** Several screens interleave logic and presentation in one file (e.g. `SDPlayerTodayView`). That is intentional for now. Restyle the view builders in place.
- **Do not add autosave**, per-item saving, or next/prev navigation.
- **Do not reorder network calls** — even if the new order looks better.
- You *may* change a **visual** presentation of a trigger (an alert → an `HPErrorState`), but **never the trigger itself**.

---

## 3. Mandatory preflight workflow

Run this **before writing any code**. Do not skip it because the change "looks small".

```bash
cd /Users/lb33/Documents/HomePlate-design
pwd                       # must be the design worktree
git branch --show-current # must be design/home-plate-os
git status --porcelain    # must be clean (or only your in-scope files)
git log -3 --oneline
```

**Environment notes (learned the hard way):**
- This is a **git worktree** sharing `/Users/lb33/Documents/HomePlate/.git`. If `git status` hangs, the index is stat-stale: run `git update-index -q --refresh` (can take minutes) — do **not** delete anything.
- Only **one agent** may drive this worktree at a time. If another agent (Codex) is mid-build or holding the index, **stop and report** — do not race it.
- **XcodeGen is not vendored.** Build it from a temp copy when authorized:
  ```bash
  cp -R /Users/lb33/Documents/HomePlate/XcodeGen /tmp/hp-xcodegen-src   # read-only copy, requires explicit permission
  swift build --package-path /tmp/hp-xcodegen-src -c release --scratch-path /tmp/hp-xcodegen-build
  /tmp/hp-xcodegen-build/release/xcodegen generate --spec project.yml --project .
  ```
  Regenerate whenever you **add or delete** a `.swift` file. Never hand-edit `project.pbxproj`.
- **Secrets:** `Configs/Secrets.xcconfig` is gitignored. If missing, it must be restored before builds.
- All build output goes to `/tmp` (`-derivedDataPath /tmp/hp-dd-ios`, `/tmp/hp-dd-mac`). Never into the repo.

---

## 4. How to inspect an existing screen

1. **Read the whole file.** Not a grep — the whole thing. Screens hide logic in computed properties.
2. **Find its row** in `HOME_PLATE_SCREEN_MIGRATION_MAP.md` (role, template, protected deps, risk).
3. **Record the BEFORE manifest** (see §5). This is your contract.
4. **Identify the seams:** which computed properties are *pure presentation* (`headerCard`, `programCard`) versus which are logic (`reloadDay`, `submitDay`). You only rewrite the former.
5. **List every DHD component in use** — each maps to an HP replacement (§7).

### BEFORE/AFTER manifest command (use verbatim)

```bash
for f in <file1> <file2>; do
  echo "== $f =="
  echo -n "@State count: "; grep -cE "@State" "$f"
  echo "async funcs:";     grep -oE "func [a-zA-Z]+\([^)]*\) async( throws)?" "$f"
  echo "supabase calls:";  grep -oE "supabase\.(client\.auth\.session|[a-zA-Z]+\()" "$f" | sort | uniq -c
  echo "lifecycle:";       grep -oE "\.(task|onChange|onAppear|refreshable|onDisappear|fileImporter|alert)\b" "$f" | sort | uniq -c
done
```

Run it **before** you edit and **after** you finish. The two outputs must be **identical**. If they differ by even one line, you changed behavior — revert and try again.

---

## 5. State requirements

Every screen must be able to render **all** of the states that apply to it. A screen that only handles the happy path is incomplete.

| State | Component | Rule |
| --- | --- | --- |
| Loading | `HPLoadingState` / `HPSkeleton` | Prefer skeletons for cards/tables (layout-stable). Never a bare spinner. |
| Empty | `HPEmptyState` | Specific, encouraging copy + a next step. Never a dead end. |
| Error | `HPErrorState` | Human message + retry. Never dump `error.localizedDescription` as the whole UI. |
| Offline | `HPStateScreenTemplate(.offline)` | Say what's shown and how old it is. |
| Stale | `HPStatusBadge(.warning)` + "Last updated…" | Never silently present stale data as fresh. |
| Locked | `HPStateScreenTemplate(.locked)` | Explain *why* + who can unlock. Never imply unverified entitlement. |
| Success | `HPToast` via `.hpToast($binding)` | Same trigger as before; visual may change. |

---

## 6. How to select a screen template

1. Look up the screen in `HOME_PLATE_SCREEN_MIGRATION_MAP.md` → use the **assigned template**.
2. If it isn't listed (new screen), choose by the **primary user question**:

| The user is trying to… | Template |
| --- | --- |
| Orient / see what needs them | `workspace_dashboard` |
| Find one record among many | `list_search_filter` |
| See everything about one record | `record_detail` |
| Create or edit a record | `form_editor` |
| Do today's assigned work | `program_execution` |
| See what's scheduled / book | `calendar_scheduling` |
| Understand a trend / profitability | `analytics` |
| Read and reply | `communication_split` |
| Change their own account | `settings_account` |
| Manage an org / staff | `admin_console` |
| Be told why they can't proceed | `state_screen` |

3. **Never invent a 17th layout.** If nothing fits, **stop and report** — propose the template rather than improvising.
4. Open the matching shell in `MultiOrg/DesignSystem/Templates/` and the matching render in the visual reference. Match it.

---

## 7. Component selection rules

**Use only approved HP components.** Never a raw SwiftUI control where an HP component exists.

| Need | Use | Never |
| --- | --- | --- |
| Page title / org context | `HPWorkspaceHeader` | `DHDHeaderCard`, ad-hoc VStack titles |
| Surface | `HPCard` (`.elevated` / `.flat`) | `DHDCard`, `Color(.systemBackground)` |
| Number with meaning | `HPMetricCard` | bare `Text` |
| Compact label/value row | `HPStatTile` | ad-hoc `HStack + Spacer` |
| Section title | `HPSectionHeader` | `DHDSectionHeader`, bare `Text().font(.headline)` |
| Action | `HPButton` | `.borderedProminent`, `.bordered` |
| Status | `HPStatusBadge` | `DHDStatusPill`, `DHDStatusBadge`, colored dots alone |
| Text input | `HPFormField` | `.textFieldStyle(.roundedBorder)` |
| Money input | `HPMoneyField` (**integer cents**) | `TextField` + `Double` |
| ≤4 choices | `HPSegmentedControl` | stock `Picker(.segmented)` |
| >4 choices | HP-styled `Menu` | a squeezed segmented control |
| Search | `HPSearchBar` | ad-hoc `TextField` |
| Filters | `HPFilterBar` / `HPDataPill` | ad-hoc chips |
| Tabular data | `HPTable` (auto-stacks) | `Grid` that overflows |
| Chart | `HPChart` (+ a table equivalent) | chart-only answers |
| Progress | `HPProgressIndicator` | ad-hoc `Circle().trim` |
| Loading / empty / error | `HPLoadingState` / `HPEmptyState` / `HPErrorState` | bare `ProgressView`, silent empty |
| Toast | `HPToast` / `.hpToast($text)` | inline `.overlay` toast |
| Identity | `HPAvatar` | `DHDAvatarView` |
| Modal / confirm | `HPModalContainer` / `HPConfirmationDialog` | ad-hoc sheets |
| Sidebar / directory | `HPSidebar` / `HPWorkspaceDirectory` | ad-hoc nav lists |

**If an HP component cannot support the screen: STOP and report.** Do not modify `MultiOrg/DesignSystem/**` and do not fork a component locally.

### Tokens — never raw values

| Use | Never |
| --- | --- |
| `HP.Color.*` | `Color.blue`, `.red`, `Color(.systemBackground)`, hex literals |
| `HP.Font.*` | `.font(.headline)` (except inside an HP component) |
| `HP.Space.*` (8/12/16/24/32) | magic numbers |
| `HP.Radius.*` (8/12/16/18) | magic corner radii |
| `HP.Motion.*` | ad-hoc `.animation(.default)` |
| `HP.Shadow.*` via `.hpShadow()` | raw `.shadow()` |

---

## 8. How to replace presentation without changing behavior

The mechanical procedure, proven on both pilots:

1. **Copy every logic function verbatim.** Do not retype them. Do not "clean them up".
2. **Rewrite only view builders** — `body`'s layout and the `private var somethingCard: some View` computed properties.
3. **Preserve every binding exactly.** In `SDPlayerTodayView`, the four `StrengthExerciseLogger` bindings are what persist on submit. A "tidier" binding is a data-loss bug.
4. **Keep lifecycle modifiers attached to the same element.** `.onChange(of: date)` stays on the `DatePicker`.
5. **Swap containers, not conditionals.** `DHDCard { … }` → `HPCard { … }`; the `if`/`else` inside stays identical.
6. **Keep nested view types** (name + stored props); reskin their `body` only. You may relax `private` → internal so a render test can exercise them — that's visibility, not behavior.
7. **Re-run the manifest.** Identical or revert.

**Worked example (from the approved Stage 5B pilot):**

```swift
// BEFORE
private var headerCard: some View {
  DHDHeaderCard {
    Text(DateUtils.prettyDateTitle(date)).font(.title3.weight(.semibold))
    DHDStatusPill(text: isDaySaved ? "Saved" : "Not logged", color: isDaySaved ? .green : .orange)
    DatePicker("", selection: $date, displayedComponents: .date)
      .onChange(of: date) { _, _ in Task { await reloadDay() } }   // ← trigger
  }
}

// AFTER — same data, same binding, same trigger; only the shell changed
private var headerCard: some View {
  VStack(alignment: .leading, spacing: HP.Space.sm) {
    HPWorkspaceHeader("Today", context: DateUtils.prettyDateTitle(date)) {
      HPStatusBadge(text: isDaySaved ? "Saved" : "Not logged", kind: isDaySaved ? .success : .warning)
    }
    HPCard {
      DatePicker("", selection: $date, displayedComponents: .date)
        .datePickerStyle(.compact).labelsHidden().tint(HP.Color.accent)
        .onChange(of: date) { _, _ in Task { await reloadDay() } }  // ← unchanged
    }
  }
}
```

---

## 9. Responsive rules

Width buckets (see `HOME_PLATE_UI_CONTRACT.yaml`):

| Bucket | Width | Layout |
| --- | --- | --- |
| compact (iPhone) | < 700 | Single column, stacked cards, one pane at a time. |
| regular (iPad) | 700–1099 | 2-col metric grids; list+detail splits; month+timeline splits. |
| wide (macOS) | ≥ 1100 | 3-col grids, dense tables, sidebar + content. |

Rules:
- **No horizontal overflow, ever.** Wide content (tables, charts, code) scrolls inside its own container; the page never scrolls sideways.
- Use `ViewThatFits` for row→column fallbacks (button pairs, metric pairs) rather than guessing widths.
- Forms and settings are **single-column at every width** (cap width ~720pt and center on wide).
- `HPTable` auto-stacks; never hand-build a grid that squeezes.
- Splits collapse to a single pane on compact — never a 3-pane phone.

---

## 10. Dynamic Type & accessibility rules

**AX3 (`.accessibility3`) is the contract minimum.** Every screen must be usable at AX3.

- **Change layout, don't scale down.** `dynamicTypeSize.isAccessibilitySize` → stack rows, collapse grids to one column, replace a 7-column month grid with an **agenda list**.
- `.fixedSize(horizontal: false, vertical: true)` on any text that may wrap. Never `.minimumScaleFactor` as an AX strategy.
- Tap targets ≥ 44pt (`HPButtonSize.lg` is 44).
- Pin genuinely-fixed chrome (a progress ring's inner "%" label) with `.environment(\.dynamicTypeSize, .large)` — this is the **only** sanctioned type-size pin, and only for non-textual chrome.
- Every icon-only control needs `.accessibilityLabel`. Status must be readable as text.
- Combine decorative groups with `.accessibilityElement(children: .combine)`; hide pure decoration with `.accessibilityHidden(true)`.
- Respect `@Environment(\.accessibilityReduceMotion)` — HP components already do; don't re-add motion.

---

## 11. Build / test / screenshot requirements

Nothing is "done" without all of this:

```bash
# 1. Regenerate (only if you added/removed .swift files)
/tmp/hp-xcodegen-build/release/xcodegen generate --spec project.yml --project .

# 2. iOS build
xcodebuild build-for-testing -project MultiOrg.xcodeproj -scheme MultiOrg \
  -destination "platform=iOS Simulator,id=<UDID>" \
  -derivedDataPath /tmp/hp-dd-ios CODE_SIGNING_ALLOWED=NO

# 3. macOS build (unsigned)
xcodebuild build -project MultiOrg.xcodeproj -scheme MultiOrgMac -destination "platform=macOS" \
  -derivedDataPath /tmp/hp-dd-mac \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=""

# 4. Tests: 123 logic tests + your focused render tests
xcodebuild test-without-building -project MultiOrg.xcodeproj -scheme MultiOrg \
  -destination "platform=iOS Simulator,id=<UDID>" -derivedDataPath /tmp/hp-dd-ios \
  -skip-testing:MultiOrgTests/HPGalleryRenderTests \
  -skip-testing:MultiOrgTests/HPLiveControlsRenderTests \
  -skip-testing:MultiOrgTests/FinanceRenderTests

# 5. Hygiene
git diff --check
git status --porcelain
```

- **The 123 Swift Testing logic tests must stay green.** They are the behavior contract.
- **Render harnesses OOM if run together.** Skipping `HPGalleryRenderTests`/`HPLiveControlsRenderTests`/`FinanceRenderTests` is a **known tooling limit**, not a product failure — but you must **report exactly what you skipped**.
- **Screenshots are mandatory** at **iPhone (393)**, **iPhone AX3 (393 @ `.accessibility3`)**, and **iPad (834)** — plus macOS (1200) where applicable.
- Render harness rules: `format.scale = 1` for AX (tall), `2` otherwise; wrap each render in `autoreleasepool`; tear the window down (`window.isHidden = true; window.rootViewController = nil`).
- **Editable controls:** a headless `ImageRenderer` shows a yellow prohibited glyph for `TextField`/spinners. Use a real `UIWindow` + `layer.render` for full pages, and `drawHierarchy(afterScreenUpdates:)` for live editable controls.

---

## 12. Forbidden shortcuts & anti-patterns

Each of these has caused a real defect or a rejected review:

- ❌ Extracting a ViewModel "while we're in here".
- ❌ Adding autosave / per-item save because it "feels better".
- ❌ Reordering or coalescing Supabase calls.
- ❌ Hand-editing `project.pbxproj` instead of running XcodeGen.
- ❌ Raw colors (`.blue`, `.red`, `Color(.systemBackground)`) or hex literals.
- ❌ Stock `.borderedProminent` / `.roundedBorder` / segmented `Picker`.
- ❌ **Two gold primaries** on one screen (a nested section's CTA must be `.secondary`).
- ❌ `Double` for money. Cents are integers. Always.
- ❌ Solving AX3 with `.minimumScaleFactor` or a smaller font.
- ❌ A spinner with no copy; an empty view with no next step; a raw error string as the UI.
- ❌ Color-only status (a red dot with no word).
- ❌ Org brand color used as a semantic/action color.
- ❌ Touching `DHDTheme.swift` / `DHDUIComponents.swift` (Codex-owned) without explicit authorization.
- ❌ Working in `/Users/lb33/Documents/HomePlate` (the Codex checkout).
- ❌ Committing/pushing without being asked.
- ❌ Claiming success without the manifest diff, builds, tests, and screenshots.

---

## 13. Required final reporting format

Report exactly this. Absolute paths, always.

```markdown
## <Screen> — <stage> report

### Git state
Branch · HEAD · `git status --porcelain` · `git diff --check`

### Scope
Files edited (exact absolute paths). Confirm nothing else changed.

### BEFORE vs AFTER behavior manifest
- @State: <count> — names identical? yes/no
- async funcs: <names> — identical? yes/no
- Supabase calls: <inventory + counts> — identical order/params? yes/no
- Lifecycle: <.task/.onChange/.alert/.fileImporter> — identical? yes/no
**Verdict:** behavior unchanged / CHANGED (explain)

### Template used
<template_id> + any deviation (and why)

### Validation
- iOS build: SUCCEEDED/FAILED
- macOS build: SUCCEEDED/FAILED
- 123 logic tests: pass/fail
- Focused render tests: pass/fail
- Harnesses skipped: <list + reason>

### Screenshots
Absolute paths — iPhone / iPhone AX3 / iPad (/ macOS)

### Open questions / blockers
Anything you could not do, and why. Never paper over a gap.
```

---

## 14. Copy-paste implementation prompt (reuse for ANY screen)

> Copy the block below, fill the four `<…>` fields, and give it to any AI agent.

```text
Redesign a Home Plate screen. Presentation only.

SCREEN:        <e.g. MultiOrg/Features/Chat/ChatChannelListView.swift>
TEMPLATE:      <e.g. list_search_filter — from HOME_PLATE_SCREEN_MIGRATION_MAP.md>
WORKSPACE:     <e.g. Communication>
ROLE(S):       <e.g. all>

Work ONLY in /Users/lb33/Documents/HomePlate-design (branch design/home-plate-os).
Never access /Users/lb33/Documents/HomePlate.

READ FIRST, COMPLETELY:
- Docs/design/HOME_PLATE_AI_UI_IMPLEMENTATION_GUIDE.md  (this is binding)
- Docs/design/HOME_PLATE_SCREEN_TEMPLATES.md            (your template's anatomy)
- Docs/design/HOME_PLATE_VISUAL_REFERENCE.md            (what it must look like)
- Docs/design/HOME_PLATE_UI_CONTRACT.yaml               (machine-checkable rules)
- The target screen file, in full.

PREFLIGHT (do not write code until these pass):
1. pwd / git branch --show-current / git status --porcelain / git log -3 --oneline
   (If git status hangs: git update-index -q --refresh. If another agent is active: STOP and report.)
2. Record the BEFORE manifest using the command in §4 of the guide.
3. State the scope, the protected behavior, and the exact files you will edit.

IMPLEMENT:
- Restyle ONLY view builders onto the assigned template using approved HP components.
- Preserve EXACTLY: every @State/@Binding/@Environment/stored prop, every async func and its
  body, every SupabaseService call + order + params, hydration, save/resume/submit, validation,
  completion calcs, offline behavior, and .task/.onChange/.onAppear/.refreshable/.fileImporter/.alert.
- Do NOT: extract a ViewModel, add autosave/per-item saving, add next/prev nav, change persistence
  timing, reorder network calls, or alter models/services/DB/auth/StoreKit/notifications.
- Do NOT modify MultiOrg/DesignSystem/** . If an HP component can't support the screen, STOP and report.
- Use HP tokens only — no raw colors, no stock controls, exactly ONE HPButton(.primary).
- Handle loading / empty / error / offline / stale as designed states.
- AX3 must change layout (stack/single-column), not scale text.

VALIDATE (all of it):
- XcodeGen regenerate if you added/removed files (never hand-edit project.pbxproj).
- iOS Simulator build; macOS unsigned build.
- 123 Swift logic tests green; focused render tests green (report any skipped harness).
- Screenshots: iPhone, iPhone AX3, iPad (+ macOS if applicable).
- Re-run the AFTER manifest and confirm it matches BEFORE exactly.
- git diff --check; git status --porcelain.

REPORT using the format in §13. Do not commit, push, or merge. Stop for visual review.
```

---

## 15. Quick validation checklist (paste into your PR/report)

- [ ] Preflight clean; single agent on the worktree
- [ ] BEFORE manifest recorded
- [ ] Template selected from the migration map
- [ ] Only view builders changed
- [ ] Only HP components; only HP tokens
- [ ] Exactly one `.primary`
- [ ] Money = integer cents
- [ ] Loading/empty/error/offline/stale handled
- [ ] AX3 relayouts (no shrink); ≥44pt targets; labels present
- [ ] No horizontal overflow at 393 / 834 / 1200
- [ ] XcodeGen regenerated (if files added)
- [ ] iOS + macOS builds SUCCEEDED
- [ ] 123 logic tests green; render tests green; skips reported
- [ ] Screenshots at iPhone / AX3 / iPad (+ macOS)
- [ ] AFTER manifest == BEFORE manifest
- [ ] `git diff --check` clean; scope confirmed
- [ ] Reported in the §13 format; not committed
