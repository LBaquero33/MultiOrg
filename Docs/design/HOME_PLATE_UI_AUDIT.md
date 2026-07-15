# HOME PLATE — UI AUDIT (Phase 10, Stage 1)

**Status:** Read-only audit. No production code was modified to produce this document.
**Author:** Claude (design initiative)
**Date:** 2026-07-15
**Scope:** Presentation layer only — website + native iOS/iPadOS/macOS SwiftUI. Backend, payments, auth, and notification systems were inspected for UI requirements only and were **not** modified.

---

## 0. How this audit was produced

| Surface | Method | Evidence |
| --- | --- | --- |
| Website | Live inspection of `https://homeplateapps.com/` — extracted computed CSS custom properties, typography, button/card styles, and a hero screenshot. | Design tokens in §2. |
| iOS app | Static read of all 84 SwiftUI files under `MultiOrg/`, plus a clean **iOS Simulator build (BUILD SUCCEEDED)** and a live launched screenshot of the login screen (iPhone 17 Pro). | §3, §4. |
| macOS app | Static read (macOS-specific `#if os(macOS)` branches) + native build of `MultiOrgMac`. | §3, §5. |
| iPad | Static read (`TARGETED_DEVICE_FAMILY = "1,2"`, shares the iOS code paths; `UIRequiresFullScreen = true`). | §5. |

Source of truth for the app structure: `project.yml` (XcodeGen). Targets: `MultiOrg` (iOS/iPadOS), `MultiOrgMac` (macOS), `MultiOrgTests`.

---

## 1. Executive summary

The application is **technically mature but visually disconnected from its own brand.** The website presents a confident, premium "baseball operating system" identity — a dark green‑charcoal canvas, baseball field‑green primary, warm gold accent, cream serif‑adjacent display type. The shipping app presents a **generic dark‑mode developer UI**: near‑black system backgrounds, a bright macOS‑blue accent, default SF typography, and stock SwiftUI controls. It is even branded **"MultiOrg,"** not "Home Plate."

The single most important finding: **the app and the website do not share a visual identity.** Closing that gap is the entire point of Phase 10.

The good news: the codebase already has the *bones* of a design system (`DHDTheme`, `DHDCard`, `DHDStatusBadge`, org‑level white‑label branding, native Swift Charts, feature‑flag/terminology gating). This is a **re‑skin + consolidation** problem far more than a rewrite. The design tokens are centralized enough that a palette/typography change propagates widely from a small number of files.

**Top 10 findings (ranked):**

1. **Brand/identity mismatch (critical).** App accent = bright blue `#4C9EFA`, background = navy/system‑black. Website = green‑charcoal + field green + gold + cream. The app does not look like Home Plate.
2. **Wrong product name on screen.** The login screen title renders **"MultiOrg"** (fallback branding) and the fallback brand color is navy. See `DHDOrgBranding.fallback` / `LoginView`.
3. **No design‑token layer for type or the full color role set.** `DHDTheme` defines navy/blue + surfaces but has **no typography scale, no accent‑gold, no primary‑green, no semantic role tokens** (e.g. muted, ring, destructive‑on‑surface). Fonts are ad‑hoc `.title3`, `.headline`, `.caption` system calls.
4. **Duplicate / inconsistent components.** Toasts implemented **twice** (`DHDToast` + inline `.thinMaterial` toast in `SDPlayerTodayView`). Metric tiles, progress rings, and "stat" tiles are re‑implemented inline (`ImprovementTile`, `ProgressRing`, `StrengthExerciseLogger`) instead of shared components.
5. **Two divergent navigation models with no unifying shell.** iOS uses flat per‑role `TabView`s; macOS uses `NavigationSplitView` (Coach only). There is no shared "workspace" concept; each role root is bespoke.
6. **iOS tab overload.** `PlayerHomeView` declares **up to 8 tabs** (Today, Calendar, Chat, Facilities, Trends, Testing, Analysis, Account); Coach declares **up to 8**. iOS collapses >5 into a system "More" list — an unbranded, low‑quality overflow.
7. **macOS is not at parity.** `PlayerHomeView` on macOS is a **"coming soon" placeholder**; `ParentRootView` on macOS is a bare `ParentHomeView` with no chrome. The macOS app is effectively coach‑only.
8. **Default SwiftUI surfaces everywhere.** `.textFieldStyle(.roundedBorder)`, `.buttonStyle(.borderedProminent)`, default `TabView`, default segmented control, default `DatePicker`, `Color(.systemBackground)` hardcoded tiles. These read as "stock," not "designed."
9. **Forced‑dark inconsistency.** iOS forces `.preferredColorScheme(.dark)` in `RootView`; macOS hardcodes a dark palette in `DHDTheme`. There is no true light mode, and the website is also dark — so **dark‑first is correct**, but it is achieved by three different mechanisms rather than one token system.
10. **Every‑state coverage is partial.** Loading/empty/error exist in the mature areas (Finance, Notifications) but are inconsistent elsewhere (ad‑hoc `ProgressView()` + `Text` blocks; some screens have no empty state).

