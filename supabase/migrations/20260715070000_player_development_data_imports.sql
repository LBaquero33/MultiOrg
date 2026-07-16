-- Home Plate Phase 11B.1: generic player-development CSV/TSV imports.
--
-- Purpose
-- - Extend the Phase 11A import job and canonical observation contracts without
--   changing existing observations or synthetic demo provenance.
-- - Add private immutable upload identity, reusable mappings, exact external
--   player identities, bounded row errors, and an idempotent service-only commit.
-- - Keep every import object organization scoped and staff readable only.
--
-- Assumptions
-- - 20260715060000_player_development_ai_foundation.sql is already applied.
-- - The player-development-imports Edge Function authenticates the JWT before
--   using service-role access and revalidates authoritative input at commit.
-- - CSV content remains in the private Storage bucket, never in PostgreSQL.
--
-- Rollback guidance (manual; export audit records first)
-- 1. Undeploy the Edge Function and disable new uploads.
-- 2. Drop the Storage policies and bucket only after retained objects are
--    deliberately exported or removed.
-- 3. Drop row errors, external identities, and mapping profiles.
-- 4. Drop the additive observation/job columns and restore the Phase 11A job
--    status constraint. Imported observations are audit data and are not
--    automatically deleted by this rollback.

alter table public.sd_development_import_jobs
  drop constraint if exists sd_development_import_jobs_status_check;

alter table public.sd_development_import_jobs
  add constraint sd_development_import_jobs_status_check
  check (status in (
    'pending', 'processing', 'canceled',
    'uploaded', 'inspecting', 'mapping_required',
    'player_resolution_required', 'validating', 'ready', 'importing',
    'completed', 'completed_with_errors', 'failed', 'archived'
  ));

alter table public.sd_development_import_jobs
  add column if not exists original_file_type text
    check (original_file_type is null or original_file_type in ('csv', 'tsv')),
  add column if not exists file_sha256 text
    check (file_sha256 is null or file_sha256 ~ '^[0-9a-f]{64}$'),
  add column if not exists file_size_bytes bigint
    check (file_size_bytes is null or file_size_bytes between 1 and 10485760),
  add column if not exists storage_bucket text,
  add column if not exists storage_path text,
  add column if not exists parser_version text not null default 'generic-csv.v1',
  add column if not exists mapping_version text,
  add column if not exists mapping_fingerprint text
    check (mapping_fingerprint is null or mapping_fingerprint ~ '^[0-9a-f]{64}$'),
  add column if not exists player_scope_fingerprint text
    check (player_scope_fingerprint is null or player_scope_fingerprint ~ '^[0-9a-f]{64}$'),
  add column if not exists header_fingerprint text
    check (header_fingerprint is null or header_fingerprint ~ '^[0-9a-f]{64}$'),
  add column if not exists file_shape text
    check (file_shape is null or file_shape in ('wide', 'long')),
  add column if not exists mapping_config jsonb not null default '{}'::jsonb,
  add column if not exists validation_summary jsonb not null default '{}'::jsonb,
  add column if not exists unmatched_player_rows integer not null default 0
    check (unmatched_player_rows >= 0),
  add column if not exists warning_count integer not null default 0
    check (warning_count >= 0),
  add column if not exists safe_error_code text,
  add column if not exists artifact_expires_at timestamptz;

alter table public.sd_development_import_jobs
  add constraint sd_development_import_provider_check
    check (provider is null or provider in (
      'generic_csv', 'rapsodo', 'hittrax', 'trackman', 'blast',
      'pocket_radar', 'strength_testing'
    )),
  add constraint sd_development_import_mapping_size_check
    check (pg_column_size(mapping_config) <= 65536 and pg_column_size(validation_summary) <= 65536),
  add constraint sd_development_import_unmatched_count_check
    check (unmatched_player_rows <= rejected_rows and unmatched_player_rows <= row_count),
  add constraint sd_development_import_file_name_check
    check (file_name is null or char_length(file_name) between 1 and 180);

alter table public.sd_development_import_jobs
  add constraint sd_development_import_storage_identity_check
  check (
    (storage_bucket is null and storage_path is null)
    or
    (storage_bucket = 'player-development-imports'
      and storage_path ~ ('^' || org_id::text || '/' || id::text || '/[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\\.(csv|tsv)$'))
  ) not valid;
alter table public.sd_development_import_jobs
  validate constraint sd_development_import_storage_identity_check;

