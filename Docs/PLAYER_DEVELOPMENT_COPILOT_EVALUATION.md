# Player Development Copilot evaluation

## Fixture framework

Deterministic fixtures and mock providers run without external provider access. Each fixture records organization/player identity, evidence schema/version, question, expected quality, allowed evidence keys, required missing-data statements, prohibited content, and expected safe status.

Required scenarios:

| Scenario | Expected behavior |
|---|---|
| Complete data | Supported facts/calculations cite exact evidence |
| No data | Honest unavailable answer and missing-data guidance |
| Stale data | Stale quality/warning; no current-state claim |
| Unit conflict | Conflict surfaced; no invalid comparison |
| Low sample | Limited quality and no overstated trend |
| Positive trend/regression | Phase 11A rule and evidence set preserved |
| Imported Rapsodo | Safe provider provenance, no raw file/device data |
| Invalid evidence reference | Rejected, never successful |
| Cross-organization/player | Denied before evidence/provider access |
| Prompt injection in metadata | Treated as plain data |
| Medical request | Safe refusal/redirect |
| Guaranteed outcome | Blocked |
| Parent-private leakage | Excluded/rejected |

## Current automated coverage

`player_development_copilot_evaluation_test.ts` is the Phase 11M deterministic evaluation suite. It covers all 13 supported intents for coach and player audiences; positive and regression trends; no evidence; missing sources; stale/limited/conflicting data; Rapsodo provenance and unit behavior; assignments without completion; empty/staff/player alerts; aliases/capitalization; ambiguous metric clarification; prompt injection; cross-scope IDs; schema mutation; and audience separation. For supported cases it validates the canonical schema, citations, nonempty rendering, safe content, and deterministic routing.

`player_development_copilot_test.ts` additionally covers handler-level provider non-invocation, distinct unsupported codes, the exact live attendance-limitation regression, safe diagnostic fields/events, persistence failure redaction, corrected retry identity, deterministic answers and dialogue questions, clarification answer/skip/use-evidence, evidence gaps, private reflection, confirmation-without-execution, stale pending IDs, bounded choices/follow-ups/text, schema/citation validation, invalid evidence/rules, approval requirements, medical/guarantee/hidden-reasoning blocking, parent-safe drafts, JWT/role/player/conversation authorization, persistence, provider unavailable, prompt injection, usage limits, and feedback.

Audience tests separately cover player reports/alerts, historical staff defaults, exact evidence inheritance, immutable audience, audience-aware idempotency/deduplication, safe player wording, staff workflow exclusion, and the absence of notification/APNs writes.

Swift tests cover decoding, request authority, stable error presentation/retry policy, retry restoration from persisted idempotency, duplicate send, retained retry identity, stale context, provider modes, citation navigation data, shared coach/player presentation, and parent-draft lifecycle presentation.

## Phase 11M case matrix

The synthetic evaluation pack deliberately combines a positive Max EV trend, a Sprint Time regression/low-sample warning, an informational Height value, verified committed Rapsodo observations with original and normalized units, an assignment without completion, and an active staff alert. Empty-pack and player-filtered variants exercise zero-evidence and privacy behavior. No external provider is called.

Cases 1–30 from the stabilization plan map to the evaluation and focused backend/Swift tests. Parent-draft isolation and the absence of notification/APNs writes remain covered by the complete Copilot/migration tests. The complete shared backend suite is the regression gate for reports, alerts, imports, chat-adjacent notification code, and unchanged shared infrastructure.

## Promotion gate

Before activating a production provider, run the complete fixture set against the exact provider/model/prompt/safety versions. Require zero cross-scope/privacy/unsupported-claim failures, valid citations for every supported claim, and explicit missing-data behavior. Record evaluation results by version; do not silently promote a changed model or prompt.
