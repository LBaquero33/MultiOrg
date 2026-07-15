import {
  buildEligiblePaymentRequestRoster,
  type CreatePaymentRequestBatchInput,
  type CreatePaymentRequestBatchResult,
  createPaymentRequestHandler,
  type EligiblePaymentRequestPlayer,
  type OrganizationMembership,
  type ParentPaymentLink,
  PAYMENT_REQUEST_MAX_AMOUNT_CENTS,
  PAYMENT_REQUEST_MAX_BATCH_SIZE,
  type PaymentRequestRecord,
  type PaymentRequestStore,
} from "./payment_requests.ts";

function assert(condition: boolean, message: string) {
  if (!condition) throw new Error(message);
}

function assertEqual<T>(actual: T, expected: T, message: string) {
  if (actual !== expected) {
    throw new Error(`${message}: expected ${expected}, received ${actual}`);
  }
}

const orgId = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
const otherOrgId = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb";
const ownerId = "11111111-1111-4111-8111-111111111111";
const adminId = "22222222-2222-4222-8222-222222222222";
const coachId = "33333333-3333-4333-8333-333333333333";
const parentId = "44444444-4444-4444-8444-444444444444";
const playerId = "55555555-5555-4555-8555-555555555555";
const otherPlayerId = "66666666-6666-4666-8666-666666666666";
const requestId = "77777777-7777-4777-8777-777777777777";
const keyId = "88888888-8888-4888-8888-888888888888";

function generatedUuid(index: number): string {
  return `aaaaaaaa-aaaa-4aaa-8aaa-${index.toString(16).padStart(12, "0")}`;
}

class FakeStore implements PaymentRequestStore {
  actorId: string | null = ownerId;
  organizations = new Map([[orgId, "active"], [otherOrgId, "active"]]);
  memberships = new Map<string, OrganizationMembership>();
  links = new Map<string, ParentPaymentLink[]>();
  records = new Map<string, PaymentRequestRecord>();
  batches = new Map<
    string,
    { input: CreatePaymentRequestBatchInput; records: PaymentRequestRecord[] }
  >();
  platformAdmins = new Set<string>();
  auditRecords: Array<{
    actorId: string;
    orgId: string;
    action: string;
    targetId: string;
    authorizationSource: string;
  }> = [];
  eligibleRosterOverride: EligiblePaymentRequestPlayer[] | null = null;
  batchCallCount = 0;
  failBatchCreation = false;

  constructor() {
    this.setMembership(orgId, ownerId, "owner");
    this.setMembership(orgId, playerId, "player");
  }

  setMembership(org: string, user: string, role: string, status = "active") {
    this.memberships.set(`${org}:${user}`, { role, status });
  }

  setLink(org: string, parent: string, child: string, canPay: boolean) {
    this.links.set(`${org}:${parent}`, [{ child_id: child, can_pay: canPay }]);
  }

  addRecord(
    status: PaymentRequestRecord["status"] = "open",
    childId = playerId,
    id = requestId,
  ) {
    const record: PaymentRequestRecord = {
      id,
      request_batch_id: null,
      org_id: orgId,
      child_id: childId,
      created_by: ownerId,
      title: "Team fee",
      notes: "One-time request",
      amount_cents: 12_345,
      currency: "usd",
      due_date: "2026-08-01",
      status,
      created_at: "2026-07-14T12:00:00.123456+00:00",
      updated_at: "2026-07-14T12:00:00.123456+00:00",
      player_name: "Test Player",
    };
    this.records.set(record.id, record);
    return record;
  }

