-- Allow active team-scoped coaches with the resolved manage_roster capability
-- to move players for their assigned team. The Edge Function remains the only
-- authenticated caller; these RPCs continue to be service-role only.

create or replace function public.sd_actor_can_manage_team_roster(
  p_actor_id uuid,
  p_organization_id uuid,
  p_team_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.sd_org_memberships membership
    where membership.org_id = p_organization_id
      and membership.user_id = p_actor_id
      and membership.status = 'active'
      and (
        membership.role in ('owner', 'admin')
        or (
          p_team_id is not null
          and 'manage_roster' = any(
            public.sd_resolve_team_capabilities(
              p_organization_id,
              p_team_id,
              p_actor_id
            )
          )
        )
      )
  );
$$;

revoke all on function public.sd_actor_can_manage_team_roster(uuid, uuid, uuid)
from public, anon, authenticated;
grant execute on function public.sd_actor_can_manage_team_roster(uuid, uuid, uuid)
to service_role;

create or replace function public.sd_assign_player_team(
  p_actor_id uuid,
  p_organization_id uuid,
  p_player_id uuid,
  p_team_id uuid,
  p_assignment_reason text,
  p_transfer_metadata jsonb,
  p_request_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_season_id uuid;
  v_membership public.sd_player_team_memberships%rowtype;
begin
  select season_id into v_season_id
  from public.sd_teams
  where id = p_team_id and org_id = p_organization_id and is_active
  for update;
  if v_season_id is null then
    raise exception 'team_or_season_not_found' using errcode = '23503';
  end if;

  if not public.sd_actor_can_manage_team_roster(
    p_actor_id,
    p_organization_id,
    p_team_id
  ) then
    raise exception 'team_roster_management_required' using errcode = '42501';
  end if;

  if not exists (
    select 1 from public.sd_org_memberships
    where org_id = p_organization_id and user_id = p_player_id
      and role = 'player' and status = 'active'
  ) then
    raise exception 'player_not_in_organization' using errcode = '23503';
  end if;

  if p_request_id is not null and exists (
    select 1 from public.sd_team_operations_audit_logs
    where organization_id = p_organization_id and request_id = p_request_id
      and action = 'assign_player_team'
  ) then
    select * into v_membership from public.sd_player_team_memberships
    where organization_id = p_organization_id and player_id = p_player_id
      and active and ended_at is null limit 1;
    return pg_catalog.to_jsonb(v_membership);
  end if;

  update public.sd_player_team_memberships
  set active = false, ended_at = now(), updated_by = p_actor_id
  where organization_id = p_organization_id and player_id = p_player_id
    and active and ended_at is null;

  insert into public.sd_player_team_memberships (
    player_id, organization_id, season_id, team_id, assignment_reason,
    transfer_metadata, created_by, updated_by
  ) values (
    p_player_id, p_organization_id, v_season_id, p_team_id,
    nullif(btrim(p_assignment_reason), ''), coalesce(p_transfer_metadata, '{}'::jsonb),
    p_actor_id, p_actor_id
  ) returning * into v_membership;

  insert into public.sd_team_members (org_id, team_id, player_id, assigned_by, assigned_at)
  values (p_organization_id, p_team_id, p_player_id, p_actor_id, now())
  on conflict (org_id, player_id) do update
  set team_id = excluded.team_id, assigned_by = excluded.assigned_by,
      assigned_at = excluded.assigned_at;

  insert into public.sd_team_operations_audit_logs (
    organization_id, actor_id, action, target_type, target_id, request_id, details
  ) values (
    p_organization_id, p_actor_id, 'assign_player_team',
    'player_team_membership', v_membership.id, p_request_id,
    pg_catalog.jsonb_build_object('player_id', p_player_id, 'team_id', p_team_id)
  );
  return pg_catalog.to_jsonb(v_membership);
end;
$$;

revoke all on function public.sd_assign_player_team(uuid, uuid, uuid, uuid, text, jsonb, uuid)
from public, anon, authenticated;
grant execute on function public.sd_assign_player_team(uuid, uuid, uuid, uuid, text, jsonb, uuid)
to service_role;

create or replace function public.sd_unassign_player_team(
  p_actor_id uuid,
  p_organization_id uuid,
  p_player_id uuid,
  p_assignment_reason text,
  p_request_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_membership public.sd_player_team_memberships%rowtype;
  v_authorization_team_id uuid;
begin
  select * into v_membership
  from public.sd_player_team_memberships
  where organization_id = p_organization_id and player_id = p_player_id
    and active and ended_at is null
  for update;

  v_authorization_team_id := v_membership.team_id;
  if v_authorization_team_id is null and p_request_id is not null then
    select nullif(details->>'previous_team_id', '')::uuid
    into v_authorization_team_id
    from public.sd_team_operations_audit_logs
    where organization_id = p_organization_id
      and request_id = p_request_id
      and action = 'unassign_player_team'
    limit 1;
  end if;

  if not public.sd_actor_can_manage_team_roster(
    p_actor_id,
    p_organization_id,
    v_authorization_team_id
  ) then
    raise exception 'team_roster_management_required' using errcode = '42501';
  end if;

  if p_request_id is not null and exists (
    select 1 from public.sd_team_operations_audit_logs
    where organization_id = p_organization_id and request_id = p_request_id
      and action = 'unassign_player_team'
  ) then
    return pg_catalog.jsonb_build_object('unassigned', true, 'replayed', true);
  end if;

  if v_membership.id is not null then
    update public.sd_player_team_memberships
    set active = false, ended_at = now(), updated_by = p_actor_id,
        assignment_reason = coalesce(nullif(btrim(p_assignment_reason), ''), assignment_reason)
    where id = v_membership.id;
  end if;

  delete from public.sd_team_members
  where org_id = p_organization_id and player_id = p_player_id;

  insert into public.sd_team_operations_audit_logs (
    organization_id, actor_id, action, target_type, target_id, request_id, details
  ) values (
    p_organization_id, p_actor_id, 'unassign_player_team',
    'player_team_membership', v_membership.id, p_request_id,
    pg_catalog.jsonb_build_object(
      'player_id', p_player_id,
      'previous_team_id', v_membership.team_id
    )
  );

  return pg_catalog.jsonb_build_object(
    'unassigned', true,
    'replayed', false,
    'previous_team_id', v_membership.team_id
  );
end;
$$;

revoke all on function public.sd_unassign_player_team(uuid, uuid, uuid, text, uuid)
from public, anon, authenticated;
grant execute on function public.sd_unassign_player_team(uuid, uuid, uuid, text, uuid)
to service_role;
