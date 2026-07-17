import Foundation

enum SDTeamEventType: String, CaseIterable, Codable, Identifiable, Sendable {
  case practice, game, tournament, meeting, travel, custom
  var id: String { rawValue }
  var label: String { rawValue.capitalized }
  var systemImage: String {
    switch self {
    case .practice: "figure.baseball"
    case .game: "baseball.diamond.bases"
    case .tournament: "trophy"
    case .meeting: "person.3"
    case .travel: "bus"
    case .custom: "calendar.badge.plus"
    }
  }
}

enum SDTeamEventStatus: String, CaseIterable, Codable, Sendable {
  case draft, scheduled, confirmed, cancelled, completed, postponed
  var label: String { rawValue.capitalized }
}

enum SDTeamEventVisibility: String, CaseIterable, Codable, Sendable {
  case team
  case staffOnly = "staff_only"
}

struct SDTeamEvent: Identifiable, Codable, Equatable, Sendable {
  let id: UUID
  let organization_id: UUID
  let season_id: UUID
  let team_id: UUID
  var team_name: String? = nil
  let series_id: UUID?
  let occurrence_index: Int?
  let event_type: SDTeamEventType
  let title: String
  let description: String?
  let status: SDTeamEventStatus
  let start_at: String
  let end_at: String
  let arrival_at: String?
  let original_start_at: String
  let timezone: String
  let all_day: Bool
  let location_name: String?
  let address: String?
  let facility_id: UUID?
  let visibility: SDTeamEventVisibility
  let notes: String?
  let metadata: [String: SDJSONValue]?
  let created_at: String?
  let updated_at: String?
  let cancelled_at: String?
  let cancellation_reason: String?
  let sd_team_event_practices: [SDPracticeEventDetails]?
  let sd_team_event_games: [SDGameEventDetails]?
  let sd_team_event_tournaments: [SDTournamentEventDetails]?
  let sd_team_event_meetings: [SDMeetingEventDetails]?
  let sd_team_event_travel: [SDTravelEventDetails]?
  let sd_team_event_coaches: [SDTeamEventCoach]?

  var startDate: Date { SDTeamEventDateParser.date(start_at) ?? .distantPast }
  var endDate: Date { SDTeamEventDateParser.date(end_at) ?? .distantPast }
  var arrivalDate: Date? { arrival_at.flatMap(SDTeamEventDateParser.date) }
  var isActive: Bool { status != .cancelled }
  var uniformOrDressCode: String? {
    sd_team_event_practices?.first?.dress_code ?? sd_team_event_games?.first?.uniform
  }
}

struct SDPracticeEventDetails: Codable, Equatable, Sendable {
  let event_id: UUID
  let objectives: [String]
  let dress_code: String?
  let equipment_notes: String?
  let practice_plan_status: String
  let facility_resource_label: String?
}

struct SDGameEventDetails: Codable, Equatable, Sendable {
  let event_id: UUID
  let opponent: String
  let venue_side: String
  let game_status: String
  let uniform: String?
  let home_score: Int?
  let away_score: Int?
  let field_details: String?
}

struct SDTournamentEventDetails: Codable, Equatable, Sendable {
  let event_id: UUID
  let tournament_name: String
  let host: String?
  let tournament_start_date: String
  let tournament_end_date: String
  let parent_tournament_event_id: UUID?
}

struct SDMeetingEventDetails: Codable, Equatable, Sendable {
  let event_id: UUID
  let meeting_type: String
  let virtual_link: String?
}

struct SDTravelEventDetails: Codable, Equatable, Sendable {
  let event_id: UUID
  let departure_at: String?
  let destination: String
  let transportation_notes: String?
  let lodging_notes: String?
}

struct SDTeamEventCoach: Codable, Equatable, Sendable {
  let event_id: UUID
  let coach_id: UUID
  let assignment_role: String
}

struct SDTeamScheduleResponse: Decodable, Sendable {
  let ok: Bool
  let events: [SDTeamEvent]
}

struct SDTeamEventResponse: Decodable, Sendable {
  let ok: Bool
  let event: SDTeamEvent?
  let events: [SDTeamEvent]?
}

