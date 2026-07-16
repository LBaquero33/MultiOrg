import SwiftUI

/// Parent root: Children + Account.
struct ParentRootView: View {
  @EnvironmentObject private var appState: AppState
#if os(iOS)
  @State private var selection = Destination.children

  private enum Destination: Hashable {
    case children, chat, account
  }
#endif

  var body: some View {
#if os(iOS)
    TabView(selection: $selection) {
      ParentHomeView()
        .tabItem { Label(term("players", fallback: "Children"), systemImage: "person.2") }
        .tag(Destination.children)
      if feature("chat") {
        ChatChannelListView()
          .tabItem { Label("Chat", systemImage: "bubble.left.and.bubble.right") }
          .tag(Destination.chat)
      }
      NavigationStack { AccountView() }
        .tabItem { Label("Account", systemImage: "gearshape") }
        .tag(Destination.account)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .onChange(of: appState.requestedChatChannelId) { _, channelId in
      guard channelId != nil, feature("chat") else { return }
      selection = .chat
    }
    .task(id: appState.requestedChatChannelId) {
      guard appState.requestedChatChannelId != nil, feature("chat") else { return }
      selection = .chat
    }
#else
    ParentHomeView()
#endif
  }

  private func term(_ key: String, fallback: String) -> String {
    appState.activeOrgSettings?.term(key, fallback: fallback) ?? fallback
  }

  private func feature(_ key: String) -> Bool {
    appState.activeOrgSettings?.feature(key) ?? true
  }
}