Dead code found: `PlotlyChartView.swift` is a documented placeholder ("preserves older project references"); real charts use **Swift Charts + Canvas** in `BPAnalysisComponents`. (Flagged, not fixed.)

---

## 2. Website — the visual source of truth (extracted tokens)

Extracted live from `homeplateapps.com` `:root`. The site is authored in **OKLCH**. SwiftUI on the current deployment targets (iOS 17 / macOS 14) has no native OKLCH literal, so the sRGB/hex column is an **approximate conversion to verify at implementation time** (ideally via Display‑P3 for the greens/gold).

### Color

| Role | Website (OKLCH) | Approx hex | Notes |
| --- | --- | --- | --- |
| Background | `oklch(15.5% .008 145)` | `~#121410` | Near‑black, faint green tint (hue 145). **Not navy.** |
| Foreground (text) | `oklch(93% .012 95)` | `~#ECE8DD` | Warm cream, not pure white (hue 95). |
| Card | `oklch(19% .011 145)` | `~#191C16` | One step up from background. |
| Popover | `oklch(19% .011 145)` | `~#191C16` | Same as card. |
| Primary | `oklch(47% .09 155)` | `~#2E7D57` | Baseball **field green**. |
| Primary‑glow | `oklch(63% .11 155)` | `~#46B07C` | Brighter green for emphasis/gradients. |
| Secondary (surface) | `oklch(23.5% .012 145)` | `~#212420` | Raised control surface. |
| Muted | `oklch(22.5% .011 145)` | `~#1F221E` | Muted fills. |
| Muted‑foreground | `oklch(67% .014 110)` | `~#A6A394` | Secondary text. |
| **Accent (gold)** | `oklch(77% .1 85)` | `~#D6B370` | Warm **gold/leather** — the primary CTA color. |
| Accent‑foreground | `oklch(20% .02 100)` | `~#2B2A1E` | Dark text on gold. |
| Destructive | `oklch(60% .2 25)` | `~#D0453E` | Red. |
| Border | `oklch(27% .012 145)` | `~#282B24` | Low‑contrast hairline. |
| Input | `oklch(29% .012 145)` | `~#2C2F27` | Field border/fill. |
| Ring (focus) | `oklch(77% .1 85)` | `~#D6B370` | **Focus ring = gold**, matches accent. |

**Semantic reading:** the palette is *leather + grass + night*. Green = the game/field/primary intent; gold = value/money/CTA/focus; cream = readable warmth; near‑black‑green = the calm canvas. This is a deliberate, ownable identity — **not** generic SaaS blue.

### Typography

| Element | Font | Weight | Size / tracking | Notes |
| --- | --- | --- | --- | --- |
| Display / headings | **Archivo** | 700 | 60px, letter‑spacing −1.2px, line‑height 75px (hero H1) | Tight, condensed‑grotesque display voice. |
| Body / UI | **Instrument Sans** | 400 / 600 | 16px base | Humanist sans for prose and controls. |
| Section eyebrows | Instrument Sans | 600 | small, uppercase, gold/muted | e.g. "THE PROBLEM", "PLATFORM OVERVIEW". |

### Shape, elevation, motion

| Token | Website value | Notes |
| --- | --- | --- |
| Base radius | `--radius: 0.75rem` (12px) | Buttons/inputs 12px. |
| Card radius | 16px | Larger than base. |
| Card shadow | `0px 12px 40px -18px` @ ~0.6 black | Large, soft, low‑opacity, high blur — "floating on dark." |
| Primary button | Gold fill, dark text, 12px radius, weight 600, padding 10×20 | |
| Secondary button | Transparent, 1px border `~#282B24`, cream text | |
| Pill/badge | Rounded‑full, gold hairline border, gold text (hero eyebrow) | |
| Hero texture | Faint square/diamond grid over the dark canvas | The app already has a diamond motif (`DHDDiamondPattern`) — reusable bridge. |

---

## 3. Current app design layer (as built)

### `DHDTheme` (MultiOrg/Core/DHDTheme.swift)

Centralized, which is good. But it encodes the **wrong** identity and is incomplete:

