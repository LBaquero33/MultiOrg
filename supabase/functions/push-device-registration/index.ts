import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import {
  createPushDeviceRegistrationHandler,
  type PushDeviceRecord,
  type PushDeviceRegistrationStore,
  PushDeviceStoreError,
  type PushEnvironment,
  type PushPlatform,
} from "../_shared/push_device_registration.ts";

const env = (name: string) => (Deno.env.get(name) ?? "").trim();
const url = env("SUPABASE_URL") || env("DHD_SUPABASE_URL");
const anonKey = env("SUPABASE_ANON_KEY") || env("DHD_SUPABASE_ANON_KEY");
const serviceKey = env("SUPABASE_SERVICE_ROLE_KEY") ||
  env("DHD_SERVICE_ROLE_KEY");
const configuredEnvironment = env("APNS_ENVIRONMENT") as PushEnvironment;
const iosTopic = env("APNS_TOPIC");
const macOSTopic = env("APNS_MAC_TOPIC") || null;

type JsonObject = Record<string, unknown>;

function isObject(value: unknown): value is JsonObject {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function parseDevice(value: unknown): PushDeviceRecord {
  if (
    !isObject(value) ||
    typeof value.id !== "string" ||
    !(value.platform === "ios" || value.platform === "macos") ||
    !(value.environment === "sandbox" || value.environment === "production") ||
    typeof value.app_bundle_id !== "string" ||
    typeof value.notifications_authorized !== "boolean" ||
    typeof value.last_registered_at !== "string" ||
    !(value.disabled_at === null || typeof value.disabled_at === "string")
  ) throw new PushDeviceStoreError("invalid_device_response");
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

function makeStore(): PushDeviceRegistrationStore {
  const admin = createClient(url, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  return {
    async authenticate(request) {
      const authorization = request.headers.get("Authorization") ?? "";
      if (!authorization) return null;
      const userClient = createClient(url, anonKey, {
        global: { headers: { Authorization: authorization } },
        auth: { persistSession: false, autoRefreshToken: false },
      });
      const { data, error } = await userClient.auth.getUser();
      if (error) return null;
      return data.user?.id ?? null;
    },

    async register(input) {
      const { data, error } = await admin.rpc("sd_register_push_device", {
        p_actor_id: input.actorId,
        p_device_token: input.deviceToken,
        p_platform: input.platform,
        p_environment: input.environment,
        p_app_bundle_id: input.appBundleId,
        p_app_version: input.appVersion,
        p_os_version: input.osVersion,
        p_notifications_authorized: input.notificationsAuthorized,
      });
      if (error || !isObject(data)) {
        throw new PushDeviceStoreError("push_registration_failed");
      }
      return parseDevice(data.device);
    },

    async unregister(input) {
      const { data, error } = await admin.rpc("sd_unregister_push_device", {
        p_actor_id: input.actorId,
        p_device_token: input.deviceToken,
        p_environment: input.environment,
        p_app_bundle_id: input.appBundleId,
      });
      if (error || !isObject(data) || typeof data.unregistered !== "boolean") {
        throw new PushDeviceStoreError("push_unregistration_failed");
      }
      return data.unregistered;
    },

    async list(actorId) {
      const { data, error } = await admin.from("sd_push_devices")
        .select(
          "id,platform,environment,app_bundle_id,notifications_authorized,last_registered_at,disabled_at",
        )
        .eq("user_id", actorId)
        .order("last_registered_at", { ascending: false });
      if (error) throw new PushDeviceStoreError("push_device_list_failed");
      return (data ?? []).map(parseDevice);
    },
  };
}

function configurationError(): Response {
  return new Response(
    JSON.stringify({
      error: "missing_configuration",
      message: "Push registration is not configured.",
    }),
    {
      status: 500,
      headers: { "content-type": "application/json" },
    },
  );
}

const validEnvironment = configuredEnvironment === "sandbox" ||
  configuredEnvironment === "production";
const handler = url && anonKey && serviceKey && iosTopic && validEnvironment
  ? createPushDeviceRegistrationHandler(makeStore(), {
    environment: configuredEnvironment,
    iosTopic,
    macOSTopic,
  })
  : null;

Deno.serve((request) => handler ? handler(request) : configurationError());
