import SwiftUI

#if os(iOS)
import UIKit
#endif

/// Presentation-only destinations used by the authenticated application shells.
///
/// The enum deliberately contains routes that already exist in the role roots.
/// It does not own authorization, feature flags, data loading, or navigation
/// destinations; role roots continue to supply those gates and views.
enum HPAppNavigationDestination: String, CaseIterable, Hashable, Identifiable {
  case directory

  case playerToday
  case playerCalendar
  case playerTrends
  case playerTesting
  case playerAnalysis
  case playerFacilities
  case playerDevelopment

  case parentChildren

  case coachPlayers
  case coachFacilities
  case coachTeams
  case coachPrograms

  case chat
  case finance
  case organizationAdmin
  case platformAdmin
  case account

  var id: String { rawValue }
}

struct HPAppNavigationItem: Identifiable, Equatable {
  let destination: HPAppNavigationDestination
  let title: String
  let systemImage: String

  var id: HPAppNavigationDestination { destination }

  var workspaceItem: HPWorkspaceItem {
    HPWorkspaceItem(
      key: destination.rawValue,
      title: title,
      icon: systemImage
    )
  }
}

struct HPAppNavigationSection: Identifiable, Equatable {
  let title: String?
  let items: [HPAppNavigationItem]

  var id: String {
    title ?? items.map(\.destination.rawValue).joined(separator: ":")
  }

  var navigationGroup: HPNavGroup {
    HPNavGroup(title: title, items: items.map(\.workspaceItem))
  }
}

/// A single role inventory rendered as compact tabs + directory or as a
/// regular-width sidebar. Feature and capability booleans are caller-owned.
struct HPAppNavigationInventory: Equatable {
  let compactItems: [HPAppNavigationItem]
  let directorySections: [HPAppNavigationSection]
  let regularSections: [HPAppNavigationSection]
  let defaultDestination: HPAppNavigationDestination

  var directoryItems: [HPAppNavigationItem] {
    directorySections.flatMap(\.items)
  }

  var regularItems: [HPAppNavigationItem] {
    regularSections.flatMap(\.items)
  }

  var compactTabCountIncludingDirectory: Int {
    compactItems.count + (directoryItems.isEmpty ? 0 : 1)
  }

  var directoryGroups: [HPNavGroup] {
    directorySections.map(\.navigationGroup)
  }

  var regularGroups: [HPNavGroup] {
    regularSections.map(\.navigationGroup)
  }

  func item(for destination: HPAppNavigationDestination) -> HPAppNavigationItem? {
    (compactItems + directoryItems + regularItems).first { $0.destination == destination }
  }

  func destination(forWorkspaceKey key: String) -> HPAppNavigationDestination? {
    regularItems.first { $0.destination.rawValue == key }?.destination
      ?? directoryItems.first { $0.destination.rawValue == key }?.destination
  }

  func isCompactItem(_ destination: HPAppNavigationDestination) -> Bool {
    compactItems.contains { $0.destination == destination }
  }

  func isDirectoryItem(_ destination: HPAppNavigationDestination) -> Bool {
    directoryItems.contains { $0.destination == destination }
  }

  func normalizedRegularSelection(
    _ destination: HPAppNavigationDestination
  ) -> HPAppNavigationDestination {
    regularItems.contains { $0.destination == destination }
      ? destination
      : defaultDestination
  }

