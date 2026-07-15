import SwiftUI

/// Shiny parity: coach sidebar has two primary destinations:
/// - Players (roster)
/// - Program Templates
struct CoachRootView: View {
  @EnvironmentObject private var appState: AppState

#if os(macOS)
  @State private var selection: Destination? = .players

  enum Destination: String, CaseIterable, Identifiable {
    case players = "Players"
    case facilities = "Facilities"
    case teams = "Teams"
    case programs = "Program Templates"
    case chat = "Chat"
    case admin = "Org Admin"
    case platform = "Platform Admin"
    case account = "Account"
    var id: String { rawValue }
  }

  var body: some View {
    NavigationSplitView {
      List(selection: $selection) {
        DHDOrgMenuHeader()
          .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 12, trailing: 8))
          .listRowBackground(Color.clear)
          .listRowSeparator(.hidden)
        NavigationLink(value: Destination.players) {
          Label(term("players", fallback: "Players"), systemImage: "person.3")
        }
        if feature("facilities") {
          NavigationLink(value: Destination.facilities) {
            Label(term("facilities", fallback: "Facilities"), systemImage: "calendar.badge.clock")
          }
        }
        NavigationLink(value: Destination.teams) {
          Label("Teams", systemImage: "person.3.sequence.fill")
        }
        if feature("programs") {
          NavigationLink(value: Destination.programs) {
            Label("\(term("program", fallback: "Program")) Templates", systemImage: "square.stack.3d.up")
          }
        }
        if feature("chat") {
          NavigationLink(value: Destination.chat) {
            Label("Chat", systemImage: "bubble.left.and.bubble.right")
          }
        }
        if appState.canAdminActiveOrg {
          NavigationLink(value: Destination.admin) {
            Label("Org Admin", systemImage: "slider.horizontal.3")
          }
        }
        if appState.isPlatformAdmin {
          NavigationLink(value: Destination.platform) {
            Label("Platform Admin", systemImage: "building.2.crop.circle")
          }
        }
        NavigationLink(value: Destination.account) {
          Label("Account", systemImage: "gearshape")
        }
      }
      .listStyle(.sidebar)
      .navigationTitle("Coach")
    } detail: {
      switch selection ?? .players {
      case .players:
        CoachHomeView()
      case .facilities:
        if feature("facilities") { CoachFacilitiesView() } else { disabledFeatureView("Facilities") }
      case .programs:
        if feature("programs") { CoachProgramsView() } else { disabledFeatureView("Programs") }
      case .chat:
        if feature("chat") { ChatChannelListView() } else { disabledFeatureView("Chat") }
      case .admin:
        OrgAdminConsoleView()
      case .teams:
        CoachTeamsView()
      case .platform:
        PlatformAdminDashboardView()
      case .account:
        AccountView()
      }
    }
    .onChange(of: appState.activeOrgAuthorizationKey) { _, _ in
      if selection == .admin && !appState.canAdminActiveOrg {
        selection = .players
      }
    }
  }

  private func term(_ key: String, fallback: String) -> String {
    appState.activeOrgSettings?.term(key, fallback: fallback) ?? fallback
  }

  private func feature(_ key: String) -> Bool {
    appState.activeOrgSettings?.feature(key) ?? true
  }

  private func disabledFeatureView(_ name: String) -> some View {
    VStack(spacing: 10) {
      Image(systemName: "switch.2")
        .font(.largeTitle)
        .foregroundStyle(DHDTheme.textSecondary)
      Text("\(name) is disabled")
        .font(.title3.weight(.semibold))
      Text("Turn it back on in Org Admin → Features.")
        .foregroundStyle(DHDTheme.textSecondary)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(DHDTheme.pageBackground)
  }
#else
  var body: some View {
    TabView {
      CoachHomeView()
        .tabItem { Label(term("players", fallback: "Players"), systemImage: "person.3") }
      if feature("facilities") {
        CoachFacilitiesView()
          .tabItem { Label(term("facilities", fallback: "Facilities"), systemImage: "calendar.badge.clock") }
      }
      NavigationStack { CoachTeamsView() }
        .tabItem { Label("Teams", systemImage: "person.3.sequence.fill") }
      if feature("chat") {
        ChatChannelListView()
          .tabItem { Label("Chat", systemImage: "bubble.left.and.bubble.right") }
      }
      if feature("programs") {
        CoachProgramsView()
          .tabItem { Label("\(term("program", fallback: "Program")) Templates", systemImage: "square.stack.3d.up") }
      }
      if appState.canAdminActiveOrg {
        NavigationStack { OrgAdminConsoleView() }
          .tabItem { Label("Org Admin", systemImage: "slider.horizontal.3") }
      }
      if appState.isPlatformAdmin {
        NavigationStack { PlatformAdminDashboardView() }
          .tabItem { Label("Platform", systemImage: "building.2.crop.circle") }
      }
      NavigationStack { AccountView() }
        .tabItem { Label("Account", systemImage: "gearshape") }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  private func term(_ key: String, fallback: String) -> String {
    appState.activeOrgSettings?.term(key, fallback: fallback) ?? fallback
  }

  private func feature(_ key: String) -> Bool {
    appState.activeOrgSettings?.feature(key) ?? true
  }
#endif
}
