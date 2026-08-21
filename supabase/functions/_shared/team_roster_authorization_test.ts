function assert(condition: boolean, message: string) {
  if (!condition) throw new Error(message);
}

const migrationURL = new URL(
  "../../migrations/20260821150000_team_scoped_coach_roster_management.sql",
  import.meta.url,
);

Deno.test("team roster mutation uses active membership and resolved capability", async () => {
  const migration = await Deno.readTextFile(migrationURL);
  assert(migration.includes("membership.status = 'active'"), "active membership required");
  assert(migration.includes("membership.role in ('owner', 'admin')"), "org admins retained");
  assert(migration.includes("'manage_roster' = any("), "team capability required");
  assert(migration.includes("public.sd_resolve_team_capabilities("), "central resolver used");
});

Deno.test("player assignment and removal both use team roster authorization", async () => {
  const migration = await Deno.readTextFile(migrationURL);
  const mutationGuards = migration.match(
    /if not public\.sd_actor_can_manage_team_roster\(/g,
  ) ?? [];
  assert(mutationGuards.length === 2, "both mutations use the helper");
  assert(migration.includes("raise exception 'team_roster_management_required'"), "controlled denial");
  assert(migration.includes("v_authorization_team_id := v_membership.team_id"), "unassign checks current team");
});

Deno.test("team roster RPCs remain service-role only", async () => {
  const migration = await Deno.readTextFile(migrationURL);
  assert(
    migration.includes("from public, anon, authenticated;"),
    "client roles revoked",
  );
  assert(
    migration.match(/to service_role;/g)?.length === 3,
    "helper and both mutation RPCs granted only to service role",
  );
});

Deno.test("unassignment replay retains its original team authorization context", async () => {
  const migration = await Deno.readTextFile(migrationURL);
  assert(migration.includes("details->>'previous_team_id'"), "previous team recovered");
  assert(migration.includes("'replayed', true"), "idempotent replay retained");
});
