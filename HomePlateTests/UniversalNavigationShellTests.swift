import XCTest
import SwiftUI
@testable import HomePlate

#if canImport(UIKit)
import UIKit
#endif

@MainActor
final class UniversalNavigationShellTests: XCTestCase {
  func testPlayerCompactInventoryUsesFourTabsPlusDirectory() {
    let inventory = playerInventory()

    XCTAssertEqual(
      inventory.compactItems.map(\.destination),
      [.playerToday, .playerCalendar, .playerTrends, .chat]
    )
    XCTAssertEqual(inventory.compactTabCountIncludingDirectory, 5)
    XCTAssertEqual(
      Set(inventory.directoryItems.map(\.destination)),
      [.playerTesting, .playerAnalysis, .playerFacilities, .playerDevelopment, .account]
    )
  }

  func testPlayerFeatureGatesRemoveOnlyGatedDestinations() {
    let inventory = HPAppNavigationInventory.player(
      chatEnabled: false,
      facilitiesEnabled: false,
      testingEnabled: false,
      analysisEnabled: false,
      facilitiesTitle: "Facilities",
      testingTitle: "Testing"
    )

    let destinations = Set((inventory.compactItems + inventory.directoryItems).map(\.destination))
    XCTAssertFalse(destinations.contains(.chat))
    XCTAssertFalse(destinations.contains(.playerFacilities))
    XCTAssertFalse(destinations.contains(.playerTesting))
    XCTAssertFalse(destinations.contains(.playerAnalysis))
    XCTAssertTrue(destinations.contains(.playerDevelopment))
    XCTAssertTrue(destinations.contains(.account))
  }

  func testParentInventoryPreservesChildrenChatAndAccount() {
    let inventory = HPAppNavigationInventory.parent(childrenTitle: "Children", chatEnabled: true)

    XCTAssertEqual(inventory.compactItems.map(\.destination), [.parentChildren, .chat])
    XCTAssertEqual(inventory.directoryItems.map(\.destination), [.account])
    XCTAssertEqual(inventory.compactTabCountIncludingDirectory, 3)
  }

  func testCoachInventoryNeverExceedsFiveCompactTabs() {
    let coach = staffInventory(canAdminister: false, isPlatformAdmin: true)
    XCTAssertEqual(coach.compactTabCountIncludingDirectory, 4)
    XCTAssertEqual(
      coach.compactItems.map(\.destination),
      [.coachToday, .coachTeam, .coachSchedule]
    )
    XCTAssertFalse(coach.directoryItems.contains { $0.destination == .coachPlayers })
    XCTAssertTrue(coach.directoryItems.contains { $0.destination == .platformAdmin })
    XCTAssertTrue(coach.directoryItems.contains { $0.destination == .account })
  }

  func testOwnerInventoryPromotesTeamScheduleChatAndFinances() {
    let owner = HPAppNavigationInventory.owner(
      facilitiesTitle: "Facilities",
      programsTitle: "Program Templates",
      facilitiesEnabled: true,
      chatEnabled: true,
      programsEnabled: true,
      isPlatformAdmin: false
    )

    XCTAssertEqual(
      owner.compactItems.map(\.destination),
      [.coachTeam, .coachSchedule, .chat, .finance]
    )
    XCTAssertEqual(owner.compactItems.map(\.title), ["Team", "Schedule", "Chat", "Finances"])
    XCTAssertEqual(owner.compactTabCountIncludingDirectory, 5)
    XCTAssertEqual(owner.defaultDestination, .coachTeam)
    XCTAssertFalse(owner.regularItems.contains { $0.destination == .coachToday })
    XCTAssertFalse(owner.regularItems.contains { $0.destination == .platformAdmin })
    XCTAssertTrue(owner.regularItems.contains { $0.destination == .finance })
    XCTAssertTrue(owner.directoryItems.contains { $0.destination == .organizationAdmin })
    XCTAssertTrue(owner.regularItems.contains { $0.destination == .account })
  }

  func testPlatformOnlyInventoryHasAdministrationAndAccountEscape() {
    let inventory = HPAppNavigationInventory.platformOnly()

    XCTAssertEqual(inventory.compactItems.map(\.destination), [.platformAdmin])
    XCTAssertEqual(inventory.directoryItems.map(\.destination), [.account])
    XCTAssertEqual(
      Set(inventory.regularItems.map(\.destination)),
      [.platformAdmin, .account]
    )
  }

