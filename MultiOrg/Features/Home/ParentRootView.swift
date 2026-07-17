import SwiftUI

/// Parent root: Children + Account.
struct ParentRootView: View {
  @EnvironmentObject private var appState: AppState
#if os(iOS)
  @State private var selection: HPAppNavigationDestination = .parentChildren
#endif

  var body: some View {
#if os(iOS)
    HPAdaptiveApplicationShell(
      role: .parent,
      roleSubtitle: "Parent workspace",
      inventory: navigationInventory,
      selection: $selection
    ) { destination in
      destinationView(destination)
    }
    .onChange(of: appState.requestedChatChannelId) { _, channelId in
      guard channelId != nil, feature("chat") else { return }
      selection = .chat
    }
    .task(id: appState.requestedChatChannelId) {
      guard appState.requestedChatChannelId != nil, feature("chat") else { return }
      selection = .chat
    }
#else
    HPApplicationIdentityShell(roleSubtitle: "Parent workspace") {
      ParentHomeView()
    }
#endif
  }

#if os(iOS)
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
    case .chat:
      if feature("chat") {
        ChatChannelListView()
      }
    case .account:
      NavigationStack { AccountView() }
    default:
      EmptyView()
    }
  }
#endif

  private func term(_ key: String, fallback: String) -> String {
    appState.activeOrgSettings?.term(key, fallback: fallback) ?? fallback
  }

  private func feature(_ key: String) -> Bool {
    appState.activeOrgSettings?.feature(key) ?? true
  }
}
