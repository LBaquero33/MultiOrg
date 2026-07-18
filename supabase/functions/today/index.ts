import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import {
  buildTodayAggregate,
  contextToken,
  type RawTodayAttention,
  type RawTodayMission,
  type RawTodaySummary,
  type TodayContext,
  type TodayRole,
  type TodayServiceState,
  unavailableService,
} from "../_shared/today.ts";

const env = (name: string) => (Deno.env.get(name) ?? "").trim();
const url = env("SUPABASE_URL") || env("DHD_SUPABASE_URL");
const anonKey = env("SUPABASE_ANON_KEY") || env("DHD_SUPABASE_ANON_KEY");
const serviceKey = env("DHD_SERVICE_ROLE_KEY") ||
  env("SUPABASE_SERVICE_ROLE_KEY");

type RequestBody = {
  organization_id?: string;
  season_id?: string | null;
  team_id?: string | null;
  child_id?: string | null;
  local_date?: string;
  timezone?: string;
  context_token?: string;
};

type Row = Record<string, unknown>;

function json(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });
}

function uuid(value: unknown): string | null {
  return typeof value === "string" &&
      /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
        .test(value)
    ? value.toLowerCase()
    : null;
}

function isoLocalDate(value: unknown): string | null {
  return typeof value === "string" && /^\d{4}-\d{2}-\d{2}$/.test(value)
    ? value
    : null;
}

function role(value: unknown): TodayRole | null {
  const normalized = typeof value === "string"
    ? value.trim().toLowerCase()
    : "";
  return ["coach", "player", "parent", "owner", "admin"].includes(normalized)
    ? normalized as TodayRole
    : null;
}

function zonedDate(localDate: string, timezone: string): Date {
  const guess = new Date(`${localDate}T00:00:00.000Z`);
  const parts = new Intl.DateTimeFormat("en-US", {
    timeZone: timezone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
    hourCycle: "h23",
  }).formatToParts(guess);
  const get = (name: string) =>
    Number(parts.find((part) => part.type === name)?.value ?? 0);
  const represented = Date.UTC(
    get("year"),
    get("month") - 1,
    get("day"),
    get("hour"),
    get("minute"),
    get("second"),
  );
  return new Date(guess.getTime() - (represented - guess.getTime()));
}

function nextDate(localDate: string, days = 1): string {
  const date = new Date(`${localDate}T12:00:00Z`);
  date.setUTCDate(date.getUTCDate() + days);
  return date.toISOString().slice(0, 10);
}

function available(asOf: string): TodayServiceState {
  return { state: "available", message: null, as_of: asOf };
}

function count(rows: Row[], predicate: (row: Row) => boolean): number {
  return rows.reduce((total, row) => total + (predicate(row) ? 1 : 0), 0);
}

