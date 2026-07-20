import XCTest
import SwiftUI
@testable import HomePlate

#if canImport(UIKit)
import UIKit

@MainActor
final class UniversalUIFoundationTests: XCTestCase {
  func testSemanticColorsResolveInLightMode() {
    let page = resolvedRGBA(DHDTheme.pageBackground, style: .light)
    let surface = resolvedRGBA(DHDTheme.cardBackground, style: .light)
    let text = resolvedRGBA(DHDTheme.textPrimary, style: .light)

    XCTAssertNotEqual(page, surface)
    XCTAssertNotEqual(page, text)
    XCTAssertGreaterThan(text.alpha, 0.99)
  }

  func testSemanticColorsResolveInDarkMode() {
    let page = resolvedRGBA(DHDTheme.pageBackground, style: .dark)
    let surface = resolvedRGBA(DHDTheme.cardBackground, style: .dark)
    let text = resolvedRGBA(DHDTheme.textPrimary, style: .dark)

    XCTAssertNotEqual(page, surface)
    XCTAssertNotEqual(page, text)
    XCTAssertGreaterThan(text.alpha, 0.99)
  }

  func testCoreTextContrastMeetsWCAGAA() {
    for appearance in DHDTheme.Appearance.allCases {
      assertContrast(.text, .pageBackground, appearance: appearance, minimum: 4.5)
      assertContrast(.text, .surface, appearance: appearance, minimum: 4.5)
      assertContrast(.textMuted, .pageBackground, appearance: appearance, minimum: 4.5)
      assertContrast(.accentText, .accent, appearance: appearance, minimum: 4.5)
    }
  }

  func testDarkCompatibilityPaletteMatchesApprovedHomePlateTokens() {
    XCTAssertEqual(DHDTheme.components(for: .pageBackground, appearance: .dark), .init(hex: 0x0F110C))
    XCTAssertEqual(DHDTheme.components(for: .surface, appearance: .dark), .init(hex: 0x1A1E16))
    XCTAssertEqual(DHDTheme.components(for: .text, appearance: .dark), .init(hex: 0xECE8DD))
    XCTAssertEqual(DHDTheme.components(for: .primary, appearance: .dark), .init(hex: 0x2E7D57))
    XCTAssertEqual(DHDTheme.components(for: .accent, appearance: .dark), .init(hex: 0xD6B370))
  }

  func testCardPreservesChildHitTesting() {
    var actions = 0
    let root = DHDCard {
      UIKitActionProbe(title: "Card action") { actions += 1 }
        .frame(width: 180, height: 52)
    }
    let hosted = host(root, size: CGSize(width: 260, height: 120))
    guard let button = firstSubview(of: UIButton.self, in: hosted.controller.view) else {
      return XCTFail("Expected UIKit action probe")
    }

    let center = button.convert(
      CGPoint(x: button.bounds.midX, y: button.bounds.midY),
      to: hosted.controller.view
    )
    let hit = hosted.controller.view.hitTest(center, with: nil)
    XCTAssertTrue(hit === button || hit?.isDescendant(of: button) == true)
    button.sendActions(for: .touchUpInside)
    XCTAssertEqual(actions, 1)
    withExtendedLifetime(hosted.window) {}
  }

  func testDecorativeHeaderOverlayDoesNotInterceptTaps() {
    var actions = 0
    let root = DHDHeaderCard {
      UIKitActionProbe(title: "Header action") { actions += 1 }
        .frame(width: 180, height: 52)
    }
    let hosted = host(root, size: CGSize(width: 260, height: 120))
    guard let button = firstSubview(of: UIButton.self, in: hosted.controller.view) else {
      return XCTFail("Expected UIKit action probe")
    }

    button.sendActions(for: .touchUpInside)
    XCTAssertEqual(actions, 1)
    withExtendedLifetime(hosted.window) {}
  }

  func testButtonCallbackPassesThroughExactlyOnce() {
    var actions = 0
    XCTAssertTrue(DHDActionGate.perform(isEnabled: true, isLoading: false) { actions += 1 })
    XCTAssertEqual(actions, 1)
  }

  func testDisabledButtonBlocksCallback() {
    var actions = 0
    XCTAssertFalse(DHDActionGate.perform(isEnabled: false, isLoading: false) { actions += 1 })
    XCTAssertEqual(actions, 0)
  }

