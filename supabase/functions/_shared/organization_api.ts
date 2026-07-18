import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

export type Row = Record<string, unknown>;
export class ApiFailure extends Error {
  constructor(public status: number, public code: string, message = code) {
    super(message);
  }
}
export const text = (value: unknown) => String(value ?? "").trim();
export const record = (value: unknown): Row =>
  value && typeof value === "object" && !Array.isArray(value)
    ? value as Row
    : {};
const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
export const uuid = (value: unknown) =>
  uuidPattern.test(text(value)) ? text(value) : null;
export const json = (status: number, body: Row) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json; charset=utf-8" },
  });
export const ok = (body: Row) => json(200, { ok: true, ...body, error: null });
export const fail = (status: number, code: string, message = code) =>
  json(status, { ok: false, error: { code, message } });

export async function organizationContext(req: Request, payload: Row) {
  if (req.method !== "POST") throw new ApiFailure(405, "method_not_allowed");
  const url = text(
    Deno.env.get("SUPABASE_URL") ?? Deno.env.get("DHD_SUPABASE_URL"),
  );
  const anon = text(
    Deno.env.get("SUPABASE_ANON_KEY") ?? Deno.env.get("DHD_SUPABASE_ANON_KEY"),
  );
  const service = text(
    Deno.env.get("DHD_SERVICE_ROLE_KEY") ??
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY"),
  );
  if (!url || !anon || !service) {
    throw new ApiFailure(500, "missing_supabase_secrets");
  }
  const token = text(
    (req.headers.get("authorization") ?? "").replace(/^Bearer\s+/i, ""),
  );
  if (!token) throw new ApiFailure(401, "missing_auth");
  const callerClient = createClient(url, anon, {
    global: { headers: { Authorization: `Bearer ${token}` } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: userData, error: userError } = await callerClient.auth.getUser(
    token,
  );
  if (userError || !userData.user?.id) {
    throw new ApiFailure(401, "invalid_auth");
  }
  const organizationId = uuid(payload.organization_id);
  if (!organizationId) throw new ApiFailure(400, "missing_organization_id");
  const admin = createClient(url, service, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: membership, error } = await admin.from("sd_org_memberships")
    .select("role,status").eq("org_id", organizationId).eq(
      "user_id",
      userData.user.id,
    ).eq("status", "active").maybeSingle();
  if (error) throw new ApiFailure(500, "membership_lookup_failed");
  if (!membership) {
    throw new ApiFailure(403, "organization_membership_required");
  }
  const role = text((membership as Row).role).toLowerCase();
  const { data: resolved, error: capabilityError } = await admin.rpc(
    "sd_resolve_organization_capabilities",
    { target_organization: organizationId, target_actor: userData.user.id },
  );
  if (capabilityError) {
    throw new ApiFailure(500, "capability_resolution_failed");
  }
  const capabilities = new Set<string>(
    (resolved as unknown[] ?? []).map(String),
  );
  return {
    admin,
    callerId: userData.user.id,
    organizationId,
    role,
    capabilities,
    isAdmin: role === "owner" || role === "admin",
  };
}

export function requireAdmin(isAdmin: boolean, capability: string) {
  if (!isAdmin) throw new ApiFailure(403, `${capability}_required`);
}

export function requireCapability(
  capabilities: Set<string>,
  capability: string,
) {
  if (!capabilities.has(capability)) {
    throw new ApiFailure(403, `${capability}_required`);
  }
}

export function rpcFailure(
  error: { message?: string; code?: string } | null,
  fallback: string,
): never {
  const code = text(error?.message).split(" ")[0] || fallback;
  throw new ApiFailure(
    error?.code === "42501" ? 403 : error?.code === "P0002" ? 404 : 409,
    code,
  );
}
