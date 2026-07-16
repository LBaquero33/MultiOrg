# Player Development Copilot data audit

Audit date: 2026-07-16. Repository source of truth: migrations through `20260715090000_player_development_import_validation_fix.sql`, the current Phase 11A/11B Edge Functions, Swift sources, `project.yml`, and `supabase/config.toml`. This audit precedes the Phase 11C–11E implementation. It does not assert that any unapplied migration is present in the hosted database.

## Decision

The Copilot can reuse the Phase 11A authorization and evidence contracts, but it needs an additive, staff-only persistence boundary for conversations, messages, citations, attempts, parent drafts, feedback, prompts, and usage. Ordinary chat, notifications, reports, and report-review events must not be overloaded for these records.

The required request order is:

```text
verified JWT
  -> active organization
  -> active owner/admin/coach membership
  -> existing team-policy player scope
  -> bounded evidence query
  -> deterministic calculations
  -> provider-neutral structured generation
  -> evidence and safety validation
  -> atomic service-role persistence
```

Knowing an organization, player, report, conversation, message, draft, or citation UUID is never authorization.

## Existing architecture to reuse

### Identity and organization authority

- `profiles` supplies display identity only. Its legacy/global role is not organization authorization.
- `sd_orgs.status` determines whether the requested organization is active.
- `sd_org_memberships` is the authoritative role/status relation. Copilot access is limited to active `owner`, `admin`, and `coach` memberships.
- `sd_org_settings.team_policy.restrictCoachActionsToTeam` plus the established team-member behavior limits a coach to authorized active players. Owners/admins retain organization-wide player scope.
- `sd_platform_admins` and platform-support access do not grant organization membership. A platform administrator without active organization membership is denied.
- `sd_parent_child_links` does not grant Copilot or parent-draft access in this phase.

The Phase 11A Edge store verifies the bearer token with `auth.getUser()` and derives a fresh actor for every request. It then checks organization status, membership, and the authorized-player set before service-role evidence reads. This request-local pattern is suitable for reuse and avoids mutable singleton caller state.

### Evidence and deterministic calculations

`_shared/player_development_ai.ts` defines `player_development_evidence_pack.v1` and already adapts bounded, organization/player-filtered data from:

- testing entries;
- normalized metric observations, including Phase 11B import provenance;
- daily logs (process-adherence facts only; missing logs are not absences);
- program assignments (assignment, never completion);
- BP sessions/events;
- reports awaiting review.

The pack already contains evidence keys, canonical metric identity, observed and normalized values, units, dates, quality, freshness, source identity, deterministic rule IDs, source metadata, and immutable evidence snapshots. Trend calculations are Home Plate-owned and versioned. These are the authoritative inputs for facts, calculations, suggested questions, and model validation.

Existing protections to preserve:

- source and evidence queries are bounded;
- the evidence cutoff excludes records created after the request cutoff;
- persisted snapshots preserve explainability after source mutation;
- private free-text notes are not copied into Phase 11A evidence;
- a booking is not attendance;
- an assignment is not program completion;
- missing data is unknown, not a negative outcome;
- vendor labels do not replace canonical metric identity.

### Reports, evidence, alerts, and imports

- `sd_development_reports` remains the official staff-reviewed report lifecycle. A conversational answer is not a report and must not mutate one.
- `sd_development_report_evidence` is report-owned. Copilot citations require message ownership and therefore need a separate table, but should use equivalent immutable snapshot fields.
- report and alert event tables establish the append-only audit-event convention.
- Phase 11B `sd_player_metric_observations` and import provenance are valid evidence sources. Copilot must expose safe provider/source labels while excluding storage paths, raw uploads, device identifiers, and unrestricted metadata.
- Phase 11A report/alert RPCs repeat transferred-actor authorization and use service-role-only grants. Copilot mutations should follow the same pattern.

### Swift application patterns

