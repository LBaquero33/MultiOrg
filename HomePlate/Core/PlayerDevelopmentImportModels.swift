import Foundation

enum SDDevelopmentImportProvider: String, Codable, CaseIterable, Identifiable, Sendable {
  case genericCSV = "generic_csv"
  case rapsodo
  case hittrax
  case trackman
  case blast
  case pocketRadar = "pocket_radar"
  case strengthTesting = "strength_testing"

  var id: String { rawValue }
  var label: String {
    switch self {
    case .genericCSV: "Generic CSV / TSV"
    case .rapsodo: "Rapsodo (automatic detection)"
    case .hittrax: "HitTrax (manual mapping)"
    case .trackman: "TrackMan Radar (automatic detection)"
    case .blast: "Blast (manual mapping)"
    case .pocketRadar: "Pocket Radar (manual mapping)"
    case .strengthTesting: "Strength Testing (manual mapping)"
    }
  }
}

enum SDDevelopmentImportFileShape: String, Codable, CaseIterable, Identifiable, Sendable {
  case wide
  case long
  var id: String { rawValue }
}

enum SDDevelopmentImportStatus: String, Codable, Sendable {
  case pending, processing, canceled, uploaded, inspecting
  case mappingRequired = "mapping_required"
  case playerResolutionRequired = "player_resolution_required"
  case validating, ready, importing, completed
  case completedWithErrors = "completed_with_errors"
  case failed, archived, unknown

  init(from decoder: Decoder) throws {
    let value = try decoder.singleValueContainer().decode(String.self)
    self = Self(rawValue: value) ?? .unknown
  }

  var label: String { rawValue.replacingOccurrences(of: "_", with: " ").capitalized }
  var isFinished: Bool { self == .completed || self == .completedWithErrors || self == .failed || self == .archived }
}

enum SDDevelopmentImportRecoveryAction: Equatable, Sendable {
  case resumeValidation
  case startOver
  case none
}

enum SDDevelopmentImportRecoveryPolicy {
  static func action(
    errorCode: String?,
    jobStatus: SDDevelopmentImportStatus?
  ) -> SDDevelopmentImportRecoveryAction {
    if errorCode == "validation_persistence_failed",
       let jobStatus,
       [.validating, .playerResolutionRequired, .ready].contains(jobStatus) {
      return .resumeValidation
    }
    if [
      "import_artifact_expired",
      "file_identity_changed",
      "upload_not_found",
      "validation_input_changed",
    ].contains(errorCode ?? "") {
      return .startOver
    }
    return .none
  }
}

struct SDDevelopmentImportJob: Identifiable, Codable, Equatable, Sendable {
  let id: UUID
  let organizationId: UUID
  let playerId: UUID?
  let requestedBy: UUID
  let provider: String?
  let fileName: String?
  let originalFileType: String?
  let fileSHA256: String?
  let fileSizeBytes: Int?
  let parserVersion: String
  var detectedExportType: String? = nil
  var adapterVersion: String? = nil
  var detectionConfidence: String? = nil
  var unitSystem: String? = nil
  var importTimezone: String? = nil
  let mappingVersion: String?
  let status: SDDevelopmentImportStatus
  let rowCount: Int
  let acceptedRows: Int
  let rejectedRows: Int
  let unmatchedPlayerRows: Int
  let warningCount: Int
  let safeErrorCode: String?
  let safeErrorSummary: String?
  let createdAt: String
  let completedAt: String?
  let archivedAt: String?

  enum CodingKeys: String, CodingKey {
    case id, provider, status
    case organizationId = "org_id"
    case playerId = "player_id"
    case requestedBy = "requested_by"
    case fileName = "file_name"
    case originalFileType = "original_file_type"
    case fileSHA256 = "file_sha256"
    case fileSizeBytes = "file_size_bytes"
    case parserVersion = "parser_version"
    case detectedExportType = "detected_export_type"
    case adapterVersion = "adapter_version"
    case detectionConfidence = "detection_confidence"
    case unitSystem = "unit_system"
    case importTimezone = "import_timezone"
    case mappingVersion = "mapping_version"
    case rowCount = "row_count"
    case acceptedRows = "accepted_rows"
    case rejectedRows = "rejected_rows"
    case unmatchedPlayerRows = "unmatched_player_rows"
    case warningCount = "warning_count"
    case safeErrorCode = "safe_error_code"
    case safeErrorSummary = "safe_error_summary"
    case createdAt = "created_at"
    case completedAt = "completed_at"
    case archivedAt = "archived_at"
  }
}

