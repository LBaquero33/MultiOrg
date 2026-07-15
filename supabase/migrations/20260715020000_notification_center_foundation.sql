-- Home Plate Phase 9A: multi-tenant in-app notification center.
--
-- This migration is additive. It creates the recipient-owned inbox, a small
-- announcement idempotency ledger, service-role-only producer functions, and
-- transaction-local producers for payment requests and verified payments.
-- It does not add an external delivery channel or change financial state.
--
-- Rollback: deploy clients/functions that no longer use notification-center,
-- drop the two producer triggers and their trigger functions, drop the four
-- RPCs below, then drop sd_notification_batches and sd_notifications. Existing
-- notification rows should normally be retained as user-visible history.

create table if not exists public.sd_notifications (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  org_id uuid not null references public.sd_orgs(id) on delete cascade,
  recipient_user_id uuid not null references auth.users(id) on delete cascade,
  category text not null,
  title text not null,
  body text not null,
  related_entity_type text,
  related_entity_id text,
  action_route text,
  action_payload jsonb not null default '{}'::jsonb,
  deduplication_key text not null,
  created_at timestamptz not null default pg_catalog.now(),
  read_at timestamptz,
  archived_at timestamptz,
  created_by uuid references auth.users(id) on delete set null,
  source text not null,
  metadata jsonb not null default '{}'::jsonb,
  constraint sd_notifications_category_check check (category in (
    'payment_request_created',
    'payment_received',
    'booking_created',
    'booking_updated',
    'program_assigned',
    'program_updated',
    'message_received',
    'testing_result_added',
    'organization_announcement',
    'system'
  )),
  constraint sd_notifications_title_check
    check (pg_catalog.char_length(pg_catalog.btrim(title)) between 1 and 120),
  constraint sd_notifications_body_check
    check (pg_catalog.char_length(pg_catalog.btrim(body)) between 1 and 2000),
  constraint sd_notifications_entity_type_check
    check (related_entity_type is null or pg_catalog.char_length(related_entity_type) between 1 and 80),
  constraint sd_notifications_entity_id_check
    check (related_entity_id is null or pg_catalog.char_length(related_entity_id) between 1 and 200),
  constraint sd_notifications_route_check
    check (action_route is null or pg_catalog.char_length(action_route) between 1 and 80),
  constraint sd_notifications_action_payload_check
    check (pg_catalog.jsonb_typeof(action_payload) = 'object'),
  constraint sd_notifications_deduplication_check
    check (pg_catalog.char_length(deduplication_key) between 1 and 255),
  constraint sd_notifications_source_check
    check (source in ('payment_request', 'payment_webhook', 'announcement', 'system')),
  constraint sd_notifications_metadata_check
    check (pg_catalog.jsonb_typeof(metadata) = 'object')
);

comment on table public.sd_notifications is
  'Organization-scoped in-app notifications readable only by their recipient.';
comment on column public.sd_notifications.action_payload is
  'Minimal internal navigation identifiers; never provider payloads or secrets.';
comment on column public.sd_notifications.metadata is
  'Server-only producer diagnostics; omitted from the public response contract.';

create unique index if not exists ux_sd_notifications_recipient_dedup
  on public.sd_notifications(
    org_id,
    recipient_user_id,
    category,
    deduplication_key
  );
create index if not exists idx_sd_notifications_recipient_created
  on public.sd_notifications(recipient_user_id, created_at desc, id desc);
create index if not exists idx_sd_notifications_recipient_org_created
  on public.sd_notifications(recipient_user_id, org_id, created_at desc, id desc);
create index if not exists idx_sd_notifications_recipient_unread
  on public.sd_notifications(recipient_user_id, org_id, created_at desc)
  where read_at is null and archived_at is null;
create index if not exists idx_sd_notifications_org_created
  on public.sd_notifications(org_id, created_at desc);

alter table public.sd_notifications enable row level security;
revoke all on table public.sd_notifications from public, anon, authenticated;
grant select on table public.sd_notifications to authenticated;
grant update (read_at, archived_at) on table public.sd_notifications to authenticated;
grant select, insert, update on table public.sd_notifications to service_role;

