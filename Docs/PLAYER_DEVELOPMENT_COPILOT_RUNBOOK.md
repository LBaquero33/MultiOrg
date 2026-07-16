# Player Development Copilot runbook

No deployment or migration apply is part of implementation. Phase 11M requires no migration.

## Deployment order

1. Confirm `20260715100000_player_development_copilot.sql` is already applied and unchanged; do not reapply it or create a Phase 11M migration.
2. Deploy only `player-development-copilot`; its bundle contains the shared deterministic/validator corrections and the Copilot index evidence change.
3. Keep the existing provider configuration unchanged for controlled deterministic validation.
4. Install the updated app and validate player reports/alerts, Coach Copilot, and Player Copilot independently.
5. Only after the deterministic evaluation gate passes may a separate approved workflow change provider configuration.

## Provider modes

- Deterministic: supported questions and parent drafts work without network AI. Supported questions bypass remote generation even if a remote provider is configured.
- OpenAI/Anthropic: select the provider, set an environment-driven model identifier, output bound, and its secret key. Never hardcode or log them.
- Unavailable: an unknown provider or missing model/key returns an explicit unavailable state. There is no silent deterministic or cross-provider fallback.

## Post-apply SQL verification

Run in a controlled SQL session and retain results:

```sql
select version from supabase_migrations.schema_migrations
where version = '20260715100000';

select tablename, rowsecurity
from pg_tables
where schemaname = 'public' and (
  tablename like 'sd_development%copilot%'
  or tablename in (
     'sd_development_generation_attempts',
     'sd_development_parent_update_drafts',
     'sd_development_parent_draft_review_events',
     'sd_development_ai_usage_ledger',
     'sd_development_reports',
     'sd_development_report_evidence',
     'sd_development_report_review_events',
     'sd_development_alerts',
     'sd_development_alert_evidence',
     'sd_development_alert_events'
  )
)
order by tablename;

select conrelid::regclass as table_name, conname, contype,
       pg_get_constraintdef(oid) as definition
from pg_constraint
where connamespace = 'public'::regnamespace
  and conrelid::regclass::text like 'sd_development%'
  and (
    conname like '%copilot%'
    or conname like '%parent_draft%'
    or conname like '%attempt%'
    or conname like '%audience%'
  )
order by table_name, conname;

select schemaname, tablename, policyname, roles, cmd, qual, with_check
from pg_policies
where schemaname = 'public' and tablename like 'sd_development%'
  and (
    tablename like '%copilot%'
    or tablename like '%parent%'
    or tablename like '%generation%'
    or tablename like '%usage%'
    or tablename like '%report%'
    or tablename like '%alert%'
  )
order by tablename, policyname;

select event_object_table, trigger_name, action_timing, event_manipulation
from information_schema.triggers
where trigger_schema = 'public'
  and trigger_name like 'trg_sd_%'
  and (
    trigger_name like '%copilot%'
    or trigger_name like '%generation%'
    or trigger_name like '%parent_draft%'
    or trigger_name like '%ai_usage%'
    or trigger_name like '%report_audience%'
    or trigger_name like '%alert_audience%'
  )
order by event_object_table, trigger_name, event_manipulation;

select p.proname, p.prosecdef, p.proconfig,
       has_function_privilege('anon', p.oid, 'execute') as anon_execute,
       has_function_privilege('authenticated', p.oid, 'execute') as authenticated_execute,
       has_function_privilege('service_role', p.oid, 'execute') as service_execute
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and (
    p.proname like 'sd_%development%copilot%'
    or p.proname like 'sd_%parent_update_draft%'
    or p.proname in (
      'sd_create_development_report_audience',
      'sd_review_development_report_audience',
      'sd_upsert_development_alerts_audience',
      'sd_review_development_alert_audience',
      'sd_development_report_current_actor_can_read',
      'sd_development_alert_current_actor_can_read'
    )
  )
order by p.proname;

select grantee, table_name, privilege_type
from information_schema.role_table_grants
where table_schema = 'public' and table_name like 'sd_development%'
  and grantee in ('anon','authenticated','service_role')
order by table_name, grantee, privilege_type;

select prompt_key, use_case, intended_audience, version,
       evidence_schema_version, output_schema_version, safety_version,
       is_active, deprecated_at
from public.sd_development_copilot_prompt_versions
order by prompt_key, version;
```

Confirm all ten Copilot tables, the report/alert audience columns and child evidence/event boundaries, RLS, audience composite foreign keys, audience-aware idempotency constraints, indexes, audience/pending-scope immutability and append-only triggers, no authenticated writes, six Copilot plus four report/alert service-role-only mutation RPCs, the two current-user authenticated report/alert read helpers only, and eight active prompt versions.

## Authorization and evidence validation

Test owner, admin, authorized coach, unauthorized coach, active self player, another player, parent, inactive staff, unrelated user, and platform-only admin. Repeat list/detail/ask/retry/archive/feedback actions with foreign organization/player/conversation/message/citation UUIDs and both audiences. Verify active players succeed only for `actor = player = creator`, active organization membership, and audience `player`. Verify coaches succeed only for audience `coach` and established player scope. Verify neither side lists the other's history. All parent-draft actions must reject a player. Denial must occur before evidence/provider access.

