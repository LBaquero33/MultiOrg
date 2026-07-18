-- Home Plate Phase 9C: direct-message notification integration and reliable
-- message retry/read synchronization.
--
-- This migration is additive. sd_notifications remains the inbox source of
-- truth and sd_notification_deliveries remains the only APNs queue.
-- Notification-production errors are caught by the message trigger so they
-- cannot roll back an already-persisted chat message.
--
-- Rollback guidance (do not run while Phase 9C clients are active): revert
-- clients to direct message inserts/read-cursor upserts; drop the notification
-- trigger and its function; drop sd_mark_chat_conversation_read and
-- sd_send_chat_message; restore sd_queue_apns_deliveries without
-- message_received; restore sd_create_notifications without the chat source;
-- remove the chat source constraint value; then drop the client-message unique
-- index and client_message_id column; restore sd_chat_channel_last_message
-- without message_id; then drop last_read_message_id from chat memberships.
-- Retain existing notifications and deliveries as user-visible/audit history
-- rather than hard-deleting them.

alter table public.sd_chat_messages
  add column if not exists client_message_id uuid;

comment on column public.sd_chat_messages.client_message_id is
  'Stable client operation UUID used to make ambiguous message-send retries idempotent.';

alter table public.sd_chat_memberships
  add column if not exists last_read_message_id uuid;

comment on column public.sd_chat_memberships.last_read_message_id is
  'Deterministic UUID tie-breaker for the last_read_at conversation cursor.';

-- Preserve the exact historical timestamp-cursor meaning by selecting the
-- greatest message tuple that the old `created_at <= last_read_at` rule treated
-- as read. This is the only historical backfill in Phase 9C.
update public.sd_chat_memberships membership
set last_read_message_id = (
  select message.id
  from public.sd_chat_messages message
  where message.channel_id = membership.channel_id
    and message.created_at <= membership.last_read_at
  order by message.created_at desc, message.id desc
  limit 1
)
where membership.last_read_at is not null
  and membership.last_read_message_id is null
  and exists (
    select 1
    from public.sd_chat_messages message
    where message.channel_id = membership.channel_id
      and message.created_at <= membership.last_read_at
  );

create unique index if not exists ux_sd_chat_messages_sender_client_operation
  on public.sd_chat_messages(org_id, sender_id, client_message_id)
  where sender_id is not null and client_message_id is not null;

-- The original view ordered only by created_at. Include the message UUID so
-- equal timestamps have the same stable ordering as the read cursor.
create or replace view public.sd_chat_channel_last_message as
select distinct on (message.channel_id)
  message.channel_id,
  pg_catalog.left(message.body, 140) as body_preview,
  message.created_at as message_created_at,
  message.id as message_id
from public.sd_chat_messages message
where message.deleted_at is null
order by message.channel_id, message.created_at desc, message.id desc;

alter view public.sd_chat_channel_last_message set (security_invoker = true);

-- Chat is a first-class notification producer. This expands only the producer
-- label allowlist; it does not change recipient ownership or inbox RLS.
alter table public.sd_notifications
  drop constraint if exists sd_notifications_source_check;
alter table public.sd_notifications
  add constraint sd_notifications_source_check
  check (source in ('payment_request', 'payment_webhook', 'announcement', 'chat', 'system'));

-- Preserve the Phase 9A producer exactly while admitting the narrowly scoped
-- chat source. Execution remains service-role-only.
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
    or p_source not in ('payment_request', 'payment_webhook', 'announcement', 'chat', 'system')
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

