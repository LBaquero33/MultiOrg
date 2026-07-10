-- Lock down `public.profiles.role` so clients cannot self-escalate to coach.
-- Only `service_role` may change role.

create or replace function public.prevent_profile_role_change()
returns trigger
language plpgsql
as $$
begin
  if (new.role is distinct from old.role) then
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

