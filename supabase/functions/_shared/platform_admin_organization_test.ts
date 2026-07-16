import { platformOrganizationCreationRPCArguments } from "./platform_admin_organization.ts";

function assert(condition: boolean, message: string) {
  if (!condition) throw new Error(message);
}

function assertEqual<T>(actual: T, expected: T, message: string) {
  if (actual !== expected) {
    throw new Error(`${message}: expected ${expected}, received ${actual}`);
  }
}

const actorId = "11111111-1111-4111-8111-111111111111";

Deno.test("organization creation assigns ownership only to the authenticated actor", () => {
  const untrustedInput = {
    name: "Home Plate Test",
    slug: "home-plate-test",
    plan: "starter",
    billingEmail: null,
    maxMembers: null,
    owner_user_id: "22222222-2222-4222-8222-222222222222",
  };
  const rpc = platformOrganizationCreationRPCArguments(actorId, untrustedInput);
  assertEqual(rpc.p_actor_id, actorId, "authenticated actor");
  assert(!("owner_user_id" in rpc), "client owner ID must not reach the RPC");
});

Deno.test("organization creation RPC remains deterministic for the same actor and input", () => {
  const input = {
    name: "Home Plate Test",
    slug: "home-plate-test",
    plan: "starter",
    billingEmail: "billing@example.com",
    maxMembers: 30,
  };
  const first = platformOrganizationCreationRPCArguments(actorId, input);
  const second = platformOrganizationCreationRPCArguments(actorId, input);
  assertEqual(JSON.stringify(first), JSON.stringify(second), "RPC arguments");
});

Deno.test("platform Edge Function derives the creation actor from verified auth", async () => {
  const functionUrl = new URL("../platform_admin/index.ts", import.meta.url);
  const source = await Deno.readTextFile(functionUrl);
  assert(
    source.includes("await userClient.auth.getUser()"),
    "verified Supabase user lookup",
  );
  assert(
    source.includes("const actorId = userData.user?.id"),
    "actor comes from verified user",
  );
  assert(
    source.includes("platformOrganizationCreationRPCArguments(actorId"),
    "verified actor reaches RPC builder",
  );
  assert(
    !source.includes("body.actor_id"),
    "browser payload cannot provide actor identity",
  );
  assert(
    !source.includes("body.owner_user_id"),
    "browser payload cannot provide owner identity",
  );
  assert(
    source.includes('.from("sd_platform_admins")'),
    "platform grant is checked",
  );
  assert(
    source.includes("Boolean(grant)"),
    "durable grant reaches authorization",
  );
  assert(
    source.includes("canAccessPlatformAdministration(userData.user?.email"),
    "temporary operator predicate is centralized",
  );
  assert(
    source.includes("return json(200, {"),
    "successful creation returns a decoded response",
  );
  assert(source.includes("organization:"), "created organization is returned");
});

Deno.test("platform permission management is server-authorized, scoped, audited, and idempotent", async () => {
  const functionUrl = new URL("../platform_admin/index.ts", import.meta.url);
  const source = await Deno.readTextFile(functionUrl);
  assert(
    source.includes('action === "list_members"'),
    "organization member directory",
  );
  assert(source.includes('action === "search_users"'), "global user lookup");
  assert(
    source.includes('action === "update_membership"'),
    "membership editor",
  );
  assert(
    source.includes('action === "list_platform_admins"'),
    "platform admin list",
  );
  assert(
    source.includes('action === "grant_platform_admin"'),
    "platform admin grant",
  );
  assert(
    source.includes('action === "revoke_platform_admin"'),
    "platform admin revoke",
  );
  assert(
    source.includes('.eq("org_id", orgId)\n      .eq("user_id", userId)'),
    "membership edits are cross-org safe",
  );
  assert(
    source.includes("auditId = await audit("),
    "audit precedes membership update",
  );
  assert(source.includes('"update_membership",'), "membership audit action");
  assert(
    source.includes("request_id: mutation.requestId"),
    "request identifier is audited",
  );
  assert(
    source.includes('outcome: "succeeded"'),
    "successful idempotency marker",
  );
  assert(
    source.includes('"last_active_owner_required"'),
    "final owner failure is stable",
  );
  assert(!source.includes("body.actor_id"), "actor remains server derived");
});