struct SDDevelopmentImportUploadTarget: Codable, Equatable, Sendable {
  let bucket: String
  let path: String
  let maxFileBytes: Int
  let upsert: Bool
  enum CodingKeys: String, CodingKey {
    case bucket, path, upsert
    case maxFileBytes = "max_file_bytes"
  }
}

struct SDDevelopmentImportInspection: Codable, Equatable, Sendable {
  let detectedFileType: String
  let detectedDelimiter: String
  let headers: [String]
  let normalizedHeaders: [String]
  let rowCount: Int
  let previewRows: [[String]]
  let warnings: [String]
  let headerFingerprint: String
  let providerAdapterActive: Bool
  var detection: SDDevelopmentImportDetection? = nil
  var suggestedMapping: SDDevelopmentImportMapping? = nil
  enum CodingKeys: String, CodingKey {
    case headers, warnings
    case detectedFileType = "detected_file_type"
    case detectedDelimiter = "detected_delimiter"
    case normalizedHeaders = "normalized_headers"
    case rowCount = "row_count"
    case previewRows = "preview_rows"
    case headerFingerprint = "header_fingerprint"
    case providerAdapterActive = "provider_adapter_active"
    case detection
    case suggestedMapping = "suggested_mapping"
  }
}

struct SDDevelopmentImportDetection: Codable, Equatable, Sendable {
  let providerKey: String
  let exportType: String
  let adapterVersion: String
  let confidence: String
  let matchedRequiredSignatures: [String]
  let matchedOptionalSignatures: [String]
  let missingSignatures: [String]
  let warnings: [String]
  let automaticMappingSafe: Bool
  let protectedColumns: [String]
  let unsupportedColumns: [String]
  let providerPlayerID: String?
  let providerPlayerName: String?
  enum CodingKeys: String, CodingKey {
    case confidence, warnings
    case providerKey = "provider_key"
    case exportType = "export_type"
    case adapterVersion = "adapter_version"
    case matchedRequiredSignatures = "matched_required_signatures"
    case matchedOptionalSignatures = "matched_optional_signatures"
    case missingSignatures = "missing_signatures"
    case automaticMappingSafe = "automatic_mapping_safe"
    case protectedColumns = "protected_columns"
    case unsupportedColumns = "unsupported_columns"
    case providerPlayerID = "provider_player_id"
    case providerPlayerName = "provider_player_name"
  }

  var title: String {
    switch exportType {
    case "rapsodo_hitting": "Rapsodo Hitting detected"
    case "rapsodo_pitching": "Rapsodo Pitching detected"
    case "trackman_radar": "TrackMan Radar detected"
    default: "Generic CSV mapping"
    }
  }
}

struct SDDevelopmentImportWideMetricMapping: Codable, Equatable, Sendable {
  let column: String
  let metricKey: String
  let sourceUnit: String?
  enum CodingKeys: String, CodingKey {
    case column
    case metricKey = "metricKey"
    case sourceUnit = "sourceUnit"
  }
}

struct SDDevelopmentImportColumnMapping: Codable, Equatable, Sendable {
  var playerExternalID: String? = nil
  var playerName: String? = nil
  var playerUsername: String? = nil
  var playerEmail: String? = nil
  var pitcherExternalID: String? = nil
  var pitcherName: String? = nil
  var batterExternalID: String? = nil
  var batterName: String? = nil
  var birthYear: String? = nil
  var observationDate: String? = nil
  var observationTimestamp: String? = nil
  var metric: String? = nil
  var value: String? = nil
  var unit: String? = nil
  var sampleSize: String? = nil
  var sessionIdentifier: String? = nil
  var sourceEventID: String? = nil
  var pitchType: String? = nil
  var swingType: String? = nil
  var team: String? = nil

