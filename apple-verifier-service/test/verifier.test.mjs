import assert from "node:assert/strict";
import fs from "node:fs";
import test from "node:test";
import {
  Environment,
  SignedDataVerifier,
} from "@apple/app-store-server-library";
import {
  signedResponseEnvelope,
  verifyTransactionRequest,
} from "../src/verifier.mjs";

const fixtureRoot = new URL(
  "../../supabase/functions/_shared/test_fixtures/apple/",
  import.meta.url,
);
const validRoot = fs.readFileSync(new URL("testCA.der", fixtureRoot));
const wrongRoot = fs.readFileSync(new URL("AppleRootCA-G3.cer", fixtureRoot));
const validJWS = fs.readFileSync(
  new URL("transactionInfo.jws", fixtureRoot),
  "utf8",
).trim();

test("Apple official verifier accepts its valid signed fixture", async () => {
  const verifier = new SignedDataVerifier(
    [validRoot],
    false,
    Environment.SANDBOX,
    "com.example",
  );
  const transaction = await verifier.verifyAndDecodeTransaction(validJWS);
  assert.equal(transaction.bundleId, "com.example");
  assert.equal(transaction.environment, Environment.SANDBOX);
});

test("Apple official verifier rejects an untrusted certificate root", async () => {
  const verifier = new SignedDataVerifier(
    [wrongRoot],
    false,
    Environment.SANDBOX,
    "com.example",
  );
  await assert.rejects(() => verifier.verifyAndDecodeTransaction(validJWS));
});

test("Apple official verifier rejects a modified JWS signature", async () => {
  const verifier = new SignedDataVerifier(
    [validRoot],
    false,
    Environment.SANDBOX,
    "com.example",
  );
  const parts = validJWS.split(".");
  const last = parts[2].at(-1) === "A" ? "B" : "A";
  parts[2] = parts[2].slice(0, -1) + last;
  await assert.rejects(() => verifier.verifyAndDecodeTransaction(parts.join(".")));
});

test("service validates the complete expected transaction context", async () => {
  const token = "123e4567-e89b-52d3-a456-426614174000";
  const payload = await verifyTransactionRequest(
    {
      signed_transaction_info: "header.payload.signature",
      expected_app_account_token: token,
      request_nonce: "0123456789abcdef0123456789abcdef",
    },
    {
      bundleId: "com.homeplate.app",
      environmentName: "sandbox",
      verifier: {
        verifyAndDecodeTransaction: async () => ({
          bundleId: "com.homeplate.app",
          environment: "Sandbox",
          productId: "com.homeplate.player.monthly",
          appAccountToken: token,
          transactionId: "1000000000000001",
          originalTransactionId: "1000000000000001",
          purchaseDate: 1,
          expiresDate: 2,
        }),
      },
    },
  );
  assert.equal(payload.transaction.appAccountToken, token);
  assert.equal(payload.transaction.productId, "com.homeplate.player.monthly");
});

test("service rejects an appAccountToken mismatch", async () => {
  await assert.rejects(
    () => verifyTransactionRequest(
      {
        signed_transaction_info: "header.payload.signature",
        expected_app_account_token: "123e4567-e89b-52d3-a456-426614174000",
        request_nonce: "0123456789abcdef0123456789abcdef",
      },
      {
        bundleId: "com.homeplate.app",
        environmentName: "sandbox",
        verifier: {
          verifyAndDecodeTransaction: async () => ({
            bundleId: "com.homeplate.app",
            environment: "Sandbox",
            productId: "com.homeplate.player.monthly",
            appAccountToken: "123e4567-e89b-52d3-a456-426614174001",
            transactionId: "1",
            originalTransactionId: "1",
          }),
        },
      },
    ),
    /apple_app_account_token_mismatch/,
  );
});

test("service response envelope is HMAC authenticated", () => {
  const envelope = signedResponseEnvelope(
    { version: 1, request_nonce: "nonce" },
    "a-secure-test-secret-that-is-long-enough",
  );
  assert.match(envelope.payload, /^[A-Za-z0-9_-]+$/);
  assert.match(envelope.signature, /^[A-Za-z0-9_-]+$/);
  assert.notEqual(envelope.payload, envelope.signature);
});
