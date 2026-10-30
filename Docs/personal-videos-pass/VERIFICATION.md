# Personal Videos and immediate-fix pass

Updated September 12, 2026. This is a partial acceptance record, not a declaration that every requested workflow has passed.

## Implemented

- Web and native player-development Videos destination aggregates existing workout-set, testing-field and hitting/pitching-session footage plus direct personal uploads. No original video objects were moved or duplicated.
- Thumbnail cards, activity date, category, title search, category/date filters and newest-first ordering; signed playback and optional original-day navigation.
- Staff/player direct upload: confirm-or-edit naming, captured player/date/category, stable upload UUID and exact-record reconciliation after a lost acknowledgement. Parents have read-only access to authorized linked children. Unrelated chat media is excluded.
- iPhone supports Photos and Files selection; player Today and parent child list have video shortcuts. Existing assignments and workout execution remain intact. No new program-folder/template work was added in this pass.
- Web profile deep-link close no longer immediately reopens the profile. Archived organizations are excluded from web sign-in/context selection. Native selected organization is remembered per user and validated against current memberships before reuse.
- Simulator Keychain entitlement corrected; signed-in app reopened without credential re-entry.
- Web media validation now times out after 15 seconds rather than waiting indefinitely for metadata. Playback network errors are surfaced. CEO finance refresh failures are surfaced rather than silently treated as missing reports; imported proceeds are no longer described as settled bank payouts.

## Verified this pass

- Authenticated web, Ryan Sullivan / Plate Team: three existing session videos, actual rendered thumbnails, Pitching filter returns two, playback reaches the end of the three-second fixture. Original-day link opens the August 22 activities and media.
- Authenticated web, Jackson Sullivan / Plate Team: no-footage state with authorized upload control; a fixture for this same player in the isolated QA organization does not appear in Plate Team.
- iPhone Simulator: Ryan's three existing videos, category labels, upload disclosure, native playback showing the recorded action. Screenshots accompany this report.
- Native organization switching Facility to Team loads the correct 9U home and its three upcoming events. Sign-in survived reinstall/relaunch.
- Live backend rolled-back role tests: staff/player/linked-parent read; parent upload denied; outsider metadata/media/upload denied; duplicate entries rejected.
- Live isolated QA upload: real MP4 bytes uploaded, storage duplicate rejected, duplicate metadata rejected, exactly one library row, signed playback download SHA-256 matches source, anonymous signing denied. One synthetic fixture remains in the QA organization; no messages sent and no original media changed.
- Web suite: 303 tests across 64 files; TypeScript checks for web and CEO passed. Final native analytics/authorization/finance tests passed: 22 test definitions / 36 parameterized executions, zero failures or skips. Final result: Test-HomePlate-2026.09.12_00-05-42--0400.xcresult. Targeted ESLint and both repository diff checks passed.

## Still open / not certified

- Full UI selection/rename/upload/forced-disconnect/retry on both clients. Chrome's file-chooser automation rejected setFiles with `Not allowed`; actual upload and idempotency were independently tested through an authenticated API client. Photos selection was added to native but has not completed its final end-to-end upload walkthrough.
- Complete authenticated player/parent home walkthrough and populated R-analysis destination check. Native R links include organization, player or athlete, and optional start/end date in source; this is not a completed live destination acceptance check.
- Fresh booking/service-price/facility-hours/paid-access/credit-removal regression walkthrough. Prior pass evidence exists in ../ui-audit-2026-09-11/FINAL-WORKFLOW-PASS.md and is not counted as fresh UI verification here.
- Facility athlete records without linked player accounts still use the existing facility media timeline, not the new direct personal-upload table.
- Finance review found remaining reconciliation work: Apple currently imports monthly Sales and Trends reports when Finance opens, not confirmed bank settlements; no Apple background cron was found. Currency-mismatch rows, refund commission reversal, and changed-report replacement require further backend work. Do not treat the combined total as fully reconciled cash or the gross/proceeds difference as an authoritative commission-only percentage.

## Deployment

- Live Home Plate backend only: migrations 20260912010000 and 20260912011000 applied and recorded. WAR Performance untouched.
- Web changes tested locally at http://127.0.0.1:8080, not deployed to production.
- Native changes built and installed only on the iPhone Simulator. No iPad created. No physical-device installation, IPA export, App Store Connect upload or App Store release in this pass.

## Screenshots

- web-player-videos.png — populated library with real existing footage.
- web-empty-player.png — Jackson Sullivan's empty library.
- iphone-player-videos.png — native Videos and upload control.
- iphone-playback.png — existing footage playing in the native player.

## Follow-up: actual iPhone Simulator check, September 12

Result: NOT a complete acceptance pass. No source changes or deployments made during this follow-up.

