export type FinanceAuthorizationSource =
  | "organization_membership"
  | "platform_support";

export type FinanceRangePreset =
  | "this_week"
  | "this_month"
  | "this_quarter"
  | "this_year"
  | "custom";

export type FinanceRequestFilter =
  | "all"
  | "open"
  | "paid"
  | "canceled"
  | "overdue";

export type FinanceDateRange = {
  preset: FinanceRangePreset;
  start: string;
  end: string;
  start_date: string;
  end_date: string;
  timezone: "UTC";
  timezone_source: "utc_fallback";
};

export type FinanceMembership = {
  role: string;
  status: string;
};

export type FinancePaymentRecord = {
  id: string;
  org_id: string;
  payment_request_id: string | null;
  player_id: string | null;
  payer_id: string | null;
  amount_cents: number;
  processing_fee_cents: number | null;
  platform_fee_cents: number | null;
  net_to_organization_cents: number | null;
  currency: string;
  status: string;
  provider: string;
  paid_at: string | null;
  created_at: string;
};

export type FinancePaymentRequestRecord = {
  id: string;
  request_batch_id: string | null;
  org_id: string;
  child_id: string;
  title: string;
  amount_cents: number | null;
  currency: string;
  status: "open" | "paid" | "canceled";
  due_date: string | null;
  paid_at: string | null;
  created_at: string;
};

export type FinanceExpenseRecord = {
  id: string;
  org_id: string;
  category: string | null;
  description: string | null;
  amount_cents: number;
  currency: string;
  expense_date: string;
  vendor: string | null;
  notes: string | null;
  created_at: string;
  updated_at: string;
  archived_at: string | null;
  archived_by: string | null;
};

export type FinanceExpenseInput = {
  category: string;
  description: string;
  amount_cents: number;
  currency: string;
  expense_date: string;
  vendor: string | null;
  notes: string | null;
};

export type FinanceRefundRecord = {
  id: string;
  org_id: string;
  payment_id: string;
  amount_cents: number;
  currency: string;
  status: string;
  reason: string | null;
  created_at: string;
};

export type FinanceOverview = {
  range: FinanceDateRange;
  currency: string;
  gross_revenue_cents: number;
  successful_payment_count: number;
  refunds_cents: number;
  provider_fees_cents: number;
  platform_fees_cents: number;
  net_payment_revenue_cents: number;
  expenses_cents: number;
  estimated_profit_cents: number;
  open_request_balance_cents: number;
  overdue_request_balance_cents: number;
  open_request_count: number;
  paid_request_count: number;
  canceled_request_count: number;
  average_payment_cents: number;
};

export type FinanceOverviewResponse = {
  overview: FinanceOverview;
  authorization_source: FinanceAuthorizationSource;
};

export type FinanceRecentPaymentsResponse = {
  range: FinanceDateRange;
  payments: FinancePaymentRecord[];
  authorization_source: FinanceAuthorizationSource;
};

export type FinancePaymentRequestsResponse = {
  range: FinanceDateRange;
  filter: FinanceRequestFilter;
  requests: FinancePaymentRequestRecord[];
  authorization_source: FinanceAuthorizationSource;
};

export type FinanceExpensesResponse = {
  range: FinanceDateRange;
  expenses: FinanceExpenseRecord[];
  authorization_source: FinanceAuthorizationSource;
};

export type FinanceExpenseMutationResponse = {
  expense: FinanceExpenseRecord;
  authorization_source: "organization_membership";
};

export type FinanceRefundsResponse = {
  range: FinanceDateRange;
  refunds: FinanceRefundRecord[];
  authorization_source: FinanceAuthorizationSource;
};

export type FinanceErrorResponse = {
  error: string;
  message: string;
};

