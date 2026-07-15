export const NOTIFICATION_PAGE_MAX = 50;
export const ANNOUNCEMENT_MAX_TITLE_LENGTH = 120;
export const ANNOUNCEMENT_MAX_BODY_LENGTH = 2_000;
export const ANNOUNCEMENT_MAX_RECIPIENTS = 1_000;

export type NotificationCategory =
  | "payment_request_created"
  | "payment_received"
  | "booking_created"
  | "booking_updated"
  | "program_assigned"
  | "program_updated"
  | "message_received"
  | "testing_result_added"
  | "organization_announcement"
  | "system";

export type AnnouncementAudience =
  | "all"
  | "players"
  | "parents"
  | "coaches"
  | "staff";

export type NotificationRecord = {
  id: string;
  org_id: string;
  organization_name: string;
  category: NotificationCategory | string;
  title: string;
  body: string;
  related_entity_type: string | null;
  related_entity_id: string | null;
  action_route: string | null;
  action_payload: Record<string, unknown>;
  created_at: string;
  read_at: string | null;
};

export type NotificationListResult = {
  notifications: NotificationRecord[];
  total: number;
};

export type AnnouncementResult = {
  announcement_id: string;
  created_count: number;
  recipient_count: number;
  reused: boolean;
  authorization_source: "organization_membership" | "platform_support";
};

export type AnnouncementInput = {
  orgId: string;
  actorId: string;
  title: string;
  body: string;
  audience: AnnouncementAudience;
  supportMode: boolean;
  idempotencyKey: string;
};

export type NotificationMembership = {
  user_id: string;
  role: string;
  status: string;
};

export function deriveAnnouncementRecipientIds(
  memberships: NotificationMembership[],
  audience: AnnouncementAudience,
): string[] {
  const recipients = memberships.filter((membership) => {
    if (membership.status !== "active") return false;
    if (audience === "all") return true;
    if (audience === "players") return membership.role === "player";
    if (audience === "parents") return membership.role === "parent";
    if (audience === "coaches") return membership.role === "coach";
    return ["owner", "admin", "coach"].includes(membership.role);
  }).map((membership) => membership.user_id.toLowerCase());
  return Array.from(new Set(recipients)).sort();
}

export interface NotificationCenterStore {
  authenticate(request: Request): Promise<string | null>;
  list(
    actorId: string,
    orgId: string | null,
    unreadOnly: boolean,
    limit: number,
    offset: number,
  ): Promise<NotificationListResult>;
  unreadCount(actorId: string, orgId: string | null): Promise<number>;
  get(
    actorId: string,
    notificationId: string,
  ): Promise<NotificationRecord | null>;
  markRead(
    actorId: string,
    notificationId: string,
  ): Promise<NotificationRecord | null>;
  markAllRead(actorId: string, orgId: string | null): Promise<number>;
  createAnnouncement(input: AnnouncementInput): Promise<AnnouncementResult>;
}

export class NotificationCenterStoreError extends Error {
  constructor(readonly code: string) {
    super(code);
    this.name = "NotificationCenterStoreError";
  }
}

type JsonObject = Record<string, unknown>;

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const audiences = new Set<AnnouncementAudience>([
  "all",
  "players",
  "parents",
  "coaches",
  "staff",
]);
const forbiddenClientFields = new Set([
  "recipient_user_id",
  "recipient_user_ids",
  "user_id",
  "actor_id",
  "created_by",
  "read_at",
  "archived_at",
  "authorization_source",
  "is_platform_admin",
  "platform_admin",
  "notification_owner_id",
]);

const messages: Record<string, string> = {
  method_not_allowed: "This notification-center action is not supported.",
  invalid_auth: "Your session could not be verified. Sign in and try again.",
  invalid_json: "The notification request could not be read.",
  server_controlled_field: "The request included a server-controlled field.",
  invalid_action: "Select a valid notification-center action.",
  invalid_organization: "Select a valid organization.",
  invalid_notification: "Select a valid notification.",
  notification_not_found: "The notification was not found in your inbox.",
  invalid_pagination: "The notification page is invalid.",
  invalid_unread_filter: "The unread filter is invalid.",
  invalid_announcement: "Enter a valid announcement title and message.",
  invalid_audience: "Select a valid announcement audience.",
  invalid_idempotency_key: "The announcement operation identifier is invalid.",
  organization_admin_required:
    "An active organization owner or administrator is required.",
  platform_support_required:
    "Explicit verified platform support access is required.",
  announcement_organization_inactive:
    "Announcements cannot be sent for an inactive organization.",
  announcement_audience_empty: "The selected audience has no active members.",
  announcement_audience_too_large:
    `Announcements are limited to ${ANNOUNCEMENT_MAX_RECIPIENTS} recipients.`,
  announcement_idempotency_conflict:
    "This announcement retry does not match the original submission.",
  announcement_failed: "The announcement could not be sent. Please try again.",
  notification_center_unavailable:
    "Notifications are temporarily unavailable. Please try again.",
};

function isObject(value: unknown): value is JsonObject {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function clean(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function validUuid(value: string): boolean {
  return UUID_PATTERN.test(value);
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
    message: messages[code] ?? messages.notification_center_unavailable,
  });
}

