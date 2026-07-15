import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import {
  type AnnouncementResult,
  createNotificationCenterHandler,
  type NotificationCenterStore,
  NotificationCenterStoreError,
  type NotificationRecord,
} from "../_shared/notification_center.ts";
import { wakeNotificationDeliveriesAfterCommit } from "../_shared/notification_delivery_wakeup.ts";

const env = (name: string) => (Deno.env.get(name) ?? "").trim();
const url = env("SUPABASE_URL") || env("DHD_SUPABASE_URL");
const anonKey = env("SUPABASE_ANON_KEY") || env("DHD_SUPABASE_ANON_KEY");
const serviceKey = env("SUPABASE_SERVICE_ROLE_KEY") ||
  env("DHD_SERVICE_ROLE_KEY");
const notificationWorkerSecret = env("NOTIFICATION_DELIVERY_WORKER_SECRET");

type JsonObject = Record<string, unknown>;
type NotificationRow = {
  id: string;
  org_id: string;
  category: string;
  title: string;
  body: string;
  related_entity_type: string | null;
  related_entity_id: string | null;
  action_route: string | null;
  action_payload: unknown;
  created_at: string;
  read_at: string | null;
};

const notificationSelection = [
  "id",
  "org_id",
  "category",
  "title",
  "body",
  "related_entity_type",
  "related_entity_id",
  "action_route",
  "action_payload",
  "created_at",
  "read_at",
].join(",");

