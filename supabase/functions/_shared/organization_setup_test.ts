import {
  canSkipSetupStep,
  MARIST_SETUP_TEST_ORGANIZATION_ID,
  nextSetupStep,
  previousSetupStep,
  protectedSetupEntity,
  setupReadiness,
  setupTestModeEligible,
} from "./organization_setup.ts";

function assert(condition: boolean, message: string) {
  if (!condition) throw new Error(message);
}

const minimumReady = {
  organization_active: true,
  basics_complete: true,
  active_or_default_season_count: 1,
  team_in_season_count: 1,
  staff_assignment_count: 0,
  player_assignment_count: 0,
  registration_offering_count: 0,
  facility_count: 0,
  communication_policy_configured: false,
  first_event_count: 0,
};

Deno.test("minimum setup readiness excludes optional work", () => {
  const result = setupReadiness(minimumReady);
  assert(result.ready, "minimum viable organization must be ready");
  assert(
    result.items.filter((item) => item.required).length === 4,
    "four requirements",
  );
});

Deno.test("team must belong to a season before launch", () => {
  const result = setupReadiness({ ...minimumReady, team_in_season_count: 0 });
  assert(!result.ready, "orphan team must block launch");
});

Deno.test("wizard navigation and skip rules are deterministic", () => {
  assert(nextSetupStep("basics") === "season", "next");
  assert(previousSetupStep("season") === "basics", "back");
  assert(!canSkipSetupStep("teams"), "team is required");
  assert(canSkipSetupStep("facilities"), "facilities are optional");
});

Deno.test("Marist setup test mode matches UUID and environment exactly", () => {
  const allowed = setupTestModeEligible({
    enabled: "true",
    configuredOrganizationId: undefined,
    requestedOrganizationId: MARIST_SETUP_TEST_ORGANIZATION_ID,
    environment: "staging",
    isOrganizationAdmin: true,
    isPlatformAdmin: false,
  });
  assert(allowed, "guarded test mode should be enabled");
  assert(
    !setupTestModeEligible({
      enabled: "true",
      configuredOrganizationId: MARIST_SETUP_TEST_ORGANIZATION_ID,
      requestedOrganizationId: "22222222-2222-4222-8222-222222222222",
      environment: "staging",
      isOrganizationAdmin: true,
      isPlatformAdmin: false,
    }),
    "name or mismatched UUID must never qualify",
  );
  assert(
    !setupTestModeEligible({
      enabled: "true",
      configuredOrganizationId: MARIST_SETUP_TEST_ORGANIZATION_ID,
      requestedOrganizationId: MARIST_SETUP_TEST_ORGANIZATION_ID,
      environment: "production",
      isOrganizationAdmin: true,
      isPlatformAdmin: false,
    }),
    "production must fail closed",
  );
});

Deno.test("setup test mode rejects retargeting and non-admin roles", () => {
  assert(
    !setupTestModeEligible({
      enabled: "false",
      configuredOrganizationId: MARIST_SETUP_TEST_ORGANIZATION_ID,
      requestedOrganizationId: MARIST_SETUP_TEST_ORGANIZATION_ID,
      environment: "development",
      isOrganizationAdmin: true,
      isPlatformAdmin: false,
    }),
    "disabled feature flag must fail closed",
  );
  assert(
    !setupTestModeEligible({
      enabled: "true",
      configuredOrganizationId: "22222222-2222-4222-8222-222222222222",
      requestedOrganizationId: "22222222-2222-4222-8222-222222222222",
      environment: "development",
      isOrganizationAdmin: true,
      isPlatformAdmin: false,
    }),
    "configuration cannot retarget setup mode",
  );
  for (const role of ["coach", "player", "parent"]) {
    assert(
      !setupTestModeEligible({
        enabled: "true",
        configuredOrganizationId: MARIST_SETUP_TEST_ORGANIZATION_ID,
        requestedOrganizationId: MARIST_SETUP_TEST_ORGANIZATION_ID,
        environment: "development",
        isOrganizationAdmin: false,
        isPlatformAdmin: false,
      }),
      `${role} must be rejected`,
    );
  }
});

Deno.test("owner admin and platform admin authority qualify only for Marist", () => {
  for (
    const authority of [
      { isOrganizationAdmin: true, isPlatformAdmin: false },
      { isOrganizationAdmin: false, isPlatformAdmin: true },
    ]
  ) {
    assert(
      setupTestModeEligible({
        enabled: "true",
        configuredOrganizationId: MARIST_SETUP_TEST_ORGANIZATION_ID,
        requestedOrganizationId: MARIST_SETUP_TEST_ORGANIZATION_ID,
        environment: "testflight",
        ...authority,
      }),
      "authorized setup actor should qualify",
    );
  }
});

Deno.test("selective reset protects durable operational history", () => {
  assert(protectedSetupEntity("payment"), "payments are protected");
  assert(protectedSetupEntity("game_operation"), "game history is protected");
  assert(!protectedSetupEntity("team"), "setup-created team may be previewed");
});