drop policy if exists "sd_notifications_select_own" on public.sd_notifications;
create policy "sd_notifications_select_own"
  on public.sd_notifications
  for select
  to authenticated
  using (recipient_user_id = (select auth.uid()));

drop policy if exists "sd_notifications_update_own" on public.sd_notifications;
create policy "sd_notifications_update_own"
  on public.sd_notifications
  for update
  to authenticated
  using (recipient_user_id = (select auth.uid()))
  with check (recipient_user_id = (select auth.uid()));

create or replace function public.sd_notifications_guard_update()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.id is distinct from old.id
    or new.org_id is distinct from old.org_id
    or new.recipient_user_id is distinct from old.recipient_user_id
    or new.category is distinct from old.category
    or new.title is distinct from old.title
    or new.body is distinct from old.body
    or new.related_entity_type is distinct from old.related_entity_type
    or new.related_entity_id is distinct from old.related_entity_id
    or new.action_route is distinct from old.action_route
    or new.action_payload is distinct from old.action_payload
    or new.deduplication_key is distinct from old.deduplication_key
    or new.created_at is distinct from old.created_at
    or new.created_by is distinct from old.created_by
    or new.source is distinct from old.source
    or new.metadata is distinct from old.metadata then
    raise exception 'notification_fields_are_immutable' using errcode = '23514';
  end if;
  if old.read_at is not null and new.read_at is distinct from old.read_at then
    raise exception 'notification_read_state_is_terminal' using errcode = '23514';
  end if;
  if old.archived_at is not null and new.archived_at is distinct from old.archived_at then
    raise exception 'notification_archive_state_is_terminal' using errcode = '23514';
  end if;
  return new;
end;
$$;

revoke all on function public.sd_notifications_guard_update()
from public, anon, authenticated;
drop trigger if exists trg_sd_notifications_guard_update on public.sd_notifications;
create trigger trg_sd_notifications_guard_update
before update on public.sd_notifications
for each row execute function public.sd_notifications_guard_update();

-- A compact server-only ledger binds an announcement idempotency key to the
-- exact actor, audience, authorization path, content fingerprint, and initial
-- recipient set. It is not exposed as notification content or audit output.
create table if not exists public.sd_notification_batches (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  org_id uuid not null references public.sd_orgs(id) on delete cascade,
  category text not null,
  source text not null,
  deduplication_key uuid not null,
  created_by uuid not null references auth.users(id) on delete restrict,
  authorization_source text not null,
  audience text not null,
  material_fingerprint text not null,
  recipient_user_ids uuid[] not null,
  created_at timestamptz not null default pg_catalog.now(),
  constraint sd_notification_batches_category_check
    check (category = 'organization_announcement'),
  constraint sd_notification_batches_source_check check (source = 'announcement'),
  constraint sd_notification_batches_authorization_check
    check (authorization_source in ('organization_membership', 'platform_support')),
  constraint sd_notification_batches_audience_check
    check (audience in ('all', 'players', 'parents', 'coaches', 'staff')),
  constraint sd_notification_batches_fingerprint_check
    check (material_fingerprint ~ '^[0-9a-f]{64}$'),
  constraint sd_notification_batches_recipients_check
    check (pg_catalog.cardinality(recipient_user_ids) between 1 and 1000),
  unique (org_id, category, source, deduplication_key)
);

comment on table public.sd_notification_batches is
  'Server-only idempotency ledger for bounded organization announcement batches.';
alter table public.sd_notification_batches enable row level security;
revoke all on table public.sd_notification_batches
from public, anon, authenticated, service_role;
grant select, insert, update on table public.sd_notification_batches to service_role;

