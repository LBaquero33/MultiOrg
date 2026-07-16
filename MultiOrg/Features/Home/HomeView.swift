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
          NavigationStack {
            PlatformAdminDashboardView()
          }
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
