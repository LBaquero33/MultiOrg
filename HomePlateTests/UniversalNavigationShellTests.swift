import XCTest
import SwiftUI
@testable import HomePlate

#if canImport(UIKit)
import UIKit
#endif

@MainActor
final class UniversalNavigationShellTests: XCTestCase {
  func testPlayerInventoryMatchesWebsiteMenu() {
    let inventory = playerInventory()

    XCTAssertEqual(
      inventory.regularItems.map(\.destination),
      [.playerToday, .playerCalendar, .playerFacilities, .playerProgram, .playerTrends, .chat, .account]
    )
    XCTAssertEqual(
      inventory.regularItems.map(\.title),
      ["Today", "Calendar", "Facilities", "Program", "Progress", "Messages", "Account"]
    )
    XCTAssertTrue(inventory.compactItems.isEmpty)
    XCTAssertTrue(inventory.directoryItems.isEmpty)
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

    let destinations = Set(inventory.regularItems.map(\.destination))
    XCTAssertFalse(destinations.contains(.chat))
    XCTAssertFalse(destinations.contains(.playerFacilities))
    XCTAssertFalse(destinations.contains(.playerTesting))
    XCTAssertFalse(destinations.contains(.playerAnalysis))
    XCTAssertTrue(destinations.contains(.playerProgram))
    XCTAssertTrue(destinations.contains(.playerTrends))
    XCTAssertTrue(destinations.contains(.account))
  }

  func testParentInventoryMatchesWebsiteMenu() {
    let inventory = HPAppNavigationInventory.parent(childrenTitle: "Children", chatEnabled: true)

    XCTAssertEqual(
      inventory.regularItems.map(\.destination),
      [.parentHome, .parentChildren, .parentCalendar, .payments, .chat, .account]
    )
    XCTAssertEqual(
      inventory.regularItems.map(\.title),
      ["Home", "Children", "Calendar", "Payments", "Messages", "Account"]
    )
    XCTAssertTrue(inventory.compactItems.isEmpty)
    XCTAssertTrue(inventory.directoryItems.isEmpty)
  }

  func testCoachInventoryMatchesWebsiteMenuWithoutAdminLeakage() {
    let coach = staffInventory(canAdminister: false, isPlatformAdmin: true)
    XCTAssertEqual(
      coach.regularItems.map(\.destination),
      [
        .coachToday, .coachCalendar, .coachTeams, .coachPrograms, .coachFacilities,
        .games, .chat, .platformAdmin, .account,
      ]
    )
    XCTAssertFalse(coach.regularItems.contains { $0.destination == .organizationAdmin })
    XCTAssertEqual(
      coach.compactItems.map(\.destination),
      [.coachToday, .coachTeams, .coachCalendar, .coachPrograms]
    )
    XCTAssertEqual(coach.compactTabCountIncludingDirectory, 5)
    XCTAssertEqual(
      coach.directoryItems.map(\.destination),
      [.coachFacilities, .games, .chat, .platformAdmin, .account]
    )
  }

  func testOwnerInventoryMatchesWebsiteMenuWithOrganizationSettings() {
    let owner = HPAppNavigationInventory.owner(
      facilitiesTitle: "Facilities",
      programsTitle: "Program Templates",
      facilitiesEnabled: true,
      chatEnabled: true,
      programsEnabled: true,
      isPlatformAdmin: false
    )

    XCTAssertEqual(owner.defaultDestination, .coachToday)
    XCTAssertTrue(owner.regularItems.contains { $0.destination == .coachToday })
    XCTAssertTrue(owner.regularItems.contains { $0.destination == .coachCalendar })
    XCTAssertFalse(owner.regularItems.contains { $0.destination == .platformAdmin })
    XCTAssertTrue(owner.regularItems.contains { $0.destination == .payments })
    XCTAssertTrue(owner.regularItems.contains { $0.destination == .organizationAdmin })
    XCTAssertTrue(owner.regularItems.contains { $0.destination == .account })
    XCTAssertEqual(
      owner.compactItems.map(\.destination),
      [.coachToday, .coachTeams, .coachCalendar, .coachPrograms]
    )
    XCTAssertEqual(owner.compactTabCountIncludingDirectory, 5)
    XCTAssertEqual(
      owner.directoryItems.map(\.destination),
      [.coachFacilities, .games, .chat, .payments, .organizationAdmin, .account]
    )
  }

