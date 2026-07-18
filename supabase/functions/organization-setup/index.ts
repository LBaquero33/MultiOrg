import {
  ApiFailure,
  fail,
  ok,
  organizationContext,
  record,
  text,
  uuid,
} from "../_shared/organization_api.ts";
import {
  canSkipSetupStep,
  cleanSetupString,
  isSetupStep,
  nextSetupStep,
  protectedSetupEntity,
  setupReadiness,
  type SetupStep,
  setupTestModeEligible,
} from "../_shared/organization_setup.ts";

const mutableActions = new Set([
  "start",
  "navigate",
  "save_basics",
  "save_season",
  "save_team",
  "save_people_draft",
  "save_registration",
  "save_facility",
  "save_communication",
  "create_first_event",
  "skip_step",
  "dismiss",
  "reopen",
  "complete",
  "preview_test_data_reset",
  "reset_progress",
  "reset_setup_test_data",
]);

type SetupContext = Awaited<ReturnType<typeof organizationContext>>;

async function setupCapabilities(ctx: SetupContext) {
  const { data, error } = await ctx.admin.rpc("sd_resolve_setup_capabilities", {
    target_organization: ctx.organizationId,
    target_actor: ctx.callerId,
  });
  if (error) throw new ApiFailure(500, "setup_capability_resolution_failed");
  return new Set<string>((data as unknown[] ?? []).map(String));
}

async function ensureSession(ctx: SetupContext, assisted: boolean) {
  const { data: existing, error: lookupError } = await ctx.admin
    .from("sd_organization_setup_sessions").select("*")
    .eq("organization_id", ctx.organizationId).maybeSingle();
  if (lookupError) throw new ApiFailure(500, "setup_session_lookup_failed");
  let session = existing;
  if (!session) {
    const { data, error } = await ctx.admin.from(
      "sd_organization_setup_sessions",
    )
      .insert({
        organization_id: ctx.organizationId,
        started_by: ctx.callerId,
        assisted_by: assisted ? ctx.callerId : null,
      }).select("*").single();
    if (error) throw new ApiFailure(500, "setup_session_create_failed");
    session = data;
  }
  const rows = [
    "basics",
    "season",
    "teams",
    "staff",
    "players_families",
    "registration_fees",
    "facilities",
    "communication",
    "first_baseball_action",
    "review_launch",
  ].map((step) => ({ organization_id: ctx.organizationId, step }));
  const { error: stepError } = await ctx.admin.from(
    "sd_organization_setup_steps",
  )
    .upsert(rows, {
      onConflict: "organization_id,step",
      ignoreDuplicates: true,
    });
  if (stepError) throw new ApiFailure(500, "setup_steps_create_failed");
  return session;
}

async function readSetup(ctx: SetupContext) {
  const { data: session, error: sessionError } = await ctx.admin
    .from("sd_organization_setup_sessions").select("*")
    .eq("organization_id", ctx.organizationId).maybeSingle();
  if (sessionError) throw new ApiFailure(500, "setup_session_lookup_failed");
  const [
    { data: steps },
    { data: drafts },
    { data: organization },
    { data: seasons },
    { data: teams },
    { data: readinessData, error: readinessError },
  ] = await Promise.all([
    ctx.admin.from("sd_organization_setup_steps").select("*")
      .eq("organization_id", ctx.organizationId).order("updated_at"),
    ctx.admin.from("sd_organization_setup_drafts").select("*")
      .eq("organization_id", ctx.organizationId),
    ctx.admin.from("sd_orgs").select(
      "id,name,status,organization_type,timezone,default_location,phone,website_host,support_email",
    )
      .eq("id", ctx.organizationId).single(),
    ctx.admin.from("sd_seasons").select(
      "id,organization_id,name,start_date,end_date,status,is_default",
    )
      .eq("organization_id", ctx.organizationId).order("created_at"),
    ctx.admin.from("sd_teams").select(
      "id,org_id,season_id,name,color_hex,description,is_active,sort_order",
    )
      .eq("org_id", ctx.organizationId).order("sort_order").order("name"),
    ctx.admin.rpc("sd_organization_setup_readiness", {
      p_organization_id: ctx.organizationId,
    }),
  ]);
  if (readinessError) throw new ApiFailure(500, "setup_readiness_failed");
  const readiness = setupReadiness(readinessData);
  return {
    session,
    steps: steps ?? [],
    drafts: drafts ?? [],
    organization,
    seasons: seasons ?? [],
    teams: teams ?? [],
    readiness,
  };
}

