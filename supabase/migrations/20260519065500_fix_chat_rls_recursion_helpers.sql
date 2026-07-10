-- Fix: stack depth limit exceeded in chat due to RLS recursion.
--
-- Root cause:
-- - RLS policies on `sd_chat_memberships` call `sd_chat_is_member()`
-- - `sd_chat_is_member()` SELECTs from `sd_chat_memberships`
-- This causes infinite recursion until Postgres throws "stack depth limit exceeded".
--
-- Fix:
-- Make membership/admin helper functions SECURITY DEFINER so they can query
-- chat tables without being subject to the caller's RLS evaluation.

create or replace function public.sd_chat_is_member(ch_id uuid, uid uuid)
returns boolean
language sql
stable
security definer
set search_path = public, auth
as $$
  select exists (
    select 1
    from public.sd_chat_memberships m
    where m.channel_id = ch_id
      and m.user_id = uid
  );
$$;

revoke all on function public.sd_chat_is_member(uuid, uuid) from public;
grant execute on function public.sd_chat_is_member(uuid, uuid) to anon, authenticated;

create or replace function public.sd_chat_is_admin(ch_id uuid, uid uuid)
returns boolean
language sql
stable
security definer
set search_path = public, auth
as $$
  select exists (
    select 1
    from public.sd_chat_channels c
    where c.id = ch_id
      and c.created_by = uid
  )
  or exists (
    select 1
    from public.sd_chat_memberships m
    where m.channel_id = ch_id
      and m.user_id = uid
      and m.member_role = 'admin'
  );
$$;

revoke all on function public.sd_chat_is_admin(uuid, uuid) from public;
grant execute on function public.sd_chat_is_admin(uuid, uuid) to anon, authenticated;

