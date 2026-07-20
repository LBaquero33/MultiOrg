import Foundation

enum SDCopilotAudience: String, Codable, Sendable {
  case coach
  case player
}

enum SDCopilotGenerationMode: String, Codable, Sendable {
  case deterministic
  case model
  case hybrid
  case unavailable
  case unknown

  init(from decoder: Decoder) throws {
    let value = try decoder.singleValueContainer().decode(String.self)
    self = Self(rawValue: value) ?? .unknown
  }
}

enum SDCopilotQualityStatus: String, Codable, Sendable {
  case sufficient
  case limited
  case stale
  case conflicting
  case unavailable
  case rejected
  case unknown

  init(from decoder: Decoder) throws {
    let value = try decoder.singleValueContainer().decode(String.self)
    self = Self(rawValue: value) ?? .unknown
  }
}

enum SDCopilotConversationStatus: String, Codable, Sendable {
  case active
  case archived
  case unknown

  init(from decoder: Decoder) throws {
    let value = try decoder.singleValueContainer().decode(String.self)
    self = Self(rawValue: value) ?? .unknown
  }
}

enum SDCopilotMessageRole: String, Codable, Sendable {
  case user
  case assistant
  case unknown

  init(from decoder: Decoder) throws {
    let value = try decoder.singleValueContainer().decode(String.self)
    self = Self(rawValue: value) ?? .unknown
  }
}

enum SDCopilotAssistantTurnType: String, Codable, Sendable {
  case answer
  case clarificationQuestion = "clarification_question"
  case evidenceGapQuestion = "evidence_gap_question"
  case reflectionQuestion = "reflection_question"
  case confirmationQuestion = "confirmation_question"
  case suggestedFollowUp = "suggested_follow_up"
  case actionPreview = "action_preview"
  case safeRefusal = "safe_refusal"
  case unknown

  init(from decoder: Decoder) throws {
    let value = try decoder.singleValueContainer().decode(String.self)
    self = Self(rawValue: value) ?? .unknown
  }

  var isQuestion: Bool {
    switch self {
    case .clarificationQuestion, .evidenceGapQuestion, .reflectionQuestion,
         .confirmationQuestion, .actionPreview:
      true
    default:
      false
    }
  }
}

enum SDCopilotPendingQuestionStatus: String, Codable, Sendable {
  case pending
  case answered
  case skipped
  case expired
  case superseded
  case unknown

  init(from decoder: Decoder) throws {
    let value = try decoder.singleValueContainer().decode(String.self)
    self = Self(rawValue: value) ?? .unknown
  }
}

enum SDCopilotPendingResponseMode: String, Codable, Sendable {
  case answer
  case skip
  case useAvailableEvidence = "use_available_evidence"
}

struct SDCopilotPendingQuestionDraft: Codable, Equatable, Sendable {
  let questionType: SDCopilotAssistantTurnType
  let whyAsked: String
  let expectedResponseType: String
  let choices: [String]
  let relatedEvidenceIds: [String]
  let isOptional: Bool
  let mayLaterBeSaved: Bool
  let expiresAt: String

  enum CodingKeys: String, CodingKey {
    case choices
    case questionType = "question_type"
    case whyAsked = "why_asked"
    case expectedResponseType = "expected_response_type"
    case relatedEvidenceIds = "related_evidence_ids"
    case isOptional = "is_optional"
    case mayLaterBeSaved = "may_later_be_saved"
    case expiresAt = "expires_at"
  }
}

struct SDCopilotPendingQuestion: Identifiable, Codable, Equatable, Sendable {
  let id: UUID
  let conversationId: UUID
  let assistantMessageId: UUID
  let questionType: SDCopilotAssistantTurnType
  let questionText: String?
  let whyAsked: String
  let expectedResponseType: String
  let choices: [String]
  let relatedEvidenceIds: [String]
  let isOptional: Bool
  let mayLaterBeSaved: Bool
  let status: SDCopilotPendingQuestionStatus
  let expiresAt: String
  let answeredAt: String?

  enum CodingKeys: String, CodingKey {
    case id, choices, status
    case conversationId = "conversation_id"
    case assistantMessageId = "assistant_message_id"
    case questionType = "question_type"
    case questionText = "question_text"
    case whyAsked = "why_asked"
    case expectedResponseType = "expected_response_type"
    case relatedEvidenceIds = "related_evidence_ids"
    case isOptional = "is_optional"
    case mayLaterBeSaved = "may_later_be_saved"
    case expiresAt = "expires_at"
    case answeredAt = "answered_at"
  }
}

enum SDCopilotGenerationStatus: String, Codable, Sendable {
  case pending
  case succeeded
  case failed
  case rejected
  case unknown

  init(from decoder: Decoder) throws {
    let value = try decoder.singleValueContainer().decode(String.self)
    self = Self(rawValue: value) ?? .unknown
  }
}

struct SDCopilotFailurePresentation: Equatable, Sendable {
  let code: String?
  let message: String
  let isRetryable: Bool

  private init(code: String?, message: String, isRetryable: Bool) {
    self.code = code
    self.message = message
    self.isRetryable = isRetryable
  }