alter table public.sd_player_metric_observations
  add column if not exists original_unit text,
  add column if not exists canonical_unit text,
  add column if not exists conversion_rule text,
  add column if not exists conversion_version text,
  add column if not exists conversion_warning text,
  add column if not exists verification_status text not null default 'unverified'
    check (verification_status in (
      'unverified', 'device_imported_unverified', 'coach_verified',
      'organization_verified', 'synthetic_unverified'
    )),
  add column if not exists parser_version text,
  add column if not exists mapping_version text,
  add column if not exists source_row_number integer
    check (source_row_number is null or source_row_number >= 2),
  add column if not exists source_date_string text,
  add column if not exists imported_timezone text;

alter table public.sd_player_metric_observations
  add constraint sd_player_metric_import_text_bounds_check check (
    (original_unit is null or char_length(original_unit) <= 50)
    and (canonical_unit is null or char_length(canonical_unit) <= 50)
    and (conversion_rule is null or char_length(conversion_rule) <= 100)
    and (conversion_version is null or char_length(conversion_version) <= 100)
    and (parser_version is null or char_length(parser_version) <= 100)
    and (mapping_version is null or char_length(mapping_version) <= 150)
    and (source_date_string is null or char_length(source_date_string) <= 200)
    and (imported_timezone is null or char_length(imported_timezone) <= 100)
  ) not valid,
  add constraint sd_player_metric_import_provenance_check
  check (
    source_entity_type <> 'player_development_import'
    or (
      import_job_id is not null and normalized_value is not null
      and verification_status = 'device_imported_unverified'
      and parser_version is not null and mapping_version is not null
      and source_row_number is not null and conversion_rule is not null
      and conversion_version is not null and source_date_string is not null
      and imported_timezone is not null
      and pg_column_size(context_metadata) <= 16384
    )
  ) not valid;
alter table public.sd_player_metric_observations
  validate constraint sd_player_metric_import_text_bounds_check;
alter table public.sd_player_metric_observations
  validate constraint sd_player_metric_import_provenance_check;

comment on column public.sd_player_metric_observations.unit is
  'Legacy/evidence unit. For imports this is the canonical normalized unit.';

create table public.sd_development_import_mapping_profiles (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.sd_orgs(id) on delete restrict,
  provider text not null check (provider in (
    'generic_csv', 'rapsodo', 'hittrax', 'trackman', 'blast',
    'pocket_radar', 'strength_testing'
  )),
  mapping_name text not null check (
    mapping_name = btrim(mapping_name)
    and char_length(mapping_name) between 1 and 100
  ),
  header_fingerprint text not null check (header_fingerprint ~ '^[0-9a-f]{64}$'),
  normalized_headers text[] not null check (cardinality(normalized_headers) between 1 and 250),
  parser_version text not null,
  mapping_version text not null,
  file_shape text not null check (file_shape in ('wide', 'long')),
  player_mapping jsonb not null default '{}'::jsonb,
  date_mapping jsonb not null default '{}'::jsonb,
  metric_mapping jsonb not null default '{}'::jsonb,
  unit_mapping jsonb not null default '{}'::jsonb,
  context_mapping jsonb not null default '{}'::jsonb,
  mapping_config jsonb not null default '{}'::jsonb,
  is_active boolean not null default true,
  archived_at timestamptz,
  created_by uuid not null references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, org_id),
  constraint sd_development_import_mapping_archive_check
    check ((is_active and archived_at is null) or (not is_active and archived_at is not null)),
  constraint sd_development_import_mapping_json_check check (
    jsonb_typeof(mapping_config) = 'object'
    and pg_column_size(mapping_config) <= 65536
    and pg_column_size(player_mapping) <= 65536
    and pg_column_size(date_mapping) <= 65536
    and pg_column_size(metric_mapping) <= 65536
    and pg_column_size(unit_mapping) <= 65536
    and pg_column_size(context_mapping) <= 65536
  )
);

create unique index idx_sd_development_import_mapping_profiles_active_name
  on public.sd_development_import_mapping_profiles (org_id, provider, lower(mapping_name))
  where is_active;
create index idx_sd_development_import_mapping_profiles_headers
  on public.sd_development_import_mapping_profiles
  (org_id, provider, header_fingerprint, parser_version) where is_active;

