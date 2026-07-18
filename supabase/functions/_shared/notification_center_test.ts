import {
  type AnnouncementInput,
  type AnnouncementResult,
  createNotificationCenterHandler,
  deriveAnnouncementRecipientIds,
  type NotificationCenterStore,
  NotificationCenterStoreError,
  type NotificationMembership,
  type NotificationRecord,
} from "./notification_center.ts";

const ORG_A = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
const ORG_B = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb";
const USER_A = "11111111-1111-4111-8111-111111111111";
const USER_B = "22222222-2222-4222-8222-222222222222";
const OWNER = "33333333-3333-4333-8333-333333333333";
const ADMIN = "44444444-4444-4444-8444-444444444444";
const COACH = "55555555-5555-4555-8555-555555555555";
const PARENT = "66666666-6666-4666-8666-666666666666";
const PLAYER = "77777777-7777-4777-8777-777777777777";
const PLATFORM = "88888888-8888-4888-8888-888888888888";

function assert(
  condition: unknown,
  message = "assertion failed",
): asserts condition {
  if (!condition) throw new Error(message);
}

function assertEquals(
  actual: unknown,
  expected: unknown,
  message = "values differ",
) {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(
      `${message}: ${JSON.stringify(actual)} !== ${JSON.stringify(expected)}`,
    );
  }
}

type StoredNotification = NotificationRecord & {
  recipient: string;
  archived: boolean;
};

class FakeStore implements NotificationCenterStore {
  notifications: StoredNotification[] = [];
  memberships = new Map<string, NotificationMembership[]>();
  platformAdmins = new Set<string>();
  announcementOperations = new Map<
    string,
    { material: string; result: AnnouncementResult }
  >();
  announcementCalls: AnnouncementInput[] = [];

  async authenticate(request: Request) {
    const value = request.headers.get("Authorization") ?? "";
    return value.startsWith("Bearer ") ? value.slice(7) : null;
  }

  async list(
    actorId: string,
    orgId: string | null,
    unreadOnly: boolean,
    limit: number,
    offset: number,
  ) {
    const rows = this.notifications.filter((row) =>
      row.recipient === actorId && !row.archived &&
      (!orgId || row.org_id === orgId) && (!unreadOnly || row.read_at === null)
    ).sort((lhs, rhs) => rhs.created_at.localeCompare(lhs.created_at));
    return {
      total: rows.length,
      notifications: rows.slice(offset, offset + limit).map(this.publicRecord),
    };
  }

  async unreadCount(actorId: string, orgId: string | null) {
    return this.notifications.filter((row) =>
      row.recipient === actorId && !row.archived && row.read_at === null &&
      (!orgId || row.org_id === orgId)
    ).length;
  }

  async get(actorId: string, notificationId: string) {
    const row = this.notifications.find((candidate) =>
      candidate.id === notificationId && candidate.recipient === actorId &&
      !candidate.archived
    );
    return row ? this.publicRecord(row) : null;
  }

  async markRead(actorId: string, notificationId: string) {
    const row = this.notifications.find((candidate) =>
      candidate.id === notificationId && candidate.recipient === actorId &&
      !candidate.archived
    );
    if (!row) return null;
    row.read_at ??= "2026-07-15T12:00:00.000Z";
    return this.publicRecord(row);
  }

  async markAllRead(actorId: string, orgId: string | null) {
    let count = 0;
    for (const row of this.notifications) {
      if (
        row.recipient === actorId && !row.archived && row.read_at === null &&
        (!orgId || row.org_id === orgId)
      ) {
        row.read_at = "2026-07-15T12:00:00.000Z";
        count += 1;
      }
    }
    return count;
  }

