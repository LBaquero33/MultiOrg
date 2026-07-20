import Foundation
import Testing
@testable import HomePlate

@Suite("Phase 12B unified team scheduling")
struct TeamSchedulingTests {
  @Test("all schedule types and filters are stable")
  func eventTypesAndFilters() {
    #expect(SDTeamEventType.allCases.map(\.rawValue) == ["practice", "game", "tournament", "meeting", "travel", "custom"])
    #expect(SDTeamScheduleFilter.practices.includes(.practice))
    #expect(!SDTeamScheduleFilter.practices.includes(.game))
    #expect(SDTeamScheduleFilter.all.includes(.travel))
  }

  @Test("consumer dates decode fractional and whole ISO timestamps")
  func timestamps() {
    #expect(SDTeamEventDateParser.date("2027-01-04T20:00:00.123Z") != nil)
    #expect(SDTeamEventDateParser.date("2027-01-04T20:00:00Z") != nil)
    #expect(SDTeamEventDateParser.date("not-a-date") == nil)
  }

  @Test("scheduling capabilities are part of the central team model")
  func capabilities() {
    let mutation: Set<SDTeamCapability> = [.createTeamEvent, .editTeamEvent, .cancelTeamEvent]
    #expect(mutation.contains(.createTeamEvent))
    #expect(SDTeamCapability.viewTeamSchedule.rawValue == "view_team_schedule")
    #expect(SDTeamCapability.manageTournamentEvent.rawValue == "manage_tournament_event")
  }

  @Test("coach navigation remains Today Team Schedule More")
  func noNewTopLevelTabs() {
    let inventory = HPAppNavigationInventory.staff(
      playersTitle: "Players",
      facilitiesTitle: "Facilities",
      programsTitle: "Programs",
      facilitiesEnabled: true,
      chatEnabled: true,
      programsEnabled: true,
      canAdministerOrganization: true,
      isPlatformAdmin: false
    )
    #expect(inventory.compactItems.map(\.destination) == [.coachToday, .coachTeam, .coachSchedule])
    #expect(inventory.compactTabCountIncludingDirectory == 4)
  }

  @Test("schedule UI is one destination with progressive filters and forms")
  func scheduleSource() throws {
    let source = try sourceFile("HomePlate/Features/Coach/CoachTeamScheduleView.swift")
    #expect(source.contains("SDTeamScheduleMode.allCases"))
    #expect(source.contains("SDTeamScheduleFilter.allCases"))
    #expect(source.contains("switch draft.type"))
    #expect(source.contains("Save Draft"))
    #expect(source.contains("Schedule"))
    #expect(source.contains("Coach-private notes"))
    #expect(source.contains("All Teams"))
    #expect(source.contains("Repeat on"))
    #expect(source.contains("Recurrence end"))
    #expect(source.contains("selectedSeasonName"))
    #expect(source.contains("Postpone"))
  }

  @Test("Today and Team use real canonical schedule responses")
  func scheduleIntegration() throws {
    let source = try sourceFile("HomePlate/Features/Coach/CoachTeamCommandCenterView.swift")
    #expect(source.contains("listTeamEvents"))
    #expect(source.contains("teamEvents"))
    #expect(source.contains("Next Event"))
    #expect(!source.contains("The next scheduled team item will appear here"))
    #expect(!source.contains("Scheduled team operations will appear here"))
  }

  @Test("Marist 10u Players remains available when Schedule fails")
  func maristTeamPlayersScheduleFailureRegression() throws {
    let source = try sourceFile("HomePlate/Features/Coach/CoachTeamCommandCenterView.swift")
    #expect(source.contains("case .players:"))
    #expect(source.contains("No players assigned"))
    #expect(source.contains("guard section == .overview || section == .schedule else { return }"))
    #expect(source.contains("if let loadError, teamEvents.isEmpty") == false)
    #expect(source.contains("title: \"Team unavailable\"") == false)
    #expect(source.contains("seasonId: team.season_id"))
  }