  func testLoadingButtonBlocksDuplicateCallback() {
    var actions = 0
    XCTAssertFalse(DHDActionGate.perform(isEnabled: true, isLoading: true) { actions += 1 })
    XCTAssertFalse(DHDActionGate.perform(isEnabled: true, isLoading: true) { actions += 1 })
    XCTAssertEqual(actions, 0)
  }

  func testAccessibilityDynamicTypeProducesFiniteCriticalLayout() {
    let view = LayerAFoundationGallery(width: 393)
      .environment(\.dynamicTypeSize, .accessibility3)
      .frame(width: 393)
    let controller = UIHostingController(rootView: view)
    let size = controller.sizeThatFits(
      in: CGSize(width: 393, height: CGFloat.greatestFiniteMagnitude)
    )

    XCTAssertEqual(size.width, 393, accuracy: 1)
    XCTAssertGreaterThan(size.height, 1_000)
    XCTAssertLessThan(size.height, 10_000)
    XCTAssertTrue(size.height.isFinite)
  }

  func testBadgeSemanticKindsRemainDistinct() {
    let kinds: [DHDStatusKind] = [.role, .informational, .success, .warning, .danger]
    let resolved = kinds.map { resolvedRGBA($0.color, style: .light) }
    XCTAssertEqual(Set(resolved).count, kinds.count)
    XCTAssertEqual(Set(kinds.map(\.accessibilityDescription)).count, kinds.count)
  }

  func testStateActionCallbackRemainsIntact() {
    var actions = 0
    let empty = DHDStateView(
      kind: .empty,
      title: "No sessions",
      actionTitle: "Create session",
      action: { actions += 1 }
    )
    empty.action?()
    XCTAssertEqual(actions, 1)

    let loading = DHDStateView(kind: .loading, title: "Loading")
    XCTAssertNil(loading.action)
  }

  func testCalendarSelectionPresentationMirrorsInput() {
    let selected = calendarCell(isSelected: true)
    XCTAssertTrue(selected.presentation.isSelected)
    XCTAssertFalse(calendarCell(isSelected: false).presentation.isSelected)
  }

  func testCalendarTodayStylingDoesNotChangeSelection() {
    let cell = calendarCell(isToday: true, isSelected: false)
    XCTAssertTrue(cell.presentation.isToday)
    XCTAssertFalse(cell.presentation.isSelected)
  }

  func testCalendarOutsideMonthRetainsDisabledPresentation() {
    XCTAssertTrue(calendarCell(isInMonth: false).presentation.isDisabled)
    XCTAssertFalse(calendarCell(isInMonth: true).presentation.isDisabled)
  }

  func testCalendarEventIndicatorsPreserveInputFlags() {
    let cell = calendarCell(showGreen: true, showBlue: false, showRed: true)
    XCTAssertTrue(cell.presentation.events.contains(.scheduledLift))
    XCTAssertFalse(cell.presentation.events.contains(.practice))
    XCTAssertTrue(cell.presentation.events.contains(.game))
  }

  func testCalendarNavigationCallbacksPassThrough() {
    var previous = 0
    var next = 0
    let header = DHDCalendarMonthHeader(
      title: "July 2026",
      onPrevious: { previous += 1 },
      onNext: { next += 1 }
    )
    header.onPrevious()
    header.onNext()
    XCTAssertEqual(previous, 1)
    XCTAssertEqual(next, 1)
  }

  func testLegacySharedComponentInitializersRemainSourceCompatible() {
    _ = DHDCard { Text("Legacy card") }
    _ = DHDCard(style: .flat) { Text("Legacy flat card") }
    _ = DHDHeaderCard { Text("Legacy header") }
    _ = DHDStatusPill(text: "Active", color: .green)
    _ = DHDStatusBadge(text: "Verified", color: .blue)
    _ = DHDSectionHeader("Section")
    _ = DHDFormRow("Label") { Text("Value") }
    _ = DHDToast(text: "Saved")
  }

  func testRenderIPhoneLightEvidence() throws {
    try renderEvidence(name: "iphone-light", width: 393, dynamicType: .large, style: .light)
  }

  func testRenderIPhoneDarkEvidence() throws {
    try renderEvidence(name: "iphone-dark", width: 393, dynamicType: .large, style: .dark)
  }

