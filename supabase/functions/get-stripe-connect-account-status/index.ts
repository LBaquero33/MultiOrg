import { env } from "../_shared/org_billing.ts";
import {
  createStripeConnectGateway,
  createStripeConnectStatusHandler,
} from "../_shared/stripe_connect.ts";
import {
  createConnectedPaymentAccountStore,
  requireStripeConnectAdministrator,
} from "../_shared/stripe_connect_supabase.ts";

const stripeSecret = env("STRIPE_SECRET_KEY");
const handler = createStripeConnectStatusHandler({
  stripeConfigured: Boolean(stripeSecret),
  gateway: createStripeConnectGateway(stripeSecret),
  authorize: async (request, orgId) => {
    const { admin } = await requireStripeConnectAdministrator(request, orgId);
    return createConnectedPaymentAccountStore(admin);
  },
});

Deno.serve(handler);
