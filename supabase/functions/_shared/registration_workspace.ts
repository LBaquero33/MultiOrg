import {
  ApiFailure,
  organizationContext,
  record,
  rpcFailure,
  text,
  uuid,
} from "./organization_api.ts";
import {
  mayUseRegistrationOffering,
  validateEvaluationValue,
} from "./connected_registration.ts";
import { signCheckInToken } from "./registration_public.ts";

type RegistrationContext = Awaited<ReturnType<typeof organizationContext>>;
type Row = Record<string, unknown>;

const DECISION_STATES = new Set([
  "unreviewed",
  "watchlist",
  "undecided",
  "offer_roster_spot",
  "decline",
]);
const STAFF_ROLES = new Set(["manager", "evaluator", "camp_staff"]);
const SESSION_TYPES = new Set(["group", "individual", "camp_day"]);
const OFFERING_TYPES = new Set(["tryout", "camp", "clinic"]);

function numberOrNull(value: unknown): number | null {
  if (value === null || value === undefined || text(value) === "") return null;
  const number = Number(value);
  return Number.isFinite(number) ? number : null;
}

function arrayOfRecords(value: unknown): Row[] {
  return Array.isArray(value) ? value.map(record) : [];
}

async function staffRoles(
  ctx: RegistrationContext,
  offeringId: string,
): Promise<Array<"manager" | "evaluator" | "camp_staff">> {
  if (ctx.isAdmin) return [];
  const { data, error } = await ctx.admin.from("sd_registration_offering_staff")
    .select("staff_role")
    .eq("organization_id", ctx.organizationId)
    .eq("offering_id", offeringId)
    .eq("user_id", ctx.callerId)
    .eq("is_active", true);
  if (error) throw new ApiFailure(500, "registration_staff_lookup_failed");
  return (data ?? []).map((row) => text(row.staff_role)).filter((role) =>
    STAFF_ROLES.has(role)
  ) as Array<"manager" | "evaluator" | "camp_staff">;
}

async function requireOfferingAccess(
  ctx: RegistrationContext,
  offeringId: string,
  operation: "manage" | "evaluate" | "camp",
) {
  const roles = await staffRoles(ctx, offeringId);
  if (!mayUseRegistrationOffering(ctx.role, roles, operation)) {
    throw new ApiFailure(403, `registration_${operation}_required`);
  }
  return roles;
}

async function defaultSeasonId(ctx: RegistrationContext): Promise<string> {
  const { data, error } = await ctx.admin.from("sd_seasons")
    .select("id")
    .eq("organization_id", ctx.organizationId)
    .order("is_default", { ascending: false })
    .order("created_at", { ascending: true })
    .limit(1)
    .maybeSingle();
  if (error) {
    throw new ApiFailure(500, "registration_scheduling_context_lookup_failed");
  }
  if (!data?.id) {
    throw new ApiFailure(409, "registration_scheduling_context_required");
  }
  return String(data.id);
}

async function listOperationalOfferings(ctx: RegistrationContext) {
  let visibleOfferingIds: string[] | null = null;
  if (!ctx.isAdmin) {
    const { data: assignments, error: assignmentError } = await ctx.admin
      .from("sd_registration_offering_staff")
      .select("offering_id")
      .eq("organization_id", ctx.organizationId)
      .eq("user_id", ctx.callerId)
      .eq("is_active", true);
    if (assignmentError) {
      throw new ApiFailure(500, "registration_staff_lookup_failed");
    }
    visibleOfferingIds = [
      ...new Set((assignments ?? []).map((row) => String(row.offering_id))),
    ];
    if (!visibleOfferingIds.length) return [];
  }
  let query = ctx.admin.from("sd_registration_offerings")
    .select(
      "*,sessions:sd_registration_sessions(id,name,session_type,start_at,end_at,status,location_id),staff:sd_registration_offering_staff(user_id,staff_role,is_active)",
    )
    .eq("organization_id", ctx.organizationId)
    .in("offering_type", ["tryout", "camp", "clinic"])
    .order("created_at", { ascending: false });
  if (visibleOfferingIds) query = query.in("id", visibleOfferingIds);
  const { data, error } = await query;
  if (error) throw new ApiFailure(500, "registration_offering_lookup_failed");
  return data ?? [];
}

