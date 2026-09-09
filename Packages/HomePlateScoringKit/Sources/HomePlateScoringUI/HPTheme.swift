import SwiftUI

public enum HPTheme {
  public enum ColorToken {
    public static let background = Color(hex: 0x0F110C)
    public static let surface = Color(hex: 0x1A1E16)
    public static let surfaceRaised = Color(hex: 0x262B21)
    public static let surfaceMuted = Color(hex: 0x20241A)
    public static let input = Color(hex: 0x2E3327)
    public static let border = Color(hex: 0x333829)
    public static let borderStrong = Color(hex: 0x474D3B)
    public static let text = Color(hex: 0xECE8DD)
    public static let textMuted = Color(hex: 0xA6A394)
    public static let textTertiary = Color(hex: 0xC8C4B4)
    public static let fieldGreen = Color(hex: 0x2E7D57)
    public static let fieldGlow = Color(hex: 0x46B07C)
    public static let gold = Color(hex: 0xD6B370)
    public static let goldText = Color(hex: 0x2B2A1E)
    public static let success = Color(hex: 0x46B07C)
    public static let warning = Color(hex: 0xE0A33E)
    public static let danger = Color(hex: 0xD0453E)
    public static let info = Color(hex: 0x5A9BD6)
    public static let clay = Color(hex: 0x8A593B)
    public static let clayLight = Color(hex: 0xA76A43)
  }

  public enum FontToken {
    public static let display = Font.system(size: 34, weight: .bold, design: .rounded)
    public static let title = Font.system(size: 22, weight: .bold, design: .rounded)
    public static let headline = Font.system(size: 17, weight: .semibold)
    public static let body = Font.system(size: 16)
    public static let callout = Font.system(size: 15)
    public static let caption = Font.system(size: 13, weight: .medium)
    public static let eyebrow = Font.system(size: 12, weight: .semibold)
    public static let badge = Font.system(size: 12, weight: .bold)
    public static func number(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
      .system(size: size, weight: weight, design: .monospaced)
    }
  }
}

public extension Color {
  init(hex: UInt32, alpha: Double = 1) {
    self.init(
      .sRGB,
      red: Double((hex >> 16) & 0xFF) / 255,
      green: Double((hex >> 8) & 0xFF) / 255,
      blue: Double(hex & 0xFF) / 255,
      opacity: alpha
    )
  }
}

public struct HPCard<Content: View>: View {
  private let elevated: Bool
  @ViewBuilder private let content: () -> Content

  public init(elevated: Bool = true, @ViewBuilder content: @escaping () -> Content) {
    self.elevated = elevated
    self.content = content
  }

  public var body: some View {
    content()
      .padding(16)
      .background(elevated ? HPTheme.ColorToken.surfaceRaised : HPTheme.ColorToken.surface)
      .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: 16, style: .continuous)
          .stroke(HPTheme.ColorToken.border, lineWidth: 1)
      )
  }
}

public enum HPBadgeKind {
  case neutral, success, warning, danger, info, gold

  var color: Color {
    switch self {
    case .neutral: HPTheme.ColorToken.textMuted
    case .success: HPTheme.ColorToken.success
    case .warning: HPTheme.ColorToken.warning
    case .danger: HPTheme.ColorToken.danger
    case .info: HPTheme.ColorToken.info
    case .gold: HPTheme.ColorToken.gold
    }
  }
}

public struct HPStatusBadge: View {
  let text: String
  let kind: HPBadgeKind

  public init(_ text: String, kind: HPBadgeKind) {
    self.text = text
    self.kind = kind
  }

  public var body: some View {
    Text(text.uppercased())
      .font(HPTheme.FontToken.badge)
      .foregroundStyle(kind.color)
      .padding(.horizontal, 9)
      .padding(.vertical, 5)
      .background(kind.color.opacity(0.15))
      .clipShape(Capsule())
      .overlay(Capsule().stroke(kind.color.opacity(0.5), lineWidth: 1))
      .accessibilityLabel(text)
  }
}

public struct HPPrimaryButtonStyle: ButtonStyle {
  public init() {}

  public func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(HPTheme.FontToken.headline)
      .foregroundStyle(HPTheme.ColorToken.goldText)
      .frame(minHeight: 44)
      .padding(.horizontal, 14)
      .background(HPTheme.ColorToken.gold)
      .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
      .scaleEffect(configuration.isPressed ? 0.98 : 1)
      .animation(.easeOut(duration: 0.10), value: configuration.isPressed)
  }
}

public struct HPSecondaryButtonStyle: ButtonStyle {
  public init() {}

  public func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(HPTheme.FontToken.callout.weight(.semibold))
      .foregroundStyle(HPTheme.ColorToken.text)
      .frame(minHeight: 44)
      .padding(.horizontal, 12)
      .background(configuration.isPressed
        ? HPTheme.ColorToken.input
        : HPTheme.ColorToken.surfaceRaised)
      .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .stroke(HPTheme.ColorToken.borderStrong, lineWidth: 1)
      )
  }
}

public struct HPSectionLabel: View {
  let text: String
  public init(_ text: String) { self.text = text }

  public var body: some View {
    Text(text.uppercased())
      .font(HPTheme.FontToken.eyebrow)
      .tracking(0.6)
      .foregroundStyle(HPTheme.ColorToken.textMuted)
  }
}

public struct HPToast: View {
  let text: String
  public init(_ text: String) { self.text = text }

  public var body: some View {
    Label(text, systemImage: "checkmark.circle.fill")
      .font(HPTheme.FontToken.callout.weight(.semibold))
      .foregroundStyle(HPTheme.ColorToken.text)
      .padding(.horizontal, 16)
      .padding(.vertical, 12)
      .background(HPTheme.ColorToken.surfaceRaised)
      .clipShape(Capsule())
      .overlay(Capsule().stroke(HPTheme.ColorToken.borderStrong))
      .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
  }
}
