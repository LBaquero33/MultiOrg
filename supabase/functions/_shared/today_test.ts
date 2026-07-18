import {
  buildTodayAggregate,
  contextToken,
  type RawTodayMission,
  resolvePrimaryAction,
  type TodayAggregateInput,
  type TodayContext,
  unavailableService,
} from "./today.ts";

function assert(condition: boolean, message: string) {
  if (!condition) throw new Error(message);
}

const now = "2026-07-18T14:00:00.000Z";
const org = "11111111-1111-4111-8111-111111111111";
const otherOrg = "22222222-2222-4222-8222-222222222222";
const team = "33333333-3333-4333-8333-333333333333";
const otherTeam = "44444444-4444-4444-8444-444444444444";
const user = "55555555-5555-4555-8555-555555555555";
const child = "66666666-6666-4666-8666-666666666666";

function context(role: TodayContext["role"]): TodayContext {
  return {
    organization_id: org,
    organization_name: "Home Plate Academy",
    user_id: user,
    role,
    season_id: "77777777-7777-4777-8777-777777777777",
    season_name: "Summer",
    team_id: team,
    team_name: "14U Navy",
    child_id: null,
    child_name: null,
    local_date: "2026-07-18",
    timezone: "America/New_York",
    scope_type: role === "coach"
      ? "team"
      : role === "player"
      ? "personal"
      : role === "parent"
      ? "household"
      : "organization",
    context_token: contextToken([
      org,
      role,
      team,
      "2026-07-18",
      "America/New_York",
    ]),
    authorized_team_ids: [team],
    linked_child_ids: [child],
    capabilities: [
      "view_event_operation",
      "manage_event_availability",
      "manage_event_attendance",
      "start_event_operation",
      "complete_event_operation",
      "create_practice_plan",
      "edit_practice_plan",
      "manage_practice",
      "create_game_plan",
      "edit_game_plan",
      "manage_game",
      "manage_batting_order",
      "review_registrations",
      "view_financial_overview",
    ],
  };
}

function mission(overrides: Partial<RawTodayMission> = {}): RawTodayMission {
  return {
    id: "88888888-8888-4888-8888-888888888888",
    organization_id: org,
    season_id: context("coach").season_id,
    team_id: team,
    team_name: "14U Navy",
    player_ids: [user],
    event_type: "practice",
    title: "Practice",
    status: "published",
    start_at: "2026-07-18T15:00:00.000Z",
    arrival_at: "2026-07-18T14:30:00.000Z",
    end_at: "2026-07-18T17:00:00.000Z",
    location: "Field 2",
    operation_state: "ready",
    plan_state: "published",
    unresolved_availability: 0,
    unresolved_attendance: 0,
    ...overrides,
  };
}

function input(
  role: TodayContext["role"],
  missions: RawTodayMission[],
): TodayAggregateInput {
  return {
    context: context(role),
    now,
    missions,
    attention: [],
    summaries: [],
    services: { scheduling: { state: "available", message: null, as_of: now } },
  };
}

Deno.test("Today aggregate isolates organization season team child and household scope", () => {
  const candidates = [
    mission(),
    mission({ id: crypto.randomUUID(), organization_id: otherOrg }),
    mission({ id: crypto.randomUUID(), team_id: otherTeam }),
  ];
  assert(
    buildTodayAggregate(input("coach", candidates)).missions.length === 1,
    "coach isolation",
  );
  const parentMission = mission({
    id: crypto.randomUUID(),
    child_id: child,
    player_ids: [child],
  });
  const unrelatedChild = mission({
    id: crypto.randomUUID(),
    child_id: crypto.randomUUID(),
    player_ids: [],
  });
  assert(
    buildTodayAggregate(input("parent", [parentMission, unrelatedChild]))
      .missions.length === 1,
    "household isolation",
  );
});

Deno.test("player and parent responses redact team-wide readiness and other-player data", () => {
  for (const role of ["player", "parent"] as const) {
    const candidate = mission(
      role === "parent" ? { child_id: child, player_ids: [child] } : {},
    );
    const result = buildTodayAggregate(input(role, [candidate]));
    assert(
      result.missions[0].availability_unresolved === null,
      `${role} availability redacted`,
    );
    assert(
      result.missions[0].attendance_unresolved === null,
      `${role} attendance redacted`,
    );
    assert(result.missions[0].eh_count === null, `${role} EH count redacted`);
  }
});

Deno.test("mission ordering is active arrival-window next later review completed and stable", () => {
  const missions = [
    mission({
      id: "f",
      status: "completed",
      operation_state: "completed",
      start_at: "2026-07-18T10:00:00Z",
    }),
    mission({
      id: "e",
      status: "completed",
      operation_state: "completed",
      unresolved_attendance: 1,
      start_at: "2026-07-18T11:00:00Z",
    }),
    mission({ id: "d", start_at: "2026-07-18T20:00:00Z", arrival_at: null }),
    mission({ id: "c", start_at: "2026-07-18T16:00:00Z", arrival_at: null }),
    mission({
      id: "b",
      start_at: "2026-07-18T14:30:00Z",
      arrival_at: "2026-07-18T13:30:00Z",
      end_at: "2026-07-18T16:00:00Z",
    }),
    mission({
      id: "a",
      operation_state: "in_progress",
      start_at: "2026-07-18T13:00:00Z",
      end_at: "2026-07-18T15:00:00Z",
    }),
  ];
  const ids = buildTodayAggregate(input("coach", missions)).missions.map((
    item,
  ) => item.source_id);
  assert(ids.join("") === "abcdef", `ordering ${ids.join("")}`);
});

