// Supabase Edge Function: create_account
//
// Purpose:
// - Create (or sign in) a Supabase Auth user using email+password without requiring email confirmation.
// - Return an Auth session (access_token + refresh_token) so the iOS app can call `auth.setSession(...)`.
// - Upsert `public.profiles` with a default role and optional full_name.
//
// Required secrets (Supabase project → Edge Functions → Secrets):
// - DHD_SERVICE_ROLE_KEY   (NEVER expose this to clients)
//
// Notes:
// - Edge Functions provide SUPABASE_URL / SUPABASE_ANON_KEY automatically.
// - We also support DHD_SUPABASE_URL / DHD_SUPABASE_ANON_KEY as optional overrides.

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

function normalizeEmail(x: unknown): string {
  return String(x ?? "").trim().toLowerCase();
}

function normalizePassword(x: unknown): string {
  return String(x ?? "");
}

function normalizeText(x: unknown): string | null {
  const t = String(x ?? "").trim();
  return t ? t : null;
}

function normalizeSlug(x: unknown): string | null {
  const t = String(x ?? "").trim().toLowerCase();
  return t ? t : null;
}

function normalizeUsername(x: unknown): string | null {
  const t = String(x ?? "").trim().toLowerCase();
  return t ? t : null;
}

async function sha256(value: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(value),
  );
  return [...new Uint8Array(digest)].map((item) =>
    item.toString(16).padStart(2, "0")
  ).join("");
}

