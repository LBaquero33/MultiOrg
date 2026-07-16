import SwiftUI

/// Status chip. Unifies `DHDStatusPill` + `DHDStatusBadge`.
/// Always pairs color with a word (never color alone).
enum HPStatusKind {
  case neutral, success, warning, danger, info, gold

  var color: Color {
    switch self {
    case .neutral: HP.Color.textMuted
    case .success: HP.Color.success
    case .warning: HP.Color.warning
    case .danger:  HP.Color.danger
    case .info:    HP.Color.info
    case .gold:    HP.Color.accent
    }
  }

  /// Text color for the badge label — brighter than `color` for the neutral
  /// kind so it stays legible on its own tinted fill.
  var textColor: Color {
    self == .neutral ? HP.Color.textTertiary : color
  }
}

struct HPStatusBadge: View {
  let text: String
  var kind: HPStatusKind = .neutral

  var body: some View {
    Text(text)
      .font(HP.Font.badge)
      .lineLimit(1)
      .fixedSize()
      .padding(.horizontal, HP.Space.sm)
      .padding(.vertical, 6)
      .background(
        Capsule()
          .fill(kind.color.opacity(0.20))
          .overlay(Capsule().strokeBorder(kind.color.opacity(0.40), lineWidth: 1))
      )
      .foregroundStyle(kind.textColor)
      .accessibilityLabel(text)
  }
}