  init(code: String?, fallbackMessage: String? = nil) {
    self.code = code
    switch code {
    case "feature_disabled":
      message = "Player Development AI and Copilot are currently disabled by Home Plate."
      isRetryable = false
    case "unsupported_without_provider", "provider_unavailable":
      message = "That conversational question needs a configured generation provider. Supported deterministic questions remain available."
      isRetryable = false
    case "provider_timeout":
      message = "Copilot took too long to answer. Please try again."
      isRetryable = true
    case "deterministic_intent_unrecognized":
      message = "Home Plate could not match that question to a supported deterministic answer. Try one of the suggested questions."
      isRetryable = false
    case "evidence_unavailable":
      message = "No authorized player-development evidence is available for that request."
      isRetryable = false
    case "structured_output_invalid", "invalid_structured_output":
      message = "The deterministic answer could not be produced because it did not match Home Plate’s validated answer format."
      isRetryable = true
    case "invalid_evidence_reference":
      message = "The deterministic answer could not be produced because an evidence citation was not authorized."
      isRetryable = true
    case "unsafe_generated_content", "unsafe_output":
      message = "The deterministic answer could not be produced because it did not pass Home Plate safety validation."
      isRetryable = true
    case "persistence_failed":
      message = "The answer could not be saved. Retry the same request."
      isRetryable = true
    case "rate_limited", "usage_limit_reached":
      message = "The development usage limit has been reached. Try again later."
      isRetryable = true
    case "stale_context", "pending_question_stale":
      message = "That Copilot context is no longer current. Review the latest conversation and try again."
      isRetryable = false
    case "unsafe_question":
      message = fallbackMessage ?? "Copilot cannot provide a diagnosis or guaranteed outcome."
      isRetryable = false
    default:
      message = fallbackMessage ?? "Player Development Copilot could not complete the request."
      isRetryable = true
    }
  }

  init(error: Error) {
    if let response = error as? SDCopilotResponseContractError {
      self.init(
        code: response.diagnosticCode,
        message: response.localizedDescription,
        isRetryable: response.isRetryable
      )
    } else if let edge = error as? SDEdgeFunctionHTTPError {
      self.init(code: edge.code, fallbackMessage: edge.message)
    } else {
      self.init(code: nil, fallbackMessage: error.localizedDescription)
    }
  }
}

enum SDCopilotFeedbackType: String, Codable, CaseIterable, Sendable {
  case helpful
  case notHelpful = "not_helpful"
  case incorrect
  case missingContext = "missing_context"
  case wrongEvidence = "wrong_evidence"
  case tooGeneric = "too_generic"
  case unsafe
  case other

  var title: String {
    switch self {
    case .helpful: "Helpful"
    case .notHelpful: "Not helpful"
    case .incorrect: "Incorrect"
    case .missingContext: "Missing context"
    case .wrongEvidence: "Wrong evidence"
    case .tooGeneric: "Too generic"
    case .unsafe: "Unsafe"
    case .other: "Other"
    }
  }
}

enum SDCopilotProposedActionType: String, Codable, Sendable {
  case scheduleRetesting = "schedule_retesting"
  case reviewAlert = "review_alert"
  case createDraftCoachNote = "create_draft_coach_note"
  case generateParentUpdate = "generate_parent_update"
  case reviewProgramAssignment = "review_program_assignment"
  case investigateDataQuality = "investigate_data_quality"
  case discussMetricWithPlayer = "discuss_metric_with_player"
  case reviewMetricWithCoach = "review_metric_with_coach"
  case requestRetesting = "request_retesting"
  case uploadUpdatedData = "upload_updated_data"
  case completeAssignedSession = "complete_assigned_session"
  case reviewAssignedProgram = "review_assigned_program"
  case logTrainingSession = "log_training_session"
  case discussDataQuality = "discuss_data_quality"
  case prepareCoachQuestions = "prepare_coach_questions"
  case updatePersonalGoal = "update_personal_goal"
  case unknown

  init(from decoder: Decoder) throws {
    let value = try decoder.singleValueContainer().decode(String.self)
    self = Self(rawValue: value) ?? .unknown
  }
}

struct SDCopilotClaim: Codable, Equatable, Sendable {
  let text: String
  let evidenceIds: [String]

  enum CodingKeys: String, CodingKey {
    case text
    case evidenceIds = "evidence_ids"
  }
}

struct SDCopilotCalculation: Codable, Equatable, Sendable {
  let text: String
  let evidenceIds: [String]
  let ruleId: String

  enum CodingKeys: String, CodingKey {
    case text
    case evidenceIds = "evidence_ids"
    case ruleId = "rule_id"
  }
}

struct SDCopilotInterpretation: Codable, Equatable, Sendable {
  let text: String
  let evidenceIds: [String]
  let confidence: Double

  enum CodingKeys: String, CodingKey {
    case text, confidence
    case evidenceIds = "evidence_ids"
  }
}

struct SDCopilotRecommendation: Codable, Equatable, Sendable {
  let text: String
  let evidenceIds: [String]
  let requiresHumanApproval: Bool

  enum CodingKeys: String, CodingKey {
    case text
    case evidenceIds = "evidence_ids"
    case requiresHumanApproval = "requires_human_approval"
  }
}

