# Player Development AI safety

## Non-negotiable rules

- Output is advisory and requires human review.
- Never diagnose medical, injury, or mental-health conditions.
- Never guarantee performance, improvement, recruiting, roster, scholarship, or professional outcomes.
- Never fabricate measurements, trends, attendance, completion, quotations, or causal explanations.
- Never compare minors publicly or calculate a simplistic overall player score.
- Never automatically modify programs, tests, schedules, bookings, access, membership, billing, payments, official statistics, or recruiting status.
- Never store chain-of-thought or private model reasoning.

## Observed versus interpreted

Evidence snapshots are observed facts. Trend fields are deterministic calculations. `interpretation` is a configured directional label with sample/freshness/unit quality. Report prose explains the calculation and asks a coach to confirm context. Recommendations are human review prompts, not autonomous decisions.

## Minor and audience safety

Phase 11A reports and alerts are staff-only. Parent/player access is denied in the Edge Function and new-table RLS, and no UI entry exists in parent/player roots. `parent_update_draft` remains an internal draft type and is never published.

A future parent workflow must exclude private coach notes, internal comparisons/flags, other players, unsupported diagnoses, recruiting evaluations, financial data, and unapproved content. Staff approval and a separate safe publication object are required.

## Data minimization

Source adapters omit free-text testing/program/daily-log notes. Evidence metadata contains identifiers and measurement context, not entire source records. Errors returned to clients are sanitized. Debug output must not include JWTs, secrets, private notes, or player measurements.

## Alert safety

Only rules supported by actual data run. Phase 11A implements no-recent/stale testing, meaningful configured-direction change, unit conflict, insufficient sample, and report-awaiting-review. Attendance, missed-session, workload, program-completion, and coach-interaction rules are deferred because authoritative ledgers are absent.

No Phase 11A alert sends APNs, notification-center items, chat messages, or parent/player content.
