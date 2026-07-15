import {
  type ConnectedPaymentAccountRow,
  type ConnectedPaymentAccountStore,
  createStripeConnectGateway,
  createStripeConnectOnboardingHandler,
  createStripeConnectRefreshFallbackHandler,
  createStripeConnectStatusHandler,
  STRIPE_CONNECT_ACCOUNT_CREATION_VERSION,
  type StripeConnectedAccount,
  type StripeConnectGateway,
  type StripeConnectSnapshot,
} from "./stripe_connect.ts";
import { canAdministerStripeConnect } from "./stripe_connect_supabase.ts";

const orgId = "11111111-1111-4111-8111-111111111111";

function assert(condition: boolean, message: string) {
  if (!condition) throw new Error(message);
}

function assertEqual<T>(actual: T, expected: T, label: string) {
  if (actual !== expected) throw new Error(`${label}: expected ${expected}, received ${actual}`);
}

function account(overrides: Partial<StripeConnectedAccount> = {}): StripeConnectedAccount {
  return {
    id: "acct_homeplate",
    details_submitted: false,
    charges_enabled: false,
    payouts_enabled: false,
    requirements: {
      currently_due: [],
      past_due: [],
      eventually_due: [],
      disabled_reason: null,
    },
    ...overrides,
  };
}

class MemoryStore implements ConnectedPaymentAccountStore {
  row: ConnectedPaymentAccountRow | null;
  snapshots: StripeConnectSnapshot[] = [];
  persistCount = 0;

  constructor(row: ConnectedPaymentAccountRow | null = null) {
    this.row = row;
  }

  load(): Promise<ConnectedPaymentAccountRow | null> {
    return Promise.resolve(this.row);
  }

  persistAccount(_orgId: string, providerAccountId: string): Promise<void> {
    this.persistCount += 1;
    this.row = { provider: "stripe", provider_account_id: providerAccountId };
    return Promise.resolve();
  }

  persistSnapshot(_orgId: string, _providerAccountId: string, snapshot: StripeConnectSnapshot): Promise<void> {
    this.snapshots.push(snapshot);
    return Promise.resolve();
  }
}

function gateway(value: StripeConnectedAccount = account()) {
  let createCount = 0;
  let retrieveCount = 0;
  const implementation: StripeConnectGateway = {
    createConnectedAccount: () => {
      createCount += 1;
      return Promise.resolve(value);
    },
    retrieveAccount: () => {
      retrieveCount += 1;
      return Promise.resolve(value);
    },
    createOnboardingLink: () => Promise.resolve({
      url: "https://connect.stripe.com/setup/example",
      expires_at: 1_800_000_000,
    }),
  };
  return {
    implementation,
    counts: () => ({ createCount, retrieveCount }),
  };
}

function request(headers: HeadersInit = {}): Request {
  return new Request("https://example.com/functions/v1/connect", {
    method: "POST",
    headers: { "content-type": "application/json", ...headers },
    body: JSON.stringify({ org_id: orgId }),
  });
}

const validOnboardingDeps = (store: ConnectedPaymentAccountStore, stripe: StripeConnectGateway) => ({
  stripeConfigured: true,
  returnUrl: "https://app.homeplate.example/stripe/return",
  refreshUrl: "https://app.homeplate.example/stripe/refresh",
  gateway: stripe,
  authorize: (incoming: Request) => {
    if (!incoming.headers.get("Authorization")) throw new Error("missing_auth");
    return Promise.resolve(store);
  },
});

Deno.test("Stripe Connect policy requires active owner or active admin authority", () => {
  assert(canAdministerStripeConnect("owner", "active"), "active owner should be authorized");
  assert(canAdministerStripeConnect("admin", "active"), "active org admin should be authorized");
  assert(!canAdministerStripeConnect("coach", "active"), "coach must be rejected");
  assert(!canAdministerStripeConnect("parent", "active"), "parent must be rejected");
  assert(!canAdministerStripeConnect("player", "active"), "player must be rejected");
  assert(!canAdministerStripeConnect("owner", "disabled"), "inactive owner must be rejected");
  assert(!canAdministerStripeConnect("owner", "suspended"), "suspended owner must be rejected");
  assert(!canAdministerStripeConnect(null, null), "unrelated user must be rejected");
});

Deno.test("onboarding rejects a missing JWT", async () => {
  const stripe = gateway();
  const handler = createStripeConnectOnboardingHandler(validOnboardingDeps(new MemoryStore(), stripe.implementation));
  const response = await handler(request());
  assertEqual(response.status, 401, "missing JWT status");
  assertEqual((await response.json()).error, "missing_auth", "missing JWT code");
});

Deno.test("onboarding rejects invalid organization input", async () => {
  const stripe = gateway();
  const handler = createStripeConnectOnboardingHandler(validOnboardingDeps(new MemoryStore(), stripe.implementation));
  const response = await handler(new Request("https://example.com", {
    method: "POST",
    body: JSON.stringify({ org_id: "not-an-org" }),
  }));
  assertEqual(response.status, 400, "invalid organization status");
  assertEqual((await response.json()).error, "invalid_org_id", "invalid organization code");
});

