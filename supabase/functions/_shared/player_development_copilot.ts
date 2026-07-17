import type {
  DevelopmentAlert,
  DevelopmentEvidence,
  DevelopmentEvidencePack,
  DevelopmentMembership,
  DevelopmentQualityStatus,
  DevelopmentReportRecord,
} from "./player_development_ai.ts";

export const COPILOT_EVIDENCE_SCHEMA_VERSION =
  "player_development_evidence_pack.v1";
export const COPILOT_OUTPUT_SCHEMA_VERSION =
  "player_development_copilot_answer.v1";
export const COPILOT_SAFETY_VERSION = "player-development-safety.v1";
export const COPILOT_GENERATOR_VERSION = "player-development-copilot.v1";
export const COPILOT_PROMPT_VERSION = "coach-copilot.v1";
export const PLAYER_COPILOT_PROMPT_VERSION = "player-copilot-self.v1";
export const PARENT_DRAFT_PROMPT_VERSION = "parent-update.v1";
export const COPILOT_MAX_QUESTION_CHARACTERS = 2_000;
export const COPILOT_MAX_REQUEST_BYTES = 65_536;
export const COPILOT_MAX_REPORTING_WINDOW_DAYS = 730;
export const COPILOT_DEFAULT_LIMITS = {
  questionsPerOrganizationDay: 200,
  questionsPerActorHour: 30,
  parentDraftsPerOrganizationDay: 50,
  evidenceRows: 500,
  conversationMessages: 40,
  outputCharacters: 16_000,
} as const;

export type CopilotLimits = {
  questionsPerOrganizationDay: number;
  questionsPerActorHour: number;
  parentDraftsPerOrganizationDay: number;
  evidenceRows: number;
  conversationMessages: number;
  outputCharacters: number;
};

export function copilotLimitsFromEnvironment(
  env: (name: string) => string | undefined = (name) => Deno.env.get(name),
): CopilotLimits {
  function bounded(
    name: string,
    fallback: number,
    minimum: number,
    maximum: number,
  ): number {
    const value = Number(env(name) ?? "");
    return Number.isInteger(value) && value >= minimum && value <= maximum
      ? value
      : fallback;
  }
  return {
    questionsPerOrganizationDay: bounded(
      "PLAYER_DEVELOPMENT_AI_QUESTIONS_PER_ORG_DAY",
      200,
      1,
      10_000,
    ),
    questionsPerActorHour: bounded(
      "PLAYER_DEVELOPMENT_AI_QUESTIONS_PER_ACTOR_HOUR",
      30,
      1,
      1_000,
    ),
    parentDraftsPerOrganizationDay: bounded(
      "PLAYER_DEVELOPMENT_AI_PARENT_DRAFTS_PER_ORG_DAY",
      50,
      1,
      1_000,
    ),
    evidenceRows: bounded(
      "PLAYER_DEVELOPMENT_AI_MAX_EVIDENCE_ROWS",
      500,
      1,
      2_000,
    ),
    conversationMessages: bounded(
      "PLAYER_DEVELOPMENT_AI_MAX_CONVERSATION_MESSAGES",
      40,
      1,
      100,
    ),
    outputCharacters: bounded(
      "PLAYER_DEVELOPMENT_AI_MAX_OUTPUT_CHARACTERS",
      16_000,
      1_000,
      32_000,
    ),
  };
}

export type CopilotGenerationMode =
  | "deterministic"
  | "model"
  | "hybrid"
  | "unavailable";

export type CopilotAudience = "coach" | "player";

export type CopilotDeterministicIntent =
  | "period_change_summary"
  | "overall_development_summary"
  | "missing_evidence"
  | "stale_evidence"
  | "improved_metrics"
  | "attention_metrics"
  | "metric_explanation"
  | "latest_import_summary"
  | "next_session_review"
  | "coach_discussion_prep"
  | "active_objective_alerts"
  | "assigned_programs"
  | "data_quality_summary";

export type CopilotIntentClassification = {
  intent: CopilotDeterministicIntent | null;
  period_days: 30 | 90 | null;
  metric_key: string | null;
  needs_clarification: boolean;
};

export type CopilotAssistantTurnType =
  | "answer"
  | "clarification_question"
  | "evidence_gap_question"
  | "reflection_question"
  | "confirmation_question"
  | "suggested_follow_up"
  | "action_preview"
  | "safe_refusal";

export type CopilotPendingQuestionDraft = {
  question_type:
    | "clarification_question"
    | "evidence_gap_question"
    | "reflection_question"
    | "confirmation_question";
  why_asked: string;
  expected_response_type: "choice" | "free_text" | "confirmation";
  choices: string[];
  related_evidence_ids: string[];
  is_optional: boolean;
  may_later_be_saved: boolean;
  expires_at: string;
};

export type CopilotPendingQuestion = CopilotPendingQuestionDraft & {
  id: string;
  conversation_id: string;
  assistant_message_id: string;
  status: "pending" | "answered" | "skipped" | "expired" | "superseded";
  answered_at: string | null;
};

export type CopilotClaim = {
  text: string;
  evidence_ids: string[];
};

export type CopilotCalculation = CopilotClaim & { rule_id: string };
export type CopilotInterpretation = CopilotClaim & { confidence: number };
export type CopilotRecommendation = CopilotClaim & {
  requires_human_approval: true;
};

export type CopilotProposedAction = {
  action_type:
    | "schedule_retesting"
    | "review_alert"
    | "create_draft_coach_note"
    | "generate_parent_update"
    | "review_program_assignment"
    | "investigate_data_quality"
    | "discuss_metric_with_player"
    | "review_metric_with_coach"
    | "request_retesting"
    | "upload_updated_data"
    | "complete_assigned_session"
    | "review_assigned_program"
    | "log_training_session"
    | "discuss_data_quality"
    | "prepare_coach_questions"
    | "update_personal_goal";
  explanation: string;
  evidence_ids: string[];
  urgency: "low" | "medium" | "high";
  confidence: number;
  requires_approval: true;
};

export type CopilotStructuredAnswer = {
  schema_version: typeof COPILOT_OUTPUT_SCHEMA_VERSION;
  assistant_turn_type: CopilotAssistantTurnType;
  pending_question: CopilotPendingQuestionDraft | null;
  answer: string;
  answer_quality: DevelopmentQualityStatus;
  facts: CopilotClaim[];
  calculations: CopilotCalculation[];
  interpretations: CopilotInterpretation[];
  recommendations: CopilotRecommendation[];
  missing_data: string[];
  follow_up_questions: string[];
  warnings: string[];
  proposed_actions: CopilotProposedAction[];
};

export type CopilotCitation = {
  evidence_key: string;
  source_entity_type: string;
  source_record_id: string;
  canonical_metric_key: string | null;
  observed_value: string | null;
  normalized_value: number | null;
  unit: string | null;
  observed_at: string | null;
  display_label: string;
  explanation: string;
  section_key: string;
  claim_identifier: string;
  source_provider: string | null;
  verification_status: string | null;
  deterministic_rule_id: string | null;
  evidence_snapshot: Record<string, unknown>;
};

export type CopilotConversation = {
  id: string;
  org_id: string;
  player_id: string;
  created_by: string;
  audience: CopilotAudience;
  title: string;
  status: "active" | "archived";
  reporting_window_days: number;
  evidence_cutoff: string;
  generation_mode: CopilotGenerationMode;
  provider: string;
  model_identifier: string | null;
  generator_version: string;
  archived_at: string | null;
  created_at: string;
  updated_at: string;
  player_name?: string | null;
  most_recent_question?: string | null;
  most_recent_answer_preview?: string | null;
  quality_status?: DevelopmentQualityStatus | "rejected" | null;
};

export type CopilotMessage = {
  id: string;
  conversation_id: string;
  org_id: string;
  player_id: string;
  actor_id: string | null;
  audience: CopilotAudience;
  role: "user" | "assistant";
  assistant_turn_type: CopilotAssistantTurnType | null;
  in_reply_to_question_id: string | null;
  user_question: string | null;
  structured_answer: CopilotStructuredAnswer | null;
  rendered_answer: string | null;
  quality_status: DevelopmentQualityStatus | "rejected";
  evidence_cutoff: string;
  generation_mode: CopilotGenerationMode;
  provider: string;
  model_identifier: string | null;
  prompt_version: string;
  generator_version: string;
  generation_status: "pending" | "succeeded" | "failed" | "rejected";
  safe_error_code: string | null;
  archived_at: string | null;
  created_at: string;
  citations?: CopilotCitation[];
  pending_question?: CopilotPendingQuestion | null;
};

export type ParentUpdateContent = {
  schema_version: "parent_update_draft.v1";
  recent_work: string;
  positive_developments: string;
  current_focus: string;
  consistency: string;
  recent_testing: string;
  evidence_limitations: string;
  upcoming_next_steps: string;
};

export type ParentUpdateDraft = {
  id: string;
  org_id: string;
  player_id: string;
  conversation_id: string | null;
  source_message_id: string | null;
  created_by: string;
  status: "generated" | "reviewed" | "approved" | "rejected" | "archived";
  generated_original: ParentUpdateContent;
  edited_content: ParentUpdateContent;
  generated_rendered_text: string;
  edited_rendered_text: string;
  evidence_cutoff: string;
  generation_mode: Exclude<CopilotGenerationMode, "unavailable">;
  provider: string;
  model_identifier: string | null;
  prompt_version: string;
  generator_version: string;
  reviewed_at: string | null;
  reviewed_by: string | null;
  approved_at: string | null;
  approved_by: string | null;
  rejected_at: string | null;
  rejected_by: string | null;
  archived_at: string | null;
  archived_by: string | null;
  created_at: string;
  updated_at: string;
};

export type ParentDraftReviewEvent = {
  id: string;
  draft_id: string;
  org_id: string;
  player_id: string;
  actor_id: string;
  event_type: string;
  from_status: string | null;
  to_status: string;
  safe_note: string | null;
  content_snapshot: ParentUpdateContent;
  created_at: string;
};

export type UsageSummary = {
  organization_questions_today: number;
  actor_questions_this_hour: number;
  organization_parent_drafts_today: number;
  limits: CopilotLimits;
};

export type CopilotPromptContext = {
  audience: CopilotAudience;
  prompt_version: string;
  safety_version: string;
  output_schema_version: string;
  question: string;
  organization_id: string;
  player_id: string;
  player_name: string;
  window_start: string;
  window_end: string;
  deterministic_calculations: DevelopmentEvidencePack["trends"];
  untrusted_evidence: Array<{
    evidence_id: string;
    source_type: string;
    metric: string | null;
    value: string | number | null;
    unit: string | null;
    observed_at: string | null;
    display_label: string;
    explanation: string;
  }>;
};

export interface CopilotGenerationProvider {
  readonly provider: string;
  readonly modelIdentifier: string | null;
  readonly mode: CopilotGenerationMode;
  readonly generatorVersion: string;
  generate(context: CopilotPromptContext): Promise<unknown>;
}

