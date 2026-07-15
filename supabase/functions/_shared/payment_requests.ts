export const PAYMENT_REQUEST_MAX_AMOUNT_CENTS = 10_000_000;
export const PAYMENT_REQUEST_MAX_TITLE_LENGTH = 120;
export const PAYMENT_REQUEST_MAX_DESCRIPTION_LENGTH = 1_000;
export const PAYMENT_REQUEST_MAX_BATCH_SIZE = 100;

export type OrganizationMembership = {
  role: string;
  status: string;
};

export type PaymentRequestAuthorizationSource =
  | "organization_membership"
  | "platform_support";

export type ParentPaymentLink = {
  child_id: string;
  can_pay: boolean;
};

export type EligiblePaymentRequestPlayer = {
  org_id: string;
  user_id: string;
  role: string;
  status: string;
  created_at: string | null;
  created_by: string | null;
  username: string | null;
  email: string | null;
  full_name: string | null;
  profile_role: string | null;
};

export type PaymentRequestStatus = "open" | "canceled" | "paid";

export type PaymentRequestRecord = {
  id: string;
  request_batch_id: string | null;
  org_id: string;
  child_id: string;
  created_by: string;
  title: string;
  notes: string | null;
  amount_cents: number | null;
  currency: string;
  due_date: string | null;
  status: PaymentRequestStatus;
  created_at: string;
  updated_at: string;
  player_name?: string | null;
};

export type PublicPaymentRequest = {
  id: string;
  request_batch_id: string | null;
  org_id: string;
  player_id: string;
  player_name: string | null;
  created_by: string;
  title: string;
  description: string | null;
  amount_cents: number | null;
  currency: string;
  due_date: string | null;
  status: PaymentRequestStatus;
  created_at: string;
  updated_at: string;
  can_current_user_pay: boolean;
};

export type CreatePaymentRequestBatchInput = {
  org_id: string;
  actor_id: string;
  player_ids: string[];
  title: string;
  description: string | null;
  amount_cents: number;
  currency: "usd";
  due_date: string | null;
  idempotency_key: string;
  idempotency_operation: "create";
};

export type CreatePaymentRequestResponse = {
  requests: PublicPaymentRequest[];
  created_count: number;
  reused: boolean;
  authorization_source: PaymentRequestAuthorizationSource;
};

export type PaymentRequestListResponse = {
  requests: PublicPaymentRequest[];
  authorization_source: PaymentRequestAuthorizationSource;
};

export type EligiblePaymentRequestPlayersResponse = {
  players: EligiblePaymentRequestPlayer[];
  authorization_source: PaymentRequestAuthorizationSource;
};

export type EligiblePaymentRequestRoster = {
  players: EligiblePaymentRequestPlayer[];
  active_membership_count: number;
  deduplicated_user_id_count: number;
  profile_enrichment_count: number;
  username_enrichment_count: number;
};

export type EligiblePaymentRequestMembershipIdentity = {
  user_id: string;
};

export type EligiblePaymentRequestProfileEnrichment = {
  id: string;
  full_name: string | null;
  role?: string | null;
};

export type EligiblePaymentRequestUsernameEnrichment = {
  user_id: string;
  username: string;
};

export type PaymentRequestSingleResponse = {
  request: PublicPaymentRequest;
  authorization_source: PaymentRequestAuthorizationSource;
};

export type PaymentRequestErrorResponse = {
  error: string;
  message: string;
};

export type CreatePaymentRequestBatchResult =
  | {
    kind: "success";
    records: PaymentRequestRecord[];
    createdCount: number;
    reused: boolean;
    authorizationSource: PaymentRequestAuthorizationSource;
  }
  | { kind: "idempotency_conflict" }
  | { kind: "active_player_membership_required" }
  | { kind: "organization_admin_required" }
  | { kind: "organization_inactive_or_missing" };

export type CancelPaymentRequestResult =
  | {
    kind: "success";
    record: PaymentRequestRecord;
    authorizationSource: PaymentRequestAuthorizationSource;
  }
  | { kind: "payment_request_not_found" }
  | { kind: "paid_request_cannot_be_canceled" }
  | { kind: "payment_request_already_canceled" }
  | { kind: "payment_request_state_conflict" }
  | { kind: "organization_admin_required" }
  | { kind: "organization_inactive_or_missing" };

