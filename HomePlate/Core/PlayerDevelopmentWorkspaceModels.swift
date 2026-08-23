import Foundation

enum SDDevelopmentStatus: String, Codable, Sendable {
  case submitted
  case missed
  case upcoming

  var title: String { rawValue.capitalized }

  var badgeKind: HPStatusKind {
    switch self {
    case .submitted: .success
    case .missed: .danger
    case .upcoming: .info
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
  let id: UUID
  let name: String
  let avatar_path: String?
  let bio: String?
  let instagram_url: String?
  let perfect_game_url: String?
  let team_ids: [UUID]
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
}
