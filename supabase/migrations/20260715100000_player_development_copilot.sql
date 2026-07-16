-- Home Plate Phase 11C-11E: private Coach/Player Copilot and staff parent drafts.
--
-- Purpose
-- - Add audience-isolated coach/player Copilot conversations, structured
--   messages, immutable citations, provider attempts, feedback, usage, and
--   coach-controlled parent update drafts.
-- - Preserve Phase 11A evidence/report lifecycle and Phase 11B imports unchanged.
-- - Keep authenticated clients read-only; all lifecycle writes are performed by
--   the verified-actor Edge Function through service-role-only RPCs.
--
-- Assumptions
-- - Phase 11A installed sd_development_actor_can_manage_player and
--   sd_development_can_manage_player.
-- - The Edge Function verifies the JWT before any service-role evidence query
--   and transfers the verified actor UUID into every mutation RPC.
-- - A missing feature-specific entitlement uses documented founding access;
--   active organization staff/player authorization remains mandatory.
--
-- Rollback guidance (manual, after exporting audit records)
-- 1. Revoke the audience-aware report/alert and dialogue RPCs before restoring
--   the retired Phase 11A/initial Copilot service-role grants.
-- 2. Drop the audience-specific policies, immutable-audience/pending-scope
--   triggers and read helpers, then drop the pending-question table.
-- 3. Only after preserving report/alert audit history, remove the audience FKs,
--   indexes and columns and restore the original idempotency/deduplication keys.
-- 4. Do not delete historical attempts, citations, feedback, review events,
--   reports, or alerts merely to roll back the application. Phase 11B import
--   observations and Phase 11A demo records remain untouched.

create table if not exists public.sd_development_copilot_prompt_versions (
  id uuid primary key default gen_random_uuid(),
  prompt_key text not null check (prompt_key ~ '^[a-z][a-z0-9_]*$'),
  use_case text not null check (use_case in (
    'coach_copilot_player_question', 'player_copilot_self_question',
    'player_development_summary',
    'parent_update_draft', 'staff_meeting_summary', 'alert_explanation'
  )),
  intended_audience text not null check (intended_audience in ('coach', 'player', 'staff', 'parent_draft', 'internal')),
  version text not null,
  evidence_schema_version text not null,
  output_schema_version text not null,
  safety_version text not null,
  template_metadata jsonb not null default '{}'::jsonb,
  is_active boolean not null default false,
  created_at timestamptz not null default now(),
  deprecated_at timestamptz,
  unique (prompt_key, use_case, intended_audience, version),
  check ((is_active and deprecated_at is null) or not is_active)
);

create unique index if not exists uq_sd_development_copilot_prompt_active
  on public.sd_development_copilot_prompt_versions(prompt_key, use_case, intended_audience)
  where is_active;

create table if not exists public.sd_development_copilot_conversations (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.sd_orgs(id) on delete restrict,
  player_id uuid not null references public.profiles(id) on delete restrict,
  created_by uuid not null references public.profiles(id) on delete restrict,
  audience text not null check (audience in ('coach', 'player')),
  title text not null check (char_length(title) between 1 and 160),
  status text not null default 'active' check (status in ('active', 'archived')),
  reporting_window_days integer not null default 90 check (reporting_window_days between 1 and 730),
  evidence_cutoff timestamptz not null,
  generation_mode text not null default 'deterministic' check (generation_mode in ('deterministic', 'model', 'hybrid', 'unavailable')),
  provider text not null default 'deterministic_template',
  model_identifier text,
  generator_version text not null,
  idempotency_key uuid not null,
  archived_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (org_id, created_by, audience, idempotency_key),
  unique (id, org_id),
  unique (id, org_id, player_id),
  unique (id, org_id, player_id, audience),
  check ((status = 'archived') = (archived_at is not null))
);

create table if not exists public.sd_development_copilot_messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null,
  org_id uuid not null references public.sd_orgs(id) on delete restrict,
  player_id uuid not null references public.profiles(id) on delete restrict,
  actor_id uuid references public.profiles(id) on delete restrict,
  audience text not null check (audience in ('coach', 'player')),
  role text not null check (role in ('user', 'assistant')),
  user_question text,
  structured_answer jsonb,
  rendered_answer text,
  quality_status text not null default 'unavailable' check (quality_status in ('sufficient', 'limited', 'stale', 'conflicting', 'unavailable', 'rejected')),
  evidence_cutoff timestamptz not null,
  generation_mode text not null check (generation_mode in ('deterministic', 'model', 'hybrid', 'unavailable')),
  provider text not null,
  model_identifier text,
  prompt_version text not null,
  generator_version text not null,
  generation_status text not null check (generation_status in ('pending', 'succeeded', 'failed', 'rejected')),
  safe_error_code text,
  idempotency_key uuid not null,
  archived_at timestamptz,
  created_at timestamptz not null default now(),
  unique (conversation_id, audience, role, idempotency_key),
  unique (id, org_id),
  unique (id, org_id, player_id),
  unique (id, org_id, player_id, audience),
  constraint sd_development_copilot_message_conversation_fk
    foreign key (conversation_id, org_id, player_id, audience)
    references public.sd_development_copilot_conversations(id, org_id, player_id, audience) on delete restrict,
  constraint sd_development_copilot_message_shape_check check (
    (role = 'user' and actor_id is not null and user_question is not null
      and char_length(user_question) between 1 and 2000
      and structured_answer is null and rendered_answer is null)
    or
    (role = 'assistant' and user_question is null
      and ((generation_status = 'succeeded' and structured_answer is not null and rendered_answer is not null)
        or generation_status in ('failed', 'rejected')))
  )
);

create table if not exists public.sd_development_copilot_message_citations (
  id uuid primary key default gen_random_uuid(),
  message_id uuid not null,
  org_id uuid not null references public.sd_orgs(id) on delete restrict,
  player_id uuid not null references public.profiles(id) on delete restrict,
  audience text not null check (audience in ('coach', 'player')),
  evidence_key text not null,
  report_evidence_id uuid references public.sd_development_report_evidence(id) on delete restrict,
  source_entity_type text not null,
  source_record_id text not null,
  canonical_metric_key text,
  observed_value text,
  normalized_value numeric,
  unit text,
  observed_at timestamptz,
  display_label text not null,
  explanation text not null,
  section_key text not null,
  claim_identifier text not null,
  source_provider text,
  verification_status text,
  deterministic_rule_id text,
  evidence_snapshot jsonb not null,
  created_at timestamptz not null default now(),
  unique (message_id, audience, evidence_key, claim_identifier),
  constraint sd_development_copilot_citation_message_fk
    foreign key (message_id, org_id, player_id, audience)
    references public.sd_development_copilot_messages(id, org_id, player_id, audience) on delete restrict
);

create table if not exists public.sd_development_generation_attempts (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.sd_orgs(id) on delete restrict,
  actor_id uuid not null references public.profiles(id) on delete restrict,
  player_id uuid not null references public.profiles(id) on delete restrict,
  audience text not null check (audience in ('coach', 'player')),
  conversation_id uuid,
  message_id uuid,
  action_type text not null check (action_type in ('ask', 'retry_message', 'parent_update_draft')),
  generation_mode text not null check (generation_mode in ('deterministic', 'model', 'hybrid', 'unavailable')),
  provider text not null,
  model_identifier text,
  prompt_version text not null,
  generator_version text not null,
  retry_count integer not null default 0 check (retry_count between 0 and 10),
  status text not null check (status in ('started', 'succeeded', 'failed', 'rejected', 'limited')),
  safe_error_code text,
  input_size integer not null default 0 check (input_size >= 0),
  output_size integer not null default 0 check (output_size >= 0),
  input_tokens integer check (input_tokens is null or input_tokens >= 0),
  output_tokens integer check (output_tokens is null or output_tokens >= 0),
  latency_ms integer check (latency_ms is null or latency_ms >= 0),
  estimated_cost_microunits bigint check (estimated_cost_microunits is null or estimated_cost_microunits >= 0),
  request_fingerprint text not null check (request_fingerprint ~ '^[0-9a-f]{64}$'),
  safe_metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  unique (id, org_id),
  constraint sd_development_attempt_conversation_fk foreign key (conversation_id, org_id, player_id, audience)
    references public.sd_development_copilot_conversations(id, org_id, player_id, audience) on delete restrict,
  constraint sd_development_attempt_message_fk foreign key (message_id, org_id, player_id, audience)
    references public.sd_development_copilot_messages(id, org_id, player_id, audience) on delete restrict
);

create table if not exists public.sd_development_parent_update_drafts (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.sd_orgs(id) on delete restrict,
  player_id uuid not null references public.profiles(id) on delete restrict,
  conversation_id uuid,
  source_message_id uuid,
  created_by uuid not null references public.profiles(id) on delete restrict,
  status text not null default 'generated' check (status in ('generated', 'reviewed', 'approved', 'rejected', 'archived')),
  generated_original jsonb not null,
  edited_content jsonb not null,
  generated_rendered_text text not null,
  edited_rendered_text text not null,
  evidence_cutoff timestamptz not null,
  generation_mode text not null check (generation_mode in ('deterministic', 'model', 'hybrid')),
  provider text not null,
  model_identifier text,
  prompt_version text not null,
  generator_version text not null,
  idempotency_key uuid not null,
  reviewed_at timestamptz,
  reviewed_by uuid references public.profiles(id) on delete restrict,
  approved_at timestamptz,
  approved_by uuid references public.profiles(id) on delete restrict,
  rejected_at timestamptz,
  rejected_by uuid references public.profiles(id) on delete restrict,
  archived_at timestamptz,
  archived_by uuid references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (org_id, created_by, idempotency_key),
  unique (id, org_id),
  unique (id, org_id, player_id),
  constraint sd_development_parent_draft_conversation_fk foreign key (conversation_id, org_id, player_id)
    references public.sd_development_copilot_conversations(id, org_id, player_id) on delete restrict,
  constraint sd_development_parent_draft_message_fk foreign key (source_message_id, org_id, player_id)
    references public.sd_development_copilot_messages(id, org_id, player_id) on delete restrict
);

create table if not exists public.sd_development_parent_draft_review_events (
  id uuid primary key default gen_random_uuid(),
  draft_id uuid not null,
  org_id uuid not null references public.sd_orgs(id) on delete restrict,
  player_id uuid not null references public.profiles(id) on delete restrict,
  actor_id uuid not null references public.profiles(id) on delete restrict,
  event_type text not null check (event_type in ('generated', 'edited', 'reviewed', 'approved', 'rejected', 'archived')),
  from_status text,
  to_status text not null,
  safe_note text check (safe_note is null or char_length(safe_note) <= 2000),
  content_snapshot jsonb not null,
  created_at timestamptz not null default now(),
  constraint sd_development_parent_draft_event_fk foreign key (draft_id, org_id, player_id)
    references public.sd_development_parent_update_drafts(id, org_id, player_id) on delete restrict
);

