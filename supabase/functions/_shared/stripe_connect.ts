import { formBody, stripeRequest } from "./stripe.ts";
import { isUuid, json } from "./org_billing.ts";

export type StripeConnectStatus =
  | "not_connected"
  | "onboarding_incomplete"
  | "requirements_due"
  | "ready"
  | "restricted";

export type ConnectedPaymentAccountRow = {
  provider: string;
  provider_account_id: string | null;
};

export type StripeConnectSnapshot = {
  status: StripeConnectStatus;
  details_submitted: boolean;
  charges_enabled: boolean;
  payouts_enabled: boolean;
  currently_due: string[];
  past_due: string[];
  eventually_due: string[];
  disabled_reason: string | null;
  last_synced_at: string | null;
};

export interface ConnectedPaymentAccountStore {
  load(orgId: string): Promise<ConnectedPaymentAccountRow | null>;
  persistAccount(orgId: string, providerAccountId: string): Promise<void>;
  persistSnapshot(orgId: string, providerAccountId: string, snapshot: StripeConnectSnapshot): Promise<void>;
}

type StripeRequirements = {
  currently_due: string[];
  past_due: string[];
  eventually_due: string[];
  disabled_reason: string | null;
};

export type StripeConnectedAccount = {
  id: string;
  details_submitted: boolean;
  charges_enabled: boolean;
  payouts_enabled: boolean;
  requirements: StripeRequirements;
};

export type StripeAccountLink = {
  url: string;
  expires_at: number;
};

export interface StripeConnectGateway {
  createConnectedAccount(orgId: string): Promise<StripeConnectedAccount>;
  retrieveAccount(providerAccountId: string): Promise<StripeConnectedAccount>;
  createOnboardingLink(
    providerAccountId: string,
    returnUrl: string,
    refreshUrl: string,
  ): Promise<StripeAccountLink>;
}

type StripeRequestOptions = {
  method?: "GET" | "POST";
  form?: URLSearchParams;
  idempotencyKey?: string;
};

// Increment whenever material /v1/accounts parameters change. Stripe binds an
// idempotency key to the exact request body used on its first attempt.
export const STRIPE_CONNECT_ACCOUNT_CREATION_VERSION = "controller-v2";

export function stripeConnectAccountCreationIdempotencyKey(
  orgId: string,
): string {
  return `homeplate-connect-account-${STRIPE_CONNECT_ACCOUNT_CREATION_VERSION}-${orgId.toLowerCase()}`;
}

export type StripeRequestLike = (
  secretKey: string,
  path: string,
  options?: StripeRequestOptions,
) => Promise<unknown>;

const defaultStripeRequest: StripeRequestLike = (secretKey, path, options) =>
  stripeRequest<unknown>(secretKey, path, options);

function record(value: unknown, code: string): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) throw new Error(code);
  return value as Record<string, unknown>;
}

function stringArray(value: unknown): string[] {
  return Array.isArray(value) ? value.filter((item): item is string => typeof item === "string") : [];
}

export function parseStripeConnectedAccount(value: unknown): StripeConnectedAccount {
  const account = record(value, "stripe_account_invalid");
  const requirements = account.requirements === null || account.requirements === undefined
    ? {}
    : record(account.requirements, "stripe_account_requirements_invalid");
  if (typeof account.id !== "string" || !account.id.startsWith("acct_")) {
    throw new Error("stripe_account_id_invalid");
  }
  return {
    id: account.id,
    details_submitted: account.details_submitted === true,
    charges_enabled: account.charges_enabled === true,
    payouts_enabled: account.payouts_enabled === true,
    requirements: {
      currently_due: stringArray(requirements.currently_due),
      past_due: stringArray(requirements.past_due),
      eventually_due: stringArray(requirements.eventually_due),
      disabled_reason: typeof requirements.disabled_reason === "string"
        ? requirements.disabled_reason
        : null,
    },
  };
}

