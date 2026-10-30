-- Retention policy: on account deletion, erase player-development observations,
-- imported identities/uploads/rows, AI conversations and generated drafts tied
-- to the departing account as actor or subject. Other organization, financial,
-- scoring, and immutable records are retained. Auth users are soft-deleted so
-- their UUID remains valid for those references. Cleanup runs in a BEFORE
-- UPDATE OF deleted_at trigger on auth.users, inside GoTrue's soft-delete
-- transaction. A hashed audit record stores counts and has no auth-user FK.
-- Preconditions: user-linked development/import/Copilot tables from the prior
-- migrations are installed. Missing optional tables are skipped defensively.
-- Rollback: stop callers, drop the auth.users trigger, then revoke/drop these
-- RPCs and audit table. Soft-deleted Auth users and erased personal records are
-- not recoverable; never use hard-delete mode.
-- Scope: nullable profile fields and known enrollment/staff-directory copies
-- are scrubbed. This does not erase arbitrary names/emails in unrelated notes,
-- documents, or immutable audit/financial records. Known image objects are
-- queued and purged after commit; failed/unknown/shared paths remain durable.
-- Storage: the Auth transaction enqueues only known personal avatar/staff-photo
-- keys. delete-account drains at most ten after commit; configure a service-only
-- invocation of delete-account-storage-cleanup to retry backlog. This migration
-- does not install a cron job. Shared/unknown keys remain for manual review.

begin;

create table if not exists public.sd_account_deletion_audit (
  id uuid primary key default gen_random_uuid(),
  subject_hash text not null,
  status text not null check (status = 'completed'),
  deleted_record_counts jsonb not null default '{}'::jsonb,
  completed_at timestamptz not null default now()
);
alter table public.sd_account_deletion_audit enable row level security;
revoke all on public.sd_account_deletion_audit from public, anon, authenticated;
grant select, insert, update on public.sd_account_deletion_audit to service_role;

-- Durable, service-only queue for personal images that live in object storage.
-- This outbox is written by the auth.users soft-delete trigger before profile
-- pointers are cleared; actual object removal occurs only after Auth commits.
create table if not exists public.sd_account_deletion_storage_outbox (
  id uuid primary key default gen_random_uuid(),
  account_user_id uuid not null references auth.users(id) on delete restrict,
  bucket_id text not null check (bucket_id = 'avatars'),
  object_path text,
  object_path_sha256 text not null check (object_path_sha256 ~ '^[0-9a-f]{64}$'),
  source_kind text not null check (source_kind in ('profile_avatar', 'public_staff_photo')),
  directory_id uuid,
  status text not null default 'pending'
    check (status in ('pending', 'processing', 'completed', 'manual_review')),
  attempts integer not null default 0 check (attempts between 0 and 100),
  available_at timestamptz not null default now(),
  claimed_at timestamptz,
  claim_token uuid,
  completed_at timestamptz,
  last_error_code text check (last_error_code is null or char_length(last_error_code) <= 80),
  created_at timestamptz not null default now(),
  check (object_path is null or (char_length(object_path) between 1 and 1024)),
  check (object_path is not null or status = 'manual_review'),
  check (
    (status = 'processing' and claimed_at is not null and claim_token is not null)
    or (status <> 'processing' and claimed_at is null and claim_token is null)
  )
);
create unique index if not exists sd_account_deletion_storage_outbox_identity
  on public.sd_account_deletion_storage_outbox(account_user_id, bucket_id, object_path)
  where object_path is not null;
create index if not exists sd_account_deletion_storage_outbox_ready
  on public.sd_account_deletion_storage_outbox(status, available_at, created_at)
  where status in ('pending', 'processing');
alter table public.sd_account_deletion_storage_outbox enable row level security;
revoke all on public.sd_account_deletion_storage_outbox from public, anon, authenticated;
grant select, insert, update on public.sd_account_deletion_storage_outbox to service_role;

create or replace function public.sd_enqueue_account_deletion_storage_path(
  p_actor_id uuid,
  p_source_kind text,
  p_directory_id uuid,
  p_object_path text
)
returns void
language plpgsql
security definer
set search_path = public, auth, extensions, pg_temp
as $$
declare
  v_allowlisted boolean := false;
  v_shared boolean := false;
  v_safe_path text;
  v_directory_id uuid := p_directory_id;