export interface FinanceDashboardStore {
  authenticate(request: Request): Promise<string | null>;
  organizationStatus(orgId: string): Promise<string | null>;
  membership(orgId: string, userId: string): Promise<FinanceMembership | null>;
  isPlatformAdmin(userId: string): Promise<boolean>;
  defaultCurrency(orgId: string): Promise<string | null>;
  payments(
    orgId: string,
    start: string,
    end: string,
  ): Promise<FinancePaymentRecord[]>;
  paymentRequests(
    orgId: string,
    start: string,
    end: string,
  ): Promise<FinancePaymentRequestRecord[]>;
  expenses(
    orgId: string,
    startDate: string,
    endDate: string,
  ): Promise<FinanceExpenseRecord[]>;
  refunds(
    orgId: string,
    start: string,
    end: string,
  ): Promise<FinanceRefundRecord[]>;
  createExpense(
    orgId: string,
    actorId: string,
    input: FinanceExpenseInput,
  ): Promise<FinanceExpenseRecord>;
  updateExpense(
    orgId: string,
    actorId: string,
    expenseId: string,
    input: FinanceExpenseInput,
  ): Promise<FinanceExpenseRecord>;
  archiveExpense(
    orgId: string,
    actorId: string,
    expenseId: string,
  ): Promise<FinanceExpenseRecord>;
}

type JsonObject = Record<string, unknown>;

const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const datePattern = /^\d{4}-\d{2}-\d{2}$/;
export const EXPENSE_MAX_AMOUNT_CENTS = 10_000_000;
export const EXPENSE_MAX_CATEGORY_LENGTH = 80;
export const EXPENSE_MAX_DESCRIPTION_LENGTH = 200;
export const EXPENSE_MAX_VENDOR_LENGTH = 120;
export const EXPENSE_MAX_NOTES_LENGTH = 2_000;
const successfulPaymentStatuses = new Set(["succeeded", "paid"]);
const successfulRefundStatuses = new Set(["succeeded", "paid", "completed"]);
const rangePresets = new Set<FinanceRangePreset>([
  "this_week",
  "this_month",
  "this_quarter",
  "this_year",
  "custom",
]);
const requestFilters = new Set<FinanceRequestFilter>([
  "all",
  "open",
  "paid",
  "canceled",
  "overdue",
]);
const expenseMutationActions = new Set([
  "create_expense",
  "update_expense",
  "archive_expense",
]);
const forbiddenClientFields = new Set([
  "actor_id",
  "user_id",
  "role",
  "is_platform_admin",
  "authorization_source",
  "gross_revenue_cents",
  "refunds_cents",
  "provider_fees_cents",
  "platform_fees_cents",
  "net_payment_revenue_cents",
  "expenses_cents",
  "estimated_profit_cents",
  "created_by",
  "created_at",
  "updated_at",
  "archived_at",
  "archived_by",
]);

const errorMessages: Record<string, string> = {
  method_not_allowed: "This finance-dashboard action is not supported.",
  invalid_auth: "Your session could not be verified. Sign in and try again.",
  invalid_json: "The finance-dashboard request could not be read.",
  server_controlled_field: "The request included a server-controlled field.",
  invalid_organization: "Select a valid organization.",
  organization_not_found: "The selected organization could not be found.",
  finance_access_denied:
    "Only an active organization owner or administrator may view finance data.",
  expense_mutation_denied:
    "Only an active organization owner or administrator may manage expenses.",
  organization_inactive:
    "Expenses cannot be changed for an inactive organization.",
  invalid_expense: "The expense request is invalid.",
  invalid_expense_id: "Select a valid expense.",
  expense_not_found: "The expense was not found in this organization.",
  expense_already_archived: "This expense is already archived.",
  expense_archived: "Archived expenses cannot be edited.",
  invalid_expense_amount: "Enter a positive expense amount in cents.",
  expense_amount_exceeds_limit: "The expense amount exceeds the allowed limit.",
  invalid_expense_category: "Enter an expense category up to 80 characters.",
  invalid_expense_description:
    "Enter an expense description up to 200 characters.",
  invalid_expense_vendor: "Vendor cannot exceed 120 characters.",
  invalid_expense_notes: "Notes cannot exceed 2000 characters.",
  invalid_expense_currency: "Select a valid organization currency.",
  expense_currency_mismatch:
    "Expense currency must match the organization financial currency.",
  invalid_expense_date: "Select a valid expense date.",
  expense_mutation_failed: "The expense could not be saved. Please try again.",
  invalid_date_range: "Select a valid finance date range.",
  invalid_filter: "Select a valid payment-request filter.",
  mixed_currency_data:
    "This date range contains multiple currencies and cannot be combined safely.",
  finance_dashboard_unavailable:
    "Finance data is temporarily unavailable. Please try again.",
};