function optionalOrgId(body: JsonObject): string | null | "invalid" {
  if (body.org_id === null || body.org_id === undefined || body.org_id === "") {
    return null;
  }
  const orgId = clean(body.org_id).toLowerCase();
  return validUuid(orgId) ? orgId : "invalid";
}

function storeFailure(error: NotificationCenterStoreError): Response {
  switch (error.code) {
    case "organization_admin_required":
    case "platform_support_required":
      return failure(403, error.code);
    case "announcement_organization_inactive":
      return failure(409, error.code);
    case "announcement_audience_empty":
    case "announcement_audience_too_large":
      return failure(400, error.code);
    case "announcement_idempotency_conflict":
      return failure(409, error.code);
    default:
      return failure(500, "notification_center_unavailable");
  }
}

export function createNotificationCenterHandler(
  store: NotificationCenterStore,
) {
  return async (request: Request): Promise<Response> => {
    if (request.method !== "POST") {
      return failure(405, "method_not_allowed");
    }

    const actorId = await store.authenticate(request).catch(() => null);
    if (!actorId) return failure(401, "invalid_auth");

    let body: JsonObject;
    try {
      const decoded: unknown = await request.json();
      if (!isObject(decoded)) return failure(400, "invalid_json");
      body = decoded;
    } catch {
      return failure(400, "invalid_json");
    }

    if (Object.keys(body).some((key) => forbiddenClientFields.has(key))) {
      return failure(400, "server_controlled_field");
    }

    const action = clean(body.action);
    const orgId = optionalOrgId(body);
    if (orgId === "invalid") return failure(400, "invalid_organization");

    try {
      if (action === "list") {
        if (
          body.unread_only !== undefined &&
          typeof body.unread_only !== "boolean"
        ) return failure(400, "invalid_unread_filter");
        const limit = body.limit === undefined ? 20 : Number(body.limit);
        const offset = body.offset === undefined ? 0 : Number(body.offset);
        if (
          !Number.isSafeInteger(limit) || limit < 1 ||
          limit > NOTIFICATION_PAGE_MAX ||
          !Number.isSafeInteger(offset) || offset < 0 || offset > 10_000
        ) return failure(400, "invalid_pagination");
        const result = await store.list(
          actorId,
          orgId,
          body.unread_only === true,
          limit,
          offset,
        );
        return json(200, {
          notifications: result.notifications,
          pagination: {
            limit,
            offset,
            total: result.total,
            has_more: offset + result.notifications.length < result.total,
          },
        });
      }

      if (action === "unread_count") {
        const totalUnread = await store.unreadCount(actorId, null);
        const organizationUnread = orgId
          ? await store.unreadCount(actorId, orgId)
          : null;
        return json(200, {
          total_unread: totalUnread,
          organization_id: orgId,
          organization_unread: organizationUnread,
        });
      }

      if (action === "get") {
        const notificationId = clean(body.notification_id).toLowerCase();
        if (!validUuid(notificationId)) {
          return failure(400, "invalid_notification");
        }
        const notification = await store.get(actorId, notificationId);
        if (!notification) return failure(404, "notification_not_found");
        return json(200, { notification });
      }

      if (action === "mark_read") {
        const notificationId = clean(body.notification_id).toLowerCase();
        if (!validUuid(notificationId)) {
          return failure(400, "invalid_notification");
        }
        const notification = await store.markRead(actorId, notificationId);
        if (!notification) return failure(404, "notification_not_found");
        return json(200, { notification });
      }

      if (action === "mark_all_read") {
        const updatedCount = await store.markAllRead(actorId, orgId);
        return json(200, {
          updated_count: updatedCount,
          organization_id: orgId,
        });
      }

      if (action === "create_announcement") {
        if (!orgId) return failure(400, "invalid_organization");
        const title = clean(body.title);
        const announcementBody = clean(body.body);
        const audience = clean(body.audience) as AnnouncementAudience;
        const idempotencyKey = clean(body.idempotency_key).toLowerCase();
        if (
          title.length < 1 || title.length > ANNOUNCEMENT_MAX_TITLE_LENGTH ||
          announcementBody.length < 1 ||
          announcementBody.length > ANNOUNCEMENT_MAX_BODY_LENGTH
        ) return failure(400, "invalid_announcement");
        if (!audiences.has(audience)) return failure(400, "invalid_audience");
        if (!validUuid(idempotencyKey)) {
          return failure(400, "invalid_idempotency_key");
        }
        if (
          body.support_mode !== undefined &&
          typeof body.support_mode !== "boolean"
        ) return failure(400, "invalid_announcement");
        const result = await store.createAnnouncement({
          orgId,
          actorId,
          title,
          body: announcementBody,
          audience,
          supportMode: body.support_mode === true,
          idempotencyKey,
        });
        return json(result.reused ? 200 : 201, result);
      }

      return failure(400, "invalid_action");
    } catch (error) {
      if (error instanceof NotificationCenterStoreError) {
        return storeFailure(error);
      }
      return failure(500, "notification_center_unavailable");
    }
  };
}
