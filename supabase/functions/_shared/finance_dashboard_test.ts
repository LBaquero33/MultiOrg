import {
  calculateFinanceOverview,
  createFinanceDashboardHandler,
  type FinanceDashboardStore,
  type FinanceExpenseInput,
  type FinanceExpenseRecord,
  type FinanceMembership,
  type FinancePaymentRecord,
  type FinancePaymentRequestRecord,
  type FinanceRefundRecord,
  resolveFinanceDateRange,
} from "./finance_dashboard.ts";

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
const now = new Date("2026-07-14T16:30:00.000Z");

function payment(
  id: string,
  amount: number,
  status: string,
  providerFee = 0,
  platformFee = 0,
): FinancePaymentRecord {
  return {
    id,
    org_id: orgId,
    payment_request_id: "aaaaaaaa-aaaa-4aaa-8aaa-000000000001",
    player_id: playerId,
    payer_id: parentId,
    amount_cents: amount,
    processing_fee_cents: providerFee,
    platform_fee_cents: platformFee,
    net_to_organization_cents: amount - providerFee - platformFee,
    currency: "usd",
    status,
    provider: "stripe",
    paid_at: status === "failed" ? null : "2026-07-10T12:00:00.000Z",
    created_at: "2026-07-10T12:00:00.000Z",
  };
}

function paymentRequest(
  id: string,
  amount: number,
  status: FinancePaymentRequestRecord["status"],
  dueDate: string | null,
): FinancePaymentRequestRecord {
  return {
    id,
    request_batch_id: null,
    org_id: orgId,
    child_id: playerId,
    title: `Request ${id.slice(-2)}`,
    amount_cents: amount,
    currency: "usd",
    status,
    due_date: dueDate,
    paid_at: status === "paid" ? "2026-07-11T12:00:00.000Z" : null,
    created_at: "2026-07-05T12:00:00.000Z",
  };
}

class FakeFinanceStore implements FinanceDashboardStore {
  actorId: string | null = ownerId;
  organizations = new Map([[orgId, "active"], [otherOrgId, "active"]]);
  memberships = new Map<string, FinanceMembership>();
  platformAdmins = new Set<string>();
  paymentRows: FinancePaymentRecord[] = [];
  requestRows: FinancePaymentRequestRecord[] = [];
  expenseRows: FinanceExpenseRecord[] = [];
  refundRows: FinanceRefundRecord[] = [];

  constructor() {
    this.setMembership(orgId, ownerId, "owner");
  }

  setMembership(org: string, user: string, role: string, status = "active") {
    this.memberships.set(`${org}:${user}`, { role, status });
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
  async defaultCurrency(_org: string) {
    return "usd";
  }
  async payments(_org: string, _start: string, _end: string) {
    return this.paymentRows;
  }
  async paymentRequests(_org: string, _start: string, _end: string) {
    return this.requestRows;
  }
  async expenses(_org: string, _start: string, _end: string) {
    return this.expenseRows;
  }
  async refunds(_org: string, _start: string, _end: string) {
    return this.refundRows;
  }
  async createExpense(
    _org: string,
    _actor: string,
    _input: FinanceExpenseInput,
  ): Promise<FinanceExpenseRecord> {
    throw new Error("not used by Phase 8A tests");
  }
  async updateExpense(
    _org: string,
    _actor: string,
    _expense: string,
    _input: FinanceExpenseInput,
  ): Promise<FinanceExpenseRecord> {
    throw new Error("not used by Phase 8A tests");
  }
  async archiveExpense(
    _org: string,
    _actor: string,
    _expense: string,
  ): Promise<FinanceExpenseRecord> {
    throw new Error("not used by Phase 8A tests");
  }
}

async function call(
  store: FakeFinanceStore,
  body: Record<string, unknown>,
  includeJWT = true,
) {
  const request = new Request("http://localhost/finance-dashboard", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      ...(includeJWT ? { Authorization: "Bearer verified-test-jwt" } : {}),
    },
    body: JSON.stringify(body),
  });
  const response = await createFinanceDashboardHandler(store, () => now)(
    request,
  );
  return {
    response,
    json: await response.json() as Record<string, unknown>,
  };
}

