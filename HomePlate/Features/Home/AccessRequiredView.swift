import SwiftUI

struct AccessRequiredView: View {
  @EnvironmentObject private var appState: AppState
  let orgId: UUID
  @State private var hasAccess: Bool?

  var body: some View {
    Group {
      if hasAccess == true {
        PlayerHomeView()
      } else if hasAccess == false {
        VStack(spacing: HP.Space.md) {
          Text("Player access could not be verified for this organization.")
          Button("Try again") { Task { await verifyAccess() } }
          Button("Sign out") { Task { await appState.signOut() } }
        }
      } else {
        ProgressView("Checking player access")
      }
    }
    .task { await verifyAccess() }
  }

  private func verifyAccess() async {
    guard let api = appState.supabase else { hasAccess = false; return }
    do {
      hasAccess = try await api.hasFreePlayerAccess(orgId: orgId)
    } catch {
      hasAccess = false
    }
  }
}
