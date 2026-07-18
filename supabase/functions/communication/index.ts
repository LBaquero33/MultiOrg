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

Deno.serve(async (req) => {
  try {
    const payload = record(await req.json());
    const ctx = await organizationContext(req, payload);
    const action = text(payload.action);
    if (action === "inbox") {
      const { data, error } = await ctx.admin.from("sd_notifications").select(
        "id,org_id,category,title,body,related_entity_type,related_entity_id,action_route,action_payload,created_at,read_at,archived_at,source",
      ).eq("org_id", ctx.organizationId).eq("recipient_user_id", ctx.callerId)
        .is("archived_at", null).order("created_at", { ascending: false })
        .limit(100);
      if (error) throw new ApiFailure(500, "notification_lookup_failed");
      return ok({ notifications: data ?? [] });
    }
    if (action === "announcements") {
      const { data, error } = await ctx.admin.from("sd_announcement_recipients")
        .select(
          "read_at,acknowledged_at,archived_at,announcement:sd_announcements(*)",
        ).eq("organization_id", ctx.organizationId).eq(
          "recipient_user_id",
          ctx.callerId,
        ).is("archived_at", null).order("created_at", { ascending: false })
        .limit(100);
      if (error) throw new ApiFailure(500, "announcement_lookup_failed");
      return ok({ announcements: data ?? [] });
    }
    if (action === "preferences") {
      const { data, error } = await ctx.admin.from(
        "sd_notification_preferences",
      )
        .select("*").eq("organization_id", ctx.organizationId).eq(
          "user_id",
          ctx.callerId,
        ).order("category");
      if (error) throw new ApiFailure(500, "preference_lookup_failed");
      return ok({ preferences: data ?? [] });
    }
    if (action === "publish_announcement") {
      const requestId = uuid(payload.request_id);
      if (!requestId) throw new ApiFailure(400, "missing_request_id");
      const { data, error } = await ctx.admin.rpc("sd_publish_announcement", {
        p_organization_id: ctx.organizationId,
        p_actor_id: ctx.callerId,
        p_request_id: requestId,
        p_payload: record(payload.announcement),
      });
      if (error) rpcFailure(error, "announcement_failed");
      return ok({ result: data });
    }
    if (action === "set_preference") {
      const { data, error } = await ctx.admin.rpc(
        "sd_set_notification_preference",
        {
          p_actor_id: ctx.callerId,
          p_organization_id: ctx.organizationId,
          p_team_id: uuid(payload.team_id),
          p_subject_player_id: uuid(payload.player_id),
          p_category: text(payload.category),
          p_payload: record(payload.preference),
          p_expected_version: payload.expected_version == null
            ? null
            : Number(payload.expected_version),
        },
      );
      if (error) rpcFailure(error, "preference_failed");
      return ok({ preference: data });
    }
    if (action === "edit_message" || action === "redact_message") {
      const rpc = action === "edit_message"
        ? "sd_edit_chat_message"
        : "sd_redact_chat_message";
      const args = action === "edit_message"
        ? {
          p_organization_id: ctx.organizationId,
          p_actor_id: ctx.callerId,
          p_message_id: uuid(payload.message_id),
          p_body: text(payload.body),
          p_expected_version: Number(payload.expected_version),
          p_request_id: uuid(payload.request_id),
        }
        : {
          p_organization_id: ctx.organizationId,
          p_actor_id: ctx.callerId,
          p_message_id: uuid(payload.message_id),
          p_expected_version: Number(payload.expected_version),
          p_request_id: uuid(payload.request_id),
          p_reason: text(payload.reason),
        };
      const { data, error } = await ctx.admin.rpc(rpc, args);
      if (error) rpcFailure(error, "message_mutation_failed");
      return ok({ message: data });
    }
    if (action === "acknowledge") {
      const announcementId = uuid(payload.announcement_id);
      if (!announcementId) throw new ApiFailure(400, "missing_announcement_id");
      const { data, error } = await ctx.admin.from("sd_announcement_recipients")
        .update({
          read_at: new Date().toISOString(),
          acknowledged_at: new Date().toISOString(),
        }).eq("announcement_id", announcementId).eq(
          "recipient_user_id",
          ctx.callerId,
        ).eq("organization_id", ctx.organizationId).select().single();
      if (error) throw new ApiFailure(409, "acknowledgment_failed");
      return ok({ recipient: data });
    }
    if (action === "delivery_status") {
      requireCapability(ctx.capabilities, "view_delivery_status");
      const { data, error } = await ctx.admin.from(
        "sd_notification_intent_receipts",
      ).select(
        "id,source_type,source_id,category,delivery_state,preference_decision,failure_reason,attempt_count,next_attempt_at,delivered_at,created_at",
      ).eq("organization_id", ctx.organizationId).order("created_at", {
        ascending: false,
      }).limit(200);
      if (error) throw new ApiFailure(500, "delivery_lookup_failed");
      return ok({ deliveries: data ?? [] });
    }
    if (action === "process_event_intents") {
      requireCapability(ctx.capabilities, "manage_notification_delivery");
      const dryRun = payload.dry_run !== false;
      const limit = Math.min(Math.max(Number(payload.limit ?? 25), 1), 100);
      const { data: intents, error } = await ctx.admin.from(
        "sd_team_event_notification_intents",
      ).select("id,intent_type,created_at").eq(
        "organization_id",
        ctx.organizationId,
      ).is("consumed_at", null).order("created_at").limit(limit);
      if (error) throw new ApiFailure(500, "intent_lookup_failed");
      const results = [];
      for (const intent of intents ?? []) {
        const response = await ctx.admin.rpc(
          "sd_consume_team_event_notification_intent",
          {
            p_intent_id: intent.id,
            p_actor_id: ctx.callerId,
            p_dry_run: dryRun,
          },
        );
        if (response.error) {
          rpcFailure(response.error, "intent_delivery_failed");
        }
        results.push(response.data);
      }
      return ok({ dry_run: dryRun, processed: results });
    }
    if (action === "process_organization_intents") {
      requireCapability(ctx.capabilities, "manage_notification_delivery");
      const dryRun = payload.dry_run !== false;
      const limit = Math.min(Math.max(Number(payload.limit ?? 25), 1), 100);
      const [registration, finance] = await Promise.all([
        ctx.admin.from("sd_registration_notification_intents").select(
          "id,created_at",
        ).eq("organization_id", ctx.organizationId).is("consumed_at", null)
          .order("created_at").limit(limit),
        ctx.admin.from("sd_financial_notification_intents").select(
          "id,created_at",
        ).eq("org_id", ctx.organizationId).is("consumed_at", null).order(
          "created_at",
        ).limit(limit),
      ]);
      if (registration.error || finance.error) {
        throw new ApiFailure(500, "intent_lookup_failed");
      }
      const pending = [
        ...(registration.data ?? []).map((row) => ({
          ...row,
          source_type: "registration",
        })),
        ...(finance.data ?? []).map((row) => ({
          ...row,
          source_type: "finance",
        })),
      ].sort((a, b) => String(a.created_at).localeCompare(String(b.created_at)))
        .slice(0, limit);
      const results = [];
      for (const intent of pending) {
        const response = await ctx.admin.rpc(
          "sd_consume_organization_notification_intent",
          {
            p_source_type: intent.source_type,
            p_source_id: intent.id,
            p_actor_id: ctx.callerId,
            p_dry_run: dryRun,
          },
        );
        if (response.error) {
          rpcFailure(response.error, "intent_delivery_failed");
        }
        results.push(response.data);
      }
      return ok({ dry_run: dryRun, processed: results });
    }
    throw new ApiFailure(400, "unsupported_action");
  } catch (error) {
    if (error instanceof ApiFailure) {
      return fail(error.status, error.code, error.message);
    }
    return fail(500, "communication_failed");
  }
});
