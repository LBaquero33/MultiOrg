-- Home Plate Phase 11B.2: versioned Rapsodo and TrackMan vendor adapters.
-- Additive only: Phase 11B.1 (20260715070000) is already applied.

-- Phase 11B.1 used `\\.` in a standard PostgreSQL string. That regular
-- expression expects a literal backslash followed by any character, so every
-- generated `<uuid>.csv`/`.tsv` storage path fails create_job with 409.
alter table public.sd_development_import_jobs
  drop constraint if exists sd_development_import_storage_identity_check;
alter table public.sd_development_import_jobs
  add constraint sd_development_import_storage_identity_check check (
    (storage_bucket is null and storage_path is null)
    or (
      storage_bucket = 'player-development-imports'
      and storage_path ~ ('^' || org_id::text || '/' || id::text || '/[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\.(csv|tsv)$')
    )
  ) not valid;
alter table public.sd_development_import_jobs
  validate constraint sd_development_import_storage_identity_check;

alter table public.sd_development_import_jobs
  add column if not exists detected_export_type text,
  add column if not exists adapter_version text,
  add column if not exists detection_confidence text,
  add column if not exists detection_metadata jsonb not null default '{}'::jsonb,
  add column if not exists unit_system text,
  add column if not exists import_timezone text;

alter table public.sd_development_import_jobs
  add constraint sd_development_import_detection_check check (
    (detected_export_type is null or detected_export_type in (
      'generic_csv', 'rapsodo_hitting', 'rapsodo_pitching', 'trackman_radar'
    ))
    and (detection_confidence is null or detection_confidence in ('high', 'medium', 'low'))
    and (unit_system is null or unit_system in ('imperial', 'metric'))
    and (adapter_version is null or char_length(adapter_version) between 1 and 100)
    and (import_timezone is null or char_length(import_timezone) between 1 and 100)
    and jsonb_typeof(detection_metadata) = 'object'
    and pg_column_size(detection_metadata) <= 16384
  ) not valid,
  add constraint sd_development_import_adapter_confirmation_check check (
    status not in ('validating', 'player_resolution_required', 'ready', 'importing', 'completed', 'completed_with_errors')
    or detected_export_type is null
    or (
      adapter_version is not null
      and import_timezone is not null
      and (detected_export_type <> 'trackman_radar' or unit_system is not null)
    )
  ) not valid;

alter table public.sd_development_import_jobs
  validate constraint sd_development_import_detection_check;
alter table public.sd_development_import_jobs
  validate constraint sd_development_import_adapter_confirmation_check;

alter table public.sd_player_metric_observations
  add column if not exists adapter_version text,
  add column if not exists provider_export_type text;

alter table public.sd_player_metric_observations
  add constraint sd_player_metric_vendor_provenance_check check (
    (adapter_version is null or char_length(adapter_version) between 1 and 100)
    and (provider_export_type is null or provider_export_type in (
      'generic_csv', 'rapsodo_hitting', 'rapsodo_pitching', 'trackman_radar'
    ))
    and (
      source_entity_type <> 'player_development_import'
      or (adapter_version is not null and provider_export_type is not null)
    )
  ) not valid;
alter table public.sd_player_metric_observations
  validate constraint sd_player_metric_vendor_provenance_check;

insert into public.sd_development_metric_definitions (
  canonical_key, display_name, category, data_type, canonical_unit,
  preferred_direction, valid_aggregations, minimum_sample_size, context_notes
) values
  ('hitting.exit_velocity', 'Exit Velocity', 'hitting', 'number', 'mph', 'context_dependent', array['latest','average','best','distribution'], 5, 'Event-level batted-ball exit velocity; do not conflate with pre-aggregated maximum or average exit velocity.'),
  ('hitting.exit_direction', 'Exit Direction', 'hitting', 'number', 'deg', 'context_dependent', array['latest','average','distribution'], 5, 'Provider sign convention and batting context must remain available.'),
  ('hitting.distance', 'Batted-ball Distance', 'hitting', 'number', 'ft', 'context_dependent', array['latest','average','best','distribution'], 5, 'Provider carry/estimated-distance definition must be preserved.'),
  ('hitting.batted_ball_spin_rate', 'Batted-ball Spin Rate', 'hitting', 'number', 'rpm', 'context_dependent', array['latest','average','distribution'], 5, 'Event-level spin rate as the ball leaves the bat.'),
  ('hitting.pitch_velocity_seen', 'Pitch Velocity Seen', 'hitting', 'number', 'mph', 'context_dependent', array['latest','average','distribution'], 5, 'Pitch speed associated with a hitting event.'),
  ('pitching.true_spin', 'True Spin', 'pitching', 'number', 'rpm', 'context_dependent', array['latest','average'], 5, 'Provider release true-spin definition must be preserved; not equivalent to total spin.'),
  ('pitching.horizontal_approach_angle', 'Horizontal Approach Angle', 'pitching', 'number', 'deg', 'context_dependent', array['latest','average'], 5, 'Provider sign convention must be preserved.'),
  ('pitching.vertical_approach_angle', 'Vertical Approach Angle', 'pitching', 'number', 'deg', 'context_dependent', array['latest','average'], 5, 'Angle as the pitch crosses the front of home plate.'),
  ('pitching.plate_location_height', 'Plate Location Height', 'pitching', 'number', 'ft', 'context_dependent', array['latest','average','distribution'], 5, 'Height as the pitch crosses the front of home plate.'),
  ('pitching.plate_location_side', 'Plate Location Side', 'pitching', 'number', 'ft', 'context_dependent', array['latest','average','distribution'], 5, 'Horizontal sign convention must be preserved.'),
  ('pitching.zone_velocity', 'Zone Velocity', 'pitching', 'number', 'mph', 'context_dependent', array['latest','average','best'], 5, 'Pitch speed as it crosses the front of home plate.')
on conflict (canonical_key) do nothing;

comment on column public.sd_development_import_jobs.detection_metadata is
  'Bounded signature names, warnings, and protected/unsupported column names only; never raw GPS, device serial, or player values.';
comment on column public.sd_player_metric_observations.adapter_version is
  'Immutable vendor adapter version used to normalize this imported observation.';
