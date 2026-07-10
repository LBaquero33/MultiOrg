// Supabase Edge Function: org_login
//
// Purpose:
// - Enforce "Pick org → username + password" login flow for a multi-org app.
// - Username is org-scoped and maps to a real Supabase Auth email (password reset works normally).
// - Returns a Supabase Auth session (access_token + refresh_token) + active_org_id.
//
// Required secrets (Supabase project → Edge Functions → Secrets):
// - DHD_SERVICE_ROLE_KEY   (NEVER expose this to clients)
//
// Notes:
// - Supabase Edge Functions provide SUPABASE_URL and SUPABASE_ANON_KEY automatically.
// - Some tooling blocks setting secrets that start with SUPABASE_. For portability we
//   also support DHD_SUPABASE_URL / DHD_SUPABASE_ANON_KEY as optional overrides.
//
// DB assumptions:
// - public.sd_orgs(slug, id)
// - public.sd_org_usernames(org_id, username, user_id)  (no client access)
// - public.sd_org_memberships(org_id, user_id, status='active')

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

function normalizeSlug(x: unknown): string {
  return String(x ?? "").trim().toLowerCase();
}

function normalizeUsername(x: unknown): string {
  return String(x ?? "").trim().toLowerCase();
}

function normalizePassword(x: unknown): string {
  return String(x ?? "");
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json(405, { error: "method_not_allowed" });

  let payload: any;
  try {
    payload = await req.json();
  } catch {
    return json(400, { error: "invalid_json" });
  }

  const org_slug = normalizeSlug(payload.org_slug);
  const username = normalizeUsername(payload.username);
  const password = normalizePassword(payload.password);
  if (!org_slug || !username || !password) return json(400, { error: "missing_fields" });

  const supabaseUrl = getEnv("SUPABASE_URL") || getEnv("DHD_SUPABASE_URL");
  const anonKey = getEnv("SUPABASE_ANON_KEY") || getEnv("DHD_SUPABASE_ANON_KEY");
  const serviceKey = getEnv("DHD_SERVICE_ROLE_KEY") || getEnv("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !anonKey || !serviceKey) return json(500, { error: "missing_supabase_secrets" });

  const admin = createClient(supabaseUrl, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  // 1) Resolve org
  const { data: orgRow, error: orgErr } = await admin
    .from("sd_orgs")
    .select("id, slug, name")
    .eq("slug", org_slug)
    .maybeSingle();
  if (orgErr) return json(500, { error: "db_error", message: orgErr.message });
  if (!orgRow) return json(404, { error: "org_not_found" });

  // 2) Resolve username -> user_id (server-only table)
  const { data: uRow, error: uErr } = await admin
    .from("sd_org_usernames")
    .select("user_id")
    .eq("org_id", (orgRow as any).id)
    .eq("username", username)
    .maybeSingle();
  if (uErr) return json(500, { error: "db_error", message: uErr.message });
  const user_id = (uRow as any)?.user_id ?? null;
  if (!user_id) return json(401, { error: "invalid_login" });

  // 3) Ensure membership is active
  const { data: mRow, error: mErr } = await admin
    .from("sd_org_memberships")
    .select("role, status")
    .eq("org_id", (orgRow as any).id)
    .eq("user_id", user_id)
    .eq("status", "active")
    .maybeSingle();
  if (mErr) return json(500, { error: "db_error", message: mErr.message });
  if (!mRow) return json(403, { error: "no_org_access" });

  // 4) Fetch real email from Auth
  const { data: authUser, error: authErr } = await admin.auth.admin.getUserById(user_id);
  if (authErr) return json(500, { error: "auth_admin_get_failed", message: authErr.message });
  const email = (authUser as any)?.user?.email ?? null;
  if (!email) return json(500, { error: "missing_email" });

  // 5) Issue a normal session by signing in with email/password
  const publicClient = createClient(supabaseUrl, anonKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: sessionData, error: signInErr } = await publicClient.auth.signInWithPassword({
    email,
    password,
  });
  if (signInErr) return json(401, { error: "invalid_login" });

  const access_token = (sessionData as any)?.session?.access_token;
  const refresh_token = (sessionData as any)?.session?.refresh_token;
  if (!access_token || !refresh_token) return json(500, { error: "missing_tokens" });

  return json(200, {
    access_token,
    refresh_token,
    active_org_id: (orgRow as any).id,
    org: { id: (orgRow as any).id, slug: (orgRow as any).slug, name: (orgRow as any).name },
  });
});
