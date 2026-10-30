import Foundation

/// Display formatting only: source keys and values remain unchanged for sync/audits.
enum HPReadableValue {
  static func words(_ value: String) -> String {
    switch value.lowercased() {
    case "home_plate": return "Home Plate"
    case "inquiry": return "Request to book"
    case "disabled": return "Not bookable"
    case "paid": return "Paid booking"
    case "free": return "Free booking"
    default: return value.replacingOccurrences(of: "_", with: " ").capitalized
    }
  }

  static func date(_ value: String) -> String {
    if let date = HPTrainingCalendar.date(value) {
      return date.formatted(date: .abbreviated, time: .shortened)
    }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd"
    formatter.isLenient = false
    if value.count == 10, let date = formatter.date(from: value) {
      return date.formatted(date: .abbreviated, time: .omitted)
    }
    return value
  }

  static func field(_ field: SDDevelopmentField) -> String {
    if field.key.lowercased().contains("cents"), let cents = Int(field.value) {
      return HPMoneyField.format(cents: cents, currencyCode: "USD")
    }
    let formatted = date(field.value)
    if formatted != field.value { return formatted }
    let isStatus = ["status", "attendance", "source", "kind", "activity"].contains(where: field.key.lowercased().contains)
    let value = field.value.contains("_") || isStatus ? words(field.value) : field.value
    return [value, field.unit].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
  }

  static func uniqueFields(_ fields: [SDDevelopmentField]) -> [SDDevelopmentField] {
    var seen = Set<String>()
    return fields.filter { field in
      let label = field.label.lowercased().filter { $0.isLetter || $0.isNumber }
      if label == "date", fields.contains(where: { $0.label.lowercased().contains("starts") && $0.value == field.value }) { return false }
      return seen.insert(label + "|" + field.value + "|" + (field.unit ?? "")).inserted
    }
  }

  static func group(_ field: SDDevelopmentField) -> String {
    let key = field.key.lowercased()
    if ["price", "payment", "cents", "rate", "refund"].contains(where: key.contains) { return "Payment" }
    if ["date", "starts", "ends", "status", "attendance", "visible", "title", "source", "activity"].contains(where: key.contains) { return "Session details" }
    return "Results"
  }

  static func label(_ field: SDDevelopmentField) -> String {
    field.label.replacingOccurrences(of: "\\s*\\(?cents\\)?$", with: "", options: [.regularExpression, .caseInsensitive])
      .replacingOccurrences(of: "_", with: " ")
  }
}

enum SDDevelopmentStatus: String, Codable, Sendable {
  case submitted
  case missed
  case upcoming

  var title: String { rawValue.capitalized }

  var badgeKind: HPStatusKind {
    switch self {
    case .submitted: .success
    case .missed: .danger
    case .upcoming: .warning
    }
  }
}

enum SDDevelopmentActivityKind: String, Codable, Sendable {
  case program
  case dailyLog = "daily_log"
  case testing
  case session
  case providerImport = "provider_import"
  case providerMetric = "provider_metric"
}

enum SDDevelopmentMediaKind: String, Codable, Sendable {
  case programSetVideo = "program_set_video"
  case testingFieldVideo = "testing_field_video"
  case sessionVideo = "session_video"
  case importFile = "import_file"
}

enum SDDevelopmentPlaybackStatus: String, Codable, Sendable {
  case ready
  case needsConversion = "needs_conversion"
}

struct SDDevelopmentPlayer: Identifiable, Codable, Equatable, Sendable {
  var subject_type: String? = nil
  var analyticsAthleteId: UUID? { subject_type == "facility_athlete" ? id : nil }
  let id: UUID
  let name: String
  let avatar_path: String?
  let bio: String?
  let instagram_url: String?
  let perfect_game_url: String?
  let team_ids: [UUID]
  let team_names: [String]?
  let active_program_count: Int?
  let next_due_date: String?
  let latest_activity_date: String?
  let summary_status: String?
}

struct SDDevelopmentField: Codable, Equatable, Sendable {
  let key: String
  let label: String
  let value: String
  let unit: String?
}

struct SDProgramAssignmentSummary: Identifiable, Codable, Equatable, Sendable {
  let id: UUID
  let template_id: UUID
  let template_name: String
  let program_kind: String
  let start_date: String
  let end_date: String
  let status: String
  let notes: String?
}

struct SDDevelopmentActivity: Identifiable, Codable, Equatable, Sendable {
  let id: String
  let date: String
  let kind: SDDevelopmentActivityKind
  let source: String
  let title: String
  let subtitle: String?
  let details: [String: SDJSONValue]
  let fields: [SDDevelopmentField]?
  let notes: String?
  let warning: String?
}

struct SDDevelopmentMedia: Identifiable, Codable, Equatable, Sendable {
  let id: UUID
  let date: String
  let kind: SDDevelopmentMediaKind
  let title: String
  let file_name: String?
  let mime_type: String?
  let source: String
  let playback_status: SDDevelopmentPlaybackStatus
}

struct SDDevelopmentDay: Identifiable, Codable, Equatable, Sendable {
  var id: String { date }
  let date: String
  let status: SDDevelopmentStatus
  let scheduled: Bool
  let activity_count: Int
  let media_count: Int
  let activities: [SDDevelopmentActivity]
  let media: [SDDevelopmentMedia]
  var planned_work: [SDDevelopmentActivity]? = nil
}

struct SDProviderSessionSummary: Identifiable, Codable, Equatable, Sendable {
  let id: String
  let date: String
  let provider: String
  let activity_type: String
  let status: String
  let metric_count: Int
  let has_file: Bool
  let has_video: Bool
}

struct SDPlayerDevelopmentWorkspace: Codable, Equatable, Sendable {
  let schema_version: Int
  let organization_id: UUID
  let generated_at: String
  let sections: [String]
  let player: SDDevelopmentPlayer
  let assignments: [SDProgramAssignmentSummary]
  let days: [SDDevelopmentDay]
  let provider_sessions: [SDProviderSessionSummary]
}

struct SDDevelopmentPlayerListResponse: Codable, Equatable, Sendable {
  let schema_version: Int
  let organization_id: UUID
  let players: [SDDevelopmentPlayer]
}

struct SDDevelopmentDayDetailResponse: Codable, Equatable, Sendable {
  let schema_version: Int
  let organization_id: UUID
  let player: SDDevelopmentPlayer
  let day: SDDevelopmentDay?
}

struct SDDevelopmentPlaybackResponse: Codable, Equatable, Sendable {
  let url: String
  let expires_in: Int
  let playback_status: SDDevelopmentPlaybackStatus
}

struct SDPlayerDevelopmentWorkspaceRequest: Encodable {
  let action: String
  let org_id: UUID
  let player_id: UUID?
  let team_id: UUID?
  let start_date: String?
  let end_date: String?
  let media_id: UUID?

  private enum CodingKeys: String, CodingKey {
    case action
    case org_id
    case player_id
    case team_id
    case start_date
    case end_date
    case media_id
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(action, forKey: .action)
    try container.encode(org_id.uuidString.lowercased(), forKey: .org_id)
    try container.encodeIfPresent(player_id?.uuidString.lowercased(), forKey: .player_id)
    try container.encodeIfPresent(team_id?.uuidString.lowercased(), forKey: .team_id)
    try container.encodeIfPresent(start_date, forKey: .start_date)
    try container.encodeIfPresent(end_date, forKey: .end_date)
    try container.encodeIfPresent(media_id?.uuidString.lowercased(), forKey: .media_id)
  }
}
