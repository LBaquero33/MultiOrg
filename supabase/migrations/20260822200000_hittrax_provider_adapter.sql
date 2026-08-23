-- Activate the versioned HitTrax hitting import adapter without changing
-- existing import rows or metric observations.

alter table public.sd_development_import_jobs
  drop constraint if exists sd_development_import_detection_check;
alter table public.sd_development_import_jobs
  add constraint sd_development_import_detection_check check (
    (detected_export_type is null or detected_export_type in (
      'generic_csv', 'rapsodo_hitting', 'rapsodo_pitching',
      'hittrax_hitting', 'trackman_radar'
    ))
    and (detection_confidence is null or detection_confidence in ('high', 'medium', 'low'))
    and (unit_system is null or unit_system in ('imperial', 'metric'))
    and (adapter_version is null or char_length(adapter_version) between 1 and 100)
    and (import_timezone is null or char_length(import_timezone) between 1 and 100)
    and jsonb_typeof(detection_metadata) = 'object'
    and pg_column_size(detection_metadata) <= 16384
  ) not valid;
alter table public.sd_development_import_jobs
  validate constraint sd_development_import_detection_check;

alter table public.sd_player_metric_observations
  drop constraint if exists sd_player_metric_vendor_provenance_check;
alter table public.sd_player_metric_observations
  add constraint sd_player_metric_vendor_provenance_check check (
    (adapter_version is null or char_length(adapter_version) between 1 and 100)
    and (provider_export_type is null or provider_export_type in (
      'generic_csv', 'rapsodo_hitting', 'rapsodo_pitching',
      'hittrax_hitting', 'trackman_radar'
    ))
    and (
      source_entity_type <> 'player_development_import'
      or (adapter_version is not null and provider_export_type is not null)
    )
  ) not valid;
alter table public.sd_player_metric_observations
  validate constraint sd_player_metric_vendor_provenance_check;
