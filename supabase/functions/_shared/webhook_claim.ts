const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export type WebhookClaimState = "claimed" | "processed" | "in_flight" | "invalid";

export type WebhookClaimDisposition =
  | { kind: "process" }
  | { kind: "acknowledge"; status: 200 }
  | { kind: "retry"; status: 503; retryAfterSeconds: number }
  | { kind: "error"; status: 500 };

export function classifyWebhookClaim(value: unknown): WebhookClaimState {
  if (!value || typeof value !== "object") return "invalid";
  const claim = value as Record<string, unknown>;
  if (claim.claimed === true) {
    return typeof claim.id === "string" && UUID.test(claim.id) &&
        typeof claim.lease_token === "string" && UUID.test(claim.lease_token)
      ? "claimed"
      : "invalid";
  }
  if (claim.state === "processed") return "processed";
  if (claim.state === "in_flight") return "in_flight";
  return "invalid";
}

export function webhookClaimDisposition(value: unknown): WebhookClaimDisposition {
  const state = classifyWebhookClaim(value);
  if (state === "claimed") return { kind: "process" };
  if (state === "processed") return { kind: "acknowledge", status: 200 };
  if (state === "invalid") return { kind: "error", status: 500 };
  const claim = value as Record<string, unknown>;
  const requested = Number(claim.retry_after_seconds);
  return {
    kind: "retry",
    status: 503,
    retryAfterSeconds: Math.max(30, Math.min(900, Number.isFinite(requested) && requested > 0 ? requested : 60)),
  };
}
