export type NotificationDeliveryWakeupResult = {
  outcome:
    | "succeeded"
    | "unauthorized"
    | "worker_failed"
    | "network_failed"
    | "not_configured";
  status: number | null;
};

type Fetcher = typeof fetch;

export async function wakeNotificationDeliveriesAfterCommit(
  supabaseUrl: string,
  internalSecret: string,
  fetcher: Fetcher = fetch,
): Promise<NotificationDeliveryWakeupResult> {
  const baseURL = supabaseUrl.trim();
  const secret = internalSecret.trim();
  if (!baseURL || !secret) {
    console.warn(JSON.stringify({
      event: "notification_delivery_producer_wakeup",
      outcome: "not_configured",
    }));
    return { outcome: "not_configured", status: null };
  }

  try {
    const endpoint = new URL(
      "/functions/v1/process-notification-deliveries",
      baseURL,
    );
    const response = await fetcher(endpoint, {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-home-plate-worker-secret": secret,
      },
      body: JSON.stringify({ source: "producer_commit" }),
      signal: AbortSignal.timeout(5_000),
    });
    const outcome = response.status === 200
      ? "succeeded"
      : response.status === 401
      ? "unauthorized"
      : "worker_failed";
    console.log(JSON.stringify({
      event: "notification_delivery_producer_wakeup",
      outcome,
      status: response.status,
    }));
    return { outcome, status: response.status };
  } catch {
    console.warn(JSON.stringify({
      event: "notification_delivery_producer_wakeup",
      outcome: "network_failed",
    }));
    return { outcome: "network_failed", status: null };
  }
}
