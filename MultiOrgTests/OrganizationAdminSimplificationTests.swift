import Foundation
import SwiftUI
import Testing
@testable import HomePlate

@Suite("Phase 12ZD simplified organization administration")
struct OrganizationAdminSimplificationTests {
  @Test("Organization Admin has exactly five primary task-based sections")
  func fivePrimarySections() throws {
    let source = try sourceFile("MultiOrg/Features/Admin/OrgAdminConsoleView.swift")
    let tabStart = try #require(source.range(of: "enum Tab: String, CaseIterable, Identifiable"))
    let tabEnd = try #require(source.range(of: "var id: String { rawValue }", range: tabStart.upperBound..<source.endIndex))
    let tabSource = String(source[tabStart.lowerBound..<tabEnd.lowerBound])

    #expect(tabSource.contains("case overview = \"Overview\""))
    #expect(tabSource.contains("case people = \"People\""))
    #expect(tabSource.contains("case teamsAndSeasons = \"Teams & Seasons\""))
    #expect(tabSource.contains("case business = \"Business\""))
    #expect(tabSource.contains("case settings = \"Settings\""))
    #expect(tabSource.components(separatedBy: "case ").count - 1 == 5)
  }

  @Test("compact header removes console and persistent autosave chrome")
  func compactHeader() throws {
    let source = try sourceFile("MultiOrg/Features/Admin/OrgAdminConsoleView.swift")
    let headerStart = try #require(source.range(of: "private var header: some View"))
    let headerEnd = try #require(source.range(of: "private var organizationIdentity", range: headerStart.upperBound..<source.endIndex))
    let header = String(source[headerStart.lowerBound..<headerEnd.lowerBound])

    #expect(header.contains("Text(\"Organization\")"))
    #expect(header.contains("Manage people, teams, business settings, and organization details."))
    #expect(header.contains("Continue Setup"))
    #expect(header.contains("Organization Admin Console") == false)
    #expect(header.contains("Autosave on") == false)
  }

  @Test("navigation switches immediately supports keyboard movement and narrows to More")
  func adaptiveNavigation() throws {
    let source = try sourceFile("MultiOrg/Features/Admin/OrgAdminConsoleView.swift")
    #expect(source.contains("ViewThatFits(in: .horizontal)"))
    #expect(source.contains("[.overview, .people, .teamsAndSeasons]"))
    #expect(source.contains("overflow: [.business, .settings]"))
    #expect(source.contains(".onMoveCommand"))
    #expect(source.contains("transaction.disablesAnimations = true"))
    #expect(source.contains(".accessibilityValue(selectedTab.rawValue)"))
  }

  @Test("wide and narrow render policies preserve the task-based structure")
  func wideAndNarrowRenderPolicies() throws {
    let narrow = HPScreenLayoutContext.resolve(
      widthMode: .automatic,
      horizontalSizeClass: .regular,
      dynamicTypeSize: .large,
      containerWidth: 393
    )
    let wide = HPScreenLayoutContext.resolve(
      widthMode: .automatic,
      horizontalSizeClass: .regular,
      dynamicTypeSize: .large,
      containerWidth: 1_200
    )
    let adminSource = try sourceFile("MultiOrg/Features/Admin/OrgAdminConsoleView.swift")
    let teamsSource = try sourceFile("MultiOrg/Features/Admin/OrgTeamOperationsAdminView.swift")

    #expect(narrow.widthClass == .compact)
    #expect(wide.widthClass == .wide)
    #expect(adminSource.contains("ViewThatFits(in: .horizontal)"))
    #expect(teamsSource.contains("ViewThatFits(in: .horizontal)"))
  }

  @Test("Overview contains readiness counts attention and required quick actions")
  func overviewContracts() throws {
    let source = try sourceFile("MultiOrg/Features/Admin/OrgAdminConsoleView.swift")
    for copy in [
      "Organization status", "Active teams", "Members", "Players", "Coaches", "Invitations",
      "Needs attention", "Add Member", "Create Team", "Create Season", "Open Registration",
      "Edit Organization",
    ] {
      #expect(source.contains(copy))
    }
    #expect(source.contains("organizationNeedsSetup"))
    #expect(source.contains("organizationAttentionItems"))
    #expect(source.contains("teamOperationsLaunchAction = .createTeam"))
    #expect(source.contains("teamOperationsLaunchAction = .createSeason"))
  }

  @Test("People consolidates search filters members and invitations without raw IDs")
  func peopleContracts() throws {
    let source = try sourceFile("MultiOrg/Features/Admin/OrgAdminConsoleView.swift")
    #expect(source.contains("HPSearchBar(text: $peopleSearch"))
    #expect(source.contains("case staff = \"Staff\""))
    #expect(source.contains("case players = \"Players\""))
    #expect(source.contains("case families = \"Families\""))
    #expect(source.contains("case invitations = \"Invitations\""))
    #expect(source.contains("peopleRoleFilter"))
    #expect(source.contains("peopleStatusFilter"))
    #expect(source.contains("Create Invite Link"))
    #expect(source.contains("Contact information not provided"))
    #expect(source.contains("title: \"People unavailable\""))
    #expect(source.contains("title: \"Invitations unavailable\""))
  }

  @Test("Teams and Seasons initial page is list detail and create forms live in sheets")
  func teamsAndSeasonsLayout() throws {
    let source = try sourceFile("MultiOrg/Features/Admin/OrgTeamOperationsAdminView.swift")
    let pageStart = try #require(source.range(of: "private var pageContent: some View"))
    let pageEnd = try #require(source.range(of: "private var organizationName", range: pageStart.upperBound..<source.endIndex))
    let page = String(source[pageStart.lowerBound..<pageEnd.lowerBound])

    #expect(page.contains("teamsAndSeasonsWorkspace"))
    #expect(page.contains("seasonCard") == false)
    #expect(page.contains("teamSeasonCard") == false)
    #expect(source.contains("ViewThatFits(in: .horizontal)"))
    #expect(source.contains("teamList"))
    #expect(source.contains("teamDetail"))
    #expect(source.contains(".sheet(isPresented: $isShowingSeasonEditor)"))
    #expect(source.contains(".sheet(isPresented: $isShowingTeamEditor)"))
  }