create table if not exists public.sd_development_copilot_feedback (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.sd_orgs(id) on delete restrict,
  player_id uuid not null references public.profiles(id) on delete restrict,
  conversation_id uuid not null,
  message_id uuid not null,
  actor_id uuid not null references public.profiles(id) on delete restrict,
  audience text not null check (audience in ('coach', 'player')),
  feedback_type text not null check (feedback_type in (
    'helpful', 'not_helpful', 'incorrect', 'missing_context', 'wrong_evidence',
    'too_generic', 'unsafe', 'other'
  )),
  safe_note text check (safe_note is null or char_length(safe_note) <= 1000),
  created_at timestamptz not null default now(),
  unique (message_id, actor_id, audience),
  constraint sd_development_copilot_feedback_conversation_fk foreign key (conversation_id, org_id, player_id, audience)
    references public.sd_development_copilot_conversations(id, org_id, player_id, audience) on delete restrict,
  constraint sd_development_copilot_feedback_message_fk foreign key (message_id, org_id, player_id, audience)
    references public.sd_development_copilot_messages(id, org_id, player_id, audience) on delete restrict
);

create table if not exists public.sd_development_ai_usage_ledger (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.sd_orgs(id) on delete restrict,
  actor_id uuid not null references public.profiles(id) on delete restrict,
  player_id uuid not null references public.profiles(id) on delete restrict,
  audience text not null check (audience in ('coach', 'player')),
  provider text not null,
  model_identifier text,
  action_type text not null check (action_type in ('ask', 'retry_message', 'parent_update_draft')),
  generation_mode text not null check (generation_mode in ('deterministic', 'model', 'hybrid', 'unavailable')),
  input_size integer not null default 0 check (input_size >= 0),
  output_size integer not null default 0 check (output_size >= 0),
  input_tokens integer check (input_tokens is null or input_tokens >= 0),
  output_tokens integer check (output_tokens is null or output_tokens >= 0),
  latency_ms integer check (latency_ms is null or latency_ms >= 0),
  status text not null check (status in ('succeeded', 'failed', 'rejected', 'limited')),
  retry_count integer not null default 0 check (retry_count between 0 and 10),
  estimated_cost_microunits bigint check (estimated_cost_microunits is null or estimated_cost_microunits >= 0),
  created_at timestamptz not null default now()
);

create index if not exists idx_sd_copilot_conversations_player_updated
  on public.sd_development_copilot_conversations(org_id, player_id, audience, updated_at desc);
create index if not exists idx_sd_copilot_messages_conversation_created
  on public.sd_development_copilot_messages(conversation_id, created_at, id);
create index if not exists idx_sd_copilot_citations_message
  on public.sd_development_copilot_message_citations(message_id, section_key, claim_identifier);
create index if not exists idx_sd_development_attempts_scope_created
  on public.sd_development_generation_attempts(org_id, actor_id, created_at desc);
create index if not exists idx_sd_parent_drafts_player_updated
  on public.sd_development_parent_update_drafts(org_id, player_id, updated_at desc);
create index if not exists idx_sd_parent_draft_events_draft_created
  on public.sd_development_parent_draft_review_events(draft_id, created_at, id);
create index if not exists idx_sd_copilot_feedback_message
  on public.sd_development_copilot_feedback(message_id, created_at desc);
create index if not exists idx_sd_ai_usage_org_created
  on public.sd_development_ai_usage_ledger(org_id, created_at desc);
create index if not exists idx_sd_ai_usage_actor_created
  on public.sd_development_ai_usage_ledger(actor_id, audience, created_at desc);

drop trigger if exists trg_sd_copilot_conversations_updated_at on public.sd_development_copilot_conversations;
create trigger trg_sd_copilot_conversations_updated_at before update on public.sd_development_copilot_conversations
for each row execute function public.sd_set_updated_at();
drop trigger if exists trg_sd_parent_drafts_updated_at on public.sd_development_parent_update_drafts;
create trigger trg_sd_parent_drafts_updated_at before update on public.sd_development_parent_update_drafts
for each row execute function public.sd_set_updated_at();

create or replace function public.sd_reject_development_copilot_audit_mutation()
returns trigger language plpgsql set search_path = '' as $$
begin
  raise exception 'development_copilot_audit_rows_are_append_only' using errcode = '23514';
end; $$;
drop trigger if exists trg_sd_copilot_citations_append_only on public.sd_development_copilot_message_citations;
create trigger trg_sd_copilot_citations_append_only before update or delete on public.sd_development_copilot_message_citations
for each row execute function public.sd_reject_development_copilot_audit_mutation();
drop trigger if exists trg_sd_generation_attempts_append_only on public.sd_development_generation_attempts;
create trigger trg_sd_generation_attempts_append_only before update or delete on public.sd_development_generation_attempts
for each row execute function public.sd_reject_development_copilot_audit_mutation();
drop trigger if exists trg_sd_parent_draft_events_append_only on public.sd_development_parent_draft_review_events;
create trigger trg_sd_parent_draft_events_append_only before update or delete on public.sd_development_parent_draft_review_events
for each row execute function public.sd_reject_development_copilot_audit_mutation();
drop trigger if exists trg_sd_ai_usage_append_only on public.sd_development_ai_usage_ledger;
create trigger trg_sd_ai_usage_append_only before update or delete on public.sd_development_ai_usage_ledger
for each row execute function public.sd_reject_development_copilot_audit_mutation();
revoke all on function public.sd_reject_development_copilot_audit_mutation() from public, anon, authenticated;

create or replace function public.sd_reject_development_copilot_audience_change()
returns trigger language plpgsql set search_path = '' as $$
begin
  if new.audience is distinct from old.audience then
    raise exception 'development_copilot_audience_is_immutable' using errcode = '23514';
  end if;
  return new;
end; $$;
drop trigger if exists trg_sd_copilot_conversation_audience_immutable on public.sd_development_copilot_conversations;
create trigger trg_sd_copilot_conversation_audience_immutable before update on public.sd_development_copilot_conversations
for each row execute function public.sd_reject_development_copilot_audience_change();
drop trigger if exists trg_sd_copilot_message_audience_immutable on public.sd_development_copilot_messages;
create trigger trg_sd_copilot_message_audience_immutable before update on public.sd_development_copilot_messages
for each row execute function public.sd_reject_development_copilot_audience_change();
drop trigger if exists trg_sd_copilot_feedback_audience_immutable on public.sd_development_copilot_feedback;
create trigger trg_sd_copilot_feedback_audience_immutable before update on public.sd_development_copilot_feedback
for each row execute function public.sd_reject_development_copilot_audience_change();
revoke all on function public.sd_reject_development_copilot_audience_change() from public, anon, authenticated;

alter table public.sd_development_copilot_prompt_versions enable row level security;
alter table public.sd_development_copilot_conversations enable row level security;
alter table public.sd_development_copilot_messages enable row level security;
alter table public.sd_development_copilot_message_citations enable row level security;
alter table public.sd_development_generation_attempts enable row level security;
alter table public.sd_development_parent_update_drafts enable row level security;
alter table public.sd_development_parent_draft_review_events enable row level security;
alter table public.sd_development_copilot_feedback enable row level security;
alter table public.sd_development_ai_usage_ledger enable row level security;

create or replace function public.sd_development_copilot_actor_can_access(
  p_actor_id uuid, p_org_id uuid, p_player_id uuid, p_audience text
) returns boolean language sql stable security definer set search_path = '' as $$
  select case
    when p_audience = 'coach' then
      public.sd_development_actor_can_manage_player(p_actor_id, p_org_id, p_player_id)
    when p_audience = 'player' then
      p_actor_id = p_player_id and exists (
        select 1 from public.sd_org_memberships membership
        join public.sd_orgs organization
          on organization.id = membership.org_id and organization.status = 'active'
        where membership.org_id = p_org_id
          and membership.user_id = p_actor_id
          and membership.role = 'player'
          and membership.status = 'active'
      )
    else false
  end;
$$;

create or replace function public.sd_development_copilot_can_read_conversation(
  p_conversation_id uuid, p_org_id uuid, p_player_id uuid, p_audience text
) returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.sd_development_copilot_conversations conversation
    where conversation.id = p_conversation_id
      and conversation.org_id = p_org_id
      and conversation.player_id = p_player_id
      and conversation.audience = p_audience
      and (
        (p_audience = 'coach' and
          public.sd_development_actor_can_manage_player(auth.uid(), p_org_id, p_player_id))
        or
        (p_audience = 'player' and conversation.created_by = auth.uid() and
          public.sd_development_copilot_actor_can_access(auth.uid(), p_org_id, p_player_id, 'player'))
      )
  );
$$;

create or replace function public.sd_development_copilot_current_actor_can_access(
  p_org_id uuid, p_player_id uuid, p_audience text
) returns boolean language sql stable security definer set search_path = '' as $$
  select public.sd_development_copilot_actor_can_access(
    auth.uid(), p_org_id, p_player_id, p_audience
  );
$$;

revoke all on function public.sd_development_copilot_actor_can_access(uuid,uuid,uuid,text)
from public, anon, authenticated, service_role;
revoke all on function public.sd_development_copilot_can_read_conversation(uuid,uuid,uuid,text)
from public, anon, authenticated, service_role;
revoke all on function public.sd_development_copilot_current_actor_can_access(uuid,uuid,text)
from public, anon, authenticated, service_role;
grant execute on function public.sd_development_copilot_can_read_conversation(uuid,uuid,uuid,text)
to authenticated;
grant execute on function public.sd_development_copilot_current_actor_can_access(uuid,uuid,text)
to authenticated;

create policy "sd_copilot_conversations_audience_read" on public.sd_development_copilot_conversations
for select to authenticated using (
  (audience = 'coach' and public.sd_development_can_manage_player(org_id, player_id))
  or
  (audience = 'player' and created_by = auth.uid() and player_id = auth.uid()
    and public.sd_development_copilot_current_actor_can_access(org_id, player_id, audience))
);
create policy "sd_copilot_messages_audience_read" on public.sd_development_copilot_messages
for select to authenticated using (
  public.sd_development_copilot_can_read_conversation(conversation_id, org_id, player_id, audience)
);
create policy "sd_copilot_citations_audience_read" on public.sd_development_copilot_message_citations
for select to authenticated using (exists (
  select 1 from public.sd_development_copilot_messages message
  where message.id = sd_development_copilot_message_citations.message_id
    and message.org_id = sd_development_copilot_message_citations.org_id
    and message.player_id = sd_development_copilot_message_citations.player_id
    and message.audience = sd_development_copilot_message_citations.audience
    and public.sd_development_copilot_can_read_conversation(
      message.conversation_id,
      sd_development_copilot_message_citations.org_id,
      sd_development_copilot_message_citations.player_id,
      sd_development_copilot_message_citations.audience
    )
));
create policy "sd_generation_attempts_audience_read" on public.sd_development_generation_attempts
for select to authenticated using (
  (audience = 'coach' and public.sd_development_can_manage_player(org_id, player_id))
  or
  (audience = 'player' and actor_id = auth.uid() and player_id = auth.uid()
    and conversation_id is not null
    and public.sd_development_copilot_can_read_conversation(
      conversation_id, org_id, player_id, audience
    ))
);
create policy "sd_parent_drafts_staff_read" on public.sd_development_parent_update_drafts
for select to authenticated using (public.sd_development_can_manage_player(org_id, player_id));
create policy "sd_parent_draft_events_staff_read" on public.sd_development_parent_draft_review_events
for select to authenticated using (public.sd_development_can_manage_player(org_id, player_id));
create policy "sd_copilot_feedback_audience_read" on public.sd_development_copilot_feedback
for select to authenticated using (
  (audience = 'coach' and public.sd_development_can_manage_player(org_id, player_id))
  or
  (audience = 'player' and actor_id = auth.uid() and player_id = auth.uid()
    and public.sd_development_copilot_can_read_conversation(
      conversation_id, org_id, player_id, audience
    ))
);
create policy "sd_ai_usage_audience_read" on public.sd_development_ai_usage_ledger
for select to authenticated using (
  (audience = 'coach' and public.sd_development_can_manage_player(org_id, player_id))
  or
  (audience = 'player' and actor_id = auth.uid() and player_id = auth.uid()
    and public.sd_development_copilot_current_actor_can_access(org_id, player_id, audience))
);