async function getDashboard(ctx: RegistrationContext, offeringId: string) {
  const roles = await requireOfferingAccess(ctx, offeringId, "evaluate");
  const canManage = mayUseRegistrationOffering(ctx.role, roles, "manage");
  const [
    offering,
    participants,
    sessions,
    checkins,
    templates,
    evaluations,
    campConfig,
    staff,
    locations,
  ] = await Promise.all([
    ctx.admin.from("sd_registration_offerings").select("*")
      .eq("organization_id", ctx.organizationId).eq("id", offeringId)
      .maybeSingle(),
    ctx.admin.from("sd_registration_participants").select("*")
      .eq("organization_id", ctx.organizationId).eq("offering_id", offeringId)
      .order("participant_number"),
    ctx.admin.from("sd_registration_sessions")
      .select("*,resources:sd_registration_session_resources(resource_id)")
      .eq("organization_id", ctx.organizationId).eq("offering_id", offeringId)
      .order("start_at"),
    ctx.admin.from("sd_registration_checkins").select("*")
      .eq("organization_id", ctx.organizationId),
    ctx.admin.from("sd_registration_evaluation_templates")
      .select("*,criteria:sd_registration_evaluation_criteria(*)")
      .eq("organization_id", ctx.organizationId)
      .or(`offering_id.eq.${offeringId},offering_id.is.null`)
      .eq("is_active", true),
    ctx.admin.from("sd_registration_evaluations")
      .select("*,values:sd_registration_evaluation_values(*)")
      .eq("organization_id", ctx.organizationId).eq("offering_id", offeringId),
    ctx.admin.from("sd_camp_tracking_configs").select("*")
      .eq("organization_id", ctx.organizationId).eq("offering_id", offeringId)
      .maybeSingle(),
    ctx.admin.from("sd_registration_offering_staff").select(
      "user_id,staff_role,is_active",
    )
      .eq("organization_id", ctx.organizationId).eq("offering_id", offeringId),
    ctx.admin.from("sd_facility_locations").select(
      "id,name,address,timezone,is_active",
    )
      .eq("org_id", ctx.organizationId).eq("is_active", true).order(
        "sort_order",
      ),
  ]);
  const failed = [
    offering,
    participants,
    sessions,
    checkins,
    templates,
    evaluations,
    campConfig,
    staff,
    locations,
  ]
    .find((result) => result.error);
  if (failed?.error) {
    throw new ApiFailure(500, "registration_dashboard_lookup_failed");
  }
  if (!offering.data) {
    throw new ApiFailure(404, "registration_offering_not_found");
  }
  const sessionIds = new Set(
    (sessions.data ?? []).map((session) => String(session.id)),
  );
  return {
    offering: offering.data,
    participants: participants.data ?? [],
    sessions: sessions.data ?? [],
    checkins: (checkins.data ?? []).filter((checkin) =>
      sessionIds.has(String(checkin.session_id))
    ),
    evaluation_templates: templates.data ?? [],
    evaluations: evaluations.data ?? [],
    camp_config: campConfig.data,
    staff: staff.data ?? [],
    locations: locations.data ?? [],
    permissions: {
      can_manage: canManage,
      can_evaluate: true,
      can_release_decisions: canManage,
    },
  };
}

