import { isOrgAdminAction, ORG_ADMIN_ACTIONS } from "./org_admin_actions.ts";

function assert(condition: boolean, message: string) {
  if (!condition) throw new Error(message);
}

Deno.test("every known org_admin action is accepted", () => {
  for (const action of ORG_ADMIN_ACTIONS) {
    assert(isOrgAdminAction(action), `${action} must be accepted`);
  }
});

Deno.test("Create Season is an authoritative supported action", () => {
  assert(isOrgAdminAction("create_season"), "create_season");
  assert(isOrgAdminAction("update_season"), "update_season");
});

Deno.test("invalid org_admin actions fail closed", () => {
  assert(!isOrgAdminAction("createSeason"), "camelCase must not be accepted");
  assert(!isOrgAdminAction("unknown_action"), "unknown action must fail");
  assert(!isOrgAdminAction(""), "blank action must fail");
});

Deno.test("org_admin dispatch uses controlled unsupported_action", async () => {
  const source = await Deno.readTextFile(
    new URL("../org_admin/index.ts", import.meta.url),
  );
  assert(!source.includes('error: "unknown_action"'), "no raw unknown_action");
  assert(source.includes('error: "unsupported_action"'), "controlled fallback");
  for (const action of ORG_ADMIN_ACTIONS) {
    assert(
      source.includes(`action === "${action}"`) ||
        source.includes(`action !== "${action}"`),
      `${action} must have a dispatch branch`,
    );
  }
});

Deno.test("platform feature controls use controlled unsupported_action", async () => {
  const source = await Deno.readTextFile(
    new URL("../platform_admin/index.ts", import.meta.url),
  );
  assert(!source.includes('error: "unknown_action"'), "no legacy fallback");
  assert(source.includes('error: "unsupported_action"'), "controlled fallback");
});

Deno.test("season requests preserve deterministic retry identity", async () => {
  const source = await Deno.readTextFile(
    new URL("../org_admin/index.ts", import.meta.url),
  );
  assert(source.includes('.eq("request_id", requestId)'), "retry lookup");
  assert(source.includes("replayed: true"), "replay response");
  assert(
    source.includes("sd_team_operations_audit_logs"),
    "auditable mutation",
  );
});
