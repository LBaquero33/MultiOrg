# HOME PLATE — STAGE 3 PLAN (Preview‑only components)

**Status:** Proposal — **requires user approval before any code is written.** No production code yet.
**Absolute path:** `/Users/lb33/Documents/DHD-Self-Development-iOS-multiorg/Docs/design/HOME_PLATE_STAGE3_PLAN.md`
**Companions:** `HOME_PLATE_DESIGN_SYSTEM.md`, `HOME_PLATE_COMPONENT_LIBRARY.md`.

Stage 3 = build the `HP` token layer + first components as **isolated SwiftUI previews with sample data**. **No production screen is modified; no existing file Codex is touching is edited.** Finance pilot (Stage 4) is separately gated.

---

## 1. Git worktree / branch strategy

**Facts:** current checkout is on `codex/apple-iap-rebuild-20260713` with a **dirty tree** (incl. `DHDTheme.swift`, `DHDUIComponents.swift` modified by Codex). `main` exists and is clean. Only one worktree exists today.

**Proposal — a dedicated worktree off `main`:**

```bash
# from the repo root; leaves Codex's dirty checkout completely untouched
git worktree add ../HomePlate-design -b design/home-plate-os main
```

- New branch **`design/home-plate-os`** based on **`main`** (clean base) in a **separate directory** (`../HomePlate-design`), so Codex's working tree and branch are never touched.
- Rationale: Stage 3 is **purely additive** (new files), so a clean `main` base avoids inheriting Codex's in‑flight backend churn and eliminates merge risk during design work.
- All design work (Stage 3, and later integration branches) happens in this worktree. Codex keeps `codex/…` in the primary checkout.
- Cleanup when done: `git worktree remove ../HomePlate-design`.

**Alternative (if you prefer one checkout):** a plain branch `design/home-plate-os` off `main` in place — but this would require stashing/switching around Codex's dirty tree and is riskier. **Worktree is recommended.**

## 2. Avoiding collisions with Codex