create table public.sd_development_external_player_identities (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.sd_orgs(id) on delete restrict,
  provider text not null check (provider in (
    'generic_csv', 'rapsodo', 'hittrax', 'trackman', 'blast',
    'pocket_radar', 'strength_testing'
  )),
  external_player_id text not null check (
    external_player_id = btrim(external_player_id)
    and char_length(external_player_id) between 1 and 200
    and external_player_id !~ '[[:cntrl:]]'
  ),
  normalized_external_player_id text generated always as
    (lower(btrim(external_player_id))) stored,
  player_id uuid not null references public.profiles(id) on delete restrict,
  display_label text check (display_label is null or char_length(display_label) <= 200),
  verification_state text not null default 'staff_verified'
    check (verification_state in ('staff_verified', 'provider_verified', 'unverified')),
  linked_by uuid not null references public.profiles(id) on delete restrict,
  linked_at timestamptz not null default now(),
  archived_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, org_id),
  unique (id, org_id, player_id)
);

create unique index idx_sd_development_external_identity_active_external
  on public.sd_development_external_player_identities
  (org_id, provider, normalized_external_player_id) where archived_at is null;
create index idx_sd_development_external_identity_player
  on public.sd_development_external_player_identities
  (org_id, player_id, provider) where archived_at is null;

create table public.sd_development_import_row_errors (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.sd_orgs(id) on delete restrict,
  import_job_id uuid not null,
  source_row_number integer not null check (source_row_number >= 2),
  player_match_state text not null default 'unmatched'
    check (player_match_state in ('matched', 'suggested', 'ambiguous', 'unmatched', 'ignored')),
  metric_mapping_state text not null default 'unmapped'
    check (metric_mapping_state in ('mapped', 'unmapped', 'unsupported', 'deprecated', 'ignored')),
  acceptance_state text not null check (acceptance_state in ('warning', 'rejected', 'duplicate')),
  error_codes text[] not null default '{}',
  warning_codes text[] not null default '{}',
  safe_summary text not null check (char_length(safe_summary) <= 500),
  safe_row_identity jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint sd_development_import_row_errors_job_fk
    foreign key (import_job_id, org_id)
    references public.sd_development_import_jobs(id, org_id) on delete restrict,
  constraint sd_development_import_row_errors_bounded_check
    check (pg_column_size(safe_row_identity) <= 4096),
  unique (import_job_id, source_row_number, error_codes, warning_codes)
);

create index idx_sd_development_import_row_errors_job_row
  on public.sd_development_import_row_errors (org_id, import_job_id, source_row_number);

create or replace function public.sd_validate_development_external_identity_scope()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (
    select 1 from public.sd_org_memberships m
    where m.org_id = new.org_id and m.user_id = new.player_id
      and m.role = 'player' and m.status = 'active'
  ) then raise exception 'development_external_identity_active_player_required'; end if;
  if not exists (
    select 1 from public.sd_org_memberships m
    where m.org_id = new.org_id and m.user_id = new.linked_by
      and m.role in ('owner', 'admin', 'coach') and m.status = 'active'
  ) then raise exception 'development_external_identity_staff_required'; end if;
  return new;
end;
$$;

create or replace function public.sd_validate_development_mapping_profile_scope()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  resolution record;
begin
  if not exists (
    select 1 from public.sd_org_memberships m
    where m.org_id = new.org_id and m.user_id = new.created_by
      and m.role in ('owner', 'admin', 'coach') and m.status = 'active'
  ) then raise exception 'development_mapping_profile_staff_required'; end if;

  for resolution in
    select value from pg_catalog.jsonb_each_text(
      coalesce(new.mapping_config -> 'playerResolutions', '{}'::jsonb)
    )
  loop
    if resolution.value !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
      or not exists (
        select 1 from public.sd_org_memberships m
        where m.org_id = new.org_id and m.user_id = resolution.value::uuid
          and m.role = 'player' and m.status = 'active'
      )
    then raise exception 'development_mapping_profile_player_scope_required'; end if;
  end loop;
  return new;
end;
$$;

