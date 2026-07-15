import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import {
  type ConnectedPaymentWebhookStore,
  createConnectedPaymentWebhookHandler,
  type ReconcileResult,
} from "../_shared/connected_payment_webhook.ts";
import { verifyStripeSignature } from "../_shared/stripe.ts";

const env = (name: string) => (Deno.env.get(name) ?? "").trim();
const supabaseUrl = env("SUPABASE_URL") || env("DHD_SUPABASE_URL");
const serviceKey = env("SUPABASE_SERVICE_ROLE_KEY") ||
  env("DHD_SERVICE_ROLE_KEY");
const signingSecret = env("STRIPE_CONNECT_PAYMENTS_WEBHOOK_SECRET");

const admin = createClient(supabaseUrl, serviceKey, {
  auth: { persistSession: false, autoRefreshToken: false },
});

const store: ConnectedPaymentWebhookStore = {
  async claim(event) {
    const summary = {
      id: event.id,
      type: event.type,
      account: event.account,
      created: event.created,
      object_id: typeof event.data.object.id === "string"
        ? event.data.object.id
        : null,
    };
    const { data, error } = await admin.from("sd_webhook_events").insert({
      provider: "stripe",
      provider_account_id: event.account,
      provider_event_id: event.id,
      event_type: event.type,
      processing_status: "processing",
      payload: summary,
      attempt_count: 1,
    }).select("id").single();
    if (!error && data?.id) {
      return { kind: "claimed", ledgerId: String(data.id) };
    }
    if (error?.code !== "23505") {
      throw new Error("webhook_ledger_insert_failed");
    }

    const { data: existing, error: existingError } = await admin.from(
      "sd_webhook_events",
    )
      .select("id,processing_status,attempt_count,received_at")
      .eq("provider", "stripe")
      .eq("provider_account_id", event.account)
      .eq("provider_event_id", event.id)
      .maybeSingle();
    if (existingError || !existing?.id) {
      throw new Error("webhook_ledger_lookup_failed");
    }
    if (existing.processing_status === "processed") {
      return { kind: "duplicate" };
    }

    const staleBefore = Date.now() - 5 * 60 * 1000;
    const receivedAt = Date.parse(String(existing.received_at ?? ""));
    if (
      existing.processing_status === "processing" &&
      Number.isFinite(receivedAt) && receivedAt > staleBefore
    ) {
      return { kind: "duplicate" };
    }

    // Optimistic attempt-count matching gives exactly one worker ownership of
    // a failed or stale-processing event. Refreshing received_at also gives a
    // worker that crashes a bounded lease instead of stranding the event.
    const nextAttemptCount = Number(existing.attempt_count ?? 0) + 1;
    const { data: reclaimed, error: retryError } = await admin.from(
      "sd_webhook_events",
    ).update({
      processing_status: "processing",
      attempt_count: nextAttemptCount,
      received_at: new Date().toISOString(),
      error_message: null,
    })
      .eq("id", existing.id)
      .eq("processing_status", existing.processing_status)
      .eq("attempt_count", Number(existing.attempt_count ?? 0))
      .select("id")
      .maybeSingle();
    if (retryError) throw new Error("webhook_ledger_retry_failed");
    if (!reclaimed?.id) return { kind: "duplicate" };
    return { kind: "claimed", ledgerId: String(existing.id) };
  },

  async complete(ledgerId, _outcome) {
    const { error } = await admin.from("sd_webhook_events").update({
      processing_status: "processed",
      processed_at: new Date().toISOString(),
      error_message: null,
    }).eq("id", ledgerId);
    if (error) throw new Error("webhook_ledger_complete_failed");
  },

  async fail(ledgerId, errorCode) {
    const { error } = await admin.from("sd_webhook_events").update({
      processing_status: "failed",
      error_message: errorCode.slice(0, 120),
    }).eq("id", ledgerId);
    if (error) throw new Error("webhook_ledger_fail_failed");
  },

  async reconcile(input) {
    const { data, error } = await admin.rpc(
      "sd_reconcile_payment_request_payment",
      {
        p_attempt_id: input.attemptId,
        p_org_id: input.orgId,
        p_payment_request_id: input.paymentRequestId,
        p_child_id: input.childId,
        p_stripe_account_id: input.stripeAccountId,
        p_stripe_checkout_session_id: input.checkoutSessionId,
        p_stripe_payment_intent_id: input.paymentIntentId,
        p_stripe_charge_id: input.chargeId,
        p_amount_cents: input.amountCents,
        p_currency: input.currency,
      },
    );
    if (error) throw new Error(error.message);
    if (
      !data || typeof data !== "object" || Array.isArray(data) ||
      typeof data.kind !== "string"
    ) {
      throw new Error("payment_reconciliation_response_invalid");
    }
    return data as ReconcileResult;
  },

  async expireAttempt(attemptId) {
    const { error } = await admin.rpc(
      "sd_finish_payment_request_checkout_attempt",
      {
        p_attempt_id: attemptId,
        p_status: "expired",
        p_error_code: "provider_session_expired",
      },
    );
    if (error) throw new Error(error.message);
  },
};

const handler = createConnectedPaymentWebhookHandler({
  signingSecretConfigured: Boolean(supabaseUrl && serviceKey && signingSecret),
  verifySignature: (rawBody, signature) =>
    verifyStripeSignature(rawBody, signature, signingSecret),
  store,
});

Deno.serve(handler);
