# HOME PLATE — UI AUDIT (HISTORICAL BASELINE AND IMPLEMENTATION RECORD)

**Status:** The Phase 10 Stage 1 audit is retained as historical evidence and is **superseded by the completed Universal UI migration through Layer E (`a588cb7`) and Layer F acceptance on 2026-07-17**.
**Historical snapshot:** `b97c1b4` on 2026-07-15
**Implementation worktree:** `/Users/lb33/Documents/HomePlate-ui-integration`
**Implementation branch:** `integration/universal-ui`
**Scope:** Native iOS/iPadOS/macOS presentation. Backend, payments, StoreKit verification, auth/authorization, notification producers, and data contracts are behavior-preservation boundaries.

This document preserves what the original audit observed and records how the dedicated integration resolved it. Current inventory and coverage are authoritative in `HOME_PLATE_SCREEN_MIGRATION_MAP.md`; current acceptance criteria are authoritative in `HOME_PLATE_DESIGN_QA.md`.

## 1. Audit method and corrected baseline

| Surface | Historical method/evidence |
| --- | --- |
| Website | Live inspection of `homeplateapps.com`; computed CSS tokens, typography, cards, controls, and hero treatment were recorded. |
| iOS | Static SwiftUI review, simulator build, and launched login-screen inspection. |
| iPadOS | Source/target review of the shared iOS paths and size-class behavior. |
| macOS | Native `MultiOrgMac` build and review of macOS-specific branches. |

The source-of-truth project structure remains `project.yml`. The corrected `b97c1b4` baseline is **62**, not 64, Swift files under `MultiOrg/App/**` and `MultiOrg/Features/**`. The Layer E tree at `a588cb7` contains **67** such files.

The initial audit itself was read-only: it created design documentation and did not modify production source, backend files, secrets, or project configuration. That statement applies only to the historical audit session; subsequent commits intentionally implemented the migration.

## 2. Historical brand evidence

The audit found a website identity best summarized as **leather + grass + night**: field green for baseball/primary intent, warm gold for value/CTA/focus, cream text, and a near-black green canvas. The app at `b97c1b4` instead relied heavily on navy, bright blue, system backgrounds, stock controls, and ad-hoc typography.

The website was authored in OKLCH. The hex values below were recorded as approximate sRGB implementation references and required visual verification rather than blind literal substitution.

| Role | Historical website token | Approximate sRGB |
| --- | --- | --- |
| Background | `oklch(15.5% .008 145)` | `#121410` |
| Foreground | `oklch(93% .012 95)` | `#ECE8DD` |
| Card/popover | `oklch(19% .011 145)` | `#191C16` |
| Primary/field green | `oklch(47% .09 155)` | `#2E7D57` |
| Primary glow | `oklch(63% .11 155)` | `#46B07C` |
| Secondary surface | `oklch(23.5% .012 145)` | `#212420` |
| Muted surface | `oklch(22.5% .011 145)` | `#1F221E` |
| Muted foreground | `oklch(67% .014 110)` | `#A6A394` |
| Accent/focus gold | `oklch(77% .1 85)` | `#D6B370` |
| Accent foreground | `oklch(20% .02 100)` | `#2B2A1E` |
| Destructive | `oklch(60% .2 25)` | `#D0453E` |
| Border | `oklch(27% .012 145)` | `#282B24` |
| Input | `oklch(29% .012 145)` | `#2C2F27` |

Historical typography evidence was Archivo 700 for display/headings and Instrument Sans 400/600 for body/UI, with a 12-point base control radius, 16-point card radius, soft dark elevation, gold primary controls, bordered secondary controls, and a faint field/diamond texture. The native implementation uses the Home Plate token and typography system with platform-safe fallbacks; the web values remain visual references, not runtime contracts.

## 3. Historical findings and implemented disposition

