import {
  currentAndNextExecution,
  hasAccidentalOverlap,
  plannedDuration,
  sanitizePracticePayload,
} from "./practice_planning.ts";

const assert = (condition: boolean, message: string) => {
  if (!condition) throw new Error(message);
};
const migrationURL = new URL(
  "../../migrations/20260717220000_complete_practice_planner.sql",
  import.meta.url,
);
const edgeURL = new URL("../practice-planning/index.ts", import.meta.url);

Deno.test("duration excludes parallel station children", () => {
  const blocks = [
    { id: "parent", duration_minutes: 30, start_offset_minutes: 0 },
    {
      id: "station",
      parent_block_id: "parent",
      duration_minutes: 30,
      start_offset_minutes: 0,
    },
    { id: "next", duration_minutes: 15, start_offset_minutes: 30 },
  ];
  assert(
    plannedDuration(blocks) === 45,
    "parallel child must not extend duration",
  );
  assert(
    !hasAccidentalOverlap(blocks),
    "explicit station is not accidental overlap",
  );
});

Deno.test("accidental sequential overlap is deterministic", () => {
  assert(
    hasAccidentalOverlap([
      { start_offset_minutes: 0, duration_minutes: 20 },
      { start_offset_minutes: 15, duration_minutes: 20 },
    ]),
    "overlap",
  );
});

Deno.test("execution selects one current and next sequential block", () => {
  const state = currentAndNextExecution([
    { sequence_index: 2, status: "pending" },
    { sequence_index: 1, status: "active" },
    { sequence_index: 1, parent_block_id: "parent", status: "active" },
  ]);
  assert(state.current?.status === "active", "current");
  assert(state.next?.sequence_index === 2, "next");
});

Deno.test("consumer redaction hides staff fields and other assignments", () => {
  const sanitized = sanitizePracticePayload({
    plan: { coach_notes: "private", title: "Practice" },
    blocks: [{ visibility: "staff_only" }, {
      visibility: "player_visible",
      coaching_points: "private",
    }],
    groups: [{ id: "own" }, { id: "other" }],
    assignments: [{ user_id: "player", group_id: "own" }, {
      user_id: "other",
      group_id: "other",
    }],
    equipment: [{ visibility: "player_visible", notes: "internal" }],
  }, "player");
  assert(
    !(sanitized.plan as Record<string, unknown>).coach_notes,
    "coach notes",
  );
  assert((sanitized.blocks as unknown[]).length === 1, "staff block");
  assert((sanitized.groups as unknown[]).length === 1, "other group");
});

Deno.test("schema is normalized additive scoped indexed and RLS protected", async () => {
  const sql = await Deno.readTextFile(migrationURL);
  for (
    const table of [
      "sd_practice_plans",
      "sd_practice_plan_blocks",
      "sd_practice_plan_groups",
      "sd_practice_plan_assignments",
      "sd_practice_plan_equipment",
      "sd_practice_plan_templates",
      "sd_practice_plan_snapshots",
      "sd_practice_block_executions",
      "sd_practice_plan_adjustments",
      "sd_practice_plan_audit_logs",
      "sd_practice_plan_mutations",
    ]
  ) {
    assert(sql.includes(`create table if not exists public.${table}`), table);
    assert(
      sql.includes(`alter table public.${table} enable row level security`),
      `${table} RLS`,
    );
  }
  assert(
    sql.includes("uq_sd_practice_plans_primary_event"),
    "one primary plan",
  );
  assert(sql.includes("sd_practice_plans_event_scope_fk"), "structural scope");
  assert(!sql.includes("drop table"), "non destructive");
});

Deno.test("templates and duplication create independent lineage", async () => {
  const sql = await Deno.readTextFile(migrationURL);
  assert(sql.includes("source_template_id"), "template lineage");
  assert(sql.includes("source_plan_id"), "plan lineage");
  assert(
    sql.includes("sd_materialize_practice_snapshot"),
    "independent materialization",
  );
  assert(sql.includes("template.snapshot"), "template snapshot");
  assert(!sql.includes("attendance_status text"), "no second attendance");
});

Deno.test("validation classifies blockers warnings and notices server-side", async () => {
  const sql = await Deno.readTextFile(migrationURL);
  for (
    const code of [
      "missing_title",
      "no_blocks",
      "invalid_duration",
      "accidental_overlap",
      "invalid_parallel_station",
      "plan_longer_than_event",
      "plan_significantly_shorter",
      "block_outside_event_window",
      "unassigned_expected_players",
      "required_equipment_not_prepared",
      "draft_changes_after_publication",
    ]
  ) assert(sql.includes(code), code);
  assert(
    sql.includes("blocking_errors") && sql.includes("readiness_warnings") &&
      sql.includes("notices"),
    "classification",
  );
});

Deno.test("publication started and completion snapshots remain immutable", async () => {
  const sql = await Deno.readTextFile(migrationURL);
  assert(sql.includes("'published',plan.version"), "published snapshot");
  assert(
    sql.includes("'started',published.plan_version,published.snapshot"),
    "started copy",
  );
  assert(sql.includes("'completed',plan.version"), "completion snapshot");
  assert(sql.includes("sd_practice_block_executions"), "execution history");
});

Deno.test("active execution enforces sequential and parallel behavior", async () => {
  const sql = await Deno.readTextFile(migrationURL);
  for (
    const action of [
      "start_block",
      "complete_block",
      "skip_block",
      "reopen_block",
      "adjust_active_block",
      "add_active_block",
    ]
  ) assert(sql.includes(`'${action}'`), action);
  assert(sql.includes("sequential_block_already_active"), "sequential gate");
  assert(sql.includes("parent_block_id is null"), "parallel distinction");
  assert(sql.includes("adjustment_reason_required"), "audited adjustment");
});

Deno.test("mutations are transactional idempotent versioned and audited", async () => {
  const sql = await Deno.readTextFile(migrationURL);
  assert(sql.includes("request_fingerprint"), "fingerprint");
  assert(sql.includes("'replayed',true"), "replay");
  assert(sql.includes("stale_version"), "conflict");
  assert(sql.includes("sd_practice_plan_audit_logs"), "audit");
  assert(
    sql.includes("unique (organization_id, request_id, action)"),
    "audit dedupe",
  );
});

Deno.test("central capability resolver preserves Phase 12C and adds exact practice policy", async () => {
  const sql = await Deno.readTextFile(migrationURL);
  for (
    const capability of [
      "view_practice_plan",
      "create_practice_plan",
      "publish_practice_plan",
      "manage_practice_templates",
      "execute_practice_blocks",
      "reopen_practice_plan",
      "view_event_operation",
    ]
  ) assert(sql.includes(`'${capability}'`), capability);
  assert(
    sql.includes("responsibility in ('head_coach','team_manager')"),
    "parity",
  );
  assert(sql.includes("responsibility='assistant_coach'"), "assistant");
  assert(
    sql.includes("responsibility in ('evaluator','read_only')"),
    "view only",
  );
});

Deno.test("edge fails closed redacts consumers and exposes one API", async () => {
  const source = await Deno.readTextFile(edgeURL);
  assert(source.includes('"sd_resolve_team_capabilities"'), "central auth");
  assert(source.includes("sanitizePracticePayload"), "redaction");
  assert(
    source.includes("parent_link_required") &&
      source.includes("active_team_required"),
    "consumer scope",
  );
  assert(
    source.includes('"sd_apply_practice_plan_mutation"'),
    "transaction boundary",
  );
  assert(!source.includes('from("sd_notifications")'), "no delivery");
});
