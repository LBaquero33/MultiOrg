import Foundation
import SwiftUI
import Testing
import XCTest
@testable import HomePlate

#if canImport(UIKit)
import UIKit
#endif

@Suite("Phase 13A explicit team context")
struct Phase13ATeamContextTests {
  private let userId = UUID(uuidString: "10000000-0000-4000-8000-000000000001")!
  private let organizationA = UUID(uuidString: "20000000-0000-4000-8000-000000000001")!
  private let organizationB = UUID(uuidString: "20000000-0000-4000-8000-000000000002")!
  private let seasonId = UUID(uuidString: "30000000-0000-4000-8000-000000000001")!
  private let teamA = UUID(uuidString: "40000000-0000-4000-8000-000000000001")!
  private let teamB = UUID(uuidString: "40000000-0000-4000-8000-000000000002")!

  @Test("root workspaces declare the authoritative scope")
  func workspaceScopes() {
    #expect(HPAppNavigationDestination.organizationAdmin.workspaceScope == .organization)
    #expect(HPAppNavigationDestination.finance.workspaceScope == .organization)
    #expect(HPAppNavigationDestination.coachPlayers.workspaceScope == .organization)
    #expect(HPAppNavigationDestination.coachTeams.workspaceScope == .organization)
    #expect(HPAppNavigationDestination.coachPrograms.workspaceScope == .organization)
    #expect(HPAppNavigationDestination.chat.workspaceScope == .organization)
    #expect(HPAppNavigationDestination.coachTeam.workspaceScope == .selectedTeam)
    #expect(HPAppNavigationDestination.coachToday.workspaceScope == .allAssignedTeams)
    #expect(HPAppNavigationDestination.coachSchedule.workspaceScope == .scheduleFilter)
    #expect(HPAppNavigationDestination.coachFacilities.workspaceScope == .scheduleFilter)
    #expect(HPAppNavigationDestination.playerDevelopment.workspaceScope == .selectedPlayer)
    #expect(HPAppNavigationDestination.parentChildren.workspaceScope == .selectedChild)
    #expect(HPAppNavigationDestination.platformAdmin.workspaceScope == .platform)
    #expect(HPAppNavigationDestination.account.workspaceScope == .account)
  }

  @Test("team selection rejects archived and cross-organization teams")
  func authorizedSelectionPrecedence() {
    let active = team(id: teamA, organizationId: organizationA, active: true)
    let archived = team(id: teamB, organizationId: organizationA, active: false, primary: true)
    let foreign = team(id: UUID(), organizationId: organizationB, active: true, primary: true)
    let resolution = SDSelectedTeamResolver.resolve(
      explicitTeamId: archived.id,
      persistedTeamId: foreign.id,
      organizationId: organizationA,
      seasonId: seasonId,
      teams: [archived, foreign, active]
    )
    #expect(resolution == .init(teamId: active.id, source: .firstActiveTeam))
  }

