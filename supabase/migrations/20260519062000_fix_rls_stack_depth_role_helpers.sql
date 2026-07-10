-- Fix "stack depth limit exceeded" caused by RLS recursion.
--
-- Root cause: RLS policies call helper functions (e.g., sd_is_coach / sd_is_player)
-- which SELECT from `public.profiles`. Those SELECTs are themselves subject to RLS,
-- and (with other policies that touch linked tables) can recurse until Postgres
-- hits max_stack_depth.
--
-- Fix: make role/link helper functions SECURITY DEFINER so they evaluate without
-- depending on caller RLS, similar to the earlier `public.is_coach()` recursion fix.

create or replace function public.sd_is_coach(uid uuid)
returns boolean
language sql
stable
security definer
set search_path = public, auth
as $$
  select exists (
    select 1
    from public.profiles p
    where p.id = uid
      and p.role = 'coach'
  );
$$;

revoke all on function public.sd_is_coach(uuid) from public;
grant execute on function public.sd_is_coach(uuid) to anon, authenticated;

create or replace function public.sd_is_parent(uid uuid)
returns boolean
language sql
stable
security definer
set search_path = public, auth
as $$
  select exists (
    select 1
    from public.profiles p
    where p.id = uid
      and p.role = 'parent'
  );
$$;

revoke all on function public.sd_is_parent(uuid) from public;
grant execute on function public.sd_is_parent(uuid) to anon, authenticated;

create or replace function public.sd_is_player(uid uuid)
returns boolean
language sql
stable
security definer
set search_path = public, auth
as $$
  select exists (
    select 1
    from public.profiles p
    where p.id = uid
      and p.role = 'player'
  );
$$;

revoke all on function public.sd_is_player(uuid) from public;
grant execute on function public.sd_is_player(uuid) to anon, authenticated;

create or replace function public.sd_is_linked_parent(parent_uid uuid, child_uid uuid)
returns boolean
language sql
stable
security definer
set search_path = public, auth
as $$
  select exists (
    select 1
    from public.sd_parent_child_links l
    where l.parent_id = parent_uid
      and l.child_id = child_uid
  );
$$;

revoke all on function public.sd_is_linked_parent(uuid, uuid) from public;
grant execute on function public.sd_is_linked_parent(uuid, uuid) to anon, authenticated;

