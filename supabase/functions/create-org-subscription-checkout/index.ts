import { env, isUuid, json, requireBillingAdministrator } from "../_shared/org_billing.ts";
import { formBody, stripeRequest } from "../_shared/stripe.ts";

Deno.serve(async (req) => {
  if (req.method !== "POST") return json(405, { error: "method_not_allowed" });
  let body: { org_id?: string };
  try { body = await req.json(); } catch { return json(400, { error: "invalid_json" }); }
  const orgId = String(body.org_id ?? "").trim();
  if (!isUuid(orgId)) return json(400, { error: "invalid_org_id" });
  const secretKey = env("STRIPE_SECRET_KEY");
  const priceId = env("STRIPE_ORG_MONTHLY_PRICE_ID");
  const successUrl = env("HOME_PLATE_BILLING_SUCCESS_URL");
  const cancelUrl = env("HOME_PLATE_BILLING_CANCEL_URL");
  if (!secretKey || !priceId || !successUrl || !cancelUrl) return json(500, { error: "missing_stripe_configuration" });

  try {
    const { admin, organization } = await requireBillingAdministrator(req, orgId);
    const { data: current } = await admin.from("sd_org_subscriptions")
      .select("id,status").eq("org_id", orgId).eq("provider", "stripe").in("status", ["active", "trialing"]).limit(1);
    if ((current ?? []).length) return json(409, { error: "organization_subscription_already_active" });

    const { data: account, error: accountError } = await admin.from("sd_org_billing_accounts")
      .select("provider_customer_id,billing_email").eq("org_id", orgId).maybeSingle();
    if (accountError) throw new Error("billing_account_lookup_failed");
    let customerId = account?.provider_customer_id as string | null;
    if (!customerId) {
      const customer = await stripeRequest<{ id: string }>(secretKey, "/customers", {
        form: formBody({
          email: account?.billing_email ?? organization.billing_email ?? organization.support_email ?? undefined,
          name: organization.name,
          "metadata[org_id]": orgId,
          "metadata[subscription_type]": "organization",
        }),
        idempotencyKey: `homeplate-org-customer-${orgId}`,
      });
      customerId = customer.id;
      const { error: saveError } = await admin.from("sd_org_billing_accounts").upsert({
        org_id: orgId, provider: "stripe", provider_customer_id: customerId,
        billing_email: account?.billing_email ?? organization.billing_email ?? organization.support_email ?? null,
      }, { onConflict: "org_id" });
      if (saveError) throw new Error("billing_customer_save_failed");
    }

    const session = await stripeRequest<{ url: string | null }>(secretKey, "/checkout/sessions", {
      form: formBody({
        mode: "subscription", customer: customerId,
        "line_items[0][price]": priceId, "line_items[0][quantity]": 1,
        success_url: successUrl, cancel_url: cancelUrl,
        "metadata[org_id]": orgId, "metadata[subscription_type]": "organization",
        "subscription_data[metadata][org_id]": orgId,
        "subscription_data[metadata][subscription_type]": "organization",
      }),
      idempotencyKey: `homeplate-org-checkout-${orgId}`,
    });
    if (!session.url) throw new Error("checkout_url_missing");
    return json(200, { url: session.url });
  } catch (error) {
    const message = error instanceof Error ? error.message : "checkout_failed";
    const status = ["missing_auth", "invalid_auth"].includes(message) ? 401 : message.includes("required") ? 403 : 500;
    return json(status, { error: message });
  }
});
