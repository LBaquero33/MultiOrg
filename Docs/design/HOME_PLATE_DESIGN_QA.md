# HOME PLATE — DESIGN QA

**Status:** Layer F acceptance record complete for Layer E `a588cb7` on 2026-07-17. The reusable per-destination checklist remains available for future changes.
**Worktree:** `/Users/lb33/Documents/HomePlate-ui-integration`
**Branch:** `integration/universal-ui`
**Companions:** `HOME_PLATE_SCREEN_MIGRATION_MAP.md` · `HOME_PLATE_DESIGN_SYSTEM.md` · `HOME_PLATE_COMPONENT_LIBRARY.md` · `HOME_PLATE_MOTION_SYSTEM.md`

A production destination is complete only when every applicable item passes. “N/A” requires a one-line reason. Visual consistency never overrides existing authorization, service, lifecycle, persistence, accessibility, or platform behavior.

## A. Identity and tokens

- [ ] Colors come from `HP.Color` semantic tokens; no new literal RGB colors, generic accent colors, or hard-coded system backgrounds in migrated presentation.
- [ ] Green/gold/danger/success/focus are HP-controlled system semantics; organization branding is limited to identity context.
- [ ] Typography uses the HP scale and platform-safe fallback; money and dense metrics use tabular figures where appropriate.
- [ ] Spacing, radius, border, and elevation use HP tokens or an existing documented layout constant.
- [ ] User-facing product identity reads “Home Plate”; no “MultiOrg” leakage.

## B. Layout and composition

- [ ] The destination uses the applicable HP workspace, list, detail, editor, analytics, calendar, communication, finance, admin, state, paywall, or program composition.
- [ ] Primary actions have clear hierarchy; normally one action is visually primary in a region, with exceptions documented for native or safety-critical flows.
- [ ] Shared components (`HPCard`, `HPWorkspaceHeader`, `HPFormField`, `HPButton`, `HPTable`, state views, and related types) replace local look-alikes where semantics match.
- [ ] Scroll containers remain scrollable, pinned controls do not cover content, and decorative overlays use `.allowsHitTesting(false)`.
- [ ] Metrics include available context, units, trend/comparison, and verification status without inventing data.

## C. States

- [ ] Loading uses the applicable HP loading/progress treatment and does not unnecessarily hide already valid content.
- [ ] Empty state has specific copy and, when useful, one clear recovery action.
- [ ] Error state exposes safe user-facing copy and an authorized retry/recovery action; raw backend errors and secrets are never displayed.
- [ ] Permission, locked, or upgrade states describe the current role/entitlement without duplicating authorization logic in the view.
- [ ] Offline and stale states appear where the existing feature can detect them; network mutations are disabled or explained consistently.
- [ ] Success feedback is accessible and non-blocking; toast overlays do not intercept input.
- [ ] State transitions preserve the existing task, appearance, refresh, change, importer, alert, dismissal, and persistence lifecycle.

## D. Accessibility

- [ ] Text and essential symbols meet applicable contrast targets; verify text-on-gold and gold-on-dark independently.
- [ ] Status uses text and/or icon in addition to color.
- [ ] Dynamic Type through Accessibility 3 does not clip, overlap, hide actions, or force destructive horizontal scrolling.
- [ ] VoiceOver labels, values, hints, traits, and heading structure describe interactive and metric content without duplicate announcements.
- [ ] Focus is visible and ordered on keyboard-capable platforms; modal Escape handling follows existing project conventions.
- [ ] Reduce Motion and Reduce Transparency are honored.
- [ ] Icon-only controls have accessible labels; iOS/iPadOS interactive targets are at least 44 points where platform controls do not already guarantee it.

## E. Interaction and destructive semantics

- [ ] Motion is calm, purposeful, and token-driven; routine transitions do not bounce.
- [ ] Destructive actions require deliberate confirmation using native SwiftUI `.confirmationDialog` or `.alert` when those provide the correct semantics and platform adaptation. `HPConfirmationDialog` is permitted but is **not** mandatory.
- [ ] Buttons retain their label during loading and do not shift layout.
- [ ] Navigation selection, push/pop, sheet dismissal, full-screen dismissal, deep links, unread/read state, and restoration work at compact and regular widths.
- [ ] No invisible overlay, disabled container, or gesture steals interaction from scrolling, coach review, forms, chat, or other controls.

## F. Platform behavior

- [ ] **iPhone:** no unbranded system “More” overflow; branded workspace directory and drill-in destinations work.
- [ ] **iPadOS:** regular width uses the adaptive sidebar/detail shell and appropriate columns/splits rather than a stretched compact layout.
- [ ] **macOS:** supported target surfaces use sidebar/detail, keyboard focus, hover/toolbar behavior where applicable, and Escape dismissal for modals.
- [ ] The macOS claim matches the actual `MultiOrgMac` source set. Feature files excluded by `project.yml` are not reported as native macOS coverage merely because a test harness renders a macOS-width frame.
- [ ] Platform-native controls are retained where Apple semantics, HIG, accessibility, StoreKit, authentication, alerts, or confirmation behavior require them.