| Token | Current value | vs. website | Verdict |
| --- | --- | --- | --- |
| `navy` | `rgb(0.05,0.14,0.27)` ≈ `#0D2445` | Website has no navy | Replace with green‑charcoal system |
| `navy2` | `rgb(0.04,0.22,0.33)` ≈ `#0A3854` | — | Replace |
| `accent` | `rgb(0.30,0.62,0.98)` ≈ `#4C9EFA` (bright blue) | Website accent = gold | **Replace with gold; add field‑green primary** |
| `cornerRadius` | 16 | Card 16 ✓ | Keep; add 12 base token |
| `pageBackground` (iOS) | `.systemGroupedBackground` | Website `#121410` | Replace with explicit token |
| `pageBackground` (macOS) | `#0F1217`ish (`0.06,0.07,0.09`) | Slightly blue‑gray | Re‑tint green‑charcoal |
| Shadows | subtle (0.06 iOS / 0.22 macOS) | Website large soft | Add elevated card shadow |
| Typography | **none** | Archivo/Instrument Sans | **Add full type scale** |
| Semantic roles | success/danger/info = system green/red/blue | Website destructive/ring/muted | Add role tokens |

Positive: `DHDTheme.color(hex:fallback:)` already parses org hex colors → org white‑labeling is respected. The new token system must keep org‑brand override working (see §7).

### Existing components (MultiOrg/Core/DHDUIComponents.swift)

| Component | Role | Reusable as | Gaps |
| --- | --- | --- | --- |
| `DHDCard` (flat/elevated) | Surface container | → `HPCard` | Uses `separator.opacity(0.35)` border; fine |
| `DHDHeaderCard` | Gradient hero header + diamond overlay | → `HPWorkspaceHeader` base | Uses org gradient; keep |
| `DHDOrgMenuHeader` | Sidebar/branding header | → `HPSidebar` header | macOS‑leaning |
| `DHDSectionHeader` | Title + trailing accessory | → `HPSectionHeader` | Good, adopt widely |
| `DHDStatusPill` / `DHDStatusBadge` | Status chips | → `HPStatusBadge` | Two variants; unify |
| `DHDFormRow` | Label + value row | → part of `HPFormField` | Read‑only row only |
| `DHDDiamondPattern` | Baseball texture | Keep as brand texture | Nice bridge to website grid |
| `DHDToast` + `dhdToast()` | Transient toast | → `HPToast` | **Duplicated** by inline toast in Today |
| `dhdFloatingModal` (macOS) | Click‑out modal | → `HPModal` (macOS) | macOS‑only |
| `dhdPageBackground()` | Page bg helper | Keep | |

### Re‑implemented inline (should become shared components)

- `ImprovementTile` (SDPlayerTodayView) → **`HPMetricCard` / `HPStatTile`**
- `ProgressRing` (SDPlayerTodayView) → **`HPProgressIndicator`**
- `StrengthExerciseLogger` local card → generic **`HPCard` + `HPFormField`**
- Finance building blocks (`FinanceOverviewView`, `RecentPaymentsView`, `FinancePaymentRequestsView`, `FinanceDateRangePicker`) — already componentized and ViewModel‑driven (good), but styled ad‑hoc.

---

## 4. iOS / iPadOS audit

**Navigation:** `RootView` → role branch (`CoachRootView` / `ParentRootView` / `PlayerHomeView`). iOS forces `.preferredColorScheme(.dark)`. Each role root is a flat `TabView`; each screen wraps itself in its own `NavigationStack`.

| Role | iOS tabs (max) | Issue |
| --- | --- | --- |
| Player | 8 (Today, Calendar, Chat, Facilities, Trends, Testing, Analysis, Account) | Overflows into system "More" (>5). No workspace grouping. |
| Coach | 8 (Players, Facilities, Teams, Chat, Programs, Org Admin, Platform, Account) | Same overflow; mixes daily + admin. |
| Parent | 3 (Children, Chat, Account) | Reasonable. |

**Login screen (live capture):** title "MultiOrg", pure‑black bg, blue org name + blue links, default segmented "Sign In / Create Account", `.roundedBorder` fields, default "Sign in with Apple". **This is the clearest single example of the identity gap.**

