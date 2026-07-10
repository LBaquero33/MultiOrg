// Supabase Edge Function: org_admin
//
// Server-side organization administration for the multi-org facility app.
// Actions:
// - list_members
// - create_user
// - update_member
// - set_username

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

type Json = Record<string, unknown>;

function json(status: number, body: Json) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });
}

function getEnv(name: string) {
  return (Deno.env.get(name) ?? "").trim();
}

function cleanText(x: unknown): string | null {
  const t = String(x ?? "").trim();
  return t ? t : null;
}

function cleanEmail(x: unknown): string | null {
  const t = String(x ?? "").trim().toLowerCase();
  return t.includes("@") ? t : null;
}

function cleanUsername(x: unknown): string | null {
  const t = String(x ?? "").trim().toLowerCase();
  return /^[a-z0-9._-]{3,40}$/.test(t) ? t : null;
}

function cleanRole(x: unknown): "owner" | "coach" | "player" | "parent" | null {
  const t = String(x ?? "").trim().toLowerCase();
  if (t === "owner" || t === "coach" || t === "player" || t === "parent") return t;
  return null;
}

function cleanStatus(x: unknown): "active" | "invited" | "disabled" | null {
  const t = String(x ?? "").trim().toLowerCase();
  if (t === "active" || t === "invited" || t === "disabled") return t;
  return null;
}

function profileRoleForOrgRole(role: string): "coach" | "player" | "parent" {
  if (role === "owner" || role === "coach") return "coach";
  if (role === "parent") return "parent";
  return "player";
}

