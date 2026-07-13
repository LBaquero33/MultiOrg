import {
  Environment,
  SignedDataVerifier,
  VerificationException,
  VerificationStatus,
} from "@apple/app-store-server-library";
import {
  createHmac,
  timingSafeEqual,
  X509Certificate,
} from "node:crypto";

const PRODUCT_ID = "com.homeplate.player.monthly";
const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const NONCE_PATTERN = /^[A-Za-z0-9_-]{16,128}$/;

function requiredEnv(name) {
  const value = String(process.env[name] ?? "").trim();
  if (!value) throw new Error(`missing_configuration:${name}`);
  return value;
}

function parseRoots(raw) {
  let values;
  try {
    values = JSON.parse(raw);
  } catch {
    throw new Error("apple_root_configuration_invalid");
  }
  if (!Array.isArray(values) || values.length === 0) {
    throw new Error("apple_root_configuration_invalid");
  }
  try {
    return values.map((value) => {
      if (typeof value !== "string" || !value.trim()) throw new Error();
      const bytes = Buffer.from(value, "base64");
      new X509Certificate(bytes);
      return bytes;
    });
  } catch {
    throw new Error("apple_root_configuration_invalid");
  }
}

function onlineChecks(environment) {
  if (environment === Environment.PRODUCTION) return true;
  return String(process.env.APPLE_ENABLE_ONLINE_CHECKS ?? "true").toLowerCase() !== "false";
}

export function createAppleVerifierFromEnvironment() {
  const bundleId = requiredEnv("APPLE_BUNDLE_ID");
  const environmentName = requiredEnv("APPLE_ENVIRONMENT").toLowerCase();
  if (!["sandbox", "production"].includes(environmentName)) {
    throw new Error("apple_environment_configuration_invalid");
  }
  const environment = environmentName === "production"
    ? Environment.PRODUCTION
    : Environment.SANDBOX;
  const appAppleId = environment === Environment.PRODUCTION
    ? Number(requiredEnv("APPLE_APP_APPLE_ID"))
    : undefined;
  if (environment === Environment.PRODUCTION && !Number.isSafeInteger(appAppleId)) {
    throw new Error("apple_app_id_configuration_invalid");
  }
  const roots = parseRoots(requiredEnv("APPLE_ROOT_CA_CERTIFICATES_BASE64"));
  return {
    bundleId,
    environmentName,
    verifier: new SignedDataVerifier(
      roots,
      onlineChecks(environment),
      environment,
      bundleId,
      appAppleId,
    ),
  };
}

function safeVerificationCode(error) {
  if (error instanceof VerificationException) {
    switch (error.status) {
      case VerificationStatus.INVALID_APP_IDENTIFIER:
        return "apple_bundle_id_mismatch";
      case VerificationStatus.INVALID_ENVIRONMENT:
        return "apple_environment_mismatch";
      case VerificationStatus.INVALID_CHAIN_LENGTH:
      case VerificationStatus.INVALID_CERTIFICATE:
        return "apple_certificate_chain_invalid";
      case VerificationStatus.RETRYABLE_VERIFICATION_FAILURE:
        return "apple_verification_temporarily_unavailable";
      default:
        return "apple_signature_or_chain_invalid";
    }
  }
  return "apple_verifier_runtime_failed";
}

function constantTimeTokenMatch(actual, expected) {
  const left = Buffer.from(String(actual ?? "").toLowerCase());
  const right = Buffer.from(String(expected ?? "").toLowerCase());
  return left.length === right.length && timingSafeEqual(left, right);
}

export async function verifyTransactionRequest(body, configuration) {
  const signed = typeof body?.signed_transaction_info === "string"
    ? body.signed_transaction_info.trim()
    : "";
  const expectedToken = typeof body?.expected_app_account_token === "string"
    ? body.expected_app_account_token.trim().toLowerCase()
    : "";
  const nonce = typeof body?.request_nonce === "string"
    ? body.request_nonce.trim()
    : "";
  if (!signed || !UUID_PATTERN.test(expectedToken) || !NONCE_PATTERN.test(nonce)) {
    throw new Error("invalid_verification_request");
  }

  let transaction;
  try {
    transaction = await configuration.verifier.verifyAndDecodeTransaction(signed);
  } catch (error) {
    const safe = new Error(safeVerificationCode(error));
    safe.cause = error;
    throw safe;
  }

  if (String(transaction.bundleId ?? "") !== configuration.bundleId) {
    throw new Error("apple_bundle_id_mismatch");
  }
  if (String(transaction.environment ?? "").toLowerCase() !== configuration.environmentName) {
    throw new Error("apple_environment_mismatch");
  }
  if (String(transaction.productId ?? "") !== PRODUCT_ID) {
    throw new Error("apple_product_id_mismatch");
  }
  if (!constantTimeTokenMatch(transaction.appAccountToken, expectedToken)) {
    throw new Error("apple_app_account_token_mismatch");
  }
  if (!transaction.transactionId || !transaction.originalTransactionId) {
    throw new Error("apple_transaction_invalid");
  }

  return {
    version: 1,
    request_nonce: nonce,
    verified_at_ms: Date.now(),
    transaction: {
      bundleId: String(transaction.bundleId),
      productId: String(transaction.productId),
      environment: String(transaction.environment),
      appAccountToken: String(transaction.appAccountToken).toLowerCase(),
      transactionId: String(transaction.transactionId),
      originalTransactionId: String(transaction.originalTransactionId),
      purchaseDate: Number(transaction.purchaseDate ?? 0),
      expiresDate: Number(transaction.expiresDate ?? 0),
      revocationDate: Number(transaction.revocationDate ?? 0),
      autoRenewStatus: transaction.autoRenewStatus == null
        ? null
        : Number(transaction.autoRenewStatus),
    },
  };
}

function base64url(value) {
  return Buffer.from(value).toString("base64url");
}

export function signedResponseEnvelope(payload, secret) {
  const payloadBytes = Buffer.from(JSON.stringify(payload));
  const signature = createHmac("sha256", secret).update(payloadBytes).digest();
  return {
    payload: base64url(payloadBytes),
    signature: base64url(signature),
  };
}

export function safeServiceError(error) {
  const allowed = new Set([
    "invalid_verification_request",
    "apple_bundle_id_mismatch",
    "apple_environment_mismatch",
    "apple_product_id_mismatch",
    "apple_app_account_token_mismatch",
    "apple_transaction_invalid",
    "apple_certificate_chain_invalid",
    "apple_signature_or_chain_invalid",
    "apple_verification_temporarily_unavailable",
    "apple_verifier_runtime_failed",
  ]);
  const code = error instanceof Error ? error.message : "";
  return allowed.has(code) ? code : "apple_verifier_service_failed";
}
