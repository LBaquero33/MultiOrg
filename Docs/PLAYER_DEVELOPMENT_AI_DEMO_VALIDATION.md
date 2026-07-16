# Phase 11A controlled demo validation

> **SYNTHETIC / UNVERIFIED DATA ONLY**
>
> Nothing created by this dataset is verified recruiting data. Use only the designated test player and organization. Never use these values in recruiting, medical, attendance, or performance claims.

These scripts are manual SQL Editor tools, not migrations. They do not generate reports, alerts, notifications, APNs messages, or external-AI requests.

## What the schema and adapter actually support

The source schema was traced through the deployed migration history before the scripts were written:

| Source | Columns used |
| --- | --- |
| `profiles` | `id`, `full_name` |
| `sd_org_memberships` | `org_id`, `user_id`, `role`, `status`, `created_at` |
| `sd_testing_entries` | organization/player/date, body/strength/exit-velocity/mobility numerics, `notes` |
| `sd_daily_logs` | organization/player/date, `feel`, `hit_daily_goals`, `stuck_to_process`, `notes` |
| `sd_program_templates` / `sd_program_assignments` | organization, coach/player/template, dates, kind, `notes` |
| `sd_bp_sessions` / `sd_bp_events` | organization/player/date/source/reps type and event exit velocity/distance/launch angle/`raw` |
| `sd_player_metric_observations` | canonical definition, original/normalized values, unit, timestamp, source identity, quality, metadata |
| Phase 11A audit tables | reports, report evidence/review events, alerts, alert evidence/events |

Canonical definitions used:

- `hitting.max_exit_velocity` — `mph`, `higher_is_better`, minimum sample 2.
- `physical.sprint_time` — `s`, `lower_is_better`, minimum sample 2.
- `strength.squat_1rm` — `lb`, `higher_is_better`, minimum sample 2.
- `consistency.process_adherence_rate` — `percent`, `higher_is_better`, minimum sample 5; adapted from daily-log process answers.

The original adapter loaded program assignments only as a coverage count. The accompanying narrow adapter change emits assignment-presence evidence while explicitly stating that assignment is not proof of attendance or completion. It also carries only sanitized demo provenance from source rows into evidence snapshots. Because this task does not deploy, live program citations and sanitized demo provenance require that adapter change to be reviewed and deployed separately before this full live checklist is run. The SQL dataset itself is valid without that deployment.

## 1. Locate the organization

Run this in the Supabase SQL Editor for project `kbulbvngysflfhaqpvtv`:

```sql
select id, slug, name, status
from public.sd_orgs
order by name;
```

Copy the intended active organization UUID as `<ORG_ID>`.

## 2. Locate Andrew and confirm membership

Replace `<ORG_ID>` in this read-only query:

```sql
select
  p.id as player_id,
  p.full_name,
  u.username as organization_username,
  m.org_id,
  m.role,
  m.status
from public.profiles p
join public.sd_org_memberships m on m.user_id = p.id
left join public.sd_org_usernames u
  on u.org_id = m.org_id and u.user_id = m.user_id
where m.org_id = '<ORG_ID>'::uuid
  and m.role = 'player'
  and m.status = 'active'
  and (
    lower(coalesce(u.username, '')) = 'andrew'
    or lower(coalesce(p.full_name, '')) like '%andrew%'
  )
order by u.username, p.full_name, p.id;
```

Copy the designated controlled account UUID as `<PLAYER_ID>`. Require exactly the expected Andrew row; do not choose by name alone if more than one result appears.

Confirm the exact scope again:

```sql
select org_id, user_id, role, status
from public.sd_org_memberships
where org_id = '<ORG_ID>'::uuid
  and user_id = '<PLAYER_ID>'::uuid;
```

Expected: one row with `role = player` and `status = active`.

## 3. Run the seed manually