function requireUuid(x: unknown, name: string): string {
  const t = String(x ?? "").trim();
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(t)) {
    throw new Error(`missing_${name}`);
  }
  return t;
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json(405, { error: "method_not_allowed" });

  let payload: any;
  try {
    payload = await req.json();
  } catch {
    return json(400, { error: "invalid_json" });
  }

  const supabaseUrl = getEnv("SUPABASE_URL") || getEnv("DHD_SUPABASE_URL");
  const anonKey = getEnv("SUPABASE_ANON_KEY") || getEnv("DHD_SUPABASE_ANON_KEY");
  const serviceKey = getEnv("DHD_SERVICE_ROLE_KEY") || getEnv("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !anonKey || !serviceKey) return json(500, { error: "missing_supabase_secrets" });

  const authHeader = req.headers.get("Authorization") ?? "";
  const token = authHeader.replace(/^Bearer\s+/i, "").trim();
  if (!token) return json(401, { error: "missing_auth" });

  const publicClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: `Bearer ${token}` } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: callerData, error: callerErr } = await publicClient.auth.getUser(token);
  if (callerErr || !callerData.user?.id) return json(401, { error: "invalid_auth" });
  const callerId = callerData.user.id;

  const admin = createClient(supabaseUrl, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  let orgId: string;
  try {
    orgId = requireUuid(payload.org_id, "org_id");
  } catch (err) {
    return json(400, { error: (err as Error).message });
  }

  const { data: callerMembership, error: callerMembershipErr } = await admin
    .from("sd_org_memberships")
    .select("role,status")
    .eq("org_id", orgId)
    .eq("user_id", callerId)
    .eq("status", "active")
    .maybeSingle();
  if (callerMembershipErr) return json(500, { error: "caller_membership_lookup_failed", message: callerMembershipErr.message });
  const callerRole = String((callerMembership as any)?.role ?? "");
  if (callerRole !== "owner" && callerRole !== "coach") return json(403, { error: "not_org_admin" });

  const action = String(payload.action ?? "").trim();

  if (action === "list_members") {
    const { data: memberships, error: membersErr } = await admin
      .from("sd_org_memberships")
      .select("org_id,user_id,role,status,created_at,created_by")
      .eq("org_id", orgId)
      .order("created_at", { ascending: false });
    if (membersErr) return json(500, { error: "members_lookup_failed", message: membersErr.message });

    const userIds = Array.from(new Set((memberships ?? []).map((m: any) => String(m.user_id))));
    const { data: profiles, error: profilesErr } = await admin
      .from("profiles")
      .select("id,role,full_name,avatar_path")
      .in("id", userIds.length ? userIds : ["00000000-0000-0000-0000-000000000000"]);
    if (profilesErr) return json(500, { error: "profiles_lookup_failed", message: profilesErr.message });

    const { data: usernameRows, error: usernameErr } = await admin
      .from("sd_org_usernames")
      .select("username,user_id")
      .eq("org_id", orgId);
    if (usernameErr) return json(500, { error: "usernames_lookup_failed", message: usernameErr.message });

    const profileById = new Map((profiles ?? []).map((p: any) => [String(p.id), p]));
    const usernameByUserId = new Map((usernameRows ?? []).map((u: any) => [String(u.user_id), String(u.username)]));
    const emailByUserId = new Map<string, string | null>();

    await Promise.all(userIds.map(async (userId) => {
      const { data } = await admin.auth.admin.getUserById(userId);
      emailByUserId.set(userId, (data as any)?.user?.email ?? null);
    }));

    const members = (memberships ?? []).map((m: any) => {
      const userId = String(m.user_id);
      const profile = profileById.get(userId) ?? {};
      return {
        org_id: m.org_id,
        user_id: userId,
        role: m.role,
        status: m.status,
        created_at: m.created_at,
        created_by: m.created_by,
        username: usernameByUserId.get(userId) ?? null,
        email: emailByUserId.get(userId) ?? null,
        full_name: profile.full_name ?? null,
        profile_role: profile.role ?? null,
      };
    });

    return json(200, { members });
  }

  if (action === "create_user") {
    const email = cleanEmail(payload.email);
    const password = String(payload.password ?? "");
    const username = cleanUsername(payload.username);
    const fullName = cleanText(payload.full_name);
    const role = cleanRole(payload.role) ?? "player";

    if (!email) return json(400, { error: "invalid_email" });
    if (!username) return json(400, { error: "invalid_username" });
    if (password.length < 8) return json(400, { error: "password_too_short" });

    const { data: existingUsername, error: usernameLookupErr } = await admin
      .from("sd_org_usernames")
      .select("user_id")
      .eq("org_id", orgId)
      .eq("username", username)
      .maybeSingle();
    if (usernameLookupErr) return json(500, { error: "username_lookup_failed", message: usernameLookupErr.message });
    if ((existingUsername as any)?.user_id) return json(409, { error: "username_taken" });

    const profileRole = profileRoleForOrgRole(role);
    const { data: created, error: createErr } = await admin.auth.admin.createUser({
      email,
      password,
      email_confirm: true,
      user_metadata: { role: profileRole, full_name: fullName ?? "" },
    });
    if (createErr || !created.user?.id) {
      return json(500, { error: "auth_admin_create_failed", message: createErr?.message ?? "missing_user_id" });
    }
    const userId = created.user.id;

    const { error: profileErr } = await admin
      .from("profiles")
      .upsert({ id: userId, role: profileRole, full_name: fullName }, { onConflict: "id" });
    if (profileErr) return json(500, { error: "profile_upsert_failed", message: profileErr.message });

    const { error: memberErr } = await admin
      .from("sd_org_memberships")
      .upsert({
        org_id: orgId,
        user_id: userId,
        role,
        status: "active",
        created_by: callerId,
      }, { onConflict: "org_id,user_id" });
    if (memberErr) return json(500, { error: "membership_upsert_failed", message: memberErr.message });

    const { error: usernameErr } = await admin
      .from("sd_org_usernames")
      .upsert({
        org_id: orgId,
        username,
        user_id: userId,
        created_by: callerId,
      }, { onConflict: "org_id,username" });
    if (usernameErr) return json(500, { error: "username_upsert_failed", message: usernameErr.message });

    if (role === "player") {
      await admin.from("sd_access_entitlements").upsert({
        org_id: orgId,
        user_id: userId,
        is_active: true,
        source: "org_admin",
      }, { onConflict: "user_id" });

      const parentCode = crypto.randomUUID().slice(0, 8).toUpperCase();
      await admin.from("sd_parent_codes").upsert({
        org_id: orgId,
        child_id: userId,
        parent_code: parentCode,
      }, { onConflict: "child_id" });
    }

    return json(200, { user_id: userId });
  }

  if (action === "update_member") {
    let userId: string;
    try {
      userId = requireUuid(payload.user_id, "user_id");
    } catch (err) {
      return json(400, { error: (err as Error).message });
    }
    const role = cleanRole(payload.role);
    const status = cleanStatus(payload.status);
    if (!role && !status) return json(400, { error: "nothing_to_update" });

    const patch: Record<string, unknown> = {};
    if (role) patch.role = role;
    if (status) patch.status = status;

    const { error: memberErr } = await admin
      .from("sd_org_memberships")
      .update(patch)
      .eq("org_id", orgId)
      .eq("user_id", userId);
    if (memberErr) return json(500, { error: "membership_update_failed", message: memberErr.message });

    if (role) {
      const { error: profileErr } = await admin
        .from("profiles")
        .update({ role: profileRoleForOrgRole(role) })
        .eq("id", userId);
      if (profileErr) return json(500, { error: "profile_role_update_failed", message: profileErr.message });
    }

    return json(200, { ok: true });
  }

  if (action === "set_username") {
    let userId: string;
    try {
      userId = requireUuid(payload.user_id, "user_id");
    } catch (err) {
      return json(400, { error: (err as Error).message });
    }
    const username = cleanUsername(payload.username);
    if (!username) return json(400, { error: "invalid_username" });

    const { data: existingUsername, error: lookupErr } = await admin
      .from("sd_org_usernames")
      .select("user_id")
      .eq("org_id", orgId)
      .eq("username", username)
      .maybeSingle();
    if (lookupErr) return json(500, { error: "username_lookup_failed", message: lookupErr.message });
    if ((existingUsername as any)?.user_id && (existingUsername as any).user_id !== userId) {
      return json(409, { error: "username_taken" });
    }

    await admin.from("sd_org_usernames").delete().eq("org_id", orgId).eq("user_id", userId);
    const { error: upsertErr } = await admin
      .from("sd_org_usernames")
      .upsert({ org_id: orgId, username, user_id: userId, created_by: callerId }, { onConflict: "org_id,username" });
    if (upsertErr) return json(500, { error: "username_upsert_failed", message: upsertErr.message });

    return json(200, { ok: true });
  }

  return json(400, { error: "unknown_action" });
});