  func testRenderIPhoneAccessibilityEvidence() throws {
    try renderEvidence(
      name: "iphone-accessibility-dark",
      width: 393,
      dynamicType: .accessibility3,
      style: .dark
    )
  }

  func testRenderIPadEvidence() throws {
    try renderEvidence(name: "ipad-dark", width: 834, dynamicType: .large, style: .dark)
  }

  func testRenderMacOSWidthEvidence() throws {
    try renderEvidence(name: "macos-width-light", width: 1_200, dynamicType: .large, style: .light)
  }

  private func calendarCell(
    isInMonth: Bool = true,
    isToday: Bool = false,
    isSelected: Bool = false,
    showGreen: Bool = false,
    showBlue: Bool = false,
    showRed: Bool = false
  ) -> DHDCalendarDayCellView {
    DHDCalendarDayCellView(
      date: Date(timeIntervalSince1970: 1_784_131_200),
      isInMonth: isInMonth,
      isToday: isToday,
      isSelected: isSelected,
      showGreen: showGreen,
      showBlue: showBlue,
      showRed: showRed,
      cellSize: CGSize(width: 52, height: 52)
    )
  }

  private func assertContrast(
    _ foreground: DHDTheme.SemanticRole,
    _ background: DHDTheme.SemanticRole,
    appearance: DHDTheme.Appearance,
    minimum: Double,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    let ratio = contrastRatio(
      DHDTheme.components(for: foreground, appearance: appearance),
      DHDTheme.components(for: background, appearance: appearance)
    )
    XCTAssertGreaterThanOrEqual(
      ratio,
      minimum,
      "\(foreground) on \(background) in \(appearance) was \(ratio)",
      file: file,
      line: line
    )
  }

  private func contrastRatio(_ first: DHDTheme.RGBA, _ second: DHDTheme.RGBA) -> Double {
    let firstLuminance = relativeLuminance(first)
    let secondLuminance = relativeLuminance(second)
    return (max(firstLuminance, secondLuminance) + 0.05)
      / (min(firstLuminance, secondLuminance) + 0.05)
  }

  private func relativeLuminance(_ color: DHDTheme.RGBA) -> Double {
    func linear(_ component: Double) -> Double {
      component <= 0.03928
        ? component / 12.92
        : pow((component + 0.055) / 1.055, 2.4)
    }
    return 0.2126 * linear(color.red)
      + 0.7152 * linear(color.green)
      + 0.0722 * linear(color.blue)
  }

  private func resolvedRGBA(_ color: Color, style: UIUserInterfaceStyle) -> ResolvedRGBA {
    let trait = UITraitCollection(userInterfaceStyle: style)
    let resolved = UIColor(color).resolvedColor(with: trait)
    var red: CGFloat = 0
    var green: CGFloat = 0
    var blue: CGFloat = 0
    var alpha: CGFloat = 0
    resolved.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
    return ResolvedRGBA(red: red, green: green, blue: blue, alpha: alpha)
  }

  private func host<V: View>(
    _ view: V,
    size: CGSize
  ) -> (window: UIWindow, controller: UIHostingController<V>) {
    let controller = UIHostingController(rootView: view)
    let window = UIWindow(frame: CGRect(origin: .zero, size: size))
    window.rootViewController = controller
    window.makeKeyAndVisible()
    controller.view.frame = window.bounds
    controller.view.layoutIfNeeded()
    RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    return (window, controller)
  }

  private func firstSubview<T: UIView>(of type: T.Type, in view: UIView) -> T? {
    if let match = view as? T { return match }
    for child in view.subviews {
      if let match = firstSubview(of: type, in: child) { return match }
    }
    return nil
  }

