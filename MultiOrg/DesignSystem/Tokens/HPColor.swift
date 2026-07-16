import SwiftUI

extension HP {
  /// Home Plate color roles (dark-first — the only mode in Phase 10).
  ///
  /// Values are Display-P3 approximations of the website's OKLCH tokens
  /// (see HOME_PLATE_DESIGN_SYSTEM.md §2). They should be verified/tuned
  /// against the live site during pilot polish.
  enum Color {
    // Surfaces — stepped ladder for clearer separation (polish pass)
    static let bg            = p3(0x0F110C)   // app background (deep green-charcoal)
    static let surface       = p3(0x1A1E16)   // card / popover (flat)
    static let surfaceRaised = p3(0x262B21)   // raised / elevated
    static let surfaceMuted  = p3(0x20241A)   // muted fills
    static let border        = p3(0x333829)   // hairline (more visible)
    static let borderStrong  = p3(0x474D3B)   // section containers / secondary controls
    static let input         = p3(0x2E3327)   // field border/fill

    // Text
    static let text          = p3(0xECE8DD)   // cream
    static let textMuted     = p3(0xA6A394)   // secondary
    static let textTertiary  = p3(0xC8C4B4)   // tertiary controls (brighter than muted)

    // Brand / semantic (HP-owned — never overridden by org branding)
    static let primary       = p3(0x2E7D57)   // field green
    static let primaryGlow   = p3(0x46B07C)   // brighter green
    static let accent        = p3(0xD6B370)   // gold — CTA / focus / value
    static let accentText    = p3(0x2B2A1E)   // text on gold
    static let focusRing     = p3(0xD6B370)   // gold ring
    static let danger        = p3(0xD0453E)
    static let success       = p3(0x46B07C)
    static let warning       = p3(0xE0A33E)
    static let info          = p3(0x5A9BD6)

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