  async authenticate(request: Request) {
    return request.headers.has("Authorization") ? this.actorId : null;
  }
  async organizationStatus(id: string) {
    return this.organizations.get(id) ?? null;
  }
  async membership(org: string, user: string) {
    return this.memberships.get(`${org}:${user}`) ?? null;
  }
  async isPlatformAdmin(user: string) {
    return this.platformAdmins.has(user);
  }
  async parentLinks(org: string, parent: string) {
    return this.links.get(`${org}:${parent}`) ?? [];
  }
  async eligiblePlayers(org: string) {
    const candidates: EligiblePaymentRequestPlayer[] = [];
    if (this.eligibleRosterOverride) {
      candidates.push(...this.eligibleRosterOverride);
    } else {
      for (const [key, membership] of this.memberships) {
        const [membershipOrg, userId] = key.split(":");
        candidates.push(eligiblePlayer(
          membershipOrg,
          userId,
          membership.role,
          membership.status,
        ));
      }
    }
    const activeMemberships = candidates.filter((candidate) =>
      candidate.org_id === org && candidate.role === "player" &&
      candidate.status === "active"
    );
    const players = Array.from(
      new Map(
        activeMemberships.map((candidate) => [candidate.user_id, candidate]),
      ).values(),
    );
    return {
      players,
      active_membership_count: activeMemberships.length,
      deduplicated_user_id_count: players.length,
      profile_enrichment_count:
        players.filter((player) => player.full_name !== null).length,
      username_enrichment_count:
        players.filter((player) => player.username !== null).length,
    };
  }
  async activePlayerIds(org: string, playerIds: string[]) {
    return new Set(playerIds.filter((id) => {
      const membership = this.memberships.get(`${org}:${id}`);
      return membership?.role === "player" && membership.status === "active";
    }));
  }
  async paymentRequest(org: string, id: string) {
    const record = this.records.get(id);
    return record?.org_id === org ? record : null;
  }
  async paymentRequests(org: string, playerIds?: string[]) {
    return Array.from(this.records.values()).filter((record) =>
      record.org_id === org &&
      (!playerIds || playerIds.includes(record.child_id))
    );
  }
  async createPaymentRequestBatch(
    input: CreatePaymentRequestBatchInput,
  ): Promise<CreatePaymentRequestBatchResult> {
    this.batchCallCount += 1;
    const lookupKey =
      `${input.org_id}:${input.actor_id}:${input.idempotency_operation}:${input.idempotency_key}`;
    const existing = this.batches.get(lookupKey);
    if (existing) {
      if (JSON.stringify(existing.input) !== JSON.stringify(input)) {
        return { kind: "idempotency_conflict" };
      }
      return {
        kind: "success",
        records: existing.records,
        createdCount: 0,
        reused: true,
        authorizationSource: this.authorizationSource(
          input.org_id,
          input.actor_id,
        ),
      };
    }
    if (this.failBatchCreation) throw new Error("simulated_atomic_failure");

    const batchId = generatedUuid(9_000 + this.batches.size);
    const records = input.player_ids.map((
      childId,
      index,
    ): PaymentRequestRecord => ({
      id: generatedUuid(10_000 + this.records.size + index),
      request_batch_id: batchId,
      org_id: input.org_id,
      child_id: childId,
      created_by: input.actor_id,
      title: input.title,
      notes: input.description,
      amount_cents: input.amount_cents,
      currency: input.currency,
      due_date: input.due_date,
      status: "open",
      created_at: "2026-07-14T12:00:00.123456+00:00",
      updated_at: "2026-07-14T12:00:00.123456+00:00",
      player_name: `Player ${index + 1}`,
    }));
    for (const record of records) this.records.set(record.id, record);
    this.batches.set(lookupKey, { input, records });
    const authorizationSource = this.authorizationSource(
      input.org_id,
      input.actor_id,
    );
    if (this.platformAdmins.has(input.actor_id)) {
      this.auditRecords.push({
        actorId: input.actor_id,
        orgId: input.org_id,
        action: "platform_payment_request_batch_created",
        targetId: batchId,
        authorizationSource,
      });
    }
    return {
      kind: "success",
      records,
      createdCount: records.length,
      reused: false,
      authorizationSource,
    };
  }
  async cancelOpenPaymentRequest(org: string, actor: string, id: string) {
    const record = this.records.get(id);
    if (!record || record.org_id !== org) {
      return { kind: "payment_request_not_found" as const };
    }
    if (record.status === "paid") {
      return { kind: "paid_request_cannot_be_canceled" as const };
    }
    if (record.status === "canceled") {
      return { kind: "payment_request_already_canceled" as const };
    }
    if (record.status !== "open") {
      return { kind: "payment_request_state_conflict" as const };
    }
    const canceled = { ...record, status: "canceled" as const };
    this.records.set(id, canceled);
    const authorizationSource = this.authorizationSource(org, actor);
    if (this.platformAdmins.has(actor)) {
      this.auditRecords.push({
        actorId: actor,
        orgId: org,
        action: "platform_payment_request_canceled",
        targetId: id,
        authorizationSource,
      });
    }
    return { kind: "success" as const, record: canceled, authorizationSource };
  }

  private authorizationSource(org: string, actor: string) {
    const membership = this.memberships.get(`${org}:${actor}`);
    return membership?.status === "active" &&
        ["owner", "admin"].includes(membership.role)
      ? "organization_membership" as const
      : "platform_support" as const;
  }
}

function eligiblePlayer(
  organizationId: string,
  userId: string,
  role = "player",
  status = "active",
  name: string | null = "Test Player",
): EligiblePaymentRequestPlayer {
  return {
    org_id: organizationId,
    user_id: userId,
    role,
    status,
    created_at: "2026-07-14T12:00:00Z",
    created_by: ownerId,
    username: null,
    email: null,
    full_name: name,
    profile_role: role,
  };
}

function createBody(overrides: Record<string, unknown> = {}) {
  return {
    action: "create",
    org_id: orgId,
    player_ids: [playerId],
    title: "Team fee",
    description: "One-time request",
    amount_cents: 12_345,
    currency: "usd",
    due_date: "2026-08-01",
    idempotency_key: keyId,
    ...overrides,
  };
}

async function call(
  store: FakeStore,
  body: Record<string, unknown>,
  authenticated = true,
) {
  const request = new Request("http://localhost/payment_requests", {
    method: "POST",
    headers: authenticated
      ? { "content-type": "application/json", Authorization: "Bearer test" }
      : { "content-type": "application/json" },
    body: JSON.stringify(body),
  });
  const response = await createPaymentRequestHandler(store)(request);
  return { response, json: await response.json() as Record<string, unknown> };
}

function jsonArray(value: unknown, message: string): Record<string, unknown>[] {
  assert(Array.isArray(value), message);
  return value as Record<string, unknown>[];
}

Deno.test("payment requests reject a missing JWT with a sanitized message", async () => {
  const { response, json } = await call(new FakeStore(), createBody(), false);
  assertEqual(response.status, 401, "status");
  assertEqual(json.error, "invalid_auth", "error");
  assert(
    typeof json.message === "string" && json.message.length > 0,
    "sanitized message",
  );
});

Deno.test("payment requests reject an invalid organization", async () => {
  const { response, json } = await call(
    new FakeStore(),
    createBody({ org_id: otherPlayerId }),
  );
  assertEqual(response.status, 404, "status");
  assertEqual(json.error, "organization_inactive_or_missing", "error");
});

