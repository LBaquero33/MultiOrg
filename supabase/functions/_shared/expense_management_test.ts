import {
  createFinanceDashboardHandler,
  type FinanceDashboardStore,
  FinanceDashboardStoreError,
  type FinanceExpenseInput,
  type FinanceExpenseRecord,
  type FinanceMembership,
  type FinancePaymentRecord,
  type FinancePaymentRequestRecord,
  type FinanceRefundRecord,
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
const platformId = "66666666-6666-4666-8666-666666666666";
const expenseId = "aaaaaaaa-aaaa-4aaa-8aaa-000000000301";
const otherExpenseId = "bbbbbbbb-bbbb-4bbb-8bbb-000000000301";
const now = new Date("2026-07-15T12:00:00.000Z");

function expense(
  id = expenseId,
  organization = orgId,
  amount = 1_500,
): FinanceExpenseRecord {
  return {
    id,
    org_id: organization,
    category: "Facilities",
    description: "Cage rental",
    amount_cents: amount,
    currency: "usd",
    expense_date: "2026-07-14",
    vendor: "Marist",
    notes: null,
    created_at: "2026-07-14T10:00:00.000Z",
    updated_at: "2026-07-14T10:00:00.000Z",
    archived_at: null,
    archived_by: null,
  };
}

class ExpenseStore implements FinanceDashboardStore {
  actorId: string | null = ownerId;
  organizations = new Map([[orgId, "active"], [otherOrgId, "active"]]);
  memberships = new Map<string, FinanceMembership>();
  platformAdmins = new Set([platformId]);
  expenseRows = [expense(), expense(otherExpenseId, otherOrgId, 2_000)];
  audits: Array<{ action: string; actor: string; expense: string }> = [];
  nextId = "aaaaaaaa-aaaa-4aaa-8aaa-000000000399";

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
    return "USD";
  }
  async payments(_org: string, _start: string, _end: string) {
    return [] as FinancePaymentRecord[];
  }
  async paymentRequests(_org: string, _start: string, _end: string) {
    return [] as FinancePaymentRequestRecord[];
  }
  async expenses(org: string, start: string, end: string) {
    return this.expenseRows.filter((row) =>
      row.org_id === org && row.archived_at === null &&
      row.expense_date >= start && row.expense_date <= end
    );
  }
  async refunds(_org: string, _start: string, _end: string) {
    return [] as FinanceRefundRecord[];
  }
  async createExpense(org: string, actor: string, input: FinanceExpenseInput) {
    const row: FinanceExpenseRecord = {
      id: this.nextId,
      org_id: org,
      ...input,
      created_at: now.toISOString(),
      updated_at: now.toISOString(),
      archived_at: null,
      archived_by: null,
    };
    this.expenseRows.push(row);
    this.audits.push({ action: "expense_created", actor, expense: row.id });
    return row;
  }
  async updateExpense(
    org: string,
    actor: string,
    id: string,
    input: FinanceExpenseInput,
  ) {
    const index = this.expenseRows.findIndex((row) =>
      row.org_id === org && row.id === id
    );
    if (index < 0) throw new FinanceDashboardStoreError("expense_not_found");
    if (this.expenseRows[index].archived_at !== null) {
      throw new FinanceDashboardStoreError("expense_archived");
    }
    const row = {
      ...this.expenseRows[index],
      ...input,
      updated_at: now.toISOString(),
    };
    this.expenseRows[index] = row;
    this.audits.push({ action: "expense_updated", actor, expense: id });
    return row;
  }
  async archiveExpense(org: string, actor: string, id: string) {
    const index = this.expenseRows.findIndex((row) =>
      row.org_id === org && row.id === id
    );
    if (index < 0) throw new FinanceDashboardStoreError("expense_not_found");
    if (this.expenseRows[index].archived_at !== null) {
      throw new FinanceDashboardStoreError("expense_already_archived");
    }
    const row = {
      ...this.expenseRows[index],
      archived_at: now.toISOString(),
      archived_by: actor,
      updated_at: now.toISOString(),
    };
    this.expenseRows[index] = row;
    this.audits.push({ action: "expense_archived", actor, expense: id });
    return row;
  }
}

function mutationBody(action: string, overrides: Record<string, unknown> = {}) {
  return {
    action,
    org_id: orgId,
    expense_id: expenseId,
    category: "Equipment",
    description: "Baseballs",
    amount_cents: 2_500,
    currency: "USD",
    expense_date: "2026-07-15",
    vendor: "Diamond Sports",
    notes: "Practice inventory",
    support_mode: false,
    ...overrides,
  };
}

function readBody(action: "expenses" | "overview", supportMode = false) {
  return {
    action,
    org_id: orgId,
    range: "this_month",
    support_mode: supportMode,
  };
}