For player evidence, seed or select objective testing plus a committed Rapsodo observation and verify original/normalized value, unit, date, provider, verification, trend, freshness, and citation. Add mock private notes/staff alerts/comparisons and prove they are removed before provider invocation. Submit an unknown evidence ID/rule and verify rejected persistence with no successful answer.

## Usage controls and monitoring

Defaults: 200 organization questions/day, 30 actor questions/hour, 50 organization drafts/day, 500 evidence rows, 40 history messages, and 16,000 output characters. Monitor safe counts by provider/model/action/status, latency, retry, rejected-output code, provider availability, and quota denial. Never log prompts, evidence payloads, credentials, or hidden reasoning.

Override only through validated server environment values: `PLAYER_DEVELOPMENT_AI_QUESTIONS_PER_ORG_DAY`, `PLAYER_DEVELOPMENT_AI_QUESTIONS_PER_ACTOR_HOUR`, `PLAYER_DEVELOPMENT_AI_PARENT_DRAFTS_PER_ORG_DAY`, `PLAYER_DEVELOPMENT_AI_MAX_EVIDENCE_ROWS`, `PLAYER_DEVELOPMENT_AI_MAX_CONVERSATION_MESSAGES`, and `PLAYER_DEVELOPMENT_AI_MAX_OUTPUT_CHARACTERS`. Missing, non-integer, or out-of-range values use the documented defaults. Do not expose these controls to Swift.

## Parent review

Generate, edit, mark reviewed, approve/reject, and archive. Confirm generated original and review history remain unchanged, the current edit is preserved, parents cannot read it, and no delivery/notification row is created.

## Rollback

Disable both Copilot navigation entries/Edge deployment first. Revert provider selection to deterministic/unavailable. Preserve and export conversation, pending-question, report, alert, citation, attempt, feedback, usage, and review-event audit rows. Revoke the audience-aware dialogue/report/alert RPCs before restoring any retired signature. Drop audience policies/helpers/triggers, then pending-question and other child objects only under an approved destructive-data plan. Removing report/alert audience columns requires restoring old keys and preserving historical Phase 11A rows. Phase 11B imports, chat, payments, notifications, and APNs require no rollback.

## Controlled live validation (provide, do not run during implementation)

1. Apply only the Copilot migration.
2. Verify tables, constraints, RLS, functions, and grants.
3. Deploy `player-development-ai`, then `player-development-copilot`; deploy no unrelated function.
4. Install the updated app.
5. Use controlled organization `800e22ae-2a9d-4109-9e11-1360eeaa8ea7` and controlled player `4b999cda-7826-4fae-9334-1a269dc34795` only after confirming that profile has an active player membership there.
6. Sign in as the controlled player, select that organization, open Player Development AI, and verify the target cannot be changed.
7. Verify objective testing/import evidence and Rapsodo value/unit/date/provider/verification labels; no raw file/path appears.
8. Create one player-audience conversation and ask “What changed in the last 90 days?”, “How am I doing overall?”, “What evidence is missing?”, and “What did my latest Rapsodo session show?”
9. Verify every claim has self-scoped citations, prompt version `player-copilot-self.v1`, and only player-safe actions requiring human action.
10. Ask an unsupported and a medical-diagnosis question; verify `deterministic_intent_unrecognized`/`unsupported_without_provider` and safe refusal behavior as appropriate.
11. Ask “Explain this metric in simple language”; verify one clarification, answer/skip/use-evidence paths, exact pending binding, and stale rejection.
12. Generate My Summary as the controlled player; verify only a player-audience draft and separately identified player alerts appear, with no notification/APNs delivery.
13. Verify staff cannot open player-private reports/alerts and the player cannot open staff equivalents.
14. Submit player feedback, retry one failed answer with its stable idempotency key, and verify no duplicate.
15. Sign in as authorized staff and confirm the player conversation/feedback is absent from Coach Copilot.
16. Create one coach-audience conversation and verify the player cannot list/read it.
17. Generate, edit, review, and approve one parent draft from the coach conversation; confirm it is staff-only and not delivered.
18. Test owner, admin, authorized/unauthorized coach, self player, another player, parent, inactive/unrelated/platform-only actors and foreign UUIDs.
19. Switch organizations and users; verify workspace/history clears and no evidence is combined.
20. Confirm Phase 11A reports, Phase 11B imports, chat, notifications/APNs, payments, and finance behavior remains functional.

## Phase 11M safe monitoring

Monitor only the documented lifecycle events and bounded metadata in `PLAYER_DEVELOPMENT_COPILOT_STABILIZATION.md`. Alert on stable validation-code counts, deterministic supported-intent failures, persistence failures, latency, and retry outcomes. Never log question/answer text, evidence, player names, tokens, or secrets.

## Intentionally deferred

External-provider activation, provider billing enforcement, automatic conversational tool execution, explicit coach/player sharing, parent visibility/delivery, notifications, APNs, future Athlete integration, general baseball chat, and feature-key subscription enforcement.
