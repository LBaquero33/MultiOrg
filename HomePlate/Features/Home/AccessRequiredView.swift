import SwiftUI

struct AccessRequiredView: View {
  @EnvironmentObject private var appState: AppState
  let orgId: UUID
  let playerId: UUID
  @State private var hasAccess: Bool?
  @State private var showingPreviousPurchases = false

  var body: some View {
    Group {
      if hasAccess == true {
        PlayerHomeView()
      } else if hasAccess == false {
        VStack(spacing: HP.Space.md) {
          Text("Player access could not be verified for this organization.")
          Button("Try again") { Task { await verifyAccess() } }
          Link("Manage existing Apple subscriptions", destination: URL(string: "https://apps.apple.com/account/subscriptions")!)
          Button("Restore a previous Apple purchase") { showingPreviousPurchases = true }
          Button("Sign out") { Task { await appState.signOut() } }
        }
      } else {
        ProgressView("Checking player access")
      }
    }
    .sheet(isPresented: $showingPreviousPurchases, onDismiss: { Task { await verifyAccess() } }) {
      PlayerSubscriptionPaywall(playerId: playerId)
    }
    .task { await verifyAccess() }
  }

  private func verifyAccess() async {
    guard let api = appState.supabase else { hasAccess = false; return }
    do {
      hasAccess = try await api.hasFreePlayerAccess(orgId: orgId)
    } catch {
      hasAccess = (try? await api.fetchAccessEntitlement(userId: playerId))?.is_active == true
    }
  }
}
