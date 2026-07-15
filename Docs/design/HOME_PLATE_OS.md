# HOME PLATE OS — Workspace & Navigation Architecture

**Status:** Proposed architecture (Phase 10). Requires user approval before implementation.
**Companion docs:** `HOME_PLATE_MANIFESTO.md`, `HOME_PLATE_DESIGN_SYSTEM.md`, `HOME_PLATE_UI_AUDIT.md`.
**Grounded in current code:** `RootView`, `CoachRootView`, `ParentRootView`, `PlayerHomeView`, `HomeView`, `DHDOrgMenuHeader`, `activeOrgSettings.feature()/term()`.

---

## 1. Workspace philosophy

Home Plate is organized into **workspaces**, not loose screens. A workspace is a coherent area of the operating system with a purpose, a set of primary questions it answers, a small number of core cards, and a few key actions. The same workspace exists across roles and platforms — what changes is *which* workspaces a user can see (role + entitlement) and *how* they are presented (phone/tablet/desktop).

**Canonical workspaces** (superset; visibility is gated):

| Workspace | One‑line purpose | Primary roles |
| --- | --- | --- |
| Overview | Orient, surface urgent items, fast actions | All |
| Development | Develop players (programs, testing, trends, logs) | Player, Coach, Parent (view) |
| Analytics | Understand performance & the business | Coach, Owner/Admin |
| AI *(future)* | Evidence‑backed development intelligence | Coach, Player |
| Game Day *(future)* | Live scoring, box score, film, CommandIQ | Coach, Player, Parent (view) |
| Recruiting *(future)* | College‑ready profile, verified metrics, film | Player, Parent, Coach |
| Communication | DMs, announcements, notification center | All |
| Scheduling | Lessons, bookings, team events, calendar | All |
| Finance | Revenue, expenses, balances, payments | Owner/Admin (+ platform support) |
| Facilities | Locations, cages, fields, availability | Coach, Owner/Admin |
| Organization | Org management, staff, branding, memberships | Owner/Admin, Platform admin |
| Settings | Account, preferences, subscription | All |

> Today these concepts exist but are **flattened into per‑role tab bars** (iOS) and a **coach‑only sidebar** (macOS). The OS model reorganizes the *same destinations* into workspaces without changing what each destination does.

## 2. Navigation architecture (per platform)

One mental model, three presentations. All three are driven by the same role‑ and entitlement‑aware workspace list.

### macOS & iPad regular width — **Sidebar**