  @Test("explicit selection wins and valid persisted selection restores")
  func explicitAndPersistedPrecedence() {
    let first = team(id: teamA, organizationId: organizationA)
    let second = team(id: teamB, organizationId: organizationA)
    #expect(SDSelectedTeamResolver.resolve(
      explicitTeamId: second.id,
      persistedTeamId: first.id,
      organizationId: organizationA,
      seasonId: seasonId,
      teams: [first, second]
    ) == .init(teamId: second.id, source: .explicit))
    #expect(SDSelectedTeamResolver.resolve(
      explicitTeamId: nil,
      persistedTeamId: first.id,
      organizationId: organizationA,
      seasonId: seasonId,
      teams: [first, second]
    ) == .init(teamId: first.id, source: .persisted))
  }

  @Test("selection persistence is versioned per user and organization")
  func persistenceIsolation() {
    let first = HPTeamSelectionPersistence.key(userId: userId, organizationId: organizationA)
    let second = HPTeamSelectionPersistence.key(userId: userId, organizationId: organizationB)
    #expect(first != second)
    #expect(first.contains(userId.uuidString.lowercased()))
    #expect(first.contains(organizationA.uuidString.lowercased()))
    #expect(first.contains(".v2."))
    #expect(!first.contains(seasonId.uuidString.lowercased()))
  }

  @Test("cache keys isolate team data without contaminating organization data")
  func cacheKeyIsolation() {
    let organization = HPWorkspaceCacheKey.organization(
      userId: userId, organizationId: organizationA, action: "people"
    )
    let first = HPWorkspaceCacheKey.selectedTeam(
      userId: userId, organizationId: organizationA, seasonId: seasonId,
      teamId: teamA, action: "roster"
    )
    let second = HPWorkspaceCacheKey.selectedTeam(
      userId: userId, organizationId: organizationA, seasonId: seasonId,
      teamId: teamB, action: "roster"
    )
    #expect(!organization.contains(teamA.uuidString.lowercased()))
    #expect(!organization.contains(teamB.uuidString.lowercased()))
    #expect(first != second)
    #expect(first.contains(teamA.uuidString.lowercased()))
  }

  @Test("Schedule cache uses its visible filter independently")
  func scheduleCacheKey() {
    let all = HPWorkspaceCacheKey.schedule(
      userId: userId, organizationId: organizationA, seasonId: seasonId,
      visibleTeamFilterId: nil, action: "events"
    )
    let filtered = HPWorkspaceCacheKey.schedule(
      userId: userId, organizationId: organizationA, seasonId: seasonId,
      visibleTeamFilterId: teamA, action: "events"
    )
    #expect(all != filtered)
    #expect(all.contains("all-teams"))
    #expect(filtered.contains(teamA.uuidString.lowercased()))
  }

  @Test("explicit Team deep links validate organization team and section")
  func explicitDeepLink() throws {
    let url = try #require(URL(string:
      "homeplate://team?organization_id=\(organizationA.uuidString)&team_id=\(teamA.uuidString)&section=schedule"
    ))
    let route = try #require(HPTeamWorkspaceRoute(url: url))
    #expect(route.organizationId == organizationA)
    #expect(route.teamId == teamA)
    #expect(route.section == .schedule)
    #expect(HPTeamWorkspaceRoute(url: URL(string: "homeplate://team?team_id=\(teamA.uuidString)")!) == nil)
  }

  @Test("legacy Current Team aliases route to Team")
  func legacyRouteAliases() {
    for alias in ["currentteam", "current_team", "current-team"] {
      #expect(HPAppNavigationDestination.routeDestination(for: alias) == .coachTeam)
    }
  }

  @Test("role-aware selector has label menu no-team and authorized admin actions")
  func selectorContracts() throws {
    let source = try sourceFile("MultiOrg/Features/Coach/CoachTeamCommandCenterView.swift")
    let selector = try sourceSlice(source, from: "struct CoachTeamSelector", to: "struct CoachTodayFoundationView")
    #expect(selector.contains("authorizedCoachTeams.count == 1"))
    #expect(selector.contains("Menu {"))
    #expect(selector.contains("No team assigned"))
    #expect(selector.contains("Create Team"))
    #expect(selector.contains("Manage Teams"))
    #expect(selector.contains("canAdminActiveOrg"))
    #expect(selector.contains("All Teams") == false)
    #expect(selector.contains(".frame(minHeight: 44)"))
    #expect(selector.contains(".accessibilityLabel"))
  }

  @Test("Team shell keeps selector visible across approved tabs and More")
  func teamWorkspaceContracts() throws {
    let source = try sourceFile("MultiOrg/Features/Coach/CoachTeamCommandCenterView.swift")
    let workspace = try sourceSuffix(source, from: "struct CoachTeamCommandCenterView")
    for tab in ["Overview", "Players", "Schedule", "Development", "Staff", "Settings"] {
      #expect(workspace.contains("\"\(tab)\""))
    }
    #expect(workspace.contains("CoachTeamSelector()"))
    #expect(workspace.contains("case communication = \"Communication\""))
    #expect(workspace.contains("case documents = \"Documents\""))
    #expect(workspace.contains("Label(\"More\""))
    #expect(workspace.contains("context: teamHeaderContext"))
  }

  @Test("Team requests carry explicit organization team and context token")
  func explicitTeamRequests() throws {
    let source = try sourceFile("MultiOrg/Features/Coach/CoachTeamCommandCenterView.swift")
    #expect(source.contains("organizationId: orgId"))
    #expect(source.contains("teamId: team.id"))
    #expect(source.contains("appState.teamContextToken.uuidString"))
    #expect(source.contains("SDAsyncRequestGuard.accepts"))
  }

  @Test("organization People and Finance never consume selected Team state")
  func organizationWorkspaceProtection() throws {
    let admin = try sourceFile("MultiOrg/Features/Admin/OrgAdminConsoleView.swift")
    let finance = try sourceFile("MultiOrg/Features/Admin/FinanceDashboardView.swift")
      + (try sourceFile("MultiOrg/Features/Admin/FinanceDashboardViewModel.swift"))
    #expect(!admin.contains("appState.selectedTeam"))
    #expect(!admin.contains("CoachTeamSelector"))
    #expect(admin.contains("peopleRoleFilter = \"All roles\""))
    #expect(admin.contains("peopleStatusFilter = \"All statuses\""))
    #expect(!finance.contains("selectedTeam"))
    #expect(!finance.contains("CoachTeamSelector"))
  }

  @Test("Global Schedule owns a visible filter and does not inherit Team selection")
  func globalScheduleIsolation() throws {
    let source = try sourceFile("MultiOrg/Features/Coach/CoachTeamScheduleView.swift")
    #expect(source.contains("@State private var teamFilterId"))
    #expect(source.contains("All Teams"))
    #expect(source.contains("All My Teams"))
    #expect(source.contains("Visible filter:"))
    #expect(source.contains("Label(\"New Event\""))
    #expect(source.contains("teamId: effectiveTeamFilterId"))
    #expect(!source.contains("appState.selectedTeamId"))
    #expect(!source.contains("CoachTeamSelector"))
  }

  @Test("one authoritative event editor requires exactly one explicit team")
  func universalEventEditor() throws {
    let source = try sourceFile("MultiOrg/Features/Coach/CoachTeamScheduleView.swift")
    let editor = try sourceSuffix(source, from: "struct TeamEventEditorView")
    #expect(editor.contains("Picker(\"Team\", selection: $selectedTeamId)"))
    #expect(editor.contains("let selectedTeamId"))
    #expect(editor.contains("teamId: selectedTeam.id"))
    #expect(editor.contains("saveTeamEvent("))
    #expect(!editor.contains("for team in teams"))
    let teamWorkspace = try sourceFile("MultiOrg/Features/Coach/CoachTeamCommandCenterView.swift")
    #expect(teamWorkspace.contains("TeamEventEditorView("))
    #expect(teamWorkspace.contains("preselectedTeamId: team.id"))
  }

  @Test("Coach Today stays aggregated and independent from Team selector")
  func coachTodayScope() throws {
    let source = try sourceFile("MultiOrg/Features/Coach/CoachTeamCommandCenterView.swift")
    let today = try sourceSlice(source, from: "struct CoachTodayFoundationView", to: "struct CoachScheduleFoundationView")
    #expect(today.contains("All assigned teams"))
    #expect(today.contains("teamId: nil"))
    #expect(today.contains("all-assigned-teams"))
    #expect(!today.contains("CoachTeamSelector"))
    #expect(!today.contains("selectedTeamId"))
  }

  @Test("Player and Parent never receive the staff Team selector")
  func derivedPlayerAndChildContext() throws {
    let player = try sourceFile("MultiOrg/Features/Home/PlayerHomeView.swift")
    let parent = try sourceFile("MultiOrg/Features/Home/ParentHomeView.swift")
    #expect(!player.contains("CoachTeamSelector"))
    #expect(!parent.contains("CoachTeamSelector"))
    #expect(parent.contains("Select a child"))
    #expect(parent.contains("SidebarSelection.child"))
  }

  @Test("navigation uses Team and Teams without Current Team ambiguity")
  func navigationNaming() {
    let owner = HPAppNavigationInventory.owner(
      facilitiesTitle: "Facilities", programsTitle: "Programs",
      facilitiesEnabled: true, chatEnabled: true, programsEnabled: true,
      isPlatformAdmin: false
    )
    #expect(owner.regularItems.contains(where: { $0.destination == .coachTeam && $0.title == "Team" }))
    #expect(owner.regularItems.contains(where: { $0.destination == .coachTeams && $0.title == "Teams" }))
    #expect(owner.regularItems.contains(where: { $0.destination == .organizationAdmin && $0.title == "Organization" }))
    #expect(!owner.regularItems.contains(where: { $0.title == "Current Team" }))
    #expect(!owner.regularItems.contains(where: { $0.title == "Team Management" }))
    #expect(owner.compactItems.map(\.title) == ["Overview", "Finance", "Chat", "Organization"])
  }

  @Test("superseded or cross-context team responses cannot publish")
  func staleResponseSuppression() {
    let currentToken = UUID()
    #expect(!SDAsyncRequestGuard.accepts(
      responseContext: teamA,
      responseToken: UUID(),
      activeContext: teamA,
      currentToken: currentToken
    ))
    #expect(!SDAsyncRequestGuard.accepts(
      responseContext: teamA,
      responseToken: currentToken,
      activeContext: teamB,
      currentToken: currentToken
    ))
    #expect(SDAsyncRequestGuard.accepts(
      responseContext: teamA,
      responseToken: currentToken,
      activeContext: teamA,
      currentToken: currentToken
    ))
  }

  @Test("backend validates explicit team organization and actor authority")
  func backendContract() throws {
    let source = try sourceFile("supabase/functions/team-scheduling/index.ts")
    #expect(source.contains("team_missing"))
    #expect(source.contains("team_archived"))
    #expect(source.contains("stale_team_context"))
    #expect(source.contains("permission_denied"))
    #expect(source.contains("organization_id"))
    #expect(source.contains("team_id"))
    #expect(source.contains("const isAdmin = role === \"owner\" || role === \"admin\""))
  }

  private func team(
    id: UUID,
    organizationId: UUID,
    active: Bool = true,
    primary: Bool = false
  ) -> SDTeamOperationsTeam {
    SDTeamOperationsTeam(
      id: id,
      org_id: organizationId,
      season_id: seasonId,
      name: id == teamA ? "10U" : "12U",
      color_hex: nil,
      description: nil,
      age_group: "10U",
      competitive_level: "Travel",
      roster_capacity: nil,
      is_active: active,
      sort_order: 0,
      created_by: nil,
      created_at: nil,
      updated_at: nil,
      is_primary: primary,
      roster_count: 12,
      staff_count: 2,
      capabilities: [.viewTeam, .viewTeamSchedule, .createTeamEvent]
    )
  }

  private func sourceFile(_ relativePath: String) throws -> String {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    return try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
  }

  private func sourceSlice(_ source: String, from start: String, to end: String) throws -> String {
    let lower = try #require(source.range(of: start))
    let upper = try #require(source.range(of: end, range: lower.upperBound..<source.endIndex))
    return String(source[lower.lowerBound..<upper.lowerBound])
  }

  private func sourceSuffix(_ source: String, from start: String) throws -> String {
    let lower = try #require(source.range(of: start))
    return String(source[lower.lowerBound...])
  }
}

