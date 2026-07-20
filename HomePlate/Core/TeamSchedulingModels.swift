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

  private enum CodingKeys: String, CodingKey {
    case id, organization_id, season_id, team_id, team_name, series_id, occurrence_index
    case event_type, title, description, status, start_at, end_at, arrival_at
    case original_start_at, timezone, all_day, location_name, address, facility_id
    case visibility, notes, metadata, created_at, updated_at, cancelled_at
    case cancellation_reason, sd_team_event_practices, sd_team_event_games
    case sd_team_event_tournaments, sd_team_event_meetings, sd_team_event_travel
    case sd_team_event_coaches
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(UUID.self, forKey: .id)
    organization_id = try container.decode(UUID.self, forKey: .organization_id)
    season_id = try container.decode(UUID.self, forKey: .season_id)
    team_id = try container.decode(UUID.self, forKey: .team_id)
    team_name = try? container.decodeIfPresent(String.self, forKey: .team_name)
    series_id = try? container.decodeIfPresent(UUID.self, forKey: .series_id)
    occurrence_index = try? container.decodeIfPresent(Int.self, forKey: .occurrence_index)
    event_type = try container.decode(SDTeamEventType.self, forKey: .event_type)
    title = (try? container.decode(String.self, forKey: .title)) ?? "Team Event"
    description = try? container.decodeIfPresent(String.self, forKey: .description)
    status = try container.decode(SDTeamEventStatus.self, forKey: .status)
    start_at = try container.decode(String.self, forKey: .start_at)
    end_at = try container.decode(String.self, forKey: .end_at)
    guard SDTeamEventDateParser.date(start_at) != nil,
          SDTeamEventDateParser.date(end_at) != nil else {
      throw DecodingError.dataCorruptedError(
        forKey: .start_at,
        in: container,
        debugDescription: "Canonical event dates are invalid."
      )
    }
    arrival_at = try? container.decodeIfPresent(String.self, forKey: .arrival_at)
    original_start_at = (try? container.decode(String.self, forKey: .original_start_at)) ?? start_at
    timezone = (try? container.decode(String.self, forKey: .timezone)) ?? "UTC"
    all_day = (try? container.decode(Bool.self, forKey: .all_day)) ?? false
    location_name = try? container.decodeIfPresent(String.self, forKey: .location_name)
    address = try? container.decodeIfPresent(String.self, forKey: .address)
    facility_id = try? container.decodeIfPresent(UUID.self, forKey: .facility_id)
    visibility = try container.decode(SDTeamEventVisibility.self, forKey: .visibility)
    notes = try? container.decodeIfPresent(String.self, forKey: .notes)
    metadata = try? container.decodeIfPresent([String: SDJSONValue].self, forKey: .metadata)
    created_at = try? container.decodeIfPresent(String.self, forKey: .created_at)
    updated_at = try? container.decodeIfPresent(String.self, forKey: .updated_at)
    cancelled_at = try? container.decodeIfPresent(String.self, forKey: .cancelled_at)
    cancellation_reason = try? container.decodeIfPresent(String.self, forKey: .cancellation_reason)
    sd_team_event_practices = Self.lossyArray(SDPracticeEventDetails.self, from: container, forKey: .sd_team_event_practices)
    sd_team_event_games = Self.lossyArray(SDGameEventDetails.self, from: container, forKey: .sd_team_event_games)
    sd_team_event_tournaments = Self.lossyArray(SDTournamentEventDetails.self, from: container, forKey: .sd_team_event_tournaments)
    sd_team_event_meetings = Self.lossyArray(SDMeetingEventDetails.self, from: container, forKey: .sd_team_event_meetings)
    sd_team_event_travel = Self.lossyArray(SDTravelEventDetails.self, from: container, forKey: .sd_team_event_travel)
    sd_team_event_coaches = Self.lossyArray(SDTeamEventCoach.self, from: container, forKey: .sd_team_event_coaches)
  }

  private static func lossyArray<Value: Decodable>(
    _ type: Value.Type,
    from container: KeyedDecodingContainer<CodingKeys>,
    forKey key: CodingKeys
  ) -> [Value]? {
    guard container.contains(key) else { return nil }
    let rows = try? container.decode([SDTeamLossyRow<Value>].self, forKey: key)
    return rows?.compactMap(\.value) ?? []
  }
}