for (const authorizationFailure of [
  ["organization_membership_required", 403],
  ["organization_connect_admin_required", 403],
  ["organization_inactive_or_missing", 404],
] as const) {
  Deno.test(`onboarding rejects ${authorizationFailure[0]}`, async () => {
    const stripe = gateway();
    const handler = createStripeConnectOnboardingHandler({
      ...validOnboardingDeps(new MemoryStore(), stripe.implementation),
      authorize: () => {
        throw new Error(authorizationFailure[0]);
      },
    });
    const response = await handler(request({ Authorization: "Bearer test" }));
    assertEqual(response.status, authorizationFailure[1], "authorization failure status");
  });
}

Deno.test("onboarding reuses an existing Stripe account", async () => {
  const store = new MemoryStore({ provider: "stripe", provider_account_id: "acct_homeplate" });
  const stripe = gateway();
  const handler = createStripeConnectOnboardingHandler(validOnboardingDeps(store, stripe.implementation));
  const response = await handler(request({ Authorization: "Bearer test" }));
  assertEqual(response.status, 200, "existing account response");
  assertEqual(stripe.counts().createCount, 0, "existing account create count");
  assertEqual(stripe.counts().retrieveCount, 1, "existing account retrieve count");
});

Deno.test("repeated onboarding prevents duplicate connected accounts", async () => {
  const store = new MemoryStore();
  const stripe = gateway();
  const handler = createStripeConnectOnboardingHandler(validOnboardingDeps(store, stripe.implementation));
  assertEqual((await handler(request({ Authorization: "Bearer test" }))).status, 200, "first onboarding");
  assertEqual((await handler(request({ Authorization: "Bearer test" }))).status, 200, "second onboarding");
  assertEqual(stripe.counts().createCount, 1, "created account count");
  assertEqual(store.persistCount, 1, "persisted account count");
});

Deno.test("status safely reports an organization with no connected account", async () => {
  const store = new MemoryStore();
  const stripe = gateway();
  const handler = createStripeConnectStatusHandler({
    stripeConfigured: true,
    gateway: stripe.implementation,
    authorize: () => Promise.resolve(store),
  });
  const response = await handler(request({ Authorization: "Bearer test" }));
  const body = await response.json();
  assertEqual(response.status, 200, "not connected response");
  assertEqual(body.status, "not_connected", "not connected status");
  assertEqual(stripe.counts().retrieveCount, 0, "not connected retrieve count");
});

for (const invalidConfiguration of [
  ["returnUrl", "http://app.homeplate.example/return", "connect_return_url_invalid"],
  ["refreshUrl", "", "connect_refresh_url_invalid"],
] as const) {
  Deno.test(`onboarding rejects invalid ${invalidConfiguration[0]}`, async () => {
    const stripe = gateway();
    const deps = validOnboardingDeps(new MemoryStore(), stripe.implementation);
    const handler = createStripeConnectOnboardingHandler({
      ...deps,
      [invalidConfiguration[0]]: invalidConfiguration[1],
    });
    const response = await handler(request({ Authorization: "Bearer test" }));
    assertEqual(response.status, 500, "invalid URL status");
    assertEqual((await response.json()).error, invalidConfiguration[2], "invalid URL code");
  });
}

for (const fixture of [
  {
    name: "ready",
    account: account({ details_submitted: true, charges_enabled: true, payouts_enabled: true }),
    status: "ready",
  },
  {
    name: "requirements due",
    account: account({
      details_submitted: true,
      requirements: {
        currently_due: ["business_profile.url"],
        past_due: [],
        eventually_due: ["representative.id_number"],
        disabled_reason: null,
      },
    }),
    status: "requirements_due",
  },
  {
    name: "restricted",
    account: account({
      details_submitted: true,
      requirements: {
        currently_due: [],
        past_due: ["representative.verification.document"],
        eventually_due: [],
        disabled_reason: "requirements.past_due",
      },
    }),
    status: "restricted",
  },
] as const) {
  Deno.test(`status safely maps a ${fixture.name} account`, async () => {
    const store = new MemoryStore({ provider: "stripe", provider_account_id: fixture.account.id });
    const stripe = gateway(fixture.account);
    const handler = createStripeConnectStatusHandler({
      stripeConfigured: true,
      gateway: stripe.implementation,
      authorize: () => Promise.resolve(store),
    });
    const response = await handler(request({ Authorization: "Bearer test" }));
    const body = await response.json();
    assertEqual(response.status, 200, `${fixture.name} response`);
    assertEqual(body.status, fixture.status, `${fixture.name} status`);
    assertEqual(store.snapshots.length, 1, `${fixture.name} persisted snapshots`);
    for (const forbidden of ["email", "business_profile", "external_accounts", "individual", "company"]) {
      assert(!(forbidden in body), `response leaked ${forbidden}`);
    }
  });
}