  enum CodingKeys: String, CodingKey {
    case playerExternalID = "player_external_id"
    case playerName = "player_name"
    case playerUsername = "player_username"
    case playerEmail = "player_email"
    case pitcherExternalID = "pitcher_external_id"
    case pitcherName = "pitcher_name"
    case batterExternalID = "batter_external_id"
    case batterName = "batter_name"
    case birthYear = "birth_year"
    case observationDate = "observation_date"
    case observationTimestamp = "observation_timestamp"
    case metric, value, unit
    case sampleSize = "sample_size"
    case sessionIdentifier = "session_identifier"
    case sourceEventID = "source_event_id"
    case pitchType = "pitch_type"
    case swingType = "swing_type"
    case team
  }
}

struct SDDevelopmentImportMapping: Codable, Equatable, Sendable {
  var shape: SDDevelopmentImportFileShape
  var timezone: String
  var dateFormat: String?
  var columns: SDDevelopmentImportColumnMapping
  var wideMetrics: [SDDevelopmentImportWideMetricMapping]?
  var longMetricKeys: [String: String]?
  var longSourceUnits: [String: String]?
  var contextColumns: [String]?
  var playerResolutions: [String: String]?
  var adapterVersion: String? = nil
  var detectedExportType: String? = nil
  var unitSystem: String? = nil

  enum CodingKeys: String, CodingKey {
    case shape, timezone, columns
    case dateFormat = "dateFormat"
    case wideMetrics = "wideMetrics"
    case longMetricKeys = "longMetricKeys"
    case longSourceUnits = "longSourceUnits"
    case contextColumns = "contextColumns"
    case playerResolutions = "playerResolutions"
    case adapterVersion = "adapterVersion"
    case detectedExportType = "detectedExportType"
    case unitSystem = "unitSystem"
  }
}

struct SDDevelopmentImportPreviewRow: Identifiable, Codable, Equatable, Sendable {
  var id: String { "\(sourceRowNumber):\(metricKey ?? "none")" }
  let sourceRowNumber: Int
  let playerSourceKey: String
  let playerMatchState: String
  let playerId: UUID?
  let playerLabel: String
  let metricKey: String?
  let metricDisplayName: String?
  let originalValue: String
  let originalUnit: String
  let normalizedValue: Double?
  let canonicalUnit: String?
  let observedAt: String?
  let acceptanceState: String
  let warnings: [String]
  let errors: [String]
  enum CodingKeys: String, CodingKey {
    case warnings, errors
    case sourceRowNumber, playerSourceKey, playerMatchState, playerId, playerLabel, metricKey
    case metricDisplayName, originalValue, originalUnit, normalizedValue
    case canonicalUnit, observedAt, acceptanceState
  }
}

struct SDDevelopmentImportPlayerCandidate: Identifiable, Codable, Equatable, Sendable {
  let id: UUID
  let fullName: String
  let username: String?
  enum CodingKeys: String, CodingKey {
    case id, username
    case fullName = "full_name"
  }
}

struct SDDevelopmentImportUnresolvedPlayerGroup: Identifiable, Equatable, Sendable {
  let sourceKey: String
  let playerLabel: String
  let playerMatchState: String
  let affectedObservationCount: Int

  var id: String { sourceKey }

  var providerPlayerIDHint: String? {
    let prefix = "external:"
    guard sourceKey.hasPrefix(prefix) else { return nil }
    let externalID = String(sourceKey.dropFirst(prefix.count))
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !externalID.isEmpty else { return nil }
    guard externalID.count > 4 else {
      return String(repeating: "•", count: externalID.count)
    }
    return "••••\(externalID.suffix(4))"
  }
}

struct SDDevelopmentImportValidationSummary: Codable, Equatable, Sendable {
  let totalRows: Int
  let generatedObservations: Int
  let acceptedRows: Int
  let rejectedRows: Int
  let unmatchedPlayerRows: Int
  let ambiguousPlayerRows: Int
  let warningCount: Int
  let duplicateRows: Int
}