begin
  if p_actor_id is null or p_source_kind is null
     or p_source_kind not in ('profile_avatar', 'public_staff_photo')
     or p_object_path is null or p_object_path = '' then
    return;
  end if;

  if p_object_path = p_actor_id::text || '/profile.jpg' then
    v_allowlisted := true;
  elsif p_source_kind = 'profile_avatar' then
    select d.id into v_directory_id
    from public.sd_training_staff_directory d
    where d.user_id = p_actor_id
      and p_object_path in (
        'trainers/' || d.id::text || '/profile.jpg',
        'trainers/' || d.id::text || '/profile.png',
        'trainers/' || d.id::text || '/profile.webp'
      )
    limit 1;
    v_allowlisted := v_directory_id is not null;
  elsif p_directory_id is not null
     and exists (
       select 1 from public.sd_training_staff_directory d
       where d.id = p_directory_id and d.user_id = p_actor_id
     )
     and p_object_path in (
       'trainers/' || p_directory_id::text || '/profile.jpg',
       'trainers/' || p_directory_id::text || '/profile.png',
       'trainers/' || p_directory_id::text || '/profile.webp'
     ) then
    v_allowlisted := true;
  end if;

  if v_allowlisted and exists (
    select 1 from public.profiles p
    where p.id <> p_actor_id and p.avatar_path = p_object_path
  ) then
    v_shared := true;
  end if;
  if v_allowlisted and to_regclass('public.sd_public_staff_profiles') is not null
     and exists (
       select 1
       from public.sd_public_staff_profiles profile
       left join public.sd_training_staff_directory directory
         on directory.id = profile.trainer_directory_id
       where profile.photo_path = p_object_path
         and (
           (profile.user_id is not null and profile.user_id <> p_actor_id)
           or (directory.user_id is not null and directory.user_id <> p_actor_id)
           or (profile.user_id is null and directory.user_id is null)
         )
     ) then
    v_shared := true;
  end if;
  if v_shared then
    v_allowlisted := false;
  end if;

  v_safe_path := case when char_length(p_object_path) <= 1024 then p_object_path else null end;
  insert into public.sd_account_deletion_storage_outbox(
    account_user_id, bucket_id, object_path, object_path_sha256, source_kind,
    directory_id, status, last_error_code
  ) values (
    p_actor_id, 'avatars', v_safe_path,
    encode(extensions.digest(convert_to(p_object_path, 'UTF8'), 'sha256'), 'hex'),
    p_source_kind, v_directory_id,
    case when v_allowlisted and v_safe_path is not null then 'pending' else 'manual_review' end,
    case when v_allowlisted and v_safe_path is not null then null
      when v_shared then 'path_shared_by_other_profile'
      else 'path_not_allowlisted' end
  ) on conflict (account_user_id, bucket_id, object_path) where object_path is not null do nothing;
end;
$$;
revoke all on function public.sd_enqueue_account_deletion_storage_path(uuid, text, uuid, text)
  from public, anon, authenticated, service_role;

create or replace function public.sd_claim_account_deletion_storage_cleanup(
  p_actor_id uuid default null,
  p_limit integer default 10
)
returns table (
  outbox_id uuid,
  account_user_id uuid,
  bucket_id text,
  object_path text,
  source_kind text,
  directory_id uuid,
  directory_owned_by_account boolean,
  auth_deleted boolean,
  claim_token uuid
)
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $$
declare
  v_row public.sd_account_deletion_storage_outbox%rowtype;
  v_claim_token uuid;