function isObject(value: unknown): value is JsonObject {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function clean(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function cleanOptional(value: unknown): string | null {
  if (value === null || value === undefined) return null;
  if (typeof value !== "string") return null;
  const normalized = value.trim();
  return normalized.length === 0 ? null : normalized;
}

export class FinanceDashboardStoreError extends Error {
  constructor(readonly code: string) {
    super(code);
    this.name = "FinanceDashboardStoreError";
  }
}

function jsonResponse(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });
}

function errorResponse(status: number, error: string): Response {
  const body: FinanceErrorResponse = {
    error,
    message: errorMessages[error] ??
      errorMessages.finance_dashboard_unavailable,
  };
  return jsonResponse(status, body);
}

function pad(value: number): string {
  return value.toString().padStart(2, "0");
}

function dateString(value: Date): string {
  return `${value.getUTCFullYear()}-${pad(value.getUTCMonth() + 1)}-${
    pad(value.getUTCDate())
  }`;
}

function startOfUTCDate(value: Date): Date {
  return new Date(Date.UTC(
    value.getUTCFullYear(),
    value.getUTCMonth(),
    value.getUTCDate(),
  ));
}

function addUTCDays(value: Date, days: number): Date {
  const copy = new Date(value.getTime());
  copy.setUTCDate(copy.getUTCDate() + days);
  return copy;
}

function parseUTCDate(value: string): Date | null {
  if (!datePattern.test(value)) return null;
  const [year, month, day] = value.split("-").map(Number);
  const parsed = new Date(Date.UTC(year, month - 1, day));
  return dateString(parsed) === value ? parsed : null;
}

function validateExpenseInput(
  body: JsonObject,
): { input: FinanceExpenseInput } | { error: string } {
  const category = clean(body.category);
  if (
    category.length === 0 || category.length > EXPENSE_MAX_CATEGORY_LENGTH
  ) {
    return { error: "invalid_expense_category" };
  }
  const description = clean(body.description);
  if (
    description.length === 0 ||
    description.length > EXPENSE_MAX_DESCRIPTION_LENGTH
  ) {
    return { error: "invalid_expense_description" };
  }
  const amountCents = body.amount_cents;
  if (!Number.isSafeInteger(amountCents) || (amountCents as number) <= 0) {
    return { error: "invalid_expense_amount" };
  }
  if ((amountCents as number) > EXPENSE_MAX_AMOUNT_CENTS) {
    return { error: "expense_amount_exceeds_limit" };
  }
  const rawCurrency = clean(body.currency);
  const currency = rawCurrency.toLowerCase();
  if (!/^[a-z]{3}$/.test(currency)) {
    return { error: "invalid_expense_currency" };
  }
  const expenseDate = clean(body.expense_date);
  if (!parseUTCDate(expenseDate)) {
    return { error: "invalid_expense_date" };
  }
  if (
    body.vendor !== null && body.vendor !== undefined &&
    typeof body.vendor !== "string"
  ) {
    return { error: "invalid_expense_vendor" };
  }
  const vendor = cleanOptional(body.vendor);
  if ((vendor?.length ?? 0) > EXPENSE_MAX_VENDOR_LENGTH) {
    return { error: "invalid_expense_vendor" };
  }
  if (
    body.notes !== null && body.notes !== undefined &&
    typeof body.notes !== "string"
  ) {
    return { error: "invalid_expense_notes" };
  }
  const notes = cleanOptional(body.notes);
  if ((notes?.length ?? 0) > EXPENSE_MAX_NOTES_LENGTH) {
    return { error: "invalid_expense_notes" };
  }
  return {
    input: {
      category,
      description,
      amount_cents: amountCents as number,
      currency,
      expense_date: expenseDate,
      vendor,
      notes,
    },
  };
}