## G. Data and correctness guardrails

- [ ] ViewModels, models, services, authorization, feature/terminology gates, task IDs, call ordering, data flow, and returned contracts behave identically unless a separately authorized product change says otherwise.
- [ ] No Supabase/RLS/Edge Function, Stripe/reconciliation, StoreKit/verification, auth/authorization, APNs/notification-producer, or external-AI behavior is changed by a UI migration.
- [ ] Money remains integer-cent, currency-aware, and locale-aware; existing validation remains intact.
- [ ] Platform-support mode remains explicit: support access is not ownership or organization membership.
- [ ] Phase 11 evidence, import provenance, player visibility, coach-review lifecycle, Copilot citations, pending questions, and parent-draft authorization remain intact.

## H. Required build and test evidence

- [x] Fresh iOS `build-for-testing` succeeds against the project’s controlled iPhone simulator runtime.
- [x] Fresh native arm64 `MultiOrgMac` build succeeds.
- [x] Focused tests for every touched feature pass before its layer commit.
- [x] The complete non-render Swift test suite passes at the Layer E/F exit gate.
- [x] Render-producing tests are run separately from the non-render suite so evidence-only work is visible and failures are attributable.
- [x] `git diff --check` passes, no file is staged unexpectedly, no ignored build secret/configuration remains, and the final worktree status is classified exactly.

### Automated render matrix

| Suite | Required viewport/state evidence |
| --- | --- |
| `UniversalUIFoundationTests` | iPhone light, iPhone dark, iPhone Accessibility 3 dark, iPad dark, macOS-width light |
| `UniversalNavigationShellTests` | Compact player light; compact directory dark at Accessibility 3; regular parent iPad; regular coach macOS-width; regular platform administration |
| `HPTemplateRenderTests` | Every template at iPhone light/dark/Accessibility 3, iPad light/dark, and macOS-width light/dark |
| `HPGalleryRenderTests` | Component-gallery viewports at iPhone normal, iPhone Accessibility 3, iPad, and macOS width |
| `HPLiveControlsRenderTests` | Live native controls/focus plus Accessibility 3 navigation/modal evidence |
| `PlayerTodayRenderTests` | Programs, completion, applicable state set, accessibility, and live editable controls |
| `FinanceRenderTests` | Loaded content, loading/empty/error states, and controls |

Render harnesses establish deterministic visual evidence; they do not prove native target inclusion, routing, authorization, or interaction by themselves. Generated images must be inspected for clipping, overlap, hierarchy, contrast, blank captures, stale legacy styling, and input-blocking overlays.

### Role and state smoke matrix

- [x] Auth/config/access/paywall: sign-in, sign-up, recovery, safe error mapping, purchase context, dismiss/sign-out recovery.
- [x] Player: navigation, Today/logging, calendar, testing, trends/analysis/facilities, Phase 11 workspace/report/alert visibility.
- [x] Parent: children/profile/program/calendar/facilities/billing, request sheets, payment confirmation, chat/account.
- [x] Coach: roster/profile/program/testing/calendar/facilities, report review, imports, Copilot conversation/citations/drafts, chat/account.
- [x] Owner/admin/platform: organization console editors, finance/expenses, platform support/admin separation, account.
- [x] Notifications/chat: pagination, unread/read, announcements, deep-link routing, channel selection, send/create, compact push, regular split, modal dismissal.
- [x] Loading, empty, error, permission, locked, stale/offline where supported, success, destructive confirmation, and Accessibility 3 are represented across the matrix.

This smoke matrix was accepted from the combined route/static contracts, focused feature tests, complete Swift suites, native builds, and inspected render evidence. Safety boundaries deliberately excluded live StoreKit purchases, payment mutations, file uploads/import commits, external-AI calls, APNs delivery, and deployment operations; those exclusions do not weaken the presentation and navigation acceptance claim.

## I. Coverage and completion reporting

- [x] Report all three denominators without conflation: historical contract **51**, strict live current **79**, and map-compatible current **82**.
- [x] Keep the three embedded panes separate from the strict screen count.
- [x] Keep components, shells/routers, and six preserved dead-source types explicitly classified.
- [x] List every changed file and exact test/build/render result; classify warnings and remaining findings by severity.
- [x] Do not claim deployment, migration application, push, notification delivery, external-AI invocation, or secret change unless it actually occurred and was authorized.

## Per-destination sign-off

```text
Destination: ____________________   Type: root [ ] screen [ ] sheet [ ] embedded [ ]
Platforms: iPhone [ ] iPadOS [ ] macOS target [ ] macOS-width render only [ ]
A Tokens [ ]  B Layout [ ]  C States [ ]  D A11y [ ]  E Interaction [ ]
F Platform [ ]  G Correctness [ ]  H Build/test/render [ ]
N/A reasons and evidence paths: __________________________________________
```

## Layer F acceptance record

