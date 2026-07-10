-- Allow all authenticated users to discover coach accounts (only) for chat.
-- This enables players/parents to start a DM with a coach without exposing the full user directory.

alter table public.profiles enable row level security;

drop policy if exists "profiles_select_coaches_public" on public.profiles;
create policy "profiles_select_coaches_public"
on public.profiles
for select
to authenticated
using (role = 'coach');

