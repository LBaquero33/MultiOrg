-- Predeployment lint repairs for legacy functions surfaced by the game
-- validation pass. These changes preserve behavior and remove one retired RPC.

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

  return jsonb_build_object(
    'channel_id', p_channel_id,
    'through_message_id', v_last_read_message_id,
    'last_read_at', v_last_read_at,
    'notifications_marked_read', v_notifications_marked
  );
end;
$$;

revoke all on function public.sd_mark_chat_conversation_read(uuid, uuid)
from public, anon, authenticated, service_role;
grant execute on function public.sd_mark_chat_conversation_read(uuid, uuid)
to authenticated;

-- Phase 11 superseded this RPC with the audience-scoped variant and revoked
-- every caller. Dropping it removes an invalid stale ON CONFLICT target.
drop function if exists public.sd_upsert_development_alerts(uuid, uuid, jsonb);
