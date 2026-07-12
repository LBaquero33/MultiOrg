import { env, isUuid, json, requireBillingAdministrator } from "../_shared/org_billing.ts";
import { formBody, stripeRequest } from "../_shared/stripe.ts";

Deno.serve(async (req) => {
  if (req.method !== "POST") return json(405, { error: "method_not_allowed" });
  let body: { org_id?: string };
  try { body = await req.json(); } catch { return json(400, { error: "invalid_json" }); }
  const orgId = String(body.org_id ?? "").trim();
  if (!isUuid(orgId)) return json(400, { error: "invalid_org_id" });
  const secretKey = env("STRIPE_SECRET_KEY");
  const returnUrl = env("HOME_PLATE_BILLING_PORTAL_RETURN_URL");
  if (!secretKey || !returnUrl) return json(500, { error: "missing_stripe_configuration" });
  try {
    const { admin } = await requireBillingAdministrator(req, orgId);
    const { data: account } = await admin.from("sd_org_billing_accounts")
      .select("provider_customer_id").eq("org_id", orgId).maybeSingle();
    const customerId = account?.provider_customer_id as string | null;
    if (!customerId) return json(404, { error: "organization_billing_customer_missing" });
    const session = await stripeRequest<{ url: string | null }>(secretKey, "/billing_portal/sessions", {
      form: formBody({ customer: customerId, return_url: returnUrl }),
    });
    if (!session.url) throw new Error("portal_url_missing");
    return json(200, { url: session.url });
  } catch (error) {
    const message = error instanceof Error ? error.message : "billing_portal_failed";
    const status = ["missing_auth", "invalid_auth"].includes(message) ? 401 : message.includes("required") ? 403 : 500;
    return json(status, { error: message });
  }
});
