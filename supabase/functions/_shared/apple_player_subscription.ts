import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { Buffer } from "node:buffer";
import { Environment, SignedDataVerifier } from "npm:@apple/app-store-server-library@1.4.0";

export const APPLE_PLAYER_MONTHLY_PRODUCT_ID = "com.homeplate.player.monthly";
export const env = (name: string) => (Deno.env.get(name) ?? "").trim();
export const json = (status: number, body: Record<string, unknown>) => new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });

export function canonicalUuid(value: unknown): string | null {
  const candidate = String(value ?? "").trim().toLowerCase();
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/.test(candidate)
    ? candidate
    : null;
}

export async function expectedAppAccountToken(orgId: string, playerId: string, billingUserId: string) {
  const bytes = new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(`${orgId.toLowerCase()}|${playerId.toLowerCase()}|${billingUserId.toLowerCase()}`))).slice(0, 16);
  bytes[6] = (bytes[6] & 0x0f) | 0x50;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  const hex = Array.from(bytes).map((b) => b.toString(16).padStart(2, "0")).join("");
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
}

export function validateAppleTransactionContext(
  transaction: any,
  expected: { bundleId: string; productId: string; environment: string; appAccountToken: string },
) {
  if (String(transaction.bundleId ?? "") !== expected.bundleId) throw new Error("bundle_id_mismatch");
  if (String(transaction.productId ?? "") !== expected.productId) throw new Error("product_id_mismatch");
  if (String(transaction.appAccountToken ?? "").toLowerCase() !== expected.appAccountToken.toLowerCase()) {
    throw new Error("app_account_token_mismatch");
  }
  if (String(transaction.environment ?? "").toLowerCase() !== expected.environment.toLowerCase()) {
    throw new Error("environment_mismatch");
  }
}

export async function appleVerifier() {
  const bundleId = env("APPLE_BUNDLE_ID");
  const mode = env("APPLE_ENVIRONMENT").toLowerCase();
  const roots = JSON.parse(env("APPLE_ROOT_CA_CERTIFICATES_BASE64") || "[]") as string[];
  if (!bundleId || !roots.length) throw new Error("missing_apple_verifier_configuration");
  const environment = mode === "production" ? Environment.PRODUCTION : Environment.SANDBOX;
  const appAppleId = environment === Environment.PRODUCTION ? Number(env("APPLE_APP_APPLE_ID")) || undefined : undefined;
  return new SignedDataVerifier(roots.map((value) => Buffer.from(value, "base64")), true, environment, bundleId, appAppleId);
}

type Membership = { user_id?: string; role?: string; status?: string } | null;
type Profile = { id?: string } | null;
type ParentLink = { parent_id?: string; child_id?: string; org_id?: string | null; can_pay?: boolean } | null;

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
  if (args.actorMembership.status?.toLowerCase() !== "active") throw new Error("actor_membership_not_active");
  if (!args.targetMembership) throw new Error("target_membership_missing");
  if (args.targetMembership.status?.toLowerCase() !== "active") throw new Error("target_membership_not_active");
  if (args.targetMembership.role?.toLowerCase() !== "player") throw new Error("target_role_not_player");

  if (args.actorId === args.playerId) {
    if (args.actorMembership.role?.toLowerCase() !== "player") throw new Error("actor_role_not_player");
    return "player" as const;
  }

  if (args.actorMembership.role?.toLowerCase() !== "parent") throw new Error("self_target_id_mismatch");
  if (!args.parentLink) throw new Error("parent_link_missing");
  if (args.parentLink.org_id && args.parentLink.org_id.toLowerCase() !== args.orgId) throw new Error("organization_context_mismatch");
  if (args.parentLink.can_pay !== true) throw new Error("parent_can_pay_false");
  return "parent" as const;
}

export async function requireApplePurchaseActor(req: Request, orgId: string, playerId: string, billingUserId: string) {
  const url = env("SUPABASE_URL");
  const anon = env("SUPABASE_ANON_KEY");
  const service = env("SUPABASE_SERVICE_ROLE_KEY");
  const authorization = req.headers.get("Authorization") ?? "";
  if (!url || !anon || !service || !authorization) throw new Error("missing_auth");

  const userClient = createClient(url, anon, { global: { headers: { Authorization: authorization } }, auth: { persistSession: false, autoRefreshToken: false } });
  const { data, error } = await userClient.auth.getUser();
  const actorId = canonicalUuid(data.user?.id);
  if (error || !actorId) throw new Error("invalid_auth");
  if (actorId !== billingUserId) throw new Error("billing_user_id_mismatch");

  // The JWT is verified above. Protected authorization rows are then read with
  // the service role so client RLS cannot turn a valid membership into a false
  // "missing" result. Every authorization predicate remains explicit below.
  const admin = createClient(url, service, { auth: { persistSession: false, autoRefreshToken: false } });
  const [actorProfileResult, targetProfileResult, actorMembershipResult, targetMembershipResult] = await Promise.all([
    admin.from("profiles").select("id").eq("id", actorId).maybeSingle(),
    admin.from("profiles").select("id").eq("id", playerId).maybeSingle(),
    admin.from("sd_org_memberships").select("user_id,role,status").eq("org_id", orgId).eq("user_id", actorId).maybeSingle(),
    admin.from("sd_org_memberships").select("user_id,role,status").eq("org_id", orgId).eq("user_id", playerId).maybeSingle(),
  ]);
  if (actorProfileResult.error || targetProfileResult.error || actorMembershipResult.error || targetMembershipResult.error) {
    throw new Error("apple_authorization_lookup_failed");
  }

  let parentLink: ParentLink = null;
  if (actorId !== playerId) {
    const parentLinkResult = await admin
      .from("sd_parent_child_links")
      .select("org_id,parent_id,child_id,can_pay")
      .eq("parent_id", actorId)
      .eq("child_id", playerId)
      .or(`org_id.eq.${orgId},org_id.is.null`)
      .maybeSingle();
    if (parentLinkResult.error) throw new Error("apple_authorization_lookup_failed");
    parentLink = parentLinkResult.data;
  }

  authorizeApplePurchaseContext({
    actorId,
    orgId,
    playerId,
    actorProfile: actorProfileResult.data,
    targetProfile: targetProfileResult.data,
    actorMembership: actorMembershipResult.data,
    targetMembership: targetMembershipResult.data,
    parentLink,
  });
  return { admin, actorId };
}