begin
  if auth.role() is distinct from 'service_role' then
    raise exception using errcode = '42501', message = 'service_role_required';
  end if;
  if p_limit is null or p_limit < 1 or p_limit > 10 then
    raise exception using errcode = '22023', message = 'account_deletion_storage_limit_invalid';
  end if;
  if p_actor_id is not null and not exists (
    select 1 from auth.users u where u.id = p_actor_id and u.deleted_at is not null
  ) then
    raise exception using errcode = 'P0001', message = 'account_deletion_not_committed';
  end if;

  for v_row in
    select q.*
    from public.sd_account_deletion_storage_outbox q
    join auth.users u on u.id = q.account_user_id and u.deleted_at is not null
    where (p_actor_id is null or q.account_user_id = p_actor_id)
      and (
        (q.status = 'pending' and q.available_at <= now())
        or (q.status = 'processing' and q.claimed_at < now() - interval '5 minutes')
      )
    order by q.created_at, q.id
    limit p_limit
    for update of q skip locked
  loop
    -- Crashed workers consume an attempt when reclaimed. Stop before increment
    -- so repeated crashes can never violate the table's attempts constraint.
    if v_row.attempts >= 8 then
      update public.sd_account_deletion_storage_outbox q
      set status = 'manual_review', claimed_at = null, claim_token = null,
          last_error_code = 'storage_remove_retry_limit'
      where q.id = v_row.id;
      continue;
    end if;

    if v_row.bucket_id <> 'avatars' or v_row.object_path is null
       or not (
         v_row.object_path = v_row.account_user_id::text || '/profile.jpg'
         or (
           v_row.directory_id is not null
           and exists (
             select 1 from public.sd_training_staff_directory d
             where d.id = v_row.directory_id and d.user_id = v_row.account_user_id
           )
           and v_row.object_path in (
             'trainers/' || v_row.directory_id::text || '/profile.jpg',
             'trainers/' || v_row.directory_id::text || '/profile.png',
             'trainers/' || v_row.directory_id::text || '/profile.webp'
           )
         )
       ) then
      update public.sd_account_deletion_storage_outbox q
      set status = 'manual_review', claimed_at = null, claim_token = null,
          last_error_code = 'path_not_allowlisted'
      where q.id = v_row.id;
      continue;
    end if;

    -- Recheck ownership at claim time: the queue can wait while profile or
    -- public-staff pointers change. Never remove an object still referenced by
    -- another account or by a detached/shared public staff profile.
    if exists (
      select 1 from public.profiles p
      where p.id <> v_row.account_user_id and p.avatar_path = v_row.object_path
    ) or exists (
      select 1
      from public.sd_public_staff_profiles profile
      left join public.sd_training_staff_directory directory
        on directory.id = profile.trainer_directory_id
      where profile.photo_path = v_row.object_path
        and (
          (profile.user_id is not null and profile.user_id <> v_row.account_user_id)
          or (directory.user_id is not null and directory.user_id <> v_row.account_user_id)
          or (profile.user_id is null and directory.user_id is null)
        )
    ) then
      update public.sd_account_deletion_storage_outbox q
      set status = 'manual_review', claimed_at = null, claim_token = null,
          last_error_code = 'path_shared_by_other_profile'
      where q.id = v_row.id;
      continue;
    end if;

    v_claim_token := gen_random_uuid();
    update public.sd_account_deletion_storage_outbox q
    set status = 'processing', claimed_at = now(), claim_token = v_claim_token,
        attempts = q.attempts + 1,
        last_error_code = null
    where q.id = v_row.id;
    outbox_id := v_row.id;
    account_user_id := v_row.account_user_id;
    bucket_id := v_row.bucket_id;
    object_path := v_row.object_path;
    source_kind := v_row.source_kind;
    directory_id := v_row.directory_id;
    directory_owned_by_account := v_row.directory_id is not null and exists (
      select 1 from public.sd_training_staff_directory d
      where d.id = v_row.directory_id and d.user_id = v_row.account_user_id
    );
    auth_deleted := true;
    claim_token := v_claim_token;
    return next;
  end loop;
end;
$$;
revoke all on function public.sd_claim_account_deletion_storage_cleanup(uuid, integer)
  from public, anon, authenticated;
grant execute on function public.sd_claim_account_deletion_storage_cleanup(uuid, integer)
  to service_role;

create or replace function public.sd_finish_account_deletion_storage_cleanup(
  p_outbox_id uuid,
  p_claim_token uuid,
  p_deleted boolean,
  p_error_code text default null,
  p_manual_review boolean default false
)
returns void
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $$
declare
  v_attempts integer;
begin
  if auth.role() is distinct from 'service_role' then
    raise exception using errcode = '42501', message = 'service_role_required';
  end if;
  if p_outbox_id is null or p_claim_token is null or p_deleted is null or p_manual_review is null then
    raise exception using errcode = '22023', message = 'account_deletion_storage_result_required';
  end if;
  select q.attempts into v_attempts
  from public.sd_account_deletion_storage_outbox q
  where q.id = p_outbox_id and q.status = 'processing'
    and q.claim_token = p_claim_token
    and q.claimed_at >= now() - interval '5 minutes'
  for update;
  if not found then
    raise exception using errcode = 'P0001', message = 'account_deletion_storage_claim_missing';
  end if;
  if p_manual_review then
    update public.sd_account_deletion_storage_outbox
    set status = 'manual_review', claimed_at = null, claim_token = null,
        last_error_code = 'path_not_allowlisted'
    where id = p_outbox_id;
  elsif p_deleted then
    update public.sd_account_deletion_storage_outbox
    set status = 'completed', completed_at = now(), claimed_at = null, claim_token = null,
        last_error_code = null
    where id = p_outbox_id;
  elsif v_attempts >= 8 then
    update public.sd_account_deletion_storage_outbox
    set status = 'manual_review', claimed_at = null, claim_token = null,
        last_error_code = 'storage_remove_retry_limit'
    where id = p_outbox_id;
  else
    update public.sd_account_deletion_storage_outbox
    set status = 'pending', claimed_at = null, claim_token = null,
        available_at = now() + make_interval(secs => least(21600, 60 * power(2, least(v_attempts, 8)))::integer),
        last_error_code = case when p_error_code = 'storage_remove_failed'
          then p_error_code else 'storage_remove_failed' end
    where id = p_outbox_id;
  end if;
