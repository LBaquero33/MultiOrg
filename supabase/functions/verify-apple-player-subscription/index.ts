import {
  appleStatus,
  canonicalUuid,
  env,
  expectedAppAccountToken,
  json,
  normalizeStoreKitVerifiedTransaction,
  requireApplePurchaseActor,
  syncAppleSubscriptionAtomically,
  validateAppleTransactionContext,
} from "../_shared/apple_player_subscription.ts";

const DEPLOYMENT_MARKER = "apple_iap_atomic_storekit_verified_20260714_2";

const safeErrorCode = (error: unknown) => {
  const candidate = error instanceof Error
    ? error.message.split(":", 1)[0]
    : "apple_verification_failed";
  const allowed = new Set([
    "invalid_purchase_context_payload",
    "missing_auth",
    "invalid_auth",
    "actor_profile_missing",
    "actor_membership_missing",
    "actor_membership_not_active",
    "actor_role_not_allowed",
    "target_profile_missing",
    "target_membership_missing",
    "target_membership_not_active",
    "target_role_not_player",
    "parent_link_missing",
    "parent_can_pay_false",
    "organization_context_mismatch",
    "app_account_token_mismatch",
    "bundle_id_mismatch",
    "product_id_mismatch",
    "environment_mismatch",
    "apple_transaction_identifiers_missing",
    "apple_transaction_invalid",
    "apple_transaction_replay",
    "apple_authorization_lookup_failed",
    "apple_transaction_reassigned",
    "apple_original_transaction_reassigned",
    "apple_transaction_lineage_conflict",
    "apple_transaction_context_mismatch",
    "apple_transaction_replay_conflict",
    "player_subscription_context_conflict",
    "apple_subscription_atomic_sync_failed",
    "apple_subscription_server_not_configured",
  ]);
  return allowed.has(candidate) ? candidate : "apple_verification_failed";
};

const statusForCode = (code: string) => {
  if (["missing_auth", "invalid_auth"].includes(code)) return 401;
  if (
    code.startsWith("actor_") || code.startsWith("target_") ||
    code.startsWith("parent_") || code === "organization_context_mismatch"
  ) return 403;
  if (
    code.includes("replay") || code.includes("reassigned") ||
    code.includes("lineage_conflict") ||
    code === "player_subscription_context_conflict"
  ) return 409;
  if (
    code === "apple_subscription_atomic_sync_failed" ||
    code === "apple_subscription_server_not_configured" ||
    code === "apple_authorization_lookup_failed"
  ) return 500;
  return 400;
};

Deno.serve(async (req) => {
  if (req.method !== "POST") return json(405, { error: "method_not_allowed" });
  try {
    let body: Record<string, unknown>;
    try {
      body = await req.json();
    } catch {
      return json(400, { error: "invalid_purchase_context_payload" });
    }

    const orgId = canonicalUuid(body.org_id);
    const playerId = canonicalUuid(body.player_id);
    const token = canonicalUuid(body.app_account_token);
    if (!orgId || !playerId || !token) {
      return json(400, { error: "invalid_purchase_context_payload" });
    }

    const { admin, actorId } = await requireApplePurchaseActor(
      req,
      orgId,
      playerId,
    );
    if (token !== await expectedAppAccountToken(orgId, playerId, actorId)) {
      throw new Error("app_account_token_mismatch");
    }

    const expectedEnvironment = env("APPLE_ENVIRONMENT").toLowerCase();
    const expectedBundleId = env("APPLE_BUNDLE_ID");
    if (
      !expectedBundleId ||
      !["sandbox", "production"].includes(expectedEnvironment)
    ) {
      throw new Error("apple_subscription_server_not_configured");
    }
    const transaction = normalizeStoreKitVerifiedTransaction(body, {
      bundleId: expectedBundleId,
      environment: expectedEnvironment,
      appAccountToken: token,
    });
    validateAppleTransactionContext(transaction, {
      bundleId: expectedBundleId,
      productId: "com.homeplate.player.monthly",
      environment: expectedEnvironment,
      appAccountToken: token,
    });

    console.info(JSON.stringify({
      event: "storekit_verified_metadata_accepted",
      deployment_marker: DEPLOYMENT_MARKER,
    }));
    const result = await syncAppleSubscriptionAtomically({
      admin,
      transaction,
      orgId,
      playerId,
      billingUserId: actorId,
      status: appleStatus(transaction),
    });
    return json(200, result);
  } catch (error) {
    const code = safeErrorCode(error);
    console.error(JSON.stringify({
      event: "apple_player_subscription_verification_failed",
      deployment_marker: DEPLOYMENT_MARKER,
      code,
    }));
    return json(statusForCode(code), { error: code });
  }
});
