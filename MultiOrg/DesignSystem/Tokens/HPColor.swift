import SwiftUI

extension HP {
  /// Home Plate semantic color roles. Layer A owns their adaptive dark and
  /// warm-light values; the `HP` and compatibility namespaces intentionally
  /// resolve through the same source so navigation and structural templates
  /// cannot drift from production screens.
  enum Color {
    // Surfaces
    static let bg            = DHDTheme.pageBackground
    static let surface       = DHDTheme.cardBackground
    static let surfaceRaised = DHDTheme.surfaceElevated
    static let surfaceMuted  = DHDTheme.surfaceMuted
    static let border        = DHDTheme.border
    static let borderStrong  = DHDTheme.borderStrong
    static let input         = DHDTheme.inputBackground

    // Text
    static let text          = DHDTheme.textPrimary
    static let textMuted     = DHDTheme.textMuted
    static let textTertiary  = DHDTheme.textTertiary

    // Brand / semantic (HP-owned — never overridden by org branding)
    static let primary       = DHDTheme.primary
    static let primaryGlow   = DHDTheme.primaryGlow
    static let accent        = DHDTheme.accent
    static let accentText    = DHDTheme.accentText
    static let focusRing     = DHDTheme.focusRing
    static let danger        = DHDTheme.danger
    static let success       = DHDTheme.success
    static let warning       = DHDTheme.warning
    static let info          = DHDTheme.info

    // Example organization identity color (gallery only — chrome, not semantic)
    static let exampleOrg    = p3(0xB02638)   // crimson
    static let exampleOrg2   = p3(0x7A1A28)

    private static func p3(_ hex: UInt32) -> SwiftUI.Color {
      SwiftUI.Color(
        .displayP3,
        red: Double((hex >> 16) & 0xFF) / 255,
        green: Double((hex >> 8) & 0xFF) / 255,
        blue: Double(hex & 0xFF) / 255
      )
    }
  }
}