Deno.test("eligible-player roster is organization scoped, active-player only, and deduplicated", async () => {
  const store = new FakeStore();
  store.eligibleRosterOverride = [
    eligiblePlayer(orgId, playerId),
    eligiblePlayer(orgId, playerId, "player", "active", "Duplicate"),
    eligiblePlayer(otherOrgId, otherPlayerId),
    eligiblePlayer(orgId, generatedUuid(21), "player", "suspended"),
    eligiblePlayer(orgId, generatedUuid(22), "coach"),
    eligiblePlayer(orgId, generatedUuid(23), "parent"),
    eligiblePlayer(orgId, generatedUuid(24), "owner"),
  ];
  const { response, json } = await call(store, {
    action: "list_eligible_players",
    org_id: orgId,
  });
  const players = jsonArray(json.players, "eligible players");
  assertEqual(response.status, 200, "status");
  assertEqual(players.length, 1, "eligible count");
  assertEqual(players[0].org_id, orgId, "organization");
  assertEqual(players[0].user_id, playerId, "player");
  assert(!("id" in players[0]), "roster identity is explicitly user_id");
});

Deno.test("eight authoritative active-player membership IDs return eight players", () => {
  const memberships = Array.from({ length: 8 }, (_, index) => ({
    user_id: generatedUuid(100 + index),
  }));
  const roster = buildEligiblePaymentRequestRoster(orgId, memberships, [], []);
  assertEqual(roster.active_membership_count, 8, "active membership count");
  assertEqual(roster.deduplicated_user_id_count, 8, "deduplicated count");
  assertEqual(roster.players.length, 8, "returned player count");
});

Deno.test("missing profile and organization username never remove an eligible membership", () => {
  const roster = buildEligiblePaymentRequestRoster(
    orgId,
    [{ user_id: playerId }, { user_id: otherPlayerId }],
    [{ id: playerId, full_name: "Named Player", role: "coach" }],
    [{ user_id: otherPlayerId, username: "org-player" }],
  );
  assertEqual(roster.players.length, 2, "both membership IDs remain");
  assertEqual(roster.profile_enrichment_count, 1, "one profile enrichment");
  assertEqual(roster.username_enrichment_count, 1, "one username enrichment");
  assertEqual(roster.players[0].username, null, "missing username is nullable");
  assertEqual(roster.players[1].full_name, null, "missing profile is nullable");
});

Deno.test("enrichment IDs cannot replace the membership user_id", () => {
  const enrichmentId = generatedUuid(999);
  const roster = buildEligiblePaymentRequestRoster(
    orgId,
    [{ user_id: playerId.toUpperCase() }],
    [{ id: enrichmentId, full_name: "Wrong Identity", role: "player" }],
    [{ user_id: enrichmentId, username: "wrong-identity" }],
  );
  assertEqual(roster.players.length, 1, "membership remains eligible");
  assertEqual(
    roster.players[0].user_id,
    playerId,
    "membership UUID is canonical",
  );
  assertEqual(
    roster.players[0].full_name,
    null,
    "foreign profile ID is ignored",
  );
  assertEqual(
    roster.players[0].username,
    null,
    "foreign username ID is ignored",
  );
});

Deno.test("missing optional display data preserves the UUID needed for the Player suffix fallback", () => {
  const fallbackId = "00000000-0000-4000-8000-00000000abcd";
  const roster = buildEligiblePaymentRequestRoster(
    orgId,
    [{ user_id: fallbackId }],
    [],
    [],
  );
  const player = roster.players[0];
  assertEqual(player.user_id, fallbackId, "fallback UUID");
  assertEqual(player.full_name, null, "full name remains optional");
  assertEqual(player.username, null, "username remains optional");
  assertEqual(player.email, null, "email remains optional");
  assertEqual(
    `Player ${player.user_id.slice(-6)}`,
    "Player 00abcd",
    "display fallback",
  );
});

Deno.test("global profile role enriches diagnostics but never changes membership eligibility", () => {
  const roster = buildEligiblePaymentRequestRoster(
    orgId,
    [{ user_id: playerId }],
    [{ id: playerId, full_name: "Player Name", role: "coach" }],
    [],
  );
  assertEqual(roster.players.length, 1, "eligible membership remains");
  assertEqual(
    roster.players[0].role,
    "player",
    "membership role is authoritative",
  );
  assertEqual(
    roster.players[0].profile_role,
    "coach",
    "profile role is enrichment only",
  );
});

Deno.test("duplicate authoritative membership IDs are deduplicated without dropping the player", () => {
  const roster = buildEligiblePaymentRequestRoster(
    orgId,
    [{ user_id: playerId }, { user_id: playerId }],
    [],
    [],
  );
  assertEqual(roster.active_membership_count, 2, "raw membership count");
  assertEqual(roster.deduplicated_user_id_count, 1, "unique ID count");
  assertEqual(roster.players.length, 1, "returned player count");
});

Deno.test("eligible-player response contract remains players plus authorization_source", async () => {
  const { response, json } = await call(
    new FakeStore(),
    { action: "list_eligible_players", org_id: orgId },
  );
  assertEqual(response.status, 200, "status");
  assertEqual(
    JSON.stringify(Object.keys(json).sort()),
    JSON.stringify(["authorization_source", "players"]),
    "top-level response keys",
  );
});

