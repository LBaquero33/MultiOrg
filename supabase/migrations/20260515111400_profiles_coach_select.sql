-- Allow coaches to view all profiles (read-only).
-- Coaches are determined by their own `public.profiles.role = 'coach'`.

drop policy if exists "profiles_select_coach_all" on public.profiles;
create policy "profiles_select_coach_all"
on public.profiles
for select
using (
  exists (
    select 1
    from public.profiles me
    where me.id = auth.uid()
      and me.role = 'coach'
  )
);

