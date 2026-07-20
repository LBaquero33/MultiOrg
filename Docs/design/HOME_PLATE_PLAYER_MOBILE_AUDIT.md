# HOME PLATE — PLAYER MOBILE AUDIT (Stage 5A)

**Status:** Read‑only audit. No production code was modified. Player‑facing iPhone experience, focus on **Programs / daily program execution**.
**Author:** Claude (design initiative) · **Date:** 2026‑07‑15
**Absolute path:** `/Users/lb33/Documents/HomePlate-design/Docs/design/HOME_PLATE_PLAYER_MOBILE_AUDIT.md`
**Companions:** `HOME_PLATE_DESIGN_SYSTEM.md`, `HOME_PLATE_COMPONENT_LIBRARY.md`, `HOME_PLATE_WORKSPACES.md`, `HOME_PLATE_DESIGN_QA.md`.

---

## 0. Method & scope

Static read of every player‑facing SwiftUI file under `HomePlate/Features/Player/`, `HomePlate/Features/Home/` (player branch), and shared program pieces under `HomePlate/Features/Shared/`, plus the program models (`SDModels`) and schedule logic (`SDProgramSchedule`). macOS excludes `Features/Player/**` (per `project.yml`), so this is an **iPhone/iPad** concern. No builds were run; nothing was changed.

---

## 1. Player‑facing production files & purpose

| File | Lines | Purpose |
| --- | --: | --- |
| `Features/Home/PlayerHomeView.swift` | 83 | Player root — the tab bar (Today, Calendar, Chat, Facilities, Trends, Testing, Analysis, Account). macOS = "coming soon" placeholder. |
| `Features/Player/SDPlayerTodayView.swift` | 686 | **Daily program execution** — today's scheduled strength work, strength logging, BP (hitting) section, self‑assessment, and Submit Day. **The pilot target.** |
| `Features/Player/SDPlayerProgramView.swift` | 150 | Assigned programs + program overview / browse (strength / hitting / pitching), week/day picker, exercise/drill list. |
| `Features/Player/SDPlayerBPDaySection.swift` | 276 | Reusable "Hitting (BP) for a day" section (embedded in Today) — CSV import (Rapsodo/HitTrax/etc.), events summary. |
| `Features/Player/SDPlayerBPView.swift` | 253 | BP/hitting analysis surface. |
| `Features/Player/SDPlayerCalendarView.swift` | 154 | Player calendar (month grid → day). |
| `Features/Player/SDPlayerTrendsView.swift` | 170 | Development trends (charts). |
| `Features/Player/SDPlayerTestingView.swift` | 215 | Testing entries (exit velo, strength, etc.). |
| `Features/Player/SDPlayerAnalysisView.swift` | 35 | Analysis entry (thin wrapper over BP analysis). |
| `Features/Player/SDPlayerFacilitiesView.swift` | 361 | Facility booking (player view). |
| `Features/Shared/SDProgramSchedule.swift` | 63 | **Schedule logic** — maps a date + assignment + template → `DayContext` (isScheduled/week/dayIndex/next lift). |
| `Features/Shared/BPAnalysisComponents.swift` | 349 | Swift Charts + Canvas visualizations (histograms, strike zone). |
| `Features/Shared/CalendarComponents.swift`, `DHDMonthGridView.swift` | 72 / 163 | Calendar grid building blocks. |
| `Features/Shared/TwoAxisScrollView.swift` | 71 | Two‑axis scroll (tables/heatmaps). |
| `Features/Home/PlayerSubscriptionPaywall.swift` | — | StoreKit paywall (player access subscription). |
| `Features/Home/AccessRequiredView.swift` | — | "Access required" gate when `needsAccess`. |
| `Features/Home/HomeView.swift` | 46 | Role router → `PlayerHomeView` when player (else Coach/Parent). |
| `Features/Account/AccountView.swift` | — | Account/settings (shared). |
| `Features/Chat/*`, `Features/Notifications/*` | — | Chat + Notification Center (shared, role‑agnostic). |

Also relevant to the player: `PlayerDetailView.swift` (coach‑side view of a player, not player‑facing).

---

## 2. Current player navigation & tab structure

`RootView` → `HomeView` → (player) `PlayerHomeView`. iOS forces `.preferredColorScheme(.dark)`.

**iPhone tab bar (`PlayerHomeView`, up to 8 tabs, feature‑gated):**
`Today` (`sun.max`) · `Calendar` · `Chat`* · `Facilities`* · `Trends` · `Testing`* · `Analysis`* · `Account`. (`*` = `activeOrgSettings.feature()` gated; terminology via `term()`.)

