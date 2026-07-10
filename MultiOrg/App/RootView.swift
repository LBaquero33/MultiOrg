import SwiftUI

struct RootView: View {
  @EnvironmentObject private var appState: AppState
  @Environment(\.scenePhase) private var scenePhase

  var body: some View {
    Group {
      #if os(iOS)
      MobileRootView {
        content
      }
      .preferredColorScheme(.dark)
      #else
      DesktopRootView {
        content
      }
      #endif
    }
    .dhdToast($appState.globalToastText)
    .onChange(of: scenePhase) { _, next in
      guard next == .active else { return }
      // When returning from the Stripe browser, refresh entitlement automatically.
      guard appState.isAuthenticated, appState.myProfile?.isPlayer == true else { return }
      if AppFlags.bypassAccessCheck { return }
      Task { await appState.refreshEntitlement() }
    }
  }

  @ViewBuilder
  private var content: some View {
    if let configError = appState.configError {
      ConfigErrorView(message: configError)
    } else if appState.isAuthenticated {
      HomeView()
    } else {
      LoginView()
    }
  }
}

#if os(iOS)
private struct MobileRootView<Content: View>: View {
  let content: Content

  init(@ViewBuilder content: () -> Content) {
    self.content = content()
  }

  var body: some View {
    GeometryReader { proxy in
      ZStack(alignment: .topLeading) {
        DHDTheme.pageBackground
          .ignoresSafeArea()

        content
          .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
          .ignoresSafeArea(.keyboard, edges: .bottom)
      }
      .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
    }
  }
}
#else
private struct DesktopRootView<Content: View>: View {
  let content: Content

  init(@ViewBuilder content: () -> Content) {
    self.content = content()
  }

  var body: some View {
    content
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .background(DHDTheme.pageBackground.ignoresSafeArea())
  }
}
#endif