Deno.test("production roster adapter uses authoritative memberships and optional enrichment", async () => {
  const source = await Deno.readTextFile(
    new URL("../payment_requests/index.ts", import.meta.url),
  );
  const rosterAdapter = source.slice(
    source.indexOf("async eligiblePlayers(orgId)"),
    source.indexOf("async activePlayerIds(orgId"),
  );
  assert(
    rosterAdapter.includes('.from("sd_org_memberships")'),
    "membership table is authoritative",
  );
  assert(
    rosterAdapter.includes('.select("user_id")'),
    "only membership user IDs establish eligibility",
  );
  assert(
    rosterAdapter.includes('.eq("org_id", orgId)'),
    "organization predicate",
  );
  assert(
    rosterAdapter.includes('.eq("role", "player")'),
    "player-role predicate",
  );
  assert(
    rosterAdapter.includes('.eq("status", "active")'),
    "active-status predicate",
  );
  assert(
    rosterAdapter.includes('admin.from("profiles")'),
    "profile enrichment is separate",
  );
  assert(
    rosterAdapter.includes('admin.from("sd_org_usernames")'),
    "username enrichment is separate",
  );
  assert(!rosterAdapter.includes("!inner"), "no inner enrichment join");
  assert(!rosterAdapter.includes("team"), "team membership is not required");
});

Deno.test("every roster user_id is valid create input, individually and as one batch", async () => {
  const rosterStore = new FakeStore();
  rosterStore.setMembership(orgId, otherPlayerId, "player");
  const rosterResult = await call(rosterStore, {
    action: "list_eligible_players",
    org_id: orgId,
  });
  const players = jsonArray(rosterResult.json.players, "eligible players");
  const rosterUserIds = players.map((player) => String(player.user_id));
  assertEqual(rosterUserIds.length, 2, "roster player count");

  for (const rosterUserId of rosterUserIds) {
    const individualStore = new FakeStore();
    individualStore.setMembership(orgId, otherPlayerId, "player");
    const result = await call(
      individualStore,
      createBody({ player_ids: [rosterUserId] }),
    );
    assertEqual(result.response.status, 201, `individual ${rosterUserId}`);
  }

  const batchStore = new FakeStore();
  batchStore.setMembership(orgId, otherPlayerId, "player");
  const batch = await call(
    batchStore,
    createBody({ player_ids: rosterUserIds }),
  );
  assertEqual(batch.response.status, 201, "batch status");
  assertEqual(
    jsonArray(batch.json.requests, "batch requests").length,
    rosterUserIds.length,
    "one request per roster user_id",
  );
});

Deno.test("uppercase Swift UUID text is canonicalized before active-membership validation and RPC input", async () => {
  const store = new FakeStore();
  const result = await call(
    store,
    createBody({ player_ids: [playerId.toUpperCase()] }),
  );
  assertEqual(result.response.status, 201, "create status");
  const request = jsonArray(result.json.requests, "requests")[0];
  assertEqual(request.player_id, playerId, "canonical membership user ID");
  const batchInput = Array.from(store.batches.values())[0].input;
  assertEqual(batchInput.player_ids[0], playerId, "canonical RPC player ID");
});

Deno.test("active organization admin can load the payment roster", async () => {
  const store = new FakeStore();
  store.actorId = adminId;
  store.setMembership(orgId, adminId, "admin");
  const result = await call(store, {
    action: "list_eligible_players",
    org_id: orgId,
  });
  assertEqual(result.response.status, 200, "status");
});

for (
  const [role, actor] of [["coach", coachId], ["parent", parentId], [
    "player",
    playerId,
  ]] as const
) {
  Deno.test(`${role} cannot load the owner/admin payment roster`, async () => {
    const store = new FakeStore();
    store.actorId = actor;
    store.setMembership(orgId, actor, role);
    const result = await call(store, {
      action: "list_eligible_players",
      org_id: orgId,
    });
    assertEqual(result.response.status, 403, "status");
  });
}

Deno.test("platform administrator without organization membership loads the scoped roster", async () => {
  const store = new FakeStore();
  store.actorId = adminId;
  store.platformAdmins.add(adminId);
  const result = await call(store, {
    action: "list_eligible_players",
    org_id: orgId,
  });
  assertEqual(result.response.status, 200, "status");
  assertEqual(
    result.json.authorization_source,
    "platform_support",
    "authorization source",
  );
  assert(
    !store.memberships.has(`${orgId}:${adminId}`),
    "support access creates no membership",
  );
});

for (const [role, actor] of [["owner", ownerId], ["admin", adminId]] as const) {
  Deno.test(`active ${role} creates a typed one-request array envelope`, async () => {
    const store = new FakeStore();
    store.actorId = actor;
    store.setMembership(orgId, actor, role);
    const { response, json } = await call(store, createBody());
    const requests = jsonArray(json.requests, "requests array");
    assertEqual(response.status, 201, "status");
    assertEqual(requests.length, 1, "request count");
    assertEqual(requests[0].status, "open", "server status");
    assertEqual(requests[0].created_by, actor, "server creator");
    assertEqual(json.created_count, 1, "created count");
    assertEqual(json.reused, false, "reused marker");
    assertEqual(
      json.authorization_source,
      "organization_membership",
      "authorization source",
    );
  });
}

for (
  const [role, actor] of [["coach", coachId], ["parent", parentId], [
    "player",
    playerId,
  ]] as const
) {
  Deno.test(`${role} cannot create a payment request`, async () => {
    const store = new FakeStore();
    store.actorId = actor;
    store.setMembership(orgId, actor, role);
    const { response } = await call(store, createBody());
    assertEqual(response.status, 403, "status");
    assertEqual(store.batchCallCount, 0, "batch calls");
  });
}