struct SDTeamEventConflict: Codable, Equatable, Identifiable, Sendable {
  let id: UUID?
  let title: String
  let type: String
  var stableID: String { "\(type):\(id?.uuidString ?? title)" }
}

struct SDTeamEventConflictsResponse: Decodable, Sendable {
  let ok: Bool
  let conflicts: [SDTeamEventConflict]
}

struct SDTeamEventDraft: Equatable, Sendable {
  var type: SDTeamEventType = .practice
  var title = ""
  var description = ""
  var status: SDTeamEventStatus = .draft
  var startAt = Date()
  var endAt = Date().addingTimeInterval(7_200)
  var arrivalAt: Date?
  var timezone = TimeZone.current.identifier
  var allDay = false
  var locationName = ""
  var address = ""
  var facilityId: UUID?
  var visibility: SDTeamEventVisibility = .team
  var notes = ""
  var opponent = ""
  var venueSide = "home"
  var uniform = ""
  var dressCode = ""
  var equipmentNotes = ""
  var objectives = ""
  var tournamentName = ""
  var tournamentHost = ""
  var meetingType = "team"
  var virtualLink = ""
  var destination = ""
  var transportationNotes = ""
  var lodgingNotes = ""
  var repeats = false
  var recurrenceFrequency = "weekly"
  var recurrenceInterval = 1
  var recurrenceWeekdays = [Calendar.current.component(.weekday, from: Date()) - 1]
  var recurrenceUsesEndDate = false
  var recurrenceEndDate = Calendar.current.date(byAdding: .month, value: 1, to: Date()) ?? Date()
  var occurrenceCount = 4

  init() {}

  init(event: SDTeamEvent) {
    type = event.event_type
    title = event.title
    description = event.description ?? ""
    status = event.status
    startAt = event.startDate
    endAt = event.endDate
    arrivalAt = event.arrivalDate
    timezone = event.timezone
    allDay = event.all_day
    locationName = event.location_name ?? ""
    address = event.address ?? ""
    facilityId = event.facility_id
    visibility = event.visibility
    notes = event.notes ?? ""
    if let practice = event.sd_team_event_practices?.first {
      objectives = practice.objectives.joined(separator: ", ")
      dressCode = practice.dress_code ?? ""
      equipmentNotes = practice.equipment_notes ?? ""
    }
    if let game = event.sd_team_event_games?.first {
      opponent = game.opponent
      venueSide = game.venue_side
      uniform = game.uniform ?? ""
    }
    if let tournament = event.sd_team_event_tournaments?.first {
      tournamentName = tournament.tournament_name
      tournamentHost = tournament.host ?? ""
    }
    if let meeting = event.sd_team_event_meetings?.first {
      meetingType = meeting.meeting_type
      virtualLink = meeting.virtual_link ?? ""
    }
    if let travel = event.sd_team_event_travel?.first {
      destination = travel.destination
      transportationNotes = travel.transportation_notes ?? ""
      lodgingNotes = travel.lodging_notes ?? ""
    }
  }
}

enum SDTeamEventDateParser {
  static func date(_ value: String) -> Date? {
    let fractional = ISO8601DateFormatter()
    fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
  }
}

enum SDTeamScheduleFilter: String, CaseIterable, Identifiable {
  case all = "All"
  case practices = "Practices"
  case games = "Games"
  case tournaments = "Tournaments"
  case meetings = "Meetings"
  case travel = "Travel"
  case custom = "Custom"
  var id: String { rawValue }
  func includes(_ type: SDTeamEventType) -> Bool {
    switch self {
    case .all: true
    case .practices: type == .practice
    case .games: type == .game
    case .tournaments: type == .tournament
    case .meetings: type == .meeting
    case .travel: type == .travel
    case .custom: type == .custom
    }
  }
}

enum SDTeamScheduleMode: String, CaseIterable, Identifiable {
  case upcoming = "Upcoming"
  case day = "Day"
  case week = "Week"
  case month = "Month"
  var id: String { rawValue }
}

extension String {
  var sdNilIfBlank: String? {
    let cleaned = trimmingCharacters(in: .whitespacesAndNewlines)
    return cleaned.isEmpty ? nil : cleaned
  }
}