async function saveOffering(ctx: RegistrationContext, payload: Row) {
  const draft = record(payload.offering);
  const id = uuid(draft.id);
  if (id) await requireOfferingAccess(ctx, id, "manage");
  else if (!ctx.isAdmin) {
    throw new ApiFailure(403, "registration_manage_required");
  }
  const offeringType = text(draft.offering_type).toLowerCase();
  if (!OFFERING_TYPES.has(offeringType)) {
    throw new ApiFailure(400, "registration_offering_type_invalid");
  }
  const format = text(draft.format).toLowerCase() || "group";
  if (!SESSION_TYPES.has(format === "individual" ? "individual" : "group")) {
    throw new ApiFailure(400, "registration_offering_format_invalid");
  }
  const opensAt = text(draft.opens_at);
  const closesAt = text(draft.closes_at);
  if (!opensAt || !closesAt || new Date(closesAt) <= new Date(opensAt)) {
    throw new ApiFailure(400, "registration_window_invalid");
  }
  const seasonId = uuid(draft.season_id) ?? await defaultSeasonId(ctx);
  const values = {
    organization_id: ctx.organizationId,
    season_id: seasonId,
    team_id: uuid(draft.team_id),
    offering_type: offeringType,
    name: text(draft.name),
    description: text(draft.description) || null,
    opens_at: opensAt,
    closes_at: closesAt,
    capacity: numberOrNull(draft.capacity),
    waitlist_capacity: numberOrNull(draft.waitlist_capacity),
    age_guidance: text(draft.age_guidance) || null,
    graduation_year_guidance: text(draft.graduation_year_guidance) || null,
    eligibility_notes: text(draft.eligibility_notes) || null,
    fee_cents: Number(draft.fee_cents ?? 0),
    deposit_cents: Number(draft.deposit_cents ?? 0),
    refund_policy: text(draft.refund_policy) || null,
    state: text(draft.state) || "draft",
    visibility: text(draft.visibility) || "organization",
    format: format === "individual" ? "individual" : "group",
    response_contact_name: text(draft.response_contact_name) || null,
    response_contact_email: text(draft.response_contact_email) || null,
    location_id: uuid(draft.location_id),
    public_visible: draft.public_visible === true,
    player_number_start: Math.max(
      1,
      Math.min(9999, Number(draft.player_number_start ?? 1)),
    ),
    evaluations_enabled: draft.evaluations_enabled === true,
    decision_cta: record(draft.decision_cta),
    roster_needs: record(draft.roster_needs),
    updated_by: ctx.callerId,
  };
  const result = id
    ? await ctx.admin.from("sd_registration_offerings").update({
      ...values,
      version: Number(draft.version ?? 1) + 1,
    }).eq("organization_id", ctx.organizationId).eq("id", id)
      .eq("version", Number(draft.version ?? 1)).select().single()
    : await ctx.admin.from("sd_registration_offerings").insert({
      ...values,
      created_by: ctx.callerId,
    }).select().single();
  if (result.error) {
    throw new ApiFailure(409, "registration_offering_save_failed");
  }
  if (offeringType === "camp" && !id) {
    await ctx.admin.from("sd_camp_tracking_configs").insert({
      offering_id: result.data.id,
      organization_id: ctx.organizationId,
      testing_enabled: true,
      final_evaluation_enabled: true,
      updated_by: ctx.callerId,
    });
  }
  return result.data;
}

