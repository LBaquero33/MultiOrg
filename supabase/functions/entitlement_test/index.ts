// Supabase Edge Function: entitlement_test
//
// Purpose (DEV ONLY):
// - Provide an in-app "test event" button without involving Stripe or real money.
// - Flips `public.sd_access_entitlements.is_active` for a target user.
//
// Security:
// - Requires a valid Supabase JWT (default Edge Functions JWT verification).
// - Requires caller role = coach (checks `public.profiles.role`).
// - Must be explicitly enabled via secret `ENABLE_ENTITLEMENT_TEST=1`.
//
// Required secrets:
// - DHD_SERVICE_ROLE_KEY
// - ENABLE_ENTITLEMENT_TEST (set to "1" to enable)
//
// Notes:
// - Edge Functions provide SUPABASE_URL automatically.
// - We also support DHD_SUPABASE_URL as an override.
//
// Request body:
// - { "user_id": "<uuid>", "is_active": true|false }

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

function getBearerToken(req: Request): string | null {
  const h = req.headers.get("Authorization") ?? "";
  if (!h.toLowerCase().startsWith("bearer ")) return null;
  const t = h.slice(7).trim();
  return t || null;
}

function decodeJwtSub(token: string): string | null {
  // JWT: header.payload.signature (base64url)
  const parts = token.split(".");
  if (parts.length < 2) return null;
  try {
    const b64 = parts[1].replace(/-/g, "+").replace(/_/g, "/");
    const padded = b64 + "=".repeat((4 - (b64.length % 4)) % 4);
    const payload = JSON.parse(atob(padded));
    const sub = String(payload?.sub ?? "").trim();
    return sub || null;
  } catch {
    return null;
  }
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { status: 204 });
  if (req.method !== "POST") return json(405, { error: "method_not_allowed" });

  const enabled = getEnv("ENABLE_ENTITLEMENT_TEST");
  if (!["1", "true", "yes", "on"].includes(enabled.toLowerCase())) {
    return json(404, { error: "not_enabled" });
  }

  const supabaseUrl = getEnv("SUPABASE_URL") || getEnv("DHD_SUPABASE_URL");
  const serviceKey = getEnv("DHD_SERVICE_ROLE_KEY") || getEnv("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceKey) return json(500, { error: "missing_required_secrets" });

  const token = getBearerToken(req);
  if (!token) return json(401, { error: "missing_auth" });
  const callerSub = decodeJwtSub(token);
  if (!callerSub) return json(401, { error: "invalid_auth" });

  let body: any;
  try {
    body = await req.json();
  } catch {
    return json(400, { error: "invalid_json" });
  }

  const userId = String(body?.user_id ?? "").trim();
  const isActive = body?.is_active;
  if (!userId) return json(400, { error: "missing_user_id" });
  if (typeof isActive !== "boolean") return json(400, { error: "missing_is_active" });

  const admin = createClient(supabaseUrl, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  // Confirm caller is a coach.
  const { data: prof, error: profErr } = await admin
    .from("profiles")
    .select("role")
    .eq("id", callerSub)
    .maybeSingle();
  if (profErr) return json(500, { error: "profile_lookup_failed" });
  if ((prof?.role ?? "") !== "coach") return json(403, { error: "forbidden" });

  const nowIso = new Date().toISOString();
  const payload = {
    user_id: userId,
    is_active: isActive,
    source: "entitlement_test",
    updated_at: nowIso,
  };

  const { error: upErr } = await admin
    .from("sd_access_entitlements")
    .upsert(payload, { onConflict: "user_id" });
  if (upErr) return json(500, { error: "entitlement_upsert_failed" });

  return json(200, { ok: true, user_id: userId, is_active: isActive });
});
