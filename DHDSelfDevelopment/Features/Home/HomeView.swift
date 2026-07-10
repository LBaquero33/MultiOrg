import SwiftUI

struct HomeView: View {
  @EnvironmentObject private var appState: AppState

  var body: some View {
    Group {
      if let profile = appState.myProfile {
        if profile.isCoach {
          CoachRootView()
        } else if profile.isParent {
          ParentRootView()
        } else {
          if appState.needsAccess {
            AccessRequiredView()
          } else {
            PlayerHomeView()
          }
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
