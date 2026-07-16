import Foundation

enum SDDevelopmentRecordAudience: String, Codable, Sendable {
  case staff
  case player
  case parent
  case unknown

  init(from decoder: Decoder) throws {
    let value = try decoder.singleValueContainer().decode(String.self)
    self = Self(rawValue: value) ?? .unknown
  }
}

enum SDDevelopmentQualityStatus: String, Codable, CaseIterable, Sendable {
  case sufficient
  case limited
  case stale
  case conflicting
  case unavailable
  case unknown

  init(from decoder: Decoder) throws {
    let value = try decoder.singleValueContainer().decode(String.self)
    self = Self(rawValue: value) ?? .unknown
  }
}

enum SDDevelopmentReportStatus: String, Codable, CaseIterable, Sendable {
  case requested
  case generating
  case draft
  case reviewed
  case approved
  case failed
  case rejected
  case archived
  case unknown

  init(from decoder: Decoder) throws {
    let value = try decoder.singleValueContainer().decode(String.self)
    self = Self(rawValue: value) ?? .unknown
  }

  var isReviewable: Bool { self == .draft || self == .reviewed }
  var canArchive: Bool { self == .draft || self == .reviewed || self == .approved }
}

enum SDDevelopmentAlertStatus: String, Codable, Sendable {
  case active
  case acknowledged
  case dismissed
  case resolved
  case archived
  case unknown

  init(from decoder: Decoder) throws {
    let value = try decoder.singleValueContainer().decode(String.self)
    self = Self(rawValue: value) ?? .unknown
  }
}

enum SDDevelopmentAlertSeverity: String, Codable, Sendable {
  case info
  case attention
  case high
  case unknown

  init(from decoder: Decoder) throws {
    let value = try decoder.singleValueContainer().decode(String.self)
    self = Self(rawValue: value) ?? .unknown
  }
}

enum SDDevelopmentReportType: String, Codable, CaseIterable, Sendable {
  case playerDevelopmentSummary = "player_development_summary"
  case coachCopilot = "coach_copilot"
  case parentUpdateDraft = "parent_update_draft"
  case rosterAttentionReport = "roster_attention_report"
  case developmentAlertReview = "development_alert_review"
}

enum SDDevelopmentReviewAction: String, Codable, Sendable {
  case review
  case edit
  case approve
  case reject
  case archive
}

enum SDDevelopmentAlertReviewAction: String, Codable, Sendable {
  case acknowledge
  case dismiss
  case resolve
  case archive
}

struct SDDevelopmentMetricDefinition: Identifiable, Codable, Equatable, Sendable {
  let id: UUID
  let canonicalKey: String
  let displayName: String
  let category: String
  let canonicalUnit: String?
  let preferredDirection: String
  let targetMin: Double?
  let targetMax: Double?
  let minimumSampleSize: Int

  enum CodingKeys: String, CodingKey {
    case id
    case canonicalKey = "canonical_key"
    case displayName = "display_name"
    case category
    case canonicalUnit = "canonical_unit"
    case preferredDirection = "preferred_direction"
    case targetMin = "target_min"
    case targetMax = "target_max"
    case minimumSampleSize = "minimum_sample_size"
  }
}

struct SDDevelopmentEvidence: Identifiable, Codable, Equatable, Sendable {
  var id: String { evidenceKey }
  let evidenceKey: String
  let sectionKey: String
  let sourceEntityType: String
  let sourceRecordId: String
  let canonicalMetricKey: String?
  let rawObservedValue: String?
  let normalizedNumericValue: Double?
  let unit: String?
  let observationDate: String?
  let comparisonValue: Double?
  let comparisonPeriod: String?
  let direction: String?
  let sampleSize: Int?
  let freshness: String
  let quality: SDDevelopmentQualityStatus
  let deterministicRuleId: String?
  let displayLabel: String
  let explanation: String
  let sourceMetadata: [String: SDJSONValue]
  let evidenceSnapshot: [String: SDJSONValue]

  enum CodingKeys: String, CodingKey {
    case evidenceKey = "evidence_key"
    case sectionKey = "section_key"
    case sourceEntityType = "source_entity_type"
    case sourceRecordId = "source_record_id"
    case canonicalMetricKey = "canonical_metric_key"
    case rawObservedValue = "raw_observed_value"
    case normalizedNumericValue = "normalized_numeric_value"
    case unit
    case observationDate = "observation_date"
    case comparisonValue = "comparison_value"
    case comparisonPeriod = "comparison_period"
    case direction
    case sampleSize = "sample_size"
    case freshness
    case quality
    case deterministicRuleId = "deterministic_rule_id"
    case displayLabel = "display_label"
    case explanation
    case sourceMetadata = "source_metadata"
    case evidenceSnapshot = "evidence_snapshot"
  }
}