function isObject(value: unknown): value is JsonObject {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function parseNotificationRow(
  value: unknown,
  organizationNames: Map<string, string>,
): NotificationRecord {
  if (
    !isObject(value) ||
    typeof value.id !== "string" ||
    typeof value.org_id !== "string" ||
    typeof value.category !== "string" ||
    typeof value.title !== "string" ||
    typeof value.body !== "string" ||
    !(value.related_entity_type === null ||
      typeof value.related_entity_type === "string") ||
    !(value.related_entity_id === null ||
      typeof value.related_entity_id === "string") ||
    !(value.action_route === null || typeof value.action_route === "string") ||
    !isObject(value.action_payload) ||
    typeof value.created_at !== "string" ||
    !(value.read_at === null || typeof value.read_at === "string")
  ) throw new Error("notification_response_invalid");

  return {
    id: value.id,
    org_id: value.org_id,
    organization_name: organizationNames.get(value.org_id) ?? "Organization",
    category: value.category,
    title: value.title,
    body: value.body,
    related_entity_type: value.related_entity_type,
    related_entity_id: value.related_entity_id,
    action_route: value.action_route,
    action_payload: value.action_payload,
    created_at: value.created_at,
    read_at: value.read_at,
  };
}

function announcementFailure(message: string): NotificationCenterStoreError {
  for (
    const code of [
      "organization_admin_required",
      "platform_support_required",
      "announcement_organization_inactive",
      "announcement_audience_empty",
      "announcement_audience_too_large",
      "announcement_idempotency_conflict",
    ]
  ) {
    if (message.includes(code)) return new NotificationCenterStoreError(code);
  }
  return new NotificationCenterStoreError("announcement_failed");
}

function parseAnnouncement(value: unknown): AnnouncementResult {
  if (
    !isObject(value) ||
    typeof value.announcement_id !== "string" ||
    !Number.isSafeInteger(value.created_count) ||
    !Number.isSafeInteger(value.recipient_count) ||
    typeof value.reused !== "boolean" ||
    !(value.authorization_source === "organization_membership" ||
      value.authorization_source === "platform_support")
  ) throw new NotificationCenterStoreError("announcement_failed");
  return {
    announcement_id: value.announcement_id,
    created_count: value.created_count as number,
    recipient_count: value.recipient_count as number,
    reused: value.reused,
    authorization_source: value.authorization_source,
  };
}

function makeStore(): NotificationCenterStore {
  const admin = createClient(url, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const organizationNames = async (orgIds: string[]) => {
    const unique = Array.from(new Set(orgIds));
    if (unique.length === 0) return new Map<string, string>();
    const { data, error } = await admin.from("sd_orgs").select("id,name").in(
      "id",
      unique,
    );
    if (error) throw new Error("notification_organization_lookup_failed");
    return new Map(
      ((data ?? []) as { id: string; name: string }[]).map((row) => [
        row.id,
        row.name,
      ]),
    );
  };

  const publicRows = async (rows: NotificationRow[]) => {
    const names = await organizationNames(rows.map((row) => row.org_id));
    return rows.map((row) => parseNotificationRow(row, names));
  };

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

    async list(actorId, orgId, unreadOnly, limit, offset) {
      let query = admin.from("sd_notifications")
        .select(notificationSelection, { count: "exact" })
        .eq("recipient_user_id", actorId)
        .is("archived_at", null);
      if (orgId) query = query.eq("org_id", orgId);
      if (unreadOnly) query = query.is("read_at", null);
      const { data, error, count } = await query
        .order("created_at", { ascending: false })
        .order("id", { ascending: false })
        .range(offset, offset + limit - 1);
      if (error) throw new Error("notification_list_failed");
      const rows = (data ?? []) as unknown as NotificationRow[];
      return {
        notifications: await publicRows(rows),
        total: count ?? rows.length,
      };
    },

    async unreadCount(actorId, orgId) {
      let query = admin.from("sd_notifications")
        .select("id", { count: "exact", head: true })
        .eq("recipient_user_id", actorId)
        .is("read_at", null)
        .is("archived_at", null);
      if (orgId) query = query.eq("org_id", orgId);
      const { error, count } = await query;
      if (error) throw new Error("notification_count_failed");
      return count ?? 0;
    },

    async get(actorId, notificationId) {
      const { data, error } = await admin.from("sd_notifications")
        .select(notificationSelection)
        .eq("id", notificationId)
        .eq("recipient_user_id", actorId)
        .is("archived_at", null)
        .maybeSingle();
      if (error) throw new Error("notification_lookup_failed");
      if (!data) return null;
      return (await publicRows([data as unknown as NotificationRow]))[0] ??
        null;
    },

    async markRead(actorId, notificationId) {
      const { error: updateError } = await admin.from("sd_notifications")
        .update({ read_at: new Date().toISOString() })
        .eq("id", notificationId)
        .eq("recipient_user_id", actorId)
        .is("read_at", null);
      if (updateError) throw new Error("notification_mark_read_failed");

      const { data, error } = await admin.from("sd_notifications")
        .select(notificationSelection)
        .eq("id", notificationId)
        .eq("recipient_user_id", actorId)
        .is("archived_at", null)
        .maybeSingle();
      if (error) throw new Error("notification_lookup_failed");
      if (!data) return null;
      return (await publicRows([data as unknown as NotificationRow]))[0] ??
        null;
    },

    async markAllRead(actorId, orgId) {
      let query = admin.from("sd_notifications")
        .update({ read_at: new Date().toISOString() })
        .eq("recipient_user_id", actorId)
        .is("read_at", null)
        .is("archived_at", null);
      if (orgId) query = query.eq("org_id", orgId);
      const { data, error } = await query.select("id");
      if (error) throw new Error("notification_mark_all_read_failed");
      return (data ?? []).length;
    },

    async createAnnouncement(input) {
      const { data, error } = await admin.rpc(
        "sd_create_organization_announcement",
        {
          p_org_id: input.orgId,
          p_actor_id: input.actorId,
          p_title: input.title,
          p_body: input.body,
          p_audience: input.audience,
          p_support_mode: input.supportMode,
          p_idempotency_key: input.idempotencyKey,
        },
      );
      if (error) throw announcementFailure(error.message);
      const result = parseAnnouncement(data);
      await wakeNotificationDeliveriesAfterCommit(
        url,
        notificationWorkerSecret,
      );
      return result;
    },
  };
}

function configurationError(): Response {
  return new Response(
    JSON.stringify({
      error: "missing_configuration",
      message: "Notifications are not configured.",
    }),
    {
      status: 500,
      headers: { "content-type": "application/json" },
    },
  );
}

const handler = url && anonKey && serviceKey
  ? createNotificationCenterHandler(makeStore())
  : null;

Deno.serve((request) => handler ? handler(request) : configurationError());
