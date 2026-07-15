export type CheckoutAuthorizationSource = "player_self" | "linked_parent";

export type CheckoutMembership = {
  role: string;
  status: string;
};

export type CheckoutParentLink = {
  can_pay: boolean;
};

export type CheckoutPaymentRequest = {
  id: string;
  request_batch_id: string | null;
  org_id: string;
  child_id: string;
  title: string;
  notes: string | null;
  amount_cents: number | null;
  currency: string;
  status: "open" | "canceled" | "paid";
};

export type CheckoutOrganization = {
  id: string;
  name: string;
  status: string;
};

export type CheckoutConnectedAccount = {
  org_id: string;
  provider: string;
  provider_account_id: string | null;
  onboarding_status: string;
  details_submitted: boolean;
  charges_enabled: boolean;
  payouts_enabled: boolean;
  disabled_reason: string | null;
  requirements_currently_due: unknown[];
  requirements_past_due: unknown[];
};

export type PreparedCheckoutAttempt = {
  attempt_id: string;
  org_id: string;
  payment_request_id: string;
  payer_user_id: string;
  child_id: string;
  authorization_source: CheckoutAuthorizationSource;
  stripe_account_id: string;
  stripe_checkout_session_id: string | null;
  stripe_idempotency_key: string;
  amount_cents: number;
  currency: string;
  application_fee_amount_cents: number;
  fee_policy_version: string;
  expires_at: string;
  reused: boolean;
};

export type StripeHostedCheckout = {
  id: string;
  url: string | null;
  status: "open" | "complete" | "expired" | string;
  expires_at: number;
  payment_intent_id: string | null;
};

export type StripeCheckoutCreationInput = {
  connectedAccountId: string;
  idempotencyKey: string;
  paymentRequestId: string;
  requestBatchId: string | null;
  organizationId: string;
  organizationName: string;
  childId: string;
  payerUserId: string;
  checkoutAttemptId: string;
  title: string;
  description: string | null;
  amountCents: number;
  currency: string;
  applicationFeeAmountCents: number;
  successUrl: string;
  cancelUrl: string;
  expiresAt: string;
};

export interface PaymentCheckoutStore {
  authenticate(request: Request): Promise<string | null>;
  paymentRequest(
    paymentRequestId: string,
  ): Promise<CheckoutPaymentRequest | null>;
  organization(orgId: string): Promise<CheckoutOrganization | null>;
  membership(orgId: string, userId: string): Promise<CheckoutMembership | null>;
  parentLink(
    orgId: string,
    parentId: string,
    childId: string,
  ): Promise<CheckoutParentLink | null>;
  connectedAccount(orgId: string): Promise<CheckoutConnectedAccount | null>;
  prepareCheckout(
    actorId: string,
    paymentRequestId: string,
    feeBasisPoints: number,
  ): Promise<PreparedCheckoutAttempt>;
  finalizeCheckout(
    attemptId: string,
    session: StripeHostedCheckout,
  ): Promise<void>;
  finishAttempt(
    attemptId: string,
    status: "expired" | "failed",
    errorCode: string,
  ): Promise<void>;
}

export interface ConnectedCheckoutGateway {
  createCheckout(
    input: StripeCheckoutCreationInput,
  ): Promise<StripeHostedCheckout>;
  retrieveCheckout(
    connectedAccountId: string,
    sessionId: string,
  ): Promise<StripeHostedCheckout>;
}

export type PaymentCheckoutDependencies = {
  store: PaymentCheckoutStore;
  stripe: ConnectedCheckoutGateway;
  stripeConfigured: boolean;
  successUrl: string;
  cancelUrl: string;
  feeBasisPoints: number;
};

type ErrorPayload = { error: string; message: string };

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const MAX_DESCRIPTION_LENGTH = 500;