struct SDDevelopmentTrend: Identifiable, Codable, Equatable, Sendable {
  var id: String { canonicalMetricKey }
  let canonicalMetricKey: String
  let displayName: String
  let unit: String?
  let latestValue: Double
  let priorValue: Double?
  let absoluteChange: Double?
  let percentageChange: Double?
  let rollingAverage: Double?
  let recentWindowAverage: Double?
  let priorWindowAverage: Double?
  let bestValue: Double?
  let worstValue: Double?
  let sampleCount: Int
  let observationFrequencyDays: Double?
  let freshness: String
  let quality: SDDevelopmentQualityStatus
  let interpretation: String
  let ruleId: String
  let evidenceKeys: [String]

  enum CodingKeys: String, CodingKey {
    case canonicalMetricKey = "canonical_metric_key"
    case displayName = "display_name"
    case unit
    case latestValue = "latest_value"
    case priorValue = "prior_value"
    case absoluteChange = "absolute_change"
    case percentageChange = "percentage_change"
    case rollingAverage = "rolling_average"
    case recentWindowAverage = "recent_window_average"
    case priorWindowAverage = "prior_window_average"
    case bestValue = "best_value"
    case worstValue = "worst_value"
    case sampleCount = "sample_count"
    case observationFrequencyDays = "observation_frequency_days"
    case freshness, quality, interpretation
    case ruleId = "rule_id"
    case evidenceKeys = "evidence_keys"
  }
}

struct SDDevelopmentEvidenceCoverage: Codable, Equatable, Sendable {
  let testingEntries: Int
  let metricObservations: Int
  let dailyLogs: Int
  let programAssignments: Int
  let bpSessions: Int

  enum CodingKeys: String, CodingKey {
    case testingEntries = "testing_entries"
    case metricObservations = "metric_observations"
    case dailyLogs = "daily_logs"
    case programAssignments = "program_assignments"
    case bpSessions = "bp_sessions"
  }
}

struct SDDevelopmentEvidencePack: Codable, Equatable, Sendable {
  let schemaVersion: String
  let organizationId: UUID
  let playerId: UUID
  let playerName: String
  let reportType: String
  let windowStart: String
  let windowEnd: String
  let evidenceCutoff: String
  let qualityStatus: SDDevelopmentQualityStatus
  let dataFreshness: String
  let coverage: SDDevelopmentEvidenceCoverage
  let trends: [SDDevelopmentTrend]
  let evidence: [SDDevelopmentEvidence]
  let missingDataWarnings: [String]
  let staleDataWarnings: [String]
  let unitConflicts: [String]
  let lowSampleWarnings: [String]

  enum CodingKeys: String, CodingKey {
    case schemaVersion = "schema_version"
    case organizationId = "organization_id"
    case playerId = "player_id"
    case playerName = "player_name"
    case reportType = "report_type"
    case windowStart = "window_start"
    case windowEnd = "window_end"
    case evidenceCutoff = "evidence_cutoff"
    case qualityStatus = "quality_status"
    case dataFreshness = "data_freshness"
    case coverage, trends, evidence
    case missingDataWarnings = "missing_data_warnings"
    case staleDataWarnings = "stale_data_warnings"
    case unitConflicts = "unit_conflicts"
    case lowSampleWarnings = "low_sample_warnings"
  }
}

struct SDDevelopmentReportSection: Codable, Equatable, Sendable {
  let title: String
  let explanation: String
  let evidenceKeys: [String]

  enum CodingKeys: String, CodingKey {
    case title, explanation
    case evidenceKeys = "evidence_keys"
  }
}

struct SDDevelopmentEvidenceSummaryItem: Codable, Equatable, Sendable {
  let label: String
  let explanation: String
  let evidenceKey: String

  enum CodingKeys: String, CodingKey {
    case label, explanation
    case evidenceKey = "evidence_key"
  }
}

struct SDDevelopmentReportContent: Codable, Equatable, Sendable {
  let overview: String
  let positiveTrends: [SDDevelopmentReportSection]
  let developmentPriorities: [SDDevelopmentReportSection]
  let consistencyAndAttendance: String
  let dataGaps: [String]
  let coachReviewQuestions: [String]
  let evidenceSummary: [SDDevelopmentEvidenceSummaryItem]

