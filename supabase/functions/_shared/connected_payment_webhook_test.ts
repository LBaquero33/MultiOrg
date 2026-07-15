import {
  type ConnectedPaymentWebhookStore,
  createConnectedPaymentWebhookHandler,
  type ReconcileInput,
  type ReconcileResult,
} from "./connected_payment_webhook.ts";

function assert(condition: boolean, message: string) {
  if (!condition) throw new Error(message);
}

function assertEqual<T>(actual: T, expected: T, message: string) {
  if (actual !== expected) {
    throw new Error(`${message}: expected ${expected}, received ${actual}`);
  }
}

const attemptId = "11111111-1111-4111-8111-111111111111";
const orgId = "22222222-2222-4222-8222-222222222222";
const requestId = "33333333-3333-4333-8333-333333333333";
const childId = "44444444-4444-4444-8444-444444444444";

class MemoryWebhookStore implements ConnectedPaymentWebhookStore {
  duplicate = false;
  reconcileCalls: ReconcileInput[] = [];
  reconciled: ReconcileResult = {
    kind: "paid",
    payment_request_id: requestId,
    payment_id: "payment-1",
  };
  reconcileError: string | null = null;
  completeCount = 0;
  failedCodes: string[] = [];
  expired: string[] = [];

  claim() {
    return Promise.resolve(
      this.duplicate
        ? { kind: "duplicate" as const }
        : { kind: "claimed" as const, ledgerId: "ledger-1" },
    );
  }
  complete() {
    this.completeCount += 1;
    return Promise.resolve();
  }
  fail(_id: string, code: string) {
    this.failedCodes.push(code);
    return Promise.resolve();
  }
  reconcile(input: ReconcileInput) {
    this.reconcileCalls.push(input);
    if (this.reconcileError) throw new Error(this.reconcileError);
    return Promise.resolve(this.reconciled);
  }
  expireAttempt(id: string) {
    this.expired.push(id);
    return Promise.resolve();
  }
}

function checkoutEvent(overrides: Record<string, unknown> = {}) {
  return {
    id: "evt_checkout",
    type: "checkout.session.completed",
    account: "acct_organization",
    created: 1_800_000_000,
    data: {
      object: {
        id: "cs_homeplate",
        payment_status: "paid",
        payment_intent: "pi_homeplate",
        amount_total: 5000,
        currency: "usd",
        metadata: {
          home_plate_checkout_attempt_id: attemptId,
          home_plate_org_id: orgId,
          home_plate_payment_request_id: requestId,
          home_plate_child_id: childId,
        },
        ...overrides,
      },
    },
  };
}

function paymentIntentEvent(overrides: Record<string, unknown> = {}) {
  return {
    id: "evt_intent",
    type: "payment_intent.succeeded",
    account: "acct_organization",
    created: 1_800_000_001,
    data: {
      object: {
        id: "pi_homeplate",
        amount_received: 5000,
        currency: "usd",
        latest_charge: "ch_homeplate",
        metadata: {
          home_plate_checkout_attempt_id: attemptId,
          home_plate_org_id: orgId,
          home_plate_payment_request_id: requestId,
          home_plate_child_id: childId,
        },
        ...overrides,
      },
    },
  };
}

function request(event: Record<string, unknown>, signature = "valid") {
  return new Request(
    "https://example.com/functions/v1/stripe-connected-payments-webhook",
    {
      method: "POST",
      headers: { "Stripe-Signature": signature },
      body: JSON.stringify(event),
    },
  );
}

function handler(store: MemoryWebhookStore, validSignature = true) {
  return createConnectedPaymentWebhookHandler({
    signingSecretConfigured: true,
    verifySignature: () => Promise.resolve(validSignature),
    store,
  });
}

Deno.test("connected payment webhook rejects missing and invalid signatures", async () => {
  const store = new MemoryWebhookStore();
  const missing = new Request("https://example.com", {
    method: "POST",
    body: "{}",
  });
  assertEqual((await handler(store)(missing)).status, 400, "missing signature");
  assertEqual(
    (await handler(store, false)(request(checkoutEvent()))).status,
    400,
    "invalid signature",
  );
});

Deno.test("verified paid Checkout reconciles exactly one payment request", async () => {
  const store = new MemoryWebhookStore();
  const response = await handler(store)(request(checkoutEvent()));
  assertEqual(response.status, 200, "Checkout success response");
  assertEqual(store.reconcileCalls.length, 1, "reconcile count");
  assertEqual(
    store.reconcileCalls[0].stripeAccountId,
    "acct_organization",
    "connected account",
  );
  assertEqual(
    store.reconcileCalls[0].paymentRequestId,
    requestId,
    "payment request ID",
  );
  assertEqual(store.reconcileCalls[0].amountCents, 5000, "amount");
  assertEqual(store.completeCount, 1, "ledger completion");
});

Deno.test("payment_intent.succeeded is independently reconcilable and includes charge", async () => {
  const store = new MemoryWebhookStore();
  const response = await handler(store)(request(paymentIntentEvent()));
  assertEqual(response.status, 200, "PaymentIntent status");
  assertEqual(
    store.reconcileCalls[0].paymentIntentId,
    "pi_homeplate",
    "intent ID",
  );
  assertEqual(store.reconcileCalls[0].chargeId, "ch_homeplate", "charge ID");
});

