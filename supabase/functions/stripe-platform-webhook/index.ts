import { createClient, type SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { env, json } from "../_shared/org_billing.ts";
import { webhookClaimDisposition } from "../_shared/webhook_claim.ts";
import { stripeRequest, stripeSubscriptionSnapshot, stripeUnixToIso, verifyStripeSignature } from "../_shared/stripe.ts";

type StripeSubscription = Record<string, any>;
type AdminClient = SupabaseClient<any, "public", any>;

function stripeId(value: unknown): string | null {
  if (typeof value === "string") return value;
  if (value && typeof value === "object" && typeof (value as any).id === "string") return (value as any).id;
  return null;
}

function subscriptionPayload(subscription: StripeSubscription, orgId: string) {
  const snapshot = stripeSubscriptionSnapshot(subscription);
  const price = snapshot.item?.price as Record<string, unknown> | undefined ?? {};
  return {
    org_id: orgId,
    provider: "stripe",
    provider_subscription_id: String(subscription.id),
    provider_product_id: stripeId(price.product),
    provider_price_id: price.id ? String(price.id) : null,
    status: String(subscription.status ?? "unknown"),
    current_period_start: snapshot.currentPeriodStart,
    current_period_end: snapshot.currentPeriodEnd,
    cancel_at_period_end: snapshot.cancelAtPeriodEnd,
    canceled_at: stripeUnixToIso(subscription.canceled_at),
    provider_state: {
      customer_id: stripeId(subscription.customer),
      collection_method: subscription.collection_method ?? null,
      latest_invoice_id: stripeId(subscription.latest_invoice),
    },
  };
}

async function resolveOrgId(admin: AdminClient, subscription: StripeSubscription, fallbackMetadata: Record<string, any> = {}) {
  const metadataOrgId = String(subscription.metadata?.org_id ?? fallbackMetadata.org_id ?? "").trim();
  if (metadataOrgId) return metadataOrgId;
  const customerId = stripeId(subscription.customer);
  if (!customerId) return null;
  const { data } = await admin.from("sd_org_billing_accounts")
    .select("org_id").eq("provider", "stripe").eq("provider_customer_id", customerId).maybeSingle();
  return data?.org_id ? String(data.org_id) : null;
}

async function synchronizeSubscription(admin: AdminClient, secret: string, subscriptionId: string, metadata: Record<string, any> = {}) {
  const subscription = await stripeRequest<StripeSubscription>(secret, `/subscriptions/${encodeURIComponent(subscriptionId)}`);
  const orgId = await resolveOrgId(admin, subscription, metadata);
  if (!orgId) throw new Error("organization_resolution_failed");
  const { error } = await admin.from("sd_org_subscriptions")
    .upsert(subscriptionPayload(subscription, orgId), { onConflict: "provider_subscription_id" });
  if (error) throw new Error(`subscription_sync_failed:${error.message}`);
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json(405, { error: "method_not_allowed" });
  const secret = env("STRIPE_SECRET_KEY");
  const webhookSecret = env("STRIPE_PLATFORM_WEBHOOK_SECRET");
  const supabaseUrl = env("SUPABASE_URL") || env("DHD_SUPABASE_URL");
  const serviceKey = env("SUPABASE_SERVICE_ROLE_KEY") || env("DHD_SERVICE_ROLE_KEY");
  if (!secret || !webhookSecret || !supabaseUrl || !serviceKey) return json(500, { error: "missing_required_secrets" });

  const rawBody = await req.text();
  const valid = await verifyStripeSignature(rawBody, req.headers.get("Stripe-Signature") ?? "", webhookSecret);
  if (!valid) return json(400, { error: "invalid_signature" });
  let event: any;
  try { event = JSON.parse(rawBody); } catch { return json(400, { error: "invalid_json" }); }
  if (!event?.id || !event?.type) return json(400, { error: "invalid_event" });

  const admin = createClient(supabaseUrl, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });
  const providerAccountId = String(event.account ?? "") || null;
  const { data: claim, error: claimError } = await admin.rpc("sd_claim_webhook_event", {
    p_provider: "stripe",
    p_provider_event_id: String(event.id),
    p_provider_account_id: providerAccountId,
    p_event_type: String(event.type),
    p_payload: event,
    p_lease_seconds: 900,
  });
  const lease = Array.isArray(claim) ? claim[0] : claim;
  const disposition = webhookClaimDisposition(lease);
  const ledgerId = String(lease?.id ?? "");
  const leaseToken = String(lease?.lease_token ?? "");
  if (claimError || disposition.kind === "error") return json(500, { error: "webhook_ledger_claim_failed" });
  if (disposition.kind === "acknowledge") {
    return json(200, { received: true, duplicate: true });
  }
  if (disposition.kind === "retry") {
    return new Response(JSON.stringify({ received: false, retryable: true }), {
      status: disposition.status,
      headers: { "content-type": "application/json", "retry-after": String(disposition.retryAfterSeconds) },
    });
  }
  if (!ledgerId || !/^[0-9a-f-]{36}$/i.test(leaseToken)) {
    return json(500, { error: "webhook_ledger_claim_failed" });
  }

  try {
    const object = event.data?.object ?? {};
    switch (String(event.type)) {
      case "checkout.session.completed": {
        const subscriptionId = stripeId(object.subscription);
        if (subscriptionId) await synchronizeSubscription(admin, secret, subscriptionId, object.metadata ?? {});
        break;
      }
      case "customer.subscription.created":
      case "customer.subscription.updated":
      case "customer.subscription.deleted":
        await synchronizeSubscription(admin, secret, String(object.id), object.metadata ?? {});
        break;
      case "invoice.paid":
      case "invoice.payment_failed": {
        const subscriptionId = stripeId(object.subscription);
        if (subscriptionId) await synchronizeSubscription(admin, secret, subscriptionId, object.metadata ?? {});
        break;
      }
      default:
        break;
    }
    const { data: completed, error: completionError } = await admin.from("sd_webhook_events").update({
      processing_status: "processed", processed_at: new Date().toISOString(), error_message: null,
      processing_lease_until: null, processing_lease_token: null,
    }).eq("id", ledgerId).eq("processing_lease_token", leaseToken).select("id").maybeSingle();
    if (completionError || !completed) throw new Error("webhook_ledger_completion_failed");
    return json(200, { received: true });
  } catch (error) {
    const message = error instanceof Error ? error.message.slice(0, 1000) : "webhook_processing_failed";
    await admin.from("sd_webhook_events").update({
      processing_status: "failed", error_message: message,
      processing_lease_until: null, processing_lease_token: null,
    }).eq("id", ledgerId).eq("processing_lease_token", leaseToken);
    return json(500, { error: "webhook_processing_failed" });
  }
});