Deno.serve(async (request) => {
  if (request.method !== "POST") {
    return json(405, { error: "method_not_allowed" });
  }
  if (!url || !anonKey || !serviceKey) {
    return json(503, { error: "service_unavailable" });
  }

  const authorization = request.headers.get("Authorization") ?? "";
  if (!authorization) return json(401, { error: "unauthorized" });
  const userClient = createClient(url, anonKey, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: userData, error: userError } = await userClient.auth.getUser();
  const userId = userData.user?.id ?? null;
  if (userError || !userId) return json(401, { error: "unauthorized" });

  let body: RequestBody;
  try {
    body = await request.json();
  } catch {
    return json(400, { error: "invalid_request" });
  }
  const organizationId = uuid(body.organization_id);
  const localDate = isoLocalDate(body.local_date);
  const timezone =
    typeof body.timezone === "string" && body.timezone.length <= 80
      ? body.timezone
      : null;
  if (!organizationId || !localDate || !timezone) {
    return json(400, { error: "invalid_context" });
  }
  try {
    new Intl.DateTimeFormat("en-US", { timeZone: timezone });
  } catch {
    return json(400, { error: "invalid_timezone" });
  }

  const admin = createClient(url, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const membershipResult = await admin.from("sd_org_memberships").select(
    "role,status",
  ).eq("org_id", organizationId).eq("user_id", userId).maybeSingle();
  const activeRole = role(membershipResult.data?.role);
  if (
    membershipResult.error || membershipResult.data?.status !== "active" ||
    !activeRole
  ) {
    return json(403, { error: "forbidden" });
  }

  const now = new Date().toISOString();
  const services: Record<string, TodayServiceState> = {};
  const attention: RawTodayAttention[] = [];
  const summaries: RawTodaySummary[] = [];
  const requestedSeasonId = uuid(body.season_id);
  const requestedTeamId = uuid(body.team_id);
  const requestedChildId = uuid(body.child_id);

  const [organizationResult, seasonsResult] = await Promise.all([
    admin.from("sd_orgs").select("id,name,status").eq("id", organizationId)
      .maybeSingle(),
    admin.from("sd_seasons").select("id,name,status,is_default,start_date").eq(
      "organization_id",
      organizationId,
    ).neq("status", "archived").order("is_default", { ascending: false }).order(
      "start_date",
      { ascending: false, nullsFirst: false },
    ),
  ]);
  if (
    organizationResult.error || organizationResult.data?.status !== "active"
  ) return json(403, { error: "forbidden" });
  const seasons = (seasonsResult.data ?? []) as Row[];
  const hasOperationalSeason = seasons.some((item) =>
    ["active", "playoffs", "registration_open", "roster_building"].includes(
      String(item.status),
    )
  );
  const season = seasons.find((item) => item.id === requestedSeasonId) ??
    seasons.find((item) =>
      ["active", "playoffs", "registration_open", "roster_building"].includes(
        String(item.status),
      )
    ) ?? seasons[0] ?? null;
  const seasonId = typeof season?.id === "string" ? season.id : null;

  let authorizedTeamIds: string[] = [];
  let linkedChildIds: string[] = [];
  let selectedTeamId: string | null = null;
  const organizationCapabilities = await admin.rpc(
    "sd_resolve_organization_capabilities",
    { target_organization: organizationId, target_actor: userId },
  );
  if (organizationCapabilities.error) {
    return json(503, { error: "service_unavailable" });
  }
  let capabilities: string[] = (organizationCapabilities.data ?? []).map(
    String,
  );
  let playerMemberships: Row[] = [];

  async function teamCapabilities(teamId: string): Promise<string[]> {
    const resolved = await admin.rpc("sd_resolve_team_capabilities", {
      target_organization: organizationId,
      target_team: teamId,
      target_actor: userId,
    });
    return resolved.error ? [] : (resolved.data ?? []).map(String);
  }

  if (activeRole === "coach") {
    const assignments = await admin.from("sd_coach_team_assignments").select(
      "team_id,season_id,is_primary",
    ).eq("organization_id", organizationId).eq("coach_id", userId).eq(
      "active",
      true,
    );
    if (assignments.error) return json(503, { error: "service_unavailable" });
    authorizedTeamIds = ((assignments.data ?? []) as Row[]).filter((item) =>
      !seasonId || item.season_id === seasonId
    ).map((item) => String(item.team_id));
    selectedTeamId =
      requestedTeamId && authorizedTeamIds.includes(requestedTeamId)
        ? requestedTeamId
        : authorizedTeamIds.length === 1
        ? authorizedTeamIds[0]
        : ((assignments.data ?? []) as Row[]).find((item) =>
          item.is_primary === true &&
          authorizedTeamIds.includes(String(item.team_id))
        )?.team_id as string ?? null;
    if (selectedTeamId) {
      capabilities = [
        ...new Set([
          ...capabilities,
          ...await teamCapabilities(selectedTeamId),
        ]),
      ];
    }
  } else if (activeRole === "player") {
    const result = await admin.from("sd_player_team_memberships").select(
      "player_id,team_id,season_id",
    ).eq("organization_id", organizationId).eq("player_id", userId).eq(
      "active",
      true,
    );
    playerMemberships = (result.data ?? []) as Row[];
    authorizedTeamIds = playerMemberships.filter((item) =>
      !seasonId || item.season_id === seasonId
    ).map((item) => String(item.team_id));
    selectedTeamId =
      requestedTeamId && authorizedTeamIds.includes(requestedTeamId)
        ? requestedTeamId
        : authorizedTeamIds[0] ?? null;
  } else if (activeRole === "parent") {
    const links = await admin.from("sd_parent_child_links").select("child_id")
      .eq("org_id", organizationId).eq("parent_id", userId);
    if (links.error) return json(503, { error: "service_unavailable" });
    linkedChildIds = ((links.data ?? []) as Row[]).map((item) =>
      String(item.child_id)
    );
    if (requestedChildId && !linkedChildIds.includes(requestedChildId)) {
      return json(403, { error: "forbidden" });
    }
    if (linkedChildIds.length > 0) {
      const result = await admin.from("sd_player_team_memberships").select(
        "player_id,team_id,season_id",
      ).eq("organization_id", organizationId).in("player_id", linkedChildIds)
        .eq("active", true);
      playerMemberships = (result.data ?? []) as Row[];
      authorizedTeamIds = [
        ...new Set(
          playerMemberships.filter((item) =>
            !seasonId || item.season_id === seasonId
          ).map((item) => String(item.team_id)),
        ),
      ];
    }
  } else {
    let teamsQuery = admin.from("sd_teams").select("id,season_id").eq(
      "org_id",
      organizationId,
    ).eq("is_active", true);
    if (seasonId) teamsQuery = teamsQuery.eq("season_id", seasonId);
    const teams = await teamsQuery;
    authorizedTeamIds = ((teams.data ?? []) as Row[]).map((item) =>
      String(item.id)
    );
    const resolved = await Promise.all(
      authorizedTeamIds.map(teamCapabilities),
    );
    capabilities = [...new Set([...capabilities, ...resolved.flat()])];
  }

  const teamResult = authorizedTeamIds.length === 0
    ? { data: [], error: null }
    : await admin.from("sd_teams").select("id,name,season_id,is_active").eq(
      "org_id",
      organizationId,
    ).in("id", authorizedTeamIds);
  const teams = (teamResult.data ?? []) as Row[];
  const selectedTeam = teams.find((item) => item.id === selectedTeamId) ?? null;
  const childProfiles = linkedChildIds.length === 0
    ? { data: [], error: null }
    : await admin.from("profiles").select("id,full_name").in(
      "id",
      linkedChildIds,
    );
  const childNames = new Map(
    ((childProfiles.data ?? []) as Row[]).map((
      item,
    ) => [String(item.id), String(item.full_name ?? "Player")]),
  );

  const context: TodayContext = {
    organization_id: organizationId,
    organization_name: String(organizationResult.data.name ?? "Organization"),
    user_id: userId,
    role: activeRole,
    season_id: seasonId,
    season_name: season ? String(season.name) : null,
    team_id: selectedTeamId,
    team_name: selectedTeam ? String(selectedTeam.name) : null,
    child_id: requestedChildId,
    child_name: requestedChildId
      ? childNames.get(requestedChildId) ?? "Player"
      : null,
    local_date: localDate,
    timezone,
    scope_type: activeRole === "coach"
      ? "team"
      : activeRole === "player"
      ? "personal"
      : activeRole === "parent"
      ? "household"
      : "organization",
    context_token: contextToken([
      organizationId,
      activeRole,
      seasonId,
      selectedTeamId,
      requestedChildId,
      localDate,
      timezone,
    ]),
    authorized_team_ids: authorizedTeamIds,
    linked_child_ids: linkedChildIds,
    capabilities,
  };

  const rangeStart = zonedDate(localDate, timezone).toISOString();
  const todayRangeEnd = zonedDate(nextDate(localDate), timezone).toISOString();
  // Include a bounded upcoming window so no-event Today can truthfully show
  // the next canonical event without a second aggregation request.
  const rangeEnd = zonedDate(nextDate(localDate, 30), timezone).toISOString();
  let rawMissions: RawTodayMission[] = [];
  if (
    (activeRole === "coach" && !selectedTeamId) ||
    ((activeRole === "player" || activeRole === "parent") &&
      authorizedTeamIds.length === 0)
  ) {
    services.scheduling = available(now);
  } else {
    let eventQuery = admin.from("sd_team_events").select(
      "id,organization_id,season_id,team_id,event_type,title,status,start_at,end_at,arrival_at,location_name,visibility,updated_at",
    ).eq("organization_id", organizationId).lt("start_at", rangeEnd).gt(
      "end_at",
      rangeStart,
    ).neq("status", "draft").order("start_at").limit(50);
    if (seasonId) eventQuery = eventQuery.eq("season_id", seasonId);
    if (selectedTeamId) eventQuery = eventQuery.eq("team_id", selectedTeamId);
    else if (
      authorizedTeamIds.length > 0 &&
      !(activeRole === "owner" || activeRole === "admin")
    ) eventQuery = eventQuery.in("team_id", authorizedTeamIds);
    const eventsResult = await eventQuery;
    if (eventsResult.error) {
      services.scheduling = unavailableService("scheduling");
    } else {
      services.scheduling = available(now);
      const events = ((eventsResult.data ?? []) as Row[]).filter((event) =>
        !(activeRole === "player" || activeRole === "parent") ||
        event.visibility !== "staff_only"
      );
      const eventIds = events.map((event) => String(event.id));
      const operationResult = eventIds.length === 0
        ? { data: [], error: null }
        : await admin.from("sd_event_operations").select(
          "id,event_id,status,attendance_finalized_at",
        ).eq("organization_id", organizationId).in("event_id", eventIds);
      services.event_operations = operationResult.error
        ? unavailableService("event_operations")
        : available(now);
      const operations = (operationResult.data ?? []) as Row[];
      const operationIds = operations.map((item) => String(item.id));
      const participantsResult = operationIds.length === 0
        ? { data: [], error: null }
        : await admin.from("sd_event_operation_participants").select(
          "event_operation_id,event_id,user_id,participant_type,expected,availability_status,attendance_status",
        ).eq("organization_id", organizationId).in(
          "event_operation_id",
          operationIds,
        );
      if (participantsResult.error) {
        services.event_operations = unavailableService("event_operations");
      }
      const participants = (participantsResult.data ?? []) as Row[];
      const practiceIds = events.filter((event) =>
        event.event_type === "practice"
      ).map((event) => String(event.id));
      const gameIds = events.filter((event) => event.event_type === "game").map(
        (event) => String(event.id),
      );
      const [practiceResult, gamePlanResult, gameDetailResult] = await Promise
        .all([
          practiceIds.length === 0
            ? Promise.resolve({ data: [], error: null })
            : admin.from("sd_practice_plans").select("id,event_id,status").eq(
              "organization_id",
              organizationId,
            ).eq("is_primary", true).is("archived_at", null).in(
              "event_id",
              practiceIds,
            ),
          gameIds.length === 0
            ? Promise.resolve({ data: [], error: null })
            : admin.from("sd_game_plans").select(
              "id,event_id,status,lineup_mode",
            ).eq("organization_id", organizationId).eq("is_primary", true).is(
              "archived_at",
              null,
            ).in("event_id", gameIds),
          gameIds.length === 0
            ? Promise.resolve({ data: [], error: null })
            : admin.from("sd_team_event_games").select(
              "event_id,opponent,venue_side,uniform,game_status",
            ).in("event_id", gameIds),
        ]);
      services.practice_planning = practiceResult.error
        ? unavailableService("practice_planning")
        : available(now);
      services.game_operations = gamePlanResult.error
        ? unavailableService("game_operations")
        : available(now);
      const practices = new Map(
        ((practiceResult.data ?? []) as Row[]).map((
          item,
        ) => [String(item.event_id), item]),
      );
      const gamePlans = new Map(
        ((gamePlanResult.data ?? []) as Row[]).map((
          item,
        ) => [String(item.event_id), item]),
      );
      const gameDetails = new Map(
        ((gameDetailResult.data ?? []) as Row[]).map((
          item,
        ) => [String(item.event_id), item]),
      );
      const gamePlanIds = ((gamePlanResult.data ?? []) as Row[]).map((item) =>
        String(item.id)
      );
      const [battingResult, defenseResult, batteryResult] = await Promise.all([
        gamePlanIds.length === 0
          ? Promise.resolve({ data: [], error: null })
          : admin.from("sd_game_batting_entries").select(
            "game_plan_id,player_id,batting_slot,offensive_role",
          ).eq("organization_id", organizationId).eq("active", true).in(
            "game_plan_id",
            gamePlanIds,
          ),
        gamePlanIds.length === 0
          ? Promise.resolve({ data: [], error: null })
          : admin.from("sd_game_defensive_assignments").select(
            "game_plan_id,player_id,inning_number,position_label,position_code",
          ).eq("organization_id", organizationId).eq("active", true).in(
            "game_plan_id",
            gamePlanIds,
          ).order("inning_number"),
        gamePlanIds.length === 0
          ? Promise.resolve({ data: [], error: null })
          : admin.from("sd_game_pitcher_catcher_plans").select(
            "game_plan_id,player_id,role_type,status",
          ).eq("organization_id", organizationId).is("archived_at", null).in(
            "game_plan_id",
            gamePlanIds,
          ).order("sequence_index"),
      ]);
      if (battingResult.error || defenseResult.error || batteryResult.error) {
        services.game_operations = unavailableService("game_operations");
      }
      const batting = (battingResult.data ?? []) as Row[];
      const defense = (defenseResult.data ?? []) as Row[];
      const battery = (batteryResult.data ?? []) as Row[];
      const assignment = (planId: string | null, playerId: string | null) => {
        if (!planId || !playerId) return {};
        const bat = batting.find((item) =>
          item.game_plan_id === planId && item.player_id === playerId
        );
        const field = defense.find((item) =>
          item.game_plan_id === planId && item.player_id === playerId
        );
        const pair = battery.find((item) =>
          item.game_plan_id === planId && item.player_id === playerId
        );
        return {
          batting_slot: bat?.batting_slot == null
            ? null
            : Number(bat.batting_slot),
          offensive_role: bat ? String(bat.offensive_role) : null,
          defensive_assignment: field
            ? `${
              String(field.inning_number) === "0"
                ? "Starting"
                : `Inning ${String(field.inning_number)}`
            } • ${String(field.position_label ?? field.position_code)}`
            : null,
          pitcher_catcher_assignment: pair ? String(pair.role_type) : null,
        };
      };
      const operationByEvent = new Map(
        operations.map((item) => [String(item.event_id), item]),
      );
      const teamsById = new Map(
        teams.map((item) => [String(item.id), String(item.name)]),
      );
      for (const event of events) {
        const eventId = String(event.id);
        const operation = operationByEvent.get(eventId);
        const eventParticipants = participants.filter((item) =>
          item.event_id === eventId && item.expected === true
        );
        let players = eventParticipants.filter((item) =>
          item.participant_type === "player"
        ).map((item) => String(item.user_id));
        if (players.length === 0) {
          players = playerMemberships.filter((item) =>
            item.team_id === event.team_id
          ).map((item) => String(item.player_id));
        }
        const unresolvedAvailability = count(
          eventParticipants,
          (item) =>
            item.participant_type === "player" &&
            item.availability_status === "unknown",
        );
        const unresolvedAttendance = count(
          eventParticipants,
          (item) =>
            item.participant_type === "player" &&
            item.attendance_status === "not_recorded",
        );
        const plan = event.event_type === "practice"
          ? practices.get(eventId)
          : gamePlans.get(eventId);
        const gamePlanId = event.event_type === "game" && plan
          ? String(plan.id)
          : null;
        const detail = gameDetails.get(eventId);
        const base: RawTodayMission = {
          id: eventId,
          organization_id: organizationId,
          season_id: String(event.season_id),
          team_id: String(event.team_id),
          team_name: teamsById.get(String(event.team_id)) ?? "Team",
          player_ids: players,
          event_type: String(event.event_type),
          title: String(event.title),
          subtitle: detail
            ? `${String(detail.opponent)} • ${String(detail.venue_side)}`
            : null,
          status: String(event.status),
          start_at: String(event.start_at),
          arrival_at: event.arrival_at ? String(event.arrival_at) : null,
          end_at: String(event.end_at),
          location: event.location_name ? String(event.location_name) : null,
          operation_state: operation ? String(operation.status) : null,
          plan_state: plan ? String(plan.status) : null,
          operation_available: !operationResult.error &&
            !participantsResult.error,
          plan_available: event.event_type === "practice"
            ? !practiceResult.error
            : event.event_type === "game"
            ? !gamePlanResult.error && !gameDetailResult.error
            : true,
          unresolved_availability: unresolvedAvailability,
          unresolved_attendance: unresolvedAttendance,
          lineup_mode: event.event_type === "game" && plan
            ? String(plan.lineup_mode)
            : null,
          eh_count: event.event_type === "game" && gamePlanId
            ? count(
              batting,
              (item) =>
                item.game_plan_id === gamePlanId &&
                item.offensive_role === "eh",
            )
            : null,
          ...(activeRole === "player" ? assignment(gamePlanId, userId) : {}),
          recently_changed:
            Date.parse(String(event.updated_at)) >= Date.now() - 86_400_000,
        };
        if (activeRole === "parent") {
          const applicableChildren = linkedChildIds.filter((id) =>
            players.includes(id)
          );
          for (const id of applicableChildren) {
            rawMissions.push({
              ...base,
              ...assignment(gamePlanId, id),
              child_id: id,
              child_name: childNames.get(id) ?? "Player",
            });
          }
        } else rawMissions.push(base);
      }
    }
  }

  for (const mission of rawMissions) {
    const roles: TodayRole[] = activeRole === "coach"
      ? ["coach"]
      : ["owner", "admin"];
    if (
      mission.unresolved_availability > 0 &&
      mission.operation_available !== false &&
      (activeRole === "coach" || activeRole === "owner" ||
        activeRole === "admin")
    ) {
      attention.push({
        id: `${mission.id}:availability`,
        organization_id: organizationId,
        season_id: mission.season_id,
        team_id: mission.team_id,
        source_type: "event",
        source_id: mission.id,
        category: "missing_availability",
        severity: "important",
        title: `${mission.title} has unresolved availability`,
        detail: `${mission.unresolved_availability} response(s) missing.`,
        roles,
        required_capability: "manage_event_availability",
      });
    }
    if (
      mission.unresolved_attendance > 0 &&
      mission.operation_available !== false &&
      mission.operation_state === "completed" &&
      (activeRole === "coach" || activeRole === "owner" ||
        activeRole === "admin")
    ) {
      attention.push({
        id: `${mission.id}:attendance`,
        organization_id: organizationId,
        season_id: mission.season_id,
        team_id: mission.team_id,
        source_type: "event",
        source_id: mission.id,
        category: "unresolved_attendance",
        severity: "urgent",
        title: `${mission.title} needs attendance review`,
        detail:
          `${mission.unresolved_attendance} attendance record(s) unresolved.`,
        roles,
        required_capability: "manage_event_attendance",
      });
    }
    if (
      !mission.plan_state &&
      mission.plan_available !== false &&
      ["practice", "game"].includes(mission.event_type) &&
      (activeRole === "coach" || activeRole === "owner" ||
        activeRole === "admin")
    ) {
      attention.push({
        id: `${mission.id}:plan`,
        organization_id: organizationId,
        season_id: mission.season_id,
        team_id: mission.team_id,
        source_type: mission.event_type === "game"
          ? "game_plan"
          : "practice_plan",
        source_id: mission.id,
        category: "plan_missing",
        severity: "important",
        title: `${mission.title} has no ${mission.event_type} plan`,
        roles,
      });
    }
  }

  const registrationQuery = admin.from("sd_registration_applications").select(
    "id,season_id,player_user_id,guardian_user_id,applicant_user_id,state,balance_cents,fee_status",
  ).eq("organization_id", organizationId);
  const registrationResult = await registrationQuery;
  if (registrationResult.error) {
    services.registration = unavailableService("registration");
  } else {
    services.registration = available(now);
    let applications = (registrationResult.data ?? []) as Row[];
    if (activeRole === "parent") {
      applications = applications.filter((item) =>
        item.guardian_user_id === userId || item.applicant_user_id === userId ||
        linkedChildIds.includes(String(item.player_user_id))
      );
    } else if (activeRole === "player") {
      applications = applications.filter((item) =>
        item.player_user_id === userId || item.applicant_user_id === userId
      );
    }
    const reviewCount = count(
      applications,
      (item) =>
        ["submitted", "under_review", "action_required", "waitlisted"].includes(
          String(item.state),
        ),
    );
    if (reviewCount > 0) {
      attention.push({
        id: "registration:attention",
        organization_id: organizationId,
        season_id: seasonId,
        source_type: "registration",
        category: "registration_attention",
        severity: count(applications, (item) =>
            item.state === "action_required") > 0
          ? "urgent"
          : "important",
        title: activeRole === "parent" || activeRole === "player"
          ? "Registration needs attention"
          : `${reviewCount} registration(s) need review`,
        roles: activeRole === "parent"
          ? ["parent"]
          : activeRole === "player"
          ? ["player"]
          : ["owner", "admin"],
        required_capability: activeRole === "owner" || activeRole === "admin"
          ? "review_registrations"
          : null,
        action: {
          id: "open_registration",
          label: activeRole === "owner" || activeRole === "admin"
            ? "Review Registrations"
            : "View Registration",
          route: "organization/registration",
          capability: activeRole === "owner" || activeRole === "admin"
            ? "review_registrations"
            : null,
        },
      });
    }
    if (reviewCount > 0) {
      summaries.push({
        category: "registration",
        label: "Registration attention",
        value: String(reviewCount),
        as_of: now,
        roles: [activeRole],
      });
    }
  }

  const communicationResult = activeRole === "owner" || activeRole === "admin"
    ? await admin.from("sd_notification_intent_receipts").select(
      "id,delivery_state",
    ).eq("organization_id", organizationId).eq("delivery_state", "failed")
    : await admin.from("sd_announcement_recipients").select(
      "announcement_id,read_at,acknowledged_at",
    ).eq("organization_id", organizationId).eq("recipient_user_id", userId).is(
      "acknowledged_at",
      null,
    );
  if (communicationResult.error) {
    services.communication = unavailableService("communication");
  } else {
    services.communication = available(now);
    const communicationCount = (communicationResult.data ?? []).length;
    if (communicationCount > 0) {
      attention.push({
        id: "communication:attention",
        organization_id: organizationId,
        source_type: "communication",
        category: activeRole === "owner" || activeRole === "admin"
          ? "failed_delivery"
          : "required_acknowledgment",
        severity: "important",
        title: activeRole === "owner" || activeRole === "admin"
          ? `${communicationCount} delivery failure(s) need review`
          : `${communicationCount} announcement(s) need acknowledgment`,
        roles: [activeRole],
        required_capability: activeRole === "owner" || activeRole === "admin"
          ? "view_delivery_status"
          : null,
        action: {
          id: "open_communication",
          label: activeRole === "owner" || activeRole === "admin"
            ? "Review Failed Deliveries"
            : "Acknowledge Announcement",
          route: "communication",
          capability: activeRole === "owner" || activeRole === "admin"
            ? "view_delivery_status"
            : null,
        },
      });
    }
  }

  if (
    activeRole === "owner" || activeRole === "admin" || activeRole === "parent"
  ) {
    let invoiceQuery = admin.from("sd_invoices").select(
      "id,payer_id,child_id,status,amount_remaining_cents,due_date",
    ).eq("org_id", organizationId).gt("amount_remaining_cents", 0);
    if (activeRole === "parent") {
      invoiceQuery = invoiceQuery.or(
        `payer_id.eq.${userId}${
          linkedChildIds.length > 0
            ? `,child_id.in.(${linkedChildIds.join(",")})`
            : ""
        }`,
      );
    }
    const invoiceResult = await invoiceQuery;
    if (invoiceResult.error) services.finance = unavailableService("finance");
    else {
      services.finance = available(now);
      const invoices = (invoiceResult.data ?? []) as Row[];
      if (invoices.length > 0) {
        attention.push({
          id: "finance:receivables",
          organization_id: organizationId,
          source_type: "finance",
          category: "outstanding_receivables",
          severity: count(invoices, (item) =>
              String(item.due_date ?? "9999-12-31") < localDate) > 0
            ? "urgent"
            : "important",
          title: activeRole === "parent"
            ? "A household balance is due"
            : `${invoices.length} receivable(s) need review`,
          detail: activeRole === "parent"
            ? "Open the invoice for the current balance and due date."
            : "Open Finance for current balances and due dates.",
          roles: [activeRole],
          required_capability: activeRole === "owner" || activeRole === "admin"
            ? "view_financial_overview"
            : null,
          action: {
            id: "open_finance",
            label: activeRole === "parent"
              ? "View Invoice"
              : "Review Outstanding Receivables",
            route: "finance",
            capability: activeRole === "owner" || activeRole === "admin"
              ? "view_financial_overview"
              : null,
          },
        });
      }
      if (activeRole === "owner" || activeRole === "admin") {
        summaries.push({
          category: "receivables",
          label: "Outstanding receivables",
          value: String(invoices.length),
          status: invoices.length > 0 ? "attention" : "current",
          as_of: now,
          roles: [activeRole],
          required_capability: "view_financial_overview",
        });
      }
    }
  } else {services.finance = {
      state: "unauthorized",
      message: null,
      as_of: null,
    };}

  services.analytics = activeRole === "owner" || activeRole === "admin"
    ? available(now)
    : { state: "unauthorized", message: null, as_of: null };
  if (
    !hasOperationalSeason &&
    (activeRole === "owner" || activeRole === "admin")
  ) {
    attention.push({
      id: "setup:season",
      organization_id: organizationId,
      source_type: "setup",
      category: "no_active_season",
      severity: "urgent",
      title: "Create an active season",
      roles: ["owner", "admin"],
      required_capability: "manage_season_lifecycle",
      action: {
        id: "create_season",
        label: "Create Season",
        route: "organization/seasons",
        capability: "manage_season_lifecycle",
      },
    });
  }
  if (
    authorizedTeamIds.length === 0 &&
    (activeRole === "owner" || activeRole === "admin")
  ) {
    attention.push({
      id: "setup:team",
      organization_id: organizationId,
      source_type: "setup",
      category: "no_team",
      severity: "important",
      title: "Create the first team",
      roles: ["owner", "admin"],
      action: {
        id: "create_team",
        label: "Create Team",
        route: "organization/teams",
        capability: null,
      },
    });
  }
  const todayOperationCount = rawMissions.filter((mission) =>
    (mission.start_at ?? "") < todayRangeEnd &&
    (mission.end_at ?? "") > rangeStart
  ).length;
  if (todayOperationCount > 0) {
    summaries.push({
      category: "today_operations",
      label: "Today’s operations",
      value: String(todayOperationCount),
      as_of: now,
      roles: [activeRole],
    });
  }

  return json(
    200,
    buildTodayAggregate({
      context,
      now,
      missions: rawMissions,
      attention,
      summaries,
      services,
    }),
  );
});