const ERROR_MESSAGES: Record<string, string> = {
  method_not_allowed: "This Checkout action is not supported.",
  invalid_request: "Select a valid payment request.",
  authentication_required:
    "Your session could not be verified. Sign in and try again.",
  payment_request_not_found: "The payment request could not be found.",
  payment_request_not_open: "This payment request is no longer open.",
  payment_request_not_payable:
    "This payment request does not have a payable amount.",
  payment_already_completed: "This payment request has already been paid.",
  payer_not_authorized: "You are not authorized to pay this request.",
  parent_payment_not_allowed:
    "You can view this request, but payment permission is not enabled for this child.",
  active_player_required: "The player must remain active in this organization.",
  organization_inactive: "This organization is inactive.",
  connected_account_missing:
    "This organization has not connected a Stripe account.",
  connected_account_not_ready:
    "This organization is not ready to accept customer payments.",
  checkout_creation_failed: "Stripe Checkout could not be created. Try again.",
  checkout_state_conflict:
    "The payment request changed while Checkout was opening. Refresh and try again.",
  configuration_missing: "Payment Checkout is not configured.",
  rate_limited: "Too many Checkout attempts were made. Try again shortly.",
  internal_error: "Checkout is temporarily unavailable.",
};

export class PaymentCheckoutError extends Error {
  constructor(
    public readonly code: string,
    public readonly status: number,
    public readonly ambiguous = false,
  ) {
    super(code);
  }
}

function json<T>(status: number, body: T): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });
}

function errorResponse(status: number, code: string): Response {
  const body: ErrorPayload = {
    error: code,
    message: ERROR_MESSAGES[code] ?? ERROR_MESSAGES.internal_error,
  };
  return json(status, body);
}

function isObject(value: unknown): value is Record<string, unknown> {
  return Boolean(value) && typeof value === "object" && !Array.isArray(value);
}

function isHttpsUrl(value: string): boolean {
  try {
    return new URL(value).protocol === "https:";
  } catch {
    return false;
  }
}

export function connectedAccountAcceptsCustomerPayments(
  account: CheckoutConnectedAccount | null,
  orgId: string,
): boolean {
  return account !== null &&
    account.org_id === orgId &&
    account.provider === "stripe" &&
    typeof account.provider_account_id === "string" &&
    account.provider_account_id.startsWith("acct_") &&
    account.onboarding_status === "ready" &&
    account.details_submitted &&
    account.charges_enabled &&
    account.payouts_enabled &&
    account.disabled_reason === null &&
    account.requirements_past_due.length === 0;
}

export function payerAuthorization(
  actorId: string,
  request: CheckoutPaymentRequest,
  actorMembership: CheckoutMembership | null,
  playerMembership: CheckoutMembership | null,
  parentLink: CheckoutParentLink | null,
): CheckoutAuthorizationSource {
  if (
    playerMembership?.role !== "player" || playerMembership.status !== "active"
  ) {
    throw new PaymentCheckoutError("active_player_required", 403);
  }
  if (
    actorId === request.child_id &&
    actorMembership?.role === "player" &&
    actorMembership.status === "active"
  ) {
    return "player_self";
  }
  if (
    actorMembership?.role === "parent" && actorMembership.status === "active"
  ) {
    if (parentLink?.can_pay === true) return "linked_parent";
    if (parentLink) {
      throw new PaymentCheckoutError("parent_payment_not_allowed", 403);
    }
  }
  throw new PaymentCheckoutError("payer_not_authorized", 403);
}

