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
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: "exclamationmark.triangle")
        .font(.system(size: 20, weight: .regular))
        .foregroundStyle(HP.Color.danger)
        .padding(.top, 2)

      VStack(alignment: .leading, spacing: 0) {
        Text(title)
          .font(HP.Font.body.weight(.medium))
          .foregroundStyle(HP.Color.text)
        Text(message)
          .font(.custom("Instrument Sans", size: 14, relativeTo: .subheadline))
          .foregroundStyle(HP.Color.textMuted)
          .fixedSize(horizontal: false, vertical: true)
          .padding(.top, 4)
        if let onRetry {
          HPButton(title: retryTitle, variant: .secondary, size: .sm, action: onRetry)
            .padding(.top, 12)
        }
      }
      Spacer(minLength: 0)
    }
    .frame(maxWidth: .infinity)
    .padding(24)
    .background(HP.Color.danger.opacity(0.10))
    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .strokeBorder(HP.Color.danger.opacity(0.40), lineWidth: 1)
    }
  }
}
