import SwiftUI

/// Designed empty state — icon, title, one-line explanation, optional single
/// CTA. Copy should be specific and encouraging, never a dead end.
struct HPEmptyState: View {
  let title: String
  var message: String? = nil
  var systemImage: String = "tray"
  var actionTitle: String? = nil
  /// When the action is the primary next step (e.g. "Create request"), keep
  /// this true so it renders as a prominent gold primary button.
  var actionIsPrimary: Bool = true
  var action: (() -> Void)? = nil

  var body: some View {
    VStack(spacing: HP.Space.sm) {
      Image(systemName: systemImage)
        .font(.system(size: 30, weight: .regular))
        .foregroundStyle(HP.Color.textMuted)
      Text(title)
        .font(HP.Font.headline)
        .foregroundStyle(HP.Color.text)
        .multilineTextAlignment(.center)
      if let message {
        Text(message)
          .font(HP.Font.callout)
          .foregroundStyle(HP.Color.textMuted)
          .multilineTextAlignment(.center)
      }
      if let actionTitle, let action {
        HPButton(title: actionTitle,
                 variant: actionIsPrimary ? .primary : .secondary,
                 size: .md,
                 action: action)
          .padding(.top, HP.Space.xs)
      }
    }
    .frame(maxWidth: .infinity)
    .padding(HP.Space.lg)
  }
}