create or replace function public.sd_create_development_copilot_conversation(
  p_actor_id uuid, p_org_id uuid, p_player_id uuid, p_title text,
  p_reporting_window_days integer, p_evidence_cutoff timestamptz,
  p_generation_mode text, p_provider text, p_model_identifier text,
  p_generator_version text, p_idempotency_key uuid, p_audience text
)
returns public.sd_development_copilot_conversations
language plpgsql security definer set search_path = '' as $$
declare v_row public.sd_development_copilot_conversations;
begin
  if not public.sd_development_copilot_actor_can_access(p_actor_id, p_org_id, p_player_id, p_audience) then
    raise exception 'copilot_player_access_denied';
  end if;
  insert into public.sd_development_copilot_conversations (
    org_id, player_id, created_by, audience, title, reporting_window_days, evidence_cutoff,
    generation_mode, provider, model_identifier, generator_version, idempotency_key
  ) values (
    p_org_id, p_player_id, p_actor_id, p_audience, left(trim(p_title), 160), p_reporting_window_days,
    p_evidence_cutoff, p_generation_mode, p_provider, nullif(p_model_identifier, ''),
    p_generator_version, p_idempotency_key
  )
  on conflict (org_id, created_by, audience, idempotency_key) do update
    set updated_at = public.sd_development_copilot_conversations.updated_at
  returning * into v_row;
  if v_row.player_id <> p_player_id or v_row.audience <> p_audience then raise exception 'copilot_idempotency_conflict'; end if;
  return v_row;
end; $$;

