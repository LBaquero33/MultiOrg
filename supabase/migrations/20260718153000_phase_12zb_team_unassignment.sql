-- Phase 12ZB: audited roster-board move to Unassigned.
-- This closes only the current team membership. It preserves the historical
-- membership row and all attendance, availability, payment, messaging,
-- development, practice, and game records.

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
begin
  if not exists (
    select 1 from public.sd_org_memberships
    where org_id = p_organization_id and user_id = p_actor_id
      and role in ('owner', 'admin') and status = 'active'
  ) then
    raise exception 'org_admin_required' using errcode = '42501';
  end if;

  if p_request_id is not null and exists (
    select 1 from public.sd_team_operations_audit_logs
    where organization_id = p_organization_id and request_id = p_request_id
      and action = 'unassign_player_team'
  ) then
    return pg_catalog.jsonb_build_object('unassigned', true, 'replayed', true);
  end if;

  select * into v_membership
  from public.sd_player_team_memberships
  where organization_id = p_organization_id and player_id = p_player_id
    and active and ended_at is null
  for update;

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
