import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import {
  completionBlockers,
  isAttendanceStatus,
  isAvailabilityStatus,
  isNearEventStart,
  isOperationStatus,
  mayTransition,
  operationTypeForEvent,
  sanitizeOperationForConsumer,
  sanitizeParticipantForConsumer,
} from "../_shared/event_operations.ts";

type Row = Record<string, unknown>;

function json(status: number, body: Row) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json; charset=utf-8" },
  });
}
const ok = (body: Row) => json(200, { ok: true, ...body, error: null });
const fail = (status: number, code: string, message = code) =>
  json(status, { ok: false, error: { code, message } });
const env = (key: string) => (Deno.env.get(key) ?? "").trim();
const text = (value: unknown) => String(value ?? "").trim();
const record = (value: unknown): Row =>
  value && typeof value === "object" && !Array.isArray(value)
    ? value as Row
    : {};
const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const uuid = (value: unknown) =>
  uuidPattern.test(text(value)) ? text(value) : null;
const validInstant = (value: unknown) => {
  if (value == null || text(value) === "") return true;
  const raw = text(value);
  return /(?:Z|[+-]\d{2}:\d{2})$/i.test(raw) &&
    Number.isFinite(new Date(raw).getTime());
};

class OperationFailure extends Error {
  constructor(public status: number, public code: string, message = code) {
    super(message);
  }
}

const operationSelect =
  "id,organization_id,season_id,team_id,event_id,operation_type,status,scheduled_start_at,started_at,started_by,completed_at,completed_by,reopened_at,reopened_by,cancelled_at,operational_summary,internal_notes,attendance_finalized_at,version,created_at,updated_at";

