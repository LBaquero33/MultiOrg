import type {
  PushEnvironment,
  PushPlatform,
} from "./push_device_registration.ts";

export const APNS_MAX_PAYLOAD_BYTES = 4_096;
export const APNS_PROVIDER_TOKEN_MAX_AGE_SECONDS = 50 * 60;

export type APNSConfiguration = {
  keyId: string;
  teamId: string;
  privateKey: string;
  environment: PushEnvironment;
  iosTopic: string;
  macOSTopic: string | null;
};

export type APNSNotificationFacts = {
  id: string;
  org_id: string;
  category: string;
  title: string;
  body: string;
  action_route: string | null;
  action_payload: Record<string, unknown>;
};

export type APNSDeliveryFacts = {
  delivery_id: string;
  attempt_count: number;
  notification: APNSNotificationFacts;
  device: {
    id: string;
    platform: PushPlatform;
    environment: PushEnvironment;
    app_bundle_id: string;
    device_token: string;
  };
  unread_count: number;
};

export type APNSOutcome =
  | "sent"
  | "retryable"
  | "failed"
  | "permanent_token";

export type APNSSendResult = {
  outcome: APNSOutcome;
  apnsId: string | null;
  status: number | null;
  reason: string;
};

type Fetcher = typeof fetch;

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const knownCategories = new Set([
  "payment_request_created",
  "payment_received",
  "booking_created",
  "booking_updated",
  "program_assigned",
  "program_updated",
  "message_received",
  "testing_result_added",
  "organization_announcement",
  "system",
]);
const knownRoutes = new Set([
  "payment_request",
  "payment",
  "finance",
  "organization_announcement",
  "notification_detail",
]);
const safePayloadKeys = new Set([
  "payment_request_id",
  "payment_id",
  "announcement_id",
]);
const permanentDeviceReasons = new Set([
  "BadDeviceToken",
  "DeviceTokenNotForTopic",
  "Unregistered",
  "TopicDisallowed",
]);
const retryableReasons = new Set([
  "Shutdown",
  "TooManyRequests",
  "InternalServerError",
  "ServiceUnavailable",
]);

function base64URL(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replaceAll("+", "-").replaceAll("/", "_").replace(
    /=+$/,
    "",
  );
}

function jsonBase64URL(value: unknown): string {
  return base64URL(new TextEncoder().encode(JSON.stringify(value)));
}

function pemBytes(value: string): ArrayBuffer {
  const normalized = value.replaceAll("\\n", "\n").trim();
  const body = normalized
    .replace("-----BEGIN PRIVATE KEY-----", "")
    .replace("-----END PRIVATE KEY-----", "")
    .replace(/\s+/g, "");
  if (!body) throw new Error("invalid_apns_private_key");
  const binary = atob(body);
  const bytes = new Uint8Array(binary.length);
  for (let index = 0; index < binary.length; index += 1) {
    bytes[index] = binary.charCodeAt(index);
  }
  return bytes.buffer;
}

export function apnsEndpoint(environment: PushEnvironment): string {
  return environment === "sandbox"
    ? "https://api.sandbox.push.apple.com"
    : "https://api.push.apple.com";
}

export function providerTokenParts(
  keyId: string,
  teamId: string,
  issuedAtSeconds: number,
): { header: Record<string, string>; claims: Record<string, string | number> } {
  return {
    header: { alg: "ES256", kid: keyId },
    claims: { iss: teamId, iat: issuedAtSeconds },
  };
}

export async function createAPNSProviderToken(
  config: Pick<APNSConfiguration, "keyId" | "teamId" | "privateKey">,
  issuedAtSeconds: number,
): Promise<string> {
  const parts = providerTokenParts(
    config.keyId,
    config.teamId,
    issuedAtSeconds,
  );
  const signingInput = `${jsonBase64URL(parts.header)}.${
    jsonBase64URL(parts.claims)
  }`;
  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemBytes(config.privateKey),
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );
  const signature = new Uint8Array(
    await crypto.subtle.sign(
      { name: "ECDSA", hash: "SHA-256" },
      key,
      new TextEncoder().encode(signingInput),
    ),
  );
  if (signature.byteLength !== 64) throw new Error("invalid_apns_signature");
  return `${signingInput}.${base64URL(signature)}`;
}

export class APNSProviderTokenCache {
  private cached: { token: string; issuedAt: number } | null = null;

  constructor(
    private readonly config: Pick<
      APNSConfiguration,
      "keyId" | "teamId" | "privateKey"
    >,
    private readonly nowSeconds: () => number = () =>
      Math.floor(Date.now() / 1000),
  ) {}

  async token(): Promise<string> {
    const now = this.nowSeconds();
    if (
      this.cached &&
      now - this.cached.issuedAt < APNS_PROVIDER_TOKEN_MAX_AGE_SECONDS
    ) return this.cached.token;
    const token = await createAPNSProviderToken(this.config, now);
    this.cached = { token, issuedAt: now };
    return token;
  }
}