1. Open [`tools/sql/player_development_ai_demo_seed.sql`](../tools/sql/player_development_ai_demo_seed.sql).
2. Replace its one `<ORG_ID>` and one `<PLAYER_ID>` placeholder. Do not change the confirmation string.
3. Review the visible `SYNTHETIC` warnings and deterministic UUIDs.
4. Paste the entire script into the authenticated Supabase SQL Editor and run it once.
5. Confirm the notices report: 1 template, 1 assignment, 4 testing entries, 8 daily logs, 3 BP sessions, 15 BP events, and 12 normalized observations.
6. A second execution is an idempotency check: it must report the same logical totals and the verification queries below must still return those counts, not doubles.

The block validates organization, profile, exact active player membership, active canonical metric contracts, a derived in-organization staff assigner, natural-key conflicts, and reserved-ID provenance before its first write. Every insert uses the selected `v_org_id` and `v_player_id`. Any exception rolls back the entire block.

## 4. Verify the source rows

Replace both placeholders in each query.

Testing evidence (expected 4):

```sql
select id, entry_date, weight_lb, squat_1rm, bench_1rm, deadlift_1rm,
       max_exit_velo, avg_exit_velo, notes
from public.sd_testing_entries
where org_id = '<ORG_ID>'::uuid
  and player_id = '<PLAYER_ID>'::uuid
  and notes like 'home_plate_demo_seed | phase_11a.v1%'
order by entry_date;
```

Normalized observations (expected 12, four per metric):

```sql
select o.id, d.canonical_key, o.observed_value, o.normalized_value, o.unit,
       o.observed_at, o.source_system, o.source_entity_type,
       o.source_record_id, o.quality_status, o.sample_size, o.context_metadata
from public.sd_player_metric_observations o
join public.sd_development_metric_definitions d on d.id = o.metric_definition_id
where o.org_id = '<ORG_ID>'::uuid
  and o.player_id = '<PLAYER_ID>'::uuid
  and o.source_system = 'home_plate_demo_seed'
  and o.context_metadata @> '{"demo_seed":true,"demo_version":"phase_11a.v1","verification_status":"synthetic_unverified"}'::jsonb
order by d.canonical_key, o.observed_at;
```

Daily-log consistency (expected 8; six true and two false process answers):

```sql
select id, log_date, feel, hit_daily_goals, stuck_to_process, notes
from public.sd_daily_logs
where org_id = '<ORG_ID>'::uuid
  and player_id = '<PLAYER_ID>'::uuid
  and notes like 'home_plate_demo_seed | phase_11a.v1%'
order by log_date;
```

Program context (expected one assignment and one exact demo template):

```sql
select a.id as assignment_id, a.player_id, a.start_date, a.ended_at, a.notes,
       t.id as template_id, t.name, t.program_kind, t.weeks
from public.sd_program_assignments a
join public.sd_program_templates t on t.id = a.template_id and t.org_id = a.org_id
where a.org_id = '<ORG_ID>'::uuid
  and a.player_id = '<PLAYER_ID>'::uuid
  and a.id = '11a00000-0000-4000-8000-000000000002'::uuid
  and a.notes like 'home_plate_demo_seed | phase_11a.v1%'
  and t.name = 'AI Demo Validation Program';
```

BP sessions and events (expected 3 sessions / 15 events):

```sql
select s.id, s.session_date, s.source, s.reps_type,
       count(e.id) as event_count,
       round(avg(e.exit_velo), 2) as average_exit_velocity,
       max(e.exit_velo) as maximum_exit_velocity
from public.sd_bp_sessions s
join public.sd_bp_events e on e.session_id = s.id
where s.org_id = '<ORG_ID>'::uuid
  and s.player_id = '<PLAYER_ID>'::uuid
  and e.raw @> '{"demo_seed":true,"demo_version":"phase_11a.v1","verification_status":"synthetic_unverified"}'::jsonb
group by s.id, s.session_date, s.source, s.reps_type
order by s.session_date;
```

One compact count check:

