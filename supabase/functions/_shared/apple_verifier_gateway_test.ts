import {
  assertEquals,
  assertRejects,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import { verifyAppleTransactionWithService } from "./apple_verifier_gateway.ts";

const secret = "a-secure-response-secret-that-is-long-enough";
const nonce = "0123456789abcdef0123456789abcdef";
const now = 1_800_000_000_000;

function base64url(value: Uint8Array) {
  let binary = "";
  for (const byte of value) binary += String.fromCharCode(byte);
  return btoa(binary).replaceAll("+", "-").replaceAll("/", "_").replace(/=+$/, "");
}

async function envelope(overrides: Record<string, unknown> = {}) {
  const payload = new TextEncoder().encode(JSON.stringify({
    version: 1,
    request_nonce: nonce,
    verified_at_ms: now,
    transaction: {
      bundleId: "com.homeplate.app",
      productId: "com.homeplate.player.monthly",
      environment: "Sandbox",
      appAccountToken: "123e4567-e89b-52d3-a456-426614174000",
      transactionId: "1",
      originalTransactionId: "1",
      purchaseDate: 1,
      expiresDate: 2,
      revocationDate: 0,
      autoRenewStatus: null,
    },
    ...overrides,
  }));
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = new Uint8Array(await crypto.subtle.sign("HMAC", key, payload));
  return { payload: base64url(payload), signature: base64url(signature) };
}

function options(body: Record<string, unknown>) {
  return {
    serviceUrl: "https://verifier.example",
    requestToken: "a-secure-request-token-that-is-long-enough",
    responseSecret: secret,
    nonce,
    now,
    fetcher: () => Promise.resolve(new Response(JSON.stringify(body), {
      status: 200,
      headers: { "content-type": "application/json" },
    })),
  };
}

Deno.test("gateway accepts a fresh signed response with matching nonce", async () => {
  const transaction = await verifyAppleTransactionWithService(
    "header.payload.signature",
    "123e4567-e89b-52d3-a456-426614174000",
    options(await envelope()),
  );
  assertEquals(transaction.productId, "com.homeplate.player.monthly");
});

Deno.test("gateway rejects a forged response signature", async () => {
  const valid = await envelope();
  valid.signature = valid.signature.slice(0, -1) + (valid.signature.endsWith("A") ? "B" : "A");
  await assertRejects(
    () => verifyAppleTransactionWithService("jws", "token", options(valid)),
    Error,
    "apple_verifier_response_signature_invalid",
  );
});

Deno.test("gateway rejects a nonce mismatch", async () => {
  const mismatched = await envelope({
    request_nonce: "fedcba9876543210fedcba9876543210",
  });
  await assertRejects(
    () => verifyAppleTransactionWithService(
      "jws",
      "token",
      options(mismatched),
    ),
    Error,
    "apple_verifier_response_nonce_mismatch",
  );
});

Deno.test("gateway rejects a stale verified response", async () => {
  const stale = await envelope({ verified_at_ms: now - 120_001 });
  await assertRejects(
    () => verifyAppleTransactionWithService(
      "jws",
      "token",
      options(stale),
    ),
    Error,
    "apple_verifier_response_expired",
  );
});
