# Player Development Copilot UI

## Entries and roles

Coach Copilot remains in the staff Player Development AI workspace for an authorized selected player.

Player Development AI is added narrowly to the existing player root. On iOS/iPadOS it is a player tab/destination; on macOS it is a player navigation button presented in the existing sheet pattern. The destination receives `appState.myProfile` as its immutable player target. No coach/admin role and no player picker are required.

Parents do not receive an entry. Presentation checks are defense in depth; backend/RLS checks remain authoritative.

## Player workspace

The player workspace is read-only and shows:

- data-coverage counts for testing, imported observations, daily logs, assigned programs, and BP sessions;
- data freshness and deterministic trends;
- player-visible testing/import evidence with normalized value, unit, date, provider, and verification;
- missing/stale/unit/sample warnings;
- player-audience summaries with a deterministic `Generate My Summary` action and loading/success/failure/stable-retry states;
- player-visible objective alerts with evidence detail and a player-only dismiss action;
- player-safe suggested questions;
- an Open Player Copilot entry and privacy explanation.

It contains no report approve/reject controls, staff alert acknowledgment/resolution, roster attention, staff review history, coach notes, parent drafts, or coach-only recommendations. Player reports expose only draft/archive; player alerts expose only informational dismissal.

## Private conversations

The shared conversation UI receives an explicit `coach` or `player` audience. Its title, loads, creates, messages, feedback, usage, and citations retain that audience. Player loads skip parent-draft APIs, hide parent-draft history/generation/usage, and display only their private player history. Coach loads continue to show coach history and parent-draft workflows.

Organization/user/player/audience changes cancel or invalidate requests, reset state, and reject stale results. Client models also reject mismatched response scopes.

## Conversation behavior

Conversation screens remain scrollable and include visible Back/Close controls. macOS modal presentations use the existing Escape shortcut convention. The bounded composer blocks empty/oversized questions and duplicate sends. Retry reuses the same idempotency key after failure.

Assistant cards separate facts, calculations, interpretations, recommendations, missing information, warnings, and proposed actions. Provider-unavailable and rejected states remain truthful. Player-safe actions are display-only and require human action.

Assistant questions use a distinct card. It labels clarification, evidence-gap, reflection, and confirmation turns; distinguishes optional from required; shows at most six response chips; supports free-text, Skip, and Use available evidence; and displays sending, answered, expired, and superseded states. The composer binds its next response to the active pending-question ID. Context reset clears that binding.

## Citations and feedback

Citation detail renders value, normalized value where available, unit, observation date, source/provider, verification, deterministic rule, and explanation. It never renders private storage paths, raw files, GPS, serials, tokens, or secrets.

Players can submit the same bounded feedback types on their own assistant answers. The request retains player audience. Feedback does not alter the answer and is not shared with coaches.

## Future sharing

The UI text prepares users for a future explicit sharing action, but this phase implements neither “Share with coach” nor “Share answer with player.” No conversation or answer crosses audiences automatically.
