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
          HPStateScreenLayout { _ in
            HPCard {
              VStack(spacing: HP.Space.sm) {
                HPEmptyState(
                  title: "No active organization membership",
                  message: "Organization access comes from your active membership in the selected organization.",
                  systemImage: "building.2.crop.circle"
                )

                if !alternativeOrganizations.isEmpty {
                  Menu {
                    ForEach(alternativeOrganizations) { organization in
                      Button {
                        Task { await appState.switchActiveOrganization(to: organization.id) }
                      } label: {
                        Label(organization.displayName, systemImage: "building.2")
                      }
                    }
                  } label: {
                    Label("Switch Organization", systemImage: "arrow.left.arrow.right")
                  }
                  .buttonStyle(HPButtonStyle(variant: .secondary, size: .md, fullWidth: true))
                  .frame(maxWidth: .infinity, minHeight: 44)
                  .contentShape(Rectangle())
                }

                HPButton(
                  title: "Sign Out",
                  variant: .destructive,
                  size: .md,
                  fullWidth: true,
                  action: { Task { await appState.signOut() } }
                )
              }
            }
          }
        }
      } else {
        HPStateScreenLayout { _ in
          HPCard {
            VStack(spacing: HP.Space.sm) {
              HPLoadingState(text: "Loading your profile…")

              if let message = appState.profileLoadError, !message.isEmpty {
                HPErrorState(
                  title: "Profile unavailable",
                  message: message,
                  onRetry: { Task { await appState.loadMyProfile() } }
                )
              } else {
                HPButton(
                  title: "Retry",
                  systemImage: "arrow.clockwise",
                  variant: .secondary,
                  size: .md,
                  action: { Task { await appState.loadMyProfile() } }
                )
              }

              HPButton(
                title: "Sign Out",
                variant: .destructive,
                size: .md,
                action: { Task { await appState.signOut() } }
              )
            }
          }
        }
      }
    }
  }

  private var alternativeOrganizations: [SDOrg] {
    appState.availableOrganizations.filter { $0.id != appState.activeOrgId }
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
