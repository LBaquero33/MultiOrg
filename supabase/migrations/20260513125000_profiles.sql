-- Minimal profile table for the iOS app (Supabase Auth-based).
-- Stores role + display name.

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  role text not null default 'player',
  full_name text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.profiles enable row level security;

-- Users can read their own profile.
drop policy if exists "profiles_select_own" on public.profiles;
create policy "profiles_select_own"
on public.profiles
for select
using (auth.uid() = id);

-- Users can insert their own profile (on sign-up).
drop policy if exists "profiles_insert_own" on public.profiles;
create policy "profiles_insert_own"
on public.profiles
for insert
with check (auth.uid() = id);

-- Users can update their own profile (name only; role updates should be admin-only later).
drop policy if exists "profiles_update_own" on public.profiles;
create policy "profiles_update_own"
on public.profiles
for update
using (auth.uid() = id)
with check (auth.uid() = id);

-- Prevent role changes unless service_role.
create or replace function public.prevent_profile_role_change()
returns trigger
language plpgsql
as $$
begin
  if (new.role is distinct from old.role) then
    -- Only allow server-side/admin updates.
    if auth.role() <> 'service_role' then
      raise exception 'role_change_not_allowed';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_profiles_prevent_role_change on public.profiles;
create trigger trg_profiles_prevent_role_change
before update on public.profiles
for each row
execute function public.prevent_profile_role_change();

create or replace function public.set_profiles_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists trg_profiles_updated_at on public.profiles;
create trigger trg_profiles_updated_at
before update on public.profiles
for each row
execute function public.set_profiles_updated_at();