export interface CopilotStore {
  authenticate(request: Request): Promise<string | null>;
  organizationStatus(orgId: string): Promise<string | null>;
  membership(
    orgId: string,
    actorId: string,
  ): Promise<DevelopmentMembership | null>;
  authorizedPlayerIds(orgId: string, actorId: string): Promise<Set<string>>;
  evidencePack(input: {
    orgId: string;
    playerId: string;
    windowStart: string;
    windowEnd: string;
    cutoff: string;
    maxEvidenceRows: number;
    audience: CopilotAudience;
  }): Promise<DevelopmentEvidencePack>;
  playerWorkspaceRecords?(
    orgId: string,
    playerId: string,
  ): Promise<{
    reports: DevelopmentReportRecord[];
    alerts: DevelopmentAlert[];
  }>;
  createConversation(input: {
    actorId: string;
    orgId: string;
    playerId: string;
    title: string;
    reportingWindowDays: number;
    evidenceCutoff: string;
    generationMode: CopilotGenerationMode;
    provider: string;
    modelIdentifier: string | null;
    generatorVersion: string;
    idempotencyKey: string;
    audience: CopilotAudience;
  }): Promise<CopilotConversation>;
  listConversations(
    orgId: string,
    playerIds: string[],
    playerId: string | undefined,
    includeArchived: boolean,
    limit: number,
    offset: number,
    audience: CopilotAudience,
    actorId: string,
  ): Promise<{ conversations: CopilotConversation[]; total: number }>;
  conversation(
    orgId: string,
    conversationId: string,
    playerIds: string[],
    audience: CopilotAudience,
    actorId: string,
  ): Promise<CopilotConversation | null>;
  archiveConversation(
    actorId: string,
    orgId: string,
    conversationId: string,
    audience: CopilotAudience,
  ): Promise<CopilotConversation>;
  messages(
    orgId: string,
    conversationId: string,
    playerIds: string[],
    limit: number,
    offset: number,
    audience: CopilotAudience,
  ): Promise<{ messages: CopilotMessage[]; total: number }>;
  message(
    orgId: string,
    conversationId: string,
    messageId: string,
    playerIds: string[],
    audience: CopilotAudience,
  ): Promise<CopilotMessage | null>;
  pendingQuestion(
    orgId: string,
    conversationId: string,
    pendingQuestionId: string,
    audience: CopilotAudience,
    actorId: string,
  ): Promise<(CopilotPendingQuestion & { originating_request: string }) | null>;
  persistExchange(input: {
    actorId: string;
    orgId: string;
    playerId: string;
    conversationId: string;
    question: string;
    answer: CopilotStructuredAnswer | null;
    renderedAnswer: string | null;
    qualityStatus: DevelopmentQualityStatus | "rejected";
    cutoff: string;
    generationMode: CopilotGenerationMode;
    provider: string;
    modelIdentifier: string | null;
    promptVersion: string;
    generatorVersion: string;
    generationStatus: "succeeded" | "failed" | "rejected";
    safeErrorCode: string | null;
    idempotencyKey: string;
    citations: CopilotCitation[];
    attempt: Record<string, unknown>;
    audience: CopilotAudience;
    pendingQuestionId: string | null;
    pendingResponseMode: "answer" | "skip" | "use_available_evidence" | null;
  }): Promise<{
    user_message: CopilotMessage;
    assistant_message: CopilotMessage;
    pending_question: CopilotPendingQuestion | null;
    reused: boolean;
  }>;
  submitFeedback(input: {
    actorId: string;
    orgId: string;
    playerId: string;
    conversationId: string;
    messageId: string;
    feedbackType: string;
    note: string | null;
    audience: CopilotAudience;
  }): Promise<Record<string, unknown>>;
  createParentDraft(input: {
    actorId: string;
    orgId: string;
    playerId: string;
    conversationId: string | null;
    sourceMessageId: string | null;
    content: ParentUpdateContent;
    renderedText: string;
    cutoff: string;
    generationMode: Exclude<CopilotGenerationMode, "unavailable">;
    provider: string;
    modelIdentifier: string | null;
    promptVersion: string;
    generatorVersion: string;
    idempotencyKey: string;
  }): Promise<ParentUpdateDraft>;
  listParentDrafts(
    orgId: string,
    playerIds: string[],
    playerId: string | undefined,
  ): Promise<ParentUpdateDraft[]>;
  parentDraft(
    orgId: string,
    draftId: string,
    playerIds: string[],
  ): Promise<
    { draft: ParentUpdateDraft; review_events: ParentDraftReviewEvent[] } | null
  >;
  reviewParentDraft(input: {
    actorId: string;
    orgId: string;
    draftId: string;
    action: string;
    content: ParentUpdateContent | null;
    renderedText: string | null;
    note: string | null;
  }): Promise<ParentUpdateDraft>;
  usage(
    orgId: string,
    actorId: string,
    audience: CopilotAudience,
  ): Promise<Omit<UsageSummary, "limits">>;
}

const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const datePattern = /^\d{4}-\d{2}-\d{2}$/;

function isObject(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function hasExactKeys(
  value: Record<string, unknown>,
  keys: readonly string[],
): boolean {
  const allowed = new Set(keys);
  return Object.keys(value).length === allowed.size &&
    Object.keys(value).every((key) => allowed.has(key));
}

function clean(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function validUuid(value: string): boolean {
  return uuidPattern.test(value);
}

function exactDate(value: string): number | null {
  if (!datePattern.test(value)) return null;
  const parsed = Date.parse(`${value}T00:00:00.000Z`);
  return Number.isFinite(parsed) &&
      new Date(parsed).toISOString().slice(0, 10) === value
    ? parsed
    : null;
}

function rawJSON(
  status: number,
  body: Record<string, unknown>,
  requestId?: string,
): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "content-type": "application/json",
      ...(requestId ? { "x-request-id": requestId } : {}),
    },
  });
}

const safeMessages: Record<string, string> = {
  invalid_auth: "Your session could not be verified. Sign in and try again.",
  invalid_json: "The Copilot request could not be read.",
  request_too_large: "The Copilot request is too large.",
  invalid_request: "The Copilot request is invalid.",
  unsupported_action: "That Copilot action is not supported.",
  organization_unavailable: "The selected organization is unavailable.",
  staff_access_required: "Active organization staff access is required.",
  player_access_denied: "You do not have access to this player.",
  conversation_not_found: "The Copilot conversation is unavailable.",
  message_not_found: "The Copilot message is unavailable.",
  parent_draft_not_found: "The parent update draft is unavailable.",
  provider_unavailable:
    "Conversational generation is not configured. Deterministic questions remain available.",
  provider_timeout:
    "The generation provider did not respond in time. Please try again.",
  unsupported_without_provider:
    "That conversational question needs a configured generation provider. Supported deterministic questions remain available.",
  deterministic_intent_unrecognized:
    "Home Plate could not match that question to a supported deterministic answer. Try one of the suggested questions.",
  evidence_unavailable: "No authorized evidence is available for that request.",
  unsafe_question:
    "Copilot cannot provide a diagnosis or guaranteed outcome. Review the available evidence and consult an appropriate qualified professional when needed.",
  unsafe_output:
    "The generated answer did not pass Home Plate safety validation.",
  unsafe_generated_content:
    "The generated answer did not pass Home Plate safety validation.",
  invalid_evidence_reference:
    "The generated answer referenced evidence outside the authorized evidence pack.",
  invalid_structured_output:
    "The provider returned an answer Home Plate could not validate.",
  structured_output_invalid:
    "The generated answer did not match Home Plate's validated answer contract.",
  persistence_failed: "The answer could not be saved. Retry the same request.",
  rate_limited:
    "The development usage limit has been reached. Try again later.",
  stale_context:
    "That Copilot context is no longer current. Review the latest conversation and try again.",
  usage_limit_reached:
    "The development usage limit has been reached. Try again later.",
  pending_question_stale:
    "That Copilot question is no longer active. Review the latest question and try again.",
  pending_question_response_invalid:
    "That response does not match the active Copilot question.",
  invalid_parent_draft_transition:
    "That parent draft action is not valid for its current status.",
  copilot_unavailable:
    "Player Development Copilot could not complete the request.",
};

async function readBoundedObject(
  request: Request,
): Promise<Record<string, unknown>> {
  const declared = Number(request.headers.get("content-length") ?? "0");
  if (Number.isFinite(declared) && declared > COPILOT_MAX_REQUEST_BYTES) {
    throw new Error("request_too_large");
  }
  if (!request.body) throw new Error("invalid_json");
  const reader = request.body.getReader();
  const chunks: Uint8Array[] = [];
  let total = 0;
  while (true) {
    const { value, done } = await reader.read();
    if (done) break;
    if (!value) continue;
    total += value.byteLength;
    if (total > COPILOT_MAX_REQUEST_BYTES) {
      await reader.cancel();
      throw new Error("request_too_large");
    }
    chunks.push(value);
  }
  const bytes = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }
  const parsed = JSON.parse(new TextDecoder().decode(bytes));
  if (!isObject(parsed)) throw new Error("invalid_json");
  return parsed;
}

const playerEvidenceSourceAllowlist = new Set([
  "sd_testing_entries",
  "player_development_import",
  "sd_player_metric_observations",
  "sd_program_assignments",
  "sd_daily_logs_window",
  "sd_bp_sessions",
  "sd_development_reports",
  "sd_development_alerts",
]);
const privateEvidencePattern =
  /(?:coach[_ ]?note|staff|private|confidential|roster|ranking|comparison|parent|finance|billing|payment|recruit|storage|signed[_ ]?url|gps|device|serial|secret|token)/i;
const playerMetadataKeys = new Set([
  "source_type",
  "source_system",
  "provider",
  "import_provider",
  "verification_status",
  "original_unit",
  "canonical_unit",
  "parser_version",
  "mapping_version",
  "source_row_number",
  "demo_seed",
  "demo_version",
]);
const playerSnapshotKeys = new Set([
  "metric_key",
  "value",
  "unit",
  "observed_at",
  "prior_value",
  "change",
  "sample_size",
  "freshness",
  "assignment_id",
  "template_id",
  "start_date",
  "ended_at",
  "completion_inferred",
  "demo_seed",
  "demo_version",
  "verification_status",
]);

function safeEvidenceObject(
  value: Record<string, unknown>,
  allowed: Set<string>,
): Record<string, unknown> {
  return Object.fromEntries(
    Object.entries(value).filter(([key, item]) =>
      allowed.has(key) && !privateEvidencePattern.test(key) &&
      (typeof item !== "string" || !privateEvidencePattern.test(item))
    ),
  );
}

/** Final fail-closed boundary applied before Player Copilot provider invocation. */
export function playerVisibleEvidencePack(
  pack: DevelopmentEvidencePack,
): DevelopmentEvidencePack {
  const evidence = pack.evidence.filter((item) =>
    playerEvidenceSourceAllowlist.has(item.source_entity_type) &&
    !privateEvidencePattern.test(item.section_key) &&
    !privateEvidencePattern.test(item.display_label) &&
    !privateEvidencePattern.test(item.explanation)
  ).map((item) => ({
    ...item,
    source_metadata: safeEvidenceObject(
      item.source_metadata,
      playerMetadataKeys,
    ),
    evidence_snapshot: safeEvidenceObject(
      item.evidence_snapshot,
      playerSnapshotKeys,
    ),
  }));
  const visibleKeys = new Set(evidence.map((item) => item.evidence_key));
  const trends = pack.trends.filter((trend) =>
    trend.evidence_keys.length > 0 &&
    trend.evidence_keys.every((key) => visibleKeys.has(key))
  );
  return {
    ...pack,
    report_type: "player_copilot_self_question",
    evidence,
    trends,
    missing_data_warnings: pack.missing_data_warnings.filter((item) =>
      !privateEvidencePattern.test(item)
    ),
    stale_data_warnings: pack.stale_data_warnings.filter((item) =>
      !privateEvidencePattern.test(item)
    ),
    unit_conflicts: pack.unit_conflicts.filter((item) =>
      !privateEvidencePattern.test(item)
    ),
    low_sample_warnings: pack.low_sample_warnings.filter((item) =>
      !privateEvidencePattern.test(item)
    ),
  };
}

export function suggestedQuestions(
  pack: DevelopmentEvidencePack,
  audience: CopilotAudience = "coach",
): string[] {
  const questions = audience === "player"
    ? ["What changed in the last 30 days?", "What changed in the last 90 days?"]
    : ["What changed in the last 30 days?"];
  if (pack.trends.length > 0) {
    questions.push(`Explain the latest ${pack.trends[0].display_name} trend.`);
  }
  if (pack.stale_data_warnings.length > 0) {
    questions.push("Which testing data is stale?");
  }
  if (
    pack.evidence.some((item) =>
      item.source_metadata?.provider === "rapsodo" ||
      item.source_metadata?.import_provider === "rapsodo"
    )
  ) {
    questions.push(
      audience === "player"
        ? "What did my latest Rapsodo session show?"
        : "Summarize the recent Rapsodo import.",
    );
  }
  questions.push("What evidence is missing?");
  if (audience === "player") {
    questions.push(
      "Which data is stale?",
      "What should I discuss with my coach?",
      "Which assigned programs appear in my record?",
    );
  } else {
    questions.push(
      "What should I review before the next session?",
      "Which active alerts deserve attention?",
    );
  }
  return [...new Set(questions)].slice(0, 6);
}

function canonicalStructuredAnswer(
  pack: DevelopmentEvidencePack,
  audience: CopilotAudience = "coach",
  overrides: Partial<CopilotStructuredAnswer> = {},
): CopilotStructuredAnswer {
  return {
    assistant_turn_type: "answer",
    pending_question: null,
    answer:
      "Home Plate does not have enough supported evidence to answer that question.",
    answer_quality: "unavailable",
    facts: [],
    calculations: [],
    interpretations: [],
    recommendations: [],
    missing_data: pack.missing_data_warnings.length > 0
      ? pack.missing_data_warnings
      : [
        "No supported player-development evidence is available in the selected window.",
      ],
    follow_up_questions: suggestedQuestions(pack, audience).slice(0, 3),
    warnings: [
      ...pack.stale_data_warnings,
      ...pack.unit_conflicts,
      ...pack.low_sample_warnings,
    ],
    proposed_actions: [],
    ...overrides,
    // These values are constructor-owned and cannot be mutated by overrides.
    schema_version: COPILOT_OUTPUT_SCHEMA_VERSION,
  };
}

