# Phase 11B.1 final deployment-readiness audit

Audit date: 2026-07-15
Project: Home Plate
Scope: migration `20260715070000_player_development_data_imports.sql`, `player-development-imports`, shared parser, Phase 11A evidence adapter, Swift workspace, configuration, fixtures, and tests.

## Verdict

**Ready for a controlled deployment, with no deployment performed by this audit.**

The initial audit found material defects in cross-job concurrency, lifecycle enforcement, coach access to organization-wide jobs, expired upload handling, parser/request resource bounds, strict number/date handling, reusable player resolutions, and Swift stale/cancellation state. They were corrected directly in the unapplied migration and associated Phase 11B.1 code. No Phase 11A demo row was changed.

Two operational limitations remain intentional:

- Expiry disables further upload/inspection/commit, but retained private objects are not automatically deleted. A privileged retention process must delete expired objects according to the adopted retention policy.
- There is no rejected-row CSV export. Any future spreadsheet export must prefix or otherwise neutralize cells beginning with `=`, `+`, `-`, or `@`.

## 1. Exact schema inventory

### `sd_development_import_jobs` (Phase 11A plus 11B.1)

- Identity: PK `id uuid`; `org_id -> sd_orgs(id)`; optional `player_id -> profiles(id)`; `requested_by -> profiles(id)`.
- Base/audit columns: `import_source`, constrained `provider`, bounded `file_name`, `idempotency_key`, `import_version`, `created_at`, `updated_at`.
- File identity: `original_file_type`, SHA-256 `file_sha256`, 1..10 MiB `file_size_bytes`, `storage_bucket`, `storage_path`, `artifact_expires_at`.
- Parser/mapping identity: `parser_version`, `mapping_version`, SHA-256 `mapping_fingerprint`, SHA-256 `player_scope_fingerprint`, SHA-256 `header_fingerprint`, `file_shape`, bounded `mapping_config`.
- Result/audit state: `status`, `row_count`, `accepted_rows`, `rejected_rows`, `unmatched_player_rows`, `warning_count`, bounded `validation_summary`, `safe_error_code`, `safe_error_summary`, `started_at`, `completed_at`, `archived_at`.
- Unique constraints: `(org_id, requested_by, idempotency_key)`, `(id, org_id)`, `(id, org_id, player_id)`.
- Checks: status allowlist; nonnegative counts; accepted+rejected <= received; unmatched <= rejected and received; timestamp/archive consistency; hashes; provider; file type/size/name; JSON size; exact bucket/path identity.
- Explicit indexes: `(org_id,status,created_at desc)`; expiry partial index; unique active/completed file identity `(org_id,provider,file_sha256,parser_version,mapping_fingerprint,player_scope_fingerprint)` for `importing/completed/completed_with_errors`.
- Triggers: active exact-org player scope; active exact-org staff requester scope; lifecycle transition validator; `updated_at`.
- RLS: enabled in Phase 11A. Owner/admin read the organization; a coach reads authorized player jobs and only their own organization-wide jobs.
- Grants: authenticated has SELECT only; service role has SELECT/INSERT/UPDATE; no authenticated mutation and no table DELETE grant.

### `sd_player_metric_observations` (Phase 11A plus 11B.1)

- Identity: PK `id`; exact `org_id`, `player_id`, and `metric_definition_id` FKs.
- Observation: raw `observed_value`, numeric `normalized_value`, canonical legacy `unit`, `observed_at`, `sample_size`, `quality_status`, `notes`.
- Source: `source_system`, `source_entity_type`, UUID `source_record_id`, optional `import_job_id`, bounded `context_metadata`.
- Import provenance: `original_unit`, `canonical_unit`, `conversion_rule/version/warning`, `verification_status`, `parser_version`, `mapping_version`, `source_row_number`, `source_date_string`, `imported_timezone`.
- Correction audit: `correction_of_id`, `corrected_at`, `corrected_by`; `created_at`, `updated_at`.
- Composite FKs: `(import_job_id,org_id) -> jobs(id,org_id)`; `(correction_of_id,org_id,player_id) -> observations(id,org_id,player_id)`.
- Uniques: observation target `(org_id,player_id,metric_definition_id,source_system,source_entity_type,source_record_id,observed_at)`; `(id,org_id,player_id)`.
- Checks: raw or normalized value required; positive sample; correction consistency; quality and verification allowlists; bounded provenance; imported rows require normalized value, job, unverified-device state, parser/mapping/conversion/row/date/timezone provenance.
- Indexes: player/metric/date; import job; correction.
- Triggers: active exact-org player; job/org/player consistency; imported metric must still be active; `updated_at`.
- RLS: enabled. Only staff with established player scope can SELECT.
- Grants: authenticated SELECT only; service role SELECT/INSERT only. Imported observations are immutable through this surface.

