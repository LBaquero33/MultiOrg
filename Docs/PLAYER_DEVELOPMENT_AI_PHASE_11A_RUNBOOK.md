# Player Development AI Phase 11A runbook

Nothing in this runbook was executed during implementation.

## Deployment order

1. Review and back up the target project. Confirm the latest applied migration is `20260715050000_notification_direct_messages_integration.sql`.
2. Apply only `20260715060000_player_development_ai_foundation.sql`.
3. Verify tables, indexes, constraints, RLS, grants, metric seed count, and RPC definitions.
4. Deploy only `player-development-ai` with JWT verification enabled.
5. Install the updated controlled test build.
6. Do not configure any external AI secret; none is required.

## Static/preflight SQL

```sql
select version from supabase_migrations.schema_migrations order by version desc limit 3;

select tablename, rowsecurity
from pg_tables
where schemaname = 'public' and tablename like 'sd_development%'
   or schemaname = 'public' and tablename = 'sd_player_metric_observations'
order by tablename;

select canonical_key, canonical_unit, preferred_direction, minimum_sample_size
from public.sd_development_metric_definitions
order by canonical_key;

select routine_name, security_type
from information_schema.routines
where routine_schema = 'public'
  and routine_name in (
    'sd_create_development_report', 'sd_review_development_report',
    'sd_upsert_development_alerts', 'sd_review_development_alert'
  );
```

Verify function configuration includes a safe empty search path. Only `service_role` may execute lifecycle RPCs; authenticated access is limited to the two `auth.uid()` RLS helper wrappers. Verify no authenticated insert/update/delete table policies or table privileges exist.

## Controlled manual validation

Use one controlled organization and player. Test active owner, admin, scoped coach, parent, player, unrelated user, inactive staff, and platform-only support.

1. Open Coach → player → Development AI.
2. Build the evidence view for 30/90/180/365 days.
3. Confirm every source row is in the same organization/player and before the cutoff.
4. Generate one deterministic summary; retry the same operation and confirm one report.
5. Confirm every conclusion references a persisted evidence key and no absent metric appears.
6. Confirm missing attendance/completion are described as unavailable, not poor performance.
7. Review and approve the report.
8. Archive it and confirm report, evidence, and review events remain queryable.
9. Run alert detection twice and confirm one row per deduplication key with updated `last_detected_at` and event history.
10. Acknowledge, dismiss, and resolve controlled alerts.
11. Open Roster Attention; confirm only authorized organization/team players appear and search/filter work.
12. Switch organizations and users; confirm prior reports/alerts are cleared and late responses are ignored.
13. Confirm parent/player/platform-only access receives 403 and no Phase 11A UI entry.
14. Confirm chat/direct-message notifications, notification center, APNs, payment requests/reconciliation, finance/expenses, Stripe/Connect, StoreKit, and organization subscriptions still behave unchanged.
15. Confirm no external AI network call, notification, or live message occurs.

## Runtime audit queries

```sql
select id, org_id, player_id, report_type, status, quality_status,
       generation_mode, provider, generator_version, input_cutoff,
       requested_by, created_at
from public.sd_development_reports
where org_id = '<CONTROLLED_ORG_UUID>'::uuid
order by created_at desc;

select report_id, org_id, player_id, evidence_key, source_entity_type,
       source_record_id, canonical_metric_key, observation_date, quality,
       deterministic_rule_id
from public.sd_development_report_evidence
where org_id = '<CONTROLLED_ORG_UUID>'::uuid
order by created_at desc;

select report_id, actor_id, event_type, from_status, to_status, created_at
from public.sd_development_report_review_events
where org_id = '<CONTROLLED_ORG_UUID>'::uuid
order by created_at;

select id, player_id, alert_type, severity, status, deduplication_key,
       first_detected_at, last_detected_at, evidence_quality
from public.sd_development_alerts
where org_id = '<CONTROLLED_ORG_UUID>'::uuid
order by last_detected_at desc;
```

## Evidence and deterministic behavior

The builder adapts testing/BP/daily-log/assignment sources plus normalized observations. It calculates only registry-backed metrics, uses explicit date/cutoff filters, preserves units, emits quality/warnings, and omits private note text. The template summarizes supported trends and evidence gaps. Trend math and alert rules are documented in the evidence model.

## Rollback

First remove the app entry points or undeploy the new Edge Function. Preserve/export all report, evidence, review, alert, and event rows. Only then follow the ordered manual drop guidance in the migration header. Do not roll back by deleting controlled reports individually; audit retention is a product requirement. Existing source tables require no rollback because Phase 11A does not alter them.

## Deferred intentionally

External model providers, secrets, live parent/player publication, APNs/notification delivery, attendance/completion/coach-interaction alerts, full vendor import parsers, game statistics, video AI, CommandIQ, recruiting, medical interpretation, autonomous actions, and public ranking/scoring.