Deno.test("cancelled and postponed events never resolve a start action", () => {
  for (const status of ["cancelled", "postponed"]) {
    const result = buildTodayAggregate(input("coach", [mission({ status })]));
    assert(result.missions[0].primary_action?.id === "review_event", status);
    assert(!result.missions[0].is_current, `${status} not current`);
  }
});

Deno.test("coach primary actions honor readiness lifecycle and capabilities", () => {
  const coach = context("coach");
  assert(
    resolvePrimaryAction(mission({ unresolved_availability: 3 }), coach)?.id ===
      "review_availability",
    "availability",
  );
  assert(
    resolvePrimaryAction(mission({ plan_state: null }), coach)?.id ===
      "prepare_practice",
    "missing plan",
  );
  assert(
    resolvePrimaryAction(
      mission({ event_type: "game", plan_state: "draft" }),
      coach,
    )?.id === "build_lineup",
    "game lineup",
  );
  assert(
    resolvePrimaryAction(
      mission({ event_type: "game", plan_state: "published" }),
      coach,
    )?.id === "start_game",
    "game start",
  );
  assert(
    resolvePrimaryAction(
      mission({ operation_state: "completed", unresolved_attendance: 1 }),
      coach,
    )?.id === "resolve_attendance",
    "attendance",
  );
  assert(
    resolvePrimaryAction(mission({ operation_state: "paused" }), coach)?.id ===
      "resume_practice",
    "resume",
  );
  const readOnly = { ...coach, capabilities: ["view_event_operation"] };
  assert(
    resolvePrimaryAction(mission({ plan_state: null }), readOnly) === null,
    "permission hidden",
  );
});

Deno.test("player assignment supports multiple EH and Bat Entire Roster without private strategy", () => {
  const result = buildTodayAggregate(input("player", [mission({
    event_type: "game",
    lineup_mode: "bat_entire_available_roster",
    eh_count: 3,
    batting_slot: 7,
    offensive_role: "eh",
  })]));
  assert(
    result.missions[0].lineup_mode === "bat_entire_available_roster",
    "BER state",
  );
  assert(
    result.missions[0].offensive_role === "eh",
    "own EH assignment",
  );
  assert(result.missions[0].eh_count === null, "team EH count redacted");
});

Deno.test("attention ordering and role authorization are deterministic", () => {
  const value = input("owner", []);
  value.attention = [
    {
      id: "z",
      organization_id: org,
      source_type: "finance",
      category: "receivable",
      severity: "important",
      title: "Receivable",
      roles: ["owner", "admin"],
      required_capability: "view_financial_overview",
    },
    {
      id: "b",
      organization_id: org,
      source_type: "registration",
      category: "missing_requirement",
      severity: "urgent",
      title: "Requirement",
      roles: ["owner", "admin", "parent"],
    },
    {
      id: "a",
      organization_id: org,
      source_type: "communication",
      category: "failed_delivery",
      severity: "urgent",
      title: "Delivery",
      roles: ["owner", "admin"],
    },
    {
      id: "private",
      organization_id: org,
      source_type: "finance",
      category: "finance",
      severity: "urgent",
      title: "Private",
      roles: ["coach"],
    },
  ];
  assert(
    buildTodayAggregate(value).attention_items.map((item) => item.id).join(
      ",",
    ) === "a,b,z",
    "ordered and authorized",
  );
});

Deno.test("no-event and partial-service failures are truthful", () => {
  const value = input("coach", []);
  value.services.practice_planning = unavailableService("practice_planning");
  const result = buildTodayAggregate(value);
  assert(result.missions.length === 0, "no fabricated mission");
  assert(
    result.services.scheduling.state === "available",
    "schedule remains available",
  );
  assert(
    result.services.practice_planning.state === "unavailable",
    "plan scoped unavailable",
  );
  assert(
    result.services.practice_planning.message ===
      "Practice-plan readiness is temporarily unavailable.",
    "controlled copy",
  );
});

Deno.test("event-operation outage does not fabricate zero readiness", () => {
  const value = input("coach", [mission({ operation_available: false })]);
  value.services.event_operations = unavailableService("event_operations");
  const result = buildTodayAggregate(value);
  assert(
    result.missions[0].availability_unresolved === null,
    "availability is unknown",
  );
  assert(
    result.missions[0].attendance_unresolved === null,
    "attendance is unknown",
  );
  assert(
    result.missions[0].primary_action?.id === "review_event",
    "no unsafe action during outage",
  );
});

Deno.test("generated_at as_of timezone and context token are explicit", () => {
  const result = buildTodayAggregate(input("coach", []));
  assert(result.generated_at === now && result.as_of === now, "timestamps");
  assert(result.context.timezone === "America/New_York", "timezone");
  assert(result.context.context_token.includes("2026-07-18"), "context token");
  assert(!("user_id" in result.context), "private server context removed");
});
