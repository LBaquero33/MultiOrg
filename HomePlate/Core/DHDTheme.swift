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
  static let cornerRadius: CGFloat = HP.Radius.md
  static let innerCornerRadius: CGFloat = HP.Radius.md
  static let gridSpacing: CGFloat = HP.Space.sm
  static let sectionSpacing: CGFloat = HP.Space.md
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
  /// contrast tests. Dark values mirror `HP.Color`; light values are the
  /// "Day Game" side of the same roles rather than system-default blue/gray.
  static func components(for role: SemanticRole, appearance: Appearance) -> RGBA {
    switch (role, appearance) {
    // "Under the Lights" (2026-10-13): the website's tokens. Mint `accent` is the
    // action colour with dark text; `primary` stays deep enough for white text.
    case (.pageBackground, .dark): return RGBA(hex: 0x0B1410)
    case (.surface, .dark): return RGBA(hex: 0x131D18)
    case (.surfaceRaised, .dark): return RGBA(hex: 0x1B2721)
    case (.surfaceMuted, .dark): return RGBA(hex: 0x17221C)
    case (.input, .dark): return RGBA(hex: 0x2C3C33)
    case (.border, .dark): return RGBA(hex: 0x243229)
    case (.borderStrong, .dark): return RGBA(hex: 0x3A4C42)
    case (.text, .dark): return RGBA(hex: 0xF4F7F5)
    case (.textMuted, .dark): return RGBA(hex: 0xA3ADA8)
    case (.textTertiary, .dark): return RGBA(hex: 0xC2CAC6)
    case (.primary, .dark): return RGBA(hex: 0x1C7A4C)
    case (.primaryGlow, .dark): return RGBA(hex: 0x5FCF8E)
    case (.brandDeep, .dark): return RGBA(hex: 0x070D0A)
    case (.accent, .dark), (.focusRing, .dark): return RGBA(hex: 0x5FCF8E)
    case (.accentText, .dark): return RGBA(hex: 0x0B1410)
    case (.danger, .dark): return RGBA(hex: 0xDE3B3D)
    case (.success, .dark): return RGBA(hex: 0x5FCF8E)
    case (.warning, .dark): return RGBA(hex: 0xF2B84B)
    case (.info, .dark): return RGBA(hex: 0xC9D2CE)

    case (.pageBackground, .light): return RGBA(hex: 0xF3F6F3)
    case (.surface, .light): return RGBA(hex: 0xFFFFFF)
    case (.surfaceRaised, .light): return RGBA(hex: 0xE9EEEA)
    case (.surfaceMuted, .light): return RGBA(hex: 0xE1E8E3)
    case (.input, .light): return RGBA(hex: 0xFFFFFF)
    case (.border, .light): return RGBA(hex: 0xC5CFC9)
    case (.borderStrong, .light): return RGBA(hex: 0x7F8C85)
    case (.text, .light): return RGBA(hex: 0x0B1410)
    case (.textMuted, .light): return RGBA(hex: 0x56625B)
    case (.textTertiary, .light): return RGBA(hex: 0x3C4A42)
    case (.primary, .light): return RGBA(hex: 0x17633E)
    case (.primaryGlow, .light): return RGBA(hex: 0x0C7A42)
    case (.brandDeep, .light): return RGBA(hex: 0x0B2A1C)
    case (.accent, .light), (.focusRing, .light): return RGBA(hex: 0x0C7A42)
    case (.accentText, .light): return RGBA(hex: 0xFFFFFF)
    case (.danger, .light): return RGBA(hex: 0xB42318)
    case (.success, .light): return RGBA(hex: 0x0C7A42)
    case (.warning, .light): return RGBA(hex: 0x7A4F00)
    case (.info, .light): return RGBA(hex: 0x4F5F58)
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
