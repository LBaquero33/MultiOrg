import {
  type CheckoutConnectedAccount,
  type CheckoutMembership,
  type CheckoutOrganization,
  type CheckoutParentLink,
  type CheckoutPaymentRequest,
  type ConnectedCheckoutGateway,
  createPaymentRequestCheckoutHandler,
  PaymentCheckoutError,
  type PaymentCheckoutStore,
  type PreparedCheckoutAttempt,
  type StripeHostedCheckout,
} from "./payment_checkout.ts";
import {
  checkoutForm,
  createConnectedStripeCheckoutGateway,
} from "./stripe_connected_payments.ts";

function assert(condition: boolean, message: string) {
  if (!condition) throw new Error(message);
}

function assertEqual<T>(actual: T, expected: T, message: string) {
  if (actual !== expected) {
    throw new Error(`${message}: expected ${expected}, received ${actual}`);
  }
}

const orgId = "11111111-1111-4111-8111-111111111111";
const requestId = "22222222-2222-4222-8222-222222222222";
const playerId = "33333333-3333-4333-8333-333333333333";
const parentId = "44444444-4444-4444-8444-444444444444";
const actorId = "55555555-5555-4555-8555-555555555555";
const attemptId = "66666666-6666-4666-8666-666666666666";

class MemoryStore implements PaymentCheckoutStore {
  actor: string | null = playerId;
  request: CheckoutPaymentRequest | null = {
    id: requestId,
    request_batch_id: null,
    org_id: orgId,
    child_id: playerId,
    title: "Summer training",
    notes: "July session",
    amount_cents: 5_000,
    currency: "usd",
    status: "open",
  };
  org: CheckoutOrganization | null = {
    id: orgId,
    name: "Home Plate Academy",
    status: "active",
  };
  memberships = new Map<string, CheckoutMembership>([
    [`${orgId}:${playerId}`, { role: "player", status: "active" }],
  ]);
  links = new Map<string, CheckoutParentLink>();
  account: CheckoutConnectedAccount | null = {
    org_id: orgId,
    provider: "stripe",
    provider_account_id: "acct_organization",
    onboarding_status: "ready",
    details_submitted: true,
    charges_enabled: true,
    payouts_enabled: true,
    disabled_reason: null,
    requirements_currently_due: [],
    requirements_past_due: [],
  };
  attempt: PreparedCheckoutAttempt | null = null;
  prepareCount = 0;
  finalizeCount = 0;
  finishStatuses: string[] = [];
  stripeKey = "homeplate_checkout_v1_stable";

  authenticate(request: Request) {
    return Promise.resolve(
      request.headers.has("Authorization") ? this.actor : null,
    );
  }
  paymentRequest(id: string) {
    return Promise.resolve(id === this.request?.id ? this.request : null);
  }
  organization(id: string) {
    return Promise.resolve(id === this.org?.id ? this.org : null);
  }
  membership(org: string, user: string) {
    return Promise.resolve(this.memberships.get(`${org}:${user}`) ?? null);
  }
  parentLink(org: string, parent: string, child: string) {
    return Promise.resolve(this.links.get(`${org}:${parent}:${child}`) ?? null);
  }
  connectedAccount(id: string) {
    return Promise.resolve(id === this.account?.org_id ? this.account : null);
  }
  prepareCheckout(actor: string, paymentRequest: string, _fee: number) {
    this.prepareCount += 1;
    if (!this.attempt) {
      this.attempt = {
        attempt_id: attemptId,
        org_id: orgId,
        payment_request_id: paymentRequest,
        payer_user_id: actor,
        child_id: playerId,
        authorization_source: actor === playerId
          ? "player_self"
          : "linked_parent",
        stripe_account_id: "acct_organization",
        stripe_checkout_session_id: null,
        stripe_idempotency_key: this.stripeKey,
        amount_cents: 5_000,
        currency: "usd",
        application_fee_amount_cents: 0,
        fee_policy_version: "home_plate_fee_bps_v1:0",
        expires_at: "2026-07-14T18:00:00.000Z",
        reused: false,
      };
    } else {
      this.attempt = { ...this.attempt, reused: true };
    }
    return Promise.resolve(this.attempt);
  }
  finalizeCheckout(_attempt: string, session: StripeHostedCheckout) {
    this.finalizeCount += 1;
    if (this.attempt) {
      this.attempt = {
        ...this.attempt,
        stripe_checkout_session_id: session.id,
      };
    }
    return Promise.resolve();
  }
  finishAttempt(_attempt: string, status: "expired" | "failed") {
    this.finishStatuses.push(status);
    if (status === "expired") this.attempt = null;
    return Promise.resolve();
  }
}