-- Reusable server-side producer. Every recipient must have an active
-- membership in the same organization; callers provide only server-derived
-- facts. The per-recipient unique key makes repeated production idempotent.
create or replace function public.sd_create_notifications(
  p_org_id uuid,
  p_recipient_user_ids uuid[],
  p_category text,
  p_title text,
  p_body text,
  p_related_entity_type text,
  p_related_entity_id text,
  p_action_route text,
  p_action_payload jsonb,
  p_deduplication_key text,
  p_created_by uuid,
  p_source text,
  p_metadata jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_recipient_user_ids uuid[];
  v_created_count integer := 0;
begin
  select coalesce(
    pg_catalog.array_agg(recipient.user_id order by recipient.user_id),
    array[]::uuid[]
  )
  into v_recipient_user_ids
  from (
    select distinct supplied.user_id
    from pg_catalog.unnest(p_recipient_user_ids) supplied(user_id)
    where supplied.user_id is not null
  ) recipient;

  if p_org_id is null
    or pg_catalog.cardinality(v_recipient_user_ids) not between 1 and 1000
    or p_category not in (
      'payment_request_created', 'payment_received', 'booking_created',
      'booking_updated', 'program_assigned', 'program_updated',
      'message_received', 'testing_result_added',
      'organization_announcement', 'system'
    )
    or pg_catalog.char_length(pg_catalog.btrim(p_title)) not between 1 and 120
    or pg_catalog.char_length(pg_catalog.btrim(p_body)) not between 1 and 2000
    or pg_catalog.char_length(pg_catalog.btrim(p_deduplication_key)) not between 1 and 255
    or p_source not in ('payment_request', 'payment_webhook', 'announcement', 'system')
    or pg_catalog.jsonb_typeof(coalesce(p_action_payload, '{}'::jsonb)) <> 'object'
    or pg_catalog.jsonb_typeof(coalesce(p_metadata, '{}'::jsonb)) <> 'object' then
    raise exception 'invalid_notification_input' using errcode = '22023';
  end if;

  if not exists (
    select 1 from public.sd_orgs organization
    where organization.id = p_org_id and organization.status = 'active'
  ) then
    raise exception 'notification_organization_inactive' using errcode = 'P0001';
  end if;

  if (
    select pg_catalog.count(distinct membership.user_id)
    from public.sd_org_memberships membership
    where membership.org_id = p_org_id
      and membership.user_id = any(v_recipient_user_ids)
      and membership.status = 'active'
  ) <> pg_catalog.cardinality(v_recipient_user_ids) then
    raise exception 'notification_recipient_membership_required' using errcode = 'P0001';
  end if;

  insert into public.sd_notifications (
    org_id,
    recipient_user_id,
    category,
    title,
    body,
    related_entity_type,
    related_entity_id,
    action_route,
    action_payload,
    deduplication_key,
    created_by,
    source,
    metadata
  )
  select
    p_org_id,
    recipient.user_id,
    p_category,
    pg_catalog.btrim(p_title),
    pg_catalog.btrim(p_body),
    nullif(pg_catalog.btrim(p_related_entity_type), ''),
    nullif(pg_catalog.btrim(p_related_entity_id), ''),
    nullif(pg_catalog.btrim(p_action_route), ''),
    coalesce(p_action_payload, '{}'::jsonb),
    pg_catalog.btrim(p_deduplication_key),
    p_created_by,
    p_source,
    coalesce(p_metadata, '{}'::jsonb)
  from pg_catalog.unnest(v_recipient_user_ids) recipient(user_id)
  on conflict (org_id, recipient_user_id, category, deduplication_key)
  do nothing;

  get diagnostics v_created_count = row_count;
  return pg_catalog.jsonb_build_object(
    'created_count', v_created_count,
    'recipient_count', pg_catalog.cardinality(v_recipient_user_ids)
  );
end;
$$;

revoke all on function public.sd_create_notifications(
  uuid, uuid[], text, text, text, text, text, text, jsonb, text, uuid, text, jsonb
) from public, anon, authenticated;
grant execute on function public.sd_create_notifications(
  uuid, uuid[], text, text, text, text, text, text, jsonb, text, uuid, text, jsonb
) to service_role;

-- Payment request notifications are part of the request insert transaction.
-- The player and active linked parents are recipients; can_pay is deliberately
-- irrelevant because request visibility and future payment authority differ.
create or replace function public.sd_notify_payment_request_created()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org_name text;
  v_recipient_user_ids uuid[];
  v_amount text;
begin
  select organization.name into v_org_name
  from public.sd_orgs organization where organization.id = new.org_id;

  select pg_catalog.array_agg(recipient.user_id order by recipient.user_id)
  into v_recipient_user_ids
  from (
    select new.child_id as user_id
    union
    select link.parent_id
    from public.sd_parent_child_links link
    join public.sd_org_memberships parent_membership
      on parent_membership.org_id = new.org_id
     and parent_membership.user_id = link.parent_id
     and parent_membership.role = 'parent'
     and parent_membership.status = 'active'
    where link.org_id = new.org_id and link.child_id = new.child_id
  ) recipient;

  v_amount := pg_catalog.format(
    '$%s.%s',
    new.amount_cents / 100,
    pg_catalog.lpad((new.amount_cents % 100)::text, 2, '0')
  );

  perform public.sd_create_notifications(
    new.org_id,
    v_recipient_user_ids,
    'payment_request_created',
    pg_catalog.left('Payment request from ' || coalesce(v_org_name, 'your organization'), 120),
    pg_catalog.left('A new payment request for ' || v_amount || ' is ready: ' || new.title, 2000),
    'payment_request',
    new.id::text,
    'payment_request',
    pg_catalog.jsonb_build_object('payment_request_id', new.id),
    'payment_request_created:' || new.id::text,
    new.created_by,
    'payment_request',
    pg_catalog.jsonb_build_object('request_batch_id', new.request_batch_id)
  );
  return new;
end;
$$;

revoke all on function public.sd_notify_payment_request_created()
from public, anon, authenticated;
drop trigger if exists trg_sd_notify_payment_request_created
on public.sd_payment_requests;
create trigger trg_sd_notify_payment_request_created
after insert on public.sd_payment_requests
for each row execute function public.sd_notify_payment_request_created();

-- A verified successful payment is already represented by sd_payments. This
-- reusable RPC derives all recipients from that authoritative row and its
-- payment request; clients cannot synthesize payment-received facts.
create or replace function public.sd_produce_payment_received_notifications(
  p_payment_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_payment public.sd_payments%rowtype;
  v_request public.sd_payment_requests%rowtype;
  v_org_name text;
  v_recipient_user_ids uuid[];
  v_amount text;
begin
  select payment.* into v_payment
  from public.sd_payments payment
  where payment.id = p_payment_id
    and payment.payment_request_id is not null
    and payment.status in ('succeeded', 'paid');
  if v_payment.id is null then
    raise exception 'successful_payment_required' using errcode = 'P0001';
  end if;

  select request.* into v_request
  from public.sd_payment_requests request
  where request.id = v_payment.payment_request_id
    and request.org_id = v_payment.org_id;
  if v_request.id is null then
    raise exception 'payment_request_not_found' using errcode = 'P0001';
  end if;

  select organization.name into v_org_name
  from public.sd_orgs organization where organization.id = v_payment.org_id;

  select pg_catalog.array_agg(recipient.user_id order by recipient.user_id)
  into v_recipient_user_ids
  from (
    select player.user_id
    from public.sd_org_memberships player
    where player.org_id = v_payment.org_id
      and player.user_id = v_request.child_id
      and player.role = 'player'
      and player.status = 'active'
    union
    select link.parent_id
    from public.sd_parent_child_links link
    join public.sd_org_memberships parent_membership
      on parent_membership.org_id = v_payment.org_id
     and parent_membership.user_id = link.parent_id
     and parent_membership.role = 'parent'
     and parent_membership.status = 'active'
    where link.org_id = v_payment.org_id and link.child_id = v_request.child_id
    union
    select staff.user_id
    from public.sd_org_memberships staff
    where staff.org_id = v_payment.org_id
      and staff.role in ('owner', 'admin')
      and staff.status = 'active'
  ) recipient;

  v_amount := pg_catalog.format(
    '$%s.%s',
    v_payment.amount_cents / 100,
    pg_catalog.lpad((v_payment.amount_cents % 100)::text, 2, '0')
  );

  return public.sd_create_notifications(
    v_payment.org_id,
    v_recipient_user_ids,
    'payment_received',
    'Payment received',
    pg_catalog.left(coalesce(v_org_name, 'Your organization') || ' received ' || v_amount || ' for ' || v_request.title || '.', 2000),
    'payment_request',
    v_request.id::text,
    'payment',
    pg_catalog.jsonb_build_object(
      'payment_request_id', v_request.id,
      'payment_id', v_payment.id
    ),
    'payment_received:' || v_payment.id::text,
    null,
    'payment_webhook',
    pg_catalog.jsonb_build_object('payment_id', v_payment.id)
  );
end;
$$;

revoke all on function public.sd_produce_payment_received_notifications(uuid)
from public, anon, authenticated;
grant execute on function public.sd_produce_payment_received_notifications(uuid)
to service_role;

-- Notification failure is deliberately non-financial. The warning contains
-- only an internal payment UUID, and an operator can safely retry the producer
-- RPC because its deduplication key is deterministic.
create or replace function public.sd_notify_payment_received()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.payment_request_id is null or new.status not in ('succeeded', 'paid') then
    return new;
  end if;
  if tg_op = 'UPDATE' and old.status in ('succeeded', 'paid') then
    return new;
  end if;
  begin
    perform public.sd_produce_payment_received_notifications(new.id);
  exception when others then
    raise warning 'payment_received_notification_failed payment_id=%', new.id;
  end;
  return new;
end;
$$;

revoke all on function public.sd_notify_payment_received()
from public, anon, authenticated;
drop trigger if exists trg_sd_notify_payment_received on public.sd_payments;
create trigger trg_sd_notify_payment_received
after insert or update of status on public.sd_payments
for each row execute function public.sd_notify_payment_received();

-- Announcement recipients always come from active organization memberships.
-- "staff" means owner, admin, and coach for this MVP. The actor is included
-- only when their own active membership matches the chosen audience; platform
-- support never receives membership or implicit inbox access.
create or replace function public.sd_create_organization_announcement(
  p_org_id uuid,
  p_actor_id uuid,
  p_title text,
  p_body text,
  p_audience text,
  p_support_mode boolean,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_title text := pg_catalog.btrim(p_title);
  v_body text := pg_catalog.btrim(p_body);
  v_authorization_source text;
  v_recipient_user_ids uuid[];
  v_fingerprint text;
  v_batch public.sd_notification_batches%rowtype;
  v_created boolean := false;
  v_result jsonb;
  v_created_count integer := 0;
begin
  if p_org_id is null or p_actor_id is null or p_idempotency_key is null
    or p_support_mode is null
    or pg_catalog.char_length(v_title) not between 1 and 120
    or pg_catalog.char_length(v_body) not between 1 and 2000
    or p_audience not in ('all', 'players', 'parents', 'coaches', 'staff') then
    raise exception 'invalid_announcement_input' using errcode = '22023';
  end if;
  if not exists (
    select 1 from public.sd_orgs organization
    where organization.id = p_org_id and organization.status = 'active'
  ) then
    raise exception 'announcement_organization_inactive' using errcode = 'P0001';
  end if;

  if p_support_mode then
    if not exists (
      select 1 from public.sd_platform_admins platform_admin
      where platform_admin.user_id = p_actor_id
    ) then
      raise exception 'platform_support_required' using errcode = 'P0001';
    end if;
    v_authorization_source := 'platform_support';
  elsif exists (
    select 1 from public.sd_org_memberships actor
    where actor.org_id = p_org_id
      and actor.user_id = p_actor_id
      and actor.role in ('owner', 'admin')
      and actor.status = 'active'
  ) then
    v_authorization_source := 'organization_membership';
  else
    raise exception 'organization_admin_required' using errcode = 'P0001';
  end if;

  select pg_catalog.array_agg(recipient.user_id order by recipient.user_id)
  into v_recipient_user_ids
  from (
    select distinct membership.user_id
    from public.sd_org_memberships membership
    where membership.org_id = p_org_id
      and membership.status = 'active'
      and (
        p_audience = 'all'
        or (p_audience = 'players' and membership.role = 'player')
        or (p_audience = 'parents' and membership.role = 'parent')
        or (p_audience = 'coaches' and membership.role = 'coach')
        or (p_audience = 'staff' and membership.role in ('owner', 'admin', 'coach'))
      )
  ) recipient;

  if coalesce(pg_catalog.cardinality(v_recipient_user_ids), 0) = 0 then
    raise exception 'announcement_audience_empty' using errcode = 'P0001';
  end if;
  if pg_catalog.cardinality(v_recipient_user_ids) > 1000 then
    raise exception 'announcement_audience_too_large' using errcode = 'P0001';
  end if;

  v_fingerprint := pg_catalog.encode(
    extensions.digest(
      pg_catalog.convert_to(
        v_title || pg_catalog.chr(31) || v_body || pg_catalog.chr(31)
          || p_audience || pg_catalog.chr(31) || p_support_mode::text,
        'UTF8'
      ),
      'sha256'
    ),
    'hex'
  );

  insert into public.sd_notification_batches (
    org_id,
    category,
    source,
    deduplication_key,
    created_by,
    authorization_source,
    audience,
    material_fingerprint,
    recipient_user_ids
  ) values (
    p_org_id,
    'organization_announcement',
    'announcement',
    p_idempotency_key,
    p_actor_id,
    v_authorization_source,
    p_audience,
    v_fingerprint,
    v_recipient_user_ids
  )
  on conflict (org_id, category, source, deduplication_key)
  do nothing
  returning * into v_batch;

  if v_batch.id is null then
    select batch.* into v_batch
    from public.sd_notification_batches batch
    where batch.org_id = p_org_id
      and batch.category = 'organization_announcement'
      and batch.source = 'announcement'
      and batch.deduplication_key = p_idempotency_key
    for update;
    if v_batch.id is null then
      raise exception 'announcement_idempotency_lookup_failed' using errcode = 'P0001';
    end if;
    if v_batch.created_by is distinct from p_actor_id
      or v_batch.authorization_source is distinct from v_authorization_source
      or v_batch.audience is distinct from p_audience
      or v_batch.material_fingerprint is distinct from v_fingerprint then
      raise exception 'announcement_idempotency_conflict' using errcode = 'P0001';
    end if;
  else
    v_created := true;
    v_result := public.sd_create_notifications(
      p_org_id,
      v_batch.recipient_user_ids,
      'organization_announcement',
      v_title,
      v_body,
      'organization_announcement',
      v_batch.id::text,
      'organization_announcement',
      pg_catalog.jsonb_build_object('announcement_id', v_batch.id),
      'organization_announcement:' || v_batch.id::text,
      p_actor_id,
      'announcement',
      pg_catalog.jsonb_build_object('audience', p_audience)
    );
    v_created_count := (v_result ->> 'created_count')::integer;

    insert into public.sd_platform_audit_logs (
      actor_id,
      action,
      target_type,
      target_id,
      org_id,
      details
    ) values (
      p_actor_id,
      'organization_announcement_created',
      'notification_batch',
      v_batch.id::text,
      p_org_id,
      pg_catalog.jsonb_build_object(
        'audience', p_audience,
        'deduplication_key', p_idempotency_key,
        'recipient_count', pg_catalog.cardinality(v_batch.recipient_user_ids),
        'authorization_source', v_authorization_source
      )
    );
  end if;

  return pg_catalog.jsonb_build_object(
    'announcement_id', v_batch.id,
    'created_count', v_created_count,
    'recipient_count', pg_catalog.cardinality(v_batch.recipient_user_ids),
    'reused', not v_created,
    'authorization_source', v_authorization_source
  );
end;
$$;

revoke all on function public.sd_create_organization_announcement(
  uuid, uuid, text, text, text, boolean, uuid
) from public, anon, authenticated;
grant execute on function public.sd_create_organization_announcement(
  uuid, uuid, text, text, text, boolean, uuid
) to service_role;
