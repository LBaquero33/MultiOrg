import {
  createClient,
  type SupabaseClient,
} from "https://esm.sh/@supabase/supabase-js@2.49.1";
import {
  type CheckoutConnectedAccount,
  type CheckoutMembership,
  type CheckoutOrganization,
  type CheckoutParentLink,
  type CheckoutPaymentRequest,
  createPaymentRequestCheckoutHandler,
  type PaymentCheckoutStore,
  type PreparedCheckoutAttempt,
  type StripeHostedCheckout,
} from "../_shared/payment_checkout.ts";
import { createConnectedStripeCheckoutGateway } from "../_shared/stripe_connected_payments.ts";

const env = (name: string) => (Deno.env.get(name) ?? "").trim();
const supabaseUrl = env("SUPABASE_URL") || env("DHD_SUPABASE_URL");
const anonKey = env("SUPABASE_ANON_KEY") || env("DHD_SUPABASE_ANON_KEY");
const serviceKey = env("SUPABASE_SERVICE_ROLE_KEY") ||
  env("DHD_SERVICE_ROLE_KEY");
const stripeSecretKey = env("STRIPE_SECRET_KEY");
const successUrl = env("HOME_PLATE_PAYMENT_SUCCESS_URL");
const cancelUrl = env("HOME_PLATE_PAYMENT_CANCEL_URL");
const feeBasisPointsText = env("HOME_PLATE_PAYMENT_PLATFORM_FEE_BPS") || "0";
const feeBasisPoints = Number(feeBasisPointsText);

function row<T>(value: unknown, code: string): T {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error(code);
  }
  return value as T;
}

function createStore(admin: SupabaseClient): PaymentCheckoutStore {
  return {
    async authenticate(request) {
      const authorization = request.headers.get("Authorization") ?? "";
      if (!authorization) return null;
      const actorClient = createClient(supabaseUrl, anonKey, {
        global: { headers: { Authorization: authorization } },
        auth: { persistSession: false, autoRefreshToken: false },
      });
      const { data, error } = await actorClient.auth.getUser();
      if (error) return null;
      return data.user?.id ?? null;
    },

    async paymentRequest(paymentRequestId) {
      const { data, error } = await admin.from("sd_payment_requests")
        .select(
          "id,request_batch_id,org_id,child_id,title,notes,amount_cents,currency,status",
        )
        .eq("id", paymentRequestId)
        .maybeSingle();
      if (error) throw new Error("payment_request_lookup_failed");
      return data
        ? row<CheckoutPaymentRequest>(data, "payment_request_invalid")
        : null;
    },

    async organization(orgId) {
      const { data, error } = await admin.from("sd_orgs")
        .select("id,name,status")
        .eq("id", orgId)
        .maybeSingle();
      if (error) throw new Error("organization_lookup_failed");
      return data
        ? row<CheckoutOrganization>(data, "organization_invalid")
        : null;
    },

    async membership(orgId, userId) {
      const { data, error } = await admin.from("sd_org_memberships")
        .select("role,status")
        .eq("org_id", orgId)
        .eq("user_id", userId)
        .maybeSingle();
      if (error) throw new Error("membership_lookup_failed");
      return data ? row<CheckoutMembership>(data, "membership_invalid") : null;
    },

    async parentLink(orgId, parentId, childId) {
      const { data, error } = await admin.from("sd_parent_child_links")
        .select("can_pay")
        .eq("org_id", orgId)
        .eq("parent_id", parentId)
        .eq("child_id", childId)
        .maybeSingle();
      if (error) throw new Error("parent_link_lookup_failed");
      return data ? row<CheckoutParentLink>(data, "parent_link_invalid") : null;
    },

    async connectedAccount(orgId) {
      const { data, error } = await admin.from("sd_connected_payment_accounts")
        .select([
          "org_id",
          "provider",
          "provider_account_id",
          "onboarding_status",
          "details_submitted",
          "charges_enabled",
          "payouts_enabled",
          "disabled_reason",
          "requirements_currently_due",
          "requirements_past_due",
        ].join(","))
        .eq("org_id", orgId)
        .maybeSingle();
      if (error) throw new Error("connected_account_lookup_failed");
      return data
        ? row<CheckoutConnectedAccount>(data, "connected_account_invalid")
        : null;
    },

    async prepareCheckout(actorId, paymentRequestId, requestedFeeBasisPoints) {
      const { data, error } = await admin.rpc(
        "sd_prepare_payment_request_checkout",
        {
          p_actor_id: actorId,
          p_payment_request_id: paymentRequestId,
          p_fee_bps: requestedFeeBasisPoints,
        },
      );
      if (error) throw new Error(error.message);
      return row<PreparedCheckoutAttempt>(
        data,
        "checkout_prepare_response_invalid",
      );
    },

    async finalizeCheckout(attemptId, session) {
      const { error } = await admin.rpc(
        "sd_finalize_payment_request_checkout",
        {
          p_attempt_id: attemptId,
          p_stripe_checkout_session_id: session.id,
          p_stripe_payment_intent_id: session.payment_intent_id,
          p_expires_at: new Date(session.expires_at * 1000).toISOString(),
        },
      );
      if (error) throw new Error(error.message);
    },

    async finishAttempt(attemptId, status, errorCode) {
      const { error } = await admin.rpc(
        "sd_finish_payment_request_checkout_attempt",
        {
          p_attempt_id: attemptId,
          p_status: status,
          p_error_code: errorCode,
        },
      );
      if (error) throw new Error(error.message);
    },
  };
}

const admin = createClient(supabaseUrl, serviceKey, {
  auth: { persistSession: false, autoRefreshToken: false },
});

const handler = createPaymentRequestCheckoutHandler({
  store: createStore(admin),
  stripe: createConnectedStripeCheckoutGateway(stripeSecretKey),
  stripeConfigured: Boolean(
    supabaseUrl && anonKey && serviceKey && stripeSecretKey,
  ),
  successUrl,
  cancelUrl,
  feeBasisPoints,
});

Deno.serve(handler);
