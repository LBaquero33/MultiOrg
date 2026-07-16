# Player Development AI architecture

## Phase 11A boundary

Phase 11A is a deterministic, staff-reviewable intelligence layer. It does not call an external AI provider, diagnose health/injury, notify users, publish parent/player content, or mutate programs, testing, membership, scheduling, billing, payments, or official statistics.

```text
authenticated staff request
  -> player-development-ai Edge Function
  -> verified JWT + active staff membership + player scope
  -> source adapters (testing, normalized observations, daily logs, assignments, BP)
  -> versioned evidence pack
  -> deterministic trend/alert engine
  -> provider-neutral deterministic template
  -> verified-actor service-role-only transactional RPC
  -> report + evidence snapshots + review history
```

## Components

- `_shared/player_development_ai.ts`: request authorization flow, evidence-pack schema, source adapters, trend calculations, alert rules, generator interface, deterministic provider, and sanitized responses.
- `player-development-ai/index.ts`: verifies the Supabase JWT, evaluates organization/team scope, reads bounded organization-filtered source data, and transfers that verified actor only to service-role-only RPC mutations.
- `20260715060000_player_development_ai_foundation.sql`: normalized/queryable data model, indexes, RLS, metric seed registry, and lifecycle RPCs.
- `PlayerDevelopmentAIModels.swift`: explicit request/response contracts and state helpers.
- `SupabaseService.swift`: authenticated actions with sanitized non-2xx decoding.
- `PlayerDevelopmentAIView.swift`: workspace state, report detail/review, alert review, and roster attention.

## Provider neutrality

`DevelopmentGenerationProvider` exposes a provider name, mode, generator version, and `generate(evidencePack)` operation. `DeterministicTemplateProvider` is the only implementation. A future approved model provider must consume the same versioned pack, return the same structured content, preserve evidence keys, and never receive secrets from the client.

Provider/model/generator/prompt fields are stored separately. A model provider must never store hidden reasoning. Only concise conclusions, evidence references, quality, and safe generation metadata may be persisted.

## Authorization

Every action starts from the JWT user returned by `auth.getUser`. The actor must have an active owner/admin/coach membership in the requested active organization. The allowed player set is derived server-side:

- owner/admin: active player memberships in that organization;
- coach with unrestricted team policy: active player memberships in that organization;
- coach with restricted policy: intersection of active organization players and the coach's assigned team.

Player UUID knowledge is insufficient. Parent, player, inactive staff, unrelated users, platform-only support, and inactive-team scope are denied. Authenticated clients cannot execute the lifecycle RPCs directly; each RPC repeats the transferred actor's organization/player authorization. The Swift UI also hides Phase 11A without an active staff membership, but this is presentation only.

## Reproducibility and idempotency

Evidence requests include organization, player, report type, date window, and an ISO-8601 cutoff. Source queries exclude rows created after the cutoff. Existing source rows are not bitemporal, so the cutoff cannot reconstruct an earlier value after an in-place edit; persisted evidence snapshots provide audit stability from report creation forward. Report identity binds organization, authenticated requester, player, type, window, cutoff, generator version, and an explicit client UUID. A transaction advisory lock plus a unique `(org_id, requested_by, idempotency_key)` constraint converges concurrent retries; changed material fails closed.

The Swift model retains the key and cutoff after an ambiguous failure. It clears them only after definitive success or material window/player/organization changes.

Alerts use `(org_id, player_id, deduplication_key)` uniqueness. Detection updates `last_detected_at` and current evidence instead of generating uncontrolled duplicates, and appends a detection/redetection event.

## Future integration points

- import parsers write audited `sd_development_import_jobs` and normalized observations;
- game, pitching, film, CommandIQ, and recruiting adapters add source-specific records without vendor-specific canonical metric keys;
- approved model providers plug into the provider interface;
- approved parent summaries use a separate audience-safe pack and publication workflow;
- pagination can replace the Phase 11A capped report/alert lists without changing row contracts.
