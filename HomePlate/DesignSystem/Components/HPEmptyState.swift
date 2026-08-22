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
    VStack(spacing: 0) {
      Image(systemName: systemImage)
        .font(.system(size: 24, weight: .regular))
        .foregroundStyle(HP.Color.textMuted)
        .frame(width: 48, height: 48)
        .background(HP.Color.surfaceRaised)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .padding(.bottom, 16)
      Text(title)
        .font(.custom("Instrument Sans", size: 18, relativeTo: .headline).weight(.semibold))
        .foregroundStyle(HP.Color.text)
        .multilineTextAlignment(.center)
      if let message {
        Text(message)
          .font(HP.Font.body)
          .foregroundStyle(HP.Color.textMuted)
          .multilineTextAlignment(.center)
          .frame(maxWidth: 448)
          .padding(.top, 8)
      }
      if let actionTitle, let action {
        HPButton(title: actionTitle,
                 variant: actionIsPrimary ? .primary : .secondary,
                 size: .md,
                 action: action)
          .padding(.top, 20)
      }
    }
    .frame(maxWidth: .infinity)
    .padding(40)
    .background(HP.Color.surface.opacity(0.5))
    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .strokeBorder(HP.Color.border, style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
    }
  }
}
