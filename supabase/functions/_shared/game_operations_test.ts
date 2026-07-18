import {
  LINEUP_MODES,
  OFFENSIVE_ROLES,
  sanitizeGamePayload,
  validateGamePlan,
} from "./game_operations.ts";

const assert = (condition: boolean, message: string) => {
  if (!condition) throw new Error(message);
};
const migrationURL = new URL(
  "../../migrations/20260718000000_complete_game_operations.sql",
  import.meta.url,
);
const edgeURL = new URL("../game-operations/index.ts", import.meta.url);

const hitters = (count: number, role = "hitter") =>
  Array.from({ length: count }, (_, index) => ({
    id: `entry-${index}`,
    player_id: `player-${index}`,
    batting_slot: index + 1,
    offensive_role: role,
    active: true,
  }));

Deno.test("travel-ball modes and offensive roles are complete", () => {
  for (
    const mode of [
      "standard_nine",
      "standard_nine_with_dh",
      "standard_nine_with_one_eh",
      "standard_nine_with_multiple_eh",
      "continuous_batting_order",
      "bat_entire_available_roster",
      "custom",
    ]
  ) assert(LINEUP_MODES.includes(mode as never), mode);
  for (
    const role of ["eh", "dh", "offensive_only", "courtesy_runner", "bench"]
  ) {
    assert(OFFENSIVE_ROLES.includes(role as never), role);
  }
});

Deno.test("arbitrary batting order allows more than nine and multiple EH", () => {
  const batting = hitters(15);
  batting[9].offensive_role = "eh";
  batting[10].offensive_role = "eh";
  const result = validateGamePlan({
    lineupMode: "standard_nine_with_multiple_eh",
    batting,
    defense: [],
    pitcherCatcher: [
      { role_type: "starting_pitcher" },
      { role_type: "starting_catcher" },
    ],
    eligibility: [],
    ruleProfile: {
      eh_allowed: true,
      maximum_eh: null,
      maximum_batting_slots: null,
    },
  });
  assert(result.valid, "uncapped order should be valid");
  assert(result.batting_count === 15, "arbitrary length");
  assert(result.eh_count === 2, "multiple EH");
});

Deno.test("null maximum is uncapped while configured maximum blocks", () => {
  const base = {
    lineupMode: "custom",
    batting: hitters(12),
    defense: [],
    pitcherCatcher: [
      { role_type: "starting_pitcher" },
      { role_type: "starting_catcher" },
    ],
    eligibility: [],
  };
  assert(
    validateGamePlan({ ...base, ruleProfile: { maximum_batting_slots: null } })
      .valid,
    "null cap",
  );
  assert(
    !validateGamePlan({ ...base, ruleProfile: { maximum_batting_slots: 9 } })
      .valid,
    "configured cap",
  );
});

Deno.test("duplicate hitters slots and gaps are blocking", () => {
  const batting = hitters(3);
  batting[1].player_id = batting[0].player_id;
  batting[2].batting_slot = 4;
  const result = validateGamePlan({
    lineupMode: "custom",
    batting,
    defense: [],
    pitcherCatcher: [],
    eligibility: [],
    ruleProfile: {},
  });
  const codes = result.blocking_errors.map((finding) => finding.code);
  assert(codes.includes("duplicate_active_hitter"), "duplicate hitter");
  assert(codes.includes("missing_batting_slot"), "slot gap");
});

Deno.test("EH DH and presets validate only configured constraints", () => {
  const batting = hitters(11);
  batting[9].offensive_role = "eh";
  batting[10].offensive_role = "eh";
  const result = validateGamePlan({
    lineupMode: "continuous_batting_order",
    batting: [...batting, {
      id: "dh",
      player_id: "dh",
      batting_slot: 12,
      offensive_role: "dh",
      active: true,
    }],
    defense: [],
    pitcherCatcher: [],
    eligibility: [],
    ruleProfile: {
      eh_allowed: false,
      maximum_eh: 1,
      dh_allowed: false,
      continuous_batting_order_allowed: false,
    },
  });
  const codes = result.blocking_errors.map((finding) => finding.code);
  for (
    const code of [
      "eh_disallowed",
      "eh_limit_exceeded",
      "dh_disallowed",
      "continuous_order_disallowed",
    ]
  ) {
    assert(codes.includes(code), code);
  }
});

Deno.test("bat entire roster requires explicit omission reasons", () => {
  const result = validateGamePlan({
    lineupMode: "bat_entire_available_roster",
    batting: hitters(2),
    defense: [],
    pitcherCatcher: [],
    eligibility: [
      { player_id: "player-0", status: "eligible" },
      { player_id: "player-1", status: "eligible" },
      { player_id: "player-2", status: "eligible" },
      {
        player_id: "player-3",
        status: "coach_excluded",
        exclusion_reason: "Tournament limit",
      },
    ],
    ruleProfile: { bat_entire_roster_allowed: true },
  });
  assert(
    result.readiness_warnings.some((finding) =>
      finding.code === "bat_entire_roster_omission"
    ),
    "unexplained eligible omission",
  );
});

