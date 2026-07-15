import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import {
  type APNSConfiguration,
  type APNSDeliveryFacts,
  APNSSender,
} from "../_shared/apns.ts";
import {
  createNotificationDeliveryWorkerHandler,
  type DeliveryClaim,
  type DeliveryFinalization,
  type NotificationDeliveryStore,
} from "../_shared/notification_delivery_worker.ts";
import type {
  PushEnvironment,
  PushPlatform,
} from "../_shared/push_device_registration.ts";

const env = (name: string) => (Deno.env.get(name) ?? "").trim();
const url = env("SUPABASE_URL") || env("DHD_SUPABASE_URL");
const serviceKey = env("SUPABASE_SERVICE_ROLE_KEY") ||
  env("DHD_SERVICE_ROLE_KEY");
const internalSecret = env("NOTIFICATION_DELIVERY_WORKER_SECRET");

type JsonObject = Record<string, unknown>;
function isObject(value: unknown): value is JsonObject {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function deliveryFacts(value: unknown): APNSDeliveryFacts {
  if (
    !isObject(value) || !isObject(value.notification) || !isObject(value.device)
  ) {
    throw new Error("invalid_delivery_claim");
  }
  const notification = value.notification;
  const device = value.device;
  if (
    typeof value.delivery_id !== "string" ||
    !Number.isSafeInteger(value.attempt_count) ||
    !Number.isSafeInteger(value.unread_count) ||
    typeof notification.id !== "string" ||
    typeof notification.org_id !== "string" ||
    typeof notification.category !== "string" ||
    typeof notification.title !== "string" ||
    typeof notification.body !== "string" ||
    !(notification.action_route === null ||
      typeof notification.action_route === "string") ||
    !isObject(notification.action_payload) ||
    typeof device.id !== "string" ||
    !(device.platform === "ios" || device.platform === "macos") ||
    !(device.environment === "sandbox" ||
      device.environment === "production") ||
    typeof device.app_bundle_id !== "string" ||
    typeof device.device_token !== "string"
  ) throw new Error("invalid_delivery_claim");
  return value as unknown as APNSDeliveryFacts;
}

function makeStore(): NotificationDeliveryStore {
  const admin = createClient(url, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  return {
    async claim(limit, claimToken): Promise<DeliveryClaim> {
      const { data, error } = await admin.rpc(
        "sd_claim_notification_deliveries",
        {
          p_limit: limit,
          p_claim_token: claimToken,
        },
      );
      if (
        error || !isObject(data) || data.claim_token !== claimToken ||
        !Array.isArray(data.deliveries)
      ) {
        throw new Error("delivery_claim_failed");
      }
      return {
        claim_token: claimToken,
        deliveries: data.deliveries.map(deliveryFacts),
      };
    },

    async finalize(input): Promise<DeliveryFinalization> {
      const { data, error } = await admin.rpc(
        "sd_finalize_notification_delivery",
        {
          p_delivery_id: input.deliveryId,
          p_claim_token: input.claimToken,
          p_outcome: input.outcome,
          p_apns_id: input.apnsId,
          p_apns_status: input.apnsStatus,
          p_error_code: input.errorCode,
          p_next_attempt_at: input.nextAttemptAt,
        },
      );
      if (
        error || !isObject(data) || typeof data.delivery_id !== "string" ||
        !(data.status === "sent" || data.status === "retryable" ||
          data.status === "failed" || data.status === "skipped") ||
        !Number.isSafeInteger(data.attempt_count)
      ) throw new Error("delivery_finalize_failed");
      return {
        delivery_id: data.delivery_id,
        status: data.status,
        attempt_count: data.attempt_count as number,
      };
    },
  };
}

function configuration(): APNSConfiguration | null {
  const environment = env("APNS_ENVIRONMENT") as PushEnvironment;
  const config = {
    keyId: env("APNS_KEY_ID"),
    teamId: env("APNS_TEAM_ID"),
    privateKey: env("APNS_PRIVATE_KEY"),
    environment,
    iosTopic: env("APNS_TOPIC"),
    macOSTopic: env("APNS_MAC_TOPIC") || null,
  };
  if (
    !config.keyId || !config.teamId || !config.privateKey || !config.iosTopic ||
    !(environment === "sandbox" || environment === "production")
  ) return null;
  return config;
}

function unavailable(): Response {
  return new Response(
    JSON.stringify({ error: "push_delivery_not_configured" }),
    {
      status: 503,
      headers: { "content-type": "application/json" },
    },
  );
}

const apnsConfiguration = url && serviceKey && internalSecret
  ? configuration()
  : null;
const handler = apnsConfiguration
  ? createNotificationDeliveryWorkerHandler(
    makeStore(),
    new APNSSender(apnsConfiguration),
    internalSecret,
  )
  : null;

Deno.serve((request) => handler ? handler(request) : unavailable());
