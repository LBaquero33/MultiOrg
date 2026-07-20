import XCTest
import SwiftUI
@testable import HomePlate
#if canImport(UIKit)
import UIKit
#endif

/// EVIDENCE-ONLY, TEST-ONLY live-control capture. Unlike `ImageRenderer`, this
/// hosts the views in a real `UIWindow` and snapshots via
/// `drawHierarchy(afterScreenUpdates:)`, which renders live `TextField` /
/// `SecureField` / `ProgressView` (native spinner) correctly. It focuses a
/// field so the gold focus ring appears. Not connected to production navigation;
/// safe to delete.
@MainActor
final class HPLiveControlsRenderTests: XCTestCase {
  #if canImport(UIKit)
  func testRenderLiveControls() throws {
    let width: CGFloat = 393
    let root = HPLiveControls().frame(width: width).background(HP.Color.bg)
    let host = UIHostingController(rootView: root)
    host.overrideUserInterfaceStyle = .dark

    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: 1400))
    window.overrideUserInterfaceStyle = .dark
    window.rootViewController = host
    window.makeKeyAndVisible()
    host.view.layoutIfNeeded()
    spin(0.3)

    // Focus the second text field so the gold focus ring is captured.
    let fields = textFields(in: host.view)
    if fields.count > 1 { fields[1].becomeFirstResponder() } else { fields.first?.becomeFirstResponder() }
    spin(0.5)

    // Size to content and capture the live hierarchy.
    let fitted = host.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude))
    window.frame = CGRect(x: 0, y: 0, width: width, height: ceil(fitted.height))
    host.view.frame = window.bounds
    host.view.layoutIfNeeded()
    spin(0.3)

    let renderer = UIGraphicsImageRenderer(size: host.view.bounds.size)
    let image = renderer.image { _ in
      _ = host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
    }
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("hp-live-controls.png")
    try image.pngData()?.write(to: url)
    print("HP_LIVE_PNG \(url.path) size=\(Int(host.view.bounds.width))x\(Int(host.view.bounds.height))")
    XCTAssertGreaterThan(host.view.bounds.height, 200)
  }

  /// Clean AX3 capture of the corrected nav/modal items (no gallery tiling).
  func testRenderAX3NavModal() throws {
    let width: CGFloat = 393
    let root = HPAX3NavModal().frame(width: width).background(HP.Color.bg)
    let host = UIHostingController(rootView: root)
    host.overrideUserInterfaceStyle = .dark
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: 2000))
    window.overrideUserInterfaceStyle = .dark
    window.rootViewController = host
    window.makeKeyAndVisible()
    host.view.layoutIfNeeded()
    spin(0.3)
    let fitted = host.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude))
    window.frame = CGRect(x: 0, y: 0, width: width, height: ceil(fitted.height))
    host.view.frame = window.bounds
    host.view.layoutIfNeeded()
    spin(0.3)
    // These items contain no editable text controls, so the layer tree
    // rasterizes fully (including content beyond the screen), unlike
    // drawHierarchy(afterScreenUpdates:) which blanks off-screen regions.
    let renderer = UIGraphicsImageRenderer(size: host.view.bounds.size)
    let image = renderer.image { ctx in
      host.view.layer.render(in: ctx.cgContext)
    }
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("hp-ax3-navmodal.png")
    try image.pngData()?.write(to: url)
    print("HP_AX3_PNG \(url.path) size=\(Int(host.view.bounds.width))x\(Int(host.view.bounds.height))")
  }

  private func spin(_ seconds: TimeInterval) {
    RunLoop.current.run(until: Date().addingTimeInterval(seconds))
  }

  private func textFields(in view: UIView) -> [UITextField] {
    var result: [UITextField] = []
    if let tf = view as? UITextField { result.append(tf) }
    for sub in view.subviews { result.append(contentsOf: textFields(in: sub)) }
    return result
  }
  #endif
}

#if canImport(UIKit)
/// Test-only host view exercising the live controls.
private struct HPLiveControls: View {
  @State private var name = "Jose Alvarez"
  @State private var emailFocused = "jose@example"
  @State private var emailError = "not-an-email"
  @State private var password = "topsecret"
  @State private var notes = "Read only"
  @State private var cents = 14900

  var body: some View {
    VStack(alignment: .leading, spacing: HP.Space.md) {
      Text("LIVE CONTROLS — drawHierarchy capture")
        .font(HP.Font.eyebrow).tracking(HP.Font.eyebrowTracking)
        .foregroundStyle(HP.Color.accent)

      HPFormField(label: "Full name (normal)", text: $name, placeholder: "Player name", helper: "As it appears on the roster.")
      HPFormField(label: "Email (focused — gold ring)", text: $emailFocused, placeholder: "name@example.com")
      HPFormField(label: "Email (validation error)", text: $emailError, error: "Enter a valid email address.")
      HPFormField(label: "Password (secure)", text: $password, kind: .secure)
      HPFormField(label: "Notes (disabled)", text: $notes, isEnabled: false)
      HPMoneyField(label: "Payment amount (editable)", cents: $cents, helper: "Stored as integer cents.")

      Text("PROGRESS").font(HP.Font.eyebrow).tracking(HP.Font.eyebrowTracking).foregroundStyle(HP.Color.accent)
      HStack(spacing: HP.Space.lg) {
        VStack(spacing: 4) { HPProgressIndicator(value: 0.72, style: .ring).frame(width: 56, height: 56); Text("Determinate").font(HP.Font.caption).foregroundStyle(HP.Color.textMuted) }
        VStack(spacing: 4) { HPProgressIndicator(style: .ring).frame(width: 56, height: 56); Text("Indeterminate").font(HP.Font.caption).foregroundStyle(HP.Color.textMuted) }
        VStack(spacing: 4) { HPProgressIndicator(style: .spinner).frame(height: 56); Text("Native spinner").font(HP.Font.caption).foregroundStyle(HP.Color.textMuted) }
      }
      HPProgressIndicator(value: 0.4, style: .bar).frame(maxWidth: 220)
    }
    .padding(HP.Space.lg)
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

/// Test-only host for the corrected AX3 nav/modal items, forced to AX3.
private struct HPAX3NavModal: View {
  @State private var role: HPRole = .owner
  @State private var selection: UUID? = nil
  var body: some View {
    VStack(alignment: .leading, spacing: HP.Space.lg) {
      label("Confirmation modal")
      HPConfirmationDialog(title: "Cancel request?",
                           message: "This cancels the payment request. This cannot be undone.",
                           confirmTitle: "Cancel request", destructive: true)
      label("Role selector")
      HPSegmentedControl(options: HPRole.allCases.map { ($0, $0.rawValue) }, selection: $role)
      label("Sidebar rows")
      HPSidebar(orgIdentity: HPSample.orgIdentity, role: .owner,
                groups: HPSample.navGroups(for: .owner), selection: $selection)
        .frame(height: 560)
        .clipShape(RoundedRectangle(cornerRadius: HP.Radius.lg, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: HP.Radius.lg, style: .continuous).strokeBorder(HP.Color.border, lineWidth: 1))
      label("Workspace directory")
      HPWorkspaceDirectory(groups: HPSample.navGroups(for: .owner))
    }
    .padding(HP.Space.lg)
    .frame(maxWidth: .infinity, alignment: .leading)
    .environment(\.dynamicTypeSize, .accessibility3)
  }
  private func label(_ text: String) -> some View {
    Text(text.uppercased()).font(HP.Font.eyebrow).tracking(HP.Font.eyebrowTracking).foregroundStyle(HP.Color.accent)
  }
}
#endif
