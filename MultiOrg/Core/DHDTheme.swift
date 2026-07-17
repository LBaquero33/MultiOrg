import SwiftUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

struct DHDOrgBranding: Equatable {
  let name: String
  let shortName: String
  let primary: Color
  let secondary: Color
  let accent: Color
  let logoURL: URL?

  static let fallback = DHDOrgBranding(
    name: "Home Plate",
    shortName: "Home Plate",
    primary: DHDTheme.primary,
    secondary: DHDTheme.brandDeep,
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

/// Compatibility tokens for production screens that predate the `HP` namespace.
///
/// Dark values are the approved Home Plate palette. Light values preserve the
/// same semantic roles with accessible contrast. Keeping adaptive resolution in
/// this one adapter lets legacy `DHD*` screens adopt Home Plate without changing
/// their public APIs or letting organization colors leak into semantic controls.
enum DHDTheme {
  enum Appearance: CaseIterable {
    case light
    case dark
  }

  enum SemanticRole: CaseIterable {
    case pageBackground
    case surface
    case surfaceRaised
    case surfaceMuted
    case input
    case border
    case borderStrong
    case text
    case textMuted
    case textTertiary
    case primary
    case primaryGlow
    case brandDeep
    case accent
    case accentText
    case focusRing
    case danger
    case success
    case warning
    case info
  }

  struct RGBA: Equatable, Sendable {
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double

    init(hex: UInt32, alpha: Double = 1) {
      red = Double((hex >> 16) & 0xFF) / 255
      green = Double((hex >> 8) & 0xFF) / 255
      blue = Double(hex & 0xFF) / 255
      self.alpha = alpha
    }
  }

  // MARK: Semantic palette

  static let pageBackground = color(for: .pageBackground)
  static let cardBackground = color(for: .surface)
  static let cardSurface = color(for: .surfaceRaised)
  static let surfaceElevated = color(for: .surfaceRaised)
  static let surfaceMuted = color(for: .surfaceMuted)
  static let inputBackground = color(for: .input)

  static let separator = color(for: .border)
  static let border = color(for: .border)
  static let borderStrong = color(for: .borderStrong)

  static let textPrimary = color(for: .text)
  static let textSecondary = color(for: .textMuted)
  static let textMuted = color(for: .textMuted)
  static let textTertiary = color(for: .textTertiary)

  static let primary = color(for: .primary)
  static let primaryGlow = color(for: .primaryGlow)
  static let brandDeep = color(for: .brandDeep)
  static let accent = color(for: .accent)
  static let accentText = color(for: .accentText)
  static let focusRing = color(for: .focusRing)
  static let success = color(for: .success)
  static let warning = color(for: .warning)
  static let danger = color(for: .danger)
  static let info = color(for: .info)

  // Organization identity chrome keeps its own neutral foreground/scrim and
  // cannot override the semantic palette above.
  static let identityText = Color.white
  static let scrim = Color.black.opacity(0.55)

  // Legacy brand names remain source-compatible. They now resolve to Home
  // Plate identity colors and are never used to redefine semantic statuses.
  static let navy = primary
  static let navy2 = brandDeep

  // MARK: Home Plate metrics

  static let pagePadding: CGFloat = HP.Space.md
  static let cardPadding: CGFloat = HP.Space.md
  static let cornerRadius: CGFloat = HP.Radius.lg
  static let innerCornerRadius: CGFloat = HP.Radius.md
  static let gridSpacing: CGFloat = HP.Space.sm
  static let minimumTouchTarget: CGFloat = 44

  static let calendarDotSize: CGFloat = 7
  static let calendarCellCornerRadius: CGFloat = HP.Radius.md
  static let calendarDayNumberWeight: Font.Weight = .semibold

  static let shadowColor = HP.Shadow.subtle.color
  static let shadowRadius = HP.Shadow.subtle.radius
  static let shadowY = HP.Shadow.subtle.y
  static let macShadowColor = HP.Shadow.card.color
  static let macShadowRadius = HP.Shadow.card.radius
  static let macShadowY = HP.Shadow.card.y

  static var headerGradient: LinearGradient {
    LinearGradient(
      colors: [primary, brandDeep],
      startPoint: .topLeading,
      endPoint: .bottomTrailing
    )
  }

  /// Exact palette components used by both the platform-adaptive colors and
  /// contrast tests. Dark values mirror `HP.Color`; light values are warm,
  /// role-equivalent Home Plate colors rather than system-default blue/gray.
  static func components(for role: SemanticRole, appearance: Appearance) -> RGBA {
    switch (role, appearance) {
    case (.pageBackground, .dark): return RGBA(hex: 0x0F110C)
    case (.surface, .dark): return RGBA(hex: 0x1A1E16)
    case (.surfaceRaised, .dark): return RGBA(hex: 0x262B21)
    case (.surfaceMuted, .dark): return RGBA(hex: 0x20241A)
    case (.input, .dark): return RGBA(hex: 0x2E3327)
    case (.border, .dark): return RGBA(hex: 0x333829)
    case (.borderStrong, .dark): return RGBA(hex: 0x474D3B)
    case (.text, .dark): return RGBA(hex: 0xECE8DD)
    case (.textMuted, .dark): return RGBA(hex: 0xA6A394)
    case (.textTertiary, .dark): return RGBA(hex: 0xC8C4B4)
    case (.primary, .dark): return RGBA(hex: 0x2E7D57)
    case (.primaryGlow, .dark): return RGBA(hex: 0x46B07C)
    case (.brandDeep, .dark): return RGBA(hex: 0x0F110C)
    case (.accent, .dark), (.focusRing, .dark): return RGBA(hex: 0xD6B370)
    case (.accentText, .dark): return RGBA(hex: 0x2B2A1E)
    case (.danger, .dark): return RGBA(hex: 0xD0453E)
    case (.success, .dark): return RGBA(hex: 0x46B07C)
    case (.warning, .dark): return RGBA(hex: 0xE0A33E)
    case (.info, .dark): return RGBA(hex: 0x5A9BD6)

    case (.pageBackground, .light): return RGBA(hex: 0xF6F3EA)
    case (.surface, .light): return RGBA(hex: 0xFFFFFF)
    case (.surfaceRaised, .light): return RGBA(hex: 0xEEE9DD)
    case (.surfaceMuted, .light): return RGBA(hex: 0xE7E1D4)
    case (.input, .light): return RGBA(hex: 0xFFFFFF)
    case (.border, .light): return RGBA(hex: 0xCCC4B2)
    case (.borderStrong, .light): return RGBA(hex: 0x8F8674)
    case (.text, .light): return RGBA(hex: 0x182019)
    case (.textMuted, .light): return RGBA(hex: 0x555D54)
    case (.textTertiary, .light): return RGBA(hex: 0x3E493F)
    case (.primary, .light): return RGBA(hex: 0x216441)
    case (.primaryGlow, .light): return RGBA(hex: 0x18794E)
    case (.brandDeep, .light): return RGBA(hex: 0x123628)
    case (.accent, .light), (.focusRing, .light): return RGBA(hex: 0x8A5A00)
    case (.accentText, .light): return RGBA(hex: 0xFFFFFF)
    case (.danger, .light): return RGBA(hex: 0xB42318)
    case (.success, .light): return RGBA(hex: 0x18794E)
    case (.warning, .light): return RGBA(hex: 0x7A4F00)
    case (.info, .light): return RGBA(hex: 0x215F9A)
    }
  }

  static func color(hex rawValue: String?, fallback: Color) -> Color {
    guard let rawValue else { return fallback }
    let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    let hex = value.hasPrefix("#") ? String(value.dropFirst()) : value
    guard hex.count == 6, let rgb = UInt32(hex, radix: 16) else { return fallback }
    return swiftUIColor(RGBA(hex: rgb))
  }

  private static func color(for role: SemanticRole) -> Color {
    adaptive(
      light: components(for: role, appearance: .light),
      dark: components(for: role, appearance: .dark)
    )
  }

  private static func adaptive(light: RGBA, dark: RGBA) -> Color {
#if canImport(UIKit)
    return Color(uiColor: UIColor { traits in
      uiColor(traits.userInterfaceStyle == .dark ? dark : light)
    })
#elseif canImport(AppKit)
    return Color(nsColor: NSColor(name: nil) { appearance in
      let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
      return nsColor(isDark ? dark : light)
    })
#else
    return swiftUIColor(light)
#endif
  }

  private static func swiftUIColor(_ value: RGBA) -> Color {
    Color(
      .displayP3,
      red: value.red,
      green: value.green,
      blue: value.blue,
      opacity: value.alpha
    )
  }

#if canImport(UIKit)
  private static func uiColor(_ value: RGBA) -> UIColor {
    UIColor(
      displayP3Red: value.red,
      green: value.green,
      blue: value.blue,
      alpha: value.alpha
    )
  }
#elseif canImport(AppKit)
  private static func nsColor(_ value: RGBA) -> NSColor {
    NSColor(
      displayP3Red: value.red,
      green: value.green,
      blue: value.blue,
      alpha: value.alpha
    )
  }
#endif
}
