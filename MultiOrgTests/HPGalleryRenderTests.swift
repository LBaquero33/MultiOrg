import XCTest
import SwiftUI
@testable import MultiOrg
#if canImport(UIKit)
import UIKit
#endif

/// EVIDENCE-ONLY render harness. Renders the preview-only `HPComponentGallery`
/// on the iOS simulator runtime at iPhone (393 pt), iPad (834 pt), and macOS
/// (1200 pt) widths, at normal and Dynamic Type accessibility sizes, and slices
/// each into ordinary **device-viewport windows** (offset + clipped).
///
/// Per-viewport rendering keeps every render target small, which avoids the
/// CoreGraphics canvas-size limit that blanks a single very tall image. Touches
/// no production screen and exercises no app logic. Safe to delete.
@MainActor
final class HPGalleryRenderTests: XCTestCase {

  #if canImport(UIKit)
  private let scale: CGFloat = 2

  func testRenderGalleryViewports() throws {
    let dir = FileManager.default.temporaryDirectory
    struct Spec { let name: String; let width: CGFloat; let dts: DynamicTypeSize; let viewportH: CGFloat }
    let specs: [Spec] = [
      Spec(name: "iphone-normal", width: 393,  dts: .large,          viewportH: 852),
      Spec(name: "iphone-xl",     width: 393,  dts: .accessibility3, viewportH: 852),
      Spec(name: "ipad",          width: 834,  dts: .large,          viewportH: 1024),
      Spec(name: "macos",         width: 1200, dts: .large,          viewportH: 800),
    ]

    for spec in specs {
      let gallery = HPComponentGallery()
        .environment(\.dynamicTypeSize, spec.dts)
        .frame(width: spec.width)

      let host = UIHostingController(rootView: gallery)
      let total = host.sizeThatFits(in: CGSize(width: spec.width, height: .greatestFiniteMagnitude)).height
      let slices = max(1, Int(ceil(total / spec.viewportH)))

      for i in 0..<slices {
        let window = gallery
          .offset(y: -CGFloat(i) * spec.viewportH)
          .frame(width: spec.width, height: spec.viewportH, alignment: .topLeading)
          .clipped()
          .background(HP.Color.bg)

        let renderer = ImageRenderer(content: window)
        renderer.scale = scale
        renderer.isOpaque = true
        guard let cg = renderer.cgImage else {
          XCTFail("Failed to render \(spec.name) viewport \(i)")
          continue
        }
        XCTAssertEqual(cg.width, Int(spec.width * scale), "\(spec.name)-\(i) wrong width")
        writePNG(cg, dir.appendingPathComponent("hp-vp-\(spec.name)-\(i).png"))
      }
      print("HP_VIEWPORTS \(spec.name) totalPt=\(Int(total)) slices=\(slices)")
    }
  }

  private func writePNG(_ cg: CGImage, _ url: URL) {
    guard let data = UIImage(cgImage: cg).pngData() else { return }
    try? data.write(to: url)
    print("HP_GALLERY_PNG \(url.path)")
  }
  #else
  func testRenderGalleryViewports() throws {
    throw XCTSkip("UIKit required for PNG rendering")
  }
  #endif
}
