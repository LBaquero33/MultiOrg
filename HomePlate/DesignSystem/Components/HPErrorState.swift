import SwiftUI

/// Designed error state — human message + optional retry. Never surface a raw
/// `error.localizedDescription` as the entire UI. Evolves from
/// `FinanceErrorState`.
struct HPErrorState: View {
  var title: String = "Something went wrong"
  let message: String
  var retryTitle: String = "Retry"
  var onRetry: (() -> Void)? = nil

  var body: some View {
    VStack(spacing: HP.Space.sm) {
      Image(systemName: "exclamationmark.triangle")
        .font(.system(size: 28, weight: .regular))
        .foregroundStyle(HP.Color.danger)
      Text(title)
        .font(HP.Font.headline)
        .foregroundStyle(HP.Color.text)
        .multilineTextAlignment(.center)
      Text(message)
        .font(HP.Font.callout)
        .foregroundStyle(HP.Color.textMuted)
        .multilineTextAlignment(.center)
      if let onRetry {
        HPButton(title: retryTitle, systemImage: "arrow.clockwise", variant: .primary, size: .md, action: onRetry)
          .padding(.top, HP.Space.xs)
      }
    }
    .frame(maxWidth: .infinity)
    .padding(HP.Space.lg)
  }
}