function mapThrownError(error: unknown): PaymentCheckoutError {
  if (error instanceof PaymentCheckoutError) return error;
  const message = error instanceof Error ? error.message : "";
  const mappings: Array<[string, string, number]> = [
    ["payment_request_not_found", "payment_request_not_found", 404],
    ["payment_already_completed", "payment_already_completed", 409],
    ["payment_request_not_open", "payment_request_not_open", 409],
    ["payment_request_not_payable", "payment_request_not_payable", 409],
    ["payer_not_authorized", "payer_not_authorized", 403],
    ["active_player_required", "active_player_required", 403],
    ["organization_inactive", "organization_inactive", 409],
    ["connected_account_missing", "connected_account_missing", 409],
    ["connected_account_not_ready", "connected_account_not_ready", 409],
    ["checkout_state_conflict", "checkout_state_conflict", 409],
    ["payment_request_state_conflict", "checkout_state_conflict", 409],
    ["rate_limit", "rate_limited", 429],
  ];
  for (const [needle, code, status] of mappings) {
    if (message.includes(needle)) return new PaymentCheckoutError(code, status);
  }
  return new PaymentCheckoutError("internal_error", 500);
}

function validateRequestRecord(request: CheckoutPaymentRequest): void {
  if (request.status === "paid") {
    throw new PaymentCheckoutError("payment_already_completed", 409);
  }
  if (request.status !== "open") {
    throw new PaymentCheckoutError("payment_request_not_open", 409);
  }
  if (
    request.amount_cents === null ||
    !Number.isSafeInteger(request.amount_cents) ||
    request.amount_cents <= 0
  ) {
    throw new PaymentCheckoutError("payment_request_not_payable", 409);
  }
  if (!/^[a-z]{3}$/.test(request.currency)) {
    throw new PaymentCheckoutError("payment_request_not_payable", 409);
  }
}

async function obtainStripeCheckout(
  deps: PaymentCheckoutDependencies,
  attempt: PreparedCheckoutAttempt,
  request: CheckoutPaymentRequest,
  organization: CheckoutOrganization,
): Promise<{ session: StripeHostedCheckout; reused: boolean }> {
  if (attempt.stripe_checkout_session_id) {
    const existing = await deps.stripe.retrieveCheckout(
      attempt.stripe_account_id,
      attempt.stripe_checkout_session_id,
    );
    if (
      existing.status === "open" && existing.url && isHttpsUrl(existing.url)
    ) {
      return { session: existing, reused: true };
    }
    if (existing.status === "expired") {
      await deps.store.finishAttempt(
        attempt.attempt_id,
        "expired",
        "provider_session_expired",
      );
      throw new PaymentCheckoutError("checkout_state_conflict", 409);
    }
    throw new PaymentCheckoutError("checkout_state_conflict", 409);
  }

  const session = await deps.stripe.createCheckout({
    connectedAccountId: attempt.stripe_account_id,
    idempotencyKey: attempt.stripe_idempotency_key,
    paymentRequestId: request.id,
    requestBatchId: request.request_batch_id,
    organizationId: request.org_id,
    organizationName: organization.name,
    childId: request.child_id,
    payerUserId: attempt.payer_user_id,
    checkoutAttemptId: attempt.attempt_id,
    title: request.title,
    description: request.notes?.slice(0, MAX_DESCRIPTION_LENGTH) ?? null,
    amountCents: attempt.amount_cents,
    currency: attempt.currency,
    applicationFeeAmountCents: attempt.application_fee_amount_cents,
    successUrl: deps.successUrl,
    cancelUrl: deps.cancelUrl,
    expiresAt: attempt.expires_at,
  });
  if (!session.url || !isHttpsUrl(session.url) || session.status !== "open") {
    throw new PaymentCheckoutError("checkout_creation_failed", 502);
  }
  await deps.store.finalizeCheckout(attempt.attempt_id, session);
  return { session, reused: attempt.reused };
}

