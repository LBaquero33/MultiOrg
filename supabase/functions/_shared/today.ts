export type TodayRole = "coach" | "player" | "parent" | "owner" | "admin";
export type TodayUrgency = "urgent" | "important" | "informational";
export type TodayServiceAvailability =
  | "available"
  | "loading"
  | "stale"
  | "unavailable"
  | "unauthorized"
  | "offline";

export type TodayAction = {
  id: string;
  label: string;
  route: string;
  capability: string | null;
};

export type TodayServiceState = {
  state: TodayServiceAvailability;
  message: string | null;
  as_of: string | null;
};

export type TodayContext = {
  organization_id: string;
  organization_name: string;
  user_id: string;
  role: TodayRole;
  season_id: string | null;
  season_name: string | null;
  team_id: string | null;
  team_name: string | null;
  child_id: string | null;
  child_name: string | null;
  local_date: string;
  timezone: string;
  scope_type: "team" | "personal" | "household" | "organization";
  context_token: string;
  authorized_team_ids: string[];
  linked_child_ids: string[];
  capabilities: string[];
};

export type RawTodayMission = {
  id: string;
  organization_id: string;
  season_id: string | null;
  team_id: string | null;
  team_name: string | null;
  player_ids: string[];
  child_id?: string | null;
  child_name?: string | null;
  event_type: string;
  title: string;
  subtitle?: string | null;
  status: string;
  start_at: string | null;
  arrival_at: string | null;
  end_at: string | null;
  location: string | null;
  operation_state: string | null;
  plan_state: string | null;
  operation_available?: boolean;
  plan_available?: boolean;
  unresolved_availability: number;
  unresolved_attendance: number;
  validation_blockers?: number;
  validation_warnings?: number;
  lineup_mode?: string | null;
  eh_count?: number | null;
  batting_slot?: number | null;
  offensive_role?: string | null;
  defensive_assignment?: string | null;
  pitcher_catcher_assignment?: string | null;
  recap_visible?: boolean;
  required_acknowledgment?: boolean;
  recently_changed?: boolean;
};

export type RawTodayAttention = {
  id: string;
  organization_id: string;
  season_id?: string | null;
  team_id?: string | null;
  child_id?: string | null;
  source_type: string;
  source_id?: string | null;
  category: string;
  severity: TodayUrgency;
  title: string;
  detail?: string | null;
  due_at?: string | null;
  action?: TodayAction | null;
  deep_link?: string | null;
  roles: TodayRole[];
  required_capability?: string | null;
};

export type RawTodaySummary = {
  category: string;
  label: string;
  value: string;
  status?: string | null;
  as_of?: string | null;
  action?: TodayAction | null;
  roles: TodayRole[];
  required_capability?: string | null;
};

export type TodayAggregateInput = {
  context: TodayContext;
  now: string;
  missions: RawTodayMission[];
  attention: RawTodayAttention[];
  summaries: RawTodaySummary[];
  services: Record<string, TodayServiceState>;
};

type TodayMission = {
  id: string;
  source_type: "event";
  source_id: string;
  mission_type: string;
  title: string;
  subtitle: string | null;
  status: string;
  start_at: string | null;
  arrival_at: string | null;
  end_at: string | null;
  location: string | null;
  team_id: string | null;
  team_name: string | null;
  season_id: string | null;
  child_id: string | null;
  child_name: string | null;
  urgency: TodayUrgency;
  is_current: boolean;
  is_next: boolean;
  requires_review: boolean;
  operation_state: string | null;
  plan_state: string | null;
  availability_unresolved: number | null;
  attendance_unresolved: number | null;
  lineup_mode: string | null;
  eh_count: number | null;
  batting_slot: number | null;
  offensive_role: string | null;
  defensive_assignment: string | null;
  pitcher_catcher_assignment: string | null;
  primary_action: TodayAction | null;
  secondary_actions: TodayAction[];
  attention_count: number;
  deep_link: string;
};