struct SDCopilotProposedAction: Identifiable, Codable, Equatable, Sendable {
  var id: String { "\(actionType.rawValue):\(evidenceIds.joined(separator: ","))" }
  let actionType: SDCopilotProposedActionType
  let explanation: String
  let evidenceIds: [String]
  let urgency: String
  let confidence: Double
  let requiresApproval: Bool

  enum CodingKeys: String, CodingKey {
    case explanation, urgency, confidence
    case actionType = "action_type"
    case evidenceIds = "evidence_ids"
    case requiresApproval = "requires_approval"
  }
}

struct SDCopilotStructuredAnswer: Codable, Equatable, Sendable {
  let schemaVersion: String
  let assistantTurnType: SDCopilotAssistantTurnType?
  let pendingQuestion: SDCopilotPendingQuestionDraft?
  let answer: String
  let answerQuality: SDCopilotQualityStatus
  let facts: [SDCopilotClaim]
  let calculations: [SDCopilotCalculation]
  let interpretations: [SDCopilotInterpretation]
  let recommendations: [SDCopilotRecommendation]
  let missingData: [String]
  let followUpQuestions: [String]
  let warnings: [String]
  let proposedActions: [SDCopilotProposedAction]

  enum CodingKeys: String, CodingKey {
    case answer, facts, calculations, interpretations, recommendations, warnings
    case schemaVersion = "schema_version"
    case assistantTurnType = "assistant_turn_type"
    case pendingQuestion = "pending_question"
    case answerQuality = "answer_quality"
    case missingData = "missing_data"
    case followUpQuestions = "follow_up_questions"
    case proposedActions = "proposed_actions"
  }
}

struct SDCopilotCitation: Identifiable, Codable, Equatable, Sendable {
  /// Immediate answers from Copilot v3 returned citation evidence before the
  /// persisted citation row was reloaded. Keep a stable local identity for
  /// those legacy responses while preferring the authoritative database UUID.
  let persistedId: UUID?
  let messageId: UUID?
  let organizationId: UUID?
  let playerId: UUID?
  let audience: SDCopilotAudience?
  let evidenceKey: String
  let sourceEntityType: String
  let sourceRecordId: String
  let canonicalMetricKey: String?
  let observedValue: String?
  let normalizedValue: Double?
  let unit: String?
  let observedAt: String?
  let displayLabel: String
  let explanation: String
  let sectionKey: String
  let claimIdentifier: String
  let sourceProvider: String?
  let verificationStatus: String?
  let deterministicRuleId: String?
  let evidenceSnapshot: [String: SDJSONValue]

  var id: String {
    persistedId?.uuidString.lowercased()
      ?? "inline:\(evidenceKey):\(sectionKey):\(claimIdentifier)"
  }

  enum CodingKeys: String, CodingKey {
    case unit, explanation, audience
    case persistedId = "id"
    case messageId = "message_id"
    case organizationId = "org_id"
    case playerId = "player_id"
    case evidenceKey = "evidence_key"
    case sourceEntityType = "source_entity_type"
    case sourceRecordId = "source_record_id"
    case canonicalMetricKey = "canonical_metric_key"
    case observedValue = "observed_value"
    case normalizedValue = "normalized_value"
    case observedAt = "observed_at"
    case displayLabel = "display_label"
    case sectionKey = "section_key"
    case claimIdentifier = "claim_identifier"
    case sourceProvider = "source_provider"
    case verificationStatus = "verification_status"
    case deterministicRuleId = "deterministic_rule_id"
    case evidenceSnapshot = "evidence_snapshot"
  }
}

struct SDCopilotConversation: Identifiable, Codable, Equatable, Sendable {
  let id: UUID
  let organizationId: UUID
  let playerId: UUID
  let createdBy: UUID
  let audience: SDCopilotAudience
  let title: String
  let status: SDCopilotConversationStatus
  let reportingWindowDays: Int
  let evidenceCutoff: String
  let generationMode: SDCopilotGenerationMode
  let provider: String
  let modelIdentifier: String?
  let generatorVersion: String
  let archivedAt: String?
  let createdAt: String
  let updatedAt: String
  let playerName: String?
  let mostRecentQuestion: String?
  let mostRecentAnswerPreview: String?
  let qualityStatus: SDCopilotQualityStatus?

  enum CodingKeys: String, CodingKey {
    case id, title, status, provider, audience
    case organizationId = "org_id"
    case playerId = "player_id"
    case createdBy = "created_by"
    case reportingWindowDays = "reporting_window_days"
    case evidenceCutoff = "evidence_cutoff"
    case generationMode = "generation_mode"
    case modelIdentifier = "model_identifier"
    case generatorVersion = "generator_version"
    case archivedAt = "archived_at"
    case createdAt = "created_at"
    case updatedAt = "updated_at"
    case playerName = "player_name"
    case mostRecentQuestion = "most_recent_question"
    case mostRecentAnswerPreview = "most_recent_answer_preview"
    case qualityStatus = "quality_status"
  }
}