export interface PaymentRequestStore {
  authenticate(request: Request): Promise<string | null>;
  organizationStatus(orgId: string): Promise<string | null>;
  membership(
    orgId: string,
    userId: string,
  ): Promise<OrganizationMembership | null>;
  isPlatformAdmin(userId: string): Promise<boolean>;
  parentLinks(orgId: string, parentId: string): Promise<ParentPaymentLink[]>;
  eligiblePlayers(orgId: string): Promise<EligiblePaymentRequestRoster>;
  activePlayerIds(orgId: string, playerIds: string[]): Promise<Set<string>>;
  paymentRequest(
    orgId: string,
    requestId: string,
  ): Promise<PaymentRequestRecord | null>;
  paymentRequests(
    orgId: string,
    playerIds?: string[],
  ): Promise<PaymentRequestRecord[]>;
  createPaymentRequestBatch(
    input: CreatePaymentRequestBatchInput,
  ): Promise<CreatePaymentRequestBatchResult>;
  cancelOpenPaymentRequest(
    orgId: string,
    actorId: string,
    requestId: string,
  ): Promise<CancelPaymentRequestResult>;
}

type JsonObject = Record<string, unknown>;

const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const forbiddenClientFields = [
  "created_by",
  "created_by_user_id",
  "payer_id",
  "payer_user_id",
  "status",
  "request_batch_id",
  "stripe_account_id",
  "checkout_session_id",
  "payment_intent_id",
  "provider_payment_status",
  "authorization_source",
  "is_platform_admin",
];

const errorMessages: Record<string, string> = {
  method_not_allowed: "This payment-request action is not supported.",
  invalid_auth: "Your session could not be verified. Sign in and try again.",
  invalid_json: "The payment-request input could not be read.",
  server_controlled_field: "The request included a server-controlled field.",
  invalid_organization: "Select a valid organization.",
  organization_inactive_or_missing:
    "The organization is unavailable or inactive.",
  organization_admin_required:
    "An active organization owner or administrator is required.",
  invalid_players: "Select at least one valid player.",
  payment_request_batch_too_large:
    `Select no more than ${PAYMENT_REQUEST_MAX_BATCH_SIZE} players.`,
  invalid_idempotency_key:
    "The operation identifier is invalid. Retry from the form.",
  invalid_title: "Enter a payment-request title up to 120 characters.",
  invalid_description: "The payment-request description is too long.",
  invalid_amount: "Enter a positive amount in integer cents.",
  amount_exceeds_limit:
    "The payment-request amount exceeds the allowed maximum.",
  unsupported_currency: "Only USD is supported for payment requests right now.",
  invalid_due_date: "Enter a valid due date.",
  active_player_membership_required:
    "Every selected player must be active in this organization.",
  idempotency_conflict:
    "This retry identifier is already bound to different payment-request details.",
  payment_request_create_failed: "The payment requests could not be created.",
  invalid_payment_request: "Select a valid payment request.",
  payment_request_not_found: "The payment request could not be found.",
  paid_request_cannot_be_canceled: "A paid payment request cannot be canceled.",
  payment_request_already_canceled: "This payment request is already canceled.",
  payment_request_state_conflict:
    "The payment request changed before it could be updated.",
  organization_membership_required:
    "An active organization membership is required.",
  payment_request_access_denied:
    "You do not have access to these payment requests.",
  invalid_player: "Select a valid player.",
  unsupported_action: "This payment-request action is not supported.",
  payment_requests_unavailable: "Payment requests are temporarily unavailable.",
};

function jsonResponse<T>(status: number, body: T): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });
}

function errorResponse(status: number, error: string): Response {
  const body: PaymentRequestErrorResponse = {
    error,
    message: errorMessages[error] ??
      "The payment-request operation could not be completed.",
  };
  return jsonResponse(status, body);
}

function clean(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function validUuid(value: string): boolean {
  return uuidPattern.test(value);
}

function validISODate(value: string): boolean {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) return false;
  const parsed = new Date(`${value}T00:00:00.000Z`);
  return !Number.isNaN(parsed.valueOf()) &&
    parsed.toISOString().slice(0, 10) === value;
}

function isActiveAdmin(membership: OrganizationMembership | null): boolean {
  return membership?.status === "active" &&
    (membership.role === "owner" || membership.role === "admin");
}

async function managementAuthorization(
  store: PaymentRequestStore,
  membership: OrganizationMembership | null,
  actorId: string,
): Promise<PaymentRequestAuthorizationSource | null> {
  if (isActiveAdmin(membership)) return "organization_membership";
  if (await store.isPlatformAdmin(actorId)) return "platform_support";
  return null;
}

