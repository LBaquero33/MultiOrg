// Supabase Edge Function: legacy_login
//
// Purpose:
// - Allow users from the legacy Shiny `public.users` table (username + salted sha256 password_hash)
//   to sign in on iOS without shipping DB credentials.
// - On success, returns a Supabase Auth session (access_token + refresh_token) that the iOS app
//   can set via `supabase.auth.setSession(...)`.
//
// Required secrets (Supabase project → Edge Functions → Secrets):
// - SUPABASE_URL
// - SUPABASE_ANON_KEY (or a function-scoped key)
// - SUPABASE_SERVICE_ROLE_KEY   (NEVER expose this to clients)
// - LEGACY_PASSWORD_SALT        (must match the Shiny app's DHD_PASSWORD_SALT; if empty, legacy may fail)
//
// Optional:
// - LEGACY_EMAIL_DOMAIN (default: legacy.dhd.local)
// - LEGACY_AUTO_CREATE_EMAIL (default: true)

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

async function sha256Hex(input: string): Promise<string> {
  const data = new TextEncoder().encode(input);
  const hash = await crypto.subtle.digest("SHA-256", data);
  const bytes = new Uint8Array(hash);
  return Array.from(bytes)
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

function normalizeUsername(x: unknown): string {
  return String(x ?? "").trim();
}

function normalizePassword(x: unknown): string {
  return String(x ?? "");
}

function legacyEmailForUsername(username: string, domain: string): string {
  const safe = username
    .toLowerCase()
    .replace(/[^a-z0-9._-]+/g, "_")
    .replace(/^_+|_+$/g, "");
  return `${safe}@${domain}`;
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json(405, { error: "method_not_allowed" });

  let payload: any;
  try {
    payload = await req.json();
  } catch {
    return json(400, { error: "invalid_json" });
  }

  const username = normalizeUsername(payload.username);
  const password = normalizePassword(payload.password);
  if (!username || !password) return json(400, { error: "missing_username_or_password" });

  const supabaseUrl = getEnv("SUPABASE_URL");
  const anonKey = getEnv("SUPABASE_ANON_KEY");
  const serviceKey = getEnv("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !anonKey || !serviceKey) return json(500, { error: "missing_supabase_secrets" });

  const legacySalt = getEnv("LEGACY_PASSWORD_SALT");
  if (!legacySalt) {
    // We do NOT assume a default here because it can silently fail; return a clear error.
    return json(500, { error: "missing_legacy_password_salt" });
  }

  const admin = createClient(supabaseUrl, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  // 1) Check legacy credentials in public.users
  const passwordHash = await sha256Hex(`${legacySalt}::${password}`);
  const { data: legacyUser, error: legacyErr } = await admin
    .from("users")
    .select("id, username, role, player_full_name, is_locked, lock_reason")
    .ilike("username", username)
    .maybeSingle();

  if (legacyErr) return json(500, { error: "db_error", message: legacyErr.message });
  if (!legacyUser) return json(401, { error: "invalid_login" });

  if ((legacyUser as any).is_locked === 1) {
    return json(403, { error: "locked", reason: (legacyUser as any).lock_reason ?? "" });
  }

  // Pull the stored password_hash separately to avoid returning it accidentally.
  const { data: pwRow, error: pwErr } = await admin
    .from("users")
    .select("password_hash")
    .ilike("username", username)
    .maybeSingle();
  if (pwErr) return json(500, { error: "db_error", message: pwErr.message });
  const storedHash = String((pwRow as any)?.password_hash ?? "").trim();
  if (!storedHash || storedHash !== passwordHash) return json(401, { error: "invalid_login" });

  // 2) Ensure a mapping row exists
  const { data: mapRow, error: mapErr } = await admin
    .from("legacy_auth_links")
    .select("auth_user_id, legacy_username, legacy_user_id, email")
    .eq("legacy_username", username)
    .maybeSingle();
  if (mapErr) return json(500, { error: "db_error", message: mapErr.message });

  const domain = getEnv("LEGACY_EMAIL_DOMAIN") || "legacy.dhd.local";
  const email = (mapRow as any)?.email ?? legacyEmailForUsername(username, domain);

  // 3) Ensure a Supabase Auth user exists (admin create / get)
  let authUserId: string | null = (mapRow as any)?.auth_user_id ?? null;
  if (!authUserId) {
    const { data: created, error: createErr } = await admin.auth.admin.createUser({
      email,
      email_confirm: true,
      password,
      user_metadata: {
        legacy_username: username,
        legacy_user_id: (legacyUser as any).id,
        role: (legacyUser as any).role ?? "player",
        player_full_name: (legacyUser as any).player_full_name ?? "",
      },
    });
    if (createErr) return json(500, { error: "auth_admin_create_failed", message: createErr.message });
    authUserId = created.user?.id ?? null;
  } else {
    // Keep auth password aligned with legacy on first bridge login.
    // If the user later changes their password in Supabase, this update would overwrite it,
    // so only do it if the mapping row has never logged in before.
    const lastLogin = (mapRow as any)?.last_login_at ?? null;
    if (!lastLogin) {
      const { error: updErr } = await admin.auth.admin.updateUserById(authUserId, { password });
      if (updErr) return json(500, { error: "auth_admin_update_failed", message: updErr.message });
    }
  }
  if (!authUserId) return json(500, { error: "missing_auth_user_id" });

  // 4) Upsert linkage row
  const { error: upsertErr } = await admin
    .from("legacy_auth_links")
    .upsert(
      {
        legacy_username: username,
        legacy_user_id: (legacyUser as any).id,
        email,
        auth_user_id: authUserId,
        role: (legacyUser as any).role ?? "player",
        player_full_name: (legacyUser as any).player_full_name ?? null,
        last_login_at: new Date().toISOString(),
      },
      { onConflict: "legacy_username" },
    );
  if (upsertErr) return json(500, { error: "db_error", message: upsertErr.message });

  // 5) Issue a normal session by signing in with the email/password we just set.
  const publicClient = createClient(supabaseUrl, anonKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: sessionData, error: signInErr } = await publicClient.auth.signInWithPassword({
    email,
    password,
  });
  if (signInErr) return json(500, { error: "auth_signin_failed", message: signInErr.message });
  const access_token = (sessionData as any)?.session?.access_token;
  const refresh_token = (sessionData as any)?.session?.refresh_token;
  if (!access_token || !refresh_token) return json(500, { error: "missing_tokens" });

  return json(200, {
    access_token,
    refresh_token,
    user: {
      legacy_username: username,
      role: (legacyUser as any).role ?? "player",
      player_full_name: (legacyUser as any).player_full_name ?? "",
      email,
    },
  });
});