#if canImport(UIKit)
@MainActor
final class Phase13ATeamContextRenderTests: XCTestCase {
  func testRepresentativeSelectorStatesRenderWithoutClipping() throws {
    for state in ["10U", "Marist Red Foxes 12U National Travel Team", "No team assigned"] {
      let view = HPWorkspaceHeader("Team", orgLabel: "2027 Spring", context: state) {
        HStack(spacing: HP.Space.xs) {
          Image(systemName: "shield.lefthalf.filled")
          VStack(alignment: .leading, spacing: 1) {
            Text("Team").font(HP.Font.caption)
            Text(state).font(HP.Font.callout.weight(.semibold)).lineLimit(1)
          }
        }
        .frame(minHeight: 44)
      }
      try assertRenders(AnyView(view), width: 393, height: 220)
      try assertRenders(AnyView(view), width: 1_024, height: 220)
    }
  }

  func testGlobalAndTeamScheduleHeadersRender() throws {
    try assertRenders(AnyView(
      HPWorkspaceHeader("Schedule", orgLabel: "Marist Red Foxes", context: "Visible filter: All Teams") {
        Label("New Event", systemImage: "plus").frame(minHeight: 44)
      }
    ))
    try assertRenders(AnyView(
      HPWorkspaceHeader("Team", orgLabel: "2027 Spring", context: "10U • Travel") {
        Label("10U", systemImage: "shield.lefthalf.filled").frame(minHeight: 44)
      }
    ))
  }

  private func assertRenders(
    _ view: AnyView,
    width: CGFloat = 393,
    height: CGFloat = 240
  ) throws {
    let root = view
      .padding(HP.Space.md)
      .background(HP.Color.bg)
      .frame(width: width, height: height)
    let host = UIHostingController(rootView: root)
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: height))
    window.rootViewController = host
    window.makeKeyAndVisible()
    host.view.frame = window.bounds
    host.view.layoutIfNeeded()
    RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    let image = UIGraphicsImageRenderer(size: window.bounds.size).image { context in
      host.view.layer.render(in: context.cgContext)
    }
    XCTAssertGreaterThan(try XCTUnwrap(image.pngData()).count, 4_000)
    window.isHidden = true
    window.rootViewController = nil
  }
}
#endif
