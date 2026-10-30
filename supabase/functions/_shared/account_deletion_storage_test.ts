import {
  cleanupStateFromCounts,
  isConfiguredServiceRequest,
  isAllowedPersonalImageClaim,
  processStorageCleanupClaims,
  type StorageCleanupClaim,
} from "./account_deletion_storage.ts";
import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";

const userId = "11111111-1111-4111-8111-111111111111";
const directoryId = "22222222-2222-4222-8222-222222222222";

function claim(overrides: Partial<StorageCleanupClaim> = {}): StorageCleanupClaim {
  return {
    outbox_id: "33333333-3333-4333-8333-333333333333",
    account_user_id: userId,
    bucket_id: "avatars",
    object_path: `${userId}/profile.jpg`,
    source_kind: "profile_avatar",
    directory_id: null,
    directory_owned_by_account: false,
    auth_deleted: true,
    claim_token: "55555555-5555-4555-8555-555555555555",
    ...overrides,
  };
}

Deno.test("personal avatar and owned trainer photo allowlist is exact", () => {
  assertEquals(isAllowedPersonalImageClaim(claim()), true);
  assertEquals(isAllowedPersonalImageClaim(claim({
    source_kind: "public_staff_photo",
    directory_id: directoryId,
    directory_owned_by_account: true,
    object_path: `trainers/${directoryId}/profile.webp`,
  })), true);
  assertEquals(isAllowedPersonalImageClaim(claim({ object_path: `${userId}/other.jpg` })), false);
  assertEquals(isAllowedPersonalImageClaim(claim({
    source_kind: "public_staff_photo",
    directory_id: directoryId,
    directory_owned_by_account: true,
    object_path: `trainers/${userId}/profile.jpg`,
  })), false);
  assertEquals(isAllowedPersonalImageClaim(claim({
    source_kind: "public_staff_photo",
    directory_id: directoryId,
    directory_owned_by_account: false,
    object_path: `trainers/${directoryId}/profile.jpg`,
  })), false);
  assertEquals(isAllowedPersonalImageClaim(claim({
    directory_id: directoryId,
    directory_owned_by_account: true,
    object_path: `trainers/${directoryId}/profile.png`,
  })), true);
  assertEquals(isAllowedPersonalImageClaim(claim({
    directory_id: directoryId,
    directory_owned_by_account: false,
    object_path: `trainers/${directoryId}/profile.png`,
  })), false);
  assertEquals(isAllowedPersonalImageClaim(claim({ bucket_id: "organization-logos" })), false);
  assertEquals(isAllowedPersonalImageClaim(claim({ claim_token: "" })), false);
  assertEquals(isAllowedPersonalImageClaim(claim({ object_path: `https://example.test/${userId}/profile.jpg` })), false);
});

Deno.test("uncommitted account deletion cannot purge storage", async () => {
  let removed = 0;
  const outcomes: Array<{ deleted: boolean; manualReview?: boolean; errorCode?: string }> = [];
  const result = await processStorageCleanupClaims([claim({ auth_deleted: false })], {
    remove: async () => { removed += 1; return {}; },
    finish: async (_id, _claimToken, outcome) => { outcomes.push(outcome); },
  });
  assertEquals(removed, 0);
  assertEquals(outcomes, [{
    deleted: false,
    manualReview: true,
    errorCode: "path_not_allowlisted",
  }]);
  assertEquals(result[0]?.outcome, "manual_review");
});

Deno.test("cleanup worker requires the exact configured service credential, without JWT decoding", () => {
  const serviceKey = "configured-service-secret";
  assertEquals(isConfiguredServiceRequest(`Bearer ${serviceKey}`, serviceKey, serviceKey), true);
  assertEquals(isConfiguredServiceRequest("Bearer user-access-token", "anon-key", serviceKey), false);
  assertEquals(isConfiguredServiceRequest(`Bearer ${serviceKey}`, "anon-key", serviceKey), false);
  assertEquals(isConfiguredServiceRequest(`Bearer ${serviceKey}x`, serviceKey, serviceKey), false);
  assertEquals(isConfiguredServiceRequest("Bearer ", "", ""), false);
});

Deno.test("partial storage failure stays retryable while successful objects complete", async () => {
  const finished: Array<{ id: string; claimToken: string; deleted: boolean; manualReview?: boolean }> = [];
  const result = await processStorageCleanupClaims([
    claim(),
    claim({
      outbox_id: "44444444-4444-4444-8444-444444444444",
      source_kind: "public_staff_photo",
      directory_id: directoryId,
      directory_owned_by_account: true,
      object_path: `trainers/${directoryId}/profile.png`,
    }),
  ], {
    remove: async (_bucket, path) => path.endsWith("profile.png") ? { error: new Error("private storage detail") } : {},
    finish: async (id, claimToken, outcome) => {
      finished.push({ id, claimToken, deleted: outcome.deleted, manualReview: outcome.manualReview });
    },
  });
  assertEquals(finished.map((row) => row.deleted), [true, false]);
  assertEquals(finished.map((row) => row.claimToken), [
    "55555555-5555-4555-8555-555555555555",
    "55555555-5555-4555-8555-555555555555",
  ]);
  assertEquals(finished[1]?.manualReview, undefined);
  assertEquals(result.map((row) => row.outcome), ["completed", "retryable"]);
  assertEquals(cleanupStateFromCounts({ pending: 1, completed: 1 }), "pending");
  assertEquals(cleanupStateFromCounts({ manual_review: 1 }), "manual_review");
  assertEquals(cleanupStateFromCounts({ completed: 1 }), "completed");
});