```sql
select
  (select count(*) from public.sd_testing_entries where org_id = '<ORG_ID>'::uuid and player_id = '<PLAYER_ID>'::uuid and notes like 'home_plate_demo_seed | phase_11a.v1%') as testing_rows,
  (select count(*) from public.sd_daily_logs where org_id = '<ORG_ID>'::uuid and player_id = '<PLAYER_ID>'::uuid and notes like 'home_plate_demo_seed | phase_11a.v1%') as daily_rows,
  (select count(*) from public.sd_player_metric_observations where org_id = '<ORG_ID>'::uuid and player_id = '<PLAYER_ID>'::uuid and source_system = 'home_plate_demo_seed') as observation_rows,
  (select count(*) from public.sd_bp_sessions where org_id = '<ORG_ID>'::uuid and player_id = '<PLAYER_ID>'::uuid and id::text like '11a00000-0000-4300-8300-%') as bp_sessions,
  (select count(*) from public.sd_bp_events e join public.sd_bp_sessions s on s.id = e.session_id where s.org_id = '<ORG_ID>'::uuid and s.player_id = '<PLAYER_ID>'::uuid and e.raw @> '{"demo_seed":true,"demo_version":"phase_11a.v1"}'::jsonb) as bp_events;
```

Expected: `4, 8, 12, 3, 15`.

## 5. Validate in the app

1. Open **Player Development AI** for Andrew in the selected organization.
2. Select the trailing **90 days**.
3. Generate a new deterministic summary. No external model is needed or expected.
4. Confirm evidence coverage is greater than zero and quality is not `unavailable`. The process-adherence aggregate may legitimately make overall quality `limited`; do not force `sufficient`.
5. Confirm positive trends include Maximum Exit Velocity, Sprint Time (falling is improvement), Squat 1RM, or other supported increases.
6. Confirm the decreasing synthetic Bench Press 1RM is presented only as a coach-review development priority, without medical or causal claims.
7. Confirm daily-log consistency describes eight available logs but makes no attendance claim.
8. Confirm `AI Demo Validation Program` appears only as assignment context and never as completion/attendance evidence.
9. Open evidence detail. Trend citations should point to the deterministic source records and show `demo_seed = true`, `demo_version = phase_11a.v1`, and `verification_status = synthetic_unverified` after the accompanying adapter change is deployed.
10. Confirm BP evidence shows improving synthetic exit velocity and no unsupported pitching claims.
11. Confirm there are no medical claims, guarantees, recruiting verification, fabricated values, or invented attendance/program-completion claims.

## 6. Validate alert detection and deduplication

1. Run alert detection once and note the visible alert IDs/count.
2. Run it a second time with the same player/window/month.
3. The same `(org_id, player_id, deduplication_key)` alerts must be redetected, not duplicated.

Read-only verification:

```sql
select id, alert_type, severity, status, deduplication_key,
       first_detected_at, last_detected_at
from public.sd_development_alerts
where org_id = '<ORG_ID>'::uuid
  and player_id = '<PLAYER_ID>'::uuid
order by last_detected_at desc;

select a.id as alert_id, a.alert_type, e.evidence_key,
       e.source_entity_type, e.source_record_id,
       e.canonical_metric_key, e.evidence_snapshot
from public.sd_development_alerts a
join public.sd_development_alert_evidence e
  on e.alert_id = a.id and e.org_id = a.org_id and e.player_id = a.player_id
where a.org_id = '<ORG_ID>'::uuid
  and a.player_id = '<PLAYER_ID>'::uuid
order by a.last_detected_at desc, e.observation_date;

select org_id, player_id, deduplication_key, count(*)
from public.sd_development_alerts
where org_id = '<ORG_ID>'::uuid
  and player_id = '<PLAYER_ID>'::uuid
group by org_id, player_id, deduplication_key
having count(*) > 1;
```

The final query must return zero rows. Alert events should contain one `detected` event followed by `redetected` events for repeated runs.

## 7. Validate report evidence, trends, idempotency, and review

Latest reports:

```sql
select id, status, quality_status, reporting_window_start, reporting_window_end,
       requested_by, idempotency_key, request_fingerprint,
       structured_content->'positive_trends' as positive_trends,
       structured_content->'development_priorities' as development_priorities,
       structured_content->'consistency_and_attendance' as consistency,
       created_at
from public.sd_development_reports
where org_id = '<ORG_ID>'::uuid
  and player_id = '<PLAYER_ID>'::uuid
order by created_at desc
limit 10;
```

