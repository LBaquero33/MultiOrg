import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
export const APPLE_PLAYER_MONTHLY_PRODUCT_ID = "com.homeplate.player.monthly";
export const env = (name: string) => (Deno.env.get(name) ?? "").trim();
export const json = (status: number, body: Record<string, unknown>) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });

export function canonicalUuid(value: unknown): string | null {
  const candidate = String(value ?? "").trim().toLowerCase();
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/
      .test(candidate)
    ? candidate
    : null;
}

export async function expectedAppAccountToken(
  orgId: string,
  playerId: string,
  billingUserId: string,
) {
  const bytes = new Uint8Array(
    await crypto.subtle.digest(
      "SHA-256",
      new TextEncoder().encode(
        `${orgId.toLowerCase()}|${playerId.toLowerCase()}|${billingUserId.toLowerCase()}`,
      ),
    ),
  ).slice(0, 16);
  bytes[6] = (bytes[6] & 0x0f) | 0x50;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  const hex = Array.from(bytes).map((b) => b.toString(16).padStart(2, "0"))
    .join("");
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${
    hex.slice(16, 20)
  }-${hex.slice(20)}`;
}

export function validateAppleTransactionContext(
  transaction: any,
  expected: {
    bundleId: string;
    productId: string;
    environment: string;
    appAccountToken: string;
  },
) {
  if (String(transaction.bundleId ?? "") !== expected.bundleId) {
    throw new Error("bundle_id_mismatch");
  }
  if (String(transaction.productId ?? "") !== expected.productId) {
    throw new Error("product_id_mismatch");
  }
  if (
    String(transaction.appAccountToken ?? "").toLowerCase() !==
      expected.appAccountToken.toLowerCase()
  ) {
    throw new Error("app_account_token_mismatch");
  }
  if (
    String(transaction.environment ?? "").toLowerCase() !==
      expected.environment.toLowerCase()
  ) {
    throw new Error("environment_mismatch");
  }
}

export type StoreKitVerifiedTransactionMetadata = {
  bundleId: string;
  productId: string;
  environment: string;
  appAccountToken: string;
  transactionId: string;
  originalTransactionId: string;
  purchaseDate: number;
  expiresDate: number;
  revocationDate: number;
};

const transactionIdPattern = /^[0-9]{1,32}$/;

function timestamp(value: unknown, code: string) {
  const parsed = Number(String(value ?? ""));
  if (!Number.isSafeInteger(parsed) || parsed < 0) throw new Error(code);
  return parsed;
}

/**
 * Normalizes metadata from a StoreKit `VerificationResult.verified`
 * transaction. This does not claim to reproduce Apple's JWS verification;
 * the iOS client must reject `.unverified` before calling the function.
 */
export function normalizeStoreKitVerifiedTransaction(
  body: Record<string, unknown>,
  expected: { appAccountToken: string; environment: string; bundleId: string },
  now = Date.now(),
): StoreKitVerifiedTransactionMetadata {
  const transactionId = String(body.transaction_id ?? "").trim();
  const originalTransactionId = String(body.original_transaction_id ?? "")
    .trim();
  const productId = String(body.product_id ?? "").trim();
  const bundleId = String(body.bundle_id ?? "").trim();
  const environment = String(body.environment ?? "").trim().toLowerCase();
  const appAccountToken = canonicalUuid(body.app_account_token);
  if (
    !transactionIdPattern.test(transactionId) ||
    !transactionIdPattern.test(originalTransactionId)
  ) throw new Error("apple_transaction_identifiers_missing");
  if (productId !== APPLE_PLAYER_MONTHLY_PRODUCT_ID) {
    throw new Error("product_id_mismatch");
  }
  if (!expected.bundleId || bundleId !== expected.bundleId) {
    throw new Error("bundle_id_mismatch");
  }
  if (!appAccountToken || appAccountToken !== expected.appAccountToken) {
    throw new Error("app_account_token_mismatch");
  }
  if (environment !== expected.environment.toLowerCase()) {
    throw new Error("environment_mismatch");
  }
  const purchaseDate = timestamp(
    body.purchase_date_ms,
    "apple_transaction_invalid",
  );
  const expiresDate = timestamp(
    body.expires_date_ms,
    "apple_transaction_invalid",
  );
  const revocationDate = timestamp(
    body.revocation_date_ms,
    "apple_transaction_invalid",
  );
  const earliestReasonablePurchase = Date.UTC(2020, 0, 1);
  const maximumMonthlyPeriod = 45 * 24 * 60 * 60 * 1_000;
  if (
    purchaseDate < earliestReasonablePurchase ||
    purchaseDate > now + 5 * 60_000 ||
    expiresDate <= purchaseDate ||
    expiresDate - purchaseDate > maximumMonthlyPeriod ||
    (revocationDate > 0 && revocationDate < purchaseDate)
  ) throw new Error("apple_transaction_invalid");
  return {
    bundleId,
    productId,
    environment,
    appAccountToken,
    transactionId,
    originalTransactionId,
    purchaseDate,
    expiresDate,
    revocationDate,
  };
}

type Membership = { user_id?: string; role?: string; status?: string } | null;
type Profile = { id?: string } | null;
type ParentLink = {
  parent_id?: string;
  child_id?: string;
  org_id?: string | null;
  can_pay?: boolean;
} | null;

export function authorizeApplePurchaseContext(args: {
  actorId: string;
  orgId: string;
  playerId: string;
  actorProfile: Profile;
  targetProfile: Profile;
  actorMembership: Membership;
  targetMembership: Membership;
  parentLink: ParentLink;
}) {
  if (!args.actorProfile) throw new Error("actor_profile_missing");
  if (!args.targetProfile) throw new Error("target_profile_missing");
  if (!args.actorMembership) throw new Error("actor_membership_missing");
  if (args.actorMembership.status?.toLowerCase() !== "active") {
    throw new Error("actor_membership_not_active");
  }
  if (!args.targetMembership) throw new Error("target_membership_missing");
  if (args.targetMembership.status?.toLowerCase() !== "active") {
    throw new Error("target_membership_not_active");
  }
  if (args.targetMembership.role?.toLowerCase() !== "player") {
    throw new Error("target_role_not_player");
  }

  if (args.actorId === args.playerId) {
    if (args.actorMembership.role?.toLowerCase() !== "player") {
      throw new Error("actor_role_not_allowed");
    }
    return "player" as const;
  }

  if (args.actorMembership.role?.toLowerCase() !== "parent") {
    throw new Error("actor_role_not_allowed");
  }
  if (!args.parentLink) throw new Error("parent_link_missing");
  if (
    canonicalUuid(args.parentLink.org_id) !== args.orgId ||
    canonicalUuid(args.parentLink.parent_id) !== args.actorId ||
    canonicalUuid(args.parentLink.child_id) !== args.playerId
  ) throw new Error("organization_context_mismatch");
  if (args.parentLink.can_pay !== true) throw new Error("parent_can_pay_false");
  return "parent" as const;
}

export async function requireApplePurchaseActor(
  req: Request,
  orgId: string,
  playerId: string,
) {
  const url = env("SUPABASE_URL");
  const anon = env("SUPABASE_ANON_KEY");
  const service = env("SUPABASE_SERVICE_ROLE_KEY");
  const authorization = req.headers.get("Authorization") ?? "";
  if (!url || !anon || !service || !authorization) {
    throw new Error("missing_auth");
  }

  const userClient = createClient(url, anon, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data, error } = await userClient.auth.getUser();
  const actorId = canonicalUuid(data.user?.id);
  if (error || !actorId) throw new Error("invalid_auth");

  // Authorization executes under the authenticated JWT in a narrowly scoped
  // SECURITY DEFINER RPC. The service role is not constructed until the actor,
  // player, organization, role, and parent can_pay relationship all pass.
  const authorizationResult = await userClient.rpc(
    "sd_authorize_apple_player_purchase",
    { p_org_id: orgId, p_player_id: playerId },
  );
  if (authorizationResult.error) {
    const message = String(authorizationResult.error.message ?? "");
    const safeCodes = [
      "invalid_auth",
      "actor_profile_missing",
      "target_profile_missing",
      "actor_membership_missing",
      "actor_membership_not_active",
      "target_membership_missing",
      "target_membership_not_active",
      "target_role_not_player",
      "actor_role_not_allowed",
      "parent_link_missing",
      "parent_can_pay_false",
    ];
    const code = safeCodes.find((candidate) => message.includes(candidate));
    throw new Error(code ?? "apple_authorization_lookup_failed");
  }
  const authorizationData = Array.isArray(authorizationResult.data)
    ? authorizationResult.data[0]
    : authorizationResult.data;
  if (canonicalUuid(authorizationData?.billing_user_id) !== actorId) {
    throw new Error("apple_authorization_lookup_failed");
  }

  const admin = createClient(url, service, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  return { admin, actorId };
}

export function appleStatus(transaction: any, notificationType = "") {
  const now = Date.now();
  const expires = Number(transaction.expiresDate ?? 0);
  const revoked = Number(transaction.revocationDate ?? 0) > 0;
  if (revoked || ["REFUND", "REVOKE"].includes(notificationType)) {
    return "revoked";
  }
  if (["GRACE_PERIOD", "DID_ENTER_GRACE_PERIOD"].includes(notificationType)) {
    return "grace_period";
  }
  if (notificationType === "DID_FAIL_TO_RENEW") return "billing_retry";
  if (notificationType === "GRACE_PERIOD_EXPIRED") return "expired";
  if (expires > 0 && expires <= now) return "expired";
  if (
    notificationType === "DID_CHANGE_RENEWAL_STATUS" &&
    Number(transaction.autoRenewStatus) === 0
  ) return "canceled_at_period_end";
  return "active";
}

export type AppleSubscriptionSyncResult = {
  status: string;
  current_period_end: string | null;
  persisted: boolean;
  entitlement_synchronized: boolean;
  access_is_active: boolean;
  idempotent: boolean;
};

const atomicSyncSafeCodes = [
  "product_id_mismatch",
  "environment_mismatch",
  "apple_transaction_invalid",
  "apple_transaction_reassigned",
  "apple_original_transaction_reassigned",
  "apple_transaction_lineage_conflict",
  "apple_transaction_context_mismatch",
  "apple_transaction_replay",
  "apple_transaction_replay_conflict",
  "player_subscription_context_conflict",
] as const;

function safeAtomicSyncError(error: unknown) {
  const raw = typeof (error as any)?.message === "string"
    ? (error as any).message
    : "";
  // Match the most specific database code first. Several codes intentionally
  // share prefixes (for example replay and replay_conflict).
  const orderedCodes = [...atomicSyncSafeCodes].sort((a, b) =>
    b.length - a.length
  );
  for (const code of orderedCodes) {
    if (raw.includes(code)) return code;
  }
  return "apple_subscription_atomic_sync_failed";
}

export async function syncAppleSubscriptionAtomically(args: {
  admin: any;
  transaction: StoreKitVerifiedTransactionMetadata;
  orgId: string;
  playerId: string;
  billingUserId: string;
  status: string;
}): Promise<AppleSubscriptionSyncResult> {
  const transaction = args.transaction;
  const periodStart = new Date(transaction.purchaseDate).toISOString();
  const periodEnd = new Date(transaction.expiresDate).toISOString();
  const revocationDate = transaction.revocationDate > 0
    ? new Date(transaction.revocationDate).toISOString()
    : null;
  const { data, error } = await args.admin.rpc(
    "sd_sync_apple_player_subscription",
    {
      p_org_id: args.orgId,
      p_player_id: args.playerId,
      p_billing_user_id: args.billingUserId,
      p_product_id: transaction.productId,
      p_transaction_id: transaction.transactionId,
      p_original_transaction_id: transaction.originalTransactionId,
      p_environment: transaction.environment,
      p_status: args.status,
      p_period_start: periodStart,
      p_period_end: periodEnd,
      p_app_account_token: transaction.appAccountToken,
      p_revocation_date: revocationDate,
    },
  );
  if (error) throw new Error(safeAtomicSyncError(error));

  const result = Array.isArray(data) ? data[0] : data;
  if (
    !result || result.persisted !== true ||
    result.entitlement_synchronized !== true ||
    typeof result.access_is_active !== "boolean"
  ) throw new Error("apple_subscription_atomic_sync_failed");

  return {
    status: String(result.status ?? args.status),
    current_period_end: result.current_period_end
      ? String(result.current_period_end)
      : null,
    persisted: true,
    entitlement_synchronized: true,
    access_is_active: result.access_is_active,
    idempotent: result.idempotent === true,
  };
}
