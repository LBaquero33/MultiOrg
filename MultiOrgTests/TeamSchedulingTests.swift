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
    let source = try sourceFile("MultiOrg/Features/Coach/CoachTeamScheduleView.swift")
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
    let source = try sourceFile("MultiOrg/Features/Coach/CoachTeamCommandCenterView.swift")
    #expect(source.contains("listTeamEvents"))
    #expect(source.contains("teamEvents"))
    #expect(source.contains("Next Event"))
    #expect(!source.contains("The next scheduled team item will appear here"))
    #expect(!source.contains("Scheduled team operations will appear here"))
  }

  @Test("player and parent calendars consume redacted team events")
  func consumerCalendars() throws {
    let player = try sourceFile("MultiOrg/Features/Player/SDPlayerCalendarView.swift")
    let parent = try sourceFile("MultiOrg/Features/Parent/ParentChildCalendarView.swift")
    #expect(player.contains("listTeamEvents"))
    #expect(parent.contains("listTeamEvents"))
    let edge = try sourceFile("supabase/functions/team-scheduling/index.ts")
    #expect(edge.contains("sanitizeEventForConsumer"))
    #expect(edge.contains("parent_link_required"))
    #expect(edge.contains("player_scope_required"))
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
}
