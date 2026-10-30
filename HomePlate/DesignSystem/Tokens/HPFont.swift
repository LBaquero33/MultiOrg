import SwiftUI

extension HP {
  /// Home Plate type scale.
  ///
  /// "Under the Lights" renders with **SF Pro** (system) + Dynamic Type: heavy
  /// weights for display, regular for reading. The custom families are `nil`,
  /// so nothing depends on a bundled font file. Setting them later (the web
  /// uses "Hanken Grotesk" and "Public Sans") switches every call site
  /// **without changing any component API**.
  enum Font {
    /// Display / heading family. Set to "Archivo" once fonts are bundled.
    static let displayFamily: String? = nil
    /// Body / UI family. Set to "InstrumentSans" once fonts are bundled.
    static let textFamily: String? = nil

    static var display:  SwiftUI.Font { resolve(displayFamily, 32, .black, .largeTitle) }
    static var pageTitle: SwiftUI.Font { resolve(displayFamily, 26, .black, .title2) }
    static var title:    SwiftUI.Font { resolve(displayFamily, 22, .heavy, .title2) }
    static var headline: SwiftUI.Font { resolve(textFamily, 17, .bold, .headline) }
    static var body:     SwiftUI.Font { resolve(textFamily, 16, .regular, .body) }
    static var callout:  SwiftUI.Font { resolve(textFamily, 15, .regular, .callout) }
    static var caption:  SwiftUI.Font { resolve(textFamily, 13, .medium, .caption) }
    /// Small uppercase section label — relative to `.caption` (not `.caption2`)
    /// for readability at small sizes while keeping the refined tone.
    static var eyebrow:  SwiftUI.Font { resolve(textFamily, 12, .heavy, .caption) }
    /// Status-badge text — slightly heavier for legibility.
    static var badge:    SwiftUI.Font { resolve(textFamily, 12, .bold, .caption) }

    /// Tabular-figure font for money / stats (Dynamic-Type aware).
    static func number(_ style: SwiftUI.Font.TextStyle = .title2,
                       weight: SwiftUI.Font.Weight = .bold) -> SwiftUI.Font {
      SwiftUI.Font.system(style, design: .default).weight(weight).monospacedDigit()
    }

    // Tracking (letter spacing) per token — apply via `.tracking(...)`.
    static let displayTracking: CGFloat = -0.8
    static let titleTracking: CGFloat = -0.3
    static let eyebrowTracking: CGFloat = 1.6

    private static func resolve(_ family: String?,
                                _ size: CGFloat,
                                _ weight: SwiftUI.Font.Weight,
                                _ style: SwiftUI.Font.TextStyle) -> SwiftUI.Font {
      if let family {
        return SwiftUI.Font.custom(family, size: size, relativeTo: style).weight(weight)
      }
      return SwiftUI.Font.system(style, design: .default).weight(weight)
    }
  }
}