struct SDCopilotMessage: Identifiable, Codable, Equatable, Sendable {
  let id: UUID
  let conversationId: UUID
  let organizationId: UUID
  let playerId: UUID
  let actorId: UUID?
  let audience: SDCopilotAudience
  let role: SDCopilotMessageRole
  let assistantTurnType: SDCopilotAssistantTurnType?
  let inReplyToQuestionId: UUID?
  let userQuestion: String?
  let structuredAnswer: SDCopilotStructuredAnswer?
  let renderedAnswer: String?
  let qualityStatus: SDCopilotQualityStatus
  let evidenceCutoff: String
  let generationMode: SDCopilotGenerationMode
  let provider: String
  let modelIdentifier: String?
  let promptVersion: String
  let generatorVersion: String
  let generationStatus: SDCopilotGenerationStatus
  let safeErrorCode: String?
  var idempotencyKey: UUID? = nil
  let archivedAt: String?
  let createdAt: String
  let citations: [SDCopilotCitation]?
  let pendingQuestion: SDCopilotPendingQuestion?

  enum CodingKeys: String, CodingKey {
    case id, role, provider, citations, audience
    case assistantTurnType = "assistant_turn_type"
    case inReplyToQuestionId = "in_reply_to_question_id"
    case conversationId = "conversation_id"
    case organizationId = "org_id"
    case playerId = "player_id"
    case actorId = "actor_id"
    case userQuestion = "user_question"
    case structuredAnswer = "structured_answer"
    case renderedAnswer = "rendered_answer"
    case qualityStatus = "quality_status"
    case evidenceCutoff = "evidence_cutoff"
    case generationMode = "generation_mode"
    case modelIdentifier = "model_identifier"
    case promptVersion = "prompt_version"
    case generatorVersion = "generator_version"
    case generationStatus = "generation_status"
    case safeErrorCode = "safe_error_code"
    case idempotencyKey = "idempotency_key"
    case archivedAt = "archived_at"
    case createdAt = "created_at"
    case pendingQuestion = "pending_question"
  }
}

struct SDParentUpdateContent: Codable, Equatable, Sendable {
  let schemaVersion: String
  var recentWork: String
  var positiveDevelopments: String
  var currentFocus: String
  var consistency: String
  var recentTesting: String
  var evidenceLimitations: String
  var upcomingNextSteps: String

  enum CodingKeys: String, CodingKey {
    case consistency
    case schemaVersion = "schema_version"
    case recentWork = "recent_work"
    case positiveDevelopments = "positive_developments"
    case currentFocus = "current_focus"
    case recentTesting = "recent_testing"
    case evidenceLimitations = "evidence_limitations"
    case upcomingNextSteps = "upcoming_next_steps"
  }
}

enum SDParentDraftStatus: String, Codable, Sendable {
  case generated
  case reviewed
  case approved
  case rejected
  case archived
  case unknown

  init(from decoder: Decoder) throws {
    let value = try decoder.singleValueContainer().decode(String.self)
    self = Self(rawValue: value) ?? .unknown
  }
}

struct SDParentUpdateDraft: Identifiable, Codable, Equatable, Sendable {
  let id: UUID
  let organizationId: UUID
  let playerId: UUID
  let conversationId: UUID?
  let sourceMessageId: UUID?
  let createdBy: UUID
  let status: SDParentDraftStatus
  let generatedOriginal: SDParentUpdateContent
  let editedContent: SDParentUpdateContent
  let generatedRenderedText: String
  let editedRenderedText: String
  let evidenceCutoff: String
  let generationMode: SDCopilotGenerationMode
  let provider: String
  let modelIdentifier: String?
  let promptVersion: String
  let generatorVersion: String
  let reviewedAt: String?
  let reviewedBy: UUID?
  let approvedAt: String?
  let approvedBy: UUID?
  let rejectedAt: String?
  let rejectedBy: UUID?
  let archivedAt: String?
  let archivedBy: UUID?
  let createdAt: String
  let updatedAt: String

  enum CodingKeys: String, CodingKey {
    case id, status, provider
    case organizationId = "org_id"
    case playerId = "player_id"
    case conversationId = "conversation_id"
    case sourceMessageId = "source_message_id"
    case createdBy = "created_by"
    case generatedOriginal = "generated_original"
    case editedContent = "edited_content"
    case generatedRenderedText = "generated_rendered_text"
    case editedRenderedText = "edited_rendered_text"
    case evidenceCutoff = "evidence_cutoff"
    case generationMode = "generation_mode"
    case modelIdentifier = "model_identifier"
    case promptVersion = "prompt_version"
    case generatorVersion = "generator_version"
    case reviewedAt = "reviewed_at"
    case reviewedBy = "reviewed_by"
    case approvedAt = "approved_at"
    case approvedBy = "approved_by"
    case rejectedAt = "rejected_at"
    case rejectedBy = "rejected_by"
    case archivedAt = "archived_at"
    case archivedBy = "archived_by"
    case createdAt = "created_at"
    case updatedAt = "updated_at"
  }
}

struct SDParentDraftReviewEvent: Identifiable, Codable, Equatable, Sendable {
  let id: UUID
  let draftId: UUID
  let organizationId: UUID
  let playerId: UUID
  let actorId: UUID
  let eventType: String
  let fromStatus: String?
  let toStatus: String
  let safeNote: String?
  let contentSnapshot: SDParentUpdateContent
  let createdAt: String

