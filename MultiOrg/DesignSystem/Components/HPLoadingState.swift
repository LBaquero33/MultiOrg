import SwiftUI

/// Inline loading indicator. Prefer `HPSkeleton` for cards/tables/metrics so
/// layout stays stable; use this for small inline waits.
struct HPLoadingState: View {
  var text: String = "Loading…"

  var body: some View {
    HStack(spacing: HP.Space.sm) {
      ProgressView().controlSize(.small)
      Text(text).font(HP.Font.callout).foregroundStyle(HP.Color.textMuted)
    }
    .frame(maxWidth: .infinity, alignment: .center)
    .padding(HP.Space.md)
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