private struct SDTeamLossyRow<Value: Decodable>: Decodable {
  let value: Value?

  init(from decoder: Decoder) throws {
    value = try? Value(from: decoder)
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

struct SDTeamScheduleContext: Decodable, Equatable, Sendable {
  let organization_id: UUID?
  let season_id: UUID?
  let team_id: UUID?
  let as_of: String?
}

enum SDTeamScheduleContractError: Error, Equatable, Sendable {
  case unsupportedSchema(Int)
  case noDecodableEvents(Int)
  case contextMismatch
}

struct SDTeamScheduleResponse: Decodable, Sendable {
  static let currentSchemaVersion = 1

  let ok: Bool
  let schema_version: Int
  let request_id: String?
  let context: SDTeamScheduleContext?
  let warnings: [String]
  let events: [SDTeamEvent]
  let discarded_event_count: Int

  private struct Payload: Decodable {
    let events: [SDTeamLossyRow<SDTeamEvent>]
  }

  private enum CodingKeys: String, CodingKey {
    case ok, schema_version, request_id, context, warnings, events, data
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    ok = try container.decode(Bool.self, forKey: .ok)
    schema_version = (try? container.decode(Int.self, forKey: .schema_version)) ?? 0
    guard schema_version <= Self.currentSchemaVersion else {
      throw SDTeamScheduleContractError.unsupportedSchema(schema_version)
    }
    request_id = try? container.decodeIfPresent(String.self, forKey: .request_id)
    context = try? container.decodeIfPresent(SDTeamScheduleContext.self, forKey: .context)
    warnings = (try? container.decode([String].self, forKey: .warnings)) ?? []
    let rows = (try? container.decode([SDTeamLossyRow<SDTeamEvent>].self, forKey: .events))
      ?? (try? container.decode(Payload.self, forKey: .data).events)
      ?? []
    events = rows.compactMap(\.value)
    discarded_event_count = rows.count - events.count
    if !rows.isEmpty, events.isEmpty {
      throw SDTeamScheduleContractError.noDecodableEvents(rows.count)
    }
  }
}

enum SDTeamRuntimeDiagnostics {
  static func record(
    requestID: UUID,
    screen: String,
    action: String,
    organizationPresent: Bool,
    seasonPresent: Bool,
    teamPresent: Bool,
    actorRole: String?,
    capabilityResolved: Bool?,
    statusCode: Int?,
    backendCode: String?,
    backendStage: String?,
    schemaVersion: Int?,
    rowCount: Int?,
    discardedRowCount: Int = 0,
    decodeStage: String,
    cacheFallbackUsed: Bool,
    elapsedMilliseconds: Int,
    cancelled: Bool,
    superseded: Bool
  ) {
    #if DEBUG
    let fields = [
      "request=\(requestID.uuidString)",
      "screen=\(screen)",
      "action=\(action)",
      "org=\(organizationPresent ? "present" : "missing")",
      "season=\(seasonPresent ? "present" : "missing")",
      "team=\(teamPresent ? "present" : "missing")",
      "role=\(actorRole ?? "unknown")",
      "capabilities=\(capabilityResolved.map { $0 ? "resolved" : "denied" } ?? "unknown")",
      "http=\(statusCode.map(String.init) ?? "unknown")",
      "code=\(backendCode ?? "none")",
      "backend_stage=\(backendStage ?? "unknown")",
      "schema=\(schemaVersion.map(String.init) ?? "unknown")",
      "rows=\(rowCount.map(String.init) ?? "unknown")",
      "discarded_rows=\(discardedRowCount)",
      "decode_stage=\(decodeStage)",
      "cache_fallback=\(cacheFallbackUsed)",
      "elapsed_ms=\(elapsedMilliseconds)",
      "cancelled=\(cancelled)",
      "superseded=\(superseded)",
    ]
    print("team_runtime_diagnostic " + fields.joined(separator: " "))
    #endif
  }
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