async function call(store: ExpenseStore, body: Record<string, unknown>) {
  const response = await createFinanceDashboardHandler(store, () => now)(
    new Request("http://localhost/finance-dashboard", {
      method: "POST",
      headers: {
        Authorization: "Bearer verified-test-jwt",
        "content-type": "application/json",
      },
      body: JSON.stringify(body),
    }),
  );
  return {
    response,
    json: await response.json() as Record<string, unknown>,
  };
}

for (const [role, actor] of [["owner", ownerId], ["admin", adminId]] as const) {
  Deno.test(`active ${role} can create an expense`, async () => {
    const store = new ExpenseStore();
    store.actorId = actor;
    store.setMembership(orgId, actor, role);
    const result = await call(store, mutationBody("create_expense"));
    assertEqual(result.response.status, 200, "status");
    const created = result.json.expense as Record<string, unknown>;
    assertEqual(created.org_id, orgId, "organization");
    assertEqual(created.amount_cents, 2_500, "integer cents");
    assertEqual(created.currency, "usd", "normalized currency");
    assertEqual(store.audits[0].action, "expense_created", "audit action");
    assertEqual(store.audits[0].actor, actor, "JWT actor");
  });

  Deno.test(`active ${role} can update an organization expense`, async () => {
    const store = new ExpenseStore();
    store.actorId = actor;
    store.setMembership(orgId, actor, role);
    const result = await call(store, mutationBody("update_expense"));
    assertEqual(result.response.status, 200, "status");
    const updated = result.json.expense as Record<string, unknown>;
    assertEqual(updated.description, "Baseballs", "description");
    assertEqual(store.audits[0].action, "expense_updated", "audit action");
  });

  Deno.test(`active ${role} can archive an organization expense`, async () => {
    const store = new ExpenseStore();
    store.actorId = actor;
    store.setMembership(orgId, actor, role);
    const result = await call(store, mutationBody("archive_expense"));
    assertEqual(result.response.status, 200, "status");
    const archived = result.json.expense as Record<string, unknown>;
    assertEqual(archived.archived_by, actor, "archived actor");
    assertEqual(store.audits[0].action, "expense_archived", "audit action");
  });
}

Deno.test("platform support can read but cannot mutate expenses", async () => {
  const store = new ExpenseStore();
  store.actorId = platformId;
  const read = await call(store, readBody("expenses", true));
  assertEqual(read.response.status, 200, "support read");
  assertEqual(read.json.authorization_source, "platform_support", "source");
  const create = await call(
    store,
    mutationBody("create_expense", { support_mode: true }),
  );
  assertEqual(create.response.status, 403, "support mutation");
  assertEqual(create.json.error, "expense_mutation_denied", "error");
  assertEqual(store.audits.length, 0, "no mutation audit");
});

for (
  const [role, actor] of [
    ["coach", coachId],
    ["parent", parentId],
    ["player", playerId],
  ] as const
) {
  Deno.test(`${role} cannot create expenses`, async () => {
    const store = new ExpenseStore();
    store.actorId = actor;
    store.setMembership(orgId, actor, role);
    const result = await call(store, mutationBody("create_expense"));
    assertEqual(result.response.status, 403, "status");
    assertEqual(store.audits.length, 0, "no audit");
  });
}

Deno.test("inactive owner and admin cannot mutate expenses", async () => {
  for (const [role, actor] of [["owner", ownerId], ["admin", adminId]]) {
    const store = new ExpenseStore();
    store.actorId = actor;
    store.setMembership(orgId, actor, role, "disabled");
    const result = await call(store, mutationBody("create_expense"));
    assertEqual(result.response.status, 403, `${role} status`);
  }
});

Deno.test("cross-organization membership cannot mutate selected organization", async () => {
  const store = new ExpenseStore();
  store.actorId = adminId;
  store.setMembership(otherOrgId, adminId, "admin");
  const result = await call(store, mutationBody("create_expense"));
  assertEqual(result.response.status, 403, "status");
});

Deno.test("another organization's expense cannot be updated or archived", async () => {
  for (const action of ["update_expense", "archive_expense"]) {
    const store = new ExpenseStore();
    const result = await call(
      store,
      mutationBody(action, { expense_id: otherExpenseId }),
    );
    assertEqual(result.response.status, 404, action);
    assertEqual(result.json.error, "expense_not_found", `${action} error`);
  }
});