Layer F validated the exact Layer E production/test tree at `a588cb77ddda2c884891d390dea5bcfdd7ce0918`. The subsequent Layer F commit changes these three design records only, so another product build after that documentation-only commit is unnecessary.

| Gate | Exact result |
| --- | --- |
| Coverage | **51/51** historical original-map contract; **79/79** strict live current roots/screens/sheets; **82/82** map-compatible current surfaces. Current application source inventory: **67** Swift files under `MultiOrg/App/**` and `MultiOrg/Features/**`. |
| Clean iOS build-for-testing | Passed on `HP-iPhone17Pro`, iOS 26.5, with derived data at `/Volumes/HomePlateBuilds/DerivedData/LayerF-final-iOS`; log: `/Volumes/HomePlateBuilds/LayerF-final-iOS-build.log`. |
| Clean native macOS build | `MultiOrgMac`, Debug, arm64 passed with derived data at `/Volumes/HomePlateBuilds/DerivedData/LayerF-final-macOS`; log: `/Volumes/HomePlateBuilds/LayerF-final-macOS-build.log`. |
| Swift non-render suite | **237/237** logical tests and **251/251** invocations passed; 0 failures, skips, or expected failures. Result: `/Volumes/HomePlateBuilds/Results/LayerF-final-nonrender.xcresult`. |
| Swift render suite | **59/59** tests passed; 0 failures, skips, or expected failures. The suite includes 28 render-producing methods plus 31 foundation/navigation assertions. Result: `/Volumes/HomePlateBuilds/Results/LayerF-final-render.xcresult`. |
| Aggregate Swift evidence | **296/296** logical tests and **310/310** invocations passed. |
| Render artifacts | 164 PNGs were emitted and source-verified in `/Volumes/HomePlateBuilds/Evidence/LayerF-final-exact`; file list and SHA-256 manifest: `LayerF-final-exact-files.txt` and `LayerF-final-exact-sha256.txt`. 162 are content-bearing evidence. The final two Accessibility 3 component-gallery windows (`hp-vp-iphone-xl-19.png` and `hp-vp-iphone-xl-20.png`) are identical background-only trailing slices caused by `sizeThatFits` height overestimation; slice 18 visibly completes the gallery at Settings. They are retained in the exact manifest but excluded from visual-evidence conclusions. |
| Focused backend guardrail | Player Development reports/imports/Copilot shared tests: **148/148** passed. |
| Complete shared backend guardrail | **373/373** tests passed. Relevant 11-file Deno format and type checks passed. Logs: `/Volumes/HomePlateBuilds/universal-ui-layer-f-backend-20260717/`. No backend file changed. |
| Static and repository integrity | `git diff --check` passed; no staged/untracked file, ignored build-secret configuration, secret path/symlink, migration/backend change, or project-definition change remained at the Layer E commit boundary. |

The exact build commands were:

```text
xcodebuild -project MultiOrg.xcodeproj -scheme MultiOrg -configuration Debug -destination 'platform=iOS Simulator,id=B7059BC9-F55C-4B72-A52A-CEF6B4BF267F' -derivedDataPath /Volumes/HomePlateBuilds/DerivedData/LayerF-final-iOS CODE_SIGNING_ALLOWED=NO clean build-for-testing
xcodebuild -project MultiOrg.xcodeproj -scheme MultiOrgMac -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath /Volumes/HomePlateBuilds/DerivedData/LayerF-final-macOS ONLY_ACTIVE_ARCH=YES CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= clean build
```

### Warning and exclusion classification

- **No blocker/high UI finding:** all build/test gates pass; inspected light/dark, compact/regular, iPhone/iPad/macOS-width, state, live-control, and Accessibility 3 evidence shows no unresolved clipping, overlap, trapped modal, or input-blocking overlay.
- **Informational build diagnostics:** the unsigned iOS build emitted two AppIntents metadata-skip warnings and four duplicate emissions of two pre-existing unused `beginContext(...)` results in `PlayerDevelopmentImportTests`; the unsigned macOS build emitted one AppIntents metadata-skip warning. Unsigned strip/bitcode notices are expected for these local validation commands.
- **Informational render-harness diagnostics:** 376 FocusState-outside-body, 564 flattened `PlatformViewRepresentableAdaptor`, 85 appearance-transition imbalance, one IOSurface, and one first-responder/window diagnostic were confined to deterministic off-window UIKit rendering. Duplicate LazyVGrid identifier diagnostics are zero. Native target builds and all render assertions pass.
- **Pre-existing backend baseline, not a Universal UI regression:** broad format check reports 17 of 66 committed function files unformatted; broad cached type check reports eight committed Stripe webhook type errors. Relevant 11-file checks and all shared tests pass, and the UI branch has no backend diff.
- **Not exercised by design:** deployment, migration application, push/PR, live purchase/payment mutation, external AI, notification/APNs delivery, import upload/commit, and secrets changes.

The migration is ready for release preparation and product-owner acceptance. This record is not deployment authorization.
