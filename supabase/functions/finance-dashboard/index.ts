import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import {
  createFinanceDashboardHandler,
  type FinanceDashboardStore,
  FinanceDashboardStoreError,
  type FinanceErrorResponse,
  type FinanceExpenseInput,
  type FinanceExpenseRecord,
  type FinancePaymentRecord,
  type FinancePaymentRequestRecord,
  type FinanceRefundRecord,
} from "../_shared/finance_dashboard.ts";

const env = (name: string) => (Deno.env.get(name) ?? "").trim();
const url = env("SUPABASE_URL") || env("DHD_SUPABASE_URL");
const anonKey = env("SUPABASE_ANON_KEY") || env("DHD_SUPABASE_ANON_KEY");
const serviceKey = env("DHD_SERVICE_ROLE_KEY") ||
  env("SUPABASE_SERVICE_ROLE_KEY");

function configurationError(): Response {
  const body: FinanceErrorResponse = {
    error: "missing_configuration",
    message: "Finance data is not configured.",
  };
  return new Response(JSON.stringify(body), {
    status: 500,
    headers: { "content-type": "application/json" },
  });
}

type PaymentRow = {
  id: string;
  org_id: string;
  invoice_id: string | null;
  payment_request_id: string | null;
  payer_id: string | null;
  provider: string;
  amount_cents: number;
  currency: string;
  status: string;
  processing_fee_cents: number | null;
  platform_fee_cents: number | null;
  net_to_organization_cents: number | null;
  paid_at: string | null;
  created_at: string;
};

type ChildRelationRow = { id: string; child_id: string | null };

type JsonObject = Record<string, unknown>;

