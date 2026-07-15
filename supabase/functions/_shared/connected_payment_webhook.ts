export type ConnectedWebhookEvent = {
  id: string;
  type: string;
  account: string;
  created: number | null;
  data: { object: Record<string, unknown> };
};

export type WebhookClaim =
  | { kind: "claimed"; ledgerId: string }
  | { kind: "duplicate" };

export type ReconcileInput = {
  attemptId: string;
  orgId: string;
  paymentRequestId: string;
  childId: string;
  stripeAccountId: string;
  checkoutSessionId: string | null;
  paymentIntentId: string;
  chargeId: string | null;
  amountCents: number;
  currency: string;
};

export type ReconcileResult = {
  kind:
    | "paid"
    | "duplicate"
    | "canceled_request_anomaly"
    | "duplicate_payment_anomaly";
  payment_request_id: string;
  payment_id?: string;
  attempt_id?: string;
};

export interface ConnectedPaymentWebhookStore {
  claim(event: ConnectedWebhookEvent): Promise<WebhookClaim>;
  complete(ledgerId: string, outcome: string): Promise<void>;
  fail(ledgerId: string, errorCode: string): Promise<void>;
  reconcile(input: ReconcileInput): Promise<ReconcileResult>;
  expireAttempt(attemptId: string): Promise<void>;
}

export type ConnectedPaymentWebhookDependencies = {
  signingSecretConfigured: boolean;
  verifySignature(rawBody: string, signature: string): Promise<boolean>;
  store: ConnectedPaymentWebhookStore;
};

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const SUPPORTED_EVENTS = new Set([
  "checkout.session.completed",
  "checkout.session.expired",
  "payment_intent.succeeded",
  "payment_intent.payment_failed",
  "charge.refunded",
]);

function json(status: number, body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });
}

function record(value: unknown): Record<string, unknown> {
  return value && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown>
    : {};
}

function stringId(value: unknown): string | null {
  if (typeof value === "string" && value.length > 0) return value;
  const nested = record(value);
  return typeof nested.id === "string" ? nested.id : null;
}

function integer(value: unknown): number | null {
  return typeof value === "number" && Number.isSafeInteger(value)
    ? value
    : null;
}

function parseEvent(value: unknown): ConnectedWebhookEvent | null {
  const event = record(value);
  const account = typeof event.account === "string" ? event.account : "";
  const data = record(event.data);
  const object = record(data.object);
  if (
    typeof event.id !== "string" || !event.id.startsWith("evt_") ||
    typeof event.type !== "string" ||
    !account.startsWith("acct_") ||
    Object.keys(object).length === 0
  ) return null;
  return {
    id: event.id,
    type: event.type,
    account,
    created: integer(event.created),
    data: { object },
  };
}

function metadataIdentifiers(object: Record<string, unknown>) {
  const metadata = record(object.metadata);
  const attemptId = metadata.home_plate_checkout_attempt_id;
  const orgId = metadata.home_plate_org_id;
  const paymentRequestId = metadata.home_plate_payment_request_id;
  const childId = metadata.home_plate_child_id;
  if (
    typeof attemptId !== "string" || !UUID_PATTERN.test(attemptId) ||
    typeof orgId !== "string" || !UUID_PATTERN.test(orgId) ||
    typeof paymentRequestId !== "string" ||
    !UUID_PATTERN.test(paymentRequestId) ||
    typeof childId !== "string" || !UUID_PATTERN.test(childId)
  ) throw new Error("payment_metadata_invalid");
  return { attemptId, orgId, paymentRequestId, childId };
}

function checkoutSuccessInput(
  event: ConnectedWebhookEvent,
): ReconcileInput | null {
  const object = event.data.object;
  if (object.payment_status !== "paid") return null;
  const ids = metadataIdentifiers(object);
  const paymentIntentId = stringId(object.payment_intent);
  const amountCents = integer(object.amount_total);
  const currency = typeof object.currency === "string"
    ? object.currency.toLowerCase()
    : "";
  if (
    !paymentIntentId || amountCents === null || amountCents <= 0 ||
    !/^[a-z]{3}$/.test(currency)
  ) {
    throw new Error("payment_event_invalid");
  }
  return {
    ...ids,
    stripeAccountId: event.account,
    checkoutSessionId: stringId(object.id),
    paymentIntentId,
    chargeId: null,
    amountCents,
    currency,
  };
}

