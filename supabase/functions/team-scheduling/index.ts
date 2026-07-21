import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import {
  type EventType,
  isEventType,
  materializeOccurrences,
  notificationIntent,
  type RecurrenceRule,
  requiredCapability,
  resolveScheduleReadAuthority,
  sanitizeEventForConsumer,
} from "../_shared/team_scheduling.ts";

type Json = Record<string, unknown>;
type EnvelopeOptions = {
  requestId?: string;
  context?: Json;
  warnings?: string[];
  stage?: string;
  details?: Json;
};

function response(status: number, body: Json) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json; charset=utf-8" },
  });
}
const ok = (data: Json, options: EnvelopeOptions = {}) =>
  response(200, {
    ok: true,
    schema_version: 1,
    request_id: options.requestId ?? crypto.randomUUID(),
    context: options.context ?? null,
    capabilities: data.capabilities ?? [],
    data,
    warnings: options.warnings ?? [],
    ...data,
    error: null,
  });
const fail = (
  status: number,
  code: string,
  message?: string,
  options: EnvelopeOptions = {},
) =>
  response(status, {
    ok: false,
    schema_version: 1,
    request_id: options.requestId ?? crypto.randomUUID(),
    context: options.context ?? null,
    ...(options.details ?? {}),
    error: { code, message: message ?? code, stage: options.stage ?? null },
  });
const env = (name: string) => (Deno.env.get(name) ?? "").trim();
const text = (value: unknown) => String(value ?? "").trim();
const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const uuid = (value: unknown) =>
  uuidPattern.test(text(value)) ? text(value) : null;
const asRecord = (value: unknown): Record<string, unknown> =>
  value && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown>
    : {};

