import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import {
  isConfiguredServiceRequest,
  processStorageCleanupClaims,
  type StorageCleanupClaim,
} from "../_shared/account_deletion_storage.ts";
import { jsonResponse } from "../_shared/cors.ts";

function env(name: string) {
  return (Deno.env.get(name) ?? "").trim();
}

Deno.serve(async (request) => {
  if (request.method !== "POST") return jsonResponse(405, { error: "method_not_allowed" });

  const supabaseUrl = env("SUPABASE_URL");
  const serviceKey = env("SUPABASE_SERVICE_ROLE_KEY") || env("DHD_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceKey) return jsonResponse(500, { error: "missing_service_configuration" });

  const authorization = request.headers.get("Authorization") ?? "";
  const apiKey = request.headers.get("apikey") ?? "";
  if (!isConfiguredServiceRequest(authorization, apiKey, serviceKey)) {
    return jsonResponse(401, { error: "service_authentication_required" });
  }

  let body: Record<string, unknown> = {};
  try {
    const parsed: unknown = await request.json();
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
      return jsonResponse(400, { error: "invalid_json" });
    }
    body = parsed as Record<string, unknown>;
  } catch {
    return jsonResponse(400, { error: "invalid_json" });
  }
  const limit = body.limit === undefined ? 10 : body.limit;
  if (!Number.isInteger(limit) || (limit as number) < 1 || (limit as number) > 10) {
    return jsonResponse(400, { error: "cleanup_limit_invalid" });
  }

  const admin = createClient(supabaseUrl, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: claims, error: claimError } = await admin.rpc(
    "sd_claim_account_deletion_storage_cleanup",
    { p_actor_id: null, p_limit: limit },
  );
  if (claimError) return jsonResponse(503, { error: "cleanup_claim_failed" });

  const results = await processStorageCleanupClaims((claims ?? []) as StorageCleanupClaim[], {
    remove: async (bucket, objectPath) => {
      const { error } = await admin.storage.from(bucket).remove([objectPath]);
      return { error };
    },
    finish: async (outboxId, claimToken, outcome) => {
      const { error } = await admin.rpc("sd_finish_account_deletion_storage_cleanup", {
        p_outbox_id: outboxId,
        p_claim_token: claimToken,
        p_deleted: outcome.deleted,
        p_error_code: outcome.errorCode ?? null,
        p_manual_review: outcome.manualReview ?? false,
      });
      if (error) throw error;
    },
  });

  return jsonResponse(200, {
    claimed: (claims ?? []).length,
    completed: results.filter((result) => result.outcome === "completed").length,
    retryable: results.filter((result) => result.outcome === "retryable").length,
    manual_review: results.filter((result) => result.outcome === "manual_review").length,
  });
});
