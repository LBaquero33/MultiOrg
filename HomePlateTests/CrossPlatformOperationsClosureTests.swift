import Foundation
import Testing
@testable import HomePlate

@Suite("Cross-platform operations closure")
struct CrossPlatformOperationsClosureTests {
  @Test("Team create and update use isolated server contracts")
  func teamMutationContracts() throws {
    let service = try sourceFile("HomePlate/Core/SupabaseService.swift")
    let view = try sourceFile("HomePlate/Features/Admin/OrgTeamOperationsAdminView.swift")
    let backend = try sourceFile("supabase/functions/org_admin/index.ts")

    #expect(service.contains("func adminCreateTeam(") && service.contains("async throws -> SDTeam"))
    #expect(service.contains("let _: TeamMutationResponse = try await invokeAuthenticatedFunction(\"org_admin\""))
    #expect(view.contains("savedTeamId = createdTeam.id"))
    #expect(view.contains("teamRequestId = UUID()"))
    #expect(backend.contains("create_team_rejects_team_id"))
    let updateStart = try #require(backend.range(of: "const teamId = cleanText(payload.team_id);"))
    let updateEnd = try #require(backend.range(of: "if (action === \"assign_team_member\")", range: updateStart.upperBound..<backend.endIndex))
    let updateContract = String(backend[updateStart.lowerBound..<updateEnd.lowerBound])
    #expect(updateContract.contains("\"id\",\n      teamId"))
    #expect(updateContract.contains(".eq(\"org_id\", orgId)"))
  }

  @Test("Calendar uses canonical events without user-facing seasons")
  func canonicalCalendarContract() throws {
    let root = try sourceFile("HomePlate/Features/Home/CoachRootView.swift")
    let calendar = try sourceFile("HomePlate/Features/Games/GameCalendarView.swift")
    let service = try sourceFile("HomePlate/Core/SupabaseService+Games.swift")

    #expect(root.contains("case .coachCalendar:\n      GameCalendarView()"))
    #expect(calendar.contains("Label(\"New Event\", systemImage: \"plus\")"))
    #expect(calendar.contains("CanonicalEventEditorView"))
    #expect(calendar.contains("Select season") == false)
    #expect(service.contains("struct SDCanonicalEventDraft"))
    #expect(service.contains("func createCanonicalEvent"))
    #expect(service.contains("func updateCanonicalEvent"))
    #expect(service.contains("func cancelCanonicalEvent"))
  }

  @Test("Calendar day selection is modal instead of inline")
  func calendarDaySelectionIsModalInsteadOfInline() throws {
    let games = try sourceFile("HomePlate/Features/Games/GameCalendarView.swift")
    let layout = try sourceFile("HomePlate/DesignSystem/Templates/HPCalendarScreenTemplate.swift")
    let player = try sourceFile("HomePlate/Features/Player/SDPlayerCalendarView.swift")
    let parent = try sourceFile("HomePlate/Features/Parent/ParentChildCalendarView.swift")
    let coach = try sourceFile("HomePlate/Features/Coach/CoachPlayerCalendarView.swift")
    let coachFacilities = try sourceFile("HomePlate/Features/Coach/CoachFacilitiesView.swift")
    let playerFacilities = try sourceFile("HomePlate/Features/Player/SDPlayerFacilitiesView.swift")
    let parentFacilities = try sourceFile("HomePlate/Features/Parent/SDParentFacilitiesView.swift")

    #expect(games.contains("onSelect: { openDay($0) }"))
    #expect(games.contains(".sheet(item: $daySheet)"))
    #expect(!games.contains("if !gamesOnly { eventTypeFilter }\n          agenda"))
    #expect(layout.contains("calendar(context).frame(maxWidth: .infinity, alignment: .top)"))
    #expect(!layout.contains("calendar(context).frame(maxWidth: .infinity, alignment: .top)\n        agenda(context)"))
    #expect(player.contains("onSelect: openDay"))
    #expect(player.contains(".sheet(item: $daySheet)"))
    #expect(parent.contains("onSelect: openDay"))
    #expect(parent.contains(".sheet(item: $daySheet)"))
    #expect(coach.contains("onSelect: openDay"))
    #expect(coach.contains(".sheet(item: $daySheet)"))
    for facilities in [coachFacilities, playerFacilities, parentFacilities] {
      #expect(facilities.contains("onSelect:"))
      #expect(facilities.contains("dayModal ="))
      #expect(facilities.contains(".sheet(item: $dayModal)"))
    }
  }

  @Test("Program workspace exposes templates tracker and day details")
  func programTrackerContract() throws {
    let programs = try sourceFile("HomePlate/Features/Coach/CoachProgramsView.swift")
    let tracker = try sourceFile("HomePlate/Features/Coach/CoachProgramTrackerView.swift")
    let workspace = try sourceFile("HomePlate/Features/Coach/UnifiedPlayerDevelopmentWorkspaceView.swift")

    #expect(programs.contains("Templates"))
    #expect(programs.contains("UnifiedPlayerDevelopmentWorkspaceView"))
    #expect(programs.contains("init(initialWorkspace: Workspace = .workspace)"))
    #expect(programs.contains("case templates = \"Library\""))
    #expect(workspace.contains("CoachProgramsView(initialWorkspace: .templates)"))
    #expect(workspace.contains("NativePlayerAnalyticsView(playerId: player.id"))
    for text in ["All players", "Active", "Ended", "Submitted", "Upcoming", "No Submission"] {
      #expect(tracker.contains(text))
    }
    for detail in ["sets completed", "Set weights", "result_values", "Notes"] {
      #expect(tracker.localizedCaseInsensitiveContains(detail))
    }
  }

  @Test("Attendance remains available on every canonical player event")
  func attendanceContract() throws {
    let detail = try sourceFile("HomePlate/Features/Games/GameDetailView.swift")
    let model = try sourceFile("HomePlate/Core/GameModels.swift")
    #expect(detail.contains("Coming"))
    #expect(detail.contains("Not Coming"))
    #expect(model.contains("case noResponse = \"No Response\""))
    #expect(detail.contains("This event"))
  }

  private func sourceFile(_ path: String) throws -> String {
    let root = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
  }
}
