import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { corsPreflight, jsonResponse } from "../_shared/cors.ts";

function env(name: string) {
  return (Deno.env.get(name) ?? "").trim();
}

function normalized(value: unknown) {
  return String(value ?? "").trim();
}

function slug(value: string) {
  return value.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "").slice(0, 48);
}

Deno.serve(async (request) => {
  const preflight = corsPreflight(request);
  if (preflight) return preflight;
  if (request.method !== "POST") return jsonResponse(405, { error: "method_not_allowed" });

  let body: Record<string, unknown>;
  try {
    body = await request.json();
  } catch {
    return jsonResponse(400, { error: "invalid_json" });
  }

  const email = normalized(body.email).toLowerCase();
  const password = String(body.password ?? "");
  const fullName = normalized(body.full_name);
  const organizationName = normalized(body.organization_name);
  const organizationSlug = slug(normalized(body.organization_slug) || organizationName);
  if (!email.includes("@") || password.length < 8 || fullName.length < 2 || organizationName.length < 2) {
    return jsonResponse(400, { error: "invalid_organization_account" });
  }
  if (organizationSlug.length < 3) return jsonResponse(400, { error: "invalid_organization_slug" });

  const supabaseUrl = env("SUPABASE_URL");
  const anonKey = env("SUPABASE_ANON_KEY");
  const serviceKey = env("DHD_SERVICE_ROLE_KEY") || env("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !anonKey || !serviceKey) {
    return jsonResponse(500, { error: "missing_supabase_configuration" });
  }

  const admin = createClient(supabaseUrl, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const publicClient = createClient(supabaseUrl, anonKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { data: created, error: createError } = await admin.auth.admin.createUser({
    email,
    password,
    email_confirm: true,
    user_metadata: { full_name: fullName },
  });
  if (createError || !created.user) {
    const message = createError?.message.toLowerCase() ?? "";
    return jsonResponse(message.includes("already") ? 409 : 400, {
      error: message.includes("already") ? "email_taken" : "account_creation_failed",
    });
  }

  const userId = created.user.id;
  let organizationCreated = false;
  try {
    const { error: profileError } = await admin.from("profiles").upsert({
      id: userId,
      full_name: fullName,
      role: "owner",
    });
    if (profileError) throw new Error("profile_creation_failed");

    const { data: orgId, error: organizationError } = await admin.rpc(
      "sd_create_owned_organization_for_actor",
      {
        p_actor_id: userId,
        p_name: organizationName,
        p_slug: organizationSlug,
        p_billing_email: email,
      },
    );
    if (organizationError || !orgId) {
      const message = organizationError?.message ?? "";
      throw new Error(message.includes("duplicate") ? "organization_slug_taken" : "organization_creation_failed");
    }
    organizationCreated = true;

    const { data: session, error: sessionError } = await publicClient.auth.signInWithPassword({ email, password });
    if (sessionError || !session.session) throw new Error("session_creation_failed");
    return jsonResponse(200, {
      access_token: session.session.access_token,
      refresh_token: session.session.refresh_token,
      org_id: orgId,
    });
  } catch (error) {
    // Once ownership is committed, keep the valid account and organization even
    // if the final convenience sign-in fails. The owner can sign in normally.
    if (!organizationCreated) await admin.auth.admin.deleteUser(userId);
    const code = error instanceof Error ? error.message : "organization_creation_failed";
    return jsonResponse(code === "organization_slug_taken" ? 409 : 500, { error: code });
  }
});