### `sd_development_import_mapping_profiles`

- PK `id`; `org_id -> sd_orgs`; `created_by -> profiles`; unique `(id,org_id)`.
- Provider, trimmed name, header fingerprint, normalized headers, parser/mapping versions, file shape, bounded player/date/metric/unit/context/config JSON.
- Lifecycle: `is_active`, `archived_at` with exact active/archive consistency.
- Audit: `created_by`, `created_at`, `updated_at`; updated-at trigger.
- Uniques/indexes: active case-insensitive `(org_id,provider,mapping_name)`; active header lookup `(org_id,provider,header_fingerprint,parser_version)`.
- Scope trigger requires the creator to be active exact-org staff and every stored resolution to be an active exact-org player. Edge-created reusable profiles strip file-specific resolutions.
- RLS enabled; organization staff SELECT policy. Authenticated SELECT only; service role SELECT/INSERT/UPDATE.

### `sd_development_external_player_identities`

- PK `id`; `org_id -> sd_orgs`; `player_id -> profiles`; `linked_by -> profiles`.
- Constrained provider; trimmed/control-free `external_player_id`; generated normalized ID `lower(btrim(external_player_id))`; optional bounded label.
- Audit/lifecycle: verification state, `linked_by`, `linked_at`, `archived_at`, `created_at`, `updated_at`; updated-at trigger.
- Uniques: `(id,org_id)`, `(id,org_id,player_id)`; one unarchived `(org_id,provider,normalized_external_player_id)`.
- Scope trigger requires an active exact-org player and active exact-org staff linker.
- RLS enabled; staff SELECT additionally requires player-management scope. Authenticated SELECT only; service role SELECT/INSERT/UPDATE.

### `sd_development_import_row_errors`

- PK `id`; `org_id -> sd_orgs`; composite `(import_job_id,org_id) -> jobs(id,org_id)`.
- Immutable fields: row number, player/metric/acceptance states, stable code arrays, <=500 safe summary, <=4 KiB safe identity, `created_at`.
- Unique `(import_job_id,source_row_number,error_codes,warning_codes)`; index `(org_id,import_job_id,source_row_number)`.
- No update timestamp or archival mutation: records remain audit children of a retained job.
- RLS enabled. Owner/admin may read scoped jobs; coaches may read authorized player jobs or their own organization-wide jobs.
- Authenticated SELECT only; service role SELECT/INSERT/DELETE. Persistence is capped at 1,000 records/job and reports truncation.

## 2–4. Cross-organization and private Storage proof

Database scope is not UUID-only:

- Job/player and requester triggers verify active memberships in the exact `org_id`.
- Observation/job and row-error/job composite FKs carry `org_id`.
- Observation trigger also requires a player-specific job to match the exact observation player.
- External identity and mapping-profile triggers validate exact-org memberships.
- Storage identity check binds the stored path to that job's own `org_id/id`.

The bucket upsert always writes `public=false`, `file_size_limit=10485760`, and MIME allowlist `text/csv`, `text/tab-separated-values`, `text/plain`, `application/csv`. It is idempotent and cannot be made public by re-running this statement.

Both Storage policies parse UUID-shaped first/second folders only inside a CASE-safe branch, then join them to the authoritative job and require `j.storage_path=name`. Insert additionally requires pending/uploaded state and a future expiry. The generated path is:

`<org UUID>/<job UUID>/<server-random UUID>.csv|tsv`

Display filename is never authorization input. There are no authenticated UPDATE or DELETE policies, upload uses `upsert=false`, and one exact path is stored per job.

Storage role matrix:

| Actor | Insert | Select |
|---|---:|---:|
| active owner/admin in job org | yes | yes |
| coach, authorized player job | yes | yes |
| coach, own organization-wide job | yes | yes |
| coach outside player scope / another coach's org-wide job / no qualifying team | no | no |
| inactive, parent, player, unrelated, platform admin without membership | no | no |
| service role | RLS bypass for the authenticated Edge workflow | RLS bypass |

Failed/archived/expired objects remain privately selectable to authorized staff for audit/cleanup; they cannot be overwritten. Expired targets cannot accept a new upload, and the Edge Function refuses expired artifacts for inspection/preview/commit.

## 5–7. Upload, JWT/service role, and action matrix

Flow: Swift validates extension/size and security-scoped access → verified actor creates job/server path → authenticated Storage insert under RLS → server downloads bytes, enforces size/UTF-8/CSV rules, and computes SHA-256 → mapping fingerprint and player-scope fingerprint are persisted → preview rebuilds server-side → commit downloads and rehashes the same object and rebuilds all rows.

No signed URL/token is generated or logged. The client never supplies bucket/path/hash/accepted rows/normalized values to commit.

`config.toml` requires JWT verification, and the function independently calls `auth.getUser()`. Actor ID comes only from that result. Request JSON is stream-read with a 1 MiB cap. The service client has no mutable caller singleton; request state is local.

Every action first verifies JWT and active owner/admin/coach membership. Job actions then load by `org_id+job_id` and apply player/creator scope. Mapping IDs are filtered by `org_id`; player IDs must occur in the current authorized candidate set. Service-role tables used are orgs, memberships, settings/teams/team members, profiles/usernames, jobs, mappings, external identities, row errors, metric definitions, observations, and private Storage.

| Action | Owner/admin | Coach with scope | Coach without scope/no team | Parent/player/inactive/unrelated/platform-only | Raw service credential |
|---|---:|---:|---:|---:|---:|
| create_job | yes | player job; multi-player only with >=1 authorized player | no player import | no | not a supported caller |
| create_upload_target, inspect_file, save_mapping, resolve_player, validate_job, get_preview, commit_job, get_job, list_row_errors, archive_job | yes | authorized player job; own org-wide job | no | no | internal Edge only |
| list_jobs | all org jobs | authorized player jobs + own org-wide jobs | only any previously owned org-wide job | no | internal Edge only |
| list_mappings, archive_mapping | yes | yes, org-scoped | yes, org-scoped | no | internal Edge only |

Organization-wide coach imports are supported, but candidates are independently restricted to the coach's active team scope. A scope fingerprint is persisted at validation and must still match at commit.

## 8. Lifecycle

Allowed states are legacy `pending/processing/canceled` plus `uploaded/inspecting/mapping_required/player_resolution_required/validating/ready/importing/completed/completed_with_errors/failed/archived`.

The SQL transition trigger permits only:

- pending → inspecting/processing/failed/canceled
- processing → completed/completed_with_errors/failed/canceled
- uploaded → inspecting/failed/canceled
- inspecting → mapping_required/failed
- mapping_required or player_resolution_required → validating/failed
- validating → ready/player_resolution_required/failed
- ready → validating/importing/failed
- importing → completed/completed_with_errors/failed
- failed → inspecting/validating/archived
- completed/completed_with_errors/canceled → archived

Commit claims only `ready`; a 15-minute stale `importing` lease can be reclaimed by compare-and-set on `updated_at`. The active/completed file unique index makes only one equivalent job enter `importing`. Completed retries return the completed job; equivalent attempts are audited as failed/reused. Imported/completed/archive timestamps and completed-with-error count semantics are enforced. A zero-accepted import cannot commit.

## 9–12. Parser, provider, and mapping safety

Limits: 10 MiB bytes, 50,000 data rows, 250 columns, 256 KiB logical row, 200-character header, 10,000-character cell, 20 context columns, 500 characters/value and 1,000 total context characters/observation, 50,000 generated observations, 100 response preview rows, 1,000 persisted row errors, 1 MiB JSON request.

The parser supports UTF-8/BOM, CSV/TSV, CRLF, quoted delimiters, escaped quotes, embedded quoted newlines, blank rows, and trailing empty fields. It rejects invalid UTF-8/NUL, empty/one-column/missing/duplicate or normalization-empty headers, extra data columns, oversized structures, unterminated/misplaced quotes, and ambiguous comma/tab headers.