function mutationErrorResponse(error: FinanceDashboardStoreError): Response {
  if (error.code === "expense_not_found") {
    return errorResponse(404, error.code);
  }
  if (
    error.code === "expense_already_archived" ||
    error.code === "expense_archived"
  ) {
    return errorResponse(409, error.code);
  }
  if (error.code === "organization_admin_required") {
    return errorResponse(403, "expense_mutation_denied");
  }
  if (error.code === "organization_inactive_or_missing") {
    return errorResponse(409, "organization_inactive");
  }
  return errorResponse(500, "expense_mutation_failed");
}

export function resolveFinanceDateRange(
  body: JsonObject,
  now = new Date(),
): FinanceDateRange | null {
  const rawPreset = clean(body.range) || "this_month";
  if (!rangePresets.has(rawPreset as FinanceRangePreset)) return null;
  const preset = rawPreset as FinanceRangePreset;
  const today = startOfUTCDate(now);
  let start: Date;
  let endExclusive: Date;

  if (preset === "custom") {
    const customStart = parseUTCDate(clean(body.start_date));
    const customEnd = parseUTCDate(clean(body.end_date));
    if (!customStart || !customEnd || customStart > customEnd) return null;
    start = customStart;
    endExclusive = addUTCDays(customEnd, 1);
  } else if (preset === "this_week") {
    const mondayOffset = (today.getUTCDay() + 6) % 7;
    start = addUTCDays(today, -mondayOffset);
    endExclusive = addUTCDays(start, 7);
  } else if (preset === "this_month") {
    start = new Date(Date.UTC(today.getUTCFullYear(), today.getUTCMonth(), 1));
    endExclusive = new Date(Date.UTC(
      today.getUTCFullYear(),
      today.getUTCMonth() + 1,
      1,
    ));
  } else if (preset === "this_quarter") {
    const quarterMonth = Math.floor(today.getUTCMonth() / 3) * 3;
    start = new Date(Date.UTC(today.getUTCFullYear(), quarterMonth, 1));
    endExclusive = new Date(
      Date.UTC(today.getUTCFullYear(), quarterMonth + 3, 1),
    );
  } else {
    start = new Date(Date.UTC(today.getUTCFullYear(), 0, 1));
    endExclusive = new Date(Date.UTC(today.getUTCFullYear() + 1, 0, 1));
  }

  return {
    preset,
    start: start.toISOString(),
    end: endExclusive.toISOString(),
    start_date: dateString(start),
    end_date: dateString(addUTCDays(endExclusive, -1)),
    timezone: "UTC",
    timezone_source: "utc_fallback",
  };
}

function isActiveFinanceMember(membership: FinanceMembership | null): boolean {
  return membership?.status === "active" &&
    (membership.role === "owner" || membership.role === "admin");
}

async function authorize(
  store: FinanceDashboardStore,
  orgId: string,
  actorId: string,
  explicitSupportMode: boolean,
): Promise<FinanceAuthorizationSource | null> {
  const membership = await store.membership(orgId, actorId);
  if (isActiveFinanceMember(membership)) return "organization_membership";
  if (explicitSupportMode && await store.isPlatformAdmin(actorId)) {
    return "platform_support";
  }
  return null;
}

function normalizeCurrency(value: string | null | undefined): string | null {
  const normalized = clean(value).toLowerCase();
  return /^[a-z]{3}$/.test(normalized) ? normalized : null;
}

function reportingCurrency(
  defaultCurrency: string | null,
  currencies: Array<string | null | undefined>,
): string | null {
  const present = new Set(
    currencies.map(normalizeCurrency).filter((value): value is string =>
      value !== null
    ),
  );
  const preferred = normalizeCurrency(defaultCurrency);
  if (preferred) present.add(preferred);
  if (present.size > 1) return null;
  return preferred ?? Array.from(present)[0] ?? "usd";
}

function sum(values: number[]): number {
  return values.reduce((total, value) => total + value, 0);
}

