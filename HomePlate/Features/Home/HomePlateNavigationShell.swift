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
  case playerProgram
  case playerTrends
  case playerTesting
  case playerAnalysis
  case playerFacilities
  case playerDevelopment

  case parentHome
  case parentChildren
  case parentCalendar

  case coachToday
  case coachTeam
  case coachSchedule
  case coachPlayers
  case coachCalendar
  case coachFacilities
  case coachTeams
  case coachPrograms
  case games

  case chat
  case payments
  case finance
  case organizationAdmin
  case platformAdmin
  case account

  var id: String { rawValue }

  var workspaceScope: HPWorkspaceScope {
    switch self {
    case .directory, .account: .account
    case .playerToday, .playerCalendar, .playerProgram, .playerTrends, .playerTesting,
         .playerAnalysis, .playerDevelopment:
      .selectedPlayer
    case .playerFacilities, .coachFacilities, .coachSchedule, .coachCalendar,
         .parentCalendar:
      .scheduleFilter
    case .parentHome, .parentChildren:
      .selectedChild
    case .coachToday:
      .allAssignedTeams
    case .coachTeam:
      .selectedTeam
    case .coachPlayers, .coachTeams, .coachPrograms, .games, .chat, .payments, .finance,
         .organizationAdmin:
      .organization
    case .platformAdmin:
      .platform
    }
  }

  static func routeDestination(for key: String) -> Self? {
    if ["currentteam", "current_team", "current-team"].contains(key.lowercased()) {
      return .coachTeam
    }
    return Self(rawValue: key)
  }
}

struct HPAppNavigationItem: Identifiable, Equatable {
  let destination: HPAppNavigationDestination
  let title: String
  let systemImage: String
  let workspaceScope: HPWorkspaceScope

  init(
    destination: HPAppNavigationDestination,
    title: String,
    systemImage: String,
    workspaceScope: HPWorkspaceScope? = nil
  ) {
    self.destination = destination
    self.title = title
    self.systemImage = systemImage
    self.workspaceScope = workspaceScope ?? destination.workspaceScope
  }

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

/// A single role inventory rendered as the website-matched mobile menu or
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
    guard let destination = HPAppNavigationDestination.routeDestination(for: key) else { return nil }
    return regularItems.first { $0.destination == destination }?.destination
      ?? directoryItems.first { $0.destination == destination }?.destination
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
    let program = item(.playerProgram, "Program", "square.stack.3d.up.fill")
    let trends = item(.playerTrends, "Progress", "chart.line.uptrend.xyaxis")
    let chat = item(.chat, "Messages", "bubble.left.and.bubble.right")
    let facilities = item(.playerFacilities, facilitiesTitle, "building.2")
    let account = item(.account, "Account", "person.crop.circle")
    let websiteItems = [today, calendar]
      + (facilitiesEnabled ? [facilities] : [])
      + [program, trends]
      + (chatEnabled ? [chat] : [])
      + [account]
    let regular = [HPAppNavigationSection(title: nil, items: websiteItems)]