async function audit(
  ctx: SetupContext,
  action: string,
  requestId: string | null,
  step: string | null,
  details: Record<string, unknown> = {},
) {
  const { error } = await ctx.admin.from("sd_organization_setup_audit_logs")
    .insert({
      organization_id: ctx.organizationId,
      actor_id: ctx.callerId,
      assisted: ctx.isPlatformAdmin,
      action,
      step,
      request_id: requestId,
      details,
    });
  if (error) throw new ApiFailure(500, "setup_audit_failed");
}

async function markEntity(
  ctx: SetupContext,
  sessionId: string,
  entityType: string,
  entityId: string,
  setupTestRunId: string | null,
) {
  const { error } = await ctx.admin.from("sd_organization_setup_entities")
    .upsert({
      organization_id: ctx.organizationId,
      session_id: sessionId,
      entity_type: entityType,
      entity_id: entityId,
      setup_test_run_id: setupTestRunId,
      created_via_setup: true,
      setup_test_created: Boolean(setupTestRunId),
      created_by: ctx.callerId,
    }, { onConflict: "organization_id,entity_type,entity_id" });
  if (error) throw new ApiFailure(500, "setup_provenance_failed");
}

async function markStep(
  ctx: SetupContext,
  step: SetupStep,
  requestId: string,
  state = "complete",
) {
  const { error } = await ctx.admin.from("sd_organization_setup_steps").upsert({
    organization_id: ctx.organizationId,
    step,
    state,
    last_request_id: requestId,
    completed_by: state === "complete" || state === "skipped"
      ? ctx.callerId
      : null,
    completed_at: state === "complete" || state === "skipped"
      ? new Date().toISOString()
      : null,
    updated_at: new Date().toISOString(),
  }, { onConflict: "organization_id,step" });
  if (error) throw new ApiFailure(500, "setup_step_update_failed");
}

async function moveSession(
  ctx: SetupContext,
  values: Record<string, unknown>,
  expectedVersion?: number,
) {
  let query = ctx.admin.from("sd_organization_setup_sessions").update({
    ...values,
    version: expectedVersion == null ? undefined : expectedVersion + 1,
    updated_by: ctx.callerId,
    updated_at: new Date().toISOString(),
  }).eq("organization_id", ctx.organizationId);
  if (expectedVersion != null) query = query.eq("version", expectedVersion);
  const { data, error } = await query.select("*").maybeSingle();
  if (error) throw new ApiFailure(500, "setup_session_update_failed");
  if (!data) throw new ApiFailure(409, "stale_setup_version");
  return data;
}

async function mutationReplay(ctx: SetupContext, requestId: string) {
  const { data, error } = await ctx.admin.from(
    "sd_organization_setup_mutations",
  )
    .select("response").eq("organization_id", ctx.organizationId)
    .eq("request_id", requestId).maybeSingle();
  if (error) throw new ApiFailure(500, "setup_receipt_lookup_failed");
  return data?.response ?? null;
}

async function saveReceipt(
  ctx: SetupContext,
  requestId: string,
  action: string,
  response: Record<string, unknown>,
) {
  const { error } = await ctx.admin.from("sd_organization_setup_mutations")
    .insert({
      organization_id: ctx.organizationId,
      request_id: requestId,
      action,
      response,
      actor_id: ctx.callerId,
    });
  if (error) throw new ApiFailure(500, "setup_receipt_failed");
}

function testModeAllowed(ctx: SetupContext) {
  return setupTestModeEligible({
    enabled: Deno.env.get("HOME_PLATE_SETUP_TEST_MODE"),
    configuredOrganizationId: Deno.env.get(
      "HOME_PLATE_SETUP_TEST_ORGANIZATION_ID",
    ),
    requestedOrganizationId: ctx.organizationId,
    environment: Deno.env.get("HOME_PLATE_ENVIRONMENT"),
    isOrganizationAdmin: ctx.isAdmin,
    isPlatformAdmin: ctx.isPlatformAdmin,
  });
}