| Rule | How |
| --- | --- |
| Separate physical checkout | Worktree at `../HomePlate-design` (§1). |
| **Do not edit files Codex is editing** | Stage 3 **adds new files only** under `MultiOrg/DesignSystem/`. It does **not** edit `DHDTheme.swift` or `DHDUIComponents.swift` (both currently modified by Codex). The `HP` namespace is new files; the later `DHDTheme→HP` alias/migration is deferred to an integration step and coordinated with Codex. |
| No backend/protected files | Nothing under `supabase/`, `Configs/`, Stripe/StoreKit/APNs/auth paths is touched (handoff §6, §25). |
| No project‑wide git ops | No broad `git add`, `reset`, `clean`, restore‑all. Commit only the new `MultiOrg/DesignSystem/**` + `project.yml`/`.pbxproj` regen, and only when you ask. |
| Rebase discipline | Before integration (Stage 4+), rebase `design/home-plate-os` onto the then‑current target branch; resolve `DHDTheme`/`DHDUIComponents` intentionally, once, with Codex's changes visible. |
| Communication | Confirm with you (and Codex's owner) before the first edit that touches a shared file. |

## 3. XcodeGen installation & regeneration workflow

**Facts:** `xcodegen` is **not** on PATH; `brew`/`mint` absent. But **XcodeGen source is vendored in‑repo** at `XcodeGen/` (`Package.swift`, `Makefile`). `project.yml` is the source of truth; the `MultiOrg`/`MultiOrgMac` targets use `sources: path: MultiOrg` globs, so **new `.swift` files under `MultiOrg/` are auto‑included — no `project.yml` edit needed** (only regeneration).

**Install (from vendored source, no brew):**
```bash
swift build -c release --package-path XcodeGen        # builds .build/release/xcodegen
# optional: ln -s "$PWD/XcodeGen/.build/release/xcodegen" /usr/local/bin/xcodegen
```

**Regenerate after adding files:**
```bash
# run in the design worktree
swift run -c release --package-path XcodeGen xcodegen generate
#   (or: ./XcodeGen/.build/release/xcodegen generate  — reads ./project.yml)
```

- Regeneration is needed so `project.pbxproj` references the new files for command‑line `xcodebuild`.
- **Only edit `project.yml`** if we add a new target, a bundled **font resource** (Archivo/Instrument Sans → resource + `UIAppFonts`), or a resource file. Component `.swift` files need no manifest edit.
- Preserve target membership (design files must build on **both** `MultiOrg` and `MultiOrgMac`; keep them out of `Features/Player/**`, which macOS excludes).

## 4. Proposed new file structure

All additive, under a new group so it's isolated and obvious:

```
MultiOrg/DesignSystem/
  Tokens/
    HPColor.swift          # Display-P3 role tokens (§2 design system) + hp.identity org channel
    HPFont.swift           # type scale, custom→SF Pro fallback, Dynamic Type
    HPMetrics.swift        # Space / Radius / Shadow / Motion tokens
    HPTheme.swift          # namespace umbrella + (later) DHDTheme alias shim — NOT edited into DHDTheme
  Components/
    HPButton.swift  HPCard.swift  HPMetricCard.swift  HPStatTile.swift
    HPWorkspaceHeader.swift  HPSectionHeader.swift  HPStatusBadge.swift  HPAvatar.swift
    HPTable.swift  HPChart.swift  HPFormField.swift  HPMoneyField.swift
    HPSearchBar.swift  HPFilterBar.swift  HPSegmentedControl.swift  HPToast.swift
    HPEmptyState.swift  HPLoadingState.swift  HPErrorState.swift  HPSidebar.swift
    HPProgressIndicator.swift  HPModal.swift  HPWorkspaceDirectory.swift
  Preview/
    HPSampleData.swift     # mock players/finance/notifications — NO network, NO Supabase
    HPComponentGallery.swift  # one #Preview per component, variant×state matrix
```

- `MultiOrg/DesignSystem/` is picked up automatically by the `path: MultiOrg` glob on both targets.
- **Sample data is local mock only** — no `SupabaseService`, no live models mutated, no auth. Previews never hit the network.

## 5. Exact Stage 3 files that would be added

**Tokens (4):** `HPColor.swift`, `HPFont.swift`, `HPMetrics.swift`, `HPTheme.swift`.
**Components (23):** `HPButton`, `HPCard`, `HPMetricCard`, `HPStatTile`, `HPWorkspaceHeader`, `HPSectionHeader`, `HPStatusBadge`, `HPAvatar`, `HPTable`, `HPChart`, `HPFormField`, `HPMoneyField`, `HPSearchBar`, `HPFilterBar`, `HPSegmentedControl`, `HPToast`, `HPEmptyState`, `HPLoadingState`, `HPErrorState`, `HPSidebar`, `HPProgressIndicator`, `HPModal`, `HPWorkspaceDirectory`.
**Preview (2):** `HPSampleData.swift`, `HPComponentGallery.swift`.

**Total: 29 new files. Zero existing files edited** (except the XcodeGen‑regenerated `project.pbxproj`, which is a generated artifact — and only when you approve a commit). `project.yml` edited **only** if fonts are bundled in this stage.

## 6. Preview‑only implementation plan

1. **Tokens first** — `HPColor/HPFont/HPMetrics`, verified in a color/type swatch `#Preview` against the live site (Display‑P3 tuning of green/gold).
2. **Foundation components** — `HPCard`, `HPButton`, `HPSectionHeader`, `HPStatusBadge`, `HPEmptyState`, `HPLoadingState`, `HPErrorState` (these unblock everything).
3. **Data components** — `HPMetricCard`, `HPStatTile`, `HPTable`, `HPChart`, `HPFormField`, `HPMoneyField`.
4. **Nav/chrome** — `HPWorkspaceHeader`, `HPSidebar`, `HPWorkspaceDirectory`, `HPToast`, `HPModal`, `HPSearchBar`, `HPFilterBar`, `HPSegmentedControl`, `HPAvatar`, `HPProgressIndicator`.
5. **Gallery** — `HPComponentGallery` renders every component × variants × states × Dynamic Type XL × iPhone/iPad/macOS, using `HPSampleData`.
6. **Fonts** — validate Archivo/Instrument Sans (license, `project.yml` resource, on‑device rendering, Dynamic Type) **or** confirm SF Pro fallback; `HPFont` must resolve cleanly either way (decision 5).
7. **No screen swaps.** Existing production views are untouched. Output = a compilable component gallery you can review in Xcode previews / simulator, plus before/after mockups for the Finance pilot proposal.

**Deliverable of Stage 3:** the 29 files above, building on iOS + macOS, with a preview gallery and screenshots — then we stop for Finance‑pilot (Stage 4) approval.

## 7. Build & verification commands

Run in the design worktree (`../HomePlate-design`). Same pattern already used successfully in Stage 1.

```bash
# 0. (once) build XcodeGen from vendored source, then regenerate the project
swift build -c release --package-path XcodeGen
swift run -c release --package-path XcodeGen xcodegen generate

# 1. iOS Simulator build (no signing)
xcodebuild -project MultiOrg.xcodeproj -scheme MultiOrg \
  -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath /tmp/hp-dd build

# 2. Native macOS build
xcodebuild -project MultiOrg.xcodeproj -scheme MultiOrgMac \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath /tmp/hp-dd-mac build

# 3. Focused tests (design system has no logic, but keep the suite green)
xcodebuild -project MultiOrg.xcodeproj -scheme MultiOrg \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test

# 4. Preview evidence (gallery) — boot sim, install, screenshot
xcrun simctl boot "iPhone 17 Pro"; \
xcrun simctl install "iPhone 17 Pro" <built .app>; \
xcrun simctl launch "iPhone 17 Pro" com.multiorg.app; \
xcrun simctl io "iPhone 17 Pro" screenshot hp-gallery.png

# 5. Hygiene
git diff --check          # whitespace/conflict markers
git status --porcelain    # confirm ONLY MultiOrg/DesignSystem/** (+ regen) changed
```

**Evidence gate:** report BUILD SUCCEEDED for both targets, test result, `git diff --check` clean, the exact new‑file list, and gallery screenshots. **Never claim success without this** (handoff §25).

## 8. What stays read‑only throughout Stage 3

Supabase schema/migrations/RLS/Edge Functions · Stripe/Connect/Checkout/reconciliation/payment‑requests · StoreKit/subscription verification/App Store notifications · authentication/authorization/membership/platform‑admin · `SupabaseService`/networking · notification producers/APNs worker/device registration · financial calculations · backend models/business rules. Inspected for UI needs only; never modified (handoff §6, §25).

---

## Approval checkpoint

Stage 3 begins only on your go‑ahead. Open confirmations:
1. Approve the **worktree off `main`** strategy (§1)?
2. OK to **build XcodeGen from the vendored source** (§3), or do you want it installed another way?
3. Bundle **Archivo/Instrument Sans in Stage 3**, or build against **SF Pro first** and add custom fonts once licensing is confirmed?
