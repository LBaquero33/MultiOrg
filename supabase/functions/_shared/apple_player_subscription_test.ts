import {
  APPLE_PLAYER_MONTHLY_PRODUCT_ID,
  authorizeApplePurchaseContext,
  canonicalUuid,
  expectedAppAccountToken,
  normalizeStoreKitVerifiedTransaction,
  syncAppleSubscriptionAtomically,
  validateAppleTransactionContext,
} from "./apple_player_subscription.ts";

type Fixture = {
  organization_id: string;
  player_id: string;
  billing_user_id: string;
  canonical_input: string;
  app_account_token: string;
};

const fixtures = JSON.parse(
  await Deno.readTextFile(
    new URL(
      "../../../SharedFixtures/apple_player_purchase_context_vectors.json",
      import.meta.url,
    ),
  ),
) as Fixture[];

const org = "800e22ae-2a9d-4109-9e11-1360eeaa8ea7";
const otherOrg = "900e22ae-2a9d-4109-9e11-1360eeaa8ea7";
const player = "b1aead64-4ecb-46c5-b30f-3c96c5322cb3";
const otherPlayer = "c1aead64-4ecb-46c5-b30f-3c96c5322cb4";
const parent = "a1aead64-4ecb-46c5-b30f-3c96c5322cb4";
const membership = (userId: string, role: string, status = "active") => ({
  user_id: userId,
  role,
  status,
});
const profile = (id: string) => ({ id });

function assertEquals(actual: unknown, expected: unknown) {
  if (actual !== expected) {
    throw new Error(`Expected ${String(expected)}, received ${String(actual)}`);
  }
}

function assertNotEquals(actual: unknown, expected: unknown) {
  if (actual === expected) {
    throw new Error(`Expected values to differ: ${actual}`);
  }
}

function assert(value: unknown, message = "Assertion failed") {
  if (!value) throw new Error(message);
}

function assertCode(code: string, operation: () => unknown) {
  try {
    operation();
    throw new Error(`Expected ${code}`);
  } catch (error) {
    assertEquals(error instanceof Error ? error.message : "", code);
  }
}

async function assertAsyncCode(
  code: string,
  operation: () => Promise<unknown>,
) {
  try {
    await operation();
    throw new Error(`Expected ${code}`);
  } catch (error) {
    assertEquals(error instanceof Error ? error.message : "", code);
  }
}

const validTransaction = async (billingUserId = player) => ({
  bundleId: "com.multiorg.app",
  productId: APPLE_PLAYER_MONTHLY_PRODUCT_ID,
  environment: "sandbox",
  appAccountToken: await expectedAppAccountToken(org, player, billingUserId),
  transactionId: "200000000000001",
  originalTransactionId: "200000000000000",
  purchaseDate: Date.now() - 1_000,
  expiresDate: Date.now() + 30 * 24 * 60 * 60 * 1_000,
  revocationDate: 0,
});

class FakeAdmin {
  calls: Array<{ name: string; args: Record<string, unknown> }> = [];
  data: unknown = {
    status: "active",
    current_period_end: "2026-08-13T00:00:00.000Z",
    persisted: true,
    entitlement_synchronized: true,
    access_is_active: true,
    idempotent: false,
  };
  error: unknown = null;

  rpc(name: string, args: Record<string, unknown>) {
    this.calls.push({ name, args });
    return Promise.resolve({ data: this.data, error: this.error });
  }
}

Deno.test("backend matches every shared appAccountToken vector", async () => {
  for (const fixture of fixtures) {
    const orgId = canonicalUuid(fixture.organization_id);
    const playerId = canonicalUuid(fixture.player_id);
    const billingUserId = canonicalUuid(fixture.billing_user_id);
    assert(orgId && playerId && billingUserId);
    assertEquals(
      `${orgId}|${playerId}|${billingUserId}`,
      fixture.canonical_input,
    );
    assertEquals(
      await expectedAppAccountToken(orgId!, playerId!, billingUserId!),
      fixture.app_account_token,
    );
  }
});

Deno.test("UUID casing is normalized and all three identities affect the token", async () => {
  const baseline = await expectedAppAccountToken(org, player, parent);
  assertEquals(
    baseline,
    await expectedAppAccountToken(
      org.toUpperCase(),
      player.toUpperCase(),
      parent.toUpperCase(),
    ),
  );
  assertNotEquals(
    baseline,
    await expectedAppAccountToken(otherOrg, player, parent),
  );
  assertNotEquals(
    baseline,
    await expectedAppAccountToken(org, otherPlayer, parent),
  );
  assertNotEquals(
    baseline,
    await expectedAppAccountToken(org, player, otherPlayer),
  );
});