async function saveSession(ctx: RegistrationContext, payload: Row) {
  const draft = record(payload.session);
  const offeringId = uuid(draft.offering_id);
  if (!offeringId) throw new ApiFailure(400, "registration_offering_required");
  await requireOfferingAccess(ctx, offeringId, "manage");
  const id = uuid(draft.id);
  const sessionType = text(draft.session_type) || "group";
  if (!SESSION_TYPES.has(sessionType)) {
    throw new ApiFailure(400, "registration_session_type_invalid");
  }
  const values = {
    organization_id: ctx.organizationId,
    offering_id: offeringId,
    name: text(draft.name),
    session_type: sessionType,
    start_at: text(draft.start_at),
    end_at: text(draft.end_at),
    location_id: uuid(draft.location_id),
    capacity: numberOrNull(draft.capacity),
    checkin_opens_at: text(draft.checkin_opens_at) || null,
    checkin_closes_at: text(draft.checkin_closes_at) || null,
    status: text(draft.status) || "scheduled",
    notes: text(draft.notes) || null,
    updated_by: ctx.callerId,
  };
  if (
    !values.name || !values.start_at || !values.end_at ||
    new Date(values.end_at) <= new Date(values.start_at)
  ) {
    throw new ApiFailure(400, "registration_session_invalid");
  }
  const response = id
    ? await ctx.admin.from("sd_registration_sessions").update(values)
      .eq("organization_id", ctx.organizationId).eq("id", id).select().single()
    : await ctx.admin.from("sd_registration_sessions").insert({
      ...values,
      created_by: ctx.callerId,
    }).select().single();
  if (response.error) {
    throw new ApiFailure(409, "registration_session_save_failed");
  }
  const sessionId = String(response.data.id);
  const resourceIds = Array.isArray(draft.resource_ids)
    ? [...new Set(draft.resource_ids.map(uuid).filter(Boolean))] as string[]
    : [];
  if (resourceIds.length) {
    const { data: resources, error: resourceError } = await ctx.admin.from(
      "sd_facilities",
    )
      .select("id,location_id").eq("org_id", ctx.organizationId).in(
        "id",
        resourceIds,
      );
    if (resourceError || (resources ?? []).length !== resourceIds.length) {
      throw new ApiFailure(409, "registration_session_resource_scope_invalid");
    }
    const reservations = (resources ?? []).map((resource) => ({
      org_id: ctx.organizationId,
      location_id: resource.location_id ?? values.location_id,
      resource_id: resource.id,
      source_kind: "registration_session",
      source_id: sessionId,
      start_at: values.start_at,
      end_at: values.end_at,
      status: values.status === "cancelled" ? "cancelled" : "confirmed",
      created_by: ctx.callerId,
    }));
    if (reservations.some((reservation) => !reservation.location_id)) {
      throw new ApiFailure(409, "registration_session_location_required");
    }
    const { error: reservationError } = await ctx.admin.from(
      "sd_resource_reservations",
    )
      .upsert(reservations, {
        onConflict: "source_kind,source_id,resource_id",
      });
    if (reservationError) {
      throw new ApiFailure(409, "registration_session_resource_conflict");
    }
    await ctx.admin.from("sd_registration_session_resources").upsert(
      resourceIds.map((resourceId) => ({
        session_id: sessionId,
        resource_id: resourceId,
      })),
      { onConflict: "session_id,resource_id" },
    );
  }
  const resourceFilter = resourceIds.length
    ? `(${resourceIds.join(",")})`
    : null;
  let staleReservations = ctx.admin.from("sd_resource_reservations").delete()
    .eq("source_kind", "registration_session").eq("source_id", sessionId);
  let staleResources = ctx.admin.from("sd_registration_session_resources")
    .delete()
    .eq("session_id", sessionId);
  if (resourceFilter) {
    staleReservations = staleReservations.not(
      "resource_id",
      "in",
      resourceFilter,
    );
    staleResources = staleResources.not("resource_id", "in", resourceFilter);
  }
  await Promise.all([staleReservations, staleResources]);
  return response.data;
}

async function saveEvaluationTemplate(ctx: RegistrationContext, payload: Row) {
  const draft = record(payload.template);
  const offeringId = uuid(draft.offering_id);
  if (!offeringId) throw new ApiFailure(400, "registration_offering_required");
  await requireOfferingAccess(ctx, offeringId, "manage");
  const criteria = arrayOfRecords(draft.criteria);
  if (!criteria.length) {
    throw new ApiFailure(400, "evaluation_criteria_required");
  }
  const id = uuid(draft.id);
  const templateResult = id
    ? await ctx.admin.from("sd_registration_evaluation_templates").update({
      name: text(draft.name),
      is_active: draft.is_active !== false,
      updated_by: ctx.callerId,
    }).eq("organization_id", ctx.organizationId).eq("offering_id", offeringId)
      .eq("id", id).select().single()
    : await ctx.admin.from("sd_registration_evaluation_templates").insert({
      organization_id: ctx.organizationId,
      offering_id: offeringId,
      name: text(draft.name),
      created_by: ctx.callerId,
      updated_by: ctx.callerId,
    }).select().single();
  if (templateResult.error) {
    throw new ApiFailure(409, "evaluation_template_save_failed");
  }
  const templateId = String(templateResult.data.id);
  const allowedInputTypes = new Set([
    "letter_grade",
    "twenty_eighty",
    "one_hundred",
    "comment_only",
  ]);
  const rows = criteria.map((criterion, index) => {
    const inputType = text(criterion.input_type);
    if (!allowedInputTypes.has(inputType)) {
      throw new ApiFailure(400, "evaluation_input_type_invalid");
    }
    return {
      template_id: templateId,
      label: text(criterion.label),
      input_type: inputType,
      help_text: text(criterion.help_text) || null,
      sort_order: index,
    };
  });
  if (id) {
    await ctx.admin.from("sd_registration_evaluation_criteria").delete().eq(
      "template_id",
      templateId,
    );
  }
  const { error: criteriaError } = await ctx.admin.from(
    "sd_registration_evaluation_criteria",
  ).insert(rows);
  if (criteriaError) {
    throw new ApiFailure(409, "evaluation_criteria_save_failed");
  }
  return templateResult.data;
}

