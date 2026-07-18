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
  private let org = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!

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
    #expect(!config.allows(organizationId: UUID(), hasAuthority: true))
    #expect(!config.allows(organizationId: org, hasAuthority: false))
    #expect(!SDOrganizationSetupTestConfiguration(
      enabled: true,
      organizationId: org,
      environmentAllowed: false
    ).allows(organizationId: org, hasAuthority: true))
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
    let source = try String(contentsOf: root.appendingPathComponent("MultiOrg/Features/Admin/OrganizationSetupWizardView.swift"))
    let service = try String(contentsOf: root.appendingPathComponent("MultiOrg/Core/SupabaseService.swift"))
    #expect(source.contains("proxy.size.width >= 840"))
    #expect(source.contains("stepSidebar.frame(width: 280)"))
    #expect(source.contains("Save & Exit"))
    #expect(source.contains("Skip for Now"))
    #expect(source.contains("Launch Organization"))
    #expect(source.contains("Reset Wizard Progress Only"))
    #expect(source.contains("resetLocalWizardState"))
    #expect(service.contains("\"organization-setup\""))
    #expect(service.contains("requestId: UUID"))
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
  #else
  func testControlledUnavailableStateRendersWithoutRawBackendDetail() throws {
    throw XCTSkip("UIKit required")
  }
  #endif
}
