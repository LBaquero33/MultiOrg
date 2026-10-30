# Home Plate requested fixes — September 9, 2026

## Implemented

- Calendar day taps open overlays on web and native; native booking sheets support nested booking actions and discard stale day responses.
- Programs opens its own template-builder segment instead of recursively presenting Programs.
- Player development exposes Program Progress, Video Library, Testing, Sessions & Data, and R Analysis. Web history no longer stops at 18 loaded days.
- Coach and parent profiles have Progress & Videos; their calendar popups use unified day submissions, testing, media and session data. Coach legacy log/import tools remain accessible.
- Day analysis sends matching start/end date filters.
- Native facility-athlete analytics now sends athlete_id instead of misidentifying the athlete as a team player. The subject discriminator survives decoding.
- Operators can save daily opening/closing hours and timezone per facility resource. Both direct bookings and shared training reservations enforce saved hours. Blank paired hours preserve unrestricted availability. Overnight/split schedules and holiday overrides are not implemented.
- Native photos retain their actual content type. Web attachment failures retain the draft, reuse the message ID and retry only unfinished attachments.
- Native payment requests default to Open, with Paid/All filters. Web and parent billing explanatory text is collapsible. Existing payment processing semantics are unchanged.

## Verified

- Web: 277 tests passed after signed-in follow-up fixes; typecheck passed; lint passed with 15 existing warnings and zero errors.
- A standalone Swift probe using the production SDDevelopmentPlayer declaration passed facility-athlete decoding, encoded round-trip, team-player routing and legacy nil routing. This is a model test, not signed-in R analysis.
- Web preview and production builds succeeded. Latest production release dpl_J4TJYmYKacbBT2gcuUcK5MZFhhZN is Ready; https://www.homeplateapps.com/signin returned HTTP 200 with that exact release header.
- web-operations version 47 and player-development-analytics version 31 are ACTIVE on kbulbvngysflfhaqpvtv. Follow-up fixes explain outside-hours booking failures and no longer incorrectly require a user-account connection for an empty facility-athlete import history.
- Migrations 20260909230000 and 20260909231000 applied. All three hours triggers are enabled.
- Rollback-only production database probe accepted exact opening/closing boundaries and rejected one-minute violations for pending, approved, held and confirmed states. Follow-up count found zero test-resource rows.
- Final native Release archive and App Store export passed after the profile and facility-athlete fixes. Both archive and extracted IPA signatures passed strict verification. Embedded build number is 7 and Supabase host is kbulbvngysflfhaqpvtv.supabase.co.
- IPA: /Users/lb33/Downloads/HomePlate-Notes-Build7-Export/Home Plate.ipa (approximately 18 MB). SHA-256: 40d6e7c0212190692143337a54c051ebefb627117ee74df6e796172d9eb36d7f.

## Open acceptance

Signed-in web owner verification completed in Home Plate QA:

- Week day header and populated month day label opened event dialogs; populated dialog showed three scheduled items. Individual event buttons retain their event-specific navigation.
- Template Builder opened directly and loaded its exercise editor; editor was canceled without a save.
- QA athlete workspace exposed all requested tabs. September 1 day dialog showed testing and session activity; September 7 showed missed work. Program Progress listed six scheduled dates. R filters matched the selected day.
- Facility resource hours saved and persisted, outside-hours booking was rejected, and the final release showed the specific explanation inside the booking dialog. Original null/null hours and America/New_York timezone were restored. Database verification confirmed restoration and zero rows for the rejected feedback probe.
- Read-only inspection of an existing WAR Performance athlete loaded two Rapsodo sources (43 rows), real Contact & Spray metrics and two charts. Unsupported topics identified missing source columns. Returned the active organization to Home Plate QA afterward. No customer records were edited.
- Empty QA athlete R state now says No provider analysis yet and explains CSV upload/DHD sync; verified against deployed analytics version 31.
- Payments layout and collapsed explanatory panel loaded. Stripe readiness reported unavailable; payment processing is NOT accepted.

### Continued acceptance, 21:30 EDT

