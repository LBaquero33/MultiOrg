import SwiftUI

struct AccessRequiredView: View {
  @EnvironmentObject private var appState: AppState

  var body: some View {
    HPStateScreenLayout { _ in
      HPCard {
        VStack(spacing: HP.Space.md) {
          Image(systemName: "lock.shield")
            .font(.system(size: 44, weight: .semibold))
            .foregroundStyle(HP.Color.textMuted)
            .accessibilityHidden(true)

          Text("Access required")
            .font(HP.Font.title)
            .tracking(HP.Font.titleTracking)
            .foregroundStyle(HP.Color.text)
            .multilineTextAlignment(.center)
            .accessibilityAddTraits(.isHeader)

          Text("This player account needs an active Home Plate subscription or organization-granted access.")
            .font(HP.Font.callout)
            .foregroundStyle(HP.Color.textMuted)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)

          if let playerId = appState.myProfile?.id {
            PlayerSubscriptionPaywall(playerId: playerId)
          }
        }
      }
    }
  }
}
