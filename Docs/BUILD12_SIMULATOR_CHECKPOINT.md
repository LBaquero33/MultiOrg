# Home Plate Simulator checkpoint — September 10, 2026

## Storage recovery

- Extreme SSD was ExFAT. Created (not formatted) `HomePlate-Builds.sparsebundle`, a 100 GB maximum grow-on-demand APFS image, mounted at `/Volumes/HomePlate-Builds`.
- Copied inactive Home Plate DerivedData, ScoringKit `.build`, and Xcode module cache. Checksum-based rsync dry runs returned no differences; open-handle checks were clear before removing internal originals and replacing them with symbolic links.
- Restore manifest: `/Volumes/HomePlate-Builds/Offloaded-2026-09-10/RESTORE.md`.
- Source repositories, active Xcode index, and Simulator app data were preserved. Keep SSD connected and image mounted while using linked caches/build outputs.

## Verified this pass

- Build 11 completed using external DerivedData, installed on both Home Plate Simulators, version confirmed. No IPA or Apple distribution performed.
- iPhone: shared library first-open video sheet now renders title, footage, and original-day link. Link loaded Ryan Sullivan's August 22 day with sessions/media.
- iPad: shared library first-open BP video sheet rendered actual footage.
- Native scoring journal tests: 3 passed, 0 failed. Evidence: `/Volumes/HomePlate-Builds/Build11-JournalTests.xcresult`.
- Web: 304 tests passed across 64 files; typecheck and production build passed. These checks are not proof of deployed library/naming/scoring UI.
- Web expense receipt retry now preserves the committed expense and offers receipt-only retry; local source only, no financial transactions performed.

## Build 12 follow-up

- Build 12 completed and installed/launched on both Simulators after additional storage offload.
- iPad original-day regression verified fixed with 15U still selected: Ryan Sullivan August 22 day loaded sessions and media. Day-linked R analysis completed with an explicit zero-source-row result for the selected date, not a permission failure. This is not a populated-chart acceptance test.
- Also checksum-verified and offloaded the inactive Screenshots folder and two inactive web dependency folders; restore instructions and original-path links preserve access.

## In progress / not accepted

- Build 13 compiled stable per-selected-file upload IDs for workout/testing videos, preserving display name/MIME storage metadata and treating only HTTP 409 as an existing upload.
- Build 14 adds an in-view pending hitting/bullpen video retry with captured organization/player/date/activity and original filename metadata. These retries survive a failed request while the view remains open, not an app termination; live retry tests remain pending explicit QA upload approval.
- Final web rerun: 304 tests passed and typecheck passed after storage offload.
- Build 14 compilation succeeded; installation is being performed separately from live-upload acceptance.

- Build 12 changes player deep-link and media requests to omit the sidebar team filter; server actor/org/player authorization remains unchanged. The iPad day-link regression is resolved as recorded above.
- Full native offline game/restart/reconnect acceptance, all upload flows, full R chart visual verification, and broad web rollout remain open.
- Recorded Games/auto-clipping rollout remains parked; no media worker infrastructure activated.

## Approved synthetic upload acceptance — build 15

- User approved isolated QA upload testing. No real player records or external conversations changed.
- iPad build 14: selected a synthetic file, saw mandatory naming, cancelled, and verified no pending attachment and disabled Send.
- Sent one 189-byte synthetic TXT in the existing internal QA owner conversation as `QA Renamed Upload 20260910.txt`. Native UI showed Sent.
- Backend verifier `Home-Plate-Web-Audit/scripts/qa/verify-native-renamed-upload.mjs` passed: exactly one attachment/object, correct original and display filename metadata, authorized QA recipient read, downloaded SHA256 equality, and denied anonymous signed access.
- Replaying the existing storage object with upsert disabled returned 409 with one object remaining. This is storage idempotency evidence, NOT native network-loss/reconnect acceptance.
- Found and fixed stale chat error text after a valid attachment selection (`ChatThreadView.appendPending`). Build 15 compiled successfully and installed/launched on both Simulators.
- iPad build 15 regression verified: unsupported synthetic MP4 produced an error; subsequently confirming a valid TXT staged it, enabled Send, and cleared both stale error and Retry. No second message sent. The synthetic TXT remains an unsent draft on the iPad.
- Native chat still excludes MP4 from its allowed attachment types. Video chat support and all other outstanding acceptance items above remain open. No production deployment, physical-device acceptance, IPA, or Apple distribution occurred in this pass.