const serviceMessage: Record<string, string> = {
  scheduling: "Today’s schedule couldn’t be loaded.",
  event_operations: "Event-operation readiness is temporarily unavailable.",
  practice_planning: "Practice-plan readiness is temporarily unavailable.",
  game_operations: "Game-plan readiness is temporarily unavailable.",
  communication: "Communication attention could not be refreshed.",
  registration: "Registration attention could not be refreshed.",
  finance: "Financial attention could not be refreshed.",
  analytics: "Operational summaries could not be refreshed.",
};

export function unavailableService(name: string): TodayServiceState {
  return {
    state: "unavailable",
    message: serviceMessage[name] ?? "This section is temporarily unavailable.",
    as_of: null,
  };
}

function dateValue(value: string | null): number {
  if (!value) return Number.MAX_SAFE_INTEGER;
  const parsed = Date.parse(value);
  return Number.isFinite(parsed) ? parsed : Number.MAX_SAFE_INTEGER;
}

function visibleMission(
  mission: RawTodayMission,
  context: TodayContext,
): boolean {
  if (mission.organization_id !== context.organization_id) return false;
  if (context.season_id && mission.season_id !== context.season_id) {
    return false;
  }
  switch (context.role) {
    case "coach":
      return context.team_id !== null &&
        mission.team_id === context.team_id &&
        context.authorized_team_ids.includes(context.team_id);
    case "player":
      return mission.player_ids.includes(context.user_id) &&
        (!context.team_id || mission.team_id === context.team_id);
    case "parent":
      return !!mission.child_id &&
        context.linked_child_ids.includes(mission.child_id) &&
        (!context.child_id || mission.child_id === context.child_id);
    case "owner":
    case "admin":
      return true;
  }
}

function action(
  id: string,
  label: string,
  capability: string | null,
  context: TodayContext,
): TodayAction | null {
  if (capability && !context.capabilities.includes(capability)) return null;
  return { id, label, route: "event", capability };
}

export function resolvePrimaryAction(
  mission: RawTodayMission,
  context: TodayContext,
): TodayAction | null {
  if (context.role === "player") {
    if (["cancelled", "postponed"].includes(mission.status)) {
      return action("view_event", "View Event", null, context);
    }
    if (mission.operation_state === "completed" && mission.recap_visible) {
      return action("review_recap", "Review Recap", null, context);
    }
    if (mission.unresolved_availability > 0) {
      return action(
        "update_availability",
        "Update Availability",
        null,
        context,
      );
    }
    if (
      mission.event_type === "practice" && mission.plan_state === "published"
    ) {
      return action(
        "view_practice_assignment",
        "View Practice Assignment",
        null,
        context,
      );
    }
    if (mission.event_type === "game" && mission.plan_state === "published") {
      return action(
        "view_game_assignment",
        "View Game Assignment",
        null,
        context,
      );
    }
    return action("view_event", "View Event", null, context);
  }
  if (context.role === "parent") {
    if (mission.unresolved_availability > 0 && mission.status !== "cancelled") {
      return action(
        "update_child_availability",
        "Update Availability",
        null,
        context,
      );
    }
    return action("view_child_event", "View Event", null, context);
  }
  if (context.role === "owner" || context.role === "admin") {
    return action(
      "review_today_operations",
      "Review Today’s Operations",
      "view_event_operation",
      context,
    );
  }

  if (
    mission.operation_available === false || mission.plan_available === false
  ) {
    return action(
      "review_event",
      "Review Event",
      "view_event_operation",
      context,
    );
  }

  if (["cancelled", "postponed"].includes(mission.status)) {
    return action(
      "review_event",
      "Review Event",
      "view_event_operation",
      context,
    );
  }
  if (mission.operation_state === "completed") {
    if (mission.unresolved_attendance > 0) {
      return action(
        "resolve_attendance",
        "Resolve Attendance",
        "manage_event_attendance",
        context,
      );
    }
    return action(
      "review_completed",
      "Review Completed Event",
      "view_event_operation",
      context,
    );
  }
  if (mission.operation_state === "in_progress") {
    return action(
      "complete_event",
      "Complete Event",
      "complete_event_operation",
      context,
    );
  }
  if (mission.operation_state === "paused") {
    return mission.event_type === "game"
      ? action("resume_game", "Resume Game Day", "manage_game", context)
      : action(
        "resume_practice",
        "Resume Practice",
        "manage_practice",
        context,
      );
  }
  if (mission.unresolved_availability > 0) {
    return action(
      "review_availability",
      "Review Availability",
      "manage_event_availability",
      context,
    );
  }
  if ((mission.validation_blockers ?? 0) > 0) {
    return action(
      "resolve_readiness",
      "Resolve Readiness Warnings",
      mission.event_type === "game" ? "edit_game_plan" : "edit_practice_plan",
      context,
    );
  }
  if (mission.event_type === "practice") {
    if (!mission.plan_state) {
      return action(
        "prepare_practice",
        "Prepare Practice",
        "create_practice_plan",
        context,
      );
    }
    if (["draft", "ready"].includes(mission.plan_state)) {
      return action(
        "review_practice",
        "Review Practice Plan",
        "edit_practice_plan",
        context,
      );
    }
    if (mission.plan_state === "published") {
      return action(
        "start_practice",
        "Start Practice",
        "start_event_operation",
        context,
      );
    }
  }
  if (mission.event_type === "game") {
    if (!mission.plan_state) {
      return action(
        "prepare_game",
        "Prepare Game",
        "create_game_plan",
        context,
      );
    }
    if (["draft", "ready"].includes(mission.plan_state)) {
      return action(
        "build_lineup",
        "Build Lineup",
        "manage_batting_order",
        context,
      );
    }
    if (mission.plan_state === "published") {
      return action(
        "start_game",
        "Start Game Day",
        "start_event_operation",
        context,
      );
    }
  }
  return action(
    "start_check_in",
    "Start Check-In",
    "start_event_operation",
    context,
  );
}

