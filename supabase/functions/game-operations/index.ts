import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import {
  type GameRow,
  sanitizeGamePayload,
} from "../_shared/game_operations.ts";

const env = (key: string) => (Deno.env.get(key) ?? "").trim();
const text = (value: unknown) => String(value ?? "").trim();
const record = (value: unknown): GameRow =>
  value && typeof value === "object" && !Array.isArray(value)
    ? value as GameRow
    : {};
const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const uuid = (value: unknown) =>
  uuidPattern.test(text(value)) ? text(value) : null;
const json = (status: number, body: GameRow) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json; charset=utf-8" },
  });
const ok = (body: GameRow) => json(200, { ok: true, ...body, error: null });
const fail = (status: number, code: string, message = code) =>
  json(status, { ok: false, error: { code, message } });

class GameFailure extends Error {
  constructor(public status: number, public code: string, message = code) {
    super(message);
  }
}

const consumerActions = new Set([
  "fetch_game_plan",
  "fetch_started_snapshot",
  "fetch_completion_snapshot",
]);
const readActions = new Set([
  ...consumerActions,
  "fetch_game_plan_history",
  "validate_game_plan",
  "fetch_rule_profile",
  "list_rule_profiles",
  "fetch_prior_game_plans",
  "list_game_plan_summaries",
]);
const capabilityByAction: Record<string, string> = {
  initialize_game_plan: "create_game_plan",
  duplicate_prior_game_plan: "create_game_plan",
  update_game_plan: "edit_game_plan",
  publish_game_plan: "publish_game_plan",
  archive_game_plan: "archive_game_plan",
  restore_game_plan: "archive_game_plan",
  delete_draft_game_plan: "archive_game_plan",
  create_rule_profile: "configure_game_rules",
  update_rule_profile: "configure_game_rules",
  duplicate_rule_profile: "configure_game_rules",
  archive_rule_profile: "configure_game_rules",
  apply_rule_profile: "edit_game_plan",
  add_batting_entry: "manage_batting_order",
  update_batting_entry: "manage_batting_order",
  remove_batting_entry: "manage_batting_order",
  reorder_batting_order: "manage_batting_order",
  initialize_standard_nine: "manage_batting_order",
  initialize_dh: "manage_batting_order",
  initialize_one_eh: "manage_batting_order",
  initialize_multiple_eh: "manage_batting_order",
  initialize_continuous_order: "manage_batting_order",
  initialize_bat_entire_roster: "manage_batting_order",
  clear_batting_order: "manage_batting_order",
  reconcile_batting_order: "manage_batting_order",
  update_eligibility: "manage_batting_order",
  set_starting_defense: "manage_defensive_plan",
  assign_defensive_position: "manage_defensive_plan",
  remove_defensive_assignment: "manage_defensive_plan",
  copy_defensive_inning: "manage_defensive_plan",
  apply_alignment_to_innings: "manage_defensive_plan",
  clear_defensive_inning: "manage_defensive_plan",
  reconcile_defensive_plan: "manage_defensive_plan",
  assign_starting_pitcher: "manage_pitcher_catcher_plan",
  add_relief_pitcher: "manage_pitcher_catcher_plan",
  reorder_pitchers: "manage_pitcher_catcher_plan",
  assign_starting_catcher: "manage_pitcher_catcher_plan",
  assign_backup_catcher: "manage_pitcher_catcher_plan",
  assign_pitcher_catcher_pair: "manage_pitcher_catcher_plan",
  update_pitcher_catcher_plan: "manage_pitcher_catcher_plan",
  remove_pitcher_catcher_plan: "manage_pitcher_catcher_plan",
  assign_game_staff: "manage_game_staff",
  update_game_staff: "manage_game_staff",
  remove_game_staff: "manage_game_staff",
  capture_started_game_snapshot: "modify_active_game_plan",
  apply_active_lineup_adjustment: "modify_active_game_plan",
  apply_active_defense_adjustment: "modify_active_game_plan",
  apply_active_pitcher_adjustment: "modify_active_game_plan",
  apply_active_eligibility_adjustment: "modify_active_game_plan",
  record_game_result: "record_game_result",
  add_game_recap: "complete_game_operation",
  capture_completion_snapshot: "complete_game_operation",
  complete_game_operation: "complete_game_operation",
  reopen_completed_game: "reopen_game_operation",
};

