function assert(condition: boolean, message: string) {
  if (!condition) throw new Error(message);
}

Deno.test("organization setup Edge Function has one guarded authoritative contract", async () => {
  const source = await Deno.readTextFile(
    new URL("../organization-setup/index.ts", import.meta.url),
  );
  for (
    const action of [
      "get",
      "start",
      "navigate",
      "save_basics",
      "save_season",
      "save_team",
      "save_people_draft",
      "save_registration",
      "save_facility",
      "save_communication",
      "create_first_event",
      "skip_step",
      "dismiss",
      "reopen",
      "complete",
      "preview_test_data_reset",
      "reset_progress",
      "reset_setup_test_data",
    ]
  ) {
    assert(
      source.includes(`action === "${action}"`) ||
        source.includes(`"${action}"`),
      action,
    );
  }
  assert(source.includes("sd_resolve_setup_capabilities"), "capabilities");
  assert(source.includes("stale_setup_version"), "optimistic concurrency");
  assert(
    source.includes("sd_organization_setup_mutations"),
    "idempotency receipts",
  );
  assert(source.includes("sd_organization_setup_entities"), "provenance");
  assert(source.includes("sd_organization_setup_audit_logs"), "audit");
  assert(source.includes('audit(ctx, "fetch_setup"'), "open audit");
});

Deno.test("setup test reset is UUID-configured and protects history", async () => {
  const source = await Deno.readTextFile(
    new URL("../organization-setup/index.ts", import.meta.url),
  );
  assert(
    source.includes("HOME_PLATE_SETUP_TEST_ORGANIZATION_ID"),
    "stable UUID config",
  );
  assert(source.includes("HOME_PLATE_SETUP_TEST_MODE"), "feature flag");
  assert(source.includes("HOME_PLATE_ENVIRONMENT"), "environment guard");
  assert(
    source.includes("protected_history_preserved: true"),
    "protected history",
  );
  assert(source.includes('eq("setup_test_run_id"'), "test run isolation");
  assert(
    source.includes("setup_test_run_required"),
    "server confirmation scope",
  );
  assert(
    !source.includes('delete().eq("id", ctx.organizationId)'),
    "no full organization delete",
  );
});

Deno.test("setup migration keeps business data authoritative", async () => {
  const migration = await Deno.readTextFile(
    new URL(
      "../../migrations/20260718160000_complete_organization_setup.sql",
      import.meta.url,
    ),
  );
  assert(
    migration.includes("sd_organization_setup_readiness"),
    "live readiness",
  );
  assert(migration.includes("sd_seasons"), "authoritative seasons");
  assert(migration.includes("sd_teams"), "authoritative teams");
  assert(migration.includes("enable row level security"), "RLS");
  assert(migration.includes("sd_resolve_setup_capabilities"), "authorization");
});
