import {
  canAccessPlatformAdministration,
  cleanPlatformMembershipStatus,
  cleanPlatformRole,
  platformMemberMatches,
  platformMembershipMutation,
} from "./platform_admin_permissions.ts";

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
}

Deno.test("only the temporary entitled LBAQ27 operator can access platform administration", () => {
  assert(
    canAccessPlatformAdministration("LBAQ27@gmail.com", true),
    "entitled LBAQ27 account",
  );
  assert(
    !canAccessPlatformAdministration("owner@example.com", true),
    "another entitled email remains forbidden during phase one",
  );
  assert(
    !canAccessPlatformAdministration("lbaq27@gmail.com", false),
    "email never replaces the durable entitlement",
  );
});

Deno.test("platform membership mutation accepts bounded exact roles and status", () => {
  for (const role of ["owner", "admin", "coach", "player", "parent"]) {
    assert(cleanPlatformRole(role) === role, `role ${role}`);
  }
  for (const status of ["active", "invited", "disabled", "suspended"]) {
    assert(
      cleanPlatformMembershipStatus(status) === status,
      `status ${status}`,
    );
  }
  assert(
    cleanPlatformRole("platform_admin") === null,
    "platform is not an org role",
  );
  assert(
    cleanPlatformMembershipStatus("deleted") === null,
    "invalid status rejected",
  );
});

Deno.test("permission payload requires an idempotency key and bounded reason", () => {
  const parsed = platformMembershipMutation({
    role: "admin",
    status: "active",
    request_id: "11111111-1111-4111-8111-111111111111",
    reason: "Promotion approved",
  });
  assert(parsed?.role === "admin", "role parsed");
  assert(parsed?.reason === "Promotion approved", "reason parsed");
  assert(
    platformMembershipMutation({ role: "admin", status: "active" }) === null,
    "key required",
  );
});

Deno.test("owner, coach, and membership-status transitions preserve the requested state", () => {
  const requestId = "22222222-2222-4222-8222-222222222222";
  const transitions = [
    { role: "owner", status: "active" },
    { role: "admin", status: "active" },
    { role: "coach", status: "active" },
    { role: "coach", status: "disabled" },
    { role: "coach", status: "active" },
  ];
  for (const transition of transitions) {
    const parsed = platformMembershipMutation({
      ...transition,
      request_id: requestId,
    });
    assert(parsed?.role === transition.role, `role ${transition.role}`);
    assert(parsed?.status === transition.status, `status ${transition.status}`);
    assert(parsed?.requestId === requestId, "stable idempotency key");
  }
});

Deno.test("member search and role/inactive filters remain organization-local", () => {
  const member = {
    role: "coach",
    status: "active",
    full_name: "Andrew Coach",
    username: "andrewc",
    email: "andrew@example.com",
  };
  assert(platformMemberMatches(member, "andrew", "coach"), "name and role");
  assert(platformMemberMatches(member, "example.com", "all"), "email");
  assert(!platformMemberMatches(member, "andrew", "owner"), "wrong role");
  assert(
    !platformMemberMatches(member, "", "inactive"),
    "active is not inactive",
  );
  assert(
    platformMemberMatches({ ...member, status: "disabled" }, "", "inactive"),
    "disabled is inactive",
  );
});
