import SwiftUI

// Home Plate OS — Design System (Phase 10, Stage 3A)
//
// Preview-only foundation: tokens + foundation components with SF Pro.
// Additive and isolated — this namespace does NOT modify `DHDTheme`,
// `DHDUIComponents`, or any production screen. Custom fonts (Archivo /
// Instrument Sans) can be enabled later without changing component APIs.

/// Root namespace for the Home Plate design system.
enum HP {}

// MARK: - Organization identity (chrome only)

/// Identity chrome for headers / avatars / badges. Per approved decision 1,
/// an organization's brand color drives *identity chrome only*; every semantic
/// color (primary, accent, success, danger, focus, finance) stays HP-owned.
struct HPIdentity: Equatable {
  var name: String
  var shortName: String
  var primary: Color
  var secondary: Color

  var gradient: LinearGradient {
    LinearGradient(colors: [primary, secondary], startPoint: .topLeading, endPoint: .bottomTrailing)
  }

  /// Home Plate fallback identity (field green → deep green-charcoal).
  static let homePlate = HPIdentity(
    name: "Home Plate",
    shortName: "Home Plate",
    primary: HP.Color.primary,
    secondary: HP.Color.bg
  )
}

// MARK: - Shadow application

extension View {
  /// Applies an `HP.Shadow` style token.
  func hpShadow(_ style: HP.ShadowStyle) -> some View {
    shadow(color: style.color, radius: style.radius, x: style.x, y: style.y)
  }
}

// MARK: - Reduce-motion-aware animation

extension HP {
  /// Returns a reduced (quick, opacity-friendly) animation when Reduce Motion
  /// is enabled; otherwise the requested animation. Centralized so components
  /// don't each re-implement the check.
  static func animation(_ animation: Animation, reduceMotion: Bool) -> Animation {
    reduceMotion ? HP.Motion.quick : animation
  }
}