  private func renderEvidence(
    name: String,
    width: CGFloat,
    dynamicType: DynamicTypeSize,
    style: UIUserInterfaceStyle
  ) throws {
    let colorScheme: ColorScheme = style == .dark ? .dark : .light
    let root = LayerAFoundationGallery(width: width)
      .environment(\.dynamicTypeSize, dynamicType)
      .environment(\.colorScheme, colorScheme)
      .frame(width: width)
    let controller = UIHostingController(rootView: root)
    controller.overrideUserInterfaceStyle = style
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: 1_400))
    window.overrideUserInterfaceStyle = style
    window.rootViewController = controller
    window.makeKeyAndVisible()
    controller.view.layoutIfNeeded()
    RunLoop.current.run(until: Date().addingTimeInterval(0.1))

    let fitted = controller.sizeThatFits(
      in: CGSize(width: width, height: CGFloat.greatestFiniteMagnitude)
    )
    let height = ceil(fitted.height)
    XCTAssertGreaterThan(height, 1_000)
    XCTAssertLessThan(height, 10_000)
    window.frame = CGRect(x: 0, y: 0, width: width, height: height)
    controller.view.frame = window.bounds
    controller.view.layoutIfNeeded()
    RunLoop.current.run(until: Date().addingTimeInterval(0.1))

    let format = UIGraphicsImageRendererFormat()
    format.scale = width > 500 || dynamicType.isAccessibilitySize ? 1 : 2
    let renderer = UIGraphicsImageRenderer(
      size: CGSize(width: width, height: height),
      format: format
    )
    let image = renderer.image { context in
      controller.view.layer.render(in: context.cgContext)
    }
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("layer-a-\(name).png")
    try XCTUnwrap(image.pngData()).write(to: url, options: .atomic)
    print("LAYER_A_PNG \(url.path) size=\(Int(width))x\(Int(height))")

    window.isHidden = true
    window.rootViewController = nil
  }
}

private struct ResolvedRGBA: Hashable {
  let red: CGFloat
  let green: CGFloat
  let blue: CGFloat
  let alpha: CGFloat
}

private struct UIKitActionProbe: UIViewRepresentable {
  let title: String
  let action: () -> Void

  func makeUIView(context: Context) -> UIButton {
    let button = UIButton(type: .system)
    button.setTitle(title, for: .normal)
    button.addAction(UIAction { _ in action() }, for: .touchUpInside)
    return button
  }

  func updateUIView(_ uiView: UIButton, context: Context) {}
}

private struct LayerAFoundationGallery: View {
  let width: CGFloat

  @State private var playerName = "Owen Pincince"
  @State private var search = "bullpen"
  @State private var invalidEmail = "coach@"

  var body: some View {
    let contentWidth = max(width - HP.Space.md * 2, 1)
    VStack(alignment: .leading, spacing: HP.Space.lg) {
      Text("HOME PLATE — UNIVERSAL FOUNDATION")
        .font(HP.Font.eyebrow)
        .tracking(HP.Font.eyebrowTracking)
        .foregroundStyle(DHDTheme.accent)

      DHDHeaderCard {
        VStack(alignment: .leading, spacing: HP.Space.xs) {
          Text("Player Development")
            .font(HP.Font.title)
            .fixedSize(horizontal: false, vertical: true)
          Text("Shared identity chrome stays separate from semantic control colors.")
            .font(HP.Font.body)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }

      section("Universal card") {
        DHDCard {
          VStack(alignment: .leading, spacing: HP.Space.sm) {
            Text("Weekly throwing load")
              .font(HP.Font.headline)
            Text("148")
              .font(HP.Font.number(.largeTitle))
              .foregroundStyle(DHDTheme.accent)
            Text("Metric values, labels, borders, and surfaces use shared semantic roles.")
              .font(HP.Font.body)
              .foregroundStyle(DHDTheme.textSecondary)
              .fixedSize(horizontal: false, vertical: true)
          }
          .frame(maxWidth: .infinity, alignment: .leading)
        }
      }

      section("Button states") {
        VStack(alignment: .leading, spacing: HP.Space.sm) {
          DHDButton("Primary action", systemImage: "checkmark", action: {})
          DHDButton("Secondary action", variant: .secondary, action: {})
          DHDButton("Destructive action", variant: .destructive, action: {})
          DHDButton("Compact action", variant: .compactAction, size: .compact, action: {})
          DHDButton("Disabled action", isEnabled: false, action: {})
          DHDButton("Loading action", isLoading: true, action: {})
          DHDButton("More actions", systemImage: "ellipsis", variant: .icon, action: {})
        }
      }

      section("Input states") {
        VStack(alignment: .leading, spacing: HP.Space.md) {
          DHDTextInput(
            label: "Player name",
            text: $playerName,
            prompt: "Enter a player",
            helper: "Matches the active organization roster."
          )
          DHDTextInput(
            label: "Search",
            text: $search,
            prompt: "Search reports",
            kind: .search
          )
          DHDTextInput(
            label: "Coach email",
            text: $invalidEmail,
            error: "Enter a complete email address."
          )
          DHDTextInput(
            label: "Disabled field",
            text: .constant("Read only"),
            isEnabled: false
          )
        }
      }

      section("Status badges") {
        VStack(alignment: .leading, spacing: HP.Space.xs) {
          badgeRow(.role, "Owner", .informational, "Provider")
          badgeRow(.success, "Verified", .warning, "Needs review")
          badgeRow(.danger, "Rejected", .neutral, "Draft")
        }
      }

      section("Empty, loading, and error") {
        VStack(spacing: HP.Space.md) {
          DHDLoadingState(title: "Loading observations", message: "Preparing player evidence.")
          DHDEmptyState(
            title: "No observations yet",
            message: "Import a provider file or record a development session.",
            actionTitle: "Add observation",
            action: {}
          )
          DHDErrorState(
            title: "Report unavailable",
            message: "The report could not be loaded. Existing data was not changed.",
            retry: {}
          )
        }
      }

      section("Calendar month grid") {
        LayerACalendarPreview(availableWidth: min(max(width - 64, 280), 760))
      }
    }
    .frame(width: contentWidth, alignment: .leading)
    .padding(HP.Space.md)
    .frame(width: width, alignment: .leading)
    .background(DHDTheme.pageBackground)
    .foregroundStyle(DHDTheme.textPrimary)
  }

  @ViewBuilder
  private func section<Content: View>(
    _ title: String,
    @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: HP.Space.sm) {
      DHDSectionHeader(title)
      content()
    }
    .frame(width: min(max(width - HP.Space.md * 2, 1), 760), alignment: .leading)
  }

