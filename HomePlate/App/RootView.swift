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
      #else
      DesktopRootView {
        content
      }
      #endif
    }
    .environment(\.dhdOrgBranding, activeBranding)
    .tint(DHDTheme.accent)
    .dhdToast($appState.globalToastText)
    #if os(iOS)
    .safeAreaInset(edge: .top, spacing: 0) {
      if appState.isAuthenticated {
        HStack {
          Spacer(minLength: 0)
          NotificationBellButton()
            .environmentObject(appState)
        }
        .padding(.horizontal, HP.Space.md)
        .padding(.vertical, HP.Space.xs)
        .background(HP.Color.bg)
        .overlay(alignment: .bottom) {
          Rectangle()
            .fill(HP.Color.border)
            .frame(height: 1)
            .allowsHitTesting(false)
        }
      }
    }
    #endif
    .onChange(of: scenePhase) { _, next in
      guard next == .active else { return }
      guard appState.isAuthenticated else { return }
      Task {
        await appState.configurePushNotifications()
        await appState.refreshPlatformFeatureFlags()
        // Platform support is server-authorized and may have changed while the
        // app was backgrounded. Refresh it before navigation or controls gate
        // on the cached value.
        await appState.refreshPlatformAdminStatus()
        guard appState.myProfile?.isPlayer == true, !AppFlags.bypassAccessCheck else { return }
        await appState.refreshEntitlement()
      }
    }
    .task(id: pushConfigurationKey) {
      await appState.configurePushNotifications()
    }
    .onOpenURL { url in
      Task { await appState.handleAppURL(url) }
    }
    .sheet(item: $appState.requestedNotification) { notification in
      NavigationStack {
        NotificationDestinationView(notification: notification)
          .environmentObject(appState)
      }
      #if os(macOS)
      .frame(minWidth: 480, minHeight: 420)
      #endif
    }
    .sheet(isPresented: Binding(
      get: { appState.isAuthenticated && appState.pendingInvitation != nil },
      set: { if !$0 { appState.dismissPendingInvitation() } }
    )) {
      PendingOrganizationInvitationView()
        .environmentObject(appState)
      #if os(macOS)
      .frame(minWidth: 480, minHeight: 360)
      #endif
    }
  }

  private var pushConfigurationKey: String {
    "\(appState.isAuthenticated):\(appState.myProfile?.id.uuidString.lowercased() ?? "none")"
  }

  private var activeBranding: DHDOrgBranding {
    guard let settings = appState.activeOrgSettings else { return .fallback }
    let name = settings.display_name ?? settings.short_name ?? "Home Plate"
    let shortName = settings.short_name ?? settings.display_name ?? "Home Plate"
    let logoURL = settings.logo_path.flatMap { appState.supabase?.publicOrganizationLogoURL(path: $0) }
    return DHDOrgBranding(
      name: name,
      shortName: shortName,
      primary: DHDTheme.color(hex: settings.primary_color_hex, fallback: DHDTheme.navy),
      secondary: DHDTheme.color(hex: settings.secondary_color_hex, fallback: DHDTheme.navy2),
      accent: DHDTheme.color(hex: settings.accent_color_hex, fallback: DHDTheme.accent),
      logoURL: logoURL
    )
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
    ZStack(alignment: .topLeading) {
      DHDTheme.pageBackground
        .ignoresSafeArea()

      content
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