  static func player(
    chatEnabled: Bool,
    facilitiesEnabled: Bool,
    testingEnabled: Bool,
    analysisEnabled: Bool,
    developmentAIEnabled: Bool = true,
    facilitiesTitle: String,
    testingTitle: String
  ) -> Self {
    let today = item(.playerToday, "Today", "sun.max")
    let calendar = item(.playerCalendar, "Calendar", "calendar")
    let trends = item(.playerTrends, "Trends", "chart.line.uptrend.xyaxis")
    let chat = item(.chat, "Chat", "bubble.left.and.bubble.right")
    let testing = item(.playerTesting, testingTitle, "tablecells")
    let analysis = item(.playerAnalysis, "Analysis", "chart.xyaxis.line")
    let facilities = item(.playerFacilities, facilitiesTitle, "building.2")
    let development = item(
      .playerDevelopment,
      "Development AI",
      "sparkles.rectangle.stack"
    )
    let developmentItems = developmentAIEnabled ? [development] : []
    let account = item(.account, "Account", "gearshape")

    let compact = [today, calendar, trends] + (chatEnabled ? [chat] : [])
    let directory = [
      HPAppNavigationSection(
        title: "Develop",
        items: (testingEnabled ? [testing] : [])
          + (analysisEnabled ? [analysis] : [])
          + developmentItems
      ),
      HPAppNavigationSection(
        title: "Run",
        items: facilitiesEnabled ? [facilities] : []
      ),
      HPAppNavigationSection(title: "Manage", items: [account]),
    ].filter { !$0.items.isEmpty }

    let regular = [
      HPAppNavigationSection(title: nil, items: [today]),
      HPAppNavigationSection(
        title: "Develop",
        items: [trends]
          + (testingEnabled ? [testing] : [])
          + (analysisEnabled ? [analysis] : [])
          + developmentItems
      ),
      HPAppNavigationSection(
        title: "Run",
        items: [calendar]
          + (chatEnabled ? [chat] : [])
          + (facilitiesEnabled ? [facilities] : [])
      ),
      HPAppNavigationSection(title: "Manage", items: [account]),
    ].filter { !$0.items.isEmpty }

    return Self(
      compactItems: compact,
      directorySections: directory,
      regularSections: regular,
      defaultDestination: .playerToday
    )
  }

  static func parent(childrenTitle: String, chatEnabled: Bool) -> Self {
    let children = item(.parentChildren, childrenTitle, "person.2")
    let chat = item(.chat, "Chat", "bubble.left.and.bubble.right")
    let account = item(.account, "Account", "gearshape")
    let compact = [children] + (chatEnabled ? [chat] : [])
    let directory = [HPAppNavigationSection(title: "Manage", items: [account])]
    let regular = [
      HPAppNavigationSection(title: nil, items: [children]),
      HPAppNavigationSection(title: "Run", items: chatEnabled ? [chat] : []),
      HPAppNavigationSection(title: "Manage", items: [account]),
    ].filter { !$0.items.isEmpty }
    return Self(
      compactItems: compact,
      directorySections: directory,
      regularSections: regular,
      defaultDestination: .parentChildren
    )
  }

  /// The native macOS player target intentionally exposes only its existing
  /// placeholder workspace. Development and Account remain the same modal
  /// actions owned by `PlayerHomeView`; this inventory adds native sidebar
  /// chrome without inventing unavailable macOS destinations.
  static func playerMacPlaceholder() -> Self {
    let player = item(.playerToday, "Player", "person.crop.circle")
    return Self(
      compactItems: [player],
      directorySections: [],
      regularSections: [HPAppNavigationSection(title: nil, items: [player])],
      defaultDestination: .playerToday
    )
  }

  static func staff(
    playersTitle: String,
    facilitiesTitle: String,
    programsTitle: String,
    facilitiesEnabled: Bool,
    chatEnabled: Bool,
    programsEnabled: Bool,
    canAdministerOrganization: Bool,
    isPlatformAdmin: Bool
  ) -> Self {
    let players = item(
      .coachPlayers,
      canAdministerOrganization ? "Overview" : playersTitle,
      "person.3"
    )
    let facilities = item(.coachFacilities, facilitiesTitle, "calendar.badge.clock")
    let teams = item(.coachTeams, "Teams", "person.3.sequence.fill")
    let programs = item(.coachPrograms, programsTitle, "square.stack.3d.up")
    let chat = item(.chat, "Chat", "bubble.left.and.bubble.right")
    let finance = item(.finance, "Finance", "dollarsign.circle")
    let organization = item(.organizationAdmin, "Organization", "slider.horizontal.3")
    let platform = item(.platformAdmin, "Platform Admin", "building.2.crop.circle")
    let account = item(.account, "Account", "gearshape")

    let compact: [HPAppNavigationItem]
    if canAdministerOrganization {
      compact = [players, finance]
        + (chatEnabled ? [chat] : [])
        + [organization]
    } else {
      compact = [players]
        + (facilitiesEnabled ? [facilities] : [])
        + (chatEnabled ? [chat] : [])
        + (programsEnabled ? [programs] : [])
    }

    let compactDestinations = Set(compact.map(\.destination))
    let directoryItems = [
      facilitiesEnabled ? facilities : nil,
      teams,
      programsEnabled ? programs : nil,
      canAdministerOrganization ? organization : nil,
      isPlatformAdmin ? platform : nil,
      account,
    ].compactMap { $0 }.filter { !compactDestinations.contains($0.destination) }

    let directory = [
      HPAppNavigationSection(
        title: "Develop",
        items: directoryItems.filter {
          [.coachTeams, .coachPrograms].contains($0.destination)
        }
      ),
      HPAppNavigationSection(
        title: "Run",
        items: directoryItems.filter { $0.destination == .coachFacilities }
      ),
      HPAppNavigationSection(
        title: "Manage",
        items: directoryItems.filter {
          [.organizationAdmin, .platformAdmin, .account].contains($0.destination)
        }
      ),
    ].filter { !$0.items.isEmpty }

    let regular = [
      HPAppNavigationSection(title: nil, items: [players]),
      HPAppNavigationSection(
        title: "Develop",
        items: [teams] + (programsEnabled ? [programs] : [])
      ),
      HPAppNavigationSection(
        title: "Run",
        items: (facilitiesEnabled ? [facilities] : [])
          + (chatEnabled ? [chat] : [])
          + (canAdministerOrganization ? [finance] : [])
      ),
      HPAppNavigationSection(
        title: "Manage",
        items: (canAdministerOrganization ? [organization] : [])
          + (isPlatformAdmin ? [platform] : [])
          + [account]
      ),
    ].filter { !$0.items.isEmpty }

    return Self(
      compactItems: compact,
      directorySections: directory,
      regularSections: regular,
      defaultDestination: .coachPlayers
    )
  }