async function testResetPreview(
  ctx: SetupContext,
  setupTestRunId: string | null,
) {
  if (!testModeAllowed(ctx)) {
    throw new ApiFailure(404, "setup_test_mode_unavailable");
  }
  if (!setupTestRunId) {
    throw new ApiFailure(400, "setup_test_run_required");
  }
  const { data, error } = await ctx.admin.from("sd_organization_setup_entities")
    .select("entity_type,entity_id,setup_test_run_id,created_at")
    .eq("organization_id", ctx.organizationId).eq("setup_test_created", true)
    .eq("setup_test_run_id", setupTestRunId)
    .order("created_at");
  if (error) throw new ApiFailure(500, "setup_test_preview_failed");
  const candidates = (data ?? []).filter((item) =>
    !protectedSetupEntity(item.entity_type)
  );
  return {
    candidates,
    protected_history_preserved: true,
    full_organization_reset_available: false,
  };
}

async function resetSetupTestData(
  ctx: SetupContext,
  setupTestRunId: string | null,
) {
  const preview = await testResetPreview(ctx, setupTestRunId);
  const tableByType: Record<string, string> = {
    team_event: "sd_team_events",
    registration_offering: "sd_registration_offerings",
    coach_team_assignment: "sd_coach_team_assignments",
    player_team_membership: "sd_player_team_memberships",
    facility: "sd_facilities",
    communication_policy: "sd_communication_policies",
    team: "sd_teams",
    season: "sd_seasons",
  };
  const orderedTypes = Object.keys(tableByType);
  let deleted = 0;
  for (const type of orderedTypes) {
    const ids = preview.candidates.filter((item) => item.entity_type === type)
      .map((item) => item.entity_id);
    if (!ids.length) continue;
    const table = tableByType[type];
    const key = type === "communication_policy" ? "organization_id" : "id";
    const { error } = await ctx.admin.from(table).delete().in(key, ids);
    if (error) throw new ApiFailure(409, "setup_test_data_in_use");
    deleted += ids.length;
  }
  await ctx.admin.from("sd_organization_setup_entities").delete()
    .eq("organization_id", ctx.organizationId).eq("setup_test_created", true)
    .eq("setup_test_run_id", setupTestRunId!);
  return { deleted_count: deleted, protected_history_preserved: true };
}

