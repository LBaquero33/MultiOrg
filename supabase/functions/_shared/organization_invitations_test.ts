function assert(condition: boolean, message: string) {
  if (!condition) throw new Error(message);
}

Deno.test("organization invite tokens are opaque hashed and server authoritative", async () => {
  const source = await Deno.readTextFile(
    new URL("../organization-invitations/index.ts", import.meta.url),
  );
  const migration = await Deno.readTextFile(
    new URL(
      "../../migrations/20260718170000_setup_invitation_links.sql",
      import.meta.url,
    ),
  );
  assert(
    source.includes("crypto.subtle.digest(") && source.includes('"SHA-256"'),
    "SHA-256 token digest",
  );
  assert(source.includes("randomToken()"), "cryptographic random token");
  assert(source.includes("invitation_not_found"), "tampered token rejected");
  assert(source.includes("invitation_expired"), "expiration enforced");
  assert(source.includes("invitation_revoked"), "revocation enforced");
  assert(source.includes("account_role_mismatch"), "wrong role rejected");
  assert(
    source.includes('.eq("org_id", ctx.organizationId)'),
    "team organization scope",
  );
  assert(!source.includes("payload.role"), "role query input not trusted");
  assert(
    !source.includes("payload.organization_id") ||
      source.includes("organizationContext"),
    "organization is authorized",
  );
  assert(
    migration.includes("token_hash text not null unique"),
    "only hash stored",
  );
  assert(!migration.includes("raw_token"), "no raw token column");
  assert(migration.includes("enable row level security"), "RLS enabled");
  assert(
    migration.includes("sd_organization_invitation_acceptances"),
    "acceptance audit",
  );
});

Deno.test("invite rotation revokes the previous link before replacement", async () => {
  const source = await Deno.readTextFile(
    new URL("../organization-invitations/index.ts", import.meta.url),
  );
  const revoke = source.indexOf("revoked_at: now.toISOString()");
  const token = source.indexOf("const token = randomToken()", revoke);
  assert(
    revoke >= 0 && token > revoke,
    "old link revoked before raw replacement token exists",
  );
  assert(
    source.includes("token_version: nextVersion"),
    "rotation version audited",
  );
});

Deno.test("invite continuation is role-scoped audited and idempotent", async () => {
  const invitation = await Deno.readTextFile(
    new URL("../organization-invitations/index.ts", import.meta.url),
  );
  const account = await Deno.readTextFile(
    new URL("../create_account/index.ts", import.meta.url),
  );
  assert(
    invitation.includes('action === "validate"'),
    "unauthenticated validation action",
  );
  assert(
    invitation.includes('action === "accept"'),
    "authenticated acceptance action",
  );
  assert(
    invitation.includes("priorAcceptance?.id"),
    "duplicate acceptance is idempotent",
  );
  assert(
    invitation.includes("sd_org_memberships"),
    "existing membership system reused",
  );
  assert(
    invitation.includes("sd_coach_team_assignments"),
    "coach assignment remains team scoped",
  );
  assert(
    invitation.includes("sd_coach_team_responsibilities"),
    "coach responsibility scope preserved",
  );
  assert(
    account.includes("invitation_token"),
    "account creation preserves opaque token",
  );
  assert(
    account.includes("setupInvitation.intended_role !== role"),
    "account role mismatch rejected",
  );
  assert(
    !account.includes("payload.intended_role"),
    "account creation does not trust role query input",
  );
});