create or replace function public.sd_persist_development_copilot_exchange(
  p_actor_id uuid, p_org_id uuid, p_player_id uuid, p_conversation_id uuid,
  p_question text, p_structured_answer jsonb, p_rendered_answer text,
  p_quality_status text, p_evidence_cutoff timestamptz, p_generation_mode text,
  p_provider text, p_model_identifier text, p_prompt_version text,
  p_generator_version text, p_generation_status text, p_safe_error_code text,
  p_idempotency_key uuid, p_citations jsonb, p_attempt jsonb, p_audience text
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_user public.sd_development_copilot_messages; v_assistant public.sd_development_copilot_messages;
declare v_existing public.sd_development_copilot_messages; v_citation jsonb; v_fingerprint text; v_reused boolean := false;
begin
  if not public.sd_development_copilot_actor_can_access(p_actor_id, p_org_id, p_player_id, p_audience) then raise exception 'copilot_player_access_denied'; end if;
  if not exists (select 1 from public.sd_development_copilot_conversations c where c.id=p_conversation_id and c.org_id=p_org_id and c.player_id=p_player_id and c.audience=p_audience and c.status='active' and (p_audience='coach' or c.created_by=p_actor_id)) then raise exception 'copilot_conversation_not_found'; end if;
  perform pg_advisory_xact_lock(hashtextextended(p_org_id::text || ':' || p_actor_id::text || ':' || p_audience || ':' || p_idempotency_key::text, 0));
  select * into v_existing from public.sd_development_copilot_messages m where m.conversation_id=p_conversation_id and m.audience=p_audience and m.role='assistant' and m.idempotency_key=p_idempotency_key;
  if found then
    select * into v_user from public.sd_development_copilot_messages m where m.conversation_id=p_conversation_id and m.audience=p_audience and m.role='user' and m.idempotency_key=p_idempotency_key;
    if v_user.user_question <> p_question then raise exception 'copilot_idempotency_conflict'; end if;
    if coalesce(p_attempt->>'action_type','ask') <> 'retry_message' or v_existing.generation_status = 'succeeded' then
      return jsonb_build_object('user_message', to_jsonb(v_user), 'assistant_message', to_jsonb(v_existing), 'reused', true);
    end if;
    v_reused := true;
    if p_generation_status = 'succeeded' then
      update public.sd_development_copilot_messages set
        structured_answer=p_structured_answer, rendered_answer=p_rendered_answer,
        quality_status=p_quality_status, evidence_cutoff=p_evidence_cutoff,
        generation_mode=p_generation_mode, provider=p_provider,
        model_identifier=nullif(p_model_identifier,''), prompt_version=p_prompt_version,
        generator_version=p_generator_version, generation_status='succeeded',
        safe_error_code=null,
        assistant_turn_type=coalesce(p_structured_answer->>'assistant_turn_type','answer')
      where id=v_existing.id returning * into v_assistant;
    else
      v_assistant := v_existing;
    end if;
  else
    insert into public.sd_development_copilot_messages (conversation_id,org_id,player_id,actor_id,audience,role,user_question,quality_status,evidence_cutoff,generation_mode,provider,model_identifier,prompt_version,generator_version,generation_status,idempotency_key)
    values (p_conversation_id,p_org_id,p_player_id,p_actor_id,p_audience,'user',p_question,'unavailable',p_evidence_cutoff,p_generation_mode,p_provider,nullif(p_model_identifier,''),p_prompt_version,p_generator_version,'succeeded',p_idempotency_key) returning * into v_user;
    insert into public.sd_development_copilot_messages (conversation_id,org_id,player_id,audience,role,assistant_turn_type,structured_answer,rendered_answer,quality_status,evidence_cutoff,generation_mode,provider,model_identifier,prompt_version,generator_version,generation_status,safe_error_code,idempotency_key)
    values (p_conversation_id,p_org_id,p_player_id,p_audience,'assistant',coalesce(p_structured_answer->>'assistant_turn_type','answer'),p_structured_answer,p_rendered_answer,p_quality_status,p_evidence_cutoff,p_generation_mode,p_provider,nullif(p_model_identifier,''),p_prompt_version,p_generator_version,p_generation_status,p_safe_error_code,p_idempotency_key) returning * into v_assistant;
  end if;
  for v_citation in select value from jsonb_array_elements(coalesce(p_citations,'[]'::jsonb)) loop
    insert into public.sd_development_copilot_message_citations (message_id,org_id,player_id,audience,evidence_key,source_entity_type,source_record_id,canonical_metric_key,observed_value,normalized_value,unit,observed_at,display_label,explanation,section_key,claim_identifier,source_provider,verification_status,deterministic_rule_id,evidence_snapshot)
    values (v_assistant.id,p_org_id,p_player_id,p_audience,v_citation->>'evidence_key',v_citation->>'source_entity_type',v_citation->>'source_record_id',nullif(v_citation->>'canonical_metric_key',''),nullif(v_citation->>'observed_value',''),nullif(v_citation->>'normalized_value','')::numeric,nullif(v_citation->>'unit',''),nullif(v_citation->>'observed_at','')::timestamptz,v_citation->>'display_label',v_citation->>'explanation',v_citation->>'section_key',v_citation->>'claim_identifier',nullif(v_citation->>'source_provider',''),nullif(v_citation->>'verification_status',''),nullif(v_citation->>'deterministic_rule_id',''),v_citation->'evidence_snapshot');
  end loop;
  v_fingerprint := pg_catalog.encode(
    extensions.digest(
      pg_catalog.convert_to(p_org_id::text || p_actor_id::text || p_audience || p_idempotency_key::text || p_question, 'UTF8'),
      'sha256'
    ),
    'hex'
  );
  insert into public.sd_development_generation_attempts (org_id,actor_id,player_id,audience,conversation_id,message_id,action_type,generation_mode,provider,model_identifier,prompt_version,generator_version,retry_count,status,safe_error_code,input_size,output_size,input_tokens,output_tokens,latency_ms,estimated_cost_microunits,request_fingerprint,safe_metadata)
  values (p_org_id,p_actor_id,p_player_id,p_audience,p_conversation_id,v_assistant.id,coalesce(p_attempt->>'action_type','ask'),p_generation_mode,p_provider,nullif(p_model_identifier,''),p_prompt_version,p_generator_version,coalesce((p_attempt->>'retry_count')::integer,0),coalesce(p_attempt->>'status','succeeded'),p_safe_error_code,coalesce((p_attempt->>'input_size')::integer,0),coalesce((p_attempt->>'output_size')::integer,0),nullif(p_attempt->>'input_tokens','')::integer,nullif(p_attempt->>'output_tokens','')::integer,nullif(p_attempt->>'latency_ms','')::integer,nullif(p_attempt->>'estimated_cost_microunits','')::bigint,v_fingerprint,coalesce(p_attempt->'safe_metadata','{}'::jsonb));
  insert into public.sd_development_ai_usage_ledger (org_id,actor_id,player_id,audience,provider,model_identifier,action_type,generation_mode,input_size,output_size,input_tokens,output_tokens,latency_ms,status,retry_count,estimated_cost_microunits)
  values (p_org_id,p_actor_id,p_player_id,p_audience,p_provider,nullif(p_model_identifier,''),coalesce(p_attempt->>'action_type','ask'),p_generation_mode,coalesce((p_attempt->>'input_size')::integer,0),coalesce((p_attempt->>'output_size')::integer,0),nullif(p_attempt->>'input_tokens','')::integer,nullif(p_attempt->>'output_tokens','')::integer,nullif(p_attempt->>'latency_ms','')::integer,coalesce(p_attempt->>'status','succeeded'),coalesce((p_attempt->>'retry_count')::integer,0),nullif(p_attempt->>'estimated_cost_microunits','')::bigint);
  update public.sd_development_copilot_conversations set evidence_cutoff=p_evidence_cutoff, generation_mode=p_generation_mode, provider=p_provider, model_identifier=nullif(p_model_identifier,''), generator_version=p_generator_version, updated_at=now() where id=p_conversation_id and org_id=p_org_id and audience=p_audience;
  return jsonb_build_object('user_message',to_jsonb(v_user),'assistant_message',to_jsonb(v_assistant),'reused',v_reused);
end; $$;

create or replace function public.sd_archive_development_copilot_conversation(
  p_actor_id uuid, p_org_id uuid, p_conversation_id uuid, p_audience text
)
returns public.sd_development_copilot_conversations
language plpgsql security definer set search_path = '' as $$
declare v_row public.sd_development_copilot_conversations;
begin
  select * into v_row from public.sd_development_copilot_conversations
  where id = p_conversation_id and org_id = p_org_id and audience = p_audience
    and (p_audience = 'coach' or created_by = p_actor_id) for update;
  if not found or not public.sd_development_copilot_actor_can_access(p_actor_id, p_org_id, v_row.player_id, p_audience) then
    raise exception 'copilot_conversation_not_found';
  end if;
  update public.sd_development_copilot_conversations
  set status = 'archived', archived_at = coalesce(archived_at, now())
  where id = p_conversation_id and audience = p_audience returning * into v_row;
  return v_row;
end; $$;

create or replace function public.sd_create_development_parent_update_draft(
  p_actor_id uuid,p_org_id uuid,p_player_id uuid,p_conversation_id uuid,p_source_message_id uuid,
  p_content jsonb,p_rendered_text text,p_evidence_cutoff timestamptz,p_generation_mode text,
  p_provider text,p_model_identifier text,p_prompt_version text,p_generator_version text,p_idempotency_key uuid
) returns public.sd_development_parent_update_drafts language plpgsql security definer set search_path='' as $$
declare v_row public.sd_development_parent_update_drafts; v_fingerprint text;
begin
  if not public.sd_development_actor_can_manage_player(p_actor_id,p_org_id,p_player_id) then raise exception 'copilot_player_access_denied'; end if;
  if p_conversation_id is not null and not exists (
    select 1 from public.sd_development_copilot_conversations conversation
    join public.sd_development_copilot_messages message
      on message.id = p_source_message_id
      and message.conversation_id = conversation.id
      and message.org_id = conversation.org_id
      and message.player_id = conversation.player_id
      and message.audience = conversation.audience
    where conversation.id = p_conversation_id and conversation.org_id = p_org_id
      and conversation.player_id = p_player_id and conversation.audience = 'coach'
      and message.role = 'assistant'
  ) then raise exception 'copilot_message_not_found'; end if;
  insert into public.sd_development_parent_update_drafts (org_id,player_id,conversation_id,source_message_id,created_by,generated_original,edited_content,generated_rendered_text,edited_rendered_text,evidence_cutoff,generation_mode,provider,model_identifier,prompt_version,generator_version,idempotency_key)
  values (p_org_id,p_player_id,p_conversation_id,p_source_message_id,p_actor_id,p_content,p_content,p_rendered_text,p_rendered_text,p_evidence_cutoff,p_generation_mode,p_provider,nullif(p_model_identifier,''),p_prompt_version,p_generator_version,p_idempotency_key)
  on conflict (org_id,created_by,idempotency_key) do update set updated_at=public.sd_development_parent_update_drafts.updated_at returning * into v_row;
  if v_row.player_id<>p_player_id then raise exception 'copilot_idempotency_conflict'; end if;
  if not exists(select 1 from public.sd_development_parent_draft_review_events e where e.draft_id=v_row.id and e.event_type='generated') then
    insert into public.sd_development_parent_draft_review_events(draft_id,org_id,player_id,actor_id,event_type,to_status,content_snapshot) values(v_row.id,p_org_id,p_player_id,p_actor_id,'generated','generated',p_content);
    v_fingerprint := pg_catalog.encode(
      extensions.digest(
        pg_catalog.convert_to(p_org_id::text || p_actor_id::text || p_idempotency_key::text || p_content::text, 'UTF8'),
        'sha256'
      ),
      'hex'
    );
    insert into public.sd_development_generation_attempts (
      org_id,actor_id,player_id,audience,conversation_id,message_id,action_type,generation_mode,
      provider,model_identifier,prompt_version,generator_version,retry_count,status,
      input_size,output_size,request_fingerprint,safe_metadata
    ) values (
      p_org_id,p_actor_id,p_player_id,'coach',p_conversation_id,p_source_message_id,
      'parent_update_draft',p_generation_mode,p_provider,nullif(p_model_identifier,''),
      p_prompt_version,p_generator_version,0,'succeeded',char_length(p_content::text),
      char_length(p_rendered_text),v_fingerprint,jsonb_build_object('draft_id',v_row.id)
    );
    insert into public.sd_development_ai_usage_ledger (
      org_id,actor_id,player_id,audience,provider,model_identifier,action_type,generation_mode,
      input_size,output_size,status,retry_count
    ) values (
      p_org_id,p_actor_id,p_player_id,'coach',p_provider,nullif(p_model_identifier,''),
      'parent_update_draft',p_generation_mode,char_length(p_content::text),
      char_length(p_rendered_text),'succeeded',0
    );
  end if;
  return v_row;
end; $$;

create or replace function public.sd_review_development_parent_update_draft(
  p_actor_id uuid,p_org_id uuid,p_draft_id uuid,p_action text,p_content jsonb,p_rendered_text text,p_safe_note text
) returns public.sd_development_parent_update_drafts language plpgsql security definer set search_path='' as $$
declare v_row public.sd_development_parent_update_drafts; v_from text; v_to text;
begin
  select * into v_row from public.sd_development_parent_update_drafts where id=p_draft_id and org_id=p_org_id for update;
  if not found or not public.sd_development_actor_can_manage_player(p_actor_id,p_org_id,v_row.player_id) then raise exception 'parent_draft_not_found'; end if;
  v_from:=v_row.status;
  if p_action='edit' and v_from in ('generated','reviewed') then v_to:=v_from;
  elsif p_action='review' and v_from='generated' then v_to:='reviewed';
  elsif p_action='approve' and v_from='reviewed' then v_to:='approved';
  elsif p_action='reject' and v_from in ('generated','reviewed') then v_to:='rejected';
  elsif p_action='archive' and v_from in ('generated','reviewed','approved','rejected') then v_to:='archived';
  else raise exception 'invalid_parent_draft_transition'; end if;
  update public.sd_development_parent_update_drafts set
    edited_content=case when p_action='edit' then p_content else edited_content end,
    edited_rendered_text=case when p_action='edit' then p_rendered_text else edited_rendered_text end,
    status=v_to,
    reviewed_at=case when p_action='review' then now() else reviewed_at end,
    reviewed_by=case when p_action='review' then p_actor_id else reviewed_by end,
    approved_at=case when p_action='approve' then now() else approved_at end,
    approved_by=case when p_action='approve' then p_actor_id else approved_by end,
    rejected_at=case when p_action='reject' then now() else rejected_at end,
    rejected_by=case when p_action='reject' then p_actor_id else rejected_by end,
    archived_at=case when p_action='archive' then now() else archived_at end,
    archived_by=case when p_action='archive' then p_actor_id else archived_by end
  where id=p_draft_id returning * into v_row;
  insert into public.sd_development_parent_draft_review_events(draft_id,org_id,player_id,actor_id,event_type,from_status,to_status,safe_note,content_snapshot)
  values(v_row.id,p_org_id,v_row.player_id,p_actor_id,
    case p_action when 'review' then 'reviewed' when 'approve' then 'approved'
      when 'archive' then 'archived' when 'reject' then 'rejected' else 'edited' end,
    v_from,v_to,left(nullif(trim(p_safe_note),''),2000),v_row.edited_content);
  return v_row;
end; $$;

create or replace function public.sd_submit_development_copilot_feedback(
  p_actor_id uuid,p_org_id uuid,p_player_id uuid,p_conversation_id uuid,p_message_id uuid,p_feedback_type text,p_safe_note text,p_audience text
) returns public.sd_development_copilot_feedback language plpgsql security definer set search_path='' as $$
declare v_row public.sd_development_copilot_feedback;
begin
  if not public.sd_development_copilot_actor_can_access(p_actor_id,p_org_id,p_player_id,p_audience) then raise exception 'copilot_player_access_denied'; end if;
  if not exists(select 1 from public.sd_development_copilot_messages m join public.sd_development_copilot_conversations c on c.id=m.conversation_id and c.org_id=m.org_id and c.player_id=m.player_id and c.audience=m.audience where m.id=p_message_id and m.conversation_id=p_conversation_id and m.org_id=p_org_id and m.player_id=p_player_id and m.audience=p_audience and m.role='assistant' and (p_audience='coach' or c.created_by=p_actor_id)) then raise exception 'copilot_message_not_found'; end if;
  insert into public.sd_development_copilot_feedback(org_id,player_id,conversation_id,message_id,actor_id,audience,feedback_type,safe_note)
  values(p_org_id,p_player_id,p_conversation_id,p_message_id,p_actor_id,p_audience,p_feedback_type,left(nullif(trim(p_safe_note),''),1000))
  on conflict(message_id,actor_id,audience) do update set feedback_type=excluded.feedback_type,safe_note=excluded.safe_note
  returning * into v_row;
  return v_row;
end; $$;

revoke all on function public.sd_create_development_copilot_conversation(uuid,uuid,uuid,text,integer,timestamptz,text,text,text,text,uuid,text) from public, anon, authenticated;
revoke all on function public.sd_persist_development_copilot_exchange(uuid,uuid,uuid,uuid,text,jsonb,text,text,timestamptz,text,text,text,text,text,text,text,uuid,jsonb,jsonb,text) from public, anon, authenticated;
revoke all on function public.sd_archive_development_copilot_conversation(uuid,uuid,uuid,text) from public, anon, authenticated;
revoke all on function public.sd_create_development_parent_update_draft(uuid,uuid,uuid,uuid,uuid,jsonb,text,timestamptz,text,text,text,text,text,uuid) from public, anon, authenticated;
revoke all on function public.sd_review_development_parent_update_draft(uuid,uuid,uuid,text,jsonb,text,text) from public, anon, authenticated;
revoke all on function public.sd_submit_development_copilot_feedback(uuid,uuid,uuid,uuid,uuid,text,text,text) from public, anon, authenticated;
grant execute on function public.sd_create_development_copilot_conversation(uuid,uuid,uuid,text,integer,timestamptz,text,text,text,text,uuid,text) to service_role;
grant execute on function public.sd_persist_development_copilot_exchange(uuid,uuid,uuid,uuid,text,jsonb,text,text,timestamptz,text,text,text,text,text,text,text,uuid,jsonb,jsonb,text) to service_role;
grant execute on function public.sd_archive_development_copilot_conversation(uuid,uuid,uuid,text) to service_role;
grant execute on function public.sd_create_development_parent_update_draft(uuid,uuid,uuid,uuid,uuid,jsonb,text,timestamptz,text,text,text,text,text,uuid) to service_role;
grant execute on function public.sd_review_development_parent_update_draft(uuid,uuid,uuid,text,jsonb,text,text) to service_role;
grant execute on function public.sd_submit_development_copilot_feedback(uuid,uuid,uuid,uuid,uuid,text,text,text) to service_role;

revoke all on table public.sd_development_copilot_prompt_versions,public.sd_development_copilot_conversations,public.sd_development_copilot_messages,public.sd_development_copilot_message_citations,public.sd_development_generation_attempts,public.sd_development_parent_update_drafts,public.sd_development_parent_draft_review_events,public.sd_development_copilot_feedback,public.sd_development_ai_usage_ledger from public,anon,authenticated;
grant select on public.sd_development_copilot_conversations,public.sd_development_copilot_messages,public.sd_development_copilot_message_citations,public.sd_development_generation_attempts,public.sd_development_parent_update_drafts,public.sd_development_parent_draft_review_events,public.sd_development_copilot_feedback,public.sd_development_ai_usage_ledger to authenticated;
grant select on public.sd_development_copilot_prompt_versions,public.sd_development_copilot_conversations,public.sd_development_copilot_messages,public.sd_development_copilot_message_citations,public.sd_development_generation_attempts,public.sd_development_parent_update_drafts,public.sd_development_parent_draft_review_events,public.sd_development_copilot_feedback,public.sd_development_ai_usage_ledger to service_role;

insert into public.sd_development_copilot_prompt_versions(prompt_key,use_case,intended_audience,version,evidence_schema_version,output_schema_version,safety_version,template_metadata,is_active)
values
('coach_player_question','coach_copilot_player_question','coach','coach-copilot.v1','player_development_evidence_pack.v1','player_development_copilot_answer.v1','player-development-safety.v1','{"client_system_prompts":false,"untrusted_evidence_delimited":true}'::jsonb,true),
('player_self_question','player_copilot_self_question','player','player-copilot-self.v1','player_development_evidence_pack.v1','player_development_copilot_answer.v1','player-development-safety.v1','{"client_system_prompts":false,"player_evidence_policy":"allowlist.v1","private_staff_evidence_excluded":true}'::jsonb,true),
('player_development_summary','player_development_summary','coach','player-development-summary.v1','player_development_evidence_pack.v1','player_development_copilot_answer.v1','player-development-safety.v1','{"client_system_prompts":false,"human_review_required":true}'::jsonb,true),
('parent_update','parent_update_draft','parent_draft','parent-update.v1','player_development_evidence_pack.v1','parent_update_draft.v1','parent-update-safety.v1','{"delivery_enabled":false,"private_notes_excluded":true}'::jsonb,true),
('staff_meeting_summary','staff_meeting_summary','staff','staff-meeting-summary.v1','player_development_evidence_pack.v1','player_development_copilot_answer.v1','player-development-safety.v1','{"client_system_prompts":false,"staff_only":true}'::jsonb,true),
('alert_explanation','alert_explanation','coach','alert-explanation.v1','player_development_evidence_pack.v1','player_development_copilot_answer.v1','player-development-safety.v1','{"client_system_prompts":false,"action_execution":false}'::jsonb,true)
on conflict(prompt_key,use_case,intended_audience,version) do nothing;

-- Bounded two-way Copilot dialogue. User replies are conversational context,
-- never verified development evidence or an implicit mutation command.
alter table public.sd_development_copilot_messages
  add column if not exists assistant_turn_type text;
update public.sd_development_copilot_messages
set assistant_turn_type='answer'
where role='assistant' and assistant_turn_type is null;
alter table public.sd_development_copilot_messages
  add constraint sd_development_copilot_message_turn_type_check check (
    (role='user' and assistant_turn_type is null) or
    (role='assistant' and assistant_turn_type in (
      'answer','clarification_question','evidence_gap_question','reflection_question',
      'confirmation_question','suggested_follow_up','action_preview','safe_refusal'
    ))
  );

create table if not exists public.sd_development_copilot_pending_questions(
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.sd_orgs(id) on delete restrict,
  player_id uuid not null references public.profiles(id) on delete restrict,
  conversation_id uuid not null,
  assistant_message_id uuid not null,
  audience text not null check(audience in ('coach','player')),
  question_type text not null check(question_type in (
    'clarification_question','evidence_gap_question','reflection_question','confirmation_question'
  )),
  question_text text not null check(char_length(question_text) between 1 and 2000),
  originating_request text not null check(char_length(originating_request) between 1 and 2000),
  why_asked text not null check(char_length(why_asked) between 1 and 500),
  expected_response_type text not null check(expected_response_type in ('choice','free_text','confirmation')),
  choices jsonb not null default '[]'::jsonb check(jsonb_typeof(choices)='array' and jsonb_array_length(choices)<=6),
  related_evidence_ids text[] not null default '{}'::text[] check(cardinality(related_evidence_ids)<=20),
  is_optional boolean not null default false,
  may_later_be_saved boolean not null default false,
  status text not null default 'pending' check(status in ('pending','answered','skipped','expired','superseded')),
  expires_at timestamptz not null,
  answered_at timestamptz,
  response_message_id uuid,
  created_at timestamptz not null default now(),
  unique(id,org_id,player_id,audience),
  constraint sd_copilot_pending_conversation_fk foreign key(conversation_id,org_id,player_id,audience)
    references public.sd_development_copilot_conversations(id,org_id,player_id,audience) on delete restrict,
  constraint sd_copilot_pending_assistant_message_fk foreign key(assistant_message_id,org_id,player_id,audience)
    references public.sd_development_copilot_messages(id,org_id,player_id,audience) on delete restrict,
  constraint sd_copilot_pending_state_check check(
    (status='pending' and answered_at is null and response_message_id is null) or
    (status in ('answered','skipped') and answered_at is not null and response_message_id is not null) or
    (status in ('expired','superseded') and answered_at is null and response_message_id is null)
  )
);
create unique index if not exists uq_sd_copilot_one_pending_question
  on public.sd_development_copilot_pending_questions(conversation_id,audience)
  where status='pending';
create index if not exists idx_sd_copilot_pending_scope_created
  on public.sd_development_copilot_pending_questions(org_id,player_id,audience,created_at desc);

alter table public.sd_development_copilot_messages
  add column if not exists in_reply_to_question_id uuid;
alter table public.sd_development_copilot_messages
  add constraint sd_copilot_message_pending_reply_fk
  foreign key(in_reply_to_question_id,org_id,player_id,audience)
  references public.sd_development_copilot_pending_questions(id,org_id,player_id,audience) on delete restrict;
alter table public.sd_development_copilot_pending_questions
  add constraint sd_copilot_pending_response_message_fk
  foreign key(response_message_id,org_id,player_id,audience)
  references public.sd_development_copilot_messages(id,org_id,player_id,audience) on delete restrict;

alter table public.sd_development_copilot_pending_questions enable row level security;
create policy "sd_copilot_pending_questions_audience_read"
on public.sd_development_copilot_pending_questions for select to authenticated using(
  public.sd_development_copilot_can_read_conversation(conversation_id,org_id,player_id,audience)
);
revoke all on table public.sd_development_copilot_pending_questions from public,anon,authenticated;
grant select on table public.sd_development_copilot_pending_questions to authenticated;
grant select on table public.sd_development_copilot_pending_questions to service_role;

create or replace function public.sd_reject_copilot_pending_scope_change()
returns trigger language plpgsql set search_path='' as $$
begin
  if new.org_id is distinct from old.org_id
    or new.player_id is distinct from old.player_id
    or new.conversation_id is distinct from old.conversation_id
    or new.assistant_message_id is distinct from old.assistant_message_id
    or new.audience is distinct from old.audience
    or new.question_type is distinct from old.question_type
    or new.question_text is distinct from old.question_text
    or new.originating_request is distinct from old.originating_request
    or new.why_asked is distinct from old.why_asked
    or new.expected_response_type is distinct from old.expected_response_type
    or new.choices is distinct from old.choices
    or new.related_evidence_ids is distinct from old.related_evidence_ids
    or new.is_optional is distinct from old.is_optional
    or new.may_later_be_saved is distinct from old.may_later_be_saved
    or new.expires_at is distinct from old.expires_at
    or new.created_at is distinct from old.created_at then
    raise exception 'copilot_pending_question_scope_is_immutable' using errcode='23514';
  end if;
  return new;
end; $$;
drop trigger if exists trg_sd_copilot_pending_scope_immutable
  on public.sd_development_copilot_pending_questions;
create trigger trg_sd_copilot_pending_scope_immutable
before update on public.sd_development_copilot_pending_questions
for each row execute function public.sd_reject_copilot_pending_scope_change();
revoke all on function public.sd_reject_copilot_pending_scope_change()
from public,anon,authenticated;

create or replace function public.sd_persist_development_copilot_dialogue_turn(
  p_actor_id uuid,p_org_id uuid,p_player_id uuid,p_conversation_id uuid,p_question text,
  p_structured_answer jsonb,p_rendered_answer text,p_quality_status text,p_evidence_cutoff timestamptz,
  p_generation_mode text,p_provider text,p_model_identifier text,p_prompt_version text,p_generator_version text,
  p_generation_status text,p_safe_error_code text,p_idempotency_key uuid,p_citations jsonb,p_attempt jsonb,
  p_audience text,p_assistant_turn_type text,p_pending_question jsonb,p_pending_question_id uuid,
  p_pending_response_mode text
) returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb; v_user_message_id uuid; v_assistant_message_id uuid; pending_row public.sd_development_copilot_pending_questions;
begin
  if p_assistant_turn_type not in (
    'answer','clarification_question','evidence_gap_question','reflection_question',
    'confirmation_question','suggested_follow_up','action_preview','safe_refusal'
  ) then raise exception 'invalid_copilot_assistant_turn'; end if;
  if p_pending_question_id is not null then
    select * into pending_row from public.sd_development_copilot_pending_questions
    where id=p_pending_question_id and org_id=p_org_id and player_id=p_player_id
      and conversation_id=p_conversation_id and audience=p_audience for update;
    if not found or pending_row.status<>'pending' or pending_row.expires_at<=pg_catalog.now()
      then raise exception 'pending_question_stale'; end if;
    if p_pending_response_mode not in ('answer','skip','use_available_evidence')
      or (p_pending_response_mode='skip' and not pending_row.is_optional)
      then raise exception 'pending_question_response_invalid'; end if;
  elsif p_pending_response_mode is not null then raise exception 'pending_question_response_invalid';
  end if;
  result:=public.sd_persist_development_copilot_exchange(
    p_actor_id,p_org_id,p_player_id,p_conversation_id,p_question,p_structured_answer,p_rendered_answer,
    p_quality_status,p_evidence_cutoff,p_generation_mode,p_provider,p_model_identifier,p_prompt_version,
    p_generator_version,p_generation_status,p_safe_error_code,p_idempotency_key,p_citations,p_attempt,p_audience
  );
  v_user_message_id:=(result->'user_message'->>'id')::uuid;
  v_assistant_message_id:=(result->'assistant_message'->>'id')::uuid;
  if coalesce((result->>'reused')::boolean,false) then
    select * into pending_row from public.sd_development_copilot_pending_questions
    where assistant_message_id=v_assistant_message_id and audience=p_audience;
    return result||pg_catalog.jsonb_build_object(
      'pending_question',case when found then pg_catalog.to_jsonb(pending_row) else null end
    );
  end if;
  update public.sd_development_copilot_messages set in_reply_to_question_id=p_pending_question_id
  where id=v_user_message_id;
  update public.sd_development_copilot_messages set assistant_turn_type=p_assistant_turn_type
  where id=v_assistant_message_id;
  if p_pending_question_id is not null then
    update public.sd_development_copilot_pending_questions set
      status=case when p_pending_response_mode='skip' then 'skipped' else 'answered' end,
      answered_at=pg_catalog.now(),response_message_id=v_user_message_id
    where id=p_pending_question_id;
  end if;
  update public.sd_development_copilot_pending_questions set status='superseded'
  where conversation_id=p_conversation_id and audience=p_audience and status='pending';
  if p_pending_question is not null then
    if pg_catalog.jsonb_typeof(p_pending_question)<>'object'
      or p_pending_question->>'question_type' not in ('clarification_question','evidence_gap_question','reflection_question','confirmation_question')
      or p_pending_question->>'expected_response_type' not in ('choice','free_text','confirmation')
      or pg_catalog.jsonb_typeof(coalesce(p_pending_question->'choices','[]'::jsonb))<>'array'
      or pg_catalog.jsonb_array_length(coalesce(p_pending_question->'choices','[]'::jsonb))>6
      or pg_catalog.char_length(coalesce(p_pending_question->>'why_asked','')) not between 1 and 500
      or (p_pending_question->>'expires_at')::timestamptz<=pg_catalog.now()
      then raise exception 'invalid_copilot_pending_question'; end if;
    insert into public.sd_development_copilot_pending_questions(
      org_id,player_id,conversation_id,assistant_message_id,audience,question_type,question_text,
      originating_request,why_asked,expected_response_type,choices,related_evidence_ids,
      is_optional,may_later_be_saved,expires_at
    ) values(
      p_org_id,p_player_id,p_conversation_id,v_assistant_message_id,p_audience,
      p_pending_question->>'question_type',p_structured_answer->>'answer',p_question,
      p_pending_question->>'why_asked',p_pending_question->>'expected_response_type',
      coalesce(p_pending_question->'choices','[]'::jsonb),
      coalesce(array(select pg_catalog.jsonb_array_elements_text(coalesce(p_pending_question->'related_evidence_ids','[]'::jsonb))),'{}'::text[]),
      coalesce((p_pending_question->>'is_optional')::boolean,false),
      coalesce((p_pending_question->>'may_later_be_saved')::boolean,false),
      (p_pending_question->>'expires_at')::timestamptz
    ) returning * into pending_row;
  else pending_row:=null;
  end if;
  select pg_catalog.jsonb_set(result,'{user_message}',pg_catalog.to_jsonb(message),false) into result
  from public.sd_development_copilot_messages message where message.id=v_user_message_id;
  select pg_catalog.jsonb_set(result,'{assistant_message}',pg_catalog.to_jsonb(message),false) into result
  from public.sd_development_copilot_messages message where message.id=v_assistant_message_id;
  return result||pg_catalog.jsonb_build_object(
    'pending_question',case when pending_row.id is not null then pg_catalog.to_jsonb(pending_row) else null end
  );
end; $$;

revoke execute on function public.sd_persist_development_copilot_exchange(uuid,uuid,uuid,uuid,text,jsonb,text,text,timestamptz,text,text,text,text,text,text,text,uuid,jsonb,jsonb,text) from service_role;
revoke all on function public.sd_persist_development_copilot_dialogue_turn(uuid,uuid,uuid,uuid,text,jsonb,text,text,timestamptz,text,text,text,text,text,text,text,uuid,jsonb,jsonb,text,text,jsonb,uuid,text)
from public,anon,authenticated,service_role;
grant execute on function public.sd_persist_development_copilot_dialogue_turn(uuid,uuid,uuid,uuid,text,jsonb,text,text,timestamptz,text,text,text,text,text,text,text,uuid,jsonb,jsonb,text,text,jsonb,uuid,text)
to service_role;

-- Player-visible Phase 11A reports and alerts. Historical rows remain staff-only.
alter table public.sd_development_reports
  add column if not exists audience text not null default 'staff';
alter table public.sd_development_reports
  drop constraint if exists sd_development_reports_audience_check;
alter table public.sd_development_reports
  add constraint sd_development_reports_audience_check
  check (audience in ('staff','player','parent'));
alter table public.sd_development_reports
  drop constraint if exists sd_development_reports_intended_audience_check;
alter table public.sd_development_reports
  add constraint sd_development_reports_intended_audience_check
  check (intended_audience in ('coach','staff','player','parent_draft','internal'));
alter table public.sd_development_reports
  drop constraint if exists sd_development_reports_org_id_requested_by_idempotency_key_key;
alter table public.sd_development_reports
  add constraint sd_development_reports_actor_audience_idempotency_key
  unique (org_id,requested_by,audience,idempotency_key);
alter table public.sd_development_reports
  add constraint sd_development_reports_scope_audience_key
  unique (id,org_id,player_id,audience);
alter table public.sd_development_reports
  add constraint sd_development_reports_org_audience_key
  unique (id,org_id,audience);

alter table public.sd_development_report_evidence
  add column if not exists audience text not null default 'staff';
alter table public.sd_development_report_evidence
  add constraint sd_development_report_evidence_audience_check
  check (audience in ('staff','player','parent'));
alter table public.sd_development_report_evidence
  drop constraint if exists sd_development_report_evidence_report_fk;
alter table public.sd_development_report_evidence
  add constraint sd_development_report_evidence_report_audience_fk
  foreign key (report_id,org_id,player_id,audience)
  references public.sd_development_reports(id,org_id,player_id,audience) on delete restrict;

alter table public.sd_development_report_review_events
  add column if not exists audience text not null default 'staff';
alter table public.sd_development_report_review_events
  add constraint sd_development_report_review_events_audience_check
  check (audience in ('staff','player','parent'));
alter table public.sd_development_report_review_events
  drop constraint if exists sd_development_report_review_event_report_fk;
alter table public.sd_development_report_review_events
  add constraint sd_development_report_review_event_report_audience_fk
  foreign key (report_id,org_id,audience)
  references public.sd_development_reports(id,org_id,audience) on delete restrict;

alter table public.sd_development_alerts
  add column if not exists audience text not null default 'staff';
alter table public.sd_development_alerts
  add constraint sd_development_alerts_audience_check
  check (audience in ('staff','player'));
alter table public.sd_development_alerts
  drop constraint if exists sd_development_alerts_org_id_player_id_deduplication_key_key;
alter table public.sd_development_alerts
  add constraint sd_development_alerts_audience_deduplication_key
  unique (org_id,player_id,audience,deduplication_key);
alter table public.sd_development_alerts
  add constraint sd_development_alerts_scope_audience_key
  unique (id,org_id,player_id,audience);
alter table public.sd_development_alerts
  add constraint sd_development_alerts_org_audience_key
  unique (id,org_id,audience);
alter table public.sd_development_alerts
  drop constraint if exists sd_development_alert_report_fk;
alter table public.sd_development_alerts
  add constraint sd_development_alert_report_audience_fk
  foreign key (report_id,org_id,player_id,audience)
  references public.sd_development_reports(id,org_id,player_id,audience) on delete restrict;

alter table public.sd_development_alert_evidence
  add column if not exists audience text not null default 'staff';
alter table public.sd_development_alert_evidence
  add constraint sd_development_alert_evidence_audience_check
  check (audience in ('staff','player'));
alter table public.sd_development_alert_evidence
  drop constraint if exists sd_development_alert_evidence_alert_fk;
alter table public.sd_development_alert_evidence
  add constraint sd_development_alert_evidence_alert_audience_fk
  foreign key (alert_id,org_id,player_id,audience)
  references public.sd_development_alerts(id,org_id,player_id,audience) on delete restrict;

alter table public.sd_development_alert_events
  add column if not exists audience text not null default 'staff';
alter table public.sd_development_alert_events
  add constraint sd_development_alert_events_audience_check
  check (audience in ('staff','player'));
alter table public.sd_development_alert_events
  drop constraint if exists sd_development_alert_event_alert_fk;
alter table public.sd_development_alert_events
  add constraint sd_development_alert_event_alert_audience_fk
  foreign key (alert_id,org_id,audience)
  references public.sd_development_alerts(id,org_id,audience) on delete restrict;

create index if not exists idx_sd_development_reports_audience_player_created
  on public.sd_development_reports(org_id,audience,player_id,created_at desc);
create index if not exists idx_sd_development_alerts_audience_player_status
  on public.sd_development_alerts(org_id,audience,player_id,status,last_detected_at desc);

create or replace function public.sd_reject_development_record_audience_change()
returns trigger language plpgsql set search_path='' as $$
begin
  if new.audience is distinct from old.audience then
    raise exception 'development_record_audience_is_immutable' using errcode='23514';
  end if;
  return new;
end; $$;
drop trigger if exists trg_sd_development_report_audience_immutable on public.sd_development_reports;
create trigger trg_sd_development_report_audience_immutable before update on public.sd_development_reports
for each row execute function public.sd_reject_development_record_audience_change();
drop trigger if exists trg_sd_development_alert_audience_immutable on public.sd_development_alerts;
create trigger trg_sd_development_alert_audience_immutable before update on public.sd_development_alerts
for each row execute function public.sd_reject_development_record_audience_change();
revoke all on function public.sd_reject_development_record_audience_change() from public,anon,authenticated;

create or replace function public.sd_development_report_current_actor_can_read(
  p_report_id uuid,p_org_id uuid,p_player_id uuid,p_audience text
) returns boolean language sql stable security definer set search_path='' as $$
  select exists(
    select 1 from public.sd_development_reports report
    where report.id=p_report_id and report.org_id=p_org_id
      and report.player_id=p_player_id and report.audience=p_audience
      and (
        (p_audience='staff' and public.sd_development_actor_can_manage_player(auth.uid(),p_org_id,p_player_id))
        or
        (p_audience='player' and report.requested_by=auth.uid()
          and public.sd_development_copilot_actor_can_access(auth.uid(),p_org_id,p_player_id,'player'))
      )
  );
$$;
create or replace function public.sd_development_alert_current_actor_can_read(
  p_alert_id uuid,p_org_id uuid,p_player_id uuid,p_audience text
) returns boolean language sql stable security definer set search_path='' as $$
  select exists(
    select 1 from public.sd_development_alerts alert
    where alert.id=p_alert_id and alert.org_id=p_org_id
      and alert.player_id=p_player_id and alert.audience=p_audience
      and (
        (p_audience='staff' and public.sd_development_actor_can_manage_player(auth.uid(),p_org_id,p_player_id))
        or
        (p_audience='player' and public.sd_development_copilot_actor_can_access(auth.uid(),p_org_id,p_player_id,'player'))
      )
  );
$$;
revoke all on function public.sd_development_report_current_actor_can_read(uuid,uuid,uuid,text)
from public,anon,authenticated,service_role;
revoke all on function public.sd_development_alert_current_actor_can_read(uuid,uuid,uuid,text)
from public,anon,authenticated,service_role;
grant execute on function public.sd_development_report_current_actor_can_read(uuid,uuid,uuid,text) to authenticated;
grant execute on function public.sd_development_alert_current_actor_can_read(uuid,uuid,uuid,text) to authenticated;

drop policy if exists "sd_development_reports_staff_read" on public.sd_development_reports;
drop policy if exists "sd_development_report_evidence_staff_read" on public.sd_development_report_evidence;
drop policy if exists "sd_development_report_review_events_staff_read" on public.sd_development_report_review_events;
drop policy if exists "sd_development_alerts_staff_read" on public.sd_development_alerts;
drop policy if exists "sd_development_alert_evidence_staff_read" on public.sd_development_alert_evidence;
drop policy if exists "sd_development_alert_events_staff_read" on public.sd_development_alert_events;

create policy "sd_development_reports_audience_read" on public.sd_development_reports
for select to authenticated using (
  player_id is not null and public.sd_development_report_current_actor_can_read(id,org_id,player_id,audience)
);
create policy "sd_development_report_evidence_audience_read" on public.sd_development_report_evidence
for select to authenticated using (
  public.sd_development_report_current_actor_can_read(report_id,org_id,player_id,audience)
);
create policy "sd_development_report_review_events_staff_read" on public.sd_development_report_review_events
for select to authenticated using (
  audience='staff' and exists(
    select 1 from public.sd_development_reports report
    where report.id=sd_development_report_review_events.report_id
      and report.org_id=sd_development_report_review_events.org_id
      and report.audience='staff'
      and report.player_id is not null
      and public.sd_development_actor_can_manage_player(auth.uid(),report.org_id,report.player_id)
  )
);
create policy "sd_development_alerts_audience_read" on public.sd_development_alerts
for select to authenticated using (
  public.sd_development_alert_current_actor_can_read(id,org_id,player_id,audience)
);
create policy "sd_development_alert_evidence_audience_read" on public.sd_development_alert_evidence
for select to authenticated using (
  public.sd_development_alert_current_actor_can_read(alert_id,org_id,player_id,audience)
);
create policy "sd_development_alert_events_staff_read" on public.sd_development_alert_events
for select to authenticated using (
  audience='staff' and exists(
    select 1 from public.sd_development_alerts alert
    where alert.id=sd_development_alert_events.alert_id
      and alert.org_id=sd_development_alert_events.org_id
      and alert.audience='staff'
      and public.sd_development_actor_can_manage_player(auth.uid(),alert.org_id,alert.player_id)
  )
);

create or replace function public.sd_create_development_report_audience(
  p_actor_id uuid,p_org_id uuid,p_player_id uuid,p_report_type text,p_intended_audience text,
  p_window_start date,p_window_end date,p_input_cutoff timestamptz,p_idempotency_key uuid,
  p_request_fingerprint text,p_evidence_fingerprint text,p_quality_status text,
  p_structured_content jsonb,p_rendered_text text,p_confidence numeric,p_data_freshness text,
  p_missing_data_warnings text[],p_evidence jsonb,p_audience text,
  p_prompt_version text,p_generator_version text
) returns jsonb language plpgsql security definer set search_path='' as $$
declare existing_report public.sd_development_reports; created_report public.sd_development_reports; evidence_item jsonb;
begin
  if p_audience='staff' then
    if not public.sd_development_actor_can_manage_player(p_actor_id,p_org_id,p_player_id) then raise exception 'development_staff_access_required'; end if;
  elsif p_audience='player' then
    if not public.sd_development_copilot_actor_can_access(p_actor_id,p_org_id,p_player_id,'player')
      or p_report_type<>'player_development_summary' or p_intended_audience<>'player'
      or p_prompt_version<>'player-development-self-summary.v1' then
      raise exception 'development_player_access_denied';
    end if;
  else raise exception 'invalid_development_report_audience';
  end if;
  if p_window_start>p_window_end or p_window_end-p_window_start>730
    or p_input_cutoff::date<p_window_end or p_input_cutoff>now()+interval '5 minutes'
    or length(coalesce(p_request_fingerprint,''))<8
    or p_evidence_fingerprint!~'^[0-9a-f]{64}$'
    or jsonb_typeof(coalesce(p_evidence,'[]'::jsonb))<>'array'
    or jsonb_array_length(coalesce(p_evidence,'[]'::jsonb))>5000 then
    raise exception 'invalid_development_report_request';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    p_org_id::text||':'||p_actor_id::text||':'||p_audience||':'||p_idempotency_key::text,0));
  select * into existing_report from public.sd_development_reports
  where org_id=p_org_id and requested_by=p_actor_id and audience=p_audience and idempotency_key=p_idempotency_key;
  if found then
    if existing_report.request_fingerprint<>p_request_fingerprint then raise exception 'development_report_idempotency_conflict'; end if;
    return pg_catalog.jsonb_build_object('report',pg_catalog.to_jsonb(existing_report),'reused',true);
  end if;
  insert into public.sd_development_reports(
    org_id,player_id,report_type,requested_by,intended_audience,audience,
    reporting_window_start,reporting_window_end,status,quality_status,structured_content,
    rendered_text,generation_mode,provider,model_identifier,generator_version,prompt_version,
    input_cutoff,generated_at,confidence,data_freshness,missing_data_warnings,
    idempotency_key,request_fingerprint,evidence_fingerprint
  ) values(
    p_org_id,p_player_id,p_report_type,p_actor_id,p_intended_audience,p_audience,
    p_window_start,p_window_end,'draft',p_quality_status,coalesce(p_structured_content,'{}'::jsonb),
    coalesce(p_rendered_text,''),'deterministic','deterministic_template',null,p_generator_version,p_prompt_version,
    p_input_cutoff,now(),p_confidence,p_data_freshness,coalesce(p_missing_data_warnings,'{}'::text[]),
    p_idempotency_key,p_request_fingerprint,p_evidence_fingerprint
  ) returning * into created_report;
  for evidence_item in select value from jsonb_array_elements(coalesce(p_evidence,'[]'::jsonb)) loop
    if evidence_item->>'evidence_key' is null or evidence_item->>'source_entity_type' is null
      or evidence_item->>'source_record_id' is null then raise exception 'invalid_development_evidence'; end if;
    if p_audience='player' and (
      evidence_item->>'source_entity_type' not in (
        'sd_testing_entries','player_development_import','sd_player_metric_observations',
        'sd_program_assignments','sd_daily_logs_window','sd_bp_sessions','sd_development_reports','sd_development_alerts'
      ) or lower(coalesce(evidence_item->>'display_label','')||' '||coalesce(evidence_item->>'explanation','')||' '||coalesce(evidence_item->'source_metadata','{}'::jsonb)::text)
        ~ '(coach.?note|staff|private|confidential|roster|ranking|comparison|parent|finance|billing|payment|recruit|storage|signed.?url|gps|device|serial|secret|token)'
    ) then raise exception 'invalid_player_development_evidence'; end if;
    insert into public.sd_development_report_evidence(
      report_id,org_id,player_id,audience,evidence_key,section_key,source_entity_type,source_record_id,
      canonical_metric_key,raw_observed_value,normalized_numeric_value,unit,observation_date,
      comparison_value,comparison_period,direction,sample_size,freshness,quality,deterministic_rule_id,
      display_label,explanation,source_metadata,evidence_snapshot
    ) values(
      created_report.id,p_org_id,p_player_id,p_audience,evidence_item->>'evidence_key',coalesce(evidence_item->>'section_key','metrics'),
      evidence_item->>'source_entity_type',evidence_item->>'source_record_id',evidence_item->>'canonical_metric_key',
      evidence_item->>'raw_observed_value',nullif(evidence_item->>'normalized_numeric_value','')::numeric,evidence_item->>'unit',
      nullif(evidence_item->>'observation_date','')::timestamptz,nullif(evidence_item->>'comparison_value','')::numeric,
      evidence_item->>'comparison_period',evidence_item->>'direction',nullif(evidence_item->>'sample_size','')::integer,
      coalesce(evidence_item->>'freshness','unavailable'),coalesce(evidence_item->>'quality','unavailable'),
      evidence_item->>'deterministic_rule_id',coalesce(evidence_item->>'display_label','Evidence'),
      coalesce(evidence_item->>'explanation','Recorded evidence.'),coalesce(evidence_item->'source_metadata','{}'::jsonb),
      coalesce(evidence_item->'evidence_snapshot','{}'::jsonb)
    ) on conflict(report_id,evidence_key) do nothing;
  end loop;
  insert into public.sd_development_report_review_events(report_id,org_id,actor_id,audience,event_type,from_status,to_status)
  values(created_report.id,p_org_id,p_actor_id,p_audience,'generated','generating','draft');
  return pg_catalog.jsonb_build_object('report',pg_catalog.to_jsonb(created_report),'reused',false);
