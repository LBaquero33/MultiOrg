import SwiftUI

/// Player-facing Analysis is the shared analysis view targeted at the current user.
struct SDPlayerAnalysisView: View {
  @EnvironmentObject private var appState: AppState
  @State private var myId: UUID?
  @State private var errorText: String?
  @State private var isResolvingId = false

  var body: some View {
    Group {
      if let myId {
        BPAnalysisView(playerId: myId)
      } else if let errorText {
        HPStateScreenLayout { _ in
          HPCard {
            HPErrorState(
              message: errorText,
              onRetry: { Task { await loadId() } }
            )
          }
        }
      } else {
        HPStateScreenLayout { _ in
          HPCard {
            HPLoadingState(text: "Loading analysis…")
          }
        }
      }
    }
    .task(id: appState.supabase != nil) {
      guard myId == nil, errorText == nil else { return }
      await loadId()
    }
  }

  private func loadId() async {
    guard !isResolvingId, let supabase = appState.supabase else { return }
    isResolvingId = true
    errorText = nil
    defer { isResolvingId = false }
    do {
      let session = try await supabase.client.auth.session
      myId = session.user.id
    } catch {
      errorText = error.localizedDescription
    }
  }
}