Formula strings are data only and are never executed. Numeric fields accept strict invariant decimal/scientific forms and correctly grouped thousands; formulas and locale decimal commas reject.

Only `generic_csv` has an active automatic adapter. Other provider labels use the generic manual mapper and have no aliases/signatures/defaults activated without sanitized fixtures.

Wide mappings require distinct source columns and distinct canonical metrics; protected role/context conflicts reject. Long mappings require metric+value and resolve at most one exact canonical metric per row. All configured aliases/metrics must exist and be active. Unknown columns are ignored. Mapping JSON, alias counts, roles, source units, timezone, and resolutions are bounded and validated.

Header fingerprint is SHA-256 of normalized headers joined by U+001F. Mapping fingerprint is SHA-256 of recursively key-sorted JSON. Profiles bind org/provider/header/parser/mapping version and archive with partial uniqueness. Swift requires exact header/provider/parser compatibility; the server always revalidates referenced headers. File-specific manual resolutions are not stored in reusable profiles.

## 13–14. Player matching and external identities

Priority is: active unarchived provider external ID → case-insensitive, punctuation-exact organization username → unique normalized full name → explicit staff resolution.

External ID and username normalization is trim+lowercase with punctuation preserved. Full names are NFKD, diacritic-stripped, lowercase, non-alphanumerics collapsed to spaces, and whitespace collapsed. That name normalization can collide; collisions are returned as ambiguous and never auto-selected. There is no fuzzy match. Email and birth-year roles are not used.

Candidates originate only from active exact-org player memberships and current coach team scope. Manual resolution uses a server-issued source key proven still present in the authoritative file, and the selected player must be in that current candidate set. External links are provider/org scoped, actively unique, staff-attributed, and never rewrite historical imports. Relinking to another player is denied; archival/relinking would require a separate explicit privileged lifecycle action.

## 15–17. Metrics, units, numbers, dates

The generic UI exposes active numeric/duration metrics only:

- Hitting: max/average exit velocity, launch angle, hard-hit rate, contact rate, bat speed, attack angle, time to contact.
- Pitching: velocity, spin rate, spin efficiency, induced vertical break, horizontal break, release height, release side, extension, strike rate, zone rate, command score, miss distance, pitch usage.
- Physical/strength: sprint time, jump height, broad jump, height, body weight, workload, squat/bench/deadlift 1RM.
- Consistency: attendance, program completion, process adherence rates.
- Mobility: hip ER/IR and shoulder IR/ER differences.

The text-only `pitching.miss_direction` is not offered by this numeric importer. The database rechecks active metric status on insertion.

Conversion formula is `normalized = value × source.scale / target.scale`. Registry scales are mph 1; km/h 0.6213711922; lb 1; kg 2.2046226218; in 1; cm 0.3937007874; ft 12; m 39.37007874; s 1; ms 0.001; deg 1; rpm 1; percent 0.01; decimal ratio 1.

Examples covered by tests: 100 km/h = 62.13711922 mph; 10 kg = 22.046226218 lb; 100 cm = 39.37007874 in; 3 ft = 36 in; 1 m = 39.37007874 in (3.280839895 ft); 1000 ms = 1 s; 90 percent = 0.9 ratio; 0.9 ratio = 90 percent. mph/lb/in/s/deg/rpm identities are tested. No magnitude-based guessing occurs. Unknown/conflicting dimensions reject. Unitless metrics require an empty source unit. Raw and normalized values/units plus conversion rule/version are retained. IEEE-754 calculation is not silently rounded by the parser.

Accepted dates: ISO `YYYY-MM-DD`; complete ISO timestamps with explicit Z/offset; and explicit `MM/DD/YYYY`. Short years, invalid dates/times, offset-free timestamps, and >5-minute future values reject. Date-only values become noon in the selected IANA timezone; DST behavior is deterministic and tested. Original date text is retained.

## 18–22. Errors, parity, provenance, idempotency, atomicity

Stable parser/row codes include unsupported type/encoding, size/header/delimiter/column/row/cell/quote errors; missing/ambiguous/inactive player; missing/unsupported/deprecated metric; missing/invalid value; missing/unsupported/conflicting unit; missing/ambiguous/future date; and source/existing duplicate.

