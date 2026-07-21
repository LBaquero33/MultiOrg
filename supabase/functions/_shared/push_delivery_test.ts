import {
  APNS_MAX_PAYLOAD_BYTES,
  type APNSConfiguration,
  type APNSDeliveryFacts,
  apnsEndpoint,
  APNSProviderTokenCache,
  APNSSender,
  buildAPNSPayload,
  classifyAPNSResponse,
  createAPNSProviderToken,
} from "./apns.ts";
import {
  createNotificationDeliveryWorkerHandler,
  NOTIFICATION_DELIVERY_COMMIT_POLL_MILLISECONDS,
  type NotificationDeliveryStore,
  retryDelaySeconds,
} from "./notification_delivery_worker.ts";
import { wakeNotificationDeliveriesAfterCommit } from "./notification_delivery_wakeup.ts";
import {
  createPushDeviceRegistrationHandler,
  type PushDeviceRecord,
  type PushDeviceRegistrationStore,
  type PushRegistrationInput,
} from "./push_device_registration.ts";

const USER_A = "11111111-1111-4111-8111-111111111111";
const USER_B = "22222222-2222-4222-8222-222222222222";
const NOTIFICATION = "33333333-3333-4333-8333-333333333333";
const ORG = "44444444-4444-4444-8444-444444444444";
const DEVICE = "55555555-5555-4555-8555-555555555555";
const DELIVERY = "66666666-6666-4666-8666-666666666666";
const TOKEN = "ab".repeat(32);
const SECRET = "test-worker-secret-with-adequate-entropy";

function assert(
  condition: unknown,
  message = "assertion failed",
): asserts condition {
  if (!condition) throw new Error(message);
}
function equals(actual: unknown, expected: unknown, message = "values differ") {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(
      `${message}: ${JSON.stringify(actual)} != ${JSON.stringify(expected)}`,
    );
  }
}
async function body(response: Response): Promise<Record<string, unknown>> {
  return await response.json();
}

class FakeRegistrationStore implements PushDeviceRegistrationStore {
  devices = new Map<
    string,
    PushDeviceRecord & { userId: string; appVersion: string | null }
  >();
  registerCalls: PushRegistrationInput[] = [];

  async authenticate(request: Request) {
    return request.headers.get("Authorization")?.replace("Bearer ", "") ?? null;
  }
  async register(input: PushRegistrationInput) {
    this.registerCalls.push(input);
    const key =
      `${input.deviceToken}:${input.environment}:${input.appBundleId}`;
    const existing = this.devices.get(key);
    const value = {
      id: existing?.id ?? DEVICE,
      userId: input.actorId,
      platform: input.platform,
      environment: input.environment,
      app_bundle_id: input.appBundleId,
      notifications_authorized: input.notificationsAuthorized,
      last_registered_at: "2026-07-15T12:00:00Z",
      disabled_at: null,
      appVersion: input.appVersion,
    };
    this.devices.set(key, value);
    return value;
  }
  async unregister(
    input: {
      actorId: string;
      deviceToken: string;
      environment: "sandbox" | "production";
      appBundleId: string;
    },
  ) {
    const key =
      `${input.deviceToken}:${input.environment}:${input.appBundleId}`;
    const value = this.devices.get(key);
    if (!value || value.userId !== input.actorId) return false;
    value.disabled_at = "2026-07-15T12:01:00Z";
    value.notifications_authorized = false;
    return true;
  }
  async list(actorId: string) {
    return [...this.devices.values()].filter((device) =>
      device.userId === actorId
    );
  }
}