export function calculateFinanceOverview(
  range: FinanceDateRange,
  currency: string,
  payments: FinancePaymentRecord[],
  requests: FinancePaymentRequestRecord[],
  expenses: FinanceExpenseRecord[],
  refunds: FinanceRefundRecord[],
  today: string,
): FinanceOverview {
  const successfulPayments = payments.filter((payment) =>
    successfulPaymentStatuses.has(payment.status)
  );
  const successfulRefunds = refunds.filter((refund) =>
    successfulRefundStatuses.has(refund.status)
  );
  const grossRevenue = sum(
    successfulPayments.map((payment) => payment.amount_cents),
  );
  const providerFees = sum(
    successfulPayments.map((payment) =>
      Math.max(0, payment.processing_fee_cents ?? 0)
    ),
  );
  const platformFees = sum(
    successfulPayments.map((payment) =>
      Math.max(0, payment.platform_fee_cents ?? 0)
    ),
  );
  const refundTotal = sum(
    successfulRefunds.map((refund) => refund.amount_cents),
  );
  const expenseTotal = sum(expenses.map((expense) => expense.amount_cents));
  const openRequests = requests.filter((request) => request.status === "open");
  const overdueRequests = openRequests.filter((request) =>
    request.due_date !== null && request.due_date < today
  );
  const netPaymentRevenue = grossRevenue - refundTotal - providerFees -
    platformFees;

  return {
    range,
    currency,
    gross_revenue_cents: grossRevenue,
    successful_payment_count: successfulPayments.length,
    refunds_cents: refundTotal,
    provider_fees_cents: providerFees,
    platform_fees_cents: platformFees,
    net_payment_revenue_cents: netPaymentRevenue,
    expenses_cents: expenseTotal,
    estimated_profit_cents: netPaymentRevenue - expenseTotal,
    open_request_balance_cents: sum(
      openRequests.map((request) => request.amount_cents ?? 0),
    ),
    overdue_request_balance_cents: sum(
      overdueRequests.map((request) => request.amount_cents ?? 0),
    ),
    open_request_count: openRequests.length,
    paid_request_count:
      requests.filter((request) => request.status === "paid").length,
    canceled_request_count:
      requests.filter((request) => request.status === "canceled").length,
    average_payment_cents: successfulPayments.length === 0
      ? 0
      : Math.trunc(grossRevenue / successfulPayments.length),
  };
}

function filterRequests(
  requests: FinancePaymentRequestRecord[],
  filter: FinanceRequestFilter,
  today: string,
): FinancePaymentRequestRecord[] {
  if (filter === "all") return requests;
  if (filter === "overdue") {
    return requests.filter((request) =>
      request.status === "open" && request.due_date !== null &&
      request.due_date < today
    );
  }
  return requests.filter((request) => request.status === filter);
}

async function loadCurrency(
  store: FinanceDashboardStore,
  orgId: string,
  values: Array<string | null | undefined>,
): Promise<string | null> {
  return reportingCurrency(await store.defaultCurrency(orgId), values);
}

