const encoder = new TextEncoder();
const decoder = new TextDecoder();

export const APPLE_VERIFIER_GATEWAY_MARKER =
  "apple_iap_node_verifier_gateway_20260713_1";

const allowedServiceErrors = new Set([
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

export type VerifiedAppleTransaction = {
  bundleId: string;
  productId: string;
  environment: string;
  appAccountToken: string;
  transactionId: string;
  originalTransactionId: string;
  purchaseDate: number;
  expiresDate: number;
  revocationDate: number;
  autoRenewStatus: number | null;
};

type GatewayOptions = {
  serviceUrl?: string;
  requestToken?: string;
  responseSecret?: string;
  fetcher?: typeof fetch;
  nonce?: string;
  now?: number;
};

function required(value: string | undefined, code: string) {
  const result = String(value ?? "").trim();
  if (!result) throw new Error(code);
  return result;
}

function requiredSecret(value: string | undefined) {
  const result = required(value, "apple_verifier_service_unconfigured");
  if (result.length < 32) {
    throw new Error("apple_verifier_service_unconfigured");
  }
  return result;
}

function decodeBase64Url(value: string) {
  if (!/^[A-Za-z0-9_-]+$/.test(value)) {
    throw new Error("apple_verifier_response_invalid");
  }
  const padded = value.replaceAll("-", "+").replaceAll("_", "/") +
    "=".repeat((4 - value.length % 4) % 4);
  try {
    return Uint8Array.from(atob(padded), (character) => character.charCodeAt(0));
  } catch {
    throw new Error("apple_verifier_response_invalid");
  }
}

async function verifyEnvelopeSignature(
  payload: Uint8Array,
  signature: Uint8Array,
  secret: string,
) {
  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["verify"],
  );
  return await crypto.subtle.verify(
    "HMAC",
    key,
    signature.buffer as ArrayBuffer,
    payload.buffer as ArrayBuffer,
  );
}

function validateTransaction(value: unknown): VerifiedAppleTransaction {
  const transaction = value as Record<string, unknown> | null;
  const strings = [
    "bundleId",
    "productId",
    "environment",
    "appAccountToken",
    "transactionId",
    "originalTransactionId",
  ];
  if (!transaction || strings.some((key) => typeof transaction[key] !== "string")) {
    throw new Error("apple_verifier_response_invalid");
  }
  for (const key of ["purchaseDate", "expiresDate", "revocationDate"]) {
    if (typeof transaction[key] !== "number" || !Number.isFinite(transaction[key])) {
      throw new Error("apple_verifier_response_invalid");
    }
  }
  return transaction as VerifiedAppleTransaction;
}

export async function verifyAppleTransactionWithService(
  signedTransactionInfo: string,
  expectedAppAccountToken: string,
  options: GatewayOptions = {},
): Promise<VerifiedAppleTransaction> {
  const serviceUrl = required(
    options.serviceUrl ?? Deno.env.get("APPLE_VERIFIER_SERVICE_URL"),
    "apple_verifier_service_unconfigured",
  ).replace(/\/$/, "");
  let parsedServiceUrl: URL;
  try {
    parsedServiceUrl = new URL(serviceUrl);
  } catch {
    throw new Error("apple_verifier_service_unconfigured");
  }
  if (parsedServiceUrl.protocol !== "https:") {
    throw new Error("apple_verifier_service_unconfigured");
  }
  const requestToken = requiredSecret(
    options.requestToken ?? Deno.env.get("APPLE_VERIFIER_SERVICE_TOKEN"),
  );
  const responseSecret = requiredSecret(
    options.responseSecret ?? Deno.env.get("APPLE_VERIFIER_RESPONSE_HMAC_SECRET"),
  );
  const nonce = options.nonce ?? crypto.randomUUID().replaceAll("-", "");
  const now = options.now ?? Date.now();
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 12_000);
  let response: Response;
  try {
    response = await (options.fetcher ?? fetch)(
      `${serviceUrl}/v1/verify-transaction`,
      {
        method: "POST",
        headers: {
          authorization: `Bearer ${requestToken}`,
          "content-type": "application/json",
        },
        body: JSON.stringify({
          signed_transaction_info: signedTransactionInfo,
          expected_app_account_token: expectedAppAccountToken,
          request_nonce: nonce,
        }),
        signal: controller.signal,
      },
    );
  } catch {
    throw new Error("apple_verifier_service_unavailable");
  } finally {
    clearTimeout(timeout);
  }

  let envelope: Record<string, unknown>;
  try {
    envelope = await response.json();
  } catch {
    throw new Error("apple_verifier_response_invalid");
  }
  if (!response.ok) {
    const code = String(envelope.error ?? "");
    throw new Error(
      allowedServiceErrors.has(code) ? code : "apple_verifier_service_rejected",
    );
  }

  const encodedPayload = String(envelope.payload ?? "");
  const encodedSignature = String(envelope.signature ?? "");
  const payloadBytes = decodeBase64Url(encodedPayload);
  const signatureBytes = decodeBase64Url(encodedSignature);
  if (
    !await verifyEnvelopeSignature(payloadBytes, signatureBytes, responseSecret)
  ) {
    throw new Error("apple_verifier_response_signature_invalid");
  }

  let payload: Record<string, unknown>;
  try {
    payload = JSON.parse(decoder.decode(payloadBytes));
  } catch {
    throw new Error("apple_verifier_response_invalid");
  }
  if (payload.version !== 1 || payload.request_nonce !== nonce) {
    throw new Error("apple_verifier_response_nonce_mismatch");
  }
  const verifiedAt = Number(payload.verified_at_ms);
  if (
    !Number.isFinite(verifiedAt) || verifiedAt < now - 120_000 ||
    verifiedAt > now + 30_000
  ) {
    throw new Error("apple_verifier_response_expired");
  }
  return validateTransaction(payload.transaction);
}
