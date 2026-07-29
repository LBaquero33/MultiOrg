-- Keep the centralized notification validator aligned with the game/calendar
-- categories already accepted by the notifications table.

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
      'message_received', 'testing_result_added', 'organization_announcement',
      'event_created', 'event_updated', 'event_canceled', 'event_postponed',
      'event_rescheduled', 'availability_requested', 'game_starting',
      'game_live', 'game_final', 'game_update', 'system'
    )
    or pg_catalog.char_length(pg_catalog.btrim(p_title)) not between 1 and 120
    or pg_catalog.char_length(pg_catalog.btrim(p_body)) not between 1 and 2000
    or pg_catalog.char_length(pg_catalog.btrim(p_deduplication_key)) not between 1 and 255
    or p_source not in (
      'payment_request', 'payment_webhook', 'announcement', 'chat', 'event', 'system'
    )
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
) from public, anon;

grant execute on function public.sd_create_notifications(
  uuid, uuid[], text, text, text, text, text, text, jsonb, text, uuid, text, jsonb
) to authenticated, service_role;