export function createFinanceDashboardHandler(
  store: FinanceDashboardStore,
  now: () => Date = () => new Date(),
) {
  return async (request: Request): Promise<Response> => {
    if (request.method !== "POST") {
      return errorResponse(405, "method_not_allowed");
    }

    const actorId = await store.authenticate(request).catch(() => null);
    if (!actorId) return errorResponse(401, "invalid_auth");

    let body: JsonObject;
    try {
      const value: unknown = await request.json();
      if (!isObject(value)) return errorResponse(400, "invalid_json");
      body = value;
    } catch {
      return errorResponse(400, "invalid_json");
    }

    if (Object.keys(body).some((key) => forbiddenClientFields.has(key))) {
      return errorResponse(400, "server_controlled_field");
    }

    const action = clean(body.action);
    const orgId = clean(body.org_id).toLowerCase();
    if (!uuidPattern.test(orgId)) {
      return errorResponse(400, "invalid_organization");
    }
    try {
      const organizationStatus = await store.organizationStatus(orgId);
      if (organizationStatus === null) {
        return errorResponse(404, "organization_not_found");
      }
      const authorizationSource = await authorize(
        store,
        orgId,
        actorId,
        body.support_mode === true,
      );
      if (!authorizationSource) {
        return errorResponse(403, "finance_access_denied");
      }

      if (expenseMutationActions.has(action)) {
        if (
          body.support_mode === true ||
          authorizationSource !== "organization_membership"
        ) {
          return errorResponse(403, "expense_mutation_denied");
        }
        if (organizationStatus !== "active") {
          return errorResponse(409, "organization_inactive");
        }

        let expense: FinanceExpenseRecord;
        if (action === "archive_expense") {
          const expenseId = clean(body.expense_id).toLowerCase();
          if (!uuidPattern.test(expenseId)) {
            return errorResponse(400, "invalid_expense_id");
          }
          expense = await store.archiveExpense(orgId, actorId, expenseId);
        } else {
          const validated = validateExpenseInput(body);
          if ("error" in validated) {
            return errorResponse(400, validated.error);
          }
          const organizationCurrency = normalizeCurrency(
            await store.defaultCurrency(orgId),
          ) ?? "usd";
          if (validated.input.currency !== organizationCurrency) {
            return errorResponse(409, "expense_currency_mismatch");
          }
          if (action === "create_expense") {
            expense = await store.createExpense(
              orgId,
              actorId,
              validated.input,
            );
          } else {
            const expenseId = clean(body.expense_id).toLowerCase();
            if (!uuidPattern.test(expenseId)) {
              return errorResponse(400, "invalid_expense_id");
            }
            expense = await store.updateExpense(
              orgId,
              actorId,
              expenseId,
              validated.input,
            );
          }
        }
        const response: FinanceExpenseMutationResponse = {
          expense,
          authorization_source: "organization_membership",
        };
        return jsonResponse(200, response);
      }

      const range = resolveFinanceDateRange(body, now());
      if (!range) return errorResponse(400, "invalid_date_range");

      const today = dateString(startOfUTCDate(now()));

      if (action === "overview") {
        const [payments, requests, expenses, refunds] = await Promise.all([
          store.payments(orgId, range.start, range.end),
          store.paymentRequests(orgId, range.start, range.end),
          store.expenses(orgId, range.start_date, range.end_date),
          store.refunds(orgId, range.start, range.end),
        ]);
        const currency = await loadCurrency(store, orgId, [
          ...payments.map((record) => record.currency),
          ...requests.map((record) => record.currency),
          ...expenses.map((record) => record.currency),
          ...refunds.map((record) => record.currency),
        ]);
        if (!currency) return errorResponse(409, "mixed_currency_data");
        const response: FinanceOverviewResponse = {
          overview: calculateFinanceOverview(
            range,
            currency,
            payments,
            requests,
            expenses,
            refunds,
            today,
          ),
          authorization_source: authorizationSource,
        };
        return jsonResponse(200, response);
      }

      if (action === "recent_payments") {
        const records = (await store.payments(orgId, range.start, range.end))
          .filter((payment) => successfulPaymentStatuses.has(payment.status))
          .sort((lhs, rhs) =>
            (rhs.paid_at ?? rhs.created_at).localeCompare(
              lhs.paid_at ?? lhs.created_at,
            )
          )
          .slice(0, 25);
        const response: FinanceRecentPaymentsResponse = {
          range,
          payments: records,
          authorization_source: authorizationSource,
        };
        return jsonResponse(200, response);
      }

      if (action === "payment_requests") {
        const rawFilter = clean(body.filter) || "all";
        if (!requestFilters.has(rawFilter as FinanceRequestFilter)) {
          return errorResponse(400, "invalid_filter");
        }
        const filter = rawFilter as FinanceRequestFilter;
        const records = await store.paymentRequests(
          orgId,
          range.start,
          range.end,
        );
        const response: FinancePaymentRequestsResponse = {
          range,
          filter,
          requests: filterRequests(records, filter, today),
          authorization_source: authorizationSource,
        };
        return jsonResponse(200, response);
      }

      if (action === "expenses") {
        const response: FinanceExpensesResponse = {
          range,
          expenses: await store.expenses(
            orgId,
            range.start_date,
            range.end_date,
          ),
          authorization_source: authorizationSource,
        };
        return jsonResponse(200, response);
      }

      if (action === "refunds") {
        const response: FinanceRefundsResponse = {
          range,
          refunds: await store.refunds(orgId, range.start, range.end),
          authorization_source: authorizationSource,
        };
        return jsonResponse(200, response);
      }

      return errorResponse(400, "method_not_allowed");
    } catch (error) {
      if (error instanceof FinanceDashboardStoreError) {
        return mutationErrorResponse(error);
      }
      return errorResponse(500, "finance_dashboard_unavailable");
    }
  };
}