  func testMacPlayerInventoryDoesNotInventUnavailableDestinations() {
    let inventory = HPAppNavigationInventory.playerMacPlaceholder()

    XCTAssertEqual(inventory.regularItems.map(\.destination), [.playerToday])
    XCTAssertEqual(inventory.defaultDestination, .playerToday)
    XCTAssertTrue(inventory.directoryItems.isEmpty)
  }

  func testAdaptiveShellRetainsBaselineDestinationSubtrees() throws {
    let projectRoot = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    let source = try String(
      contentsOf: projectRoot
        .appendingPathComponent("HomePlate/Features/Home/HomePlateNavigationShell.swift"),
      encoding: .utf8
    )

    XCTAssertTrue(source.contains("struct HPAdaptiveApplicationShell"))
    XCTAssertTrue(source.contains("HStack(spacing: 0)"))
    XCTAssertTrue(source.contains("TabView(selection: $selection)"))
    XCTAssertTrue(source.contains(".tabViewStyle(.page(indexDisplayMode: .never))"))
    XCTAssertTrue(source.contains("HPPageSwipeLock"))
  }

  func testNavigationKeysRemainStableWhenInventoriesAreRebuilt() {
    let first = playerInventory().regularGroups.flatMap(\.items).map(\.key)
    let second = playerInventory().regularGroups.flatMap(\.items).map(\.key)

    XCTAssertEqual(first, second)
    XCTAssertEqual(Set(first).count, first.count)
  }

  func testRegularSelectionFallsBackOnlyWhenDestinationIsUnavailable() {
    let inventory = playerInventory()

    XCTAssertEqual(inventory.normalizedRegularSelection(.playerAnalysis), .playerAnalysis)
    XCTAssertEqual(inventory.normalizedRegularSelection(.organizationAdmin), .playerToday)
    XCTAssertEqual(inventory.normalizedRegularSelection(.directory), .playerToday)
  }

  func testChatWorkspaceKeyResolvesToTheSameTypedDestination() {
    let inventory = playerInventory()

    XCTAssertEqual(inventory.destination(forWorkspaceKey: "chat"), .chat)
  }

  func testApplicationIdentityAndTargetMetricsUseHomePlateDefaults() {
    XCTAssertEqual(DHDOrgBranding.fallback.name, "Home Plate")
    XCTAssertEqual(DHDOrgBranding.fallback.shortName, "Home Plate")
    XCTAssertGreaterThanOrEqual(DHDTheme.minimumTouchTarget, 44)
  }

#if canImport(UIKit)
  func testRenderCompactPlayerNavigationLight() throws {
    try renderNavigation(
      name: "compact-player-light",
      role: .player,
      inventory: playerInventory(),
      selection: .playerToday,
      width: 393,
      height: 852,
      dynamicTypeSize: .large,
      style: .light,
      regular: false
    )
  }

  func testRenderCompactDirectoryDarkAX3() throws {
    try renderNavigation(
      name: "compact-directory-ax3-dark",
      role: .player,
      inventory: playerInventory(),
      selection: .directory,
      width: 393,
      height: 1_260,
      dynamicTypeSize: .accessibility3,
      style: .dark,
      regular: false
    )
  }

  func testRenderRegularParentIPad() throws {
    try renderNavigation(
      name: "regular-parent-ipad-light",
      role: .parent,
      inventory: .parent(childrenTitle: "Children", chatEnabled: true),
      selection: .parentChildren,
      width: 834,
      height: 1_112,
      dynamicTypeSize: .large,
      style: .light,
      regular: true
    )
  }

  func testRenderRegularCoachMacOSWidth() throws {
    try renderNavigation(
      name: "regular-coach-macos-dark",
      role: .coach,
      inventory: staffInventory(canAdminister: false, isPlatformAdmin: false),
      selection: .coachToday,
      width: 1_200,
      height: 820,
      dynamicTypeSize: .large,
      style: .dark,
      regular: true
    )
  }

  func testRenderRegularPlatformAdministration() throws {
    try renderNavigation(
      name: "regular-platform-light",
      role: .platformAdmin,
      inventory: .platformOnly(),
      selection: .platformAdmin,
      width: 1_200,
      height: 820,
      dynamicTypeSize: .large,
      style: .light,
      regular: true
    )
  }

