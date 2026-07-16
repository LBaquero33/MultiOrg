-- Home Plate Phase 11B.2 corrective migration: atomic validation persistence.
-- Additive only: 20260715070000 and 20260715080000 are already applied.

create or replace function public.sd_persist_development_import_validation(
  p_actor_id uuid,
  p_org_id uuid,
  p_job_id uuid,
  p_expected_file_sha256 text,
  p_expected_mapping_fingerprint text,
  p_expected_player_scope_fingerprint text,
  p_row_count integer,
  p_accepted_rows integer,
  p_rejected_rows integer,
  p_unmatched_player_rows integer,
  p_ambiguous_player_rows integer,
  p_warning_count integer,
  p_validation_summary jsonb,
  p_row_errors jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_job public.sd_development_import_jobs%rowtype;
  v_actor_role text;
  v_next_status text;
  v_row_error_count integer;
begin
  select j.* into v_job
  from public.sd_development_import_jobs j
  where j.id = p_job_id and j.org_id = p_org_id
  for update;

  if not found then
    raise exception using errcode = '42501', message = 'validation_scope_failed';
  end if;

  select m.role into v_actor_role
  from public.sd_org_memberships m
  where m.org_id = p_org_id and m.user_id = p_actor_id
    and m.status = 'active' and m.role in ('owner', 'admin', 'coach');

  if v_actor_role is null or (
    v_actor_role = 'coach' and not (
      (v_job.player_id is null and v_job.requested_by = p_actor_id)
      or
      (v_job.player_id is not null and public.sd_development_can_manage_player(
        p_org_id,
        v_job.player_id
      ))
    )
  ) then
    raise exception using errcode = '42501', message = 'validation_scope_failed';
  end if;

  if v_job.status not in ('validating', 'player_resolution_required', 'ready') then
    raise exception using errcode = 'P0001', message = 'validation_transition_failed';
  end if;

  if p_expected_file_sha256 is null
    or p_expected_file_sha256 !~ '^[0-9a-f]{64}$'
    or v_job.file_sha256 is distinct from p_expected_file_sha256
    or p_expected_mapping_fingerprint is null
    or p_expected_mapping_fingerprint !~ '^[0-9a-f]{64}$'
    or v_job.mapping_fingerprint is distinct from p_expected_mapping_fingerprint
    or p_expected_player_scope_fingerprint is null
    or p_expected_player_scope_fingerprint !~ '^[0-9a-f]{64}$'
    or v_job.player_scope_fingerprint is distinct from p_expected_player_scope_fingerprint
    or v_job.artifact_expires_at is null
    or v_job.artifact_expires_at <= now()
  then
    raise exception using errcode = '40001', message = 'validation_input_changed';
  end if;

  if p_row_count is null or p_row_count < 0
    or p_row_count is distinct from v_job.row_count
    or p_accepted_rows is null or p_accepted_rows < 0
    or p_rejected_rows is null or p_rejected_rows < 0
    or p_unmatched_player_rows is null or p_unmatched_player_rows < 0
    or p_ambiguous_player_rows is null or p_ambiguous_player_rows < 0
    or p_warning_count is null or p_warning_count < 0
    or p_accepted_rows + p_rejected_rows > p_row_count
    or p_unmatched_player_rows > p_rejected_rows
    or p_unmatched_player_rows > p_row_count
    or p_ambiguous_player_rows > p_rejected_rows
    or p_ambiguous_player_rows > p_row_count
  then
    raise exception using errcode = '23514', message = 'validation_summary_constraint_failed';
  end if;

  if p_validation_summary is null
    or jsonb_typeof(p_validation_summary) is distinct from 'object'
    or pg_column_size(p_validation_summary) > 65536
    or p_row_errors is null
    or jsonb_typeof(p_row_errors) is distinct from 'array'
    or pg_column_size(p_row_errors) > 1048576
  then
    raise exception using errcode = '23514', message = 'validation_summary_constraint_failed';
  end if;

  v_row_error_count := jsonb_array_length(p_row_errors);
  if v_row_error_count > 1000
    or not p_validation_summary @> jsonb_build_object(
      'totalRows', p_row_count,
      'acceptedRows', p_accepted_rows,
      'rejectedRows', p_rejected_rows,
      'unmatchedPlayerRows', p_unmatched_player_rows,
      'ambiguousPlayerRows', p_ambiguous_player_rows,
      'warningCount', p_warning_count,
      'persistedRowErrors', v_row_error_count
    )
    or jsonb_typeof(p_validation_summary -> 'rowErrorsTruncated') is distinct from 'boolean'
  then
    raise exception using errcode = '23514', message = 'validation_summary_constraint_failed';
  end if;

  if exists (
    select 1
    from pg_catalog.jsonb_array_elements(p_row_errors) item
    where jsonb_typeof(item) is distinct from 'object'
      or item
        - 'source_row_number' - 'player_match_state' - 'metric_mapping_state'
        - 'acceptance_state' - 'error_codes' - 'warning_codes'
        - 'safe_summary' - 'safe_row_identity' <> '{}'::jsonb
      or jsonb_typeof(item -> 'safe_row_identity') is distinct from 'object'
      or (item -> 'safe_row_identity')
        - 'source_row_number' - 'metric_keys' - 'metric_keys_truncated' <> '{}'::jsonb
      or jsonb_typeof(item -> 'safe_row_identity' -> 'source_row_number') is distinct from 'number'
      or (item -> 'safe_row_identity' ->> 'source_row_number')
        is distinct from (item ->> 'source_row_number')
      or jsonb_typeof(item -> 'safe_row_identity' -> 'metric_keys_truncated')
        is distinct from 'boolean'
      or jsonb_typeof(item -> 'safe_row_identity' -> 'metric_keys') is distinct from 'array'
      or jsonb_array_length(item -> 'safe_row_identity' -> 'metric_keys') > 50
      or pg_column_size(item -> 'safe_row_identity') > 4096
      or jsonb_typeof(item -> 'error_codes') is distinct from 'array'
      or jsonb_array_length(item -> 'error_codes') > 50
      or jsonb_typeof(item -> 'warning_codes') is distinct from 'array'
      or jsonb_array_length(item -> 'warning_codes') > 50
      or exists (
        select 1
        from pg_catalog.jsonb_array_elements_text(item -> 'error_codes')
          as error_code(value)
        where pg_catalog.char_length(error_code.value) > 100
      )
      or exists (
        select 1
        from pg_catalog.jsonb_array_elements_text(item -> 'warning_codes')
          as warning_code(value)
        where pg_catalog.char_length(warning_code.value) > 100
      )
      or exists (
        select 1
        from pg_catalog.jsonb_array_elements_text(
          item -> 'safe_row_identity' -> 'metric_keys'
        ) as metric_key(value)
        where pg_catalog.char_length(metric_key.value) > 150
      )
  ) then
    raise exception using errcode = '23514', message = 'validation_row_error_replace_failed';
  end if;

  v_next_status := case
    when p_unmatched_player_rows > 0 or p_ambiguous_player_rows > 0
      then 'player_resolution_required'
    else 'ready'
  end;

  begin
    delete from public.sd_development_import_row_errors e
    where e.org_id = p_org_id and e.import_job_id = p_job_id;

    insert into public.sd_development_import_row_errors (
      org_id,
      import_job_id,
      source_row_number,
      player_match_state,
      metric_mapping_state,
      acceptance_state,
      error_codes,
      warning_codes,
      safe_summary,
      safe_row_identity
    )
    select
      p_org_id,
      p_job_id,
      e.source_row_number,
      e.player_match_state,
      e.metric_mapping_state,
      e.acceptance_state,
      e.error_codes,
      e.warning_codes,
      e.safe_summary,
      e.safe_row_identity
    from pg_catalog.jsonb_to_recordset(p_row_errors) as e(
      source_row_number integer,
      player_match_state text,
      metric_mapping_state text,
      acceptance_state text,
      error_codes text[],
      warning_codes text[],
      safe_summary text,
      safe_row_identity jsonb
    );
  exception when others then
    raise exception using errcode = sqlstate, message = 'validation_row_error_replace_failed';
  end;

  begin
    -- Revalidation from ready may need to move back through validating before
    -- player resolution is required; both transitions remain trigger-checked.
    if v_job.status in ('ready', 'player_resolution_required')
      and v_job.status <> v_next_status
    then
      update public.sd_development_import_jobs
      set status = 'validating'
      where id = p_job_id and org_id = p_org_id;
    end if;

    update public.sd_development_import_jobs
    set status = v_next_status,
      file_sha256 = p_expected_file_sha256,
      mapping_fingerprint = p_expected_mapping_fingerprint,
      player_scope_fingerprint = p_expected_player_scope_fingerprint,
      row_count = p_row_count,
      accepted_rows = p_accepted_rows,
      rejected_rows = p_rejected_rows,
      unmatched_player_rows = p_unmatched_player_rows,
      warning_count = p_warning_count,
      validation_summary = p_validation_summary,
      safe_error_code = null,
      safe_error_summary = null
    where id = p_job_id and org_id = p_org_id;
  exception
    when check_violation then
      raise exception using errcode = '23514', message = 'validation_summary_constraint_failed';
    when others then
      raise exception using errcode = sqlstate, message = 'validation_transition_failed';
  end;

  return jsonb_build_object(
    'job_id', p_job_id,
    'status', v_next_status,
    'persisted_row_errors', v_row_error_count
  );
end;
$$;

create or replace function public.sd_archive_development_import_job(
  p_actor_id uuid,
  p_org_id uuid,
  p_job_id uuid,
  p_for_restart boolean
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_job public.sd_development_import_jobs%rowtype;
  v_actor_role text;
begin
  select j.* into v_job
  from public.sd_development_import_jobs j
  where j.id = p_job_id and j.org_id = p_org_id
  for update;

  if not found then
    raise exception using errcode = '42501', message = 'development_import_archive_scope_failed';
  end if;

  select m.role into v_actor_role
  from public.sd_org_memberships m
  where m.org_id = p_org_id and m.user_id = p_actor_id
    and m.status = 'active' and m.role in ('owner', 'admin', 'coach');

  if v_actor_role is null or (
    v_actor_role = 'coach' and not (
      (v_job.player_id is null and v_job.requested_by = p_actor_id)
      or
      (v_job.player_id is not null and public.sd_development_can_manage_player(
        p_org_id,
        v_job.player_id
      ))
    )
  ) then
    raise exception using errcode = '42501', message = 'development_import_archive_scope_failed';
  end if;

  if p_for_restart then
    if v_job.status not in (
      'pending', 'uploaded', 'inspecting', 'mapping_required',
      'player_resolution_required', 'validating', 'ready', 'failed'
    ) or exists (
      select 1 from public.sd_player_metric_observations o
      where o.import_job_id = p_job_id and o.org_id = p_org_id
    ) then
      raise exception using errcode = 'P0001', message = 'development_import_restart_denied';
    end if;
    if v_job.status <> 'failed' then
      update public.sd_development_import_jobs
      set status = 'failed',
        completed_at = coalesce(completed_at, now()),
        safe_error_code = 'start_over_requested',
        safe_error_summary = 'The incomplete import was archived before starting over.'
      where id = p_job_id and org_id = p_org_id;
    end if;
  elsif v_job.status not in ('completed', 'completed_with_errors', 'failed', 'canceled') then
    raise exception using errcode = 'P0001', message = 'development_import_archive_denied';
  end if;

  update public.sd_development_import_jobs
  set status = 'archived',
    completed_at = coalesce(completed_at, now()),
    archived_at = now()
  where id = p_job_id and org_id = p_org_id;

  return jsonb_build_object('job_id', p_job_id, 'status', 'archived');
end;
$$;

revoke all on function public.sd_persist_development_import_validation(
  uuid, uuid, uuid, text, text, text,
  integer, integer, integer, integer, integer, integer, jsonb, jsonb
) from public, anon, authenticated, service_role;
grant execute on function public.sd_persist_development_import_validation(
  uuid, uuid, uuid, text, text, text,
  integer, integer, integer, integer, integer, integer, jsonb, jsonb
) to service_role;

revoke all on function public.sd_archive_development_import_job(
  uuid, uuid, uuid, boolean
) from public, anon, authenticated, service_role;
grant execute on function public.sd_archive_development_import_job(
  uuid, uuid, uuid, boolean
) to service_role;

comment on function public.sd_persist_development_import_validation(
  uuid, uuid, uuid, text, text, text,
  integer, integer, integer, integer, integer, integer, jsonb, jsonb
) is 'Atomically replaces bounded import row errors and advances the authoritative validation summary/status after actor, organization, file, mapping, and player-scope checks.';
