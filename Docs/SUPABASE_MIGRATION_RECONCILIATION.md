# Supabase Migration Reconciliation

## Scope

- Linked Supabase project: `kbulbvngysflfhaqpvtv`
- Reconciliation date: 2026-07-30
- Source branch: `feature/game-calendar-live-scoring`
- Source commit before reconciliation: `adae6b11b5f368c27f3e941506d64c37b330b678`

The linked migration ledger contained 18 timestamps that were not represented in
the repository. Their SQL was recovered with `supabase migration fetch --linked`
inside a disposable detached Git worktree. The fetch also rewrote comments in
older local migrations; those unrelated rewrites were discarded. Only the 18
missing, remotely applied files were imported.

No migration repair, squash, linked reset, or placeholder migration was used.
All recovered files contain SQL, no timestamp collision was found, and none of
the recovered SQL was manually edited.

## Recovered Remote Migrations

| Timestamp | Imported filename | SHA-256 |
| --- | --- | --- |
| `20260717153000` | `20260717153000_player_development_copilot_feature_flag.sql` | `3a600e938d544313aa49d81bf0d1350345ec1184fc55df6fb263b39cd544cb4f` |
| `20260717170000` | `20260717170000_team_operations_foundation.sql` | `20a8b5f384c0c4c3672ba3a9021ce3e8ba393192a160598db51b56eaec58ef28` |
| `20260717183000` | `20260717183000_unified_team_scheduling.sql` | `8820225fb4176d604c764f763988972e70db2918aa2ffb681ac8fa76cc5e1621` |
| `20260717200000` | `20260717200000_baseball_day_operations.sql` | `73b2daa1e330bf8abe7be05df5bf1268aacfe773d2a5064134dbb5ce5d83c4d0` |
| `20260717220000` | `20260717220000_complete_practice_planner.sql` | `fbd693f529905320c4a1d34818b55eb6812f2b75c0bc3c06126451a8fe623eba` |
| `20260718000000` | `20260718000000_complete_game_operations.sql` | `3ea7cb2158706acd0e82df5e9e3d44f8ff653efa963cd61376fea54af28c5df4` |
| `20260718100000` | `20260718100000_organization_communication.sql` | `ebb023b0add85aaf20870e2b33ec08b3c6243087db219091742186948732a697` |
| `20260718110000` | `20260718110000_registration_season_lifecycle.sql` | `ce073bccf006f8effe8816f733a9297c4db6e0af5fa23f9fc59172f984065ec1` |
| `20260718120000` | `20260718120000_organization_business_operations.sql` | `15782a620f400bdd99834749a271c7805b048cc51f2990504630ca940f062857` |
| `20260718130000` | `20260718130000_organization_analytics.sql` | `155f2b0daeab55fa24fe6fd0f31906dea7b8f6413db239d2ef64e2d9f090a74d` |
| `20260718140000` | `20260718140000_phase12_migration_execution_repairs.sql` | `d67406baebcde3fa5c0ccefb9ae51462f746c616d1f00e42bc5c4bfee5022ae0` |
| `20260718150000` | `20260718150000_phase12_game_mutation_execution_repair.sql` | `90330ef71e80ff0bb7d905df7eb6e8bbc451560bdf0250113d6832d18087330e` |
| `20260718153000` | `20260718153000_phase_12zb_team_unassignment.sql` | `f0c127f84c1abc6059dadd5dd82c1092ceb4a97209b9cb9e0199d3d3059e1d7f` |
| `20260718160000` | `20260718160000_complete_organization_setup.sql` | `b15416f67e59445bfd5e612dca64f083a17fa51262ff7d5718946398e0916c65` |
| `20260718170000` | `20260718170000_setup_invitation_links.sql` | `bc72a87a2dbe7bb8aa9323b1f4f74e668fa556756f003eca579e8baf81608705` |
| `20260718171000` | `20260718171000_repair_setup_practice_subtypes.sql` | `a56bedcf6eb7e1c9c7725c21561512da1462e6d35db5a711cbb23ecd51780bbb` |
| `20260721050000` | `20260721050000_schedule_event_notifications.sql` | `6532fbe36993cb12a21ad1ef3c6962369d817d89e6ceca452fd0f8c924d07af6` |
| `20260721060000` | `20260721060000_schedule_event_delete.sql` | `d35cb6d14e573f75f0a3e651711ba3ef4098bfd08ba0d7377241ba5e26e29ba3` |

The recovered migrations predate the July 29 game/calendar series and now align
exactly by timestamp with the linked remote ledger.

## Compatibility Repair

Strict local lint identified an ambiguous PL/pgSQL variable/column reference in
the remotely applied `sd_process_event_reminders` function. Historical SQL was
left unchanged. Additive migration
`20260729120000_repair_event_reminder_deduplication_lint.sql` recreates the
function with the local variable renamed to `v_deduplication_key`; behavior and
permissions are otherwise preserved.

Concurrent scorekeeping validation then reproduced a lock-order deadlock between
scorekeeper-control transfer and scoring-event append. Historical SQL was again
left unchanged. Additive migration
`20260729130000_fix_scorekeeping_transfer_lock_order.sql` makes transfer lock the
game before the scorekeeper session, matching the append path. Lease ownership,
token checks, permissions, and result semantics are preserved.

## Local-Only Deployment Delta

`supabase db push --dry-run` proposes exactly:

1. `20260729010000_game_events_foundation.sql`
2. `20260729020000_game_calendar_integration.sql`
3. `20260729030000_game_rulesets.sql`
4. `20260729040000_game_scoring_ledger.sql`
5. `20260729050000_game_scorekeeper_sessions.sql`
6. `20260729060000_game_official_scoring.sql`
7. `20260729070000_game_finalization_and_audit.sql`
8. `20260729080000_predeploy_lint_repairs.sql`
9. `20260729090000_restore_game_calendar_notification_categories.sql`
10. `20260729100000_align_game_notification_validation.sql`
11. `20260729110000_allow_linked_parents_to_view_team_games.sql`
12. `20260729120000_repair_event_reminder_deduplication_lint.sql`
13. `20260729130000_fix_scorekeeping_transfer_lock_order.sql`

None of the 18 recovered remote migrations would be reapplied.

## Verification

- Clean local reset 1: pass
- Clean local reset 2: pass
- `supabase db lint --local --level error --fail-on error`: pass
- `supabase test db`: pass, 42 assertions
- Realtime/concurrency integration: pass twice, including 25 simultaneous lease races
- Linked migration list: all previously remote-only timestamps aligned
- Timestamp collisions: none
- Recovered SQL unavailable: none