-- The sender is always auth.uid(). No actor, recipient, organization, status,
-- or notification fact is accepted from the client. The stable client UUID is
-- bound to the sender, organization, channel, and exact trimmed body.
create or replace function public.sd_send_chat_message(
  p_channel_id uuid,
  p_body text,
  p_client_message_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid := auth.uid();
  v_channel public.sd_chat_channels%rowtype;
  v_body text := pg_catalog.btrim(coalesce(p_body, ''));
  v_message public.sd_chat_messages%rowtype;
  v_reused boolean := false;
begin
  if v_actor_id is null then
    raise exception 'chat_authentication_required' using errcode = '28000';
  end if;
  if p_channel_id is null or p_client_message_id is null
    or pg_catalog.char_length(v_body) not between 1 and 4000 then
    raise exception 'invalid_chat_message' using errcode = '22023';
  end if;

  select channel.* into v_channel
  from public.sd_chat_channels channel
  where channel.id = p_channel_id
    and channel.is_archived = false;
  if v_channel.id is null or v_channel.org_id is null then
    raise exception 'chat_channel_not_found' using errcode = 'P0002';
  end if;
  if not public.sd_is_org_member(v_channel.org_id) then
    raise exception 'chat_organization_membership_required' using errcode = '42501';
  end if;
  if (
    v_channel.channel_type in ('dm', 'group')
    and not exists (
      select 1
      from public.sd_chat_memberships membership
      where membership.org_id = v_channel.org_id
        and membership.channel_id = v_channel.id
        and membership.user_id = v_actor_id
    )
  ) or (
    v_channel.channel_type = 'announcement'
    and not public.sd_is_org_staff(v_channel.org_id)
  ) then
    raise exception 'chat_participant_required' using errcode = '42501';
  end if;

  select message.* into v_message
  from public.sd_chat_messages message
  where message.org_id = v_channel.org_id
    and message.sender_id = v_actor_id
    and message.client_message_id = p_client_message_id;
  if v_message.id is not null then
    if v_message.channel_id is distinct from p_channel_id
      or v_message.body is distinct from v_body then
      raise exception 'chat_idempotency_conflict' using errcode = '23505';
    end if;
    v_reused := true;
  else
    insert into public.sd_chat_messages (
      org_id, channel_id, sender_id, body, client_message_id
    ) values (
      v_channel.org_id, p_channel_id, v_actor_id, v_body, p_client_message_id
    )
    on conflict (org_id, sender_id, client_message_id)
      where sender_id is not null and client_message_id is not null
    do nothing
    returning * into v_message;

    if v_message.id is null then
      select message.* into v_message
      from public.sd_chat_messages message
      where message.org_id = v_channel.org_id
        and message.sender_id = v_actor_id
        and message.client_message_id = p_client_message_id;
      if v_message.id is null
        or v_message.channel_id is distinct from p_channel_id
        or v_message.body is distinct from v_body then
        raise exception 'chat_idempotency_conflict' using errcode = '23505';
      end if;
      v_reused := true;
    end if;
  end if;

  return pg_catalog.jsonb_build_object(
    'message', pg_catalog.to_jsonb(v_message),
    'reused', v_reused
  );
end;
$$;

revoke all on function public.sd_send_chat_message(uuid, text, uuid)
from public, anon, authenticated, service_role;
grant execute on function public.sd_send_chat_message(uuid, text, uuid)
to authenticated;

-- Keep direct inserts available for older clients while closing the existing
-- inactive-membership gap. The remaining participant/staff rules are unchanged.
drop policy if exists "sd_chat_messages_insert" on public.sd_chat_messages;
create policy "sd_chat_messages_insert"
on public.sd_chat_messages
for insert
to authenticated
with check (
  sender_id = (select auth.uid())
  and public.sd_is_org_member(org_id)
  and exists (
    select 1
    from public.sd_chat_channels channel
    where channel.id = sd_chat_messages.channel_id
      and channel.org_id = sd_chat_messages.org_id
      and channel.is_archived = false
      and (
        (channel.channel_type in ('dm', 'group')
          and public.sd_chat_is_member(channel.id, (select auth.uid())))
        or (channel.channel_type = 'announcement'
          and public.sd_is_org_staff(channel.org_id))
      )
  )
);

-- One authoritative producer: successful persisted DM inserts. Recipient IDs
-- come only from chat memberships joined to active memberships in the same
-- organization. Per-recipient inbox uniqueness supplies the recipient portion
-- of the organization/conversation/message/recipient deduplication identity.
create or replace function public.sd_notify_direct_message_received()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_channel public.sd_chat_channels%rowtype;
  v_recipient_user_ids uuid[];
  v_sender_name text;
  v_preview text;
begin
  select channel.* into v_channel
  from public.sd_chat_channels channel
  where channel.id = new.channel_id
    and channel.org_id = new.org_id
    and channel.is_archived = false;
  if v_channel.id is null or v_channel.channel_type <> 'dm'
    or new.sender_id is null then
    return new;
  end if;

  select coalesce(
    pg_catalog.array_agg(recipient.user_id order by recipient.user_id),
    array[]::uuid[]
  )
  into v_recipient_user_ids
  from (
    select distinct membership.user_id
    from public.sd_chat_memberships membership
    join public.sd_org_memberships organization_membership
      on organization_membership.org_id = new.org_id
     and organization_membership.user_id = membership.user_id
     and organization_membership.status = 'active'
    where membership.org_id = new.org_id
      and membership.channel_id = new.channel_id
      and membership.user_id <> new.sender_id
  ) recipient;

  if pg_catalog.cardinality(v_recipient_user_ids) = 0 then
    raise log 'direct_message_notification_no_active_recipient message_id=% org_id=% channel_id=%',
      new.id, new.org_id, new.channel_id;
    return new;
  end if;

  select nullif(pg_catalog.btrim(profile.full_name), '')
  into v_sender_name
  from public.profiles profile
  where profile.id = new.sender_id;
  v_sender_name := coalesce(
    v_sender_name,
    'Player ' || pg_catalog.upper(pg_catalog.left(
      pg_catalog.replace(new.sender_id::text, '-', ''),
      6
    ))
  );
  v_preview := pg_catalog.left(
    pg_catalog.regexp_replace(pg_catalog.btrim(new.body), '[[:space:]]+', ' ', 'g'),
    180
  );

  begin
    perform public.sd_create_notifications(
      new.org_id,
      v_recipient_user_ids,
      'message_received',
      pg_catalog.left('New message from ' || v_sender_name, 120),
      case when nullif(v_preview, '') is null then 'Sent you a message.' else v_preview end,
      'chat_message',
      new.id::text,
      'chat_conversation',
      pg_catalog.jsonb_build_object(
        'organization_id', new.org_id,
        'conversation_id', new.channel_id,
        'message_id', new.id,
        'sender_id', new.sender_id
      ),
      'message_received:' || new.org_id::text || ':' || new.channel_id::text || ':' || new.id::text,
      new.sender_id,
      'chat',
      pg_catalog.jsonb_build_object(
        'producer', 'sd_chat_messages_after_insert',
        'conversation_type', 'dm'
      )
    );
  exception when others then
    raise warning 'direct_message_notification_production_failed message_id=% org_id=% channel_id=% sqlstate=%',
      new.id, new.org_id, new.channel_id, sqlstate;
  end;
  return new;
exception when others then
  raise warning 'direct_message_notification_production_failed message_id=% org_id=% channel_id=% sqlstate=%',
    new.id, new.org_id, new.channel_id, sqlstate;
  return new;
end;
$$;

revoke all on function public.sd_notify_direct_message_received()
from public, anon, authenticated, service_role;
drop trigger if exists trg_sd_notify_direct_message_received
on public.sd_chat_messages;
create trigger trg_sd_notify_direct_message_received
after insert on public.sd_chat_messages
for each row execute function public.sd_notify_direct_message_received();

-- Admit message_received to the existing durable APNs queue. Every other
-- Phase 9B condition, uniqueness rule, wakeup call, and worker behavior is
-- preserved verbatim.
create or replace function public.sd_queue_apns_deliveries()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_created_count integer := 0;
begin
  insert into public.sd_notification_deliveries (
    notification_id, device_id, channel, status, next_attempt_at
  )
  select notification.id, device.id, 'apns', 'pending', pg_catalog.now()
  from notification_rows notification
  join public.sd_push_devices device
    on device.user_id = notification.recipient_user_id
   and device.notifications_authorized
   and device.disabled_at is null
  where notification.category in (
    'payment_request_created', 'payment_received',
    'organization_announcement', 'message_received'
  )
  on conflict (notification_id, device_id, channel) do nothing;
  get diagnostics v_created_count = row_count;
  if v_created_count > 0 then
    perform public.sd_request_notification_delivery_worker();
  end if;
  return null;
end;
$$;

revoke all on function public.sd_queue_apns_deliveries()
from public, anon, authenticated, service_role;

-- A read cursor advances only to an authoritative message in the same
-- conversation. Related DM notifications at or before that boundary are
-- marked read; newer notifications and messages remain unread.
create or replace function public.sd_mark_chat_conversation_read(
  p_channel_id uuid,
  p_through_message_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid := auth.uid();
  v_channel public.sd_chat_channels%rowtype;
  v_boundary_at timestamptz;
  v_last_read_at timestamptz;
  v_last_read_message_id uuid;
  v_notifications_marked integer := 0;
begin
  if v_actor_id is null then
    raise exception 'chat_authentication_required' using errcode = '28000';
  end if;
  if p_channel_id is null or p_through_message_id is null then
    raise exception 'invalid_chat_read_boundary' using errcode = '22023';
  end if;

  select channel.* into v_channel
  from public.sd_chat_channels channel
  where channel.id = p_channel_id
    and channel.is_archived = false;
  if v_channel.id is null or v_channel.org_id is null then
    raise exception 'chat_channel_not_found' using errcode = 'P0002';
  end if;
  if not public.sd_is_org_member(v_channel.org_id) then
    raise exception 'chat_organization_membership_required' using errcode = '42501';
  end if;
  if v_channel.channel_type in ('dm', 'group') and not exists (
    select 1
    from public.sd_chat_memberships membership
    where membership.org_id = v_channel.org_id
      and membership.channel_id = p_channel_id
      and membership.user_id = v_actor_id
  ) then
    raise exception 'chat_participant_required' using errcode = '42501';
  end if;
  if v_channel.channel_type = 'announcement' and not (
    v_channel.audience = 'all'
    or (
      v_channel.audience = 'players'
      and exists (
        select 1
        from public.sd_org_memberships membership
        where membership.org_id = v_channel.org_id
          and membership.user_id = v_actor_id
          and membership.role = 'player'
          and membership.status = 'active'
      )
    )
  ) then
    raise exception 'chat_participant_required' using errcode = '42501';
  end if;

  select message.created_at into v_boundary_at
  from public.sd_chat_messages message
  where message.id = p_through_message_id
    and message.org_id = v_channel.org_id
    and message.channel_id = p_channel_id;
  if v_boundary_at is null then
    raise exception 'invalid_chat_read_boundary' using errcode = '22023';
  end if;

  insert into public.sd_chat_memberships (
    org_id, channel_id, user_id, member_role, last_read_at,
    last_read_message_id
  ) values (
    v_channel.org_id, p_channel_id, v_actor_id, 'member', v_boundary_at,
    p_through_message_id
  )
  on conflict (channel_id, user_id) do update
  set last_read_at = greatest(
    coalesce(public.sd_chat_memberships.last_read_at, '-infinity'::timestamptz),
    excluded.last_read_at
  ),
  last_read_message_id = case
    when public.sd_chat_memberships.last_read_at is null
      or excluded.last_read_at > public.sd_chat_memberships.last_read_at
      then excluded.last_read_message_id
    when excluded.last_read_at = public.sd_chat_memberships.last_read_at
      and (
        public.sd_chat_memberships.last_read_message_id is null
        or excluded.last_read_message_id > public.sd_chat_memberships.last_read_message_id
      )
      then excluded.last_read_message_id
    else public.sd_chat_memberships.last_read_message_id
  end
  returning last_read_at, last_read_message_id
  into v_last_read_at, v_last_read_message_id;

  update public.sd_notifications notification
  set read_at = pg_catalog.now()
  from public.sd_chat_messages message
  where notification.org_id = v_channel.org_id
    and notification.recipient_user_id = v_actor_id
    and notification.category = 'message_received'
    and notification.action_route = 'chat_conversation'
    and notification.related_entity_type = 'chat_message'
    and notification.related_entity_id = message.id::text
    and notification.read_at is null
    and notification.archived_at is null
    and message.org_id = v_channel.org_id
    and message.channel_id = p_channel_id
    and (
      message.created_at < v_boundary_at
      or (
        message.created_at = v_boundary_at
        and message.id <= p_through_message_id
      )
    );
  get diagnostics v_notifications_marked = row_count;

  return pg_catalog.jsonb_build_object(
    'organization_id', v_channel.org_id,
    'conversation_id', p_channel_id,
    'through_message_id', p_through_message_id,
    'last_read_at', v_last_read_at,
    'last_read_message_id', v_last_read_message_id,
    'notifications_marked_read', v_notifications_marked
  );
end;
$$;

revoke all on function public.sd_mark_chat_conversation_read(uuid, uuid)
from public, anon, authenticated, service_role;
grant execute on function public.sd_mark_chat_conversation_read(uuid, uuid)
to authenticated;
