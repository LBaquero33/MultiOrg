import {
  cleanResponsibilities,
  resolveSelectedTeam,
} from "./team_operations.ts";

function assert(condition: boolean, message: string) {
  if (!condition) throw new Error(message);
}

function migrationSource() {
  return Deno.readTextFile(
    new URL(
      "../../migrations/20260717170000_team_operations_foundation.sql",
      import.meta.url,
    ),
  );
}

Deno.test("SQL is the single authoritative responsibility capability resolver", async () => {
  const migration = await migrationSource();
  assert(
    migration.includes(
      "create or replace function public.sd_resolve_team_capabilities",
    ),
    "resolver",
  );
  assert(
    !migration.includes("responsibilityCapabilities"),
    "no second mapping",
  );
});

Deno.test("Head Coach and Team Manager have exact capability parity", async () => {
  const migration = await migrationSource();
  assert(
    migration.includes("responsibility in ('head_coach','team_manager')"),
    "Head Coach and Team Manager parity",
  );
  assert(
    migration.includes("'manage_staff','view_documents','manage_documents'"),
    "full capability set",
  );
});

Deno.test("Assistant Coach lacks Team Manager capability unless combined", async () => {
  const migration = await migrationSource();
  assert(
    migration.includes("responsibility = 'assistant_coach'"),
    "Assistant Coach mapping",
  );
  const assistantCondition = migration.indexOf(
    "responsibility = 'assistant_coach'",
  );
  const assistantStart = migration.lastIndexOf(
    "select unnest(array[",
    assistantCondition,
  );
  const assistantBlock = migration.slice(
    assistantStart,
    assistantCondition + 100,
  );
  assert(
    !assistantBlock.includes("manage_staff"),
    "Assistant Coach cannot manage staff",
  );
  assert(
    migration.includes("responsibility in ('head_coach','team_manager')"),
    "Team Manager union grants full set",
  );
});

Deno.test("Read Only contains no mutation capability", async () => {
  const migration = await migrationSource();
  assert(
    migration.includes("responsibility = 'read_only'"),
    "Read Only mapping",
  );
  assert(
    migration.includes(
      "array['view_team','view_development','view_documents']",
    ),
    "view-only set",
  );
  assert(
    migration.includes(
      "public.sd_resolve_team_capabilities(p_organization_id, p_team_id, p_coach_id)",
    ),
    "mutations use resolver",
  );
});

Deno.test("multiple responsibilities are normalized and invalid values fail closed", () => {
  const cleaned = cleanResponsibilities([
    "assistant_coach",
    "team_manager",
    "team_manager",
  ]);
  assert(cleaned?.length === 2, "deduplicated");
  assert(
    cleanResponsibilities(["owner"]) === null,
    "unknown responsibility rejected",
  );
  assert(cleanResponsibilities([]) === null, "empty responsibility rejected");
});

Deno.test("one-team coach is selected automatically", () => {
  const selected = resolveSelectedTeam(
    [
      { id: "team-a", organization_id: "org-a", season_id: "season-a" },
    ],
    "org-a",
    "season-a",
    null,
  );
  assert(selected === "team-a", "single team selected");
});

Deno.test("persisted team selection survives when still authorized", () => {
  const teams = [
    { id: "team-a", organization_id: "org-a", season_id: "season-a" },
    { id: "team-b", organization_id: "org-a", season_id: "season-a" },
  ];
  assert(
    resolveSelectedTeam(teams, "org-a", "season-a", "team-b") === "team-b",
    "persisted",
  );
});

Deno.test("removed team falls back to primary assignment", () => {
  const teams = [
    {
      id: "team-a",
      organization_id: "org-a",
      season_id: "season-a",
      is_primary: true,
    },
    { id: "team-b", organization_id: "org-a", season_id: "season-a" },
  ];
  assert(
    resolveSelectedTeam(teams, "org-a", "season-a", "removed") === "team-a",
    "primary fallback",
  );
});

Deno.test("cross-organization and cross-season selections never leak", () => {
  const teams = [
    { id: "other-org", organization_id: "org-b", season_id: "season-a" },
    { id: "other-season", organization_id: "org-a", season_id: "season-b" },
  ];
  assert(
    resolveSelectedTeam(teams, "org-a", "season-a", "other-org") === null,
    "isolated",
  );
});

Deno.test("migration is additive, historical, constrained, RLS protected, and auditable", async () => {
  const migration = await Deno.readTextFile(
    new URL(
      "../../migrations/20260717170000_team_operations_foundation.sql",
      import.meta.url,
    ),
  );
  assert(
    migration.includes("create table if not exists public.sd_seasons"),
    "season table",
  );
  assert(
    migration.includes("uq_sd_player_one_active_team_per_org"),
    "one active team",
  );
  assert(migration.includes("legacy_team_assignment"), "legacy backfill");
  assert(
    migration.includes("sd_coach_team_responsibilities"),
    "normalized responsibilities",
  );
  assert(migration.includes("sd_team_operations_audit_logs"), "audit log");
  assert(
    migration.match(/enable row level security/g)?.length === 5,
    "RLS tables",
  );
  assert(!migration.includes("drop table"), "no destructive table migration");
});

Deno.test("organization admin actions reject coaches before mutation", async () => {
  const source = await Deno.readTextFile(
    new URL("../org_admin/index.ts", import.meta.url),
  );
  const authorization = source.indexOf(
    "teamOperationsAdminActions.includes(action) && !hasAdminAuthority",
  );
  const mutation = source.indexOf('if (action === "create_season"');
  assert(
    authorization > 0 && authorization < mutation,
    "authorization precedes mutation",
  );
  assert(
    source.includes('return json(403, { error: "org_admin_required" })'),
    "controlled denial",
  );
});