end;
$$;
revoke all on function public.sd_finish_account_deletion_storage_cleanup(uuid, uuid, boolean, text, boolean)
  from public, anon, authenticated;
grant execute on function public.sd_finish_account_deletion_storage_cleanup(uuid, uuid, boolean, text, boolean)
  to service_role;

create or replace function public.sd_account_deletion_storage_cleanup_status(p_actor_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $$
begin
  if auth.role() is distinct from 'service_role' then
    raise exception using errcode = '42501', message = 'service_role_required';
  end if;
  if p_actor_id is null or not exists (
    select 1 from auth.users u where u.id = p_actor_id and u.deleted_at is not null
  ) then
    raise exception using errcode = 'P0001', message = 'account_deletion_not_committed';
  end if;
  return (
    select jsonb_build_object(
      'pending', count(*) filter (where q.status = 'pending'),
      'processing', count(*) filter (where q.status = 'processing'),
      'manual_review', count(*) filter (where q.status = 'manual_review'),
      'completed', count(*) filter (where q.status = 'completed')
    )
    from public.sd_account_deletion_storage_outbox q
    where q.account_user_id = p_actor_id
  );
end;
$$;
revoke all on function public.sd_account_deletion_storage_cleanup_status(uuid)
  from public, anon, authenticated;
grant execute on function public.sd_account_deletion_storage_cleanup_status(uuid)
  to service_role;

create or replace function public.sd_delete_account_personal_data(p_actor_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_counts jsonb := '{}'::jsonb;
  v_count bigint;
  v_observation_deleted bigint := 0;
  v_hash text;
  v_actor text := p_actor_id::text;
  v_spec text[] := array[
    'sd_development_copilot_feedback:player_id,actor_id',
    'sd_development_parent_draft_review_events:player_id,actor_id',
    'sd_development_generation_attempts:player_id,actor_id',
    'sd_development_ai_usage_ledger:player_id,actor_id',
    'sd_development_copilot_message_citations:player_id',
    'sd_development_report_evidence:player_id',
    'sd_development_report_review_events:actor_id',
    'sd_development_alert_evidence:player_id',
    'sd_development_alert_events:actor_id',
    'sd_development_alerts:player_id,acknowledged_by,dismissed_by,resolved_by,archived_by',
    'sd_development_parent_update_drafts:player_id,created_by,reviewed_by,approved_by,rejected_by,archived_by',
    'sd_development_copilot_messages:player_id,actor_id',
    'sd_development_copilot_conversations:player_id,created_by',
    'sd_development_external_player_identities:player_id,linked_by',
    'sd_development_import_mapping_profiles:created_by',
    'sd_development_import_jobs:player_id,requested_by',
    'sd_player_metric_observations:player_id,corrected_by'
  ];
  v_parts text[];
  v_table text;
  v_predicate text;
  v_reports uuid[];
  v_alerts uuid[];
  v_conversations uuid[];
  v_messages uuid[];
  v_drafts uuid[];
  v_questions uuid[];
  v_observation_depth integer;
  v_profile_column text;
  v_profile_is_nullable text;
  v_profile_assignments text[] := array[]::text[];
  v_profile_pii_columns text[] := array[
    'bio', 'avatar_path', 'phone', 'grad_year', 'primary_position', 'bats',
    'throws', 'school', 'team', 'height_in', 'weight_lb', 'notes',
    'professional_title', 'specialties', 'website', 'years_experience',
    'instagram_url', 'perfect_game_url', 'username', 'email'
  ];
begin
  if p_actor_id is null then
    raise exception using errcode = '22023', message = 'account_deletion_actor_required';
  end if;
  v_hash := encode(extensions.digest(convert_to(v_actor, 'UTF8'), 'sha256'), 'hex');

  -- Delete dependents of records owned by the departing user even when another
  -- staff member authored the dependent event or citation.
  if to_regclass('public.sd_development_reports') is not null then
    select array_agg(id) into v_reports
    from public.sd_development_reports
    where player_id = p_actor_id or requested_by = p_actor_id or reviewed_by = p_actor_id;
  end if;
  if to_regclass('public.sd_development_alerts') is not null then
    select array_agg(id) into v_alerts
    from public.sd_development_alerts
    where player_id = p_actor_id or acknowledged_by = p_actor_id
       or dismissed_by = p_actor_id or resolved_by = p_actor_id or archived_by = p_actor_id
       or (v_reports is not null and report_id = any(v_reports));
  end if;
  if to_regclass('public.sd_development_copilot_conversations') is not null then
    select array_agg(id) into v_conversations
    from public.sd_development_copilot_conversations
    where player_id = p_actor_id or created_by = p_actor_id;
  end if;
  if to_regclass('public.sd_development_copilot_messages') is not null then
    select array_agg(id) into v_messages
    from public.sd_development_copilot_messages
    where player_id = p_actor_id or actor_id = p_actor_id
       or (v_conversations is not null and conversation_id = any(v_conversations));
  end if;
  if to_regclass('public.sd_development_parent_update_drafts') is not null then
    select array_agg(id) into v_drafts
    from public.sd_development_parent_update_drafts
    where player_id = p_actor_id or created_by = p_actor_id or reviewed_by = p_actor_id
       or approved_by = p_actor_id or rejected_by = p_actor_id or archived_by = p_actor_id
       or (v_messages is not null and source_message_id = any(v_messages))
       or (v_conversations is not null and conversation_id = any(v_conversations));
  end if;
  if to_regclass('public.sd_development_copilot_pending_questions') is not null then
    select array_agg(id) into v_questions
    from public.sd_development_copilot_pending_questions
    where player_id = p_actor_id
       or (v_conversations is not null and conversation_id = any(v_conversations))
       or (v_messages is not null and (
         assistant_message_id = any(v_messages) or response_message_id = any(v_messages)
       ));
  end if;
  if v_questions is not null
     and to_regclass('public.sd_development_copilot_messages') is not null then
    -- The pending-question/message foreign keys form a cycle. Clear nullable
    -- links in a constraint-valid state, delete question rows, then messages.
    update public.sd_development_copilot_messages m
    set in_reply_to_question_id = null
    where m.in_reply_to_question_id = any(v_questions);
    update public.sd_development_copilot_pending_questions q
    set status = 'expired', answered_at = null, response_message_id = null
    where q.id = any(v_questions);
    delete from public.sd_development_copilot_pending_questions q
    where q.id = any(v_questions);
  end if;

  if to_regclass('public.sd_development_import_row_errors') is not null
     and to_regclass('public.sd_development_import_jobs') is not null then
    delete from public.sd_development_import_row_errors e
    where e.import_job_id in (
      select j.id from public.sd_development_import_jobs j
      where j.player_id = p_actor_id or j.requested_by = p_actor_id
    );
    get diagnostics v_count = row_count;
    v_counts := v_counts || jsonb_build_object('sd_development_import_row_errors', v_count);
  end if;
  if to_regclass('public.sd_player_metric_observations') is not null then
    -- Imported observations restrict deletion of their import job. Correction
    -- rows can in turn be referenced by later corrections, so remove affected
    -- correction chains deepest-first before deleting any roots.
    with recursive affected(id, org_id, player_id, depth, path) as (
      select o.id, o.org_id, o.player_id, 0, array[o.id]
      from public.sd_player_metric_observations o
      where o.player_id = p_actor_id or o.corrected_by = p_actor_id
         or o.import_job_id in (
           select j.id from public.sd_development_import_jobs j
           where j.player_id = p_actor_id or j.requested_by = p_actor_id
         )
      union all
      select child.id, child.org_id, child.player_id, parent.depth + 1,
        parent.path || child.id
      from public.sd_player_metric_observations child
      join affected parent on child.correction_of_id = parent.id
        and child.org_id = parent.org_id and child.player_id = parent.player_id
      where not child.id = any(parent.path)
    )
    select coalesce(max(depth), -1) into v_observation_depth from affected;
    if v_observation_depth >= 0 then
      for v_observation_depth in reverse v_observation_depth..0 loop
        with recursive affected(id, org_id, player_id, depth, path) as (
          select o.id, o.org_id, o.player_id, 0, array[o.id]
          from public.sd_player_metric_observations o
          where o.player_id = p_actor_id or o.corrected_by = p_actor_id
             or o.import_job_id in (
               select j.id from public.sd_development_import_jobs j
               where j.player_id = p_actor_id or j.requested_by = p_actor_id
             )
          union all
          select child.id, child.org_id, child.player_id, parent.depth + 1,
            parent.path || child.id
          from public.sd_player_metric_observations child
          join affected parent on child.correction_of_id = parent.id
            and child.org_id = parent.org_id and child.player_id = parent.player_id
          where not child.id = any(parent.path)
        )
        delete from public.sd_player_metric_observations o
        where o.id in (select a.id from affected a where a.depth = v_observation_depth);
        get diagnostics v_count = row_count;
        v_observation_deleted := v_observation_deleted + v_count;
      end loop;
    end if;
    v_counts := v_counts || jsonb_build_object('sd_player_metric_observations', v_observation_deleted);
  end if;
  if to_regclass('public.sd_development_copilot_message_citations') is not null then
    delete from public.sd_development_copilot_message_citations c
    where c.player_id = p_actor_id
       or (v_messages is not null and c.message_id = any(v_messages))
       or (v_reports is not null and c.report_evidence_id in (
         select e.id from public.sd_development_report_evidence e
         where e.report_id = any(v_reports)
       ));
  end if;
  if to_regclass('public.sd_development_copilot_feedback') is not null then
    delete from public.sd_development_copilot_feedback f
    where f.player_id = p_actor_id or f.actor_id = p_actor_id
       or (v_conversations is not null and f.conversation_id = any(v_conversations))
       or (v_messages is not null and f.message_id = any(v_messages));
  end if;
  if to_regclass('public.sd_development_parent_draft_review_events') is not null then
    delete from public.sd_development_parent_draft_review_events e
    where e.player_id = p_actor_id
       or (v_drafts is not null and e.draft_id = any(v_drafts));
  end if;
  if to_regclass('public.sd_development_report_evidence') is not null then
    delete from public.sd_development_report_evidence e
    where e.player_id = p_actor_id
       or (v_reports is not null and e.report_id = any(v_reports));
  end if;
  if to_regclass('public.sd_development_report_review_events') is not null then
    delete from public.sd_development_report_review_events e
    where e.actor_id = p_actor_id
       or (v_reports is not null and e.report_id = any(v_reports));
  end if;
  if to_regclass('public.sd_development_alert_evidence') is not null then
    delete from public.sd_development_alert_evidence e
    where e.player_id = p_actor_id
       or (v_alerts is not null and e.alert_id = any(v_alerts));
  end if;
  if to_regclass('public.sd_development_alert_events') is not null then
    delete from public.sd_development_alert_events e
    where e.actor_id = p_actor_id
       or (v_alerts is not null and e.alert_id = any(v_alerts));
  end if;
  if to_regclass('public.sd_development_alerts') is not null then
    delete from public.sd_development_alerts a
    where a.id = any(coalesce(v_alerts, '{}'::uuid[]));
    get diagnostics v_count = row_count;
    v_counts := v_counts || jsonb_build_object('sd_development_alerts', v_count);
  end if;
  if to_regclass('public.sd_development_reports') is not null then
    delete from public.sd_development_reports r
    where r.id = any(coalesce(v_reports, '{}'::uuid[]));
    get diagnostics v_count = row_count;
    v_counts := v_counts || jsonb_build_object('sd_development_reports', v_count);
  end if;

  -- Generation attempts retain composite RESTRICT links to messages and
  -- conversations in the selected roots, including attempts written by other
  -- staff members. Remove them before deleting those roots and preserve counts.
  if to_regclass('public.sd_development_generation_attempts') is not null then
    delete from public.sd_development_generation_attempts a
    where a.player_id = p_actor_id or a.actor_id = p_actor_id
       or (v_messages is not null and a.message_id = any(v_messages))
       or (v_conversations is not null and a.conversation_id = any(v_conversations));
    get diagnostics v_count = row_count;
    v_counts := v_counts || jsonb_build_object('sd_development_generation_attempts', v_count);
  end if;

  -- Draft review events were removed above using v_drafts; now remove every
  -- selected draft root before their source messages/conversations are deleted.
  if to_regclass('public.sd_development_parent_update_drafts') is not null then
    delete from public.sd_development_parent_update_drafts d
    where d.id = any(coalesce(v_drafts, '{}'::uuid[]));
    get diagnostics v_count = row_count;
    v_counts := v_counts || jsonb_build_object('sd_development_parent_update_drafts', v_count);
  end if;

  foreach v_table in array v_spec loop
    v_parts := string_to_array(v_table, ':');
    v_table := v_parts[1];
    if v_table in ('sd_development_copilot_message_citations',
         'sd_development_report_evidence','sd_development_report_review_events',
         'sd_development_alert_evidence','sd_development_alert_events',
         'sd_development_alerts','sd_development_reports',
         'sd_development_parent_draft_review_events','sd_development_copilot_feedback',
         'sd_development_generation_attempts','sd_development_parent_update_drafts',
         'sd_player_metric_observations') then
      continue;
    end if;
    if to_regclass('public.' || v_table) is null then continue; end if;
    v_parts := string_to_array(v_parts[2], ',');
    select string_agg(format('%I = $1', requested.column_name), ' or ')
      into v_predicate
    from unnest(v_parts) as requested(column_name)
    where exists (
      select 1 from information_schema.columns c
      where c.table_schema = 'public' and c.table_name = v_table
        and c.column_name = requested.column_name
    );
    if v_predicate is null then continue; end if;
    execute format('delete from public.%I where %s', v_table, v_predicate)
      using p_actor_id;
    get diagnostics v_count = row_count;
    v_counts := v_counts || jsonb_build_object(v_table, v_count);
  end loop;
  -- Keep the stable profile UUID/role/timestamps for retained records. Clear
  -- only nullable personal fields from an explicit allowlist, discovered via
  -- the catalog so this remains safe when optional profile migrations differ.
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'profiles'
      and column_name = 'full_name'
  ) then
    v_profile_assignments := array_append(v_profile_assignments, 'full_name = ''Deleted account''');
  end if;
  foreach v_profile_column in array v_profile_pii_columns loop
    select c.is_nullable into v_profile_is_nullable
    from information_schema.columns c
    where c.table_schema = 'public' and c.table_name = 'profiles'
      and c.column_name = v_profile_column;
    if v_profile_is_nullable = 'YES' then
      v_profile_assignments := array_append(
        v_profile_assignments,
        format('%I = null', v_profile_column)
      );
    end if;
    v_profile_is_nullable := null;
  end loop;
  if cardinality(v_profile_assignments) > 0 then
    execute format(
      'update public.profiles set %s where id = $1',
      array_to_string(v_profile_assignments, ', ')
    ) using p_actor_id;
    get diagnostics v_count = row_count;
  else
    v_count := 0;
  end if;
  v_counts := v_counts || jsonb_build_object('public.profiles_anonymized', v_count);

  -- Enrollment and public staff-directory rows copy identity fields instead of
  -- joining the profile at read time. Preserve their stable row/financial links
  -- but remove copied contact/profile content for this account only.
  if to_regclass('public.sd_organization_athletes') is not null then
    update public.sd_organization_athletes
    set display_name = 'Deleted athlete',
        invited_email = null,
        date_of_birth = null,
        legacy_profile_id = null,
        legacy_profile_snapshot = '{}'::jsonb,
        status = 'inactive'
    where athlete_user_id = p_actor_id;
    get diagnostics v_count = row_count;
    v_counts := v_counts || jsonb_build_object('sd_organization_athletes_anonymized', v_count);
  end if;
  if to_regclass('public.sd_training_staff_directory') is not null then
    update public.sd_training_staff_directory
    set display_name = 'Deleted staff', invited_email = null, public_title = null,
        specialties = null, account_status = 'disabled', status = 'inactive'
    where user_id = p_actor_id;
    get diagnostics v_count = row_count;
    v_counts := v_counts || jsonb_build_object('sd_training_staff_directory_anonymized', v_count);
  end if;
  if to_regclass('public.sd_public_staff_profiles') is not null then
    update public.sd_public_staff_profiles
    set is_published = false, display_name = 'Deleted staff', public_title = null,
        biography = null, photo_path = null, specialties = null, public_email = null,
        show_contact_button = false, social_links = '{}'::jsonb
    where user_id = p_actor_id;
    get diagnostics v_count = row_count;
    v_counts := v_counts || jsonb_build_object('sd_public_staff_profiles_anonymized', v_count);
  end if;

  -- Preserve membership history with the schema's actual disabled state.
  update public.sd_org_memberships
  set status = 'disabled'
  where user_id = p_actor_id and status <> 'disabled';
  get diagnostics v_count = row_count;
  v_counts := v_counts || jsonb_build_object('sd_org_memberships_disabled', v_count);

  -- Remove parent/child access links while keeping referenced UUIDs intact.
  delete from public.sd_parent_child_links
  where parent_id = p_actor_id or child_id = p_actor_id;
  get diagnostics v_count = row_count;
  v_counts := v_counts || jsonb_build_object('sd_parent_child_links_removed', v_count);

  -- Notification delivery history can restrict device deletion. Disable the
  -- device and replace its APNs token with a non-routable digest instead.
  if to_regclass('public.sd_push_devices') is not null then
    update public.sd_push_devices d
    set device_token = encode(
          extensions.digest(convert_to('deleted:' || d.id::text, 'UTF8'), 'sha256'),
          'hex'
        ),
        notifications_authorized = false,
        disabled_at = coalesce(d.disabled_at, now()),
        disable_reason = 'account_deleted'
    where d.user_id = p_actor_id;
    get diagnostics v_count = row_count;
    v_counts := v_counts || jsonb_build_object('sd_push_devices_scrubbed', v_count);
  end if;
  return v_counts;
end;
$$;
revoke all on function public.sd_delete_account_personal_data(uuid)
  from public, anon, authenticated, service_role;

create or replace function public.sd_prepare_account_deletion(p_actor_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, auth, extensions, pg_temp
as $$
begin
  if auth.role() is distinct from 'service_role' then
    raise exception using errcode = '42501', message = 'service_role_required';
  end if;
  if p_actor_id is null then
    raise exception using errcode = '22023', message = 'account_deletion_actor_required';
  end if;
  if not exists (
    select 1 from auth.users u where u.id = p_actor_id and u.deleted_at is null
  ) then
    raise exception using errcode = 'P0001', message = 'account_deletion_user_not_active';
  end if;
  if exists (
    select 1
    from public.sd_org_memberships actor_membership
    where actor_membership.user_id = p_actor_id
      and actor_membership.role = 'owner'
      and actor_membership.status = 'active'
      and (
        select count(*)
        from public.sd_org_memberships active_owner
        where active_owner.org_id = actor_membership.org_id
          and active_owner.role = 'owner'
          and active_owner.status = 'active'
      ) = 1
  ) then
    raise exception using errcode = 'P0001', message = 'account_deletion_sole_active_owner';
  end if;
  -- Read-only eligibility check. No personal or organization records are changed.
  return jsonb_build_object('eligible', true, 'auth_mode', 'soft_delete');
end;
$$;
revoke all on function public.sd_prepare_account_deletion(uuid) from public, anon, authenticated;
grant execute on function public.sd_prepare_account_deletion(uuid) to service_role;

create or replace function public.sd_cleanup_account_personal_data_before_auth_soft_delete()
returns trigger
language plpgsql
security definer
set search_path = public, auth, extensions, pg_temp
as $$
declare
  v_counts jsonb;
  v_hash text;
  v_owner_org_ids uuid[];
  v_avatar_path text;
  v_staff_photo record;
begin
  if old.deleted_at is not null or new.deleted_at is null then
    return new;
  end if;

  select coalesce(array_agg(m.org_id order by m.org_id), '{}'::uuid[])
    into v_owner_org_ids
  from public.sd_org_memberships m
  where m.user_id = old.id and m.role = 'owner' and m.status = 'active';

  -- Serialize soft-deletion transactions for owners in the same organization,
  -- then repeat the ownership check before changing any domain data.
  perform 1
  from public.sd_orgs o
  where o.id = any(v_owner_org_ids)
  order by o.id
  for update;
  if exists (
    select 1
    from public.sd_org_memberships actor_membership
    where actor_membership.user_id = old.id
      and actor_membership.role = 'owner'
      and actor_membership.status = 'active'
      and (
        select count(*)
        from public.sd_org_memberships active_owner
        where active_owner.org_id = actor_membership.org_id
          and active_owner.role = 'owner'
          and active_owner.status = 'active'
      ) = 1
  ) then
    raise exception using errcode = 'P0001', message = 'account_deletion_sole_active_owner';
  end if;

  -- GoTrue soft-deletes inside a database transaction. Any cleanup error aborts
  -- the Auth update and rolls back all work performed by this trigger.
  -- Snapshot only known personal image references before their DB pointers are
  -- cleared. The queue rejects unknown/shared keys for manual review.
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'profiles'
      and column_name = 'avatar_path'
  ) then
    select p.avatar_path into v_avatar_path
    from public.profiles p where p.id = old.id;
    if v_avatar_path is not null then
      perform public.sd_enqueue_account_deletion_storage_path(
        old.id, 'profile_avatar', null, v_avatar_path
      );
    end if;
  end if;
  if to_regclass('public.sd_public_staff_profiles') is not null
     and to_regclass('public.sd_training_staff_directory') is not null then
    for v_staff_photo in
      select profile.photo_path, profile.trainer_directory_id
      from public.sd_public_staff_profiles profile
      left join public.sd_training_staff_directory directory
        on directory.id = profile.trainer_directory_id
      where profile.user_id = old.id or directory.user_id = old.id
    loop
      if v_staff_photo.photo_path is not null then
        perform public.sd_enqueue_account_deletion_storage_path(
          old.id, 'public_staff_photo', v_staff_photo.trainer_directory_id,
          v_staff_photo.photo_path
        );
      end if;
    end loop;
  end if;

  v_counts := public.sd_delete_account_personal_data(old.id);
  v_hash := encode(extensions.digest(convert_to(old.id::text, 'UTF8'), 'sha256'), 'hex');
  insert into public.sd_account_deletion_audit(subject_hash, status, deleted_record_counts)
  values (v_hash, 'completed', v_counts);
  return new;
end;
$$;
revoke all on function public.sd_cleanup_account_personal_data_before_auth_soft_delete()
  from public, anon, authenticated, service_role;

drop trigger if exists trg_sd_cleanup_account_personal_data_before_auth_delete on auth.users;
drop trigger if exists trg_sd_cleanup_account_personal_data_before_auth_soft_delete on auth.users;
create trigger trg_sd_cleanup_account_personal_data_before_auth_soft_delete
before update of deleted_at on auth.users
for each row
when (old.deleted_at is null and new.deleted_at is not null)
execute function public.sd_cleanup_account_personal_data_before_auth_soft_delete();

-- Rollback only before any soft-delete succeeds: drop the trigger, then revoke
-- and drop the RPCs/audit table. Soft-deleted Auth users and erased personal
-- records cannot be recovered through this migration. Do not hard-delete users.

commit;