async function saveEvaluation(ctx: RegistrationContext, payload: Row) {
  const offeringId = uuid(payload.offering_id);
  const participantId = uuid(payload.participant_id);
  const templateId = uuid(payload.template_id);
  if (!offeringId || !participantId || !templateId) {
    throw new ApiFailure(400, "evaluation_context_required");
  }
  await requireOfferingAccess(ctx, offeringId, "evaluate");
  const { data: criteria, error: criteriaError } = await ctx.admin
    .from("sd_registration_evaluation_criteria").select("id,input_type")
    .eq("template_id", templateId);
  if (criteriaError || !criteria?.length) {
    throw new ApiFailure(404, "evaluation_template_not_found");
  }
  const submittedValues = new Map(
    arrayOfRecords(payload.values).map((
      value,
    ) => [text(value.criterion_id), value]),
  );
  const sessionId = uuid(payload.session_id);
  let existingQuery = ctx.admin.from("sd_registration_evaluations")
    .select("id").eq("organization_id", ctx.organizationId)
    .eq("offering_id", offeringId).eq("participant_id", participantId)
    .eq("template_id", templateId).eq("evaluator_user_id", ctx.callerId);
  existingQuery = sessionId
    ? existingQuery.eq("session_id", sessionId)
    : existingQuery.is("session_id", null);
  const { data: existing } = await existingQuery.maybeSingle();
  const evaluationValues = {
    organization_id: ctx.organizationId,
    offering_id: offeringId,
    participant_id: participantId,
    session_id: sessionId,
    template_id: templateId,
    evaluator_user_id: ctx.callerId,
    private_comments: text(payload.private_comments) || null,
    submitted_at: payload.submitted === false ? null : new Date().toISOString(),
  };
  const evaluation = existing?.id
    ? await ctx.admin.from("sd_registration_evaluations").update(
      evaluationValues,
    )
      .eq("id", existing.id).select().single()
    : await ctx.admin.from("sd_registration_evaluations").insert(
      evaluationValues,
    ).select().single();
  if (evaluation.error) throw new ApiFailure(409, "evaluation_save_failed");
  const rows = criteria.map((criterion) => {
    const submitted = submittedValues.get(String(criterion.id)) ?? {};
    let normalized;
    try {
      normalized = validateEvaluationValue(
        text(criterion.input_type) as
          | "letter_grade"
          | "twenty_eighty"
          | "one_hundred"
          | "comment_only",
        submitted.value,
      );
    } catch (error) {
      throw new ApiFailure(
        400,
        error instanceof Error ? error.message : "evaluation_value_invalid",
      );
    }
    return {
      evaluation_id: evaluation.data.id,
      criterion_id: criterion.id,
      value_text: normalized.valueText,
      value_number: normalized.valueNumber,
      comment: text(submitted.comment) || null,
    };
  });
  await ctx.admin.from("sd_registration_evaluation_values").delete()
    .eq("evaluation_id", evaluation.data.id);
  const { error: valueError } = await ctx.admin.from(
    "sd_registration_evaluation_values",
  ).insert(rows);
  if (valueError) throw new ApiFailure(409, "evaluation_values_save_failed");
  return evaluation.data;
}