struct SDDevelopmentImportMappingProfile: Identifiable, Codable, Equatable, Sendable {
  let id: UUID
  let organizationId: UUID
  let provider: String
  let mappingName: String
  let headerFingerprint: String
  let parserVersion: String
  let mappingVersion: String
  let fileShape: SDDevelopmentImportFileShape
  let mappingConfig: SDDevelopmentImportMapping
  let isActive: Bool
  let createdAt: String
  enum CodingKeys: String, CodingKey {
    case id, provider
    case organizationId = "org_id"
    case mappingName = "mapping_name"
    case headerFingerprint = "header_fingerprint"
    case parserVersion = "parser_version"
    case mappingVersion = "mapping_version"
    case fileShape = "file_shape"
    case mappingConfig = "mapping_config"
    case isActive = "is_active"
    case createdAt = "created_at"
  }
}

struct SDDevelopmentImportRowError: Identifiable, Codable, Equatable, Sendable {
  let id: UUID
  let sourceRowNumber: Int
  let acceptanceState: String
  let errorCodes: [String]
  let warningCodes: [String]
  let safeSummary: String
  enum CodingKeys: String, CodingKey {
    case id
    case sourceRowNumber = "source_row_number"
    case acceptanceState = "acceptance_state"
    case errorCodes = "error_codes"
    case warningCodes = "warning_codes"
    case safeSummary = "safe_summary"
  }
}

struct SDDevelopmentImportCreateResponse: Codable, Sendable {
  let job: SDDevelopmentImportJob
  let upload: SDDevelopmentImportUploadTarget
}
struct SDDevelopmentImportInspectResponse: Codable, Sendable {
  let job: SDDevelopmentImportJob
  let inspection: SDDevelopmentImportInspection
}
struct SDDevelopmentImportPreviewResponse: Codable, Sendable {
  let notice: String
  let status: String
  let summary: SDDevelopmentImportValidationSummary
  let rows: [SDDevelopmentImportPreviewRow]
  let detectedFileType: String
  let detectedDelimiter: String
  let headers: [String]
  var playerCandidates: [SDDevelopmentImportPlayerCandidate]? = nil
  var playerCandidatesTruncated: Bool? = nil
  enum CodingKeys: String, CodingKey {
    case notice, status, summary, rows, headers
    case playerCandidates = "player_candidates"
    case playerCandidatesTruncated = "player_candidates_truncated"
    case detectedFileType = "detected_file_type"
    case detectedDelimiter = "detected_delimiter"
  }
}

extension SDDevelopmentImportPreviewResponse {
  var unresolvedPlayerGroups: [SDDevelopmentImportUnresolvedPlayerGroup] {
    let unresolvedRows = rows.filter {
      $0.playerMatchState == "unmatched" || $0.playerMatchState == "ambiguous"
    }
    let groupedRows = Dictionary(grouping: unresolvedRows, by: \.playerSourceKey)
    return groupedRows.map { sourceKey, rows in
      let representative = rows.sorted(by: Self.previewRowSort).first
      return SDDevelopmentImportUnresolvedPlayerGroup(
        sourceKey: sourceKey,
        playerLabel: representative?.playerLabel ?? "Unknown imported player",
        playerMatchState: representative?.playerMatchState ?? "unmatched",
        affectedObservationCount: rows.count
      )
    }
    .sorted {
      let left = Self.stableSortKey($0.playerLabel)
      let right = Self.stableSortKey($1.playerLabel)
      return left == right ? $0.sourceKey < $1.sourceKey : left < right
    }
  }

  var sortedPlayerCandidates: [SDDevelopmentImportPlayerCandidate] {
    (playerCandidates ?? []).sorted {
      let left = Self.stableSortKey($0.fullName)
      let right = Self.stableSortKey($1.fullName)
      if left != right { return left < right }
      let leftUsername = Self.stableSortKey($0.username ?? "")
      let rightUsername = Self.stableSortKey($1.username ?? "")
      return leftUsername == rightUsername
        ? $0.id.uuidString < $1.id.uuidString
        : leftUsername < rightUsername
    }
  }

