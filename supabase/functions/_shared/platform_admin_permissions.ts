export const PLATFORM_ORGANIZATION_ROLES = [
  "owner",
  "admin",
  "coach",
  "player",
  "parent",
] as const;

export const PLATFORM_MEMBERSHIP_STATUSES = [
  "active",
  "invited",
  "disabled",
  "suspended",
] as const;

export type PlatformOrganizationRole =
  (typeof PLATFORM_ORGANIZATION_ROLES)[number];
export type PlatformMembershipStatus =
  (typeof PLATFORM_MEMBERSHIP_STATUSES)[number];

export type PlatformMembershipMutation = {
  role: PlatformOrganizationRole;
  status: PlatformMembershipStatus;
  requestId: string;
  reason: string | null;
};

// Temporary phase-one gate. The durable authorization remains the explicit
// sd_platform_admins entitlement; replacing this predicate later does not
// change any organization authorization or platform UI contracts.
export const TEMPORARY_PLATFORM_OPERATOR_EMAIL = "lbaq27@gmail.com";

export function canAccessPlatformAdministration(
  email: unknown,
  hasEntitlement: boolean,
): boolean {
  return hasEntitlement &&
    String(email ?? "").trim().toLowerCase() ===
      TEMPORARY_PLATFORM_OPERATOR_EMAIL;
}

const UUID =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export function cleanPlatformRole(
  value: unknown,
): PlatformOrganizationRole | null {
  const role = String(value ?? "").trim().toLowerCase();
  return PLATFORM_ORGANIZATION_ROLES.includes(
      role as PlatformOrganizationRole,
    )
    ? role as PlatformOrganizationRole
    : null;
}

export function cleanPlatformMembershipStatus(
  value: unknown,
): PlatformMembershipStatus | null {
  const status = String(value ?? "").trim().toLowerCase();
  return PLATFORM_MEMBERSHIP_STATUSES.includes(
      status as PlatformMembershipStatus,
    )
    ? status as PlatformMembershipStatus
    : null;
}

export function platformMembershipMutation(
  body: Record<string, unknown>,
): PlatformMembershipMutation | null {
  const role = cleanPlatformRole(body.role);
  const status = cleanPlatformMembershipStatus(body.status);
  const requestId = String(body.request_id ?? "").trim().toLowerCase();
  const reasonValue = String(body.reason ?? "").trim();
  if (!role || !status || !UUID.test(requestId) || reasonValue.length > 500) {
    return null;
  }
  return {
    role,
    status,
    requestId,
    reason: reasonValue || null,
  };
}

export function platformMemberMatches(
  member: {
    role: string;
    status: string;
    full_name?: string | null;
    username?: string | null;
    email?: string | null;
  },
  query: string,
  filter: string,
): boolean {
  const normalizedFilter = filter.trim().toLowerCase();
  const role = member.role.trim().toLowerCase();
  const status = member.status.trim().toLowerCase();
  if (
    normalizedFilter && normalizedFilter !== "all" &&
    (normalizedFilter === "inactive"
      ? status === "active"
      : role !== normalizedFilter)
  ) return false;
  const needle = query.trim().toLowerCase();
  if (!needle) return true;
  return [member.full_name, member.username, member.email]
    .some((value) => String(value ?? "").toLowerCase().includes(needle));
}
