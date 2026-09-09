# Audit closeout engineering verification

September 8, 2026 (EDT). This supersedes the native implementation gaps in the earlier nine-area checkpoint, not its release limitations.

## Implemented and exercised

- Native training catalog: edit services; replace a trainer's offerings while retaining prices, locations and resource restrictions; create/edit versioned packages. Uncertain writes require a refresh, and organization/account changes dismiss editors. Package edits cannot rewrite issued credit terms.
- Schema-2 native scoring: canonical saved lineup, organization rules snapshot, account/org/game/device-bound durable signed journal, exact retry and receipt acceptance, no silent rebase, permission failures pause scoring. Recovery export excludes signing keys and bearer/control tokens. Local rules remain bound to the saved journal.
- Schema-2 reports read the schema-2 ledger rather than the legacy reducer. Reads are cursor-paginated and reject sequence gaps. Reports label derived statistics provisional. Official schema-2 postgame certification remains a web workflow.
- Imported scoring core/store/UI from the existing Game Hub worktree (`bdf6ed0`, scoring integration ancestry `5fdc0e3`); production controller and transport were replaced/hardened rather than merged wholesale. Unused ScoringLabRootView is excluded from package compilation.
- StoreKit configuration corrected and a separate opt-in local commerce test scheme added. Production test runs do not silently enable local purchases.

## Evidence

- Full native app suite: 428 Swift Testing tests passed, plus 92 XCTest tests passed; two explicit environment-gated tests skipped (live QA and StoreKit). `/tmp/homeplate-closeout-native-full.log`.
- Scoring package: 32 tests passed. `/tmp/homeplate-closeout-package-tests.log`. Only its freshly generated scratch build cache was cleaned afterward; source and logs retained.
- Live signed scoring against guarded QA organization `00000000-0000-4000-8000-0000000000aa`: game `f13f34cc-adc1-4d8d-b64b-a909774cc1d8`, three local commands, accepted and retried without duplicate events.
- Extended live QA: game `11ef6a01-409f-4d9c-a447-6cb751ec44e5`, nine local commands covering a walk, two-run home run, and strikeout. Every command and duplicate accepted; replay verified 2 runs, 1 hit, 1 out and a reset pitch count. `/tmp/homeplate-native-live-scoring.log`. An earlier fixture deliberately remains separate: its single without runner advancement failed locally with `destinationOccupied` before synchronization; corrected fixture uses explicit automatic home-run advancement.
- Cross-language fixture verifies native projection/statistics/envelope/journal hashes and P-256 signatures in the web test suite. Fixed locale-aware key ordering based on this test.
- WAR Performance was not a mutation target. Live role canaries confirmed unchanged organization/membership hashes and three retained memberships during their run.

## Release boundaries and open acceptance

These native changes are source/simulator/live-QA verified, **not included in uploaded build 5**. Build 5 was processed by Apple but shows Missing Compliance; the pending App Review submission still contains build 4. No compliance declaration was submitted and no review submission was replaced.

Local StoreKit product discovery succeeded, but simulated purchase failed with `notEntitled` in both existing and freshly created simulators. This is a failed purchase test, not purchase/restore acceptance. Real Apple sandbox purchase and restore remain release gates.

No new archive was attempted after disk availability fell below 250 MB. Preserve prior signed archives; make sufficient disk space before a new signed build. Actual recovery-email delivery also awaits a dedicated inbox supplied by the owner. Exhaustive physical-device/VoiceOver checks, all role/archetype UI permutations, and official native schema-2 postgame certification are not claimed complete.
