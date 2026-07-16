# Player Development Import Security

- Every action verifies the bearer token with Supabase Auth, then requires an active owner/admin/coach membership in the selected active organization. Platform-only administrators, parents, players, inactive members, and unrelated users are denied.
- Coach access follows the established team restriction when calculating eligible players. IDs and Storage paths grant no access.
- The Storage bucket is private. Insert/select policies validate organization and job path segments against `sd_development_import_jobs`; authenticated delete/update is absent. Display filenames are never authorization input.
- Clients cannot write import metadata, mappings, identities, row errors, or observations directly. Service-role writes happen only after repeated backend authorization.
- Preview data supplied by Swift is never accepted for commit. The backend re-downloads, re-hashes, re-parses, and revalidates the immutable object.
- Files, full rows, JWTs, Storage tokens, emails, secrets, raw database errors, and private notes are not logged. Row errors retain only bounded codes, labels, metric keys, and row numbers.
- Complete files are not stored in PostgreSQL. Default retention is 30 days after creation and 7 days after archival; cleanup requires a separately reviewed service process and must preserve audit rows.
- Stable observation identities, completed-file/mapping uniqueness, `upsert: false`, and optimistic job claiming provide idempotency. Failed finalization is surfaced for support review rather than hidden.

The legacy `coach_import_bp` function is not linked from this workspace because it lacks safe organization scope and trusts client-normalized input.