  async createAnnouncement(input: AnnouncementInput) {
    this.announcementCalls.push(input);
    const memberships = this.memberships.get(input.orgId) ?? [];
    const actorMembership = memberships.find((row) =>
      row.user_id === input.actorId
    );
    let authorizationSource: AnnouncementResult["authorization_source"];
    if (input.supportMode) {
      if (!this.platformAdmins.has(input.actorId)) {
        throw new NotificationCenterStoreError("platform_support_required");
      }
      authorizationSource = "platform_support";
    } else if (
      actorMembership?.status === "active" &&
      ["owner", "admin"].includes(actorMembership.role)
    ) {
      authorizationSource = "organization_membership";
    } else {
      throw new NotificationCenterStoreError("organization_admin_required");
    }
    const recipients = deriveAnnouncementRecipientIds(
      memberships,
      input.audience,
    );
    if (recipients.length === 0) {
      throw new NotificationCenterStoreError("announcement_audience_empty");
    }
    const key = `${input.orgId}:${input.idempotencyKey}`;
    const material = JSON.stringify([
      input.actorId,
      input.title,
      input.body,
      input.audience,
      input.supportMode,
    ]);
    const existing = this.announcementOperations.get(key);
    if (existing) {
      if (existing.material !== material) {
        throw new NotificationCenterStoreError(
          "announcement_idempotency_conflict",
        );
      }
      return { ...existing.result, created_count: 0, reused: true };
    }
    const result: AnnouncementResult = {
      announcement_id: "99999999-9999-4999-8999-999999999999",
      created_count: recipients.length,
      recipient_count: recipients.length,
      reused: false,
      authorization_source: authorizationSource,
    };
    this.announcementOperations.set(key, { material, result });
    return result;
  }

  addNotification(
    id: string,
    recipient: string,
    orgId = ORG_A,
    createdAt = "2026-07-15T10:00:00.000Z",
  ) {
    this.notifications.push({
      id,
      recipient,
      archived: false,
      org_id: orgId,
      organization_name: orgId === ORG_A ? "Marist" : "Other Org",
      category: "system",
      title: "Update",
      body: "Body",
      related_entity_type: null,
      related_entity_id: null,
      action_route: "notification_detail",
      action_payload: {},
      created_at: createdAt,
      read_at: null,
    });
  }

  private publicRecord(row: StoredNotification): NotificationRecord {
    const { recipient: _recipient, archived: _archived, ...record } = row;
    return record;
  }
}

function request(actor: string | null, body: Record<string, unknown>) {
  return new Request("https://example.test/notification-center", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      ...(actor ? { Authorization: `Bearer ${actor}` } : {}),
    },
    body: JSON.stringify(body),
  });
}

async function responseJSON(response: Response): Promise<Record<string, any>> {
  return await response.json();
}

function memberships(): NotificationMembership[] {
  return [
    { user_id: OWNER, role: "owner", status: "active" },
    { user_id: ADMIN, role: "admin", status: "active" },
    { user_id: COACH, role: "coach", status: "active" },
    { user_id: PARENT, role: "parent", status: "active" },
    { user_id: PLAYER, role: "player", status: "active" },
    { user_id: PLAYER, role: "player", status: "active" },
    { user_id: USER_B, role: "player", status: "disabled" },
  ];
}

Deno.test("missing JWT is rejected with a sanitized response", async () => {
  const response = await createNotificationCenterHandler(new FakeStore())(
    request(null, { action: "list" }),
  );
  assertEquals(response.status, 401);
  assertEquals((await responseJSON(response)).error, "invalid_auth");
});

Deno.test("user lists only their own newest notifications with pagination", async () => {
  const store = new FakeStore();
  store.addNotification(
    "aaaaaaaa-0000-4000-8000-000000000001",
    USER_A,
    ORG_A,
    "2026-07-15T10:00:00Z",
  );
  store.addNotification(
    "aaaaaaaa-0000-4000-8000-000000000002",
    USER_B,
    ORG_A,
    "2026-07-15T12:00:00Z",
  );
  store.addNotification(
    "aaaaaaaa-0000-4000-8000-000000000003",
    USER_A,
    ORG_B,
    "2026-07-15T11:00:00Z",
  );
  const response = await createNotificationCenterHandler(store)(
    request(USER_A, {
      action: "list",
      limit: 1,
      offset: 0,
    }),
  );
  const body = await responseJSON(response);
  assertEquals(response.status, 200);
  assertEquals(body.notifications.map((row: any) => row.id), [
    "aaaaaaaa-0000-4000-8000-000000000003",
  ]);
  assertEquals(body.pagination, {
    limit: 1,
    offset: 0,
    total: 2,
    has_more: true,
  });
  assert(!("recipient_user_id" in body.notifications[0]));
});

