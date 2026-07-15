# HOME PLATE — DESIGN QA

**Status:** Stage 2 spec — approved direction. This checklist gates every screen from Stage 4 onward.
**Absolute path:** `/Users/lb33/Documents/DHD-Self-Development-iOS-multiorg/Docs/design/HOME_PLATE_DESIGN_QA.md`
**Companions:** `HOME_PLATE_DESIGN_SYSTEM.md`, `HOME_PLATE_COMPONENT_LIBRARY.md`, `HOME_PLATE_MOTION_SYSTEM.md`.

A screen is **not done** until every applicable item passes. Use per‑screen in PRs (copy the checklist). "N/A" is allowed with a one‑line reason.

## A. Identity & tokens
- [ ] Colors come from `HP.Color` tokens — **no** literal `Color(red:…)`, no raw `.blue/.orange/.mint`, no `Color(.systemBackground)`.
- [ ] Green/gold/danger/success/focus are **HP‑controlled**; org brand color only on identity chrome (header/avatar/badge) (decision 1).
- [ ] Typography via `HPFont` scale (custom→SF fallback); money/stats use **tabular figures**.
- [ ] Spacing/radius/shadow from tokens; no ad‑hoc 10/14 spacing.
- [ ] Product name reads **"Home Plate"** (no "MultiOrg" leakage).

## B. Layout & composition
- [ ] `HPWorkspaceHeader` present with title + context.
- [ ] **Exactly one** primary action (gold) — Manifesto principle 8.
- [ ] Vertical rhythm: header → attention → core cards → detail.
- [ ] Uses shared components (`HPCard`, `HPMetricCard`, `HPTable`, …) — no re‑implemented tiles/rings/toasts.
- [ ] Metrics show **context** (delta/trend/comparison) where available — Manifesto principle 3.

## C. States (every applicable one designed)
- [ ] Loading (`HPLoadingState`/skeleton; partial data not fully blocked)
- [ ] Empty (`HPEmptyState`, specific copy + optional single CTA)
- [ ] Error (`HPErrorState` with retry; no raw `localizedDescription`)
- [ ] Permission‑denied (`HPPermissionState`; calm, role‑aware)
- [ ] Offline (`HPOfflineBanner`; mutations needing network disabled w/ reason)
- [ ] Stale (`HPStaleIndicator` + refresh)
- [ ] Success (`HPToast`/inline; single toast implementation; non‑bouncy)
- [ ] Locked/upgrade (`HPLockedState`/`HPUpgradeCard`; **renders state only, no hardcoded plan checks**)

## D. Accessibility
- [ ] Contrast ≥ 4.5:1 (verify text‑on‑gold and gold‑text‑on‑dark separately).
- [ ] Status conveyed by **text/icon + color**, never color alone.
- [ ] Dynamic Type to XL without clipping/overlap (relative fonts).
- [ ] VoiceOver: labels/values/traits on interactive + metric elements; headers marked `.isHeader`.
- [ ] Focus visible (gold ring) on macOS/iPad; logical focus order.
- [ ] Reduce Motion + Reduce Transparency honored (`HOME_PLATE_MOTION_SYSTEM.md`).
- [ ] Icon‑only controls have `accessibilityLabel`.

## E. Interaction & motion
- [ ] Motion uses `hp.motion.*` tokens; calm/purposeful; no bounce on routine transitions.
- [ ] Destructive actions go through `HPConfirmationDialog`.
- [ ] Touch targets ≥ 44pt (iOS).
- [ ] Loading buttons keep label, no layout shift.

## F. Platform
- [ ] **iPhone:** ≤5 primary tabs (hard cap); overflow via branded `HPWorkspaceDirectory` (not system "More"); drill‑in works.
- [ ] **iPad:** regular‑width uses split/sidebar + multi‑col grids; not a stretched phone; portrait‑lock relaxed where applicable.
- [ ] **macOS:** sidebar + detail, toolbar, hover/focus, click‑out modals; not an enlarged iPhone.
- [ ] macOS scope: existing coach/admin surfaces only — **no net‑new player/parent macOS** (decision 3).
- [ ] Keyboard: sidebar navigable; sensible ⌘‑Return primary; Esc dismisses modals.

## G. Data & correctness (presentation‑only guardrails)
- [ ] **No business‑logic regression** — ViewModels, services, models, authorization, data flow behave identically.
- [ ] No changes to Supabase/RLS/Edge Functions, Stripe/reconciliation, StoreKit/verification, auth/authorization, APNs/producers (handoff §6, §25).
- [ ] Money is integer‑cent, currency‑ and locale‑aware; validation logic preserved.
- [ ] Feature/terminology gating via existing `feature()`/`term()`; entitlement/locked states render UI only.
- [ ] Platform‑support mode stays visually explicit (support ≠ ownership).

## H. Build & verification (evidence required — never claim success without it)
- [ ] iOS Simulator build succeeds.
- [ ] Native macOS build succeeds.
- [ ] Focused tests pass (affected areas).
- [ ] `git diff --check` clean.
- [ ] Before/after screenshots (iPhone + iPad + macOS as applicable) attached.
- [ ] Exact files changed listed.

## Per‑screen sign‑off block (paste in PR)

```
Screen: ____________________   Platforms: iPhone [ ] iPad [ ] macOS [ ]
A Identity/tokens [ ]   B Layout [ ]   C States [ ]   D A11y [ ]
E Motion [ ]   F Platform [ ]   G Correctness [ ]   H Build+evidence [ ]
Notes / N-A justifications: __________________________________________
```