function overviewBody(overrides: Record<string, unknown> = {}) {
  return {
    action: "overview",
    org_id: orgId,
    range: "this_month",
    ...overrides,
  };
}

function populatedStore() {
  const store = new FakeFinanceStore();
  store.paymentRows = [
    payment(
      "aaaaaaaa-aaaa-4aaa-8aaa-000000000101",
      10_000,
      "succeeded",
      300,
      100,
    ),
    payment("aaaaaaaa-aaaa-4aaa-8aaa-000000000102", 5_000, "paid", 150, 50),
    payment("aaaaaaaa-aaaa-4aaa-8aaa-000000000103", 9_000, "failed", 250, 90),
  ];
  store.requestRows = [
    paymentRequest(
      "aaaaaaaa-aaaa-4aaa-8aaa-000000000201",
      7_000,
      "open",
      "2026-07-13",
    ),
    paymentRequest(
      "aaaaaaaa-aaaa-4aaa-8aaa-000000000202",
      3_000,
      "open",
      "2026-07-20",
    ),
    paymentRequest(
      "aaaaaaaa-aaaa-4aaa-8aaa-000000000203",
      5_000,
      "paid",
      "2026-07-12",
    ),
    paymentRequest(
      "aaaaaaaa-aaaa-4aaa-8aaa-000000000204",
      2_500,
      "canceled",
      null,
    ),
  ];
  store.expenseRows = [{
    id: "aaaaaaaa-aaaa-4aaa-8aaa-000000000301",
    org_id: orgId,
    category: "facilities",
    description: "Cage rental",
    amount_cents: 1_000,
    currency: "usd",
    expense_date: "2026-07-08",
    vendor: "Marist",
    notes: "July session",
    created_at: "2026-07-08T12:00:00.000Z",
    updated_at: "2026-07-08T12:00:00.000Z",
    archived_at: null,
    archived_by: null,
  }];
  store.refundRows = [{
    id: "aaaaaaaa-aaaa-4aaa-8aaa-000000000401",
    org_id: orgId,
    payment_id: store.paymentRows[0].id,
    amount_cents: 2_000,
    currency: "usd",
    status: "succeeded",
    reason: "requested_by_customer",
    created_at: "2026-07-12T12:00:00.000Z",
  }, {
    id: "aaaaaaaa-aaaa-4aaa-8aaa-000000000402",
    org_id: orgId,
    payment_id: store.paymentRows[1].id,
    amount_cents: 500,
    currency: "usd",
    status: "pending",
    reason: null,
    created_at: "2026-07-13T12:00:00.000Z",
  }];
  return store;
}

Deno.test("finance dashboard requires a verified JWT", async () => {
  const result = await call(new FakeFinanceStore(), overviewBody(), false);
  assertEqual(result.response.status, 401, "status");
  assertEqual(result.json.error, "invalid_auth", "error");
});

for (const [role, actor] of [["owner", ownerId], ["admin", adminId]] as const) {
  Deno.test(`active organization ${role} can load finance overview`, async () => {
    const store = new FakeFinanceStore();
    store.actorId = actor;
    store.setMembership(orgId, actor, role);
    const result = await call(store, overviewBody());
    assertEqual(result.response.status, 200, "status");
    assertEqual(
      result.json.authorization_source,
      "organization_membership",
      "source",
    );
  });
}

Deno.test("platform admin requires explicit support mode and creates no membership", async () => {
  const store = new FakeFinanceStore();
  store.actorId = adminId;
  store.platformAdmins.add(adminId);
  const membershipCount = store.memberships.size;
  assertEqual(
    (await call(store, overviewBody())).response.status,
    403,
    "implicit denial",
  );
  const result = await call(store, overviewBody({ support_mode: true }));
  assertEqual(result.response.status, 200, "explicit status");
  assertEqual(result.json.authorization_source, "platform_support", "source");
  assertEqual(store.memberships.size, membershipCount, "membership count");
  assert(
    !store.memberships.has(`${orgId}:${adminId}`),
    "no support membership",
  );
});