| Historical finding at `b97c1b4` | Implemented disposition through Layer E |
| --- | --- |
| App identity was navy/blue rather than Home Plate green/gold/cream. | Layer A introduced the Home Plate semantic color foundation and compatibility mappings. |
| Fallback UI exposed “MultiOrg” instead of “Home Plate.” | Application identity and auth/access presentation now use Home Plate naming and safe organization context. |
| Type, spacing, radius, focus, and semantic roles were incomplete or ad hoc. | Layer A supplies the shared tokens; Layer C supplies production screen templates. |
| Cards, metrics, progress, states, and toasts were duplicated. | Shared HP components/templates are used across migrated surfaces; compatibility wrappers remain only where preserving public API avoids behavior churn. |
| Role roots used divergent navigation models. | Layer B supplies adaptive compact and regular-width application shells. |
| Player and coach could exceed five iOS tabs and fall into system “More.” | Compact navigation uses the branded Home Plate primary/overflow structure; regular widths use the adaptive sidebar/detail shell. |
| iPad looked like a stretched phone and macOS support was inconsistent. | Migrated screens use size-class-aware templates and the shared regular-width shell within the actual target source scope. iOS/iPadOS and native macOS builds are both release gates. |
| Stock fields/buttons/cards dominated production screens. | Layers C–D5 adopted HP fields, buttons, cards, tables, states, modals, and responsive compositions where semantics allow. Platform-native controls remain when required by Apple behavior or accessibility. |
| Light/dark behavior and state presentation were inconsistent. | Semantic tokens and the render matrix cover light, dark, and accessibility-size variants; screen migrations use shared state components for applicable cases. |
| Loading, empty, error, permission, stale, and success handling varied by feature. | Migrations standardized applicable state presentation while preserving each screen's existing lifecycle and service behavior. |

The original audit also said AI/Game Day/Recruiting screens did not exist. That was true only for the historical snapshot. The current tree has **12 live Phase 11 AI/import/Copilot destinations**, all included in migration coverage:

- Player: `PlayerDevelopmentPlayerWorkspaceView`, `PlayerDevelopmentPlayerReportDetailView`, `PlayerDevelopmentPlayerAlertDetailView`.
- Coach AI evidence/review: `PlayerDevelopmentAIWorkspaceView`, `DevelopmentReportDetailView`, `DevelopmentAlertDetailView`, `DevelopmentRosterAttentionView`.
- Import: `PlayerDevelopmentImportWorkspaceView`.
- Copilot: `PlayerDevelopmentCopilotWorkspaceView`, `PlayerDevelopmentCopilotConversationView`, `EvidenceCitationDetailView`, `ParentUpdateDraftDetailView`.

Therefore, the historical zero-consumer AI-evidence conclusion must not be used for current planning or coverage.

## 4. Current implementation record

| Layer | Commit | Result |
| --- | --- | --- |
| A | `6984417` | Universal foundation |
| B | `a98a772` | Navigation shells |
| C | `b651477` | Shared screen templates |
| D1 | `3d3bbae` | Player migration |
| D2 | `ef52cbb` | Parent migration |
| D3 | `7de2267` | Coach and Phase 11 coach migration |
| D4 | `4bd8262` | Owner/admin migration |
| D5 | `9d45f65` | Auth/access/subscription/notifications/chat/shared migration |
| E | `a588cb7` | Final cross-role consistency, recovery-state, accessibility, and interaction hardening |

Coverage at the Layer E/F boundary is:

- **51/51** historical original-map contract.
- **79/79** strict live current roots/screens/sheets.
- **82/82** map-compatible current surfaces after adding the three embedded targets.

The strict inventory deliberately excludes leaf components and six preserved but unreachable original source types. See the migration map for the exact lists and denominator rules.

## 5. Operational risks — current status

| Historical risk | Current status |
| --- | --- |
| Collision with an unrelated dirty worktree/branch | Resolved by the dedicated `/Users/lb33/Documents/HomePlate-ui-integration` worktree on `integration/universal-ui`. Other protected worktrees are not the implementation location. |
| Foundation files concurrently owned elsewhere | Resolved for this integration; Layer A is committed. Layer ownership and file manifests remain required for concurrent edits. |
| Xcode project generation was unavailable/uncertain | Superseded. The Xcode project was regenerated during Layers A–C where new source/test membership and iPad settings required it; `project.yml` remains authoritative. Layers D–F required no additional project-membership change. |
| Organization branding could override system semantics | HP system roles own CTA, focus, status, finance, and destructive semantics; organization color is constrained to identity context. |
| Navigation changes could disturb authorization/routing | Screen migrations preserve role/feature/entitlement gates, destinations, service calls, and lifecycle triggers; navigation smoke tests remain mandatory. |
| macOS scope could be overstated | QA must test the actual `MultiOrgMac` target source set and may not claim excluded feature files as native macOS coverage. |
| Protected worktree state could be misreported | `/Users/lb33/Documents/HomePlate-design` was verified clean on `design/home-plate-os` at `0116ab1c2c3ff41e9fd7e7e09796f3c9f5a60dd2`. `/Users/lb33/Documents/HomePlate` was read-only but had externally changed to `docs/hpms` at `d109326e7b3e55be85db506c0a8ea9594f6ece9d`, with pre-existing untracked `.agents/`, `.aider-desk/`, `XcodeGen/`, `build/`, `skills-lock.json`, `spatial`, and tools artifacts. This integration did not alter either protected worktree. |
| Visual completion could be mistaken for deployment readiness | Layer E consistency and Layer F full tests/renders/smoke/audit are complete. The result is ready for release preparation, but no UI coverage ratio or this audit authorizes deployment. |

