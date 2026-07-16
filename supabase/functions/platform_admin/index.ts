// Server-authorized platform administration. Only users in sd_platform_admins
// can view or change data across organizations.
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { platformOrganizationCreationRPCArguments } from "../_shared/platform_admin_organization.ts";
import {
  canAccessPlatformAdministration,
  platformMembershipMutation,
} from "../_shared/platform_admin_permissions.ts";

type Json = Record<string, unknown>;
const json = (status: number, body: Json) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });
const env = (name: string) => (Deno.env.get(name) ?? "").trim();
const clean = (value: unknown) => String(value ?? "").trim();
const uuid = (value: unknown) =>
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
    .test(clean(value));

Deno.serve(async (req) => {
  if (req.method !== "POST") return json(405, { error: "method_not_allowed" });
  let body: any;
  try {
    body = await req.json();
  } catch {
    return json(400, { error: "invalid_json" });
  }

  const url = env("SUPABASE_URL") || env("DHD_SUPABASE_URL");
  const anon = env("SUPABASE_ANON_KEY") || env("DHD_SUPABASE_ANON_KEY");
  const service = env("DHD_SERVICE_ROLE_KEY") ||
    env("SUPABASE_SERVICE_ROLE_KEY");
  const authorization = req.headers.get("Authorization") ?? "";
  if (!url || !anon || !service || !authorization) {
    return json(500, { error: "missing_configuration" });
  }

  const userClient = createClient(url, anon, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: userData, error: userError } = await userClient.auth.getUser();
  const actorId = userData.user?.id;
  if (userError || !actorId) return json(401, { error: "invalid_auth" });

  const admin = createClient(url, service, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: grant } = await admin.from("sd_platform_admins").select(
    "user_id",
  ).eq("user_id", actorId).maybeSingle();
  if (!canAccessPlatformAdministration(userData.user?.email, Boolean(grant))) {
    return json(403, { error: "not_platform_admin" });
  }

  const audit = async (
    action: string,
    targetType: string,
    targetId: string | null,
    orgId: string | null,
    details: Json = {},
  ) => {
    const { data, error } = await admin.from("sd_platform_audit_logs")
      .insert({
        actor_id: actorId,
        action,
        target_type: targetType,
        target_id: targetId,
        org_id: orgId,
        details,
      })
      .select("id")
      .single();
    if (error || !data?.id) throw new Error("platform_audit_failed");
    return String(data.id);
  };
  const action = clean(body.action);

  const organizationMembers = async (orgId: string) => {
    const { data: organization, error: organizationError } = await admin
      .from("sd_orgs")
      .select("id,slug,name,status")
      .eq("id", orgId)
      .maybeSingle();
    if (organizationError) throw new Error("organization_lookup_failed");
    if (!organization) return null;
    const { data: memberships, error: membershipsError } = await admin
      .from("sd_org_memberships")
      .select("org_id,user_id,role,status,created_at,created_by")
      .eq("org_id", orgId)
      .order("created_at", { ascending: false });
    if (membershipsError) throw new Error("memberships_lookup_failed");
    const userIds = [
      ...new Set((memberships ?? []).map((row: any) => String(row.user_id))),
    ];
    const [
      { data: profiles, error: profilesError },
      { data: usernames, error: usernamesError },
    ] = await Promise.all([
      admin.from("profiles").select("id,full_name,role").in(
        "id",
        userIds.length ? userIds : ["00000000-0000-0000-0000-000000000000"],
      ),
      admin.from("sd_org_usernames").select("user_id,username").eq(
        "org_id",
        orgId,
      ),
    ]);
    if (profilesError || usernamesError) {
      throw new Error("member_identity_lookup_failed");
    }
    const profileById = new Map(
      (profiles ?? []).map((row: any) => [String(row.id), row]),
    );
    const usernameById = new Map(
      (usernames ?? []).map((
        row: any,
      ) => [String(row.user_id), String(row.username)]),
    );
    const authById = new Map<string, any>();
    await Promise.all(userIds.map(async (userId) => {
      const { data } = await admin.auth.admin.getUserById(userId);
      if ((data as any)?.user) authById.set(userId, (data as any).user);
    }));
    return {
      organization,
      members: (memberships ?? []).map((membership: any) => {
        const userId = String(membership.user_id);
        const profile = profileById.get(userId) ?? {};
        const authUser = authById.get(userId) ?? {};
        return {
          ...membership,
          full_name: profile.full_name ?? authUser.user_metadata?.full_name ??
            authUser.user_metadata?.name ?? null,
          username: usernameById.get(userId) ?? null,
          email: authUser.email ?? null,
          profile_role: profile.role ?? null,
          last_activity: authUser.last_sign_in_at ?? null,
        };
      }),
    };
  };

  if (action === "dashboard") {
    const [
      { data: orgs, error: orgError },
      { data: memberships, error: membershipsError },
      { data: entitlements, error: entitlementsError },
      { data: teams, error: teamsError },
    ] = await Promise.all([
      admin.from("sd_orgs").select(
        "id,slug,name,status,plan,billing_email,max_members,created_at",
      ).order("name"),
      admin.from("sd_org_memberships").select("org_id,role,status"),
      admin.from("sd_access_entitlements").select("org_id,is_active"),
      admin.from("sd_teams").select("org_id,id").eq("is_active", true),
    ]);
    if (orgError) {
      return json(500, {
        error: "orgs_lookup_failed",
        message: orgError.message,
      });
    }
    if (membershipsError) {
      return json(500, {
        error: "memberships_lookup_failed",
        message: membershipsError.message,
      });
    }
    if (entitlementsError) {
      return json(500, {
        error: "entitlements_lookup_failed",
        message: entitlementsError.message,
      });
    }
    if (teamsError) {
      return json(500, {
        error: "teams_lookup_failed",
        message: teamsError.message,
      });
    }
    const organizationRows = (orgs ?? []).map((org: any) => {
      const orgMembers = (memberships ?? []).filter((m: any) =>
        m.org_id === org.id && m.status === "active"
      );
      const orgEntitlements = (entitlements ?? []).filter((e: any) =>
        e.org_id === org.id
      );
      return {
        ...org,
        active_members: orgMembers.length,
        players: orgMembers.filter((m: any) => m.role === "player").length,
        coaches: orgMembers.filter((m: any) =>
          ["owner", "admin", "coach"].includes(m.role)
        ).length,
        active_entitlements: orgEntitlements.filter((e: any) =>
          e.is_active === true
        ).length,
        teams: (teams ?? []).filter((t: any) => t.org_id === org.id).length,
      };
    });
    const ownerlessOrganizations = organizationRows.filter((org: any) => {
      const activeOwners = (memberships ?? []).filter((membership: any) =>
        membership.org_id === org.id &&
        membership.status === "active" &&
        membership.role === "owner"
      );
      return activeOwners.length === 0;
    });
    const unmanagedOrganizations = organizationRows.filter((org: any) => {
      const activeAdministrators = (memberships ?? []).filter((
        membership: any,
      ) =>
        membership.org_id === org.id &&
        membership.status === "active" &&
        (membership.role === "owner" || membership.role === "admin")
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

  if (action === "list_members") {
    const orgId = clean(body.org_id).toLowerCase();
    if (!uuid(orgId)) return json(400, { error: "invalid_org_id" });
    try {
      const directory = await organizationMembers(orgId);
      return directory
        ? json(200, directory)
        : json(404, { error: "organization_not_found" });
    } catch (error) {
      return json(500, {
        error: clean((error as Error).message) || "members_lookup_failed",
      });
    }
  }

  if (action === "search_users") {
    const query = clean(body.query).toLowerCase();
    if (query.length < 2 || query.length > 100) {
      return json(400, { error: "invalid_search_query" });
    }
    const { data: usernameMatches, error: usernamesError } = await admin
      .from("sd_org_usernames")
      .select("user_id")
      .ilike("username", `%${query}%`)
      .limit(1_000);
    if (usernamesError) return json(500, { error: "user_lookup_failed" });
    const usernameMatchIds = new Set(
      (usernameMatches ?? []).map((row: any) => String(row.user_id)),
    );

    // The admin API does not expose a server-side email/name search. Page
    // through the complete authenticated directory so "global" never means
    // only the first page of accounts.
    const authUsers: any[] = [];
    const perPage = 200;
    for (let page = 1;; page += 1) {
      const { data, error } = await admin.auth.admin.listUsers({
        page,
        perPage,
      });
      if (error) return json(500, { error: "user_lookup_failed" });
      const pageUsers = data?.users ?? [];
      authUsers.push(...pageUsers);
      if (pageUsers.length < perPage) break;
    }
    const matchedUsers = authUsers.filter((user: any) => {
      const names = `${user.user_metadata?.full_name ?? ""} ${
        user.user_metadata?.name ?? ""
      }`.toLowerCase();
      return String(user.id).toLowerCase().includes(query) ||
        String(user.email ?? "").toLowerCase().includes(query) ||
        names.includes(query) ||
        usernameMatchIds.has(String(user.id));
    }).slice(0, 50);
    const matchedIds = matchedUsers.map((user: any) => String(user.id));
    const { data: usernames, error: matchedUsernamesError } = matchedIds.length
      ? await admin.from("sd_org_usernames")
        .select("user_id,username,org_id")
        .in("user_id", matchedIds)
        .limit(1_000)
      : { data: [], error: null };
    if (matchedUsernamesError) {
      return json(500, { error: "user_lookup_failed" });
    }
    const usernamesByUser = new Map<
      string,
      Array<{ username: string; org_id: string }>
    >();
    for (const row of usernames ?? []) {
      const userId = String((row as any).user_id);
      const values = usernamesByUser.get(userId) ?? [];
      values.push({
        username: String((row as any).username),
        org_id: String((row as any).org_id),
      });
      usernamesByUser.set(userId, values);
    }
    const users = matchedUsers.map((user: any) => ({
      user_id: user.id,
      email: user.email ?? null,
      full_name: user.user_metadata?.full_name ?? user.user_metadata?.name ??
        null,
      usernames: usernamesByUser.get(String(user.id)) ?? [],
      created_at: user.created_at ?? null,
      last_activity: user.last_sign_in_at ?? null,
    }));
    return json(200, { users });
  }

  if (action === "update_membership") {
    const orgId = clean(body.org_id).toLowerCase();
    const userId = clean(body.user_id).toLowerCase();
    const mutation = platformMembershipMutation(body as Json);
    if (!uuid(orgId) || !uuid(userId) || !mutation) {
      return json(400, { error: "invalid_membership_update" });
    }
    const { data: current, error: currentError } = await admin
      .from("sd_org_memberships")
      .select("org_id,user_id,role,status,created_at,created_by")
      .eq("org_id", orgId)
      .eq("user_id", userId)
      .maybeSingle();
    if (currentError) return json(500, { error: "membership_lookup_failed" });
    if (!current) return json(404, { error: "membership_not_found" });

    const { data: replay } = await admin.from("sd_platform_audit_logs")
      .select("id,details")
      .eq("actor_id", actorId)
      .eq("action", "update_membership")
      .eq("org_id", orgId)
      .eq("target_id", userId)
      .contains("details", {
        request_id: mutation.requestId,
        outcome: "succeeded",
      })
      .maybeSingle();
    if (replay) {
      return json(200, { membership: current, idempotent_replay: true });
    }
    if (current.role === mutation.role && current.status === mutation.status) {
      return json(200, { membership: current, idempotent_replay: true });
    }

    let auditId: string;
    const auditDetails = {
      request_id: mutation.requestId,
      previous_role: current.role,
      previous_status: current.status,
      new_role: mutation.role,
      new_status: mutation.status,
      reason: mutation.reason,
      outcome: "authorized_attempt",
    };
    try {
      // Authorization and audit recording occur before the service-role edit;
      // the database final-owner constraint remains the final invariant.
      auditId = await audit(
        "update_membership",
        "organization_membership",
        userId,
        orgId,
        auditDetails,
      );
    } catch {
      return json(500, { error: "platform_audit_failed" });
    }
    const { data: updated, error: updateError } = await admin
      .from("sd_org_memberships")
      .update({ role: mutation.role, status: mutation.status })
      .eq("org_id", orgId)
      .eq("user_id", userId)
      .select("org_id,user_id,role,status,created_at,created_by")
      .single();
    if (updateError) {
      await admin.from("sd_platform_audit_logs").update({
        details: { ...auditDetails, outcome: "rejected" },
      }).eq("id", auditId);
      const finalOwner = updateError.code === "23514" ||
        String(updateError.message).includes("last_active_owner_required");
      return json(finalOwner ? 409 : 500, {
        error: finalOwner
          ? "last_active_owner_required"
          : "membership_update_failed",
      });
    }
    await admin.from("sd_platform_audit_logs").update({
      details: { ...auditDetails, outcome: "succeeded" },
    }).eq("id", auditId);
    return json(200, { membership: updated, idempotent_replay: false });
  }

  if (action === "list_platform_admins") {
    const { data: grants, error } = await admin.from("sd_platform_admins")
      .select("user_id,granted_at,granted_by,notes")
      .order("granted_at", { ascending: true });
    if (error) return json(500, { error: "platform_admin_lookup_failed" });
    const administrators = await Promise.all(
      (grants ?? []).map(async (row: any) => {
        const { data } = await admin.auth.admin.getUserById(
          String(row.user_id),
        );
        const user = (data as any)?.user;
        return {
          ...row,
          email: user?.email ?? null,
          full_name: user?.user_metadata?.full_name ??
            user?.user_metadata?.name ?? null,
          last_activity: user?.last_sign_in_at ?? null,
        };
      }),
    );
    return json(200, { administrators });
  }

  if (action === "grant_platform_admin" || action === "revoke_platform_admin") {
    const userId = clean(body.user_id).toLowerCase();
    const requestId = clean(body.request_id).toLowerCase();
    const reason = clean(body.reason).slice(0, 500) || null;
    if (!uuid(userId) || !uuid(requestId)) {
      return json(400, { error: "invalid_platform_admin_update" });
    }
    if (action === "revoke_platform_admin" && userId === actorId) {
      return json(409, { error: "cannot_revoke_current_operator" });
    }
    const { data: target } = await admin.auth.admin.getUserById(userId);
    if (!(target as any)?.user) return json(404, { error: "user_not_found" });
    const { data: existingGrant, error: existingGrantError } = await admin
      .from("sd_platform_admins")
      .select("user_id")
      .eq("user_id", userId)
      .maybeSingle();
    if (existingGrantError) {
      return json(500, { error: "platform_admin_lookup_failed" });
    }
    const shouldBeGranted = action === "grant_platform_admin";
    if (Boolean(existingGrant) === shouldBeGranted) {
      return json(200, { ok: true, idempotent_replay: true });
    }
    const auditDetails = {
      request_id: requestId,
      reason,
      previous_granted: Boolean(existingGrant),
      new_granted: shouldBeGranted,
      outcome: "authorized_attempt",
    };
    let auditId: string;
    try {
      auditId = await audit(
        action,
        "platform_admin",
        userId,
        null,
        auditDetails,
      );
    } catch {
      return json(500, { error: "platform_audit_failed" });
    }
    const result = shouldBeGranted
      ? await admin.from("sd_platform_admins").upsert({
        user_id: userId,
        granted_by: actorId,
        notes: reason,
      }, { onConflict: "user_id" })
      : await admin.from("sd_platform_admins").delete().eq("user_id", userId);
    if (result.error) {
      await admin.from("sd_platform_audit_logs").update({
        details: { ...auditDetails, outcome: "rejected" },
      }).eq("id", auditId);
      return json(500, { error: "platform_admin_update_failed" });
    }
    await admin.from("sd_platform_audit_logs").update({
      details: { ...auditDetails, outcome: "succeeded" },
    }).eq("id", auditId);
    return json(200, { ok: true, idempotent_replay: false });
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
    const organization = Array.isArray(createdRows)
      ? createdRows[0]
      : createdRows;
    if (createError || !organization) {
      return json(400, {
        error: createError?.code === "23505"
          ? "organization_slug_exists"
          : "organization_create_failed",
        message: createError?.message,
      });
    }

    await audit(
      "create_organization",
      "organization",
      organization.id,
      organization.id,
      {
        name,
        slug,
        plan,
        max_members: maxMembers,
      },
    );

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
    for (
      const key of [
        "name",
        "slug",
        "status",
        "plan",
        "billing_email",
        "max_members",
      ]
    ) {
      if (body[key] !== undefined) patch[key] = body[key];
    }
    const { data, error } = await admin.from("sd_orgs").update(patch).eq(
      "id",
      orgId,
    ).select("id,slug,name,status,plan,billing_email,max_members").single();
    if (error) {
      return json(400, {
        error: "organization_update_failed",
        message: error.message,
      });
    }
    await audit("update_organization", "organization", orgId, orgId, patch);
    return json(200, { organization: data });
  }

  if (action === "audit_log") {
    const { data, error } = await admin.from("sd_platform_audit_logs").select(
      "id,actor_id,action,target_type,target_id,org_id,details,created_at",
    ).order("created_at", { ascending: false }).limit(100);
    if (error) {
      return json(500, {
        error: "audit_lookup_failed",
        message: error.message,
      });
    }
    return json(200, { entries: data ?? [] });
  }

  return json(400, { error: "unknown_action" });
});
