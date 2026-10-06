# Supabase migration variant alignment — 2026-10-06

## Scope and decision

This note records alignment of seven local, untracked Native migration copies with the exact tracked versions in the primary Web checkout at commit `f057dbd` on `codex/public-facility-booking-links-20261002`. The Web versions were selected because they are the committed migration lineage; the Native versions had no Git history. The 2026-07-30 note in `Docs/SUPABASE_MIGRATION_RECONCILIATION.md` says the linked Home Plate project is `kbulbvngysflfhaqpvtv` and treats migrations as immutable. The Web local config has that project ID. Native's local `project_id` label is `DHD-Self-Development-iOS-multiorg`; it does not prove the active remote target, and no live target was checked here.

## Comparison evidence

All seven native copies were compared to the same-named file from Web `HEAD`. For all seven, the ordered nonblank lines are byte-identical; six files differ only by extra blank lines, and `20260824050000_registration_public_visibility_backfill.sql` was already byte-identical. A token comparison also found no difference while preserving SQL literals, quoted identifiers, and comments. No function, table, policy, trigger, grant, literal, or other SQL semantics changed. No forward migration is needed for these variants.

The Native migration directory has 115 filenames, all represented in Web's 179-file set; Web has 64 additional migration filenames. Only the seven listed variants were compared and aligned in this operation. The broader migration ledger and live applied state were not reconciled or verified.

The exact pre-alignment Native files are preserved under `Docs/migration-reconciliation/native-local-variants/`; that directory is an audit archive outside `supabase/migrations` and must not be applied. The seven top-level Native migration files now match Web byte-for-byte. No Web file or prior tracked migration history was edited. No SQL was executed, and no database, deployment, or push action occurred.

## File checksums

| Migration | Web source commit | Preserved Native SHA-256 | Aligned SHA-256 |
| --- | --- | --- | --- |
| `20260718185410_86fb60bd-cc9e-482c-85f9-3ee0bb7410f5.sql` | `574ecc4` | `c210811fa4269fe2045baebc4e102fb36f1e3f9ed06fc39e51637a60bb2aca38` | `b9c02a035cad73fa70bb68d7580d91cd4147089dbca417b483708af7c2a60914` |
| `20260823120000_public_website_builder.sql` | `0d45d2e` | `fa51d8588107ed7e6a9e9b84a1f4977cec67bf2ca1147b97fecac06b8d8e1334` | `83a1a9d11073e2059504f8e709e3c842f372d4463f7507d3057b2e6d7013cd19` |
| `20260823183000_website_builder_completion.sql` | `5abf6e8` | `d93619e2aac2d4fe01b5ff5541729fcb7801ad2482f3a9c153a585cc77f0889e` | `8c7421a2cc06ae8d144ad0a0e96801f6011adafcc1437feb7fcb87c0ebd3ffa2` |
| `20260823233000_website_ai_generation.sql` | `d00f922` | `b396b0fea37b3fa5428a1c1324067c2116e59e3dba79ae3e56ee1043be708a8d` | `3cd01fec90de4c36a511fcc910b6c0c5cacf6ce889d44ac0b771c34a812ff0a0` |
| `20260824020000_public_booking_authorization.sql` | `78292f0` | `847c712f9f3ae5aa273480f7774ef519b3f4354847a54053588f31dba1b25a7a` | `11d5f0583d2f131acf900405242414b80de9ff23bd5bd3825d33aae8259b12a1` |
| `20260824030000_website_builder_completion_pass.sql` | `78292f0` | `65573a41de7b5567fc12e2b1d275fa46a70fdbb6501d3c913824c32231abf4c7` | `ffe07937c215ca730ab8668ab744946225b793ada2321ee94904d4b5f697cf7d` |
| `20260824050000_registration_public_visibility_backfill.sql` | `de930c1` | `e1da54832a1758c2300135f94bc958540dca310e4f8464afb96ce427a59cb72b` | `e1da54832a1758c2300135f94bc958540dca310e4f8464afb96ce427a59cb72b` |