  enum CodingKeys: String, CodingKey {
    case id
    case draftId = "draft_id"
    case organizationId = "org_id"
    case playerId = "player_id"
    case actorId = "actor_id"
    case eventType = "event_type"
    case fromStatus = "from_status"
    case toStatus = "to_status"
    case safeNote = "safe_note"
    case contentSnapshot = "content_snapshot"
    case createdAt = "created_at"
  }
}

struct SDCopilotUsageLimits: Codable, Equatable, Sendable {
  let questionsPerOrganizationDay: Int
  let questionsPerActorHour: Int
  let parentDraftsPerOrganizationDay: Int
  let evidenceRows: Int
  let conversationMessages: Int
  let outputCharacters: Int

  enum CodingKeys: String, CodingKey {
    case questionsPerOrganizationDay
    case questionsPerActorHour
    case parentDraftsPerOrganizationDay
    case evidenceRows
    case conversationMessages
    case outputCharacters
  }
}

struct SDCopilotUsage: Codable, Equatable, Sendable {
  let organizationQuestionsToday: Int
  let actorQuestionsThisHour: Int
  let organizationParentDraftsToday: Int
  let limits: SDCopilotUsageLimits

  enum CodingKeys: String, CodingKey {
    case limits
    case organizationQuestionsToday = "organization_questions_today"
    case actorQuestionsThisHour = "actor_questions_this_hour"
    case organizationParentDraftsToday = "organization_parent_drafts_today"
  }
}

struct SDCopilotPagination: Codable, Equatable, Sendable {
  let limit: Int
  let offset: Int
  let hasMore: Bool

  enum CodingKeys: String, CodingKey {
    case limit, offset
    case hasMore = "has_more"
  }
}

struct SDCopilotConversationsResponse: Codable, Equatable, Sendable {
  let conversations: [SDCopilotConversation]
  let total: Int
  let pagination: SDCopilotPagination
}

struct SDCopilotConversationResponse: Codable, Equatable, Sendable {
  let conversation: SDCopilotConversation
}

struct SDCopilotConversationDetailResponse: Codable, Equatable, Sendable {
  let conversation: SDCopilotConversation
  let messages: [SDCopilotMessage]
  let total: Int
  let pagination: SDCopilotPagination
}

struct SDCopilotAskResponse: Codable, Equatable, Sendable {
  let userMessage: SDCopilotMessage
  let assistantMessage: SDCopilotMessage
  let reused: Bool
  let suggestedQuestions: [String]
  let error: String?
  let message: String?
  let pendingQuestion: SDCopilotPendingQuestion?

  enum CodingKeys: String, CodingKey {
    case reused, error, message
    case pendingQuestion = "pending_question"
    case userMessage = "user_message"
    case assistantMessage = "assistant_message"
    case suggestedQuestions = "suggested_questions"
  }
}

enum SDCopilotCanonicalPayloadKey: String, Sendable {
  case data
  case answer
}

struct SDCopilotResponseDiagnostic: Equatable, Sendable {
  let requestId: String
  let statusCode: Int
  let contentType: String?
  let decodingCase: String
  let missingKey: String?
  let codingPath: String
  let debugDescription: String
  let redactedBody: String
}

struct SDCopilotAPIErrorPayload: Codable, Equatable, Sendable {
  let code: String
  let message: String
  let retryable: Bool
}

enum SDCopilotResponseContractError: LocalizedError, Equatable, Sendable {
  case emptyBody(SDCopilotResponseDiagnostic)
  case malformedJSON(SDCopilotResponseDiagnostic)
  case incompleteResponse(SDCopilotResponseDiagnostic)
  case backend(statusCode: Int, requestId: String, payload: SDCopilotAPIErrorPayload)

  var diagnosticCode: String {
    switch self {
    case .emptyBody: return "copilot_empty_response"
    case .malformedJSON: return "copilot_malformed_response"
    case .incompleteResponse: return "copilot_incomplete_response"
    case .backend(_, _, let payload): return payload.code
    }
  }

  var requestId: String {
    switch self {
    case .emptyBody(let diagnostic), .malformedJSON(let diagnostic), .incompleteResponse(let diagnostic):
      return diagnostic.requestId
    case .backend(_, let requestId, _):
      return requestId
    }
  }

  var diagnostic: SDCopilotResponseDiagnostic? {
    switch self {
    case .emptyBody(let diagnostic), .malformedJSON(let diagnostic), .incompleteResponse(let diagnostic):
      return diagnostic
    case .backend:
      return nil
    }
  }

  var isRetryable: Bool {
    switch self {
    case .emptyBody, .malformedJSON, .incompleteResponse:
      return true
    case .backend(_, _, let payload):
      return payload.retryable
    }
  }

  var errorDescription: String? {
    switch self {
    case .emptyBody, .malformedJSON, .incompleteResponse:
      return "Copilot received an incomplete response. Please try again."
    case .backend(_, _, let payload):
      return payload.message
    }
  }
}

