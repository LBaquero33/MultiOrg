import { buildAPNSPayload } from "./apns.ts";
import { notificationScenarioMatrix } from "./notification_scenario_matrix.ts";

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
}

const ORG = "11111111-1111-4111-8111-111111111111";
const NOTIFICATION = "22222222-2222-4222-8222-222222222222";

Deno.test("every operational notification scenario is unique and APNs-safe", () => {
  const ids = new Set<string>();
  for (const scenario of notificationScenarioMatrix) {
    assert(!ids.has(scenario.id), `duplicate scenario ${scenario.id}`);
    ids.add(scenario.id);
    assert(scenario.recipients.length > 0, `${scenario.id} has no recipients`);
    const encoded = buildAPNSPayload({
      id: NOTIFICATION,
      org_id: ORG,
      category: scenario.category,
      title: "Home Plate update",
      body: `Scenario ${scenario.id}`,
      action_route: scenario.route,
      action_payload: { scenario: scenario.id },
    }, 1);
    const aps = encoded.payload.aps as { alert: { title: string } };
    assert(aps.alert.title === "Home Plate update", `${scenario.id} title`);
    assert(encoded.byteLength < 4_096, `${scenario.id} exceeds APNs limit`);
  }
});

Deno.test("scenario categories and routes stay aligned with backend and iOS contracts", async () => {
  const sql = await Deno.readTextFile("../../migrations/20260729100000_align_game_notification_validation.sql");
  const swift = await Deno.readTextFile("../../../HomePlate/Core/NotificationCenterModels.swift");
  for (const scenario of notificationScenarioMatrix) {
    assert(sql.includes(`'${scenario.category}'`), `${scenario.id} category is not backend-valid`);
    assert(swift.includes(`\"${scenario.category}\"`), `${scenario.id} category is not decoded by iOS`);
    assert(swift.includes(`\"${scenario.route}\"`), `${scenario.id} route is not decoded by iOS`);
  }
});

Deno.test("cancel scenarios are one-time first-open notices", () => {
  const cancellations = notificationScenarioMatrix.filter((scenario) => scenario.id.includes("canceled"));
  assert(cancellations.length === 2, "event and booking cancellation coverage required");
  assert(cancellations.every((scenario) => scenario.dismissAfterFirstOpen === true), "cancellations must dismiss after first open");
});