Deno.serve(async (req) => {
  if (req.method !== "POST") return fail(405, "method_not_allowed");
  let payload: GameRow;
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
  const action = text(payload.action);
  if (!action) return fail(400, "missing_action");

  try {
    const { data: membership, error: membershipError } = await admin.from(
      "sd_org_memberships",
    ).select("role,status").eq("org_id", organizationId).eq("user_id", callerId)
      .eq("status", "active").maybeSingle();
    if (membershipError) throw new GameFailure(500, "membership_lookup_failed");
    if (!membership) {
      throw new GameFailure(403, "organization_membership_required");
    }
    const role = text((membership as GameRow).role).toLowerCase();
    const eventId = uuid(payload.event_id);
    const teamIdInput = uuid(payload.team_id);
    let event: GameRow | null = null;
    if (eventId) {
      const eventResult = await admin.from("sd_team_events").select("*")
        .eq("id", eventId).eq("organization_id", organizationId)
        .eq("event_type", "game").maybeSingle();
      if (eventResult.error) throw new GameFailure(500, "event_lookup_failed");
      if (!eventResult.data) throw new GameFailure(404, "game_event_not_found");
      event = eventResult.data as GameRow;
    }
    const teamId = event ? text(event.team_id) : teamIdInput;
    if (!teamId) throw new GameFailure(400, "missing_team_id");
    const tournamentEventId = event
      ? uuid(record(event.metadata).tournament_event_id)
      : uuid(payload.tournament_event_id);
    const { data: resolved, error: capabilityError } = await admin.rpc(
      "sd_resolve_team_capabilities",
      {
        target_organization: organizationId,
        target_team: teamId,
        target_actor: callerId,
      },
    );
    if (capabilityError) {
      throw new GameFailure(500, "capability_resolution_failed");
    }
    const capabilities = new Set((resolved ?? []).map(String));
    const isConsumer = role === "player" || role === "parent";
    let playerId: string | null = null;
    if (isConsumer) {
      if (
        !consumerActions.has(action) || !event || event.visibility !== "team" ||
        event.status === "draft"
      ) {
        throw new GameFailure(404, "game_plan_not_found");
      }
      playerId = role === "player" ? callerId : uuid(payload.player_id);
      if (!playerId) throw new GameFailure(400, "missing_player_id");
      if (role === "parent") {
        const link = await admin.from("sd_parent_child_links").select(
          "child_id",
        )
          .eq("org_id", organizationId).eq("parent_id", callerId)
          .eq("child_id", playerId).maybeSingle();
        if (!link.data) throw new GameFailure(403, "parent_link_required");
      } else if (playerId !== callerId) {
        throw new GameFailure(403, "player_scope_required");
      }
      const activeTeam = await admin.from("sd_player_team_memberships").select(
        "id",
      )
        .eq("organization_id", organizationId).eq("team_id", teamId)
        .eq("player_id", playerId).eq("active", true).is("ended_at", null)
        .maybeSingle();
      if (!activeTeam.data) throw new GameFailure(403, "active_team_required");
    } else if (!capabilities.has("view_game_plan")) {
      throw new GameFailure(403, "view_game_plan_required");
    }

    async function loadPlan(includeArchived = false) {
      if (!eventId) throw new GameFailure(400, "missing_event_id");
      let query = admin.from("sd_game_plans").select("*")
        .eq("organization_id", organizationId).eq("event_id", eventId)
        .eq("is_primary", true);
      if (!includeArchived) query = query.is("archived_at", null);
      const result = await query.maybeSingle();
      if (result.error) throw new GameFailure(500, "game_plan_lookup_failed");
      return result.data as GameRow | null;
    }

    async function detail(plan: GameRow) {
      const planId = text(plan.id);
      const [
        eligibility,
        batting,
        defense,
        pitcherCatcher,
        staff,
        recaps,
        result,
        validation,
      ] = await Promise.all([
        admin.from("sd_game_plan_eligibility").select("*").eq(
          "game_plan_id",
          planId,
        ).order("created_at"),
        admin.from("sd_game_batting_entries").select("*").eq(
          "game_plan_id",
          planId,
        ).eq("active", true).order("batting_slot"),
        admin.from("sd_game_defensive_assignments").select("*").eq(
          "game_plan_id",
          planId,
        ).eq("active", true).order("inning_number").order("position_code"),
        admin.from("sd_game_pitcher_catcher_plans").select("*").eq(
          "game_plan_id",
          planId,
        ).is("archived_at", null).order("role_type").order("sequence_index"),
        admin.from("sd_game_staff_assignments").select("*").eq(
          "game_plan_id",
          planId,
        ).eq("active", true).order("responsibility_code"),
        admin.from("sd_game_recaps").select("*").eq("game_plan_id", planId)
          .order("created_at"),
        admin.from("sd_game_results").select("*").eq("game_plan_id", planId)
          .maybeSingle(),
        admin.rpc("sd_validate_game_plan", { p_plan_id: planId }),
      ]);
      const ruleProfile = plan.rule_profile_id
        ? await admin.from("sd_game_rule_profiles").select("*").eq(
          "id",
          plan.rule_profile_id,
        ).maybeSingle()
        : { data: null, error: null };
      const queryErrors = [
        eligibility,
        batting,
        defense,
        pitcherCatcher,
        staff,
        recaps,
        result,
        validation,
        ruleProfile,
      ]
        .map((query) => query.error).filter(Boolean);
      if (queryErrors.length) {
        throw new GameFailure(500, "game_plan_detail_failed");
      }
      return {
        plan,
        rule_profile: ruleProfile.data,
        eligibility: eligibility.data ?? [],
        batting_order: batting.data ?? [],
        defense: defense.data ?? [],
        pitcher_catcher: pitcherCatcher.data ?? [],
        staff: staff.data ?? [],
        recaps: recaps.data ?? [],
        result: result.data,
        validation: validation.data,
        capabilities: [...capabilities].sort(),
      };
    }

    if (action === "fetch_game_plan") {
      const plan = await loadPlan();
      if (!plan) {
        return ok({ plan: null, capabilities: [...capabilities].sort() });
      }
      const body = await detail(plan);
      return ok(
        isConsumer && playerId
          ? sanitizeGamePayload(body, playerId, role as "player" | "parent")
          : body,
      );
    }
    if (action === "validate_game_plan") {
      const plan = await loadPlan();
      if (!plan) throw new GameFailure(404, "game_plan_not_found");
      const result = await admin.rpc("sd_validate_game_plan", {
        p_plan_id: plan.id,
      });
      if (result.error) {
        throw new GameFailure(500, "game_plan_validation_failed");
      }
      return ok({
        validation: result.data,
        capabilities: [...capabilities].sort(),
      });
    }
    if (action === "fetch_game_plan_history") {
      const plan = await loadPlan(true);
      if (!plan) throw new GameFailure(404, "game_plan_not_found");
      const [snapshots, adjustments, audit] = await Promise.all([
        admin.from("sd_game_plan_snapshots").select("*").eq(
          "game_plan_id",
          plan.id,
        ).order("created_at", { ascending: false }),
        admin.from("sd_game_active_adjustments").select("*").eq(
          "game_plan_id",
          plan.id,
        ).order("created_at", { ascending: false }),
        admin.from("sd_game_plan_audit_logs").select("*").eq(
          "game_plan_id",
          plan.id,
        ).order("created_at", { ascending: false }),
      ]);
      if (snapshots.error || adjustments.error || audit.error) {
        throw new GameFailure(500, "game_plan_history_failed");
      }
      return ok({
        plan,
        snapshots: snapshots.data ?? [],
        adjustments: adjustments.data ?? [],
        audit: audit.data ?? [],
        capabilities: [...capabilities].sort(),
      });
    }
    if (
      action === "fetch_started_snapshot" ||
      action === "fetch_completion_snapshot"
    ) {
      const plan = await loadPlan(true);
      if (!plan) throw new GameFailure(404, "game_plan_not_found");
      const snapshotType = action === "fetch_started_snapshot"
        ? "started"
        : "completed";
      const snapshotResult = await admin.from("sd_game_plan_snapshots").select(
        "*",
      )
        .eq("game_plan_id", plan.id).eq("snapshot_type", snapshotType)
        .order("created_at", { ascending: false }).limit(1).maybeSingle();
      if (snapshotResult.error) {
        throw new GameFailure(500, "game_snapshot_lookup_failed");
      }
      if (!snapshotResult.data) {
        throw new GameFailure(404, "game_snapshot_not_found");
      }
      let snapshot = snapshotResult.data as GameRow;
      if (isConsumer && playerId) {
        snapshot = {
          ...snapshot,
          snapshot: sanitizeGamePayload(
            record(snapshot.snapshot),
            playerId,
            role as "player" | "parent",
          ),
        };
      }
      return ok({ snapshot, capabilities: [...capabilities].sort() });
    }
    if (action === "list_rule_profiles" || action === "fetch_rule_profile") {
      let query = admin.from("sd_game_rule_profiles").select("*")
        .eq("organization_id", organizationId).eq("active", true);
      if (action === "fetch_rule_profile" && uuid(payload.rule_profile_id)) {
        query = query.eq("id", uuid(payload.rule_profile_id)!);
      }
      const profileResult = await query.order("event_id", { nullsFirst: false })
        .order("tournament_event_id", { nullsFirst: false })
        .order("team_id", { nullsFirst: false }).order("season_id", {
          nullsFirst: false,
        });
      if (profileResult.error) {
        throw new GameFailure(500, "rule_profile_lookup_failed");
      }
      const scoped = (profileResult.data ?? []).filter((profile: GameRow) =>
        (!profile.season_id || profile.season_id === event?.season_id ||
          profile.season_id === payload.season_id) &&
        (!profile.team_id || profile.team_id === teamId) &&
        (!profile.tournament_event_id ||
          profile.tournament_event_id === tournamentEventId) &&
        (!profile.event_id || profile.event_id === eventId)
      );
      return ok(
        action === "fetch_rule_profile"
          ? { rule_profile: scoped[0] ?? null }
          : { rule_profiles: scoped },
      );
    }
    if (action === "fetch_prior_game_plans") {
      const result = await admin.from("sd_game_plans").select(
        "id,event_id,title,status,lineup_mode,published_version,updated_at",
      )
        .eq("organization_id", organizationId).eq("team_id", teamId)
        .neq("event_id", eventId ?? "00000000-0000-0000-0000-000000000000")
        .not("published_version", "is", null).order("updated_at", {
          ascending: false,
        }).limit(20);
      if (result.error) throw new GameFailure(500, "prior_game_plans_failed");
      return ok({ plans: result.data ?? [] });
    }
    if (action === "list_game_plan_summaries") {
      const seasonId = uuid(payload.season_id);
      let query = admin.from("sd_game_plans").select(
        "id,organization_id,season_id,team_id,event_id,title,status,lineup_mode,version,published_version,published_at,updated_at",
      )
        .eq("organization_id", organizationId).eq("team_id", teamId).is(
          "archived_at",
          null,
        );
      if (seasonId) query = query.eq("season_id", seasonId);
      const result = await query.order("updated_at", { ascending: false });
      if (result.error) {
        throw new GameFailure(500, "game_plan_summaries_failed");
      }
      return ok({
        plans: result.data ?? [],
        capabilities: [...capabilities].sort(),
      });
    }
    if (readActions.has(action)) {
      throw new GameFailure(400, "invalid_read_scope");
    }

    const required = capabilityByAction[action];
    if (!required) throw new GameFailure(400, "unsupported_game_action");
    if (!capabilities.has(required)) {
      throw new GameFailure(403, `${required}_required`);
    }
    if (!eventId || !event) throw new GameFailure(400, "missing_event_id");
    const requestId = uuid(payload.request_id);
    if (!requestId) throw new GameFailure(400, "missing_request_id");
    const data = record(payload.data);
    if (
      action === "initialize_game_plan" ||
      action === "duplicate_prior_game_plan"
    ) {
      const initialized = await admin.rpc("sd_apply_event_operation_mutation", {
        p_organization_id: organizationId,
        p_event_id: eventId,
        p_actor_id: callerId,
        p_action: "initialize",
        p_request_id: requestId,
        p_staff: true,
        p_payload: {},
      });
      if (
        initialized.error &&
        !String(initialized.error.message).includes("idempotency")
      ) {
        throw new GameFailure(409, controlledCode(initialized.error.message));
      }
    }
    const mutation = await admin.rpc("sd_apply_game_plan_mutation", {
      p_organization_id: organizationId,
      p_event_id: eventId,
      p_actor_id: callerId,
      p_action: action,
      p_request_id: requestId,
      p_payload: data,
    });
    if (mutation.error) {
      const code = controlledCode(mutation.error.message);
      throw new GameFailure(
        code.includes("stale") ? 409 : code.includes("not_found") ? 404 : 422,
        code,
      );
    }
    return ok({
      ...record(mutation.data),
      capabilities: [...capabilities].sort(),
    });
  } catch (error) {
    if (error instanceof GameFailure) {
      return fail(error.status, error.code, error.message);
    }
    return fail(500, "game_operations_failed");
  }
});

