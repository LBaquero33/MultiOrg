# Player Development AI evidence model

## Versioned pack

`player_development_evidence_pack.v1` contains organization/player identity, player display context, report type, date window, evidence cutoff, quality/freshness, source coverage, deterministic trends, evidence snapshots, and explicit warnings.

Evidence keys are stable within a pack: `<source type>:<source record>:<canonical metric>:<observation date>`. Conclusions contain `evidence_keys`; the persisted relationship table retains the corresponding historical snapshot even when a source row later changes.

## Evidence fields

Each persisted item keeps queryable source type/record, organization/player, canonical metric key, raw and normalized values, unit, observation time, comparison fields, direction, sample size, freshness, quality, rule identifier, display label, and concise explanation. `source_metadata` is deliberately limited. `evidence_snapshot` contains only enough measurement context to explain the report later, not an entire private source record.

Each report also stores a SHA-256 fingerprint of the complete versioned evidence pack. The fingerprint is audit metadata, not the idempotency key: an ambiguous retry returns the already committed report and its original snapshots/fingerprint.

## Canonical registry

Canonical identity is provider neutral: for example `hitting.max_exit_velocity`, not `rapsodo.exit_velocity`. Provider, file, source table, and protocol remain observation metadata. Definitions specify data type, canonical unit, preferred direction, optional target range, supported aggregations, minimum-sample guidance, context notes, and lifecycle status.

Phase 11A seeds hitting, pitching, physical, strength, consistency, and mobility definitions. Only metrics backed by current sources are adapted into conclusions. Future definitions do not imply current data availability.

## Trend behavior

For comparable finite observations sorted by date, the engine calculates latest, prior, absolute change, guarded percentage change, last-five rolling mean, recent/prior half-window means, best/worst, sample count, mean observation interval, freshness, and preferred-direction interpretation.

- A percentage is omitted when the prior baseline is zero/near zero.
- Higher/lower direction is applied only when configured.
- Target-range metrics require a configured range and are not declared universally good.
- Informational/context-dependent metrics remain informational.
- A two-percent relative tolerance (minimum 0.01 unit) is stable for directional metrics.
- Mixed non-null units mark a metric/pack conflicting.
- Fewer than the definition's recommended samples marks it limited.
- More than 90 days marks the trend stale; 31–90 days is aging.

Phase 11A uses means for small, existing comparable sets. Median/trimmed/outlier-resistant aggregation should be added per metric only after protocols and sufficient sample sizes are defined; silently discarding an apparent outlier would currently reduce explainability.

## Missing evidence

Missing data is never negative player performance. The pack explicitly states unavailable testing, daily logs, authoritative attendance, and program completion. A booking is not attendance, an assignment is not completion, and a missing log is not a missed session.