end; $$;

create or replace function public.sd_review_development_report_audience(
  p_actor_id uuid,p_org_id uuid,p_report_id uuid,p_action text,p_review_notes text,
  p_coach_edits jsonb,p_audience text
) returns public.sd_development_reports language plpgsql security definer set search_path='' as $$
declare current_report public.sd_development_reports; prior_status text; next_status text; event_name text;
begin
  select * into current_report from public.sd_development_reports
  where id=p_report_id and org_id=p_org_id and audience=p_audience for update;
  if not found then raise exception 'report_not_found'; end if;
  if p_audience='player' then
    if p_action<>'archive' or current_report.status<>'draft'
      or not public.sd_development_copilot_actor_can_access(p_actor_id,p_org_id,current_report.player_id,'player')
      or current_report.requested_by<>p_actor_id then raise exception 'invalid_report_transition'; end if;
    next_status:='archived'; event_name:='archived';
  elsif p_audience='staff' then
    if not public.sd_development_actor_can_manage_player(p_actor_id,p_org_id,current_report.player_id) then raise exception 'development_staff_access_required'; end if;
    next_status:=case p_action when 'review' then 'reviewed' when 'edit' then 'reviewed' when 'approve' then 'approved' when 'reject' then 'rejected' when 'archive' then 'archived' else null end;
    event_name:=case p_action when 'review' then 'reviewed' when 'edit' then 'edited' else p_action||'d' end;
    if next_status is null
      or (current_report.status='draft' and next_status not in ('reviewed','approved','rejected','archived'))
      or (current_report.status='reviewed' and next_status not in ('reviewed','approved','rejected','archived'))
      or (current_report.status='approved' and next_status<>'archived')
      or current_report.status in ('failed','rejected','archived') then raise exception 'invalid_report_transition'; end if;
  else raise exception 'invalid_development_report_audience'; end if;
  prior_status:=current_report.status;
  update public.sd_development_reports set status=next_status,
    reviewed_at=case when p_audience='staff' and next_status in ('reviewed','approved','rejected') then now() else reviewed_at end,
    reviewed_by=case when p_audience='staff' and next_status in ('reviewed','approved','rejected') then p_actor_id else reviewed_by end,
    approved_at=case when p_audience='staff' and next_status='approved' then now() else approved_at end,
    rejected_at=case when p_audience='staff' and next_status='rejected' then now() else rejected_at end,
    archived_at=case when next_status='archived' then now() else archived_at end,
    coach_edits=case when p_audience='staff' and p_action='edit' then coalesce(p_coach_edits,'{}'::jsonb) else coach_edits end,
    review_notes=case when p_audience='staff' then coalesce(nullif(pg_catalog.btrim(p_review_notes),''),review_notes) else null end
  where id=p_report_id returning * into current_report;
  insert into public.sd_development_report_review_events(report_id,org_id,actor_id,audience,event_type,from_status,to_status,review_notes,coach_edits_snapshot)
  values(p_report_id,p_org_id,p_actor_id,p_audience,event_name,prior_status,next_status,
    case when p_audience='staff' then nullif(pg_catalog.btrim(p_review_notes),'') else null end,
    case when p_audience='staff' then coalesce(p_coach_edits,'{}'::jsonb) else '{}'::jsonb end);
  return current_report;
