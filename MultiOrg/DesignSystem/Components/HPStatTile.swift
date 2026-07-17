import SwiftUI

/// Compact label + value row for dense metric lists. Evolves from
/// `FinanceCompactMetric`. Value stays cohesive; label wraps.
struct HPStatTile: View {
  let label: String
  let value: String
  var systemImage: String? = nil
  var valueColor: Color = HP.Color.text

  var body: some View {
    ViewThatFits(in: .horizontal) {
      horizontalContent
      stackedContent
    }
    .padding(.vertical, 6)
    .accessibilityElement(children: .combine)
  }

  private var horizontalContent: some View {
    HStack(spacing: HP.Space.sm) {
      labelContent
      Spacer(minLength: HP.Space.sm)
      Text(value)
        .font(HP.Font.callout.weight(.semibold)).foregroundStyle(valueColor)
        .lineLimit(1).fixedSize(horizontal: true, vertical: false)
    }
    .fixedSize(horizontal: true, vertical: false)
  }

  private var stackedContent: some View {
    VStack(alignment: .leading, spacing: 4) {
      labelContent
      Text(value)
        .font(HP.Font.callout.weight(.semibold))
        .foregroundStyle(valueColor)
        .fixedSize(horizontal: false, vertical: true)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var labelContent: some View {
    HStack(spacing: HP.Space.xs) {
      if let systemImage {
        Image(systemName: systemImage)
          .foregroundStyle(HP.Color.textMuted)
          .accessibilityHidden(true)
      }
      Text(label)
        .font(HP.Font.caption)
        .foregroundStyle(HP.Color.textMuted)
        .fixedSize(horizontal: false, vertical: true)
    }
  }
}
