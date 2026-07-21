import Foundation
import Testing
@testable import HomePlate

@Suite("Phase 12B unified team scheduling")
struct TeamSchedulingTests {
  @Test("all schedule types and filters are stable")
  func eventTypesAndFilters() {
    #expect(SDTeamEventType.allCases.map(\.rawValue) == ["practice", "game", "tournament", "meeting", "travel", "custom"])
    #expect(SDTeamEventType.mvpCases.map(\.label) == ["Practice", "Game", "Meeting", "Other"])
    #expect(SDTeamEventType.custom.rawValue == "custom")
    #expect(SDTeamScheduleFilter.practices.includes(.practice))
    #expect(!SDTeamScheduleFilter.practices.includes(.game))
    #expect(SDTeamScheduleFilter.all.includes(.travel))
  }

  @Test("stale selected team falls back to All Teams")
  func staleTeamFallback() {
    let ids = ContractIDs()
    let staleTeam = UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")!
    let result = SDTeamScheduleSelectionResolver.resolve(
      organizationId: ids.organization,
      selectedSeasonId: ids.season,
      selectedTeamId: staleTeam,
      seasons: [season(id: ids.season, organizationId: ids.organization, status: .active)],
      teams: [team(id: ids.team, organizationId: ids.organization, seasonId: ids.season)]
    )
    #expect(result.seasonId == ids.season)
    #expect(result.teamId == nil)
    #expect(result.repairedTeam)
  }

  @Test("stale selected season falls back to the active season and All Teams")
  func staleSeasonFallback() {
    let ids = ContractIDs()
    let staleSeason = UUID(uuidString: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb")!
    let result = SDTeamScheduleSelectionResolver.resolve(
      organizationId: ids.organization,
      selectedSeasonId: staleSeason,
      selectedTeamId: ids.team,
      seasons: [
        season(id: staleSeason, organizationId: ids.organization, status: .completed, isDefault: true),
        season(id: ids.season, organizationId: ids.organization, status: .active),
      ],
      teams: [team(id: ids.team, organizationId: ids.organization, seasonId: ids.season)]
    )
    #expect(result.seasonId == ids.season)
    #expect(result.teamId == ids.team)
    #expect(result.repairedSeason)
  }

  @Test("no active season produces the precise empty schedule state")
  func noActiveSeason() throws {
    let ids = ContractIDs()
    let result = SDTeamScheduleSelectionResolver.resolve(
      organizationId: ids.organization,
      selectedSeasonId: ids.season,
      selectedTeamId: ids.team,
      seasons: [season(id: ids.season, organizationId: ids.organization, status: .completed)],
      teams: [team(id: ids.team, organizationId: ids.organization, seasonId: ids.season)]
    )
    #expect(result.seasonId == nil)
    #expect(result.teamId == nil)
    let source = try sourceFile("HomePlate/Features/Coach/CoachTeamScheduleView.swift")
    #expect(source.contains("title: \"No active season\""))
  }

  @Test("an end time crossing midnight advances to the following day")
  func crossingMidnight() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(identifier: "America/New_York"))
    let start = try #require(calendar.date(from: DateComponents(year: 2026, month: 7, day: 21, hour: 22, minute: 59)))
    let proposed = try #require(calendar.date(from: DateComponents(year: 2026, month: 7, day: 21, hour: 0, minute: 59)))
    let adjusted = SDTeamEventTiming.endAfterSelecting(proposed, start: start, calendar: calendar)
    #expect(calendar.component(.day, from: adjusted) == 22)
    #expect(calendar.component(.hour, from: adjusted) == 0)
    #expect(SDTeamEventTiming.validationIssue(start: start, end: adjusted, arrival: nil) == nil)
  }

  @Test("invalid end and arrival times provide inline validation")
  func timingValidation() {
    let start = Date(timeIntervalSince1970: 1_000)
    #expect(SDTeamEventTiming.validationIssue(start: start, end: start, arrival: nil) == .endNotAfterStart)
    #expect(SDTeamEventTiming.validationIssue(start: start, end: start.addingTimeInterval(3_600), arrival: start.addingTimeInterval(60)) == .arrivalAfterStart)
    #expect(SDTeamEventTimingIssue.endNotAfterStart.message == "End time must be after the start time.")
  }

  @Test("MVP create publish refresh authorization and notification boundaries remain explicit")
  func mvpRuntimeContract() throws {
    let view = try sourceFile("HomePlate/Features/Coach/CoachTeamScheduleView.swift")
    let service = try sourceFile("HomePlate/Core/SupabaseService.swift")
    let edge = try sourceFile("supabase/functions/team-scheduling/index.ts")
    #expect(view.contains("Button(\"Save Draft\")"))
    #expect(view.contains("Button(\"Publish\")"))
    #expect(view.contains("Task { await reload() }"))
    #expect(service.contains("eventId == nil ? \"create\" : \"update\""))
    #expect(edge.contains("resolveScheduleReadAuthority(role, candidateCapabilities).allowed"))
    #expect(edge.contains("const isAdmin = role === \"owner\" || role === \"admin\""))
    #expect(edge.contains("consumer) query = query.eq(\"visibility\", \"team\").neq(\"status\", \"draft\")"))
    #expect(edge.contains("await admin.from(\"sd_team_event_notification_intents\").insert"))
    #expect(edge.contains("return ok({ events: inserted ?? [], conflicts: conflictList })"))
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
    #expect(source.contains("SDTeamScheduleFilter.mvpCases"))
    #expect(source.contains("switch draft.type"))
    #expect(source.contains("Save Draft"))
    #expect(source.contains("Schedule"))
    #expect(source.contains("Coach-private notes"))
    #expect(source.contains("All Teams"))
    #expect(source.contains("Repeats weekly"))
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

  private func season(
    id: UUID,
    organizationId: UUID,
    status: SDSeasonLifecycle,
    isDefault: Bool = false
  ) -> SDSeason {
    SDSeason(
      id: id,
      organization_id: organizationId,
      name: "Season",
      start_date: nil,
      end_date: nil,
      status: status,
      is_default: isDefault,
      created_by: nil,
      updated_by: nil,
      created_at: nil,
      updated_at: nil
    )
  }

  private func team(id: UUID, organizationId: UUID, seasonId: UUID) -> SDTeamOperationsTeam {
    SDTeamOperationsTeam(
      id: id,
      org_id: organizationId,
      season_id: seasonId,
      name: "Team",
      color_hex: nil,
      description: nil,
      age_group: nil,
      competitive_level: nil,
      roster_capacity: nil,
      is_active: true,
      sort_order: 0,
      created_by: nil,
      created_at: nil,
      updated_at: nil,
      is_primary: false,
      roster_count: 0,
      staff_count: 0,
      capabilities: [.viewTeamSchedule, .createTeamEvent]
    )
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
