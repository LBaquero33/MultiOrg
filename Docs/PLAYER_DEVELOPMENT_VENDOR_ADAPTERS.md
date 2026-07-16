# Player Development Vendor Adapters

The detector returns provider, export type, adapter version, confidence, required/optional matches, missing signatures, warnings, protected/unsupported columns, and whether automatic mapping is safe. The result and confirmed time zone/unit system are persisted with the job; mapping fingerprints include adapter assumptions.

Rapsodo Hitting requires both preamble keys plus `HitID`, `ExitVelocity`, `LaunchAngle`, and `Unique ID`. Rapsodo Pitching requires both keys plus `Pitch ID`, `Pitch Type`, `Velocity`, `Total Spin`, and `Unique ID`. The preamble search is capped at 20 physical lines, rejects missing/duplicate/conflicting metadata, preserves original source row numbers, and treats `-` as missing only after a Rapsodo adapter is recognized.

TrackMan high confidence requires `PitchNo`, `PitchUID`, a pitcher identity (`Pitcher` or `PitcherId`), a pitch type (`TaggedPitchType` or `AutoPitchType`), and at least three of `RelSpeed`, `SpinRate`, `RelHeight`, and `Extension`. `Batter`/`BatterId` enable row/metric-specific hitting identity. Common `Date`, `Velocity`, or `SpinRate` fields cannot identify TrackMan.

Player matching remains organization and authorized-player scoped: saved exact provider ID, exact legitimate organization username, unique normalized name, then manual resolution. TrackMan resolves pitcher identity for pitching metrics and batter identity for hitting metrics. A metadata name is a candidate, never authorization.

## Phase 11A canonical-registry audit

All 38 original definitions were reviewed. Safe reuse is limited to `hitting.launch_angle`; `pitching.velocity`, `spin_rate`, `spin_efficiency`, `induced_vertical_break`, `horizontal_break`, `release_height`, `release_side`, and `extension`. Raw batted-ball events cannot map to the existing aggregate `hitting.max_exit_velocity` or `hitting.average_exit_velocity`. Rate, bat/attack/time-to-contact, pitch usage/command/miss, physical, strength, consistency, and mobility definitions have no semantically equivalent source column in these exports.

The additive migration creates 11 non-duplicate event definitions: `hitting.exit_velocity`, `exit_direction`, `distance`, `batted_ball_spin_rate`, `pitch_velocity_seen`; and `pitching.true_spin`, `horizontal_approach_angle`, `vertical_approach_angle`, `plate_location_height`, `plate_location_side`, `zone_velocity`. Rapsodo contact depth and strike-zone location remain unsupported because their source units are not documented. Rapsodo movement variants remain unsupported. TrackMan plate location and break map only under the official glossary definitions and confirmed unit system.