Deno.test("temporary manual organization provisioning is atomic and preserves explicit creator ownership", async () => {
  const migrationUrl = new URL(
    "../../migrations/20260714150000_org_ownership_and_admin_authorization.sql",
    import.meta.url,
  );
  const sql = (await Deno.readTextFile(migrationUrl)).toLowerCase();
  assert(
    sql.includes(
      "create or replace function public.sd_platform_create_organization",
    ),
    "atomic RPC",
  );
  assert(sql.includes("insert into public.sd_orgs"), "organization insert");
  assert(
    sql.includes("insert into public.sd_org_memberships"),
    "owner membership insert",
  );
  assert(
    sql.includes("created_org_id, p_actor_id, 'owner', 'active'"),
    "active creator ownership",
  );
  assert(sql.includes("insert into public.sd_org_settings"), "settings insert");
  assert(sql.includes("unexpected_sd_org_membership_roles"), "role preflight");
  assert(
    sql.includes("unexpected_sd_org_membership_statuses"),
    "status preflight",
  );
  assert(!sql.includes("set role = 'owner'"), "no automatic role promotion");
  assert(
    !sql.includes("insert into public.sd_org_memberships\n  select"),
    "existing organizations are never bulk-assigned",
  );
});

Deno.test("last-active-owner protection excludes admins and permits transactional replacement", async () => {
  const migrationUrl = new URL(
    "../../migrations/20260714150000_org_ownership_and_admin_authorization.sql",
    import.meta.url,
  );
  const sql = (await Deno.readTextFile(migrationUrl)).toLowerCase();
  const invariant = sql.split(
    "create or replace function public.sd_enforce_last_active_owner()",
  )[1]
    ?.split("-- temporary manual platform provisioning")[0] ?? "";
  assert(invariant.includes("m.role = 'owner'"), "active owner invariant");
  assert(invariant.includes("m.status = 'active'"), "active status invariant");
  assert(
    !invariant.includes("m.role in ('owner', 'admin')"),
    "admins must not satisfy owner invariant",
  );
  assert(
    sql.includes("deferrable initially deferred"),
    "replacement owner may be added in the same transaction",
  );
  assert(
    invariant.includes("for update"),
    "concurrent owner removals must serialize per organization",
  );
  assert(sql.includes("last_active_owner_required"), "clear invariant failure");
});

Deno.test("owner and administrator diagnostics remain distinct", async () => {
  const migrationUrl = new URL(
    "../../migrations/20260714150000_org_ownership_and_admin_authorization.sql",
    import.meta.url,
  );
  const sql = (await Deno.readTextFile(migrationUrl)).toLowerCase();
  const ownerless = sql.split("sd_platform_list_ownerless_organizations")[1]
    ?.split(
      "revoke all on function public.sd_platform_list_ownerless_organizations",
    )[0] ?? "";
  const unmanaged = sql.split("sd_platform_list_unmanaged_organizations")[1]
    ?.split(
      "revoke all on function public.sd_platform_list_unmanaged_organizations",
    )[0] ?? "";
  assert(ownerless.includes("m.role = 'owner'"), "no-active-owner diagnostic");
  assert(
    !ownerless.includes("m.role in ('owner', 'admin')"),
    "ownerless must not accept admins",
  );
  assert(
    unmanaged.includes("m.role in ('owner', 'admin')"),
    "no-active-owner/admin diagnostic",
  );
});

Deno.test("security-definer functions use hardened paths and explicit grants", async () => {
  const migrationUrl = new URL(
    "../../migrations/20260714150000_org_ownership_and_admin_authorization.sql",
    import.meta.url,
  );
  const sql = (await Deno.readTextFile(migrationUrl)).toLowerCase();
  assert(
    !sql.includes("set search_path = public, auth"),
    "writable schemas must not be in search_path",
  );
  assert(sql.includes("set search_path = ''"), "empty search_path");
  for (
    const helper of [
      "sd_is_org_member",
      "sd_is_org_admin",
      "sd_is_org_coach",
      "sd_is_org_staff",
    ]
  ) {
    assert(
      sql.includes(`revoke all on function public.${helper}(uuid)`),
      `${helper} revoke`,
    );
    assert(
      sql.includes(`grant execute on function public.${helper}(uuid)`),
      `${helper} grant`,
    );
  }
  assert(
    sql.includes(
      "revoke all on function public.sd_can_manage_team_player(uuid, uuid)",
    ),
    "team helper revoke",
  );
  assert(
    sql.includes(
      "grant execute on function public.sd_can_manage_team_player(uuid, uuid)",
    ),
    "team helper grant",
  );
  assert(
    sql.includes(
      "revoke all on function public.sd_enforce_last_active_owner()",
    ),
    "trigger function revoke",
  );
  for (
    const rpc of [
      "sd_platform_create_organization(\n  uuid, text, text, text, text, integer\n)",
      "sd_platform_list_ownerless_organizations(uuid)",
      "sd_platform_list_unmanaged_organizations(uuid)",
    ]
  ) {
    assert(
      sql.includes(`revoke all on function public.${rpc}`),
      `${rpc} revoke`,
    );
    assert(
      sql.includes(`grant execute on function public.${rpc}`),
      `${rpc} grant`,
    );
  }
  assert(
    sql.includes("to service_role"),
    "platform RPCs remain service-role-only",
  );
});
