import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import {
  buildEligiblePaymentRequestRoster,
  type CancelPaymentRequestResult,
  type CreatePaymentRequestBatchInput,
  type CreatePaymentRequestBatchResult,
  createPaymentRequestHandler,
  type EligiblePaymentRequestMembershipIdentity,
  type EligiblePaymentRequestProfileEnrichment,
  type EligiblePaymentRequestUsernameEnrichment,
  type PaymentRequestAuthorizationSource,
  type PaymentRequestErrorResponse,
  type PaymentRequestRecord,
  type PaymentRequestStatus,
  type PaymentRequestStore,
} from "../_shared/payment_requests.ts";
import { wakeNotificationDeliveriesAfterCommit } from "../_shared/notification_delivery_wakeup.ts";

const env = (name: string) => (Deno.env.get(name) ?? "").trim();
const url = env("SUPABASE_URL") || env("DHD_SUPABASE_URL");
const anonKey = env("SUPABASE_ANON_KEY") || env("DHD_SUPABASE_ANON_KEY");
const serviceKey = env("DHD_SERVICE_ROLE_KEY") ||
  env("SUPABASE_SERVICE_ROLE_KEY");
const notificationWorkerSecret = env("NOTIFICATION_DELIVERY_WORKER_SECRET");

const rowSelection = [
  "id",
  "request_batch_id",
  "org_id",
  "child_id",
  "created_by",
  "title",
  "notes",
  "amount_cents",
  "currency",
  "due_date",
  "status",
  "created_at",
  "updated_at",
].join(",");

type DatabasePaymentRequest = Omit<PaymentRequestRecord, "player_name">;
type ProfileName = {
  id: string;
  full_name: string | null;
  role?: string | null;
};
type BatchRPCResponse = {
  requests: DatabasePaymentRequest[];
  created_count: number;
  reused: boolean;
  authorization_source: PaymentRequestAuthorizationSource;
};
type CancelRPCResponse = {
  request: DatabasePaymentRequest;
  authorization_source: PaymentRequestAuthorizationSource;
};

function errorJSON(status: number, error: string, message: string): Response {
  const body: PaymentRequestErrorResponse = { error, message };
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });
}

