import XCTest
import SwiftUI
@testable import MultiOrg
#if canImport(UIKit)
import UIKit
#endif

/// EVIDENCE-ONLY, TEST-ONLY render harness for the **Universal Screen Templates**.
///
/// Produces one canonical rendered example of every `HPScreenTemplateID` at
/// iPhone, iPhone AX3, iPad, and macOS-width. These renders are the visual
/// reference future AI agents must match (see
/// `Docs/design/HOME_PLATE_VISUAL_REFERENCE.md`).
///
/// Preview-only: approved HP components + local sample data, no network, no
/// `AppState`, not wired to production navigation. Safe to delete.
///
/// Split by viewport so each method stays well under the per-test timeout, and
/// renders are wrapped in `autoreleasepool` with the window torn down (these
/// harnesses are memory-heavy).
@MainActor
final class HPTemplateRenderTests: XCTestCase {
  #if canImport(UIKit)

  func testRenderTemplatesIPhoneLight() throws {
    try renderAll(name: "iphone-light", width: 393, dts: .large, isWide: false, style: .light)
  }

  func testRenderTemplatesIPhoneDark() throws {
    try renderAll(name: "iphone-dark", width: 393, dts: .large, isWide: false, style: .dark)
  }

  func testRenderTemplatesIPhoneAX3() throws {
    try renderAll(name: "iphone-ax3-dark", width: 393, dts: .accessibility3, isWide: false, style: .dark)
  }

  func testRenderTemplatesIPadLight() throws {
    try renderAll(name: "ipad-light", width: 834, dts: .large, isWide: true, style: .light)
  }

  func testRenderTemplatesIPadDark() throws {
    try renderAll(name: "ipad-dark", width: 834, dts: .large, isWide: true, style: .dark)
  }

  func testRenderTemplatesMacLight() throws {
    try renderAll(name: "macos-light", width: 1200, dts: .large, isWide: true, style: .light)
  }

  func testRenderTemplatesMacDark() throws {
    try renderAll(name: "macos-dark", width: 1200, dts: .large, isWide: true, style: .dark)
  }

  /// Renders every template at one viewport. Asserts each canonical example
  /// produces real content (guards against an empty/blank template shell).
  private func renderAll(
    name: String,
    width: CGFloat,
    dts: DynamicTypeSize,
    isWide: Bool,
    style: UIUserInterfaceStyle
  ) throws {
    let dir = FileManager.default.temporaryDirectory
    let colorScheme: ColorScheme = style == .dark ? .dark : .light

    for template in HPScreenTemplateID.allCases {
      try autoreleasepool {
        let format = UIGraphicsImageRendererFormat()
        // Accessibility renders are very tall; 1x keeps us inside the budget.
        format.scale = dts.isAccessibilitySize ? 1 : 2

        let view = HPTemplateGallery(template: template, isWide: isWide)
          .environment(\.dynamicTypeSize, dts)
          .environment(\.colorScheme, colorScheme)
          .frame(width: width)
          .background(HP.Color.bg)
        let host = UIHostingController(rootView: view)
        host.overrideUserInterfaceStyle = style
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: 1_400))
        window.overrideUserInterfaceStyle = style
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.layoutIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.15))

        let fitted = host.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude))
        let height = ceil(fitted.height)
        XCTAssertGreaterThan(height, 120,
                             "Template \(template.rawValue) rendered no meaningful content at \(name)")
        window.frame = CGRect(x: 0, y: 0, width: width, height: height)
        host.view.frame = window.bounds
        host.view.layoutIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.15))

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format)
        var captured = false
        let image = renderer.image { context in
          captured = host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
          if !captured {
            // The simulator render server can reject the very tall AX analytics
            // chart snapshot. Preserve that deterministic evidence with a layer
            // fallback; every other capture must include live UIKit controls.
            host.view.layer.render(in: context.cgContext)
          }
        }
        let permitsChartFallback = template == .analytics && dts.isAccessibilitySize
        if !permitsChartFallback {
          XCTAssertTrue(captured, "Template \(template.rawValue) must render live controls at \(name)")
        }
        let url = dir.appendingPathComponent("tmpl-\(template.rawValue)-\(name).png")
        if let data = image.pngData() { try data.write(to: url) }
        print("TEMPLATE_PNG \(url.path) size=\(Int(width))x\(Int(height))")

        window.isHidden = true
        window.rootViewController = nil
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
      }
    }
  }
  #else
  func testRenderTemplatesIPhoneLight() throws { throw XCTSkip("UIKit required") }
  #endif
}
