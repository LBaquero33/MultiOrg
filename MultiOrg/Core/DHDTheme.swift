import SwiftUI

struct DHDOrgBranding: Equatable {
  let name: String
  let shortName: String
  let primary: Color
  let secondary: Color
  let accent: Color
  let logoURL: URL?

  static let fallback = DHDOrgBranding(
    name: "MultiOrg",
    shortName: "MultiOrg",
    primary: DHDTheme.navy,
    secondary: DHDTheme.navy2,
    accent: DHDTheme.accent,
    logoURL: nil
  )

  var headerGradient: LinearGradient {
    LinearGradient(
      colors: [primary, secondary],
      startPoint: .topLeading,
      endPoint: .bottomTrailing
    )
  }
}

private struct DHDOrgBrandingKey: EnvironmentKey {
  static let defaultValue = DHDOrgBranding.fallback
}

extension EnvironmentValues {
  var dhdOrgBranding: DHDOrgBranding {
    get { self[DHDOrgBrandingKey.self] }
    set { self[DHDOrgBrandingKey.self] = newValue }
  }
}

enum DHDTheme {
  // Brand
  static let navy = Color(red: 0.05, green: 0.14, blue: 0.27)
  static let navy2 = Color(red: 0.04, green: 0.22, blue: 0.33)
  static let accent = Color(red: 0.30, green: 0.62, blue: 0.98) // macOS-friendly blue

  // Layout
  static let pagePadding: CGFloat = 16
  static let cardPadding: CGFloat = 14
  static let cornerRadius: CGFloat = 16
  static let innerCornerRadius: CGFloat = 14
  static let gridSpacing: CGFloat = 10

  // Calendar
  static let calendarDotSize: CGFloat = 6.5
  static let calendarCellCornerRadius: CGFloat = 14
  static let calendarDayNumberWeight: Font.Weight = .semibold

  // Surfaces
  static let pageBackground: Color = {
#if canImport(UIKit)
    return Color(uiColor: .systemGroupedBackground)
#elseif canImport(AppKit)
    // High-contrast dark macOS palette (we force dark mode on macOS).
    return Color(red: 0.06, green: 0.07, blue: 0.09)
#else
    return Color.gray.opacity(0.12)
#endif
  }()

  static let cardBackground: Color = {
#if canImport(UIKit)
    return Color(uiColor: .secondarySystemGroupedBackground)
#elseif canImport(AppKit)
    return Color(red: 0.10, green: 0.11, blue: 0.14)
#else
    return Color.white.opacity(0.9)
#endif
  }()

  static let cardSurface: Color = {
#if canImport(UIKit)
    return Color(uiColor: .systemBackground)
#elseif canImport(AppKit)
    return Color(red: 0.13, green: 0.14, blue: 0.18)
#else
    return Color.white
#endif
  }()

  static let surfaceElevated: Color = {
#if canImport(AppKit)
    return Color(red: 0.16, green: 0.17, blue: 0.22)
#else
    return cardSurface
#endif
  }()

  static let separator: Color = {
#if canImport(UIKit)
    return Color(uiColor: .separator)
#elseif canImport(AppKit)
    return Color.white.opacity(0.10)
#else
    return Color.gray.opacity(0.25)
#endif
  }()

  static let textPrimary: Color = {
#if canImport(AppKit)
    return Color.white.opacity(0.96)
#else
    return Color.primary
#endif
  }()

  static let textSecondary: Color = {
#if canImport(AppKit)
    return Color.white.opacity(0.70)
#else
    return Color.secondary
#endif
  }()

  static let success: Color = Color.green
  static let danger: Color = Color.red
  static let info: Color = Color.blue

  // Shadows (subtle; iOS-native feel)
  static let shadowColor = Color.black.opacity(0.06)
  static let shadowRadius: CGFloat = 10
  static let shadowY: CGFloat = 3
  static let macShadowColor = Color.black.opacity(0.22)
  static let macShadowRadius: CGFloat = 10
  static let macShadowY: CGFloat = 5

  static var headerGradient: LinearGradient {
    LinearGradient(
      colors: [navy.opacity(0.95), navy2.opacity(0.92)],
      startPoint: .topLeading,
      endPoint: .bottomTrailing
    )
  }

  static func color(hex rawValue: String?, fallback: Color) -> Color {
    guard let rawValue else { return fallback }
    let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    let hex = value.hasPrefix("#") ? String(value.dropFirst()) : value
    guard hex.count == 6, let rgb = UInt64(hex, radix: 16) else { return fallback }
    return Color(
      red: Double((rgb & 0xFF0000) >> 16) / 255,
      green: Double((rgb & 0x00FF00) >> 8) / 255,
      blue: Double(rgb & 0x0000FF) / 255
    )
  }
}