  static func platformOnly() -> Self {
    let platform = item(.platformAdmin, "Platform Admin", "building.2.crop.circle")
    let account = item(.account, "Account", "gearshape")
    return Self(
      compactItems: [platform],
      directorySections: [HPAppNavigationSection(title: "Manage", items: [account])],
      regularSections: [
        HPAppNavigationSection(title: nil, items: [platform]),
        HPAppNavigationSection(title: "Manage", items: [account]),
      ],
      defaultDestination: .platformAdmin
    )
  }

  private static func item(
    _ destination: HPAppNavigationDestination,
    _ title: String,
    _ systemImage: String
  ) -> HPAppNavigationItem {
    HPAppNavigationItem(destination: destination, title: title, systemImage: systemImage)
  }
}

/// Compact authenticated identity chrome shared by player, parent, staff, and
/// platform workspaces. Global actions live in RootView's reserved app chrome.
struct HPApplicationIdentityShell<Content: View>: View {
  let roleSubtitle: String
  let showsIdentity: Bool
  let content: Content

  init(
    roleSubtitle: String,
    showsIdentity: Bool = true,
    @ViewBuilder content: () -> Content
  ) {
    self.roleSubtitle = roleSubtitle
    self.showsIdentity = showsIdentity
    self.content = content()
  }

  var body: some View {
    VStack(spacing: 0) {
      if showsIdentity {
        DHDOrgMenuHeader(subtitle: roleSubtitle)
          .padding(.horizontal, HP.Space.xs)
          .padding(.vertical, HP.Space.xs)
          .frame(maxWidth: .infinity)

        Rectangle()
          .fill(DHDTheme.border)
          .frame(height: 1)
          .allowsHitTesting(false)
      }

      content
        .tint(DHDTheme.accent)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(DHDTheme.pageBackground)
  }
}

#if os(iOS)
/// A single adaptive iOS/iPadOS shell. Its layout and retained destination host
/// never change structural identity when the window crosses a
/// size-class boundary, so selected player/child, navigation, filter, and form
/// state survive iPad multitasking transitions.
struct HPAdaptiveApplicationShell<DestinationContent: View>: View {
  @Environment(\.dhdOrgBranding) private var branding
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass

  let role: HPRole
  let roleSubtitle: String
  let inventory: HPAppNavigationInventory
  @Binding var selection: HPAppNavigationDestination
  let destinationContent: (HPAppNavigationDestination) -> DestinationContent

  init(
    role: HPRole,
    roleSubtitle: String,
    inventory: HPAppNavigationInventory,
    selection: Binding<HPAppNavigationDestination>,
    @ViewBuilder destinationContent: @escaping (HPAppNavigationDestination) -> DestinationContent
  ) {
    self.role = role
    self.roleSubtitle = roleSubtitle
    self.inventory = inventory
    _selection = selection
    self.destinationContent = destinationContent
  }