export function createPaymentRequestCheckoutHandler(
  deps: PaymentCheckoutDependencies,
): (request: Request) => Promise<Response> {
  return async (incoming: Request): Promise<Response> => {
    if (incoming.method !== "POST") {
      return errorResponse(405, "method_not_allowed");
    }
    if (
      !deps.stripeConfigured ||
      !isHttpsUrl(deps.successUrl) ||
      !isHttpsUrl(deps.cancelUrl) ||
      !Number.isInteger(deps.feeBasisPoints) ||
      deps.feeBasisPoints < 0 ||
      deps.feeBasisPoints > 1000
    ) {
      return errorResponse(500, "configuration_missing");
    }

    let payload: unknown;
    try {
      payload = await incoming.json();
    } catch {
      return errorResponse(400, "invalid_request");
    }
    if (!isObject(payload)) return errorResponse(400, "invalid_request");
    const fields = Object.keys(payload);
    if (
      fields.length !== 1 ||
      fields[0] !== "payment_request_id" ||
      typeof payload.payment_request_id !== "string" ||
      !UUID_PATTERN.test(payload.payment_request_id)
    ) {
      return errorResponse(400, "invalid_request");
    }

    let attempt: PreparedCheckoutAttempt | null = null;
    try {
      const actorId = await deps.store.authenticate(incoming);
      if (!actorId) {
        throw new PaymentCheckoutError("authentication_required", 401);
      }

      const paymentRequest = await deps.store.paymentRequest(
        payload.payment_request_id,
      );
      if (!paymentRequest) {
        throw new PaymentCheckoutError("payment_request_not_found", 404);
      }

      const [
        organization,
        actorMembership,
        playerMembership,
        parentLink,
        connectedAccount,
      ] = await Promise.all([
        deps.store.organization(paymentRequest.org_id),
        deps.store.membership(paymentRequest.org_id, actorId),
        deps.store.membership(paymentRequest.org_id, paymentRequest.child_id),
        deps.store.parentLink(
          paymentRequest.org_id,
          actorId,
          paymentRequest.child_id,
        ),
        deps.store.connectedAccount(paymentRequest.org_id),
      ]);

      const authorization = payerAuthorization(
        actorId,
        paymentRequest,
        actorMembership,
        playerMembership,
        parentLink,
      );
      // Establish payer authority before returning request-state or connected-
      // account errors so an authenticated but unrelated actor cannot probe a
      // known request UUID for financial lifecycle details.
      validateRequestRecord(paymentRequest);
      if (!organization || organization.status !== "active") {
        throw new PaymentCheckoutError("organization_inactive", 409);
      }
      if (!connectedAccount) {
        throw new PaymentCheckoutError("connected_account_missing", 409);
      }
      if (
        !connectedAccountAcceptsCustomerPayments(
          connectedAccount,
          paymentRequest.org_id,
        )
      ) {
        throw new PaymentCheckoutError("connected_account_not_ready", 409);
      }

      attempt = await deps.store.prepareCheckout(
        actorId,
        paymentRequest.id,
        deps.feeBasisPoints,
      );
      if (
        attempt.authorization_source !== authorization ||
        attempt.org_id !== paymentRequest.org_id ||
        attempt.payment_request_id !== paymentRequest.id ||
        attempt.child_id !== paymentRequest.child_id ||
        attempt.payer_user_id !== actorId ||
        attempt.stripe_account_id !== connectedAccount.provider_account_id ||
        attempt.amount_cents !== paymentRequest.amount_cents ||
        attempt.currency !== paymentRequest.currency
      ) {
        throw new PaymentCheckoutError("checkout_state_conflict", 409);
      }

      const result = await obtainStripeCheckout(
        deps,
        attempt,
        paymentRequest,
        organization,
      );
      return json(200, {
        checkout: {
          payment_request_id: paymentRequest.id,
          session_id: result.session.id,
          url: result.session.url,
          expires_at: new Date(result.session.expires_at * 1000).toISOString(),
          reused: result.reused,
        },
      });
    } catch (error) {
      const mapped = mapThrownError(error);
      if (
        attempt &&
        mapped.code === "checkout_creation_failed" &&
        !mapped.ambiguous
      ) {
        try {
          await deps.store.finishAttempt(
            attempt.attempt_id,
            "failed",
            mapped.code,
          );
        } catch {
          // The sanitized Checkout failure remains the client-facing result.
        }
      }
      return errorResponse(mapped.status, mapped.code);
    }
  };
}
