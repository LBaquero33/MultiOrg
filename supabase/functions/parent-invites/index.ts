import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { corsPreflight, jsonResponse } from "../_shared/cors.ts";

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const EMAIL = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const text = (value: unknown, max = 300) =>
  typeof value === "string" ? value.trim().slice(0, max) : "";
const json = (status: number, body: Record<string, unknown>) =>
  jsonResponse(status, body);

function hex(bytes: Uint8Array) {
  return Array.from(bytes, (value) => value.toString(16).padStart(2, "0"))
    .join("");
}

async function digest(value: string) {
  return new Uint8Array(await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(value),
  ));
}

function byteaHex(value: unknown): string | null {
  const raw = text(value, 100);
  const match = /^(?:\\\\x|\\x)([0-9a-f]{64})$/i.exec(raw);
  return match?.[1]?.toLowerCase() ?? null;
}

function clients(authorization?: string) {
  const url = Deno.env.get("SUPABASE_URL")?.trim() ?? "";
  const anon = Deno.env.get("SUPABASE_ANON_KEY")?.trim() ?? "";
  const service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")?.trim() ?? "";
  if (!url || !anon || !service) throw new Error("server_not_configured");
  const admin = createClient(url, service, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const user = authorization
    ? createClient(url, anon, {
      global: { headers: { Authorization: authorization } },
      auth: { persistSession: false, autoRefreshToken: false },
    })
    : null;
  return { admin, user };
}

type UserClient = NonNullable<ReturnType<typeof clients>["user"]>;

async function authenticatedActor(req: Request, user: UserClient | null) {
  const authorization = req.headers.get("Authorization")?.trim() ?? "";
  if (!authorization || !user) throw new Error("authentication_required");
  const { data, error } = await user.auth.getUser();
  if (error || !data.user?.id || !UUID.test(data.user.id)) {
    throw new Error("authentication_required");
  }
  return { id: data.user.id.toLowerCase(), email: text(data.user.email, 254).toLowerCase() };
}

async function issue(req: Request, body: Record<string, unknown>) {
  const orgId = text(body.org_id, 36).toLowerCase();
  const childId = text(body.child_id, 36).toLowerCase();
  const email = text(body.email_norm, 254).toLowerCase();
  const relationship = text(body.relationship, 80);
  if (!UUID.test(orgId) || !UUID.test(childId) || !EMAIL.test(email)) {
    return json(400, { error: "invalid_parent_invite_request" });
  }
  const { admin, user } = clients(req.headers.get("Authorization") ?? undefined);
  const actor = await authenticatedActor(req, user);
  const allowed = await user!.rpc("sd_can_manage_player_development", {
    p_org_id: orgId,
    p_actor_id: actor.id,
  });
  if (allowed.error || allowed.data !== true) {
    return json(403, { error: "parent_invite_actor_not_authorized" });
  }

  const tokenBytes = crypto.getRandomValues(new Uint8Array(32));
  const token = hex(tokenBytes);
  const tokenHash = `\\x${hex(await digest(token))}`;
  const expiresAt = new Date(Date.now() + 7 * 24 * 60 * 60 * 1000).toISOString();
  const issued = await admin.rpc("sd_issue_parent_invite", {
    p_org_id: orgId,
    p_child_id: childId,
    p_email_norm: email,
    p_relationship: relationship || null,
    p_invited_by: actor.id,
    p_token_hash: tokenHash,
    p_expires_at: expiresAt,
  });
  const inviteId = String(issued.data ?? "").toLowerCase();
  if (issued.error || !UUID.test(inviteId)) {
    return json(400, { error: "parent_invite_issue_failed" });
  }

  const apiKey = Deno.env.get("RESEND_API_KEY")?.trim() ?? "";
  const from = Deno.env.get("HOME_PLATE_ACCOUNTS_FROM_EMAIL")?.trim() ||
    "Home Plate Accounts <accounts@homeplateapps.com>";
  if (!apiKey) {
    await admin.from("sd_parent_invites").delete().eq("id", inviteId);
    return json(503, { error: "parent_invite_delivery_unavailable" });
  }
  const deepLink = `homeplate://parent-invite/${inviteId}?token=${token}`;
  const delivery = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      authorization: `Bearer ${apiKey}`,
      "content-type": "application/json",
      "idempotency-key": `parent-invite-${inviteId}`,
    },
    body: JSON.stringify({
      from,
      to: [email],
      subject: "You have a Home Plate parent invitation",
      text: `A Home Plate organization invited you to connect to a player account. Open this link in Home Plate to review and accept: ${deepLink}\n\nThis link expires in 7 days and can only be used by ${email}.`,
    }),
  }).catch(() => null);
  if (!delivery?.ok) {
    await admin.from("sd_parent_invites").delete().eq("id", inviteId);
    return json(503, { error: "parent_invite_delivery_failed" });
  }
  return json(200, { invite_id: inviteId, delivery: "email", expires_at: expiresAt });
}

