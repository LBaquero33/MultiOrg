export const ORG_ADMIN_ACTIONS = [
  "team_context",
  "create_season",
  "update_season",
  "assign_team_season",
  "assign_player_team",
  "unassign_player_team",
  "assign_coach_team",
  "get_player_access",
  "set_player_access",
  "list_members",
  "create_user",
  "update_member",
  "set_username",
  "list_teams",
  "create_team",
  "update_team",
  "assign_team_member",
  "remove_team_member",
] as const;

export type OrgAdminAction = typeof ORG_ADMIN_ACTIONS[number];

const orgAdminActionSet = new Set<string>(ORG_ADMIN_ACTIONS);

export function isOrgAdminAction(value: string): value is OrgAdminAction {
  return orgAdminActionSet.has(value);
}
