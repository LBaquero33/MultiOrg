import SwiftUI

/// Player-facing Analysis is the shared analysis view targeted at the current user.
struct SDPlayerAnalysisView: View {
  @EnvironmentObject private var appState: AppState
  @State private var myId: UUID?
  @State private var errorText: String?

  var body: some View {
    Group {
      if let myId {
        BPAnalysisView(playerId: myId)
      } else {
        VStack(spacing: 12) {
          ProgressView()
          Text("Loading…").foregroundStyle(.secondary)
        }
        .task { await loadId() }
      }
    }
    .alert("Error", isPresented: Binding(get: { errorText != nil }, set: { _ in errorText = nil })) {
      Button("OK", role: .cancel) {}
    } message: { Text(errorText ?? "") }
  }

  private func loadId() async {
    guard let supabase = appState.supabase else { return }
    do {
      let session = try await supabase.client.auth.session
      myId = session.user.id
    } catch {
      errorText = error.localizedDescription
    }
  }
}