Deno.test("inactive owner and inactive platform administrator cannot create", async () => {
  const inactive = new FakeStore();
  inactive.setMembership(orgId, ownerId, "owner", "disabled");
  assertEqual(
    (await call(inactive, createBody())).response.status,
    403,
    "inactive owner",
  );

  const platformOnly = new FakeStore();
  platformOnly.actorId = adminId;
  assertEqual(
    (await call(platformOnly, createBody())).response.status,
    403,
    "platform grant absent",
  );
});

Deno.test("platform support creates one request and audits the mutation", async () => {
  const store = new FakeStore();
  store.actorId = adminId;
  store.platformAdmins.add(adminId);
  const result = await call(store, createBody());
  assertEqual(result.response.status, 201, "status");
  assertEqual(
    result.json.authorization_source,
    "platform_support",
    "authorization source",
  );
  assertEqual(
    jsonArray(result.json.requests, "requests").length,
    1,
    "single request",
  );
  assertEqual(store.auditRecords.length, 1, "audit count");
  assertEqual(
    store.auditRecords[0].action,
    "platform_payment_request_batch_created",
    "audit action",
  );
  assertEqual(
    store.auditRecords[0].authorizationSource,
    "platform_support",
    "audit source",
  );
  assert(
    !store.memberships.has(`${orgId}:${adminId}`),
    "support access creates no membership",
  );
});

Deno.test("a platform administrator using an owner membership is still audited with membership authority", async () => {
  const store = new FakeStore();
  store.platformAdmins.add(ownerId);
  const result = await call(store, createBody());
  assertEqual(
    result.json.authorization_source,
    "organization_membership",
    "response source",
  );
  assertEqual(store.auditRecords.length, 1, "audit count");
  assertEqual(
    store.auditRecords[0].authorizationSource,
    "organization_membership",
    "audit source",
  );
});

Deno.test("platform support creates a multi-player batch without changing idempotency", async () => {
  const store = new FakeStore();
  store.actorId = adminId;
  store.platformAdmins.add(adminId);
  store.setMembership(orgId, otherPlayerId, "player");
  const first = await call(
    store,
    createBody({ player_ids: [otherPlayerId, playerId] }),
  );
  const retry = await call(
    store,
    createBody({ player_ids: [playerId, otherPlayerId] }),
  );
  assertEqual(
    jsonArray(first.json.requests, "requests").length,
    2,
    "batch size",
  );
  assertEqual(
    first.json.authorization_source,
    "platform_support",
    "authorization source",
  );
  assertEqual(retry.json.reused, true, "retry reused");
  assertEqual(store.records.size, 2, "no duplicate requests");
  assertEqual(store.auditRecords.length, 1, "retry is not a second mutation");
});

Deno.test("client-provided platform authority is ignored and rejected", async () => {
  const store = new FakeStore();
  store.actorId = coachId;
  store.setMembership(orgId, coachId, "coach");
  const result = await call(store, createBody({ is_platform_admin: true }));
  assertEqual(result.response.status, 400, "status");
  assertEqual(result.json.error, "server_controlled_field", "error");
  assertEqual(store.batchCallCount, 0, "no mutation");
});

Deno.test("empty selection is rejected and duplicate player UUIDs are deduplicated", async () => {
  const store = new FakeStore();
  const empty = await call(store, createBody({ player_ids: [] }));
  assertEqual(empty.response.status, 400, "empty status");
  assertEqual(empty.json.error, "invalid_players", "empty error");

  const duplicate = await call(
    store,
    createBody({ player_ids: [playerId, playerId] }),
  );
  assertEqual(duplicate.response.status, 201, "duplicate status");
  assertEqual(
    jsonArray(duplicate.json.requests, "requests").length,
    1,
    "deduplicated rows",
  );
});

Deno.test("batch-size limit is enforced", async () => {
  const store = new FakeStore();
  const players = Array.from(
    { length: PAYMENT_REQUEST_MAX_BATCH_SIZE + 1 },
    (_, index) => generatedUuid(index + 1),
  );
  const result = await call(store, createBody({ player_ids: players }));
  assertEqual(result.response.status, 400, "status");
  assertEqual(result.json.error, "payment_request_batch_too_large", "error");
  assertEqual(store.batchCallCount, 0, "no transaction");
});

Deno.test("cross-organization player rejects the entire batch", async () => {
  const store = new FakeStore();
  store.setMembership(otherOrgId, otherPlayerId, "player");
  const result = await call(
    store,
    createBody({ player_ids: [playerId, otherPlayerId] }),
  );
  assertEqual(result.response.status, 400, "status");
  assertEqual(result.json.error, "active_player_membership_required", "error");
  assertEqual(store.records.size, 0, "no rows");
  assertEqual(store.batchCallCount, 0, "no transaction");
});

Deno.test("inactive player rejects the entire batch", async () => {
  const store = new FakeStore();
  store.setMembership(orgId, otherPlayerId, "player", "suspended");
  const result = await call(
    store,
    createBody({ player_ids: [playerId, otherPlayerId] }),
  );
  assertEqual(result.response.status, 400, "status");
  assertEqual(store.records.size, 0, "no partial rows");
});