Deno.test("expense amount, category, description, vendor, and notes are validated", async () => {
  const cases: Array<[Record<string, unknown>, string]> = [
    [{ amount_cents: 0 }, "invalid_expense_amount"],
    [{ amount_cents: -1 }, "invalid_expense_amount"],
    [{ amount_cents: 1.5 }, "invalid_expense_amount"],
    [{ amount_cents: 10_000_001 }, "expense_amount_exceeds_limit"],
    [{ category: " " }, "invalid_expense_category"],
    [{ description: " " }, "invalid_expense_description"],
    [{ vendor: "v".repeat(121) }, "invalid_expense_vendor"],
    [{ notes: "n".repeat(2_001) }, "invalid_expense_notes"],
    [{ expense_date: "2026-02-30" }, "invalid_expense_date"],
  ];
  for (const [override, expected] of cases) {
    const store = new ExpenseStore();
    const result = await call(
      store,
      mutationBody("create_expense", override),
    );
    assertEqual(result.response.status, 400, expected);
    assertEqual(result.json.error, expected, `${expected} code`);
  }
});

Deno.test("currency is normalized and must match the organization currency", async () => {
  const store = new ExpenseStore();
  const valid = await call(store, mutationBody("create_expense"));
  assertEqual(valid.response.status, 200, "uppercase USD");
  const invalid = await call(
    new ExpenseStore(),
    mutationBody("create_expense", { currency: "US" }),
  );
  assertEqual(invalid.json.error, "invalid_expense_currency", "format");
  const mismatch = await call(
    new ExpenseStore(),
    mutationBody("create_expense", { currency: "eur" }),
  );
  assertEqual(mismatch.response.status, 409, "mismatch status");
  assertEqual(mismatch.json.error, "expense_currency_mismatch", "mismatch");
});

Deno.test("archived expenses are excluded from active lists and totals", async () => {
  const store = new ExpenseStore();
  const archive = await call(store, mutationBody("archive_expense"));
  assertEqual(archive.response.status, 200, "archive");
  const list = await call(store, readBody("expenses"));
  const expenses = list.json.expenses as unknown[];
  assertEqual(expenses.length, 0, "active list");
  const overview = await call(store, readBody("overview"));
  const metrics = overview.json.overview as Record<string, unknown>;
  assertEqual(metrics.expenses_cents, 0, "expense total");
  assertEqual(metrics.estimated_profit_cents, 0, "profit");
});

Deno.test("archived expenses cannot be edited or archived twice", async () => {
  const store = new ExpenseStore();
  await call(store, mutationBody("archive_expense"));
  const update = await call(store, mutationBody("update_expense"));
  assertEqual(update.response.status, 409, "update status");
  assertEqual(update.json.error, "expense_archived", "update error");
  const archive = await call(store, mutationBody("archive_expense"));
  assertEqual(archive.response.status, 409, "archive status");
  assertEqual(archive.json.error, "expense_already_archived", "archive error");
});

Deno.test("expense migration is additive, atomic, audited, and service-role-only", async () => {
  const sql = await Deno.readTextFile(
    new URL(
      "../../migrations/20260715010000_expense_management.sql",
      import.meta.url,
    ),
  );
  assert(sql.includes("add column if not exists archived_at"), "archive time");
  assert(sql.includes("add column if not exists archived_by"), "archive actor");
  assert(
    sql.includes('drop policy if exists "sd_expenses_write_staff"'),
    "old writes removed",
  );
  assert(
    sql.includes('create policy "sd_expenses_select_owner_admin"'),
    "owner/admin reads",
  );
  assert(
    sql.includes("public.sd_is_org_admin(org_id)"),
    "active owner/admin helper",
  );
  assertEqual(
    sql.match(/security definer/g)?.length,
    3,
    "security definer count",
  );
  assertEqual(sql.match(/set search_path = ''/g)?.length, 3, "safe paths");
  assert(sql.includes("expense_created"), "create audit");
  assert(sql.includes("expense_updated"), "update audit");
  assert(sql.includes("expense_archived"), "archive audit");
  assert(
    sql.includes("insert into public.sd_platform_audit_logs"),
    "audit table",
  );
  assert(sql.includes("changed_fields"), "minimal changed-field audit");
  assert(!sql.includes("delete from public.sd_expenses"), "no hard delete");
  assert(
    sql.match(/from public, anon, authenticated/g)?.length === 3,
    "public execution revoked",
  );
  assertEqual(
    sql.match(/to service_role/g)?.length,
    3,
    "service-role grants",
  );
});

Deno.test("production expense adapter uses RPCs, excludes archives, and has no Stripe API", async () => {
  const source = await Deno.readTextFile(
    new URL("../finance-dashboard/index.ts", import.meta.url),
  );
  assert(source.includes('"sd_create_expense"'), "create RPC");
  assert(source.includes('"sd_update_expense"'), "update RPC");
  assert(source.includes('"sd_archive_expense"'), "archive RPC");
  assert(source.includes('.is("archived_at", null)'), "active filter");
  assert(!source.includes("api.stripe.com"), "no Stripe API");
  assert(!source.includes('.from("sd_expenses").delete'), "no hard delete");
});
