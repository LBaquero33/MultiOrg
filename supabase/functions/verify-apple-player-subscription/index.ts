import {
  APPLE_PLAYER_MONTHLY_PRODUCT_ID,
  appleStatus,
  canonicalUuid,
  env,
  expectedAppAccountToken,
  json,
  requireApplePurchaseActor,
  syncAppleSubscription,
  validateAppleTransactionContext,
} from "../_shared/apple_player_subscription.ts";
import {
  inspectAppleCompactJWS,
} from "../_shared/apple_jws_diagnostics.ts";
import {
  APPLE_VERIFIER_GATEWAY_MARKER,
  verifyAppleTransactionWithService,
} from "../_shared/apple_verifier_gateway.ts";

const DEPLOYMENT_MARKER = APPLE_VERIFIER_GATEWAY_MARKER;

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
    "actor_role_not_player",
    "target_profile_missing",
    "target_membership_missing",
    "target_membership_not_active",
    "target_role_not_player",
    "self_target_id_mismatch",
    "parent_link_missing",
    "parent_can_pay_false",
    "organization_context_mismatch",
    "billing_user_id_mismatch",
    "app_account_token_mismatch",
    "bundle_id_mismatch",
    "product_id_mismatch",
    "environment_mismatch",
    "apple_transaction_identifiers_missing",
    "apple_jws_compact_format_invalid",
    "apple_jws_header_decode_failed",
    "apple_jws_alg_invalid",
    "apple_jws_x5c_missing",
    "apple_jws_x5c_decode_failed",
    "apple_jws_certificate_chain_invalid",
    "apple_jws_root_untrusted",
    "apple_jws_signature_invalid",
    "apple_jws_payload_decode_failed",
    "apple_jws_verifier_library_error",
    "apple_transaction_source_local_storekit",
    "apple_bundle_id_mismatch",
    "apple_environment_mismatch",
    "apple_certificate_chain_verification_failed",
    "apple_certificate_extension_validation_failed",
    "apple_certificate_date_validation_failed",
    "apple_ocsp_network_failed",
    "apple_ocsp_response_invalid",
    "apple_jwt_signature_verification_failed",
    "apple_node_crypto_runtime_failed",
    "apple_verifier_unknown_failure",
    "apple_verifier_service_unconfigured",
    "apple_verifier_service_unavailable",
    "apple_verifier_service_rejected",
    "apple_verifier_response_invalid",
    "apple_verifier_response_signature_invalid",
    "apple_verifier_response_expired",
    "apple_verifier_response_nonce_mismatch",
    "apple_signature_or_chain_invalid",
    "apple_verification_temporarily_unavailable",
    "apple_verifier_runtime_failed",
    "subscription_upsert_failed",
    "entitlement_sync_failed",
    "missing_apple_verifier_configuration",
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

    const { admin, actorId } = await requireApplePurchaseActor(
      req,
      orgId,
      playerId,
      billingUserId,
    );
    if (token !== await expectedAppAccountToken(orgId, playerId, actorId)) {
      return json(400, { error: "app_account_token_mismatch" });
    }

    console.info(
      JSON.stringify({
        event: "apple_verification_stage",
        stage: "compact_jws_inspection_started",
        deployment_marker: DEPLOYMENT_MARKER,
      }),
    );
    const inspection = inspectAppleCompactJWS(signed);
    console.info(
      JSON.stringify({
        event: "apple_verification_stage",
        stage: "compact_jws_inspection_passed",
        deployment_marker: DEPLOYMENT_MARKER,
        transaction_environment: inspection.transactionEnvironment,
      }),
    );
    if (["xcode", "localtesting"].includes(inspection.transactionEnvironment)) {
      throw new Error("apple_transaction_source_local_storekit");
    }

    console.info(JSON.stringify({
      event: "apple_remote_verification_started",
      deployment_marker: DEPLOYMENT_MARKER,
    }));
    const transaction = await verifyAppleTransactionWithService(signed, token);
    console.info(JSON.stringify({
      event: "apple_remote_verification_passed",
      deployment_marker: DEPLOYMENT_MARKER,
    }));

    const expectedEnvironment =
      env("APPLE_ENVIRONMENT").toLowerCase() === "production"
        ? "production"
        : "sandbox";
    validateAppleTransactionContext(transaction, {
      bundleId: env("APPLE_BUNDLE_ID"),
      productId: APPLE_PLAYER_MONTHLY_PRODUCT_ID,
      environment: expectedEnvironment,
      appAccountToken: token,
    });

    const result = await syncAppleSubscription({
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
    console.error(
      JSON.stringify({
        event: "apple_player_subscription_verification_failed",
        code,
      }),
    );
    return json(400, { error: code });
  }
});