export function createStripeConnectGateway(
  secretKey: string,
  request: StripeRequestLike = defaultStripeRequest,
): StripeConnectGateway {
  return {
    async createConnectedAccount(orgId) {
      const value = await request(secretKey, "/accounts", {
        form: formBody({
          "metadata[home_plate_org_id]": orgId,
          "controller[losses][payments]": "stripe",
          "controller[fees][payer]": "account",
          "controller[requirement_collection]": "stripe",
          "controller[stripe_dashboard][type]": "full",
          "capabilities[card_payments][requested]": true,
          "capabilities[transfers][requested]": true,
        }),
        idempotencyKey: stripeConnectAccountCreationIdempotencyKey(orgId),
      });
      return parseStripeConnectedAccount(value);
    },

    async retrieveAccount(providerAccountId) {
      const value = await request(secretKey, `/accounts/${encodeURIComponent(providerAccountId)}`, {
        method: "GET",
      });
      return parseStripeConnectedAccount(value);
    },

    async createOnboardingLink(providerAccountId, returnUrl, refreshUrl) {
      const value = record(await request(secretKey, "/account_links", {
        form: formBody({
          account: providerAccountId,
          return_url: returnUrl,
          refresh_url: refreshUrl,
          type: "account_onboarding",
          "collection_options[fields]": "eventually_due",
        }),
      }), "stripe_account_link_invalid");
      if (typeof value.url !== "string" || !isHttpsUrl(value.url)) {
        throw new Error("stripe_account_link_url_invalid");
      }
      if (typeof value.expires_at !== "number" || !Number.isFinite(value.expires_at)) {
        throw new Error("stripe_account_link_expiry_invalid");
      }
      return { url: value.url, expires_at: value.expires_at };
    },
  };
}

export function isHttpsUrl(value: string): boolean {
  try {
    const url = new URL(value);
    return url.protocol === "https:" && Boolean(url.hostname);
  } catch {
    return false;
  }
}

export function mapStripeConnectStatus(
  account: StripeConnectedAccount,
  syncedAt = new Date().toISOString(),
): StripeConnectSnapshot {
  const requirements = account.requirements;
  const hasPastDue = requirements.past_due.length > 0;
  let status: StripeConnectStatus;
  if (requirements.disabled_reason) {
    status = "restricted";
  } else if (
    account.details_submitted &&
    account.charges_enabled &&
    account.payouts_enabled &&
    !hasPastDue
  ) {
    status = "ready";
  } else if (hasPastDue || requirements.currently_due.length > 0) {
    status = "requirements_due";
  } else {
    status = "onboarding_incomplete";
  }
  return {
    status,
    details_submitted: account.details_submitted,
    charges_enabled: account.charges_enabled,
    payouts_enabled: account.payouts_enabled,
    currently_due: requirements.currently_due,
    past_due: requirements.past_due,
    eventually_due: requirements.eventually_due,
    disabled_reason: requirements.disabled_reason,
    last_synced_at: syncedAt,
  };
}

export const notConnectedSnapshot = (): StripeConnectSnapshot => ({
  status: "not_connected",
  details_submitted: false,
  charges_enabled: false,
  payouts_enabled: false,
  currently_due: [],
  past_due: [],
  eventually_due: [],
  disabled_reason: null,
  last_synced_at: null,
});

export async function getOrCreateStripeAccount(
  orgId: string,
  store: ConnectedPaymentAccountStore,
  gateway: StripeConnectGateway,
): Promise<StripeConnectedAccount> {
  const current = await store.load(orgId);
  if (current && current.provider !== "stripe") throw new Error("connected_payment_provider_conflict");
  if (current?.provider_account_id) return await gateway.retrieveAccount(current.provider_account_id);

  // The Stripe idempotency key and the org_id primary key jointly prevent
  // concurrent onboarding attempts from creating separate active accounts.
  const created = await gateway.createConnectedAccount(orgId);
  await store.persistAccount(orgId, created.id);
  return created;
}

export type StripeConnectAuthorization = (
  request: Request,
  orgId: string,
) => Promise<ConnectedPaymentAccountStore>;

type OnboardingHandlerDependencies = {
  authorize: StripeConnectAuthorization;
  gateway: StripeConnectGateway;
  stripeConfigured: boolean;
  returnUrl: string;
  refreshUrl: string;
};

type StatusHandlerDependencies = {
  authorize: StripeConnectAuthorization;
  gateway: StripeConnectGateway;
  stripeConfigured: boolean;
};

function safeErrorResponse(error: unknown): Response {
  const message = error instanceof Error ? error.message : "stripe_connect_failed";
  if (["missing_auth", "invalid_auth"].includes(message)) return json(401, { error: message });
  if (["organization_membership_required", "organization_connect_admin_required"].includes(message)) {
    return json(403, { error: message });
  }
  if (message === "organization_inactive_or_missing") return json(404, { error: message });
  if (message === "connected_payment_provider_conflict") return json(409, { error: message });
  if (message.startsWith("missing_") || message.endsWith("_url_invalid")) {
    return json(500, { error: message });
  }
  return json(502, { error: "stripe_connect_unavailable" });
}