Deno.test("checkout redirect or unpaid completion never marks a request paid", async () => {
  const store = new MemoryWebhookStore();
  const response = await handler(store)(
    request(checkoutEvent({ payment_status: "unpaid" })),
  );
  assertEqual(response.status, 200, "unpaid completion status");
  assertEqual(
    store.reconcileCalls.length,
    0,
    "unpaid completion reconciliation",
  );
  assertEqual(
    (await response.json()).outcome,
    "awaiting_payment_confirmation",
    "unpaid outcome",
  );
});

Deno.test("duplicate webhook event is idempotent", async () => {
  const store = new MemoryWebhookStore();
  store.duplicate = true;
  const response = await handler(store)(request(paymentIntentEvent()));
  assertEqual(response.status, 200, "duplicate status");
  assertEqual((await response.json()).duplicate, true, "duplicate marker");
  assertEqual(store.reconcileCalls.length, 0, "duplicate reconciliation count");
});

Deno.test("wrong account, organization, amount, and currency are quarantined", async () => {
  for (
    const code of [
      "checkout_attempt_not_found",
      "payment_amount_mismatch",
      "payment_currency_mismatch",
    ]
  ) {
    const store = new MemoryWebhookStore();
    store.reconcileError = code;
    const response = await handler(store)(request(paymentIntentEvent()));
    assertEqual(response.status, 200, `${code} response`);
    assertEqual((await response.json()).anomaly, true, `${code} anomaly`);
    assertEqual(store.failedCodes[0], code, `${code} ledger code`);
  }
});

Deno.test("verified events with invalid internal metadata are quarantined", async () => {
  const store = new MemoryWebhookStore();
  const response = await handler(store)(request(paymentIntentEvent({
    metadata: { home_plate_org_id: "not-a-uuid" },
  })));
  assertEqual(response.status, 200, "invalid metadata response");
  assertEqual(
    (await response.json()).anomaly,
    true,
    "invalid metadata anomaly",
  );
  assertEqual(
    store.failedCodes[0],
    "payment_metadata_invalid",
    "invalid metadata ledger code",
  );
  assertEqual(
    store.reconcileCalls.length,
    0,
    "invalid metadata reconciliation",
  );
});

Deno.test("canceled request success is an anomaly and is not silently overwritten", async () => {
  const store = new MemoryWebhookStore();
  store.reconciled = {
    kind: "canceled_request_anomaly",
    payment_request_id: requestId,
    attempt_id: attemptId,
  };
  const response = await handler(store)(request(paymentIntentEvent()));
  assertEqual((await response.json()).anomaly, true, "canceled anomaly marker");
});

Deno.test("duplicate successful payment anomaly does not become a second payment", async () => {
  const store = new MemoryWebhookStore();
  store.reconciled = {
    kind: "duplicate_payment_anomaly",
    payment_request_id: requestId,
    attempt_id: attemptId,
  };
  const response = await handler(store)(request(paymentIntentEvent()));
  assertEqual(
    (await response.json()).anomaly,
    true,
    "duplicate payment anomaly marker",
  );
  assertEqual(store.reconcileCalls.length, 1, "single reconciliation call");
});

Deno.test("failed PaymentIntent and expired Checkout never mark a request paid", async () => {
  const failedStore = new MemoryWebhookStore();
  const failed = paymentIntentEvent();
  failed.type = "payment_intent.payment_failed";
  const failedResponse = await handler(failedStore)(request(failed));
  assertEqual(failedResponse.status, 200, "failed intent status");
  assertEqual(
    failedStore.reconcileCalls.length,
    0,
    "failed intent reconciliation",
  );

  const expiredStore = new MemoryWebhookStore();
  const expired = checkoutEvent();
  expired.type = "checkout.session.expired";
  const expiredResponse = await handler(expiredStore)(request(expired));
  assertEqual(expiredResponse.status, 200, "expired session status");
  assertEqual(expiredStore.expired[0], attemptId, "expired attempt");
  assertEqual(expiredStore.reconcileCalls.length, 0, "expired reconciliation");
});

Deno.test("out-of-order duplicate success result does not regress paid state", async () => {
  const store = new MemoryWebhookStore();
  store.reconciled = {
    kind: "duplicate",
    payment_request_id: requestId,
    payment_id: "payment-1",
  };
  const response = await handler(store)(request(checkoutEvent()));
  assertEqual(response.status, 200, "out-of-order duplicate status");
  assertEqual(
    (await response.json()).outcome,
    "duplicate",
    "out-of-order outcome",
  );
});

Deno.test("production webhook claim uses a bounded optimistic processing lease", async () => {
  const source = await Deno.readTextFile(
    new URL(
      "../stripe-connected-payments-webhook/index.ts",
      import.meta.url,
    ),
  );
  assert(
    source.includes("Date.now() - 5 * 60 * 1000"),
    "five-minute stale-processing lease",
  );
  assert(
    source.includes(
      '.eq("attempt_count", Number(existing.attempt_count ?? 0))',
    ),
    "optimistic attempt-count claim",
  );
  assert(
    source.includes("received_at: new Date().toISOString()"),
    "processing lease refresh",
  );
});
