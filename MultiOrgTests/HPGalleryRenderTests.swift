import XCTest
import SwiftUI
@testable import MultiOrg
#if canImport(UIKit)
import UIKit
#endif

/// EVIDENCE-ONLY render harness (Stage 3A). Renders the preview-only
/// `HPComponentGallery` on the iOS simulator runtime at a standard **393-pt**
/// iPhone width and captures ordinary **device-viewport windows** (393 × 852 pt)
/// for top / middle / bottom review — at normal and Dynamic Type accessibility
/// sizes.
///
/// Each viewport is rendered independently (offset + clipped to an 852-pt
/// window) so the render target stays small. This avoids the CoreGraphics
/// canvas-size limit that blanks a single very tall image at large Dynamic Type,
/// and it produces true viewport-sized screenshots rather than one long stitch.
///
/// Touches no production screen and exercises no app logic. Safe to delete.
@MainActor
final class HPGalleryRenderTests: XCTestCase {

  #if canImport(UIKit)
  private let width: CGFloat = 393     // standard iPhone logical width
  private let viewportH: CGFloat = 852 // iPhone logical viewport height
  private let scale: CGFloat = 2

  func testRenderGalleryViewports() throws {
    let dir = FileManager.default.temporaryDirectory
    let specs: [(name: String, dts: DynamicTypeSize)] = [
      ("normal", .large),
      ("xl", .accessibility3),
    ]

    for spec in specs {
      let gallery = HPComponentGallery()
        .environment(\.dynamicTypeSize, spec.dts)
        .frame(width: width)

      // Measure total content height at 393 pt so we know how many viewports.
      let host = UIHostingController(rootView: gallery)
      let total = host.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude)).height
      let slices = max(1, Int(ceil(total / viewportH)))

      for i in 0..<slices {
        let window = gallery
          .offset(y: -CGFloat(i) * viewportH)
          .frame(width: width, height: viewportH, alignment: .topLeading)
          .clipped()
          .background(HP.Color.bg)

        let renderer = ImageRenderer(content: window)
        renderer.scale = scale
        renderer.isOpaque = true
        guard let cg = renderer.cgImage else {
          XCTFail("Failed to render \(spec.name) viewport \(i)")
          continue
        }
        // Each viewport must be exactly 393 × 852 pt (× scale) — horizontal
        // overflow would clip/show at the 393-pt edge.
        XCTAssertEqual(cg.width, Int(width * scale), "\(spec.name)-\(i) not 393 pt wide")
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