end; $$;

create or replace function public.sd_upsert_development_alerts_audience(
  p_actor_id uuid,p_org_id uuid,p_alerts jsonb,p_audience text
) returns setof public.sd_development_alerts language plpgsql security definer set search_path='' as $$
declare item jsonb; evidence_item jsonb; target_player uuid; saved_alert public.sd_development_alerts; prior_status text;
begin
  if p_audience not in ('staff','player') or jsonb_typeof(coalesce(p_alerts,'[]'::jsonb))<>'array'
    or jsonb_array_length(coalesce(p_alerts,'[]'::jsonb))>250 then raise exception 'invalid_development_alert_request'; end if;
  for item in select value from jsonb_array_elements(coalesce(p_alerts,'[]'::jsonb)) loop
    target_player:=(item->>'player_id')::uuid;
    if (p_audience='staff' and not public.sd_development_actor_can_manage_player(p_actor_id,p_org_id,target_player))
      or (p_audience='player' and not public.sd_development_copilot_actor_can_access(p_actor_id,p_org_id,target_player,'player'))
      or (item ? 'audience' and item->>'audience'<>p_audience) then raise exception 'development_player_access_denied'; end if;
    if p_audience='player' and item->>'alert_type' not in (
      'no_recent_testing','stale_testing','meaningful_metric_improvement','meaningful_metric_regression',
      'inconsistent_units','insufficient_sample_size'
    ) then raise exception 'invalid_player_alert_type'; end if;
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
      p_org_id::text||':'||target_player::text||':'||p_audience||':'||(item->>'deduplication_key'),0));
    select status into prior_status from public.sd_development_alerts
    where org_id=p_org_id and player_id=target_player and audience=p_audience and deduplication_key=item->>'deduplication_key';
    insert into public.sd_development_alerts(
      org_id,player_id,report_id,audience,alert_type,severity,status,first_detected_at,last_detected_at,
      evidence_window_start,evidence_window_end,rule_version,explanation,recommended_human_action,
      data_freshness,evidence_quality,deduplication_key
    ) values(
      p_org_id,target_player,nullif(item->>'report_id','')::uuid,p_audience,item->>'alert_type',item->>'severity','active',now(),now(),
      (item->>'evidence_window_start')::date,(item->>'evidence_window_end')::date,item->>'rule_version',
      item->>'explanation',item->>'recommended_human_action',item->>'data_freshness',item->>'evidence_quality',item->>'deduplication_key'
    ) on conflict(org_id,player_id,audience,deduplication_key) do update set
      last_detected_at=now(),severity=excluded.severity,explanation=excluded.explanation,
      recommended_human_action=excluded.recommended_human_action,data_freshness=excluded.data_freshness,
      evidence_quality=excluded.evidence_quality,evidence_window_start=excluded.evidence_window_start,
      evidence_window_end=excluded.evidence_window_end
    returning * into saved_alert;
    for evidence_item in select value from jsonb_array_elements(coalesce(item->'evidence','[]'::jsonb)) loop
      if p_audience='player' and evidence_item->>'source_entity_type' not in (
        'sd_testing_entries','player_development_import','sd_player_metric_observations','sd_program_assignments',
        'sd_daily_logs_window','sd_bp_sessions','sd_development_reports','sd_development_alerts'
      ) then raise exception 'invalid_player_development_evidence'; end if;
      insert into public.sd_development_alert_evidence(
        alert_id,org_id,player_id,audience,evidence_key,source_entity_type,source_record_id,
        canonical_metric_key,observation_date,display_label,explanation,evidence_snapshot
      ) values(
        saved_alert.id,p_org_id,target_player,p_audience,evidence_item->>'evidence_key',evidence_item->>'source_entity_type',
        evidence_item->>'source_record_id',evidence_item->>'canonical_metric_key',nullif(evidence_item->>'observation_date','')::timestamptz,
        coalesce(evidence_item->>'display_label','Evidence'),coalesce(evidence_item->>'explanation','Recorded evidence.'),
        coalesce(evidence_item->'evidence_snapshot','{}'::jsonb)
      ) on conflict(alert_id,evidence_key) do update set evidence_snapshot=excluded.evidence_snapshot,explanation=excluded.explanation;
    end loop;
    insert into public.sd_development_alert_events(alert_id,org_id,actor_id,audience,event_type,from_status,to_status)
    values(saved_alert.id,p_org_id,p_actor_id,p_audience,case when prior_status is null then 'detected' else 'redetected' end,prior_status,saved_alert.status);
    return next saved_alert;
  end loop;
