import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { corsPreflight, jsonResponse } from "../_shared/cors.ts";

function env(name: string) {
  return (Deno.env.get(name) ?? "").trim();
}

Deno.serve(async (request) => {
  const preflight = corsPreflight(request);
  if (preflight) return preflight;
  if (request.method !== "POST") return jsonResponse(405, { error: "method_not_allowed" });

  const authorization = request.headers.get("Authorization") ?? "";
  if (!authorization.startsWith("Bearer ")) return jsonResponse(401, { error: "authentication_required" });

  let body: Record<string, unknown>;
  try {
    body = await request.json();
  } catch {
    return jsonResponse(400, { error: "invalid_json" });
  }
  if (body.confirmation !== "DELETE") return jsonResponse(400, { error: "deletion_confirmation_required" });

  const supabaseUrl = env("SUPABASE_URL");
  const anonKey = env("SUPABASE_ANON_KEY");
  const serviceKey = env("DHD_SERVICE_ROLE_KEY") || env("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !anonKey || !serviceKey) {
    return jsonResponse(500, { error: "missing_supabase_configuration" });
  }

  const actorClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: actor, error: actorError } = await actorClient.auth.getUser();
  if (actorError || !actor.user) return jsonResponse(401, { error: "authentication_required" });

  const admin = createClient(supabaseUrl, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { error: deletionError } = await admin.auth.admin.deleteUser(actor.user.id);
  if (deletionError) return jsonResponse(500, { error: "account_deletion_failed" });

  return jsonResponse(200, { deleted: true });
});