async function sendQueuedDecisionEmails(
  ctx: RegistrationContext,
  releaseId: string,
) {
  const apiKey = text(Deno.env.get("RESEND_API_KEY"));
  const from = text(Deno.env.get("HOME_PLATE_DECISION_FROM_EMAIL"));
  if (!apiKey || !from) return { configured: false, sent: 0, failed: 0 };
  const { data: release, error: releaseError } = await ctx.admin
    .from("sd_registration_decision_releases")
    .select(
      "message,decision_cta,offering:sd_registration_offerings(name,response_contact_name,response_contact_email)",
    )
    .eq("id", releaseId).single();
  const { data: recipients, error: recipientError } = await ctx.admin
    .from("sd_registration_decision_recipients")
    .select(
      "participant_id,decision_state,recipient_email,participant:sd_registration_participants(display_name)",
    )
    .eq("release_id", releaseId).eq("delivery_status", "queued");
  if (releaseError || recipientError) {
    throw new ApiFailure(500, "decision_delivery_lookup_failed");
  }
  let sent = 0;
  let failed = 0;
  const offering = record(release.offering);
  for (const row of recipients ?? []) {
    const participant = record(row.participant);
    const offered = row.decision_state === "offer_roster_spot";
    const subject = `${text(offering.name) || "Tryout"}: ${
      offered ? "Roster spot offer" : "Decision update"
    }`;
    const body = [
      `Hello ${text(participant.display_name) || "player family"},`,
      offered
        ? `You have been offered a roster spot following ${
          text(offering.name) || "the tryout"
        }.`
        : `Thank you for participating in ${
          text(offering.name) || "the tryout"
        }. We are not able to offer a roster spot at this time.`,
      text(release.message),
      text(offering.response_contact_email)
        ? `Questions: ${text(offering.response_contact_name) || "Coach"} at ${
          text(offering.response_contact_email)
        }.`
        : "",
    ].filter(Boolean).join("\n\n");
    try {
      const response = await fetch("https://api.resend.com/emails", {
        method: "POST",
        headers: {
          authorization: `Bearer ${apiKey}`,
          "content-type": "application/json",
        },
        body: JSON.stringify({
          from,
          to: [row.recipient_email],
          subject,
          text: body,
        }),
      });
      const responseBody = record(await response.json().catch(() => ({})));
      if (!response.ok) throw new Error("decision_email_provider_rejected");
      await ctx.admin.from("sd_registration_decision_recipients").update({
        delivery_status: "sent",
        provider_message_id: text(responseBody.id) || null,
        sent_at: new Date().toISOString(),
        error_code: null,
      }).eq("release_id", releaseId).eq("participant_id", row.participant_id);
      sent += 1;
    } catch {
      await ctx.admin.from("sd_registration_decision_recipients").update({
        delivery_status: "failed",
        error_code: "decision_email_delivery_failed",
      }).eq("release_id", releaseId).eq("participant_id", row.participant_id);
      failed += 1;
    }
  }
  return { configured: true, sent, failed };
}

