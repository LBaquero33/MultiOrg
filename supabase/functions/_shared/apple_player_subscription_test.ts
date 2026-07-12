import {
  authorizeApplePurchaseContext,
  canonicalUuid,
  expectedAppAccountToken,
  syncAppleSubscription,
  validateAppleTransactionContext,
} from "./apple_player_subscription.ts";

const org = "800e22ae-2a9d-4109-9e11-1360eeaa8ea7";
const player = "b1aead64-4ecb-46c5-b30f-3c96c5322cb3";
const parent = "a1aead64-4ecb-46c5-b30f-3c96c5322cb4";
const membership = (userId: string, role: string, status = "active") => ({ user_id: userId, role, status });
const profile = (id: string) => ({ id });

function assertEquals(actual: unknown, expected: unknown) {
  if (actual !== expected) throw new Error(`Expected ${String(expected)}, received ${String(actual)}`);
}

function assertCode(code: string, operation: () => unknown) {
  try {
    operation();
    throw new Error(`Expected ${code}`);
  } catch (error) {
    assertEquals(error instanceof Error ? error.message : "", code);
  }
}

async function assertAsyncCode(code: string, operation: () => Promise<unknown>) {
  try {
    await operation();
    throw new Error(`Expected ${code}`);
  } catch (error) {
    assertEquals(error instanceof Error ? error.message : "", code);
  }
}

const transaction = (token: string) => ({
  bundleId: "com.homeplate.app",
  productId: "com.homeplate.player.monthly",
  environment: "Sandbox",
  appAccountToken: token,
  transactionId: "200000000000001",
  originalTransactionId: "200000000000000",
  purchaseDate: Date.now() - 1_000,
  expiresDate: Date.now() + 86_400_000,
});

class FakeAdmin {
  existingSubscription: Record<string, unknown> | null = null;
  entitlement: Record<string, unknown> | null = null;
  subscriptionWriteError: unknown = null;
  entitlementReadError: unknown = null;
  entitlementWriteError: unknown = null;
  subscriptionWrite = "";
  entitlementPayload: Record<string, unknown> | null = null;

  from(table: string) {
    return new FakeQuery(this, table);
  }
}

class FakeQuery {
  private operation = "select";
  constructor(private admin: FakeAdmin, private table: string) {}
  select(_columns: string) { this.operation = "select"; return this; }
  eq(_column: string, _value: unknown) { return this; }
  update(_payload: unknown) { this.operation = "update"; this.admin.subscriptionWrite = "update"; return this; }
  insert(_payload: unknown) { this.operation = "insert"; this.admin.subscriptionWrite = "insert"; return this; }
  upsert(payload: Record<string, unknown>) {
    this.admin.entitlementPayload = payload;
    return Promise.resolve({ data: null, error: this.admin.entitlementWriteError });
  }
  maybeSingle() {
    if (this.table === "sd_player_subscriptions") {
      return Promise.resolve({ data: this.admin.existingSubscription, error: null });
    }
    return Promise.resolve({ data: this.admin.entitlement, error: this.admin.entitlementReadError });
  }
  then(resolve: (value: unknown) => unknown, reject: (reason?: unknown) => unknown) {
    return Promise.resolve({ data: null, error: this.admin.subscriptionWriteError }).then(resolve, reject);
  }
}

Deno.test("canonical UUID removes Swift UUID casing differences", () => {
  assertEquals(canonicalUuid(player.toUpperCase()), player);
});

Deno.test("deterministic token ignores UUID string casing", async () => {
  assertEquals(
    await expectedAppAccountToken(org, player, player),
    await expectedAppAccountToken(org.toUpperCase(), player.toUpperCase(), player.toUpperCase()),
  );
});

Deno.test("transaction context accepts the current deterministic token", async () => {
  const token = await expectedAppAccountToken(org, player, player);
  validateAppleTransactionContext(transaction(token), {
    bundleId: "com.homeplate.app",
    productId: "com.homeplate.player.monthly",
    environment: "sandbox",
    appAccountToken: token,
  });
});

Deno.test("wrong or legacy app account token remains blocked", async () => {
  const expected = await expectedAppAccountToken(org, player, player);
  assertCode("app_account_token_mismatch", () => validateAppleTransactionContext(transaction(parent), {
    bundleId: "com.homeplate.app",
    productId: "com.homeplate.player.monthly",
    environment: "sandbox",
    appAccountToken: expected,
  }));
});

Deno.test("valid player self-purchase", () => {
  assertEquals(authorizeApplePurchaseContext({
    actorId: player, orgId: org, playerId: player,
    actorProfile: profile(player), targetProfile: profile(player),
    actorMembership: membership(player, "player"), targetMembership: membership(player, "player"),
    parentLink: null,
  }), "player");
});