**iPad:** `TARGETED_DEVICE_FAMILY = "1,2"` and `UIRequiresFullScreen = true`, portrait‑only. iPad currently runs the **iPhone** layout scaled up — no split view, no sidebar, no multi‑column. This is a large opportunity (handoff §3: "iPad app must not feel like a compressed desktop dashboard" — today it's a stretched *phone*).

**Recurring iOS anti‑patterns:** hardcoded `Color(.systemBackground)` tiles inside dark cards; ad‑hoc toasts; `.borderedProminent` blue buttons; per‑screen toolbar `Menu` with Refresh/Sign Out repeated; inconsistent section spacing (14/16 mixed).

---

## 5. macOS audit

**Navigation:** `DesktopRootView` → Coach uses a real `NavigationSplitView` sidebar (`DHDOrgMenuHeader` + labeled `NavigationLink`s + role/feature gating). This is the **closest existing thing to the handoff's workspace sidebar** and a good foundation for `HPSidebar`.

**Gaps:**
- `PlayerHomeView` (macOS) = **placeholder** ("Player features coming soon on macOS").
- `ParentRootView` (macOS) = bare `ParentHomeView`, no sidebar/chrome.
- `MultiOrgMac` target **excludes `Features/Player/**`** entirely (see `project.yml`) — player workflows are structurally absent on macOS.
- Palette hardcoded dark in `DHDTheme` `#if canImport(AppKit)` branches (blue‑gray, not green‑charcoal).

macOS build: `MultiOrgMac` compiles (see build log). Enlarged‑iPhone risk is **low for Coach** (real sidebar) but **the app is coach‑only** on desktop.

---

## 6. Cross‑cutting issues

| Theme | Detail | Risk |
| --- | --- | --- |
| Identity | Navy/blue vs green/gold; "MultiOrg" branding | Critical (brand) |
| Token completeness | No type scale, no primary/accent/semantic roles | High |
| Component duplication | Toasts, tiles, rings, stat blocks | Medium |
| Navigation | Two models, tab overflow, no workspace shell | High |
| Platform parity | macOS coach‑only; iPad = scaled phone | High |
| Default SwiftUI surfaces | fields/buttons/pickers/tabs stock | Medium (visual) |
| State coverage | inconsistent empty/error/loading | Medium |
| Accessibility | some good `accessibilityElement` use; contrast of gold‑on‑dark and org‑arbitrary colors unverified | Medium |
| Org white‑label | Arbitrary org hex colors can fight the HP system | Medium (see §7) |

---

## 7. Risks specific to the redesign

1. **Coordination collision (highest operational risk).** The working tree is **dirty** and currently on branch **`codex/apple-iap-rebuild-20260713`**, with `DHDTheme.swift` and `DHDUIComponents.swift` — the exact core design files a redesign edits — **already modified by Codex**. Editing them now would collide directly with active backend work. → *Design implementation must happen on a separate branch/worktree, and must be sequenced with Codex.* (Handoff §7, §25.)
2. **Org white‑label vs. HP identity.** `DHDOrgBranding` lets each org inject `primary/secondary/accent` hex. A pure HP repaint could be overridden per‑org (as seen: "Marist Red Foxes" renders blue). The token system must define **how org brand color and HP system color coexist** (e.g. org color for header/avatar/identity only; HP gold/green for system semantics like CTAs, focus, finance).
3. **Forced dark + no light mode.** Website is dark, app is dark — fine. But three mechanisms enforce it. Consolidating to one token layer risks regressions if any screen assumed system colors.
4. **`xcodegen` is not installed** on this machine (`xcodegen not found`). Adding new component files requires updating `project.yml` and regenerating — either install XcodeGen or add files via the existing `.xcodeproj` groups carefully. Flag before Stage 3.
5. **OKLCH → sRGB fidelity.** Naive conversion can dull the green/gold. Recommend Display‑P3 color literals and eyeball verification against the live site.
6. **iPad restructuring is behavior‑adjacent.** Introducing split views changes navigation presentation (allowed) but must not change routing/permission logic. Keep NavigationStack destinations identical.
7. **macOS player parity is net‑new UI**, not a repaint. Scope it separately from the pilot.

---

## 8. Redesign risk map — where to start

| Area | Redesign risk | Why |
| --- | --- | --- |
| **Finance Overview** (pilot) ✅ | **Low** | Already componentized + ViewModel; cards/metrics/charts/tables/filters/loading/empty/error all present; stable backend; high visual payoff. |
| Notification Center | Low | Already MVVM, clear rows. |
| Token layer + core components (Stage 3) | Low‑med | Isolated, preview‑driven; no screen swaps. |
| Global nav shell / sidebar | Medium | Touches all role roots; must preserve routing/permissions. |
| Player Today | Medium | Dense logging UI, lots of inline state. |
| Coach player workflows | Medium‑high | Many interdependent screens. |
| iPad split‑view restructure | High | Layout change across the app. |
| macOS player parity | High | Net‑new UI, not a repaint. |
| Login/auth surfaces | Medium | High brand value, but touches Apple Sign‑In flow (do not alter auth logic — presentation only). |

**Recommended pilot: Finance Overview** (matches handoff §24 Stage 4).

---

## 9. What was confirmed untouched

No files under `MultiOrg/`, `supabase/`, `Configs/`, or `project.yml` were modified. No git staging/commit/reset/clean was performed. The dirty worktree from Codex's branch is preserved. Builds were read‑only compilations into a scratch `derivedDataPath` outside the repo. The only files created are the four Markdown documents under `Docs/design/`.