Problems: **8 tabs overflow into the unbranded system "More"** (iOS shows only 5). No workspace grouping; each screen wraps itself in its own `NavigationStack`. There is **no "Programs" tab** — assigned‑program browsing lives in `SDPlayerProgramView` but is **not wired into `PlayerHomeView`** (it's reachable only where linked, if at all); daily program work is folded into **Today**. macOS player = placeholder.

Per `HOME_PLATE_OS.md`, the approved iPhone player tabs are **Today · Calendar · Trends · Chat · More** (≤5), with a branded `HPWorkspaceDirectory` replacing "More".

---

## 3. Full Programs data & presentation flow

### Models (`SDModels.swift`) — read‑only
`SDProgramTemplate` (name, `kind`, `weeks`, `lift_weekdays`), `SDProgramAssignment` (template_id, start_date), `SDProgramDay` (week, day_index, `exercises: [SDExercise]`), `SDExercise` (name, sets, reps, unit, notes), `SDStrengthLog` (per‑exercise: set_weights_json, sets_completed, no_weight, notes), `SDDailyLog` (self‑assessment: feel, got_video, ate_breakfast, hit_daily_goals, stuck_to_process, fell_short, excelled, comments), `SDTestingEntry`, `SDBPSession` / `SDBPEvent`. `ProgramKind` = **strength / hitting / pitching** (`title`, `systemImage`).

### Schedule (`SDProgramSchedule.context(...)`) — read‑only
Pure function: given today + assignment + template, returns `DayContext { isScheduled, week, dayIndex, nextLiftDateISO, isInProgramWindow }` (counts lifts on `lift_weekdays` within the program window). Drives whether Today shows scheduled work.

### Presentation flow
1. **Today (`SDPlayerTodayView`)** — on `.task`: `reloadAssignment()` → `fetchActiveAssignment` + `fetchTemplate`; `reloadDay()` → `fetchDailyLog` + `fetchStrengthLogs` + (if scheduled) `fetchProgramDays` → filters to today's week/day exercises; `reloadTesting()`. Renders: gradient header (date picker + Scheduled/Off‑day + Saved/Not‑logged pills), Improvement tiles, Strength program card (`ProgressRing`), **Strength logger** (`DisclosureGroup` → `StrengthExerciseLogger` per exercise: per‑set weight `TextField`s, "No weight" toggle + `Stepper`, add/remove set, notes), **`SDPlayerBPDaySection`** (hitting), **Self‑assessment** (`DisclosureGroup`: toggles, `TextField`s, feel `Slider`), **Submit Day** (`.borderedProminent`).
2. **Programs (`SDPlayerProgramView`)** — `List`/`Section`; `fetchActiveAssignments` → per‑assignment `fetchTemplate`; program `Picker` (menu, by kind), week/day `Picker`s, exercise/drill list. Empty via `ContentUnavailableView`, errors via `.alert`.
3. **Save/submit** — `submitDay()` upserts each scheduled exercise's `SDStrengthLog` (`upsertStrengthLog`) then the daily log (`upsertDailyLog`), then `reloadDay()`; a brief inline success toast. **All‑or‑nothing at the bottom of the screen; no autosave or per‑exercise save.**

---

## 4. Read‑only (must NOT change)

- **Models:** all of `SDModels.swift` (templates, assignments, days, exercises, strength/daily logs, testing, BP).
- **Schedule logic:** `SDProgramSchedule.swift` (`DayContext` computation).
- **Services / networking:** `SupabaseService` methods — `fetchActiveAssignment(s)`, `fetchTemplate`, `fetchProgramDays`, `fetchDailyLog`, `fetchStrengthLogs`, `upsertStrengthLog`, `upsertDailyLog`, `listTestingEntries`, `listBPSessions`, `upsertBPSession`, `fetchBPEvents`, `replaceBPEvents`.
- **Program completion / save / resume logic:** the in‑view async funcs (`reloadAll/reloadAssignment/reloadDay/reloadTesting`, `submitDay`, `upsertDailyLogOnly`, `hydrateFromExistingLogs`, `isExerciseLogged`, `progressFraction`) and the CSV import/mapping in `SDPlayerBPDaySection` (`importCSV`, `mapRapsodo`, `loadSession`, `inferExisting`).
- **Auth / access / entitlements / StoreKit:** `AppState` auth, `needsAccess`, `refreshEntitlement`, `PlayerSubscriptionPaywall`, `AccessRequiredView`, `ApplePlayerPurchaseContext`.
- **Notifications:** producers/APNs/`NotificationCenter*`.

**Critical structural note:** `SDPlayerTodayView` has **no ViewModel** — the data‑loading, hydration, save/resume, and submit logic all live inside the View via `@State` + direct `SupabaseService` calls, deeply interleaved with layout. This is unlike the Finance pilot (which had a clean `FinanceDashboardViewModel`). The redesign must preserve that exact `@State` model and every async func, restyling **only** the view builders around them.

---

## 5. Inline / duplicated UI that should migrate to Home Plate OS

| Current | → HP component |
| --- | --- |
| `DHDHeaderCard` gradient header (Today) | `HPWorkspaceHeader` |
| `DHDCard` everywhere | `HPCard` |
| `ImprovementTile` (inline, Today) | `HPMetricCard` (value + delta + context) |
| `ProgressRing` (inline, Today) | `HPProgressIndicator` (ring) |
| `StrengthExerciseLogger` (inline card + `.roundedBorder` set fields) | `HPCard` + `HPFormField` / `HPStepper` / `HPToggle` |
| `DHDStatusPill` (Scheduled/Off/Saved) | `HPStatusBadge` |
| **Three separate toast implementations** — inline `.thinMaterial` in Today, inline `.thinMaterial` in `SDPlayerBPDaySection`, and `DHDToast` | **one `HPToast`** |
| Native `Picker(.menu)` / `List`/`Section` (Programs) | `HPCard` + HP menu/`HPSegmentedControl` (kind), HP rows |
| `ContentUnavailableView` / ad‑hoc `ProgressView`+Text / `.alert` errors | `HPEmptyState` / `HPLoadingState` / `HPErrorState` |
| `.borderedProminent` "Submit day" / "Import CSV" | `HPButton(.primary/.secondary)` |
| Hardcoded `Color(.systemBackground)` tiles inside dark cards | `HP.Color.surface/surfaceRaised` |
| BP charts (`BPAnalysisComponents`, Swift Charts) | `HPChart` wrapper |

---

## 6. Mobile usability problems (ranked by severity)

1. **Heavy typing during training (critical).** Strength logging is per‑set weight entry via keyboard `TextField`s; self‑assessment uses free‑text fields. On the gym floor (one hand, sweaty, mid‑set) this is slow and error‑prone. → needs large steppers/quick‑pick weights, big tap targets, minimal typing.
2. **All‑or‑nothing save at the bottom (critical — data‑loss risk).** Everything is held in `@State` and only persisted by **Submit Day** at the end of a long scroll. If the app is backgrounded/killed mid‑workout, unsaved sets are lost; there is **no autosave and no per‑exercise save**. Resume only rehydrates what was already submitted.
3. **Long single scroll + nested disclosure groups.** Today stacks header → improvement → program → strength logger → BP → self‑assessment → submit. High cognitive load; the primary action (Submit) is far from the work; easy to lose place between exercises.
4. **No next/previous exercise navigation.** Exercises are a flat stack inside one disclosure group — no focused "current exercise" mode, no step-through.
5. **Small / stock tap targets.** `.roundedBorder` fields, native steppers, toggles — not tuned for gloved/one‑handed use.
6. **Duplicated, inconsistent toasts** (three implementations) and inconsistent surfaces (`Color(.systemBackground)` tiles on dark cards).
7. **No offline/stale handling.** All screens are live‑fetch; failure → `.alert` or red text; a dropped connection mid‑workout has no graceful degradation or local queue.
8. **Incomplete state coverage.** Loading is ad‑hoc `ProgressView`+Text; some empties exist (`ContentUnavailableView`), errors are `.alert`s; no permission/locked/stale states in the program flow.
9. **Navigation overload.** 8 player tabs overflow into the unbranded system "More"; no "Programs" home; Programs browse is under‑surfaced.
10. **Accessibility unverified.** No confirmed Dynamic Type / VoiceOver support in the logger; risk of horizontal overflow in per‑set weight rows and BP event rows at large text.
11. **Pitching daily execution is thin.** `ProgramKind.pitching` exists and is browsable in Programs, but daily *logging* in Today centers on strength + BP hitting; pitching execution has no dedicated logging path.

---

## 7. Risks of redesigning the Programs workflow

1. **Logic lives in the View (highest risk).** With no ViewModel, presentation and save/resume/submit logic are intertwined in `SDPlayerTodayView`. Restyling risks accidentally altering hydration, `isExerciseLogged`, `progressFraction`, or `submitDay`. Mitigation: keep every `@State` var and every async func byte‑for‑byte; change only the view builders they feed.
2. **Save semantics are subtle.** `submitDay` conditionally writes strength logs only when scheduled and only for non‑empty sets, plus the daily log; `hydrateFromExistingLogs` maps server rows back into `@State`. Any layout change that alters bindings could change what gets saved. Mitigation: reuse the exact bindings.
3. **Data‑loss sensitivity.** Users care most here. A redesign that *improves* save UX (autosave/per‑exercise save) would be a **behavior change** → out of scope; must be proposed separately. The pilot must preserve current save/submit behavior exactly.
4. **BP CSV import is real device I/O** (`fileImporter`, mapping). Reskin the surrounding UI only; do not touch import/mapping.
5. **Schedule‑driven conditional UI** (`DayContext`): scheduled vs off‑day changes which cards render. Preserve the conditionals.
6. **Dynamic Type / overflow** in per‑set weight rows is a real correctness risk (the AX3 lessons from Finance apply).

---

## 8. Screens that can be reskinned safely (low behavior risk)

- **`SDPlayerProgramView`** (browse) — mostly read‑only display; swap `List`/`Picker`/`ContentUnavailableView` for HP equivalents. Low risk.
- **`SDPlayerTrendsView` / `SDPlayerAnalysisView`** — read‑only charts → `HPChart`. Low risk.
- **`SDPlayerTestingView`** — read + simple entry; medium‑low.
- **Today's read‑only cards** (header, improvement, program summary, status pills) — reskin without touching the logger bindings. Low risk.
- Higher risk (defer or handle carefully): the **strength logger inputs**, **BP section**, **Submit** — these carry the save logic.

---

## 9. Recommended phased redesign order (player mobile)

1. **Program Day Execution pilot** (Today's execution) — the daily core; highest player value. *(first pilot, below)*
2. **Player navigation shell** — ≤5 tabs + `HPWorkspaceDirectory`; surface a real **Programs** home.
3. **Programs browse** (`SDPlayerProgramView`) — reskin to HP.
4. **Calendar** (`SDPlayerCalendarView` + grid) — reskin.
5. **Trends / Analysis** (charts → `HPChart`).
6. **Testing** entry.
7. **Facilities** (player).
8. **Account / paywall / access states** (reskin presentation; StoreKit untouched).
9. **BP/hitting analysis** deep surfaces.
10. Later: pitching daily execution, offline/queue, AI summaries.

---

## 10. Recommended first production pilot — **Player Program Day Execution**

**Scope:** the screen where a player views today's assigned work, reads instructions, logs exercises, records results, and submits/completes the day — i.e. **`SDPlayerTodayView`** and its embedded **`SDPlayerBPDaySection`**.

**Why these two together:** the "day" is one experience — strength logging and BP hitting are both part of completing the day and are rendered in the same scroll. Reskinning Today without the BP section would leave a visual seam mid‑screen (the Finance/Expenses seam lesson).

**Prerequisite check:** none blocking. The HP component library (Stage 3A/3B, committed) already provides everything needed (`HPCard`, `HPMetricCard`, `HPProgressIndicator`, `HPFormField`, `HPButton`, `HPStatusBadge`, `HPToast`, `HPWorkspaceHeader`, states). The pilot is a single screen and does **not** require the player nav shell to be redesigned first. **However**, because the save/resume/submit logic is embedded in the View (no ViewModel), the pilot is presentation‑only by strict discipline: preserve all `@State` and async funcs; restyle the builders. (A future, separately‑approved step could extract a ViewModel and improve save UX — explicitly out of this pilot.)

**Guardrails honored:** no changes to Supabase, models, ViewModels (none exist here), completion/save/resume logic, authorization, entitlements, StoreKit, networking, notifications, or business rules.

---

## Proposed files for the first player pilot

- **`HomePlate/Features/Player/SDPlayerTodayView.swift`** — reskin the view builders (header, improvement, program, strength logger, self‑assessment, submit) to HP components; preserve every `@State` and async func.
- **`HomePlate/Features/Player/SDPlayerBPDaySection.swift`** — reskin the card/inputs/toast to HP; preserve CSV import + session logic.
- Test‑only evidence harness (new): `HomePlateTests/PlayerTodayRenderTests.swift` — mock‑data renders (no network/AppState), like the Finance harness.

**Read‑only (unchanged):** `SDModels.swift`, `SDProgramSchedule.swift`, `SupabaseService.swift`, `AppState.swift`, `PlayerHomeView.swift`, `SDPlayerProgramView.swift`, all other player screens, and `HomePlate/DesignSystem/**` (used, not modified).

**Stop point:** awaiting approval of this pilot scope before any implementation.
