# Player Development AI UI

## Entry points

- Coach player detail adds a **Development AI** segment next to Overview, Calendar, Testing, Program, and Analysis.
- Coach roster adds **Roster Attention** to the existing toolbar. It opens a staff-only organization workspace.
- No parent or player root receives an entry point.

## Player workspace

The modular workspace uses current `DHDHeaderCard`, `DHDCard`, section headers, badges, typography, backgrounds, buttons, lists, empty states, and progress indicators. It shows:

- player and reporting-window context;
- evidence coverage, quality, freshness, and missing/conflicting data;
- deterministic trends without an overall score;
- latest report and report history;
- generation with duplicate-tap prevention and stable retry idempotency;
- current alerts and explicit detection;
- readable errors and retry.

Changing organization, authenticated user, player, or reporting window resets state. Results are accepted only for the current organization/user request token.

## Report detail

Report detail shows status/window/cutoff, quality, generator mode/version, structured sections, evidence-key citations, evidence snapshots/source identifiers/rules, data gaps, coach questions, notes, and audit history. Staff can mark reviewed, approve, reject, or archive within the backend state machine.

## Alerts

Alert detail separates severity from evidence quality, explains the deterministic rule result, gives a recommended human review action, and supports acknowledge/dismiss/resolve/archive. These actions do not affect the player's source data.

## Roster attention

The organization list supports player search and severity filtering. Rows show player, alert type, severity, freshness, and evidence quality. Known roster players navigate to their Development AI workspace. It does not rank players.

The presentation is intentionally functional rather than a redesign so future design work can restyle components without replacing service/state logic.
