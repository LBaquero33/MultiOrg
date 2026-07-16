# Player Copilot

Player Copilot is a private, evidence-backed assistant for an athlete's own Home Plate development record. It is distinct from Coach Copilot.

## Eligibility

The request succeeds only when all of these are true:

1. The JWT resolves to an authenticated profile.
2. The selected organization is active.
3. The actor has an active `player` membership in that exact organization.
4. The requested player UUID equals the authenticated actor UUID.
5. The request and conversation audience are `player`.
6. Every returned/persisted item retains the same organization, player, creator, and audience scope.

Players cannot select another athlete. A known UUID grants nothing. Organization memberships are evaluated independently; evidence is never combined across organizations.

## Supported deterministic questions

The deterministic provider supports evidence-grounded variations of:

- What changed in the last 30 or 90 days?
- What did my latest Rapsodo/imported session show?
- Which metrics improved or need attention?
- Which data is stale or missing?
- Explain a metric or trend in simple language.
- What should I discuss with my coach?
- Summarize my recent development.
- Which assigned programs appear in my record?
- Which evidence supports this conclusion?

Answers cite the exact evidence items and deterministic trend rules. If evidence is absent, the answer says so. If a free-form request needs a provider that is unavailable, Home Plate reports provider unavailable and does not pretend a model answered.

## Player-visible evidence

Current supported sources are objective testing rows, normalized/imported metric observations (including Rapsodo and supported CSV/TrackMan adapters), safe provider/verification metadata, deterministic trends/freshness/sample counts, assigned-program context, objective player-log aggregates, and supported BP session metrics.

Player Copilot may also cite the player's own `audience=player` reports and objective player alerts. Those are generated and persisted separately from staff reports/alerts, use the same exact organization/player boundary, and never expose staff review history or staff evidence. See `PLAYER_DEVELOPMENT_DATA_VISIBILITY.md` for the complete matrix.

## Bounded two-way dialogue

Assistant turns are typed as `answer`, `clarification_question`, `evidence_gap_question`, `reflection_question`, `confirmation_question`, `suggested_follow_up`, `action_preview`, or `safe_refusal`. Ambiguous requests can produce one focused clarification; missing session context can produce an evidence-gap question; and age-appropriate reflection remains private conversational context.

Pending questions persist their type, reason, expected response, at most six choices, authorized evidence IDs, optional/save-later flags, expiry, and answer state. A response must bind the exact conversation/audience/question ID. Users may answer, choose a chip, skip an optional question, or continue with available evidence. Expired, answered, or superseded questions cannot accept a stale reply.

One to three evidence-grounded follow-ups may appear after an answer. Proposed mutations produce a structured preview and confirmation question, but confirmation executes nothing in this phase because no dedicated audited tool is in scope.

## Private exclusions

Player Copilot never receives staff notes, confidential evaluations, staff-only alerts, roster attention, rankings/comparisons, other players' evidence, parent drafts, coach feedback, finances, internal operations, private recruiting evaluations, storage paths/URLs, GPS, device serials, secrets, or tokens.

## Safe actions

Player answers may suggest reviewing a metric with a coach, requesting retesting, uploading current data, completing/reviewing assigned work, logging training, discussing data quality, preparing coach questions, or updating a goal in a future workflow. These are proposals only and always require a person to act.

Copilot cannot modify records, programs, schedules, tests, notes, messages, parent communications, or recruiting status. The explicit player report archive and player informational-alert dismissal endpoints are narrow audience-bound lifecycle actions, not conversational tools.

## Player summaries and alerts

`Generate My Summary` calls the player-only deterministic report action for `auth.uid()` and the selected active organization. It uses `player-development-self-summary.v1`, the player evidence allowlist, audience-aware idempotency, and refreshes the workspace. The same explicit action may generate separately worded player-audience objective alerts; it never relabels staff alerts and never sends notifications or APNs pushes.

## Privacy and sharing

Player conversations, citations, feedback, attempts, and usage are private to the player in the selected organization. Coaches do not automatically see them, and players do not see coach conversations or feedback. No automatic sharing exists. Future sharing must be explicit, auditable, and preserve a source copy.

## Prompt and safety

The backend-owned use case is `player_copilot_self_question`; the prompt version is `player-copilot-self.v1`. It requires age-appropriate language, clear fact/interpretation boundaries, verification and data-limit disclosure, no diagnosis, no guaranteed outcomes, and no unsupported causality.