for (
  const [role, actor] of [["coach", coachId], ["parent", parentId], [
    "player",
    playerId,
  ]] as const
) {
  Deno.test(`${role} cannot view organization finance`, async () => {
    const store = new FakeFinanceStore();
    store.actorId = actor;
    store.setMembership(orgId, actor, role);
    const result = await call(store, overviewBody());
    assertEqual(result.response.status, 403, "status");
  });
}

Deno.test("cross-organization owner membership cannot view selected organization finance", async () => {
  const store = new FakeFinanceStore();
  store.actorId = adminId;
  store.setMembership(otherOrgId, adminId, "owner");
  const result = await call(store, overviewBody());
  assertEqual(result.response.status, 403, "status");
});

Deno.test("overview uses succeeded payments and subtracts refunds, fees, and expenses in cents", async () => {
  const result = await call(populatedStore(), overviewBody());
  const overview = result.json.overview as Record<string, unknown>;
  assertEqual(overview.gross_revenue_cents, 15_000, "gross");
  assertEqual(overview.successful_payment_count, 2, "successful count");
  assertEqual(overview.refunds_cents, 2_000, "completed refunds only");
  assertEqual(overview.provider_fees_cents, 450, "provider fees");
  assertEqual(overview.platform_fees_cents, 150, "platform fees");
  assertEqual(overview.net_payment_revenue_cents, 12_400, "net revenue");
  assertEqual(overview.expenses_cents, 1_000, "expenses");
  assertEqual(overview.estimated_profit_cents, 11_400, "estimated profit");
  assertEqual(overview.average_payment_cents, 7_500, "average");
});

Deno.test("outstanding and overdue balances use open requests only", async () => {
  const result = await call(populatedStore(), overviewBody());
  const overview = result.json.overview as Record<string, unknown>;
  assertEqual(overview.open_request_balance_cents, 10_000, "open balance");
  assertEqual(overview.overdue_request_balance_cents, 7_000, "overdue balance");
  assertEqual(overview.open_request_count, 2, "open count");
  assertEqual(overview.paid_request_count, 1, "paid count");
  assertEqual(overview.canceled_request_count, 1, "canceled count");
});

Deno.test("zero successful payments produce a safe zero average", async () => {
  const store = populatedStore();
  store.paymentRows = [
    payment("aaaaaaaa-aaaa-4aaa-8aaa-000000000501", 9_000, "failed"),
  ];
  const result = await call(store, overviewBody());
  const overview = result.json.overview as Record<string, unknown>;
  assertEqual(overview.gross_revenue_cents, 0, "gross");
  assertEqual(overview.average_payment_cents, 0, "average");
});

Deno.test("payment-request filters preserve only the requested organization records", async () => {
  const store = populatedStore();
  const overdue = await call(store, {
    action: "payment_requests",
    org_id: orgId,
    range: "this_month",
    filter: "overdue",
  });
  const rows = overdue.json.requests as Record<string, unknown>[];
  assertEqual(rows.length, 1, "overdue count");
  assertEqual(rows[0].status, "open", "status");
  assertEqual(rows[0].due_date, "2026-07-13", "due date");
});

Deno.test("recent payments include successful records only and no provider secrets", async () => {
  const result = await call(populatedStore(), {
    action: "recent_payments",
    org_id: orgId,
    range: "this_month",
  });
  const rows = result.json.payments as Record<string, unknown>[];
  assertEqual(rows.length, 2, "successful rows");
  const serialized = JSON.stringify(rows);
  assert(
    !serialized.includes("provider_payment_intent_id"),
    "no payment intent",
  );
  assert(!serialized.includes("provider_charge_id"), "no charge ID");
  assert(
    !serialized.includes("connected_account_id"),
    "no connected account ID",
  );
});