Deno.test("valid linked-parent purchase", () => {
  assertEquals(authorizeApplePurchaseContext({
    actorId: parent, orgId: org, playerId: player,
    actorProfile: profile(parent), targetProfile: profile(player),
    actorMembership: membership(parent, "parent"), targetMembership: membership(player, "player"),
    parentLink: { org_id: org, parent_id: parent, child_id: player, can_pay: true },
  }), "parent");
});

Deno.test("parent without payment permission is blocked", () => {
  assertCode("parent_can_pay_false", () => authorizeApplePurchaseContext({
    actorId: parent, orgId: org, playerId: player,
    actorProfile: profile(parent), targetProfile: profile(player),
    actorMembership: membership(parent, "parent"), targetMembership: membership(player, "player"),
    parentLink: { org_id: org, parent_id: parent, child_id: player, can_pay: false },
  }));
});

Deno.test("inactive player membership is blocked", () => {
  assertCode("actor_membership_not_active", () => authorizeApplePurchaseContext({
    actorId: player, orgId: org, playerId: player,
    actorProfile: profile(player), targetProfile: profile(player),
    actorMembership: membership(player, "player", "disabled"), targetMembership: membership(player, "player", "disabled"),
    parentLink: null,
  }));
});

Deno.test("coach or admin actor cannot use player purchase endpoint", () => {
  assertCode("self_target_id_mismatch", () => authorizeApplePurchaseContext({
    actorId: parent, orgId: org, playerId: player,
    actorProfile: profile(parent), targetProfile: profile(player),
    actorMembership: membership(parent, "coach"), targetMembership: membership(player, "player"),
    parentLink: null,
  }));
});

Deno.test("wrong player ID is blocked", () => {
  assertCode("self_target_id_mismatch", () => authorizeApplePurchaseContext({
    actorId: parent, orgId: org, playerId: player,
    actorProfile: profile(parent), targetProfile: profile(player),
    actorMembership: membership(parent, "player"), targetMembership: membership(player, "player"),
    parentLink: null,
  }));
});

Deno.test("cross-organization parent link is blocked", () => {
  assertCode("organization_context_mismatch", () => authorizeApplePurchaseContext({
    actorId: parent, orgId: org, playerId: player,
    actorProfile: profile(parent), targetProfile: profile(player),
    actorMembership: membership(parent, "parent"), targetMembership: membership(player, "player"),
    parentLink: { org_id: "900e22ae-2a9d-4109-9e11-1360eeaa8ea7", parent_id: parent, child_id: player, can_pay: true },
  }));
});

Deno.test("missing membership remains distinguishable from inactive membership", () => {
  assertCode("actor_membership_missing", () => authorizeApplePurchaseContext({
    actorId: player, orgId: org, playerId: player,
    actorProfile: profile(player), targetProfile: profile(player),
    actorMembership: null, targetMembership: membership(player, "player"), parentLink: null,
}));
});

Deno.test("duplicate transaction retry updates the same subscription context", async () => {
  const admin = new FakeAdmin();
  admin.existingSubscription = { id: "subscription-id", org_id: org, player_id: player, billing_user_id: player };
  const result = await syncAppleSubscription({
    admin, transaction: transaction(await expectedAppAccountToken(org, player, player)),
    orgId: org, playerId: player, billingUserId: player, status: "active",
  });
  assertEquals(admin.subscriptionWrite, "update");
  assertEquals(result.access_may_be_active, true);
  assertEquals(admin.entitlementPayload?.user_id, player);
});

Deno.test("an existing transaction cannot move to another player or organization", async () => {
  const admin = new FakeAdmin();
  admin.existingSubscription = { id: "subscription-id", org_id: org, player_id: parent, billing_user_id: player };
  await assertAsyncCode("organization_context_mismatch", () => syncAppleSubscription({
    admin, transaction: transaction(parent), orgId: org, playerId: player, billingUserId: player, status: "active",
  }));
});

Deno.test("subscription database failures retain a safe diagnostic code", async () => {
  const admin = new FakeAdmin();
  admin.subscriptionWriteError = { message: "database details must not escape" };
  await assertAsyncCode("subscription_upsert_failed", () => syncAppleSubscription({
    admin, transaction: transaction(player), orgId: org, playerId: player, billingUserId: player, status: "active",
  }));
});

Deno.test("entitlement database failures retain a safe diagnostic code", async () => {
  const admin = new FakeAdmin();
  admin.entitlementWriteError = { message: "database details must not escape" };
  await assertAsyncCode("entitlement_sync_failed", () => syncAppleSubscription({
    admin, transaction: transaction(player), orgId: org, playerId: player, billingUserId: player, status: "active",
  }));
});

Deno.test("active non-Apple access is preserved", async () => {
  const admin = new FakeAdmin();
  admin.entitlement = { user_id: player, is_active: true, source: "organization" };
  const result = await syncAppleSubscription({
    admin, transaction: transaction(player), orgId: org, playerId: player, billingUserId: player, status: "expired",
  });
  assertEquals(result.access_may_be_active, true);
  assertEquals(admin.entitlementPayload, null);
});