function stripeGateway() {
  let creates = 0;
  let retrieves = 0;
  const keys: string[] = [];
  const session: StripeHostedCheckout = {
    id: "cs_test_homeplate",
    url: "https://checkout.stripe.com/c/pay/test",
    status: "open",
    expires_at: 1_800_000_000,
    payment_intent_id: null,
  };
  const gateway: ConnectedCheckoutGateway = {
    createCheckout(input) {
      creates += 1;
      keys.push(input.idempotencyKey);
      return Promise.resolve(session);
    },
    retrieveCheckout() {
      retrieves += 1;
      return Promise.resolve(session);
    },
  };
  return { gateway, counts: () => ({ creates, retrieves, keys }) };
}

function handler(store: MemoryStore, stripe: ConnectedCheckoutGateway) {
  return createPaymentRequestCheckoutHandler({
    store,
    stripe,
    stripeConfigured: true,
    successUrl: "https://app.homeplate.example/payments/success",
    cancelUrl: "https://app.homeplate.example/payments/cancel",
    feeBasisPoints: 0,
  });
}

function request(
  body: Record<string, unknown> = { payment_request_id: requestId },
  auth = true,
) {
  return new Request(
    "https://example.com/functions/v1/create-payment-request-checkout",
    {
      method: "POST",
      headers: {
        "content-type": "application/json",
        ...(auth ? { Authorization: "Bearer test" } : {}),
      },
      body: JSON.stringify(body),
    },
  );
}

Deno.test("Checkout requires a verified JWT", async () => {
  const store = new MemoryStore();
  const stripe = stripeGateway();
  const response = await handler(store, stripe.gateway)(request({}, false));
  assertEqual(response.status, 400, "malformed body is rejected before auth");
  const unauthenticated = await handler(store, stripe.gateway)(
    request({ payment_request_id: requestId }, false),
  );
  assertEqual(unauthenticated.status, 401, "missing JWT status");
});

Deno.test("player creates Checkout only for their own open request", async () => {
  const store = new MemoryStore();
  const stripe = stripeGateway();
  const response = await handler(store, stripe.gateway)(request());
  assertEqual(response.status, 200, "player Checkout status");
  const body = await response.json();
  assertEqual(
    body.checkout.payment_request_id,
    requestId,
    "response request ID",
  );
  assertEqual(stripe.counts().creates, 1, "Stripe create count");
  assertEqual(store.finalizeCount, 1, "finalize count");
});

Deno.test("player cannot pay another player's request", async () => {
  const store = new MemoryStore();
  store.actor = actorId;
  store.memberships.set(`${orgId}:${actorId}`, {
    role: "player",
    status: "active",
  });
  const response = await handler(store, stripeGateway().gateway)(request());
  assertEqual(response.status, 403, "other player denial");
  assertEqual(
    (await response.json()).error,
    "payer_not_authorized",
    "other player code",
  );
});

Deno.test("linked active parent with can_pay can create Checkout", async () => {
  const store = new MemoryStore();
  store.actor = parentId;
  store.memberships.set(`${orgId}:${parentId}`, {
    role: "parent",
    status: "active",
  });
  store.links.set(`${orgId}:${parentId}:${playerId}`, { can_pay: true });
  const response = await handler(store, stripeGateway().gateway)(request());
  assertEqual(response.status, 200, "authorized parent status");
  assertEqual(
    store.attempt?.authorization_source,
    "linked_parent",
    "parent authorization source",
  );
});

Deno.test("linked parent with can_pay false is denied readably", async () => {
  const store = new MemoryStore();
  store.actor = parentId;
  store.memberships.set(`${orgId}:${parentId}`, {
    role: "parent",
    status: "active",
  });
  store.links.set(`${orgId}:${parentId}:${playerId}`, { can_pay: false });
  const response = await handler(store, stripeGateway().gateway)(request());
  assertEqual(response.status, 403, "parent can_pay false status");
  assertEqual(
    (await response.json()).error,
    "parent_payment_not_allowed",
    "parent can_pay false code",
  );
});

for (
  const [label, role] of [
    ["unrelated parent", "parent"],
    ["coach", "coach"],
    ["owner", "owner"],
    ["organization admin", "admin"],
    ["platform-only admin", "platform_admin"],
  ] as const
) {
  Deno.test(`${label} is not automatically an authorized payer`, async () => {
    const store = new MemoryStore();
    store.actor = actorId;
    if (role !== "platform_admin") {
      store.memberships.set(`${orgId}:${actorId}`, { role, status: "active" });
    }
    const response = await handler(store, stripeGateway().gateway)(request());
    assertEqual(response.status, 403, `${label} status`);
  });
}