- `AppState.activeOrgAuthorizationKey` includes organization, user, membership role, and membership status. Copilot view models should bind requests to this plus player identity and clear state on changes.
- Phase 11A uses request tokens, task cancellation, stale-response rejection, retained idempotency after ambiguous failures, and duplicate-mutation guards.
- `PlayerDevelopmentAIWorkspaceView` is already visible only to active staff and is the correct player-scoped entry point.
- Recursive source discovery in `project.yml` includes modular Swift additions for iOS and macOS. `project.yml` remains the project source of truth; XcodeGen regeneration is required after new Swift files.

## Existing systems deliberately not reused

### Ordinary chat

`sd_chat_channels`, memberships, and messages support human communication, realtime delivery, and participant RLS. Copilot conversations are staff-only, player-scoped audit records with structured answers, evidence cutoffs, prompt/generator metadata, citations, and generation state. Reusing chat would risk parent/player exposure and would not preserve the required provenance. No Copilot content is written to chat.

### Notifications and APNs

The notification center and push-delivery pipeline are delivery systems. Phase 11C–11E creates no notification, delivery, device registration, queue wake-up, or APNs action. Parent drafts remain ineligible for delivery until a future separately authorized phase.

### Current access entitlements

`sd_access_entitlements` is a user subscription/access record and has no feature-key dimension. It cannot safely represent `player_ai`, `coach_copilot`, `parent_ai_updates`, `roster_attention`, or `advanced_reports` without a redesign. For this additive phase, the backend uses documented founding/development access: an absent feature-entitlement record does not block an otherwise authorized staff member. A future feature-entitlement table can be enforced behind the backend without changing clients.

### Secrets and client prompts

There is no client-owned provider key or prompt architecture to reuse. Swift must never send a system prompt, provider credential, model identifier, or arbitrary prompt template. The backend selects prompt records and provider configuration from environment values. This implementation does not create or set any secrets and does not hardcode a production model.

## Security findings and required controls

1. Every action must independently authenticate and authorize; list/detail/retry/archive/feedback/draft UUIDs cannot bypass player scope.
2. Service-role source queries must begin only after actor, organization, role, and player authorization.
3. All new tables require RLS, staff-only read policies, no authenticated direct writes, composite organization/player foreign keys, and explicit service-role grants.
4. Mutation functions must use `SECURITY DEFINER`, `SET search_path = ''`, schema-qualified objects, transferred actor validation, restricted execute grants, and transaction-level idempotency.
5. Generation attempts, feedback, citations, and draft review events are audit data and must not be hard deleted or retroactively rewritten.
6. Imported text, metadata, names, program/session labels, and any future notes are untrusted data. They must be structurally separated from system rules and never interpreted as instructions.
7. Provider output must be schema validated, bounded, checked against the exact authorized evidence-key set, and rejected for cross-player/cross-org content, fabricated values, diagnosis, guaranteed outcomes, unsupported comparisons/causality, hidden reasoning, or invalid lifecycle actions.
8. Persisted responses must never contain chain-of-thought. Only concise user-visible conclusions, classifications, citations, and operational metadata are stored.
9. Parent-draft evidence must use an audience-safe projection that excludes coach notes, internal labels/comments, other players, raw device/GPS/file data, financial data, and private storage references.
10. Usage limits are backend-authoritative and must count by organization/actor/action before provider invocation.

## Recommended additive schema

### `sd_development_copilot_prompt_versions`

Queryable backend-owned prompt registry: prompt key, use case, audience, semantic version, evidence/output/safety schema versions, active/deprecated timestamps, and safe template metadata. Prompt bodies are backend-owned; Swift sends no system prompt. Only one active row per prompt key/use case/audience is allowed.

### `sd_development_copilot_conversations`

Organization/player/creator scope, title, status, default reporting window, evidence cutoff, generation metadata, idempotency key, archive timestamp, and timestamps. Composite organization/player integrity and `(org_id, created_by, idempotency_key)` uniqueness provide deterministic creation.

### `sd_development_copilot_messages`