end; $$;

create or replace function public.sd_review_development_alert_audience(
  p_actor_id uuid,p_org_id uuid,p_alert_id uuid,p_action text,p_notes text,p_audience text
) returns public.sd_development_alerts language plpgsql security definer set search_path='' as $$
declare current_alert public.sd_development_alerts; prior_status text; next_status text;
begin
  select * into current_alert from public.sd_development_alerts
  where id=p_alert_id and org_id=p_org_id and audience=p_audience for update;
  if not found then raise exception 'alert_not_found'; end if;
  if p_audience='player' then
    if p_action<>'dismiss' or not public.sd_development_copilot_actor_can_access(p_actor_id,p_org_id,current_alert.player_id,'player')
      then raise exception 'invalid_alert_transition'; end if;
    next_status:='dismissed';
  elsif p_audience='staff' then
    if not public.sd_development_actor_can_manage_player(p_actor_id,p_org_id,current_alert.player_id) then raise exception 'development_staff_access_required'; end if;
    next_status:=case p_action when 'acknowledge' then 'acknowledged' when 'dismiss' then 'dismissed' when 'resolve' then 'resolved' when 'archive' then 'archived' else null end;
  else raise exception 'invalid_development_alert_audience'; end if;
  prior_status:=current_alert.status;
  if next_status is null or prior_status in ('dismissed','resolved','archived')
    or (prior_status='acknowledged' and next_status='acknowledged') then raise exception 'invalid_alert_transition'; end if;
  update public.sd_development_alerts set status=next_status,
    acknowledged_at=case when next_status='acknowledged' then now() else acknowledged_at end,
    acknowledged_by=case when next_status='acknowledged' then p_actor_id else acknowledged_by end,
    dismissed_at=case when next_status='dismissed' then now() else dismissed_at end,
    dismissed_by=case when next_status='dismissed' then p_actor_id else dismissed_by end,
    resolved_at=case when next_status='resolved' then now() else resolved_at end,
    resolved_by=case when next_status='resolved' then p_actor_id else resolved_by end,
    archived_at=case when next_status='archived' then now() else archived_at end,
    archived_by=case when next_status='archived' then p_actor_id else archived_by end
  where id=p_alert_id returning * into current_alert;
  insert into public.sd_development_alert_events(alert_id,org_id,actor_id,audience,event_type,from_status,to_status,notes)
  values(p_alert_id,p_org_id,p_actor_id,p_audience,next_status,prior_status,next_status,
    case when p_audience='staff' then nullif(pg_catalog.btrim(p_notes),'') else null end);
  return current_alert;