function controlledCode(message: string): string {
  const known = [
    "idempotency_mismatch",
    "mutation_in_progress",
    "game_event_not_found",
    "game_plan_not_found",
    "stale_version",
    "stale_or_locked_game_plan",
    "stale_or_missing_rule_profile",
    "stale_or_missing_batting_entry",
    "stale_or_missing_defensive_assignment",
    "stale_or_missing_pitcher_catcher_plan",
    "stale_or_missing_staff_assignment",
    "rule_profile_scope_mismatch",
    "exclusion_reason_required",
    "batting_order_locked",
    "active_adjustment_required",
    "game_plan_validation_failed",
    "published_game_plan_required",
    "event_operation_not_ready",
    "active_adjustment_reason_required",
    "active_game_plan_required",
    "result_correction_reason_required",
    "reopen_reason_required",
    "completed_game_required",
    "event_operation_reopen_required",
    "published_game_plan_delete_forbidden",
    "historical_game_plan_archive_forbidden",
    "authorized_team_staff_required",
    "authorized_prior_game_plan_required",
    "rule_profile_season_scope_mismatch",
    "rule_profile_team_scope_mismatch",
    "rule_profile_tournament_scope_mismatch",
    "rule_profile_event_scope_mismatch",
    "unsupported_game_action",
  ];
  return known.find((code) => message.includes(code)) ??
    "game_mutation_rejected";
}
