# UI fixes and verification — September 11, 2026

## Installed locally

Updated signed Debug builds are installed on the Home Plate iPhone and iPad simulators. No App Store Connect upload or production deployment was performed.

- Adaptive segmented controls avoid broken labels on narrow screens.
- Messages has a cleaner action row and fewer repeated headings.
- Programs has shorter navigation labels, consolidated creation actions, improved weekday selection, and no redundant root Done button.
- Player workspaces have a clearer profile header, grouped and deduplicated activity fields, readable values, and explicit empty media states.
- Team, Facility, and Trainer dashboards use compact metric layouts. Facility/Trainer navigation no longer shows irrelevant team scope.
- Team Games is scoped to the selected team. Team overview uses official calendar events; coaching plans are identified separately.
- Development, Communication, Documents guidance, and Settings have explicit destinations rather than placeholder content.
- Organization switching requests active organizations only; the visible list contained Plate Team, Plate Facility, Plate Trainer, and WAR Performance.
- Payments uses readable dates. Service editors use dollar inputs, clearer sections, and expandable advanced settings; no services or payments were changed during testing.
- Calendar day labels, facility day summaries, account headings, and admin tab accessibility were refined.

## Evidence

Signed build: `/tmp/homeplate-ui-polish-build.log` — BUILD SUCCEEDED.

Navigation and workspace run: `/tmp/homeplate-ui-tests-final.log` — 23 navigation tests and 9 workspace/format tests passed. After final polish, the 9 workspace tests passed again on iPad (`/tmp/homeplate-ui-polish-tests.log`). `git diff --check` passed.

See [screenshot gallery](after/index.html). iPhone checks include all three organization dashboards, Messages, Programs/player details, active organization switching, team Games, official schedule, and Development routing. iPad checks include Messages, Programs, Payments, and the admin People tab. Earlier screenshots precede the final small root-button and field-format refinements; files ending `final` show the latest build.

## Verification limits

This is representative Simulator verification, not an assertion that every role, menu, deep form, financial transaction, or physical device has passed. Player/parent role coverage, service-save transactions, and exhaustive deep-menu checks remain open. Some cosmetic repetition remains. Account briefly returned a Gateway Timeout; a later attempt loaded. The populated iPad People screen rendered, but Simulator stopped exposing its controls to automation after loading. Neither limitation is represented as fixed.

## Storage

The approved approximately 4.2 GB of caches/intermediates was moved to a dated Trash folder under the recoverable-cleanup procedure; source, installed apps, sign-ins, recordings, and the finished archive were preserved. See [cleanup manifest](CACHE-CLEANUP.md). Empty that specific dated Trash folder to reclaim its space. Following rebuilt caches, the latest free-space check was about 860 MiB, so additional large builds should wait for more space.
