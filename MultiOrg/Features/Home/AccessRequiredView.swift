import SwiftUI

struct AccessRequiredView: View {
  @EnvironmentObject private var appState: AppState

  var body: some View {
    ScrollView {
      VStack(spacing: 14) {
      Image(systemName: "lock.shield")
        .font(.system(size: 44, weight: .semibold))
        .foregroundStyle(.secondary)

      Text("Access required")
        .font(.title3.weight(.semibold))

      Text("This player account needs an active Home Plate subscription or organization-granted access.")
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)

      if let playerId = appState.myProfile?.id {
        DHDCard {
          PlayerSubscriptionPaywall(playerId: playerId)
        }
      }
      }
      .padding()
      .frame(maxWidth: 640)
      .frame(maxWidth: .infinity)
    }
    .background(DHDTheme.pageBackground.ignoresSafeArea())
  }
}