Deno.test("expense and refund actions are read-only typed lists", async () => {
  const store = populatedStore();
  const expenses = await call(store, {
    action: "expenses",
    org_id: orgId,
    range: "this_month",
  });
  const refunds = await call(store, {
    action: "refunds",
    org_id: orgId,
    range: "this_month",
  });
  assertEqual((expenses.json.expenses as unknown[]).length, 1, "expense count");
  assertEqual((refunds.json.refunds as unknown[]).length, 2, "refund count");
});

Deno.test("week, month, quarter, year, and inclusive custom UTC boundaries are exact", () => {
  const expected: Record<string, [string, string]> = {
    this_week: ["2026-07-13", "2026-07-19"],
    this_month: ["2026-07-01", "2026-07-31"],
    this_quarter: ["2026-07-01", "2026-09-30"],
    this_year: ["2026-01-01", "2026-12-31"],
  };
  for (const [range, dates] of Object.entries(expected)) {
    const resolved = resolveFinanceDateRange({ range }, now);
    assertEqual(resolved?.start_date, dates[0], `${range} start`);
    assertEqual(resolved?.end_date, dates[1], `${range} end`);
    assertEqual(resolved?.timezone_source, "utc_fallback", `${range} timezone`);
  }
  const custom = resolveFinanceDateRange({
    range: "custom",
    start_date: "2026-06-10",
    end_date: "2026-06-12",
  }, now);
  assertEqual(custom?.start, "2026-06-10T00:00:00.000Z", "custom start");
  assertEqual(custom?.end, "2026-06-13T00:00:00.000Z", "custom exclusive end");
});

Deno.test("overview calculator uses integer arithmetic", () => {
  const range = resolveFinanceDateRange({ range: "this_month" }, now)!;
  const value = calculateFinanceOverview(
    range,
    "usd",
    [payment("aaaaaaaa-aaaa-4aaa-8aaa-000000000601", 100, "succeeded")],
    [],
    [],
    [],
    "2026-07-14",
  );
  assertEqual(value.average_payment_cents, 100, "integer average");
  assert(Number.isInteger(value.estimated_profit_cents), "integer profit");
});

Deno.test("client-supplied roles, platform flags, and totals are rejected", async () => {
  for (const field of ["role", "is_platform_admin", "gross_revenue_cents"]) {
    const result = await call(
      new FakeFinanceStore(),
      overviewBody({ [field]: true }),
    );
    assertEqual(result.response.status, 400, field);
    assertEqual(result.json.error, "server_controlled_field", `${field} error`);
  }
});

Deno.test("production finance adapter is JWT verified, service-read-only, and has no Stripe API call", async () => {
  const source = await Deno.readTextFile(
    new URL("../finance-dashboard/index.ts", import.meta.url),
  );
  const config = await Deno.readTextFile(
    new URL("../../config.toml", import.meta.url),
  );
  assert(
    source.includes("userClient.auth.getUser()"),
    "JWT actor verification",
  );
  assert(
    source.includes('.from("sd_org_memberships")'),
    "membership authorization",
  );
  assert(
    source.includes('.from("sd_platform_admins")'),
    "platform support authorization",
  );
  assert(source.includes('.from("sd_payments")'), "payment reads");
  assert(
    source.includes("paid_at.gte.${start}") &&
      source.includes("paid_at.lt.${end}") &&
      source.includes("paid_at.is.null,created_at.gte.${start}"),
    "payment range uses paid_at with a legacy created_at fallback",
  );
  assert(source.includes('.from("sd_payment_requests")'), "request reads");
  assert(source.includes('.from("sd_expenses")'), "expense reads");
  assert(source.includes('.from("sd_refunds")'), "refund reads");
  assert(!source.includes(".insert("), "no insert");
  assert(!source.includes(".update("), "no update");
  assert(!source.includes(".delete("), "no delete");
  assert(!source.includes("api.stripe.com"), "no Stripe API");
  assert(
    config.includes("[functions.finance-dashboard]\nverify_jwt = true"),
    "verify_jwt configuration",
  );
});