Evidence for the latest report:

```sql
with latest as (
  select id
  from public.sd_development_reports
  where org_id = '<ORG_ID>'::uuid and player_id = '<PLAYER_ID>'::uuid
  order by created_at desc
  limit 1
)
select e.section_key, e.evidence_key, e.source_entity_type,
       e.source_record_id, e.canonical_metric_key,
       e.normalized_numeric_value, e.unit, e.comparison_value,
       e.direction, e.sample_size, e.quality,
       e.source_metadata, e.evidence_snapshot
from public.sd_development_report_evidence e
join latest l on l.id = e.report_id
order by e.section_key, e.observation_date, e.evidence_key;
```

Expanded structured trends:

```sql
with latest as (
  select structured_content
  from public.sd_development_reports
  where org_id = '<ORG_ID>'::uuid and player_id = '<PLAYER_ID>'::uuid
  order by created_at desc
  limit 1
)
select 'positive' as section, item
from latest, jsonb_array_elements(coalesce(structured_content->'positive_trends', '[]'::jsonb)) item
union all
select 'priority', item
from latest, jsonb_array_elements(coalesce(structured_content->'development_priorities', '[]'::jsonb)) item;
```

Report idempotency is bound by `(org_id, requested_by, idempotency_key)` and a request fingerprint. To exercise ambiguous retry behavior, keep the same organization/player/window, induce only a temporary client-network interruption during one Generate attempt, restore connectivity, and use the app's explicit Retry action without changing the material request. The client retains its operation key until definite success. Whether the first request committed or not, the retry must leave one logical report for that key.

```sql
select org_id, requested_by, idempotency_key, count(*)
from public.sd_development_reports
where org_id = '<ORG_ID>'::uuid
  and player_id = '<PLAYER_ID>'::uuid
group by org_id, requested_by, idempotency_key
having count(*) > 1;
```

Expected: zero rows. Do not repeatedly press Generate after a definite success; a new completed operation is allowed to use a new key.

Open the newest draft in the app and exercise **Review**, then **Approve** or **Reject** as appropriate. Verify immutable review history:

```sql
select r.id, r.status, r.reviewed_at, r.reviewed_by, r.approved_at,
       r.rejected_at, r.archived_at, e.event_type, e.from_status,
       e.to_status, e.created_at
from public.sd_development_reports r
join public.sd_development_report_review_events e
  on e.report_id = r.id and e.org_id = r.org_id
where r.org_id = '<ORG_ID>'::uuid
  and r.player_id = '<PLAYER_ID>'::uuid
order by r.created_at desc, e.created_at;
```

## 8. Optional cleanup

Before cleanup, capture the report and alert IDs from the queries above. Phase 11A audit records intentionally survive source cleanup.

1. Open [`tools/sql/player_development_ai_demo_cleanup.sql`](../tools/sql/player_development_ai_demo_cleanup.sql).
2. Replace only `<ORG_ID>` and `<PLAYER_ID>` with the same values used for seeding.
3. Run the entire block in the SQL Editor.
4. Rerun it once to confirm cleanup idempotency (all delete notices should be zero on the second run).
5. Rerun the source verification queries; demo source counts should be zero. Query unrelated rows before and after if the test player already had other data; their IDs/counts must be unchanged.

The cleanup does **not** hard-delete `sd_development_reports`, report evidence/review events, alerts, alert evidence, or alert events. To retire generated demo lifecycle records, use the authenticated app:

- Open each demo report and choose **Archive** when its current status permits it.
- Open each demo alert and choose **Resolve** or **Archive** when its current status permits it.

The lifecycle RPCs (`sd_review_development_report` and `sd_review_development_alert`) are executable only by `service_role` and trust an actor transferred by the JWT-authenticated Edge Function. Do not paste a service-role secret into the SQL Editor and do not call these RPCs directly with a caller-supplied actor UUID. Use the app/Edge Function path so authorization and audit events remain intact.

After source cleanup, historical report/alert evidence remains an immutable snapshot and continues to show that it came from synthetic, unverified demo provenance.