Deno.test("availability eligibility batting and defense remain separate", () => {
  const result = validateGamePlan({
    lineupMode: "continuous_batting_order",
    batting: hitters(10),
    defense: [
      {
        player_id: "player-0",
        inning_number: 1,
        inning_half: "defense",
        position_code: "P",
      },
      {
        player_id: "player-0",
        inning_number: 1,
        inning_half: "defense",
        position_code: "1B",
      },
      {
        player_id: "defense-only",
        inning_number: 1,
        inning_half: "defense",
        position_code: "RF",
      },
    ],
    pitcherCatcher: [],
    eligibility: [{ player_id: "player-1", status: "unavailable" }],
    ruleProfile: {
      continuous_batting_order_allowed: true,
      defensive_only_players_allowed: true,
    },
  });
  const warnings = result.readiness_warnings.map((finding) => finding.code);
  assert(
    warnings.includes("unavailable_player_in_lineup"),
    "availability warning",
  );
  assert(
    warnings.includes("duplicate_simultaneous_defender"),
    "defense warning",
  );
  assert(
    !result.blocking_errors.some((finding) =>
      finding.code.includes("defensive")
    ),
    "defense-only permitted",
  );
});

Deno.test("missing rules are advisory and never invent MLB rules", () => {
  const result = validateGamePlan({
    lineupMode: "custom",
    batting: hitters(14),
    defense: [],
    pitcherCatcher: [],
    eligibility: [],
    ruleProfile: null,
  });
  assert(result.valid, "no invented maximum");
  assert(
    result.readiness_warnings.some((finding) =>
      finding.code === "missing_rule_profile"
    ),
    "advisory warning",
  );
  assert(
    result.notices.some((finding) =>
      finding.code === "rule_profile_uncertainty"
    ),
    "uncertainty notice",
  );
});

Deno.test("consumer redaction returns only own assignments", () => {
  const output = sanitizeGamePayload(
    {
      plan: { title: "Game", internal_strategy_notes: "private" },
      batting_order: [
        { player_id: "own", notes: "coach", batting_slot: 2 },
        { player_id: "other", batting_slot: 1 },
      ],
      defense: [{ player_id: "own", notes: "private" }, { player_id: "other" }],
      pitcher_catcher: [{ player_id: "own" }, { player_id: "other" }],
      eligibility: [{ player_id: "own", exclusion_reason: "private" }],
      staff: [{ staff_user_id: "coach" }],
      validation: { blocking_errors: [] },
      audit: [{ reason: "private" }],
      recaps: [
        { visibility: "parent", body: "visible" },
        { visibility: "staff", body: "private" },
      ],
    },
    "own",
    "parent",
  );
  assert(
    !(output.plan as Record<string, unknown>).internal_strategy_notes,
    "strategy redacted",
  );
  assert(
    (output.batting_order as unknown[]).length === 1,
    "other lineup redacted",
  );
  assert(output.staff === undefined, "staff redacted");
  assert(output.validation === undefined, "coach validation redacted");
  assert((output.recaps as unknown[]).length === 1, "visibility enforced");
});

Deno.test("schema is additive normalized indexed auditable and RLS protected", async () => {
  const sql = await Deno.readTextFile(migrationURL);
  for (
    const table of [
      "sd_game_rule_profiles",
      "sd_game_plans",
      "sd_game_plan_eligibility",
      "sd_game_batting_entries",
      "sd_game_defensive_assignments",
      "sd_game_pitcher_catcher_plans",
      "sd_game_staff_assignments",
      "sd_game_plan_snapshots",
      "sd_game_active_adjustments",
      "sd_game_results",
      "sd_game_recaps",
      "sd_game_plan_audit_logs",
      "sd_game_plan_mutations",
    ]
  ) {
    assert(sql.includes(`create table if not exists public.${table}`), table);
    assert(
      sql.includes(`alter table public.${table} enable row level security`),
      `${table} RLS`,
    );
  }
  for (
    const token of [
      "uq_sd_game_plans_primary_event",
      "sd_game_plan_snapshot",
      "sd_validate_game_plan",
      "sd_apply_game_plan_mutation",
      "idempotency_mismatch",
      "active_adjustment_required",
      "published_game_plan_delete_forbidden",
      "game_lineup_major_change",
      "view_game_plan",
      "reopen_game_operation",
      "pg_catalog.upper(position_code) not in ('EH','DH')",
    ]
  ) assert(sql.includes(token), token);
  assert(
    !sql.includes("maximum_batting_slots integer not null"),
    "maximum is nullable",
  );
  assert(!sql.includes("batting_slot <= 9"), "no nine-player cap");
});

Deno.test("edge exposes one focused authenticated action surface", async () => {
  const source = await Deno.readTextFile(edgeURL);
  for (
    const action of [
      "fetch_game_plan",
      "fetch_game_plan_history",
      "validate_game_plan",
      "initialize_game_plan",
      "duplicate_prior_game_plan",
      "initialize_multiple_eh",
      "initialize_bat_entire_roster",
      "copy_defensive_inning",
      "assign_pitcher_catcher_pair",
      "capture_started_game_snapshot",
      "apply_active_lineup_adjustment",
      "record_game_result",
      "complete_game_operation",
      "reopen_completed_game",
    ]
  ) assert(source.includes(action), action);
  assert(
    source.includes("sd_resolve_team_capabilities"),
    "central capabilities",
  );
  assert(source.includes("sanitizeGamePayload"), "consumer redaction");
  assert(!source.includes("play_by_play"), "no scorekeeping");
  assert(!source.includes("pitch_by_pitch"), "no pitch tracking");
});