Conversation-scoped user/assistant rows with actor/role, bounded question or structured/rendered answer, quality, evidence cutoff, generation mode/provider/model, prompt/generator versions, status, safe error code, idempotency key, archive timestamp, and timestamps. No hidden reasoning column exists. User and assistant messages are persisted as one atomic ask operation.

### `sd_development_copilot_message_citations`

Immutable assistant-message citations: evidence key, optional Phase 11A report-evidence link, source type/record, metric identity, observed and normalized values, unit/date, display/explanation, claim/section identity, provider/verification/rule metadata, and full historical snapshot. Unique message/evidence/claim relationships prevent accidental duplicates.

### `sd_development_generation_attempts`

Append-only attempt metadata: action, provider/model/mode, prompt/generator versions, retry number, status, safe error, input/output sizes and token counts, latency, request fingerprint, and timestamps. No raw prompt, credential, or hidden reasoning is stored.

### `sd_development_parent_update_drafts`

Staff-only generated original, editable current content, rendered versions, status (`generated`, `reviewed`, `approved`, `rejected`, `archived`), evidence cutoff, generator metadata, review/approval/rejection/archive identities and timestamps, idempotency, and explicit `delivered_at` absence. Approval only marks future eligibility; no delivery function exists.

### `sd_development_parent_draft_review_events`

Append-only generated/edited/reviewed/approved/rejected/archived history with actor, status transition, safe note, and content snapshot.

### `sd_development_copilot_feedback`

Authorized actor/message feedback with bounded note and an enumerated type. It does not update the historical answer.

### `sd_development_ai_usage_ledger`

Append-only organization/actor/player/action/provider/model usage, sizes, optional tokens/cost, latency, status, retry count, and timestamp. It functions when billing metadata is absent.

## Quotas and founding behavior

Development defaults should be generous and environment-overridable: 200 questions per organization/day, 30 questions per actor/hour, 50 parent drafts per organization/day, 500 evidence rows, 40 conversation messages in provider context, and a bounded output size. Missing provider configuration returns `provider_unavailable` for unsupported conversational generation; deterministic suggested questions and supported deterministic answers remain available. There is no silent provider fallback or provider mislabeling.

## Final player visibility and dialogue correction

- Development reports now carry immutable `staff | player | parent` audience with historical default `staff`; parent read remains disabled.
- Development alerts now carry immutable `staff | player` audience with historical default `staff`.
- Report idempotency and alert deduplication include audience. Evidence rows inherit exact parent organization/player/audience through composite foreign keys and read helpers.
- Player summaries are deterministic self-only drafts using `player-development-self-summary.v1`; players may archive but cannot review/approve/reject or read staff review history.
- Player alerts are separately generated objective informational rows. Players may dismiss their own row; staff workflow/roster alerts never become player-visible.
- Player Copilot accepts only player-audience report/alert citation sources after pre-provider filtering.
- Assistant turns and pending-question state distinguish answers, clarifications, evidence gaps, reflections, confirmations, follow-ups, previews, and refusals. Exact pending ID/audience/conversation binding prevents stale responses.
- Reflection answers remain private conversation content. Confirmation executes no tool or official-record mutation.
- No report/alert/dialogue path inserts notification-center or APNs delivery rows.

Absent feature-specific entitlement rows use founding/development allow behavior for otherwise authorized active staff. This behavior must be documented and observable; the backend remains authoritative and can later enforce feature keys.

## Migration recommendation

The actual latest local migration is `20260715090000_player_development_import_validation_fix.sql`, so the additive migration should be `20260715100000_player_development_copilot.sql`. It must not modify an applied migration, must not be applied during implementation, and requires PostgreSQL runtime validation after review.

## Audit conclusion

No database defect was found in Phase 11A/11B. The new schema is product capability, not a repair. The Phase 11A evidence builder and authorization behavior should be shared with a separate `player-development-copilot` function. Reports, imports, chat, payments, notifications, and APNs remain independent and unchanged.
