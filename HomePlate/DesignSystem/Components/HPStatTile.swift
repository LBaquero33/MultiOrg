import SwiftUI

/// Compact label + value row for dense metric lists. Evolves from
/// `FinanceCompactMetric`. Value stays cohesive; label wraps.
struct HPStatTile: View {
  let label: String
  let value: String
  var systemImage: String? = nil
  var valueColor: Color = HP.Color.text
  var hint: String? = nil

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 6) {
        if let systemImage {
          Image(systemName: systemImage)
            .foregroundStyle(HP.Color.textMuted)
            .accessibilityHidden(true)
        }
        Text(label)
          .font(.custom("Instrument Sans", size: 14, relativeTo: .subheadline).weight(.medium))
          .foregroundStyle(HP.Color.textMuted)
      }
      Text(value)
        .font(.custom("Instrument Sans", size: 30, relativeTo: .title).weight(.bold))
        .foregroundStyle(valueColor)
        .monospacedDigit()
        .padding(.top, 8)
      if let hint {
        Text(hint)
          .font(.custom("Instrument Sans", size: 14, relativeTo: .subheadline))
          .foregroundStyle(HP.Color.textMuted)
          .padding(.top, 4)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(20)
    .background(HP.Color.surface)
    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .strokeBorder(HP.Color.border, lineWidth: 1)
    }
    .accessibilityElement(children: .combine)
  }
}