  var body: some View {
    HStack(spacing: 0) {
      if isRegular {
        HPSidebar(
          orgIdentity: identity,
          role: role,
          groups: inventory.regularGroups,
          selectionKey: selectionKey
        )
        .frame(width: regularSidebarWidth)

        Rectangle()
          .fill(DHDTheme.border)
          .frame(width: 1)
          .allowsHitTesting(false)
      }

      HPApplicationIdentityShell(
        roleSubtitle: roleSubtitle,
        showsIdentity: !isRegular
      ) {
        retainedDestinationHost
      }
      .safeAreaInset(edge: .bottom, spacing: 0) {
        if !isRegular {
          compactNavigationBar
        }
      }
    }
    .onAppear { synchronizePresentation() }
    .onChange(of: isRegular) { _, _ in synchronizePresentation() }
    .onChange(of: inventory) { _, _ in synchronizePresentation() }
  }

  private var isRegular: Bool {
    horizontalSizeClass == .regular
  }

  private var regularSidebarWidth: CGFloat {
    dynamicTypeSize.isAccessibilitySize ? 320 : 272
  }

  private var retainedItems: [HPAppNavigationItem] {
    var seen: Set<HPAppNavigationDestination> = []
    return inventory.regularItems.filter { seen.insert($0.destination).inserted }
  }

  private var retainedDestinationHost: some View {
    TabView(selection: $selection) {
      ForEach(retainedItems) { item in
        retainedDestination(item.destination)
          .background(HPPageSwipeLock().allowsHitTesting(false))
          .tag(item.destination)
      }

      if !inventory.directoryItems.isEmpty {
        compactDirectory
          .background(HPPageSwipeLock().allowsHitTesting(false))
          .tag(HPAppNavigationDestination.directory)
      }
    }
    .tabViewStyle(.page(indexDisplayMode: .never))
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(DHDTheme.pageBackground)
  }

  private func retainedDestination(
    _ destination: HPAppNavigationDestination
  ) -> some View {
    VStack(spacing: 0) {
      if !isRegular, inventory.isDirectoryItem(destination) {
        HStack {
          DHDButton(
            "Back to More",
            systemImage: "chevron.left",
            variant: .secondary,
            size: .compact
          ) {
            selection = .directory
          }
          Spacer(minLength: 0)
        }
        .padding(.horizontal, DHDTheme.pagePadding)
        .padding(.top, HP.Space.xs)
      }

      destinationContent(destination)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
  }

  private var compactDirectory: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: HP.Space.md) {
        HPWorkspaceHeader(
          "More",
          orgLabel: branding.shortName,
          context: "All available workspaces"
        )
        HPWorkspaceDirectory(groups: inventory.directoryGroups) { item in
          guard let destination = inventory.destination(forWorkspaceKey: item.key) else { return }
          selection = destination
        }
      }
      .padding(DHDTheme.pagePadding)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .dhdPageBackground()
  }

  private var compactNavigationBar: some View {
    HStack(spacing: HP.Space.xs) {
      ForEach(inventory.compactItems) { item in
        compactNavigationButton(item)
      }

      if !inventory.directoryItems.isEmpty {
        compactNavigationButton(
          HPAppNavigationItem(
            destination: .directory,
            title: "More",
            systemImage: "square.grid.2x2"
          )
        )
      }
    }
    .padding(.horizontal, HP.Space.xs)
    .padding(.vertical, HP.Space.xs)
    .padding(.bottom, HP.Space.xs)
    .background(DHDTheme.cardBackground)
    .overlay(alignment: .top) {
      Rectangle()
        .fill(DHDTheme.border)
        .frame(height: 1)
        .allowsHitTesting(false)
    }
  }

  private func compactNavigationButton(
    _ item: HPAppNavigationItem
  ) -> some View {
    let selected = item.destination == .directory
      ? (selection == .directory || inventory.isDirectoryItem(selection))
      : selection == item.destination

    return Button {
      selection = item.destination
    } label: {
      VStack(spacing: 2) {
        Image(systemName: item.systemImage)
          .font(.system(size: 18, weight: .semibold))
          .accessibilityHidden(true)
        Text(item.title)
          // Match native tab-bar behavior: navigation labels stay compact at
          // accessibility sizes while destination content continues to scale.
          .font(.system(size: 10, weight: .semibold))
          .lineLimit(1)
          .minimumScaleFactor(0.8)
      }
      .foregroundStyle(selected ? DHDTheme.accent : DHDTheme.textSecondary)
      .frame(maxWidth: .infinity, minHeight: 48)
      .background(
        RoundedRectangle(cornerRadius: HP.Radius.md, style: .continuous)
          .fill(selected ? DHDTheme.accent.opacity(0.14) : .clear)
      )
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(item.title)
    .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
  }

  private var identity: HPIdentity {
    HPIdentity(
      name: branding.name,
      shortName: branding.shortName,
      primary: branding.primary,
      secondary: branding.secondary
    )
  }

  private var selectionKey: Binding<String?> {
    Binding(
      get: {
        inventory.regularItems.contains { $0.destination == selection }
          ? selection.rawValue
          : inventory.defaultDestination.rawValue
      },
      set: { key in
        guard let key, let destination = inventory.destination(forWorkspaceKey: key) else { return }
        selection = destination
      }
    )
  }

  private func synchronizePresentation() {
    let selectionIsAvailable = inventory.regularItems.contains { $0.destination == selection }
      || (!isRegular && selection == .directory)
    if !selectionIsAvailable {
      selection = inventory.defaultDestination
    }
  }
}
#endif

/// Regular-width application chrome. Role roots own the selected destination
/// and the detail content, while this type owns only presentation.
struct HPRegularApplicationShell<Detail: View>: View {
  @Environment(\.dhdOrgBranding) private var branding
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  let role: HPRole
  let inventory: HPAppNavigationInventory
  @Binding var selection: HPAppNavigationDestination
  let detail: (HPAppNavigationDestination) -> Detail

