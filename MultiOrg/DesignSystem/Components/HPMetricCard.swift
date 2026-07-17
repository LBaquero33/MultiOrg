import SwiftUI

/// A metric shown **with context** (Manifesto principle 3 — context over raw
/// numbers). Serves both player metrics (mph/lb) and finance metrics (money).
/// Evolves from `ImprovementTile` + `FinanceMetricCard`.
enum HPTrendDirection {
  case up, down, flat
  var color: Color {
    switch self { case .up: HP.Color.success; case .down: HP.Color.danger; case .flat: HP.Color.textMuted }
  }
  var symbol: String {
    switch self { case .up: "arrow.up.right"; case .down: "arrow.down.right"; case .flat: "arrow.right" }
  }
}

struct HPMetricCard: View {
  let title: String
  let value: String
  var unit: String? = nil
  var delta: String? = nil
  var trend: HPTrendDirection? = nil
  var context: String? = nil
  /// Value color — finance may pass `HP.Color.success` / `.danger`.
  var valueColor: Color = HP.Color.text

  var body: some View {
    HPCard(style: .flat) {
      VStack(alignment: .leading, spacing: HP.Space.xs) {
        Text(title.uppercased())
          .font(HP.Font.eyebrow)
          .tracking(HP.Font.eyebrowTracking)
          .foregroundStyle(HP.Color.textMuted)
          .lineLimit(2)
          .fixedSize(horizontal: false, vertical: true)

        // Keep the primary value + unit visually cohesive. Prefer them side by
        // side; fall back to stacked (value over unit) when width is tight —
        // never letting the value itself fragment (e.g. "88.\n4").
        ViewThatFits(in: .horizontal) {
          HStack(alignment: .firstTextBaseline, spacing: 4) { valueText; unitText }
          VStack(alignment: .leading, spacing: 2) { valueText; unitText }
        }

        if let delta, let trend {
          HStack(alignment: .firstTextBaseline, spacing: 4) {
            Image(systemName: trend.symbol).font(.caption2)
            Text(delta)
              .font(HP.Font.caption)
              .fixedSize(horizontal: false, vertical: true)
          }
          .foregroundStyle(trend.color)
        }

        if let context {
          Text(context)
            .font(HP.Font.caption)
            .foregroundStyle(HP.Color.textMuted)
            .lineLimit(3)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .accessibilityElement(children: .combine)
  }

  private var valueText: some View {
    Text(value)
      .font(HP.Font.number())
      .foregroundStyle(valueColor)
      .lineLimit(1)
      .fixedSize(horizontal: true, vertical: false)
  }

  @ViewBuilder private var unitText: some View {
    if let unit {
      Text(unit)
        .font(HP.Font.callout)
        .foregroundStyle(HP.Color.textMuted)
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
    }
  }
}