function publicSelect() {
  return "id,organization_id,season_id,team_id,series_id,occurrence_index,event_type,title,description,status,start_at,end_at,arrival_at,original_start_at,timezone,all_day,location_name,address,facility_id,visibility,created_at,updated_at,cancelled_at,cancellation_reason,sd_teams(name),sd_team_event_practices(event_id,objectives,dress_code,equipment_notes,practice_plan_status,facility_resource_label),sd_team_event_games(event_id,opponent,venue_side,game_status,uniform,home_score,away_score,field_details),sd_team_event_tournaments(event_id,tournament_name,host,tournament_start_date,tournament_end_date,parent_tournament_event_id),sd_team_event_meetings(event_id,meeting_type,virtual_link),sd_team_event_travel(event_id,departure_at,destination,transportation_notes,lodging_notes)";
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return fail(405, "method_not_allowed");
  let payload: Record<string, unknown>;
  try {
    payload = asRecord(await req.json());
  } catch {
    return fail(400, "invalid_json");
  }
  const supabaseUrl = env("SUPABASE_URL") || env("DHD_SUPABASE_URL");
  const anonKey = env("SUPABASE_ANON_KEY") || env("DHD_SUPABASE_ANON_KEY");
  const serviceKey = env("DHD_SERVICE_ROLE_KEY") ||
    env("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !anonKey || !serviceKey) {
    return fail(500, "missing_supabase_secrets");
  }
  const token = (req.headers.get("Authorization") ?? "").replace(
    /^Bearer\s+/i,
    "",
  ).trim();
  if (!token) return fail(401, "missing_auth");
  const publicClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: `Bearer ${token}` } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: userData, error: userError } = await publicClient.auth.getUser(
    token,
  );
  if (userError || !userData.user?.id) return fail(401, "invalid_auth");
  const callerId = userData.user.id;
  const admin = createClient(supabaseUrl, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const organizationId = uuid(payload.organization_id);
  if (!organizationId) return fail(400, "missing_organization_id");
  const { data: membership, error: membershipError } = await admin.from(
    "sd_org_memberships",
  )
    .select("role,status").eq("org_id", organizationId).eq("user_id", callerId)
    .eq("status", "active").maybeSingle();
  if (membershipError) return fail(500, "membership_lookup_failed");
  if (!membership) return fail(403, "organization_membership_required");
  const role = text((membership as Record<string, unknown>).role).toLowerCase();
  const isAdmin = role === "owner" || role === "admin";
  const action = text(payload.action);

  async function capabilities(teamId: string): Promise<string[]> {
    const { data, error } = await admin.rpc("sd_resolve_team_capabilities", {
      target_organization: organizationId,
      target_team: teamId,
      target_actor: callerId,
    });
    if (error) throw new Error("capability_resolution_failed");
    return (data ?? []).map(String);
  }

  async function persistNotificationIntentsBestEffort(
    rows: Record<string, unknown>[],
  ): Promise<boolean> {
    try {
      const { error } = await admin.from("sd_team_event_notification_intents")
        .insert(rows);
      if (error) {
        console.error("team_schedule_notification_intent_failed");
        return false;
      }
      return true;
    } catch {
      console.error("team_schedule_notification_intent_failed");
      return false;
    }
  }

  async function persistSubtype(
    eventIds: string[],
    eventType: EventType,
    source: Record<string, unknown>,
  ): Promise<string | null> {
    const subtype = asRecord(source.subtype);
    const tables = [
      "sd_team_event_practices",
      "sd_team_event_games",
      "sd_team_event_tournaments",
      "sd_team_event_meetings",
      "sd_team_event_travel",
    ];
    for (const table of tables) {
      const { error } = await admin.from(table).delete().in(
        "event_id",
        eventIds,
      );
      if (error) return "subtype_reset_failed";
    }
    let rows: Record<string, unknown>[] = [];
    if (eventType === "practice") {
      rows = eventIds.map((event_id) => ({
        event_id,
        objectives: Array.isArray(subtype.objectives)
          ? subtype.objectives.map(text).filter(Boolean)
          : [],
        dress_code: text(subtype.dress_code) || null,
        equipment_notes: text(subtype.equipment_notes) || null,
        practice_plan_status: text(subtype.practice_plan_status) ||
          "not_started",
        facility_resource_label: text(subtype.facility_resource_label) || null,
      }));
    } else if (eventType === "game") {
      if (!text(subtype.opponent)) return "missing_opponent";
      rows = eventIds.map((event_id) => ({
        event_id,
        opponent: text(subtype.opponent),
        venue_side: text(subtype.venue_side) || "home",
        game_status: text(subtype.game_status) || "scheduled",
        uniform: text(subtype.uniform) || null,
        home_score: subtype.home_score ?? null,
        away_score: subtype.away_score ?? null,
        field_details: text(subtype.field_details) || null,
      }));
    } else if (eventType === "tournament") {
      if (
        !text(subtype.tournament_name) ||
        !text(subtype.tournament_start_date) ||
        !text(subtype.tournament_end_date)
      ) return "invalid_tournament_details";
      rows = eventIds.map((event_id) => ({
        event_id,
        tournament_name: text(subtype.tournament_name),
        host: text(subtype.host) || null,
        tournament_start_date: text(subtype.tournament_start_date),
        tournament_end_date: text(subtype.tournament_end_date),
        parent_tournament_event_id: uuid(subtype.parent_tournament_event_id),
      }));
    } else if (eventType === "meeting") {
      rows = eventIds.map((event_id) => ({
        event_id,
        meeting_type: text(subtype.meeting_type) || "team",
        virtual_link: text(subtype.virtual_link) || null,
      }));
    } else if (eventType === "travel") {
      if (!text(subtype.destination)) return "missing_destination";
      rows = eventIds.map((event_id) => ({
        event_id,
        departure_at: text(subtype.departure_at) || null,
        destination: text(subtype.destination),
        transportation_notes: text(subtype.transportation_notes) || null,
        lodging_notes: text(subtype.lodging_notes) || null,
      }));
    }
    if (!rows.length) return null;
    const table = eventType === "practice"
      ? "sd_team_event_practices"
      : eventType === "game"
      ? "sd_team_event_games"
      : eventType === "tournament"
      ? "sd_team_event_tournaments"
      : eventType === "meeting"
      ? "sd_team_event_meetings"
      : "sd_team_event_travel";
    const { error } = await admin.from(table).insert(rows);
    return error ? "subtype_save_failed" : null;
  }

  if (action === "list") {
    const envelopeRequestId = uuid(payload.request_id) ?? crypto.randomUUID();
    const requestedSeason = uuid(payload.season_id);
    const requestedTeam = uuid(payload.team_id);
    const contractContext = {
      organization_id: organizationId,
      season_id: requestedSeason,
      team_id: requestedTeam,
      as_of: new Date().toISOString(),
    };
    const listFail = (status: number, code: string, stage: string) =>
      fail(status, code, undefined, {
        requestId: envelopeRequestId,
        context: contractContext,
        stage,
      });
    const rangeStart = text(payload.range_start);
    const rangeEnd = text(payload.range_end);
    if (
      !rangeStart || !rangeEnd || new Date(rangeEnd) <= new Date(rangeStart)
    ) {
      return listFail(400, "invalid_range", "validate_season");
    }
    if (requestedSeason) {
      const { data: season, error: seasonError } = await admin.from(
        "sd_seasons",
      ).select("id,status").eq("id", requestedSeason).eq(
        "organization_id",
        organizationId,
      ).maybeSingle();
      if (seasonError) {
        return listFail(500, "service_unavailable", "validate_season");
      }
      if (!season) return listFail(404, "season_missing", "validate_season");
      if (["completed", "archived"].includes(text(season.status))) {
        return listFail(409, "season_inactive", "validate_season");
      }
    }
    let teamIds: string[] = [];
    let listCapabilities: string[] = isAdmin ? ["view_team_schedule"] : [];
    let consumer = role === "player" || role === "parent";
    if (role === "player") {
      const requestedPlayer = uuid(payload.player_id) ?? callerId;
      if (requestedPlayer !== callerId) {
        return listFail(403, "permission_denied", "resolve_role");
      }
      const { data, error } = await admin.from("sd_player_team_memberships")
        .select("team_id")
        .eq("organization_id", organizationId).eq("player_id", callerId)
        .eq("active", true).is("ended_at", null);
      if (error) return listFail(500, "service_unavailable", "execute_query");
      teamIds = (data ?? []).map((row: Record<string, unknown>) =>
        text(row.team_id)
      );
    } else if (role === "parent") {
      const childId = uuid(payload.player_id);
      if (!childId) return listFail(400, "team_missing", "validate_team");
      const { data: link, error: linkError } = await admin.from(
        "sd_parent_child_links",
      ).select("child_id")
        .eq("org_id", organizationId).eq("parent_id", callerId).eq(
          "child_id",
          childId,
        ).maybeSingle();
      if (linkError) {
        return listFail(500, "service_unavailable", "resolve_role");
      }
      if (!link) return listFail(403, "permission_denied", "resolve_role");
      const { data, error } = await admin.from("sd_player_team_memberships")
        .select("team_id")
        .eq("organization_id", organizationId).eq("player_id", childId)
        .eq("active", true).is("ended_at", null);
      if (error) return listFail(500, "service_unavailable", "execute_query");
      teamIds = (data ?? []).map((row: Record<string, unknown>) =>
        text(row.team_id)
      );
    } else {
      if (requestedTeam) {
        // Validate context before authorization so a stale or missing team is
        // never mislabeled as a capability denial.
        const { data: ownedTeam, error: ownedTeamError } = await admin
          .from("sd_teams").select("id,season_id,is_active")
          .eq("id", requestedTeam).eq("org_id", organizationId).maybeSingle();
        if (ownedTeamError) {
          return listFail(500, "service_unavailable", "validate_team");
        }
        if (!ownedTeam) return listFail(404, "team_missing", "validate_team");
        if (ownedTeam.is_active !== true) {
          return listFail(409, "team_archived", "validate_team");
        }
        if (
          requestedSeason && text(ownedTeam.season_id) !== requestedSeason
        ) {
          return listFail(409, "stale_team_context", "validate_team");
        }
        if (!isAdmin) {
          let resolved: string[];
          try {
            resolved = await capabilities(requestedTeam);
          } catch {
            return listFail(
              500,
              "service_unavailable",
              "resolve_capabilities",
            );
          }
          const authority = resolveScheduleReadAuthority(role, resolved);
          if (!authority.allowed) {
            return listFail(403, "permission_denied", "resolve_capabilities");
          }
          listCapabilities = resolved;
        }
        teamIds = [requestedTeam];
      } else if (isAdmin) {
        const { data, error } = await admin.from("sd_teams").select("id").eq(
          "org_id",
          organizationId,
        ).eq("is_active", true);
        if (error) return listFail(500, "service_unavailable", "execute_query");
        teamIds = (data ?? []).map((row: Record<string, unknown>) =>
          text(row.id)
        );
      } else {
        let teamQuery = admin.from("sd_teams").select("id").eq(
          "org_id",
          organizationId,
        ).eq("is_active", true);
        if (requestedSeason) {
          teamQuery = teamQuery.eq("season_id", requestedSeason);
        }
        const { data: candidateTeams, error: candidateError } = await teamQuery;
        if (candidateError) {
          return listFail(500, "service_unavailable", "execute_query");
        }
        const capabilityUnion = new Set<string>();
        for (const candidate of candidateTeams ?? []) {
          let candidateCapabilities: string[];
          try {
            candidateCapabilities = await capabilities(text(candidate.id));
          } catch {
            return listFail(500, "service_unavailable", "resolve_capabilities");
          }
          if (
            resolveScheduleReadAuthority(role, candidateCapabilities).allowed
          ) {
            teamIds.push(text(candidate.id));
            candidateCapabilities.forEach((capability) =>
              capabilityUnion.add(capability)
            );
          }
        }
        listCapabilities = [...capabilityUnion];
      }
    }
    if (!teamIds.length) {
      return ok({ events: [], capabilities: [] }, {
        requestId: envelopeRequestId,
        context: contractContext,
      });
    }
    let query = admin.from("sd_team_events").select(
      consumer
        ? publicSelect()
        : "*,sd_teams(name),sd_team_event_practices(*),sd_team_event_games(*),sd_team_event_tournaments(*),sd_team_event_meetings(*),sd_team_event_travel(*),sd_team_event_coaches(*)",
    )
      .eq("organization_id", organizationId).in("team_id", teamIds)
      .lt("start_at", rangeEnd).gt("end_at", rangeStart).order("start_at", {
        ascending: true,
      });
    if (requestedSeason) query = query.eq("season_id", requestedSeason);
    if (consumer) query = query.eq("visibility", "team").neq("status", "draft");
    const { data, error } = await query;
    if (error) return listFail(500, "service_unavailable", "execute_query");
    const normalizedEvents =
      ((data ?? []) as unknown as Record<string, unknown>[]).map((event) => {
        const normalized = { ...event };
        normalized.team_name = text(asRecord(normalized.sd_teams).name) || null;
        delete normalized.sd_teams;
        for (
          const key of [
            "sd_team_event_practices",
            "sd_team_event_games",
            "sd_team_event_tournaments",
            "sd_team_event_meetings",
            "sd_team_event_travel",
            "sd_team_event_coaches",
          ]
        ) {
          const value = normalized[key];
          if (value == null) normalized[key] = [];
          else if (!Array.isArray(value)) normalized[key] = [value];
        }
        return normalized;
      });
    const warnings = normalizedEvents.some((event) =>
        (event.event_type === "practice" &&
          (event.sd_team_event_practices as unknown[]).length === 0) ||
        (event.event_type === "game" &&
          (event.sd_team_event_games as unknown[]).length === 0)
      )
      ? ["optional_event_details_unavailable"]
      : [];
    return ok({
      events: consumer
        ? normalizedEvents.map((event) =>
          sanitizeEventForConsumer(event)
        )
        : normalizedEvents,
      capabilities: listCapabilities,
    }, {
      requestId: envelopeRequestId,
      context: contractContext,
      warnings,
    });
  }

  const teamId = uuid(payload.team_id);
  const seasonId = uuid(payload.season_id);
  if (!teamId || !seasonId) return fail(400, "missing_event_scope");
  let resolved: string[];
  try {
    resolved = await capabilities(teamId);
  } catch {
    return fail(500, "capability_resolution_failed");
  }
  if (!resolved.includes("view_team_schedule")) {
    return fail(403, "view_team_schedule_required");
  }

  if (action === "conflicts") {
    const event = asRecord(payload.event);
    const coachIds = Array.isArray(event.coach_ids)
      ? event.coach_ids.map(uuid).filter(Boolean)
      : [];
    const conflictCoachIds = coachIds.length
      ? coachIds
      : role === "coach"
      ? [callerId]
      : [];
    const { data, error } = await admin.rpc("sd_team_event_conflicts", {
      p_organization_id: organizationId,
      p_team_id: teamId,
      p_start_at: text(event.start_at),
      p_end_at: text(event.end_at),
      p_facility_id: uuid(event.facility_id),
      p_coach_ids: conflictCoachIds,
      p_exclude_event_id: uuid(payload.event_id),
    });
    if (error) return fail(400, "conflict_check_failed");
    const { data: season } = await admin.from("sd_seasons").select(
      "start_date,end_date",
    )
      .eq("id", seasonId).eq("organization_id", organizationId).maybeSingle();
    const warnings = [...(Array.isArray(data) ? data : [])];
    const eventDay = text(event.start_at).slice(0, 10);
    if (
      (season?.start_date && eventDay < season.start_date) ||
      (season?.end_date && eventDay > season.end_date)
    ) {
      warnings.push({
        type: "season_boundary",
        title: "Event is outside season dates",
      });
    }
    return ok({ conflicts: warnings });
  }

  if (
    ![
      "create",
      "update",
      "update_future",
      "cancel",
      "cancel_series",
      "delete_draft",
      "duplicate",
    ].includes(
      action,
    )
  ) {
    return fail(400, "unsupported_action");
  }
  const needed = action === "create" || action === "duplicate"
    ? "create_team_event"
    : action === "cancel" || action === "cancel_series"
    ? "cancel_team_event"
    : "edit_team_event";
  if (!resolved.includes(needed)) return fail(403, `${needed}_required`);
  const requestId = uuid(payload.request_id);
  if (!requestId) return fail(400, "missing_request_id");
  const eventId = uuid(payload.event_id);
  let before: Record<string, unknown> | null = null;
  if (eventId) {
    const { data } = await admin.from("sd_team_events").select("*").eq(
      "id",
      eventId,
    )
      .eq("organization_id", organizationId).eq("team_id", teamId)
      .maybeSingle();
    before = data as Record<string, unknown> | null;
    if (!before) return fail(404, "event_not_found");
  }

  if (action === "delete_draft") {
    if (before?.status !== "draft") {
      return fail(409, "only_drafts_can_be_deleted");
    }
    const { error } = await admin.from("sd_team_events").delete().eq(
      "id",
      eventId!,
    );
    if (error) return fail(400, "draft_delete_failed");
    await admin.from("sd_team_event_audit_logs").insert({
      organization_id: organizationId,
      season_id: seasonId,
      team_id: teamId,
      event_id: eventId,
      actor_id: callerId,
      action: "draft_deleted",
      request_id: requestId,
    });
    return ok({ deleted: true });
  }

  if (action === "cancel_series") {
    const seriesId = uuid(before?.series_id);
    if (!seriesId) return fail(409, "event_is_not_recurring");
    const reason = text(payload.reason) || "Series cancelled";
    const cancelledAt = new Date().toISOString();
    const { data: cancelled, error } = await admin.from("sd_team_events")
      .update({
        status: "cancelled",
        cancelled_at: cancelledAt,
        cancellation_reason: reason,
        updated_by: callerId,
      }).eq("series_id", seriesId).gte(
        "occurrence_index",
        Number(before?.occurrence_index ?? 0),
      ).neq("status", "cancelled").select();
    if (error) return fail(400, "series_cancel_failed");
    await admin.from("sd_team_event_series").update({
      status: "cancelled",
      cancelled_at: cancelledAt,
      cancellation_reason: reason,
      updated_by: callerId,
    }).eq("id", seriesId);
    const cancelledIds = ((cancelled ?? []) as Record<string, unknown>[]).map((
      row,
    ) => text(row.id));
    if (cancelledIds.length) {
      await admin.from("sd_team_event_notification_intents").insert(
        cancelledIds.map((id) => ({
          organization_id: organizationId,
          team_id: teamId,
          event_id: id,
          intent_type: "cancellation",
          deduplication_key: `${requestId}:${id}:cancellation`,
          created_by: callerId,
        })),
      );
    }
    await admin.from("sd_team_event_audit_logs").insert({
      organization_id: organizationId,
      season_id: seasonId,
      team_id: teamId,
      event_id: eventId,
      series_id: seriesId,
      actor_id: callerId,
      action: "series_cancelled",
      request_id: requestId,
      reason,
      details: { affected_occurrences: cancelledIds.length },
    });
    return ok({ events: cancelled ?? [] });
  }

  const input = asRecord(payload.event);
  const source = input;
  const eventType = source.event_type;
  if (!isEventType(eventType)) return fail(400, "invalid_event_type");
  const typeCapability = requiredCapability(eventType);
  if (typeCapability && !resolved.includes(typeCapability)) {
    return fail(403, `${typeCapability}_required`);
  }
  const startAt = text(source.start_at);
  const endAt = text(source.end_at);
  const arrivalAt = text(source.arrival_at) || null;
  if (!startAt || !endAt || new Date(endAt) <= new Date(startAt)) {
    return fail(400, "invalid_event_times");
  }
  if (arrivalAt && new Date(arrivalAt) > new Date(startAt)) {
    return fail(400, "arrival_after_start");
  }
  const patch: Record<string, unknown> = {
    organization_id: organizationId,
    season_id: seasonId,
    team_id: teamId,
    event_type: eventType,
    title: text(source.title),
    description: text(source.description) || null,
    status: action === "cancel"
      ? "cancelled"
      : action === "duplicate"
      ? "draft"
      : text(source.status) || "draft",
    start_at: startAt,
    end_at: endAt,
    arrival_at: arrivalAt,
    original_start_at: action === "update"
      ? before?.original_start_at ?? startAt
      : startAt,
    timezone: text(source.timezone) || "America/New_York",
    all_day: source.all_day === true,
    location_name: text(source.location_name) || null,
    address: text(source.address) || null,
    facility_id: uuid(source.facility_id),
    visibility: text(source.visibility) || "team",
    notes: text(source.notes) || null,
    metadata: asRecord(source.metadata),
    updated_by: callerId,
    cancelled_at: action === "cancel" ? new Date().toISOString() : null,
    cancellation_reason: action === "cancel"
      ? text(payload.reason) || "Cancelled"
      : null,
  };
  if (!patch.title) return fail(400, "missing_title");
  if (action !== "cancel" && !patch.location_name) {
    return fail(400, "missing_location");
  }

  const coachIds = Array.isArray(source.coach_ids)
    ? source.coach_ids.map(uuid).filter(Boolean) as string[]
    : [];
  const effectiveCoachIds = coachIds.length
    ? coachIds
    : role === "coach"
    ? [callerId]
    : [];
  const { data: conflicts, error: conflictError } = await admin.rpc(
    "sd_team_event_conflicts",
    {
      p_organization_id: organizationId,
      p_team_id: teamId,
      p_start_at: startAt,
      p_end_at: endAt,
      p_facility_id: patch.facility_id,
      p_coach_ids: effectiveCoachIds,
      p_exclude_event_id: eventId,
    },
  );
  if (conflictError) {
    return fail(400, "conflict_check_failed");
  }
  const conflictList = Array.isArray(conflicts) ? [...conflicts] : [];
  const { data: mutationSeason } = await admin.from("sd_seasons").select(
    "start_date,end_date",
  )
    .eq("id", seasonId).eq("organization_id", organizationId).maybeSingle();
  const mutationEventDay = startAt.slice(0, 10);
  if (
    (mutationSeason?.start_date &&
      mutationEventDay < mutationSeason.start_date) ||
    (mutationSeason?.end_date && mutationEventDay > mutationSeason.end_date)
  ) {
    conflictList.push({
      type: "season_boundary",
      title: "Event is outside season dates",
    });
  }
  const overrideReason = text(payload.override_reason);
  if (conflictList.length && !overrideReason && action !== "update_future") {
    return fail(
      409,
      "conflict_override_required",
      "Scheduling conflicts require an override reason.",
      { details: { conflicts: conflictList } },
    );
  }

  if (action === "create" || action === "duplicate") {
    const recurrence = payload.recurrence ? asRecord(payload.recurrence) : null;
    let occurrences;
    try {
      occurrences = materializeOccurrences(
        startAt,
        endAt,
        recurrence
          ? {
            frequency: text(recurrence.frequency) as "daily" | "weekly",
            interval: Number(recurrence.interval ?? 1),
            weekdays: Array.isArray(recurrence.weekdays)
              ? recurrence.weekdays.map(Number)
              : undefined,
            endsOn: text(recurrence.ends_on) || null,
            occurrenceCount: recurrence.occurrence_count == null
              ? null
              : Number(recurrence.occurrence_count),
          } satisfies RecurrenceRule
          : null,
      );
    } catch {
      return fail(400, "invalid_recurrence");
    }
    for (const occurrence of occurrences.slice(1)) {
      const { data: occurrenceConflicts, error: occurrenceConflictError } =
        await admin.rpc("sd_team_event_conflicts", {
          p_organization_id: organizationId,
          p_team_id: teamId,
          p_start_at: occurrence.startAt,
          p_end_at: occurrence.endAt,
          p_facility_id: patch.facility_id,
          p_coach_ids: effectiveCoachIds,
          p_exclude_event_id: null,
        });
      if (occurrenceConflictError) {
        return fail(
          400,
          "conflict_check_failed",
          undefined,
        );
      }
      if (Array.isArray(occurrenceConflicts)) {
        conflictList.push(...occurrenceConflicts);
      }
      const occurrenceDay = occurrence.startAt.slice(0, 10);
      if (
        (mutationSeason?.start_date &&
          occurrenceDay < mutationSeason.start_date) ||
        (mutationSeason?.end_date && occurrenceDay > mutationSeason.end_date)
      ) {
        conflictList.push({
          type: "season_boundary",
          title: "Recurring occurrence is outside season dates",
        });
      }
    }
    if (
      occurrences.some((occurrence, index) =>
        index > 0 &&
        new Date(occurrences[index - 1].endAt) > new Date(occurrence.startAt)
      )
    ) {
      conflictList.push({
        type: "recurrence",
        title: "Recurring occurrences overlap each other",
      });
    }
    if (conflictList.length && !overrideReason) {
      return fail(
        409,
        "conflict_override_required",
        "Scheduling conflicts require an override reason.",
        { details: { conflicts: conflictList } },
      );
    }
    let seriesId: string | null = null;
    if (recurrence) {
      const durationMinutes = Math.round(
        (new Date(endAt).getTime() - new Date(startAt).getTime()) / 60000,
      );
      const { data: series, error } = await admin.from("sd_team_event_series")
        .insert({
          organization_id: organizationId,
          season_id: seasonId,
          team_id: teamId,
          frequency: recurrence.frequency,
          interval_count: recurrence.interval ?? 1,
          weekdays: recurrence.weekdays ?? [],
          ends_on: text(recurrence.ends_on) || null,
          occurrence_count: recurrence.occurrence_count ?? null,
          timezone: patch.timezone,
          starts_at: startAt,
          duration_minutes: durationMinutes,
          created_by: callerId,
          updated_by: callerId,
        }).select("id").single();
      if (error) return fail(400, "series_create_failed");
      seriesId = series.id;
    }
    const rows = occurrences.map((occurrence) => ({
      ...patch,
      id: crypto.randomUUID(),
      series_id: seriesId,
      occurrence_index: occurrence.index,
      start_at: occurrence.startAt,
      end_at: occurrence.endAt,
      original_start_at: occurrence.originalStartAt,
      created_by: callerId,
    }));
    const { data: inserted, error } = await admin.from("sd_team_events").insert(
      rows,
    ).select();
    if (error) {
      if (seriesId) {
        await admin.from("sd_team_event_series").delete().eq("id", seriesId);
      }
      return fail(400, "event_create_failed");
    }
    const ids = (inserted ?? []).map((row: Record<string, unknown>) =>
      text(row.id)
    );
    const subtypeError = await persistSubtype(ids, eventType, source);
    if (subtypeError) {
      await admin.from("sd_team_events").delete().in("id", ids);
      if (seriesId) {
        await admin.from("sd_team_event_series").delete().eq("id", seriesId);
      }
      return fail(400, subtypeError);
    }
    if (effectiveCoachIds.length) {
      await admin.from("sd_team_event_coaches").insert(
        ids.flatMap((id) =>
          effectiveCoachIds.map((coach_id) => ({ event_id: id, coach_id }))
        ),
      );
    }
    const intent = notificationIntent(null, patch);
    if (intent) {
      await persistNotificationIntentsBestEffort(
        ids.map((id) => ({
          organization_id: organizationId,
          team_id: teamId,
          event_id: id,
          intent_type: intent,
          deduplication_key: `${requestId}:${id}:${intent}`,
          created_by: callerId,
        })),
      );
    }
    await admin.from("sd_team_event_audit_logs").insert({
      organization_id: organizationId,
      season_id: seasonId,
      team_id: teamId,
      event_id: ids[0],
      series_id: seriesId,
      actor_id: callerId,
      action: action === "duplicate"
        ? "duplicated"
        : patch.status === "draft"
        ? "created"
        : "published",
      request_id: requestId,
      details: { occurrence_count: ids.length },
    });
    if (overrideReason) {
      await admin.from("sd_team_event_audit_logs").insert({
        organization_id: organizationId,
        season_id: seasonId,
        team_id: teamId,
        event_id: ids[0],
        series_id: seriesId,
        actor_id: callerId,
        action: "conflict_override",
        request_id: crypto.randomUUID(),
        reason: overrideReason,
        details: { conflicts: conflictList },
      });
    }
    return ok({ events: inserted ?? [], conflicts: conflictList });
  }

  if (action === "update_future") {
    const seriesId = uuid(before?.series_id);
    if (!seriesId) return fail(409, "event_is_not_recurring");
    const { data: futureRows, error: futureError } = await admin.from(
      "sd_team_events",
    ).select("*").eq("series_id", seriesId).gte(
      "occurrence_index",
      Number(before?.occurrence_index ?? 0),
    ).neq("status", "cancelled").order("occurrence_index");
    if (futureError) return fail(400, "future_occurrences_lookup_failed");
    const startDelta = new Date(startAt).getTime() -
      new Date(text(before?.start_at)).getTime();
    const duration = new Date(endAt).getTime() - new Date(startAt).getTime();
    const futureIds = new Set(
      ((futureRows ?? []) as Record<string, unknown>[]).map((row) =>
        text(row.id)
      ),
    );
    for (let index = conflictList.length - 1; index >= 0; index -= 1) {
      if (futureIds.has(text(asRecord(conflictList[index]).id))) {
        conflictList.splice(index, 1);
      }
    }
    const projectedRows = ((futureRows ?? []) as Record<string, unknown>[]).map(
      (row) => {
        const shiftedStart = new Date(
          new Date(text(row.start_at)).getTime() + startDelta,
        );
        return {
          row,
          patch: {
            ...patch,
            start_at: shiftedStart.toISOString(),
            end_at: new Date(shiftedStart.getTime() + duration).toISOString(),
            original_start_at: row.original_start_at,
            arrival_at: arrivalAt
              ? new Date(
                shiftedStart.getTime() -
                  (new Date(startAt).getTime() -
                    new Date(arrivalAt).getTime()),
              ).toISOString()
              : null,
          },
        };
      },
    );
    for (const projected of projectedRows) {
      const { data: projectedConflicts, error: projectedConflictError } =
        await admin.rpc("sd_team_event_conflicts", {
          p_organization_id: organizationId,
          p_team_id: teamId,
          p_start_at: projected.patch.start_at,
          p_end_at: projected.patch.end_at,
          p_facility_id: patch.facility_id,
          p_coach_ids: effectiveCoachIds,
          p_exclude_event_id: text(projected.row.id),
        });
      if (projectedConflictError) {
        return fail(
          400,
          "conflict_check_failed",
          undefined,
        );
      }
      if (Array.isArray(projectedConflicts)) {
        conflictList.push(
          ...projectedConflicts.filter((conflict) =>
            !futureIds.has(text(asRecord(conflict).id))
          ),
        );
      }
      const projectedDay = projected.patch.start_at.slice(0, 10);
      if (
        (mutationSeason?.start_date &&
          projectedDay < mutationSeason.start_date) ||
        (mutationSeason?.end_date && projectedDay > mutationSeason.end_date)
      ) {
        conflictList.push({
          type: "season_boundary",
          title: "Updated occurrence is outside season dates",
        });
      }
    }
    if (
      projectedRows.some((projected, index) =>
        index > 0 &&
        new Date(projectedRows[index - 1].patch.end_at) >
          new Date(projected.patch.start_at)
      )
    ) {
      conflictList.push({
        type: "recurrence",
        title: "Updated occurrences overlap each other",
      });
    }
    if (conflictList.length && !overrideReason) {
      return fail(
        409,
        "conflict_override_required",
        "Scheduling conflicts require an override reason.",
        { details: { conflicts: conflictList } },
      );
    }
    const updatedRows: Record<string, unknown>[] = [];
    for (const projected of projectedRows) {
      const { data, error } = await admin.from("sd_team_events").update(
        projected.patch,
      ).eq("id", text(projected.row.id)).select().single();
      if (error) return fail(400, "future_occurrence_update_failed");
      updatedRows.push(data as Record<string, unknown>);
    }
    const updatedIds = updatedRows.map((row) => text(row.id));
    const subtypeError = await persistSubtype(updatedIds, eventType, source);
    if (subtypeError) return fail(400, subtypeError);
    await admin.from("sd_team_event_series").update({
      starts_at: startAt,
      duration_minutes: Math.round(duration / 60_000),
      updated_by: callerId,
    }).eq("id", seriesId);
    if (updatedIds.length) {
      await admin.from("sd_team_event_notification_intents").insert(
        updatedIds.map((id) => ({
          organization_id: organizationId,
          team_id: teamId,
          event_id: id,
          intent_type: "time_change",
          deduplication_key: `${requestId}:${id}:time_change`,
          created_by: callerId,
        })),
      );
      for (const row of updatedRows) {
        const changedId = text(row.id);
        await admin.from("sd_event_operations").update({
          scheduled_start_at: row.start_at,
        }).eq("event_id", changedId).eq("organization_id", organizationId);
        const delta = new Date(text(row.start_at)).getTime() - Date.now();
        if (delta <= 86_400_000 && delta >= -21_600_000) {
          await admin.from("sd_team_event_notification_intents").upsert({
            organization_id: organizationId,
            team_id: teamId,
            event_id: changedId,
            intent_type: "late_schedule_change",
            deduplication_key: `${requestId}:${changedId}:late_schedule_change`,
            payload: { change_type: "time_change" },
            created_by: callerId,
          }, { onConflict: "organization_id,deduplication_key" });
        }
      }
    }
    await admin.from("sd_team_event_audit_logs").insert({
      organization_id: organizationId,
      season_id: seasonId,
      team_id: teamId,
      event_id: eventId,
      series_id: seriesId,
      actor_id: callerId,
      action: "recurrence_changed",
      request_id: requestId,
      details: { affected_occurrences: updatedIds.length },
    });
    return ok({ events: updatedRows, conflicts: conflictList });
  }

  const { data: updated, error: updateError } = await admin.from(
    "sd_team_events",
  ).update(patch).eq("id", eventId!).select().single();
  if (updateError) return fail(400, "event_update_failed");
  const subtypeError = await persistSubtype([eventId!], eventType, source);
  if (subtypeError) return fail(400, subtypeError);
  await admin.from("sd_team_event_coaches").delete().eq("event_id", eventId!);
  if (effectiveCoachIds.length) {
    await admin.from("sd_team_event_coaches").insert(
      effectiveCoachIds.map((coach_id) => ({ event_id: eventId, coach_id })),
    );
  }
  const intent = notificationIntent(before, updated as Record<string, unknown>);
  if (intent) {
    await admin.from("sd_team_event_notification_intents").insert({
      organization_id: organizationId,
      team_id: teamId,
      event_id: eventId,
      intent_type: intent,
      deduplication_key: `${requestId}:${eventId}:${intent}`,
      created_by: callerId,
    });
  }
  if (
    (intent === "time_change" || intent === "location_change") &&
    new Date(text(updated.start_at)).getTime() - Date.now() <= 86_400_000 &&
    new Date(text(updated.start_at)).getTime() >= Date.now() - 21_600_000
  ) {
    await admin.from("sd_team_event_notification_intents").upsert({
      organization_id: organizationId,
      team_id: teamId,
      event_id: eventId,
      intent_type: "late_schedule_change",
      deduplication_key: `${requestId}:${eventId}:late_schedule_change`,
      payload: { change_type: intent },
      created_by: callerId,
    }, { onConflict: "organization_id,deduplication_key" });
  }
  if (before?.start_at !== updated.start_at) {
    await admin.from("sd_event_operations").update({
      scheduled_start_at: updated.start_at,
    }).eq("event_id", eventId!).eq("organization_id", organizationId);
  }
  const auditAction = action === "cancel"
    ? "cancelled"
    : before?.status !== "postponed" && updated.status === "postponed"
    ? "postponed"
    : before?.start_at !== updated.start_at
    ? "rescheduled"
    : before?.visibility !== updated.visibility
    ? "visibility_changed"
    : "edited";
  await admin.from("sd_team_event_audit_logs").insert({
    organization_id: organizationId,
    season_id: seasonId,
    team_id: teamId,
    event_id: eventId,
    actor_id: callerId,
    action: auditAction,
    request_id: requestId,
    reason: text(payload.reason) || null,
  });
  if (overrideReason) {
    await admin.from("sd_team_event_audit_logs").insert({
      organization_id: organizationId,
      season_id: seasonId,
      team_id: teamId,
      event_id: eventId,
      actor_id: callerId,
      action: "conflict_override",
      request_id: crypto.randomUUID(),
      reason: overrideReason,
      details: { conflicts: conflictList },
    });
  }
  return ok({ event: updated, conflicts: conflictList });
});