  private func badgeRow(
    _ firstKind: DHDStatusKind,
    _ firstText: String,
    _ secondKind: DHDStatusKind,
    _ secondText: String
  ) -> some View {
    ViewThatFits(in: .horizontal) {
      HStack(spacing: HP.Space.xs) {
        DHDStatusBadge(text: firstText, kind: firstKind)
        DHDStatusBadge(text: secondText, kind: secondKind)
      }
      VStack(alignment: .leading, spacing: HP.Space.xs) {
        DHDStatusBadge(text: firstText, kind: firstKind)
        DHDStatusBadge(text: secondText, kind: secondKind)
      }
    }
  }
}

private struct LayerACalendarPreview: View {
  private struct GridIndex: Identifiable {
    let id: String
    let value: Int
  }

  let availableWidth: CGFloat

  var body: some View {
    let spacing: CGFloat = 4
    let cellWidth = (availableWidth - spacing * 6) / 7
    let cellSize = CGSize(width: cellWidth, height: max(52, cellWidth * 0.78))
    let columns = Array(repeating: GridItem(.fixed(cellWidth), spacing: spacing), count: 7)
    let start = Date(timeIntervalSince1970: 1_783_036_800)
    let weekdayIndices = (0..<7).map { GridIndex(id: "weekday-\($0)", value: $0) }
    let dayOffsets = (0..<14).map { GridIndex(id: "day-\($0)", value: $0) }

    VStack(spacing: HP.Space.sm) {
      DHDCalendarMonthHeader(title: "July 2026", onPrevious: {}, onNext: {})
      LazyVGrid(columns: columns, spacing: spacing) {
        ForEach(weekdayIndices) { item in
          let index = item.value
          Text(["S", "M", "T", "W", "T", "F", "S"][index])
            .font(HP.Font.caption)
            .foregroundStyle(DHDTheme.textSecondary)
            .frame(width: cellWidth)
        }
        ForEach(dayOffsets) { item in
          let offset = item.value
          let date = DateUtils.calendarET.date(byAdding: .day, value: offset, to: start) ?? start
          DHDCalendarDayCellView(
            date: date,
            isInMonth: offset > 1,
            isToday: offset == 8,
            isSelected: offset == 9,
            showGreen: offset == 4 || offset == 9,
            showBlue: offset == 6,
            showRed: offset == 11,
            cellSize: cellSize
          )
        }
      }
    }
    .frame(width: availableWidth)
  }
}
#endif
