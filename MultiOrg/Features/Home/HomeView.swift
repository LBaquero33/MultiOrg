import SwiftUI

struct HomeView: View {
  @EnvironmentObject private var appState: AppState

  var body: some View {
    Group {
      if appState.myProfile != nil {
        switch SDAuthenticatedWorkspace.resolve(
          membership: appState.activeOrgMembership,
          isPlatformAdmin: appState.isPlatformAdmin
        ) {
        case .staff:
          CoachRootView()
        case .parent:
          ParentRootView()
        case .player:
          if appState.needsAccess {
            AccessRequiredView()
          } else {
            PlayerHomeView()
          }
        case .platformOnly:
          PlatformRootView()
        case .unavailable:
          ContentUnavailableView(
            "No active organization membership",
            systemImage: "building.2.crop.circle",
            description: Text("Organization access comes from your active membership in the selected organization.")
          )
        }
      } else {
        VStack(spacing: 12) {
          ProgressView()
          Text("Loading your profile…")
            .foregroundStyle(.secondary)
          if let msg = appState.profileLoadError, !msg.isEmpty {
            Text(msg)
              .font(.footnote)
              .foregroundStyle(.red)
              .multilineTextAlignment(.center)
              .padding(.top, 4)
          }
          Button("Retry") {
            Task { await appState.loadMyProfile() }
          }
          .buttonStyle(.bordered)
          Button(role: .destructive) {
            Task { await appState.signOut() }
          } label: {
            Text("Sign Out")
          }
        }
        .padding()
      }
    }
  }
}

/// Platform authorization remains supplied exclusively by `AppState`; this
/// shell adds only the same Home Plate navigation presentation and an Account
/// escape route for platform-only users.
private struct PlatformRootView: View {
  @State private var selection: HPAppNavigationDestination = .platformAdmin

  private let inventory = HPAppNavigationInventory.platformOnly()

  var body: some View {
#if os(iOS)
    HPAdaptiveApplicationShell(
      role: .platformAdmin,
      roleSubtitle: "Platform admin workspace",
      inventory: inventory,
      selection: $selection
    ) { destination in
      destinationView(destination)
    }
#else
    regularShell
#endif
  }

  private var regularShell: some View {
    HPRegularApplicationShell(
      role: .platformAdmin,
      inventory: inventory,
      selection: $selection
    ) { destination in
      destinationView(destination)
    }
  }

  @ViewBuilder
  private func destinationView(_ destination: HPAppNavigationDestination) -> some View {
    switch destination {
    case .platformAdmin:
#if os(macOS)
      PlatformAdminDashboardView()
#else
      NavigationStack { PlatformAdminDashboardView() }
#endif
    case .account:
#if os(macOS)
      AccountView()
#else
      NavigationStack { AccountView() }
#endif
    default:
      PlatformAdminDashboardView()
    }
  }
}
