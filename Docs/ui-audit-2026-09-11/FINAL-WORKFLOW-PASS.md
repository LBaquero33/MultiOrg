# iPhone workflow pass — September 11, 2026

Only Home Plate iPhone Simulator was used. iPad remains deleted; DHD remains shut down. No App Store Connect upload.

## Reproduced and fixed

Authenticated appointment reads failed with PostgreSQL RLS infinite recursion. The appointment SELECT policy read participants, whose ALL policy read appointments again. Migration `20260911221500_training_appointment_read_recursion` replaces only the cyclic participant predicate with a fixed-search-path, actor-bound security-definer helper. Existing admin, trainer, front-desk and athlete authorization predicates remain in place.

The migration was applied to the linked Home Plate backend only after owner-read and outsider-denial assertions passed in the same transaction. Separate transactional tests then confirmed player access to their own appointment, linked-parent access, and unrelated-user denial; test family/athlete records were rolled back.

## Live checks

- Account profile and pending-request reads passed nine times across three runs. The historical gateway timeout did not reproduce; its upstream cause is unknown. The earlier inline retry/duplicate-alert correction remains installed.
- Synthetic booking creation, read-back, stable retry ID, conflict rejection, cancellation and cancelled-state read-back passed after the policy fix. All appointments created by this check were cancelled. No charges or external notifications.
- Service-price save/read-back/restore and in-form Save/Cancel were verified in the preceding pass.
- Fresh native scoring integration passed against QA game `2d33d197-87e7-4b5e-ac9b-a0bf83018a66`: 132 locally persisted/reloaded commands, injected transport loss, reconnect, duplicate replay, exact remote event identity and final score assertions. Runtime 508.7 seconds. Evidence: `/tmp/homeplate-scoring-20260911-passed.log`.
- Native TXT/MP4 integration passed: rename validation, injected upload failure, retry with stable upload identity, duplicate message retry, one attachment per message, signed download byte hashes and AVFoundation playability/duration. Runtime 4.7 seconds. Evidence: `/tmp/homeplate-media-20260911-passed.log`. Private QA channel `e5ab3f1f-11ff-4ea4-b16e-ac9726bed446` has only the current owner as a member. No third-party messages.

## Regression scope

The initial broad run executed 93 XCTest cases with one explicit skip and no failures, while 435 Swift Testing cases exposed stale source/title expectations (15 issues). Those expectations were updated to the approved Programs/Library labels, adaptive layout and canonical schedule wording; routing and privacy checks remain. The final rerun PASSED: 435 Swift Testing cases and 93 XCTest cases (one explicit skip, no failures). Log: `/tmp/homeplate-full-iphone-final.log`; xcresult: `Test-HomePlate-2026.09.11_18-11-16--0400.xcresult` in the current DerivedData Logs/Test directory.

Read-only media verification separately confirmed two attachments, preserved original/display filename metadata, exactly one recipient (current owner), and anonymous access denial.

The explicit StoreKit skip requires the separate HomePlateStoreKitAudit scheme; this pass did not enable local commerce or initiate purchases.

## Final session recovery

The final interactive Home check exposed a QA harness issue: temporary integration credentials were being written into the app's normal Keychain store, then invalidated by test cleanup. Console diagnostics showed `401 invalid_auth`; a focused native live-workspace decoding test passed, ruling out the suspected appointment response decoding problem. The user's authorized sign-in was restored, and Home loaded. SupabaseService now accepts an optional auth storage dependency (production retains its existing Keychain default); all live integration services use a locked in-memory store. This prevents future test runs from replacing the user's saved session. The updated test build passed; the isolated live workspace test passed again, followed by relaunch and visual confirmation that the saved login survived and Home loaded without error. Evidence: `/tmp/homeplate-isolated-auth-workspace-passed.log`.

Final screenshots: [healthy Home](after/iphone-home-session-verified.jpg), [native media message](after/iphone-live-media-verified.jpg).

## QA fixture notes

The historical QA owner lost membership during organization consolidation. No removed membership was restored. Provisioning now checks active owner membership before creating fixtures, and can explicitly use the already-authorized current owner in the isolated QA organization. The first failed attempt left a named QA season/team/event; that event (`409415cd-2e32-476c-8689-f26f68872673`) was cancelled, with its records retained as audit evidence. No customer records were changed by provisioning.

This report separates API/native integration checks from interactive UI and physical-device acceptance. It does not claim a physical airplane-mode trial or every authenticated player/parent screen was exercised.
