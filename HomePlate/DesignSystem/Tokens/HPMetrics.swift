import SwiftUI

extension HP {
  /// Spacing scale (4-pt based).
  enum Space {
    static let xs: CGFloat = 8
    static let sm: CGFloat = 12
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let xl: CGFloat = 32
  }

  /// Corner-radius scale.
  enum Radius {
    static let sm: CGFloat = 8
    static let md: CGFloat = 12   // base (matches site --radius)
    static let lg: CGFloat = 16   // cards
    static let xl: CGFloat = 18   // modals
  }

  /// Elevation shadow style token.
  struct ShadowStyle {
    let color: SwiftUI.Color
    let radius: CGFloat
    let x: CGFloat
    let y: CGFloat
  }

  enum Shadow {
    static let subtle = ShadowStyle(color: .black.opacity(0.06), radius: 10, x: 0, y: 3)
    static let card   = ShadowStyle(color: .black.opacity(0.5),  radius: 28, x: 0, y: 12)
    static let modal  = ShadowStyle(color: .black.opacity(0.45), radius: 24, x: 0, y: 14)
  }

  /// Motion tokens (see HOME_PLATE_MOTION_SYSTEM.md). Calm, purposeful.
  enum Motion {
    static let instant  = Animation.easeOut(duration: 0.10)
    static let quick    = Animation.easeOut(duration: 0.18)
    static let standard = Animation.easeInOut(duration: 0.25)
    static let emphasis = Animation.spring(response: 0.35, dampingFraction: 0.85)
  }
}
