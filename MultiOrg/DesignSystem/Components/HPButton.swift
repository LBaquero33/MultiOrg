import SwiftUI

/// The one action affordance. Evolves from scattered `.borderedProminent` /
/// `.bordered` usages. Exactly one `.primary` (gold) per screen.
enum HPButtonVariant { case primary, secondary, tertiary, destructive }

enum HPButtonSize {
  case sm, md, lg
  var minHeight: CGFloat { switch self { case .sm: 28; case .md: 36; case .lg: 44 } }
  var hPadding: CGFloat { switch self { case .sm: 12; case .md: 16; case .lg: 20 } }
  var font: Font { switch self { case .sm: HP.Font.caption; case .md: HP.Font.callout; case .lg: HP.Font.headline } }
}

struct HPButton: View {
  let title: String
  var systemImage: String? = nil
  var variant: HPButtonVariant = .primary
  var size: HPButtonSize = .md
  var isLoading: Bool = false
  /// Stretch to fill available width (used for stacked accessibility actions).
  var fullWidth: Bool = false
  var action: () -> Void = {}

  var body: some View {
    Button(action: action) {
      HStack(spacing: 6) {
        if isLoading {
          ProgressView().controlSize(.small)
        } else if let systemImage {
          Image(systemName: systemImage)
        }
        Text(title)
          .multilineTextAlignment(.center)
          .lineLimit(fullWidth ? nil : 2)
          .minimumScaleFactor(fullWidth ? 1 : 0.85)
      }
      .fixedSize(horizontal: false, vertical: true)
    }
    .buttonStyle(HPButtonStyle(variant: variant, size: size, fullWidth: fullWidth))
    .disabled(isLoading)
    .accessibilityLabel(title)
    .accessibilityValue(isLoading ? "Loading" : "")
  }
}

struct HPButtonStyle: ButtonStyle {
  var variant: HPButtonVariant = .primary
  var size: HPButtonSize = .md
  var fullWidth: Bool = false
  @Environment(\.isEnabled) private var isEnabled

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(size.font.weight(.semibold))
      .foregroundStyle(foreground)
      .multilineTextAlignment(.center)
      .padding(.horizontal, size.hPadding)
      .padding(.vertical, 6)
      .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: size.minHeight)
      .background(
        RoundedRectangle(cornerRadius: HP.Radius.md, style: .continuous)
          .fill(background(pressed: configuration.isPressed))
      )
      .overlay(
        RoundedRectangle(cornerRadius: HP.Radius.md, style: .continuous)
          .strokeBorder(borderColor, lineWidth: borderWidth)
      )
      .opacity(isEnabled ? 1 : 0.32)
      .saturation(isEnabled ? 1 : 0.5)
      .scaleEffect(configuration.isPressed ? 0.98 : 1)
      .animation(HP.Motion.instant, value: configuration.isPressed)
      .contentShape(Rectangle())
  }

  private var foreground: Color {
    switch variant {
    case .primary:     HP.Color.accentText
    case .secondary:   HP.Color.text
    case .tertiary:    HP.Color.textTertiary
    case .destructive: HP.Color.text
    }
  }

  private func background(pressed: Bool) -> Color {
    let base: Color = switch variant {
    case .primary:     HP.Color.accent
    case .destructive: HP.Color.danger
    case .secondary, .tertiary: .clear
    }
    return pressed ? base.opacity(0.85) : base
  }

  private var borderColor: Color {
    variant == .secondary ? HP.Color.borderStrong : .clear
  }

  private var borderWidth: CGFloat {
    variant == .secondary ? 1.5 : 0
  }
}