  @Test("Team render contract keeps the selected-team shell while Schedule is unavailable")
  func scopedScheduleUnavailableRenderContract() throws {
    let source = try sourceFile("HomePlate/Features/Coach/CoachTeamCommandCenterView.swift")
    let header = try #require(source.range(of: "HPWorkspaceHeader("))
    let content = try #require(source.range(of: "private var content: some View"))

    #expect(header.lowerBound < content.lowerBound)
    #expect(source.contains("context: teamHeaderContext"))
    #expect(source.contains("CoachTeamSelector()"))
    #expect(source.contains("case .players:"))
    #expect(source.contains("title: displayedTeamEvents.isEmpty ? \"Schedule unavailable\" : \"Schedule may be out of date\""))
    #expect(source.contains("Previously loaded events remain visible."))
    #expect(source.contains("onRetry: { Task { await reloadTeamEvents() } }"))
    #expect(source.contains("title: \"Team unavailable\"") == false)
  }

  @Test("versioned Schedule envelope accepts a canonical base event")
  func versionedEnvelopeBaseEvent() throws {
    let ids = ContractIDs()
    let response = try decodeScheduleResponse(
      events: [event(ids: ids)],
      schemaVersion: 1,
      context: [
        "organization_id": ids.organization.uuidString,
        "season_id": ids.season.uuidString,
        "team_id": ids.team.uuidString,
        "as_of": "2027-01-04T18:00:00Z",
      ]
    )
    #expect(response.schema_version == 1)
    #expect(response.events.count == 1)
    #expect(response.events[0].facility_id == nil)
    #expect(response.events[0].location_name == "Field 1")
    #expect(response.events[0].sd_team_event_practices?.isEmpty == true)
  }

  @Test("malformed optional subtype is isolated without erasing its base event")
  func partialSubtypeDegradation() throws {
    let ids = ContractIDs()
    var base = event(ids: ids)
    base["metadata"] = "unexpected optional metadata"
    base["sd_team_event_practices"] = [["event_id": "not-a-uuid"]]
    let response = try decodeScheduleResponse(events: [base], schemaVersion: 1)
    #expect(response.events.count == 1)
    #expect(response.events[0].metadata == nil)
    #expect(response.events[0].sd_team_event_practices == [])
  }

  @Test("one invalid identity row cannot collapse valid Schedule rows")
  func invalidIdentityRowIsolation() throws {
    let ids = ContractIDs()
    var invalid = event(ids: ids)
    invalid["id"] = "not-a-uuid"
    let response = try decodeScheduleResponse(
      events: [invalid, event(ids: ids)],
      schemaVersion: 1
    )
    #expect(response.events.count == 1)
    #expect(response.discarded_event_count == 1)
  }

