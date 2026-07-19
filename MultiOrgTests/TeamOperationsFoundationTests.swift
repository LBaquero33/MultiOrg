import Foundation
import Supabase
import SwiftUI
import Testing
import XCTest
@testable import HomePlate

#if canImport(UIKit)
import UIKit
#endif

@Suite("Phase 12A team operations foundation")
struct TeamOperationsFoundationTests {
  private let orgA = UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")!
  private let orgB = UUID(uuidString: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb")!
  private let seasonA = UUID(uuidString: "cccccccc-cccc-4ccc-8ccc-cccccccccccc")!
  private let seasonB = UUID(uuidString: "dddddddd-dddd-4ddd-8ddd-dddddddddddd")!

  @Test("one-team coach is selected without a switch choice")
  func oneTeamAutoSelection() {
    let only = team(name: "Varsity")
    #expect(SDSelectedTeamResolver.resolve(
      persistedTeamId: nil,
      organizationId: orgA,
      seasonId: seasonA,
      teams: [only]
    ) == only.id)
  }

  @Test("multi-team selection persists while authorized")
  func multiTeamPersistence() {
    let first = team(name: "Varsity")
    let second = team(name: "JV")
    #expect(SDSelectedTeamResolver.resolve(
      persistedTeamId: second.id,
      organizationId: orgA,
      seasonId: seasonA,
      teams: [first, second]
    ) == second.id)
  }

  @Test("removed team safely falls back to primary")
  func removedTeamFallback() {
    let primary = team(name: "Varsity", isPrimary: true)
    let other = team(name: "JV")
    #expect(SDSelectedTeamResolver.resolve(
      persistedTeamId: UUID(),
      organizationId: orgA,
      seasonId: seasonA,
      teams: [other, primary]
    ) == primary.id)
  }

  @Test("selected team cannot cross organization or season")
  func crossOrganizationIsolation() {
    let foreignOrg = team(name: "Foreign", organizationId: orgB)
    let foreignSeason = team(name: "Old", seasonId: seasonB)
    #expect(SDSelectedTeamResolver.resolve(
      persistedTeamId: foreignOrg.id,
      organizationId: orgA,
      seasonId: seasonA,
      teams: [foreignOrg, foreignSeason]
    ) == nil)
  }

  @Test("coach iPhone inventory is Today Team Schedule More")
  func compactNavigation() {
    let inventory = HPAppNavigationInventory.staff(
      playersTitle: "Players",
      facilitiesTitle: "Facilities",
      programsTitle: "Programs",
      facilitiesEnabled: true,
      chatEnabled: true,
      programsEnabled: true,
      canAdministerOrganization: false,
      isPlatformAdmin: false
    )
    #expect(inventory.compactItems.map(\.destination) == [.coachToday, .coachTeam, .coachSchedule])
    #expect(inventory.compactTabCountIncludingDirectory == 4)
    #expect(inventory.defaultDestination == .coachToday)
    #expect(!inventory.directoryItems.contains(where: { $0.destination == .coachPlayers }))
  }

  @Test("team selector is hidden for one team and compact for multiple teams")
  func switcherWiring() throws {
    let source = try sourceFile("MultiOrg/Features/Coach/CoachTeamCommandCenterView.swift")
    #expect(source.contains("if appState.authorizedCoachTeams.count > 1"))
    #expect(source.contains("struct CoachTeamSelector"))
    #expect(source.contains("Menu {"))
    #expect(source.contains("teamOperationsContext?.can_access_all_teams == true"))
  }

  @Test("Team opens the command-center overview")
  func commandCenterDefault() throws {
    let source = try sourceFile("MultiOrg/Features/Coach/CoachTeamCommandCenterView.swift")
    #expect(source.contains("@State private var section: Section = .overview"))
    #expect(source.contains("case overview = \"Overview\""))
    #expect(source.contains("case players = \"Players\""))
    #expect(source.contains("case settings = \"Settings\""))
  }

  @Test("database preserves player history and enforces one active team")
  func schemaInvariants() throws {
    let migration = try sourceFile("supabase/migrations/20260717170000_team_operations_foundation.sql")
    #expect(migration.contains("uq_sd_player_one_active_team_per_org"))
    #expect(migration.contains("where active and ended_at is null"))
    #expect(migration.contains("legacy_team_assignment"))
    #expect(migration.contains("update({ active: false") == false)
    #expect(migration.contains("enable row level security"))
  }

  @Test("organization admin mutations are authorized on the server")
  func adminAuthorization() throws {
    let source = try sourceFile("supabase/functions/org_admin/index.ts")
    #expect(source.contains("teamOperationsAdminActions.includes(action) && !hasAdminAuthority"))
    #expect(source.contains("return json(403, { error: \"org_admin_required\" })"))
    #expect(source.contains("sd_team_operations_audit_logs"))
  }

  @Test("Swift and backend org_admin action contracts stay synchronized")
  func orgAdminActionContractSynchronization() throws {
    let backend = try sourceFile("supabase/functions/_shared/org_admin_actions.ts")
    let swiftActions = Set(SDOrgAdminAction.allCases.map(\.rawValue))
    #expect(swiftActions.contains("create_season"))
    #expect(swiftActions.contains("update_season"))
    #expect(swiftActions.count == 18)
    for action in swiftActions {
      #expect(backend.contains("\"\(action)\""))
    }
    #expect(!backend.contains("createSeason"))
  }

  @Test("unsupported actions map to controlled copy without raw server text")
  func unsupportedActionMapping() {
    for code in ["unknown_action", "unsupported_action"] {
      let error = SDEdgeFunctionHTTPError(
        statusCode: 400,
        code: code,
        message: "Unknown Action. RPC sd_create_season failed."
      )
      let presentation = SDApplicationErrorClassifier.presentation(for: error)
      #expect(presentation?.category == .unsupportedAction)
      #expect(presentation?.message == "This action is not available in this version.")
      #expect(presentation?.message.localizedCaseInsensitiveContains("unknown") == false)
      #expect(presentation?.message.localizedCaseInsensitiveContains("sd_create_season") == false)
    }
  }

  @Test("season draft validates required context name and date order")
  func seasonDraftValidation() {
    let valid = SDSeasonDraft(
      organizationId: orgA,
      name: "2027 Spring",
      startDate: "2027-05-09",
      endDate: "2027-07-26",
      lifecycle: .planning,
      isDefault: true
    )
    #expect(valid.isValid)
    #expect(SDSeasonDraft(
      organizationId: orgA,
      name: "Spring",
      startDate: "2027-07-26",
      endDate: "2027-05-09",
      lifecycle: .planning,
      isDefault: false
    ).validationIssue == .endBeforeStart)
    #expect(SDSeasonDraft(
      organizationId: nil,
      name: "Spring",
      startDate: nil,
      endDate: nil,
      lifecycle: .planning,
      isDefault: false
    ).validationIssue == .missingOrganization)
  }

  @Test("Team Operations uses local loading contextual errors and a context header")
  func teamOperationsUsabilityContracts() throws {
    let source = try sourceFile("MultiOrg/Features/Admin/OrgTeamOperationsAdminView.swift")
    #expect(source.contains("HPWorkspaceHeader("))
    #expect(source.contains("Organization Administration"))
    #expect(source.contains("activeMutations.contains(.season)"))
    #expect(source.contains("This action is not available in the current environment."))
    #expect(source.contains("DatePicker(\"Start date\""))
    #expect(source.contains(".alert(\"Team Operations\"") == false)
    #expect(source.contains("error.localizedDescription") == false)
  }

  @Test("team selection precedence is explicit persisted primary first active then none")
  func teamSelectionPrecedence() {
    let first = team(name: "First")
    let primary = team(name: "Primary", isPrimary: true)
    let explicit = team(name: "Explicit")
    #expect(SDSelectedTeamResolver.resolve(
      explicitTeamId: explicit.id, persistedTeamId: first.id,
      organizationId: orgA, seasonId: seasonA,
      teams: [first, primary, explicit]
    ) == .init(teamId: explicit.id, source: .explicit))
    #expect(SDSelectedTeamResolver.resolve(
      explicitTeamId: UUID(), persistedTeamId: first.id,
      organizationId: orgA, seasonId: seasonA,
      teams: [first, primary]
    ) == .init(teamId: first.id, source: .persisted))
    #expect(SDSelectedTeamResolver.resolve(
      explicitTeamId: nil, persistedTeamId: nil,
      organizationId: orgA, seasonId: seasonA,
      teams: [first, primary]
    ) == .init(teamId: primary.id, source: .primaryAssignment))
    #expect(SDSelectedTeamResolver.resolve(
      explicitTeamId: nil, persistedTeamId: nil,
      organizationId: orgA, seasonId: seasonA,
      teams: [first]
    ) == .init(teamId: first.id, source: .firstActiveTeam))
    #expect(SDSelectedTeamResolver.resolve(
      explicitTeamId: nil, persistedTeamId: nil,
      organizationId: orgA, seasonId: seasonA,
      teams: []
    ) == .init(teamId: nil, source: .none))
  }

  @Test("Mac team roster board preserves history and offers accessible move alternatives")
  func macTeamManagementContract() throws {
    let view = try sourceFile("MultiOrg/Features/Admin/OrgTeamOperationsAdminView.swift")
    let migration = try sourceFile("supabase/migrations/20260718153000_phase_12zb_team_unassignment.sql")
    #expect(view.contains(".dropDestination(for: String.self)"))
    #expect(view.contains("Drag player cards between columns"))
    #expect(view.contains("optimisticTeamByPlayer"))
    #expect(migration.contains("set active = false, ended_at = now()"))
    #expect(!migration.localizedCaseInsensitiveContains("delete from public.sd_player_team_memberships"))
    #expect(migration.contains("sd_team_operations_audit_logs"))
  }

  @Test("Mac destination shell owns notification chrome and one vertical screen scroll")
  func macShellContract() throws {
    let root = try sourceFile("MultiOrg/App/RootView.swift")
    let shell = try sourceFile("MultiOrg/Features/Home/HomePlateNavigationShell.swift")
    let scaffold = try sourceFile("MultiOrg/DesignSystem/Templates/HPScreenScaffold.swift")
    #expect(root.contains("#if os(iOS)\n    .safeAreaInset(edge: .top"))
    #expect(shell.contains("ToolbarItem(placement: .primaryAction)"))
    #expect(scaffold.contains(".contentMargins(.top, HP.Space.lg, for: .scrollContent)"))
  }

  @Test("Programs use a two-pane desktop workspace without a nested split or editor cap")
  func macProgramsContract() throws {
    let programs = try sourceFile("MultiOrg/Features/Coach/CoachProgramsView.swift")
    let editor = try sourceFile("MultiOrg/Features/Coach/ProgramTemplateEditorView.swift")
    #expect(programs.contains("HSplitView"))
    #expect(programs.contains("idealWidth: 300"))
    #expect(!programs.contains("NavigationSplitView"))
    #expect(editor.contains("HPFormScreenLayout(maxContentWidth: nil)"))
  }

  @Test("organization lifecycle and finance rules preserve history")
  func organizationLifecycleRules() {
    #expect(SDSeasonLifecycle.planning.canTransition(to: .registrationOpen))
    #expect(!SDSeasonLifecycle.planning.canTransition(to: .active))
    #expect(!SDSeasonLifecycle.archived.canTransition(to: .planning))
    #expect(SDInvoiceLifecycleRule.nextStatus(current: "draft", action: "issue") == "issued")
    #expect(SDInvoiceLifecycleRule.nextStatus(current: "paid", action: "void") == nil)
  }

  @Test("required in-app notices survive quiet-hours push suppression")
  func notificationPreferenceRules() {
    let decision = SDNotificationPreferenceRule.delivery(
      inAppEnabled: false,
      pushEnabled: true,
      required: true,
      localMinutes: 23 * 60,
      quietStartMinutes: 22 * 60,
      quietEndMinutes: 7 * 60
    )
    #expect(decision.inApp)
    #expect(!decision.push)
  }

  @Test("organization operations stay contextual instead of becoming tabs")
  func organizationNavigationContract() throws {
    let shell = try sourceFile("MultiOrg/Features/Home/HomePlateNavigationShell.swift")
    #expect(!shell.contains("case registration"))
    #expect(!shell.contains("case reports"))
    let admin = try sourceFile("MultiOrg/Features/Admin/OrgAdminConsoleView.swift")
    #expect(admin.contains("case communication = \"Communication\""))
    #expect(admin.contains("case registration = \"Registration\""))
    #expect(admin.contains("case analytics = \"Analytics\""))
    #expect(admin.contains("Report center"))
    #expect(admin.contains("Share CSV"))
  }

  @Test("organization operations migrations preserve isolation and provider safety")
  func organizationOperationsMigrationContracts() throws {
    let communication = try sourceFile("supabase/migrations/20260718100000_organization_communication.sql")
    #expect(communication.contains("sd_notification_intent_receipts"))
    #expect(communication.contains("app.notification_delivery_enabled"))
    #expect(communication.contains("p_dry_run boolean default true"))
    let registration = try sourceFile("supabase/migrations/20260718110000_registration_season_lifecycle.sql")
    #expect(registration.contains("sd_season_transition_allowed"))
    #expect(registration.contains("players_copied',0"))
    let finance = try sourceFile("supabase/migrations/20260718120000_organization_business_operations.sql")
    #expect(finance.contains("financial_layer='organization_customer'"))
    #expect(finance.contains("m.role in ('owner','admin')"))
    let analytics = try sourceFile("supabase/migrations/20260718130000_organization_analytics.sql")
    #expect(analytics.contains("'as_of',pg_catalog.now()"))
    #expect(!analytics.localizedCaseInsensitiveContains("health score"))
  }

  @Test("Edge Function 404 maps to a controlled unavailable state")
  func edgeFunctionUnavailableMapping() {
    let error = FunctionsError.httpError(code: 404, data: Data())
    let presentation = SDApplicationErrorClassifier.presentation(for: error)
    #expect(presentation?.category == .notDeployed)
    #expect(presentation?.message == "This feature is temporarily unavailable.")
    #expect(presentation?.message.contains("404") == false)
    #expect(presentation?.message.localizedCaseInsensitiveContains("Edge Function") == false)
  }

  @Test("expected cancellation never creates an alert")
  func cancellationMapping() {
    #expect(SDApplicationErrorClassifier.alertMessage(for: CancellationError()) == nil)
    #expect(SDApplicationErrorClassifier.alertMessage(for: URLError(.cancelled)) == nil)
    let wrapped = NSError(
      domain: "NetworkWrapper",
      code: 1,
      userInfo: [NSUnderlyingErrorKey: URLError(.cancelled)]
    )
    #expect(SDApplicationErrorClassifier.alertMessage(for: wrapped) == nil)
  }

  @Test("a genuine network failure remains user visible")
  func genuineNetworkFailureMapping() {
    let presentation = SDApplicationErrorClassifier.presentation(
      for: URLError(.notConnectedToInternet)
    )
    #expect(presentation?.category == .offline)
    #expect(presentation?.message != nil)
  }

  @Test("superseded and context-changed requests cannot publish")
  func asyncRequestGuard() {
    let current = UUID()
    let superseded = UUID()
    #expect(!SDAsyncRequestGuard.accepts(
      responseContext: "organization-a",
      responseToken: superseded,
      activeContext: "organization-a",
      currentToken: current
    ))
    #expect(!SDAsyncRequestGuard.accepts(
      responseContext: "organization-a",
      responseToken: current,
      activeContext: "organization-b",
      currentToken: current
    ))
    #expect(SDAsyncRequestGuard.accepts(
      responseContext: "organization-a",
      responseToken: current,
      activeContext: "organization-a",
      currentToken: current
    ))
  }

  @Test("player coach and owner navigation remain role appropriate")
  func roleNavigationInventories() {
    let player = HPAppNavigationInventory.player(
      chatEnabled: true,
      facilitiesEnabled: true,
      testingEnabled: true,
      analysisEnabled: true,
      facilitiesTitle: "Facilities",
      testingTitle: "Testing"
    )
    #expect(player.compactItems.map(\.title) == ["Today", "Calendar", "Trends", "Chat"])
    #expect(player.compactTabCountIncludingDirectory == 5)

    let coach = HPAppNavigationInventory.staff(
      playersTitle: "Players",
      facilitiesTitle: "Facilities",
      programsTitle: "Programs",
      facilitiesEnabled: true,
      chatEnabled: true,
      programsEnabled: true,
      canAdministerOrganization: false,
      isPlatformAdmin: false
    )
    #expect(coach.compactItems.map(\.title) == ["Today", "Team", "Schedule"])
    #expect(coach.compactTabCountIncludingDirectory == 4)

    let owner = HPAppNavigationInventory.owner(
      facilitiesTitle: "Facilities",
      programsTitle: "Programs",
      facilitiesEnabled: true,
      chatEnabled: true,
      programsEnabled: true,
      isPlatformAdmin: false
    )
    #expect(owner.compactItems.map(\.title) == ["Overview", "Finance", "Chat", "Organization"])
    #expect(owner.compactTabCountIncludingDirectory == 5)
    #expect(owner.regularItems.contains(where: { $0.title == "Current Team" }))
    #expect(owner.regularItems.contains(where: { $0.title == "Team Management" }))
    #expect(!owner.regularItems.contains(where: { $0.destination == .platformAdmin }))
    #expect(owner.regularSections.contains(where: { $0.title == "Operate" }))
    #expect(owner.regularSections.contains(where: { $0.title == "Administer" }))

    let platformOwner = HPAppNavigationInventory.owner(
      facilitiesTitle: "Facilities",
      programsTitle: "Programs",
      facilitiesEnabled: true,
      chatEnabled: true,
      programsEnabled: true,
      isPlatformAdmin: true
    )
    #expect(platformOwner.regularItems.contains(where: { $0.destination == .platformAdmin }))
  }

  private func team(
    name: String,
    organizationId: UUID? = nil,
    seasonId: UUID? = nil,
    isPrimary: Bool = false
  ) -> SDTeamOperationsTeam {
    SDTeamOperationsTeam(
      id: UUID(),
      org_id: organizationId ?? orgA,
      season_id: seasonId ?? seasonA,
      name: name,
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
      is_primary: isPrimary,
      roster_count: 0,
      staff_count: 0,
      capabilities: [.viewTeam]
    )
  }

  private func sourceFile(_ path: String) throws -> String {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
  }
}