  enum CodingKeys: String, CodingKey {
    case overview
    case positiveTrends = "positive_trends"
    case developmentPriorities = "development_priorities"
    case consistencyAndAttendance = "consistency_and_attendance"
    case dataGaps = "data_gaps"
    case coachReviewQuestions = "coach_review_questions"
    case evidenceSummary = "evidence_summary"
  }
}

struct SDDevelopmentReport: Identifiable, Codable, Equatable, Sendable {
  let id: UUID
  let organizationId: UUID
  let playerId: UUID?
  let teamId: UUID?
  let reportType: String
  let requestedBy: UUID
  let intendedAudience: String
  let audience: SDDevelopmentRecordAudience?
  let reportingWindowStart: String
  let reportingWindowEnd: String
  let status: SDDevelopmentReportStatus
  let qualityStatus: SDDevelopmentQualityStatus
  let structuredContent: SDDevelopmentReportContent
  let renderedText: String
  let generationMode: String
  let provider: String
  let modelIdentifier: String?
  let generatorVersion: String
  let promptVersion: String
  let inputCutoff: String
  let generatedAt: String?
  let reviewedAt: String?
  let reviewedBy: UUID?
  let approvedAt: String?
  let rejectedAt: String?
  let archivedAt: String?
  let coachEdits: [String: SDJSONValue]
  let reviewNotes: String?
  let confidence: Double?
  let dataFreshness: String
  let missingDataWarnings: [String]
  let evidenceFingerprint: String?
  let createdAt: String
  let updatedAt: String

  enum CodingKeys: String, CodingKey {
    case id
    case organizationId = "org_id"
    case playerId = "player_id"
    case teamId = "team_id"
    case reportType = "report_type"
    case requestedBy = "requested_by"
    case intendedAudience = "intended_audience"
    case audience
    case reportingWindowStart = "reporting_window_start"
    case reportingWindowEnd = "reporting_window_end"
    case status
    case qualityStatus = "quality_status"
    case structuredContent = "structured_content"
    case renderedText = "rendered_text"
    case generationMode = "generation_mode"
    case provider
    case modelIdentifier = "model_identifier"
    case generatorVersion = "generator_version"
    case promptVersion = "prompt_version"
    case inputCutoff = "input_cutoff"
    case generatedAt = "generated_at"
    case reviewedAt = "reviewed_at"
    case reviewedBy = "reviewed_by"
    case approvedAt = "approved_at"
    case rejectedAt = "rejected_at"
    case archivedAt = "archived_at"
    case coachEdits = "coach_edits"
    case reviewNotes = "review_notes"
    case confidence
    case dataFreshness = "data_freshness"
    case missingDataWarnings = "missing_data_warnings"
    case evidenceFingerprint = "evidence_fingerprint"
    case createdAt = "created_at"
    case updatedAt = "updated_at"
  }
}

struct SDDevelopmentReviewEvent: Identifiable, Codable, Equatable, Sendable {
  let id: UUID
  let reportId: UUID
  let organizationId: UUID
  let actorId: UUID
  let eventType: String
  let fromStatus: String?
  let toStatus: String
  let reviewNotes: String?
  let createdAt: String

  enum CodingKeys: String, CodingKey {
    case id
    case reportId = "report_id"
    case organizationId = "org_id"
    case actorId = "actor_id"
    case eventType = "event_type"
    case fromStatus = "from_status"
    case toStatus = "to_status"
    case reviewNotes = "review_notes"
    case createdAt = "created_at"
  }
}

struct SDDevelopmentReportDetail: Codable, Equatable, Sendable {
  let report: SDDevelopmentReport
  let evidence: [SDDevelopmentEvidence]
  let reviewHistory: [SDDevelopmentReviewEvent]

  enum CodingKeys: String, CodingKey {
    case report, evidence
    case reviewHistory = "review_history"
  }
}

struct SDDevelopmentAlert: Identifiable, Codable, Equatable, Sendable {
  let id: UUID
  let organizationId: UUID
  let playerId: UUID
  let reportId: UUID?
  let audience: SDDevelopmentRecordAudience?
  let alertType: String
  let severity: SDDevelopmentAlertSeverity
  let status: SDDevelopmentAlertStatus
  let firstDetectedAt: String
  let lastDetectedAt: String
  let evidenceWindowStart: String
  let evidenceWindowEnd: String
  let ruleVersion: String
  let explanation: String
  let recommendedHumanAction: String
  let dataFreshness: String
  let evidenceQuality: SDDevelopmentQualityStatus
  let deduplicationKey: String
  let playerName: String?