    return Self(
      compactItems: [],
      directorySections: [],
      regularSections: regular,
      defaultDestination: .playerToday
    )
  }

  static func parent(childrenTitle: String, chatEnabled: Bool) -> Self {
    let home = item(.parentHome, "Home", "house")
    let children = item(.parentChildren, childrenTitle, "person.2")
    let calendar = item(.parentCalendar, "Calendar", "calendar")
    let chat = item(.chat, "Messages", "bubble.left.and.bubble.right")
    let payments = item(.payments, "Payments", "creditcard")
    let account = item(.account, "Account", "person.crop.circle")
    let websiteItems = [home, children, calendar, payments]
      + (chatEnabled ? [chat] : [])
      + [account]
    return Self(
      compactItems: [],
      directorySections: [],
      regularSections: [HPAppNavigationSection(title: nil, items: websiteItems)],
      defaultDestination: .parentHome
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
    paymentsEnabled: Bool = false,
    canAdministerOrganization: Bool,
    isPlatformAdmin: Bool
  ) -> Self {
    let home = item(.coachToday, "Home", "house")
    let calendar = item(.coachCalendar, "Calendar", "calendar")
    let teams = item(.coachTeams, "Teams", "person.3")
    let facilities = item(.coachFacilities, facilitiesTitle, "building.2")
    let payments = item(.payments, "Payments", "creditcard")
    let programs = item(.coachPrograms, "Programs & Player Development", "list.clipboard")
    let games = item(.games, "Games", "trophy")
    let chat = item(.chat, "Messages", "bubble.left.and.bubble.right")
    let organization = item(.organizationAdmin, "Organization Settings", "gearshape")
    let platform = item(.platformAdmin, "Platform Admin", "building.2.crop.circle")
    let account = item(.account, "Account", "person.crop.circle")
    let compactItems = [home, teams, calendar] + (programsEnabled ? [programs] : [])
    let teamOperations = (facilitiesEnabled ? [facilities] : []) + [games]
    let communication = chatEnabled ? [chat] : []
    let administration = (paymentsEnabled ? [payments] : [])
      + (canAdministerOrganization ? [organization] : [])
      + (isPlatformAdmin ? [platform] : [])
      + [account]
    let directorySections = [
      HPAppNavigationSection(title: "Team Operations", items: teamOperations),
      HPAppNavigationSection(title: "Communication", items: communication),
      HPAppNavigationSection(title: "Administration", items: administration),
    ].filter { !$0.items.isEmpty }
    let regularSections = [
      HPAppNavigationSection(title: "Daily Work", items: [home, calendar]),
      HPAppNavigationSection(
        title: "Team Operations",
        items: [teams] + (programsEnabled ? [programs] : []) + teamOperations
      ),
      HPAppNavigationSection(title: "Communication", items: communication),
      HPAppNavigationSection(title: "Administration", items: administration),
    ].filter { !$0.items.isEmpty }

    return Self(
      compactItems: compactItems,
      directorySections: directorySections,
      regularSections: regularSections,
      defaultDestination: .coachToday
    )
  }

  static func owner(
    facilitiesTitle: String,
    programsTitle: String,
    facilitiesEnabled: Bool,
    chatEnabled: Bool,
    programsEnabled: Bool,
    isPlatformAdmin: Bool
  ) -> Self {
    staff(
      playersTitle: "Players",
      facilitiesTitle: facilitiesTitle,
      programsTitle: programsTitle,
      facilitiesEnabled: facilitiesEnabled,
      chatEnabled: chatEnabled,
      programsEnabled: programsEnabled,
      paymentsEnabled: true,
      canAdministerOrganization: true,
      isPlatformAdmin: isPlatformAdmin
    )
  }

  static func platformOnly() -> Self {
    let platform = item(.platformAdmin, "Platform Admin", "building.2.crop.circle")
    let account = item(.account, "Account", "gearshape")
    return Self(
      compactItems: [],
      directorySections: [],
      regularSections: [HPAppNavigationSection(title: nil, items: [platform, account])],
      defaultDestination: .platformAdmin
    )
  }

  private static func item(
    _ destination: HPAppNavigationDestination,
    _ title: String,
    _ systemImage: String,
    workspaceScope: HPWorkspaceScope? = nil
  ) -> HPAppNavigationItem {
    HPAppNavigationItem(
      destination: destination,
      title: title,
      systemImage: systemImage,
      workspaceScope: workspaceScope
    )
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
  @EnvironmentObject private var appState: AppState
  @Environment(\.dhdOrgBranding) private var branding
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass
  @State private var menuIsOpen = false

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
          teamScopeControl: sidebarTeamScopeControl,
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
        showsIdentity: false
      ) {
        VStack(spacing: 0) {
          if !isRegular {
            mobileHeader
          }

          GeometryReader { proxy in
            ZStack(alignment: .leading) {
              retainedDestinationHost

              if !isRegular && menuIsOpen {
                Color.black.opacity(0.34)
                  .ignoresSafeArea()
                  .contentShape(Rectangle())
                  .onTapGesture { closeMobileMenu() }
                  .transition(.opacity)

                mobileMenu
                  .frame(width: min(proxy.size.width * 0.88, 380))
                  .transition(.move(edge: .leading).combined(with: .opacity))
                  .gesture(
                    DragGesture(minimumDistance: 12)
                      .onEnded { value in
                        if value.translation.width < -50 {
                          closeMobileMenu()
                        }
                      }
                  )
              }
            }
          }

          if !isRegular && usesBottomNavigation {
            mobileBottomBar
          }
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
    dynamicTypeSize.isAccessibilitySize ? 320 : 288
  }

  private var usesBottomNavigation: Bool {
    !inventory.compactItems.isEmpty
  }

  private var retainedDestinationHost: some View {
    retainedDestination(selection)
      .id(selection)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(DHDTheme.pageBackground)
  }

  private func retainedDestination(
    _ destination: HPAppNavigationDestination
  ) -> some View {
    destinationContent(destination)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  private var mobileHeader: some View {
    HStack(spacing: HP.Space.sm) {
      Button {
        toggleMobileMenu()
      } label: {
        Image(systemName: menuIsOpen ? "xmark" : "line.3.horizontal")
          .font(.system(size: 22, weight: .medium))
          .foregroundStyle(HP.Color.text)
          .frame(width: 44, height: 44)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel(menuIsOpen ? "Close menu" : "Open menu")

      organizationBadge
      Text(branding.name)
        .font(HP.Font.headline)
        .foregroundStyle(HP.Color.text)
        .lineLimit(1)
      if showsTeamScopeControl {
        teamScopeMenu(compact: true)
      }
      Spacer(minLength: HP.Space.xs)
    }
    .padding(.horizontal, HP.Space.md)
    .padding(.vertical, HP.Space.xs)
    .background(HP.Color.bg.opacity(0.98))
    .overlay(alignment: .bottom) {
      Rectangle().fill(HP.Color.border).frame(height: 1)
    }
  }

  private var mobileMenu: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: HP.Space.sm) {
        organizationSwitcher
        if showsTeamScopeControl {
          teamScopeMenu(compact: false)
        }

        ForEach(mobileMenuSections) { section in
          VStack(alignment: .leading, spacing: 4) {
            if let title = section.title {
              Text(title)
                .font(HP.Font.caption.weight(.bold))
                .foregroundStyle(HP.Color.textMuted)
                .textCase(.uppercase)
                .padding(.horizontal, HP.Space.sm)
                .padding(.top, HP.Space.xs)
            }
            ForEach(section.items) { item in
              mobileMenuRow(item)
            }
          }
        }

        Button(role: .destructive) {
          Task { await appState.signOut() }
        } label: {
          Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
            .font(HP.Font.body.weight(.medium))
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            .padding(.horizontal, HP.Space.sm)
        }
        .buttonStyle(.plain)
        .foregroundStyle(HP.Color.textMuted)
        .padding(.top, 4)
      }
      .padding(HP.Space.md)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .background(HP.Color.surface)
  }

  private var mobileMenuSections: [HPAppNavigationSection] {
    usesBottomNavigation ? inventory.directorySections : inventory.regularSections
  }

  private var mobileBottomBar: some View {
    HStack(spacing: 0) {
      ForEach(inventory.compactItems) { item in
        mobileBottomButton(item)
      }
      Button {
        toggleMobileMenu()
      } label: {
        VStack(spacing: 3) {
          Image(systemName: "ellipsis.circle")
            .font(.system(size: 20, weight: .medium))
          Text("More")
            .font(HP.Font.eyebrow)
            .lineLimit(1)
        }
        .foregroundStyle(menuIsOpen || inventory.isDirectoryItem(selection) ? HP.Color.accent : HP.Color.textMuted)
        .frame(maxWidth: .infinity, minHeight: 50)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel("More")
      .accessibilityValue(menuIsOpen ? "Open" : "Closed")
    }
    .padding(.horizontal, HP.Space.xs)
    .padding(.top, 4)
    .background(HP.Color.bg.opacity(0.98))
    .overlay(alignment: .top) {
      Rectangle().fill(HP.Color.border).frame(height: 1)
    }
  }

  private func mobileBottomButton(_ item: HPAppNavigationItem) -> some View {
    let selected = selection == item.destination && !menuIsOpen
    return Button {
      selection = item.destination
      withAnimation(HP.Motion.quick) { menuIsOpen = false }
    } label: {
      VStack(spacing: 3) {
        Image(systemName: item.systemImage)
          .font(.system(size: 20, weight: .medium))
        Text(item.title)
          .font(HP.Font.eyebrow)
          .lineLimit(1)
          .minimumScaleFactor(0.75)
      }
      .foregroundStyle(selected ? HP.Color.accent : HP.Color.textMuted)
      .frame(maxWidth: .infinity, minHeight: 50)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
  }

  private func toggleMobileMenu() {
    withAnimation(HP.Motion.quick) { menuIsOpen.toggle() }
  }

  private func closeMobileMenu() {
    withAnimation(HP.Motion.quick) { menuIsOpen = false }
  }

  private var organizationSwitcher: some View {
    Group {
      if appState.availableOrganizations.count <= 1 {
        Text(branding.name)
          .font(HP.Font.body.weight(.semibold))
          .foregroundStyle(HP.Color.text)
          .lineLimit(1)
          .padding(.horizontal, HP.Space.sm)
          .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
      } else {
        Menu {
          ForEach(appState.availableOrganizations) { organization in
            Button {
              Task {
                await appState.switchActiveOrganization(to: organization.id)
                menuIsOpen = false
              }
            } label: {
              if organization.id == appState.activeOrgId {
                Label(organization.displayName, systemImage: "checkmark")
              } else {
                Text(organization.displayName)
              }
            }
          }
        } label: {
          HStack(spacing: HP.Space.sm) {
            Text(branding.name)
              .font(HP.Font.body.weight(.semibold))
              .foregroundStyle(HP.Color.text)
              .lineLimit(1)
            Spacer()
            Image(systemName: "chevron.up.chevron.down")
              .font(.caption.weight(.semibold))
              .foregroundStyle(HP.Color.textMuted)
          }
          .padding(.horizontal, HP.Space.sm)
          .frame(minHeight: 44)
          .background(HP.Color.surfaceRaised)
          .clipShape(RoundedRectangle(cornerRadius: HP.Radius.sm, style: .continuous))
          .overlay {
            RoundedRectangle(cornerRadius: HP.Radius.sm, style: .continuous)
              .strokeBorder(HP.Color.input, lineWidth: 1)
          }
        }
        .buttonStyle(.plain)
      }
    }
  }

  private var organizationBadge: some View {
    Group {
      if let logoURL = branding.logoURL {
        AsyncImage(url: logoURL) { image in
          image.resizable().scaledToFit()
        } placeholder: {
          Text(String(branding.shortName.prefix(2)).uppercased())
        }
      } else {
        Text(String(branding.shortName.prefix(2)).uppercased())
      }
    }
    .font(HP.Font.caption.weight(.bold))
    .foregroundStyle(Color.white)
    .frame(width: 36, height: 36)
    .background(branding.primary)
    .clipShape(RoundedRectangle(cornerRadius: HP.Radius.sm, style: .continuous))
  }

  private var activeTeamScopes: [SDTeamOperationsTeam] {
    appState.authorizedScheduleTeams
      .filter(\.is_active)
      .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
  }

  private var showsTeamScopeControl: Bool {
    let canSelectTeam = role == .coach || role == .owner
    return canSelectTeam && !activeTeamScopes.isEmpty
  }

  private var sidebarTeamScopeControl: AnyView? {
    guard showsTeamScopeControl else { return nil }
    return AnyView(teamScopeMenu(compact: false))
  }

  private func teamScopeMenu(compact: Bool) -> some View {
    Menu {
      Button {
        appState.selectAllTeams()
      } label: {
        if appState.selectedTeamId == nil {
          Label("All Teams", systemImage: "checkmark")
        } else {
          Text("All Teams")
        }
      }
      ForEach(activeTeamScopes) { team in
        Button {
          appState.selectTeam(team.id)
        } label: {
          if appState.selectedTeamId == team.id {
            Label(team.name, systemImage: "checkmark")
          } else {
            Text(team.name)
          }
        }
      }
    } label: {
      HStack(spacing: HP.Space.xs) {
        Image(systemName: "person.3")
        Text(appState.selectedTeam?.name ?? "All Teams")
          .lineLimit(1)
        Image(systemName: "chevron.up.chevron.down")
          .font(.caption2.weight(.bold))
      }
      .font(compact ? HP.Font.caption.weight(.semibold) : HP.Font.body.weight(.semibold))
      .foregroundStyle(HP.Color.text)
      .padding(.horizontal, compact ? HP.Space.xs : HP.Space.sm)
      .frame(minHeight: 40)
      .background(HP.Color.surfaceRaised)
      .clipShape(RoundedRectangle(cornerRadius: HP.Radius.sm, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: HP.Radius.sm, style: .continuous)
          .strokeBorder(HP.Color.input, lineWidth: 1)
      }
    }
    .buttonStyle(.plain)
    .accessibilityLabel("Team workspace")
    .accessibilityValue(appState.selectedTeam?.name ?? "All Teams")
  }

  private func mobileMenuRow(_ item: HPAppNavigationItem) -> some View {
    let selected = selection == item.destination
    return Button {
      selection = item.destination
      withAnimation(HP.Motion.quick) { menuIsOpen = false }
    } label: {
      HStack(spacing: HP.Space.sm) {
        Image(systemName: item.systemImage)
          .font(.system(size: 20, weight: .regular))
          .frame(width: 20)
        Text(item.title)
          .font(HP.Font.body.weight(.medium))
        Spacer()
      }
      .foregroundStyle(selected ? HP.Color.text : HP.Color.textMuted)
      .padding(.horizontal, HP.Space.sm)
      .padding(.vertical, 12)
      .background(selected ? HP.Color.surfaceRaised : .clear)
      .clipShape(RoundedRectangle(cornerRadius: HP.Radius.sm, style: .continuous))
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
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
    #if os(macOS)
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        NotificationBellButton()
      }
    }
    #endif
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
      : (minimum: 288, ideal: 288, maximum: 288)
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