Deno.test("platform support cannot select an inactive or cross-organization player", async () => {
  const store = new FakeStore();
  store.actorId = adminId;
  store.platformAdmins.add(adminId);
  store.setMembership(otherOrgId, otherPlayerId, "player");
  const crossOrg = await call(
    store,
    createBody({ player_ids: [playerId, otherPlayerId] }),
  );
  assertEqual(
    crossOrg.json.error,
    "active_player_membership_required",
    "cross-org error",
  );
  assertEqual(store.records.size, 0, "cross-org atomic rejection");

  store.setMembership(orgId, otherPlayerId, "player", "disabled");
  const inactive = await call(
    store,
    createBody({ player_ids: [playerId, otherPlayerId] }),
  );
  assertEqual(
    inactive.json.error,
    "active_player_membership_required",
    "inactive error",
  );
  assertEqual(store.records.size, 0, "inactive atomic rejection");
});

Deno.test("multi-player creation creates independent requests sharing one batch", async () => {
  const store = new FakeStore();
  store.setMembership(orgId, otherPlayerId, "player");
  const { response, json } = await call(
    store,
    createBody({ player_ids: [otherPlayerId, playerId] }),
  );
  const requests = jsonArray(json.requests, "requests");
  assertEqual(response.status, 201, "status");
  assertEqual(requests.length, 2, "one row per player");
  assertEqual(json.created_count, 2, "created count");
  assert(requests[0].id !== requests[1].id, "independent request IDs");
  assertEqual(
    requests[0].request_batch_id,
    requests[1].request_batch_id,
    "shared batch ID",
  );
  assert(
    requests[0].player_id !== requests[1].player_id,
    "independent players",
  );
});

Deno.test("same batch retry is reused without duplicates", async () => {
  const store = new FakeStore();
  const first = await call(store, createBody());
  const second = await call(store, createBody());
  assertEqual(first.response.status, 201, "first status");
  assertEqual(second.response.status, 200, "retry status");
  assertEqual(second.json.created_count, 0, "retry created count");
  assertEqual(second.json.reused, true, "reused marker");
  assertEqual(store.records.size, 1, "no duplicate rows");
});

Deno.test("same key with changed player set or amount fails closed", async () => {
  const store = new FakeStore();
  store.setMembership(orgId, otherPlayerId, "player");
  await call(store, createBody());
  const players = await call(
    store,
    createBody({ player_ids: [playerId, otherPlayerId] }),
  );
  assertEqual(players.response.status, 409, "player-set conflict");
  assertEqual(players.json.error, "idempotency_conflict", "player-set error");

  const amount = await call(store, createBody({ amount_cents: 54_321 }));
  assertEqual(amount.response.status, 409, "amount conflict");
  assertEqual(amount.json.error, "idempotency_conflict", "amount error");
  assertEqual(store.records.size, 1, "original only");
});

Deno.test("simulated batch failure leaves no partial rows", async () => {
  const store = new FakeStore();
  store.failBatchCreation = true;
  const result = await call(store, createBody());
  assertEqual(result.response.status, 500, "status");
  assertEqual(store.records.size, 0, "no partial rows");
  assertEqual(store.batches.size, 0, "no partial batch");
});

Deno.test("amount, currency, due date, and text validation remain server authoritative", async () => {
  for (const amount of [0, -1, 12.5, "100"]) {
    const result = await call(
      new FakeStore(),
      createBody({ amount_cents: amount }),
    );
    assertEqual(result.json.error, "invalid_amount", `amount ${amount}`);
  }
  assertEqual(
    (await call(
      new FakeStore(),
      createBody({ amount_cents: PAYMENT_REQUEST_MAX_AMOUNT_CENTS + 1 }),
    )).json.error,
    "amount_exceeds_limit",
    "upper bound",
  );
  assertEqual(
    (await call(new FakeStore(), createBody({ currency: "eur" }))).json.error,
    "unsupported_currency",
    "currency",
  );
  assertEqual(
    (await call(new FakeStore(), createBody({ due_date: "2026-02-30" }))).json
      .error,
    "invalid_due_date",
    "date",
  );
  assertEqual(
    (await call(new FakeStore(), createBody({ title: "x".repeat(121) }))).json
      .error,
    "invalid_title",
    "title",
  );
  assertEqual(
    (await call(new FakeStore(), createBody({ description: "x".repeat(1001) })))
      .json.error,
    "invalid_description",
    "description",
  );
});

for (const [role, actor] of [["owner", ownerId], ["admin", adminId]] as const) {
  Deno.test(`${role} can cancel one open request`, async () => {
    const store = new FakeStore();
    store.actorId = actor;
    store.setMembership(orgId, actor, role);
    store.addRecord("open");
    const { response, json } = await call(store, {
      action: "cancel",
      org_id: orgId,
      request_id: requestId,
    });
    assertEqual(response.status, 200, "status");
    const request = json.request as Record<string, unknown>;
    assertEqual(request.status, "canceled", "canceled state");
  });
}

Deno.test("platform support cancels an open request and audits it", async () => {
  const store = new FakeStore();
  store.actorId = adminId;
  store.platformAdmins.add(adminId);
  store.addRecord("open");
  const result = await call(store, {
    action: "cancel",
    org_id: orgId,
    request_id: requestId,
  });
  assertEqual(result.response.status, 200, "status");
  assertEqual(
    result.json.authorization_source,
    "platform_support",
    "authorization source",
  );
  assertEqual(
    (result.json.request as Record<string, unknown>).status,
    "canceled",
    "status transition",
  );
  assertEqual(store.auditRecords.length, 1, "audit count");
  assertEqual(
    store.auditRecords[0].action,
    "platform_payment_request_canceled",
    "audit action",
  );
  assertEqual(store.auditRecords[0].targetId, requestId, "audit request");
});