function registrationRequest(
  actor: string,
  overrides: Record<string, unknown> = {},
) {
  return new Request("https://example.test/push-device-registration", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${actor}`,
      "content-type": "application/json",
    },
    body: JSON.stringify({
      action: "register",
      device_token: TOKEN,
      platform: "ios",
      environment: "sandbox",
      app_bundle_id: "com.multiorg.app",
      app_version: "1.0",
      os_version: "iOS test",
      notifications_authorized: true,
      ...overrides,
    }),
  });
}

Deno.test("device registration derives actor and rejects server-controlled identity", async () => {
  const store = new FakeRegistrationStore();
  const handler = createPushDeviceRegistrationHandler(store, {
    environment: "sandbox",
    iosTopic: "com.multiorg.app",
    macOSTopic: "com.multiorg.app.mac",
  });
  const response = await handler(registrationRequest(USER_A));
  equals(response.status, 200);
  equals(store.registerCalls[0]?.actorId, USER_A);
  const denied = await handler(
    registrationRequest(USER_A, { user_id: USER_B }),
  );
  equals(denied.status, 400);
  equals((await body(denied)).error, "server_controlled_field");
});

Deno.test("device registration validates token platform environment and topic", async () => {
  const handler = createPushDeviceRegistrationHandler(
    new FakeRegistrationStore(),
    {
      environment: "sandbox",
      iosTopic: "com.multiorg.app",
      macOSTopic: null,
    },
  );
  for (
    const [overrides, code] of [
      [{ device_token: "xyz" }, "invalid_device_token"],
      [{ platform: "android" }, "invalid_platform"],
      [{ environment: "production" }, "invalid_environment"],
      [{ app_bundle_id: "example.bad" }, "invalid_bundle_id"],
    ] as [Record<string, unknown>, string][]
  ) {
    const response = await handler(registrationRequest(USER_A, overrides));
    equals(response.status, 400);
    equals((await body(response)).error, code);
  }
});

Deno.test("registration is idempotent, refreshes metadata, and transfers a token", async () => {
  const store = new FakeRegistrationStore();
  const handler = createPushDeviceRegistrationHandler(store, {
    environment: "sandbox",
    iosTopic: "com.multiorg.app",
    macOSTopic: null,
  });
  await handler(registrationRequest(USER_A));
  await handler(registrationRequest(USER_A, { app_version: "2.0" }));
  await handler(registrationRequest(USER_B));
  equals(store.devices.size, 1);
  equals([...store.devices.values()][0]?.userId, USER_B);
  equals(store.registerCalls[1]?.appVersion, "2.0");
});

Deno.test("unregister affects only the authenticated token owner and hides tokens in responses", async () => {
  const store = new FakeRegistrationStore();
  const handler = createPushDeviceRegistrationHandler(store, {
    environment: "sandbox",
    iosTopic: "com.multiorg.app",
    macOSTopic: null,
  });
  await handler(registrationRequest(USER_A));
  const denied = await handler(
    registrationRequest(USER_B, { action: "unregister" }),
  );
  equals(denied.status, 404);
  const response = await handler(
    registrationRequest(USER_A, { action: "unregister" }),
  );
  equals(response.status, 200);
  assert(!JSON.stringify(await body(response)).includes(TOKEN));
});

const facts: APNSDeliveryFacts = {
  delivery_id: DELIVERY,
  attempt_count: 1,
  notification: {
    id: NOTIFICATION,
    org_id: ORG,
    category: "payment_request_created",
    title: "Payment request",
    body: "A new request is ready.",
    action_route: "payment_request",
    action_payload: {
      payment_request_id: "77777777-7777-4777-8777-777777777777",
      secret: "no",
    },
  },
  device: {
    id: DEVICE,
    platform: "ios",
    environment: "sandbox",
    app_bundle_id: "com.multiorg.app",
    device_token: TOKEN,
  },
  unread_count: 7,
};

Deno.test("APNs endpoints and response classifications are exact", () => {
  equals(apnsEndpoint("sandbox"), "https://api.sandbox.push.apple.com");
  equals(apnsEndpoint("production"), "https://api.push.apple.com");
  equals(classifyAPNSResponse(200, "Success"), "sent");
  for (
    const reason of [
      "BadDeviceToken",
      "DeviceTokenNotForTopic",
      "Unregistered",
      "TopicDisallowed",
    ]
  ) {
    equals(classifyAPNSResponse(400, reason), "permanent_token");
  }
  for (const status of [429, 500, 503]) {
    equals(classifyAPNSResponse(status, "Unknown"), "retryable");
  }
  equals(classifyAPNSResponse(403, "ExpiredProviderToken"), "failed");
});

Deno.test("payload contains authoritative badge and only allowlisted routing metadata", () => {
  const result = buildAPNSPayload(facts.notification, facts.unread_count);
  assert(result.byteLength <= APNS_MAX_PAYLOAD_BYTES);
  const payload = result.payload as {
    aps: { badge: number };
    home_plate: Record<string, unknown>;
  };
  equals(payload.aps.badge, 7);
  equals(payload.home_plate.notification_id, NOTIFICATION);
  assert(!result.body.includes("secret"));
  assert(!result.body.includes("Stripe"));
});

Deno.test("schedule and reminder pushes retain safe event copy and routing", () => {
  for (const category of ["schedule_change", "event_reminder"]) {
    const result = buildAPNSPayload({
      ...facts.notification,
      category,
      title: category === "event_reminder" ? "Event Tomorrow" : "New Event",
      body: "Practice was added for Marist 10U.",
      action_route: "team_event",
      action_payload: {
        event_id: "77777777-7777-4777-8777-777777777777",
        team_id: "88888888-8888-4888-8888-888888888888",
        private_note: "do not include",
      },
    }, 1);
    assert(result.body.includes("Practice was added for Marist 10U."));
    assert(result.body.includes('"action_route":"team_event"'));
    assert(
      result.body.includes('"event_id":"77777777-7777-4777-8777-777777777777"'),
    );
    assert(!result.body.includes("private_note"));
  }
});

Deno.test("oversized and unknown notification payloads are bounded and generic", () => {
  const oversized = buildAPNSPayload({
    ...facts.notification,
    category: "future_private_type",
    title: "Private title",
    body: "x".repeat(10_000),
    action_route: "untrusted_route",
    action_payload: { email: "private@example.test" },
  }, 123_456);
  assert(oversized.byteLength <= APNS_MAX_PAYLOAD_BYTES);
  assert(oversized.body.includes('"title":"Home Plate"'));
  assert(oversized.body.includes('"badge":99999'));
  assert(!oversized.body.includes("private@example.test"));
});

async function privateKeyPEM(): Promise<string> {
  const pair = await crypto.subtle.generateKey(
    { name: "ECDSA", namedCurve: "P-256" },
    true,
    ["sign", "verify"],
  );
  const bytes = new Uint8Array(
    await crypto.subtle.exportKey("pkcs8", pair.privateKey),
  );
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return `-----BEGIN PRIVATE KEY-----\n${
    btoa(binary)
  }\n-----END PRIVATE KEY-----`;
}

Deno.test("provider JWT has ES256 header and team claims and cache reuses it", async () => {
  const privateKey = await privateKeyPEM();
  const token = await createAPNSProviderToken({
    keyId: "KEY123",
    teamId: "TEAM123",
    privateKey,
  }, 1_721_000_000);
  const [header, claims] = token.split(".").slice(0, 2).map((part) =>
    JSON.parse(atob(part.replaceAll("-", "+").replaceAll("_", "/")))
  );
  equals(header, { alg: "ES256", kid: "KEY123" });
  equals(claims, { iss: "TEAM123", iat: 1_721_000_000 });
  let now = 1_721_000_000;
  const cache = new APNSProviderTokenCache({
    keyId: "KEY123",
    teamId: "TEAM123",
    privateKey,
  }, () => now);
  const first = await cache.token();
  now += 60;
  equals(await cache.token(), first);
});

Deno.test("APNs sender uses environment topic and safe headers", async () => {
  const privateKey = await privateKeyPEM();
  let requestedURL = "";
  let requestedTopic = "";
  let requestedPushType = "";
  const config: APNSConfiguration = {
    keyId: "KEY123",
    teamId: "TEAM123",
    privateKey,
    environment: "sandbox",
    iosTopic: "com.multiorg.app",
    macOSTopic: null,
  };
  const sender = new APNSSender(config, async (input, init) => {
    requestedURL = String(input);
    const headers = new Headers(init?.headers);
    requestedTopic = headers.get("apns-topic") ?? "";
    requestedPushType = headers.get("apns-push-type") ?? "";
    return new Response(null, {
      status: 200,
      headers: { "apns-id": DELIVERY },
    });
  }, () => 1_721_000_000);
  const result = await sender.send(facts);
  equals(result.outcome, "sent");
  assert(
    requestedURL.startsWith("https://api.sandbox.push.apple.com/3/device/"),
  );
  equals(requestedTopic, "com.multiorg.app");
  equals(requestedPushType, "alert");
});

class FakeDeliveryStore implements NotificationDeliveryStore {
  finalizations: Array<Record<string, unknown>> = [];
  constructor(readonly delivery: APNSDeliveryFacts = facts) {}
  async claim(_limit: number, claimToken: string) {
    return { claim_token: claimToken, deliveries: [this.delivery] };
  }
  async finalize(input: Parameters<NotificationDeliveryStore["finalize"]>[0]) {
    this.finalizations.push(input);
    const status = input.outcome === "sent"
      ? "sent"
      : input.outcome === "retryable" && this.delivery.attempt_count < 5
      ? "retryable"
      : "failed";
    return {
      delivery_id: input.deliveryId,
      status: status as "sent" | "retryable" | "failed",
      attempt_count: this.delivery.attempt_count,
    };
  }
}

class SequenceDeliveryStore extends FakeDeliveryStore {
  claimCalls = 0;
  constructor(private readonly claims: APNSDeliveryFacts[][]) {
    super();
  }
  override async claim(_limit: number, claimToken: string) {
    const deliveries = this.claims[this.claimCalls] ?? [];
    this.claimCalls += 1;
    return { claim_token: claimToken, deliveries };
  }
}

function workerRequest(source?: string, secret = SECRET): Request {
  return new Request("https://worker.test", {
    method: "POST",
    headers: {
      "x-home-plate-worker-secret": secret,
      "content-type": "application/json",
    },
    body: source ? JSON.stringify({ source }) : undefined,
  });
}

Deno.test("worker requires internal secret and finalizes APNs success", async () => {
  const store = new FakeDeliveryStore();
  const handler = createNotificationDeliveryWorkerHandler(store, {
    send: async () => ({
      outcome: "sent",
      apnsId: DELIVERY,
      status: 200,
      reason: "Success",
    }),
  }, SECRET);
  equals(
    (await handler(new Request("https://worker.test", { method: "POST" })))
      .status,
    401,
  );
  const response = await handler(
    workerRequest(),
  );
  equals(response.status, 200);
  equals((await body(response)).sent, 1);
  equals(store.finalizations[0]?.outcome, "sent");
});

Deno.test("worker retries transient failures with bounded schedule and stops at five", async () => {
  equals([1, 2, 3, 4].map(retryDelaySeconds), [30, 120, 600, 1_800]);
  for (const attempt of [1, 5]) {
    const store = new FakeDeliveryStore({ ...facts, attempt_count: attempt });
    const handler = createNotificationDeliveryWorkerHandler(
      store,
      {
        send: async () => ({
          outcome: "retryable",
          apnsId: null,
          status: 503,
          reason: "ServiceUnavailable",
        }),
      },
      SECRET,
      () => 1_721_000_000_000,
    );
    await handler(
      workerRequest(),
    );
    equals(store.finalizations[0]?.nextAttemptAt === null, attempt === 5);
  }
});

Deno.test("queue wakeup performs one bounded follow-up claim for a commit visibility race", async () => {
  const store = new SequenceDeliveryStore([[], [facts]]);
  let sent = 0;
  const delays: number[] = [];
  const handler = createNotificationDeliveryWorkerHandler(
    store,
    {
      send: async () => {
        sent += 1;
        return {
          outcome: "sent",
          apnsId: DELIVERY,
          status: 200,
          reason: "Success",
        };
      },
    },
    SECRET,
    () => 1_721_000_000_000,
    async (milliseconds) => {
      delays.push(milliseconds);
    },
  );
  const response = await handler(workerRequest("queue_trigger"));
  const result = await body(response);
  equals(response.status, 200);
  equals(store.claimCalls, 2);
  equals(delays, [NOTIFICATION_DELIVERY_COMMIT_POLL_MILLISECONDS]);
  equals(result.polls, 2);
  equals(result.claimed, 1);
  equals(sent, 1);
});

Deno.test("post-commit producer wake sends only the exact worker header and safe source", async () => {
  let requestedURL = "";
  let requestedHeaders = new Headers();
  let requestedBody = "";
  const result = await wakeNotificationDeliveriesAfterCommit(
    "https://project.supabase.co",
    SECRET,
    async (input, init) => {
      requestedURL = String(input);
      requestedHeaders = new Headers(init?.headers);
      requestedBody = String(init?.body ?? "");
      return new Response(JSON.stringify({ claimed: 1 }), { status: 200 });
    },
  );
  equals(result, { outcome: "succeeded", status: 200 });
  equals(
    requestedURL,
    "https://project.supabase.co/functions/v1/process-notification-deliveries",
  );
  equals(requestedHeaders.get("x-home-plate-worker-secret"), SECRET);
  equals(requestedHeaders.get("content-type"), "application/json");
  equals(JSON.parse(requestedBody), { source: "producer_commit" });
  equals(requestedHeaders.get("apikey"), null);
});

Deno.test("post-commit producer wake exposes 401 and 500 safely without throwing business work", async () => {
  for (
    const [status, outcome] of [[401, "unauthorized"], [
      500,
      "worker_failed",
    ]] as const
  ) {
    const result = await wakeNotificationDeliveriesAfterCommit(
      "https://project.supabase.co",
      SECRET,
      async () => new Response(null, { status }),
    );
    equals(result, { outcome, status });
  }
  equals(
    await wakeNotificationDeliveriesAfterCommit("", SECRET),
    { outcome: "not_configured", status: null },
  );
  equals(
    await wakeNotificationDeliveriesAfterCommit(
      "https://project.supabase.co",
      SECRET,
      async () => {
        throw new Error("network down");
      },
    ),
    { outcome: "network_failed", status: null },
  );
});

Deno.test("an empty immediate queue is polled only once and manual invocation remains single-pass", async () => {
  const immediateStore = new SequenceDeliveryStore([[], []]);
  const immediate = createNotificationDeliveryWorkerHandler(
    immediateStore,
    {
      send: async () => ({
        outcome: "sent",
        apnsId: null,
        status: 200,
        reason: "Success",
      }),
    },
    SECRET,
    () => 0,
    async () => {},
  );
  const immediateBody = await body(
    await immediate(workerRequest("database_queue")),
  );
  equals(immediateStore.claimCalls, 2);
  equals(immediateBody.polls, 2);
  equals(immediateBody.claimed, 0);

  const manualStore = new SequenceDeliveryStore([[], [facts]]);
  const manual = createNotificationDeliveryWorkerHandler(
    manualStore,
    {
      send: async () => ({
        outcome: "sent",
        apnsId: null,
        status: 200,
        reason: "Success",
      }),
    },
    SECRET,
    () => 0,
    async () => {},
  );
  const manualBody = await body(await manual(workerRequest()));
  equals(manualStore.claimCalls, 1);
  equals(manualBody.source, "manual");
  equals(manualBody.polls, 1);
});

Deno.test("one-minute cron fallback processes work missed by the immediate wakeup", async () => {
  const store = new SequenceDeliveryStore([[], [], [facts]]);
  let sent = 0;
  const handler = createNotificationDeliveryWorkerHandler(
    store,
    {
      send: async () => {
        sent += 1;
        return {
          outcome: "sent",
          apnsId: DELIVERY,
          status: 200,
          reason: "Success",
        };
      },
    },
    SECRET,
    () => 0,
    async () => {},
  );
  equals(
    (await body(await handler(workerRequest("queue_trigger")))).claimed,
    0,
  );
  const fallback = await body(await handler(workerRequest("cron_fallback")));
  equals(fallback.claimed, 1);
  equals(fallback.polls, 1);
  equals(sent, 1);
});

Deno.test("concurrent wakeups remain harmless when the store claim is exclusive", async () => {
  let claimed = false;
  let sent = 0;
  const store: NotificationDeliveryStore = {
    async claim(_limit, claimToken) {
      if (claimed) return { claim_token: claimToken, deliveries: [] };
      claimed = true;
      return { claim_token: claimToken, deliveries: [facts] };
    },
    async finalize(input) {
      return {
        delivery_id: input.deliveryId,
        status: "sent",
        attempt_count: 1,
      };
    },
  };
  const handler = createNotificationDeliveryWorkerHandler(store, {
    send: async () => {
      sent += 1;
      return {
        outcome: "sent",
        apnsId: DELIVERY,
        status: 200,
        reason: "Success",
      };
    },
  }, SECRET);
  await Promise.all([handler(workerRequest()), handler(workerRequest())]);
  equals(sent, 1);
});

Deno.test("migration creates durable idempotent server-only delivery queue for all Phase 9B producers", async () => {
  const migration = await Deno.readTextFile(
    new URL(
      "../../migrations/20260715030000_apns_push_delivery.sql",
      import.meta.url,
    ),
  );
  for (
    const expected of [
      "unique (notification_id, device_id, channel)",
      "device.notifications_authorized",
      "device.disabled_at is null",
      "payment_request_created",
      "payment_received",
      "organization_announcement",
      "for update of delivery skip locked",
      "delivery.attempt_count < 5",
      "grant execute on function public.sd_claim_notification_deliveries(integer, uuid)\nto service_role",
    ]
  ) assert(migration.includes(expected), `missing ${expected}`);
  assert(
    !migration.includes(
      "grant execute on function public.sd_claim_notification_deliveries(integer, uuid)\nto authenticated",
    ),
  );
});

Deno.test("wakeup reliability migration preserves exact header, Vault names, diagnostics, and one-minute cron", async () => {
  const migration = await Deno.readTextFile(
    new URL(
      "../../migrations/20260715040000_notification_delivery_wakeup_reliability.sql",
      import.meta.url,
    ),
  );
  for (
    const expected of [
      "'x-home-plate-worker-secret', v_secret",
      "'content-type', 'application/json'",
      "secret.name = 'notification_delivery_worker_url'",
      "secret.name = 'notification_delivery_worker_secret'",
      "'vault_url_missing'",
      "'vault_secret_missing'",
      "'worker_unauthorized'",
      "'worker_server_error'",
      "join net._http_response response on response.id = wakeup.request_id",
      "'home-plate-notification-delivery-worker'",
      "'* * * * *'",
      "select public.sd_request_notification_delivery_worker('cron_fallback');",
      "perform cron.unschedule(v_job_id)",
      "revoke all on function public.sd_request_notification_delivery_worker(text)",
    ]
  ) assert(migration.includes(expected), `missing ${expected}`);
  assert(!migration.includes("update public.sd_notifications"));
  assert(!migration.includes("delete from public.sd_notifications"));
  assert(!migration.includes("apikey"));
});

Deno.test("interactive Phase 9B producers wake the worker only after their transaction RPC returns", async () => {
  for (
    const path of [
      "../payment_requests/index.ts",
      "../notification-center/index.ts",
    ]
  ) {
    const source = await Deno.readTextFile(new URL(path, import.meta.url));
    const rpcIndex = source.indexOf("admin.rpc(");
    const wakeIndex = source.indexOf("wakeNotificationDeliveriesAfterCommit(");
    assert(rpcIndex >= 0, `${path} has no transaction RPC`);
    assert(wakeIndex > rpcIndex, `${path} wakes before its transaction RPC`);
  }
});

Deno.test("chat realtime no longer schedules a duplicate local alert beside APNs", async () => {
  const appState = await Deno.readTextFile(
    new URL("../../../HomePlate/Core/AppState.swift", import.meta.url),
  );
  const notificationCenter = await Deno.readTextFile(
    new URL(
      "../../../HomePlate/Features/Notifications/NotificationCenterView.swift",
      import.meta.url,
    ),
  );
  assert(!appState.includes("sd_chat_message_"));
  assert(!appState.includes("scheduleChatNotification"));
  assert(appState.includes("chatLastInsert = ins"));
  assert(!notificationCenter.includes("UNNotificationRequest"));
});
