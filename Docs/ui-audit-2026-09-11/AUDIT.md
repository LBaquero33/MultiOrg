# Home Plate native UI audit — September 11, 2026

## Release hold and scope

**Nothing was uploaded to App Store Connect in this pass.** The local 1.02 (7) archive completed successfully. The simulator examined here reports Debug build 7, marketing version 1.0.0, built at 2026-09-11T20:12:32Z from commit 3471bfcde093c0f6f6a7f4f9dd0109a53b78a6b8. This is not acceptance testing of the signed 1.02 archive or the App Store binary.

This is a broad, but **not exhaustive**, native UI audit of Team, Facility, and Individual Trainer. Owner/Admin access was used. Player profiles were inspected as staff; player/parent sign-in experiences were not tested. No scoring, messages, payments, bookings, invitations, or configuration changes were submitted during the audit. Changing the active organization was the only account navigation state change.

71 original Simulator-window screenshots are retained locally. They contain account/team information; do not publish them publicly. The gallery labels loading/duplicate captures separately. Screenshots were not cosmetically modified.

## Highest-priority confirmed visual problems

| Priority | Finding | Evidence | Recommended change |
|---|---|---|---|
| High | Messages buttons break words: Refresh and Announcements wrap awkwardly on iPhone **and iPad**. Chat / Messages / Conversations repeat headings. | [iPhone Messages](iphone-facility-messages.jpg), [iPad Messages](ipad-team-messages.jpg) | Make actions adapt to width; move actions to a toolbar, use a scrollable or menu-based filter, and keep one page title. |
| High | Player day details display raw ISO timestamps, underscore statuses, internal source names, cents, and repeated metric values. | [Day details](iphone-facility-day-details.jpg), [Sessions data](iphone-facility-sessions-data.jpg) | Format dates locally, translate status labels, format currency, deduplicate metrics, and group results, attendance, payment, and notes. |
| High | iPhone Programs title and status filters truncate; player header can force a name into three lines. | [Programs](iphone-facility-programs.jpg), [Player calendar](iphone-facility-player-calendar.jpg) | Shorten the navigation title, make filters adaptive, and move secondary player actions below the name. |
| Medium | Service/offering editors are long, dim, developer-oriented forms. Prices use cents; copy includes “atomically.” | [Service editor](iphone-facility-service-editor.jpg), [Offerings](iphone-facility-offerings.jpg) | Use clearly labeled sections, currency inputs, human-readable booking modes, and progressive disclosure for overrides. |
| Medium | Empty player Video Library looks like a blank screen below filters. | [Video library](iphone-facility-video-library.jpg) | Add an explicit empty state, explain filter scope, and expose an upload action only where permitted. |
| Medium | Home uses three large cards in an unbalanced two-column iPhone grid; iPad has excessive unused space. | [Trainer iPhone](iphone-trainer-home.jpg), [Team iPad](ipad-team-home.jpg) | Use compact summary strips or a balanced responsive grid and make upcoming work more prominent. |
| Medium | iPhone calendar's selected day can show an ellipsis instead of a readable day number. | [Facility calendar](iphone-facility-resources.jpg), [Team calendar](iphone-team-games.jpg) | Protect the date label width and position the event/today indicator independently. |
| Medium | Facility day sheet repeats its title and gives oversized counters priority over the day's schedule. | [Day sheet](iphone-facility-day-popup.jpg) | Use a readable date heading and compact counters above the actual schedule. |
| Medium | Payments opens Finance, repeats the Finance heading, and displays technical date/UTC formatting. | [iPhone Finance](iphone-facility-payments.jpg), [iPad Finance](ipad-team-payments.jpg) | Align navigation naming, remove the duplicate title, and use a compact, localized date range. |
| Medium | Program Library's controls occupy most of the first iPhone screen before folders/content. New-program editor repeats its heading and is a long switch-heavy form. | [Library](iphone-facility-program-library.jpg), [New program](iphone-facility-new-program.jpg) | Prioritize folders/programs; put creation actions in one toolbar and group scheduling inputs. |
| Medium | iPad sidebar truncates Programs even in landscape. | [iPad Programs](ipad-team-programs.jpg) | Use a shorter visible label with a complete accessibility name, or an adaptive sidebar width. |
| Low | Multiple screens repeat headings (Teams, Organization/Org Admin, Athletes, Account) and switch abruptly between green custom cards and gold native-style forms. | [Teams](iphone-team-teams.jpg), [Account](iphone-facility-account.jpg), [Training catalog](iphone-facility-training-catalog.jpg) | Establish one heading hierarchy and shared forms/buttons/spacing. |

## Navigation and content issues — not merely cosmetic

