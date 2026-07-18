export type GameRow = Record<string, unknown>;

export const GAME_PLAN_STATUSES = [
  "draft",
  "ready",
  "published",
  "active",
  "completed",
  "archived",
] as const;

export const LINEUP_MODES = [
  "standard_nine",
  "standard_nine_with_dh",
  "standard_nine_with_one_eh",
  "standard_nine_with_multiple_eh",
  "continuous_batting_order",
  "bat_entire_available_roster",
  "custom",
] as const;

export const OFFENSIVE_ROLES = [
  "hitter",
  "eh",
  "dh",
  "pitcher_batting",
  "offensive_only",
  "substitute",
  "courtesy_runner",
  "bench",
  "custom",
] as const;

export type FindingSeverity =
  | "blocking_error"
  | "readiness_warning"
  | "informational_notice";

export type GameFinding = {
  code: string;
  severity: FindingSeverity;
  actual?: number;
  expected?: number;
};

export type RuleProfile = {
  minimum_batting_slots?: number | null;
  maximum_batting_slots?: number | null;
  continuous_batting_order_allowed?: boolean | null;
  bat_entire_roster_allowed?: boolean | null;
  dh_allowed?: boolean | null;
  eh_allowed?: boolean | null;
  maximum_eh?: number | null;
  defensive_only_players_allowed?: boolean | null;
  offensive_only_players_allowed?: boolean | null;
  defensive_player_count?: number | null;
  required_positions?: string[];
};

export type ValidationInput = {
  lineupMode: string;
  batting: GameRow[];
  defense: GameRow[];
  pitcherCatcher: GameRow[];
  eligibility: GameRow[];
  ruleProfile?: RuleProfile | null;
};

const finding = (
  code: string,
  severity: FindingSeverity,
  numbers: Pick<GameFinding, "actual" | "expected"> = {},
): GameFinding => ({ code, severity, ...numbers });

export function validateGamePlan(input: ValidationInput) {
  const active = input.batting.filter((entry) =>
    entry.active !== false && Number(entry.batting_slot ?? 0) > 0
  );
  const blockingErrors: GameFinding[] = [];
  const readinessWarnings: GameFinding[] = [];
  const notices: GameFinding[] = [];
  const playerIds = active.map((entry) => String(entry.player_id ?? ""));
  const slots = active.map((entry) => Number(entry.batting_slot));
  const ehCount =
    active.filter((entry) => entry.offensive_role === "eh").length;
  if (active.length === 0) {
    blockingErrors.push(finding("no_batting_order", "blocking_error"));
  }
  if (new Set(playerIds).size !== playerIds.length) {
    blockingErrors.push(finding("duplicate_active_hitter", "blocking_error"));
  }
  if (new Set(slots).size !== slots.length) {
    blockingErrors.push(finding("duplicate_batting_slot", "blocking_error"));
  }
  if (slots.length > 0) {
    const ordered = [...slots].sort((a, b) => a - b);
    if (ordered.some((slot, index) => slot !== index + 1)) {
      blockingErrors.push(finding("missing_batting_slot", "blocking_error"));
    }
  }
  const rules = input.ruleProfile;
  if (!rules) {
    readinessWarnings.push(
      finding("missing_rule_profile", "readiness_warning"),
    );
    notices.push(finding("rule_profile_uncertainty", "informational_notice"));
  } else {
    if (
      rules.minimum_batting_slots != null &&
      active.length < rules.minimum_batting_slots
    ) {
      blockingErrors.push(
        finding("batting_order_below_minimum", "blocking_error", {
          actual: active.length,
          expected: rules.minimum_batting_slots,
        }),
      );
    }
    // Null means no cap. It never means zero.
    if (
      rules.maximum_batting_slots != null &&
      active.length > rules.maximum_batting_slots
    ) {
      blockingErrors.push(
        finding("batting_order_above_maximum", "blocking_error", {
          actual: active.length,
          expected: rules.maximum_batting_slots,
        }),
      );
    }
    if (rules.eh_allowed === false && ehCount > 0) {
      blockingErrors.push(finding("eh_disallowed", "blocking_error"));
    }
    if (rules.maximum_eh != null && ehCount > rules.maximum_eh) {
      blockingErrors.push(finding("eh_limit_exceeded", "blocking_error", {
        actual: ehCount,
        expected: rules.maximum_eh,
      }));
    }
    if (
      rules.dh_allowed === false &&
      active.some((entry) => entry.offensive_role === "dh")
    ) blockingErrors.push(finding("dh_disallowed", "blocking_error"));
    if (
      rules.continuous_batting_order_allowed === false &&
      input.lineupMode === "continuous_batting_order"
    ) {
      blockingErrors.push(
        finding("continuous_order_disallowed", "blocking_error"),
      );
    }
    if (
      rules.bat_entire_roster_allowed === false &&
      input.lineupMode === "bat_entire_available_roster"
    ) {
      blockingErrors.push(
        finding("bat_entire_roster_disallowed", "blocking_error"),
      );
    }
  }

  const eligible = input.eligibility.filter((entry) =>
    ["eligible", "tentative", "late", "leaving_early", "pending_confirmation"]
      .includes(String(entry.status))
  );
  if (
    input.lineupMode === "bat_entire_available_roster" &&
    eligible.some((entry) =>
      !playerIds.includes(String(entry.player_id)) &&
      !String(entry.exclusion_reason ?? "").trim()
    )
  ) {
    readinessWarnings.push(
      finding("bat_entire_roster_omission", "readiness_warning"),
    );
  }
  const unavailable = new Set(
    input.eligibility.filter((entry) =>
      ["unavailable", "injured", "suspended", "absent", "rostered_not_dressing"]
        .includes(String(entry.status))
    ).map((entry) => String(entry.player_id)),
  );
  if (playerIds.some((id) => unavailable.has(id))) {
    readinessWarnings.push(
      finding("unavailable_player_in_lineup", "readiness_warning"),
    );
  }

  const simultaneous = new Set<string>();
  for (
    const assignment of input.defense.filter((row) => row.active !== false)
  ) {
    if (String(assignment.position_code).toUpperCase() === "BENCH") continue;
    const key =
      `${assignment.inning_number}:${assignment.inning_half}:${assignment.player_id}`;
    if (simultaneous.has(key)) {
      readinessWarnings.push(
        finding("duplicate_simultaneous_defender", "readiness_warning"),
      );
      break;
    }
    simultaneous.add(key);
  }
  if (
    !input.pitcherCatcher.some((row) => row.role_type === "starting_pitcher")
  ) {
    readinessWarnings.push(
      finding("starting_pitcher_missing", "readiness_warning"),
    );
  }
  if (
    !input.pitcherCatcher.some((row) => row.role_type === "starting_catcher")
  ) {
    readinessWarnings.push(
      finding("starting_catcher_missing", "readiness_warning"),
    );
  }
  return {
    blocking_errors: blockingErrors,
    readiness_warnings: unique(readinessWarnings),
    notices,
    valid: blockingErrors.length === 0,
    batting_count: active.length,
    eh_count: ehCount,
  };
}