- Web template save/reopen passed for the unassigned `[QA] Notes acceptance 20260909` program: one Monday, one exercise, 3 sets, 5 reps, and QA notes. The same template and values loaded in the native iPhone program/day editor. No athlete was assigned this verification template.
- Attachment service probe passed using the existing QA owner identity and user-scoped APIs: duplicate send reused the same message ID, exactly one attachment metadata row persisted, and downloaded bytes matched the fixture. Message ID 9e7af627-2e63-4948-94dd-26a13adc464e; attachment ID 43aa0497-e94b-4617-8614-0907b69df6be. Receiver web session reloaded the conversation and opened the file successfully. The browser file-picker step remains separately unverified. Probe: web scripts/qa/verify-notes-attachment.mjs. No customer data was included; external notifications and live payments remained disabled.
- Existing team-player session video opened from Video Library → day popup and played to completion: duration/currentTime 12.794195 seconds, ended=true, media error=null. Customer records were read-only.
- Native sign-in failure was diagnosed with targeted debugger reads of authError/profileLoadError and Keychain OSStatus only: profile could not load because the auth session was missing; Keychain returned -34018. The prior simulator build had no entitlement section. A direct re-sign was insufficient; `xcodebuild ... CODE_SIGNING_ALLOWED=YES build` regenerated the simulator executable with `__TEXT,__entitlements`. Install/launch passed and user sign-in succeeded on both iPhone and iPad. No password or session-token values were inspected. Debugger detached.
- iPhone live UI passed Template Builder direct access (no loop), exercise editor cross-platform persistence, player Calendar → Day Details popup, submitted testing/session values, day R navigation, and Program Progress dates/status counts.
- iPhone native R analysis passed against an existing facility athlete: Rapsodo source selector loaded; Contact & Spray returned 29-row model output, average/max exit velocity, batted-ball chart, and spray chart. No customer records were edited.
- iPad native sign-in and dashboard rendering passed in portrait and landscape. Its current accessibility tree omits application controls and coordinate clicks fail with windowNotFoundAtPosition; user-assisted navigation was requested. This is not a functional pass for its remaining screens.
- QA Stripe status is intentionally blocked by requireStripeConnectAdministrator → assertQaSideEffectAllowed(payment). The UI's generic unavailable message is not evidence of a Stripe outage; actual money movement was not attempted or accepted.

Open acceptance: remaining authenticated iPad feature interactions; native attachment picker/send/open; native facility-hour saves and all role-specific calendar/profile/payment surfaces. Broad all-role/all-device acceptance is NOT claimed complete.

### Continued acceptance, 22:00 EDT