create or replace function public.sd_validate_development_import_lifecycle()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.status = new.status then return new; end if;
  if not (
    (old.status = 'pending' and new.status in ('inspecting', 'processing', 'failed', 'canceled'))
    or (old.status = 'processing' and new.status in ('completed', 'completed_with_errors', 'failed', 'canceled'))
    or (old.status = 'uploaded' and new.status in ('inspecting', 'failed', 'canceled'))
    or (old.status = 'inspecting' and new.status in ('mapping_required', 'failed'))
    or (old.status = 'mapping_required' and new.status in ('validating', 'failed'))
    or (old.status = 'player_resolution_required' and new.status in ('validating', 'failed'))
    or (old.status = 'validating' and new.status in ('ready', 'player_resolution_required', 'failed'))
    or (old.status = 'ready' and new.status in ('validating', 'importing', 'failed'))
    or (old.status = 'importing' and new.status in ('completed', 'completed_with_errors', 'failed'))
    or (old.status = 'failed' and new.status in ('inspecting', 'validating', 'archived'))
    or (old.status in ('completed', 'completed_with_errors', 'canceled') and new.status = 'archived')
  ) then raise exception 'invalid_development_import_status_transition'; end if;
  if new.status = 'importing' and new.started_at is null
  then raise exception 'development_import_started_at_required'; end if;
  if new.status = 'completed' and new.rejected_rows <> 0
  then raise exception 'completed_import_cannot_have_rejections'; end if;
  if new.status = 'completed_with_errors' and new.rejected_rows = 0
  then raise exception 'completed_with_errors_requires_rejections'; end if;
  if new.status in ('completed', 'completed_with_errors', 'archived')
    and new.completed_at is null
  then raise exception 'development_import_completed_at_required'; end if;
  if new.status = 'archived' and new.archived_at is null
  then raise exception 'development_import_archived_at_required'; end if;
  return new;
end;
$$;

create or replace function public.sd_validate_imported_metric_active()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.source_entity_type = 'player_development_import' and not exists (
    select 1 from public.sd_development_metric_definitions d
    where d.id = new.metric_definition_id and d.status = 'active'
  ) then raise exception 'active_development_metric_required'; end if;
  return new;
end;
$$;

create trigger trg_sd_development_external_identity_scope
before insert or update of org_id, player_id, linked_by
on public.sd_development_external_player_identities
for each row execute function public.sd_validate_development_external_identity_scope();

create trigger trg_sd_development_mapping_profile_scope
before insert or update of org_id, created_by, mapping_config
on public.sd_development_import_mapping_profiles
for each row execute function public.sd_validate_development_mapping_profile_scope();

create trigger trg_sd_development_import_lifecycle
before update of status on public.sd_development_import_jobs
for each row execute function public.sd_validate_development_import_lifecycle();

create trigger trg_sd_imported_metric_active
before insert or update of metric_definition_id, source_entity_type
on public.sd_player_metric_observations
for each row execute function public.sd_validate_imported_metric_active();

create trigger trg_sd_development_import_mapping_profiles_updated_at
before update on public.sd_development_import_mapping_profiles
for each row execute function public.sd_set_updated_at();
create trigger trg_sd_development_external_player_identities_updated_at
before update on public.sd_development_external_player_identities
for each row execute function public.sd_set_updated_at();

alter table public.sd_development_import_mapping_profiles enable row level security;
alter table public.sd_development_external_player_identities enable row level security;
alter table public.sd_development_import_row_errors enable row level security;

drop policy if exists "sd_development_import_jobs_staff_read"
on public.sd_development_import_jobs;
create policy "sd_development_import_jobs_staff_read"
on public.sd_development_import_jobs for select to authenticated
using (exists (
  select 1 from public.sd_org_memberships m
  where m.org_id = sd_development_import_jobs.org_id
    and m.user_id = auth.uid() and m.status = 'active'
    and (
      m.role in ('owner', 'admin')
      or (m.role = 'coach' and (
        (player_id is null and requested_by = auth.uid())
        or (player_id is not null and public.sd_development_can_manage_player(org_id, player_id))
      ))
    )
));

create policy "sd_development_import_mapping_profiles_staff_read"
on public.sd_development_import_mapping_profiles for select to authenticated
using (public.sd_development_is_org_staff(org_id));
create policy "sd_development_external_player_identities_staff_read"
on public.sd_development_external_player_identities for select to authenticated
using (
  public.sd_development_is_org_staff(org_id)
  and public.sd_development_can_manage_player(org_id, player_id)
);
create policy "sd_development_import_row_errors_staff_read"
on public.sd_development_import_row_errors for select to authenticated
using (public.sd_development_is_org_staff(org_id) and exists (
  select 1 from public.sd_development_import_jobs j
  where j.id = import_job_id and j.org_id = sd_development_import_row_errors.org_id
    and exists (
      select 1 from public.sd_org_memberships m
      where m.org_id = j.org_id and m.user_id = auth.uid() and m.status = 'active'
        and (
          m.role in ('owner', 'admin')
          or (m.role = 'coach' and (
            (j.player_id is null and j.requested_by = auth.uid())
            or (j.player_id is not null and public.sd_development_can_manage_player(j.org_id, j.player_id))
          ))
        )
    )
));

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'player-development-imports', 'player-development-imports', false, 10485760,
  array['text/csv', 'text/tab-separated-values', 'text/plain', 'application/csv']
)
on conflict (id) do update set
  public = false,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