  func testPlatformOnlyInventoryHasAdministrationAndAccountEscape() {
    let inventory = HPAppNavigationInventory.platformOnly()

    XCTAssertTrue(inventory.compactItems.isEmpty)
    XCTAssertTrue(inventory.directoryItems.isEmpty)
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

  func testAdaptiveShellHostsOnlyTheSelectedDestination() throws {
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
    XCTAssertTrue(source.contains("retainedDestination(selection)"))
    XCTAssertTrue(source.contains(".id(selection)"))
    XCTAssertFalse(source.contains("TabView(selection: $selection)"))
    XCTAssertFalse(source.contains(".tabViewStyle(.page(indexDisplayMode: .never))"))
    XCTAssertTrue(source.contains("private var mobileHeader"))
    XCTAssertTrue(source.contains("private var mobileMenu"))
    XCTAssertTrue(source.contains("private var mobileBottomBar"))
    XCTAssertTrue(source.contains(".move(edge: .leading)"))
    XCTAssertTrue(source.contains("DragGesture(minimumDistance: 12)"))
    XCTAssertTrue(source.contains("value.translation.width < -50"))
    XCTAssertTrue(source.contains(".onTapGesture { closeMobileMenu() }"))
    XCTAssertFalse(source.contains("compactNavigationBar"))
    XCTAssertFalse(source.contains("HPPageSwipeLock"))
  }

  func testTeamScopeSelectorIsVisibleToStaffAndAdminsWithOneOrMoreTeams() throws {
    let projectRoot = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    let source = try String(
      contentsOf: projectRoot
        .appendingPathComponent("HomePlate/Features/Home/HomePlateNavigationShell.swift"),
      encoding: .utf8
    )

    XCTAssertTrue(source.contains("role == .coach || role == .owner"))
    XCTAssertTrue(source.contains("canSelectTeam && !activeTeamScopes.isEmpty"))
    XCTAssertTrue(source.contains("Text(\"All Teams\")"))
  }

  func testNavigationKeysRemainStableWhenInventoriesAreRebuilt() {
    let first = playerInventory().regularGroups.flatMap(\.items).map(\.key)
    let second = playerInventory().regularGroups.flatMap(\.items).map(\.key)

    XCTAssertEqual(first, second)
    XCTAssertEqual(Set(first).count, first.count)
  }

  func testRegularSelectionFallsBackOnlyWhenDestinationIsUnavailable() {
    let inventory = playerInventory()

    XCTAssertEqual(inventory.normalizedRegularSelection(.playerProgram), .playerProgram)
    XCTAssertEqual(inventory.normalizedRegularSelection(.playerAnalysis), .playerToday)
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

  func testRenderCompactPlayerProgramDarkAX3() throws {
    try renderNavigation(
      name: "compact-player-program-ax3-dark",
      role: .player,
      inventory: playerInventory(),
      selection: .playerProgram,
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

  func testAdaptiveShellPreservesSelectionAcrossSizeClassesWithoutPagingHost() throws {
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

    model.isRegular = false
    RunLoop.current.run(until: Date().addingTimeInterval(0.2))
    XCTAssertEqual(model.selection, .parentChildren)
    model.selection = .account
    RunLoop.current.run(until: Date().addingTimeInterval(0.2))
    model.selection = .parentChildren
    RunLoop.current.run(until: Date().addingTimeInterval(0.2))
    model.isRegular = true
    RunLoop.current.run(until: Date().addingTimeInterval(0.2))

    let visits = try XCTUnwrap(recorder.identities[.parentChildren])
    XCTAssertGreaterThanOrEqual(visits.count, 2)
    XCTAssertEqual(model.selection, .parentChildren)
    XCTAssertTrue(pagingScrollViews(in: controller.view).isEmpty)

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

    let pageScrollViews = pagingScrollViews(in: controller.view)
    XCTAssertTrue(
      pageScrollViews.isEmpty,
      "The adaptive shell must not embed destination navigation stacks in a page controller"
    )

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
    .environmentObject(AppState())
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
    .environmentObject(AppState())
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