enum SDCopilotResponseContract {
  static func decode<Response: Decodable>(
    _ type: Response.Type,
    from data: Data,
    statusCode: Int,
    contentType: String?,
    requestId: String,
    canonicalPayloadKey: SDCopilotCanonicalPayloadKey = .data
  ) throws -> Response {
    let redactedBody = redactedBody(from: data)
    func diagnostic(
      _ decodingCase: String,
      missingKey: String? = nil,
      codingPath: String = "<root>",
      debugDescription: String
    ) -> SDCopilotResponseDiagnostic {
      SDCopilotResponseDiagnostic(
        requestId: requestId,
        statusCode: statusCode,
        contentType: contentType,
        decodingCase: decodingCase,
        missingKey: missingKey,
        codingPath: codingPath,
        debugDescription: debugDescription,
        redactedBody: redactedBody
      )
    }

    guard !data.isEmpty,
          !String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw SDCopilotResponseContractError.emptyBody(diagnostic(
        "empty_body",
        debugDescription: "The response body was empty."
      ))
    }

    let rawObject: Any
    do {
      rawObject = try JSONSerialization.jsonObject(with: data)
    } catch {
      throw SDCopilotResponseContractError.malformedJSON(diagnostic(
        "malformed_json",
        debugDescription: "The response body was not valid JSON."
      ))
    }
    guard let object = rawObject as? [String: Any] else {
      throw SDCopilotResponseContractError.incompleteResponse(diagnostic(
        "invalid_top_level",
        debugDescription: "The response JSON was not an object."
      ))
    }

    var payloadData = data
    if object.keys.contains("ok") {
      guard let ok = object["ok"] as? Bool else {
        throw SDCopilotResponseContractError.incompleteResponse(diagnostic(
          "invalid_discriminator",
          missingKey: "ok",
          debugDescription: "The response discriminator was not a Boolean."
        ))
      }
      let responseRequestId = (object["request_id"] as? String) ?? requestId
      if !ok {
        let errorObject = object["error"] as? [String: Any]
        let code = errorObject?["code"] as? String ?? "copilot_unavailable"
        let message = errorObject?["message"] as? String
          ?? "Player Development Copilot could not complete the request."
        let retryable = errorObject?["retryable"] as? Bool
          ?? (statusCode == 429 || statusCode >= 500)
        throw SDCopilotResponseContractError.backend(
          statusCode: statusCode,
          requestId: responseRequestId,
          payload: SDCopilotAPIErrorPayload(code: code, message: message, retryable: retryable)
        )
      }
      guard (200..<300).contains(statusCode) else {
        throw SDCopilotResponseContractError.incompleteResponse(diagnostic(
          "success_envelope_non_success_status",
          debugDescription: "A success envelope used a non-success HTTP status."
        ))
      }
      let payloadKey = canonicalPayloadKey.rawValue
      guard let payload = object[payloadKey], !(payload is NSNull) else {
        throw SDCopilotResponseContractError.incompleteResponse(diagnostic(
          "missing_payload",
          missingKey: payloadKey,
          debugDescription: "The success envelope did not contain its required payload."
        ))
      }
      guard JSONSerialization.isValidJSONObject(payload) else {
        throw SDCopilotResponseContractError.incompleteResponse(diagnostic(
          "invalid_payload",
          missingKey: payloadKey,
          debugDescription: "The success payload was not valid JSON."
        ))
      }
      payloadData = try JSONSerialization.data(withJSONObject: payload)
    } else if !(200..<300).contains(statusCode) {
      let nestedError = object["error"] as? [String: Any]
      let legacyCode = object["error"] as? String
      let code = nestedError?["code"] as? String ?? legacyCode ?? "invalid_error_response"
      let message = nestedError?["message"] as? String
        ?? object["message"] as? String
        ?? "The server rejected the Copilot request (HTTP \(statusCode))."
      throw SDCopilotResponseContractError.backend(
        statusCode: statusCode,
        requestId: requestId,
        payload: SDCopilotAPIErrorPayload(
          code: code,
          message: message,
          retryable: statusCode == 429 || statusCode >= 500
        )
      )
    }

