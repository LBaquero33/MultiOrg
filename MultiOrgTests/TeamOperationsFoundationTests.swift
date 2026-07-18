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
}
#endif
