import SwiftUI

/// Parent root: Children + Account.
struct ParentRootView: View {
  @EnvironmentObject private var appState: AppState

  var body: some View {
#if os(iOS)
    TabView {
      ParentHomeView()
        .tabItem { Label(term("players", fallback: "Children"), systemImage: "person.2") }
      if feature("chat") {
        ChatChannelListView()
          .tabItem { Label("Chat", systemImage: "bubble.left.and.bubble.right") }
      }
      NavigationStack { AccountView() }
        .tabItem { Label("Account", systemImage: "gearshape") }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
