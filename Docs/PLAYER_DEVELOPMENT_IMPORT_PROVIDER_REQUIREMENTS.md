# Player Development Import Provider Requirements

Phase 11B.2 activates deterministic adapters for `rapsodo_hitting` (`rapsodo-hitting.v1`), `rapsodo_pitching` (`rapsodo-pitching.v1`), and `trackman_radar` (`trackman-radar.v1`). Detection uses bounded preamble metadata and normalized structural header signatures, never a filename or value magnitude.

High confidence requires the complete documented signature. Medium confidence may suggest TrackMan when at least five distinctive signature elements including `PitchUID` exist, but automatic mapping remains off. Low confidence uses Generic CSV. A file satisfying both Rapsodo signature groups is ambiguous and falls back rather than guessing.

HitTrax, Blast, Pocket Radar, and strength-testing adapters remain inactive until a sanitized real fixture preserves the complete preamble, header spelling/order, delimiter, quoting, units, date/time formats, blank columns, optional fields, and representative rows. A filename alone is never provider evidence.

Private fixture rules: originals never enter source control. Committed fixtures replace names, IDs, event/session identifiers, device serials, and coordinates with fictional or redacted values. GPS and orientation matrix data must never enter observation context, evidence, normal UI, or logs.