Deno.test("unauthorized actors cannot probe payment-request state", async () => {
  const store = new MemoryStore();
  store.actor = actorId;
  if (store.request) store.request = { ...store.request, status: "paid" };
  const response = await handler(store, stripeGateway().gateway)(request());
  assertEqual(response.status, 403, "unauthorized state probe status");
  assertEqual(
    (await response.json()).error,
    "payer_not_authorized",
    "unauthorized state probe code",
  );
});

Deno.test("inactive actor and inactive player are denied", async () => {
  const inactiveActor = new MemoryStore();
  inactiveActor.memberships.set(`${orgId}:${playerId}`, {
    role: "player",
    status: "disabled",
  });
  assertEqual(
    (await handler(inactiveActor, stripeGateway().gateway)(request())).status,
    403,
    "inactive actor status",
  );

  const inactiveChild = new MemoryStore();
  inactiveChild.actor = parentId;
  inactiveChild.memberships.set(`${orgId}:${parentId}`, {
    role: "parent",
    status: "active",
  });
  inactiveChild.memberships.set(`${orgId}:${playerId}`, {
    role: "player",
    status: "disabled",
  });
  inactiveChild.links.set(`${orgId}:${parentId}:${playerId}`, {
    can_pay: true,
  });
  const response = await handler(inactiveChild, stripeGateway().gateway)(
    request(),
  );
  assertEqual(
    (await response.json()).error,
    "active_player_required",
    "inactive child code",
  );
});

for (
  const [status, expected] of [["canceled", "payment_request_not_open"], [
    "paid",
    "payment_already_completed",
  ]] as const
) {
  Deno.test(`${status} request cannot create Checkout`, async () => {
    const store = new MemoryStore();
    if (store.request) store.request = { ...store.request, status };
    const response = await handler(store, stripeGateway().gateway)(request());
    assertEqual((await response.json()).error, expected, `${status} error`);
  });
}

Deno.test("missing request and inactive organization are rejected", async () => {
  const missing = new MemoryStore();
  missing.request = null;
  assertEqual(
    (await handler(missing, stripeGateway().gateway)(request())).status,
    404,
    "missing request",
  );

  const inactive = new MemoryStore();
  if (inactive.org) inactive.org = { ...inactive.org, status: "disabled" };
  assertEqual(
    (await handler(inactive, stripeGateway().gateway)(request())).status,
    409,
    "inactive org",
  );
});

Deno.test("client-controlled payment and Connect fields are rejected", async () => {
  for (
    const field of [
      "amount_cents",
      "stripe_account_id",
      "application_fee_amount",
      "player_id",
      "is_platform_admin",
    ]
  ) {
    const store = new MemoryStore();
    const response = await handler(store, stripeGateway().gateway)(request({
      payment_request_id: requestId,
      [field]: field === "amount_cents" ? 1 : "spoofed",
    }));
    assertEqual(response.status, 400, `${field} status`);
    assertEqual(store.prepareCount, 0, `${field} prepare count`);
  }
});

Deno.test("missing, cross-organization, and not-ready connected accounts fail safely", async () => {
  const missing = new MemoryStore();
  missing.account = null;
  assertEqual(
    (await (await handler(missing, stripeGateway().gateway)(request())).json())
      .error,
    "connected_account_missing",
    "missing account code",
  );

  const crossOrg = new MemoryStore();
  if (crossOrg.account) {
    crossOrg.account = { ...crossOrg.account, org_id: actorId };
  }
  assertEqual(
    (await (await handler(crossOrg, stripeGateway().gateway)(request())).json())
      .error,
    "connected_account_missing",
    "cross-org account code",
  );

  const notReady = new MemoryStore();
  if (notReady.account) {
    notReady.account = { ...notReady.account, charges_enabled: false };
  }
  assertEqual(
    (await (await handler(notReady, stripeGateway().gateway)(request())).json())
      .error,
    "connected_account_not_ready",
    "not-ready account code",
  );
});

Deno.test("double tap reuses one session and one stable Stripe idempotency key", async () => {
  const store = new MemoryStore();
  const stripe = stripeGateway();
  const invoke = handler(store, stripe.gateway);
  assertEqual((await invoke(request())).status, 200, "first status");
  assertEqual((await invoke(request())).status, 200, "second status");
  assertEqual(stripe.counts().creates, 1, "create count");
  assertEqual(stripe.counts().retrieves, 1, "retrieve count");
  assertEqual(stripe.counts().keys[0], store.stripeKey, "stable Stripe key");
});