  enum CodingKeys: String, CodingKey {
    case id
    case organizationId = "org_id"
    case playerId = "player_id"
    case reportId = "report_id"
    case audience
    case alertType = "alert_type"
    case severity, status
    case firstDetectedAt = "first_detected_at"
    case lastDetectedAt = "last_detected_at"
    case evidenceWindowStart = "evidence_window_start"
    case evidenceWindowEnd = "evidence_window_end"
    case ruleVersion = "rule_version"
    case explanation
    case recommendedHumanAction = "recommended_human_action"
    case dataFreshness = "data_freshness"
    case evidenceQuality = "evidence_quality"
    case deduplicationKey = "deduplication_key"
    case playerName = "player_name"
  }
}

struct SDDevelopmentAlertEvidence: Identifiable, Codable, Equatable, Sendable {
  var id: String { evidenceKey }
  let evidenceKey: String
  let sourceEntityType: String
  let sourceRecordId: String
  let canonicalMetricKey: String?
  let observationDate: String?
  let displayLabel: String
  let explanation: String
  let evidenceSnapshot: [String: SDJSONValue]

  enum CodingKeys: String, CodingKey {
    case evidenceKey = "evidence_key"
    case sourceEntityType = "source_entity_type"
    case sourceRecordId = "source_record_id"
    case canonicalMetricKey = "canonical_metric_key"
    case observationDate = "observation_date"
    case displayLabel = "display_label"
    case explanation
    case evidenceSnapshot = "evidence_snapshot"
  }
}

struct SDDevelopmentAlertEvent: Identifiable, Codable, Equatable, Sendable {
  let id: UUID
  let alertId: UUID
  let organizationId: UUID
  let actorId: UUID
  let eventType: String
  let fromStatus: String?
  let toStatus: String
  let notes: String?
  let createdAt: String

  enum CodingKeys: String, CodingKey {
    case id
    case alertId = "alert_id"
    case organizationId = "org_id"
    case actorId = "actor_id"
    case eventType = "event_type"
    case fromStatus = "from_status"
    case toStatus = "to_status"
    case notes
    case createdAt = "created_at"
  }
}

struct SDDevelopmentAlertDetail: Codable, Equatable, Sendable {
  let alert: SDDevelopmentAlert
  let evidence: [SDDevelopmentAlertEvidence]
  let reviewHistory: [SDDevelopmentAlertEvent]

  enum CodingKeys: String, CodingKey {
    case alert, evidence
    case reviewHistory = "review_history"
  }
}

struct SDDevelopmentEvidencePackResponse: Codable, Equatable, Sendable {
  let evidencePack: SDDevelopmentEvidencePack
  enum CodingKeys: String, CodingKey { case evidencePack = "evidence_pack" }
}

struct SDDevelopmentGenerateResponse: Codable, Equatable, Sendable {
  let report: SDDevelopmentReport
  let reused: Bool
  let evidencePack: SDDevelopmentEvidencePack
  let playerAlerts: [SDDevelopmentAlert]?
  enum CodingKeys: String, CodingKey {
    case report, reused
    case evidencePack = "evidence_pack"
    case playerAlerts = "player_alerts"
  }
}

struct SDDevelopmentReportsResponse: Codable, Equatable, Sendable {
  let reports: [SDDevelopmentReport]
}

struct SDDevelopmentAlertsResponse: Codable, Equatable, Sendable {
  let alerts: [SDDevelopmentAlert]
}

struct SDDevelopmentReportResponse: Codable, Equatable, Sendable {
  let report: SDDevelopmentReport
}

struct SDDevelopmentAlertResponse: Codable, Equatable, Sendable {
  let alert: SDDevelopmentAlert
}

struct SDDevelopmentAlertDetectionResponse: Codable, Equatable, Sendable {
  let alerts: [SDDevelopmentAlert]
  let detectedCount: Int
  enum CodingKeys: String, CodingKey {
    case alerts
    case detectedCount = "detected_count"
  }
}

struct SDDevelopmentRosterAttentionResponse: Codable, Equatable, Sendable {
  let alerts: [SDDevelopmentAlert]
  let reportsAwaitingReview: [SDDevelopmentReport]
  enum CodingKeys: String, CodingKey {
    case alerts
    case reportsAwaitingReview = "reports_awaiting_review"
  }
}

