# Player Development Copilot architecture

## Product boundary

Phase 11C–11E provides two private products over the same objective development foundation:

- Coach Copilot for an active owner, admin, or authorized coach and a player in that staff actor's organization/team scope.
- Player Copilot for an active organization player, their own profile UUID only, and audience `player` only.

Parents, inactive memberships, unrelated users, and platform-only roles are denied. Neither product changes programs, testing, schedules, alerts, notes, official records, messages, recruiting status, or parent delivery. Conversations are not shared automatically.

## Request and generation flow

```text
Swift request (org + fixed player + audience + user input)
  -> player-development-copilot (JWT actor derived server-side)
  -> active organization and active membership
  -> coach team-policy scope OR exact player self-scope
  -> audience-specific conversation lookup
  -> bounded Phase 11A objective evidence source
  -> player allowlist filter when audience=player
  -> deterministic provider or explicitly configured structured provider
  -> audience-specific prompt and action schema
  -> evidence/rule/safety validation
  -> service-role-only atomic dialogue RPC
  -> audience-tagged messages, pending question, citations, attempt, feedback, and usage
```

The provider is never authoritative. Home Plate owns actor scope, values, units, dates, verification, freshness, deterministic trends, evidence IDs, and persistence.

## Audience identity and ownership

`audience` is constrained to `coach | player` on conversations, messages, citations, generation attempts, feedback, and usage. It participates in composite foreign keys, unique/idempotency identities, query filters, RPC validation, and RLS.

Coach conversations use staff player scope and remain visible only through coach-audience reads. Player conversations require `created_by = player_id = auth.uid()` and an active player membership in the exact organization. A database trigger rejects audience changes. Otherwise-identical coach and player requests remain different identities. No read path merges the histories.

## Evidence policies

Coach Copilot preserves the established Phase 11A evidence behavior and authorized staff scope.

Player Copilot applies `playerVisibleEvidencePack` before provider invocation. Its fail-closed source allowlist is:

- `sd_testing_entries`;
- `player_development_import` observations, including normalized Rapsodo/TrackMan/generic CSV values;
- `sd_player_metric_observations`;
- `sd_program_assignments`;
- objective aggregates from `sd_daily_logs_window`;
- objective `sd_bp_sessions` measurements.

Only safe metadata/snapshot keys survive. Private/staff/confidential/roster/ranking/comparison/parent/finance/recruiting/storage/GPS/device/secret labels or metadata are removed. Trends survive only when every evidence key remains visible. Explicit `audience=player` reports and alerts are supported citation sources; staff-audience equivalents remain excluded before provider invocation and persistence.

## Reports and alerts

Reports add immutable `audience = staff | player | parent`; historical rows default to `staff`, and `parent` is reserved with no parent read policy. Alerts add immutable `audience = staff | player`, also defaulting historical rows to `staff`. Audience participates in report idempotency, alert deduplication, exact evidence foreign keys, queries, lifecycle validation, and RLS.

Staff retains its existing staff-scope report/alert lifecycle. An active player may generate/list/open/archive only their own player summary and list/open/dismiss only their own player informational alerts. Staff is not automatically granted player-audience reads, and a player is never granted staff-audience reads. Report review history and alert event history remain staff-only.

## Dialogue state

Assistant message type is constrained to the eight supported turn types. Question turns persist in `sd_development_copilot_pending_questions`; immutable scope includes organization, player, conversation, audience, assistant message, question text/type/reason, choices, evidence IDs, and expiry. Only status/answer binding may change. One pending question exists per conversation/audience, and a new question supersedes the old one.

The Edge Function validates question type, text, choice/evidence bounds, prohibited privacy/medical/prompt-injection content, optional skip rules, expiry, and the exact pending ID. Reflection answers are not evidence. Confirmation records a conversational response but invokes no mutation tool.

## Prompts and providers

The backend owns all system instructions. Coach questions use `coach-copilot.v1`. Player questions use use case `player_copilot_self_question` and prompt version `player-copilot-self.v1`, with a separate age-appropriate privacy/safety prompt and player-only proposed-action enum.

`DeterministicCopilotProvider` answers supported evidence questions without network access. Unsupported questions return an honest provider-unavailable result when no configured provider can answer. OpenAI and Anthropic adapters exist behind environment configuration, structured-output schemas, bounded output, a 15-second timeout, and zero automatic network retries. Swift cannot select a model, provide a secret, or send a system prompt.

## Persistence and integrity

Conversation creation is unique by organization, actor, audience, and idempotency key. Dialogue persistence uses an advisory transaction lock whose identity includes audience. The user message, assistant result/failure, pending-question binding, immutable citation snapshots, generation attempt, and usage record are written atomically. Failed/rejected generations are never labeled successful.

Authenticated clients receive RLS-scoped reads only. They receive no direct table writes and no mutation-RPC execution. The initial exchange and Phase 11A mutation grants are retired in favor of the audience-aware dialogue/report/alert RPCs, callable only by `service_role`. Authenticated read helpers derive the current actor with `auth.uid()`.

## Swift boundaries

Player navigation supplies `appState.myProfile` as the fixed target; no player picker exists. Context tokens contain organization, user, player, and audience. Models clear on context changes, reject stale results, and validate returned organization/player/audience/creator plus message/citation scope before presentation.

## Deferred integration

Future explicit “Share with coach” and “Share answer with player” workflows may bridge private histories, but no sharing exists now. Dedicated audited tools may later execute confirmed actions; conversational confirmation alone never executes. Games, film, CommandIQ, goals, recruiting, parent reports, and any future source must be added through explicit schema visibility and allowlist changes.
