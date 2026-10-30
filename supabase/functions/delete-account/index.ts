import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import {
  accountDeletionConflictResponse,
  accountDeletionUnavailableResponse,
  isAccountDeletionEnabled,
  isSoleActiveOwnerConflict,
} from "../_shared/account_deletion.ts";
import {
  cleanupStateFromCounts,
  processStorageCleanupClaims,
  type StorageCleanupClaim,
} from "../_shared/account_deletion_storage.ts";
import { corsPreflight, jsonResponse } from "../_shared/cors.ts";

function env(name: string) {
  return (Deno.env.get(name) ?? "").trim();
}

async function purgeAccountImages(adminInput: unknown, actorId: string) {
  const admin = adminInput as {
    rpc: (name: string, args: Record<string, unknown>) => Promise<{ data: unknown; error: unknown }>;
    storage: {
      from: (bucket: string) => {
        remove: (paths: string[]) => Promise<{ error: unknown }>;
      };
    };
  };
  const { data: claims, error: claimError } = await admin.rpc(
    "sd_claim_account_deletion_storage_cleanup",
    { p_actor_id: actorId, p_limit: 10 },
  );
  if (claimError) return "pending" as const;
  await processStorageCleanupClaims((claims ?? []) as StorageCleanupClaim[], {
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
  const { data: counts, error: statusError } = await admin.rpc(
    "sd_account_deletion_storage_cleanup_status",
    { p_actor_id: actorId },
  );
  if (statusError) return "pending" as const;
  return cleanupStateFromCounts(counts as {
    pending?: number;
    processing?: number;
    manual_review?: number;
  } | null);
}

Deno.serve(async (request) => {
  const preflight = corsPreflight(request);
  if (preflight) return preflight;
  if (request.method !== "POST") return jsonResponse(405, { error: "method_not_allowed" });
  if (!isAccountDeletionEnabled(Deno.env.get("ACCOUNT_DELETION_ENABLED"))) {
    const unavailable = accountDeletionUnavailableResponse();
    return jsonResponse(unavailable.status, unavailable.body);
  }

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
  const { error: activeGuardError } = await admin.rpc("sd_require_active_account");
  if (activeGuardError) {
    const unavailable = accountDeletionUnavailableResponse();
    return jsonResponse(unavailable.status, unavailable.body);
  }
  const { error: preparationError } = await admin.rpc(
    "sd_prepare_account_deletion",
    { p_actor_id: actor.user.id },
  );
  if (preparationError) {
    if (isSoleActiveOwnerConflict(preparationError)) {
      const conflict = accountDeletionConflictResponse();
      return jsonResponse(conflict.status, conflict.body);
    }
    return jsonResponse(503, { error: "account_deletion_preparation_failed" });
  }
  const { error: deletionError } = await admin.auth.admin.deleteUser(actor.user.id, true);
  if (deletionError) {
    // The trigger rechecks ownership in GoTrue's transaction. If ownership
    // changed after preflight, repeat the read-only check to return the same
    // actionable response without relying on Auth's wrapped SQL error text.
    const { error: refreshedPreflightError } = await admin.rpc(
      "sd_prepare_account_deletion",
      { p_actor_id: actor.user.id },
    );
    if (isSoleActiveOwnerConflict(deletionError) || isSoleActiveOwnerConflict(refreshedPreflightError)) {
      const conflict = accountDeletionConflictResponse();
      return jsonResponse(conflict.status, conflict.body);
    }
    return jsonResponse(500, { error: "account_deletion_failed" });
  }

  let storageCleanup: "completed" | "pending" | "manual_review" = "pending";
  try {
    storageCleanup = await purgeAccountImages(admin, actor.user.id);
  } catch {
    // Auth has committed; the durable outbox remains available to the retry worker.
    storageCleanup = "pending";
  }
  return jsonResponse(200, {
    deleted: true,
    account_status: "deactivated",
    storage_cleanup: storageCleanup,
  });
});