struct SDDevelopmentPlayerRequest: Encodable, Equatable, Sendable {
  let action: String
  let organizationId: UUID
  let playerId: UUID
  let reportType: String?
  let windowStart: String?
  let windowEnd: String?
  let evidenceCutoff: String?

  enum CodingKeys: String, CodingKey {
    case action
    case organizationId = "org_id"
    case playerId = "player_id"
    case reportType = "report_type"
    case windowStart = "window_start"
    case windowEnd = "window_end"
    case evidenceCutoff = "evidence_cutoff"
  }
}

struct SDDevelopmentGenerateRequest: Encodable, Equatable, Sendable {
  let action = "generate_report"
  let organizationId: UUID
  let playerId: UUID
  let reportType: SDDevelopmentReportType
  let intendedAudience: String
  let windowStart: String
  let windowEnd: String
  let evidenceCutoff: String
  let idempotencyKey: UUID

  enum CodingKeys: String, CodingKey {
    case action
    case organizationId = "org_id"
    case playerId = "player_id"
    case reportType = "report_type"
    case intendedAudience = "intended_audience"
    case windowStart = "window_start"
    case windowEnd = "window_end"
    case evidenceCutoff = "evidence_cutoff"
    case idempotencyKey = "idempotency_key"
  }
}

struct SDDevelopmentPlayerGenerateRequest: Encodable, Equatable, Sendable {
  let action = "generate_player_report"
  let organizationId: UUID
  let playerId: UUID
  let windowStart: String
  let windowEnd: String
  let evidenceCutoff: String
  let idempotencyKey: UUID

  enum CodingKeys: String, CodingKey {
    case action
    case organizationId = "org_id"
    case playerId = "player_id"
    case windowStart = "window_start"
    case windowEnd = "window_end"
    case evidenceCutoff = "evidence_cutoff"
    case idempotencyKey = "idempotency_key"
  }
}

struct SDDevelopmentReportResourceRequest: Encodable, Equatable, Sendable {
  let action: String
  let organizationId: UUID
  let reportId: UUID

  enum CodingKeys: String, CodingKey {
    case action
    case organizationId = "org_id"
    case reportId = "report_id"
  }
}

struct SDDevelopmentAlertResourceRequest: Encodable, Equatable, Sendable {
  let action: String
  let organizationId: UUID
  let alertId: UUID

  enum CodingKeys: String, CodingKey {
    case action
    case organizationId = "org_id"
    case alertId = "alert_id"
  }
}

struct SDDevelopmentOrganizationRequest: Encodable, Equatable, Sendable {
  let action: String
  let organizationId: UUID
  enum CodingKeys: String, CodingKey {
    case action
    case organizationId = "org_id"
  }
}

struct SDDevelopmentReportReviewRequest: Encodable, Equatable, Sendable {
  let action = "review_report"
  let organizationId: UUID
  let reportId: UUID
  let reviewAction: SDDevelopmentReviewAction
  let reviewNotes: String?
  let coachEdits: [String: SDJSONValue]

  enum CodingKeys: String, CodingKey {
    case action
    case organizationId = "org_id"
    case reportId = "report_id"
    case reviewAction = "review_action"
    case reviewNotes = "review_notes"
    case coachEdits = "coach_edits"
  }
}

struct SDDevelopmentAlertReviewRequest: Encodable, Equatable, Sendable {
  let action = "review_alert"
  let organizationId: UUID
  let alertId: UUID
  let reviewAction: SDDevelopmentAlertReviewAction
  let reviewNotes: String?

  enum CodingKeys: String, CodingKey {
    case action
    case organizationId = "org_id"
    case alertId = "alert_id"
    case reviewAction = "review_action"
    case reviewNotes = "review_notes"
  }
}

struct SDDevelopmentWindow: Equatable, Sendable {
  let start: String
  let end: String

  static func trailingDays(_ days: Int, endingAt date: Date = Date(), calendar: Calendar = .current) -> Self {
    let formatter = DateFormatter()
    formatter.calendar = calendar
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd"
    let startDate = calendar.date(byAdding: .day, value: -max(1, days), to: date) ?? date
    return Self(start: formatter.string(from: startDate), end: formatter.string(from: date))
  }
}