function normalizeAccountType(
  x: unknown,
): "player" | "parent" | "coach" | null {
  const t = String(x ?? "").trim().toLowerCase();
  if (!t) return null;
  if (t === "player") return "player";
  if (t === "parent") return "parent";
  if (t === "coach") return "coach";
  // Back-compat: some callers used `role`.
  if (t === "coaches") return "coach";
  if (t === "players") return "player";
  return null;
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json(405, { error: "method_not_allowed" });

  let payload: any;
  try {
    payload = await req.json();
  } catch {
    return json(400, { error: "invalid_json" });
  }

  const email = normalizeEmail(payload.email);
  const password = normalizePassword(payload.password);
  const org_slug = normalizeSlug(payload.org_slug);
  const username = normalizeUsername(payload.username);
  // `account_type` is what the client should send.
  // `role` is supported only for backward compatibility, but the server still enforces restrictions.
  const accountType = normalizeAccountType(payload.account_type) ??
    normalizeAccountType(payload.role) ?? null;

  let role = normalizeText(payload.role);
  const full_name = normalizeText(payload.full_name);
  const parent_code = normalizeText(payload.parent_code);
  const relationship = normalizeText(payload.relationship);
  const coach_code = normalizeText(payload.coach_code);
  const invitation_token = normalizeText(payload.invitation_token);

  if (!email || !password) {
    return json(400, { error: "missing_email_or_password" });
  }
  if (!org_slug) return json(400, { error: "missing_org_slug" });
  if (!username) return json(400, { error: "missing_username" });

  const supabaseUrl = getEnv("SUPABASE_URL") || getEnv("DHD_SUPABASE_URL");
  const anonKey = getEnv("SUPABASE_ANON_KEY") ||
    getEnv("DHD_SUPABASE_ANON_KEY");
  const serviceKey = getEnv("DHD_SERVICE_ROLE_KEY") ||
    getEnv("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !anonKey || !serviceKey) {
    return json(500, { error: "missing_supabase_secrets" });
  }

  const admin = createClient(supabaseUrl, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  let setupInvitation: Record<string, any> | null = null;
  if (invitation_token) {
    const { data, error } = await admin.from("sd_organization_invitation_links")
      .select(
        "id,organization_id,invitation_context,intended_role,expires_at,revoked_at",
      )
      .eq("token_hash", await sha256(invitation_token)).maybeSingle();
    if (error) return json(500, { error: "invitation_lookup_failed" });
    if (!data || data.revoked_at || new Date(data.expires_at) <= new Date()) {
      return json(410, { error: "invitation_expired" });
    }
    setupInvitation = data;
  }

  const { data: orgRow, error: orgErr } = await admin
    .from("sd_orgs")
    .select("id, slug, name")
    // Imported organizations may store uppercase slugs (for example "MRST"),
    // while client input is normalized. Keep account creation consistent with login.
    .ilike("slug", org_slug)
    .maybeSingle();
  if (orgErr) {
    return json(500, { error: "org_lookup_failed", message: orgErr.message });
  }
  if (!orgRow?.id) return json(404, { error: "org_not_found" });
  if (setupInvitation && setupInvitation.organization_id !== orgRow.id) {
    return json(403, { error: "invitation_organization_mismatch" });
  }

  // Optional: validate parent_code early so we don't create a user account that can't be linked.
  let parentChildId: string | null = null;
  if (accountType === "parent") {
    if (setupInvitation?.intended_role === "parent") {
      parentChildId = null;
    } else {
      if (!parent_code) return json(400, { error: "missing_parent_code" });
      const { data: pc, error: pcErr } = await admin
        .from("sd_parent_codes")
        .select("child_id")
        .eq("parent_code", parent_code)
        .limit(1)
        .maybeSingle();
      if (pcErr) {
        return json(500, {
          error: "parent_code_lookup_failed",
          message: pcErr.message,
        });
      }
      parentChildId = pc?.child_id ?? null;
      if (!parentChildId) return json(400, { error: "invalid_parent_code" });
    }
  }

  // Auto-role selection:
  // - If the client explicitly provides a role, respect it.
  // - Otherwise, if this email has pending parent invites, default to "parent".
  // - Else default to "player".
  //
  // IMPORTANT SECURITY RULES:
  // - Clients are NEVER allowed to self-escalate to "coach" by passing role.
  // - "coach" is only allowed if a server-side COACH_SIGNUP_CODE secret matches.
  // - "parent" is allowed (it does not grant coach powers).
  if (!role) {
    const legacy = email.endsWith("@legacy.dhd.local");
    if (legacy) {
      role = "player";
    } else {
      try {
        const { data: invites } = await admin
          .from("sd_parent_invites")
          .select("id")
          .eq("email_norm", email)
          .is("accepted_at", null)
          .limit(1);
        role = invites && invites.length > 0 ? "parent" : "player";
      } catch {
        role = "player";
      }
    }
  }

  // If the UI provided an explicit account type, it overrides role (within security constraints).
  if (accountType === "player") role = "player";
  if (accountType === "parent") role = "parent";
  if (accountType === "coach") {
    if (setupInvitation?.intended_role !== "coach") {
      const expected = getEnv("COACH_SIGNUP_CODE");
      if (!expected) return json(403, { error: "coach_signup_disabled" });
      if (!coach_code || coach_code !== expected) {
        return json(403, { error: "coach_invite_required" });
      }
    }
    role = "coach";
  }
  if (setupInvitation && setupInvitation.intended_role !== role) {
    return json(403, { error: "invitation_role_mismatch" });
  }

  // Final clamp: never allow coach unless accountType=coach and code validated above.
  if (role?.toLowerCase() === "coach" && accountType !== "coach") {
    role = "player";
  }

  // Try to create the user (email_confirm=true avoids the "confirm your email" trap for username-style accounts).
  // If the user already exists, we still proceed to sign in with password.
  let userId: string | null = null;
  const { data: created, error: createErr } = await admin.auth.admin.createUser(
    {
      email,
      password,
      email_confirm: true,
      user_metadata: {
        role,
        full_name: full_name ?? "",
      },
    },
  );

  if (createErr) {
    const msg = (createErr.message ?? "").toLowerCase();
    const alreadyExists = msg.includes("already registered") ||
      msg.includes("already exists") ||
      msg.includes("user already") ||
      msg.includes("duplicate");
    if (!alreadyExists) {
      return json(500, {
        error: "auth_admin_create_failed",
        message: createErr.message,
      });
    }
  } else {
    userId = created.user?.id ?? null;
  }

  // Issue a normal session by signing in with the provided email/password.
  const publicClient = createClient(supabaseUrl, anonKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: sessionData, error: signInErr } = await publicClient.auth
    .signInWithPassword({ email, password });
  if (signInErr) {
    return json(401, { error: "invalid_login", message: signInErr.message });
  }

  const session = (sessionData as any)?.session ?? null;
  const access_token = session?.access_token;
  const refresh_token = session?.refresh_token;
  const authedUserId = session?.user?.id ?? null;
  if (!access_token || !refresh_token || !authedUserId) {
    return json(500, { error: "missing_tokens" });
  }

  userId = userId ?? authedUserId;

  // Prevent two users from claiming the same username inside the same org.
  const { data: existingUsername, error: usernameErr } = await admin
    .from("sd_org_usernames")
    .select("user_id")
    .eq("org_id", orgRow.id)
    .eq("username", username)
    .maybeSingle();
  if (usernameErr) {
    return json(500, {
      error: "username_lookup_failed",
      message: usernameErr.message,
    });
  }
  if (existingUsername?.user_id && existingUsername.user_id !== userId) {
    return json(409, { error: "username_taken" });
  }

  // Upsert profile.
  const { error: profErr } = await admin
    .from("profiles")
    .upsert({ id: userId, role, full_name }, { onConflict: "id" });
  if (profErr) {
    return json(500, {
      error: "profile_upsert_failed",
      message: profErr.message,
    });
  }

  const { error: membershipErr } = await admin
    .from("sd_org_memberships")
    .upsert(
      {
        org_id: orgRow.id,
        user_id: userId,
        role,
        status: setupInvitation ? "invited" : "active",
      },
      { onConflict: "org_id,user_id" },
    );
  if (membershipErr) {
    return json(500, {
      error: "membership_upsert_failed",
      message: membershipErr.message,
    });
  }

  const { error: usernameUpsertErr } = await admin
    .from("sd_org_usernames")
    .upsert(
      {
        org_id: orgRow.id,
        username,
        user_id: userId,
      },
      { onConflict: "org_id,username" },
    );
  if (usernameUpsertErr) {
    return json(500, {
      error: "username_upsert_failed",
      message: usernameUpsertErr.message,
    });
  }

  // Ensure every player has a parent code (for parent signup linking).
  // We generate this server-side and store it in `sd_parent_codes` (RLS-protected).
  if (role === "player") {
    const { error: entErr } = await admin
      .from("sd_access_entitlements")
      .upsert(
        {
          user_id: userId,
          is_active: false,
          source: "stripe",
        },
        { onConflict: "user_id" },
      );
    if (entErr) {
      return json(500, {
        error: "entitlement_seed_failed",
        message: entErr.message,
      });
    }

    try {
      const { data: existing } = await admin
        .from("sd_parent_codes")
        .select("child_id")
        .eq("child_id", userId)
        .limit(1);
      if (!existing || existing.length === 0) {
        const { data: gen, error: genErr } = await admin
          .rpc("sd_generate_parent_code", { size: 8 });
        if (genErr) {
          // Best-effort: don't block account creation if the DB hasn't been migrated yet.
          // (We can backfill codes later via SQL migration.)
          console.warn("parent_code_generate_failed", genErr.message);
          // Skip code creation.
          throw genErr;
        }
        const parent_code = String(gen ?? "").trim();
        if (parent_code) {
          const { error: insErr } = await admin
            .from("sd_parent_codes")
            .insert({ child_id: userId, parent_code })
            .select("child_id")
            .limit(1);
          if (insErr) {
            console.warn("parent_code_insert_failed", insErr.message);
          }
        }
      }
    } catch {
      // Best-effort; do not block account creation if codes table isn't installed yet.
    }
  }

  // If parent_code was provided (accountType=parent), create the parent-child link.
  if (role === "parent" && parentChildId) {
    const { error: linkErr } = await admin
      .from("sd_parent_child_links")
      .upsert(
        {
          parent_id: userId,
          child_id: parentChildId,
          relationship: relationship ?? null,
          can_book: true,
          can_pay: true,
          created_by: null,
        },
        { onConflict: "parent_id,child_id" },
      );
    if (linkErr) {
      return json(500, {
        error: "parent_link_failed",
        message: linkErr.message,
      });
    }
  }

  return json(200, {
    access_token,
    refresh_token,
    user: { id: userId, email, role, full_name, org_id: orgRow.id, username },
  });
});
