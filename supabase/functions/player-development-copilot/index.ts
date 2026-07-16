import {
  createClient,
  type SupabaseClient,
} from "https://esm.sh/@supabase/supabase-js@2.49.1";
import {
  buildEvidencePack,
  type DevelopmentAlert,
  type DevelopmentEvidence,
  type DevelopmentEvidencePack,
  type DevelopmentMembership,
  type DevelopmentReportRecord,
} from "../_shared/player_development_ai.ts";
import {
  type CopilotConversation,
  copilotLimitsFromEnvironment,
  type CopilotMessage,
  type CopilotStore,
  createPlayerDevelopmentCopilotHandler,
  type ParentDraftReviewEvent,
  type ParentUpdateDraft,
} from "../_shared/player_development_copilot.ts";
import { createConfiguredCopilotProvider } from "../_shared/player_development_copilot_providers.ts";
import { SupabasePlayerDevelopmentAIStore } from "../player-development-ai/index.ts";

const env = (name: string) => (Deno.env.get(name) ?? "").trim();
const url = env("SUPABASE_URL") || env("DHD_SUPABASE_URL");
const serviceKey = env("DHD_SERVICE_ROLE_KEY") ||
  env("SUPABASE_SERVICE_ROLE_KEY");

type Row = Record<string, unknown>;

function rows(value: unknown): Row[] {
  return Array.isArray(value)
    ? value.filter((item): item is Row =>
      typeof item === "object" && item !== null
    )
    : [];
}

function throwStoreError(error: unknown, fallback: string): never {
  const message =
    typeof error === "object" && error !== null && "message" in error &&
      typeof error.message === "string"
      ? error.message
      : fallback;
  throw new Error(message || fallback);
}

class SupabaseCopilotStore implements CopilotStore {
  private readonly admin: SupabaseClient;
  private readonly development = new SupabasePlayerDevelopmentAIStore();

