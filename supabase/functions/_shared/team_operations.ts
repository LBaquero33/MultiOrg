export const teamResponsibilities = [
  "head_coach",
  "assistant_coach",
  "hitting_coach",
  "pitching_coach",
  "catching_coach",
  "strength_coach",
  "team_manager",
  "evaluator",
  "read_only",
] as const;

export type TeamResponsibility = (typeof teamResponsibilities)[number];

export const teamCapabilities = [
  "view_team",
  "manage_roster",
  "manage_schedule",
  "manage_attendance",
  "manage_practice",
  "manage_game",
  "message_team",
  "view_development",
  "edit_development",
  "manage_staff",
  "view_documents",
  "manage_documents",
] as const;

export type TeamCapability = (typeof teamCapabilities)[number];

export function cleanResponsibilities(
  value: unknown,
): TeamResponsibility[] | null {
  if (!Array.isArray(value)) return null;
  const valid = new Set<string>(teamResponsibilities);
  const cleaned = Array.from(
    new Set(value.map((item) => String(item).trim().toLowerCase())),
  );
  return cleaned.length > 0 && cleaned.every((item) => valid.has(item))
    ? cleaned as TeamResponsibility[]
    : null;
}

export type SelectableTeam = {
  id: string;
  organization_id: string;
  season_id: string;
  is_primary?: boolean;
};

export function resolveSelectedTeam(
  teams: readonly SelectableTeam[],
  organizationId: string,
  seasonId: string,
  persistedTeamId: string | null,
): string | null {
  const authorized = teams.filter((team) =>
    team.organization_id === organizationId && team.season_id === seasonId
  );
  if (
    persistedTeamId && authorized.some((team) => team.id === persistedTeamId)
  ) {
    return persistedTeamId;
  }
  return authorized.find((team) => team.is_primary)?.id ?? authorized[0]?.id ??
    null;
}