## Build 16 — chat video and reconnect closeout

- Added MP4/MOV support to native Files and Photos selection; mandatory naming and 50 MB limit remain. Attachment lookup now fails closed during retry instead of treating network failure as an empty attachment list.
- Deployed only `20260910160000_chat_video_attachments.sql`. Verified private bucket, unchanged 50 MB cap, and both video MIME types. No game-video migration deployed.
- Build 16 compiled and installed on iPad; iPad renamed/sent `QA Video Upload 20260910.mp4` to existing isolated QA owner DM, then opened playable footage.
- Video verifier passed: one attachment/object, 5,565 bytes, original/display names preserved, exact downloaded SHA256 match, authorized QA recipient access, anonymous denial, duplicate replay 409.
- Isolated production web picker hotfix `dpl_rRrtfrMWqTyrkYAZSkP1118Pzy23` READY; production target and `/auth` HTTP 200 release header confirmed. Only deployed source change is adding MP4/MOV picker types; broader local library/naming/offline changes are NOT included.
- Web 304 tests / 64 files and typecheck passed.
- Native live QA test expanded to seven innings with durable journal reload after every command and duplicate synchronization checks. Initial run interrupted during disk pressure (144 MB free); space recovered without deleting user files. Reusing that canary correctly rejected a different device as `offline_authority_reserved`; preserved reservation. Fresh sequential canary test pending, game `96853410-2f9d-4c73-b0c2-3e3f45b2d6f8`.
- Sequential run failed after 147 seconds with Cocoa 640 / POSIX 28 during journal save. No scoring synchronization acceptance. Tight test loop now uses a per-command autorelease pool to limit transient Objective-C/Foundation allocations; this test-only change still needs rebuild/rerun. Retained earlier journal measured 2.9 MB; disk recovered to 5 GB after test exited. Do not interpret this as proof of a production journal-size defect or completed reconnect verification.

## Final automated reconnect acceptance — build 17

- Bounded-allocation run generated and reloaded 132 local commands (193 events), then synchronized every command and replayed every command as a duplicate against isolated live QA game `8856afd1-c450-4235-a9ff-73f0e0a425ba`. All receipt/event identity/score assertions passed; the run's sole failure was an incorrect test expectation of inning 7 rather than the projection's inning 8 after 42 outs. Corrected that assertion. Game finalization itself was not exercised.
- Preserved that exact QA journal privately on external APFS for recovery verification; includes test signing material, so do not publish its contents. Original and snapshot remain intact.
- Build 17 compiled. `testSavedJournalSurvivesTransportFailureAndReconnect` then PASSED against the preserved journal: scoped URLSession connection failure, durable reload with unchanged events/pending count, restored network and duplicate receipt acceptance, exact full server event identity, 132 commands, inning 8, away score 2/home score 0/away hits 1.
- Passing result: `/Volumes/HomePlate-Builds/DerivedData/Logs/Test/Test-HomePlate-2026.09.10_16-15-00--0400.xcresult`.
- Production SupabaseService defaults to the same shared URLSession; injection is test-scoped, not an OS network setting or a production debug switch.
- This is native automated journal/transport/live-backend acceptance, NOT a physical-device airplane-mode trial or complete UI game walkthrough. No IPA/TestFlight/App Store release performed. Broad local web program-library/naming/offline UI still excluded from the narrow deployed video-picker hotfix.