Deno.test("organization and unread list filters remain actor scoped", async () => {
  const store = new FakeStore();
  store.addNotification("aaaaaaaa-0000-4000-8000-000000000011", USER_A, ORG_A);
  store.addNotification("aaaaaaaa-0000-4000-8000-000000000012", USER_A, ORG_B);
  store.addNotification("aaaaaaaa-0000-4000-8000-000000000013", USER_B, ORG_A);
  store.notifications[1].read_at = "2026-07-15T11:00:00Z";
  const body = await responseJSON(
    await createNotificationCenterHandler(store)(request(USER_A, {
      action: "list",
      org_id: ORG_A,
      unread_only: true,
    })),
  );
  assertEquals(body.notifications.map((row: any) => row.id), [
    "aaaaaaaa-0000-4000-8000-000000000011",
  ]);
});

Deno.test("archived notifications are excluded", async () => {
  const store = new FakeStore();
  store.addNotification("aaaaaaaa-0000-4000-8000-000000000021", USER_A);
  store.notifications[0].archived = true;
  const body = await responseJSON(
    await createNotificationCenterHandler(store)(
      request(USER_A, { action: "list" }),
    ),
  );
  assertEquals(body.notifications, []);
});

Deno.test("push tap lookup returns only the JWT actor's authoritative row", async () => {
  const store = new FakeStore();
  const id = "aaaaaaaa-0000-4000-8000-000000000025";
  store.addNotification(id, USER_A);
  const handler = createNotificationCenterHandler(store);
  const owned = await handler(request(USER_A, {
    action: "get",
    notification_id: id,
  }));
  assertEquals(owned.status, 200);
  assertEquals((await responseJSON(owned)).notification.id, id);
  const denied = await handler(request(USER_B, {
    action: "get",
    notification_id: id,
  }));
  assertEquals(denied.status, 404);
  assertEquals((await responseJSON(denied)).error, "notification_not_found");
});

Deno.test("mark read is actor-owned and idempotent", async () => {
  const store = new FakeStore();
  const id = "aaaaaaaa-0000-4000-8000-000000000031";
  store.addNotification(id, USER_A);
  const handler = createNotificationCenterHandler(store);
  const first = await responseJSON(
    await handler(request(USER_A, {
      action: "mark_read",
      notification_id: id,
    })),
  );
  const readAt = first.notification.read_at;
  const second = await responseJSON(
    await handler(request(USER_A, {
      action: "mark_read",
      notification_id: id,
    })),
  );
  assert(typeof readAt === "string");
  assertEquals(second.notification.read_at, readAt);
  assertEquals(
    (await handler(request(USER_B, {
      action: "mark_read",
      notification_id: id,
    }))).status,
    404,
  );
});

Deno.test("mark all read affects only JWT actor and optional organization", async () => {
  const store = new FakeStore();
  store.addNotification("aaaaaaaa-0000-4000-8000-000000000041", USER_A, ORG_A);
  store.addNotification("aaaaaaaa-0000-4000-8000-000000000042", USER_A, ORG_B);
  store.addNotification("aaaaaaaa-0000-4000-8000-000000000043", USER_B, ORG_A);
  const result = await responseJSON(
    await createNotificationCenterHandler(store)(request(USER_A, {
      action: "mark_all_read",
      org_id: ORG_A,
    })),
  );
  assertEquals(result.updated_count, 1);
  assert(store.notifications[0].read_at !== null);
  assertEquals(store.notifications[1].read_at, null);
  assertEquals(store.notifications[2].read_at, null);
});