  @Test("Create Season sheet validates labeled fields and closes after save")
  func createSeasonSheet() throws {
    let source = try sourceFile("MultiOrg/Features/Admin/OrgTeamOperationsAdminView.swift")
    #expect(source.contains("private var seasonEditorSheet"))
    #expect(source.contains("TextField(\"Season name\""))
    #expect(source.contains("Example: 2027 Spring"))
    #expect(source.contains("DatePicker(\"Start date\""))
    #expect(source.contains("DatePicker(\"End date\""))
    #expect(source.contains("Picker(\"Lifecycle\""))
    #expect(source.contains("Toggle(\"Make default season\""))
    #expect(source.contains("isShowingSeasonEditor = false"))
    #expect(source.contains("selectedSeasonId = saved.id"))
    #expect(source.contains("let requestId = seasonRequestId"))
  }

  @Test("Create Team sheet has the approved fields no color and idempotent retry")
  func createTeamSheet() throws {
    let source = try sourceFile("MultiOrg/Features/Admin/OrgTeamOperationsAdminView.swift")
    let sheetStart = try #require(source.range(of: "private var teamEditorSheet"))
    let sheetEnd = try #require(source.range(of: "private var schedulingCard", range: sheetStart.upperBound..<source.endIndex))
    let sheet = String(source[sheetStart.lowerBound..<sheetEnd.lowerBound])

    #expect(sheet.contains("TextField(\"Team name\""))
    #expect(sheet.contains("Picker(\"Season\""))
    #expect(sheet.contains("TextField(\"Age group\""))
    #expect(sheet.contains("TextField(\"Level\""))
    #expect(sheet.contains("Roster capacity (optional)"))
    #expect(sheet.contains("TextField(\"Color\"") == false)
    #expect(sheet.contains("teamColor") == false)
    #expect(source.contains("requestId: teamRequestId"))
    #expect(source.contains("teamRequestId = UUID()"))
    #expect(source.contains("isShowingTeamEditor = false"))
  }

  @Test("Team detail owns metadata and deep links operations")
  func teamDetailRouting() throws {
    let source = try sourceFile("MultiOrg/Features/Admin/OrgTeamOperationsAdminView.swift")
    for copy in [
      "Open Team", "Manage Roster", "Manage Staff", "View Schedule", "Edit Team",
      "Archive Team", "Next event",
    ] {
      #expect(source.contains(copy))
    }
    #expect(source.contains("CoachTeamCommandCenterView()"))
    #expect(source.contains("CoachTeamCommandCenterView(initialSection: .schedule)"))
    #expect(source.contains("appState.selectCoachTeam(team.id)"))
  }

  @Test("Business summarizes registration billing analytics and deep links Finance")
  func businessContracts() throws {
    let source = try sourceFile("MultiOrg/Features/Admin/OrgAdminConsoleView.swift")
    #expect(source.contains("private enum BusinessSection"))
    #expect(source.contains("businessSummaryCard"))
    #expect(source.contains("Open detailed Finance"))
    #expect(source.contains("organizationOperationsSection(.registration)"))
    #expect(source.contains("organizationOperationsSection(.analytics)"))
  }

  @Test("Settings shows one selected group and contextual save status")
  func settingsContracts() throws {
    let source = try sourceFile("MultiOrg/Features/Admin/OrgAdminConsoleView.swift")
    #expect(source.contains("private enum SettingsSection"))
    #expect(source.contains("case general = \"General\""))
    #expect(source.contains("case branding = \"Branding\""))
    #expect(source.contains("case operations = \"Operations\""))
    #expect(source.contains("case advanced = \"Advanced\""))
    #expect(source.contains("Label(\"Saving…\""))
    #expect(source.contains("Label(\"Saved\""))
    #expect(source.contains("Label(\"Couldn’t save\""))
    #expect(source.contains("SDOrganizationSetupTestConfiguration.current().allows"))
  }

  @Test("section failures preserve other authoritative content")
  func scopedFailures() throws {
    let source = try sourceFile("MultiOrg/Features/Admin/OrgAdminConsoleView.swift")
    #expect(source.contains("peopleErrorText"))
    #expect(source.contains("invitationErrorText"))
    #expect(source.contains("facilitiesErrorText"))
    #expect(source.contains("settingsSaveErrorText"))
    #expect(source.contains("adminMembers = try await"))
    #expect(source.contains("invitationLinks = try await"))
    #expect(source.contains("facilities = try await"))
  }

  @Test("season validation rejects missing name and reversed dates")
  func seasonValidation() {
    let organizationId = UUID()
    let missingName = SDSeasonDraft(
      organizationId: organizationId,
      name: "",
      startDate: nil,
      endDate: nil,
      lifecycle: .planning,
      isDefault: false
    )
    #expect(!missingName.isValid)

    let reversed = SDSeasonDraft(
      organizationId: organizationId,
      name: "2027 Spring",
      startDate: "2027-05-01",
      endDate: "2027-04-01",
      lifecycle: .planning,
      isDefault: false
    )
    #expect(!reversed.isValid)
  }

  private func sourceFile(_ relativePath: String) throws -> String {
    let current = URL(fileURLWithPath: #filePath)
    let root = current.deletingLastPathComponent().deletingLastPathComponent()
    return try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
  }
}
