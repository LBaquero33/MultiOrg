// Server-authorized platform administration. Only users in sd_platform_admins
// can view or change data across organizations.
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { platformOrganizationCreationRPCArguments } from "../_shared/platform_admin_organization.ts";

type Json = Record<string, unknown>;
const json = (status: number, body: Json) => new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });
const env = (name: string) => (Deno.env.get(name) ?? "").trim();
const clean = (value: unknown) => String(value ?? "").trim();

Deno.serve(async (req) => {
  if (req.method !== "POST") return json(405, { error: "method_not_allowed" });
  let body: any;
  try { body = await req.json(); } catch { return json(400, { error: "invalid_json" }); }

  const url = env("SUPABASE_URL") || env("DHD_SUPABASE_URL");
  const anon = env("SUPABASE_ANON_KEY") || env("DHD_SUPABASE_ANON_KEY");
  const service = env("DHD_SERVICE_ROLE_KEY") || env("SUPABASE_SERVICE_ROLE_KEY");
  const authorization = req.headers.get("Authorization") ?? "";
  if (!url || !anon || !service || !authorization) return json(500, { error: "missing_configuration" });

  const userClient = createClient(url, anon, { global: { headers: { Authorization: authorization } }, auth: { persistSession: false, autoRefreshToken: false } });
  const { data: userData, error: userError } = await userClient.auth.getUser();
  const actorId = userData.user?.id;
  if (userError || !actorId) return json(401, { error: "invalid_auth" });

  const admin = createClient(url, service, { auth: { persistSession: false, autoRefreshToken: false } });
  const { data: grant } = await admin.from("sd_platform_admins").select("user_id").eq("user_id", actorId).maybeSingle();
  if (!grant) return json(403, { error: "not_platform_admin" });

  const audit = async (action: string, targetType: string, targetId: string | null, orgId: string | null, details: Json = {}) => {
    await admin.from("sd_platform_audit_logs").insert({ actor_id: actorId, action, target_type: targetType, target_id: targetId, org_id: orgId, details });
  };
  const action = clean(body.action);

  if (action === "dashboard") {
    const [
      { data: orgs, error: orgError },
      { data: memberships, error: membershipsError },
      { data: entitlements, error: entitlementsError },
      { data: teams, error: teamsError },
    ] = await Promise.all([
      admin.from("sd_orgs").select("id,slug,name,status,plan,billing_email,max_members,created_at").order("name"),
      admin.from("sd_org_memberships").select("org_id,role,status"),
      admin.from("sd_access_entitlements").select("org_id,is_active"),
      admin.from("sd_teams").select("org_id,id").eq("is_active", true),
    ]);
    if (orgError) return json(500, { error: "orgs_lookup_failed", message: orgError.message });
    if (membershipsError) return json(500, { error: "memberships_lookup_failed", message: membershipsError.message });
    if (entitlementsError) return json(500, { error: "entitlements_lookup_failed", message: entitlementsError.message });
    if (teamsError) return json(500, { error: "teams_lookup_failed", message: teamsError.message });
    const organizationRows = (orgs ?? []).map((org: any) => {
      const orgMembers = (memberships ?? []).filter((m: any) => m.org_id === org.id && m.status === "active");
      const orgEntitlements = (entitlements ?? []).filter((e: any) => e.org_id === org.id);
      return {
        ...org,
        active_members: orgMembers.length,
        players: orgMembers.filter((m: any) => m.role === "player").length,
        coaches: orgMembers.filter((m: any) => ["owner", "admin", "coach"].includes(m.role)).length,
        active_entitlements: orgEntitlements.filter((e: any) => e.is_active === true).length,
        teams: (teams ?? []).filter((t: any) => t.org_id === org.id).length,
      };
    });
    const ownerlessOrganizations = organizationRows.filter((org: any) => {
      const activeOwners = (memberships ?? []).filter((membership: any) =>
        membership.org_id === org.id
        && membership.status === "active"
        && membership.role === "owner"
      );
      return activeOwners.length === 0;
    });
    const unmanagedOrganizations = organizationRows.filter((org: any) => {
      const activeAdministrators = (memberships ?? []).filter((membership: any) =>
        membership.org_id === org.id
        && membership.status === "active"
        && (membership.role === "owner" || membership.role === "admin")
      );
      return activeAdministrators.length === 0;
    });
    return json(200, {
      organizations: organizationRows,
      ownerless_organizations: ownerlessOrganizations,
      unmanaged_organizations: unmanagedOrganizations,
      audit_available: true,
    });
  }

  if (action === "create_organization") {
    const name = clean(body.name);
    const slug = clean(body.slug).toLowerCase();
    const plan = clean(body.plan) || "starter";
    const billingEmail = clean(body.billing_email).toLowerCase() || null;
    const maxMembersRaw = Number(body.max_members);
    const maxMembers = Number.isFinite(maxMembersRaw) && maxMembersRaw > 0
      ? Math.floor(maxMembersRaw)
      : null;

    if (!name) return json(400, { error: "missing_organization_name" });
    if (!/^[a-z0-9][a-z0-9-]{1,62}$/.test(slug)) {
      return json(400, { error: "invalid_organization_slug" });
    }
    if (!["starter", "professional", "enterprise"].includes(plan)) {
      return json(400, { error: "invalid_organization_plan" });
    }

    const rpcArguments = platformOrganizationCreationRPCArguments(actorId, {
      name,
      slug,
      plan,
      billingEmail,
      maxMembers,
    });
    const { data: createdRows, error: createError } = await admin
      .rpc("sd_platform_create_organization", rpcArguments);
    const organization = Array.isArray(createdRows) ? createdRows[0] : createdRows;
    if (createError || !organization) {
      return json(400, {
        error: createError?.code === "23505" ? "organization_slug_exists" : "organization_create_failed",
        message: createError?.message,
      });
    }

    await audit("create_organization", "organization", organization.id, organization.id, {
      name,
      slug,
      plan,
      max_members: maxMembers,
    });

    return json(200, {
      organization: {
        ...organization,
        active_members: 1,
        players: 0,
        coaches: 1,
        active_entitlements: 0,
        teams: 0,
      },
    });
  }

  if (action === "update_organization") {
    const orgId = clean(body.org_id);
    if (!orgId) return json(400, { error: "missing_org_id" });
    const patch: Record<string, unknown> = {};
    for (const key of ["name", "slug", "status", "plan", "billing_email", "max_members"]) {
      if (body[key] !== undefined) patch[key] = body[key];
    }
    const { data, error } = await admin.from("sd_orgs").update(patch).eq("id", orgId).select("id,slug,name,status,plan,billing_email,max_members").single();
    if (error) return json(400, { error: "organization_update_failed", message: error.message });
    await audit("update_organization", "organization", orgId, orgId, patch);
    return json(200, { organization: data });
  }

  if (action === "audit_log") {
    const { data, error } = await admin.from("sd_platform_audit_logs").select("id,action,target_type,target_id,org_id,details,created_at").order("created_at", { ascending: false }).limit(100);
    if (error) return json(500, { error: "audit_lookup_failed", message: error.message });
    return json(200, { entries: data ?? [] });
  }

  return json(400, { error: "unknown_action" });
});
