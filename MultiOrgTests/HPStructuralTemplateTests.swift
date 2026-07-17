import XCTest
import SwiftUI
@testable import MultiOrg

@MainActor
final class HPStructuralTemplateTests: XCTestCase {
  func testAutomaticWidthResolutionUsesHorizontalSizeClass() {
    let compact = HPScreenLayoutContext.resolve(
      widthMode: .automatic,
      horizontalSizeClass: .compact,
      dynamicTypeSize: .large
    )
    let regular = HPScreenLayoutContext.resolve(
      widthMode: .automatic,
      horizontalSizeClass: .regular,
      dynamicTypeSize: .large
    )
    let mac = HPScreenLayoutContext.resolve(
      widthMode: .automatic,
      horizontalSizeClass: nil,
      dynamicTypeSize: .large
    )

    XCTAssertFalse(compact.isRegularWidth)
    XCTAssertTrue(regular.isRegularWidth)
    XCTAssertTrue(mac.isRegularWidth)
  }

  func testExplicitWidthModesAreDeterministic() {
    let compact = HPScreenLayoutContext.resolve(
      widthMode: .compact,
      horizontalSizeClass: .regular,
      dynamicTypeSize: .large
    )
    let regular = HPScreenLayoutContext.resolve(
      widthMode: .regular,
      horizontalSizeClass: .compact,
      dynamicTypeSize: .large
    )
    let wide = HPScreenLayoutContext.resolve(
      widthMode: .wide,
      horizontalSizeClass: .compact,
      dynamicTypeSize: .large
    )

    XCTAssertFalse(compact.isRegularWidth)
    XCTAssertTrue(regular.isRegularWidth)
    XCTAssertTrue(wide.isWide)
  }

  func testAutomaticWidthResolutionUsesContractBreakpoints() {
    func context(_ width: CGFloat) -> HPScreenLayoutContext {
      .resolve(
        widthMode: .automatic,
        horizontalSizeClass: .regular,
        dynamicTypeSize: .large,
        containerWidth: width
      )
    }

    XCTAssertEqual(context(393).widthClass, .compact)
    XCTAssertEqual(context(834).widthClass, .regular)
    XCTAssertEqual(context(1_200).widthClass, .wide)
  }

  func testCompactAndAccessibilityTablesAlwaysStack() {
    let compact = HPScreenLayoutContext(
      isRegularWidth: false,
      isAccessibilitySize: false
    )
    let accessibility = HPScreenLayoutContext(
      isRegularWidth: true,
      isAccessibilitySize: true
    )
    let expanded = HPScreenLayoutContext(
      isRegularWidth: true,
      isAccessibilitySize: false
    )

    XCTAssertEqual(compact.tableLayout, .stacked)
    XCTAssertEqual(accessibility.tableLayout, .stacked)
    XCTAssertEqual(expanded.tableLayout, .columns)

    XCTAssertTrue(
      HPTableLayout.auto.resolvesStacked(
        isAccessibilitySize: false,
        isCompactWidth: true
      )
    )
    XCTAssertTrue(
      HPTableLayout.auto.resolvesStacked(
        isAccessibilitySize: true,
        isCompactWidth: false
      )
    )
    XCTAssertFalse(
      HPTableLayout.auto.resolvesStacked(
        isAccessibilitySize: false,
        isCompactWidth: false
      )
    )
  }

  func testMetricGridColumnCountsRespectWidthAndAccessibility() {
    let compact = HPScreenLayoutContext(
      isRegularWidth: false,
      isAccessibilitySize: false
    )
    let expanded = HPScreenLayoutContext(
      isRegularWidth: true,
      isAccessibilitySize: false
    )
    let accessibility = HPScreenLayoutContext(
      isRegularWidth: true,
      isAccessibilitySize: true
    )

    XCTAssertEqual(compact.gridColumnCount(compact: 2, regular: 4), 2)
    XCTAssertEqual(expanded.gridColumnCount(compact: 2, regular: 4), 4)
    XCTAssertEqual(accessibility.gridColumnCount(compact: 2, regular: 4), 1)

    let wide = HPScreenLayoutContext(widthClass: .wide, isAccessibilitySize: false)
    XCTAssertEqual(wide.gridColumnCount(compact: 2, regular: 3, wide: 4), 4)
  }

