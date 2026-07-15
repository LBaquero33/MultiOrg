// Supabase Edge Function: org_admin
//
// Server-side organization administration for the multi-org facility app.
// Actions:
// - list_members
// - create_user
// - update_member
// - set_username
// - list_teams / create_team / update_team / assign_team_member / remove_team_member
// - get_player_access / set_player_access

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import {
  canAdministerOrganization,
  canOperateOrganization,
} from "../_shared/org_authorization.ts";

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

function humanNameFromEmail(x: unknown): string | null {
  const email = cleanEmail(x);
  if (!email) return null;
  const local = email.split("@")[0]
    .replace(/[._-]+/g, " ")
    .replace(/\d+$/g, "")
    .trim();
  if (!local) return null;
  return local
    .split(/\s+/)
    .map((part) => part.charAt(0).toUpperCase() + part.slice(1))
    .join(" ");
}

function cleanRole(x: unknown): "owner" | "admin" | "coach" | "player" | "parent" | null {
  const t = String(x ?? "").trim().toLowerCase();
  if (t === "owner" || t === "admin" || t === "coach" || t === "player" || t === "parent") return t;
  return null;
}

function cleanStatus(x: unknown): "active" | "invited" | "disabled" | "suspended" | null {
  const t = String(x ?? "").trim().toLowerCase();
  if (t === "active" || t === "invited" || t === "disabled" || t === "suspended") return t;
  return null;
}