function missionPriority(mission: TodayMission, now: number): number {
  if (
    mission.is_current ||
    ["active", "in_progress", "paused"].includes(mission.operation_state ?? "")
  ) return 0;
  const arrival = dateValue(mission.arrival_at);
  const end = dateValue(mission.end_at ?? mission.start_at);
  if (
    !["cancelled", "postponed"].includes(mission.status) && arrival <= now &&
    end >= now
  ) return 1;
  if (mission.is_next) return 2;
  if (
    !["completed", "cancelled", "postponed"].includes(mission.status) &&
    dateValue(mission.start_at) >= now
  ) return 3;
  if (mission.requires_review) return 4;
  return 5;
}

function attentionVisible(
  item: RawTodayAttention,
  context: TodayContext,
): boolean {
  if (
    item.organization_id !== context.organization_id ||
    !item.roles.includes(context.role)
  ) return false;
  if (
    context.season_id && item.season_id && item.season_id !== context.season_id
  ) return false;
  if (context.role === "coach" && item.team_id !== context.team_id) {
    return false;
  }
  if (
    context.role === "parent" && item.child_id &&
    !context.linked_child_ids.includes(item.child_id)
  ) return false;
  if (
    item.required_capability &&
    !context.capabilities.includes(item.required_capability)
  ) return false;
  return true;
}

function urgencyRank(value: TodayUrgency): number {
  return value === "urgent" ? 0 : value === "important" ? 1 : 2;
}