Deno.test("ambiguous Stripe failure keeps the attempt reusable", async () => {
  const store = new MemoryStore();
  const keys: string[] = [];
  let calls = 0;
  const stripe: ConnectedCheckoutGateway = {
    createCheckout(input) {
      calls += 1;
      keys.push(input.idempotencyKey);
      if (calls === 1) {
        throw new PaymentCheckoutError("checkout_creation_failed", 502, true);
      }
      return Promise.resolve({
        id: "cs_retry",
        url: "https://checkout.stripe.com/c/pay/retry",
        status: "open",
        expires_at: 1_800_000_000,
        payment_intent_id: null,
      });
    },
    retrieveCheckout: () => Promise.reject(new Error("not expected")),
  };
  const invoke = handler(store, stripe);
  assertEqual((await invoke(request())).status, 502, "ambiguous response");
  assertEqual(store.finishStatuses.length, 0, "attempt must stay creating");
  assertEqual((await invoke(request())).status, 200, "retry response");
  assertEqual(keys[0], keys[1], "ambiguous retry key");
});

Deno.test("expired provider session is retired before a controlled new attempt", async () => {
  const store = new MemoryStore();
  await store.prepareCheckout(playerId, requestId, 0);
  if (store.attempt) {
    store.attempt = {
      ...store.attempt,
      stripe_checkout_session_id: "cs_expired",
    };
  }
  let creates = 0;
  const stripe: ConnectedCheckoutGateway = {
    createCheckout() {
      creates += 1;
      return Promise.resolve({
        id: "cs_replacement",
        url: "https://checkout.stripe.com/c/pay/replacement",
        status: "open",
        expires_at: 1_800_000_000,
        payment_intent_id: null,
      });
    },
    retrieveCheckout() {
      return Promise.resolve({
        id: "cs_expired",
        url: null,
        status: "expired",
        expires_at: 1_700_000_000,
        payment_intent_id: null,
      });
    },
  };
  const invoke = handler(store, stripe);
  const expiredResponse = await invoke(request());
  assertEqual(expiredResponse.status, 409, "expired session response");
  assertEqual(store.finishStatuses[0], "expired", "expired attempt status");
  assertEqual((await invoke(request())).status, 200, "replacement response");
  assertEqual(creates, 1, "one replacement session");
});

Deno.test("prepared idempotency material mismatch fails closed", async () => {
  const store = new MemoryStore();
  await store.prepareCheckout(playerId, requestId, 0);
  if (store.attempt) {
    store.attempt = { ...store.attempt, amount_cents: 4_999 };
  }
  const stripe = stripeGateway();
  const response = await handler(store, stripe.gateway)(request());
  assertEqual(response.status, 409, "material mismatch response");
  assertEqual(
    (await response.json()).error,
    "checkout_state_conflict",
    "material mismatch code",
  );
  assertEqual(stripe.counts().creates, 0, "mismatch must not call Stripe");
});

Deno.test("different payment requests use isolated attempts and Stripe keys", async () => {
  const otherRequestId = "77777777-7777-4777-8777-777777777777";
  const first = new MemoryStore();
  const second = new MemoryStore();
  second.request = second.request
    ? { ...second.request, id: otherRequestId }
    : null;
  second.stripeKey = "homeplate_checkout_v1_other";
  const firstStripe = stripeGateway();
  const secondStripe = stripeGateway();
  const firstResponse = await handler(first, firstStripe.gateway)(request());
  const secondResponse = await handler(second, secondStripe.gateway)(
    request({ payment_request_id: otherRequestId }),
  );
  assertEqual(firstResponse.status, 200, "first request status");
  assertEqual(secondResponse.status, 200, "second request status");
  assert(
    firstStripe.counts().keys[0] !== secondStripe.counts().keys[0],
    "request-specific Stripe keys",
  );
});

Deno.test("Checkout URLs come only from server configuration", async () => {
  const store = new MemoryStore();
  let successUrl = "";
  let cancelUrl = "";
  const stripe: ConnectedCheckoutGateway = {
    createCheckout(input) {
      successUrl = input.successUrl;
      cancelUrl = input.cancelUrl;
      return Promise.resolve({
        id: "cs_server_urls",
        url: "https://checkout.stripe.com/c/pay/server-urls",
        status: "open",
        expires_at: 1_800_000_000,
        payment_intent_id: null,
      });
    },
    retrieveCheckout: () => Promise.reject(new Error("not expected")),
  };
  const response = await handler(store, stripe)(request());
  assertEqual(response.status, 200, "server URL response");
  assertEqual(
    successUrl,
    "https://app.homeplate.example/payments/success",
    "server success URL",
  );
  assertEqual(
    cancelUrl,
    "https://app.homeplate.example/payments/cancel",
    "server cancel URL",
  );
});

