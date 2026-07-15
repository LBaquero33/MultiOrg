# HOME PLATE — MOTION SYSTEM

**Status:** Stage 2 spec — approved direction, pre‑implementation.
**Absolute path:** `/Users/lb33/Documents/DHD-Self-Development-iOS-multiorg/Docs/design/HOME_PLATE_MOTION_SYSTEM.md`
**Companions:** `HOME_PLATE_DESIGN_SYSTEM.md`, `HOME_PLATE_COMPONENT_LIBRARY.md`.

## Philosophy

Motion in Home Plate is **calm and purposeful** — it clarifies state changes and spatial relationships; it never performs. Premium software feels *fast and quiet*. No bounce for its own sake, no decorative parallax, no attention‑seeking loops. When in doubt, less. Game Day is the one place motion may become more energetic (live, broadcast‑like) — still controlled.

## Duration & curve tokens

| Token | Duration | Curve | Use |
| --- | --- | --- | --- |
| `hp.motion.instant` | 0.10s | easeOut | Toggles, taps, hover |
| `hp.motion.quick` | 0.18s | easeOut | Toasts, badges, small fades |
| `hp.motion.standard` | 0.25s | easeInOut | View/workspace transitions, card appearance |
| `hp.motion.emphasis` | 0.35s | spring(response 0.35, damping 0.85) | Sheet/modal present, primary confirmations |
| `hp.motion.chart` | 0.4–0.6s | easeOut | Chart draw‑in (once, on appear) |

Springs are **critically‑ish damped** (damping ≥ 0.8) — a settle, not a bounce.

## Patterns

| Pattern | Motion |
| --- | --- |
| Workspace switch | `standard` cross‑fade; sidebar selection is instant, detail cross‑fades. |
| Card appearance (list build) | `standard` fade + 6–8pt upward offset; **stagger ≤ 3 items** then appear together (avoid long cascades). |
| List insert/delete | Native `.animation` on the collection; insert = fade+height; delete = fade+collapse. |
| Sidebar (macOS/iPad) | Column show/hide uses system split‑view animation; no custom override. |
| Sheet / `HPModal` | `emphasis` present; macOS `dhdFloatingModal` uses opacity + slight scale (0.98→1). |
| Loading → content | Skeleton cross‑fades (`quick`) to real content; no spinner→content pop. |
| Success confirmation | `HPToast` slides from top (`quick`, move+opacity) OR inline checkmark scale 0.9→1 once. **Non‑bouncy.** |
| Error | Content fade‑in; **at most one** subtle horizontal nudge (2–3pt, `instant`) for inline field errors — never a hard shake. |
| Badge / unread | Count change = `quick` scale 1→1.15→1; new‑unread dot fades in. |
| Progress (`HPProgressIndicator`) | Ring/bar animates value changes with `standard`; determinate preferred. |
| Button press | Scale 0.98 on press (`instant`); loading swaps label→spinner without size change. |
| Pull‑to‑refresh | Native refreshable. |

## Chart motion

- Draw‑in **once** on first appear (`hp.motion.chart`): bars grow from baseline, lines trace left→right, areas fade+rise.
- Data updates: animate to new values (`standard`), don't re‑draw from zero.
- No looping/idle animation. Respect Reduce Motion (see below).

## Reduced Motion (required)

When `accessibilityReduceMotion` is on:
- Replace all move/scale/slide with **opacity‑only** cross‑fades at `quick`.
- Charts render in final state (no draw‑in).
- Staggers become simultaneous.
- Toasts fade (no slide); button press = opacity only.
- Also honor **Reduce Transparency** (swap material/blur backgrounds for solid `hp.surface`).

Implementation: centralize via an `HPAnimation` helper that reads `@Environment(\.accessibilityReduceMotion)` and returns the reduced variant, so components don't each re‑implement the check.

## Anti‑patterns

- Bouncy springs on routine transitions; cascading long list animations; parallax/scroll‑jacking; animated gradients or looping glows (including on AI — its accent is static, evidence is the emphasis, not motion); motion conveying meaning without a non‑motion equivalent; blocking interaction during decorative animation.

## Platform notes

- **iPhone:** lean on native transitions; keep custom motion minimal for battery/perf.
- **iPad/macOS:** hover transitions (`instant`), focus‑ring fade (`quick`); no hover motion on touch.
- **macOS:** respect system "Reduce motion"; window/sheet use AppKit‑native timing where possible.
