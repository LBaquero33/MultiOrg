import {
  ACCOUNT_DELETION_SUPPORT_URL,
  accountDeletionUnavailableResponse,
  accountDeletionConflictResponse,
  isAccountDeletionEnabled,
  isSoleActiveOwnerConflict,
} from "./account_deletion.ts";
import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";

Deno.test("account deletion maps the exact sole-owner SQL error to actionable conflict", () => {
  const response = accountDeletionConflictResponse();
  assertEquals(isSoleActiveOwnerConflict({
    code: "P0001",
    message: "account_deletion_sole_active_owner",
  }), true);
  assertEquals(response.status, 409);
  assertEquals(response.body.error, "sole_active_owner");
  assertEquals(response.body.message.includes("another active owner"), true);
});

Deno.test("account deletion does not misclassify unrelated Auth or database errors", () => {
  assertEquals(isSoleActiveOwnerConflict({
    code: "500",
    message: "Database error deleting user",
  }), false);
  assertEquals(isSoleActiveOwnerConflict(null), false);
});

Deno.test("account deletion activation is default-off and accepts only exact true", () => {
  for (const value of [undefined, "", "false", "TRUE", "True", " true", "true ", "1"]) {
    assertEquals(isAccountDeletionEnabled(value), false);
  }
  assertEquals(isAccountDeletionEnabled("true"), true);
});

Deno.test("disabled account deletion response includes support route", () => {
  const response = accountDeletionUnavailableResponse();
  assertEquals(response.status, 503);
  assertEquals(response.body.error, "account_deletion_temporarily_unavailable");
  assertEquals(response.body.support_url, ACCOUNT_DELETION_SUPPORT_URL);
});