Persisted errors contain only row number, player/metric/acceptance state, codes, safe summary, and metric key/row identity—not full rows, email, or player name. Pagination is capped at 500 server-side and 100 in Swift.

Preview and commit call the same download, decode, parser, mapping validator, player matcher, metric resolver, converter, and date parser. Commit reconstructs observations from the authoritative object and persisted mapping. It checks SHA-256 and player-scope fingerprint; client preview state is irrelevant.

Each observation writes org/player/metric, raw and normalized values/units, timestamp, provider, entity type, SHA-256-derived deterministic UUID, job, row, sample/quality/verification, parser/mapping/conversion provenance, and bounded context. Imported state is `device_imported_unverified`, never coach/org verified.

Source identity material is org + provider + file SHA + parser + mapping fingerprint + source row + player + metric + raw value/unit + timestamp; it excludes job UUID. The conflict target is the full Phase 11A observation uniqueness tuple. The file-level active/completed unique index prevents two equivalent jobs from writing concurrently. One PostgREST upsert statement makes each observation batch atomic; a finalization failure leaves a recoverable importing lease, and retry is idempotent.

Changed mapping/parser/player scope produces a different controlled identity. Different organizations cannot conflict. Phase 11A synthetic rows are neither updated nor relabeled.

## 23. Evidence integration

The Phase 11A adapter reads normalized observations and emits provider/source system, import job ID, device-imported verification, original/canonical units, parser/mapping version, source row, and observation date into evidence. It does not include bucket/path, URLs, file contents, unrelated row fields, JWTs, tokens, or service credentials.

Commit contains no report generation, alert persistence, notification table write, APNs call, or external AI invocation. Its response explicitly reports all automatic-action flags false.

## 24–26. Swift and staff UI

- File importer allows CSV/TSV UTTypes and rechecks extension.
- Security-scoped access is started and always released; file size is checked before and after mapped read.
- Upload/validation/commit state is visible, duplicate taps are blocked, primary tasks can be canceled, and cancellation invalidates the context token.
- Organization/user change and disappearance cancel work and clear job, upload target response, file-derived state, preview, history, mappings, errors, and commit guard.
- Every awaited mutation is stored only after token revalidation; provider changes issue a new nonce.
- Mapping shape is explicit. Any draft change invalidates preview. Resolution revalidates server-side.
- Preview states no import occurred, uses backend totals, caps rows/errors, and filters display only.
- Commit requires an alert confirmation and a one-shot guard; partial completion state is preserved.
- Multi-player resolution displays only server-returned authorized candidates and sends the exact server-issued source key.
- Navigation is visible only for active owner/admin/coach membership. Backend JWT/org/player checks remain authoritative if UI is bypassed.

## 27. RLS, grants, and functions

All five relevant tables have RLS enabled. There are SELECT policies only for authenticated users; no direct authenticated INSERT/UPDATE/DELETE policy exists. `PUBLIC` and `anon` have no table grants.

Internal scope/lifecycle/metric trigger functions are SECURITY DEFINER with empty search paths and have EXECUTE revoked from public, anon, authenticated, and service role. The two Phase 11A authenticated policy helpers are intentionally executable by authenticated users and return authorization booleans; their underlying actor helper is not executable.

Policies use schema-qualified tables and hardened helpers. The row-error policy's job lookup follows the job policy direction and does not recurse back into row errors. Service-role privileges are the minimum used by this Edge workflow: job/mapping/external identity select+insert/update, row-error select+insert/delete, observation select+insert.

## 28. Runtime readiness evidence

- `supabase migration list`: local and remote match through `20260715060000`; exactly `20260715070000` is pending.
- `supabase db push --dry-run`: would push only `20260715070000_player_development_data_imports.sql`; no migration was applied.
- Deno format/check: pass.
- Focused parser/import tests: 24/24 pass.
- Full Deno suite: 266/266 pass.
- Focused Swift import suite: pass.
- Full Swift suite: 162/162 pass (0 failed, 0 skipped).
- iOS Simulator Debug build: pass.
- macOS Debug build: pass.

No deploy, migration apply, upload, live import, secret operation, AI call, notification, APNs call, or git mutation was performed.
