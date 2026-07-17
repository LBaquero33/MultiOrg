export const PLAYER_DEVELOPMENT_COPILOT_FEATURE_KEY =
  "player_development_copilot";

export const PLAYER_DEVELOPMENT_COPILOT_DESCRIPTION =
  "Enables AI-assisted coach and player Copilot experiences across Home Plate.";

const UUID =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export type PlatformFeatureFlagMutation = {
  key: typeof PLAYER_DEVELOPMENT_COPILOT_FEATURE_KEY;
  enabled: boolean;
  requestId: string;
};

export function platformFeatureFlagMutation(
  body: Record<string, unknown>,
  isPlatformAdmin: boolean,
): PlatformFeatureFlagMutation | null {
  if (!isPlatformAdmin) return null;
  const key = String(body.key ?? "").trim().toLowerCase();
  const requestId = String(body.request_id ?? "").trim().toLowerCase();
  if (
    key !== PLAYER_DEVELOPMENT_COPILOT_FEATURE_KEY ||
    typeof body.enabled !== "boolean" ||
    !UUID.test(requestId)
  ) return null;
  return { key, enabled: body.enabled, requestId };
}

export function platformFeatureEnabled(
  row: { enabled?: unknown } | null | undefined,
): boolean {
  return row?.enabled === true;
}
