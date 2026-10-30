export type StorageCleanupClaim = {
  outbox_id: string;
  account_user_id: string;
  bucket_id: string;
  object_path: string;
  source_kind: "profile_avatar" | "public_staff_photo";
  directory_id: string | null;
  directory_owned_by_account: boolean;
  auth_deleted: boolean;
  claim_token: string;
};

export type StorageCleanupResult = {
  outboxId: string;
  outcome: "completed" | "retryable" | "manual_review";
};

export type StorageCleanupAdapter = {
  remove(bucket: string, objectPath: string): Promise<{ error?: unknown | null }>;
  finish(
    outboxId: string,
    claimToken: string,
    result: { deleted: boolean; manualReview?: boolean; errorCode?: string },
  ): Promise<void>;
};

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function exactSecretMatch(provided: string, expected: string): boolean {
  if (provided.length !== expected.length) return false;
  let mismatch = 0;
  for (let index = 0; index < expected.length; index += 1) {
    mismatch |= provided.charCodeAt(index) ^ expected.charCodeAt(index);
  }
  return mismatch === 0;
}

export function isConfiguredServiceRequest(
  authorization: string,
  apiKey: string,
  serviceKey: string,
): boolean {
  return serviceKey.length > 0 &&
    exactSecretMatch(authorization, `Bearer ${serviceKey}`) &&
    exactSecretMatch(apiKey, serviceKey);
}

export function isAllowedPersonalImageClaim(claim: StorageCleanupClaim): boolean {
  if (!claim.auth_deleted || !UUID.test(claim.claim_token) || claim.bucket_id !== "avatars" ||
    !UUID.test(claim.account_user_id)) {
    return false;
  }
  if (claim.source_kind === "profile_avatar") {
    if (claim.object_path === `${claim.account_user_id}/profile.jpg`) return true;
    return Boolean(
      claim.directory_id && claim.directory_owned_by_account && UUID.test(claim.directory_id) &&
        ["jpg", "png", "webp"].some((extension) =>
          claim.object_path === `trainers/${claim.directory_id}/profile.${extension}`
        ),
    );
  }
  if (claim.source_kind !== "public_staff_photo") {
    return false;
  }
  if (claim.object_path === `${claim.account_user_id}/profile.jpg`) return true;
  if (!claim.directory_id || !UUID.test(claim.directory_id)) return false;
  if (!claim.directory_owned_by_account) return false;
  return ["jpg", "png", "webp"].some((extension) =>
    claim.object_path === `trainers/${claim.directory_id}/profile.${extension}`
  ) || claim.object_path === `${claim.account_user_id}/profile.jpg`;
}

export async function processStorageCleanupClaims(
  claims: StorageCleanupClaim[],
  adapter: StorageCleanupAdapter,
): Promise<StorageCleanupResult[]> {
  const results: StorageCleanupResult[] = [];
  const finishSafely = async (
    claim: StorageCleanupClaim,
    result: { deleted: boolean; manualReview?: boolean; errorCode?: string },
  ): Promise<boolean> => {
    try {
      await adapter.finish(claim.outbox_id, claim.claim_token, result);
      return true;
    } catch {
      // Leave the durable claim leased. SQL will make it reclaimable after the
      // claim timeout; deleting an already removed object is safe to retry.
      return false;
    }
  };
  for (const claim of claims) {
    if (!isAllowedPersonalImageClaim(claim)) {
      const recorded = await finishSafely(claim, {
        deleted: false,
        manualReview: true,
        errorCode: "path_not_allowlisted",
      });
      results.push({ outboxId: claim.outbox_id, outcome: recorded ? "manual_review" : "retryable" });
      continue;
    }

    let error: unknown;
    try {
      error = (await adapter.remove(claim.bucket_id, claim.object_path)).error;
    } catch {
      error = true;
    }
    if (error) {
      await finishSafely(claim, {
        deleted: false,
        errorCode: "storage_remove_failed",
      });
      results.push({ outboxId: claim.outbox_id, outcome: "retryable" });
      continue;
    }
    const recorded = await finishSafely(claim, { deleted: true });
    results.push({ outboxId: claim.outbox_id, outcome: recorded ? "completed" : "retryable" });
  }
  return results;
}

export function cleanupStateFromCounts(counts: {
  pending?: number;
  processing?: number;
  manual_review?: number;
  completed?: number;
} | null): "completed" | "pending" | "manual_review" {
  if (!counts) return "pending";
  if ((counts.pending ?? 0) > 0 || (counts.processing ?? 0) > 0) return "pending";
  if ((counts.manual_review ?? 0) > 0) return "manual_review";
  return "completed";
}