Deno.test("unread count returns total and selected organization truth", async () => {
  const store = new FakeStore();
  store.addNotification("aaaaaaaa-0000-4000-8000-000000000051", USER_A, ORG_A);
  store.addNotification("aaaaaaaa-0000-4000-8000-000000000052", USER_A, ORG_B);
  store.addNotification("aaaaaaaa-0000-4000-8000-000000000053", USER_B, ORG_A);
  const body = await responseJSON(
    await createNotificationCenterHandler(store)(request(USER_A, {
      action: "unread_count",
      org_id: ORG_A,
    })),
  );
  assertEquals(body.total_unread, 2);
  assertEquals(body.organization_unread, 1);
});

Deno.test("client cannot claim notification ownership or platform authority", async () => {
  const handler = createNotificationCenterHandler(new FakeStore());
  for (
    const field of [
      "recipient_user_id",
      "actor_id",
      "is_platform_admin",
      "read_at",
    ]
  ) {
    const response = await handler(
      request(USER_A, { action: "list", [field]: USER_A }),
    );
    assertEquals(response.status, 400);
    assertEquals(
      (await responseJSON(response)).error,
      "server_controlled_field",
    );
  }
});

Deno.test("announcement audience derivation is active, role scoped, and deduplicated", () => {
  const rows = memberships();
  assertEquals(
    deriveAnnouncementRecipientIds(rows, "all"),
    [ADMIN, COACH, OWNER, PARENT, PLAYER].sort(),
  );
  assertEquals(deriveAnnouncementRecipientIds(rows, "players"), [PLAYER]);
  assertEquals(deriveAnnouncementRecipientIds(rows, "parents"), [PARENT]);
  assertEquals(deriveAnnouncementRecipientIds(rows, "coaches"), [COACH]);
  assertEquals(
    deriveAnnouncementRecipientIds(rows, "staff"),
    [ADMIN, COACH, OWNER].sort(),
  );
});

Deno.test("owner and admin can create an organization announcement", async () => {
  for (const actor of [OWNER, ADMIN]) {
    const store = new FakeStore();
    store.memberships.set(ORG_A, memberships());
    const response = await createNotificationCenterHandler(store)(
      request(actor, {
        action: "create_announcement",
        org_id: ORG_A,
        title: "Practice update",
        body: "The schedule has changed.",
        audience: "all",
        idempotency_key: "99999999-9999-4999-8999-999999999991",
      }),
    );
    assertEquals(response.status, 201);
    assertEquals(
      (await responseJSON(response)).authorization_source,
      "organization_membership",
    );
  }
});

Deno.test("platform support requires explicit mode and verified platform admin", async () => {
  const store = new FakeStore();
  store.memberships.set(ORG_A, memberships());
  store.platformAdmins.add(PLATFORM);
  const handler = createNotificationCenterHandler(store);
  const denied = await handler(request(PLATFORM, {
    action: "create_announcement",
    org_id: ORG_A,
    title: "Support update",
    body: "Sent for the organization.",
    audience: "all",
    idempotency_key: "99999999-9999-4999-8999-999999999992",
  }));
  assertEquals(denied.status, 403);
  const allowed = await handler(request(PLATFORM, {
    action: "create_announcement",
    org_id: ORG_A,
    title: "Support update",
    body: "Sent for the organization.",
    audience: "all",
    support_mode: true,
    idempotency_key: "99999999-9999-4999-8999-999999999992",
  }));
  assertEquals(allowed.status, 201);
  assertEquals(
    (await responseJSON(allowed)).authorization_source,
    "platform_support",
  );
});