function emptyAnswer(
  pack: DevelopmentEvidencePack,
  audience: CopilotAudience = "coach",
): CopilotStructuredAnswer {
  return canonicalStructuredAnswer(pack, audience);
}

function evidenceValue(item: DevelopmentEvidence): string {
  const value = item.normalized_numeric_value ?? item.raw_observed_value ??
    "recorded";
  return `${value}${item.unit ? ` ${item.unit}` : ""}`;
}

function normalizedQuestion(question: string): string {
  return question.normalize("NFKD").toLowerCase().replace(/[’']/g, "")
    .replace(/[_-]+/g, " ").replace(/[^a-z0-9.%/ ]+/g, " ")
    .replace(/\s+/g, " ").trim();
}

const metricAliases: ReadonlyArray<[RegExp, string]> = [
  [
    /\b(?:maximum|max) (?:exit velocity|exit velo|ev)\b|\bmax ev\b/,
    "hitting.max_exit_velocity",
  ],
  [/\b(?:latest )?ev(?: trend)?\b/, "hitting.max_exit_velocity"],
  [
    /\b(?:average|avg) (?:exit velocity|exit velo|ev)\b|\bavg ev\b/,
    "hitting.average_exit_velocity",
  ],
  [/\b(?:sprint|sprint time)\b/, "physical.sprint_time"],
  [/\b(?:squat|squat 1rm|back squat)\b/, "strength.squat_1rm"],
  [/\b(?:jump height|vertical jump)\b/, "physical.jump_height"],
  [/\b(?:release height)\b/, "pitching.release_height"],
  [/\b(?:body height|standing height|height)\b/, "physical.height"],
  [/\b(?:launch angle)\b/, "hitting.launch_angle"],
  [/\b(?:bat speed)\b/, "hitting.bat_speed"],
  [/\b(?:pitch velocity|pitch velo)\b/, "pitching.velocity"],
];

function resolveMetricKey(
  normalized: string,
  pack?: DevelopmentEvidencePack,
): string | null {
  for (const [pattern, key] of metricAliases) {
    if (pattern.test(normalized)) return key;
  }
  if (/\bexit velocity\b|\bexit velo\b/.test(normalized)) {
    const available = new Set(
      pack?.evidence.map((item) => item.canonical_metric_key).filter(Boolean),
    );
    if (available.has("hitting.max_exit_velocity")) {
      return "hitting.max_exit_velocity";
    }
    if (available.has("hitting.average_exit_velocity")) {
      return "hitting.average_exit_velocity";
    }
    return "hitting.max_exit_velocity";
  }
  for (const trend of pack?.trends ?? []) {
    const display = normalizedQuestion(trend.display_name);
    const canonical = normalizedQuestion(
      trend.canonical_metric_key.replaceAll(".", " "),
    );
    if (display && normalized.includes(display)) {
      return trend.canonical_metric_key;
    }
    if (canonical && normalized.includes(canonical)) {
      return trend.canonical_metric_key;
    }
  }
  for (const item of pack?.evidence ?? []) {
    if (!item.canonical_metric_key) continue;
    const display = normalizedQuestion(item.display_label);
    if (display && normalized.includes(display)) {
      return item.canonical_metric_key;
    }
  }
  return null;
}

export function classifyCopilotIntent(
  question: string,
  pack?: DevelopmentEvidencePack,
): CopilotIntentClassification {
  const q = normalizedQuestion(question);
  const result = (
    intent: CopilotDeterministicIntent | null,
    options: Partial<Omit<CopilotIntentClassification, "intent">> = {},
  ): CopilotIntentClassification => ({
    intent,
    period_days: null,
    metric_key: null,
    needs_clarification: false,
    ...options,
  });
  if (/\brapsodo\b|\brecent import\b|\blatest import\b/.test(q)) {
    return result("latest_import_summary");
  }
  if (
    /\bactive (?:objective )?alerts?\b|\balerts? deserve attention\b/.test(q)
  ) {
    return result("active_objective_alerts");
  }
  if (
    /\bassigned programs?\b|\bprogram assignments?\b|\bprograms? appear\b/.test(
      q,
    )
  ) {
    return result("assigned_programs");
  }
  if (
    /\bmissing\b|\bevidence gaps?\b|\bwhat data (?:do i|does .*?) not have\b/
      .test(q)
  ) {
    return result("missing_evidence");
  }
  if (/\bstale\b|\bout of date\b|\bneeds? retesting\b/.test(q)) {
    return result("stale_evidence");
  }
  if (
    /\bdata quality\b|\bunit conflicts?\b|\bsample (?:size|quality)\b/.test(q)
  ) {
    return result("data_quality_summary");
  }
  if (
    /\bwhich metrics? improved\b|\bwhat improved\b|\bimproving metrics?\b/.test(
      q,
    )
  ) {
    return result("improved_metrics");
  }
  if (
    /\bmetrics? (?:need|needs|requiring) attention\b|\bwhat needs attention\b|\bregress(?:ed|ing|ion)?\b/
      .test(q)
  ) {
    return result("attention_metrics");
  }
  if (/\bnext session\b|\breview before\b/.test(q)) {
    return result("next_session_review");
  }
  if (
    /\bdiscuss with (?:my|the) coach\b|\bask (?:my|the) coach\b|\bcoach discussion\b/
      .test(q)
  ) {
    return result("coach_discussion_prep");
  }
  const metricKey = resolveMetricKey(q, pack);
  if (
    metricKey ||
    /\bexplain (?:this|the|my|latest)? ?metric\b|\bmetric in (?:plain|simple) language\b/
      .test(q)
  ) {
    return result("metric_explanation", {
      metric_key: metricKey,
      needs_clarification: metricKey === null,
    });
  }
  if (/\b30 days?\b|\blast month\b/.test(q)) {
    return result("period_change_summary", { period_days: 30 });
  }
  if (/\b90 days?\b|\blast (?:three|3) months?\b/.test(q)) {
    return result("period_change_summary", { period_days: 90 });
  }
  if (/\bwhat changed\b|\brecent changes?\b|\btrend summary\b/.test(q)) {
    return result("period_change_summary");
  }
  if (
    /\boverall\b|\bhow (?:am i|is [a-z0-9 ]+) doing\b|\bsummar(?:y|ize) (?:my|the|recent|.*) development\b|\bevidence supports? this conclusion\b/
      .test(
        q,
      )
  ) {
    return result("overall_development_summary");
  }
  if (/\blatest evidence\b|\bavailable evidence\b/.test(q)) {
    return result("overall_development_summary");
  }
  return result(null);
}

function newestEvidence(
  evidence: DevelopmentEvidence[],
): DevelopmentEvidence[] {
  return [...evidence].sort((left, right) =>
    (right.observation_date ?? "").localeCompare(left.observation_date ?? "") ||
    left.evidence_key.localeCompare(right.evidence_key)
  );
}

function providerName(item: DevelopmentEvidence): string {
  return clean(item.source_metadata?.provider) ||
    clean(item.source_metadata?.import_provider) || "Home Plate";
}

function verificationName(item: DevelopmentEvidence): string {
  return clean(item.source_metadata?.verification_status) || "not specified";
}

function metricDirection(ruleId: string | null): string {
  if (ruleId?.includes("higher_is_better")) return "higher is preferred";
  if (ruleId?.includes("lower_is_better")) return "lower is preferred";
  if (ruleId?.includes("target_range")) {
    return "the configured range is preferred";
  }
  return "the preferred direction is context-dependent or informational";
}

function trendClaims(
  trends: DevelopmentEvidencePack["trends"],
): {
  calculations: CopilotCalculation[];
  interpretations: CopilotInterpretation[];
} {
  const calculations: CopilotCalculation[] = [];
  const interpretations: CopilotInterpretation[] = [];
  for (const trend of trends.slice(0, 5)) {
    calculations.push({
      text: trend.prior_value === null
        ? `${trend.display_name} has ${trend.sample_count} supported observation${
          trend.sample_count === 1 ? "" : "s"
        }; no supported prior comparison is available.`
        : `${trend.display_name} changed from ${trend.prior_value} to ${trend.latest_value}${
          trend.unit ? ` ${trend.unit}` : ""
        } across ${trend.sample_count} supported observations.`,
      evidence_ids: trend.evidence_keys,
      rule_id: trend.rule_id,
    });
    interpretations.push({
      text:
        `${trend.display_name} is ${trend.interpretation} under the configured ${
          metricDirection(trend.rule_id)
        } rule. This describes the cited measurements and does not explain why they changed.`,
      evidence_ids: trend.evidence_keys,
      confidence: trend.quality === "sufficient" ? 0.85 : 0.55,
    });
  }
  return { calculations, interpretations };
}

function metricClarificationTurn(
  pack: DevelopmentEvidencePack,
  audience: CopilotAudience,
  now: Date,
): CopilotStructuredAnswer {
  const choices = [...new Set(pack.trends.map((trend) => trend.display_name))]
    .slice(0, 5);
  if (choices.length === 0) {
    choices.push("Height", "Maximum Exit Velocity", "Sprint Time");
  }
  if (choices.length < 6) choices.push("Use available evidence");
  return canonicalStructuredAnswer(pack, audience, {
    assistant_turn_type: "clarification_question",
    answer: "Which supported metric would you like me to explain?",
    answer_quality: pack.quality_status,
    pending_question: {
      question_type: "clarification_question",
      why_asked:
        "A specific supported metric is required before Home Plate can provide a player-specific value or trend.",
      expected_response_type: "choice",
      choices,
      related_evidence_ids: [],
      is_optional: true,
      may_later_be_saved: false,
      expires_at: new Date(now.getTime() + 24 * 60 * 60 * 1000).toISOString(),
    },
    missing_data: pack.missing_data_warnings.length > 0
      ? pack.missing_data_warnings
      : pack.evidence.length === 0
      ? [
        "No supported player-development evidence is available in the selected window.",
      ]
      : [],
    follow_up_questions: [],
  });
}

export function deterministicDialogueTurn(
  question: string,
  pack: DevelopmentEvidencePack,
  audience: CopilotAudience,
  now: Date = new Date(),
): CopilotStructuredAnswer | null {
  const q = question.trim().toLowerCase();
  const expiresAt = new Date(now.getTime() + 24 * 60 * 60 * 1000)
    .toISOString();
  const turn = (
    answer: string,
    draft: CopilotPendingQuestionDraft,
    type: CopilotAssistantTurnType = draft.question_type,
  ): CopilotStructuredAnswer => ({
    ...emptyAnswer(pack, audience),
    assistant_turn_type: type,
    pending_question: draft,
    answer,
    answer_quality: pack.quality_status,
    missing_data: pack.missing_data_warnings,
    follow_up_questions: [],
  });
  const classification = classifyCopilotIntent(question, pack);
  if (
    classification.intent === "metric_explanation" &&
    classification.needs_clarification
  ) return metricClarificationTurn(pack, audience, now);
  if (
    /\b(save|record|create|update|send|message|request testing|generate (?:a )?parent draft)\b/i
      .test(question)
  ) {
    return turn(
      "I can preview that request, but no official record will change from this conversation. Do you want to confirm the preview for a separately authorized workflow?",
      {
        question_type: "confirmation_question",
        why_asked:
          "Any proposed mutation requires explicit confirmation and backend reauthorization before a dedicated audited tool may run.",
        expected_response_type: "confirmation",
        choices: ["Confirm preview", "Cancel"],
        related_evidence_ids: [],
        is_optional: false,
        may_later_be_saved: false,
        expires_at: expiresAt,
      },
      "action_preview",
    );
  }
  if (
    ["help me improve", "tell me more", "analyze me"]
      .includes(q)
  ) {
    return turn(
      audience === "player"
        ? "Which development area would you like me to focus on?"
        : "Which development domain should this analysis emphasize?",
      {
        question_type: "clarification_question",
        why_asked:
          "The request does not identify a metric or development domain, and choosing one without you could produce the wrong analysis.",
        expected_response_type: "choice",
        choices: audience === "player"
          ? [
            "Hitting",
            "Pitching",
            "Physical testing",
            "Use available evidence",
          ]
          : [
            "Hitting",
            "Pitching",
            "Physical testing",
            "Use available evidence",
          ],
        related_evidence_ids: [],
        is_optional: true,
        may_later_be_saved: false,
        expires_at: expiresAt,
      },
    );
  }
  if (
    /\b(that|the|latest) session\b/.test(q) &&
    !/\b(rapsodo|trackman|batting practice|bp|testing|hitting|pitching)\b/.test(
      q,
    )
  ) {
    return turn(
      "Which session type do you mean?",
      {
        question_type: "evidence_gap_question",
        why_asked:
          "Session type matters because Home Plate may contain testing, batting-practice, and imported device sessions with different measurements.",
        expected_response_type: "choice",
        choices: [
          "Rapsodo",
          "TrackMan",
          "Batting practice",
          "Use available evidence",
        ],
        related_evidence_ids: [],
        is_optional: true,
        may_later_be_saved: false,
        expires_at: expiresAt,
      },
    );
  }
  if (/\b(reflect|ask me a question|what should i think about)\b/.test(q)) {
    const evidenceIds = pack.trends[0]?.evidence_keys.slice(0, 3) ?? [];
    return turn(
      audience === "player"
        ? "What felt different in your most recent session?"
        : "Was there a documented intervention during this evidence window?",
      {
        question_type: "reflection_question",
        why_asked: audience === "player"
          ? "Your reflection may help you prepare context for a coach, but it will not be treated as a verified metric or medical evidence."
          : "Documented context may help a coach interpret the cited evidence without changing the underlying measurements.",
        expected_response_type: "free_text",
        choices: [],
        related_evidence_ids: evidenceIds,
        is_optional: true,
        may_later_be_saved: true,
        expires_at: expiresAt,
      },
    );
  }
  return null;
}

export function deterministicAnswer(
  question: string,
  pack: DevelopmentEvidencePack,
  audience: CopilotAudience = "coach",
): CopilotStructuredAnswer | null {
  const classification = classifyCopilotIntent(question, pack);
  if (!classification.intent || classification.needs_clarification) return null;
  return constructDeterministicAnswer(classification, pack, audience);
}

/** The only constructor for supported deterministic answer turns. */
export function constructDeterministicAnswer(
  classification: CopilotIntentClassification,
  pack: DevelopmentEvidencePack,
  audience: CopilotAudience = "coach",
): CopilotStructuredAnswer {
  const intent = classification.intent;
  if (!intent || classification.needs_clarification) {
    throw new Error("deterministic_intent_unrecognized");
  }
  const base = (overrides: Partial<CopilotStructuredAnswer>) =>
    canonicalStructuredAnswer(pack, audience, overrides);
  const warnings = [
    ...pack.stale_data_warnings,
    ...pack.unit_conflicts,
    ...pack.low_sample_warnings,
  ];
  if (intent === "missing_evidence") {
    const missing = pack.missing_data_warnings.length > 0
      ? pack.missing_data_warnings
      : ["No required evidence gap was identified in the selected window."];
    return base({
      answer: pack.missing_data_warnings.length > 0
        ? `Home Plate found ${pack.missing_data_warnings.length} explicit evidence limitation${
          pack.missing_data_warnings.length === 1 ? "" : "s"
        }. Missing evidence is not evidence of poor performance.`
        : "Home Plate did not identify an explicit evidence gap in this window. Source coverage is still bounded to authorized Home Plate records.",
      answer_quality: pack.quality_status,
      missing_data: missing,
      warnings,
    });
  }
  if (intent === "stale_evidence") {
    const stale = newestEvidence(
      pack.evidence.filter((item) => item.freshness === "stale"),
    ).slice(0, 5);
    return base({
      answer: stale.length > 0
        ? `${stale.length} cited evidence record${
          stale.length === 1 ? " is" : "s are"
        } stale in this window.`
        : "No supported evidence record is currently marked stale in this window.",
      answer_quality: pack.quality_status,
      facts: stale.map((item) => ({
        text: `${item.display_label} was last observed on ${
          item.observation_date?.slice(0, 10) ?? "an unavailable date"
        } and is marked stale.`,
        evidence_ids: [item.evidence_key],
      })),
      missing_data: [],
      warnings,
    });
  }
  if (intent === "active_objective_alerts") {
    const alerts = newestEvidence(
      pack.evidence.filter((item) =>
        item.source_entity_type === "sd_development_alerts" &&
        (item.evidence_snapshot.status === undefined ||
          item.evidence_snapshot.status === "active")
      ),
    ).slice(0, 5);
    if (alerts.length === 0) {
      return base({
        answer:
          "No active objective alerts were found for this evidence window.",
        answer_quality: pack.quality_status,
        missing_data: [],
        warnings,
      });
    }
    return base({
      answer: `${alerts.length} active ${
        audience === "player" ? "player-visible" : "staff"
      } objective alert${alerts.length === 1 ? " is" : "s are"} available.`,
      answer_quality: pack.quality_status,
      facts: alerts.map((item) => ({
        text: `${item.display_label} is active as of ${
          item.observation_date?.slice(0, 10) ?? "an unavailable date"
        }.`,
        evidence_ids: [item.evidence_key],
      })),
      missing_data: [],
      warnings,
    });
  }
  if (intent === "assigned_programs") {
    const programs = newestEvidence(
      pack.evidence.filter((item) =>
        item.source_entity_type === "sd_program_assignments"
      ),
    ).slice(0, 5);
    return base({
      answer: programs.length > 0
        ? `${programs.length} assigned program record${
          programs.length === 1 ? " is" : "s are"
        } available. Assignment does not prove attendance or completion.`
        : "No assigned program record was found in this evidence window. Assignment, attendance, and completion are separate facts.",
      answer_quality: pack.quality_status,
      facts: programs.map((item) => ({
        text: `A program assignment started on ${
          item.observation_date?.slice(0, 10) ?? "an unavailable date"
        }. This record proves assignment only, not attendance or completion.`,
        evidence_ids: [item.evidence_key],
      })),
      missing_data: programs.length > 0
        ? [
          "No authoritative attendance or program-completion ledger is available.",
        ]
        : pack.missing_data_warnings,
      warnings,
    });
  }
  if (intent === "latest_import_summary") {
    const imported = newestEvidence(
      pack.evidence.filter((item) =>
        item.source_entity_type.includes("import") ||
        providerName(item).toLowerCase() === "rapsodo"
      ),
    );
    const rapsodo = imported.filter((item) =>
      providerName(item).toLowerCase() === "rapsodo"
    ).slice(0, 8);
    if (rapsodo.length === 0) {
      return base({
        answer:
          "No committed authorized Rapsodo observations were found in this evidence window.",
        answer_quality: pack.quality_status,
        missing_data: [
          "Rapsodo fields that are not mapped to an authorized canonical metric are unavailable to Copilot.",
        ],
        warnings,
      });
    }
    const dates = rapsodo.map((item) => item.observation_date?.slice(0, 10))
      .filter((value): value is string => Boolean(value)).sort();
    return base({
      answer: `${rapsodo.length} committed Rapsodo observation${
        rapsodo.length === 1 ? " is" : "s are"
      } available${
        dates.length ? ` from ${dates[0]} through ${dates.at(-1)}` : ""
      }. Only mapped metrics are summarized.`,
      answer_quality: pack.quality_status,
      facts: rapsodo.map((item) => {
        const originalUnit = clean(item.source_metadata?.original_unit);
        const normalized = evidenceValue(item);
        const original = originalUnit && originalUnit !== item.unit
          ? `${
            item.raw_observed_value ?? "recorded"
          } ${originalUnit}; normalized ${normalized}`
          : normalized;
        return {
          text: `${item.display_label}: ${original} on ${
            item.observation_date?.slice(0, 10) ?? "an unavailable date"
          }; provider Rapsodo; verification ${verificationName(item)}; sample ${
            item.sample_size ?? 1
          }; freshness ${item.freshness}.`,
          evidence_ids: [item.evidence_key],
        };
      }),
      missing_data: [
        "Unmapped or ambiguous Rapsodo fields are excluded; device serials, GPS, and storage paths are never exposed.",
      ],
      warnings,
    });
  }
  if (intent === "metric_explanation") {
    const key = classification.metric_key;
    const metricEvidence = newestEvidence(
      pack.evidence.filter((item) => item.canonical_metric_key === key),
    );
    const latest = metricEvidence[0];
    const trend = pack.trends.find((item) => item.canonical_metric_key === key);
    const label = trend?.display_name ?? latest?.display_label ??
      key?.split(".").at(-1)?.replaceAll("_", " ") ?? "The requested metric";
    if (!latest) {
      return base({
        answer:
          `${label} is a supported metric, but no authorized observation is available in this evidence window.`,
        answer_quality: "unavailable",
        missing_data: [`No supported ${label} observation is available.`],
        warnings,
      });
    }
    const claims = trendClaims(trend ? [trend] : []);
    return base({
      answer: `${label} is reported as a measured player-development value. ${
        metricDirection(trend?.rule_id ?? latest.deterministic_rule_id)
      }; context and measurement protocol still matter.`,
      answer_quality: latest.quality,
      facts: [{
        text: `The latest supported ${label} value is ${
          evidenceValue(latest)
        } on ${
          latest.observation_date?.slice(0, 10) ?? "an unavailable date"
        }; source ${providerName(latest)}; verification ${
          verificationName(latest)
        }; sample ${
          latest.sample_size ?? trend?.sample_count ?? 1
        }; freshness ${latest.freshness}.`,
        evidence_ids: [latest.evidence_key],
      }],
      calculations: claims.calculations,
      interpretations: claims.interpretations,
      missing_data: trend
        ? pack.missing_data_warnings
        : [`No supported prior ${label} comparison is available.`],
      warnings,
    });
  }
  if (intent === "data_quality_summary") {
    const limitations = [
      ...pack.unit_conflicts,
      ...pack.low_sample_warnings,
      ...pack.stale_data_warnings,
      ...pack.missing_data_warnings,
    ];
    return base({
      answer: limitations.length > 0
        ? `Home Plate found ${limitations.length} bounded data-quality or coverage limitation${
          limitations.length === 1 ? "" : "s"
        }.`
        : "No explicit unit, sample, freshness, or coverage limitation was identified in this evidence window.",
      answer_quality: pack.quality_status,
      missing_data: pack.missing_data_warnings,
      warnings: [
        ...pack.unit_conflicts,
        ...pack.low_sample_warnings,
        ...pack.stale_data_warnings,
      ],
    });
  }

  let selectedTrends = pack.trends;
  if (intent === "improved_metrics") {
    selectedTrends = pack.trends.filter((trend) =>
      trend.interpretation === "improvement"
    );
  } else if (intent === "attention_metrics") {
    selectedTrends = pack.trends.filter((trend) =>
      trend.interpretation === "regression" || trend.quality !== "sufficient" ||
      trend.freshness === "stale"
    );
  }
  selectedTrends = selectedTrends.slice(
    0,
    intent === "overall_development_summary" ? 3 : 5,
  );
  const claims = trendClaims(selectedTrends);
  const latest = newestEvidence(
    pack.evidence.filter((item) => item.canonical_metric_key !== null),
  ).slice(0, 3);
  const facts = latest.map((item) => ({
    text: `${item.display_label}: ${evidenceValue(item)} on ${
      item.observation_date?.slice(0, 10) ?? "an unavailable date"
    }; source ${providerName(item)}; verification ${verificationName(item)}.`,
    evidence_ids: [item.evidence_key],
  }));
  const reviewIntent = intent === "next_session_review" ||
    intent === "coach_discussion_prep" || intent === "attention_metrics";
  const actionIds = selectedTrends[0]?.evidence_keys ??
    latest.slice(0, 1).map((item) => item.evidence_key);
  const recommendations: CopilotRecommendation[] =
    reviewIntent && actionIds.length
      ? [{
        text: audience === "player"
          ? "Discuss the cited evidence and its limitations with a coach before requesting a program or official-record change."
          : "Review the cited evidence and its limitations with the player before changing a program or schedule.",
        evidence_ids: actionIds,
        requires_human_approval: true,
      }]
      : [];
  const proposedActions: CopilotProposedAction[] =
    reviewIntent && actionIds.length
      ? [{
        action_type: audience === "player"
          ? "prepare_coach_questions"
          : "discuss_metric_with_player",
        explanation: audience === "player"
          ? "Prepare questions about the cited measurements and evidence limitations."
          : "Discuss the cited measurements and evidence limitations with the player.",
        evidence_ids: actionIds,
        urgency: "low",
        confidence: 0.7,
        requires_approval: true,
      }]
      : [];
  const labels: Record<string, string> = {
    period_change_summary: "change summary",
    overall_development_summary: "overall development summary",
    improved_metrics: "improvement summary",
    attention_metrics: "attention summary",
    next_session_review: "next-session review",
    coach_discussion_prep: "coach-discussion preparation",
  };
  const answerText = selectedTrends.length > 0
    ? `This ${
      labels[intent] ?? "development summary"
    } is limited to ${selectedTrends.length} cited deterministic trend${
      selectedTrends.length === 1 ? "" : "s"
    }. It is not an overall score and does not establish causation.`
    : intent === "improved_metrics"
    ? "No supported metric is currently classified as improving in this evidence window."
    : intent === "attention_metrics"
    ? "No supported metric is currently classified as regressing, stale, or limited in this evidence window."
    : "There is not enough supported comparison evidence to calculate a trend summary. Missing evidence is not poor performance.";
  return base({
    answer: answerText,
    answer_quality: pack.quality_status,
    facts:
      intent === "overall_development_summary" || selectedTrends.length === 0
        ? facts
        : [],
    calculations: claims.calculations,
    interpretations: claims.interpretations,
    recommendations,
    missing_data: pack.missing_data_warnings.length > 0
      ? pack.missing_data_warnings
      : pack.evidence.length === 0
      ? [
        "No supported player-development evidence is available in the selected window.",
      ]
      : [],
    warnings,
    proposed_actions: proposedActions,
  });
}

export class DeterministicCopilotProvider implements CopilotGenerationProvider {
  readonly provider = "deterministic_template";
  readonly modelIdentifier = null;
  readonly mode = "deterministic" as const;
  readonly generatorVersion = COPILOT_GENERATOR_VERSION;
  constructor(private readonly pack: DevelopmentEvidencePack) {}
  generate(context: CopilotPromptContext): Promise<unknown> {
    return Promise.resolve(
      deterministicAnswer(context.question, this.pack, context.audience),
    );
  }
}

function stringArray(value: unknown, max = 20): string[] | null {
  if (!Array.isArray(value) || value.length > max) return null;
  const result = value.map(clean);
  return result.every((item) => item.length <= 500) ? result : null;
}

function evidenceIds(value: unknown): string[] | null {
  const result = stringArray(value, 20);
  return result && result.every((item) => item.length > 0 && item.length <= 300)
    ? result
    : null;
}

export function validateStructuredAnswer(
  raw: unknown,
  pack: DevelopmentEvidencePack,
  limits: CopilotLimits = COPILOT_DEFAULT_LIMITS,
  audience: CopilotAudience = "coach",
): { answer: CopilotStructuredAnswer; citations: CopilotCitation[] } {
  if (
    !isObject(raw) ||
    !hasExactKeys(raw, [
      "schema_version",
      "assistant_turn_type",
      "pending_question",
      "answer",
      "answer_quality",
      "facts",
      "calculations",
      "interpretations",
      "recommendations",
      "missing_data",
      "follow_up_questions",
      "warnings",
      "proposed_actions",
    ]) ||
    clean(raw.schema_version) !== COPILOT_OUTPUT_SCHEMA_VERSION
  ) throw new Error("invalid_structured_output");
  const answerText = clean(raw.answer);
  const quality = clean(raw.answer_quality) as DevelopmentQualityStatus;
  const assistantTurnType = clean(
    raw.assistant_turn_type,
  ) as CopilotAssistantTurnType;
  const allowedTurnTypes: CopilotAssistantTurnType[] = [
    "answer",
    "clarification_question",
    "evidence_gap_question",
    "reflection_question",
    "confirmation_question",
    "suggested_follow_up",
    "action_preview",
    "safe_refusal",
  ];
  if (
    !answerText ||
    answerText.length > limits.outputCharacters ||
    !allowedTurnTypes.includes(assistantTurnType) ||
    !["sufficient", "limited", "stale", "conflicting", "unavailable"].includes(
      quality,
    )
  ) throw new Error("invalid_structured_output");
  const evidenceMap = new Map(
    pack.evidence.map((item) => [item.evidence_key, item]),
  );
  const citationMap = new Map<string, CopilotCitation>();
  let pendingQuestion: CopilotPendingQuestionDraft | null = null;
  if (raw.pending_question !== null) {
    if (
      !isObject(raw.pending_question) ||
      !hasExactKeys(raw.pending_question, [
        "question_type",
        "why_asked",
        "expected_response_type",
        "choices",
        "related_evidence_ids",
        "is_optional",
        "may_later_be_saved",
        "expires_at",
      ])
    ) throw new Error("invalid_structured_output");
    const questionType = clean(
      raw.pending_question.question_type,
    ) as CopilotPendingQuestionDraft["question_type"];
    const expectedResponseType = clean(
      raw.pending_question.expected_response_type,
    ) as CopilotPendingQuestionDraft["expected_response_type"];
    const choices = stringArray(raw.pending_question.choices, 6);
    const relatedIds = evidenceIds(raw.pending_question.related_evidence_ids);
    const whyAsked = clean(raw.pending_question.why_asked);
    const expiresAt = clean(raw.pending_question.expires_at);
    if (
      ![
        "clarification_question",
        "evidence_gap_question",
        "reflection_question",
        "confirmation_question",
      ].includes(questionType) ||
      !["choice", "free_text", "confirmation"].includes(
        expectedResponseType,
      ) || !choices || choices.some((choice) => choice.length > 80) ||
      !relatedIds || relatedIds.some((id) => !evidenceMap.has(id)) ||
      !whyAsked || whyAsked.length > 500 ||
      !Number.isFinite(Date.parse(expiresAt)) ||
      typeof raw.pending_question.is_optional !== "boolean" ||
      typeof raw.pending_question.may_later_be_saved !== "boolean" ||
      /(?:diagnos|injury details|medical history|mental health|another player|coach note|private|secret|token|ignore previous|system prompt)/i
        .test(
          `${answerText} ${whyAsked} ${choices.join(" ")}`,
        )
    ) throw new Error("invalid_structured_output");
    if (
      assistantTurnType !== questionType &&
      !(assistantTurnType === "action_preview" &&
        questionType === "confirmation_question")
    ) throw new Error("invalid_structured_output");
    if (
      (expectedResponseType === "free_text" && choices.length !== 0) ||
      (expectedResponseType === "choice" && choices.length < 2) ||
      (expectedResponseType === "confirmation" && choices.length !== 2)
    ) throw new Error("invalid_structured_output");
    pendingQuestion = {
      question_type: questionType,
      why_asked: whyAsked,
      expected_response_type: expectedResponseType,
      choices,
      related_evidence_ids: relatedIds,
      is_optional: raw.pending_question.is_optional,
      may_later_be_saved: raw.pending_question.may_later_be_saved,
      expires_at: expiresAt,
    };
  } else if (
    [
      "clarification_question",
      "evidence_gap_question",
      "reflection_question",
      "confirmation_question",
      "action_preview",
    ].includes(assistantTurnType)
  ) {
    throw new Error("invalid_structured_output");
  }

  function validateMeasurements(text: string, ids: string[]): void {
    const cited = ids.map((id) => evidenceMap.get(id)).filter(
      (item): item is DevelopmentEvidence => item !== undefined,
    );
    const units = new Set(
      cited.map((item) => clean(item.unit).toLowerCase()).filter(Boolean),
    );
    if (units.size === 0) return;
    const allowedValues: number[] = [];
    for (const item of cited) {
      if (item.normalized_numeric_value !== null) {
        allowedValues.push(item.normalized_numeric_value);
      }
      const rawValue = Number(item.raw_observed_value);
      if (Number.isFinite(rawValue)) allowedValues.push(rawValue);
      if (item.comparison_value !== null) {
        allowedValues.push(item.comparison_value);
      }
    }
    for (const trend of pack.trends) {
      if (!trend.evidence_keys.some((id) => ids.includes(id))) continue;
      for (
        const value of [
          trend.latest_value,
          trend.prior_value,
          trend.absolute_change,
          trend.percentage_change,
          trend.rolling_average,
          trend.recent_window_average,
          trend.prior_window_average,
          trend.best_value,
          trend.worst_value,
        ]
      ) {
        if (value !== null && Number.isFinite(value)) allowedValues.push(value);
      }
    }
    const measurementPattern = /(-?\d+(?:\.\d+)?)\s*([a-z%°/]+)/gi;
    for (const match of text.matchAll(measurementPattern)) {
      const unit = match[2].toLowerCase();
      if (!units.has(unit)) continue;
      const stated = Number(match[1]);
      if (
        !allowedValues.some((value) =>
          Math.abs(value - stated) <= Math.max(0.01, Math.abs(value) * 0.005)
        )
      ) throw new Error("invalid_structured_output");
    }
  }

  function claims(
    value: unknown,
    section: string,
    additionalKeys: string[] = [],
  ): CopilotClaim[] {
    if (!Array.isArray(value) || value.length > 30) {
      throw new Error("invalid_structured_output");
    }
    return value.map((entry, index) => {
      if (
        !isObject(entry) ||
        !hasExactKeys(entry, ["text", "evidence_ids", ...additionalKeys])
      ) throw new Error("invalid_structured_output");
      const text = clean(entry.text);
      const ids = evidenceIds(entry.evidence_ids);
      if (!text || text.length > 1000 || !ids || ids.length === 0) {
        throw new Error("invalid_structured_output");
      }
      for (const id of ids) {
        const evidence = evidenceMap.get(id);
        if (!evidence) throw new Error("invalid_evidence_reference");
        const key = `${section}:${index}:${id}`;
        citationMap.set(key, {
          evidence_key: id,
          source_entity_type: evidence.source_entity_type,
          source_record_id: evidence.source_record_id,
          canonical_metric_key: evidence.canonical_metric_key,
          observed_value: evidence.raw_observed_value,
          normalized_value: evidence.normalized_numeric_value,
          unit: evidence.unit,
          observed_at: evidence.observation_date,
          display_label: evidence.display_label,
          explanation: evidence.explanation,
          section_key: section,
          claim_identifier: `${section}.${index}`,
          source_provider: clean(evidence.source_metadata?.provider) ||
            clean(evidence.source_metadata?.import_provider) || null,
          verification_status:
            clean(evidence.source_metadata?.verification_status) || null,
          deterministic_rule_id: evidence.deterministic_rule_id,
          evidence_snapshot: evidence.evidence_snapshot,
        });
      }
      validateMeasurements(text, ids);
      return { text, evidence_ids: ids };
    });
  }

  const facts = claims(raw.facts, "facts");
  const baseCalculations = claims(raw.calculations, "calculations", [
    "rule_id",
  ]);
  const rawCalculations = raw.calculations as Record<string, unknown>[];
  const calculations: CopilotCalculation[] = baseCalculations.map(
    (item, index) => {
      const ruleId = clean(rawCalculations[index].rule_id);
      if (
        !ruleId || !pack.trends.some((trend) =>
          trend.rule_id === ruleId &&
          item.evidence_ids.every((id) => trend.evidence_keys.includes(id))
        )
      ) throw new Error("invalid_structured_output");
      return { ...item, rule_id: ruleId };
    },
  );
  const baseInterpretations = claims(raw.interpretations, "interpretations", [
    "confidence",
  ]);
  const rawInterpretations = raw.interpretations as Record<string, unknown>[];
  const interpretations: CopilotInterpretation[] = baseInterpretations.map(
    (item, index) => {
      const confidence = Number(rawInterpretations[index].confidence);
      if (!Number.isFinite(confidence) || confidence < 0 || confidence > 1) {
        throw new Error("invalid_structured_output");
      }
      return { ...item, confidence };
    },
  );
  const baseRecommendations = claims(raw.recommendations, "recommendations", [
    "requires_human_approval",
  ]);
  const rawRecommendations = raw.recommendations as Record<string, unknown>[];
  const recommendations: CopilotRecommendation[] = baseRecommendations.map(
    (item, index) => {
      if (rawRecommendations[index].requires_human_approval !== true) {
        throw new Error("invalid_structured_output");
      }
      return { ...item, requires_human_approval: true };
    },
  );

  const missing = stringArray(raw.missing_data);
  const followUps = stringArray(raw.follow_up_questions, 3);
  const warnings = stringArray(raw.warnings);
  if (!missing || !followUps || !warnings) {
    throw new Error("invalid_structured_output");
  }
  const proposedActions: CopilotProposedAction[] = [];
  if (
    !Array.isArray(raw.proposed_actions) || raw.proposed_actions.length > 10
  ) throw new Error("invalid_structured_output");
  for (const entry of raw.proposed_actions) {
    if (
      !isObject(entry) ||
      !hasExactKeys(entry, [
        "action_type",
        "explanation",
        "evidence_ids",
        "urgency",
        "confidence",
        "requires_approval",
      ])
    ) throw new Error("invalid_structured_output");
    const actionType = clean(
      entry.action_type,
    ) as CopilotProposedAction["action_type"];
    const coachAllowed = [
      "schedule_retesting",
      "review_alert",
      "create_draft_coach_note",
      "generate_parent_update",
      "review_program_assignment",
      "investigate_data_quality",
      "discuss_metric_with_player",
    ];
    const playerAllowed = [
      "review_metric_with_coach",
      "request_retesting",
      "upload_updated_data",
      "complete_assigned_session",
      "review_assigned_program",
      "log_training_session",
      "discuss_data_quality",
      "prepare_coach_questions",
      "update_personal_goal",
    ];
    const allowed = audience === "player" ? playerAllowed : coachAllowed;
    const ids = evidenceIds(entry.evidence_ids);
    const confidence = Number(entry.confidence);
    const urgency = clean(entry.urgency) as CopilotProposedAction["urgency"];
    if (
      !allowed.includes(actionType) || !ids?.length || ids.some((id) =>
        !evidenceMap.has(id)
      ) || !["low", "medium", "high"].includes(urgency) ||
      !Number.isFinite(confidence) || confidence < 0 || confidence > 1 ||
      entry.requires_approval !== true
    ) throw new Error("invalid_structured_output");
    proposedActions.push({
      action_type: actionType,
      explanation: clean(entry.explanation).slice(0, 1000),
      evidence_ids: ids,
      urgency,
      confidence,
      requires_approval: true,
    });
  }
  const answer: CopilotStructuredAnswer = {
    schema_version: COPILOT_OUTPUT_SCHEMA_VERSION,
    assistant_turn_type: assistantTurnType,
    pending_question: pendingQuestion,
    answer: answerText,
    answer_quality: quality,
    facts,
    calculations,
    interpretations,
    recommendations,
    missing_data: missing,
    follow_up_questions: followUps,
    warnings,
    proposed_actions: proposedActions,
  };
  validateMeasurements(answerText, [...evidenceMap.keys()]);
  validateSafety(answer, pack);
  return { answer, citations: [...citationMap.values()] };
}

const blockedOutputPatterns = [
  /\b(diagnos(?:e|es|ed|ing|is)|torn|fracture|concussion|depression|anxiety disorder)\b/i,
  /\b(guarantee[ds]?|will definitely|certain to)\b/i,
  /\b(major league|mlb|professional player|pro player)\b.*\b(compare|same as|like)\b/i,
  /\b(chain[- ]of[- ]thought|hidden reasoning|internal reasoning)\b/i,
  /\b(caused by|proves? that)\b/i,
  /\b(?:the )?player (?:attended|completed)\b/i,
  /\battendance (?:is|was|has been) (?:confirmed|verified|recorded)\b/i,
  /\b(?:program|assignment) (?:is|was|has been) completed\b/i,
  /\b(private coach note|internal staff comment)\b/i,
];

export function unsafeQuestionCode(question: string): string | null {
  const q = question.toLowerCase();
  if (
    /\b(diagnos(?:e|ed|es|ing|is)?|injur(?:y|ies|ed)?|medical|mental health|concussion|torn|fracture)\b/
      .test(q)
  ) return "unsafe_question";
  if (
    /\b(guarantee|certain|definitely).*(improv|recruit|scholarship|draft)/.test(
      q,
    )
  ) return "unsafe_question";
  if (
    /\b(compare|like).*(mlb|major league|professional player|pro player)/.test(
      q,
    )
  ) return "unsafe_question";
  return null;
}

export function validateSafety(
  answer: CopilotStructuredAnswer,
  pack: DevelopmentEvidencePack,
): void {
  const serialized = JSON.stringify(answer);
  if (blockedOutputPatterns.some((pattern) => pattern.test(serialized))) {
    throw new Error("unsafe_generated_content");
  }
  if (
    serialized.includes(pack.organization_id) ||
    serialized.includes(pack.player_id)
  ) {
    // UUIDs may appear only inside evidence snapshots/citations, never in the user-visible structured answer.
    throw new Error("unsafe_generated_content");
  }
}

export function promptContext(
  question: string,
  pack: DevelopmentEvidencePack,
  maxEvidenceRows: number = COPILOT_DEFAULT_LIMITS.evidenceRows,
  audience: CopilotAudience = "coach",
): CopilotPromptContext {
  return {
    audience,
    prompt_version: audience === "player"
      ? PLAYER_COPILOT_PROMPT_VERSION
      : COPILOT_PROMPT_VERSION,
    safety_version: COPILOT_SAFETY_VERSION,
    output_schema_version: COPILOT_OUTPUT_SCHEMA_VERSION,
    question,
    organization_id: pack.organization_id,
    player_id: pack.player_id,
    player_name: pack.player_name,
    window_start: pack.window_start,
    window_end: pack.window_end,
    deterministic_calculations: pack.trends,
    untrusted_evidence: pack.evidence.slice(
      0,
      maxEvidenceRows,
    ).map((item) => ({
      evidence_id: item.evidence_key,
      source_type: item.source_entity_type,
      metric: item.canonical_metric_key,
      value: item.normalized_numeric_value ?? item.raw_observed_value,
      unit: item.unit,
      observed_at: item.observation_date,
      display_label: item.display_label,
      explanation: item.explanation,
    })),
  };
}

export function renderAnswer(
  answer: CopilotStructuredAnswer,
  maxCharacters: number = COPILOT_DEFAULT_LIMITS.outputCharacters,
): string {
  const lines = [answer.answer];
  const sections: Array<[string, CopilotClaim[]]> = [
    ["Facts", answer.facts],
    ["Calculations", answer.calculations],
    ["Interpretation", answer.interpretations],
    ["Recommendations", answer.recommendations],
  ];
  for (const [title, entries] of sections) {
    if (entries.length > 0) {
      lines.push(
        title,
        ...entries.map((item) => `• ${item.text}`),
      );
    }
  }
  if (answer.missing_data.length > 0) {
    lines.push(
      "Missing information",
      ...answer.missing_data.map((item) => `• ${item}`),
    );
  }
  return lines.join("\n\n").slice(0, maxCharacters);
}

export function deterministicParentDraft(
  pack: DevelopmentEvidencePack,
): ParentUpdateContent {
  const privateEvidencePattern =
    /(?:coach[_ ]?note|internal|staff comment|financial|storage|gps|device|serial|token|secret)/i;
  const recent = pack.evidence.filter((item) =>
    !privateEvidencePattern.test(item.source_entity_type) &&
    !privateEvidencePattern.test(item.display_label)
  ).slice(-3);
  const positives = pack.trends.filter((item) =>
    item.interpretation === "improvement"
  ).slice(0, 2);
  return {
    schema_version: "parent_update_draft.v1",
    recent_work: recent.length > 0
      ? `Recent supported records include ${
        recent.map((item) => item.display_label).join(", ")
      }.`
      : "No recent supported work records are available in the selected window.",
    positive_developments: positives.length > 0
      ? positives.map((item) =>
        `${item.display_name} is classified as improving by Home Plate's deterministic trend rule.`
      ).join(" ")
      : "The available evidence does not support a positive trend statement at this time.",
    current_focus:
      "The coach will determine the current development focus after reviewing the cited evidence.",
    consistency: pack.coverage.daily_logs > 0
      ? `${pack.coverage.daily_logs} player daily log${
        pack.coverage.daily_logs === 1 ? " is" : "s are"
      } available in this reporting window. Missing logs are not treated as missed work.`
      : "No supported consistency conclusion is available from daily logs in this window.",
    recent_testing:
      recent.filter((item) =>
        item.source_entity_type.includes("testing") || item.canonical_metric_key
      ).map((item) => `${item.display_label}: ${evidenceValue(item)}.`).join(
        " ",
      ) || "No recent supported testing measurement is available.",
    evidence_limitations: [
      ...pack.missing_data_warnings,
      ...pack.stale_data_warnings,
      ...pack.unit_conflicts,
      ...pack.low_sample_warnings,
    ].join(" ") ||
      "No specific evidence limitation was flagged; source coverage is still bounded to the selected reporting window.",
    upcoming_next_steps:
      "The coach will review the evidence and decide whether retesting or a player discussion is appropriate.",
  };
}

export function renderParentDraft(content: ParentUpdateContent): string {
  return [
    ["Recent work", content.recent_work],
    ["Positive developments", content.positive_developments],
    ["Current focus", content.current_focus],
    ["Consistency", content.consistency],
    ["Recent testing", content.recent_testing],
    ["Evidence limitations", content.evidence_limitations],
    ["Upcoming next steps", content.upcoming_next_steps],
  ].map(([title, text]) => `${title}\n${text}`).join("\n\n");
}

function validParentContent(value: unknown): value is ParentUpdateContent {
  if (!isObject(value) || value.schema_version !== "parent_update_draft.v1") {
    return false;
  }
  return [
    "recent_work",
    "positive_developments",
    "current_focus",
    "consistency",
    "recent_testing",
    "evidence_limitations",
    "upcoming_next_steps",
  ].every((key) =>
    clean(value[key]).length > 0 && clean(value[key]).length <= 4_000
  );
}

const actions = new Set([
  "create_conversation",
  "list_conversations",
  "get_conversation",
  "archive_conversation",
  "ask",
  "retry_message",
  "get_message",
  "submit_feedback",
  "create_parent_draft",
  "list_parent_drafts",
  "get_parent_draft",
  "update_parent_draft",
  "approve_parent_draft",
  "reject_parent_draft",
  "archive_parent_draft",
  "get_usage",
  "suggested_questions",
  "get_player_workspace",
]);

export type CopilotDiagnosticLogger = (
  event: string,
  metadata: Record<string, string | number | null>,
) => void;

const consoleCopilotDiagnosticLogger: CopilotDiagnosticLogger = (
  event,
  metadata,
) => {
  console.info(JSON.stringify({ event, ...metadata }));
};

function validationFailure(error: unknown): {
  code: string;
  stage: string;
} {
  const message = error instanceof Error ? error.message : "";
  if (message === "invalid_evidence_reference") {
    return { code: "invalid_evidence_reference", stage: "evidence" };
  }
  if (message === "unsafe_output" || message === "unsafe_generated_content") {
    return { code: "unsafe_generated_content", stage: "safety" };
  }
  if (
    message === "invalid_structured_output" ||
    message === "structured_output_invalid"
  ) {
    return { code: "structured_output_invalid", stage: "structured_output" };
  }
  if (message === "provider_rate_limited") {
    return { code: "rate_limited", stage: "provider" };
  }
  if (message === "provider_unavailable") {
    return { code: "provider_unavailable", stage: "provider" };
  }
  if (message === "provider_timeout") {
    return { code: "provider_timeout", stage: "provider" };
  }
  if (message === "deterministic_intent_unrecognized") {
    return { code: message, stage: "classification" };
  }
  return { code: "copilot_unavailable", stage: "generation" };
}

export function createPlayerDevelopmentCopilotHandler(
  store: CopilotStore,
  providerFactory: (pack: DevelopmentEvidencePack) => CopilotGenerationProvider,
  now: () => Date = () => new Date(),
  limits: CopilotLimits = COPILOT_DEFAULT_LIMITS,
  diagnostic: CopilotDiagnosticLogger = consoleCopilotDiagnosticLogger,
) {
  return async (request: Request): Promise<Response> => {
    const suppliedRequestId =
      clean(request.headers.get("x-client-request-id")) ||
      "";
    const requestId = validUuid(suppliedRequestId.toLowerCase())
      ? suppliedRequestId.toLowerCase()
      : crypto.randomUUID();
    const nonRetryableCodes = new Set([
      "invalid_auth",
      "invalid_json",
      "request_too_large",
      "invalid_request",
      "unsupported_action",
      "organization_unavailable",
      "staff_access_required",
      "player_access_denied",
      "conversation_not_found",
      "message_not_found",
      "parent_draft_not_found",
      "provider_unavailable",
      "unsupported_without_provider",
      "deterministic_intent_unrecognized",
      "evidence_unavailable",
      "unsafe_question",
      "stale_context",
      "pending_question_stale",
      "pending_question_response_invalid",
      "invalid_parent_draft_transition",
    ]);
    const failure = (
      status: number,
      code: string,
      data: Record<string, unknown> | null = null,
    ): Response =>
      rawJSON(status, {
        ok: false,
        answer: null,
        data,
        error: {
          code,
          message: safeMessages[code] ?? safeMessages.copilot_unavailable,
          retryable: !nonRetryableCodes.has(code) &&
            (status === 429 || status >= 500),
        },
        request_id: requestId,
      }, requestId);
    const json = (status: number, body: Record<string, unknown>): Response => {
      if (status < 200 || status >= 300) {
        const code = typeof body.error === "string"
          ? body.error
          : "copilot_unavailable";
        return failure(status, code, body);
      }
      const isAnswer = "user_message" in body && "assistant_message" in body;
      return rawJSON(status, {
        // Transitional top-level fields keep older clients operational while
        // the discriminated envelope becomes the authoritative contract.
        ...body,
        ok: true,
        answer: isAnswer ? body : null,
        data: isAnswer ? null : body,
        error: null,
        request_id: requestId,
      }, requestId);
    };
    if (request.method !== "POST") return failure(405, "unsupported_action");
    const actorId = await store.authenticate(request);
    if (!actorId) return failure(401, "invalid_auth");
    let body: Record<string, unknown>;
    try {
      body = await readBoundedObject(request);
    } catch (error) {
      const code =
        error instanceof Error && error.message === "request_too_large"
          ? "request_too_large"
          : "invalid_json";
      return failure(code === "request_too_large" ? 413 : 400, code);
    }
    const action = clean(body.action);
    const orgId = clean(body.org_id).toLowerCase();
    if (!actions.has(action)) return failure(400, "unsupported_action");
    if (!validUuid(orgId)) return failure(400, "invalid_request");
    try {
      if (await store.organizationStatus(orgId) !== "active") {
        return failure(404, "organization_unavailable");
      }
      const membership = await store.membership(orgId, actorId);
      if (!membership || membership.status !== "active") {
        return failure(403, "staff_access_required");
      }
      const parentDraftAction = action.includes("parent_draft");
      const audience = clean(body.audience) as CopilotAudience;
      diagnostic("copilot_request_received", {
        request_id: requestId,
        action,
        audience: ["coach", "player"].includes(audience) ? audience : null,
        intent: null,
        generator_version: COPILOT_GENERATOR_VERSION,
        validation_code: null,
        evidence_count: 0,
        latency_ms: 0,
      });
      if (!parentDraftAction && !["coach", "player"].includes(audience)) {
        return failure(400, "invalid_request");
      }
      const isStaff = ["owner", "admin", "coach"].includes(membership.role);
      const isSelfPlayer = membership.role === "player";
      if (parentDraftAction && !isStaff) {
        return failure(403, "staff_access_required");
      }
      if (
        (!isStaff && !isSelfPlayer) ||
        (isStaff && !parentDraftAction && audience !== "coach") ||
        (isSelfPlayer && audience !== "player")
      ) return failure(403, "staff_access_required");
      const allowedPlayers = isSelfPlayer
        ? new Set([actorId])
        : await store.authorizedPlayerIds(orgId, actorId);
      const requestedPlayer = clean(body.player_id).toLowerCase();
      if (
        requestedPlayer &&
        (!validUuid(requestedPlayer) || !allowedPlayers.has(requestedPlayer))
      ) return failure(403, "player_access_denied");
      if (isSelfPlayer && requestedPlayer && requestedPlayer !== actorId) {
        return failure(403, "player_access_denied");
      }

      if (action === "list_conversations") {
        const limit = Math.min(50, Math.max(1, Number(body.limit ?? 25)));
        const offset = Math.max(0, Number(body.offset ?? 0));
        const result = await store.listConversations(
          orgId,
          [...allowedPlayers],
          requestedPlayer || undefined,
          body.include_archived === true,
          limit,
          offset,
          audience,
          actorId,
        );
        return json(200, {
          ...result,
          pagination: {
            limit,
            offset,
            has_more: offset + result.conversations.length < result.total,
          },
        });
      }

      const conversationId = clean(body.conversation_id).toLowerCase();
      if (
        [
          "get_conversation",
          "archive_conversation",
          "ask",
          "retry_message",
          "get_message",
          "submit_feedback",
        ].includes(action)
      ) {
        if (!validUuid(conversationId)) return failure(400, "invalid_request");
        const conversation = await store.conversation(
          orgId,
          conversationId,
          [
            ...allowedPlayers,
          ],
          audience,
          actorId,
        );
        if (!conversation || !allowedPlayers.has(conversation.player_id)) {
          return failure(404, "conversation_not_found");
        }
        if (requestedPlayer && requestedPlayer !== conversation.player_id) {
          return failure(404, "conversation_not_found");
        }
        if (action === "get_conversation" || action === "get_message") {
          if (action === "get_message") {
            const messageId = clean(body.message_id).toLowerCase();
            if (!validUuid(messageId)) return failure(400, "invalid_request");
            const message = await store.message(
              orgId,
              conversationId,
              messageId,
              [...allowedPlayers],
              audience,
            );
            return message
              ? json(200, { message })
              : failure(404, "message_not_found");
          }
          const limit = Math.min(
            limits.conversationMessages,
            Math.max(1, Number(body.limit ?? limits.conversationMessages)),
          );
          const offset = Math.max(0, Number(body.offset ?? 0));
          const result = await store.messages(
            orgId,
            conversationId,
            [...allowedPlayers],
            limit,
            offset,
            audience,
          );
          return json(200, {
            conversation,
            ...result,
            pagination: {
              limit,
              offset,
              has_more: offset + result.messages.length < result.total,
            },
          });
        }
        if (action === "archive_conversation") {
          return json(200, {
            conversation: await store.archiveConversation(
              actorId,
              orgId,
              conversationId,
              audience,
            ),
          });
        }
        if (action === "submit_feedback") {
          const messageId = clean(body.message_id).toLowerCase();
          const feedbackType = clean(body.feedback_type);
          if (
            !validUuid(messageId) ||
            ![
              "helpful",
              "not_helpful",
              "incorrect",
              "missing_context",
              "wrong_evidence",
              "too_generic",
              "unsafe",
              "other",
            ].includes(feedbackType)
          ) return failure(400, "invalid_request");
          const result = await store.submitFeedback({
            actorId,
            orgId,
            playerId: conversation.player_id,
            conversationId,
            messageId,
            feedbackType,
            note: clean(body.note).slice(0, 1000) || null,
            audience,
          });
          return json(200, { feedback: result });
        }
        if (conversation.status !== "active") {
          return failure(409, "conversation_not_found");
        }
        const question = clean(body.question);
        const idempotencyKey = clean(body.idempotency_key).toLowerCase();
        if (
          !question || question.length > COPILOT_MAX_QUESTION_CHARACTERS ||
          !validUuid(idempotencyKey)
        ) return failure(400, "invalid_request");
        const unsafe = unsafeQuestionCode(question);
        if (unsafe) return failure(422, unsafe);
        const pendingQuestionId = clean(body.pending_question_id).toLowerCase();
        const pendingResponseMode = clean(body.pending_response_mode) as
          | "answer"
          | "skip"
          | "use_available_evidence";
        let pendingQuestion:
          | (CopilotPendingQuestion & { originating_request: string })
          | null = null;
        if (pendingQuestionId) {
          if (
            !validUuid(pendingQuestionId) ||
            !["answer", "skip", "use_available_evidence"].includes(
              pendingResponseMode,
            )
          ) return failure(400, "pending_question_response_invalid");
          pendingQuestion = await store.pendingQuestion(
            orgId,
            conversationId,
            pendingQuestionId,
            audience,
            actorId,
          );
          if (
            !pendingQuestion || pendingQuestion.status !== "pending" ||
            Date.parse(pendingQuestion.expires_at) <= now().getTime()
          ) return failure(409, "stale_context");
          if (pendingResponseMode === "skip" && !pendingQuestion.is_optional) {
            return failure(409, "pending_question_response_invalid");
          }
          if (
            pendingResponseMode === "answer" &&
            pendingQuestion.expected_response_type === "choice" &&
            !pendingQuestion.choices.some((choice) =>
              choice.toLowerCase() === question.toLowerCase()
            )
          ) return failure(409, "pending_question_response_invalid");
        } else if (body.pending_response_mode !== undefined) {
          return failure(400, "pending_question_response_invalid");
        }
        const windowEnd = clean(body.window_end) ||
          now().toISOString().slice(0, 10);
        const defaultStart = new Date(
          Date.parse(`${windowEnd}T00:00:00Z`) -
            (conversation.reporting_window_days - 1) * 86_400_000,
        ).toISOString().slice(0, 10);
        let windowStart = clean(body.window_start) || defaultStart;
        let startMs = exactDate(windowStart);
        const endMs = exactDate(windowEnd);
        if (
          startMs === null || endMs === null || startMs > endMs ||
          endMs - startMs > COPILOT_MAX_REPORTING_WINDOW_DAYS * 86_400_000
        ) return failure(400, "invalid_request");
        const initialClassification = classifyCopilotIntent(question);
        if (
          initialClassification.intent === "period_change_summary" &&
          initialClassification.period_days && endMs !== null &&
          startMs !== null
        ) {
          const periodStart = endMs -
            (initialClassification.period_days - 1) * 86_400_000;
          if (startMs < periodStart) {
            startMs = periodStart;
            windowStart = new Date(periodStart).toISOString().slice(0, 10);
          }
        }
        const usage = await store.usage(orgId, actorId, audience);
        if (
          usage.organization_questions_today >=
            limits.questionsPerOrganizationDay ||
          usage.actor_questions_this_hour >=
            limits.questionsPerActorHour
        ) return failure(429, "rate_limited");
        const cutoff = now().toISOString();
        const sourcePack = await store.evidencePack({
          orgId,
          playerId: conversation.player_id,
          windowStart,
          windowEnd,
          cutoff,
          maxEvidenceRows: limits.evidenceRows,
          audience,
        });
        const pack = audience === "player"
          ? playerVisibleEvidencePack(sourcePack)
          : sourcePack;
        const classification = classifyCopilotIntent(question, pack);
        diagnostic(
          classification.intent
            ? "copilot_intent_classified"
            : "copilot_intent_unrecognized",
          {
            request_id: requestId,
            action,
            audience,
            intent: classification.intent,
            generator_version: COPILOT_GENERATOR_VERSION,
            validation_code: classification.intent
              ? null
              : "deterministic_intent_unrecognized",
            evidence_count: pack.evidence.length,
            latency_ms: 0,
          },
        );
        diagnostic("copilot_evidence_built", {
          request_id: requestId,
          action,
          audience,
          intent: classification.intent,
          generator_version: COPILOT_GENERATOR_VERSION,
          validation_code: null,
          evidence_count: pack.evidence.length,
          trend_count: pack.trends.length,
          latency_ms: 0,
        });
        const configuredProvider = providerFactory(pack);
        let activeProvider: CopilotGenerationProvider = configuredProvider;
        const started = performance.now();
        let generationStatus: "succeeded" | "failed" | "rejected" = "succeeded";
        let safeErrorCode: string | null = null;
        let answer: CopilotStructuredAnswer | null = null;
        let citations: CopilotCitation[] = [];
        try {
          let raw: unknown;
          if (pendingQuestion?.question_type === "reflection_question") {
            activeProvider = new DeterministicCopilotProvider(pack);
            raw = {
              ...emptyAnswer(pack, audience),
              answer:
                "Thanks for reflecting. Your response remains private conversation context and is not stored as a verified metric, medical fact, or official record.",
              answer_quality: pack.quality_status,
              missing_data: pack.missing_data_warnings,
            };
          } else if (
            pendingQuestion?.question_type === "confirmation_question"
          ) {
            activeProvider = new DeterministicCopilotProvider(pack);
            raw = {
              ...emptyAnswer(pack, audience),
              answer: pendingResponseMode === "answer" &&
                  question.toLowerCase().includes("confirm")
                ? "Your confirmation was recorded for this preview. No action was executed because this phase has no dedicated audited tool for that mutation."
                : "The proposed action was canceled. No official data was changed.",
              answer_quality: "unavailable",
              missing_data: [],
            };
          } else {
            const dialogue = pendingQuestion
              ? null
              : deterministicDialogueTurn(question, pack, audience, now());
            const effectiveQuestion = pendingQuestion
              ? pendingResponseMode === "answer"
                ? `Summarize my recent ${question} development using the currently available evidence.`
                : "Summarize my recent development using the currently available evidence."
              : question;
            const deterministic = pendingQuestion
              ? deterministicAnswer(effectiveQuestion, pack, audience)
              : classification.intent && !classification.needs_clarification
              ? constructDeterministicAnswer(classification, pack, audience)
              : null;
            if (dialogue || deterministic) {
              activeProvider = new DeterministicCopilotProvider(pack);
              raw = dialogue ?? deterministic;
              diagnostic("copilot_deterministic_generated", {
                request_id: requestId,
                action,
                audience,
                intent: classification.intent,
                generator_version: activeProvider.generatorVersion,
                validation_code: null,
                evidence_count: pack.evidence.length,
                latency_ms: Math.round(performance.now() - started),
              });
            } else {
              raw = await configuredProvider.generate(
                promptContext(
                  effectiveQuestion,
                  pack,
                  limits.evidenceRows,
                  audience,
                ),
              );
            }
          }
          if (raw === null) {
            throw new Error(
              configuredProvider.mode === "deterministic"
                ? "deterministic_intent_unrecognized"
                : "provider_unavailable",
            );
          }
          const validated = validateStructuredAnswer(
            raw,
            pack,
            limits,
            audience,
          );
          answer = validated.answer;
          citations = validated.citations;
        } catch (error) {
          const classifiedFailure = validationFailure(error);
          safeErrorCode = classifiedFailure.code === "provider_unavailable" &&
              configuredProvider.mode === "unavailable"
            ? "unsupported_without_provider"
            : classifiedFailure.code;
          generationStatus = [
              "invalid_evidence_reference",
              "structured_output_invalid",
              "unsafe_generated_content",
            ].includes(safeErrorCode)
            ? "rejected"
            : "failed";
          const event = classifiedFailure.stage === "structured_output"
            ? "copilot_structured_validation_failed"
            : classifiedFailure.stage === "evidence"
            ? "copilot_evidence_validation_failed"
            : classifiedFailure.stage === "safety"
            ? "copilot_safety_validation_failed"
            : classifiedFailure.stage === "classification"
            ? "copilot_intent_unrecognized"
            : "copilot_generation_failed";
          diagnostic(event, {
            request_id: requestId,
            action,
            audience,
            intent: classification.intent,
            generator_version: activeProvider.generatorVersion,
            validation_code: safeErrorCode,
            evidence_count: pack.evidence.length,
            latency_ms: Math.round(performance.now() - started),
          });
        }
        const rendered = answer
          ? renderAnswer(answer, limits.outputCharacters)
          : null;
        diagnostic("copilot_persist_started", {
          request_id: requestId,
          action,
          audience,
          intent: classification.intent,
          generator_version: activeProvider.generatorVersion,
          validation_code: safeErrorCode,
          evidence_count: pack.evidence.length,
          latency_ms: Math.round(performance.now() - started),
        });
        let persisted: Awaited<ReturnType<CopilotStore["persistExchange"]>>;
        try {
          persisted = await store.persistExchange({
            actorId,
            orgId,
            playerId: conversation.player_id,
            conversationId,
            question,
            answer,
            renderedAnswer: rendered,
            qualityStatus: answer?.answer_quality ??
              (generationStatus === "rejected" ? "rejected" : "unavailable"),
            cutoff,
            generationMode: activeProvider.mode,
            provider: activeProvider.provider,
            modelIdentifier: activeProvider.modelIdentifier,
            promptVersion: audience === "player"
              ? PLAYER_COPILOT_PROMPT_VERSION
              : COPILOT_PROMPT_VERSION,
            generatorVersion: activeProvider.generatorVersion,
            generationStatus,
            safeErrorCode,
            idempotencyKey,
            citations,
            attempt: {
              action_type: action,
              retry_count: action === "retry_message" ? 1 : 0,
              status: generationStatus === "succeeded"
                ? "succeeded"
                : generationStatus,
              input_size: question.length +
                JSON.stringify(
                  promptContext(question, pack, limits.evidenceRows, audience),
                ).length,
              output_size: rendered?.length ?? 0,
              latency_ms: Math.round(performance.now() - started),
              safe_metadata: {
                evidence_count: pack.evidence.length,
                history_limit: limits.conversationMessages,
              },
            },
            audience,
            pendingQuestionId: pendingQuestion?.id ?? null,
            pendingResponseMode: pendingQuestion ? pendingResponseMode : null,
          });
        } catch {
          diagnostic("copilot_persist_failed", {
            request_id: requestId,
            action,
            audience,
            intent: classification.intent,
            generator_version: activeProvider.generatorVersion,
            validation_code: "persistence_failed",
            evidence_count: pack.evidence.length,
            latency_ms: Math.round(performance.now() - started),
          });
          return failure(500, "persistence_failed");
        }
        diagnostic("copilot_persist_succeeded", {
          request_id: requestId,
          action,
          audience,
          intent: classification.intent,
          generator_version: activeProvider.generatorVersion,
          validation_code: safeErrorCode,
          evidence_count: pack.evidence.length,
          latency_ms: Math.round(performance.now() - started),
        });
        try {
          const hydratedAssistant = await store.message(
            orgId,
            conversationId,
            persisted.assistant_message.id,
            [...allowedPlayers],
            audience,
          );
          if (!hydratedAssistant) throw new Error("message_not_found");
          persisted.assistant_message = hydratedAssistant;
          persisted.pending_question = hydratedAssistant.pending_question ??
            persisted.pending_question;
        } catch {
          diagnostic("copilot_response_hydration_failed", {
            request_id: requestId,
            action,
            audience,
            intent: classification.intent,
            generator_version: activeProvider.generatorVersion,
            validation_code: "persistence_failed",
            evidence_count: pack.evidence.length,
            latency_ms: Math.round(performance.now() - started),
          });
          return failure(500, "persistence_failed");
        }
        return json(generationStatus === "succeeded" ? 200 : 503, {
          ...persisted,
          suggested_questions: suggestedQuestions(pack, audience),
          error: safeErrorCode,
          message: safeErrorCode ? safeMessages[safeErrorCode] : undefined,
        });
      }

      if (action === "create_conversation") {
        if (!requestedPlayer) return failure(400, "invalid_request");
        const idempotencyKey = clean(body.idempotency_key).toLowerCase();
        const title = clean(body.title) || "Player Development Copilot";
        const days = Number(body.reporting_window_days ?? 90);
        if (
          !validUuid(idempotencyKey) || title.length > 160 ||
          !Number.isInteger(days) || days < 1 || days > 730
        ) return failure(400, "invalid_request");
        const provider = providerFactory({} as DevelopmentEvidencePack);
        const conversation = await store.createConversation({
          actorId,
          orgId,
          playerId: requestedPlayer,
          title,
          reportingWindowDays: days,
          evidenceCutoff: now().toISOString(),
          generationMode: provider.mode,
          provider: provider.provider,
          modelIdentifier: provider.modelIdentifier,
          generatorVersion: provider.generatorVersion,
          idempotencyKey,
          audience,
        });
        return json(200, { conversation });
      }

      if (action === "suggested_questions") {
        if (!requestedPlayer) return failure(400, "invalid_request");
        const end = now().toISOString().slice(0, 10);
        const start = new Date(now().getTime() - 89 * 86_400_000).toISOString()
          .slice(0, 10);
        const sourcePack = await store.evidencePack({
          orgId,
          playerId: requestedPlayer,
          windowStart: start,
          windowEnd: end,
          cutoff: now().toISOString(),
          maxEvidenceRows: limits.evidenceRows,
          audience,
        });
        const pack = audience === "player"
          ? playerVisibleEvidencePack(sourcePack)
          : sourcePack;
        return json(200, {
          suggested_questions: suggestedQuestions(pack, audience),
          evidence_quality: pack.quality_status,
        });
      }

      if (action === "get_player_workspace") {
        if (
          !isSelfPlayer || audience !== "player" || requestedPlayer !== actorId
        ) {
          return failure(403, "player_access_denied");
        }
        const end = now().toISOString().slice(0, 10);
        const start = new Date(now().getTime() - 89 * 86_400_000).toISOString()
          .slice(0, 10);
        const sourcePack = await store.evidencePack({
          orgId,
          playerId: actorId,
          windowStart: start,
          windowEnd: end,
          cutoff: now().toISOString(),
          maxEvidenceRows: limits.evidenceRows,
          audience,
        });
        const pack = playerVisibleEvidencePack(sourcePack);
        const records = await store.playerWorkspaceRecords?.(orgId, actorId) ??
          { reports: [], alerts: [] };
        return json(200, {
          evidence_pack: pack,
          suggested_questions: suggestedQuestions(pack, "player"),
          player_visible_reports: records.reports,
          player_visible_alerts: records.alerts,
          reports_availability: records.reports.length > 0
            ? "Player summaries are available."
            : "No player summary has been generated yet.",
          alerts_availability: records.alerts.length > 0
            ? "Player-visible objective alerts are available."
            : "No player-visible objective alert is active.",
        });
      }

      if (action === "get_usage") {
        return json(200, {
          usage: {
            ...(await store.usage(orgId, actorId, audience)),
            limits,
          },
        });
      }

      if (
        [
          "list_parent_drafts",
          "get_parent_draft",
          "update_parent_draft",
          "approve_parent_draft",
          "reject_parent_draft",
          "archive_parent_draft",
        ].includes(action)
      ) {
        if (action === "list_parent_drafts") {
          return json(200, {
            drafts: await store.listParentDrafts(
              orgId,
              [...allowedPlayers],
              requestedPlayer || undefined,
            ),
          });
        }
        const draftId = clean(body.draft_id).toLowerCase();
        if (!validUuid(draftId)) return failure(400, "invalid_request");
        const detail = await store.parentDraft(orgId, draftId, [
          ...allowedPlayers,
        ]);
        if (!detail || !allowedPlayers.has(detail.draft.player_id)) {
          return failure(404, "parent_draft_not_found");
        }
        if (action === "get_parent_draft") return json(200, detail);
        const mappedAction = action === "update_parent_draft"
          ? (body.mark_reviewed === true ? "review" : "edit")
          : action.replace("_parent_draft", "");
        const content = body.content;
        if (mappedAction === "edit" && !validParentContent(content)) {
          return failure(400, "invalid_request");
        }
        const updated = await store.reviewParentDraft({
          actorId,
          orgId,
          draftId,
          action: mappedAction,
          content: validParentContent(content) ? content : null,
          renderedText: validParentContent(content)
            ? renderParentDraft(content)
            : null,
          note: clean(body.note).slice(0, 2000) || null,
        });
        return json(200, { draft: updated, not_shared_with_parent: true });
      }

      if (action === "create_parent_draft") {
        if (!requestedPlayer) return failure(400, "invalid_request");
        const idempotencyKey = clean(body.idempotency_key).toLowerCase();
        if (!validUuid(idempotencyKey)) return failure(400, "invalid_request");
        const sourceConversationId = clean(body.conversation_id).toLowerCase();
        const sourceMessageId = clean(body.source_message_id).toLowerCase();
        if (
          (sourceConversationId || sourceMessageId) &&
          (!validUuid(sourceConversationId) || !validUuid(sourceMessageId))
        ) {
          return failure(400, "invalid_request");
        }
        if (sourceConversationId) {
          const sourceConversation = await store.conversation(
            orgId,
            sourceConversationId,
            [...allowedPlayers],
            "coach",
            actorId,
          );
          const sourceMessage = await store.message(
            orgId,
            sourceConversationId,
            sourceMessageId,
            [...allowedPlayers],
            "coach",
          );
          if (
            !sourceConversation ||
            sourceConversation.player_id !== requestedPlayer ||
            !sourceMessage || sourceMessage.player_id !== requestedPlayer ||
            sourceMessage.role !== "assistant"
          ) return failure(404, "message_not_found");
        }
        const usage = await store.usage(orgId, actorId, "coach");
        if (
          usage.organization_parent_drafts_today >=
            limits.parentDraftsPerOrganizationDay
        ) return failure(429, "usage_limit_reached");
        const end = clean(body.window_end) || now().toISOString().slice(0, 10);
        const start = clean(body.window_start) ||
          new Date(Date.parse(`${end}T00:00:00Z`) - 89 * 86_400_000)
            .toISOString().slice(0, 10);
        const startMs = exactDate(start);
        const endMs = exactDate(end);
        if (
          startMs === null || endMs === null || startMs > endMs ||
          endMs - startMs > COPILOT_MAX_REPORTING_WINDOW_DAYS * 86_400_000
        ) {
          return failure(400, "invalid_request");
        }
        const cutoff = now().toISOString();
        const pack = await store.evidencePack({
          orgId,
          playerId: requestedPlayer,
          windowStart: start,
          windowEnd: end,
          cutoff,
          maxEvidenceRows: limits.evidenceRows,
          audience: "coach",
        });
        const content = deterministicParentDraft(pack);
        const draft = await store.createParentDraft({
          actorId,
          orgId,
          playerId: requestedPlayer,
          conversationId: sourceConversationId || null,
          sourceMessageId: sourceMessageId || null,
          content,
          renderedText: renderParentDraft(content),
          cutoff,
          generationMode: "deterministic",
          provider: "deterministic_template",
          modelIdentifier: null,
          promptVersion: PARENT_DRAFT_PROMPT_VERSION,
          generatorVersion: COPILOT_GENERATOR_VERSION,
          idempotencyKey,
        });
        return json(200, { draft, not_shared_with_parent: true });
      }
      return failure(400, "unsupported_action");
    } catch (error) {
      const message = error instanceof Error ? error.message : "";
      const code = message.includes("idempotency_conflict")
        ? "invalid_request"
        : message.includes("invalid_parent_draft_transition")
        ? "invalid_parent_draft_transition"
        : "copilot_unavailable";
      return failure(
        code === "invalid_parent_draft_transition" ? 409 : 500,
        code,
      );
    }
  };
}
