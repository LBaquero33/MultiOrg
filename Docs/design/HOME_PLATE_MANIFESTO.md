# HOME PLATE — MANIFESTO

**Status:** Design foundation (Phase 10). Living document.
**Companion docs:** `HOME_PLATE_OS.md`, `HOME_PLATE_DESIGN_SYSTEM.md`, `HOME_PLATE_UI_AUDIT.md`.

---

## Mission

Baseball has world‑class technology for measuring players and fragmented software for running the organizations around them. Coaches jump between five apps, parents between three, players between two, and administrators live in spreadsheets. **Home Plate exists to unify the baseball experience — from the first lesson to the college commitment — in one operating system.**

## Product identity

**Home Plate is the operating system for baseball organizations.** It is one connected platform for business operations, player development, competition, film, pitching intelligence, communication, and recruiting.

It is designed as **premium professional software that happens to be built specifically for baseball** — in the register of Stripe, Linear, Notion, Arc, and Apple, with its own ownable identity. Its baseball soul comes from the *data, terminology, workflows, and game state* — not from decorative clip art.

## The user promise

> Whoever you are in the game — player, parent, coach, owner, or advisor — Home Plate gives you one calm, trustworthy place to do your part of it, and one thread that connects your part to everyone else's.

- **A player** opens it daily to train, log, and see themselves getting better — with context, not just numbers.
- **A parent** trusts it with a child: schedules, payments, and honest development updates in one place.
- **A coach** trusts it with development: rosters, programs, testing, and (soon) AI that shows its evidence.
- **An owner** trusts it with money: revenue, expenses, and outstanding balances that feel precise and stable.
- **A recruiting advisor** trusts its metrics and film enough to act on them.

## Product principles

1. **One system, many workspaces.** Player, parent, coach, admin, and platform‑admin are different *workspaces within one operating system*, not different apps.
2. **Baseball‑first, not baseball‑themed.** Structure and language come from the game; styling stays premium and restrained.
3. **Context over raw numbers.** A metric without its trend, comparison, or personal best is only half the story.
4. **Calm density.** Professionals need a lot of data on screen; it must never feel chaotic.
5. **Every state is designed.** Loading, empty, error, permission‑denied, offline, stale, and success are all first‑class.
6. **Trust is a visual property.** Finance feels precise. AI shows its evidence. Recruiting feels credible. Nothing important feels playful by accident.
7. **Native behavior, shared identity.** Respect Apple‑platform conventions on each of iPhone, iPad, and macOS while keeping one recognizable Home Plate identity.
8. **Progressive disclosure.** Summaries first; detail on demand. One clear primary action per screen.

## What Home Plate is

- The connective tissue of a baseball organization: **operations + development + competition + film + intelligence + communication + recruiting.**
- A **multi‑tenant** platform where each organization is fully isolated, and one person can be an owner at one org, a coach at another, and a parent at a third.
- A **long‑term player‑journey** system: signs up → trains → completes programs → tests → gets feedback → attends sessions → plays games → builds statistics → captures film → receives CommandIQ and AI insight → builds a recruiting profile → connects with SportsForce → commits.
- **Premium, precise, calm, confident, fast, data‑driven.**

## What Home Plate is not

- Not a youth‑baseball app, and not cartoonish.
- Not a lightweight scheduling tool or a generic CRM with baseball icons.
- Not a GameChanger clone or a simple development dashboard.
- Not decorated with excessive baseball imagery, random gradients, giant icons, or motion for its own sake.
- Not a desktop dashboard squeezed onto a phone — nor a phone screen stretched onto a Mac.

## Long‑term vision

Home Plate intends to own the *entire* baseball‑development journey that no single existing platform owns today — from a player's first lesson to a college commitment — and to become the network layer connecting organizations, players, coaches, and recruiters. Game Day, synchronized film and auto‑clipping, CommandIQ pitching intelligence, Player‑Development AI, and SportsForce recruiting all plug into **one operating system, one design language.**

## Design implications (how this manifesto binds the UI)

| Principle | Concrete design rule |
| --- | --- |
| Premium, not themed | Green‑charcoal canvas, field‑green primary, gold accent, cream type. No clip art. Baseball texture used sparingly (subtle diamond/grid). |
| One system, many workspaces | A shared navigation shell, component library, and token layer across all roles and platforms. |
| Context over numbers | Metric components ship with trend/delta/comparison slots by default (see `HPMetricCard`). |
| Trust is visual | Finance = stable, precise, no decoration. AI = distinct controlled accent + explicit evidence/confidence separation. Recruiting = portfolio‑grade. |
| Every state designed | `HPLoadingState`, `HPEmptyState`, `HPErrorState` are mandatory building blocks, not afterthoughts. |
| Native + shared | Platform‑aware layouts (iPhone tabs, iPad split, macOS sidebar) drawn from one design system. |

> **The goal is not to make Home Plate prettier. The goal is to build the operating system baseball deserved.**