create policy "player_development_import_objects_staff_insert"
on storage.objects for insert to authenticated
with check (
  bucket_id = 'player-development-imports'
  and case
    when (storage.foldername(name))[1] ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
      and (storage.foldername(name))[2] ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
    then public.sd_development_is_org_staff(((storage.foldername(name))[1])::uuid)
      and exists (
        select 1 from public.sd_development_import_jobs j
        where j.id = ((storage.foldername(name))[2])::uuid
          and j.org_id = ((storage.foldername(name))[1])::uuid
          and j.storage_path = name
          and j.status in ('pending', 'uploaded')
          and j.artifact_expires_at > now()
          and exists (
            select 1 from public.sd_org_memberships m
            where m.org_id = j.org_id and m.user_id = auth.uid() and m.status = 'active'
              and (
                m.role in ('owner', 'admin')
                or (m.role = 'coach' and (
                  (j.player_id is null and j.requested_by = auth.uid())
                  or (j.player_id is not null and public.sd_development_can_manage_player(j.org_id, j.player_id))
                ))
              )
          )
      )
    else false
  end
);

create policy "player_development_import_objects_staff_select"
on storage.objects for select to authenticated
using (
  bucket_id = 'player-development-imports'
  and case
    when (storage.foldername(name))[1] ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
      and (storage.foldername(name))[2] ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
    then public.sd_development_is_org_staff(((storage.foldername(name))[1])::uuid)
      and exists (
        select 1 from public.sd_development_import_jobs j
        where j.id = ((storage.foldername(name))[2])::uuid
          and j.org_id = ((storage.foldername(name))[1])::uuid
          and j.storage_path = name
          and exists (
            select 1 from public.sd_org_memberships m
            where m.org_id = j.org_id and m.user_id = auth.uid() and m.status = 'active'
              and (
                m.role in ('owner', 'admin')
                or (m.role = 'coach' and (
                  (j.player_id is null and j.requested_by = auth.uid())
                  or (j.player_id is not null and public.sd_development_can_manage_player(j.org_id, j.player_id))
                ))
              )
          )
      )
    else false
  end
);

create unique index idx_sd_development_import_jobs_completed_file_mapping
on public.sd_development_import_jobs
  (org_id, provider, file_sha256, parser_version, mapping_fingerprint, player_scope_fingerprint)
where status in ('importing', 'completed', 'completed_with_errors')
  and file_sha256 is not null and mapping_fingerprint is not null
  and player_scope_fingerprint is not null;
create index idx_sd_development_import_jobs_artifact_expiry
on public.sd_development_import_jobs (artifact_expires_at)
where artifact_expires_at is not null and status in ('completed', 'completed_with_errors', 'failed', 'archived');

-- The Edge Function owns lifecycle writes. Authenticated users retain the
-- existing read grants but receive no direct table writes.
revoke all on table public.sd_development_import_mapping_profiles,
  public.sd_development_external_player_identities,
  public.sd_development_import_row_errors
from public, anon, authenticated;
grant select on table public.sd_development_import_mapping_profiles,
  public.sd_development_external_player_identities,
  public.sd_development_import_row_errors
to authenticated;
grant select, insert, update on table public.sd_development_import_jobs,
  public.sd_development_import_mapping_profiles,
  public.sd_development_external_player_identities
to service_role;
grant select, insert, delete on table public.sd_development_import_row_errors to service_role;
grant select, insert on table public.sd_player_metric_observations to service_role;

revoke all on function public.sd_validate_development_external_identity_scope()
from public, anon, authenticated, service_role;
revoke all on function public.sd_validate_development_mapping_profile_scope()
from public, anon, authenticated, service_role;
revoke all on function public.sd_validate_development_import_lifecycle()
from public, anon, authenticated, service_role;
revoke all on function public.sd_validate_imported_metric_active()
from public, anon, authenticated, service_role;