- User confirmed iPad clicks also failed manually. Read-only UIKit inspection showed an active, interactive key window, no presented blocking controller, and an idle main thread. Restarting only the iPad device did not restore the control connection. With explicit user approval, quit/reopened the Simulator application and restored all three previously booted devices without erasing data. iPad input/accessibility recovered and saved login survived.
- iPad live UI passed direct Template Builder access and saved exercise values, Testing Setup reachability, athlete calendar day popup, testing/session values, day R navigation, Program Progress dates, Testing list, and Sessions & Data list. Native received TXT attachment opened in Safari with the expected contents.
- Live iPad portrait inspection exposed messaging's nested split layout clipping the composer. ChatChannelListView now chooses split vs pushed navigation from actual available width (760-point threshold); ChatThreadView adapts its composer below 520 points. Rebuilt and reinstalled with simulator entitlements intact. Portrait chat now shows the complete conversation and composer.
- Missed-day popup originally named no assigned work. Added backward-compatible planned_work to the development-day response and both clients, separate from submitted activities/counts. It names the assigned template, program week/day, available exercises, and whether a program submission exists. Also removed internal row identifiers from normalized visible activity fields. No historical records were changed.
- player-development-workspace version 30 is ACTIVE. The QA user-scoped live probe passed missed-day program identification, zero recorded-activity count, retained 91.2 testing metric, and hidden internal metadata. Script: web scripts/qa/verify-notes-development.mjs.
- Latest web release is dpl_2P4tdEQYFTiebzfCrHDv5SfiPBnE (https://homeplateapps-i16st19kk-msn14.vercel.app). Production signin returned HTTP 200 with that exact release header. Signed-in production September 7 popup shows QA Surface Development Program, week 2/day 1, and the missed-submission explanation. Preview dpl_41nJ8TffcPn187RCrjMoDXsvYjef also built successfully.
- All 280 web tests passed; typecheck passed; lint zero errors/15 existing warnings. Seven focused native tests passed, zero failures/skips, including planned-work Codable round-trip and narrow-iPad messaging policy. Result: HomePlate-Notes-DerivedData/Logs/Test/Test-HomePlate-2026.09.09_21-57-24--0400.xcresult.
- With explicit user approval, selected the public Home Plate icon in the native Photos picker and sent it to the existing QA owner conversation. Native UI showed Sent. Read-only backend verification found exactly one PNG attachment and downloaded bytes matched public/home-plate-icon-192.png (20,471 bytes). Message 97d662d4-0d4b-4e76-b23f-1c569eef91fb; attachment cf55e751-b75f-42e3-96a4-5451707385fe. No personal photo was uploaded. Document picker opened, but file selection from its empty local locations remains unverified.
- The previously exported build-7 IPA predates the new portrait-messaging and planned-work native changes; a refreshed signed export is still required. Do not label the earlier IPA as containing these follow-up fixes.
- Rechecked the rebuilt iPad September 7 popup: assigned program, week 2/day 1, missed explanation, and assignment notes all render. This is a live native pass, not only a contract test.
- User approved the native QA resource save. iPad Organization Settings → Settings → Operations → Facility Resources → Edit saved 09:00–21:00 and reopened those values. A separate database read confirmed opens_at=09:00:00, closes_at=21:00:00, hours_timezone=America/New_York. With the user's restoration approval, clearing both hours and saving in the native editor passed. Separate database verification confirmed the original null/null hours and America/New_York timezone were restored.
- Native-uploaded PNG also rendered in the signed-in web conversation (complete=true, natural size 192×192). iPad finance loaded zero-dollar QA totals and payment-request filters; no charge, refund, or expense was created.
- Reclaimed the inactive npx Vercel installation cache and completed task Debug Intermediates cache after open-handle checks (approximately 660 MB regenerable data). Source, test results, app products, and original archives/IPA were preserved. Release build-8 archive is running separately at HomePlate-Notes-Build8.xcarchive.
- Build 8 archive and App Store IPA export succeeded. New artifact: /Users/lb33/Downloads/HomePlate-Notes-Build8-Export/Home Plate.ipa (approximately 18 MB), SHA-256 fb0215964d2bdf35794fa30c48895741054d7412e57ad5ce19081d41566dacb4. Both archive and extracted IPA passed strict signature verification. IPA build number 8, production push entitlement, get-task-allow=false, and team/application identifiers match L9HQB8S3M3/com.multiorg.app. Compiled IPA contains planned_work and Assigned work for this day. No upload or App Review submission was performed. Completed ArchiveIntermediates cache was removed after no-open-handle verification; source and both build-7/build-8 archives and IPA exports remain.

### Continued acceptance, 22:20 EDT

- Follow-up: iPad returned to Home Plate QA, confirmed by the account screen and switch success message. iPhone is also in QA. Latest iPhone chat navigation/composer layout passed; TXT attachment control and the sent image-message record were present. Image-thumbnail visibility in the short iPhone message viewport was not confirmed because control-tool scroll/drag attempts did not advance the viewport; do not label that image-thumbnail check a pass.

- iPad live R Analysis → Contact & Spray passed on the real 29-row Rapsodo source: average EV 79.30 mph, maximum EV 103.20 mph, Batted-Ball Quality and Spray Chart outputs. Customer records were read-only. iPad remains on WAR Performance pending return to QA; do not write there.
- User asked whether iPhone confirmation was already done. Clarified prior iPhone sign-in/template/day/progress/real-R passes and rechecked the newest native changes. Latest signed-in iPhone missed-day popup now visibly shows Assigned work for this day, QA Surface Development Program, week 2/day 1, and missed-submission explanation. iPhone current app is the tested Debug build from 2026-09-10T01:57:38Z; release IPA build 8 is separately verified.

Storage note: removed only this task's inactive ModuleCache.noindex (approximately 450 MB of regenerable compiler cache) after confirming no compiler process or open handles. Archive, IPA, source and test result bundles were preserved.

Additional storage recovery removed the completed task ArchiveIntermediates cache (320 MB) and temporary extracted IPA inspection copy (78 MB), after checking for open handles. The original archive/IPA remain intact; the IPA SHA-256 was rechecked unchanged after Simulator signing repair.

The first native regression attempt was interrupted during a storage-constrained simulator launch. The final focused run passed: 9 tests, zero failures, zero skips, on iPhone 15 Pro simulator. Result bundle: /Users/lb33/Downloads/HomePlate-Notes-DerivedData/Logs/Test/Test-HomePlate-2026.09.09_20-19-56--0400.xcresult. This verifies model/source contracts, not signed-in UI acceptance. No physical device is attached.

The current checkout's placeholder runtime configuration was restored from the previously verified build-6 archive. Source and earlier archives were preserved. Build-7 export is separate and verified; no Apple review submission or compliance declaration has been changed.

See web scripts/qa/verify-facility-operating-hours.sql for the repeatable rollback-only boundary test.
