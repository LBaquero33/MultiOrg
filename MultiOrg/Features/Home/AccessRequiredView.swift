import SwiftUI

struct AccessRequiredView: View {
  @EnvironmentObject private var appState: AppState

  @ViewBuilder
  var body: some View {
    if let playerId = appState.myProfile?.id {
      PlayerSubscriptionPaywall(playerId: playerId)
    } else {
      HPStateScreenLayout(widthMode: .compact) { _ in
        HPCard {
          VStack(spacing: HP.Space.md) {
            HPEmptyState(
              title: "Access required",
              message: "Home Plate couldn’t verify the player account for this session. Sign in again before managing access.",
              systemImage: "lock.shield"
            )
            HPButton(
              title: "Sign Out",
              systemImage: "rectangle.portrait.and.arrow.right",
              variant: .primary,
              size: .lg,
              fullWidth: true
            ) {
              Task { await appState.signOut() }
            }
          }
        }
      }
    }
  }
}
