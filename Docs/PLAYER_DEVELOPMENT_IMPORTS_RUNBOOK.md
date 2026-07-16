# Player Development Imports Runbook

## Deployment order (do not perform from this implementation task)

1. Confirm `20260715070000_player_development_data_imports.sql` is already applied.
2. Review and apply `20260715080000_player_development_vendor_adapters.sql`.
3. Verify schema, constraints, RLS, grants, private bucket, and Storage policies using the SQL below.
4. Deploy only `player-development-imports`; confirm JWT verification is enabled.
5. Install the regenerated app and run the controlled sanitized-fixture validation plans.

## Phase 11B.1 HTTP 409 correction

Read-only live logs showed the failure at `create_job`; a scoped query confirmed no job row was inserted. The safe Edge response was the `job_create_failed` 409 path. The applied storage identity constraint used `\\.` inside a standard PostgreSQL string, which matches a literal backslash plus any character instead of the dot in `<uuid>.csv`/`.tsv`. Migration `20260715080000` replaces that constraint with `\.` and validates it. The function also lowercases every UUID component when constructing the path.

Swift now decodes both the nested `{ "error": { "code", "message" } }` Edge envelope and the legacy flat envelope, and displays `[stable_code] readable message`. Active/completed/idempotency/lifecycle conflicts retain their uniqueness and transition checks and expose resume/view/refresh-oriented recovery instead of a bare HTTP status.

## Post-apply SQL verification

```sql
select version from supabase_migrations.schema_migrations order by version desc limit 3;
select tablename, rowsecurity from pg_tables where schemaname = 'public' and tablename like 'sd_development_import%';
select policyname, schemaname, tablename, roles, cmd from pg_policies
where (schemaname = 'public' and tablename like 'sd_development_import%')
   or (schemaname = 'storage' and tablename = 'objects' and policyname like 'player_development_import%');
select id, public, file_size_limit, allowed_mime_types from storage.buckets where id = 'player-development-imports';
select conname, convalidated from pg_constraint
where conrelid in ('public.sd_development_import_jobs'::regclass,
  'public.sd_player_metric_observations'::regclass,
  'public.sd_development_import_mapping_profiles'::regclass,
  'public.sd_development_external_player_identities'::regclass,
  'public.sd_development_import_row_errors'::regclass);
select grantee, table_name, privilege_type from information_schema.role_table_grants
where table_schema = 'public' and table_name like 'sd_development_import%';
```

Supported input is UTF-8 or UTF-8 BOM `.csv`/`.tsv`, at most 10 MiB, 50,000 data rows, 250 columns, and 256 KiB per logical line. XLS/XLSX must be exported as CSV. Comma/tab detection, quoted delimiters, escaped quotes, CRLF, and blank rows are supported; missing/duplicate headers and other encodings fail safely.

Preview is read-only. Commit repeats actor, membership, player, job, object, digest, parser, mapping, active metric, player match, date, unit, duplicate, and idempotency checks. Accepted observations retain original and normalized provenance as device-imported/unverified. Any rejected rows produce `completed_with_errors`; sanitized errors remain organization scoped after archival.

Retention target is 30 days after job creation and 7 days after archival. No automatic deletion task is installed in 11B.1; operations must review and implement a service-role cleanup worker before relying on automatic retention. Never delete audit rows or imported observations as part of object cleanup.

## Controlled manual validation (provide, do not execute here)

1. Apply `20260715080000_player_development_vendor_adapters.sql` after the already-applied Phase 11B.1 migration.
2. Run the post-apply SQL above and verify tables, constraints, RLS, grants, the private bucket, and Storage policies.
3. Deploy only `player-development-imports` with JWT verification enabled.
4. Install the regenerated app.
5. Select one controlled test organization.
6. Select one controlled test player in that organization.
7. First upload the sanitized Rapsodo hitting fixture, confirm high-confidence detection, time zone, player candidate, mappings, ignored columns, and sensitive-field exclusion.
8. Repeat with sanitized Rapsodo pitching and confirm GPS/device/matrix fields never display or persist and ambiguous movement fields remain unsupported.
9. Upload sanitized TrackMan radar data twice: confirm Imperial and Metric unit selection produce the documented conversions and invalidate an older preview when changed.
10. Exercise Generic CSV fallback with a materially changed signature.
11. Review the normalized dry-run preview and its accepted/rejected totals.
12. Query the scoped observations and confirm the job has written none before commit.
13. Explicitly confirm the import.
14. Confirm accepted canonical observations and their complete import provenance.
15. Reupload the exact same file with the same mapping.
16. Confirm the retry creates no duplicate observations.
17. Upload a synthetic file containing one invalid row.
18. Confirm accepted rows persist and the job becomes `completed_with_errors` with a sanitized row error.
19. Exercise an ambiguous player row, resolve it manually, and revalidate.
20. Save, reuse, reject on header mismatch, and archive a mapping profile.
21. Manually generate a new Phase 11A report for the controlled player.
22. Confirm imported metrics appear as provider/job-sourced, device-imported/unverified evidence.
23. Confirm original and normalized values/units plus the observation date appear without a Storage path or raw row.
24. Confirm no report, alert, notification, or APNs action occurred automatically.
25. Test owner, admin, scoped coach, parent, player, unrelated user, inactive user, and platform-only admin authorization, including cross-organization IDs and paths.
26. Switch organizations and users during upload/preview; confirm cancellation, state clearing, and stale-response rejection.
27. Run the complete post-apply SQL diagnostics, backend tests, Swift tests, and both platform builds again.

## Rollback

Stop uploads and undeploy the import function first. Export audit data. Follow the migration header’s manual reverse order; never delete imported observations or retained error history without explicit data-governance approval. Phase 11A remains compatible because its original columns and lifecycle values are preserved.

Deferred: HitTrax activation pending a real sanitized fixture, authoritative email/birth-year matching, scheduled object cleanup, staff verification workflow, and custom metric-definition review.