Deno.test("coach cannot cancel and terminal requests remain terminal", async () => {
  const coach = new FakeStore();
  coach.actorId = coachId;
  coach.setMembership(orgId, coachId, "coach");
  coach.addRecord("open");
  assertEqual(
    (await call(coach, {
      action: "cancel",
      org_id: orgId,
      request_id: requestId,
    })).response.status,
    403,
    "coach",
  );

  const canceled = new FakeStore();
  canceled.addRecord("canceled");
  assertEqual(
    (await call(canceled, {
      action: "cancel",
      org_id: orgId,
      request_id: requestId,
    })).json.error,
    "payment_request_already_canceled",
    "canceled",
  );

  const paid = new FakeStore();
  paid.addRecord("paid");
  assertEqual(
    (await call(paid, {
      action: "cancel",
      org_id: orgId,
      request_id: requestId,
    })).json.error,
    "paid_request_cannot_be_canceled",
    "paid",
  );
});

Deno.test("player and linked-parent reads retain organization-scoped pay permission", async () => {
  const player = new FakeStore();
  player.actorId = playerId;
  player.addRecord();
  const playerResult = await call(player, { action: "list", org_id: orgId });
  const playerRequests = jsonArray(
    playerResult.json.requests,
    "player requests",
  );
  assertEqual(playerRequests.length, 1, "player count");
  assertEqual(
    playerRequests[0].can_current_user_pay,
    true,
    "player permission",
  );

  const parent = new FakeStore();
  parent.actorId = parentId;
  parent.setMembership(orgId, parentId, "parent");
  parent.setLink(orgId, parentId, playerId, false);
  parent.addRecord();
  const parentResult = await call(parent, { action: "list", org_id: orgId });
  const parentRequests = jsonArray(
    parentResult.json.requests,
    "parent requests",
  );
  assertEqual(
    parentRequests[0].can_current_user_pay,
    false,
    "parent pay permission",
  );
});

Deno.test("player reads only own child_id requests when Swift sends an uppercase UUID", async () => {
  const player = new FakeStore();
  player.actorId = playerId;
  player.setMembership(orgId, otherPlayerId, "player");
  player.addRecord("open", playerId);
  player.addRecord("paid", otherPlayerId, generatedUuid(20_001));

  const result = await call(player, {
    action: "list",
    org_id: orgId,
    player_id: playerId.toUpperCase(),
  });
  const requests = jsonArray(result.json.requests, "player requests");
  assertEqual(result.response.status, 200, "status");
  assertEqual(requests.length, 1, "own-request count");
  assertEqual(requests[0].player_id, playerId, "authoritative child_id");
});

Deno.test("player cannot read another player's child_id request", async () => {
  const player = new FakeStore();
  player.actorId = playerId;
  player.setMembership(orgId, otherPlayerId, "player");
  player.addRecord("canceled", otherPlayerId);

  const listResult = await call(player, {
    action: "list",
    org_id: orgId,
    player_id: otherPlayerId.toUpperCase(),
  });
  assertEqual(listResult.response.status, 403, "list status");
  assertEqual(
    listResult.json.error,
    "payment_request_access_denied",
    "list denial",
  );

  const detailResult = await call(player, {
    action: "get_detail",
    org_id: orgId,
    request_id: requestId,
  });
  assertEqual(detailResult.response.status, 404, "detail status");
  assertEqual(
    detailResult.json.error,
    "payment_request_not_found",
    "detail does not disclose another player's request",
  );
});

Deno.test("owner and platform support use the management list with explicit sources", async () => {
  const owner = new FakeStore();
  owner.addRecord();
  const ownerResult = await call(owner, {
    action: "list_manage",
    org_id: orgId,
  });
  assertEqual(ownerResult.response.status, 200, "owner status");
  assertEqual(
    ownerResult.json.authorization_source,
    "organization_membership",
    "owner source",
  );

  const platform = new FakeStore();
  platform.actorId = adminId;
  platform.platformAdmins.add(adminId);
  platform.addRecord();
  const platformResult = await call(platform, {
    action: "list_manage",
    org_id: orgId,
  });
  assertEqual(platformResult.response.status, 200, "platform status");
  assertEqual(
    platformResult.json.authorization_source,
    "platform_support",
    "platform source",
  );
  assertEqual(
    jsonArray(platformResult.json.requests, "requests").length,
    1,
    "request count",
  );
});

for (
  const [role, actor] of [["coach", coachId], ["parent", parentId], [
    "player",
    playerId,
  ]] as const
) {
  Deno.test(`${role} cannot use the payment-request management list`, async () => {
    const store = new FakeStore();
    store.actorId = actor;
    store.setMembership(orgId, actor, role);
    store.addRecord();
    const result = await call(store, { action: "list_manage", org_id: orgId });
    assertEqual(result.response.status, 403, "status");
    assertEqual(result.json.error, "organization_admin_required", "error");
  });
}

Deno.test("unrelated parent cannot read requests", async () => {
  const store = new FakeStore();
  store.actorId = parentId;
  store.setMembership(orgId, parentId, "parent");
  store.addRecord();
  assertEqual(
    (await call(store, { action: "list", org_id: orgId })).response.status,
    403,
    "status",
  );
});

