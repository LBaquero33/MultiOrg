import Foundation

enum SDGameEventType: String, Codable, CaseIterable, Hashable, Sendable {
  case practice, game, training
  case facilityBooking = "facility_booking"
  case testing, meeting
  case organizationEvent = "organization_event"
  case other

  var label: String {
    rawValue.replacingOccurrences(of: "_", with: " ").capitalized
  }

  var systemImage: String {
    switch self {
    case .practice: "figure.baseball"
    case .game: "baseball.diamond.bases"
    case .training: "dumbbell"
    case .facilityBooking: "building.2"
    case .testing: "chart.bar.doc.horizontal"
    case .meeting: "person.3"
    case .organizationEvent: "calendar.badge.clock"
    case .other: "calendar"
    }
  }
}

enum SDGameLifecycle: String, Codable, CaseIterable, Sendable {
  case draft, scheduled, pregame, live, delayed, suspended, postponed, canceled
  case final, forfeit
  case noContest = "no_contest"
}

enum SDEventVisibility: String, Codable, CaseIterable, Sendable {
  case organization, team, participants
  case staffOnly = "staff_only"
  case `private`
}

enum SDGameSite: String, Codable, CaseIterable, Sendable {
  case home, away, neutral
}

struct SDCanonicalEvent: Identifiable, Codable, Equatable, Sendable {
  let id: UUID
  let org_id: UUID
  let title: String
  let event_type: SDGameEventType
  let description: String?
  let scheduled_start: Date
  let scheduled_end: Date
  let arrival_time: Date?
  let timezone: String
  let location_name: String?
  let venue_address: String?
  let facility_id: UUID?
  let facility_booking_id: UUID?
  let team_id: UUID?
  let visibility: SDEventVisibility
  let status: SDGameLifecycle
  let recurrence: [String: SDJSONValue]
  let created_by: UUID
  let updated_by: UUID
  let created_at: Date?
  let updated_at: Date?
  let canceled_at: Date?
  let postponed_at: Date?
}

struct SDGame: Identifiable, Codable, Equatable, Sendable {
  let id: UUID
  let event_id: UUID
  let org_id: UUID
  let season_id: UUID?
  let team_id: UUID
  let opponent_name: String
  let opponent_org_id: UUID?
  let opponent_team_id: UUID?
  let site: SDGameSite
  let venue_name: String?
  let scheduled_innings: Int
  let ruleset_id: UUID?
  let ruleset_version: Int?
  let ruleset_snapshot: [String: SDJSONValue]
  let assigned_scorekeeper_id: UUID?
  let status: SDGameLifecycle
  let live_status: String
  let home_team_name: String
  let away_team_name: String
  let lineup_ready: Bool
  let game_version: Int
  let finalized_at: Date?
  let created_at: Date?
  let updated_at: Date?
}

struct SDGameCalendarItem: Identifiable, Codable, Equatable, Sendable {
  let event: SDCanonicalEvent
  let game: SDGame?
  var id: UUID { event.id }
}

struct SDEventParticipant: Identifiable, Codable, Equatable, Sendable {
  let id: UUID
  let org_id: UUID
  let event_id: UUID
  let participant_type: String
  let user_id: UUID?
  let team_id: UUID?
  let player_id: UUID?
  let role: String?
  let can_view: Bool
  let can_edit: Bool
  let can_score: Bool
}

struct SDEventAttendance: Identifiable, Codable, Equatable, Sendable {
  let id: UUID
  let org_id: UUID
  let event_id: UUID
  let player_id: UUID
  let availability: String
  let expected_attendance: Bool?
  let actual_attendance: String?
  let response_author_id: UUID?
  let notes: String?
  let responded_at: Date?
  let recorded_at: Date?
}

struct SDGameAttendanceRosterRow: Identifiable, Codable, Equatable, Sendable {
  var id: String { "\(event_id.uuidString):\(player_id.uuidString)" }
  let event_id: UUID
  let player_id: UUID
  let display_name: String
  let expected_attendance: Bool?
  let responded_at: Date?
}

enum SDGameAttendanceResponseGroup: String, CaseIterable, Identifiable, Sendable {
  case coming = "Coming"
  case notComing = "Not Coming"
  case noResponse = "No Response"

  var id: String { rawValue }

  func contains(_ row: SDGameAttendanceRosterRow) -> Bool {
    switch self {
    case .coming: return row.expected_attendance == true
    case .notComing: return row.expected_attendance == false
    case .noResponse: return row.expected_attendance == nil
    }
  }
}

struct SDCreateGameRequest: Encodable, Sendable {
  let p_org_id: UUID
  let p_team_id: UUID
  let p_title: String
  let p_opponent_name: String
  let p_scheduled_start: Date
  let p_scheduled_end: Date
  let p_arrival_time: Date?
  let p_timezone: String
  let p_site: String
  let p_venue_name: String?
  let p_facility_id: UUID?
  let p_scheduled_innings: Int
  let p_visibility: String
}

enum SDGameAuthorization {
  static func canOpen(
    item: SDGameCalendarItem,
    activeOrganizationId: UUID?
  ) -> Bool {
    item.event.org_id == activeOrganizationId
  }

  static func canScore(
    game: SDGame,
    userId: UUID?,
    membership: SDOrgMembership?,
    participants: [SDEventParticipant]
  ) -> Bool {
    guard game.org_id == membership?.org_id, membership?.isActive == true else { return false }
    if membership?.canAdministerOrganization == true { return true }
    return participants.contains {
      $0.event_id == game.event_id && $0.user_id == userId && $0.can_score
    }
  }
}

enum SDGameAttendanceAuthorization {
  static func canRespond(
    event: SDCanonicalEvent,
    userId: UUID?,
    membership: SDOrgMembership?
  ) -> Bool {
    guard event.event_type == .game,
          event.canceled_at == nil,
          event.status != .canceled,
          let userId,
          let membership else { return false }
    return membership.user_id == userId
      && membership.org_id == event.org_id
      && membership.isActive
      && membership.normalizedRole == "player"
  }
}
