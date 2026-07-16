# Player Development Copilot deterministic stabilization

Phase 11M stabilizes the already-deployed Coach and Player Copilot data path. It adds no database object, provider, secret, notification, or mutation capability.

## Confirmed pre-fix failures

`How is Andrew doing overall?` did not match the former substring predicates. `DeterministicCopilotProvider.generate` therefore returned `null`, and the handler converted that into `provider_unavailable` even though deterministic mode was selected.

`What evidence is missing?` did match, but every real evidence pack includes `No authoritative attendance table is available.` The safety validator scanned the entire serialized answer with a blanket `attendance` prohibition, so an honest negated evidence limitation was persisted as rejected with `unsafe_output`.

Phase 11M replaces those public results with successful deterministic answers. The stable replacement safety code for a genuine generated-content rejection is `unsafe_generated_content`.

## Deterministic intent catalog

| Intent | Representative aliases | Bounded behavior |
|---|---|---|
| `period_change_summary` | what changed, last month, last 30/90 days, trend summary | Cited deterministic comparisons only; 30/90-day phrases narrow the evidence start date. |
| `overall_development_summary` | how is NAME doing overall, how am I doing, summarize recent development | Up to three cited trends, recent facts when available, no overall score or causation. |
| `missing_evidence` | evidence missing, data missing, evidence gap | Explicit limitations; missing evidence is never poor performance; zero citations allowed. |
| `stale_evidence` | stale, out of date, needs retesting | Cites records actually marked stale; empty result succeeds. |
| `improved_metrics` | which metrics improved, what improved | Only `improvement` deterministic classifications. |
| `attention_metrics` | needs attention, regression | Regression, stale, conflicting, or limited trends only. |
| `metric_explanation` | Height, Max EV, latest EV trend, exit velocity, Sprint Time, Squat 1RM, supported display/canonical names | Latest value/source/date/verification/sample/freshness, cited trend, and preferred direction. Ambiguous generic metric requests create a clarification question. |
| `latest_import_summary` | latest Rapsodo session/import | Committed mapped Rapsodo observations only, with original/normalized units when available. |
| `next_session_review` | review before next session | Cited review preparation; no schedule/program mutation. |
| `coach_discussion_prep` | discuss/ask my coach | Cited questions/preparation; no messaging action. |
| `active_objective_alerts` | active alerts, alerts deserve attention | Coach uses staff-audience alerts; player uses player-audience alerts. Empty result succeeds without citations. |
| `assigned_programs` | assigned programs, program assignments | Assignment facts only; explicitly not attendance or completion. |
| `data_quality_summary` | data quality, unit conflict, sample size | Missing, stale, conflict, and low-sample limitations only. |

Matching is case-insensitive, punctuation/hyphen tolerant, and bounded to explicit expressions plus canonical metric/display names present in the authorized pack. Unknown conversational requests are not forced into a nearby intent.

## Routing contract

The handler classifies after authorization and again after the audience-filtered evidence pack is built. A supported answer or typed dialogue turn is constructed locally and persisted as:

- generation mode `deterministic`;
- provider `deterministic_template`;
- model identifier `null`;
- generator version `player-development-copilot.v1`.

The configured provider object is never invoked for a supported deterministic intent. An unknown request with deterministic-only configuration returns `deterministic_intent_unrecognized`. An unknown request with a selected but incomplete remote-provider configuration returns `unsupported_without_provider`. A configured remote provider may handle only an unsupported conversational request.

## Canonical output and citations

`canonicalStructuredAnswer` owns all required `player_development_copilot_answer.v1` fields. `constructDeterministicAnswer` is the only supported deterministic answer constructor. Every result still passes `validateStructuredAnswer` before persistence.

Every player-specific fact, calculation, interpretation, recommendation, and proposed action has one or more evidence IDs from the exact authorized pack. Citation snapshots are created only after ID lookup. Missing-evidence and empty-alert answers contain no factual claim arrays and legitimately produce zero citations. Raw file paths, GPS, device serials, tokens, and ambiguous/unmapped import fields are never included.

## Validator stages and stable codes

| Stage | Stable public code | Retryable in app |
|---|---|---|
| Unsupported without configured remote provider | `unsupported_without_provider` | No |
| No deterministic match | `deterministic_intent_unrecognized` | No |
| Evidence absent where an operation requires it | `evidence_unavailable` | No |
| Structured schema/claim contract | `structured_output_invalid` | Yes |
| Evidence authorization/reference | `invalid_evidence_reference` | Yes |
| Generated-content safety | `unsafe_generated_content` | Yes |
| Atomic persistence | `persistence_failed` | Yes |
| Usage limit | `rate_limited` | Yes |
| Expired pending context | `stale_context` | No |

Legacy codes remain readable in Swift for already-persisted messages. Raw database/provider errors are never returned.

Safety validation still rejects positive unsupported attendance/completion assertions. It now distinguishes those assertions from approved limitation text such as `No authoritative attendance table is available` and `Assignment does not prove attendance or completion`.

## Dialogue and retry lifecycle

Answer, clarification, evidence-gap, reflection, confirmation, suggested-follow-up, action-preview, and safe-refusal turn types retain separate validation. Question turns require an allowed question type, bounded text, at most six choices, authorized related evidence, correct response-mode/choice shape, no prohibited solicitation, and no mutation. Ambiguous metric questions persist as clarification questions.

Retry reuses the original question and idempotency key. The deployed RPC locks that logical operation, never inserts a second user/assistant pair, updates a failed assistant message only when the corrected attempt succeeds, and appends generation-attempt and usage-ledger rows for every attempt. Swift decodes the persisted idempotency key so a retryable failed message remains retryable after reloading the conversation.

## Safe diagnostics

The Edge handler emits these bounded events:

- `copilot_request_received`
- `copilot_intent_classified`
- `copilot_intent_unrecognized`
- `copilot_evidence_built`
- `copilot_deterministic_generated`
- `copilot_structured_validation_failed`
- `copilot_evidence_validation_failed`
- `copilot_safety_validation_failed`
- `copilot_persist_started`
- `copilot_persist_succeeded`
- `copilot_persist_failed`

Only request ID, action, audience, intent, generator version, stable validation code, bounded counts, and latency are logged. Question/answer text, evidence contents, names, provider tokens, secrets, and credentials are prohibited.

## Deployment boundary

No migration is required. When separately approved, deploy only the `player-development-copilot` Edge Function bundle and the app containing the Swift presentation changes. Do not change provider configuration during deterministic validation.