function isObject(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function isNullableString(value: unknown): value is string | null {
  return value === null || typeof value === "string";
}

function isStatus(value: unknown): value is PaymentRequestStatus {
  return value === "open" || value === "canceled" || value === "paid";
}

function isAuthorizationSource(
  value: unknown,
): value is PaymentRequestAuthorizationSource {
  return value === "organization_membership" || value === "platform_support";
}

function parseDatabasePaymentRequest(value: unknown): DatabasePaymentRequest {
  if (
    !isObject(value) ||
    typeof value.id !== "string" ||
    !isNullableString(value.request_batch_id) ||
    typeof value.org_id !== "string" ||
    typeof value.child_id !== "string" ||
    typeof value.created_by !== "string" ||
    typeof value.title !== "string" ||
    !isNullableString(value.notes) ||
    !(value.amount_cents === null || typeof value.amount_cents === "number") ||
    typeof value.currency !== "string" ||
    !isNullableString(value.due_date) ||
    !isStatus(value.status) ||
    typeof value.created_at !== "string" ||
    typeof value.updated_at !== "string"
  ) {
    throw new Error("payment_request_response_invalid");
  }
  return {
    id: value.id,
    request_batch_id: value.request_batch_id,
    org_id: value.org_id,
    child_id: value.child_id,
    created_by: value.created_by,
    title: value.title,
    notes: value.notes,
    amount_cents: value.amount_cents,
    currency: value.currency,
    due_date: value.due_date,
    status: value.status,
    created_at: value.created_at,
    updated_at: value.updated_at,
  };
}

function parseBatchRPCResponse(value: unknown): BatchRPCResponse {
  if (
    !isObject(value) ||
    !Array.isArray(value.requests) ||
    typeof value.created_count !== "number" ||
    !Number.isInteger(value.created_count) ||
    typeof value.reused !== "boolean" ||
    !isAuthorizationSource(value.authorization_source)
  ) {
    throw new Error("payment_request_batch_response_invalid");
  }
  return {
    requests: value.requests.map(parseDatabasePaymentRequest),
    created_count: value.created_count,
    reused: value.reused,
    authorization_source: value.authorization_source,
  };
}

function parseCancelRPCResponse(value: unknown): CancelRPCResponse {
  if (!isObject(value) || !isAuthorizationSource(value.authorization_source)) {
    throw new Error("payment_request_cancel_response_invalid");
  }
  return {
    request: parseDatabasePaymentRequest(value.request),
    authorization_source: value.authorization_source,
  };
}

function rpcFailure(message: string): CreatePaymentRequestBatchResult | null {
  if (message.includes("payment_request_idempotency_conflict")) {
    return { kind: "idempotency_conflict" };
  }
  if (message.includes("active_player_membership_required")) {
    return { kind: "active_player_membership_required" };
  }
  if (message.includes("organization_admin_required")) {
    return { kind: "organization_admin_required" };
  }
  if (message.includes("organization_inactive_or_missing")) {
    return { kind: "organization_inactive_or_missing" };
  }
  return null;
}

function cancelRPCFailure(message: string): CancelPaymentRequestResult | null {
  for (
    const kind of [
      "payment_request_not_found",
      "paid_request_cannot_be_canceled",
      "payment_request_already_canceled",
      "payment_request_state_conflict",
      "organization_admin_required",
      "organization_inactive_or_missing",
    ] as const
  ) {
    if (message.includes(kind)) return { kind };
  }
  return null;
}

function makeStore(): PaymentRequestStore {
  const admin = createClient(url, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const withPlayerNames = async (
    rows: DatabasePaymentRequest[],
  ): Promise<PaymentRequestRecord[]> => {
    const playerIds = Array.from(new Set(rows.map((row) => row.child_id)));
    if (playerIds.length === 0) return [];
    const { data, error } = await admin
      .from("profiles")
      .select("id,full_name")
      .in("id", playerIds);
    if (error) throw new Error("profile_lookup_failed");
    const profiles = (data ?? []) as ProfileName[];
    const names = new Map(
      profiles.map((profile) => [profile.id, profile.full_name]),
    );
    return rows.map((row) => ({
      ...row,
      player_name: names.get(row.child_id) ?? null,
    }));
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

    async parentLinks(orgId, parentId) {
      const { data, error } = await admin
        .from("sd_parent_child_links")
        .select("child_id,can_pay")
        .eq("org_id", orgId)
        .eq("parent_id", parentId);
      if (error) throw new Error("parent_link_lookup_failed");
      return data ?? [];
    },

    async eligiblePlayers(orgId) {
      const { data: membershipData, error: membershipError } = await admin
        .from("sd_org_memberships")
        .select("user_id")
        .eq("org_id", orgId)
        .eq("role", "player")
        .eq("status", "active");
      if (membershipError) {
        throw new Error("eligible_player_membership_lookup_failed");
      }

      const memberships =
        (membershipData ?? []) as EligiblePaymentRequestMembershipIdentity[];
      const userIds = Array.from(
        new Set(memberships.map((membership) => membership.user_id)),
      );
      if (userIds.length === 0) {
        return buildEligiblePaymentRequestRoster(orgId, memberships, [], []);
      }

      const [profileResult, usernameResult] = await Promise.all([
        admin.from("profiles").select("id,full_name,role").in("id", userIds),
        admin.from("sd_org_usernames").select("user_id,username").eq(
          "org_id",
          orgId,
        ).in("user_id", userIds),
      ]);
      if (profileResult.error) {
        console.warn(JSON.stringify({
          event: "payment_request_roster_enrichment_unavailable",
          org_id: orgId,
          enrichment: "profile",
        }));
      }
      if (usernameResult.error) {
        console.warn(JSON.stringify({
          event: "payment_request_roster_enrichment_unavailable",
          org_id: orgId,
          enrichment: "organization_username",
        }));
      }

      const profiles = profileResult.error ? [] : (profileResult.data ??
        []) as EligiblePaymentRequestProfileEnrichment[];
      const usernames = usernameResult.error ? [] : (usernameResult.data ??
        []) as EligiblePaymentRequestUsernameEnrichment[];
      return buildEligiblePaymentRequestRoster(
        orgId,
        memberships,
        profiles,
        usernames,
      );
    },

    async activePlayerIds(orgId, playerIds) {
      const { data, error } = await admin
        .from("sd_org_memberships")
        .select("user_id")
        .eq("org_id", orgId)
        .eq("role", "player")
        .eq("status", "active")
        .in("user_id", playerIds);
      if (error) throw new Error("player_membership_lookup_failed");
      const rows = (data ?? []) as { user_id: string }[];
      return new Set(rows.map((row) => row.user_id.toLowerCase()));
    },

    async paymentRequest(orgId, requestId) {
      const { data, error } = await admin
        .from("sd_payment_requests")
        .select(rowSelection)
        .eq("org_id", orgId)
        .eq("id", requestId)
        .maybeSingle();
      if (error) throw new Error("payment_request_lookup_failed");
      if (!data) return null;
      return (await withPlayerNames([parseDatabasePaymentRequest(data)]))[0] ??
        null;
    },

    async paymentRequests(orgId, playerIds) {
      let query = admin
        .from("sd_payment_requests")
        .select(rowSelection)
        .eq("org_id", orgId);
      if (playerIds) query = query.in("child_id", playerIds);
      const { data, error } = await query.order("created_at", {
        ascending: false,
      });
      if (error) throw new Error("payment_requests_lookup_failed");
      return withPlayerNames((data ?? []).map(parseDatabasePaymentRequest));
    },

    async createPaymentRequestBatch(input: CreatePaymentRequestBatchInput) {
      const { data, error } = await admin.rpc(
        "sd_create_payment_request_batch",
        {
          p_org_id: input.org_id,
          p_actor_id: input.actor_id,
          p_player_ids: input.player_ids,
          p_title: input.title,
          p_description: input.description,
          p_amount_cents: input.amount_cents,
          p_currency: input.currency,
          p_due_date: input.due_date,
          p_idempotency_key: input.idempotency_key,
        },
      );
      if (error) {
        const recognized = rpcFailure(error.message);
        if (recognized) return recognized;
        throw new Error("payment_request_batch_rpc_failed");
      }
      const decoded = parseBatchRPCResponse(data as unknown);
      const records = await withPlayerNames(decoded.requests);
      await wakeNotificationDeliveriesAfterCommit(
        url,
        notificationWorkerSecret,
      );
      return {
        kind: "success" as const,
        records,
        createdCount: decoded.created_count,
        reused: decoded.reused,
        authorizationSource: decoded.authorization_source,
      };
    },

    async cancelOpenPaymentRequest(orgId, actorId, requestId) {
      const { data, error } = await admin.rpc("sd_cancel_payment_request", {
        p_org_id: orgId,
        p_actor_id: actorId,
        p_request_id: requestId,
      });
      if (error) {
        const recognized = cancelRPCFailure(error.message);
        if (recognized) return recognized;
        throw new Error("payment_request_cancel_rpc_failed");
      }
      const decoded = parseCancelRPCResponse(data as unknown);
      const record = (await withPlayerNames([decoded.request]))[0];
      if (!record) throw new Error("payment_request_cancel_response_invalid");
      return {
        kind: "success" as const,
        record,
        authorizationSource: decoded.authorization_source,
      };
    },
  };
}

const handler = url && anonKey && serviceKey
  ? createPaymentRequestHandler(makeStore())
  : null;

Deno.serve((request) =>
  handler ? handler(request) : errorJSON(
    500,
    "missing_configuration",
    "Payment requests are not configured.",
  )
);