function paymentIntentSuccessInput(
  event: ConnectedWebhookEvent,
): ReconcileInput {
  const object = event.data.object;
  const ids = metadataIdentifiers(object);
  const paymentIntentId = stringId(object.id);
  const amountCents = integer(object.amount_received);
  const currency = typeof object.currency === "string"
    ? object.currency.toLowerCase()
    : "";
  if (
    !paymentIntentId || amountCents === null || amountCents <= 0 ||
    !/^[a-z]{3}$/.test(currency)
  ) {
    throw new Error("payment_event_invalid");
  }
  return {
    ...ids,
    stripeAccountId: event.account,
    checkoutSessionId: null,
    paymentIntentId,
    chargeId: stringId(object.latest_charge),
    amountCents,
    currency,
  };
}

function anomalyCode(message: string): string | null {
  for (
    const code of [
      "payment_metadata_invalid",
      "payment_event_invalid",
      "checkout_attempt_not_found",
      "payment_intent_mismatch",
      "payment_amount_mismatch",
      "payment_currency_mismatch",
      "payment_request_not_found",
      "payment_request_not_open",
    ]
  ) {
    if (message.includes(code)) return code;
  }
  return null;
}

export function createConnectedPaymentWebhookHandler(
  deps: ConnectedPaymentWebhookDependencies,
): (request: Request) => Promise<Response> {
  return async (request: Request): Promise<Response> => {
    if (request.method !== "POST") {
      return json(405, { error: "method_not_allowed" });
    }
    if (!deps.signingSecretConfigured) {
      return json(500, { error: "webhook_configuration_missing" });
    }

    const signature = request.headers.get("Stripe-Signature") ?? "";
    if (!signature) return json(400, { error: "missing_signature" });
    const rawBody = await request.text();
    if (!await deps.verifySignature(rawBody, signature)) {
      return json(400, { error: "invalid_signature" });
    }

    let event: ConnectedWebhookEvent | null;
    try {
      event = parseEvent(JSON.parse(rawBody));
    } catch {
      return json(400, { error: "invalid_json" });
    }
    if (!event) return json(400, { error: "invalid_event" });

    let claim: WebhookClaim;
    try {
      claim = await deps.store.claim(event);
    } catch {
      return json(500, { error: "webhook_ledger_unavailable" });
    }
    if (claim.kind === "duplicate") {
      return json(200, { received: true, duplicate: true });
    }

    try {
      let outcome = "ignored";
      if (SUPPORTED_EVENTS.has(event.type)) {
        switch (event.type) {
          case "checkout.session.completed": {
            const input = checkoutSuccessInput(event);
            if (input) outcome = (await deps.store.reconcile(input)).kind;
            else outcome = "awaiting_payment_confirmation";
            break;
          }
          case "payment_intent.succeeded":
            outcome =
              (await deps.store.reconcile(paymentIntentSuccessInput(event)))
                .kind;
            break;
          case "checkout.session.expired": {
            const attemptId = metadataIdentifiers(event.data.object).attemptId;
            await deps.store.expireAttempt(attemptId);
            outcome = "expired";
            break;
          }
          case "payment_intent.payment_failed":
            // The hosted session may still permit another payment attempt. The
            // request remains open and provider state remains authoritative.
            outcome = "payment_failed_request_open";
            break;
          case "charge.refunded":
            // Refund reconciliation is intentionally deferred; retain the
            // signed event in the ledger without regressing paid state.
            outcome = "refund_reconciliation_deferred";
            break;
        }
      }
      await deps.store.complete(claim.ledgerId, outcome);
      return json(200, {
        received: true,
        outcome,
        anomaly: outcome.endsWith("anomaly"),
      });
    } catch (error) {
      const message = error instanceof Error
        ? error.message
        : "webhook_processing_failed";
      const anomaly = anomalyCode(message);
      await deps.store.fail(
        claim.ledgerId,
        anomaly ?? "webhook_processing_failed",
      );
      if (anomaly) {
        // The signed event is quarantined in the failed ledger for operations;
        // retrying the same invalid financial facts cannot make them valid.
        return json(200, { received: true, anomaly: true, error: anomaly });
      }
      return json(500, { error: "webhook_processing_failed" });
    }
  };
}
