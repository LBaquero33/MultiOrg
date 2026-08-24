import {
  identityKey,
  normalizePhoneLastFour,
  publicCheckInParticipant,
  signCheckInToken,
  verifyCheckInToken,
} from "./registration_public.ts";

Deno.test("check-in token rejects tampering and expiry", async () => {
  const token = await signCheckInToken(
    "test-secret-long-enough",
    "session-1",
    200,
  );
  const valid = await verifyCheckInToken("test-secret-long-enough", token, 100);
  if (valid?.session_id !== "session-1") {
    throw new Error("valid token rejected");
  }
  if (await verifyCheckInToken("test-secret-long-enough", `${token}x`, 100)) {
    throw new Error("tampered token accepted");
  }
  if (await verifyCheckInToken("test-secret-long-enough", token, 201)) {
    throw new Error("expired token accepted");
  }
});

Deno.test("identity key is normalized and organization scoped", async () => {
  const first = await identityKey("identity-secret", "ORG-A", {
    displayName: "  Casey   Jones ",
    email: "CASEY@EXAMPLE.COM",
    phone: "(555) 111-2222",
  });
  const same = await identityKey("identity-secret", "org-a", {
    displayName: "casey jones",
    email: "casey@example.com",
    phone: "5551112222",
  });
  const other = await identityKey("identity-secret", "org-b", {
    displayName: "casey jones",
    email: "casey@example.com",
    phone: "5551112222",
  });
  if (first !== same || first === other) {
    throw new Error("identity normalization failed");
  }
});

Deno.test("public projection omits contact and private fields", () => {
  const projected = publicCheckInParticipant({
    id: "participant",
    display_name: "Jordan",
    participant_number: 14,
    age_group: "14U",
    contact_email: "private@example.com",
    contact_phone: "5551112222",
    staff_comments: "private",
  });
  if (
    "contact_email" in projected || "contact_phone" in projected ||
    "staff_comments" in projected
  ) {
    throw new Error("private field leaked");
  }
  if (normalizePhoneLastFour("(555) 111-2222") !== "2222") {
    throw new Error("phone normalization failed");
  }
});
