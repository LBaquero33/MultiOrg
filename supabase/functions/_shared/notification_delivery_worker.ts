import type { APNSDeliveryFacts, APNSSendResult } from "./apns.ts";

export const NOTIFICATION_DELIVERY_BATCH_SIZE = 25;
export const NOTIFICATION_DELIVERY_MAX_ATTEMPTS = 5;
export const NOTIFICATION_DELIVERY_COMMIT_POLL_MILLISECONDS = 600;

export type DeliveryWakeupSource =
  | "queue_trigger"
  | "database_queue"
  | "cron_fallback"
  | "producer_commit"
  | "manual";

export type DeliveryClaim = {
  claim_token: string;
  deliveries: APNSDeliveryFacts[];
};

export type DeliveryFinalization = {
  delivery_id: string;
  status: "sent" | "retryable" | "failed" | "skipped";
  attempt_count: number;
};

export interface NotificationDeliveryStore {
  claim(limit: number, claimToken: string): Promise<DeliveryClaim>;
  finalize(input: {
    deliveryId: string;
    claimToken: string;
    outcome: APNSSendResult["outcome"];
    apnsId: string | null;
    apnsStatus: number | null;
    errorCode: string;
    nextAttemptAt: string | null;
  }): Promise<DeliveryFinalization>;
}

export interface NotificationPushSender {
  send(delivery: APNSDeliveryFacts): Promise<APNSSendResult>;
}

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function json(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });
}

export function safeSecretEquals(actual: string, expected: string): boolean {
  const left = new TextEncoder().encode(actual);
  const right = new TextEncoder().encode(expected);
  let difference = left.length ^ right.length;
  const length = Math.max(left.length, right.length);
  for (let index = 0; index < length; index += 1) {
    difference |= (left[index] ?? 0) ^ (right[index] ?? 0);
  }
  return difference === 0;
}

export function retryDelaySeconds(attemptCount: number): number {
  const schedule = [30, 120, 600, 1_800];
  return schedule[Math.max(0, Math.min(attemptCount - 1, schedule.length - 1))];
}

function nextAttempt(attemptCount: number, now: () => number): string | null {
  if (attemptCount >= NOTIFICATION_DELIVERY_MAX_ATTEMPTS) return null;
  return new Date(now() + retryDelaySeconds(attemptCount) * 1_000)
    .toISOString();
}

function validDelivery(value: APNSDeliveryFacts): boolean {
  return UUID_PATTERN.test(value.delivery_id) &&
    Number.isSafeInteger(value.attempt_count) && value.attempt_count >= 1 &&
    UUID_PATTERN.test(value.notification.id) &&
    UUID_PATTERN.test(value.notification.org_id) &&
    UUID_PATTERN.test(value.device.id) &&
    /^[0-9a-f]{64,400}$/.test(value.device.device_token) &&
    value.device.device_token.length % 2 === 0 &&
    Number.isSafeInteger(value.unread_count) && value.unread_count >= 0;
}

function validClaim(claim: DeliveryClaim, claimToken: string): boolean {
  return claim.claim_token === claimToken && Array.isArray(claim.deliveries) &&
    !claim.deliveries.some((delivery) => !validDelivery(delivery));
}

async function wakeupSource(request: Request): Promise<DeliveryWakeupSource> {
  try {
    const value: unknown = await request.json();
    if (typeof value !== "object" || value === null || Array.isArray(value)) {
      return "manual";
    }
    const source = (value as Record<string, unknown>).source;
    if (
      source === "queue_trigger" || source === "database_queue" ||
      source === "cron_fallback" || source === "producer_commit"
    ) return source;
  } catch {
    // A manual invocation does not need a JSON body.
  }
  return "manual";
}

function defaultDelay(milliseconds: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

export function createNotificationDeliveryWorkerHandler(
  store: NotificationDeliveryStore,
  sender: NotificationPushSender,
  internalSecret: string,
  now: () => number = () => Date.now(),
  delay: (milliseconds: number) => Promise<void> = defaultDelay,
) {
  return async (request: Request): Promise<Response> => {
    if (request.method !== "POST") {
      return json(405, { error: "method_not_allowed" });
    }
    const suppliedSecret = request.headers.get("x-home-plate-worker-secret") ??
      "";
    if (!internalSecret || !safeSecretEquals(suppliedSecret, internalSecret)) {
      return json(401, { error: "worker_auth_required" });
    }

    const source = await wakeupSource(request);
    const claimToken = crypto.randomUUID();
    let claim: DeliveryClaim;
    let polls = 1;
    try {
      claim = await store.claim(NOTIFICATION_DELIVERY_BATCH_SIZE, claimToken);
      if (!validClaim(claim, claimToken)) {
        return json(500, { error: "delivery_claim_invalid" });
      }
      if (
        claim.deliveries.length === 0 &&
        (source === "queue_trigger" || source === "database_queue")
      ) {
        console.log(JSON.stringify({
          event: "apns_delivery_commit_followup",
          claim_token: claimToken,
          source,
          delay_milliseconds: NOTIFICATION_DELIVERY_COMMIT_POLL_MILLISECONDS,
        }));
        await delay(NOTIFICATION_DELIVERY_COMMIT_POLL_MILLISECONDS);
        polls = 2;
        claim = await store.claim(NOTIFICATION_DELIVERY_BATCH_SIZE, claimToken);
      }
    } catch {
      return json(503, { error: "delivery_claim_unavailable" });
    }
    if (!validClaim(claim, claimToken)) {
      return json(500, { error: "delivery_claim_invalid" });
    }

    const counts = {
      claimed: claim.deliveries.length,
      sent: 0,
      retryable: 0,
      failed: 0,
      polls,
      source,
    };
    await Promise.all(claim.deliveries.map(async (delivery) => {
      const result = await sender.send(delivery);
      const retryAt = result.outcome === "retryable"
        ? nextAttempt(delivery.attempt_count, now)
        : null;
      try {
        const finalization = await store.finalize({
          deliveryId: delivery.delivery_id,
          claimToken,
          outcome: result.outcome,
          apnsId: result.apnsId,
          apnsStatus: result.status,
          errorCode: result.reason.slice(0, 120),
          nextAttemptAt: retryAt,
        });
        if (finalization.status === "sent") counts.sent += 1;
        else if (finalization.status === "retryable") counts.retryable += 1;
        else counts.failed += 1;
      } catch {
        counts.failed += 1;
      }

      console.log(JSON.stringify({
        event: "apns_delivery_result",
        delivery_id: delivery.delivery_id,
        category: delivery.notification.category,
        platform: delivery.device.platform,
        environment: delivery.device.environment,
        apns_status: result.status,
        reason: result.reason,
        decision: result.outcome,
        attempt_count: delivery.attempt_count,
        token_suffix: delivery.device.device_token.slice(-6),
      }));
    }));

    console.log(JSON.stringify({
      event: "apns_delivery_batch",
      claim_token: claimToken,
      ...counts,
    }));
    return json(200, counts);
  };
}