function profileRoleForOrgRole(role: string): "coach" | "player" | "parent" {
  if (role === "owner" || role === "admin" || role === "coach") return "coach";
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
  const membership = callerMembership as { role?: string; status?: string } | null;
  const hasAdminAuthority = canAdministerOrganization(membership);
  if (!canOperateOrganization(membership)) return json(403, { error: "organization_membership_required" });

  const action = String(payload.action ?? "").trim();

  // Owners always manage team composition. Coaches can be given that ability
  // per organization; the default is view-only team access for coaches.
  const teamAction = ["create_team", "update_team", "assign_team_member", "remove_team_member"].includes(action);
  if (teamAction && !hasAdminAuthority) {
    const { data: settings, error: settingsErr } = await admin
      .from("sd_org_settings")
      .select("team_policy")
      .eq("org_id", orgId)
      .maybeSingle();
    if (settingsErr) return json(500, { error: "team_policy_lookup_failed", message: settingsErr.message });
    const teamPolicy = ((settings as any)?.team_policy ?? {}) as Record<string, unknown>;
    if (teamPolicy.coachesCanManageTeams !== true) {
      return json(403, { error: "coach_team_management_disabled" });
    }
  }

  // Member, account, and organization mutations are owner/admin-only. Staff retain
  // access to the read-only team board, and optionally team management when
  // that organization setting is explicitly enabled.
  if (!hasAdminAuthority && action !== "list_teams" && !teamAction) {
    return json(403, { error: "org_admin_required" });
  }

  if (action === "get_player_access" || action === "set_player_access") {
    let playerId: string;
    try {
      playerId = requireUuid(payload.player_id, "player_id");
    } catch (err) {
      return json(400, { error: (err as Error).message });
    }

    const { data: playerMembership, error: membershipErr } = await admin
      .from("sd_org_memberships")
      .select("user_id,role,status")
      .eq("org_id", orgId)
      .eq("user_id", playerId)
      .eq("role", "player")
      .maybeSingle();
    if (membershipErr) return json(500, { error: "player_membership_lookup_failed", message: membershipErr.message });
    if (!playerMembership) return json(404, { error: "player_not_in_organization" });

    if (action === "set_player_access") {
      const normalized = String(payload.is_active ?? "").trim().toLowerCase();
      if (!['true', 'false'].includes(normalized)) return json(400, { error: "invalid_access_state" });
      const isActive = normalized === "true";
      const { error: upsertErr } = await admin
        .from("sd_access_entitlements")
        .upsert({
          org_id: orgId,
          user_id: playerId,
          is_active: isActive,
          source: "org_admin_override",
        }, { onConflict: "user_id" });
      if (upsertErr) return json(500, { error: "player_access_update_failed", message: upsertErr.message });
    }

    const { data: entitlement, error: entitlementErr } = await admin
      .from("sd_access_entitlements")
      .select("org_id,user_id,is_active,source,updated_at")
      .eq("user_id", playerId)
      .maybeSingle();
    if (entitlementErr) return json(500, { error: "player_access_lookup_failed", message: entitlementErr.message });

    return json(200, {
      entitlement: entitlement ?? {
        org_id: orgId,
        user_id: playerId,
        is_active: false,
        source: null,
        updated_at: null,
      },
    });
  }

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
    const authNameByUserId = new Map<string, string | null>();

    await Promise.all(userIds.map(async (userId) => {
      const { data } = await admin.auth.admin.getUserById(userId);
      const user = (data as any)?.user;
      emailByUserId.set(userId, user?.email ?? null);
      authNameByUserId.set(userId, cleanText(user?.user_metadata?.full_name ?? user?.user_metadata?.name));
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
        full_name: profile.full_name ?? authNameByUserId.get(userId) ?? usernameByUserId.get(userId) ?? humanNameFromEmail(emailByUserId.get(userId)) ?? null,
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
    if (memberErr) {
      const lastOwnerRequired = memberErr.code === "23514"
        && memberErr.message.includes("last_active_owner_required");
      return json(lastOwnerRequired ? 409 : 500, {
        error: lastOwnerRequired ? "last_active_owner_required" : "membership_update_failed",
        message: memberErr.message,
      });
    }

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

  if (action === "list_teams") {
    const { data: teams, error: teamsErr } = await admin
      .from("sd_teams")
      .select("id,org_id,name,color_hex,description,is_active,sort_order,created_by,created_at,updated_at")
      .eq("org_id", orgId)
      .order("sort_order", { ascending: true })
      .order("name", { ascending: true });
    if (teamsErr) return json(500, { error: "teams_lookup_failed", message: teamsErr.message });
    const { data: members, error: membersErr } = await admin
      .from("sd_team_members")
      .select("org_id,team_id,player_id,assigned_by,assigned_at")
      .eq("org_id", orgId);
    if (membersErr) return json(500, { error: "team_members_lookup_failed", message: membersErr.message });

    // Return the eligible roster through the authorized edge layer. This keeps
    // the team board scoped to the organization and includes both players and
    // coaches, rather than relying on a global client-side profiles query.
    const { data: memberships, error: rosterMembershipErr } = await admin
      .from("sd_org_memberships")
      .select("user_id,role")
      .eq("org_id", orgId)
      .eq("status", "active")
      .in("role", ["owner", "admin", "coach", "player"]);
    if (rosterMembershipErr) return json(500, { error: "team_roster_lookup_failed", message: rosterMembershipErr.message });
    const rosterIds = Array.from(new Set((memberships ?? []).map((row: any) => String(row.user_id))));
    const { data: profiles, error: rosterProfilesErr } = await admin
      .from("profiles")
      .select("id,role,full_name,avatar_path")
      .in("id", rosterIds.length ? rosterIds : ["00000000-0000-0000-0000-000000000000"]);
    if (rosterProfilesErr) return json(500, { error: "team_roster_profiles_lookup_failed", message: rosterProfilesErr.message });
    const profileById = new Map((profiles ?? []).map((profile: any) => [String(profile.id), profile]));
    const { data: usernameRows } = await admin
      .from("sd_org_usernames")
      .select("username,user_id")
      .eq("org_id", orgId);
    const usernameByUserId = new Map((usernameRows ?? []).map((row: any) => [String(row.user_id), String(row.username)]));
    const resolvedNameById = new Map<string, string | null>();
    await Promise.all(rosterIds.map(async (userId) => {
      const profile = profileById.get(userId) ?? {};
      let resolvedName = cleanText(profile.full_name);
      if (!resolvedName) {
        const { data } = await admin.auth.admin.getUserById(userId);
        const user = (data as any)?.user;
        resolvedName = cleanText(user?.user_metadata?.full_name ?? user?.user_metadata?.name)
          ?? cleanText(usernameByUserId.get(userId))
          ?? humanNameFromEmail(user?.email);
        if (resolvedName) {
          await admin.from("profiles").upsert(
            { id: userId, role: profile.role ?? "player", full_name: resolvedName },
            { onConflict: "id" },
          );
        }
      }
      resolvedNameById.set(userId, resolvedName);
    }));
    const roster = (memberships ?? []).map((membership: any) => {
      const id = String(membership.user_id);
      const profile = profileById.get(id) ?? {};
      return {
        id,
        // Owners have staff privileges even if their legacy profile row says
        // player, so surface them as Coach in the board.
        role: membership.role === "player" ? "player" : "coach",
        full_name: resolvedNameById.get(id) ?? null,
        avatar_path: profile.avatar_path ?? null,
      };
    });
    return json(200, { teams: teams ?? [], members: members ?? [], roster });
  }

  if (action === "create_team" || action === "update_team") {
    const name = cleanText(payload.name);
    if (!name) return json(400, { error: "missing_team_name" });
    const patch = {
      org_id: orgId,
      name,
      color_hex: cleanText(payload.color_hex),
      description: cleanText(payload.description),
      is_active: payload.is_active !== false,
      sort_order: Number.isFinite(Number(payload.sort_order)) ? Number(payload.sort_order) : 0,
      created_by: callerId,
    };
    if (action === "create_team") {
      const { data, error } = await admin.from("sd_teams").insert(patch).select().single();
      if (error) return json(400, { error: "team_create_failed", message: error.message });
      return json(200, { team: data });
    }
    const teamId = cleanText(payload.team_id);
    if (!teamId) return json(400, { error: "missing_team_id" });
    const { data, error } = await admin.from("sd_teams").update(patch).eq("id", teamId).eq("org_id", orgId).select().single();
    if (error) return json(400, { error: "team_update_failed", message: error.message });
    return json(200, { team: data });
  }

  if (action === "assign_team_member") {
    const teamId = cleanText(payload.team_id);
    const memberId = cleanText(payload.member_id ?? payload.player_id);
    if (!teamId || !memberId) return json(400, { error: "missing_team_or_member" });
    const { data: team } = await admin.from("sd_teams").select("id").eq("id", teamId).eq("org_id", orgId).maybeSingle();
    if (!team) return json(404, { error: "team_not_found" });
    const { data: memberMembership } = await admin.from("sd_org_memberships").select("user_id").eq("org_id", orgId).eq("user_id", memberId).in("role", ["owner", "admin", "coach", "player"]).eq("status", "active").maybeSingle();
    if (!memberMembership) return json(400, { error: "member_not_in_organization" });
    const { error: deleteErr } = await admin.from("sd_team_members").delete().eq("org_id", orgId).eq("player_id", memberId);
    if (deleteErr) return json(500, { error: "team_assignment_clear_failed", message: deleteErr.message });
    const { error: insertErr } = await admin.from("sd_team_members").insert({ org_id: orgId, team_id: teamId, player_id: memberId, assigned_by: callerId });
    if (insertErr) return json(500, { error: "team_assignment_failed", message: insertErr.message });
    return json(200, { ok: true });
  }

  if (action === "remove_team_member") {
    const memberId = cleanText(payload.member_id ?? payload.player_id);
    if (!memberId) return json(400, { error: "missing_member_id" });
    const { error } = await admin.from("sd_team_members").delete().eq("org_id", orgId).eq("player_id", memberId);
    if (error) return json(500, { error: "team_assignment_remove_failed", message: error.message });
    return json(200, { ok: true });
  }

  return json(400, { error: "unknown_action" });
});