#if canImport(UIKit)
@MainActor
final class Phase12UnavailableStateRenderTests: XCTestCase {
  func testRenderControlledUnavailableState() throws {
    let view = HPCard {
      HPErrorState(
        title: "Calendar unavailable",
        message: "This feature is temporarily unavailable.",
        onRetry: {}
      )
    }
    .padding(HP.Space.md)
    .background(HP.Color.bg)
    .frame(width: 393, height: 320)

    let host = UIHostingController(rootView: view)
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 320))
    window.rootViewController = host
    window.makeKeyAndVisible()
    host.view.frame = window.bounds
    host.view.layoutIfNeeded()
    RunLoop.current.run(until: Date().addingTimeInterval(0.1))

    let renderer = UIGraphicsImageRenderer(size: window.bounds.size)
    let image = renderer.image { context in
      host.view.layer.render(in: context.cgContext)
    }
    let data = try XCTUnwrap(image.pngData())
    XCTAssertGreaterThan(data.count, 5_000)
    XCTAssertFalse(String(describing: view).contains("404"))

    window.isHidden = true
    window.rootViewController = nil
  }

  func testRenderCreateSeasonRepresentativeStates() throws {
    try assertRenders(AnyView(
      HPCard {
        VStack(alignment: .leading, spacing: HP.Space.sm) {
          HPSectionHeader("Seasons")
          HPFormField(label: "Season name", text: .constant("2027 Spring"), placeholder: "2027 Spring")
          DatePicker("Start date", selection: .constant(Date()), displayedComponents: .date)
          DatePicker("End date", selection: .constant(Date()), displayedComponents: .date)
          Picker("Lifecycle", selection: .constant(SDSeasonLifecycle.planning)) {
            Text("Planning").tag(SDSeasonLifecycle.planning)
          }
          Toggle("Default season", isOn: .constant(true))
          HPButton(title: "Create Season", systemImage: "plus", variant: .primary, size: .md) {}
        }
      }
    ))
    try assertRenders(AnyView(
      HPCard {
        VStack(spacing: HP.Space.sm) {
          HPFormField(label: "Season name", text: .constant(""), placeholder: "2027 Spring")
          Text("Enter a season name.").foregroundStyle(HP.Color.warning)
          HPButton(title: "Create Season", variant: .primary, size: .md) {}
            .disabled(true)
        }
      }
    ))
    try assertRenders(AnyView(
      HPCard {
        HPErrorState(
          title: "The season could not be created.",
          message: "This action is not available in the current environment.",
          onRetry: {}
        )
      }
    ))
  }

  func testRenderMacContextLoadingAndSidebarFixtures() throws {
    try assertRenders(AnyView(
      VStack(spacing: HP.Space.md) {
        HPWorkspaceHeader(
          "Team Management",
          orgLabel: "Red Foxes",
          context: "Organization Administration · 2027 Spring · Organization-wide"
        )
        HPCard { HPLoadingState(text: "Creating season…") }
      }
    ), width: 720, height: 420)

    for platformAdmin in [false, true] {
      let inventory = HPAppNavigationInventory.owner(
        facilitiesTitle: "Facilities",
        programsTitle: "Program Templates",
        facilitiesEnabled: true,
        chatEnabled: true,
        programsEnabled: true,
        isPlatformAdmin: platformAdmin
      )
      try assertRenders(AnyView(
        HPSidebar(
          orgIdentity: .homePlate,
          role: .owner,
          groups: inventory.regularGroups,
          selectionKey: .constant(Optional(HPAppNavigationDestination.coachToday.rawValue))
        )
      ), width: 300, height: 700)
    }
  }

  func testRenderPopulatedOperationsAndScopedUnavailableFixtures() throws {
    try assertRenders(AnyView(
      HPCard {
        VStack(alignment: .leading, spacing: HP.Space.sm) {
          HPSectionHeader("Seasons") { HPStatusBadge(text: "1 active", kind: .success) }
          Text("2027 Spring").font(HP.Font.headline)
          Text("May 9 – July 26").foregroundStyle(HP.Color.textMuted)
          HPStatusBadge(text: "Planning", kind: .neutral)
        }
      }
    ))
    for title in ["Today’s schedule couldn’t be loaded.", "Calendar couldn’t be loaded."] {
      try assertRenders(AnyView(
        HPCard {
          HPErrorState(
            title: title,
            message: "The scheduling service is not available in this environment.",
            onRetry: {}
          )
        }
      ))
    }
  }

  private func assertRenders(
    _ view: AnyView,
    width: CGFloat = 393,
    height: CGFloat = 480
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
    XCTAssertGreaterThan(try XCTUnwrap(image.pngData()).count, 5_000)
    window.isHidden = true
    window.rootViewController = nil
  }
}
#endif