Deno.test("verified StoreKit metadata is strictly normalized", async () => {
  const transaction = await validTransaction();
  const normalized = normalizeStoreKitVerifiedTransaction({
    bundle_id: transaction.bundleId,
    product_id: transaction.productId,
    environment: "Sandbox",
    app_account_token: transaction.appAccountToken,
    transaction_id: transaction.transactionId,
    original_transaction_id: transaction.originalTransactionId,
    purchase_date_ms: String(transaction.purchaseDate),
    expires_date_ms: String(transaction.expiresDate),
    revocation_date_ms: "0",
    is_active: true,
  }, {
    bundleId: transaction.bundleId,
    environment: "sandbox",
    appAccountToken: transaction.appAccountToken,
  });
  assertEquals(normalized.productId, APPLE_PLAYER_MONTHLY_PRODUCT_ID);
  assertEquals("is_active" in normalized, false);
  validateAppleTransactionContext(normalized, {
    bundleId: transaction.bundleId,
    productId: APPLE_PLAYER_MONTHLY_PRODUCT_ID,
    environment: "sandbox",
    appAccountToken: transaction.appAccountToken,
  });
});

Deno.test("metadata manipulation is rejected", async () => {
  const transaction = await validTransaction();
  const body = {
    bundle_id: transaction.bundleId,
    product_id: transaction.productId,
    environment: transaction.environment,
    app_account_token: transaction.appAccountToken,
    transaction_id: transaction.transactionId,
    original_transaction_id: transaction.originalTransactionId,
    purchase_date_ms: String(transaction.purchaseDate),
    expires_date_ms: String(transaction.expiresDate),
    revocation_date_ms: "0",
  };
  const expected = {
    bundleId: transaction.bundleId,
    environment: "sandbox",
    appAccountToken: transaction.appAccountToken,
  };
  assertCode("product_id_mismatch", () =>
    normalizeStoreKitVerifiedTransaction(
      { ...body, product_id: "wrong.product" },
      expected,
    ));
  assertCode("bundle_id_mismatch", () =>
    normalizeStoreKitVerifiedTransaction(
      { ...body, bundle_id: "wrong.bundle" },
      expected,
    ));
  assertCode("environment_mismatch", () =>
    normalizeStoreKitVerifiedTransaction(
      { ...body, environment: "production" },
      expected,
    ));
  assertCode(
    "app_account_token_mismatch",
    () =>
      normalizeStoreKitVerifiedTransaction(
        { ...body, app_account_token: parent },
        expected,
      ),
  );
  assertCode(
    "apple_transaction_invalid",
    () =>
      normalizeStoreKitVerifiedTransaction(
        { ...body, expires_date_ms: String(Date.now() + 90 * 86_400_000) },
        expected,
      ),
  );
});

Deno.test("active player may purchase only for self", () => {
  assertEquals(
    authorizeApplePurchaseContext({
      actorId: player,
      orgId: org,
      playerId: player,
      actorProfile: profile(player),
      targetProfile: profile(player),
      actorMembership: membership(player, "player"),
      targetMembership: membership(player, "player"),
      parentLink: null,
    }),
    "player",
  );
});

Deno.test("active linked parent with can_pay may purchase", () => {
  assertEquals(
    authorizeApplePurchaseContext({
      actorId: parent,
      orgId: org,
      playerId: player,
      actorProfile: profile(parent),
      targetProfile: profile(player),
      actorMembership: membership(parent, "parent"),
      targetMembership: membership(player, "player"),
      parentLink: {
        org_id: org,
        parent_id: parent,
        child_id: player,
        can_pay: true,
      },
    }),
    "parent",
  );
});

Deno.test("parent without can_pay is blocked", () => {
  assertCode("parent_can_pay_false", () =>
    authorizeApplePurchaseContext({
      actorId: parent,
      orgId: org,
      playerId: player,
      actorProfile: profile(parent),
      targetProfile: profile(player),
      actorMembership: membership(parent, "parent"),
      targetMembership: membership(player, "player"),
      parentLink: {
        org_id: org,
        parent_id: parent,
        child_id: player,
        can_pay: false,
      },
    }));
});