  @Test("unsupported Schedule schema maps to controlled compatibility copy")
  func unsupportedEnvelopeVersion() throws {
    let data = try scheduleResponseData(events: [], schemaVersion: 2)
    #expect(throws: SDTeamScheduleContractError.unsupportedSchema(2)) {
      try JSONDecoder().decode(SDTeamScheduleResponse.self, from: data)
    }
    let presentation = SDApplicationErrorClassifier.presentation(
      for: SDTeamScheduleContractError.unsupportedSchema(2)
    )
    #expect(presentation?.category == .malformedResponse)
    #expect(presentation?.message == "This feature is temporarily unavailable.")
  }

  @Test("Schedule backend separates context validation from capability denial")
  func scheduleAuthorizationAndEnvelopeContract() throws {
    let edge = try sourceFile("supabase/functions/team-scheduling/index.ts")
    #expect(edge.contains("schema_version: 1"))
    #expect(edge.contains("stale_team_context"))
    #expect(edge.contains("team_archived"))
    #expect(edge.contains("season_missing"))
    #expect(edge.contains("permission_denied"))
    #expect(edge.contains("if (!isAdmin)"))
    #expect(edge.contains("resolve_capabilities"))
    #expect(edge.contains("error.message") == false)
  }

  @Test("owner schedule scope validates organization ownership without coach assignment")
  func ownerScheduleAuthorization() throws {
    let edge = try sourceFile("supabase/functions/team-scheduling/index.ts")
    #expect(edge.contains("const isAdmin = role === \"owner\" || role === \"admin\""))
    #expect(edge.contains("let listCapabilities: string[] = isAdmin"))
    #expect(edge.contains("if (!isAdmin)"))
    #expect(edge.contains(".from(\"sd_teams\").select(\"id,season_id,is_active\")"))
    #expect(edge.contains("listFail(404, \"team_missing\", \"validate_team\")"))
  }

  @Test("schedule keeps cached events and exposes progressive filters")
  func scheduleReliabilityContract() throws {
    let source = try sourceFile("HomePlate/Features/Coach/CoachTeamScheduleView.swift")
    #expect(source.contains("Schedule may be out of date"))
    #expect(source.contains("Previously loaded events remain visible"))
    #expect(source.contains("teamFilterId"))
    #expect(source.contains("facilityFilterId"))
    #expect(source.contains("moveAnchor(backward:"))
    #expect(source.contains("Create First Event"))
  }

  @Test("player and parent calendars consume redacted team events")
  func consumerCalendars() throws {
    let player = try sourceFile("HomePlate/Features/Player/SDPlayerCalendarView.swift")
    let parent = try sourceFile("HomePlate/Features/Parent/ParentChildCalendarView.swift")
    #expect(player.contains("listTeamEvents"))
    #expect(parent.contains("listTeamEvents"))
    let edge = try sourceFile("supabase/functions/team-scheduling/index.ts")
    #expect(edge.contains("sanitizeEventForConsumer"))
    #expect(edge.contains("role === \"player\""))
    #expect(edge.contains("role === \"parent\""))
    #expect(edge.contains("parent_link_required") == false)
    #expect(edge.contains("player_scope_required") == false)
    #expect(edge.contains("permission_denied"))
  }

  @Test("migration preserves legacy calendar sources and notification boundary")
  func migrationBoundaries() throws {
    let migration = try sourceFile("supabase/migrations/20260717183000_unified_team_scheduling.sql")
    #expect(migration.contains("Program assignments, BP sessions, and facility"))
    #expect(migration.contains("sd_facility_bookings booking"))
    #expect(migration.contains("does not dispatch APNs"))
    #expect(!migration.contains("drop table"))
  }

  private func sourceFile(_ path: String) throws -> String {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
  }

  private struct ContractIDs {
    let organization = UUID(uuidString: "800e22ae-2a9d-4109-9e11-1360eeaa8ea7")!
    let season = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
    let team = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!
    let event = UUID(uuidString: "33333333-3333-4333-8333-333333333333")!
  }

  private func event(ids: ContractIDs) -> [String: Any] {
    [
      "id": ids.event.uuidString,
      "organization_id": ids.organization.uuidString,
      "season_id": ids.season.uuidString,
      "team_id": ids.team.uuidString,
      "event_type": "practice",
      "title": "Practice",
      "status": "scheduled",
      "start_at": "2027-01-04T20:00:00Z",
      "end_at": "2027-01-04T22:00:00Z",
      "original_start_at": "2027-01-04T20:00:00Z",
      "timezone": "America/New_York",
      "all_day": false,
      "location_name": "Field 1",
      "visibility": "team",
      "sd_team_event_practices": [],
      "sd_team_event_games": [],
      "sd_team_event_tournaments": [],
      "sd_team_event_meetings": [],
      "sd_team_event_travel": [],
      "sd_team_event_coaches": [],
    ]
  }

  private func decodeScheduleResponse(
    events: [[String: Any]],
    schemaVersion: Int,
    context: [String: Any]? = nil
  ) throws -> SDTeamScheduleResponse {
    try JSONDecoder().decode(
      SDTeamScheduleResponse.self,
      from: scheduleResponseData(
        events: events,
        schemaVersion: schemaVersion,
        context: context
      )
    )
  }

  private func scheduleResponseData(
    events: [[String: Any]],
    schemaVersion: Int,
    context: [String: Any]? = nil
  ) throws -> Data {
    var payload: [String: Any] = [
      "ok": true,
      "schema_version": schemaVersion,
      "request_id": UUID().uuidString,
      "warnings": [],
      "events": events,
    ]
    if let context { payload["context"] = context }
    return try JSONSerialization.data(withJSONObject: payload)
  }
}
