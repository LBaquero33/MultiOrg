import SwiftUI

/// Surface container. Two elevations: `flat` (grouped fills) and `elevated`
/// (raised surface + soft shadow). Evolves from `DHDCard`.
enum HPCardStyle { case flat, elevated }

struct HPCard<Content: View>: View {
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass
  private let style: HPCardStyle
  private let content: Content

  init(style: HPCardStyle = .flat, @ViewBuilder content: () -> Content) {
    self.style = style
    self.content = content()
  }

  var body: some View {
    content
      .padding(resolvedPadding)
      .background(
        RoundedRectangle(cornerRadius: HP.Radius.md, style: .continuous)
          .fill(style == .elevated ? HP.Color.surfaceRaised : HP.Color.surface)
      )
      .overlay(
        RoundedRectangle(cornerRadius: HP.Radius.md, style: .continuous)
          .strokeBorder(HP.Color.border, lineWidth: 1)
          .allowsHitTesting(false)
      )
      .modifier(HPCardShadow(style: style))
  }

  private var resolvedPadding: CGFloat {
    #if os(macOS)
    24
    #else
    horizontalSizeClass == .regular ? 24 : 20
    #endif
  }
}

private struct HPCardShadow: ViewModifier {
  let style: HPCardStyle
  @ViewBuilder func body(content: Content) -> some View {
    if style == .elevated { content.hpShadow(HP.Shadow.card) } else { content }
  }
}