export function buildEligiblePaymentRequestRoster(
  orgId: string,
  memberships: EligiblePaymentRequestMembershipIdentity[],
  profileRows: EligiblePaymentRequestProfileEnrichment[],
  usernameRows: EligiblePaymentRequestUsernameEnrichment[],
): EligiblePaymentRequestRoster {
  // The database query has already enforced organization, role, and status.
  // PostgreSQL's UUID column is authoritative here; do not re-validate its
  // values with a narrower client UUID pattern that could remove valid rows.
  const userIds = Array.from(
    new Set(memberships.map((membership) => membership.user_id.toLowerCase())),
  );
  const eligibleUserIds = new Set(userIds);
  const profiles = new Map(
    profileRows
      .filter((profile) => eligibleUserIds.has(profile.id.toLowerCase()))
      .map((profile) => [profile.id.toLowerCase(), profile]),
  );
  const usernames = new Map(
    usernameRows
      .filter((row) => eligibleUserIds.has(row.user_id.toLowerCase()))
      .map((row) => [row.user_id.toLowerCase(), row.username]),
  );
  const players = userIds.map((userId): EligiblePaymentRequestPlayer => {
    const profile = profiles.get(userId);
    return {
      org_id: orgId,
      user_id: userId,
      role: "player",
      status: "active",
      created_at: null,
      created_by: null,
      username: usernames.get(userId) ?? null,
      email: null,
      full_name: profile?.full_name ?? null,
      profile_role: profile?.role ?? null,
    };
  });
  return {
    players,
    active_membership_count: memberships.length,
    deduplicated_user_id_count: userIds.length,
    profile_enrichment_count: profiles.size,
    username_enrichment_count: usernames.size,
  };
}

function publicRequest(
  record: PaymentRequestRecord,
  canPay: boolean,
): PublicPaymentRequest {
  return {
    id: record.id,
    request_batch_id: record.request_batch_id,
    org_id: record.org_id,
    player_id: record.child_id,
    player_name: record.player_name ?? null,
    created_by: record.created_by,
    title: record.title,
    description: record.notes,
    amount_cents: record.amount_cents,
    currency: record.currency,
    due_date: record.due_date,
    status: record.status,
    created_at: record.created_at,
    updated_at: record.updated_at,
    can_current_user_pay: canPay,
  };
}

function normalizedPlayerIds(value: unknown): string[] | null {
  if (!Array.isArray(value)) return null;
  const normalized = value.map((item) => clean(item));
  if (normalized.some((playerId) => !validUuid(playerId))) return null;
  return Array.from(
    new Set(normalized.map((playerId) => playerId.toLowerCase())),
  ).sort();
}

async function readablePlayers(
  store: PaymentRequestStore,
  orgId: string,
  actorId: string,
  membership: OrganizationMembership,
): Promise<Map<string, boolean> | null> {
  if (isActiveAdmin(membership)) return null;
  if (membership.status !== "active") return new Map();
  if (membership.role === "player") {
    return new Map([[actorId.toLowerCase(), true]]);
  }
  if (membership.role !== "parent") return new Map();

  const permissions = new Map<string, boolean>();
  for (const link of await store.parentLinks(orgId, actorId)) {
    const playerMembership = await store.membership(orgId, link.child_id);
    if (
      playerMembership?.status === "active" &&
      playerMembership.role === "player"
    ) {
      permissions.set(link.child_id, link.can_pay === true);
    }
  }
  return permissions;
}