  func testAdaptiveShellPreservesDestinationStateAcrossSizeClassesWithoutSwipe() throws {
    let inventory = HPAppNavigationInventory.parent(
      childrenTitle: "Children",
      chatEnabled: true
    )
    let model = LayerBSelectionModel(selection: .parentChildren, isRegular: true)
    let recorder = LayerBRetentionRecorder()
    let view = LayerBRegularRetentionHarness(
      inventory: inventory,
      model: model,
      recorder: recorder
    )
    .environment(\.horizontalSizeClass, .regular)
    .frame(width: 834, height: 1_112)

    let controller = UIHostingController(rootView: view)
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 834, height: 1_112))
    window.rootViewController = controller
    window.makeKeyAndVisible()
    controller.view.frame = window.bounds
    controller.view.layoutIfNeeded()
    RunLoop.current.run(until: Date().addingTimeInterval(0.2))

    let firstIdentity = try XCTUnwrap(recorder.identities[.parentChildren]?.last)
    model.isRegular = false
    RunLoop.current.run(until: Date().addingTimeInterval(0.2))
    model.selection = .account
    RunLoop.current.run(until: Date().addingTimeInterval(0.2))
    model.selection = .parentChildren
    RunLoop.current.run(until: Date().addingTimeInterval(0.2))
    model.isRegular = true
    RunLoop.current.run(until: Date().addingTimeInterval(0.2))

    let visits = try XCTUnwrap(recorder.identities[.parentChildren])
    XCTAssertGreaterThanOrEqual(visits.count, 2)
    XCTAssertEqual(visits.last, firstIdentity)
    let pageScrollViews = pagingScrollViews(in: controller.view)
    XCTAssertFalse(pageScrollViews.isEmpty)
    XCTAssertTrue(pageScrollViews.allSatisfy { !$0.isScrollEnabled })

    window.isHidden = true
    window.rootViewController = nil
  }

  private func renderNavigation(
    name: String,
    role: HPRole,
    inventory: HPAppNavigationInventory,
    selection: HPAppNavigationDestination,
    width: CGFloat,
    height: CGFloat,
    dynamicTypeSize: DynamicTypeSize,
    style: UIUserInterfaceStyle,
    regular: Bool
  ) throws {
    let colorScheme: ColorScheme = style == .dark ? .dark : .light
    let view = LayerBNavigationEvidence(
      role: role,
      inventory: inventory,
      initialSelection: selection
    )
    .environment(\.dynamicTypeSize, dynamicTypeSize)
    .environment(\.colorScheme, colorScheme)
    .environment(\.horizontalSizeClass, regular ? .regular : .compact)
    .environment(
      \.dhdOrgBranding,
      DHDOrgBranding(
        name: "Diamond Baseball Academy",
        shortName: "Diamond BA",
        primary: DHDTheme.primary,
        secondary: DHDTheme.brandDeep,
        accent: DHDTheme.accent,
        logoURL: nil
      )
    )
    .tint(DHDTheme.accent)
    .frame(width: width, height: height)

    let controller = UIHostingController(rootView: view)
    controller.overrideUserInterfaceStyle = style
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: height))
    window.overrideUserInterfaceStyle = style
    window.rootViewController = controller
    window.makeKeyAndVisible()
    controller.view.frame = window.bounds
    controller.view.layoutIfNeeded()
    RunLoop.current.run(until: Date().addingTimeInterval(0.1))

    if regular || selection == .directory {
      let pageScrollViews = pagingScrollViews(in: controller.view)
      XCTAssertFalse(pageScrollViews.isEmpty, "Expected a page-style retention host")
      XCTAssertTrue(
        pageScrollViews.allSatisfy { !$0.isScrollEnabled },
        "Retained destinations must not add swipe navigation"
      )
    }

    let format = UIGraphicsImageRendererFormat()
    format.scale = dynamicTypeSize.isAccessibilitySize || width > 500 ? 1 : 2
    let renderer = UIGraphicsImageRenderer(
      size: CGSize(width: width, height: height),
      format: format
    )
    let image = renderer.image { _ in
      controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
    }
    let data = try XCTUnwrap(image.pngData())
    XCTAssertGreaterThan(data.count, 10_000)
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("layer-b-\(name).png")
    try data.write(to: url, options: .atomic)
    print("LAYER_B_PNG \(url.path) size=\(Int(width))x\(Int(height))")

    window.isHidden = true
    window.rootViewController = nil
  }

  private func pagingScrollViews(in view: UIView) -> [UIScrollView] {
    let current = (view as? UIScrollView).map { $0.isPagingEnabled ? [$0] : [] } ?? []
    return current + view.subviews.flatMap(pagingScrollViews(in:))
  }