export function buildTodayAggregate(input: TodayAggregateInput) {
  const now = Date.parse(input.now);
  const visible = input.missions.filter((mission) =>
    visibleMission(mission, input.context)
  );
  const nextId = visible
    .filter((mission) =>
      !["cancelled", "postponed", "completed"].includes(mission.status) &&
      dateValue(mission.start_at) >= now
    )
    .sort((a, b) =>
      dateValue(a.arrival_at ?? a.start_at) -
        dateValue(b.arrival_at ?? b.start_at) || a.id.localeCompare(b.id)
    )[0]?.id;

  const missions: TodayMission[] = visible.map((raw): TodayMission => {
    const start = dateValue(raw.start_at);
    const end = dateValue(raw.end_at);
    const isCurrent =
      !["cancelled", "postponed", "completed"].includes(raw.status) &&
      start <= now && end >= now;
    const requiresReview = raw.operation_state === "completed" &&
      (raw.unresolved_attendance > 0 ||
        (raw.event_type === "game" && !raw.recap_visible));
    const attentionCount = (raw.operation_available === false
      ? 0
      : raw.unresolved_availability + raw.unresolved_attendance) +
      (raw.plan_available === false || raw.plan_state ? 0 : 1) +
      (raw.validation_blockers ?? 0) +
      (raw.validation_warnings ?? 0);
    const consumer = input.context.role === "player" ||
      input.context.role === "parent";
    return {
      id: `${raw.child_id ?? input.context.user_id}:${raw.id}`,
      source_type: "event",
      source_id: raw.id,
      mission_type: raw.event_type,
      title: raw.title,
      subtitle: raw.subtitle ?? null,
      status: raw.status,
      start_at: raw.start_at,
      arrival_at: raw.arrival_at,
      end_at: raw.end_at,
      location: raw.location,
      team_id: raw.team_id,
      team_name: raw.team_name,
      season_id: raw.season_id,
      child_id: raw.child_id ?? null,
      child_name: raw.child_name ?? null,
      urgency: isCurrent || requiresReview
        ? "urgent"
        : attentionCount > 0
        ? "important"
        : "informational",
      is_current: isCurrent,
      is_next: raw.id === nextId,
      requires_review: requiresReview,
      operation_state: raw.operation_state,
      plan_state: raw.plan_state,
      availability_unresolved: consumer || raw.operation_available === false
        ? null
        : raw.unresolved_availability,
      attendance_unresolved: consumer || raw.operation_available === false
        ? null
        : raw.unresolved_attendance,
      lineup_mode: raw.lineup_mode ?? null,
      eh_count: consumer ? null : raw.eh_count ?? null,
      batting_slot: raw.batting_slot ?? null,
      offensive_role: raw.offensive_role ?? null,
      defensive_assignment: raw.defensive_assignment ?? null,
      pitcher_catcher_assignment: raw.pitcher_catcher_assignment ?? null,
      primary_action: resolvePrimaryAction(raw, input.context),
      secondary_actions: [],
      attention_count: consumer ? 0 : attentionCount,
      deep_link: `homeplate://event/${raw.id}`,
    };
  }).sort((a, b) =>
    missionPriority(a, now) - missionPriority(b, now) ||
    dateValue(a.arrival_at ?? a.start_at) -
      dateValue(b.arrival_at ?? b.start_at) ||
    a.id.localeCompare(b.id)
  );

  const attention = input.attention.filter((item) =>
    attentionVisible(item, input.context)
  ).sort((a, b) =>
    urgencyRank(a.severity) - urgencyRank(b.severity) ||
    dateValue(a.due_at ?? null) - dateValue(b.due_at ?? null) ||
    a.id.localeCompare(b.id)
  ).map((item) => ({
    id: item.id,
    source_type: item.source_type,
    source_id: item.source_id ?? null,
    category: item.category,
    severity: item.severity,
    title: item.title,
    detail: item.detail ?? null,
    due_at: item.due_at ?? null,
    action: item.action ?? null,
    deep_link: item.deep_link ?? null,
  }));

  const summaries = input.summaries.filter((summary) =>
    summary.roles.includes(input.context.role) &&
    (!summary.required_capability ||
      input.context.capabilities.includes(summary.required_capability))
  ).map(({ roles: _roles, required_capability: _required, ...summary }) => ({
    ...summary,
    status: summary.status ?? null,
    as_of: summary.as_of ?? null,
    action: summary.action ?? null,
  }));
  const primaryAction = attention.find((item) => item.action)?.action ??
    missions.find((mission) => mission.primary_action)?.primary_action ?? null;
  const {
    user_id: _userId,
    authorized_team_ids: _teams,
    linked_child_ids: _children,
    ...publicContext
  } = input.context;
  return {
    context: publicContext,
    missions,
    attention_items: attention,
    summaries,
    primary_action: primaryAction,
    secondary_actions: [],
    services: input.services,
    capabilities: input.context.capabilities,
    generated_at: input.now,
    as_of: input.now,
  };
}

export function contextToken(parts: Array<string | null | undefined>): string {
  return parts.map((part) => part ?? "none").join(":");
}