Deno.test("coach, parent, player, inactive admin, and cross-org owner are denied announcements", async () => {
  for (const actor of [COACH, PARENT, PLAYER, USER_B]) {
    const store = new FakeStore();
    store.memberships.set(ORG_A, memberships());
    store.memberships.set(ORG_B, [{
      user_id: USER_B,
      role: "owner",
      status: "active",
    }]);
    const response = await createNotificationCenterHandler(store)(
      request(actor, {
        action: "create_announcement",
        org_id: ORG_A,
        title: "Denied",
        body: "This should not send.",
        audience: "all",
        idempotency_key: "99999999-9999-4999-8999-999999999993",
      }),
    );
    assertEquals(response.status, 403);
  }
});

Deno.test("announcement validation and stable idempotency fail closed", async () => {
  const store = new FakeStore();
  store.memberships.set(ORG_A, memberships());
  const handler = createNotificationCenterHandler(store);
  const operation = {
    action: "create_announcement",
    org_id: ORG_A,
    title: "One",
    body: "Body",
    audience: "players",
    idempotency_key: "99999999-9999-4999-8999-999999999994",
  };
  assertEquals((await handler(request(OWNER, operation))).status, 201);
  const reused = await responseJSON(await handler(request(OWNER, operation)));
  assertEquals(reused.reused, true);
  assertEquals(reused.created_count, 0);
  const conflict = await handler(
    request(OWNER, { ...operation, body: "Changed" }),
  );
  assertEquals(conflict.status, 409);
  assertEquals(
    (await responseJSON(conflict)).error,
    "announcement_idempotency_conflict",
  );
});

Deno.test("notification migration hardens RLS, privileges, and SECURITY DEFINER producers", async () => {
  const source = await Deno.readTextFile(
    new URL(
      "../../migrations/20260715020000_notification_center_foundation.sql",
      import.meta.url,
    ),
  );
  assert(source.includes("create table if not exists public.sd_notifications"));
  assert(source.includes('create policy "sd_notifications_select_own"'));
  assert(source.includes("recipient_user_id = (select auth.uid())"));
  assert(source.includes("grant update (read_at, archived_at)"));
  assert(source.includes("notification_fields_are_immutable"));
  assert(source.includes("set search_path = ''"));
  assert(source.includes("from public, anon, authenticated"));
  assert(source.includes("to service_role"));
  assert(source.includes("idx_sd_notifications_recipient_unread"));
  assert(source.includes("ux_sd_notifications_recipient_dedup"));
});

Deno.test("payment-request producer notifies player and active linked parents transactionally", async () => {
  const source = await Deno.readTextFile(
    new URL(
      "../../migrations/20260715020000_notification_center_foundation.sql",
      import.meta.url,
    ),
  );
  assert(source.includes("after insert on public.sd_payment_requests"));
  assert(source.includes("new.child_id as user_id"));
  assert(source.includes("link.parent_id"));
  assert(source.includes("parent_membership.role = 'parent'"));
  assert(source.includes("parent_membership.status = 'active'"));
  assert(!source.includes("link.can_pay = true"));
  assert(source.includes("'payment_request_created:' || new.id::text"));
  assert(source.includes("'payment_request_id', new.id"));
});

Deno.test("payment-received producer derives player, linked parents, and owner/admin recipients", async () => {
  const source = await Deno.readTextFile(
    new URL(
      "../../migrations/20260715020000_notification_center_foundation.sql",
      import.meta.url,
    ),
  );
  assert(source.includes("sd_produce_payment_received_notifications"));
  assert(source.includes("payment.status in ('succeeded', 'paid')"));
  assert(source.includes("staff.role in ('owner', 'admin')"));
  assert(source.includes("'payment_received:' || v_payment.id::text"));
  assert(source.includes("'payment_id', v_payment.id"));
  assert(source.includes("exception when others"));
  assert(source.includes("payment_received_notification_failed payment_id=%"));
});

