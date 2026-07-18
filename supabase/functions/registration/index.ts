import {
  ApiFailure,
  fail,
  ok,
  organizationContext,
  record,
  requireCapability,
  rpcFailure,
  text,
  uuid,
} from "../_shared/organization_api.ts";
import {
  mayTransitionSeason,
  registrationIsOpen,
  sanitizeRegistration,
} from "../_shared/organization_operations.ts";

Deno.serve(async (req) => {
  try {
    const payload = record(await req.json());
    const ctx = await organizationContext(req, payload);
    const action = text(payload.action);
    if (action === "offerings") {
      const query = ctx.admin.from("sd_registration_offerings").select(
        "*,requirements:sd_registration_offering_requirements(*,template:sd_registration_requirement_templates(*))",
      ).eq("organization_id", ctx.organizationId).order("opens_at");
      const { data, error } = await query;
      if (error) throw new ApiFailure(500, "offering_lookup_failed");
      return ok({
        offerings: (data ?? []).filter((row) =>
          ctx.isAdmin || row.visibility !== "staff_only"
        ).map((row) => ({
          ...row,
          accepting_submissions: registrationIsOpen(row),
        })),
      });
    }
    if (action === "applications") {
      let linkedIds: string[] = [];
      let query = ctx.admin.from("sd_registration_applications").select(
        "*,requirements:sd_registration_requirement_responses(*),waitlist:sd_registration_waitlist(*)",
      ).eq("organization_id", ctx.organizationId).order("created_at", {
        ascending: false,
      });
      if (!ctx.isAdmin) {
        const { data: links, error: linkError } = await ctx.admin.from(
          "sd_parent_child_links",
        ).select("child_id").eq("org_id", ctx.organizationId).eq(
          "parent_id",
          ctx.callerId,
        );
        if (linkError) throw new ApiFailure(500, "parent_link_lookup_failed");
        linkedIds = (links ?? []).map((link) => String(link.child_id));
        const linkedFilter = linkedIds.length
          ? `,player_user_id.in.(${linkedIds.join(",")})`
          : "";
        query = query.or(
          `applicant_user_id.eq.${ctx.callerId},player_user_id.eq.${ctx.callerId},guardian_user_id.eq.${ctx.callerId}${linkedFilter}`,
        );
      }
      const { data, error } = await query.limit(200);
      if (error) throw new ApiFailure(500, "registration_lookup_failed");
      return ok({
        applications: (data ?? []).map((row) => {
          const authorizedParty = linkedIds.includes(String(row.player_user_id))
            ? String(row.player_user_id)
            : ctx.callerId;
          return sanitizeRegistration(row, ctx.role, authorizedParty);
        }),
      });
    }
    if (action === "save_draft") {
      if (
        !ctx.capabilities.has("submit_registration") &&
        !ctx.capabilities.has("manage_child_registration") &&
        !ctx.capabilities.has("manage_registration_offerings")
      ) throw new ApiFailure(403, "submit_registration_required");
      const draft = record(payload.application);
      const id = uuid(draft.id);
      const playerId = uuid(draft.player_user_id);
      const prospectivePlayer = record(draft.prospective_player);
      if (!playerId && !text(prospectivePlayer.display_name)) {
        throw new ApiFailure(400, "player_or_prospective_player_required");
      }
      if (playerId && playerId !== ctx.callerId && !ctx.isAdmin) {
        const { data: link } = await ctx.admin.from("sd_parent_child_links")
          .select("child_id").eq("org_id", ctx.organizationId).eq(
            "parent_id",
            ctx.callerId,
          ).eq("child_id", playerId).maybeSingle();
        if (!link) throw new ApiFailure(403, "parent_child_link_required");
      }
      const values = {
        organization_id: ctx.organizationId,
        season_id: uuid(draft.season_id),
        offering_id: uuid(draft.offering_id),
        applicant_user_id: ctx.callerId,
        player_user_id: playerId,
        guardian_user_id: playerId && playerId !== ctx.callerId
          ? ctx.callerId
          : null,
        team_preference_id: uuid(draft.team_preference_id),
        answers: record(draft.answers),
        sensitive_answers: record(draft.sensitive_answers),
        prospective_player: prospectivePlayer,
        consent_metadata: record(draft.consent_metadata),
        payment_responsible_user_id: uuid(draft.payment_responsible_user_id) ??
          ctx.callerId,
        jersey_number_request: text(draft.jersey_number_request) || null,
        position_preference: text(draft.position_preference) || null,
      };
      const response = id
        ? await ctx.admin.from("sd_registration_applications").update(values)
          .eq("id", id).eq("organization_id", ctx.organizationId).eq(
            "state",
            "draft",
          ).select().single()
        : await ctx.admin.from("sd_registration_applications").insert(values)
          .select().single();
      if (response.error) throw new ApiFailure(409, "draft_save_failed");
      return ok({ application: response.data });
    }
    if (action === "save_requirement") {
      const applicationId = uuid(payload.application_id);
      const templateId = uuid(payload.requirement_template_id);
      if (!applicationId || !templateId) {
        throw new ApiFailure(400, "missing_requirement_context");
      }
      const { data: application } = await ctx.admin.from(
        "sd_registration_applications",
      ).select("applicant_user_id,player_user_id,guardian_user_id,state").eq(
        "id",
        applicationId,
      ).eq("organization_id", ctx.organizationId).maybeSingle();
      if (
        !application ||
        (![
          application.applicant_user_id,
          application.player_user_id,
          application.guardian_user_id,
        ].includes(ctx.callerId) && !ctx.isAdmin)
      ) throw new ApiFailure(403, "registration_party_required");
      if (!["draft", "action_required"].includes(String(application.state))) {
        throw new ApiFailure(409, "registration_requirements_locked");
      }
      const { data: template } = await ctx.admin.from(
        "sd_registration_requirement_templates",
      ).select("version,requirement_type").eq("id", templateId).eq(
        "organization_id",
        ctx.organizationId,
      ).eq("active", true).maybeSingle();
      if (!template) throw new ApiFailure(404, "requirement_not_found");
      const consent = record(payload.consent_metadata);
      const accepted = payload.accepted === true;
      if (accepted && (!text(consent.captured_at) || !text(consent.method))) {
        throw new ApiFailure(400, "consent_metadata_required");
      }
      const documentPath = text(payload.document_path) || null;
      if (
        documentPath &&
        !documentPath.startsWith(`${ctx.organizationId}/${applicationId}/`)
      ) throw new ApiFailure(403, "document_scope_required");
      const { data, error } = await ctx.admin.from(
        "sd_registration_requirement_responses",
      ).upsert({
        organization_id: ctx.organizationId,
        application_id: applicationId,
        requirement_template_id: templateId,
        required_version: template.version,
        accepted_version: accepted ? template.version : null,
        response: record(payload.response),
        document_path: documentPath,
        status: accepted ? "accepted" : "in_progress",
        accepted_by: accepted ? ctx.callerId : null,
        accepted_at: accepted ? new Date().toISOString() : null,
        consent_metadata: consent,
      }, { onConflict: "application_id,requirement_template_id" }).select()
        .single();
      if (error) throw new ApiFailure(409, "requirement_save_failed");
      return ok({ requirement: data });
    }
    if (action === "link_player") {
      requireCapability(ctx.capabilities, "assign_registered_player");
      const applicationId = uuid(payload.application_id);
      const playerId = uuid(payload.player_id);
      if (!applicationId || !playerId) {
        throw new ApiFailure(400, "missing_player_link_context");
      }
      const { data: membership } = await ctx.admin.from("sd_org_memberships")
        .select("role,status").eq("org_id", ctx.organizationId).eq(
          "user_id",
          playerId,
        ).eq("status", "active").eq("role", "player").maybeSingle();
      if (!membership) {
        throw new ApiFailure(409, "active_organization_player_required");
      }
      const { data, error } = await ctx.admin.from(
        "sd_registration_applications",
      ).update({
        player_user_id: playerId,
        version: Number(payload.expected_version) + 1,
      }).eq("id", applicationId).eq("organization_id", ctx.organizationId).eq(
        "version",
        Number(payload.expected_version),
      ).is("player_user_id", null).select().single();
      if (error) throw new ApiFailure(409, "player_link_failed");
      return ok({ application: data });
    }
    if (action === "create_offering" || action === "update_offering") {
      requireCapability(ctx.capabilities, "manage_registration_offerings");
      const offering = record(payload.offering);
      const seasonId = uuid(offering.season_id);
      const { data: season } = await ctx.admin.from("sd_seasons").select(
        "status",
      ).eq("id", seasonId).eq("organization_id", ctx.organizationId)
        .maybeSingle();
      if (
        !season || !["planning", "registration_open"].includes(season.status)
      ) {
        throw new ApiFailure(409, "season_structure_locked");
      }
      const values = {
        organization_id: ctx.organizationId,
        season_id: seasonId,
        team_id: uuid(offering.team_id),
        offering_type: text(offering.offering_type),
        name: text(offering.name),
        description: text(offering.description) || null,
        opens_at: text(offering.opens_at),
        closes_at: text(offering.closes_at),
        capacity: offering.capacity == null ? null : Number(offering.capacity),
        waitlist_capacity: offering.waitlist_capacity == null
          ? null
          : Number(offering.waitlist_capacity),
        age_guidance: text(offering.age_guidance) || null,
        graduation_year_guidance: text(offering.graduation_year_guidance) ||
          null,
        eligibility_notes: text(offering.eligibility_notes) || null,
        fee_cents: Number(offering.fee_cents ?? 0),
        deposit_cents: Number(offering.deposit_cents ?? 0),
        installment_configuration: record(offering.installment_configuration),
        refund_policy: text(offering.refund_policy) || null,
        custom_questions: Array.isArray(offering.custom_questions)
          ? offering.custom_questions
          : [],
        state: text(offering.state) || "draft",
        visibility: text(offering.visibility) || "organization",
        auto_assign_team: offering.auto_assign_team === true,
        updated_by: ctx.callerId,
      };
      const response = action === "create_offering"
        ? await ctx.admin.from("sd_registration_offerings").insert({
          ...values,
          created_by: ctx.callerId,
        }).select().single()
        : await ctx.admin.from("sd_registration_offerings").update({
          ...values,
          version: Number(payload.expected_version) + 1,
        }).eq("id", uuid(offering.id)).eq("organization_id", ctx.organizationId)
          .eq("version", Number(payload.expected_version)).select().single();
      if (response.error) throw new ApiFailure(409, "offering_save_failed");
      return ok({ offering: response.data });
    }
    if (action === "create_requirement_template") {
      requireCapability(ctx.capabilities, "manage_requirements");
      const requirement = record(payload.requirement);
      const { data, error } = await ctx.admin.from(
        "sd_registration_requirement_templates",
      ).insert({
        organization_id: ctx.organizationId,
        season_id: uuid(requirement.season_id),
        name: text(requirement.name),
        requirement_type: text(requirement.requirement_type),
        version: Number(requirement.version ?? 1),
        content: record(requirement.content),
        expires_after_days: requirement.expires_after_days == null
          ? null
          : Number(requirement.expires_after_days),
        active: true,
        created_by: ctx.callerId,
        updated_by: ctx.callerId,
      }).select().single();
      if (error) throw new ApiFailure(409, "requirement_create_failed");
      return ok({ requirement: data });
    }
    if (action === "transition_season") {
      requireCapability(ctx.capabilities, "manage_season_lifecycle");
      if (
        !mayTransitionSeason(
          text(payload.expected_status),
          text(payload.to_status),
        )
      ) throw new ApiFailure(409, "invalid_season_transition");
      const { data, error } = await ctx.admin.rpc("sd_transition_season", {
        p_organization_id: ctx.organizationId,
        p_actor_id: ctx.callerId,
        p_season_id: uuid(payload.season_id),
        p_to: text(payload.to_status),
        p_expected_status: text(payload.expected_status),
        p_request_id: uuid(payload.request_id),
        p_reason: text(payload.reason),
      });
      if (error) rpcFailure(error, "season_transition_failed");
      return ok({ result: data });
    }
    if (["submit", "review", "assign"].includes(action)) {
      const rpc = action === "submit"
        ? "sd_submit_registration"
        : action === "review"
        ? "sd_review_registration"
        : "sd_assign_registered_player";
      if (action !== "submit") {
        requireCapability(
          ctx.capabilities,
          action === "review"
            ? "review_registrations"
            : "assign_registered_player",
        );
      }
      const args = action === "submit"
        ? {
          p_organization_id: ctx.organizationId,
          p_actor_id: ctx.callerId,
          p_application_id: uuid(payload.application_id),
          p_expected_version: Number(payload.expected_version),
          p_request_id: uuid(payload.request_id),
        }
        : action === "review"
        ? {
          p_organization_id: ctx.organizationId,
          p_actor_id: ctx.callerId,
          p_application_id: uuid(payload.application_id),
          p_action: text(payload.review_action),
          p_expected_version: Number(payload.expected_version),
          p_request_id: uuid(payload.request_id),
          p_notes: text(payload.notes),
        }
        : {
          p_organization_id: ctx.organizationId,
          p_actor_id: ctx.callerId,
          p_application_id: uuid(payload.application_id),
          p_team_id: uuid(payload.team_id),
          p_expected_version: Number(payload.expected_version),
          p_request_id: uuid(payload.request_id),
        };
      const { data, error } = await ctx.admin.rpc(rpc, args);
      if (error) rpcFailure(error, "registration_command_failed");
      return ok({ result: data });
    }
    if (action === "rollover_preview") {
      requireCapability(ctx.capabilities, "execute_season_rollover");
      const sourceSeasonId = uuid(payload.source_season_id);
      if (!sourceSeasonId) {
        throw new ApiFailure(400, "missing_source_season_id");
      }
      const [teams, coaches, offerings, requirements] = await Promise.all([
        ctx.admin.from("sd_teams").select("id", { count: "exact", head: true })
          .eq("org_id", ctx.organizationId).eq("season_id", sourceSeasonId),
        ctx.admin.from("sd_coach_team_assignments").select("id", {
          count: "exact",
          head: true,
        }).eq("organization_id", ctx.organizationId).eq(
          "season_id",
          sourceSeasonId,
        ).eq("active", true),
        ctx.admin.from("sd_registration_offerings").select("id", {
          count: "exact",
          head: true,
        }).eq("organization_id", ctx.organizationId).eq(
          "season_id",
          sourceSeasonId,
        ),
        ctx.admin.from("sd_registration_requirement_templates").select("id", {
          count: "exact",
          head: true,
        }).eq("organization_id", ctx.organizationId).or(
          `season_id.eq.${sourceSeasonId},season_id.is.null`,
        ),
      ]);
      const preview = {
        teams: teams.count ?? 0,
        coach_assignments: coaches.count ?? 0,
        offerings: offerings.count ?? 0,
        requirements: requirements.count ?? 0,
        players: 0,
        attendance: 0,
        availability: 0,
        events: 0,
        payments: 0,
        operational_history: 0,
      };
      const { data, error } = await ctx.admin.from("sd_season_rollover_plans")
        .insert({
          organization_id: ctx.organizationId,
          source_season_id: sourceSeasonId,
          target_name: text(payload.target_name),
          target_start_date: text(payload.target_start_date) || null,
          target_end_date: text(payload.target_end_date) || null,
          copy_options: record(payload.copy_options),
          preview,
          state: "preview",
          created_by: ctx.callerId,
        }).select().single();
      if (error) throw new ApiFailure(409, "rollover_preview_failed");
      return ok({ plan: data });
    }
    if (action === "execute_rollover") {
      requireCapability(ctx.capabilities, "execute_season_rollover");
      const planId = uuid(payload.plan_id);
      const requestId = uuid(payload.request_id);
      if (!planId || !requestId || payload.confirmed !== true) {
        throw new ApiFailure(400, "rollover_confirmation_required");
      }
      const { error: confirmationError } = await ctx.admin.from(
        "sd_season_rollover_plans",
      ).update({ state: "confirmed", confirmed_by: ctx.callerId }).eq(
        "id",
        planId,
      ).eq("organization_id", ctx.organizationId).eq("state", "preview");
      if (confirmationError) {
        throw new ApiFailure(409, "rollover_confirmation_failed");
      }
      const { data, error } = await ctx.admin.rpc(
        "sd_execute_season_rollover",
        {
          p_organization_id: ctx.organizationId,
          p_actor_id: ctx.callerId,
          p_plan_id: planId,
          p_request_id: requestId,
        },
      );
      if (error) rpcFailure(error, "rollover_failed");
      return ok({ result: data });
    }
    throw new ApiFailure(400, "unsupported_action");
  } catch (error) {
    if (error instanceof ApiFailure) {
      return fail(error.status, error.code, error.message);
    }
    return fail(500, "registration_failed");
  }
});