function isObject(value: unknown): value is JsonObject {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function nullableString(value: unknown): string | null | undefined {
  return value === null ? null : typeof value === "string" ? value : undefined;
}

function decodeExpenseMutation(value: unknown): FinanceExpenseRecord {
  if (!isObject(value) || !isObject(value.expense)) {
    throw new FinanceDashboardStoreError("expense_mutation_failed");
  }
  const expense = value.expense;
  const requiredStrings = [
    "id",
    "org_id",
    "currency",
    "expense_date",
    "created_at",
    "updated_at",
  ] as const;
  if (
    requiredStrings.some((key) => typeof expense[key] !== "string") ||
    !Number.isSafeInteger(expense.amount_cents)
  ) {
    throw new FinanceDashboardStoreError("expense_mutation_failed");
  }
  const category = nullableString(expense.category);
  const description = nullableString(expense.description);
  const vendor = nullableString(expense.vendor);
  const notes = nullableString(expense.notes);
  const archivedAt = nullableString(expense.archived_at);
  const archivedBy = nullableString(expense.archived_by);
  if (
    category === undefined || description === undefined ||
    vendor === undefined || notes === undefined ||
    archivedAt === undefined || archivedBy === undefined
  ) {
    throw new FinanceDashboardStoreError("expense_mutation_failed");
  }
  return {
    id: expense.id as string,
    org_id: expense.org_id as string,
    category,
    description,
    amount_cents: expense.amount_cents as number,
    currency: expense.currency as string,
    expense_date: expense.expense_date as string,
    vendor,
    notes,
    created_at: expense.created_at as string,
    updated_at: expense.updated_at as string,
    archived_at: archivedAt,
    archived_by: archivedBy,
  };
}

function expenseStoreError(message: string): FinanceDashboardStoreError {
  for (
    const code of [
      "expense_not_found",
      "expense_already_archived",
      "expense_archived",
      "organization_admin_required",
      "organization_inactive_or_missing",
    ]
  ) {
    if (message.includes(code)) return new FinanceDashboardStoreError(code);
  }
  return new FinanceDashboardStoreError("expense_mutation_failed");
}

function makeStore(): FinanceDashboardStore {
  const admin = createClient(url, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const loadPaymentChildren = async (rows: PaymentRow[]) => {
    const requestIds = Array.from(
      new Set(
        rows.map((row) => row.payment_request_id).filter((id): id is string =>
          id !== null
        ),
      ),
    );
    const invoiceIds = Array.from(
      new Set(
        rows.map((row) => row.invoice_id).filter((id): id is string =>
          id !== null
        ),
      ),
    );
    const [requestResult, invoiceResult] = await Promise.all([
      requestIds.length === 0
        ? Promise.resolve({ data: [] as ChildRelationRow[], error: null })
        : admin.from("sd_payment_requests").select("id,child_id").in(
          "id",
          requestIds,
        ),
      invoiceIds.length === 0
        ? Promise.resolve({ data: [] as ChildRelationRow[], error: null })
        : admin.from("sd_invoices").select("id,child_id").in("id", invoiceIds),
    ]);
    if (requestResult.error || invoiceResult.error) {
      throw new Error("payment_child_lookup_failed");
    }
    const requestChildren = new Map(
      ((requestResult.data ?? []) as ChildRelationRow[]).map((
        row,
      ) => [row.id, row.child_id]),
    );
    const invoiceChildren = new Map(
      ((invoiceResult.data ?? []) as ChildRelationRow[]).map((
        row,
      ) => [row.id, row.child_id]),
    );
    return { requestChildren, invoiceChildren };
  };

  const mutateExpense = async (
    functionName:
      | "sd_create_expense"
      | "sd_update_expense"
      | "sd_archive_expense",
    parameters: JsonObject,
  ): Promise<FinanceExpenseRecord> => {
    const { data, error } = await admin.rpc(functionName, parameters);
    if (error) throw expenseStoreError(error.message);
    return decodeExpenseMutation(data);
  };

  const expenseParameters = (
    orgId: string,
    actorId: string,
    input: FinanceExpenseInput,
  ): JsonObject => ({
    p_org_id: orgId,
    p_actor_id: actorId,
    p_category: input.category,
    p_description: input.description,
    p_amount_cents: input.amount_cents,
    p_currency: input.currency,
    p_expense_date: input.expense_date,
    p_vendor: input.vendor,
    p_notes: input.notes,
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

    async organizationStatus(orgId) {
      const { data, error } = await admin
        .from("sd_orgs")
        .select("status")
        .eq("id", orgId)
        .maybeSingle();
      if (error) throw new Error("organization_lookup_failed");
      return data?.status ?? null;
    },

    async membership(orgId, userId) {
      const { data, error } = await admin
        .from("sd_org_memberships")
        .select("role,status")
        .eq("org_id", orgId)
        .eq("user_id", userId)
        .maybeSingle();
      if (error) throw new Error("membership_lookup_failed");
      return data ?? null;
    },

    async isPlatformAdmin(userId) {
      const { data, error } = await admin
        .from("sd_platform_admins")
        .select("user_id")
        .eq("user_id", userId)
        .maybeSingle();
      if (error) throw new Error("platform_admin_lookup_failed");
      return data?.user_id === userId;
    },

    async defaultCurrency(orgId) {
      const { data, error } = await admin
        .from("sd_connected_payment_accounts")
        .select("default_currency")
        .eq("org_id", orgId)
        .maybeSingle();
      if (error) throw new Error("connected_account_currency_lookup_failed");
      return data?.default_currency ?? null;
    },

    async payments(orgId, start, end) {
      const { data, error } = await admin
        .from("sd_payments")
        .select([
          "id",
          "org_id",
          "invoice_id",
          "payment_request_id",
          "payer_id",
          "provider",
          "amount_cents",
          "currency",
          "status",
          "processing_fee_cents",
          "platform_fee_cents",
          "net_to_organization_cents",
          "paid_at",
          "created_at",
        ].join(","))
        .eq("org_id", orgId)
        .or(
          `and(paid_at.gte.${start},paid_at.lt.${end}),and(paid_at.is.null,created_at.gte.${start},created_at.lt.${end})`,
        )
        .order("created_at", { ascending: false });
      if (error) throw new Error("payments_lookup_failed");
      const rows = (data ?? []) as unknown as PaymentRow[];
      const { requestChildren, invoiceChildren } = await loadPaymentChildren(
        rows,
      );
      return rows.map((row): FinancePaymentRecord => ({
        id: row.id,
        org_id: row.org_id,
        payment_request_id: row.payment_request_id,
        player_id: row.payment_request_id
          ? requestChildren.get(row.payment_request_id) ?? null
          : row.invoice_id
          ? invoiceChildren.get(row.invoice_id) ?? null
          : null,
        payer_id: row.payer_id,
        amount_cents: row.amount_cents,
        processing_fee_cents: row.processing_fee_cents,
        platform_fee_cents: row.platform_fee_cents,
        net_to_organization_cents: row.net_to_organization_cents,
        currency: row.currency,
        status: row.status,
        provider: row.provider,
        paid_at: row.paid_at,
        created_at: row.created_at,
      }));
    },

    async paymentRequests(orgId, start, end) {
      const { data, error } = await admin
        .from("sd_payment_requests")
        .select([
          "id",
          "request_batch_id",
          "org_id",
          "child_id",
          "title",
          "amount_cents",
          "currency",
          "status",
          "due_date",
          "paid_at",
          "created_at",
        ].join(","))
        .eq("org_id", orgId)
        .gte("created_at", start)
        .lt("created_at", end)
        .order("created_at", { ascending: false });
      if (error) throw new Error("payment_requests_lookup_failed");
      return (data ?? []) as unknown as FinancePaymentRequestRecord[];
    },

    async expenses(orgId, startDate, endDate) {
      const { data, error } = await admin
        .from("sd_expenses")
        .select([
          "id",
          "org_id",
          "category",
          "description",
          "amount_cents",
          "currency",
          "expense_date",
          "vendor",
          "notes",
          "created_at",
          "updated_at",
          "archived_at",
          "archived_by",
        ].join(","))
        .eq("org_id", orgId)
        .is("archived_at", null)
        .gte("expense_date", startDate)
        .lte("expense_date", endDate)
        .order("expense_date", { ascending: false });
      if (error) throw new Error("expenses_lookup_failed");
      return (data ?? []) as unknown as FinanceExpenseRecord[];
    },

    async refunds(orgId, start, end) {
      const { data, error } = await admin
        .from("sd_refunds")
        .select("id,org_id,payment_id,amount_cents,status,reason,created_at")
        .eq("org_id", orgId)
        .gte("created_at", start)
        .lt("created_at", end)
        .order("created_at", { ascending: false });
      if (error) throw new Error("refunds_lookup_failed");
      const rows = (data ?? []) as Omit<FinanceRefundRecord, "currency">[];
      const paymentIds = Array.from(new Set(rows.map((row) => row.payment_id)));
      if (paymentIds.length === 0) return [];
      const { data: paymentData, error: paymentError } = await admin
        .from("sd_payments")
        .select("id,currency")
        .eq("org_id", orgId)
        .in("id", paymentIds);
      if (paymentError) throw new Error("refund_currency_lookup_failed");
      const currencies = new Map(
        ((paymentData ?? []) as { id: string; currency: string }[])
          .map((row) => [row.id, row.currency]),
      );
      if (rows.some((row) => !currencies.has(row.payment_id))) {
        throw new Error("refund_currency_missing");
      }
      return rows.map((row): FinanceRefundRecord => ({
        ...row,
        currency: currencies.get(row.payment_id)!,
      }));
    },

    async createExpense(orgId, actorId, input) {
      return await mutateExpense(
        "sd_create_expense",
        expenseParameters(orgId, actorId, input),
      );
    },

    async updateExpense(orgId, actorId, expenseId, input) {
      return await mutateExpense("sd_update_expense", {
        ...expenseParameters(orgId, actorId, input),
        p_expense_id: expenseId,
      });
    },

    async archiveExpense(orgId, actorId, expenseId) {
      return await mutateExpense("sd_archive_expense", {
        p_org_id: orgId,
        p_actor_id: actorId,
        p_expense_id: expenseId,
      });
    },
  };
}

const handler = url && anonKey && serviceKey
  ? createFinanceDashboardHandler(makeStore())
  : null;

Deno.serve((request) => handler ? handler(request) : configurationError());
