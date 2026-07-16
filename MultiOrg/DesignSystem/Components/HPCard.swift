import SwiftUI

/// Surface container. Two elevations: `flat` (grouped fills) and `elevated`
/// (raised surface + soft shadow). Evolves from `DHDCard`.
enum HPCardStyle { case flat, elevated }

struct HPCard<Content: View>: View {
  private let style: HPCardStyle
  private let content: Content

  init(style: HPCardStyle = .elevated, @ViewBuilder content: () -> Content) {
    self.style = style
    self.content = content()
  }

  var body: some View {
    content
      .padding(HP.Space.md)
      .background(
        RoundedRectangle(cornerRadius: HP.Radius.lg, style: .continuous)
          .fill(style == .elevated ? HP.Color.surfaceRaised : HP.Color.surface)
      )
      .overlay(
        RoundedRectangle(cornerRadius: HP.Radius.lg, style: .continuous)
          .strokeBorder(HP.Color.border, lineWidth: 1)
      )
      .modifier(HPCardShadow(style: style))
  }
}

private struct HPCardShadow: ViewModifier {
  let style: HPCardStyle
  @ViewBuilder func body(content: Content) -> some View {
    if style == .elevated { content.hpShadow(HP.Shadow.card) } else { content }
  }
}
