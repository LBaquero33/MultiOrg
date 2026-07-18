import {
  canSkipSetupStep,
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
    configuredOrganizationId: "11111111-1111-4111-8111-111111111111",
    requestedOrganizationId: "11111111-1111-4111-8111-111111111111",
    environment: "staging",
    isOrganizationAdmin: true,
    isPlatformAdmin: false,
  });
  assert(allowed, "guarded test mode should be enabled");
  assert(
    !setupTestModeEligible({
      enabled: "true",
      configuredOrganizationId: "11111111-1111-4111-8111-111111111111",
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
      configuredOrganizationId: "11111111-1111-4111-8111-111111111111",
      requestedOrganizationId: "11111111-1111-4111-8111-111111111111",
      environment: "production",
      isOrganizationAdmin: true,
      isPlatformAdmin: false,
    }),
    "production must fail closed",
  );
});

Deno.test("selective reset protects durable operational history", () => {
  assert(protectedSetupEntity("payment"), "payments are protected");
  assert(protectedSetupEntity("game_operation"), "game history is protected");
  assert(!protectedSetupEntity("team"), "setup-created team may be previewed");
});