  func testDetailMetricsUseFourColumnsAtRegularAndWideWidths() {
    let compact = HPScreenLayoutContext(widthClass: .compact, isAccessibilitySize: false)
    let regular = HPScreenLayoutContext(widthClass: .regular, isAccessibilitySize: false)
    let wide = HPScreenLayoutContext(widthClass: .wide, isAccessibilitySize: false)
    let accessibility = HPScreenLayoutContext(widthClass: .wide, isAccessibilitySize: true)

    XCTAssertEqual(HPDetailMetricGridPolicy.columnCount(for: compact), 2)
    XCTAssertEqual(HPDetailMetricGridPolicy.columnCount(for: regular), 4)
    XCTAssertEqual(HPDetailMetricGridPolicy.columnCount(for: wide), 4)
    XCTAssertEqual(HPDetailMetricGridPolicy.columnCount(for: accessibility), 1)
  }

  func testEveryHomePlateButtonSizePreservesMinimumTapTarget() {
    XCTAssertEqual(HPButtonSize.sm.minHeight, 28)
    XCTAssertEqual(HPButtonSize.md.minHeight, 36)
    XCTAssertEqual(HPButtonSize.lg.minHeight, 44)
    XCTAssertGreaterThanOrEqual(HPButtonSize.sm.hitTargetHeight, 44)
    XCTAssertGreaterThanOrEqual(HPButtonSize.md.hitTargetHeight, 44)
    XCTAssertGreaterThanOrEqual(HPButtonSize.lg.hitTargetHeight, 44)
  }

  func testReusableLayoutInitializersRemainSourceCompatible() {
    _ = HPWorkspaceScreenLayout {
      Text("Header")
    } attention: {
      Text("Attention")
    } metrics: {
      Text("Metric")
    } supporting: {
      Text("Supporting")
    }

    _ = HPListScreenLayout {
      Text("Header")
    } controls: {
      Text("Controls")
    } results: { _ in
      Text("Results")
    }

    _ = HPDetailScreenLayout {
      Text("Identity")
    } metrics: {
      Text("Metric")
    } details: {
      Text("Details")
    } related: { _ in
      Text("Related")
    } primaryAction: {
      Text("Action")
    }

    _ = HPFormScreenLayout { _ in
      Text("Header")
    } sections: { _ in
      Text("Sections")
    } primaryAction: { _ in
      Text("Save")
    } secondaryAction: { _ in
      Text("Cancel")
    }

    _ = HPProgramExecutionLayout {
      Text("Header")
    } dateContext: {
      Text("Date")
    } programSummary: {
      Text("Program")
    } activities: {
      Text("Activities")
    } subActivities: {
      Text("Subactivities")
    } assessment: {
      Text("Assessment")
    } submission: {
      Text("Submit")
    }

    _ = HPCalendarScreenLayout(
      compactPane: .calendar,
      header: { _ in Text("Header") },
      scopeControl: { _ in Text("Scope") },
      calendar: { _ in Text("Calendar") },
      agenda: { _ in Text("Agenda") },
      stateContent: { _ in Text("State") }
    )

    _ = HPAnalyticsScreenLayout {
      Text("Header")
    } rangeControls: {
      Text("Range")
    } metrics: {
      Text("Metrics")
    } charts: {
      Text("Charts")
    } breakdown: { _ in
      Text("Breakdown")
    }

    _ = HPCommunicationScreenLayout(
      compactPane: .conversations,
      conversationList: { _ in Text("Conversations") },
      thread: { _ in Text("Thread") }
    )

    _ = HPSettingsScreenLayout { _ in
      Text("Header")
    } sections: { _ in
      Text("Sections")
    } destructiveAction: { _ in
      Text("Sign out")
    }

    _ = HPAdminScreenLayout(
      supportContext: HPAdminSupportContext(organizationName: "Home Plate"),
      header: { _ in Text("Header") },
      sectionNavigation: { _ in Text("Sections") },
      content: { _ in Text("Content") },
      dangerZone: { _ in Text("Danger") }
    )

    _ = HPStateScreenLayout { _ in
      Text("State")
    }
  }

  func testTemplateGalleryInitializersRemainSourceCompatible() {
    _ = HPWorkspaceScreenTemplate(isWide: true)
    _ = HPListScreenTemplate(isWide: true, state: .loaded)
    _ = HPDetailScreenTemplate(isWide: true)
    _ = HPFormScreenTemplate(isWide: true)
    _ = HPProgramExecutionTemplate(isWide: true, state: .loaded)
    _ = HPCalendarScreenTemplate(isWide: true, state: .loaded)
    _ = HPAnalyticsScreenTemplate(isWide: true, state: .loaded)
    _ = HPCommunicationScreenTemplate(isWide: true, state: .loaded)
    _ = HPSettingsScreenTemplate(isWide: true)
    _ = HPAdminScreenTemplate(isWide: true, isSupportMode: true)
    _ = HPStateScreenTemplate(kind: .paywall, isWide: true)
  }
}
