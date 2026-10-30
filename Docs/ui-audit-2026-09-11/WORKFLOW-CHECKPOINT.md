# iPhone workflow checkpoint — September 11

- Only Home Plate iPhone Simulator is booted. Home Plate iPad was deleted at user request; DHD is shut down.
- Service editor now has labeled in-form save/cancel actions with stable accessibility identifiers, reachable without the missing Simulator toolbar controls.
- Live iPhone test: changed nonpublic QA Surface Hitting Session price from blank/default to 12.34; saved, reopened, verified 12.34. Cleared, saved, reopened, verified Use default. Cancel action also exercised. No payment transaction.
- Account loaded successfully and profile Refresh returned without a modal timeout. The prior gateway timeout was not reproduced; server root cause remains unknown.
- Coach parent-request load failure no longer raises both inline retry state and a modal alert. Cancellation does not display a load error. Mutation errors retain their alerts.
- Fifteen targeted tests passed: TrainingCatalogTests, NativeScoringV2JournalTests, PlayerDevelopmentWorkspaceContractTests. Log: /tmp/homeplate-workflow-tests.log. Final action-placement build succeeded: /tmp/homeplate-workflow-final.log. This is not live reconnect acceptance.
- Booking form opened with QA athlete/service/trainer/location selectors; no new reservation was submitted.
- New live upload/message sends and end-to-end offline/reconnect rerun remain open. Historical acceptance in BUILD12_SIMULATOR_CHECKPOINT.md is not claimed as a new run.
- No production deployment, IPA, or App Store Connect upload.
