import SwiftUI

/// Compact label + value row for dense metric lists. Evolves from
/// `FinanceCompactMetric`. Value stays cohesive; label wraps.
struct HPStatTile: View {
  let label: String
  let value: String
  var systemImage: String? = nil
  var valueColor: Color = HP.Color.text

  var body: some View {
    HStack(spacing: HP.Space.sm) {
      if let systemImage {
        Image(systemName: systemImage).foregroundStyle(HP.Color.textMuted)
      }
      Text(label)
        .font(HP.Font.caption).foregroundStyle(HP.Color.textMuted)
        .fixedSize(horizontal: false, vertical: true)
      Spacer(minLength: HP.Space.sm)
      Text(value)
        .font(HP.Font.callout.weight(.semibold)).foregroundStyle(valueColor)
        .lineLimit(1).fixedSize(horizontal: true, vertical: false)
    }
    .padding(.vertical, 6)
    .accessibilityElement(children: .combine)
  }
}