export function createPaymentRequestHandler(store: PaymentRequestStore) {
  return async (request: Request): Promise<Response> => {
    if (request.method !== "POST") {
      return errorResponse(405, "method_not_allowed");
    }

    let actorId: string | null;
    try {
      actorId = await store.authenticate(request);
    } catch {
      return errorResponse(401, "invalid_auth");
    }
    if (!actorId) return errorResponse(401, "invalid_auth");

    let body: JsonObject;
    try {
      const decoded: unknown = await request.json();
      if (!decoded || typeof decoded !== "object" || Array.isArray(decoded)) {
        return errorResponse(400, "invalid_json");
      }
      body = decoded as JsonObject;
    } catch {
      return errorResponse(400, "invalid_json");
    }

    if (
      forbiddenClientFields.some((field) =>
        Object.prototype.hasOwnProperty.call(body, field)
      )
    ) {
      return errorResponse(400, "server_controlled_field");
    }

    const action = clean(body.action);
    const orgId = clean(body.org_id);
    if (!validUuid(orgId)) return errorResponse(400, "invalid_organization");

    try {
      const orgStatus = await store.organizationStatus(orgId);
      if (orgStatus !== "active") {
        return errorResponse(404, "organization_inactive_or_missing");
      }

      const actorMembership = await store.membership(orgId, actorId);

      if (action === "list_eligible_players") {
        const authorizationSource = await managementAuthorization(
          store,
          actorMembership,
          actorId,
        );
        if (!authorizationSource) {
          return errorResponse(403, "organization_admin_required");
        }
        const roster = await store.eligiblePlayers(orgId);
        console.info(JSON.stringify({
          event: "payment_request_eligible_roster",
          org_id: orgId,
          authorization_source: authorizationSource,
          active_player_membership_count: roster.active_membership_count,
          deduplicated_user_id_count: roster.deduplicated_user_id_count,
          profile_enrichment_count: roster.profile_enrichment_count,
          username_enrichment_count: roster.username_enrichment_count,
          final_returned_player_count: roster.players.length,
        }));
        const rosterResponse: EligiblePaymentRequestPlayersResponse = {
          players: roster.players,
          authorization_source: authorizationSource,
        };
        return jsonResponse(200, rosterResponse);
      }

      if (action === "create") {
        const authorizationSource = await managementAuthorization(
          store,
          actorMembership,
          actorId,
        );
        if (!authorizationSource) {
          return errorResponse(403, "organization_admin_required");
        }

        const playerIds = normalizedPlayerIds(body.player_ids);
        const idempotencyKey = clean(body.idempotency_key);
        const title = clean(body.title);
        const description = body.description == null
          ? null
          : clean(body.description);
        const currency = clean(body.currency).toLowerCase();
        const dueDateValue = body.due_date == null ? "" : clean(body.due_date);
        const dueDate = dueDateValue || null;

        if (!playerIds || playerIds.length === 0) {
          return errorResponse(400, "invalid_players");
        }
        if (playerIds.length > PAYMENT_REQUEST_MAX_BATCH_SIZE) {
          return errorResponse(400, "payment_request_batch_too_large");
        }
        if (!validUuid(idempotencyKey)) {
          return errorResponse(400, "invalid_idempotency_key");
        }
        if (!title || title.length > PAYMENT_REQUEST_MAX_TITLE_LENGTH) {
          return errorResponse(400, "invalid_title");
        }
        if (body.description != null && typeof body.description !== "string") {
          return errorResponse(400, "invalid_description");
        }
        if (
          description != null &&
          description.length > PAYMENT_REQUEST_MAX_DESCRIPTION_LENGTH
        ) {
          return errorResponse(400, "invalid_description");
        }
        if (
          !Number.isInteger(body.amount_cents) || Number(body.amount_cents) <= 0
        ) {
          return errorResponse(400, "invalid_amount");
        }
        const amountCents = Number(body.amount_cents);
        if (amountCents > PAYMENT_REQUEST_MAX_AMOUNT_CENTS) {
          return errorResponse(400, "amount_exceeds_limit");
        }
        if (currency !== "usd") {
          return errorResponse(400, "unsupported_currency");
        }
        if (body.due_date != null && typeof body.due_date !== "string") {
          return errorResponse(400, "invalid_due_date");
        }
        if (dueDate && !validISODate(dueDate)) {
          return errorResponse(400, "invalid_due_date");
        }

        const activePlayerIds = await store.activePlayerIds(orgId, playerIds);
        console.info(JSON.stringify({
          event: "payment_request_active_player_validation",
          org_id: orgId,
          submitted_player_id_count: playerIds.length,
          active_membership_match_count: activePlayerIds.size,
        }));
        if (playerIds.some((playerId) => !activePlayerIds.has(playerId))) {
          return errorResponse(400, "active_player_membership_required");
        }

        const result = await store.createPaymentRequestBatch({
          org_id: orgId,
          actor_id: actorId,
          player_ids: playerIds,
          title,
          description: description || null,
          amount_cents: amountCents,
          currency: "usd",
          due_date: dueDate,
          idempotency_key: idempotencyKey,
          idempotency_operation: "create",
        });

        if (result.kind === "idempotency_conflict") {
          return errorResponse(409, "idempotency_conflict");
        }
        if (result.kind === "active_player_membership_required") {
          return errorResponse(400, "active_player_membership_required");
        }
        if (result.kind === "organization_admin_required") {
          return errorResponse(403, "organization_admin_required");
        }
        if (result.kind === "organization_inactive_or_missing") {
          return errorResponse(404, "organization_inactive_or_missing");
        }

        const createResponse: CreatePaymentRequestResponse = {
          requests: result.records.map((record) =>
            publicRequest(record, false)
          ),
          created_count: result.createdCount,
          reused: result.reused,
          authorization_source: result.authorizationSource,
        };
        return jsonResponse(result.reused ? 200 : 201, createResponse);
      }

      if (action === "cancel") {
        const authorizationSource = await managementAuthorization(
          store,
          actorMembership,
          actorId,
        );
        if (!authorizationSource) {
          return errorResponse(403, "organization_admin_required");
        }
        const requestId = clean(body.request_id);
        if (!validUuid(requestId)) {
          return errorResponse(400, "invalid_payment_request");
        }

        const result = await store.cancelOpenPaymentRequest(
          orgId,
          actorId,
          requestId,
        );
        if (result.kind === "success") {
          const cancelResponse: PaymentRequestSingleResponse = {
            request: publicRequest(result.record, false),
            authorization_source: result.authorizationSource,
          };
          return jsonResponse(200, cancelResponse);
        }
        if (result.kind === "organization_admin_required") {
          return errorResponse(403, "organization_admin_required");
        }
        if (result.kind === "organization_inactive_or_missing") {
          return errorResponse(404, "organization_inactive_or_missing");
        }
        if (result.kind === "payment_request_not_found") {
          return errorResponse(404, "payment_request_not_found");
        }
        return errorResponse(409, result.kind);
      }

      if (action === "list_manage") {
        const authorizationSource = await managementAuthorization(
          store,
          actorMembership,
          actorId,
        );
        if (!authorizationSource) {
          return errorResponse(403, "organization_admin_required");
        }
        const records = await store.paymentRequests(orgId);
        const listResponse: PaymentRequestListResponse = {
          requests: records.map((record) => publicRequest(record, false)),
          authorization_source: authorizationSource,
        };
        return jsonResponse(200, listResponse);
      }

      if (action === "list" || action === "get_detail") {
        if (!actorMembership || actorMembership.status !== "active") {
          return errorResponse(403, "organization_membership_required");
        }
        const permissions = await readablePlayers(
          store,
          orgId,
          actorId,
          actorMembership,
        );
        if (permissions && permissions.size === 0) {
          return errorResponse(403, "payment_request_access_denied");
        }
        const authorizationSource: PaymentRequestAuthorizationSource =
          "organization_membership";

        if (action === "get_detail") {
          const requestId = clean(body.request_id);
          if (!validUuid(requestId)) {
            return errorResponse(400, "invalid_payment_request");
          }
          const record = await store.paymentRequest(orgId, requestId);
          if (!record) return errorResponse(404, "payment_request_not_found");
          if (permissions && !permissions.has(record.child_id)) {
            return errorResponse(404, "payment_request_not_found");
          }
          const detailResponse: PaymentRequestSingleResponse = {
            request: publicRequest(
              record,
              permissions?.get(record.child_id) === true,
            ),
            authorization_source: authorizationSource,
          };
          return jsonResponse(200, detailResponse);
        }

        const requestedPlayerIdInput = clean(body.player_id);
        if (requestedPlayerIdInput && !validUuid(requestedPlayerIdInput)) {
          return errorResponse(400, "invalid_player");
        }
        const requestedPlayerId = requestedPlayerIdInput.toLowerCase();
        if (
          requestedPlayerId && permissions &&
          !permissions.has(requestedPlayerId)
        ) {
          return errorResponse(403, "payment_request_access_denied");
        }
        const playerIds = requestedPlayerId
          ? [requestedPlayerId]
          : permissions
          ? Array.from(permissions.keys())
          : undefined;
        const records = await store.paymentRequests(orgId, playerIds);
        const listResponse: PaymentRequestListResponse = {
          requests: records.map((record) =>
            publicRequest(record, permissions?.get(record.child_id) === true)
          ),
          authorization_source: authorizationSource,
        };
        return jsonResponse(200, listResponse);
      }

      return errorResponse(400, "unsupported_action");
    } catch {
      return errorResponse(500, "payment_requests_unavailable");
    }
  };
}
