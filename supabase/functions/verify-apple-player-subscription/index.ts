import {
  APPLE_PLAYER_MONTHLY_PRODUCT_ID,
  appleStatus,
  appleVerifier,
  canonicalUuid,
  env,
  expectedAppAccountToken,
  json,
  requireApplePurchaseActor,
  syncAppleSubscription,
  validateAppleTransactionContext,
} from "../_shared/apple_player_subscription.ts";

const safeErrorCode = (error: unknown) => {
  const candidate = error instanceof Error ? error.message.split(":", 1)[0] : "apple_verification_failed";
  const allowed = new Set([
    "invalid_purchase_context_payload", "missing_auth", "invalid_auth",
    "actor_profile_missing", "actor_membership_missing", "actor_membership_not_active", "actor_role_not_player",
    "target_profile_missing", "target_membership_missing", "target_membership_not_active", "target_role_not_player",
    "self_target_id_mismatch", "parent_link_missing", "parent_can_pay_false", "organization_context_mismatch",
    "billing_user_id_mismatch", "app_account_token_mismatch", "bundle_id_mismatch", "product_id_mismatch",
    "environment_mismatch", "apple_jws_invalid", "apple_transaction_identifiers_missing",
    "subscription_upsert_failed", "entitlement_sync_failed", "missing_apple_verifier_configuration",
    "apple_authorization_lookup_failed",
  ]);
  return allowed.has(candidate) ? candidate : "apple_verification_failed";
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
    const billingUserId = canonicalUuid(body.billing_user_id);
    const token = canonicalUuid(body.app_account_token);
    const signed = String(body.signed_transaction_info ?? "").trim();
    if (!orgId || !playerId || !billingUserId || !token || !signed) {
      return json(400, { error: "invalid_purchase_context_payload" });
    }

    const { admin, actorId } = await requireApplePurchaseActor(req, orgId, playerId, billingUserId);
    if (token !== await expectedAppAccountToken(orgId, playerId, actorId)) {
      return json(400, { error: "app_account_token_mismatch" });
    }

    const verifier: any = await appleVerifier();
    let transaction: any;
    try {
      transaction = await verifier.verifyAndDecodeTransaction(signed);
    } catch {
      throw new Error("apple_jws_invalid");
    }

    const expectedEnvironment = env("APPLE_ENVIRONMENT").toLowerCase() === "production" ? "production" : "sandbox";
    validateAppleTransactionContext(transaction, {
      bundleId: env("APPLE_BUNDLE_ID"),
      productId: APPLE_PLAYER_MONTHLY_PRODUCT_ID,
      environment: expectedEnvironment,
      appAccountToken: token,
    });

    const result = await syncAppleSubscription({ admin, transaction, orgId, playerId, billingUserId: actorId, status: appleStatus(transaction) });
    return json(200, result);
  } catch (error) {
    const code = safeErrorCode(error);
    console.error(JSON.stringify({ event: "apple_player_subscription_verification_failed", code }));
    return json(400, { error: code });
  }
});