## 6. Behavior-preservation conclusions

The redesign is presentation and navigation composition, not a product-logic rewrite. The following remain guarded boundaries:

- authorization, organization membership, feature and terminology gating;
- Supabase/RLS/Edge Function behavior and Phase 11 evidence/import/Copilot data contracts;
- auth and Sign in with Apple flows;
- StoreKit purchase and verification behavior;
- Stripe/payment/reconciliation behavior and integer-cent money handling;
- notification producers, APNs, chat transport, unread/read semantics, and deep-link routing;
- task, refresh, change, appearance, dismissal, file-import, alert, and persistence lifecycle behavior.

Current readiness claims must be supported by the builds, test suites, render matrix, interaction smoke tests, static checks, and exact inventory in the companion QA and migration-map documents.

## 7. Layer F final acceptance audit

Layer F validated the exact production/test tree in Layer E `a588cb77ddda2c884891d390dea5bcfdd7ce0918`. The Layer F closeout commit is documentation-only and therefore does not invalidate the exact build/test evidence below.

| Audit area | Result |
| --- | --- |
| Coverage/reachability | **51/51** historical contract, **79/79** strict live current roots/screens/sheets, and **82/82** map-compatible surfaces. The three embedded panes and six preserved unreachable source types remain separately classified. |
| Swift validation | Non-render: **237** logical / **251** invocations passed. Render: **59/59** passed. Aggregate: **296** logical / **310** invocations, zero failures/skips/expected failures. |
| Builds | Clean iOS simulator `build-for-testing` passed on iOS 26.5. Clean native arm64 `MultiOrgMac` build passed. |
| Render/visual QA | 28 render-producing methods emitted 164 exact PNGs across light/dark, compact/regular, iPhone/iPad/macOS-width, live controls, state variants, and Accessibility 3. 162 are content-bearing; two retained final gallery windows are proven background-only height-estimation artifacts after the preceding window completes the gallery. Inspected evidence has no unresolved blocker/high UI finding. |
| Backend guardrail | Focused Phase 11 shared tests **148/148**; complete shared backend tests **373/373**; relevant 11-file Deno format/type checks passed. No backend file changed. Broad committed baseline findings—17/66 unformatted files and eight Stripe webhook type errors—are pre-existing and outside this presentation-only diff. |
| Static/security/data integrity | `git diff --check` passed. No migration, Supabase function, `project.yml`, or Xcode project diff in Layer E; no staged/untracked file, ignored build secret/config, tracked secret path, secret symlink, debug marker, merge operation, or repository-history operation remained at its boundary. Authorization, organization scoping, money/data contracts, and lifecycle behavior are unchanged. |
| Operational exclusions | No deployment, migration application, push/PR, external-AI invocation, APNs/notification delivery, import upload/commit, StoreKit purchase, payment mutation, or secrets change occurred. |

Recurring render-only UIKit diagnostics were classified as informational: 376 FocusState-outside-body messages, 564 flattened representable messages, 85 appearance-transition imbalance messages, one IOSurface message, and one first-responder/window message. Duplicate LazyVGrid ID diagnostics are zero. These arise from off-window evidence rendering; the native builds and all render assertions pass.

The only build warnings are informational local-validation output: two AppIntents metadata skips plus four repeated emissions of two existing unused test-helper results in the unsigned iOS test build, and one AppIntents metadata skip in the unsigned macOS build. No new production compiler warning or error was found.

Conclusion: no blocker or high-severity Universal UI defect remains in the validated scope. The branch is ready for release preparation and product-owner acceptance, not deployment.