Deno.serve(async (req) => {
  if (req.method !== "POST") return fail(405, "method_not_allowed");
  let payload: Row;
  try {
    payload = record(await req.json());
  } catch {
    return fail(400, "invalid_json");
  }

  const url = env("SUPABASE_URL") || env("DHD_SUPABASE_URL");
  const anon = env("SUPABASE_ANON_KEY") || env("DHD_SUPABASE_ANON_KEY");
  const service = env("DHD_SERVICE_ROLE_KEY") ||
    env("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !anon || !service) return fail(500, "missing_supabase_secrets");
  const token = (req.headers.get("authorization") ?? "").replace(
    /^Bearer\s+/i,
    "",
  ).trim();
  if (!token) return fail(401, "missing_auth");
  const callerClient = createClient(url, anon, {
    global: { headers: { Authorization: `Bearer ${token}` } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: userData, error: userError } = await callerClient.auth.getUser(
    token,
  );
  if (userError || !userData.user?.id) return fail(401, "invalid_auth");
  const callerId = userData.user.id;
  const admin = createClient(url, service, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const organizationId = uuid(payload.organization_id);
  if (!organizationId) return fail(400, "missing_organization_id");
  const { data: membership, error: membershipError } = await admin.from(
    "sd_org_memberships",
  ).select("role,status").eq("org_id", organizationId).eq(
    "user_id",
    callerId,
  ).eq("status", "active").maybeSingle();
  if (membershipError) return fail(500, "membership_lookup_failed");
  if (!membership) return fail(403, "organization_membership_required");
  const role = text((membership as Row).role).toLowerCase();
  const isAdmin = role === "owner" || role === "admin";
  const action = text(payload.action);

  async function capabilities(teamId: string) {
    const { data, error } = await admin.rpc("sd_resolve_team_capabilities", {
      target_organization: organizationId,
      target_team: teamId,
      target_actor: callerId,
    });
    if (error) throw new OperationFailure(500, "capability_resolution_failed");
    return new Set((data ?? []).map(String));
  }

  async function loadEvent(eventId: string) {
    const { data, error } = await admin.from("sd_team_events").select(
      "*,sd_team_event_practices(*),sd_team_event_games(*),sd_team_event_tournaments(*),sd_team_event_meetings(*),sd_team_event_travel(*),sd_team_event_coaches(*)",
    ).eq("id", eventId).eq("organization_id", organizationId).maybeSingle();
    if (error) throw new OperationFailure(500, "event_lookup_failed");
    if (!data) throw new OperationFailure(404, "event_not_found");
    return data as Row;
  }

  async function consumerPlayer(event: Row): Promise<string | null> {
    if (role === "player") {
      const target = uuid(payload.player_id) ?? callerId;
      if (target !== callerId) {
        throw new OperationFailure(403, "player_scope_required");
      }
      const { data } = await admin.from("sd_player_team_memberships").select(
        "id",
      ).eq("organization_id", organizationId).eq("player_id", target).eq(
        "team_id",
        event.team_id,
      ).eq("active", true).is("ended_at", null).maybeSingle();
      if (!data) throw new OperationFailure(403, "active_team_required");
      return target;
    }
    if (role === "parent") {
      const target = uuid(payload.player_id);
      if (!target) throw new OperationFailure(400, "missing_player_id");
      const { data: link } = await admin.from("sd_parent_child_links").select(
        "child_id",
      ).eq("org_id", organizationId).eq("parent_id", callerId).eq(
        "child_id",
        target,
      ).maybeSingle();
      if (!link) throw new OperationFailure(403, "parent_link_required");
      const { data } = await admin.from("sd_player_team_memberships").select(
        "id",
      ).eq("organization_id", organizationId).eq("player_id", target).eq(
        "team_id",
        event.team_id,
      ).eq("active", true).is("ended_at", null).maybeSingle();
      if (!data) throw new OperationFailure(403, "active_team_required");
      return target;
    }
    return null;
  }

  async function authorizeView(event: Row) {
    if (role === "player" || role === "parent") {
      if (event.visibility !== "team" || event.status === "draft") {
        throw new OperationFailure(404, "event_not_found");
      }
      return { consumer: true, playerId: await consumerPlayer(event) };
    }
    const resolved = await capabilities(text(event.team_id));
    if (!resolved.has("view_event_operation")) {
      throw new OperationFailure(403, "view_event_operation_required");
    }
    return { consumer: false, playerId: null, resolved };
  }

  async function audit(
    operation: Row,
    requestId: string,
    auditAction: string,
    values: Row = {},
  ) {
    const { error } = await admin.from("sd_event_operation_audit_logs").upsert({
      organization_id: organizationId,
      season_id: operation.season_id,
      team_id: operation.team_id,
      event_id: operation.event_id,
      event_operation_id: operation.id,
      actor_id: callerId,
      action: auditAction,
      request_id: requestId,
      target_id: values.target_id ?? null,
      previous_value: values.previous_value ?? null,
      new_value: values.new_value ?? null,
      reason: values.reason ?? null,
      details: values.details ?? {},
    }, {
      onConflict: "organization_id,request_id,action",
      ignoreDuplicates: true,
    });
    if (error) throw new OperationFailure(500, "audit_persistence_failed");
  }

  async function intent(
    operation: Row,
    requestId: string,
    intentType: string,
    suffix: string,
    intentPayload: Row = {},
  ) {
    const { error } = await admin.from("sd_team_event_notification_intents")
      .upsert({
        organization_id: organizationId,
        team_id: operation.team_id,
        event_id: operation.event_id,
        event_operation_id: operation.id,
        intent_type: intentType,
        deduplication_key: `${requestId}:${operation.id}:${suffix}`,
        payload: intentPayload,
        created_by: callerId,
      }, {
        onConflict: "organization_id,deduplication_key",
        ignoreDuplicates: true,
      });
    if (error) throw new OperationFailure(500, "notification_intent_failed");
  }

  async function ensureOperation(event: Row, requestId: string) {
    const { data: existing } = await admin.from("sd_event_operations").select(
      operationSelect,
    ).eq("event_id", event.id).maybeSingle();
    let operation = existing as Row | null;
    let initialized = false;
    if (!operation) {
      const operationRow = {
        organization_id: organizationId,
        season_id: event.season_id,
        team_id: event.team_id,
        event_id: event.id,
        operation_type: operationTypeForEvent(text(event.event_type)),
        status: "not_started",
        scheduled_start_at: event.start_at,
      };
      let { data: inserted, error } = await admin.from("sd_event_operations")
        .insert(operationRow).select(operationSelect).single();
      if (error?.code === "23505") {
        const result = await admin.from("sd_event_operations").select(
          operationSelect,
        ).eq("event_id", event.id).single();
        inserted = result.data;
        error = result.error;
      } else if (!error) {
        initialized = true;
      }
      if (error || !inserted) {
        throw new OperationFailure(500, "operation_initialization_failed");
      }
      operation = inserted as Row;
    }
    const { data: players, error: playerError } = await admin.from(
      "sd_player_team_memberships",
    ).select("player_id").eq("organization_id", organizationId).eq(
      "season_id",
      event.season_id,
    ).eq("team_id", event.team_id).eq("active", true).is("ended_at", null);
    if (playerError) throw new OperationFailure(500, "roster_snapshot_failed");
    let coachIds = Array.isArray(event.sd_team_event_coaches)
      ? (event.sd_team_event_coaches as Row[]).map((row) => text(row.coach_id))
      : [];
    if (!coachIds.length) {
      const { data: coaches } = await admin.from("sd_coach_team_assignments")
        .select("coach_id").eq("organization_id", organizationId).eq(
          "season_id",
          event.season_id,
        ).eq("team_id", event.team_id).eq("active", true).is("ended_at", null);
      coachIds = (coaches ?? []).map((row: Row) => text(row.coach_id));
    }
    const participantRows = [
      ...(players ?? []).map((row: Row) => ({
        user_id: row.player_id,
        participant_type: "player",
      })),
      ...[...new Set(coachIds)].map((coachId) => ({
        user_id: coachId,
        participant_type: "coach",
      })),
    ].map((participant) => ({
      event_operation_id: operation.id,
      organization_id: organizationId,
      season_id: event.season_id,
      team_id: event.team_id,
      event_id: event.id,
      expected: true,
      ...participant,
    }));
    if (participantRows.length) {
      const { error: participantError } = await admin.from(
        "sd_event_operation_participants",
      ).upsert(participantRows, {
        onConflict: "event_operation_id,user_id",
        ignoreDuplicates: true,
      });
      if (participantError) {
        throw new OperationFailure(500, "participant_snapshot_failed");
      }
    }
    const checklist: Row[] = [{
      event_operation_id: operation.id,
      organization_id: organizationId,
      phase: "pre_event",
      title: "Review expected participants and attendance",
      required: true,
      sort_order: 10,
      source: "system",
      visibility: "staff",
    }];
    if (event.arrival_at || event.location_name) {
      checklist.push({
        event_operation_id: operation.id,
        organization_id: organizationId,
        phase: "pre_event",
        title: "Confirm configured arrival and location details",
        details: [event.arrival_at, event.location_name].filter(Boolean).join(
          " • ",
        ),
        required: false,
        sort_order: 20,
        source: "event",
        visibility: "team",
      });
    }
    const { error: checklistError } = await admin.from(
      "sd_event_operation_checklist_items",
    ).upsert(checklist, {
      onConflict: "event_operation_id,source,title",
      ignoreDuplicates: true,
    });
    if (checklistError) {
      throw new OperationFailure(500, "checklist_initialization_failed");
    }
    if (initialized) {
      await audit(operation, requestId, "initialized", {
        details: { participant_count: participantRows.length },
      });
    }
    return { operation, initialized };
  }

  async function operationPayload(
    operation: Row,
    consumer: boolean,
    playerId: string | null,
  ) {
    let participantQuery = admin.from("sd_event_operation_participants").select(
      "*",
    ).eq("event_operation_id", operation.id).order("participant_type");
    if (consumer && playerId) {
      participantQuery = participantQuery.eq("user_id", playerId);
    }
    const [participantResult, checklistResult, noteResult] = await Promise.all([
      participantQuery,
      admin.from("sd_event_operation_checklist_items").select("*").eq(
        "event_operation_id",
        operation.id,
      ).order("sort_order"),
      admin.from("sd_event_operation_notes").select("*").eq(
        "event_operation_id",
        operation.id,
      ).order("created_at"),
    ]);
    if (participantResult.error || checklistResult.error || noteResult.error) {
      throw new OperationFailure(500, "operation_detail_failed");
    }
    if (!consumer) {
      return {
        operation,
        participants: participantResult.data ?? [],
        checklist: checklistResult.data ?? [],
        notes: noteResult.data ?? [],
      };
    }
    const notes = (noteResult.data ?? []).filter((note: Row) =>
      note.visibility === "team" ||
      (note.visibility === "player" && note.subject_player_id === playerId)
    ).map((note: Row) => ({
      id: note.id,
      event_operation_id: note.event_operation_id,
      note_type: note.note_type,
      visibility: note.visibility,
      subject_player_id: note.subject_player_id,
      body: note.body,
      published_at: note.published_at,
      created_at: note.created_at,
      updated_at: note.updated_at,
      version: note.version,
    }));
    return {
      operation: sanitizeOperationForConsumer(operation),
      participants: (participantResult.data ?? []).map((participant: Row) =>
        sanitizeParticipantForConsumer(participant)
      ),
      checklist: (checklistResult.data ?? []).filter((item: Row) =>
        item.visibility === "team"
      ).map((item: Row) => ({
        id: item.id,
        event_operation_id: item.event_operation_id,
        phase: item.phase,
        title: item.title,
        details: item.details,
        completed_at: item.completed_at,
        required: item.required,
        visibility: item.visibility,
        version: item.version,
      })),
      notes,
    };
  }

  async function withReceipt(
    requestId: string,
    operationId: string | null,
    run: () => Promise<Row>,
  ): Promise<Response> {
    const { error } = await admin.from("sd_event_operation_mutations").insert({
      organization_id: organizationId,
      request_id: requestId,
      action,
      actor_id: callerId,
      event_operation_id: operationId,
    });
    if (error?.code === "23505") {
      const { data: receipt } = await admin.from("sd_event_operation_mutations")
        .select("action,status,response").eq("organization_id", organizationId)
        .eq("request_id", requestId).single();
      if (receipt?.action !== action) return fail(409, "idempotency_mismatch");
      if (receipt?.status === "completed" && receipt.response) {
        return ok({ ...record(receipt.response), replayed: true });
      }
      return fail(
        409,
        "mutation_in_progress",
        "This change is still processing. Please retry shortly.",
      );
    }
    if (error) return fail(500, "mutation_claim_failed");
    try {
      const result = await run();
      const { error: completionError } = await admin.from(
        "sd_event_operation_mutations",
      ).update({
        status: "completed",
        response: result,
        completed_at: new Date().toISOString(),
        event_operation_id: result.operation_id ?? operationId,
      }).eq("organization_id", organizationId).eq("request_id", requestId);
      if (completionError) {
        throw new OperationFailure(500, "mutation_receipt_failed");
      }
      return ok(result);
    } catch (error) {
      await admin.from("sd_event_operation_mutations").delete().eq(
        "organization_id",
        organizationId,
      ).eq("request_id", requestId).eq("status", "processing");
      const failure = error instanceof OperationFailure
        ? error
        : new OperationFailure(500, "operation_mutation_failed");
      return fail(failure.status, failure.code, failure.message);
    }
  }

  async function applyTransactionalMutation(
    eventId: string,
    requestId: string,
    staff: boolean,
    mutationPayload: Row,
  ): Promise<Row> {
    const { data, error } = await admin.rpc(
      "sd_apply_event_operation_mutation",
      {
        p_organization_id: organizationId,
        p_event_id: eventId,
        p_actor_id: callerId,
        p_action: action,
        p_request_id: requestId,
        p_staff: staff,
        p_payload: mutationPayload,
      },
    );
    if (!error) return record(data);
    const diagnostic = [error.message, error.details, error.hint].filter(
      Boolean,
    ).join(" ");
    const known = [
      "idempotency_mismatch",
      "mutation_in_progress",
      "event_not_found",
      "operation_not_initialized",
      "availability_closed",
      "event_not_operable",
      "participant_not_found",
      "missing_expected_version",
      "stale_version",
      "reopen_reason_required",
      "ready_completion_reason_required",
      "completion_override_required",
      "invalid_operation_transition",
      "missing_participants",
      "duplicate_participant",
      "attendance_correction_reason_required",
      "attendance_review_required",
      "attendance_locked",
      "checklist_item_not_found",
      "invalid_note_visibility",
      "unsupported_action",
    ].find((code) => diagnostic.includes(code));
    const code = known ?? "operation_mutation_failed";
    const conflict = new Set([
      "idempotency_mismatch",
      "mutation_in_progress",
      "stale_version",
      "invalid_operation_transition",
      "completion_override_required",
      "attendance_correction_reason_required",
      "attendance_review_required",
      "attendance_locked",
      "event_not_operable",
    ]).has(code);
    const missing = code.endsWith("_not_found");
    throw new OperationFailure(missing ? 404 : conflict ? 409 : 400, code);
  }

  try {
    if (action === "list") {
      const teamId = uuid(payload.team_id);
      if (!teamId) throw new OperationFailure(400, "missing_team_id");
      const resolved = await capabilities(teamId);
      if (!resolved.has("view_event_operation")) {
        throw new OperationFailure(403, "view_event_operation_required");
      }
      const eventIds = Array.isArray(payload.event_ids)
        ? payload.event_ids.map(uuid).filter(Boolean) as string[]
        : [];
      if (!eventIds.length) return ok({ operations: [] });
      const { data: operations, error } = await admin.from(
        "sd_event_operations",
      )
        .select(operationSelect).eq("organization_id", organizationId).eq(
          "team_id",
          teamId,
        ).in("event_id", eventIds);
      if (error) throw new OperationFailure(500, "operation_list_failed");
      const operationIds = (operations ?? []).map((row: Row) => text(row.id));
      const { data: participants, error: participantError } =
        operationIds.length
          ? await admin.from("sd_event_operation_participants").select(
            "event_operation_id,participant_type,expected,availability_status,attendance_status",
          ).in("event_operation_id", operationIds)
          : { data: [], error: null };
      const { data: checklist, error: checklistError } = operationIds.length
        ? await admin.from("sd_event_operation_checklist_items").select(
          "event_operation_id,required,completed_at,overridden_at",
        ).in("event_operation_id", operationIds)
        : { data: [], error: null };
      if (participantError || checklistError) {
        throw new OperationFailure(500, "operation_summary_failed");
      }
      return ok({
        operations: (operations ?? []).map((operation: Row) => {
          const people = (participants ?? []).filter((row: Row) =>
            row.event_operation_id === operation.id &&
            row.participant_type === "player" && row.expected === true
          );
          const tasks = (checklist ?? []).filter((row: Row) =>
            row.event_operation_id === operation.id
          );
          return {
            ...operation,
            expected_players: people.length,
            unresolved_availability: people.filter((row: Row) =>
              row.availability_status === "unknown" ||
              row.availability_status === "tentative"
            ).length,
            unrecorded_attendance: people.filter((row: Row) =>
              row.attendance_status === "not_recorded"
            ).length,
            checklist_total: tasks.length,
            checklist_completed: tasks.filter((row: Row) =>
              row.completed_at || row.overridden_at
            ).length,
          };
        }),
      });
    }

    const eventId = uuid(payload.event_id);
    if (!eventId) throw new OperationFailure(400, "missing_event_id");
    const event = await loadEvent(eventId);
    const authorization = await authorizeView(event);
    const existingResult = await admin.from("sd_event_operations").select(
      operationSelect,
    ).eq("event_id", eventId).maybeSingle();
    if (existingResult.error) {
      throw new OperationFailure(500, "operation_lookup_failed");
    }
    let existing = existingResult.data as Row | null;

    if (action === "get") {
      if (!existing) {
        return ok({
          operation: null,
          participants: [],
          checklist: [],
          notes: [],
        });
      }
      return ok(
        await operationPayload(
          existing,
          authorization.consumer,
          authorization.playerId,
        ),
      );
    }

    const requestId = uuid(payload.request_id);
    if (!requestId) throw new OperationFailure(400, "missing_request_id");

    const transactionalActions = new Set([
      "initialize",
      "availability",
      "transition",
      "attendance",
      "attendance_bulk",
      "finalize_attendance",
      "checklist",
      "note",
      "note_update",
      "reconcile_participants",
    ]);
    if (transactionalActions.has(action)) {
      const mutationPayload: Row = { ...payload };
      if (action === "initialize") {
        if (
          authorization.consumer ||
          !authorization.resolved?.has("start_event_operation")
        ) {
          throw new OperationFailure(403, "start_event_operation_required");
        }
      } else if (action === "availability") {
        const targetPlayerId = uuid(payload.player_id) ??
          authorization.playerId;
        if (!targetPlayerId) {
          throw new OperationFailure(400, "missing_player_id");
        }
        if (!isAvailabilityStatus(payload.availability_status)) {
          throw new OperationFailure(400, "invalid_availability_status");
        }
        if (
          !validInstant(payload.expected_arrival_at) ||
          !validInstant(payload.expected_departure_at)
        ) {
          throw new OperationFailure(400, "invalid_timestamp");
        }
        if (
          payload.availability_status === "late" &&
          !text(payload.expected_arrival_at)
        ) {
          throw new OperationFailure(400, "expected_arrival_required");
        }
        if (
          payload.availability_status === "leaving_early" &&
          !text(payload.expected_departure_at)
        ) {
          throw new OperationFailure(400, "expected_departure_required");
        }
        if (
          !authorization.consumer &&
          !authorization.resolved?.has("manage_event_availability")
        ) {
          throw new OperationFailure(403, "manage_event_availability_required");
        }
        if (
          authorization.consumer && authorization.playerId !== targetPlayerId
        ) {
          throw new OperationFailure(403, "availability_subject_required");
        }
        if (
          !authorization.consumer && !text(payload.override_reason)
        ) {
          throw new OperationFailure(
            400,
            "availability_override_reason_required",
          );
        }
        mutationPayload.player_id = targetPlayerId;
      } else {
        if (authorization.consumer) {
          throw new OperationFailure(403, "staff_operation_required");
        }
        const resolved = authorization.resolved!;
        if (action === "transition") {
          const nextStatus = payload.status;
          if (!isOperationStatus(nextStatus) || nextStatus === "cancelled") {
            throw new OperationFailure(400, "invalid_operation_status");
          }
          const needed = nextStatus === "completed"
            ? "complete_event_operation"
            : nextStatus === "ready"
            ? "reopen_event_operation"
            : "start_event_operation";
          if (!resolved.has(needed)) {
            throw new OperationFailure(403, `${needed}_required`);
          }
        } else if (
          action === "attendance" || action === "attendance_bulk" ||
          action === "finalize_attendance" ||
          action === "reconcile_participants"
        ) {
          if (!resolved.has("manage_event_attendance")) {
            throw new OperationFailure(
              403,
              "manage_event_attendance_required",
            );
          }
          if (action === "attendance") {
            const participantId = uuid(payload.participant_id);
            const expectedVersion = Number(payload.participant_version);
            if (!participantId || !Number.isInteger(expectedVersion)) {
              throw new OperationFailure(400, "missing_participants");
            }
            mutationPayload.participants = [{
              participant_id: participantId,
              expected_version: expectedVersion,
            }];
          } else if (action === "attendance_bulk") {
            const targets = Array.isArray(payload.participants)
              ? payload.participants.map(record).map((target) => ({
                participant_id: uuid(target.participant_id),
                expected_version: Number(target.expected_version),
              }))
              : [];
            if (
              !targets.length ||
              targets.some((target) =>
                !target.participant_id ||
                !Number.isInteger(target.expected_version)
              )
            ) {
              throw new OperationFailure(400, "missing_participants");
            }
            mutationPayload.participants = targets;
          } else if (action === "reconcile_participants") {
            if (!text(payload.reason)) {
              throw new OperationFailure(
                400,
                "reconciliation_reason_required",
              );
            }
            if (!Number.isInteger(Number(payload.expected_version))) {
              throw new OperationFailure(400, "missing_expected_version");
            }
          }
          if (
            (action === "attendance" || action === "attendance_bulk") &&
            !isAttendanceStatus(payload.attendance_status)
          ) {
            throw new OperationFailure(400, "invalid_attendance_status");
          }
          if (
            (action === "attendance" || action === "attendance_bulk") &&
            (!validInstant(payload.arrival_at) ||
              !validInstant(payload.departure_at))
          ) {
            throw new OperationFailure(400, "invalid_timestamp");
          }
        } else if (action === "checklist") {
          if (!resolved.has("manage_event_checklist")) {
            throw new OperationFailure(403, "manage_event_checklist_required");
          }
          if (
            !uuid(payload.item_id) ||
            !Number.isInteger(Number(payload.item_version))
          ) {
            throw new OperationFailure(400, "missing_checklist_item");
          }
        } else if (action === "note" || action === "note_update") {
          const noteType = text(payload.note_type);
          const visibility = text(payload.visibility);
          const privatePlayer = noteType === "player_coach_note";
          const needed = privatePlayer
            ? "add_private_player_notes"
            : "add_team_event_notes";
          if (!resolved.has(needed)) {
            throw new OperationFailure(403, `${needed}_required`);
          }
          if (!text(payload.body)) {
            throw new OperationFailure(400, "missing_note_body");
          }
          if (
            action === "note_update" &&
            (!uuid(payload.note_id) ||
              !Number.isInteger(Number(payload.note_version)))
          ) {
            throw new OperationFailure(400, "missing_note_version");
          }
          const valid =
            (noteType === "internal_staff_note" && visibility === "staff" &&
              !payload.player_id) ||
            (privatePlayer && ["staff", "player"].includes(visibility) &&
              Boolean(uuid(payload.player_id))) ||
            (noteType === "team_coach_note" &&
              ["staff", "team"].includes(visibility) && !payload.player_id) ||
            (noteType === "post_event_recap" && visibility === "team" &&
              !payload.player_id);
          if (!valid) {
            throw new OperationFailure(400, "invalid_note_visibility");
          }
        }
      }

      const result = await applyTransactionalMutation(
        eventId,
        requestId,
        !authorization.consumer,
        mutationPayload,
      );
      if (action === "initialize") {
        const operation = record(result.operation);
        return ok({
          ...result,
          ...await operationPayload(operation, false, null),
        });
      }
      if (action === "availability" && authorization.consumer) {
        return ok({
          ...result,
          participant: sanitizeParticipantForConsumer(
            record(result.participant),
          ),
        });
      }
      return ok(result);
    }

    if (action === "initialize") {
      if (
        authorization.consumer ||
        !authorization.resolved?.has("start_event_operation")
      ) {
        throw new OperationFailure(403, "start_event_operation_required");
      }
      return await withReceipt(
        requestId,
        existing ? text(existing.id) : null,
        async () => {
          const initialized = await ensureOperation(event, requestId);
          return {
            operation_id: initialized.operation.id,
            initialized: initialized.initialized,
            ...await operationPayload(initialized.operation, false, null),
          };
        },
      );
    }

    if (action === "availability") {
      const targetPlayerId = uuid(payload.player_id) ?? authorization.playerId;
      if (!targetPlayerId) throw new OperationFailure(400, "missing_player_id");
      const status = payload.availability_status;
      if (!isAvailabilityStatus(status)) {
        throw new OperationFailure(400, "invalid_availability_status");
      }
      const staffOverride = !authorization.consumer;
      if (
        staffOverride &&
        !authorization.resolved?.has("manage_event_availability")
      ) {
        throw new OperationFailure(403, "manage_event_availability_required");
      }
      if (staffOverride && !text(payload.override_reason)) {
        throw new OperationFailure(
          400,
          "availability_override_reason_required",
        );
      }
      if (authorization.consumer && authorization.playerId !== targetPlayerId) {
        throw new OperationFailure(403, "availability_subject_required");
      }
      return await withReceipt(
        requestId,
        existing ? text(existing.id) : null,
        async () => {
          const initialized = await ensureOperation(event, requestId);
          existing = initialized.operation;
          const { data: participant } = await admin.from(
            "sd_event_operation_participants",
          ).select("*").eq("event_operation_id", existing.id).eq(
            "user_id",
            targetPlayerId,
          ).maybeSingle();
          if (!participant) {
            throw new OperationFailure(404, "participant_not_found");
          }
          const expectedVersion = Number(
            payload.participant_version ?? participant.version,
          );
          const now = new Date().toISOString();
          const patch = {
            availability_status: status,
            availability_reason: text(payload.reason) || null,
            expected_arrival_at: text(payload.expected_arrival_at) || null,
            expected_departure_at: text(payload.expected_departure_at) || null,
            availability_submitted_by: callerId,
            availability_submitted_at: participant.availability_submitted_at ??
              now,
            availability_last_changed_at: now,
            version: expectedVersion + 1,
          };
          const { data: updated, error } = await admin.from(
            "sd_event_operation_participants",
          ).update(patch).eq("id", participant.id).eq(
            "version",
            expectedVersion,
          )
            .select("*").maybeSingle();
          if (error) {
            throw new OperationFailure(500, "availability_update_failed");
          }
          if (!updated) {
            throw new OperationFailure(
              409,
              "stale_version",
              "Availability changed on another device. Refresh and try again.",
            );
          }
          await audit(
            existing,
            requestId,
            staffOverride ? "availability_overridden" : "availability_declared",
            {
              target_id: participant.id,
              previous_value: {
                status: participant.availability_status,
                version: participant.version,
              },
              new_value: { status, version: updated.version },
              reason: staffOverride
                ? text(payload.override_reason) || null
                : null,
            },
          );
          await intent(
            existing,
            requestId,
            "availability_changed",
            "availability",
            { player_id: targetPlayerId, status },
          );
          if (status === "unavailable") {
            await intent(
              existing,
              requestId,
              "player_unavailable",
              "unavailable",
              { player_id: targetPlayerId },
            );
          }
          return {
            operation_id: existing.id,
            participant: authorization.consumer
              ? sanitizeParticipantForConsumer(updated as Row)
              : updated,
            attention: isNearEventStart(text(event.start_at)),
          };
        },
      );
    }

    if (!existing) throw new OperationFailure(409, "operation_not_initialized");
    if (authorization.consumer) {
      throw new OperationFailure(403, "staff_operation_required");
    }
    const resolved = authorization.resolved!;

    if (action === "transition") {
      const nextStatus = payload.status;
      if (!isOperationStatus(nextStatus)) {
        throw new OperationFailure(400, "invalid_operation_status");
      }
      const currentStatus = text(existing.status);
      if (
        !isOperationStatus(currentStatus) ||
        !mayTransition(currentStatus, nextStatus)
      ) {
        throw new OperationFailure(409, "invalid_operation_transition");
      }
      const needed = nextStatus === "completed"
        ? "complete_event_operation"
        : nextStatus === "ready" && currentStatus === "completed"
        ? "reopen_event_operation"
        : "start_event_operation";
      if (!resolved.has(needed)) {
        throw new OperationFailure(403, `${needed}_required`);
      }
      const expectedVersion = Number(payload.expected_version);
      if (!Number.isInteger(expectedVersion)) {
        throw new OperationFailure(400, "missing_expected_version");
      }
      const reason = text(payload.reason);
      if (currentStatus === "completed" && !reason) {
        throw new OperationFailure(400, "reopen_reason_required");
      }
      if (
        currentStatus === "ready" && nextStatus === "completed" && !reason
      ) {
        throw new OperationFailure(400, "ready_completion_reason_required");
      }
      return await withReceipt(requestId, text(existing.id), async () => {
        const people = await admin.from("sd_event_operation_participants")
          .select("*").eq("event_operation_id", existing!.id);
        const tasks = await admin.from("sd_event_operation_checklist_items")
          .select("*").eq("event_operation_id", existing!.id);
        if (people.error || tasks.error) {
          throw new OperationFailure(500, "completion_check_failed");
        }
        const blockers = completionBlockers(
          people.data ?? [],
          tasks.data ?? [],
        );
        if (
          nextStatus === "completed" &&
          (blockers.attendance || blockers.requiredChecklist) && !reason
        ) {
          throw new OperationFailure(
            409,
            "completion_override_required",
            "Review attendance and required checklist items, or provide a completion reason.",
          );
        }
        const now = new Date().toISOString();
        const patch: Row = { status: nextStatus, version: expectedVersion + 1 };
        if (nextStatus === "in_progress" && currentStatus !== "paused") {
          patch.started_at = existing!.started_at ?? now;
          patch.started_by = existing!.started_by ?? callerId;
        }
        if (nextStatus === "completed") {
          patch.completed_at = now;
          patch.completed_by = callerId;
          patch.operational_summary = text(payload.operational_summary) || null;
        }
        if (currentStatus === "completed" && nextStatus === "ready") {
          const snapshot = {
            operation: existing,
            participants: people.data,
            checklist: tasks.data,
          };
          const { error: snapshotError } = await admin.from(
            "sd_event_operation_versions",
          ).upsert({
            event_operation_id: existing!.id,
            organization_id: organizationId,
            operation_version: existing!.version,
            snapshot,
            reason,
            captured_by: callerId,
          }, {
            onConflict: "event_operation_id,operation_version",
            ignoreDuplicates: true,
          });
          if (snapshotError) {
            throw new OperationFailure(500, "reopen_snapshot_failed");
          }
          patch.reopened_at = now;
          patch.reopened_by = callerId;
          patch.completed_at = null;
          patch.completed_by = null;
        }
        const { data: updated, error } = await admin.from("sd_event_operations")
          .update(patch).eq("id", existing!.id).eq("version", expectedVersion)
          .select(operationSelect).maybeSingle();
        if (error) {
          throw new OperationFailure(500, "operation_transition_failed");
        }
        if (!updated) {
          throw new OperationFailure(
            409,
            "stale_version",
            "Operation changed on another device. Refresh and try again.",
          );
        }
        const auditAction = nextStatus === "completed"
          ? "completed"
          : currentStatus === "completed"
          ? "reopened"
          : nextStatus === "paused"
          ? "paused"
          : currentStatus === "paused"
          ? "resumed"
          : "started";
        await audit(updated as Row, requestId, auditAction, {
          previous_value: { status: currentStatus, version: expectedVersion },
          new_value: { status: nextStatus, version: updated.version },
          reason: reason || null,
          details: blockers,
        });
        if (nextStatus === "in_progress" && currentStatus !== "paused") {
          await intent(
            updated as Row,
            requestId,
            "operation_started",
            "started",
          );
        }
        if (nextStatus === "completed") {
          await admin.from("sd_team_events").update({
            status: "completed",
            updated_by: callerId,
          })
            .eq("id", eventId).eq("organization_id", organizationId);
          await intent(
            updated as Row,
            requestId,
            "event_completed",
            "completed",
          );
        } else if (currentStatus === "completed" && nextStatus === "ready") {
          await admin.from("sd_team_events").update({
            status: "confirmed",
            updated_by: callerId,
          })
            .eq("id", eventId).eq("organization_id", organizationId);
        }
        return { operation_id: updated.id, operation: updated, blockers };
      });
    }

    if (action === "attendance" || action === "attendance_bulk") {
      if (!resolved.has("manage_event_attendance")) {
        throw new OperationFailure(403, "manage_event_attendance_required");
      }
      const targetIds = action === "attendance_bulk"
        ? (Array.isArray(payload.participant_ids)
          ? payload.participant_ids.map(uuid).filter(Boolean) as string[]
          : [])
        : [uuid(payload.participant_id)].filter(Boolean) as string[];
      if (!targetIds.length) {
        throw new OperationFailure(400, "missing_participants");
      }
      const status = payload.attendance_status;
      if (!isAttendanceStatus(status)) {
        throw new OperationFailure(400, "invalid_attendance_status");
      }
      const correctionReason = text(payload.correction_reason);
      if (existing.status === "completed" && !correctionReason) {
        throw new OperationFailure(
          409,
          "attendance_correction_reason_required",
        );
      }
      return await withReceipt(requestId, text(existing.id), async () => {
        const { data: participants, error: lookupError } = await admin.from(
          "sd_event_operation_participants",
        ).select("*").eq("event_operation_id", existing!.id).in(
          "id",
          targetIds,
        );
        if (lookupError || participants?.length !== targetIds.length) {
          throw new OperationFailure(404, "participant_not_found");
        }
        const updates: Row[] = [];
        for (const participant of participants as Row[]) {
          const expected = action === "attendance"
            ? Number(payload.participant_version)
            : Number(participant.version);
          const patch = {
            attendance_status: status,
            arrival_at: text(payload.arrival_at) ||
              (status === "present" || status === "late"
                ? new Date().toISOString()
                : participant.arrival_at),
            departure_at: text(payload.departure_at) || null,
            checked_in_by: callerId,
            attendance_notes: text(payload.attendance_notes) || null,
            private_notes: text(payload.private_notes) || null,
            version: expected + 1,
          };
          const { data: updated } = await admin.from(
            "sd_event_operation_participants",
          )
            .update(patch).eq("id", participant.id).eq(
              "event_operation_id",
              existing!.id,
            )
            .eq("version", expected).select("*").maybeSingle();
          if (!updated) {
            throw new OperationFailure(
              409,
              "stale_version",
              "Attendance changed on another device. Refresh and try again.",
            );
          }
          updates.push(updated as Row);
        }
        const corrected = existing!.status === "completed";
        await audit(
          existing!,
          requestId,
          corrected
            ? "attendance_corrected"
            : action === "attendance_bulk"
            ? "attendance_bulk_changed"
            : "attendance_changed",
          {
            previous_value: {
              participants: (participants as Row[]).map((row) => ({
                id: row.id,
                status: row.attendance_status,
                version: row.version,
              })),
            },
            new_value: {
              participants: updates.map((row) => ({
                id: row.id,
                status: row.attendance_status,
                version: row.version,
              })),
            },
            reason: correctionReason || null,
          },
        );
        if (corrected) {
          await intent(
            existing!,
            requestId,
            "attendance_correction",
            "attendance-correction",
          );
        }
        return { operation_id: existing!.id, participants: updates };
      });
    }

    if (action === "finalize_attendance") {
      if (!resolved.has("manage_event_attendance")) {
        throw new OperationFailure(403, "manage_event_attendance_required");
      }
      const expectedVersion = Number(payload.expected_version);
      return await withReceipt(requestId, text(existing.id), async () => {
        const { count } = await admin.from("sd_event_operation_participants")
          .select("id", { count: "exact", head: true })
          .eq("event_operation_id", existing!.id).eq(
            "participant_type",
            "player",
          ).eq("expected", true)
          .eq("attendance_status", "not_recorded");
        if ((count ?? 0) > 0 && !text(payload.reason)) {
          throw new OperationFailure(409, "attendance_review_required");
        }
        const now = new Date().toISOString();
        const { data: updated } = await admin.from("sd_event_operations")
          .update({
            attendance_finalized_at: now,
            attendance_finalized_by: callerId,
            version: expectedVersion + 1,
          }).eq("id", existing!.id).eq("version", expectedVersion).select(
            operationSelect,
          ).maybeSingle();
        if (!updated) throw new OperationFailure(409, "stale_version");
        await audit(updated as Row, requestId, "attendance_finalized", {
          reason: text(payload.reason) || null,
        });
        return { operation_id: updated.id, operation: updated };
      });
    }

    if (action === "checklist") {
      if (!resolved.has("manage_event_checklist")) {
        throw new OperationFailure(403, "manage_event_checklist_required");
      }
      const itemId = uuid(payload.item_id);
      const expectedVersion = Number(payload.item_version);
      if (!itemId || !Number.isInteger(expectedVersion)) {
        throw new OperationFailure(400, "missing_checklist_item");
      }
      const overrideReason = text(payload.override_reason);
      return await withReceipt(requestId, text(existing.id), async () => {
        const now = new Date().toISOString();
        const patch = overrideReason
          ? {
            overridden_at: now,
            overridden_by: callerId,
            override_reason: overrideReason,
            version: expectedVersion + 1,
          }
          : {
            completed_at: payload.completed === false ? null : now,
            completed_by: payload.completed === false ? null : callerId,
            version: expectedVersion + 1,
          };
        const { data: updated } = await admin.from(
          "sd_event_operation_checklist_items",
        )
          .update(patch).eq("id", itemId).eq("event_operation_id", existing!.id)
          .eq("version", expectedVersion).select("*").maybeSingle();
        if (!updated) throw new OperationFailure(409, "stale_version");
        await audit(
          existing!,
          requestId,
          overrideReason ? "checklist_overridden" : "checklist_completed",
          {
            target_id: itemId,
            new_value: {
              completed_at: updated.completed_at,
              overridden_at: updated.overridden_at,
              version: updated.version,
            },
            reason: overrideReason || null,
          },
        );
        return { operation_id: existing!.id, checklist_item: updated };
      });
    }

    if (action === "note") {
      const noteType = text(payload.note_type);
      if (
        ![
          "team_coach_note",
          "internal_staff_note",
          "player_coach_note",
          "post_event_recap",
        ].includes(noteType)
      ) {
        throw new OperationFailure(400, "invalid_note_type");
      }
      const privatePlayer = noteType === "player_coach_note";
      const required = privatePlayer
        ? "add_private_player_notes"
        : "add_team_event_notes";
      if (!resolved.has(required)) {
        throw new OperationFailure(403, `${required}_required`);
      }
      const body = text(payload.body);
      if (!body) throw new OperationFailure(400, "missing_note_body");
      const visibility = text(payload.visibility) ||
        (privatePlayer ? "player" : "staff");
      if (!["staff", "team", "player"].includes(visibility)) {
        throw new OperationFailure(400, "invalid_note_visibility");
      }
      if (noteType === "internal_staff_note" && visibility !== "staff") {
        throw new OperationFailure(400, "private_note_visibility_required");
      }
      if (privatePlayer && visibility === "team") {
        throw new OperationFailure(400, "player_note_visibility_required");
      }
      const subject = privatePlayer ? uuid(payload.player_id) : null;
      if (privatePlayer && !subject) {
        throw new OperationFailure(400, "missing_player_id");
      }
      if (privatePlayer) {
        const { data: participant, error: participantError } = await admin.from(
          "sd_event_operation_participants",
        ).select("id").eq("event_operation_id", existing.id).eq(
          "user_id",
          subject,
        ).eq("participant_type", "player").maybeSingle();
        if (participantError) {
          throw new OperationFailure(500, "participant_lookup_failed");
        }
        if (!participant) {
          throw new OperationFailure(404, "participant_not_found");
        }
      }
      return await withReceipt(requestId, text(existing.id), async () => {
        const note = {
          id: requestId,
          event_operation_id: existing!.id,
          organization_id: organizationId,
          note_type: noteType,
          visibility,
          subject_player_id: subject,
          body,
          published_at: noteType === "post_event_recap" && visibility === "team"
            ? new Date().toISOString()
            : null,
          created_by: callerId,
          updated_by: callerId,
        };
        const { data: saved, error } = await admin.from(
          "sd_event_operation_notes",
        )
          .upsert(note, { onConflict: "id" }).select("*").single();
        if (error) throw new OperationFailure(500, "note_save_failed");
        const recap = noteType === "post_event_recap" && visibility === "team";
        await audit(
          existing!,
          requestId,
          recap ? "recap_published" : "note_created",
          {
            target_id: requestId,
            new_value: { note_type: noteType, visibility },
          },
        );
        if (recap) {
          await intent(existing!, requestId, "recap_published", "recap");
        }
        return { operation_id: existing!.id, note: saved };
      });
    }

    if (action === "reconcile_participants") {
      if (!resolved.has("manage_event_attendance")) {
        throw new OperationFailure(403, "manage_event_attendance_required");
      }
      const reason = text(payload.reason);
      if (!reason) {
        throw new OperationFailure(400, "reconciliation_reason_required");
      }
      return await withReceipt(requestId, text(existing.id), async () => {
        const { data: activePlayers } = await admin.from(
          "sd_player_team_memberships",
        )
          .select("player_id").eq("organization_id", organizationId).eq(
            "season_id",
            event.season_id,
          )
          .eq("team_id", event.team_id).eq("active", true).is("ended_at", null);
        const { data: snapshot } = await admin.from(
          "sd_event_operation_participants",
        )
          .select("user_id").eq("event_operation_id", existing!.id).eq(
            "participant_type",
            "player",
          );
        const prior = new Set(
          (snapshot ?? []).map((row: Row) => text(row.user_id)),
        );
        const additions = (activePlayers ?? []).map((row: Row) =>
          text(row.player_id)
        ).filter((id: string) => !prior.has(id));
        if (additions.length) {
          await admin.from("sd_event_operation_participants").insert(
            additions.map((userId: string) => ({
              event_operation_id: existing!.id,
              organization_id: organizationId,
              season_id: event.season_id,
              team_id: event.team_id,
              event_id: event.id,
              user_id: userId,
              participant_type: "player",
              expected: true,
            })),
          );
        }
        await audit(existing!, requestId, "participants_reconciled", {
          reason,
          details: { additions },
        });
        return { operation_id: existing!.id, additions };
      });
    }

    if (action === "audit_history") {
      if (!isAdmin) {
        throw new OperationFailure(403, "organization_admin_required");
      }
      const { data, error } = await admin.from("sd_event_operation_audit_logs")
        .select(
          "id,event_operation_id,actor_id,action,target_id,previous_value,new_value,reason,details,created_at",
        ).eq("event_operation_id", existing.id).order("created_at", {
          ascending: false,
        });
      if (error) throw new OperationFailure(500, "audit_history_failed");
      return ok({ operation: existing, audit: data ?? [] });
    }

    throw new OperationFailure(400, "unsupported_action");
  } catch (error) {
    const failure = error instanceof OperationFailure
      ? error
      : new OperationFailure(500, "event_operation_failed");
    return fail(failure.status, failure.code, failure.message);
  }
});