export function appleStatus(transaction: any, notificationType = "") {
  const now = Date.now();
  const expires = Number(transaction.expiresDate ?? 0);
  const revoked = Number(transaction.revocationDate ?? 0) > 0;
  if (revoked || ["REFUND", "REVOKE"].includes(notificationType)) return "revoked";
  if (["GRACE_PERIOD", "DID_ENTER_GRACE_PERIOD"].includes(notificationType)) return "grace_period";
  if (notificationType === "DID_FAIL_TO_RENEW") return "billing_retry";
  if (notificationType === "GRACE_PERIOD_EXPIRED") return "expired";
  if (expires > 0 && expires <= now) return "expired";
  if (notificationType === "DID_CHANGE_RENEWAL_STATUS" && Number(transaction.autoRenewStatus) === 0) return "canceled_at_period_end";
  return "active";
}

export async function syncAppleSubscription(args: { admin: any; transaction: any; orgId: string; playerId: string; billingUserId: string; status: string; notificationType?: string }) {
  const t = args.transaction;
  const original = String(t.originalTransactionId ?? t.transactionId ?? "");
  if (!original || !t.transactionId) throw new Error("apple_transaction_identifiers_missing");
  const periodEnd = Number(t.expiresDate ?? 0) > 0 ? new Date(Number(t.expiresDate)).toISOString() : null;
  const periodStart = Number(t.purchaseDate ?? 0) > 0 ? new Date(Number(t.purchaseDate)).toISOString() : null;
  const existing = await args.admin.from("sd_player_subscriptions").select("id,org_id,player_id,billing_user_id").eq("provider", "apple").eq("original_transaction_id", original).maybeSingle();
  if (existing.error) throw new Error("subscription_upsert_failed");
  if (existing.data && (
    String(existing.data.org_id).toLowerCase() !== args.orgId ||
    String(existing.data.player_id).toLowerCase() !== args.playerId ||
    String(existing.data.billing_user_id).toLowerCase() !== args.billingUserId
  )) throw new Error("organization_context_mismatch");

  const payload = {
    org_id: args.orgId,
    player_id: args.playerId,
    billing_user_id: args.billingUserId,
    provider: "apple",
    provider_subscription_id: original,
    provider_transaction_id: String(t.transactionId),
    original_transaction_id: original,
    provider_product_id: String(t.productId),
    status: args.status,
    current_period_start: periodStart,
    current_period_end: periodEnd,
    cancel_at_period_end: args.status === "canceled_at_period_end",
    environment: String(t.environment ?? ""),
    provider_state: { app_account_token: t.appAccountToken ?? null, notification_type: args.notificationType ?? null },
  };
  const query = existing.data?.id
    ? args.admin.from("sd_player_subscriptions").update(payload).eq("id", existing.data.id)
    : args.admin.from("sd_player_subscriptions").insert(payload);
  const { error } = await query;
  if (error) throw new Error("subscription_upsert_failed");

  const active = ["active", "grace_period", "billing_retry", "canceled_at_period_end"].includes(args.status) && (!periodEnd || new Date(periodEnd).getTime() > Date.now());
  const { data: entitlement, error: entitlementError } = await args.admin.from("sd_access_entitlements").select("user_id,is_active,source").eq("user_id", args.playerId).maybeSingle();
  if (entitlementError) throw new Error("entitlement_sync_failed");
  const preserveOtherSource = entitlement?.is_active === true && entitlement?.source && entitlement.source !== "apple";
  if (!preserveOtherSource) {
    const { error: upsertError } = await args.admin.from("sd_access_entitlements").upsert({ user_id: args.playerId, org_id: args.orgId, is_active: active, source: "apple", current_period_end: periodEnd }, { onConflict: "user_id" });
    if (upsertError) throw new Error("entitlement_sync_failed");
  }
  return { status: args.status, current_period_end: periodEnd, access_may_be_active: active || preserveOtherSource };
}
