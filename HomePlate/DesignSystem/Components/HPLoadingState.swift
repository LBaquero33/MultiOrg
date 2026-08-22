import SwiftUI

/// Inline loading indicator. Prefer `HPSkeleton` for cards/tables/metrics so
/// layout stays stable; use this for small inline waits.
struct HPLoadingState: View {
  var text: String = "Loading…"

  var body: some View {
    HStack(spacing: 12) {
      ProgressView().controlSize(.small).frame(width: 20, height: 20)
      Text(text).font(HP.Font.body).foregroundStyle(HP.Color.textMuted)
      Spacer(minLength: 0)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(24)
    .background(HP.Color.surface)
    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .strokeBorder(HP.Color.border, lineWidth: 1)
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel(text)
  }
}

/// Skeleton placeholder block (layout-stable loading). Reduce-Motion aware:
/// the pulse animation is suppressed when Reduce Motion is enabled.
struct HPSkeleton: View {
  var height: CGFloat = 14
  var cornerRadius: CGFloat = HP.Radius.sm

  @State private var pulsing = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
      .fill(HP.Color.surfaceRaised)
      .frame(height: height)
      .opacity(pulsing ? 0.5 : 1)
      .onAppear {
        guard !reduceMotion else { return }
        withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
          pulsing = true
        }
      }
      .accessibilityHidden(true)
  }
}