Deno.test("coach, admin, wrong-player, inactive, and cross-org actors are blocked", () => {
  for (const role of ["coach", "owner", "admin"]) {
    assertCode("actor_role_not_allowed", () =>
      authorizeApplePurchaseContext({
        actorId: parent,
        orgId: org,
        playerId: player,
        actorProfile: profile(parent),
        targetProfile: profile(player),
        actorMembership: membership(parent, role),
        targetMembership: membership(player, "player"),
        parentLink: null,
      }));
  }
  assertCode("actor_role_not_allowed", () =>
    authorizeApplePurchaseContext({
      actorId: parent,
      orgId: org,
      playerId: player,
      actorProfile: profile(parent),
      targetProfile: profile(player),
      actorMembership: membership(parent, "player"),
      targetMembership: membership(player, "player"),
      parentLink: null,
    }));
  assertCode(
    "actor_membership_not_active",
    () =>
      authorizeApplePurchaseContext({
        actorId: player,
        orgId: org,
        playerId: player,
        actorProfile: profile(player),
        targetProfile: profile(player),
        actorMembership: membership(player, "player", "disabled"),
        targetMembership: membership(player, "player"),
        parentLink: null,
      }),
  );
  assertCode(
    "organization_context_mismatch",
    () =>
      authorizeApplePurchaseContext({
        actorId: parent,
        orgId: org,
        playerId: player,
        actorProfile: profile(parent),
        targetProfile: profile(player),
        actorMembership: membership(parent, "parent"),
        targetMembership: membership(player, "player"),
        parentLink: {
          org_id: otherOrg,
          parent_id: parent,
          child_id: player,
          can_pay: true,
        },
      }),
  );
});

Deno.test("atomic sync makes one RPC and returns persistence facts", async () => {
  const admin = new FakeAdmin();
  const transaction = await validTransaction();
  const result = await syncAppleSubscriptionAtomically({
    admin,
    transaction,
    orgId: org,
    playerId: player,
    billingUserId: player,
    status: "active",
  });
  assertEquals(admin.calls.length, 1);
  assertEquals(admin.calls[0].name, "sd_sync_apple_player_subscription");
  assertEquals(admin.calls[0].args.p_transaction_id, transaction.transactionId);
  assertEquals(result.persisted, true);
  assertEquals(result.entitlement_synchronized, true);
  assertEquals(result.access_is_active, true);
});

Deno.test("idempotent retry remains a successful atomic synchronization", async () => {
  const admin = new FakeAdmin();
  admin.data = {
    status: "active",
    current_period_end: "2026-08-13T00:00:00.000Z",
    persisted: true,
    entitlement_synchronized: true,
    access_is_active: true,
    idempotent: true,
  };
  const result = await syncAppleSubscriptionAtomically({
    admin,
    transaction: await validTransaction(),
    orgId: org,
    playerId: player,
    billingUserId: player,
    status: "active",
  });
  assertEquals(result.idempotent, true);
});

Deno.test("replay, reassignment, and malformed atomic responses fail closed", async () => {
  const transaction = await validTransaction();
  for (
    const code of [
      "apple_transaction_reassigned",
      "apple_original_transaction_reassigned",
      "apple_transaction_replay",
      "apple_transaction_replay_conflict",
      "player_subscription_context_conflict",
    ]
  ) {
    const admin = new FakeAdmin();
    admin.error = { message: `database rejected: ${code}` };
    await assertAsyncCode(code, () =>
      syncAppleSubscriptionAtomically({
        admin,
        transaction,
        orgId: org,
        playerId: player,
        billingUserId: player,
        status: "active",
      }));
  }
  const malformed = new FakeAdmin();
  malformed.data = { persisted: true, access_is_active: true };
  await assertAsyncCode(
    "apple_subscription_atomic_sync_failed",
    async () =>
      syncAppleSubscriptionAtomically({
        admin: malformed,
        transaction: await validTransaction(),
        orgId: org,
        playerId: player,
        billingUserId: player,
        status: "active",
      }),
  );
});

Deno.test("corrective migration uses real Apple subscription columns", async () => {
  const sql = await Deno.readTextFile(
    new URL(
      "../../../supabase/migrations/20260714020000_apple_subscription_atomic_sync.sql",
      import.meta.url,
    ),
  );
  for (
    const column of [
      "provider_transaction_id",
      "original_transaction_id",
      "provider_subscription_id",
      "provider_product_id",
      "current_period_start",
      "current_period_end",
    ]
  ) assert(sql.includes(column), `Migration must reference ${column}`);
  assert(
    sql.includes("pg_advisory_xact_lock"),
    "Replay guards must serialize lineage writes",
  );
  assert(
    sql.includes("sd_sync_apple_player_subscription"),
    "Atomic RPC must exist",
  );
});