Deno.test("Stripe gateway uses explicit controller properties and hosted onboarding fields", async () => {
  const calls: Array<{ path: string; form?: URLSearchParams; idempotencyKey?: string }> = [];
  const stripe = createStripeConnectGateway("sk_test_mock", (_secret, path, options) => {
    calls.push({ path, form: options?.form, idempotencyKey: options?.idempotencyKey });
    if (path === "/account_links") {
      return Promise.resolve({ url: "https://connect.stripe.com/setup/mock", expires_at: 1_800_000_000 });
    }
    return Promise.resolve({
      id: "acct_homeplate",
      details_submitted: false,
      charges_enabled: false,
      payouts_enabled: false,
      requirements: {},
      email: "must-not-be-returned@example.com",
      external_accounts: { data: [{ id: "ba_sensitive" }] },
    });
  });
  const created = await stripe.createConnectedAccount(orgId);
  await stripe.createOnboardingLink(
    "acct_homeplate",
    "https://app.homeplate.example/return",
    "https://app.homeplate.example/refresh",
  );

  assertEqual(calls[0].path, "/accounts", "account creation path");
  assertEqual(calls[0].form?.has("type"), false, "legacy connected account type omitted");
  assertEqual(calls[0].form?.get("controller[losses][payments]"), "stripe", "losses controller");
  assertEqual(calls[0].form?.get("controller[fees][payer]"), "account", "fee payer controller");
  assertEqual(
    calls[0].form?.get("controller[requirement_collection]"),
    "stripe",
    "requirement collection controller",
  );
  assertEqual(calls[0].form?.get("controller[stripe_dashboard][type]"), "full", "dashboard controller");
  assertEqual(calls[0].form?.get("capabilities[card_payments][requested]"), "true", "card capability");
  assertEqual(calls[0].form?.get("capabilities[transfers][requested]"), "true", "transfers capability");
  assertEqual(
    calls[0].idempotencyKey,
    `homeplate-connect-account-controller-v2-${orgId}`,
    "versioned account idempotency key",
  );
  assert(!calls[0].idempotencyKey?.includes(`homeplate-connect-account-${orgId}`), "old account key omitted");
  assertEqual(calls[1].form?.get("type"), "account_onboarding", "account link type");
  assertEqual(calls[1].form?.get("collection_options[fields]"), "eventually_due", "collection fields");
  assertEqual(created.id, "acct_homeplate", "sanitized account ID");
  for (const forbidden of ["email", "external_accounts", "business_profile", "individual", "company"]) {
    assert(!(forbidden in created), `created account leaked ${forbidden}`);
  }
});

Deno.test("connected account idempotency keys are stable, versioned, lowercase, and organization scoped", async () => {
  const keys: string[] = [];
  const stripe = createStripeConnectGateway("sk_test_mock", (_secret, path, options) => {
    assertEqual(path, "/accounts", "account creation path");
    keys.push(options?.idempotencyKey ?? "");
    return Promise.resolve({
      id: "acct_homeplate",
      details_submitted: false,
      charges_enabled: false,
      payouts_enabled: false,
      requirements: {},
    });
  });
  const mixedCaseOrgId = "800E22AE-2A9D-4109-9E11-1360EEAA8EA7";
  const otherOrgId = "11111111-2222-4333-8444-555555555555";

  await stripe.createConnectedAccount(mixedCaseOrgId);
  await stripe.createConnectedAccount(mixedCaseOrgId);
  await stripe.createConnectedAccount(otherOrgId);

  const expected =
    `homeplate-connect-account-${STRIPE_CONNECT_ACCOUNT_CREATION_VERSION}-${mixedCaseOrgId.toLowerCase()}`;
  assertEqual(keys[0], expected, "normalized versioned key");
  assertEqual(keys[1], expected, "identical retry key");
  assert(keys[0] !== keys[2], "different organizations must use different keys");
  assert(!keys.includes(`homeplate-connect-account-${mixedCaseOrgId}`), "old unversioned key must not be used");
});

Deno.test("refresh fallback accepts no state and cannot become an open redirect", async () => {
  const handler = createStripeConnectRefreshFallbackHandler();
  const response = handler(new Request(
    "https://example.com/stripe-connect-refresh?org_id=secret-org&account=acct_secret&next=https://evil.example",
  ));
  const body = await response.text();

  assertEqual(response.status, 200, "refresh fallback status");
  assertEqual(response.headers.get("location"), null, "refresh fallback redirect");
  assertEqual(response.headers.get("cache-control"), "no-store, max-age=0", "refresh fallback cache policy");
  assert(body.includes("Continue Stripe Setup"), "refresh fallback should explain the safe recovery action");
  for (const forbidden of ["secret-org", "acct_secret", "evil.example", "Authorization", "Bearer"]) {
    assert(!body.includes(forbidden), `refresh fallback reflected ${forbidden}`);
  }
});

Deno.test("refresh fallback rejects mutating methods", () => {
  const handler = createStripeConnectRefreshFallbackHandler();
  const response = handler(new Request("https://example.com/stripe-connect-refresh", { method: "POST" }));
  assertEqual(response.status, 405, "refresh fallback POST status");
});