A persistent `HPSidebar` (evolved from today's `CoachRootView` `NavigationSplitView` + `DHDOrgMenuHeader`):

```
HOME PLATE            ← org identity header (brandmark + org name + role subtitle)

  Overview            ← primary

  ── Develop ──
  Development
  Game Day  (preview)
  Analytics
  AI        (preview)
  Recruiting (preview)

  ── Run ──
  Communication
  Scheduling
  Finance
  Facilities

  ── Manage ──
  Organization
  Settings
```

- Selecting a workspace fills the detail column; workspaces own their internal `NavigationStack`.
- Section dividers group by intent (Develop / Run / Manage). Order matches handoff §13.
- iPad in compact width falls back to the iPhone model.

### iPhone — **Focused tab bar + workspace directory**

- A **role‑specific tab bar of ≤5 high‑frequency destinations** (never the whole sidebar).
- A **"More" / workspace directory** for the long tail, presented as a branded `HPWorkspaceDirectory` (not the stock iOS "More" list, which today is where Player's 6th–8th tabs land).
- Drill‑in via `NavigationStack` within each workspace.
- An **org/workspace switcher** in the header for users who belong to multiple orgs or need to jump workspaces.

**Proposed default tab sets** (≤5, entitlement‑gated, using existing `feature()` flags):

| Role | Tabs | Directory (More) |
| --- | --- | --- |
| Player | Today · Calendar · Trends · Chat · More | Testing, Analysis, Facilities, Account |
| Coach | Players · Schedule · Chat · Analytics · More | Teams, Programs, Facilities, Org Admin, Platform, Account |
| Parent | Children · Schedule · Chat · More | Payments, Account |
| Owner/Admin | Overview · Finance · Communication · Organization · More | Facilities, Scheduling, Account |

> This directly fixes the audit finding that Player and Coach declare **up to 8 flat tabs** that overflow into the unbranded system "More."

## 3. Information hierarchy

Every workspace follows the same vertical rhythm:

1. **Workspace header** (`HPWorkspaceHeader`) — title, context (org/date/filter), one primary action, optional secondary/overflow.
2. **Attention row** *(optional)* — the 0–3 things that need the user now (overdue payment, unlogged day, roster attention).
3. **Core cards** — the workspace's answers to its primary questions (metrics → trends → lists).
4. **Detail on demand** — progressive disclosure into `NavigationStack` destinations.

One clearly dominant primary action per screen (Manifesto principle 8 / handoff §12.1).

## 4. Global interaction model

| Concern | Rule |
| --- | --- |
| Primary action | One per screen; rendered as `HPButton(.primary)` (gold). |
| Destructive action | Always confirmed via `HPConfirmationDialog`; never a bare tap. |
| Transient feedback | `HPToast` (one implementation — replaces the duplicate inline toast). |
| Selection/detail | Sidebar detail (desktop) / push (`NavigationStack`) / sheet (`HPModal`) — chosen by platform, not per‑screen whim. |
| Search & filter | `HPSearchBar` + `HPFilterBar` with consistent placement (top of list workspaces). |
| Empty/loading/error | Mandatory `HPEmptyState` / `HPLoadingState` / `HPErrorState`. |
| Keyboard (macOS/iPad) | Sidebar navigable; primary action = ⌘‑return where sensible; escape dismisses modals (already true for `dhdFloatingModal`). |

## 5. Responsive strategy

| Class | Layout |
| --- | --- |
| iPhone (compact) | Single column, tab bar, drill‑in. Cards full‑width. |
| iPad (regular) | Sidebar + detail; 2‑column card grids; larger `HPWorkspaceHeader`. **Not** a scaled‑up phone (fixes audit finding: today iPad = stretched iPhone, portrait‑locked full‑screen). |
| macOS | Sidebar + detail; toolbar (`HPToolbar`); denser grids; hover/focus states; click‑out modals. **Not** an enlarged iPhone. |

Breakpoint driver: SwiftUI size classes + `NavigationSplitView` on regular width, `TabView` on compact.

## 6. Cross‑role consistency

- Same components, tokens, spacing, and motion for every role — a coach's Finance card and an owner's Finance card are the same component.
- Role differences are expressed as **which workspaces/cards/actions appear**, gated by `appState` authorization (`canAdminActiveOrg`, `isPlatformAdmin`, `needsAccess`) and `activeOrgSettings.feature()` — reusing today's gating, not inventing new authorization.
- **Platform‑admin support mode stays visually explicit** (today: the Finance dashboard shows a "Platform Support — viewing finance for {org}… This does not make you an organization owner or member" banner). The OS keeps a persistent support‑mode chrome so support access never masquerades as ownership.

## 7. Platform differences (summary)

| | iPhone | iPad | macOS |
| --- | --- | --- | --- |
| Primary nav | Tab bar + directory | Sidebar + detail | Sidebar + detail |
| Density | Comfortable | Increased | Dense |
| Modals | Sheets | Sheets / popovers | Click‑out floating modals |
| Player workspaces | Full | Full | **Gap today** — macOS excludes `Features/Player/**`; parity is future scope, not the pilot |
| Motion | Calm, reduced‑motion aware | Same | Same |

## 8. Naming rules

- **Product name is "Home Plate"** everywhere user‑facing. The current on‑screen fallback **"MultiOrg"** (from `DHDOrgBranding.fallback`) is a bug‑level identity issue to correct — internal target names (`MultiOrg`, `MultiOrgMac`, bundle ids) can remain.
- Component names are prefixed **`HP`** (`HPButton`, `HPCard`, …) — see `HOME_PLATE_COMPONENT_LIBRARY.md` (to be authored in Stage 2/3).
- Workspaces use the canonical names in §1; organization‑configurable terminology (`term()` — e.g. "Players" vs "Athletes", "Facilities") continues to override *labels* without changing workspace identity.
- Feature/entitlement keys reuse the future set in handoff §16 (`finance_dashboard`, `game_day`, `command_iq`, …); the UI must render **polished locked/upgrade states** without hardcoding plan checks (handoff §15–16).

## 9. Open questions for the user (do not block Stage 2)

1. Org white‑label scope: should an org's brand color drive only identity chrome (header/avatar) while HP gold/green owns system semantics (CTA/focus/finance)? *(Recommended — see audit §7.2.)*
2. iPhone default tab sets in §2 — approve as proposed or adjust per role?
3. Is macOS player parity in Phase 10 scope, or explicitly deferred?