  constructor() {
    this.admin = createClient(url, serviceKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
  }

  authenticate(request: Request): Promise<string | null> {
    return this.development.authenticate(request);
  }

  organizationStatus(orgId: string): Promise<string | null> {
    return this.development.organizationStatus(orgId);
  }

  membership(
    orgId: string,
    actorId: string,
  ): Promise<DevelopmentMembership | null> {
    return this.development.membership(orgId, actorId);
  }

  authorizedPlayerIds(orgId: string, actorId: string): Promise<Set<string>> {
    return this.development.authorizedPlayerIds(orgId, actorId);
  }

  async evidencePack(input: {
    orgId: string;
    playerId: string;
    windowStart: string;
    windowEnd: string;
    cutoff: string;
    maxEvidenceRows: number;
    audience: "coach" | "player";
  }): Promise<DevelopmentEvidencePack> {
    const [definitions, source] = await Promise.all([
      this.development.metricDefinitions(),
      this.development.evidenceSource(
        input.orgId,
        input.playerId,
        input.windowStart,
        input.windowEnd,
        input.cutoff,
      ),
    ]);
    const pack = buildEvidencePack({
      orgId: input.orgId,
      playerId: input.playerId,
      reportType: input.audience === "player"
        ? "player_copilot_self_question"
        : "coach_copilot",
      windowStart: input.windowStart,
      windowEnd: input.windowEnd,
      cutoff: input.cutoff,
      definitions,
      source,
    });
    const records = await this.playerWorkspaceRecords(
      input.orgId,
      input.playerId,
      input.audience === "player" ? "player" : "staff",
    );
    const reportEvidence: DevelopmentEvidence[] = records.reports.map((
      report,
    ) => ({
      evidence_key: `player-report:${report.id}`,
      section_key: "player_reports",
      source_entity_type: "sd_development_reports",
      source_record_id: report.id,
      canonical_metric_key: null,
      raw_observed_value: null,
      normalized_numeric_value: null,
      unit: null,
      observation_date: report.generated_at ?? report.created_at,
      comparison_value: null,
      comparison_period: null,
      direction: null,
      sample_size: null,
      freshness: report.data_freshness,
      quality: report.quality_status,
      deterministic_rule_id: null,
      display_label: "My development summary",
      explanation: report.structured_content.overview,
      source_metadata: {
        provider: report.provider,
        verification_status: "deterministic",
      },
      evidence_snapshot: {
        report_id: report.id,
        status: report.status,
        prompt_version: report.prompt_version,
        generated_at: report.generated_at,
      },
    }));
    const alertEvidence: DevelopmentEvidence[] = records.alerts.map((
      alert,
    ) => ({
      evidence_key: `player-alert:${alert.id}`,
      section_key: "player_alerts",
      source_entity_type: "sd_development_alerts",
      source_record_id: alert.id,
      canonical_metric_key: null,
      raw_observed_value: null,
      normalized_numeric_value: null,
      unit: null,
      observation_date: alert.last_detected_at,
      comparison_value: null,
      comparison_period: null,
      direction: null,
      sample_size: null,
      freshness: alert.data_freshness,
      quality: alert.evidence_quality,
      deterministic_rule_id: alert.rule_version,
      display_label: "Development notice",
      explanation: `${alert.explanation} ${alert.recommended_human_action}`,
      source_metadata: {
        provider: "deterministic_template",
        verification_status: "deterministic",
      },
      evidence_snapshot: {
        alert_id: alert.id,
        alert_type: alert.alert_type,
        severity: alert.severity,
        status: alert.status,
      },
    }));
    const enrichedPack = {
      ...pack,
      evidence: [...pack.evidence, ...reportEvidence, ...alertEvidence],
    };
    if (enrichedPack.evidence.length <= input.maxEvidenceRows) {
      return enrichedPack;
    }
    const evidence = enrichedPack.evidence.slice(-input.maxEvidenceRows);
    const keys = new Set(evidence.map((item) => item.evidence_key));
    return {
      ...enrichedPack,
      evidence,
      trends: pack.trends.filter((trend) =>
        trend.evidence_keys.every((key) => keys.has(key))
      ),
      missing_data_warnings: [
        ...enrichedPack.missing_data_warnings,
        `The evidence pack was bounded to ${input.maxEvidenceRows} rows.`,
      ],
      quality_status: enrichedPack.quality_status === "sufficient"
        ? "limited"
        : enrichedPack.quality_status,
    };
  }

  async playerWorkspaceRecords(
    orgId: string,
    playerId: string,
    audience: "staff" | "player" = "player",
  ): Promise<
    { reports: DevelopmentReportRecord[]; alerts: DevelopmentAlert[] }
  > {
    const [reports, alerts] = await Promise.all([
      this.development.listReports(orgId, [playerId], playerId, audience),
      this.development.listAlerts(orgId, [playerId], playerId, audience),
    ]);
    return {
      reports: reports.filter((report) => report.status !== "archived"),
      alerts: alerts.filter((alert) => alert.status === "active"),
    };
  }

  async createConversation(
    input: Parameters<CopilotStore["createConversation"]>[0],
  ): Promise<CopilotConversation> {
    const { data, error } = await this.admin.rpc(
      "sd_create_development_copilot_conversation",
      {
        p_actor_id: input.actorId,
        p_org_id: input.orgId,
        p_player_id: input.playerId,
        p_title: input.title,
        p_reporting_window_days: input.reportingWindowDays,
        p_evidence_cutoff: input.evidenceCutoff,
        p_generation_mode: input.generationMode,
        p_provider: input.provider,
        p_model_identifier: input.modelIdentifier,
        p_generator_version: input.generatorVersion,
        p_idempotency_key: input.idempotencyKey,
        p_audience: input.audience,
      },
    );
    if (error) throwStoreError(error, "conversation_create_failed");
    return data as CopilotConversation;
  }

  async listConversations(
    orgId: string,
    playerIds: string[],
    playerId: string | undefined,
    includeArchived: boolean,
    limit: number,
    offset: number,
    audience: "coach" | "player",
    actorId: string,
  ): Promise<{ conversations: CopilotConversation[]; total: number }> {
    if (playerIds.length === 0) return { conversations: [], total: 0 };
    let query = this.admin.from("sd_development_copilot_conversations")
      .select("*", { count: "exact" }).eq("org_id", orgId)
      .eq("audience", audience).in("player_id", playerIds)
      .order("updated_at", { ascending: false })
      .range(offset, offset + limit - 1);
    if (audience === "player") query = query.eq("created_by", actorId);
    if (playerId) query = query.eq("player_id", playerId);
    if (!includeArchived) query = query.eq("status", "active");
    const { data, error, count } = await query;
    if (error) throwStoreError(error, "conversation_list_failed");
    const conversations = (data ?? []) as CopilotConversation[];
    await this.enrichConversations(conversations);
    return { conversations, total: count ?? conversations.length };
  }

  private async enrichConversations(
    conversations: CopilotConversation[],
  ): Promise<void> {
    if (conversations.length === 0) return;
    const playerIds = [...new Set(conversations.map((item) => item.player_id))];
    const conversationIds = conversations.map((item) => item.id);
    const [profileResult, messageResult] = await Promise.all([
      this.admin.from("profiles").select("id,full_name").in("id", playerIds),
      this.admin.from("sd_development_copilot_messages")
        .select(
          "conversation_id,role,user_question,rendered_answer,quality_status,created_at",
        )
        .eq("audience", conversations[0].audience).in(
          "conversation_id",
          conversationIds,
        ).order("created_at", {
          ascending: false,
        }),
    ]);
    if (profileResult.error || messageResult.error) {
      throwStoreError(
        profileResult.error ?? messageResult.error,
        "conversation_enrichment_failed",
      );
    }
    const names = new Map(
      rows(profileResult.data).map((item) => [item.id, item.full_name]),
    );
    const messages = rows(messageResult.data);
    for (const conversation of conversations) {
      conversation.player_name =
        typeof names.get(conversation.player_id) === "string"
          ? names.get(conversation.player_id) as string
          : null;
      const scoped = messages.filter((item) =>
        item.conversation_id === conversation.id
      );
      const question = scoped.find((item) => item.role === "user");
      const answer = scoped.find((item) => item.role === "assistant");
      conversation.most_recent_question =
        typeof question?.user_question === "string"
          ? question.user_question
          : null;
      conversation.most_recent_answer_preview =
        typeof answer?.rendered_answer === "string"
          ? answer.rendered_answer.slice(0, 240)
          : null;
      conversation.quality_status = typeof answer?.quality_status === "string"
        ? answer.quality_status as CopilotConversation["quality_status"]
        : null;
    }
  }

  async conversation(
    orgId: string,
    conversationId: string,
    playerIds: string[],
    audience: "coach" | "player",
    actorId: string,
  ): Promise<CopilotConversation | null> {
    if (playerIds.length === 0) return null;
    let query = this.admin.from(
      "sd_development_copilot_conversations",
    ).select("*").eq("org_id", orgId).eq("id", conversationId).eq(
      "audience",
      audience,
    ).in(
      "player_id",
      playerIds,
    );
    if (audience === "player") query = query.eq("created_by", actorId);
    const { data, error } = await query.maybeSingle();
    if (error) throwStoreError(error, "conversation_lookup_failed");
    return data as CopilotConversation | null;
  }

  async archiveConversation(
    actorId: string,
    orgId: string,
    conversationId: string,
    audience: "coach" | "player",
  ): Promise<CopilotConversation> {
    const { data, error } = await this.admin.rpc(
      "sd_archive_development_copilot_conversation",
      {
        p_actor_id: actorId,
        p_org_id: orgId,
        p_conversation_id: conversationId,
        p_audience: audience,
      },
    );
    if (error) throwStoreError(error, "conversation_archive_failed");
    return data as CopilotConversation;
  }

  async messages(
    orgId: string,
    conversationId: string,
    playerIds: string[],
    limit: number,
    offset: number,
    audience: "coach" | "player",
  ): Promise<{ messages: CopilotMessage[]; total: number }> {
    if (playerIds.length === 0) return { messages: [], total: 0 };
    const { data, error, count } = await this.admin.from(
      "sd_development_copilot_messages",
    ).select("*", { count: "exact" }).eq("org_id", orgId).eq(
      "conversation_id",
      conversationId,
    ).eq("audience", audience).in("player_id", playerIds).order("created_at")
      .order("id").range(
        offset,
        offset + limit - 1,
      );
    if (error) throwStoreError(error, "message_list_failed");
    const messages = (data ?? []) as CopilotMessage[];
    const assistantIds = messages.filter((item) => item.role === "assistant")
      .map((item) => item.id);
    if (assistantIds.length > 0) {
      const [citationResult, pendingResult] = await Promise.all([
        this.admin.from("sd_development_copilot_message_citations").select("*")
          .eq("org_id", orgId).eq("audience", audience).in(
            "message_id",
            assistantIds,
          ).order("section_key").order("claim_identifier"),
        this.admin.from("sd_development_copilot_pending_questions").select("*")
          .eq("org_id", orgId).eq("audience", audience).in(
            "assistant_message_id",
            assistantIds,
          ),
      ]);
      if (citationResult.error || pendingResult.error) {
        throwStoreError(
          citationResult.error ?? pendingResult.error,
          "message_enrichment_failed",
        );
      }
      for (const message of messages) {
        message.citations = rows(citationResult.data).filter((item) =>
          item.message_id === message.id
        ) as CopilotMessage["citations"];
        message.pending_question = rows(pendingResult.data).find((item) =>
          item.assistant_message_id === message.id
        ) as CopilotMessage["pending_question"] ?? null;
      }
    }
    return { messages, total: count ?? messages.length };
  }

  async message(
    orgId: string,
    conversationId: string,
    messageId: string,
    playerIds: string[],
    audience: "coach" | "player",
  ): Promise<CopilotMessage | null> {
    if (playerIds.length === 0) return null;
    const { data, error } = await this.admin.from(
      "sd_development_copilot_messages",
    ).select("*").eq("org_id", orgId).eq("audience", audience).eq(
      "conversation_id",
      conversationId,
    ).eq("id", messageId).in("player_id", playerIds).maybeSingle();
    if (error) throwStoreError(error, "message_lookup_failed");
    const message = data as CopilotMessage | null;
    if (!message || message.role !== "assistant") return message;
    const citationResult = await this.admin.from(
      "sd_development_copilot_message_citations",
    ).select("*").eq("org_id", orgId).eq("audience", audience).eq(
      "message_id",
      message.id,
    ).order(
      "section_key",
    ).order("claim_identifier");
    if (citationResult.error) {
      throwStoreError(citationResult.error, "citation_list_failed");
    }
    message.citations = rows(
      citationResult.data,
    ) as CopilotMessage["citations"];
    const pendingResult = await this.admin.from(
      "sd_development_copilot_pending_questions",
    ).select("*").eq("org_id", orgId).eq("audience", audience).eq(
      "assistant_message_id",
      message.id,
    ).maybeSingle();
    if (pendingResult.error) {
      throwStoreError(pendingResult.error, "pending_question_lookup_failed");
    }
    message.pending_question = pendingResult
      .data as CopilotMessage["pending_question"];
    return message;
  }

  async pendingQuestion(
    orgId: string,
    conversationId: string,
    pendingQuestionId: string,
    audience: "coach" | "player",
    actorId: string,
  ): ReturnType<CopilotStore["pendingQuestion"]> {
    const { data, error } = await this.admin.from(
      "sd_development_copilot_pending_questions",
    ).select("*").eq("org_id", orgId).eq("conversation_id", conversationId)
      .eq("audience", audience).eq("id", pendingQuestionId).maybeSingle();
    if (error) throwStoreError(error, "pending_question_lookup_failed");
    if (!data) return null;
    if (audience === "player") {
      const { data: conversation, error: conversationError } = await this.admin
        .from("sd_development_copilot_conversations").select("id").eq(
          "id",
          conversationId,
        ).eq("org_id", orgId).eq("player_id", actorId).eq(
          "created_by",
          actorId,
        ).eq("audience", "player").maybeSingle();
      if (conversationError) {
        throwStoreError(conversationError, "pending_question_lookup_failed");
      }
      if (!conversation) return null;
    }
    return data as Awaited<ReturnType<CopilotStore["pendingQuestion"]>>;
  }

  async persistExchange(
    input: Parameters<CopilotStore["persistExchange"]>[0],
  ): ReturnType<CopilotStore["persistExchange"]> {
    const { data, error } = await this.admin.rpc(
      "sd_persist_development_copilot_dialogue_turn",
      {
        p_actor_id: input.actorId,
        p_org_id: input.orgId,
        p_player_id: input.playerId,
        p_conversation_id: input.conversationId,
        p_question: input.question,
        p_structured_answer: input.answer,
        p_rendered_answer: input.renderedAnswer,
        p_quality_status: input.qualityStatus,
        p_evidence_cutoff: input.cutoff,
        p_generation_mode: input.generationMode,
        p_provider: input.provider,
        p_model_identifier: input.modelIdentifier,
        p_prompt_version: input.promptVersion,
        p_generator_version: input.generatorVersion,
        p_generation_status: input.generationStatus,
        p_safe_error_code: input.safeErrorCode,
        p_idempotency_key: input.idempotencyKey,
        p_citations: input.citations,
        p_attempt: input.attempt,
        p_audience: input.audience,
        p_assistant_turn_type: input.answer?.assistant_turn_type ??
          (input.generationStatus === "rejected" ? "safe_refusal" : "answer"),
        p_pending_question: input.answer?.pending_question ?? null,
        p_pending_question_id: input.pendingQuestionId,
        p_pending_response_mode: input.pendingResponseMode,
      },
    );
    if (error) throwStoreError(error, "exchange_persistence_failed");
    return data as Awaited<ReturnType<CopilotStore["persistExchange"]>>;
  }

  async submitFeedback(
    input: Parameters<CopilotStore["submitFeedback"]>[0],
  ): Promise<Record<string, unknown>> {
    const { data, error } = await this.admin.rpc(
      "sd_submit_development_copilot_feedback",
      {
        p_actor_id: input.actorId,
        p_org_id: input.orgId,
        p_player_id: input.playerId,
        p_conversation_id: input.conversationId,
        p_message_id: input.messageId,
        p_feedback_type: input.feedbackType,
        p_safe_note: input.note,
        p_audience: input.audience,
      },
    );
    if (error) throwStoreError(error, "feedback_submit_failed");
    return data as Record<string, unknown>;
  }

  async createParentDraft(
    input: Parameters<CopilotStore["createParentDraft"]>[0],
  ): Promise<ParentUpdateDraft> {
    const { data, error } = await this.admin.rpc(
      "sd_create_development_parent_update_draft",
      {
        p_actor_id: input.actorId,
        p_org_id: input.orgId,
        p_player_id: input.playerId,
        p_conversation_id: input.conversationId,
        p_source_message_id: input.sourceMessageId,
        p_content: input.content,
        p_rendered_text: input.renderedText,
        p_evidence_cutoff: input.cutoff,
        p_generation_mode: input.generationMode,
        p_provider: input.provider,
        p_model_identifier: input.modelIdentifier,
        p_prompt_version: input.promptVersion,
        p_generator_version: input.generatorVersion,
        p_idempotency_key: input.idempotencyKey,
      },
    );
    if (error) throwStoreError(error, "parent_draft_create_failed");
    return data as ParentUpdateDraft;
  }

  async listParentDrafts(
    orgId: string,
    playerIds: string[],
    playerId: string | undefined,
  ): Promise<ParentUpdateDraft[]> {
    if (playerIds.length === 0) return [];
    let query = this.admin.from("sd_development_parent_update_drafts")
      .select("*").eq("org_id", orgId).in("player_id", playerIds).order(
        "updated_at",
        { ascending: false },
      ).limit(100);
    if (playerId) query = query.eq("player_id", playerId);
    const { data, error } = await query;
    if (error) throwStoreError(error, "parent_draft_list_failed");
    return (data ?? []) as ParentUpdateDraft[];
  }

  async parentDraft(
    orgId: string,
    draftId: string,
    playerIds: string[],
  ): Promise<
    { draft: ParentUpdateDraft; review_events: ParentDraftReviewEvent[] } | null
  > {
    if (playerIds.length === 0) return null;
    const draftResult = await this.admin.from(
      "sd_development_parent_update_drafts",
    ).select("*").eq("org_id", orgId).eq("id", draftId).in(
      "player_id",
      playerIds,
    ).maybeSingle();
    if (draftResult.error) {
      throwStoreError(draftResult.error, "parent_draft_lookup_failed");
    }
    if (!draftResult.data) return null;
    const eventResult = await this.admin.from(
      "sd_development_parent_draft_review_events",
    ).select("*").eq("org_id", orgId).eq("draft_id", draftId).order(
      "created_at",
    ).order("id");
    if (eventResult.error) {
      throwStoreError(eventResult.error, "parent_draft_event_lookup_failed");
    }
    return {
      draft: draftResult.data as ParentUpdateDraft,
      review_events: (eventResult.data ?? []) as ParentDraftReviewEvent[],
    };
  }

  async reviewParentDraft(
    input: Parameters<CopilotStore["reviewParentDraft"]>[0],
  ): Promise<ParentUpdateDraft> {
    const { data, error } = await this.admin.rpc(
      "sd_review_development_parent_update_draft",
      {
        p_actor_id: input.actorId,
        p_org_id: input.orgId,
        p_draft_id: input.draftId,
        p_action: input.action,
        p_content: input.content,
        p_rendered_text: input.renderedText,
        p_safe_note: input.note,
      },
    );
    if (error) throwStoreError(error, "parent_draft_review_failed");
    return data as ParentUpdateDraft;
  }

  async usage(
    orgId: string,
    actorId: string,
    audience: "coach" | "player",
  ): Promise<{
    organization_questions_today: number;
    actor_questions_this_hour: number;
    organization_parent_drafts_today: number;
  }> {
    const now = new Date();
    const day = new Date(
      Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate()),
    ).toISOString();
    const hour = new Date(now.getTime() - 3_600_000).toISOString();
    const [orgQuestions, actorQuestions, drafts] = await Promise.all([
      this.admin.from("sd_development_ai_usage_ledger").select("id", {
        count: "exact",
        head: true,
      }).eq("org_id", orgId).eq("audience", audience).in("action_type", [
        "ask",
        "retry_message",
      ]).gte(
        "created_at",
        day,
      ),
      this.admin.from("sd_development_ai_usage_ledger").select("id", {
        count: "exact",
        head: true,
      }).eq("org_id", orgId).eq("audience", audience).eq("actor_id", actorId)
        .in("action_type", [
          "ask",
          "retry_message",
        ]).gte("created_at", hour),
      this.admin.from("sd_development_parent_update_drafts").select("id", {
        count: "exact",
        head: true,
      }).eq("org_id", orgId).gte("created_at", day),
    ]);
    if (orgQuestions.error || actorQuestions.error || drafts.error) {
      throwStoreError(
        orgQuestions.error ?? actorQuestions.error ?? drafts.error,
        "usage_lookup_failed",
      );
    }
    return {
      organization_questions_today: orgQuestions.count ?? 0,
      actor_questions_this_hour: actorQuestions.count ?? 0,
      organization_parent_drafts_today: drafts.count ?? 0,
    };
  }
}

Deno.serve((request) =>
  createPlayerDevelopmentCopilotHandler(
    new SupabaseCopilotStore(),
    (pack) => createConfiguredCopilotProvider(pack),
    () => new Date(),
    copilotLimitsFromEnvironment(),
  )(request)
);