end; $$;

-- Retire the Phase 11A service mutation signatures; all post-11C writes carry audience.
revoke execute on function public.sd_create_development_report(uuid,uuid,uuid,text,text,date,date,timestamptz,uuid,text,text,text,jsonb,text,numeric,text,text[],jsonb) from service_role;
revoke execute on function public.sd_review_development_report(uuid,uuid,uuid,text,text,jsonb) from service_role;
revoke execute on function public.sd_upsert_development_alerts(uuid,uuid,jsonb) from service_role;
revoke execute on function public.sd_review_development_alert(uuid,uuid,uuid,text,text) from service_role;
revoke all on function public.sd_create_development_report_audience(uuid,uuid,uuid,text,text,date,date,timestamptz,uuid,text,text,text,jsonb,text,numeric,text,text[],jsonb,text,text,text) from public,anon,authenticated,service_role;
revoke all on function public.sd_review_development_report_audience(uuid,uuid,uuid,text,text,jsonb,text) from public,anon,authenticated,service_role;
revoke all on function public.sd_upsert_development_alerts_audience(uuid,uuid,jsonb,text) from public,anon,authenticated,service_role;
revoke all on function public.sd_review_development_alert_audience(uuid,uuid,uuid,text,text,text) from public,anon,authenticated,service_role;
grant execute on function public.sd_create_development_report_audience(uuid,uuid,uuid,text,text,date,date,timestamptz,uuid,text,text,text,jsonb,text,numeric,text,text[],jsonb,text,text,text) to service_role;
grant execute on function public.sd_review_development_report_audience(uuid,uuid,uuid,text,text,jsonb,text) to service_role;
grant execute on function public.sd_upsert_development_alerts_audience(uuid,uuid,jsonb,text) to service_role;
grant execute on function public.sd_review_development_alert_audience(uuid,uuid,uuid,text,text,text) to service_role;

insert into public.sd_development_copilot_prompt_versions(
  prompt_key,use_case,intended_audience,version,evidence_schema_version,output_schema_version,
  safety_version,template_metadata,is_active
) values
('player_development_summary','player_development_summary','player','player-development-self-summary.v1',
 'player_development_evidence_pack.v1','player_development_report.v1','player-development-safety.v1',
 '{"client_system_prompts":false,"player_evidence_policy":"allowlist.v1","staff_review_workflow":false}'::jsonb,true),
('player_alert_explanation','alert_explanation','player','player-alert-explanation.v1',
 'player_development_evidence_pack.v1','player_development_alert.v1','player-development-safety.v1',
 '{"client_system_prompts":false,"notification_delivery":false,"nonjudgmental_wording":true}'::jsonb,true)
on conflict(prompt_key,use_case,intended_audience,version) do nothing;
