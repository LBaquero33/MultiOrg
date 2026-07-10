# Shiny → iOS Parity Checklist (Source of Truth: DHD Self Development Shiny)

Source Shiny app directory: `/Users/lb33/Documents/DHD Self Development`

Target iOS app directory: `/Users/lb33/Documents/DHD-Self-Development-iOS`

## Roles + Navigation
- [x] Auth-backed roles in `public.profiles` (`role`, `full_name`)
- [x] Coach vs Player routing (`HomeView`)
- [ ] Coach home matches Shiny layout:
  - Players roster “cards” + search
  - Selecting player opens player detail with tabs: Overview / Calendar (view-only) / Testing / Program / Analysis
  - “Program Templates” as a first-class coach area (not a modal)
- [ ] Player navigation matches Shiny sidebar tabs: Today / Calendar / Trends / Testing / Analysis

## Auth + Account Lifecycle
Shiny features (server.R):
- Username/password login
- Create account (player/coach)
- Password recovery (recovery key)
- Persistent session token in local storage

iOS parity targets:
- [x] Email/password sign-in (Supabase Auth)
- [x] Username-style sign-in via legacy bridge (`legacy_login` Edge Function)
- [x] Create account in-app (`create_account` Edge Function)
- [x] Apple Sign-In
- [ ] Password recovery UX parity (Shiny recovery key flow vs iOS reset-email flow)
- [ ] Persistent session UX parity (Shiny localStorage token vs iOS Keychain session restore)

## Onboarding (Player Accounts)
Shiny onboarding:
- Step 1: improvement focus (dropdown)
- Step 2: “How are you going to get there?” (text)
- Step 3: daily goals (text)
- Coach tool: reset onboarding for a player

iOS parity targets:
- [ ] Onboarding triggers automatically for new player accounts
- [ ] Coach can reset onboarding for a player
- [ ] Player can review/edit onboarding later

## Today (Player)
Shiny Today tab:
- Date picker
- “Submit Day”
- Daily Strength section (scheduled program awareness)
- Daily Hitting section (BP/game/practice signals + CSV import)
- Daily self-assessment (checkboxes + text areas)
- Improvement summary + Current program widget

iOS parity targets:
- [ ] Today screen matches Shiny fields/logic (including off-day behavior)
- [ ] Daily self-assessment fields present and stored
- [ ] “Submit Day” equivalent and success/error UX

## Calendar
Shiny Calendar:
- Month grid
- Dots: scheduled lift (green), BP practice (blue), game reps (red)
- Clicking a date loads that day’s entry (player editable; coach view-only)

iOS parity targets:
- [ ] Same dots + definitions
- [ ] Tap day → edit/view daily entry
- [ ] Coach view is read-only

## Strength Programs + Templates
Shiny Program Templates:
- 2- or 4-week templates
- Weekdays per week (1–6 days)
- Grid editor: 1 row per week, 1 col per lift day
- Day editor: exercises in chronological order
- Copy week within template
- Shared templates + “copy shared”
- Assign program to player with start date
- End current program
- Coach note per day (viewable to player)

iOS parity targets:
- [ ] Template list + create/edit/delete
- [ ] Grid editor parity (week x day, tap-to-edit)
- [ ] Copy-week, shared templates, and copy-shared
- [ ] Assign/end program parity
- [ ] Coach day-note parity

## Testing Entries
Shiny Testing tab:
- Add / edit entries
- Metrics: height/weight, squat/bench/deadlift 1RM, max/avg EV, hip/shoulder rotation diffs, notes
- Table listing entries

iOS parity targets:
- [ ] Full metric set parity
- [ ] Add/edit entries parity
- [ ] Instant refresh of tables and derived “Improvement” UI

## Hitting BP Data (Daily CSV → Graphs)
Shiny Analysis:
- Daily BP import (Rapsodo / HitTrax)
- Events stored and drive all analysis graphs
- Plots: EV hist, distance hist, LA hist, EV vs LA scatter (and any Plotly charts in analysis_playground.R if in use)

iOS parity targets:
- [ ] CSV import options: Rapsodo + HitTrax
- [ ] Events persisted and used for “Analysis” plots
- [ ] Plots parity (match Shiny outputs first; refine visuals second)

## Coach “Program ↔ Testing Links”
Shiny coach Testing view:
- Track exercises during program window (max or avg)
- Link built-in testing fields (e.g., Squat 1RM) to a program day/exercise

iOS parity targets:
- [ ] UI and storage for “program → testing links”
- [ ] Aggregation options (max/avg)
- [ ] Links drive Testing/Trends displays

## Data / Backend
- [x] Supabase Postgres primary backend
- [ ] All Shiny tables/models represented in Supabase schema (no local-only gaps)
- [ ] RLS verified for player vs coach views
- [ ] Seed scripts parity (mock accounts/data/programs)

