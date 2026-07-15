import { env } from "../_shared/org_billing.ts";
import {
  createStripeConnectGateway,
  createStripeConnectOnboardingHandler,
} from "../_shared/stripe_connect.ts";
import {
  createConnectedPaymentAccountStore,
  requireStripeConnectAdministrator,
} from "../_shared/stripe_connect_supabase.ts";

const stripeSecret = env("STRIPE_SECRET_KEY");
const handler = createStripeConnectOnboardingHandler({
  stripeConfigured: Boolean(stripeSecret),
  returnUrl: env("HOME_PLATE_CONNECT_RETURN_URL"),
  refreshUrl: env("HOME_PLATE_CONNECT_REFRESH_URL"),
  gateway: createStripeConnectGateway(stripeSecret),
  authorize: async (request, orgId) => {
    const { admin } = await requireStripeConnectAdministrator(request, orgId);
    return createConnectedPaymentAccountStore(admin);
  },
});

Deno.serve(handler);
