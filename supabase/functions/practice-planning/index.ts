import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import {
  type Row,
  sanitizePracticePayload,
} from "../_shared/practice_planning.ts";

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
const json = (status: number, body: Row) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json; charset=utf-8" },
  });
const ok = (body: Row) => json(200, { ok: true, ...body, error: null });
const fail = (status: number, code: string, message = code) =>
  json(status, { ok: false, error: { code, message } });

class PlanningFailure extends Error {
  constructor(public status: number, public code: string, message = code) {
    super(message);
  }
}

const readActions = new Set([
  "fetch_plan",
  "fetch_plan_history",
  "fetch_template",
  "list_templates",
  "list_prior_practices",
  "validate_plan",
  "fetch_started_snapshot",
  "fetch_completion_snapshot",
  "list_plan_summaries",
]);
const consumerActions = new Set([
  "fetch_plan",
  "fetch_started_snapshot",
  "fetch_completion_snapshot",
]);
const capabilityByAction: Record<string, string> = {
  initialize_blank_plan: "create_practice_plan",
  initialize_from_template: "create_practice_plan",
  duplicate_prior_plan: "create_practice_plan",
  update_plan: "edit_practice_plan",
  add_block: "edit_practice_plan",
  update_block: "edit_practice_plan",
  remove_block: "edit_practice_plan",
  reorder_blocks: "edit_practice_plan",
  create_parallel_station_group: "edit_practice_plan",
  add_station: "edit_practice_plan",
  update_station: "edit_practice_plan",
  remove_station: "edit_practice_plan",
  update_location_assignment: "edit_practice_plan",
  create_group: "assign_practice_groups",
  update_group: "assign_practice_groups",
  archive_group: "assign_practice_groups",
  assign_group_to_block: "assign_practice_groups",
  assign_player: "assign_practice_players",
  unassign_player: "assign_practice_players",
  assign_player_to_station: "assign_practice_players",
  reconcile_roster: "assign_practice_players",
  assign_coach: "assign_practice_coaches",
  unassign_coach: "assign_practice_coaches",
  assign_coach_to_station: "assign_practice_coaches",
  add_equipment_requirement: "manage_practice_equipment",
  update_equipment_requirement: "manage_practice_equipment",
  remove_equipment_requirement: "manage_practice_equipment",
  publish_plan: "publish_practice_plan",
  republish_plan: "publish_practice_plan",
  archive_plan: "archive_practice_plan",
  restore_plan: "archive_practice_plan",
  delete_draft_plan: "archive_practice_plan",
  create_template: "manage_practice_templates",
  update_template: "manage_practice_templates",
  duplicate_template: "manage_practice_templates",
  archive_template: "manage_practice_templates",
  restore_template: "manage_practice_templates",
  save_plan_as_template: "manage_practice_templates",
  capture_started_snapshot: "modify_active_practice_plan",
  start_block: "execute_practice_blocks",
  complete_block: "execute_practice_blocks",
  skip_block: "execute_practice_blocks",
  reopen_block: "execute_practice_blocks",
  adjust_active_block: "modify_active_practice_plan",
  add_active_block: "modify_active_practice_plan",
  capture_completion_snapshot: "complete_practice_plan",
  complete_practice_plan: "complete_practice_plan",
  reopen_completed_practice: "reopen_practice_plan",
};
const rpcAction: Record<string, string> = {
  create_parallel_station_group: "add_block",
  update_location_assignment: "update_block",
};

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
  ).select("role,status").eq("org_id", organizationId).eq("user_id", callerId)
    .eq("status", "active").maybeSingle();
  if (membershipError) return fail(500, "membership_lookup_failed");
  if (!membership) return fail(403, "organization_membership_required");
  const role = text((membership as Row).role).toLowerCase();
  const action = text(payload.action);

  try {
    const eventId = uuid(payload.event_id);
    const teamIdInput = uuid(payload.team_id);
    let event: Row | null = null;
    if (eventId) {
      const result = await admin.from("sd_team_events").select("*").eq(
        "id",
        eventId,
      ).eq("organization_id", organizationId).eq("event_type", "practice")
        .maybeSingle();
      if (result.error) throw new PlanningFailure(500, "event_lookup_failed");
      if (!result.data) {
        throw new PlanningFailure(404, "practice_event_not_found");
      }
      event = result.data as Row;
    }
    const teamId = event ? text(event.team_id) : teamIdInput;
    if (!teamId) throw new PlanningFailure(400, "missing_team_id");

    const { data: capabilityData, error: capabilityError } = await admin.rpc(
      "sd_resolve_team_capabilities",
      {
        target_organization: organizationId,
        target_team: teamId,
        target_actor: callerId,
      },
    );
    if (capabilityError) {
      throw new PlanningFailure(500, "capability_resolution_failed");
    }
    const capabilities = new Set((capabilityData ?? []).map(String));
    const isConsumer = role === "player" || role === "parent";
    let playerId: string | null = null;
    if (isConsumer) {
      if (
        !consumerActions.has(action) || !event || event.visibility !== "team" ||
        event.status === "draft"
      ) throw new PlanningFailure(404, "plan_not_found");
      playerId = role === "player" ? callerId : uuid(payload.player_id);
      if (!playerId) throw new PlanningFailure(400, "missing_player_id");
      if (role === "parent") {
        const link = await admin.from("sd_parent_child_links").select(
          "child_id",
        ).eq("org_id", organizationId).eq("parent_id", callerId).eq(
          "child_id",
          playerId,
        ).maybeSingle();
        if (!link.data) throw new PlanningFailure(403, "parent_link_required");
      } else if (playerId !== callerId) {
        throw new PlanningFailure(403, "player_scope_required");
      }
      const activeTeam = await admin.from("sd_player_team_memberships").select(
        "id",
      ).eq("organization_id", organizationId).eq("team_id", teamId).eq(
        "player_id",
        playerId,
      ).eq("active", true).is("ended_at", null).maybeSingle();
      if (!activeTeam.data) {
        throw new PlanningFailure(403, "active_team_required");
      }
    } else if (!capabilities.has("view_practice_plan")) {
      throw new PlanningFailure(403, "view_practice_plan_required");
    }

    async function loadPlan() {
      if (!eventId) throw new PlanningFailure(400, "missing_event_id");
      const result = await admin.from("sd_practice_plans").select("*").eq(
        "organization_id",
        organizationId,
      ).eq("event_id", eventId).eq("is_primary", true).is("archived_at", null)
        .maybeSingle();
      if (result.error) throw new PlanningFailure(500, "plan_lookup_failed");
      return result.data as Row | null;
    }
    async function detail(plan: Row) {
      const [blocks, groups, assignments, equipment, executions, validation] =
        await Promise.all([
          admin.from("sd_practice_plan_blocks").select("*").eq(
            "practice_plan_id",
            plan.id,
          ).is("archived_at", null).order("sequence_index"),
          admin.from("sd_practice_plan_groups").select("*").eq(
            "practice_plan_id",
            plan.id,
          ).eq("active", true).order("sort_order"),
          admin.from("sd_practice_plan_assignments").select("*").eq(
            "practice_plan_id",
            plan.id,
          ),
          admin.from("sd_practice_plan_equipment").select("*").eq(
            "practice_plan_id",
            plan.id,
          ),
          admin.from("sd_practice_block_executions").select("*").eq(
            "practice_plan_id",
            plan.id,
          ).order("sequence_index"),
          admin.rpc("sd_validate_practice_plan", { target_plan: plan.id }),
        ]);
      if (
        blocks.error || groups.error || assignments.error || equipment.error ||
        executions.error || validation.error
      ) throw new PlanningFailure(500, "plan_detail_failed");
      const output = {
        plan,
        blocks: blocks.data ?? [],
        groups: groups.data ?? [],
        assignments: assignments.data ?? [],
        equipment: equipment.data ?? [],
        executions: executions.data ?? [],
        validation: validation.data,
      };
      return isConsumer
        ? sanitizePracticePayload(output, playerId ?? undefined)
        : output;
    }

    if (action === "fetch_plan") {
      const plan = await loadPlan();
      if (!plan) {
        return ok({
          plan: null,
          blocks: [],
          groups: [],
          assignments: [],
          equipment: [],
          executions: [],
          validation: null,
        });
      }
      return ok(await detail(plan));
    }
    if (action === "list_plan_summaries") {
      if (!capabilities.has("view_practice_plan")) {
        throw new PlanningFailure(403, "view_practice_plan_required");
      }
      let query = admin.from("sd_practice_plans").select(
        "id,organization_id,season_id,team_id,event_id,title,status,version,published_version,published_at,updated_at",
      ).eq("organization_id", organizationId).eq("team_id", teamId).is(
        "archived_at",
        null,
      );
      if (uuid(payload.season_id)) {
        query = query.eq("season_id", uuid(payload.season_id)!);
      }
      const result = await query.order("updated_at", { ascending: false });
      if (result.error) throw new PlanningFailure(500, "plan_list_failed");
      return ok({ plans: result.data ?? [] });
    }
    if (action === "validate_plan") {
      const plan = await loadPlan();
      if (!plan) throw new PlanningFailure(404, "plan_not_found");
      const result = await admin.rpc("sd_validate_practice_plan", {
        target_plan: plan.id,
      });
      if (result.error) {
        throw new PlanningFailure(500, "plan_validation_failed");
      }
      return ok({ plan, validation: result.data });
    }
    if (
      action === "fetch_plan_history" || action === "fetch_started_snapshot" ||
      action === "fetch_completion_snapshot"
    ) {
      const plan = await loadPlan();
      if (!plan) throw new PlanningFailure(404, "plan_not_found");
      let query = admin.from("sd_practice_plan_snapshots").select("*").eq(
        "practice_plan_id",
        plan.id,
      );
      if (action === "fetch_started_snapshot") {
        query = query.eq("snapshot_type", "started");
      }
      if (action === "fetch_completion_snapshot") {
        query = query.eq("snapshot_type", "completed");
      }
      const result = await query.order("created_at", { ascending: false });
      if (result.error) throw new PlanningFailure(500, "history_lookup_failed");
      const snapshots = isConsumer
        ? (result.data ?? []).map((row: Row) => ({
          ...row,
          snapshot: sanitizePracticePayload(
            record(row.snapshot),
            playerId ?? undefined,
          ),
        }))
        : result.data ?? [];
      return ok({ plan, snapshots });
    }
    if (action === "list_templates") {
      if (!capabilities.has("view_practice_plan")) {
        throw new PlanningFailure(403, "view_practice_plan_required");
      }
      let query = admin.from("sd_practice_plan_templates").select("*")
        .eq("organization_id", organizationId).or(
          `team_id.is.null,team_id.eq.${teamId}`,
        );
      if (payload.include_archived !== true) query = query.eq("active", true);
      const result = await query.order("name");
      if (result.error) throw new PlanningFailure(500, "template_list_failed");
      return ok({ templates: result.data ?? [] });
    }
    if (action === "fetch_template") {
      const templateId = uuid(payload.template_id);
      if (!templateId) throw new PlanningFailure(400, "missing_template_id");
      const result = await admin.from("sd_practice_plan_templates").select("*")
        .eq("id", templateId).eq("organization_id", organizationId).or(
          `team_id.is.null,team_id.eq.${teamId}`,
        ).maybeSingle();
      if (!result.data) throw new PlanningFailure(404, "template_not_found");
      return ok({ template: result.data });
    }
    if (action === "list_prior_practices") {
      const result = await admin.from("sd_practice_plans").select(
        "id,event_id,title,status,objectives,updated_at",
      ).eq("organization_id", organizationId).eq("team_id", teamId).neq(
        "event_id",
        eventId ?? "00000000-0000-0000-0000-000000000000",
      ).in("status", ["draft", "ready", "published", "completed"]).order(
        "updated_at",
        {
          ascending: false,
        },
      ).limit(30);
      if (result.error) {
        throw new PlanningFailure(500, "prior_practice_list_failed");
      }
      return ok({ plans: result.data ?? [] });
    }
    if (readActions.has(action)) {
      throw new PlanningFailure(400, "unsupported_read_action");
    }

    const requiredCapability = capabilityByAction[action];
    if (!requiredCapability) {
      throw new PlanningFailure(400, "unsupported_action");
    }
    if (isConsumer || !capabilities.has(requiredCapability)) {
      throw new PlanningFailure(403, `${requiredCapability}_required`);
    }
    if (!eventId) throw new PlanningFailure(400, "missing_event_id");
    const requestId = uuid(payload.request_id);
    if (!requestId) throw new PlanningFailure(400, "missing_request_id");
    const mutationPayload = { ...record(payload.data) };
    if (action === "duplicate_template") {
      const templateId = uuid(mutationPayload.template_id);
      const source = await admin.from("sd_practice_plan_templates").select(
        "snapshot,objectives",
      ).eq("id", templateId).eq("organization_id", organizationId)
        .maybeSingle();
      if (!source.data) throw new PlanningFailure(404, "template_not_found");
      mutationPayload.snapshot = source.data.snapshot;
      mutationPayload.objectives = source.data.objectives;
    }
    const { data, error } = await admin.rpc("sd_apply_practice_plan_mutation", {
      p_organization_id: organizationId,
      p_event_id: eventId,
      p_actor_id: callerId,
      p_action: rpcAction[action] ?? action,
      p_request_id: requestId,
      p_payload: mutationPayload,
    });
    if (error) {
      const diagnostic = [error.message, error.details, error.hint].filter(
        Boolean,
      ).join(" ");
      const known = [
        "idempotency_mismatch",
        "mutation_in_progress",
        "practice_event_not_found",
        "plan_not_found",
        "primary_plan_exists",
        "template_not_found",
        "source_plan_not_found",
        "stale_version",
        "plan_validation_failed",
        "block_not_found",
        "stale_or_missing_block",
        "invalid_duration",
        "invalid_active_adjustment",
        "incomplete_block_order",
        "cross_team_player",
        "cross_team_coach",
        "adjustment_reason_required",
        "published_plan_required",
        "event_operation_not_ready",
        "execution_not_found",
        "sequential_block_already_active",
        "active_blocks_remaining",
        "attendance_review_required",
        "reopen_reason_required",
        "event_operation_reopen_required",
        "published_plan_delete_forbidden",
        "unsupported_action",
      ].find((code) => diagnostic.includes(code));
      const code = known ?? "practice_plan_mutation_failed";
      const conflict = [
        "idempotency_mismatch",
        "mutation_in_progress",
        "primary_plan_exists",
        "stale_version",
        "stale_or_missing_block",
        "sequential_block_already_active",
      ].includes(code);
      throw new PlanningFailure(
        conflict ? 409 : code.endsWith("_not_found") ? 404 : 400,
        code,
      );
    }
    return ok(record(data));
  } catch (error) {
    const failure = error instanceof PlanningFailure
      ? error
      : new PlanningFailure(500, "practice_planning_failed");
    return fail(failure.status, failure.code, failure.message);
  }
});