Deno.serve(async (req) => {
  try {
    const payload = record(await req.json());
    const ctx = await organizationContext(req, payload, {
      allowPlatformAdmin: true,
    });
    const capabilities = await setupCapabilities(ctx);
    const action = text(payload.action) || "get";
    if (!capabilities.has("view_organization_setup")) {
      throw new ApiFailure(403, "setup_access_required");
    }
    if (
      mutableActions.has(action) &&
      !capabilities.has("manage_organization_setup")
    ) {
      throw new ApiFailure(403, "setup_management_required");
    }
    const session = await ensureSession(ctx, ctx.isPlatformAdmin);
    const requestId = mutableActions.has(action)
      ? uuid(payload.request_id)
      : null;
    if (mutableActions.has(action) && !requestId) {
      throw new ApiFailure(400, "missing_request_id");
    }
    if (requestId) {
      const replay = await mutationReplay(ctx, requestId);
      if (replay) return ok({ ...replay, replayed: true });
    }
    const expectedVersion = payload.expected_version == null
      ? undefined
      : Number(payload.expected_version);
    const setupTestRunId = testModeAllowed(ctx)
      ? uuid(payload.setup_test_run_id)
      : null;
    let result: Record<string, unknown> = {};

    if (action === "get") {
      result = await readSetup(ctx);
      result.test_mode = testModeAllowed(ctx);
      result.assisted = ctx.isPlatformAdmin;
      await audit(ctx, "fetch_setup", null, null, {
        environment: Deno.env.get("HOME_PLATE_ENVIRONMENT") ?? "unset",
      });
    } else if (action === "start" || action === "reopen") {
      await moveSession(ctx, {
        status: "in_progress",
        started_at: session.started_at ?? new Date().toISOString(),
        dismissed_at: null,
      }, expectedVersion);
    } else if (action === "navigate") {
      const step = text(payload.step);
      if (!isSetupStep(step)) throw new ApiFailure(400, "invalid_setup_step");
      await moveSession(
        ctx,
        { current_step: step, status: "in_progress" },
        expectedVersion,
      );
    } else if (action === "save_basics") {
      const basics = record(payload.basics);
      const name = cleanSetupString(basics.name, 160);
      const timezone = cleanSetupString(basics.timezone, 120);
      if (!name || !timezone) {
        throw new ApiFailure(422, "organization_name_and_timezone_required");
      }
      const { error } = await ctx.admin.from("sd_orgs").update({
        name,
        organization_type: cleanSetupString(basics.organization_type, 80) ||
          null,
        timezone,
        default_location: cleanSetupString(basics.default_location, 240) ||
          null,
        phone: cleanSetupString(basics.phone, 40) || null,
        website_host: cleanSetupString(basics.website_host, 200) || null,
        support_email: cleanSetupString(basics.support_email, 200) || null,
        updated_at: new Date().toISOString(),
      }).eq("id", ctx.organizationId);
      if (error) throw new ApiFailure(500, "organization_basics_save_failed");
      await markStep(ctx, "basics", requestId!);
      await moveSession(
        ctx,
        { current_step: "season", status: "in_progress" },
        expectedVersion,
      );
    } else if (action === "save_season") {
      const input = record(payload.season);
      const name = cleanSetupString(input.name, 120);
      if (!name) throw new ApiFailure(422, "season_name_required");
      const id = uuid(input.id);
      if (input.is_default !== false) {
        await ctx.admin.from("sd_seasons").update({ is_default: false })
          .eq("organization_id", ctx.organizationId).eq("is_default", true);
      }
      const values = {
        organization_id: ctx.organizationId,
        name,
        start_date: text(input.start_date) || null,
        end_date: text(input.end_date) || null,
        status: text(input.status) || "planning",
        is_default: input.is_default !== false,
        updated_by: ctx.callerId,
        created_by: ctx.callerId,
      };
      const query = id
        ? ctx.admin.from("sd_seasons").update(values).eq("id", id).eq(
          "organization_id",
          ctx.organizationId,
        )
        : ctx.admin.from("sd_seasons").insert(values);
      const { data, error } = await query.select("id").single();
      if (error) throw new ApiFailure(409, "season_save_failed");
      if (!id) {
        await markEntity(ctx, session.id, "season", data.id, setupTestRunId);
      }
      await markStep(ctx, "season", requestId!);
      await moveSession(
        ctx,
        { current_step: "teams", status: "in_progress" },
        expectedVersion,
      );
      result.entity_id = data.id;
    } else if (action === "save_team") {
      const input = record(payload.team);
      const name = cleanSetupString(input.name, 120);
      const seasonId = uuid(input.season_id);
      if (!name || !seasonId) {
        throw new ApiFailure(422, "team_name_and_season_required");
      }
      const { data: validSeason } = await ctx.admin.from("sd_seasons").select(
        "id",
      )
        .eq("id", seasonId).eq("organization_id", ctx.organizationId)
        .maybeSingle();
      if (!validSeason) throw new ApiFailure(422, "season_not_in_organization");
      const id = uuid(input.id);
      const values = {
        org_id: ctx.organizationId,
        season_id: seasonId,
        name,
        color_hex: cleanSetupString(input.color_hex, 16) || null,
        description: cleanSetupString(input.description, 500) || null,
        is_active: true,
        created_by: ctx.callerId,
      };
      const query = id
        ? ctx.admin.from("sd_teams").update(values).eq("id", id).eq(
          "org_id",
          ctx.organizationId,
        )
        : ctx.admin.from("sd_teams").insert(values);
      const { data, error } = await query.select("id").single();
      if (error) throw new ApiFailure(409, "team_save_failed");
      if (!id) {
        await markEntity(ctx, session.id, "team", data.id, setupTestRunId);
      }
      await markStep(ctx, "teams", requestId!);
      await moveSession(
        ctx,
        { current_step: "staff", status: "in_progress" },
        expectedVersion,
      );
      result.entity_id = data.id;
    } else if (action === "save_people_draft") {
      const step = text(payload.step);
      if (step !== "staff" && step !== "players_families") {
        throw new ApiFailure(400, "invalid_people_step");
      }
      const draft = record(payload.draft);
      const { error } = await ctx.admin.from("sd_organization_setup_drafts")
        .upsert({
          organization_id: ctx.organizationId,
          step,
          draft_key: text(payload.draft_key) || "default",
          payload: draft,
          updated_by: ctx.callerId,
          updated_at: new Date().toISOString(),
        }, { onConflict: "organization_id,step,draft_key" });
      if (error) throw new ApiFailure(500, "people_draft_save_failed");
      await markStep(ctx, step as SetupStep, requestId!, "complete");
      await moveSession(ctx, {
        current_step: nextSetupStep(step as SetupStep),
        status: "in_progress",
      }, expectedVersion);
    } else if (action === "save_registration") {
      const input = record(payload.registration);
      const seasonId = uuid(input.season_id);
      const name = cleanSetupString(input.name, 120);
      if (!seasonId || !name) {
        throw new ApiFailure(422, "registration_name_and_season_required");
      }
      const now = new Date();
      const closes = new Date(now.getTime() + 30 * 86400000);
      const { data, error } = await ctx.admin.from("sd_registration_offerings")
        .insert({
          organization_id: ctx.organizationId,
          season_id: seasonId,
          team_id: uuid(input.team_id),
          offering_type: text(input.offering_type) || "season",
          name,
          opens_at: text(input.opens_at) || now.toISOString(),
          closes_at: text(input.closes_at) || closes.toISOString(),
          fee_cents: Math.max(0, Number(input.fee_cents) || 0),
          deposit_cents: Math.max(0, Number(input.deposit_cents) || 0),
          state: "draft",
          visibility: "organization",
          created_by: ctx.callerId,
          updated_by: ctx.callerId,
        }).select("id").single();
      if (error) throw new ApiFailure(409, "registration_save_failed");
      await markEntity(
        ctx,
        session.id,
        "registration_offering",
        data.id,
        setupTestRunId,
      );
      await markStep(ctx, "registration_fees", requestId!);
      await moveSession(ctx, {
        current_step: "facilities",
        status: "in_progress",
      }, expectedVersion);
      result.entity_id = data.id;
    } else if (action === "save_facility") {
      const input = record(payload.facility);
      const name = cleanSetupString(input.name, 120);
      if (!name) throw new ApiFailure(422, "facility_name_required");
      const { data, error } = await ctx.admin.from("sd_facilities").insert({
        org_id: ctx.organizationId,
        name,
        is_active: true,
        resource_type: text(input.resource_type) || "field",
        capacity: Math.max(1, Number(input.capacity) || 1),
        color_hex: cleanSetupString(input.color_hex, 16) || null,
      }).select("id").single();
      if (error) throw new ApiFailure(409, "facility_save_failed");
      await markEntity(ctx, session.id, "facility", data.id, setupTestRunId);
      await markStep(ctx, "facilities", requestId!);
      await moveSession(ctx, {
        current_step: "communication",
        status: "in_progress",
      }, expectedVersion);
      result.entity_id = data.id;
    } else if (action === "save_communication") {
      const input = record(payload.communication);
      const { data: existingPolicy, error: policyLookupError } = await ctx.admin
        .from("sd_communication_policies").select("organization_id")
        .eq("organization_id", ctx.organizationId).maybeSingle();
      if (policyLookupError) {
        throw new ApiFailure(500, "communication_policy_lookup_failed");
      }
      const { error } = await ctx.admin.from("sd_communication_policies")
        .upsert({
          organization_id: ctx.organizationId,
          player_to_coach_allowed: input.player_to_coach_allowed !== false,
          parent_to_coach_allowed: input.parent_to_coach_allowed !== false,
          minor_parent_visibility_required:
            input.minor_parent_visibility_required !== false,
          updated_by: ctx.callerId,
        }, { onConflict: "organization_id" });
      if (error) throw new ApiFailure(500, "communication_policy_save_failed");
      if (!existingPolicy) {
        await markEntity(
          ctx,
          session.id,
          "communication_policy",
          ctx.organizationId,
          setupTestRunId,
        );
      }
      await markStep(ctx, "communication", requestId!);
      await moveSession(ctx, {
        current_step: "first_baseball_action",
        status: "in_progress",
      }, expectedVersion);
    } else if (action === "create_first_event") {
      const input = record(payload.event);
      const seasonId = uuid(input.season_id);
      const teamId = uuid(input.team_id);
      const start = new Date(text(input.start_at));
      const end = new Date(text(input.end_at));
      if (
        !seasonId || !teamId || !Number.isFinite(start.getTime()) ||
        !Number.isFinite(end.getTime()) || end <= start
      ) {
        throw new ApiFailure(422, "valid_event_scope_and_time_required");
      }
      const { data, error } = await ctx.admin.from("sd_team_events").insert({
        organization_id: ctx.organizationId,
        season_id: seasonId,
        team_id: teamId,
        event_type: text(input.event_type) || "practice",
        title: cleanSetupString(input.title, 160) || "First Practice",
        status: "draft",
        start_at: start.toISOString(),
        end_at: end.toISOString(),
        original_start_at: start.toISOString(),
        timezone: cleanSetupString(input.timezone, 120) || "UTC",
        location_name: cleanSetupString(input.location_name, 200) || null,
        created_by: ctx.callerId,
        updated_by: ctx.callerId,
      }).select("id").single();
      if (error) throw new ApiFailure(409, "first_event_save_failed");
      await markEntity(ctx, session.id, "team_event", data.id, setupTestRunId);
      await markStep(ctx, "first_baseball_action", requestId!);
      await moveSession(ctx, {
        current_step: "review_launch",
        status: "in_progress",
      }, expectedVersion);
      result.entity_id = data.id;
    } else if (action === "skip_step") {
      const step = text(payload.step);
      if (!isSetupStep(step) || !canSkipSetupStep(step)) {
        throw new ApiFailure(422, "required_step_cannot_be_skipped");
      }
      await markStep(ctx, step, requestId!, "skipped");
      await moveSession(ctx, {
        current_step: nextSetupStep(step),
        status: "in_progress",
      }, expectedVersion);
    } else if (action === "dismiss") {
      await moveSession(ctx, {
        status: "dismissed",
        dismissed_at: new Date().toISOString(),
      }, expectedVersion);
    } else if (action === "complete") {
      const current = await readSetup(ctx);
      if (!current.readiness.ready) {
        throw new ApiFailure(422, "setup_requirements_incomplete");
      }
      await markStep(ctx, "review_launch", requestId!);
      await moveSession(ctx, {
        status: "completed",
        current_step: "review_launch",
        completed_at: new Date().toISOString(),
      }, expectedVersion);
    } else if (action === "preview_test_data_reset") {
      result.preview = await testResetPreview(ctx, setupTestRunId);
    } else if (action === "reset_progress") {
      if (!testModeAllowed(ctx)) {
        throw new ApiFailure(404, "setup_test_mode_unavailable");
      }
      await ctx.admin.from("sd_organization_setup_steps").delete().eq(
        "organization_id",
        ctx.organizationId,
      );
      await ctx.admin.from("sd_organization_setup_drafts").delete().eq(
        "organization_id",
        ctx.organizationId,
      );
      await moveSession(ctx, {
        status: "not_started",
        current_step: "basics",
        started_at: null,
        dismissed_at: null,
        completed_at: null,
      }, expectedVersion);
      result.reset = { progress_only: true, business_data_changed: false };
    } else if (action === "reset_setup_test_data") {
      result.reset = await resetSetupTestData(ctx, setupTestRunId);
    } else {
      throw new ApiFailure(400, "unsupported_action");
    }

    if (action !== "get") {
      await audit(
        ctx,
        action,
        requestId,
        isSetupStep(payload.step) ? payload.step : null,
        { setup_test_run_id: setupTestRunId },
      );
      if (action !== "preview_test_data_reset") {
        result.setup = await readSetup(ctx);
      }
      if (requestId) await saveReceipt(ctx, requestId, action, result);
    }
    return ok(result);
  } catch (error) {
    if (error instanceof ApiFailure) return fail(error.status, error.code);
    console.error("organization_setup_failed", error);
    return fail(500, "organization_setup_failed");
  }
});