  init(
    role: HPRole,
    inventory: HPAppNavigationInventory,
    selection: Binding<HPAppNavigationDestination>,
    @ViewBuilder detail: @escaping (HPAppNavigationDestination) -> Detail
  ) {
    self.role = role
    self.inventory = inventory
    _selection = selection
    self.detail = detail
  }

  var body: some View {
    NavigationSplitView {
      HPSidebar(
        orgIdentity: identity,
        role: role,
        groups: inventory.regularGroups,
        selectionKey: selectionKey
      )
      .navigationSplitViewColumnWidth(
        min: sidebarColumnWidths.minimum,
        ideal: sidebarColumnWidths.ideal,
        max: sidebarColumnWidths.maximum
      )
    } detail: {
      retainedDetail
    }
    .navigationSplitViewStyle(.balanced)
    .onAppear { normalizeSelection() }
    .onChange(of: inventory) { _, _ in normalizeSelection() }
  }

  @ViewBuilder
  private var retainedDetail: some View {
    // The existing macOS coach shell already used a selected-detail switch.
    // Preserve that lifecycle rather than mounting every operational workspace.
    detail(inventory.normalizedRegularSelection(selection))
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .background(DHDTheme.pageBackground)
  }

  private var identity: HPIdentity {
    HPIdentity(
      name: branding.name,
      shortName: branding.shortName,
      primary: branding.primary,
      secondary: branding.secondary
    )
  }

  private var sidebarColumnWidths: (minimum: CGFloat, ideal: CGFloat, maximum: CGFloat) {
    dynamicTypeSize.isAccessibilitySize
      ? (minimum: 280, ideal: 320, maximum: 360)
      : (minimum: 238, ideal: 272, maximum: 310)
  }

  private var selectionKey: Binding<String?> {
    Binding(
      get: { inventory.normalizedRegularSelection(selection).rawValue },
      set: { key in
        guard let key, let destination = inventory.destination(forWorkspaceKey: key) else { return }
        selection = destination
      }
    )
  }

  private func normalizeSelection() {
    selection = inventory.normalizedRegularSelection(selection)
  }
}

#if os(iOS)
/// `PageTabViewStyle` is the only system TabView presentation that emits no
/// regular-width or nested tab chrome. Programmatic selection remains enabled,
/// while this noninteractive marker disables only the enclosing UIKit paging
/// scroll view so the shell does not add a new swipe-navigation behavior or
/// steal horizontal gestures from charts and other destination content.
private struct HPPageSwipeLock: UIViewRepresentable {
  func makeUIView(context: Context) -> HPPageSwipeLockView {
    HPPageSwipeLockView()
  }

  func updateUIView(_ uiView: HPPageSwipeLockView, context: Context) {
    uiView.disableEnclosingPageScrollWhenReady()
  }
}

private final class HPPageSwipeLockView: UIView {
  override func didMoveToWindow() {
    super.didMoveToWindow()
    disableEnclosingPageScrollWhenReady()
  }

  func disableEnclosingPageScrollWhenReady() {
    DispatchQueue.main.async { [weak self] in
      var ancestor = self?.superview
      while let current = ancestor {
        if let scrollView = current as? UIScrollView, scrollView.isPagingEnabled {
          scrollView.isScrollEnabled = false
          return
        }
        ancestor = current.superview
      }
    }
  }
}
#endif