Deno.test("announcement RPC derives recipients and audits without storing body", async () => {
  const source = await Deno.readTextFile(
    new URL(
      "../../migrations/20260715020000_notification_center_foundation.sql",
      import.meta.url,
    ),
  );
  assert(source.includes("sd_create_organization_announcement"));
  assert(source.includes("membership.status = 'active'"));
  assert(source.includes("membership.role in ('owner', 'admin', 'coach')"));
  assert(source.includes("organization_announcement_created"));
  assert(source.includes("'authorization_source', v_authorization_source"));
  const auditBlock = source.slice(
    source.indexOf("insert into public.sd_platform_audit_logs"),
  );
  assert(!auditBlock.includes("'body', v_body"));
});

Deno.test("production notification center verifies JWT and never returns metadata or provider secrets", async () => {
  const source = await Deno.readTextFile(
    new URL("../notification-center/index.ts", import.meta.url),
  );
  const config = await Deno.readTextFile(
    new URL("../../config.toml", import.meta.url),
  );
  assert(source.includes("auth.getUser()"));
  assert(source.includes('.eq("recipient_user_id", actorId)'));
  assert(source.includes("sd_create_organization_announcement"));
  assert(!source.includes("api.stripe.com"));
  assert(!source.includes("metadata,"));
  assert(config.includes("[functions.notification-center]\nverify_jwt = true"));
});

Deno.test("Phase 9C message producer derives active same-organization DM recipients and excludes sender", async () => {
  const migration = (await Deno.readTextFile(
    new URL(
      "../../migrations/20260715050000_notification_direct_messages_integration.sql",
      import.meta.url,
    ),
  )).toLowerCase();
  const producer = migration.slice(
    migration.indexOf(
      "create or replace function public.sd_notify_direct_message_received",
    ),
    migration.indexOf(
      "create or replace function public.sd_queue_apns_deliveries",
    ),
  );
  for (
    const expected of [
      "after insert on public.sd_chat_messages",
      "channel.is_archived = false",
      "v_channel.channel_type <> 'dm'",
      "from public.sd_chat_memberships membership",
      "join public.sd_org_memberships organization_membership",
      "organization_membership.org_id = new.org_id",
      "organization_membership.user_id = membership.user_id",
      "organization_membership.status = 'active'",
      "membership.org_id = new.org_id",
      "membership.channel_id = new.channel_id",
      "membership.user_id <> new.sender_id",
      "'message_received'",
      "'chat_message'",
      "'chat_conversation'",
      "'organization_id', new.org_id",
      "'conversation_id', new.channel_id",
      "'message_id', new.id",
      "'sender_id', new.sender_id",
      "'chat'",
    ]
  ) assert(producer.includes(expected), `missing ${expected}`);
  assert(
    !producer.includes("p_recipient_user_ids uuid[]\n)\nreturns trigger"),
  );
  assert(!producer.includes("new.recipient_user_id"));
});

Deno.test("Phase 9C message and notification retries are deterministic and concurrency safe", async () => {
  const migration = (await Deno.readTextFile(
    new URL(
      "../../migrations/20260715050000_notification_direct_messages_integration.sql",
      import.meta.url,
    ),
  )).toLowerCase();
  for (
    const expected of [
      "add column if not exists client_message_id uuid",
      "ux_sd_chat_messages_sender_client_operation",
      "on public.sd_chat_messages(org_id, sender_id, client_message_id)",
      "create or replace function public.sd_send_chat_message",
      "v_actor_id uuid := auth.uid()",
      "p_channel_id is null or p_client_message_id is null",
      "message.client_message_id = p_client_message_id",
      "v_message.channel_id is distinct from p_channel_id",
      "v_message.body is distinct from v_body",
      "chat_idempotency_conflict",
      "on conflict (org_id, sender_id, client_message_id)",
      "on conflict (org_id, recipient_user_id, category, deduplication_key)",
      "'message_received:' || new.org_id::text || ':' || new.channel_id::text || ':' || new.id::text",
      "on conflict (notification_id, device_id, channel) do nothing",
    ]
  ) assert(migration.includes(expected), `missing ${expected}`);
  assert(!migration.includes("p_sender_id"));
  assert(
    !migration.includes("p_org_id uuid,\n  p_channel_id uuid,\n  p_body text"),
  );
});

