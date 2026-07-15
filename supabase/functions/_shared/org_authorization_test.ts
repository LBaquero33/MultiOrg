import {
  canAdministerOrganization,
  canOperateOrganization,
} from "./org_authorization.ts";

function assert(condition: boolean, message: string) {
  if (!condition) throw new Error(message);
}

Deno.test("organization administration requires active owner or admin", () => {
  assert(canAdministerOrganization({ role: "owner", status: "active" }), "owner");
  assert(canAdministerOrganization({ role: "admin", status: "active" }), "admin");
  assert(!canAdministerOrganization({ role: "coach", status: "active" }), "coach");
  assert(!canAdministerOrganization({ role: "player", status: "active" }), "player");
  assert(!canAdministerOrganization({ role: "parent", status: "active" }), "parent");
  assert(!canAdministerOrganization({ role: "owner", status: "disabled" }), "inactive owner");
  assert(!canAdministerOrganization({ role: "admin", status: "suspended" }), "suspended admin");
  assert(!canAdministerOrganization(null), "missing membership");
});

Deno.test("organization operations keep coach access separate from administration", () => {
  assert(canOperateOrganization({ role: "owner", status: "active" }), "owner operations");
  assert(canOperateOrganization({ role: "admin", status: "active" }), "admin operations");
  assert(canOperateOrganization({ role: "coach", status: "active" }), "coach operations");
  assert(!canOperateOrganization({ role: "coach", status: "suspended" }), "suspended coach");
  assert(!canOperateOrganization({ role: "player", status: "active" }), "player operations");
});
