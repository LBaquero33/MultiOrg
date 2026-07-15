export type OrganizationMembership = {
  role?: string | null;
  status?: string | null;
};

function normalized(value: string | null | undefined): string {
  return String(value ?? "").trim().toLowerCase();
}

export function canAdministerOrganization(
  membership: OrganizationMembership | null | undefined,
): boolean {
  if (normalized(membership?.status) !== "active") return false;
  const role = normalized(membership?.role);
  return role === "owner" || role === "admin";
}

export function canOperateOrganization(
  membership: OrganizationMembership | null | undefined,
): boolean {
  if (normalized(membership?.status) !== "active") return false;
  const role = normalized(membership?.role);
  return role === "owner" || role === "admin" || role === "coach";
}