Deno.test("Phase 9C preserves complete notification and APNs allowlists", async () => {
  const migration = (await Deno.readTextFile(
    new URL(
      "../../migrations/20260715050000_notification_direct_messages_integration.sql",
      import.meta.url,
    ),
  )).toLowerCase();
  const foundation = (await Deno.readTextFile(
    new URL(
      "../../migrations/20260715020000_notification_center_foundation.sql",
      import.meta.url,
    ),
  )).toLowerCase();
  const pushMigration = (await Deno.readTextFile(
    new URL(
      "../../migrations/20260715030000_apns_push_delivery.sql",
      import.meta.url,
    ),
  )).toLowerCase();
  const values = (text: string) =>
    [...text.matchAll(/'([^']+)'/g)].map((match) => match[1]);
  const sorted = (items: string[]) => [...items].sort();

  const priorSource = foundation.match(
    /constraint sd_notifications_source_check\s+check \(source in \(([^)]+)\)\)/,
  );
  const priorCategories = foundation.match(
    /constraint sd_notifications_category_check check \(category in \(([\s\S]*?)\)\),/,
  );
  const priorQueue = pushMigration.match(
    /notification\.category in \(([^)]+)\)/,
  );
  assert(
    priorSource && priorCategories && priorQueue,
    "missing prior allowlist",
  );

  const sourceConstraint = migration.match(
    /add constraint sd_notifications_source_check\s+check \(source in \(([^)]+)\)\)/,
  );
  assert(sourceConstraint, "missing replacement source constraint");
  assertEquals(
    sorted(values(sourceConstraint[1])),
    sorted([...values(priorSource[1]), "chat"]),
  );

  const sourceValidation = migration.match(
    /p_source not in \(([^)]+)\)/,
  );
  assert(sourceValidation, "missing producer source allowlist");
  assertEquals(
    sorted(values(sourceValidation[1])),
    sorted([...values(priorSource[1]), "chat"]),
  );

  const categoryValidation = migration.match(
    /p_category not in \(([\s\S]*?)\)\s+or pg_catalog\.char_length/,
  );
  assert(categoryValidation, "missing producer category allowlist");
  assertEquals(
    sorted(values(categoryValidation[1])),
    sorted(values(priorCategories[1])),
  );

  const queueFunction = migration.slice(
    migration.indexOf(
      "create or replace function public.sd_queue_apns_deliveries",
    ),
    migration.indexOf(
      "create or replace function public.sd_mark_chat_conversation_read",
    ),
  );
  const queueAllowlist = queueFunction.match(
    /notification\.category in \(([^)]+)\)/,
  );
  assert(queueAllowlist, "missing APNs queue category allowlist");
  assertEquals(
    sorted(values(queueAllowlist[1])),
    sorted([...values(priorQueue[1]), "message_received"]),
  );
});

Deno.test("Phase 9C send/read RPCs preserve messaging authorization and use safe SECURITY DEFINER grants", async () => {
  const migration = (await Deno.readTextFile(
    new URL(
      "../../migrations/20260715050000_notification_direct_messages_integration.sql",
      import.meta.url,
    ),
  )).toLowerCase();
  for (
    const expected of [
      "security definer\nset search_path = ''",
      "if not public.sd_is_org_member(v_channel.org_id)",
      "membership.channel_id = v_channel.id",
      "membership.user_id = v_actor_id",
      "and public.sd_is_org_member(org_id)",
      "channel.org_id = sd_chat_messages.org_id",
      "public.sd_chat_is_member(channel.id, (select auth.uid()))",
      "public.sd_is_org_staff(channel.org_id)",
      "revoke all on function public.sd_send_chat_message(uuid, text, uuid)\nfrom public, anon, authenticated, service_role",
      "grant execute on function public.sd_send_chat_message(uuid, text, uuid)\nto authenticated",
      "revoke all on function public.sd_mark_chat_conversation_read(uuid, uuid)\nfrom public, anon, authenticated, service_role",
      "grant execute on function public.sd_mark_chat_conversation_read(uuid, uuid)\nto authenticated",
      "revoke all on function public.sd_notify_direct_message_received()\nfrom public, anon, authenticated, service_role",
      "revoke all on function public.sd_create_notifications(\n  uuid, uuid[], text, text, text, text, text, text, jsonb, text, uuid, text, jsonb\n) from public, anon, authenticated",
      "grant execute on function public.sd_create_notifications(\n  uuid, uuid[], text, text, text, text, text, text, jsonb, text, uuid, text, jsonb\n) to service_role",
      "revoke all on function public.sd_queue_apns_deliveries()\nfrom public, anon, authenticated, service_role",
    ]
  ) assert(migration.includes(expected), `missing ${expected}`);
});

