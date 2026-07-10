-- Phase 0: harden identity layer
-- - Ensure `public.profiles` row exists for every `auth.users` row
-- - Provide a simple debug RPC to confirm the caller's profile/role without guesswork

-- Create profile row for new auth users (never rely on the client).
create or replace function public.create_profile_for_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_full_name text;
begin
  begin
    v_full_name := nullif(trim(coalesce(new.raw_user_meta_data->>'full_name', '')), '');
  exception when others then
    v_full_name := null;
  end;

  insert into public.profiles (id, full_name)
  values (new.id, v_full_name)
  on conflict (id) do nothing;

  return new;
end;
$$;

revoke all on function public.create_profile_for_new_auth_user() from public;

drop trigger if exists trg_create_profile_for_new_auth_user on auth.users;
create trigger trg_create_profile_for_new_auth_user
after insert on auth.users
for each row
execute function public.create_profile_for_new_auth_user();

-- Debug helper: confirm caller's profile (id/role/name).
create or replace function public.debug_my_profile()
returns table (
  id uuid,
  role text,
  full_name text
)
language sql
stable
security definer
set search_path = public, auth
as $$
  select p.id, p.role, p.full_name
  from public.profiles p
  where p.id = auth.uid();
$$;

revoke all on function public.debug_my_profile() from public;
grant execute on function public.debug_my_profile() to anon, authenticated;

