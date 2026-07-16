# Player Development Imports Architecture

Phase 11B.1 adds one production parser, `generic_csv`, behind the separate authenticated `player-development-imports` Edge Function. Provider labels share the manual mapper; Rapsodo, HitTrax, TrackMan, Blast, Pocket Radar, and strength-testing auto-adapters are inactive pending real fixtures.

## Flow

1. `create_job` verifies the JWT, active organization staff membership, optional player scope, file extension, and provider. It creates `sd_development_import_jobs` and allocates `<org>/<job>/<random>.<csv|tsv>` in the private `player-development-imports` bucket.
2. Swift uploads directly with `upsert: false`. Storage RLS requires the organization/job path to match the job record.
3. `inspect_file` downloads the object with service-role Storage access, enforces 10 MiB/50,000 rows/250 columns/256 KiB line limits, strictly decodes UTF-8, parses CSV/TSV quoting, hashes the original bytes, and stores only inspection metadata.
4. `save_mapping` stores an explicit wide/long mapping and deterministic fingerprint. Named profiles require the exact normalized-header fingerprint to be reused.
5. `validate_job` re-downloads and re-hashes the object, performs exact player matching, active canonical metric checks, explicit date/unit conversion, duplicate detection, and persists bounded sanitized row errors. It writes no observations.
6. `commit_job` claims the job with an optimistic status transition, re-runs authoritative validation, inserts stable-id observations, and marks the job `completed` or `completed_with_errors`. Concurrent/repeated confirmation cannot create duplicate observations.

Lifecycle states preserve Phase 11A values and add `uploaded → inspecting → mapping_required → player_resolution_required → validating → ready → importing → completed`, plus `completed_with_errors`, `failed`, and `archived`.

Imported observations reuse `sd_player_metric_observations` and retain original value/unit, normalized value/canonical unit, conversion version, source row/date/time zone, parser/mapping versions, job/provider provenance, and `device_imported_unverified`. Phase 11A reads them immediately. Nothing automatically generates reports, detects alerts, or sends notifications.