    do {
      return try JSONDecoder().decode(type, from: payloadData)
    } catch let error as DecodingError {
      throw SDCopilotResponseContractError.incompleteResponse(
        decodingDiagnostic(
          error,
          statusCode: statusCode,
          contentType: contentType,
          requestId: requestId,
          redactedBody: redactedBody
        )
      )
    } catch {
      throw SDCopilotResponseContractError.incompleteResponse(diagnostic(
        "decoding_failed",
        debugDescription: "The response payload could not be decoded."
      ))
    }
  }

  private static func decodingDiagnostic(
    _ error: DecodingError,
    statusCode: Int,
    contentType: String?,
    requestId: String,
    redactedBody: String
  ) -> SDCopilotResponseDiagnostic {
    let decodingCase: String
    let missingKey: String?
    let context: DecodingError.Context
    switch error {
    case .keyNotFound(let key, let value):
      decodingCase = "key_not_found"
      missingKey = key.stringValue
      context = value
    case .valueNotFound(_, let value):
      decodingCase = "value_not_found"
      missingKey = value.codingPath.last?.stringValue
      context = value
    case .typeMismatch(_, let value):
      decodingCase = "type_mismatch"
      missingKey = value.codingPath.last?.stringValue
      context = value
    case .dataCorrupted(let value):
      decodingCase = "data_corrupted"
      missingKey = value.codingPath.last?.stringValue
      context = value
    @unknown default:
      decodingCase = "unknown_decoding_error"
      missingKey = nil
      context = DecodingError.Context(codingPath: [], debugDescription: "Unknown decoding error.")
    }
    let path = context.codingPath.map(\.stringValue).joined(separator: ".")
    return SDCopilotResponseDiagnostic(
      requestId: requestId,
      statusCode: statusCode,
      contentType: contentType,
      decodingCase: decodingCase,
      missingKey: missingKey,
      codingPath: path.isEmpty ? "<root>" : path,
      debugDescription: context.debugDescription,
      redactedBody: redactedBody
    )
  }

  static func redactedBody(from data: Data) -> String {
    guard let object = try? JSONSerialization.jsonObject(with: data) else {
      return "<non-json body: \(data.count) bytes>"
    }
    let redacted = redact(object)
    guard let encoded = try? JSONSerialization.data(withJSONObject: redacted, options: [.sortedKeys]),
          let string = String(data: encoded, encoding: .utf8) else {
      return "<unavailable redacted body: \(data.count) bytes>"
    }
    return String(string.prefix(8_000))
  }

  private static func redact(_ value: Any) -> Any {
    switch value {
    case let dictionary as [String: Any]:
      return dictionary.mapValues(redact)
    case let array as [Any]:
      var values = array.prefix(10).map(redact)
      if array.count > 10 { values.append("<\(array.count - 10) additional items>") }
      return values
    case let string as String:
      return "<redacted string: \(string.count) characters>"
    case is NSNumber:
      return "<redacted number>"
    case is NSNull:
      return NSNull()
    default:
      return "<redacted \(String(describing: type(of: value)))>"
    }
  }
}

struct SDCopilotSuggestedQuestionsResponse: Codable, Equatable, Sendable {
  let suggestedQuestions: [String]
  let evidenceQuality: SDCopilotQualityStatus

  enum CodingKeys: String, CodingKey {
    case suggestedQuestions = "suggested_questions"
    case evidenceQuality = "evidence_quality"
  }
}

struct SDParentDraftsResponse: Codable, Equatable, Sendable {
  let drafts: [SDParentUpdateDraft]
}

struct SDParentDraftResponse: Codable, Equatable, Sendable {
  let draft: SDParentUpdateDraft
  let notSharedWithParent: Bool?

  enum CodingKeys: String, CodingKey {
    case draft
    case notSharedWithParent = "not_shared_with_parent"
  }
}

struct SDParentDraftDetailResponse: Codable, Equatable, Sendable {
  let draft: SDParentUpdateDraft
  let reviewEvents: [SDParentDraftReviewEvent]

  enum CodingKeys: String, CodingKey {
    case draft
    case reviewEvents = "review_events"
  }
}

struct SDCopilotUsageResponse: Codable, Equatable, Sendable {
  let usage: SDCopilotUsage
}

struct SDCopilotFeedbackResponse: Codable, Equatable, Sendable {
  let feedback: [String: SDJSONValue]
}

struct SDCopilotMessageResponse: Codable, Equatable, Sendable {
  let message: SDCopilotMessage
}

struct SDPlayerDevelopmentWorkspaceResponse: Codable, Equatable, Sendable {
  let evidencePack: SDDevelopmentEvidencePack
  let suggestedQuestions: [String]
  let playerVisibleReports: [SDDevelopmentReport]
  let reportsAvailability: String
  let playerVisibleAlerts: [SDDevelopmentAlert]
  let alertsAvailability: String

  enum CodingKeys: String, CodingKey {
    case evidencePack = "evidence_pack"
    case suggestedQuestions = "suggested_questions"
    case playerVisibleReports = "player_visible_reports"
    case reportsAvailability = "reports_availability"
    case playerVisibleAlerts = "player_visible_alerts"
    case alertsAvailability = "alerts_availability"
  }
}

struct SDCopilotRequest: Encodable, Equatable, Sendable {
  let action: String
  let organizationId: UUID
  var clientRequestId: UUID? = nil
  var audience: SDCopilotAudience? = nil
  var playerId: UUID?
  var conversationId: UUID?
  var messageId: UUID?
  var sourceMessageId: UUID?
  var draftId: UUID?
  var title: String?
  var question: String?
  var reportingWindowDays: Int?
  var windowStart: String?
  var windowEnd: String?
  var idempotencyKey: UUID?
  var feedbackType: SDCopilotFeedbackType?
  var note: String?
  var content: SDParentUpdateContent?
  var markReviewed: Bool?
  var includeArchived: Bool?
  var limit: Int?
  var offset: Int?
  var pendingQuestionId: UUID?
  var pendingResponseMode: SDCopilotPendingResponseMode?

  enum CodingKeys: String, CodingKey {
    case action, title, question, note, content, limit, offset, audience
    case organizationId = "org_id"
    case clientRequestId = "client_request_id"
    case playerId = "player_id"
    case conversationId = "conversation_id"
    case messageId = "message_id"
    case sourceMessageId = "source_message_id"
    case draftId = "draft_id"
    case reportingWindowDays = "reporting_window_days"
    case windowStart = "window_start"
    case windowEnd = "window_end"
    case idempotencyKey = "idempotency_key"
    case feedbackType = "feedback_type"
    case markReviewed = "mark_reviewed"
    case includeArchived = "include_archived"
    case pendingQuestionId = "pending_question_id"
    case pendingResponseMode = "pending_response_mode"
  }
}

