import { createStripeConnectRefreshFallbackHandler } from "../_shared/stripe_connect.ts";

Deno.serve(createStripeConnectRefreshFallbackHandler());