async function requestedOrgId(request: Request): Promise<string | Response> {
  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return json(400, { error: "invalid_json" });
  }
  if (!body || typeof body !== "object" || Array.isArray(body)) {
    return json(400, { error: "invalid_json" });
  }
  const orgId = String((body as Record<string, unknown>).org_id ?? "").trim();
  return isUuid(orgId) ? orgId : json(400, { error: "invalid_org_id" });
}

export function createStripeConnectOnboardingHandler(deps: OnboardingHandlerDependencies) {
  return async (request: Request): Promise<Response> => {
    if (request.method !== "POST") return json(405, { error: "method_not_allowed" });
    const orgId = await requestedOrgId(request);
    if (orgId instanceof Response) return orgId;
    try {
      const store = await deps.authorize(request, orgId);
      if (!deps.stripeConfigured) throw new Error("missing_stripe_configuration");
      if (!isHttpsUrl(deps.returnUrl)) throw new Error("connect_return_url_invalid");
      if (!isHttpsUrl(deps.refreshUrl)) throw new Error("connect_refresh_url_invalid");
      const account = await getOrCreateStripeAccount(orgId, store, deps.gateway);
      const link = await deps.gateway.createOnboardingLink(account.id, deps.returnUrl, deps.refreshUrl);
      return json(200, { url: link.url, expires_at: link.expires_at });
    } catch (error) {
      return safeErrorResponse(error);
    }
  };
}

export function createStripeConnectStatusHandler(deps: StatusHandlerDependencies) {
  return async (request: Request): Promise<Response> => {
    if (request.method !== "POST") return json(405, { error: "method_not_allowed" });
    const orgId = await requestedOrgId(request);
    if (orgId instanceof Response) return orgId;
    try {
      const store = await deps.authorize(request, orgId);
      if (!deps.stripeConfigured) throw new Error("missing_stripe_configuration");
      const current = await store.load(orgId);
      if (current && current.provider !== "stripe") throw new Error("connected_payment_provider_conflict");
      if (!current?.provider_account_id) return json(200, notConnectedSnapshot());
      const account = await deps.gateway.retrieveAccount(current.provider_account_id);
      const snapshot = mapStripeConnectStatus(account);
      await store.persistSnapshot(orgId, account.id, snapshot);
      return json(200, snapshot);
    } catch (error) {
      return safeErrorResponse(error);
    }
  };
}

const connectRefreshPage = `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Return to Home Plate</title>
  <style>
    :root { color-scheme: light dark; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; }
    body { margin: 0; min-height: 100vh; display: grid; place-items: center; background: #0b1018; color: #f7f9fc; }
    main { width: min(34rem, calc(100% - 3rem)); }
    h1 { margin: 0 0 .75rem; font-size: clamp(1.8rem, 7vw, 2.5rem); }
    p { margin: 0; color: #c4ccd8; font-size: 1.05rem; line-height: 1.6; }
  </style>
</head>
<body>
  <main>
    <h1>Stripe setup link expired</h1>
    <p>Return to Home Plate and tap <strong>Continue Stripe Setup</strong>. The app will securely create a new single-use link.</p>
  </main>
</body>
</html>`;

/**
 * Account Link refreshes arrive without the app's authenticated Supabase JWT.
 * This endpoint deliberately accepts no state and creates no Stripe link. The
 * authenticated app remains the only place that can request a replacement.
 */
export function createStripeConnectRefreshFallbackHandler() {
  return (request: Request): Response => {
    if (request.method !== "GET" && request.method !== "HEAD") {
      return new Response("Method Not Allowed", {
        status: 405,
        headers: { Allow: "GET, HEAD" },
      });
    }
    const headers = new Headers({
      "cache-control": "no-store, max-age=0",
      "content-security-policy": "default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'",
      "content-type": "text/html; charset=utf-8",
      "referrer-policy": "no-referrer",
      "x-content-type-options": "nosniff",
      "x-frame-options": "DENY",
    });
    return new Response(request.method === "HEAD" ? null : connectRefreshPage, {
      status: 200,
      headers,
    });
  };
}
