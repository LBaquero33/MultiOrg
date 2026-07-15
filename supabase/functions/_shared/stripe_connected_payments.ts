import { formBody, stripeRequest, stripeUnixToIso } from "./stripe.ts";
import {
  type ConnectedCheckoutGateway,
  PaymentCheckoutError,
  type StripeCheckoutCreationInput,
  type StripeHostedCheckout,
} from "./payment_checkout.ts";

type StripeRequestOptions = {
  method?: "GET" | "POST";
  form?: URLSearchParams;
  idempotencyKey?: string;
  connectedAccountId?: string;
};

export type ConnectedStripeRequest = (
  secretKey: string,
  path: string,
  options?: StripeRequestOptions,
) => Promise<unknown>;

const defaultRequest: ConnectedStripeRequest = (secretKey, path, options) =>
  stripeRequest<unknown>(secretKey, path, options);

function record(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new PaymentCheckoutError("checkout_creation_failed", 502);
  }
  return value as Record<string, unknown>;
}

function stripeId(value: unknown): string | null {
  if (typeof value === "string") return value;
  if (
    value && typeof value === "object" &&
    typeof (value as { id?: unknown }).id === "string"
  ) {
    return String((value as { id: string }).id);
  }
  return null;
}

export function parseStripeHostedCheckout(
  value: unknown,
): StripeHostedCheckout {
  const session = record(value);
  if (typeof session.id !== "string" || !session.id.startsWith("cs_")) {
    throw new PaymentCheckoutError("checkout_creation_failed", 502);
  }
  const expiresAt = Number(session.expires_at);
  if (!Number.isFinite(expiresAt) || expiresAt <= 0) {
    throw new PaymentCheckoutError("checkout_creation_failed", 502);
  }
  return {
    id: session.id,
    url: typeof session.url === "string" ? session.url : null,
    status: typeof session.status === "string" ? session.status : "unknown",
    expires_at: expiresAt,
    payment_intent_id: stripeId(session.payment_intent),
  };
}

export function checkoutForm(
  input: StripeCheckoutCreationInput,
): URLSearchParams {
  const expiresAt = Math.floor(new Date(input.expiresAt).valueOf() / 1000);
  const metadata: Record<string, string | null> = {
    home_plate_schema_version: "payment_request_checkout_v1",
    home_plate_payment_request_id: input.paymentRequestId,
    home_plate_request_batch_id: input.requestBatchId,
    home_plate_org_id: input.organizationId,
    home_plate_child_id: input.childId,
    home_plate_payer_user_id: input.payerUserId,
    home_plate_checkout_attempt_id: input.checkoutAttemptId,
  };
  const values: Record<string, string | number | boolean | null> = {
    mode: "payment",
    success_url: input.successUrl,
    cancel_url: input.cancelUrl,
    expires_at: expiresAt,
    client_reference_id: input.paymentRequestId,
    "line_items[0][quantity]": 1,
    "line_items[0][price_data][currency]": input.currency,
    "line_items[0][price_data][unit_amount]": input.amountCents,
    "line_items[0][price_data][product_data][name]": input.title,
    "line_items[0][price_data][product_data][description]": input.description,
    "payment_intent_data[application_fee_amount]":
      input.applicationFeeAmountCents > 0
        ? input.applicationFeeAmountCents
        : null,
    "payment_intent_data[description]":
      `${input.organizationName}: ${input.title}`.slice(0, 500),
  };
  for (const [key, value] of Object.entries(metadata)) {
    values[`metadata[${key}]`] = value;
    values[`payment_intent_data[metadata][${key}]`] = value;
  }
  return formBody(values);
}

export function createConnectedStripeCheckoutGateway(
  secretKey: string,
  request: ConnectedStripeRequest = defaultRequest,
): ConnectedCheckoutGateway {
  return {
    async createCheckout(input) {
      try {
        const value = await request(secretKey, "/checkout/sessions", {
          form: checkoutForm(input),
          idempotencyKey: input.idempotencyKey,
          connectedAccountId: input.connectedAccountId,
        });
        return parseStripeHostedCheckout(value);
      } catch (error) {
        if (error instanceof PaymentCheckoutError) throw error;
        const message = error instanceof Error ? error.message : "";
        const statusMatch = message.match(/^stripe_(\d{3}):/);
        const status = statusMatch ? Number(statusMatch[1]) : 0;
        if (status === 429) {
          throw new PaymentCheckoutError("rate_limited", 429, true);
        }
        if (status >= 400 && status < 500) {
          throw new PaymentCheckoutError(
            "checkout_creation_failed",
            502,
            false,
          );
        }
        // Network failures and Stripe 5xx responses have an uncertain provider
        // outcome. Keep the internal attempt in `creating` so the same stable
        // Stripe idempotency key is used on the next request.
        throw new PaymentCheckoutError("checkout_creation_failed", 502, true);
      }
    },

    async retrieveCheckout(connectedAccountId, sessionId) {
      try {
        const value = await request(
          secretKey,
          `/checkout/sessions/${encodeURIComponent(sessionId)}`,
          { method: "GET", connectedAccountId },
        );
        return parseStripeHostedCheckout(value);
      } catch (error) {
        if (error instanceof PaymentCheckoutError) throw error;
        throw new PaymentCheckoutError("checkout_creation_failed", 502, true);
      }
    },
  };
}

export function checkoutExpiryIso(value: unknown): string | null {
  return stripeUnixToIso(value);
}
