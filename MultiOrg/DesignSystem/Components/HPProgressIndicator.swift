import SwiftUI

/// Progress indicator — determinate ring/bar or indeterminate spinner.
/// Reduce-Motion aware: the indeterminate ring stops spinning when Reduce
/// Motion is enabled. Evolves from the inline `ProgressRing`.
enum HPProgressStyle { case ring, bar, spinner }

struct HPProgressIndicator: View {
  /// 0...1 for determinate; `nil` = indeterminate.
  var value: Double? = nil
  var style: HPProgressStyle = .ring
  var lineWidth: CGFloat = 6

  var body: some View {
    switch style {
    case .spinner:
      ProgressView().controlSize(.regular).tint(HP.Color.accent)
    case .bar:
      Group {
        if let value {
          ProgressView(value: min(1, max(0, value))).tint(HP.Color.accent)
        } else {
          ProgressView().tint(HP.Color.accent)
        }
      }
    case .ring:
      HPProgressRing(value: value, lineWidth: lineWidth)
    }
  }
}

private struct HPProgressRing: View {
  var value: Double?
  var lineWidth: CGFloat
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var spin = false

  var body: some View {
    ZStack {
      Circle()
        .stroke(HP.Color.surfaceRaised, lineWidth: lineWidth)
        .allowsHitTesting(false)
      if let value {
        Circle()
          .trim(from: 0, to: min(1, max(0, value)))
          .stroke(HP.Color.accent, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
          .rotationEffect(.degrees(-90))
          .allowsHitTesting(false)
        Text("\(Int((min(1, max(0, value)) * 100).rounded()))%")
          .font(HP.Font.caption).foregroundStyle(HP.Color.textMuted)
      } else {
        Circle()
          .trim(from: 0, to: 0.25)
          .stroke(HP.Color.accent, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
          .rotationEffect(.degrees(spin ? 360 : 0))
          .allowsHitTesting(false)
          .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) { spin = true }
          }
      }
    }
    .accessibilityElement()
    .accessibilityLabel(value != nil ? "Progress" : "Loading")
    .accessibilityValue(accessibilityValue)
  }

  private var accessibilityValue: String {
    guard let value else { return "In progress" }
    return "\(Int((min(1, max(0, value)) * 100).rounded())) percent"
  }
}
