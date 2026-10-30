import { classifyWebhookClaim, webhookClaimDisposition } from "./webhook_claim.ts";

Deno.test("webhook claim distinguishes completed, in-flight, and owned leases", () => {
  const id = "11111111-1111-4111-8111-111111111111";
  const lease = "22222222-2222-4222-8222-222222222222";
  if (classifyWebhookClaim({ claimed: false, state: "processed", id }) !== "processed") {
    throw new Error("processed Stripe events must be acknowledged as duplicates");
  }
  if (classifyWebhookClaim({ claimed: false, state: "in_flight", id }) !== "in_flight") {
    throw new Error("live leases must trigger a retryable response");
  }
  const retry = webhookClaimDisposition({
    claimed: false,
    state: "in_flight",
    id,
    retry_after_seconds: 420,
  });
  if (retry.kind !== "retry" || retry.status !== 503 || retry.retryAfterSeconds !== 420) {
    throw new Error("in-flight events must remain retryable until their lease expires");
  }
  const processed = webhookClaimDisposition({ claimed: false, state: "processed", id });
  if (processed.kind !== "acknowledge" || processed.status !== 200) {
    throw new Error("only final processed events should be acknowledged as duplicates");
  }
  if (classifyWebhookClaim({ claimed: true, state: "claimed", id, lease_token: lease }) !== "claimed") {
    throw new Error("only an owned lease may process the event");
  }
  if (classifyWebhookClaim({ claimed: true, id, lease_token: "forged" }) !== "invalid") {
    throw new Error("malformed lease tokens must fail closed");
  }
});
