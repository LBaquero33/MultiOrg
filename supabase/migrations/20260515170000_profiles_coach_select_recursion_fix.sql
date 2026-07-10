-- Fix: infinite recursion in RLS policy on `public.profiles`.
-- The previous policy referenced `public.profiles` inside a policy for `public.profiles`,
-- which triggers "infinite recursion detected in policy for relation \"profiles\"".

-- Helper: determine if a user is a coach, evaluated as a SECURITY DEFINER function.
-- This avoids self-referencing `public.profiles` within the policy expression itself.
create or replace function public.is_coach(_uid uuid)
returns boolean
language sql
stable
security definer
set search_path = public, auth
as $$
  select exists (
    select 1
    from public.profiles p
    where p.id = _uid
      and p.role = 'coach'
  );
$$;

revoke all on function public.is_coach(uuid) from public;
grant execute on function public.is_coach(uuid) to anon, authenticated;

-- Replace the recursive policy with a non-recursive one.
drop policy if exists "profiles_select_coach_all" on public.profiles;
create policy "profiles_select_coach_all"
on public.profiles
for select
using (public.is_coach(auth.uid()));

