-- Team-scoped coach mutations. Coaches can browse organization data, while
-- owner/admin accounts retain global authority. Organizations may turn the
-- restriction off in Settings → Features → Team permissions.

create or replace function public.sd_can_manage_team_player(target_org uuid, target_player uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = public, auth
as $$
declare
  actor_role text;
  restrict_actions boolean := true;
  actor_team uuid;
  player_team uuid;
begin
  select role into actor_role
  from public.sd_org_memberships
  where org_id = target_org
    and user_id = auth.uid()
    and status = 'active'
  limit 1;

  if actor_role = 'owner' then
    return true;
  end if;
  if actor_role <> 'coach' then
    return false;
  end if;

  select coalesce((team_policy ->> 'restrictCoachActionsToTeam')::boolean, true)
  into restrict_actions
  from public.sd_org_settings
  where org_id = target_org;

  if coalesce(restrict_actions, true) = false then
    return true;
  end if;

  select team_id into actor_team
  from public.sd_team_members
  where org_id = target_org and player_id = auth.uid()
  limit 1;

  select team_id into player_team
  from public.sd_team_members
  where org_id = target_org and player_id = target_player
  limit 1;

  return actor_team is not null and actor_team = player_team;
end;
$$;

revoke all on function public.sd_can_manage_team_player(uuid, uuid) from public;
grant execute on function public.sd_can_manage_team_player(uuid, uuid) to authenticated;

drop policy if exists "sd_assignments_insert" on public.sd_program_assignments;
create policy "sd_assignments_insert"
on public.sd_program_assignments
for insert
to authenticated
with check (
  coach_id = auth.uid()
  and public.sd_can_manage_team_player(org_id, player_id)
);

drop policy if exists "sd_assignments_update" on public.sd_program_assignments;
create policy "sd_assignments_update"
on public.sd_program_assignments
for update
to authenticated
using (
  coach_id = auth.uid()
  and public.sd_can_manage_team_player(org_id, player_id)
)
with check (
  coach_id = auth.uid()
  and public.sd_can_manage_team_player(org_id, player_id)
);

drop policy if exists "sd_testing_write_coach" on public.sd_testing_entries;
create policy "sd_testing_write_coach"
on public.sd_testing_entries
for all
to authenticated
using (public.sd_can_manage_team_player(org_id, player_id))
with check (public.sd_can_manage_team_player(org_id, player_id));