function safeActionPayload(
  value: Record<string, unknown>,
): Record<string, string> {
  const result: Record<string, string> = {};
  for (const [key, candidate] of Object.entries(value)) {
    if (
      safePayloadKeys.has(key) && typeof candidate === "string" &&
      UUID_PATTERN.test(candidate)
    ) result[key] = candidate.toLowerCase();
  }
  return result;
}

function boundedText(value: string, maximumCharacters: number): string {
  return Array.from(value.trim()).slice(0, maximumCharacters).join("");
}

export function buildAPNSPayload(
  notification: APNSNotificationFacts,
  unreadCount: number,
): { payload: Record<string, unknown>; body: string; byteLength: number } {
  const known = knownCategories.has(notification.category);
  const actionRoute = knownRoutes.has(notification.action_route ?? "")
    ? notification.action_route
    : "notification_detail";
  const safeAction = safeActionPayload(notification.action_payload);
  const title = known
    ? boundedText(notification.title, 120) || "Home Plate"
    : "Home Plate";
  let alertBody = known
    ? boundedText(notification.body, 2_000) || "You have a new notification."
    : "You have a new notification.";

  const makePayload = () => ({
    aps: {
      alert: { title, body: alertBody },
      sound: "default",
      badge: Math.max(0, Math.min(Math.trunc(unreadCount), 99_999)),
      category: "HOME_PLATE_NOTIFICATION",
      "thread-id": notification.org_id,
    },
    home_plate: {
      notification_id: notification.id,
      org_id: notification.org_id,
      category: known ? notification.category : "system",
      action_route: actionRoute,
      action_payload: safeAction,
      schema_version: "notification_v1",
    },
  });

  let payload = makePayload();
  let body = JSON.stringify(payload);
  while (
    new TextEncoder().encode(body).byteLength > APNS_MAX_PAYLOAD_BYTES &&
    alertBody.length > 1
  ) {
    alertBody = Array.from(alertBody).slice(
      0,
      Math.max(1, alertBody.length - 64),
    )
      .join("");
    payload = makePayload();
    body = JSON.stringify(payload);
  }
  const byteLength = new TextEncoder().encode(body).byteLength;
  if (byteLength > APNS_MAX_PAYLOAD_BYTES) {
    throw new Error("apns_payload_too_large");
  }
  return { payload, body, byteLength };
}

export function classifyAPNSResponse(
  status: number,
  reason: string,
): APNSOutcome {
  if (status === 200) return "sent";
  if (permanentDeviceReasons.has(reason)) return "permanent_token";
  if ([429, 500, 503].includes(status) || retryableReasons.has(reason)) {
    return "retryable";
  }
  return "failed";
}

export class APNSSender {
  private readonly providerTokens: APNSProviderTokenCache;

  constructor(
    private readonly config: APNSConfiguration,
    private readonly fetcher: Fetcher = fetch,
    private readonly nowSeconds: () => number = () =>
      Math.floor(Date.now() / 1000),
  ) {
    this.providerTokens = new APNSProviderTokenCache(config, nowSeconds);
  }

  async send(delivery: APNSDeliveryFacts): Promise<APNSSendResult> {
    if (delivery.device.environment !== this.config.environment) {
      return {
        outcome: "failed",
        apnsId: null,
        status: null,
        reason: "EnvironmentMismatch",
      };
    }
    const topic = delivery.device.platform === "ios"
      ? this.config.iosTopic
      : this.config.macOSTopic;
    if (!topic || topic !== delivery.device.app_bundle_id) {
      return {
        outcome: "failed",
        apnsId: null,
        status: null,
        reason: "BadTopic",
      };
    }

    try {
      const token = await this.providerTokens.token();
      const payload = buildAPNSPayload(
        delivery.notification,
        delivery.unread_count,
      );
      const response = await this.fetcher(
        `${
          apnsEndpoint(delivery.device.environment)
        }/3/device/${delivery.device.device_token}`,
        {
          method: "POST",
          headers: {
            authorization: `bearer ${token}`,
            "content-type": "application/json",
            "apns-topic": topic,
            "apns-push-type": "alert",
            "apns-priority": "10",
            "apns-expiration": String(this.nowSeconds() + 86_400),
            "apns-id": delivery.delivery_id,
          },
          body: payload.body,
        },
      );
      let reason = response.status === 200 ? "Success" : "UnknownAPNSError";
      if (response.status !== 200) {
        try {
          const decoded: unknown = await response.json();
          if (
            typeof decoded === "object" && decoded !== null &&
            "reason" in decoded && typeof decoded.reason === "string"
          ) reason = decoded.reason.slice(0, 120);
        } catch {
          // APNs occasionally returns no JSON body; the HTTP status still
          // determines whether the attempt is retryable.
        }
      }
      return {
        outcome: classifyAPNSResponse(response.status, reason),
        apnsId: response.headers.get("apns-id"),
        status: response.status,
        reason,
      };
    } catch {
      return {
        outcome: "retryable",
        apnsId: null,
        status: null,
        reason: "NetworkError",
      };
    }
  }
}
