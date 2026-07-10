// Supabase Edge Function: promote_me
//
// Purpose:
// - Temporary bootstrap helper: promote the caller to role=coach if their email is allow-listed.
//
// Required secrets:
// - SUPABASE_URL
// - SUPABASE_SERVICE_ROLE_KEY
// - COACH_ALLOWLIST_EMAILS (comma-separated, lowercase)

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

type Json = Record<string, unknown>;

function json(status: number, body: Json) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });
}

function getEnv(name: string) {
  const v = Deno.env.get(name);
  return (v ?? "").trim();
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json(405, { error: "method_not_allowed" });

  const supabaseUrl = getEnv("SUPABASE_URL");
  const serviceKey = getEnv("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceKey) return json(500, { error: "missing_supabase_secrets" });

  const allow = (getEnv("COACH_ALLOWLIST_EMAILS") || "")
    .split(",")
    .map((x) => x.trim().toLowerCase())
    .filter(Boolean);
  if (allow.length == 0) return json(500, { error: "missing_allowlist" });

  const authHeader = req.headers.get("authorization") || "";
  const token = authHeader.toLowerCase().startsWith("bearer ") ? authHeader.slice(7).trim() : "";
  if (!token) return json(401, { error: "missing_auth" });

  const admin = createClient(supabaseUrl, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });
  const { data: userResp, error: userErr } = await admin.auth.getUser(token);
  if (userErr || !userResp?.user) return json(401, { error: "invalid_auth" });

  const email = String(userResp.user.email ?? "").toLowerCase();
  if (!email || !allow.includes(email)) return json(403, { error: "not_allowed" });

  const { error: updErr } = await admin
    .from("profiles")
    .update({ role: "coach" })
    .eq("id", userResp.user.id);
  if (updErr) return json(500, { error: "db_error", message: updErr.message });

  return json(200, { ok: true, role: "coach" });
});