Deno.test("Phase 9C read synchronization advances an exact boundary and leaves newer messages unread", async () => {
  const migration = (await Deno.readTextFile(
    new URL(
      "../../migrations/20260715050000_notification_direct_messages_integration.sql",
      import.meta.url,
    ),
  )).toLowerCase();
  for (
    const expected of [
      "message.id = p_through_message_id",
      "message.org_id = v_channel.org_id",
      "message.channel_id = p_channel_id",
      "add column if not exists last_read_message_id uuid",
      "order by message.created_at desc, message.id desc",
      "message.id as message_id",
      "set last_read_at = greatest",
      "last_read_message_id = case",
      "excluded.last_read_at > public.sd_chat_memberships.last_read_at",
      "public.sd_chat_memberships.last_read_message_id is null",
      "excluded.last_read_message_id > public.sd_chat_memberships.last_read_message_id",
      "notification.recipient_user_id = v_actor_id",
      "notification.category = 'message_received'",
      "notification.action_route = 'chat_conversation'",
      "notification.related_entity_id = message.id::text",
      "message.created_at < v_boundary_at",
      "message.created_at = v_boundary_at",
      "message.id <= p_through_message_id",
      "notification.read_at is null",
      "'last_read_message_id', v_last_read_message_id",
      "'notifications_marked_read', v_notifications_marked",
    ]
  ) assert(migration.includes(expected), `missing ${expected}`);
  const readFunction = migration.slice(
    migration.indexOf(
      "create or replace function public.sd_mark_chat_conversation_read",
    ),
  );
  assert(!readFunction.includes("update public.sd_chat_messages"));
  assert(!readFunction.includes("mark_all_read"));
  assert(!readFunction.includes("message.created_at > v_boundary_at"));
  assert(!readFunction.includes("message.created_at <= v_boundary_at"));
});

Deno.test("Phase 9C notification and delivery failures cannot roll back or delete persisted messages", async () => {
  const migration = (await Deno.readTextFile(
    new URL(
      "../../migrations/20260715050000_notification_direct_messages_integration.sql",
      import.meta.url,
    ),
  )).toLowerCase();
  const producer = migration.slice(
    migration.indexOf(
      "create or replace function public.sd_notify_direct_message_received",
    ),
    migration.indexOf(
      "create or replace function public.sd_queue_apns_deliveries",
    ),
  );
  assert(
    producer.includes("begin\n    perform public.sd_create_notifications"),
  );
  assert(producer.includes("exception when others then"));
  assert(producer.includes("direct_message_notification_production_failed"));
  assert(producer.includes("return new"));
  assert(producer.includes("sqlstate=%"));
  assert(
    !producer.includes(
      "raise warning 'direct_message_notification_production_failed body=",
    ),
  );
  assert(!producer.includes("delete from public.sd_chat_messages"));
  assert(!producer.includes("update public.sd_chat_messages"));
  assert(migration.includes("'organization_announcement', 'message_received'"));
  assert(
    migration.includes(
      "perform public.sd_request_notification_delivery_worker()",
    ),
  );
});
