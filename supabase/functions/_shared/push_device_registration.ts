export type PushPlatform = "ios" | "macos";
export type PushEnvironment = "sandbox" | "production";

export type PushDeviceRecord = {
  id: string;
  platform: PushPlatform;
  environment: PushEnvironment;
  app_bundle_id: string;
  notifications_authorized: boolean;
  last_registered_at: string;
  disabled_at: string | null;
};

export type PushRegistrationInput = {
  actorId: string;
  deviceToken: string;
  platform: PushPlatform;
  environment: PushEnvironment;
  appBundleId: string;
  appVersion: string | null;
  osVersion: string | null;
  notificationsAuthorized: boolean;
};

export type PushRegistrationConfiguration = {
  environment: PushEnvironment;
  iosTopic: string;
  macOSTopic: string | null;
};

export interface PushDeviceRegistrationStore {
  authenticate(request: Request): Promise<string | null>;
  register(input: PushRegistrationInput): Promise<PushDeviceRecord>;
  unregister(input: {
    actorId: string;
    deviceToken: string;
    environment: PushEnvironment;
    appBundleId: string;
  }): Promise<boolean>;
  list(actorId: string): Promise<PushDeviceRecord[]>;
}

type JsonObject = Record<string, unknown>;

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const TOKEN_PATTERN = /^[0-9a-f]{64,400}$/;
const BUNDLE_PATTERN = /^[A-Za-z0-9][A-Za-z0-9.-]{2,254}$/;
const forbiddenFields = new Set([
  "user_id",
  "actor_id",
  "recipient_user_id",
  "is_platform_admin",
  "authorization_source",
  "disabled_at",
  "disable_reason",
]);

const messages: Record<string, string> = {
  method_not_allowed: "This push-registration action is not supported.",
  invalid_auth: "Your session could not be verified. Sign in and try again.",
  invalid_json: "The device registration could not be read.",
  invalid_action: "Select a valid device-registration action.",
  server_controlled_field: "The request included a server-controlled field.",
  invalid_device_token: "The Apple device token is invalid.",
  invalid_platform: "This Apple platform is not supported.",
  invalid_environment: "The push environment does not match this app build.",
  invalid_bundle_id:
    "The app identifier does not match the configured push topic.",
  invalid_device_metadata: "The device metadata is invalid.",
  device_not_found: "This device registration is not active for your account.",
  push_registration_unavailable:
    "Push registration is temporarily unavailable. Please try again.",
};

export class PushDeviceStoreError extends Error {
  constructor(readonly code: string) {
    super(code);
    this.name = "PushDeviceStoreError";
  }
}

function isObject(value: unknown): value is JsonObject {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function clean(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function json(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });
}

function failure(status: number, code: string): Response {
  return json(status, {
    error: code,
    message: messages[code] ?? messages.push_registration_unavailable,
  });
}

export function expectedTopic(
  platform: PushPlatform,
  config: PushRegistrationConfiguration,
): string | null {
  return platform === "ios" ? config.iosTopic : config.macOSTopic;
}

function parsePlatform(value: unknown): PushPlatform | null {
  return value === "ios" || value === "macos" ? value : null;
}

function parseEnvironment(value: unknown): PushEnvironment | null {
  return value === "sandbox" || value === "production" ? value : null;
}

function parseToken(value: unknown): string | null {
  const token = clean(value).toLowerCase();
  return TOKEN_PATTERN.test(token) && token.length % 2 === 0 ? token : null;
}

function optionalMetadata(value: unknown): string | null | "invalid" {
  if (value === undefined || value === null || value === "") return null;
  if (typeof value !== "string") return "invalid";
  const result = value.trim();
  return result.length <= 80 ? result || null : "invalid";
}

function publicDevice(value: PushDeviceRecord): PushDeviceRecord {
  return {
    id: value.id,
    platform: value.platform,
    environment: value.environment,
    app_bundle_id: value.app_bundle_id,
    notifications_authorized: value.notifications_authorized,
    last_registered_at: value.last_registered_at,
    disabled_at: value.disabled_at,
  };
}

export function createPushDeviceRegistrationHandler(
  store: PushDeviceRegistrationStore,
  config: PushRegistrationConfiguration,
) {
  return async (request: Request): Promise<Response> => {
    if (request.method !== "POST") return failure(405, "method_not_allowed");
    const actorId = await store.authenticate(request).catch(() => null);
    if (!actorId || !UUID_PATTERN.test(actorId)) {
      return failure(401, "invalid_auth");
    }

    let body: JsonObject;
    try {
      const decoded: unknown = await request.json();
      if (!isObject(decoded)) return failure(400, "invalid_json");
      body = decoded;
    } catch {
      return failure(400, "invalid_json");
    }
    if (Object.keys(body).some((key) => forbiddenFields.has(key))) {
      return failure(400, "server_controlled_field");
    }

    const action = clean(body.action);
    if (action === "list_current_user_devices") {
      const devices = await store.list(actorId).catch(() => null);
      if (!devices) return failure(500, "push_registration_unavailable");
      return json(200, { devices: devices.map(publicDevice) });
    }
    if (action !== "register" && action !== "unregister") {
      return failure(400, "invalid_action");
    }

    const deviceToken = parseToken(body.device_token);
    if (!deviceToken) return failure(400, "invalid_device_token");
    const platform = parsePlatform(body.platform);
    if (!platform) return failure(400, "invalid_platform");
    const environment = parseEnvironment(body.environment);
    if (!environment || environment !== config.environment) {
      return failure(400, "invalid_environment");
    }
    const appBundleId = clean(body.app_bundle_id);
    if (
      !BUNDLE_PATTERN.test(appBundleId) ||
      expectedTopic(platform, config) !== appBundleId
    ) return failure(400, "invalid_bundle_id");

    if (action === "unregister") {
      try {
        const unregistered = await store.unregister({
          actorId,
          deviceToken,
          environment,
          appBundleId,
        });
        if (!unregistered) return failure(404, "device_not_found");
        return json(200, { unregistered: true });
      } catch {
        return failure(500, "push_registration_unavailable");
      }
    }

    const appVersion = optionalMetadata(body.app_version);
    const osVersion = optionalMetadata(body.os_version);
    if (
      appVersion === "invalid" || osVersion === "invalid" ||
      typeof body.notifications_authorized !== "boolean"
    ) return failure(400, "invalid_device_metadata");

    try {
      const device = await store.register({
        actorId,
        deviceToken,
        platform,
        environment,
        appBundleId,
        appVersion,
        osVersion,
        notificationsAuthorized: body.notifications_authorized,
      });
      return json(200, { device: publicDevice(device) });
    } catch (error) {
      if (error instanceof PushDeviceStoreError) {
        return failure(400, error.code);
      }
      return failure(500, "push_registration_unavailable");
    }
  };
}
