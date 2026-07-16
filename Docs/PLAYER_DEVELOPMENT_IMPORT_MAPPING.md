# Player Development Import Mapping

## File shapes

Wide files map one player/date row to one or more metric columns. Every metric column requires an active canonical metric and an explicit source unit when the metric has a canonical unit.

Long files map player, date/timestamp, metric label/key, value, and unit columns. Source metric labels may be explicitly mapped to canonical keys. Unknown headers or metric labels never create new metric definitions.

Supported roles are ignore, provider external player ID, player name, organization username, email/birth year (contract prepared; not active because the current scoped profile schema has no authoritative fields), date/timestamp, canonical metric, value, unit, sample size, session, pitch/swing type, team, and bounded context.

## Player matching

Matching stays inside the active organization and coach player scope: verified provider external ID, exact organization username, exact normalized full name when unique, then manual resolution. Email and birth-year matching remain unavailable until an authoritative organization-scoped source exists. Fuzzy matches are never confirmed. Inactive players are excluded. Manual external IDs are unique per organization/provider.

## Units and dates

`unit-registry.v1` supports mph; km/h→mph; lb; kg→lb; in; cm→in; ft; m; seconds; ms→seconds; degrees; rpm; and percent. A conversion runs only when source unit is explicit and dimensions match. Percent and decimal ratios are intentionally separate. The system never converts spin axis to spin rate, drop to induced break, distance to velocity, or provider scores without a documented formula.

Dates support `YYYY-MM-DD`, ISO timestamps with an explicit zone/offset, and `MM/DD/YYYY` only when selected. Two-digit years and zoneless timestamps are rejected. Date-only observations use a stable midday UTC instant while retaining the selected import time zone and source string.

Mapping profiles store normalized headers and a SHA-256 header fingerprint. The UI refuses reuse when the fingerprint differs; every reused mapping is revalidated.
