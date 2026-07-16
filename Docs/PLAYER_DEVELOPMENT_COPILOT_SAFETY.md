# Player Development Copilot safety

## Audience isolation

- Coach output is generated only from an authorized coach-audience conversation and staff evidence scope.
- Player output is generated only for an active player whose actor UUID, target player UUID, and conversation creator UUID are identical in the selected organization.
- Player and coach conversations, messages, citations, feedback, attempts, and usage are never merged or automatically shared.
- Parents gain no Copilot access through a linked-player relationship. Parent drafts remain staff-only and undelivered.

## Grounding

Every factual, calculated, interpretive, recommendation, and proposed-action claim must cite evidence from the exact authorized pack. Calculations must also cite a known deterministic rule whose evidence set matches. The validator rejects unknown IDs, cross-player IDs, fabricated measurements, invalid rules, unsupported fields, and claims that do not retain citations.

Missing logs are unknown. Program assignment is not completion. A booking is not attendance. A trend is not causation. The system must state stale, limited, conflicting, or missing evidence honestly.

Approved negated limitations are not unsafe claims. `No authoritative attendance table is available` and `Assignment does not prove attendance or completion` must validate. Positive unsupported statements that a player attended or completed work remain blocked.

## Player pre-provider evidence boundary

Player Copilot uses a fail-closed source and metadata allowlist before any provider call. Objective self evidence can include testing, normalized/imported observations, values, units, dates, provider/verification, deterministic trends, freshness, samples, assigned-program context, objective player-log aggregates, and supported BP session metrics.

The provider must not receive:

- coach/staff/private notes, comments, or confidential evaluations;
- staff-only alerts, roster attention, rankings, comparisons, or other-player identity/context;
- parent drafts, review history, or coach feedback;
- finance, billing, payments, or internal operations;
- private recruiting evaluations;
- storage paths, signed URLs, raw files, GPS, device serials, secrets, or tokens.

If a future source is not explicitly allowlisted, it is excluded. Filtering output after generation is not accepted as a privacy boundary.

## Prompt injection and output safety

Evidence strings are untrusted data and are never system instructions. The backend selects fixed coach/player system rules. Imported content such as “ignore previous instructions” remains inside bounded evidence and cannot expand scope.

Player answers must be clear, age-appropriate, encouraging without exaggeration, and explicit about fact versus interpretation and verification. Questions or output involving medical/injury/mental-health diagnosis, guaranteed development/recruiting outcomes, unsupported causality, hidden reasoning, or unsupported professional comparisons are refused or rejected.

## Human control

Player-safe proposed actions are limited to review with a coach, request retesting, upload data, complete/review assigned work, log training, discuss data quality, prepare coach questions, or prepare a future personal-goal update. Every action has `requires_approval = true` and requires a person to act.

Assistant-initiated questions are bounded and typed. A question may clarify an ambiguous request, ask why missing evidence matters, invite an age-appropriate reflection, or confirm a preview. It may not solicit diagnosis/medical history, another player's information, private coach content, secrets, or prompt/system instructions. Reflection answers remain private conversational context and are never promoted to verified evidence.

Every proposed mutation follows preview → confirmation → future dedicated reauthorization/tool. This phase stops after confirmation and executes no official-record mutation. Player summary archive and player alert dismissal remain explicit UI/Edge lifecycle actions outside conversation.

Copilot never modifies a program, test, schedule, official record, alert, note, message, parent communication, or recruiting status. Approval of a parent draft still sends nothing. No notification or APNs integration is invoked.

## Feedback privacy and operations

Player feedback is limited to the authenticated player's own assistant message in their player-audience conversation. Coach feedback remains coach-audience data. Neither side automatically sees the other's feedback.

Operational records contain bounded sizes, provider/model identifiers, latency, status, retry, safe errors, fingerprints, and safe metadata. They do not contain credentials, hidden reasoning, arbitrary system prompts, or raw provider payloads. Logs must use safe identifiers/stage codes only.

Phase 11M diagnostic events contain request ID, action, audience, deterministic intent, generator version, stable validation code, bounded evidence/trend counts, and latency only. The stable failure taxonomy is `unsupported_without_provider`, `deterministic_intent_unrecognized`, `evidence_unavailable`, `structured_output_invalid`, `invalid_evidence_reference`, `unsafe_generated_content`, `persistence_failed`, `rate_limited`, and `stale_context`. Swift may show the code in a development-only technical disclosure; raw database/provider errors are never shown.