Deno.test("Stripe direct-charge request uses authoritative values and zero fee by default", () => {
  const form = checkoutForm({
    connectedAccountId: "acct_organization",
    idempotencyKey: "stable-key",
    paymentRequestId: requestId,
    requestBatchId: null,
    organizationId: orgId,
    organizationName: "Home Plate Academy",
    childId: playerId,
    payerUserId: parentId,
    checkoutAttemptId: attemptId,
    title: "Summer training",
    description: "July session",
    amountCents: 5_000,
    currency: "usd",
    applicationFeeAmountCents: 0,
    successUrl: "https://app.homeplate.example/success",
    cancelUrl: "https://app.homeplate.example/cancel",
    expiresAt: "2027-01-15T08:00:00.000Z",
  });
  assertEqual(
    form.get("line_items[0][price_data][unit_amount]"),
    "5000",
    "database amount",
  );
  assertEqual(
    form.get("line_items[0][price_data][currency]"),
    "usd",
    "database currency",
  );
  assertEqual(
    form.get("payment_intent_data[application_fee_amount]"),
    null,
    "zero fee omission",
  );
  assertEqual(
    form.get("metadata[home_plate_payment_request_id]"),
    requestId,
    "request metadata",
  );
  assertEqual(
    form.get("metadata[home_plate_checkout_attempt_id]"),
    attemptId,
    "attempt metadata",
  );
  assert(
    !Array.from(form.keys()).some((key) => key.includes("notes")),
    "metadata must exclude notes",
  );
});

Deno.test("connected Checkout gateway sets Stripe account context and idempotency", async () => {
  let options: Record<string, unknown> = {};
  const gateway = createConnectedStripeCheckoutGateway(
    "sk_test",
    (_key, _path, requestOptions) => {
      options = requestOptions ?? {};
      return Promise.resolve({
        id: "cs_test_context",
        url: "https://checkout.stripe.com/c/pay/context",
        status: "open",
        expires_at: 1_800_000_000,
        payment_intent: null,
      });
    },
  );
  await gateway.createCheckout({
    connectedAccountId: "acct_organization",
    idempotencyKey: "stable-key",
    paymentRequestId: requestId,
    requestBatchId: null,
    organizationId: orgId,
    organizationName: "Academy",
    childId: playerId,
    payerUserId: playerId,
    checkoutAttemptId: attemptId,
    title: "Fee",
    description: null,
    amountCents: 100,
    currency: "usd",
    applicationFeeAmountCents: 0,
    successUrl: "https://app.homeplate.example/success",
    cancelUrl: "https://app.homeplate.example/cancel",
    expiresAt: "2027-01-15T08:00:00.000Z",
  });
  assertEqual(
    options.connectedAccountId,
    "acct_organization",
    "Stripe-Account context",
  );
  assertEqual(options.idempotencyKey, "stable-key", "Stripe idempotency key");
});

Deno.test("Checkout migration is additive, service-role-only, and transactionally reconciles payment", async () => {
  const migration = (await Deno.readTextFile(
    new URL(
      "../../migrations/20260714210000_payment_request_checkout_foundation.sql",
      import.meta.url,
    ),
  )).toLowerCase();
  assert(
    migration.includes(
      "create table if not exists public.sd_payment_checkout_sessions",
    ),
    "checkout table",
  );
  assert(
    migration.includes("add column if not exists payment_request_id uuid"),
    "payment linkage",
  );
  assert(
    migration.includes("add column if not exists paid_at timestamptz"),
    "paid timestamp",
  );
  assert(
    migration.includes("security definer\nset search_path = ''"),
    "safe search path",
  );
  assert(
    migration.includes(
      "revoke all on function public.sd_prepare_payment_request_checkout",
    ) &&
      migration.includes("to service_role"),
    "service-role-only RPC",
  );
  assert(
    migration.includes(
      "revoke all on table public.sd_payment_checkout_sessions from public, anon, authenticated",
    ),
    "no authenticated checkout mutation",
  );
  assert(
    migration.includes("where status in ('creating', 'open')"),
    "one active attempt index",
  );
  assert(
    migration.includes("insert into public.sd_payments") &&
      migration.includes("set status = 'paid'"),
    "atomic reconciliation",
  );
  assert(
    !migration.includes("http://") &&
      !migration.includes("https://api.stripe.com"),
    "RPC does not call Stripe",
  );
});
