export const SETUP_STEPS = [
  "basics",
  "season",
  "teams",
  "staff",
  "players_families",
  "registration_fees",
  "facilities",
  "communication",
  "first_baseball_action",
  "review_launch",
] as const;

export type SetupStep = typeof SETUP_STEPS[number];

export const OPTIONAL_SETUP_STEPS = new Set<SetupStep>([
  "staff",
  "players_families",
  "registration_fees",
  "facilities",
  "communication",
  "first_baseball_action",
]);

export type SetupReadinessCounts = {
  organization_active: boolean;
  basics_complete: boolean;
  active_or_default_season_count: number;
  team_in_season_count: number;
  staff_assignment_count: number;
  player_assignment_count: number;
  registration_offering_count: number;
  facility_count: number;
  communication_policy_configured: boolean;
  first_event_count: number;
};

export type SetupReadinessItem = {
  key: string;
  label: string;
  required: boolean;
  complete: boolean;
  route_step: SetupStep;
};

export function isSetupStep(value: unknown): value is SetupStep {
  return typeof value === "string" &&
    (SETUP_STEPS as readonly string[]).includes(value);
}

export function setupReadiness(counts: SetupReadinessCounts) {
  const items: SetupReadinessItem[] = [
    {
      key: "organization",
      label: "Active organization",
      required: true,
      complete: counts.organization_active,
      route_step: "basics",
    },
    {
      key: "basics",
      label: "Organization name and timezone",
      required: true,
      complete: counts.basics_complete,
      route_step: "basics",
    },
    {
      key: "season",
      label: "Active or default season",
      required: true,
      complete: counts.active_or_default_season_count > 0,
      route_step: "season",
    },
    {
      key: "team",
      label: "Active team assigned to a season",
      required: true,
      complete: counts.team_in_season_count > 0,
      route_step: "teams",
    },
    {
      key: "staff",
      label: "Staff assignment",
      required: false,
      complete: counts.staff_assignment_count > 0,
      route_step: "staff",
    },
    {
      key: "players",
      label: "Player and family roster",
      required: false,
      complete: counts.player_assignment_count > 0,
      route_step: "players_families",
    },
    {
      key: "registration",
      label: "Registration and fees",
      required: false,
      complete: counts.registration_offering_count > 0,
      route_step: "registration_fees",
    },
    {
      key: "facilities",
      label: "Facility resources",
      required: false,
      complete: counts.facility_count > 0,
      route_step: "facilities",
    },
    {
      key: "communication",
      label: "Communication policy",
      required: false,
      complete: counts.communication_policy_configured,
      route_step: "communication",
    },
    {
      key: "first_event",
      label: "First baseball action",
      required: false,
      complete: counts.first_event_count > 0,
      route_step: "first_baseball_action",
    },
  ];
  return {
    ready: items.filter((item) => item.required).every((item) => item.complete),
    items,
  };
}

export function nextSetupStep(current: SetupStep): SetupStep {
  const index = SETUP_STEPS.indexOf(current);
  return SETUP_STEPS[Math.min(index + 1, SETUP_STEPS.length - 1)];
}

export function previousSetupStep(current: SetupStep): SetupStep {
  const index = SETUP_STEPS.indexOf(current);
  return SETUP_STEPS[Math.max(index - 1, 0)];
}

export function canSkipSetupStep(step: SetupStep) {
  return OPTIONAL_SETUP_STEPS.has(step);
}

export function cleanSetupString(value: unknown, maxLength = 200) {
  return String(value ?? "").trim().slice(0, maxLength);
}

export const MARIST_SETUP_TEST_ORGANIZATION_ID =
  "800e22ae-2a9d-4109-9e11-1360eeaa8ea7";

export function setupTestModeEligible(input: {
  enabled: string | undefined;
  configuredOrganizationId: string | undefined;
  requestedOrganizationId: string;
  environment: string | undefined;
  isOrganizationAdmin: boolean;
  isPlatformAdmin: boolean;
}) {
  const enabled = input.enabled?.trim().toLowerCase() === "true";
  const configured = (input.configuredOrganizationId ??
    MARIST_SETUP_TEST_ORGANIZATION_ID).trim().toLowerCase();
  const requested = input.requestedOrganizationId.trim().toLowerCase();
  const environment = input.environment?.trim().toLowerCase() ?? "";
  const environmentAllowed = ["local", "development", "staging", "testflight"]
    .includes(environment);
  return enabled && environmentAllowed &&
    configured === MARIST_SETUP_TEST_ORGANIZATION_ID &&
    requested === MARIST_SETUP_TEST_ORGANIZATION_ID &&
    (input.isOrganizationAdmin || input.isPlatformAdmin);
}

export function protectedSetupEntity(entityType: string) {
  return [
    "payment",
    "refund",
    "invoice",
    "expense",
    "registration_application",
    "event_operation",
    "practice_operation",
    "game_operation",
    "chat_message",
    "notification_delivery",
    "audit_log",
  ].includes(entityType);
}
