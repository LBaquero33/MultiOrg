# Player Development Imports Data Audit

## Scope and repository state

This audit was completed before Phase 11B.1 schema, parser, or UI work. The latest migration in repository order is `20260715060000_player_development_ai_foundation.sql`; the next additive timestamp is therefore `20260715070000`. The Phase 11A migration is treated as immutable. The worktree already contains unrelated Phase 11A, chat, notification, and project-generation changes; Phase 11B.1 must not discard or rewrite those changes.

## Reusable objects

- `public.sd_development_import_jobs` is the correct job identity and audit root. It already enforces organization, optional player scope, staff requester scope, lifecycle counts, timestamps, and actor-scoped idempotency.
- `public.sd_player_metric_observations` is the canonical destination. It already enforces organization/player/import-job scope and stable source uniqueness, and Phase 11A reads it directly.
- `public.sd_development_metric_definitions` contains the 38 provider-neutral canonical definitions, status, unit, category, direction, and minimum sample guidance.
- `public.sd_is_org_staff(uuid)` and `public.sd_can_manage_team_player(uuid, uuid)` are the hardened RLS helpers. The Player Development AI Edge Function additionally resolves an authenticated JWT, checks active owner/admin/coach membership, and computes coach-authorized players before using the service role.
- `public.sd_org_usernames` provides exact organization-scoped usernames. `public.sd_org_memberships`, `public.sd_team_members`, and `public.profiles` provide active membership, team scope, and display names.
- Phase 11A's metric-observation evidence adapter already exposes normalized observations without generating reports, alerts, notifications, or pushes. It preserves `source_system` and demo metadata.
- Supabase Swift already supports authenticated Edge Function calls and Storage upload. Existing avatar and organization-asset uploads demonstrate the installed SDK API, but both return public URLs and are not suitable for import files.
- `HomePlate/Core/CSV.swift` handles quoted comma fields and contains a legacy provider mapper. It is useful only as historical input; its ISO-Latin-1 fallback, unbounded parsing, guessed aliases, and filename/provider behavior are unsafe for canonical imports.

## Existing schema limitations

`sd_development_import_jobs` lacks file type, digest, size, private object identity, parser/mapping versions, mapping fingerprint/configuration, unmatched and warning counts, validation summary, and the inspection/validation lifecycle states. Its existing status constraint must be replaced additively while retaining every valid Phase 11A state.

`sd_player_metric_observations` has a single `unit` column and does not separately expose original and canonical units, conversion provenance, import parser/mapping versions, source row number/string date/time zone, or an explicit verification state. New nullable/defaulted columns can preserve existing rows and synthetic demo provenance unchanged.

No safe tables currently exist for organization-scoped mapping profiles, external player identities, or bounded row errors. Complete source files must not be stored in PostgreSQL.

Profiles do not contain birth year or email. Email matching can only be performed by a trusted backend against organization members and Auth metadata where policy permits; it must not be added as an unscoped client query. Birth-year matching remains unavailable until a reviewed organization-scoped birth-year source exists. Exact username, external ID, and unique normalized full name are safe today.

## Storage and upload options

The project has Storage enabled. `avatars` and `org-assets` are public-URL flows and cannot be reused for private performance files. Phase 11B.1 should create a private `player-development-imports` bucket with a 10 MiB object limit and CSV/TSV MIME allow-list. Object names use `<org UUID>/<job UUID>/<unpredictable file UUID>.<csv|tsv>`; authorization derives from the organization and job records, never the display filename. Authenticated staff may upload/read only an object for a scoped job; normal client delete is denied so audit input remains immutable. The service-role Edge Function downloads and re-hashes the authoritative object for inspection, preview, and commit.

Retention should default to 30 days after completion and 7 days after archival, with deletion performed by a separately reviewed service task. Archiving a job does not erase row-error or observation audit history.

## Existing provider and import code

- `coach_import_bp` accepts client-supplied normalized JSON, checks only global profile role, has no organization scope, replaces events destructively, returns raw database error messages, and trusts the client parser. It is an unsafe legacy path and must not be exposed or extended for Phase 11B.1.
- `BPImportMapper` guesses Rapsodo, HitTrax, and TrackMan schemas from aliases and accepts ISO-Latin-1. No real provider fixtures establish those guesses as production contracts.
- `20260710100500_trackman_bp_source.sql` only extends a BP source enum; it is not a generic import architecture.
- No validated Rapsodo or HitTrax fixture exports are present. Those provider adapters remain inactive; staff can select their label but must use Generic CSV manual mapping.

## Authorization conventions

Every Edge Function action must authenticate with `auth.getUser`, require an active organization membership with role owner/admin/coach, and calculate coach player scope. A platform administrator without that membership is denied. IDs, object paths, and mapping IDs convey no authority. Authenticated clients get read-only RLS access to job/profile/error history and narrowly scoped Storage access; all lifecycle and canonical-data writes occur through a service-role backend which repeats authorization.

## Data-quality risks

- Provider identity, player identity, units, dates, and metrics are all unsafe to infer from filenames or numeric magnitude.
- Duplicate/blank headers, embedded delimiters, BOMs, ambiguous U.S. dates, future timestamps, unknown units, inactive players, and repeated files can silently corrupt evidence if not blocked.
- Client-generated preview results are mutable and cannot be commit input.
- Free-form context can leak private notes or spreadsheet contents. Only mapped, bounded scalar context values may be retained.
- Existing evidence currently displays one unit. Phase 11B.1 must add safe original/canonical metadata without changing synthetic demo labels.

## Recommended Phase 11B.1 architecture

1. Create a job through `player-development-imports`; the server allocates an unpredictable organization/job-scoped Storage path.
2. Swift uploads UTF-8 CSV/TSV bytes to the private bucket, then requests inspection.
3. The Edge Function downloads, bounds, decodes, hashes, parses, and records only inspection metadata.
4. Staff selects wide/long shape and supplies explicit player/date/metric/unit/context mappings. Saved profiles are reused only on an exact normalized-header fingerprint.
5. The backend performs organization-scoped exact matching, explicit unit/date validation, duplicate checks, and a dry-run preview. No observation writes occur.
6. Commit re-downloads and re-hashes the object, re-runs the same parser and validation, locks/idempotently commits accepted rows through a service-role-only RPC, and persists bounded sanitized errors.
7. Observations become available to Phase 11A evidence immediately, marked `device_imported_unverified`. Report generation and alert detection remain explicit user actions.

The production adapter contract is provider-neutral, but only `generic_csv` is active until genuine sanitized provider exports and fixture-backed tests are supplied.