function unique(findings: GameFinding[]): GameFinding[] {
  return findings.filter((entry, index) =>
    findings.findIndex((candidate) => candidate.code === entry.code) === index
  );
}

export function sanitizeGamePayload(
  payload: GameRow,
  playerId: string,
  role: "player" | "parent",
): GameRow {
  const own = (value: unknown) =>
    Array.isArray(value)
      ? (value as GameRow[]).filter((row) =>
        String(row.player_id ?? row.subject_player_id) === playerId
      )
      : [];
  const plan = payload.plan && typeof payload.plan === "object"
    ? strip(payload.plan as GameRow, [
      "internal_strategy_notes",
      role === "player" ? "parent_reminders" : "player_reminders",
      "created_by",
      "updated_by",
      "published_by",
    ])
    : payload.plan;
  const visibleRecaps = Array.isArray(payload.recaps)
    ? (payload.recaps as GameRow[]).filter((row) =>
      row.visibility === "team" ||
      (row.visibility === role &&
        (!row.subject_player_id || row.subject_player_id === playerId)) ||
      (row.visibility === "player" && role === "parent" &&
        row.subject_player_id === playerId)
    ).map((row) => strip(row, ["created_by", "updated_by"]))
    : [];
  return {
    ...payload,
    plan,
    batting_order: own(payload.batting_order).map((row) =>
      strip(row, ["notes"])
    ),
    defense: own(payload.defense).map((row) => strip(row, ["notes"])),
    pitcher_catcher: own(payload.pitcher_catcher).map((row) =>
      strip(row, ["notes"])
    ),
    eligibility: own(payload.eligibility).map((row) =>
      strip(row, ["exclusion_reason"])
    ),
    staff: undefined,
    adjustments: undefined,
    audit: undefined,
    validation: undefined,
    rule_profile:
      payload.rule_profile && typeof payload.rule_profile === "object"
        ? strip(payload.rule_profile as GameRow, [
          "notes",
          "created_by",
          "updated_by",
        ])
        : payload.rule_profile,
    recaps: visibleRecaps,
  };
}

function strip(row: GameRow, keys: string[]): GameRow {
  const output = { ...row };
  for (const key of keys) delete output[key];
  return output;
}