struct SDCopilotContextToken: Equatable, Sendable {
  let organizationId: UUID
  let userId: UUID
  let playerId: UUID
  let audience: SDCopilotAudience

  func accepts(organizationId: UUID?, userId: UUID?, playerId: UUID?, audience: SDCopilotAudience) -> Bool {
    self.organizationId == organizationId && self.userId == userId && self.playerId == playerId && self.audience == audience
  }
}

enum SDCopilotClientScopeError: LocalizedError, Equatable, Sendable {
  case invalidResponseScope

  var errorDescription: String? {
    "Home Plate rejected Copilot data outside the active organization, player, or audience."
  }
}

struct SDCopilotPresentationPolicy: Equatable, Sendable {
  let audience: SDCopilotAudience

  var showsPlayerSafeWorkspace: Bool { audience == .player }
  var showsParentDraftControls: Bool { audience == .coach }
  var showsStaffReviewControls: Bool { audience == .coach }
  var showsParentDraftUsage: Bool { audience == .coach }
}

enum SDCopilotWorkspacePresentationStyle: Equatable, Sendable {
  case pushed
  case modal
}

struct SDCopilotConversationPresentation: Identifiable, Equatable, Sendable {
  let conversation: SDCopilotConversation
  let initialQuestion: String?

  var id: UUID { conversation.id }
}

@MainActor
protocol PlayerDevelopmentCopilotClient: AnyObject {
  func listCopilotConversations(organizationId: UUID, playerId: UUID, audience: SDCopilotAudience, offset: Int, limit: Int) async throws -> SDCopilotConversationsResponse
  func createCopilotConversation(organizationId: UUID, playerId: UUID, audience: SDCopilotAudience, title: String, reportingWindowDays: Int, idempotencyKey: UUID) async throws -> SDCopilotConversation
  func copilotConversation(organizationId: UUID, conversationId: UUID, audience: SDCopilotAudience, offset: Int, limit: Int) async throws -> SDCopilotConversationDetailResponse
  func copilotMessage(organizationId: UUID, conversationId: UUID, messageId: UUID, audience: SDCopilotAudience) async throws -> SDCopilotMessage
  func archiveCopilotConversation(organizationId: UUID, conversationId: UUID, audience: SDCopilotAudience) async throws -> SDCopilotConversation
  func askCopilot(organizationId: UUID, playerId: UUID, conversationId: UUID, audience: SDCopilotAudience, question: String, window: SDDevelopmentWindow, idempotencyKey: UUID, retry: Bool, pendingQuestionId: UUID?, pendingResponseMode: SDCopilotPendingResponseMode?) async throws -> SDCopilotAskResponse
  func submitCopilotFeedback(organizationId: UUID, conversationId: UUID, messageId: UUID, audience: SDCopilotAudience, type: SDCopilotFeedbackType, note: String?) async throws
  func copilotSuggestedQuestions(organizationId: UUID, playerId: UUID, audience: SDCopilotAudience) async throws -> SDCopilotSuggestedQuestionsResponse
  func playerDevelopmentWorkspace(organizationId: UUID, playerId: UUID) async throws -> SDPlayerDevelopmentWorkspaceResponse
  func generatePlayerDevelopmentReport(organizationId: UUID, playerId: UUID, window: SDDevelopmentWindow, evidenceCutoff: Date, idempotencyKey: UUID) async throws -> SDDevelopmentGenerateResponse
  func playerDevelopmentReportDetail(organizationId: UUID, reportId: UUID) async throws -> SDDevelopmentReportDetail
  func archivePlayerDevelopmentReport(organizationId: UUID, reportId: UUID) async throws -> SDDevelopmentReport
  func playerDevelopmentAlertDetail(organizationId: UUID, alertId: UUID) async throws -> SDDevelopmentAlertDetail
  func dismissPlayerDevelopmentAlert(organizationId: UUID, alertId: UUID) async throws -> SDDevelopmentAlert
  func listParentUpdateDrafts(organizationId: UUID, playerId: UUID) async throws -> [SDParentUpdateDraft]
  func createParentUpdateDraft(organizationId: UUID, playerId: UUID, conversationId: UUID?, sourceMessageId: UUID?, window: SDDevelopmentWindow, idempotencyKey: UUID) async throws -> SDParentUpdateDraft
  func parentUpdateDraft(organizationId: UUID, draftId: UUID) async throws -> SDParentDraftDetailResponse
  func updateParentUpdateDraft(organizationId: UUID, draftId: UUID, content: SDParentUpdateContent?, markReviewed: Bool, note: String?) async throws -> SDParentUpdateDraft
  func transitionParentUpdateDraft(organizationId: UUID, draftId: UUID, action: String, note: String?) async throws -> SDParentUpdateDraft
  func copilotUsage(organizationId: UUID, audience: SDCopilotAudience) async throws -> SDCopilotUsage
}