export async function handleConnectedRegistrationAction(
  ctx: RegistrationContext,
  payload: Row,
  action: string,
): Promise<Row | null> {
  if (action === "list_offerings") {
    return { offerings: await listOperationalOfferings(ctx) };
  }
  if (action === "get_offering_dashboard") {
    const offeringId = uuid(payload.offering_id);
    if (!offeringId) {
      throw new ApiFailure(400, "registration_offering_required");
    }
    return { dashboard: await getDashboard(ctx, offeringId) };
  }
  if (action === "save_offering") {
    return { offering: await saveOffering(ctx, payload) };
  }
  if (action === "save_session") {
    return { session: await saveSession(ctx, payload) };
  }
  if (action === "save_offering_staff") {
    const offeringId = uuid(payload.offering_id);
    if (!offeringId) {
      throw new ApiFailure(400, "registration_offering_required");
    }
    await requireOfferingAccess(ctx, offeringId, "manage");
    const assignments = arrayOfRecords(payload.assignments).map(
      (assignment) => {
        const userId = uuid(assignment.user_id);
        const staffRole = text(assignment.staff_role).toLowerCase();
        if (!userId || !STAFF_ROLES.has(staffRole)) {
          throw new ApiFailure(400, "registration_staff_assignment_invalid");
        }
        return {
          organization_id: ctx.organizationId,
          offering_id: offeringId,
          user_id: userId,
          staff_role: staffRole,
          is_active: assignment.is_active !== false,
          created_by: ctx.callerId,
        };
      },
    );
    const { data: memberships, error: membershipError } = assignments.length
      ? await ctx.admin.from("sd_org_memberships").select("user_id")
        .eq("org_id", ctx.organizationId).eq("status", "active")
        .in("user_id", assignments.map((assignment) => assignment.user_id))
      : { data: [], error: null };
    if (
      membershipError ||
      (memberships ?? []).length !==
        new Set(assignments.map((assignment) => assignment.user_id)).size
    ) {
      throw new ApiFailure(409, "registration_staff_membership_required");
    }
    await ctx.admin.from("sd_registration_offering_staff").delete()
      .eq("organization_id", ctx.organizationId).eq("offering_id", offeringId);
    if (!assignments.length) return { assignments: [] };
    const { data, error } = await ctx.admin.from(
      "sd_registration_offering_staff",
    )
      .insert(assignments).select("user_id,staff_role,is_active");
    if (error) {
      throw new ApiFailure(409, "registration_staff_assignment_failed");
    }
    return { assignments: data ?? [] };
  }
  if (action === "list_participants") {
    const offeringId = uuid(payload.offering_id);
    if (!offeringId) {
      throw new ApiFailure(400, "registration_offering_required");
    }
    const dashboard = await getDashboard(ctx, offeringId);
    return { participants: dashboard.participants };
  }
  if (action === "check_in_participant") {
    const { data, error } = await ctx.admin.rpc(
      "sd_staff_check_in_registration_participant",
      {
        p_organization_id: ctx.organizationId,
        p_actor_id: ctx.callerId,
        p_session_id: uuid(payload.session_id),
        p_participant_id: uuid(payload.participant_id),
        p_request_id: uuid(payload.request_id),
        p_status: text(payload.status) || "present",
        p_notes: text(payload.notes) || null,
      },
    );
    if (error) rpcFailure(error, "registration_checkin_failed");
    return { checkin: data };
  }
  if (action === "save_evaluation_template") {
    return { template: await saveEvaluationTemplate(ctx, payload) };
  }
  if (action === "save_evaluation") {
    return { evaluation: await saveEvaluation(ctx, payload) };
  }
  if (action === "set_decision") {
    const participantId = uuid(payload.participant_id);
    const offeringId = uuid(payload.offering_id);
    const decision = text(payload.decision_state).toLowerCase();
    if (!participantId || !offeringId || !DECISION_STATES.has(decision)) {
      throw new ApiFailure(400, "registration_decision_invalid");
    }
    await requireOfferingAccess(ctx, offeringId, "manage");
    const { data, error } = await ctx.admin.from("sd_registration_participants")
      .update({
        decision_state: decision,
        staff_comments: text(payload.staff_comments) || null,
        decision_released_at: null,
        version: Number(payload.expected_version) + 1,
      }).eq("organization_id", ctx.organizationId).eq("offering_id", offeringId)
      .eq("id", participantId).eq("version", Number(payload.expected_version))
      .select().single();
    if (error) throw new ApiFailure(409, "registration_decision_save_failed");
    return { participant: data };
  }
  if (action === "release_decisions") {
    const offeringId = uuid(payload.offering_id);
    if (!offeringId) {
      throw new ApiFailure(400, "registration_offering_required");
    }
    await requireOfferingAccess(ctx, offeringId, "manage");
    const participantIds = Array.isArray(payload.participant_ids)
      ? payload.participant_ids.map(uuid).filter(Boolean)
      : [];
    const { data, error } = await ctx.admin.rpc(
      "sd_release_registration_decisions",
      {
        p_organization_id: ctx.organizationId,
        p_actor_id: ctx.callerId,
        p_offering_id: offeringId,
        p_participant_ids: participantIds,
        p_release_all: payload.release_all === true,
        p_request_id: uuid(payload.request_id),
        p_message: text(payload.message) || null,
        p_decision_cta: record(payload.decision_cta),
      },
    );
    if (error) rpcFailure(error, "registration_decision_release_failed");
    const result = record(data);
    const delivery = await sendQueuedDecisionEmails(
      ctx,
      text(result.release_id),
    );
    return { release: result, delivery };
  }
  if (action === "generate_signin_pdf") {
    const offeringId = uuid(payload.offering_id);
    const sessionId = uuid(payload.session_id);
    if (!offeringId || !sessionId) {
      throw new ApiFailure(400, "registration_session_required");
    }
    const dashboard = await getDashboard(ctx, offeringId);
    const session = (dashboard.sessions as Row[]).find((row) =>
      String(row.id) === sessionId
    );
    if (!session) throw new ApiFailure(404, "registration_session_not_found");
    const checkins = new Map(
      (dashboard.checkins as Row[]).map((
        row,
      ) => [String(row.participant_id), row]),
    );
    return {
      sign_in_sheet: {
        offering: { id: dashboard.offering.id, name: dashboard.offering.name },
        session,
        participants: (dashboard.participants as Row[]).map((participant) => ({
          id: participant.id,
          participant_number: participant.participant_number,
          display_name: participant.display_name,
          age_group: participant.age_group,
          graduation_year: participant.graduation_year,
          positions: participant.positions,
          payment_status: participant.payment_status,
          waiver_status: participant.waiver_status,
          checked_in: checkins.has(String(participant.id)),
        })),
      },
    };
  }
  if (action === "create_checkin_link") {
    const offeringId = uuid(payload.offering_id);
    const sessionId = uuid(payload.session_id);
    if (!offeringId || !sessionId) {
      throw new ApiFailure(400, "registration_session_required");
    }
    await requireOfferingAccess(ctx, offeringId, "evaluate");
    const { data: session, error } = await ctx.admin.from(
      "sd_registration_sessions",
    )
      .select("id,end_at,checkin_closes_at").eq(
        "organization_id",
        ctx.organizationId,
      )
      .eq("offering_id", offeringId).eq("id", sessionId).maybeSingle();
    if (error || !session) {
      throw new ApiFailure(404, "registration_session_not_found");
    }
    const secret = text(Deno.env.get("REGISTRATION_CHECKIN_SIGNING_SECRET"));
    if (secret.length < 24) {
      throw new ApiFailure(500, "registration_checkin_secret_required");
    }
    const requestedExpiration = new Date(
      text(session.checkin_closes_at) || text(session.end_at),
    ).valueOf() + 3_600_000;
    const expiresAt = Math.floor(
      Math.min(
        requestedExpiration,
        Date.now() + 7 * 86_400_000,
      ) / 1000,
    );
    const token = await signCheckInToken(secret, sessionId, expiresAt);
    const base = text(Deno.env.get("HOME_PLATE_PUBLIC_BASE_URL")) ||
      "https://homeplateapps.com";
    return {
      checkin_link: `${base.replace(/\/$/, "")}/check-in?token=${
        encodeURIComponent(token)
      }`,
      expires_at: new Date(expiresAt * 1000).toISOString(),
    };
  }
  if (action === "get_prospect_history") {
    const prospectId = uuid(payload.prospect_id);
    if (!prospectId) {
      throw new ApiFailure(400, "registration_prospect_required");
    }
    const { data: participant, error: participantError } = await ctx.admin
      .from("sd_registration_participants").select("offering_id")
      .eq("organization_id", ctx.organizationId).eq("prospect_id", prospectId)
      .limit(1).maybeSingle();
    if (participantError || !participant) {
      throw new ApiFailure(404, "registration_prospect_not_found");
    }
    await requireOfferingAccess(
      ctx,
      String(participant.offering_id),
      "evaluate",
    );
    const { data, error } = await ctx.admin.from("sd_registration_participants")
      .select(
        "*,offering:sd_registration_offerings(id,name,offering_type),evaluations:sd_registration_evaluations(*,values:sd_registration_evaluation_values(*))",
      )
      .eq("organization_id", ctx.organizationId).eq("prospect_id", prospectId)
      .order("created_at", { ascending: false });
    if (error) {
      throw new ApiFailure(500, "registration_prospect_history_failed");
    }
    return { history: data ?? [] };
  }
  if (action === "save_camp_tracking_config") {
    const offeringId = uuid(payload.offering_id);
    if (!offeringId) {
      throw new ApiFailure(400, "registration_offering_required");
    }
    await requireOfferingAccess(ctx, offeringId, "manage");
    const config = record(payload.config);
    const delivery = text(config.final_evaluation_delivery) === "email_family"
      ? "email_family"
      : "internal";
    const { data, error } = await ctx.admin.from("sd_camp_tracking_configs")
      .upsert({
        offering_id: offeringId,
        organization_id: ctx.organizationId,
        testing_enabled: config.testing_enabled !== false,
        final_evaluation_enabled: config.final_evaluation_enabled !== false,
        final_evaluation_delivery: delivery,
        daily_attendance_enabled: config.daily_attendance_enabled === true,
        daily_notes_enabled: config.daily_notes_enabled === true,
        media_enabled: config.media_enabled === true,
        updated_by: ctx.callerId,
        updated_at: new Date().toISOString(),
      }, { onConflict: "offering_id" }).select().single();
    if (error) throw new ApiFailure(409, "camp_tracking_config_save_failed");
    return { config: data };
  }
  return null;
}