async function preview(body: Record<string, unknown>) {
  const inviteId = text(body.invite_id, 36).toLowerCase();
  const token = text(body.token, 128).toLowerCase();
  if (!UUID.test(inviteId) || !/^[0-9a-f]{64}$/.test(token)) {
    return json(404, { error: "parent_invite_invalid_or_expired" });
  }
  const { admin } = clients();
  const { data: invite, error } = await admin.from("sd_parent_invites")
    .select("id,org_id,child_id,email_norm,relationship,accepted_at,parent_id,acceptance_token_hash,acceptance_token_expires_at")
    .eq("id", inviteId).maybeSingle();
  const expectedHash = hex(await digest(token));
  const savedHash = byteaHex(invite?.acceptance_token_hash);
  if (
    error || !invite || invite.accepted_at || invite.parent_id ||
    !invite.org_id || !savedHash || savedHash !== expectedHash ||
    !invite.acceptance_token_expires_at ||
    Date.parse(invite.acceptance_token_expires_at) <= Date.now()
  ) return json(404, { error: "parent_invite_invalid_or_expired" });

  const [org, child] = await Promise.all([
    admin.from("sd_orgs").select("name").eq("id", invite.org_id).maybeSingle(),
    admin.from("profiles").select("full_name").eq("id", invite.child_id).maybeSingle(),
  ]);
  if (org.error || child.error || !org.data || !child.data) {
    return json(404, { error: "parent_invite_invalid_or_expired" });
  }
  return json(200, {
    valid: true,
    org_id: invite.org_id,
    organization_name: org.data.name,
    child_id: invite.child_id,
    child_name: child.data.full_name,
    relationship: invite.relationship,
    expires_at: invite.acceptance_token_expires_at,
  });
}

async function list(req: Request, body: Record<string, unknown>) {
  const orgId = text(body.org_id, 36).toLowerCase();
  if (!UUID.test(orgId)) return json(400, { error: "invalid_parent_invite_request" });
  const { admin, user } = clients(req.headers.get("Authorization") ?? undefined);
  const actor = await authenticatedActor(req, user);
  const allowed = await user!.rpc("sd_can_manage_player_development", {
    p_org_id: orgId,
    p_actor_id: actor.id,
  });
  if (allowed.error || allowed.data !== true) {
    return json(403, { error: "parent_invite_actor_not_authorized" });
  }
  const { data, error } = await admin.from("sd_parent_invites")
    .select("id,org_id,child_id,email_norm,relationship,accepted_at,acceptance_token_expires_at")
    .eq("org_id", orgId).order("created_at", { ascending: false }).limit(500);
  if (error) return json(500, { error: "parent_invite_list_failed" });
  return json(200, {
    invites: (data ?? []).map((invite) => ({
      invite_id: invite.id,
      org_id: invite.org_id,
      child_id: invite.child_id,
      email_norm: invite.email_norm,
      relationship: invite.relationship,
      accepted_at: invite.accepted_at,
      expires_at: invite.acceptance_token_expires_at,
    })),
  });
}

async function accept(req: Request, body: Record<string, unknown>) {
  const inviteId = text(body.invite_id, 36).toLowerCase();
  const token = text(body.token, 128).toLowerCase();
  if (!UUID.test(inviteId) || !/^[0-9a-f]{64}$/.test(token)) {
    return json(404, { error: "parent_invite_invalid_or_expired" });
  }
  const { user } = clients(req.headers.get("Authorization") ?? undefined);
  await authenticatedActor(req, user);
  const result = await user!.rpc("sd_accept_parent_invite", {
    p_invite_id: inviteId,
    p_token: token,
  });
  if (result.error) return json(404, { error: "parent_invite_invalid_or_expired" });
  const accepted = Array.isArray(result.data) ? result.data[0] : result.data;
  return json(200, {
    accepted: true,
    org_id: accepted.org_id,
    child_id: accepted.child_id,
  });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return corsPreflight(req)!;
  if (req.method !== "POST") return json(405, { error: "method_not_allowed" });
  try {
    let body: Record<string, unknown>;
    try {
      body = await req.json();
    } catch {
      return json(400, { error: "invalid_request" });
    }
    const action = text(body.action, 32);
    if (action === "issue") return await issue(req, body);
    if (action === "list") return await list(req, body);
    if (action === "preview") return await preview(body);
    if (action === "accept") return await accept(req, body);
    return json(400, { error: "unsupported_action" });
  } catch (error) {
    const message = error instanceof Error ? error.message : "request_failed";
    if (message === "authentication_required") return json(401, { error: message });
    console.error(JSON.stringify({ event: "parent_invite_request_failed", code: message }));
    return json(500, { error: "parent_invite_request_failed" });
  }
});
