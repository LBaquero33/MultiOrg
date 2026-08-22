-- Group channels must not inherit the communication schema direct default.
create or replace function public.sd_create_group_chat(
  p_org_id uuid,
  p_title text,
  p_member_ids uuid[]
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid := auth.uid();
  v_channel_id uuid;
  v_member_ids uuid[];
  v_title text;
begin
  if v_actor_id is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if not exists (
    select 1 from public.sd_org_memberships membership
    where membership.org_id = p_org_id
      and membership.user_id = v_actor_id
      and membership.status = 'active'
  ) then
    raise exception 'not_authorized' using errcode = '42501';
  end if;

  select coalesce(pg_catalog.array_agg(candidate.user_id order by candidate.user_id), '{}'::uuid[])
  into v_member_ids
  from (
    select distinct requested.user_id
    from pg_catalog.unnest(coalesce(p_member_ids, '{}'::uuid[])) as requested(user_id)
    where requested.user_id is not null and requested.user_id <> v_actor_id
  ) candidate;

  if pg_catalog.cardinality(v_member_ids) < 2 then
    raise exception 'group_requires_two_other_members' using errcode = '22023';
  end if;
  if pg_catalog.cardinality(v_member_ids) > 100 then
    raise exception 'group_member_limit_exceeded' using errcode = '22023';
  end if;
  if exists (
    select 1 from pg_catalog.unnest(v_member_ids) as requested(user_id)
    where not exists (
      select 1 from public.sd_org_memberships membership
      where membership.org_id = p_org_id
        and membership.user_id = requested.user_id
        and membership.status = 'active'
    )
  ) then
    raise exception 'group_member_not_in_org' using errcode = '42501';
  end if;

  v_title := nullif(pg_catalog.btrim(coalesce(p_title, '')), '');
  if v_title is not null and pg_catalog.char_length(v_title) > 120 then
    raise exception 'group_title_too_long' using errcode = '22023';
  end if;

  insert into public.sd_chat_channels(
    org_id, channel_type, conversation_kind, minor_visibility, title, created_by
  ) values (
    p_org_id, 'group', 'group', 'standard',
    coalesce(v_title, 'Group conversation'), v_actor_id
  ) returning id into v_channel_id;

  insert into public.sd_chat_memberships(org_id, channel_id, user_id, member_role, last_read_at)
  values (p_org_id, v_channel_id, v_actor_id, 'admin', pg_catalog.now());
  insert into public.sd_chat_memberships(org_id, channel_id, user_id, member_role)
  select p_org_id, v_channel_id, requested.user_id, 'member'
  from pg_catalog.unnest(v_member_ids) as requested(user_id);
  return v_channel_id;
end;
$$;

revoke all on function public.sd_create_group_chat(uuid, text, uuid[]) from public, anon, authenticated;
grant execute on function public.sd_create_group_chat(uuid, text, uuid[]) to authenticated;