#endif

  private func playerInventory() -> HPAppNavigationInventory {
    .player(
      chatEnabled: true,
      facilitiesEnabled: true,
      testingEnabled: true,
      analysisEnabled: true,
      facilitiesTitle: "Facilities",
      testingTitle: "Testing"
    )
  }

  private func staffInventory(
    canAdminister: Bool,
    isPlatformAdmin: Bool
  ) -> HPAppNavigationInventory {
    .staff(
      playersTitle: "Players",
      facilitiesTitle: "Facilities",
      programsTitle: "Program Templates",
      facilitiesEnabled: true,
      chatEnabled: true,
      programsEnabled: true,
      canAdministerOrganization: canAdminister,
      isPlatformAdmin: isPlatformAdmin
    )
  }
}

#if canImport(UIKit)
private struct LayerBNavigationEvidence: View {
  let role: HPRole
  let inventory: HPAppNavigationInventory

  @State private var selection: HPAppNavigationDestination

  init(
    role: HPRole,
    inventory: HPAppNavigationInventory,
    initialSelection: HPAppNavigationDestination
  ) {
    self.role = role
    self.inventory = inventory
    _selection = State(initialValue: initialSelection)
  }

  var body: some View {
    HPAdaptiveApplicationShell(
      role: role,
      roleSubtitle: "\(role.rawValue) workspace",
      inventory: inventory,
      selection: $selection
    ) { destination in
      detail(destination)
    }
  }

  private func detail(_ destination: HPAppNavigationDestination) -> some View {
    ScrollView {
      VStack(alignment: .leading, spacing: HP.Space.md) {
        HPWorkspaceHeader(
          inventory.item(for: destination)?.title ?? "Home Plate",
          orgLabel: "Diamond BA",
          context: role.rawValue
        )
        HPCard {
          VStack(alignment: .leading, spacing: HP.Space.sm) {
            HPSectionHeader("Workspace shell")
            HPStatTile(label: "Selected destination", value: destination.rawValue)
            HPStatusBadge(text: "Available", kind: .success)
          }
          .frame(maxWidth: .infinity, alignment: .leading)
        }
      }
      .padding(HP.Space.md)
    }
    .background(HP.Color.bg)
  }
}

@MainActor
private final class LayerBSelectionModel: ObservableObject {
  @Published var selection: HPAppNavigationDestination
  @Published var isRegular: Bool

  init(selection: HPAppNavigationDestination, isRegular: Bool) {
    self.selection = selection
    self.isRegular = isRegular
  }
}

@MainActor
private final class LayerBRetentionRecorder {
  private(set) var identities: [HPAppNavigationDestination: [UUID]] = [:]

  func record(_ identity: UUID, for destination: HPAppNavigationDestination) {
    identities[destination, default: []].append(identity)
  }
}

private struct LayerBRegularRetentionHarness: View {
  let inventory: HPAppNavigationInventory
  @ObservedObject var model: LayerBSelectionModel
  let recorder: LayerBRetentionRecorder

  var body: some View {
    HPAdaptiveApplicationShell(
      role: .parent,
      roleSubtitle: "Parent workspace",
      inventory: inventory,
      selection: Binding(
        get: { model.selection },
        set: { model.selection = $0 }
      )
    ) { destination in
      LayerBRetentionProbe(
        destination: destination,
        model: model,
        recorder: recorder
      )
    }
    .environment(\.horizontalSizeClass, model.isRegular ? .regular : .compact)
  }
}

private struct LayerBRetentionProbe: View {
  let destination: HPAppNavigationDestination
  @ObservedObject var model: LayerBSelectionModel
  let recorder: LayerBRetentionRecorder
  @State private var identity = UUID()

  var body: some View {
    Text(destination.rawValue)
      .onAppear { recordIfSelected(model.selection) }
      .onChange(of: model.selection) { _, selection in
        recordIfSelected(selection)
      }
      .onChange(of: model.isRegular) { _, _ in
        recordIfSelected(model.selection)
      }
  }

  private func recordIfSelected(_ selection: HPAppNavigationDestination) {
    guard selection == destination else { return }
    recorder.record(identity, for: destination)
  }
}
#endif