Deno.test("no client action can mark a request paid or set provider fields", async () => {
  const store = new FakeStore();
  store.addRecord();
  const status = await call(store, {
    action: "cancel",
    org_id: orgId,
    request_id: requestId,
    status: "paid",
  });
  assertEqual(status.json.error, "server_controlled_field", "status field");
  const action = await call(store, {
    action: "mark_paid",
    org_id: orgId,
    request_id: requestId,
  });
  assertEqual(action.json.error, "unsupported_action", "paid action");
  const provider = await call(store, {
    ...createBody(),
    checkout_session_id: "cs_test",
  });
  assertEqual(provider.json.error, "server_controlled_field", "provider field");
});

Deno.test("success responses contain no secrets or idempotency key", async () => {
  const encoded = JSON.stringify(
    (await call(new FakeStore(), createBody())).json,
  );
  for (
    const key of [
      "idempotency_key",
      "payer_id",
      "stripe_account_id",
      "checkout_session_id",
      "payment_intent_id",
      "provider_payment_status",
      "client_secret",
    ]
  ) {
    assert(!encoded.includes(key), `${key} must not be returned`);
  }
});

Deno.test("batch migration is atomic, hardened, and preserves legacy retries without rewriting rows", async () => {
  const migration = await Deno.readTextFile(
    new URL(
      "../../migrations/20260714190000_payment_request_batches.sql",
      import.meta.url,
    ),
  );
  const sql = migration.toLowerCase();
  assert(
    sql.includes(
      "create or replace function public.sd_create_payment_request_batch",
    ),
    "transactional RPC",
  );
  assert(
    sql.includes("security definer\nset search_path = ''"),
    "safe search path",
  );
  assert(sql.includes("to service_role"), "service role only");
  assert(
    sql.includes("from public, anon, authenticated"),
    "client execution revoked",
  );
  assert(
    sql.includes("request.request_batch_id is null"),
    "legacy retry lookup",
  );
  assert(sql.includes("'created_count', 0"), "legacy reuse response");
  assert(
    sql.includes("payment_request_idempotency_conflict"),
    "material mismatch fails closed",
  );
  assert(
    sql.includes("active_player_membership_required"),
    "all-player validation",
  );
  assert(sql.includes("request_batch_id"), "batch foreign key");
  assert(
    !sql.includes("update public.sd_payment_requests set request_batch_id"),
    "legacy requests not rewritten",
  );
});

Deno.test("platform-support migration verifies authority and audits mutations atomically", async () => {
  const migration = await Deno.readTextFile(
    new URL(
      "../../migrations/20260714200000_platform_payment_request_support.sql",
      import.meta.url,
    ),
  );
  const sql = migration.toLowerCase();
  assert(
    sql.includes("from public.sd_platform_admins platform_admin"),
    "authoritative platform grant lookup",
  );
  assert(
    sql.includes("from public.sd_org_memberships actor"),
    "organization membership remains first authority",
  );
  assert(
    sql.includes("v_authorization_source := 'organization_membership'"),
    "membership source",
  );
  assert(
    sql.includes("v_authorization_source := 'platform_support'"),
    "support source",
  );
  assert(
    sql.includes("platform_payment_request_batch_created"),
    "batch audit action",
  );
  assert(
    sql.includes("platform_payment_request_canceled"),
    "cancel audit action",
  );
  assert(
    sql.includes("insert into public.sd_platform_audit_logs"),
    "existing audit table reused",
  );
  assert(
    sql.includes("create or replace function public.sd_cancel_payment_request"),
    "transactional cancel RPC",
  );
  assert(
    sql.match(/security definer\nset search_path = ''/g)?.length === 2,
    "safe search paths",
  );
  assert(
    sql.includes("from public, anon, authenticated"),
    "client execution revoked",
  );
  assert(
    sql.match(/to service_role/g)?.length === 2,
    "service-role-only execution",
  );
  assert(
    !sql.includes("insert into public.sd_org_memberships"),
    "support creates no membership",
  );
});

Deno.test("production adapter verifies JWT, uses the batch RPC, and has no Stripe payment API call", async () => {
  const source = (await Deno.readTextFile(
    new URL("../payment_requests/index.ts", import.meta.url),
  )).toLowerCase();
  assert(
    source.includes("userclient.auth.getuser()"),
    "JWT actor verification",
  );
  assert(
    source.includes('.from("sd_platform_admins")'),
    "authoritative platform grant lookup",
  );
  assert(
    /rpc\(\s*"sd_create_payment_request_batch"/.test(source),
    "batch RPC",
  );
  assert(/rpc\(\s*"sd_cancel_payment_request"/.test(source), "cancel RPC");
  assert(
    !source.includes('.from("sd_payment_requests")\n        .insert'),
    "no best-effort direct inserts",
  );
  assert(
    !source.includes('.from("sd_payment_requests")\n        .update'),
    "no direct cancel update",
  );
  assert(
    !source.includes('.from("sd_org_memberships")\n        .insert'),
    "no support membership insert",
  );
  assert(!source.includes("api.stripe.com"), "no Stripe API host");
  assert(!source.includes("checkout.sessions"), "no Checkout Session creation");
  assert(!source.includes("payment_intents"), "no PaymentIntent creation");
});

Deno.test("payment support does not broaden Stripe Connect authorization", async () => {
  const source = (await Deno.readTextFile(
    new URL("./stripe_connect_supabase.ts", import.meta.url),
  )).toLowerCase();
  assert(
    source.includes('.from("sd_org_memberships")'),
    "Connect still checks organization membership",
  );
  assert(
    source.includes('role === "owner" || role === "admin"'),
    "Connect retains owner/admin policy",
  );
  assert(
    !source.includes("sd_platform_admins"),
    "Connect has no platform-support override",
  );
});
