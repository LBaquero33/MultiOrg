# Rapsodo Import Mapping

Both adapters require staff confirmation of an IANA session time zone because the `EEE MMM d yyyy h:mm:ss a` timestamp contains no zone.

Hitting maps `ExitVelocity`, `PitchBallVelocity`, `LaunchAngle`, `ExitDirection`, `Spin`, and `Distance` to event-level exit velocity, pitch velocity seen, launch angle, exit direction, batted-ball spin rate, and distance using mph/degrees/rpm/feet. It never writes event rows to aggregate maximum or average exit-velocity keys. `StrikeZoneX/Y`, `Contact Depth`, spin direction/confidence are unsupported until their units/semantics are documented.

Pitching maps `Velocity`, `Total Spin`, `True Spin (release)`, `Spin Efficiency (release)`, `Release Height`, `Release Side`, horizontal/vertical approach angle, and `Release Extension (ft)`. `VB/HB (trajectory)`, `VB/HB (spin)`, and SSW variants remain distinct and unsupported.

Safe context is limited to pitch type, intent type, session name, and non-identifying hitting context. `SerialNumber`, `Device Serial Number`, raw unique IDs in UI, every `SO -` GPS/confidence/timestamp field, and every orientation matrix field are protected and excluded.
