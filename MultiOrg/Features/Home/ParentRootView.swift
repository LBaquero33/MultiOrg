import SwiftUI

/// Parent root: Children, calendar, chat, and account.
struct ParentRootView: View {
  @EnvironmentObject private var appState: AppState
  @State private var selection: HPAppNavigationDestination = .parentChildren

  var body: some View {
    Group {
#if os(iOS)
      HPAdaptiveApplicationShell(
        role: .parent,
        roleSubtitle: "Parent workspace",
        inventory: navigationInventory,
        selection: $selection
      ) { destination in
        destinationView(destination)
      }
#else
      HPRegularApplicationShell(
        role: .parent,
        inventory: navigationInventory,
        selection: $selection
      ) { destination in
        destinationView(destination)
      }
#endif
    }
    .onChange(of: appState.requestedChatChannelId) { _, channelId in
      guard channelId != nil, feature("chat") else { return }
      selection = .chat
    }
    .task(id: appState.requestedChatChannelId) {
      guard appState.requestedChatChannelId != nil, feature("chat") else { return }
      selection = .chat
    }
  }

  private var navigationInventory: HPAppNavigationInventory {
    .parent(
      childrenTitle: term("players", fallback: "Children"),
      chatEnabled: feature("chat")
    )
  }

  @ViewBuilder
  private func destinationView(_ destination: HPAppNavigationDestination) -> some View {
    switch destination {
    case .parentChildren:
      ParentHomeView()
    case .parentCalendar:
      GameCalendarView()
    case .chat:
      if feature("chat") {
        ChatChannelListView()
      }
    case .account:
#if os(iOS)
      NavigationStack { AccountView() }
#else
      AccountView()
#endif
    default:
      EmptyView()
    }
  }

  private func term(_ key: String, fallback: String) -> String {
    appState.activeOrgSettings?.term(key, fallback: fallback) ?? fallback
  }

  private func feature(_ key: String) -> Bool {
    appState.activeOrgSettings?.feature(key) ?? true
  }
}