- PASS: Plate Team / 9U selection and player-development navigation to Ryan Sullivan's Videos.
- PASS: existing three videos and category labels load. Native playback displays the recorded action; fresh evidence is iphone-simulator-recheck-playback.png.
- PASS: Open original day reaches August 22, with hitting and bullpen activities plus both media records marked Ready and Play video controls.
- PASS: after restarting the Simulator UI and relaunching Home Plate, the existing account and selected Plate Team / 9U restore without entering credentials. A sign-in view appears briefly while restoration loads, then Home opens.
- PARTIAL: Photos picker opens and displays two synthetic three-second clips. The control service repeatedly rejects selection taps with noWindowsAvailable, including after restarting the Simulator application. No rename/upload success is claimed and no additional cloud video was uploaded in this follow-up.
- FAIL: on the second library visit, a request failed and the UI simultaneously displayed an error and No videos yet. Load more recovered the three videos, but the Upload a video control remained hidden after its separate permission request failed. Permission-loading errors need a visible retry; they must not be treated as a definitive lack of permission.
- PARTIAL: R Analysis for this day opens the correct native Ryan Sullivan report handoff, then launches the website in Simulator Safari. The observed address is https://www.homeplateapps.com/signin. Preservation of the selected player/date through web authentication is not verified.
- NOT RUN: completed direct upload/name confirmation, forced-upload-failure retry, player/parent-role UI tests, and the remaining booking/payment workflows. Earlier API/unit results are not substitutes for these UI checks.

## Recovery repair, September 12

- Native permission checks now distinguish allowed, denied, and unavailable. A failed check exposes Retry upload access and retries when the app becomes active. Upload context is keyed to organization, player, and actor.
- Native library errors expose Retry loading videos, suppress the incorrect empty-library message, and do not misleadingly offer pagination as the error recovery action.
- Web permission-check errors now expose an equivalent retry instead of hiding the upload control.
- Added native regression tests for transport failure, retry to allowed, and explicit denial. These test the same permission-resolution function used by the view.
- R handoff inspection found an existing session-storage return mechanism in the web app: the analysis route stores the requested URL, and sign-in uses safeAnalysisReturn before restoring it. Seeing /signin alone therefore does not prove context loss; end-to-end authentication acceptance remains open.
- The rebuilt app loaded Ryan's library and displayed the upload control. Apple Photos picker again displayed the synthetic clips, but both bundle-ID and display-name coordinate taps failed with noWindowsAvailable. This is a tool-control blocker, not a passed upload test. Do not replace this missing result with the successful API upload result.
- Final recovery regression results: web TypeScript and 303 tests passed; native OrganizationAuthorizationTests passed 15 test definitions / 29 parameterized executions with zero failures or skips, including the new permission failure/retry tests. Result bundle: Test-HomePlate-2026.09.12_00-24-21--0400.xcresult. Corrected build reinstalled on the iPhone Simulator. No web production deploy or Apple upload.

## After manual Photos selection

- User selected the synthetic clip. The app returned to Videos with “Video preparation was cancelled or failed.” No upload completed.
- Removed the personal-library path's timing-dependent global UIKit naming alert. The selected bytes are now prepared and retained in view state, with an inline required name field and Confirm name and upload action. Invalid names retain the selected bytes; upload retries retain the committed UUID and metadata.
- Preparation errors now include the underlying description instead of merging every failure with cancellation. Successful preparation clears the old error.
- Naming-recovery build passed and was installed on the same iPhone Simulator. This is not yet an end-to-end upload pass; the rebuilt app requires a fresh selection.

## Final immediate-fix acceptance, September 12

- PASS — latest iPhone controls: the player workspace now uses a compact plain close control, labeled `Assign program` action, one compact disclosure arrow, and plain 44-point calendar tap targets. On-screen evidence: `iphone-compact-player-controls.jpg`. Team, Facility, and Individual Trainer homes were also inspected; no matching oversized bordered X/plus/chevron controls were found.
- PASS — personal-video reliability: live rolled-back authorization/duplicate checks passed for staff, player, linked parent, and outsider denial. Existing upload/playback bytes matched. The targeted native retry suite passed 2/2, covering retained prepared bytes, stable upload identity, duplicate-acknowledgement reconciliation, retry state, and interruption messaging (`Test-HomePlate-2026.09.12_01-48-54--0400.xcresult`).
- PASS — organization/account acceptance: Plate Team, Plate Facility, and Plate Trainer switched successfully in the Simulator and loaded their role-appropriate homes. Account loaded repeatedly without timeout. Organization-sponsored access remained available without presenting the individual Apple player paywall.
- PASS — R handoff contract: the native Ryan Sullivan analysis action opened the production website and supplied organization/player/date context. Web route and sign-in-return tests verify that the requested analysis URL is retained through authentication. A populated chart after a fresh web sign-in was not visually inspected in this pass.
- PASS — live operational canaries: owner, coach, player, parent, and multi-organization roles passed workspace/source/cross-organization checks. Booking create/read/idempotent duplicate/conflict/cancel passed. Service price save/read/restore passed. Facility operating-hour booking boundaries passed. Credit-package endpoints return HTTP 410 and zero services retain `package_credit`; WAR membership state remained unchanged.
- PASS — financial reconciliation behavior: Apple report authorization, refund fee reversal, revised-report replacement, idempotency, and zero-value filtering passed. The August report contains 28 USD and 1 EUR free-download units with zero gross, fees, refunds, and proceeds; the financial ledger correctly remains empty. No Stripe or Apple cash transaction exists to reconcile at this time, so pending and settled totals correctly remain zero.

## Final deployment boundary

- Production backend deployed: `apple-finance-sync` version 7, `war-operations` version 32, migrations `20260912020000` and `20260912021500`.
- The web frontend was built and tested locally; this pass did not publish a new frontend deployment.
- Native UI remains iPhone-Simulator-only. No iPad was recreated, no IPA was exported, and nothing was uploaded or submitted to App Store Connect.