  private static func previewRowSort(
    _ left: SDDevelopmentImportPreviewRow,
    _ right: SDDevelopmentImportPreviewRow
  ) -> Bool {
    if left.sourceRowNumber != right.sourceRowNumber {
      return left.sourceRowNumber < right.sourceRowNumber
    }
    let leftMetric = left.metricKey ?? ""
    let rightMetric = right.metricKey ?? ""
    return leftMetric == rightMetric ? left.id < right.id : leftMetric < rightMetric
  }

  private static func stableSortKey(_ value: String) -> String {
    value.folding(
      options: [.caseInsensitive, .diacriticInsensitive],
      locale: Locale(identifier: "en_US_POSIX")
    )
  }
}
struct SDDevelopmentImportJobResponse: Codable, Sendable { let job: SDDevelopmentImportJob }
struct SDDevelopmentImportJobsResponse: Codable, Sendable { let jobs: [SDDevelopmentImportJob] }
struct SDDevelopmentImportMappingsResponse: Codable, Sendable { let mappings: [SDDevelopmentImportMappingProfile] }
struct SDDevelopmentImportMappingResponse: Codable, Sendable { let mapping: SDDevelopmentImportMappingProfile }
struct SDDevelopmentImportErrorsResponse: Codable, Sendable { let errors: [SDDevelopmentImportRowError] }
struct SDDevelopmentImportCommitResponse: Codable, Sendable {
  let job: SDDevelopmentImportJob
  let reused: Bool
}

struct SDDevelopmentImportContextToken: Equatable, Sendable {
  let organizationId: UUID
  let userId: UUID
  let nonce: UUID
  func accepts(organizationId: UUID?, userId: UUID?) -> Bool {
    self.organizationId == organizationId && self.userId == userId
  }
}

@MainActor
protocol PlayerDevelopmentImportClient: AnyObject {
  func createDevelopmentImportJob(organizationId: UUID, playerId: UUID?, provider: SDDevelopmentImportProvider, fileName: String, idempotencyKey: UUID) async throws -> SDDevelopmentImportCreateResponse
  func uploadDevelopmentImportFile(_ data: Data, target: SDDevelopmentImportUploadTarget, fileType: String) async throws
  func inspectDevelopmentImport(organizationId: UUID, jobId: UUID) async throws -> SDDevelopmentImportInspectResponse
  func saveDevelopmentImportMapping(organizationId: UUID, jobId: UUID, mapping: SDDevelopmentImportMapping, mappingName: String?) async throws -> SDDevelopmentImportJob
  func validateDevelopmentImport(organizationId: UUID, jobId: UUID) async throws -> SDDevelopmentImportPreviewResponse
  func getDevelopmentImportJob(organizationId: UUID, jobId: UUID) async throws -> SDDevelopmentImportJob
  func commitDevelopmentImport(organizationId: UUID, jobId: UUID) async throws -> SDDevelopmentImportCommitResponse
  func listDevelopmentImportJobs(organizationId: UUID) async throws -> [SDDevelopmentImportJob]
  func listDevelopmentImportMappings(organizationId: UUID, provider: SDDevelopmentImportProvider) async throws -> [SDDevelopmentImportMappingProfile]
  func archiveDevelopmentImportMapping(organizationId: UUID, mappingProfileId: UUID) async throws -> SDDevelopmentImportMappingProfile
  func listDevelopmentMetricDefinitions() async throws -> [SDDevelopmentMetricDefinition]
  func resolveDevelopmentImportPlayer(organizationId: UUID, jobId: UUID, sourceKey: String, playerId: UUID) async throws -> SDDevelopmentImportJob
  func listDevelopmentImportRowErrors(organizationId: UUID, jobId: UUID) async throws -> [SDDevelopmentImportRowError]
  func archiveDevelopmentImport(organizationId: UUID, jobId: UUID) async throws -> SDDevelopmentImportJob
}

enum SDDevelopmentImportPresentationAuthorization {
  static func isVisible(membership: SDOrgMembership?) -> Bool {
    membership?.isStaff == true
  }
}
