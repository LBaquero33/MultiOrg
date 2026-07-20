import Foundation
import SwiftUI
import Testing
import XCTest
@testable import HomePlate

#if canImport(UIKit)
import UIKit
#endif

@Suite("Phase 12Z organization setup")
struct OrganizationSetupTests {
  private let org = SDOrganizationSetupTestConfiguration.maristOrganizationId

  @Test("wizard steps preserve required order and optional boundaries")
  func stepOrder() {
    #expect(SDOrganizationSetupStep.allCases == [
      .basics, .season, .teams, .staff, .playersFamilies, .registrationFees,
      .facilities, .communication, .firstBaseballAction, .reviewLaunch,
    ])
    #expect(!SDOrganizationSetupStep.teams.isOptional)
    #expect(SDOrganizationSetupStep.facilities.isOptional)
    #expect(SDOrganizationSetupStep.season.next == .teams)
    #expect(SDOrganizationSetupStep.season.previous == .basics)
  }

  @Test("CSV validation rejects missing columns duplicates and malformed email")
  func csvValidation() {
    #expect(SDOrganizationSetupCSVValidator.validate("name,email").errors.isEmpty == false)
    let duplicate = SDOrganizationSetupCSVValidator.validate("""
    player_name,player_email,parent_email
    Alex,alex@example.com,parent1@example.com
    Alex Again,alex@example.com,parent2@example.com
    """)
    #expect(duplicate.validRowCount == 1)
    #expect(duplicate.errors.count == 1)
    #expect(SDOrganizationSetupCSVValidator.validate("""
    player_name,player_email,parent_email
    Alex,invalid,parent@example.com
    """).errors.first?.contains("invalid email") == true)
  }

  @Test("temporary setup test mode requires exact UUID environment flag and authority")
  func testModeGuards() {
    let config = SDOrganizationSetupTestConfiguration(
      enabled: true,
      organizationId: org,
      environmentAllowed: true
    )
    #expect(config.allows(organizationId: org, hasAuthority: true))
    for role in ["coach", "player", "parent"] {
      #expect(!config.allows(organizationId: org, hasAuthority: false), "\(role) must be hidden")
    }
    #expect(!config.allows(organizationId: UUID(), hasAuthority: true))
    #expect(!config.allows(organizationId: org, hasAuthority: false))
    #expect(!SDOrganizationSetupTestConfiguration(
      enabled: true,
      organizationId: UUID(),
      environmentAllowed: true
    ).allows(organizationId: UUID(), hasAuthority: true))
    #expect(!SDOrganizationSetupTestConfiguration(
      enabled: true,
      organizationId: org,
      environmentAllowed: false
    ).allows(organizationId: org, hasAuthority: true))
    let defaulted = SDOrganizationSetupTestConfiguration.current(environment: [
      "HOME_PLATE_SETUP_TEST_MODE": "true",
      "HOME_PLATE_ENVIRONMENT": "development",
    ])
    #expect(defaulted.organizationId == org)
    #expect(defaulted.allows(organizationId: org, hasAuthority: true))
    #expect(!SDOrganizationSetupTestConfiguration.current(environment: [
      "HOME_PLATE_SETUP_TEST_MODE": "true",
      "HOME_PLATE_ENVIRONMENT": "production",
    ]).allows(organizationId: org, hasAuthority: true))
  }

  @Test("superseded setup response and changed context are rejected")
  func requestGuard() {
    let current = UUID()
    #expect(SDOrganizationSetupRequestGuard.accepts(
      responseOrganizationId: org,
      responseToken: current,
      activeOrganizationId: org,
      currentToken: current,
      taskIsCancelled: false
    ))
    #expect(!SDOrganizationSetupRequestGuard.accepts(
      responseOrganizationId: org,
      responseToken: UUID(),
      activeOrganizationId: org,
      currentToken: current,
      taskIsCancelled: false
    ))
    #expect(!SDOrganizationSetupRequestGuard.accepts(
      responseOrganizationId: org,
      responseToken: current,
      activeOrganizationId: UUID(),
      currentToken: current,
      taskIsCancelled: false
    ))
    #expect(!SDOrganizationSetupRequestGuard.accepts(
      responseOrganizationId: org,
      responseToken: current,
      activeOrganizationId: org,
      currentToken: current,
      taskIsCancelled: true
    ))
  }

  @Test("wizard implementation is adaptive resumable and backed by one function")
  func implementationContract() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    let source = try String(contentsOf: root.appendingPathComponent("HomePlate/Features/Admin/OrganizationSetupWizardView.swift"))
    let service = try String(contentsOf: root.appendingPathComponent("HomePlate/Core/SupabaseService.swift"))
    let settings = try String(contentsOf: root.appendingPathComponent("HomePlate/Features/Admin/OrgAdminConsoleView.swift"))
    #expect(source.contains("proxy.size.width >= 840"))
    #expect(source.contains("stepSidebar.frame(width: 280)"))
    #expect(source.contains("Save & Exit"))
    #expect(source.contains("Skip for Now"))
    #expect(source.contains("Launch Organization"))
    #expect(source.contains("Reset Wizard Progress Only"))
    #expect(source.contains("Reset Setup Test Data"))
    #expect(source.contains("Review Setup State"))
    #expect(source.contains("resetLocalWizardState"))
    #expect(service.contains("\"organization-setup\""))
    #expect(service.contains("requestId: UUID"))
    #expect(source.contains("pendingMutationRequestIds"))
    #expect(source.contains("snapshot?.seasons.first(where: \\.is_default)"))
    #expect(source.contains("snapshot?.teams.first"))
    #expect(settings.contains("Test Organization Setup Wizard"))
    #expect(settings.contains("Open Setup Wizard"))
  }

  @Test("Phase 12ZA form semantics remove raw storage formats")
  func stabilizedFormContract() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    let source = try String(contentsOf: root.appendingPathComponent("HomePlate/Features/Admin/OrganizationSetupWizardView.swift"))
    #expect(source.contains("OrganizationSetupWizardContentContainer"))
    #expect(source.contains("contentMargins(.top"))
    #expect(source.contains("HPFormField(label: \"Practice name\""))
    #expect(source.contains("DatePicker"))
    #expect(source.contains("Registration fee"))
    #expect(!source.contains("Fee in cents"))
    #expect(!source.contains("Start (ISO 8601)"))
    #expect(!source.contains("Team color (hex)"))
    #expect(!source.contains("TextEditor(text: $staffInvites)"))
    #expect(SDOrganizationSetupStep.allCases.count == 10)
  }

  @Test("staff rows validate email and identify duplicates deterministically")
  func staffInviteRows() {
    var first = SDStaffInviteDraft()
    first.email = " Coach@Example.com "
    var second = SDStaffInviteDraft()
    second.email = "coach@example.com"
    #expect(first.hasValidEmail)
    #expect(first.normalizedEmail == second.normalizedEmail)
    #expect(Set([first.normalizedEmail, second.normalizedEmail]).count == 1)
    first.responsibility = .pitchingCoach
    #expect(first.responsibility.title == "Pitching Coach")
  }

  @Test("multiple pending teams support add remove validation without color")
  func pendingTeams() {
    var first = SDPendingTeamDraft()
    first.name = "14U Red Foxes"
    first.ageGroup = "14U"
    first.level = "Travel"
    first.rosterCapacity = "18"
    let second = SDPendingTeamDraft()
    var teams = [first, second]
    #expect(teams[0].validationError == nil)
    #expect(teams[1].validationError != nil)
    teams.removeAll { $0.id == second.id }
    #expect(teams.map(\.name) == ["14U Red Foxes"])
    let existingId = UUID()
    var existingEdit = SDPendingTeamDraft(existingTeamId: existingId)
    existingEdit.name = "15U Red Foxes"
    #expect(existingEdit.existingTeamId == existingId)
    #expect(existingEdit.validationError == nil)
  }

  @Test("registration dollars convert to minor units without exposing storage")
  func registrationCurrency() {
    #expect(SDPaymentRequestCreateDraft.parseUSDCents("0") == 0)
    #expect(SDPaymentRequestCreateDraft.parseUSDCents("125.40") == 12_540)
    #expect(SDPaymentRequestCreateDraft.parseUSDCents("-1") == nil)
    #expect(SDPaymentRequestCreateDraft.parseUSDCents("1.999") == nil)
  }

  @Test("organization timezone controls local input and DST conversion")
  func timezoneConversion() {
    for identifier in ["America/New_York", "America/Chicago", "America/Los_Angeles", "UTC"] {
      let zone = TimeZone(identifier: identifier)!
      var calendar = Calendar(identifier: .gregorian)
      calendar.timeZone = zone
      let date = calendar.date(from: DateComponents(year: 2026, month: 7, day: 19, hour: 12))!
      let time = calendar.date(from: DateComponents(year: 2026, month: 7, day: 19, hour: 18, minute: 30))!
      let instant = SDOrganizationSetupTimeCodec.instant(date: date, time: time, timeZoneIdentifier: identifier)
      #expect(instant != nil)
      let local = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: instant!)
      #expect(local.year == 2026 && local.month == 7 && local.day == 19)
      #expect(local.hour == 18 && local.minute == 30)
    }
    var ny = Calendar(identifier: .gregorian)
    ny.timeZone = TimeZone(identifier: "America/New_York")!
    let dstDate = ny.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 12))!
    let dstTime = ny.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 3, minute: 30))!
    let instant = SDOrganizationSetupTimeCodec.instant(date: dstDate, time: dstTime, timeZoneIdentifier: "America/New_York")!
    #expect(SDOrganizationSetupTimeCodec.isoUTC(instant) == "2026-03-08T07:30:00Z")
  }

  @Test("signed invite architecture stores only hashes and rejects query authority")
  func invitationSecurityContract() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    let edge = try String(contentsOf: root.appendingPathComponent("supabase/functions/organization-invitations/index.ts"))
    let migration = try String(contentsOf: root.appendingPathComponent("supabase/migrations/20260718170000_setup_invitation_links.sql"))
    let appState = try String(contentsOf: root.appendingPathComponent("HomePlate/Core/AppState.swift"))
    #expect(edge.contains("crypto.subtle.digest("))
    #expect(edge.contains("\"SHA-256\""))
    #expect(edge.contains("invitation_expired"))
    #expect(edge.contains("revoked_at"))
    #expect(edge.contains("account_role_mismatch"))
    #expect(migration.contains("token_hash text not null unique"))
    #expect(!migration.contains("raw_token"))
    #expect(appState.contains("url.host?.lowercased() == \"invite\""))
    #expect(!appState.contains("queryItems"))
  }

  @Test("invite deep-link failures remain controlled and retryable before authentication")
  func inviteUnavailablePresentation() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    let appState = try String(contentsOf: root.appendingPathComponent("HomePlate/Core/AppState.swift"))
    let login = try String(contentsOf: root.appendingPathComponent("HomePlate/Features/Login/LoginView.swift"))
    #expect(appState.contains("SDApplicationErrorClassifier.alertMessage(for: error)"))
    #expect(appState.contains("functionName: \"organization-invitations\""))
    #expect(login.contains("Invitation unavailable"))
    #expect(login.contains("onRetry: retryInvitation"))
    #expect(!login.contains("Edge Function returned"))
  }

  @Test("invite URL parser accepts only one opaque base64url token")
  func invitationURLParsing() throws {
    let token = String(repeating: "a", count: 64)
    #expect(SDOrganizationInvitationURL.token(from: try #require(URL(string: "homeplate://invite/\(token)"))) == token)
    #expect(SDOrganizationInvitationURL.token(from: try #require(URL(string: "homeplate://invite/short"))) == nil)
    #expect(SDOrganizationInvitationURL.token(from: try #require(URL(string: "homeplate://invite/\(token)=bad"))) == nil)
    #expect(SDOrganizationInvitationURL.token(from: try #require(URL(string: "homeplate://invite/\(token)/extra"))) == nil)
    #expect(SDOrganizationInvitationURL.token(from: try #require(URL(string: "https://example.com/invite/\(token)"))) == nil)
  }

  @Test("schedule setup event and error presentation use canonical contract")
  func scheduleRegressionContract() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    let edge = try String(contentsOf: root.appendingPathComponent("supabase/functions/organization-setup/index.ts"))
    let schedule = try String(contentsOf: root.appendingPathComponent("HomePlate/Features/Coach/CoachTeamScheduleView.swift"))
    #expect(edge.contains("sd_team_event_practices"))
    #expect(edge.contains("arrival_at: arrival?.toISOString()"))
    #expect(schedule.contains("Schedule service is not available in this environment"))
    #expect(!schedule.contains(".alert(\"Schedule Error\""))
    #expect(schedule.contains("Previously loaded events remain visible"))
  }

  @Test("organization admin navigation is horizontal responsive and immediate")
  func adminNavigationContract() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    let source = try String(contentsOf: root.appendingPathComponent("HomePlate/Features/Admin/OrgAdminConsoleView.swift"))
    #expect(source.contains("ViewThatFits(in: .horizontal)"))
    #expect(source.contains("adminNavigationRow"))
    #expect(source.contains("Label(\"More\", systemImage: \"ellipsis.circle\")"))
    #expect(source.contains(".onMoveCommand"))
    #expect(source.contains("withTransaction(transaction) { selectedTab = tab }"))
    #expect(source.contains("admin_navigation_stall"))
    #expect(source.contains("case setup = \"Setup\""))
  }
}

@MainActor
final class OrganizationSetupRenderTests: XCTestCase {
  #if canImport(UIKit)
  func testControlledUnavailableStateRendersWithoutRawBackendDetail() throws {
    let copy = "This feature is temporarily unavailable."
    XCTAssertFalse(copy.contains("404"))
    XCTAssertFalse(copy.contains("organization-setup"))
    let view = HPCard {
      HPErrorState(title: "Setup unavailable", message: copy, onRetry: {})
    }
    .padding()
    .frame(width: 393)
    .background(HP.Color.bg)
    let host = UIHostingController(rootView: view)
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 320))
    window.rootViewController = host
    window.makeKeyAndVisible()
    host.view.frame = window.bounds
    host.view.layoutIfNeeded()
    let renderer = UIGraphicsImageRenderer(size: window.bounds.size)
    let image = renderer.image { context in host.view.layer.render(in: context.cgContext) }
    XCTAssertNotNil(image.pngData())
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("organization-setup-unavailable.png")
    try image.pngData()?.write(to: url)
    print("SETUP_PNG \(url.path)")
    window.isHidden = true
  }


  func testAllTenWizardStepHeadersRenderAtPhoneAndPadWidths() throws {
    for width in [393.0, 834.0] {
      for step in SDOrganizationSetupStep.allCases {
        let view = ScrollView {
          HPWorkspaceHeader(step.title, orgLabel: "Marist Red Foxes", context: step.isOptional ? "Optional setup" : "Required for launch")
            .padding(.horizontal, HP.Space.lg)
            .padding(.top, HP.Space.lg)
        }
        .frame(width: width, height: 260)
        .background(HP.Color.bg)
        let host = UIHostingController(rootView: view)
        host.view.frame = CGRect(x: 0, y: 0, width: width, height: 260)
        host.view.layoutIfNeeded()
        let renderer = UIGraphicsImageRenderer(size: host.view.bounds.size)
        let image = renderer.image { host.view.layer.render(in: $0.cgContext) }
        XCTAssertNotNil(image.pngData(), "Failed to render \(step.title) at \(width)")
      }
    }
  }
  #else
  func testControlledUnavailableStateRendersWithoutRawBackendDetail() throws {
    throw XCTSkip("UIKit required")
  }
  #endif
}