1. **Team Development and Team Settings are dead ends in the inspected staff flow.** They show explanatory text without a next action. [Development](iphone-team-development-deadend.jpg), [Settings](iphone-team-settings-deadend.jpg).
2. **Games opens the general Calendar.** A dedicated game list or an explicitly game-filtered calendar would better match the label. [Games](iphone-team-games.jpg).
3. **Trainer empty states do not help staff get started.** Athletes says no athletes are available to the role, without an obvious add/invite route. Facilities uses cage/drag-booking language even for the individual-trainer experience. [Athletes](iphone-trainer-athletes.jpg), [Facilities](iphone-trainer-facilities.jpg).
4. **Retired/test organizations remain in the organization switcher.** Plate Academy and older QA/review organizations are still visible. This confirms discoverability, not whether they can still be entered or mutated. [Switcher](iphone-organization-switcher-archived.jpg).
5. **Context and counts need clarification.** Facility showed a QA team workspace selector; Home athlete counts and organization member counts describe different populations without explaining scope. Shared testing memberships were requested historically, so this is **not evidence of a cross-organization data leak**. The inspected member endpoint filters organization ID.
6. **Schedule consistency needs a functional follow-up.** Team Home showed the September 14 9U game, while the selected 9U team Schedule showed zero upcoming events. Different data sources/scopes could explain this; cause was not established. [Home](iphone-team-home.jpg), [Schedule](iphone-team-schedule.jpg).
7. Team document empty state and player profile lack clear next-step actions in the inspected flow. [Documents](iphone-team-documents.jpg), [Profile](iphone-team-ryan-profile.jpg).
8. **Admin accessibility labels are ambiguous.** Several different section buttons all expose “Organization admin sections, Value: Overview.” AX clicks failed with duplicate matching elements. Coordinate fallback navigated to a different control, so deeper admin tabs are not claimed as verified.

## What looked better / worked in this pass

- Calendar day taps opened a detail sheet in the tested facility and team calendars.
- The R-analysis screen presents a clear website handoff button on iPhone and iPad. This audit did not revalidate the destination's authenticated analytics content.
- Program Library opened from Template Builder; New program opened an editor. The earlier infinite-loop behavior was not reproduced along that tested route.
- Team roster and staff rows are substantially clearer than the raw player-development activity details.
- Main Programs title and filters fit on iPad; their specific truncation defect is iPhone-focused.

## Actual coverage

| Organization | iPhone | iPad |
|---|---|---|
| Facility | Home, Athletes, services/trainer catalog, service editor, offerings editor, Calendar/Sessions, attendance form, Facilities/month/day sheet, Programs player hub, player calendar/day details, progress, sessions, testing, R handoff, media, profile, Library/new program, Testing Setup, Messages/thread, Finance overview, organization overview/general settings, Account/switcher | Home portrait/landscape, Athletes, Facilities, Programs/player calendar/R handoff, Messages, Finance overview, organization overview, Account; Calendar screenshot remained loading |
| Individual Trainer | Home, Athletes, Calendar/Sessions, Facilities, Programs, Messages, Finance overview, organization overview, account switching | Home and Programs; shared menus not independently repeated |
| Team | Home, Teams, selected 9U overview/roster/player profile/schedule/development/staff/settings/documents, Games/calendar/day/event overview/lineup, account switching | Home, Teams, Programs, Messages, Finance overview, organization overview |

### Remaining coverage — do not treat as passed

- Player and parent account roots; front-desk-only permissions; other account-specific roles.
- Every create/edit form, all organization People/Business/Branding/Operations/Advanced tabs, registration and billing subflows.
- Full lower Finance and Account content; an attempted iPhone Finance scroll did not change the screen.
- Live scoring workspace, completed game video, file pickers, permissions prompts, keyboard/Dynamic Type/VoiceOver, offline/errors and physical devices.
- Independent iPad Trainer menu repetition; every orientation on every screen.
- Authenticated website destination and App Store-distributed build.

These gaps mean “every corner” is **not yet fully verified**. Deeper admin navigation hit a tooling barrier; other gaps require additional role/data-specific testing. No UI fixes were implemented in this audit-only pass.

## Source pointers for remediation

- `HomePlate/Features/Coach/UnifiedPlayerDevelopmentWorkspaceView.swift:109` — status filter layout.
- `HomePlate/Features/Coach/UnifiedPlayerDevelopmentWorkspaceView.swift:1404` — raw activity field rendering.
- `HomePlate/Features/Chat/ChatChannelListView.swift:263` — conversation filters.
- `HomePlate/Features/Chat/ChatChannelListView.swift:304` — Refresh action.
- `HomePlate/Features/Home/HomePlateNavigationShell.swift` — shared navigation/adaptive shell.

Recommended order: responsive shared controls → formatted player data → functional dead-end routes → contextual empty states → dashboard/form polish → role-specific and physical-device acceptance. Keep App Store Connect on hold.

