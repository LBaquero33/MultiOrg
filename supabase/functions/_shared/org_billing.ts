import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

export type Json = Record<string, unknown>;

export const json = (status: number, body: Json) => new Response(JSON.stringify(body), {
  status,
  headers: { "content-type": "application/json" },
});

export const env = (name: string) => (Deno.env.get(name) ?? "").trim();

export const isUuid = (value: string) => /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value);

export async function requireBillingAdministrator(req: Request, orgId: string) {
  const url = env("SUPABASE_URL") || env("DHD_SUPABASE_URL");
  const anon = env("SUPABASE_ANON_KEY") || env("DHD_SUPABASE_ANON_KEY");
  const service = env("SUPABASE_SERVICE_ROLE_KEY") || env("DHD_SERVICE_ROLE_KEY");
  const authorization = req.headers.get("Authorization") ?? "";
  if (!url || !anon || !service) throw new Error("missing_supabase_configuration");
  if (!authorization) throw new Error("missing_auth");

  const userClient = createClient(url, anon, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: userData, error: userError } = await userClient.auth.getUser();
  const actorId = userData.user?.id;
  if (userError || !actorId) throw new Error("invalid_auth");

  const admin = createClient(url, service, { auth: { persistSession: false, autoRefreshToken: false } });
  const [{ data: organization, error: orgError }, { data: membership, error: membershipError }, { data: platformAdmin }] = await Promise.all([
    admin.from("sd_orgs").select("id,name,status,billing_email,support_email").eq("id", orgId).maybeSingle(),
    admin.from("sd_org_memberships").select("role,status").eq("org_id", orgId).eq("user_id", actorId).maybeSingle(),
    admin.from("sd_platform_admins").select("user_id").eq("user_id", actorId).maybeSingle(),
  ]);
  if (orgError) throw new Error("organization_lookup_failed");
  if (!organization || organization.status !== "active") throw new Error("organization_inactive_or_missing");
  if (membershipError) throw new Error("membership_lookup_failed");

  // Existing app convention: organization owners and platform admins receive
  // organization-administration authority. Coaches remain staff, not billers.
  const isOwner = membership?.status === "active" && membership?.role === "owner";
  if (!isOwner && !platformAdmin?.user_id) throw new Error("organization_billing_admin_required");

  return { admin, actorId, organization };
}
