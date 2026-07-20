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
      "save_teams",
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
  assert(
    source.includes("sd_team_event_practices"),
    "canonical practice subtype",
  );
  assert(source.includes("setup_request_id"), "event retry idempotency");
});

Deno.test("multi-team setup reuses existing teams and excludes color input", async () => {
  const source = await Deno.readTextFile(
    new URL("../organization-setup/index.ts", import.meta.url),
  );
  const wizard = await Deno.readTextFile(
    new URL(
      "../../../HomePlate/Features/Admin/OrganizationSetupWizardView.swift",
      import.meta.url,
    ),
  );
  assert(source.includes('action === "save_teams"'), "multi-team action");
  assert(source.includes('.ilike("name", name)'), "retry reuse");
  assert(source.includes("roster_capacity"), "team metadata");
  assert(!wizard.includes("Team color (hex)"), "no setup color field");
});

Deno.test("setup test reset is UUID-configured and protects history", async () => {
  const source = await Deno.readTextFile(
    new URL("../organization-setup/index.ts", import.meta.url),
  );
  const shared = await Deno.readTextFile(
    new URL("organization_setup.ts", import.meta.url),
  );
  assert(
    source.includes("HOME_PLATE_SETUP_TEST_ORGANIZATION_ID"),
    "stable UUID config",
  );
  assert(
    shared.includes("800e22ae-2a9d-4109-9e11-1360eeaa8ea7"),
    "sole Marist UUID",
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

  const progressReset = source.slice(
    source.indexOf('action === "reset_progress"'),
    source.indexOf('action === "reset_setup_test_data"'),
  );
  assert(progressReset.includes("sd_organization_setup_steps"), "step reset");
  assert(progressReset.includes("sd_organization_setup_drafts"), "draft reset");
  for (
    const protectedTable of [
      "sd_orgs",
      "sd_seasons",
      "sd_teams",
      "sd_facilities",
      "sd_registration_offerings",
      "sd_team_events",
    ]
  ) {
    assert(
      !progressReset.includes(protectedTable),
      `${protectedTable} preserved`,
    );
  }
  assert(
    progressReset.includes('current_step: "basics"'),
    "wizard reopens at basics",
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

Deno.test("setup practice compatibility repair is provenance-scoped and idempotent", async () => {
  const migration = await Deno.readTextFile(
    new URL(
      "../../migrations/20260718171000_repair_setup_practice_subtypes.sql",
      import.meta.url,
    ),
  );
  assert(
    migration.includes("sd_organization_setup_entities"),
    "setup provenance required",
  );
  assert(
    migration.includes("provenance.created_via_setup"),
    "created-via-setup required",
  );
  assert(
    migration.includes("event.event_type = 'practice'"),
    "practice events only",
  );
  assert(
    migration.includes("practice.event_id is null"),
    "missing subtype only",
  );
  assert(
    migration.includes("on conflict (event_id) do nothing"),
    "idempotent repair",
  );
  assert(
    !migration.includes("update public.sd_team_events"),
    "event preserved",
  );
  assert(!migration.includes("delete from"), "no destructive repair");
});
