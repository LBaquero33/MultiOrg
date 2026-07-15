import { createClient, type SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { env } from "./org_billing.ts";
import type {
  ConnectedPaymentAccountRow,
  ConnectedPaymentAccountStore,
  StripeConnectSnapshot,
} from "./stripe_connect.ts";

export function canAdministerStripeConnect(
  role: string | null | undefined,
  status: string | null | undefined,
): boolean {
  if (status !== "active") return false;
  return role === "owner" || role === "admin";
}

export async function requireStripeConnectAdministrator(request: Request, orgId: string) {
  const url = env("SUPABASE_URL") || env("DHD_SUPABASE_URL");
  const anonKey = env("SUPABASE_ANON_KEY") || env("DHD_SUPABASE_ANON_KEY");
  const serviceKey = env("SUPABASE_SERVICE_ROLE_KEY") || env("DHD_SERVICE_ROLE_KEY");
  const authorization = request.headers.get("Authorization") ?? "";
  if (!url || !anonKey || !serviceKey) throw new Error("missing_supabase_configuration");
  if (!authorization) throw new Error("missing_auth");

  const actorClient = createClient(url, anonKey, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: actorData, error: actorError } = await actorClient.auth.getUser();
  const actorId = actorData.user?.id;
  if (actorError || !actorId) throw new Error("invalid_auth");

  const admin = createClient(url, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const [orgResult, membershipResult] = await Promise.all([
    admin.from("sd_orgs").select("id,status").eq("id", orgId).maybeSingle(),
    admin.from("sd_org_memberships").select("role,status").eq("org_id", orgId).eq("user_id", actorId).maybeSingle(),
  ]);
  if (orgResult.error) throw new Error("organization_lookup_failed");
  if (!orgResult.data || orgResult.data.status !== "active") {
    throw new Error("organization_inactive_or_missing");
  }
  if (membershipResult.error) throw new Error("membership_lookup_failed");
  if (!membershipResult.data) throw new Error("organization_membership_required");
  if (!canAdministerStripeConnect(
    membershipResult.data.role,
    membershipResult.data.status,
  )) {
    throw new Error("organization_connect_admin_required");
  }
  return { admin, actorId };
}

export function createConnectedPaymentAccountStore(admin: SupabaseClient): ConnectedPaymentAccountStore {
  return {
    async load(orgId): Promise<ConnectedPaymentAccountRow | null> {
      const { data, error } = await admin.from("sd_connected_payment_accounts")
        .select("provider,provider_account_id")
        .eq("org_id", orgId)
        .maybeSingle();
      if (error) throw new Error("connected_payment_account_lookup_failed");
      if (!data) return null;
      return {
        provider: String(data.provider ?? ""),
        provider_account_id: typeof data.provider_account_id === "string"
          ? data.provider_account_id
          : null,
      };
    },

    async persistAccount(orgId, providerAccountId) {
      const { data, error } = await admin.from("sd_connected_payment_accounts").upsert({
        org_id: orgId,
        provider: "stripe",
        provider_account_id: providerAccountId,
        onboarding_status: "onboarding_incomplete",
      }, { onConflict: "org_id" }).select("provider_account_id").single();
      if (error) throw new Error("connected_payment_account_save_failed");
      if (data.provider_account_id !== providerAccountId) {
        throw new Error("connected_payment_account_conflict");
      }
    },

    async persistSnapshot(orgId, providerAccountId, snapshot: StripeConnectSnapshot) {
      const { data, error } = await admin.from("sd_connected_payment_accounts").update({
        onboarding_status: snapshot.status,
        details_submitted: snapshot.details_submitted,
        charges_enabled: snapshot.charges_enabled,
        payouts_enabled: snapshot.payouts_enabled,
        requirements_currently_due: snapshot.currently_due,
        requirements_past_due: snapshot.past_due,
        requirements_eventually_due: snapshot.eventually_due,
        disabled_reason: snapshot.disabled_reason,
        last_synced_at: snapshot.last_synced_at,
      }).eq("org_id", orgId).eq("provider", "stripe").eq("provider_account_id", providerAccountId)
        .select("provider_account_id").maybeSingle();
      if (error) throw new Error("connected_payment_status_save_failed");
      if (!data) throw new Error("connected_payment_account_conflict");
    },
  };
}