struct SDDevelopmentRequestToken: Equatable, Sendable {
  let organizationId: UUID
  let userId: UUID
  let nonce: UUID

  func accepts(organizationId: UUID?, userId: UUID?) -> Bool {
    self.organizationId == organizationId && self.userId == userId
  }
}

enum SDDevelopmentPresentationAuthorization {
  static func isVisible(membership: SDOrgMembership?) -> Bool {
    membership?.isActive == true && membership?.isStaff == true
  }

  static func isVisible(
    membership: SDOrgMembership?,
    selectedOrganizationId: UUID?,
    resourceOrganizationId: UUID
  ) -> Bool {
    selectedOrganizationId == resourceOrganizationId &&
      membership?.org_id == resourceOrganizationId &&
      isVisible(membership: membership)
  }

  static func isCopilotVisible(
    membership: SDOrgMembership?,
    audience: SDCopilotAudience,
    userId: UUID?,
    playerId: UUID
  ) -> Bool {
    guard membership?.isActive == true else { return false }
    switch audience {
    case .coach:
      return membership?.isStaff == true
    case .player:
      return membership?.normalizedRole == "player" && userId == playerId
    }
  }
}

enum SDDevelopmentEvidenceRenderingState: Equatable, Sendable {
  case empty
  case missingData([String])
  case evidence(count: Int)

  static func resolve(pack: SDDevelopmentEvidencePack?) -> Self {
    guard let pack else { return .empty }
    if pack.evidence.isEmpty { return .missingData(pack.missingDataWarnings) }
    return .evidence(count: pack.evidence.count)
  }
}

enum SDDevelopmentNavigationDestination: Equatable, Sendable {
  case playerWorkspace(UUID)
  case rosterAttention
}

@MainActor
protocol PlayerDevelopmentAIClient: AnyObject {
  func buildDevelopmentEvidencePack(
    organizationId: UUID,
    playerId: UUID,
    reportType: SDDevelopmentReportType,
    window: SDDevelopmentWindow,
    evidenceCutoff: Date
  ) async throws -> SDDevelopmentEvidencePack
  func generateDevelopmentReport(
    organizationId: UUID,
    playerId: UUID,
    reportType: SDDevelopmentReportType,
    intendedAudience: String,
    window: SDDevelopmentWindow,
    evidenceCutoff: Date,
    idempotencyKey: UUID
  ) async throws -> SDDevelopmentGenerateResponse
  func listDevelopmentReports(organizationId: UUID, playerId: UUID) async throws -> [SDDevelopmentReport]
  func developmentReportDetail(organizationId: UUID, reportId: UUID) async throws -> SDDevelopmentReportDetail
  func reviewDevelopmentReport(
    organizationId: UUID,
    reportId: UUID,
    action: SDDevelopmentReviewAction,
    notes: String?,
    coachEdits: [String: SDJSONValue]
  ) async throws -> SDDevelopmentReport
  func listDevelopmentAlerts(organizationId: UUID, playerId: UUID) async throws -> [SDDevelopmentAlert]
  func developmentAlertDetail(organizationId: UUID, alertId: UUID) async throws -> SDDevelopmentAlertDetail
  func runDevelopmentAlertDetection(
    organizationId: UUID,
    playerId: UUID,
    window: SDDevelopmentWindow,
    evidenceCutoff: Date
  ) async throws -> SDDevelopmentAlertDetectionResponse
  func reviewDevelopmentAlert(
    organizationId: UUID,
    alertId: UUID,
    action: SDDevelopmentAlertReviewAction,
    notes: String?
  ) async throws -> SDDevelopmentAlert
  func generatePlayerDevelopmentReport(
    organizationId: UUID,
    playerId: UUID,
    window: SDDevelopmentWindow,
    evidenceCutoff: Date,
    idempotencyKey: UUID
  ) async throws -> SDDevelopmentGenerateResponse
  func playerDevelopmentReportDetail(organizationId: UUID, reportId: UUID) async throws -> SDDevelopmentReportDetail
  func archivePlayerDevelopmentReport(organizationId: UUID, reportId: UUID) async throws -> SDDevelopmentReport
  func playerDevelopmentAlertDetail(organizationId: UUID, alertId: UUID) async throws -> SDDevelopmentAlertDetail
  func dismissPlayerDevelopmentAlert(organizationId: UUID, alertId: UUID) async throws -> SDDevelopmentAlert
  func developmentRosterAttention(organizationId: UUID) async throws -> SDDevelopmentRosterAttentionResponse
}
