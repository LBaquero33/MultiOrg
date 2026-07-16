import SwiftUI

/// Template 7 — **Analytics screen**.
///
/// Purpose: answer "what's trending / what's profitable" with evidence.
/// Anatomy: header → range control → headline metrics → charts → breakdown table.
///
/// Rules:
/// - Every chart states its range and units; a chart alone is never the answer —
///   pair it with `HPMetricCard` context.
/// - Charts never carry meaning by color alone; the breakdown table is the
///   accessible equivalent and is always present.
/// - AX3: charts keep a fixed readable height and the table stacks.
struct HPAnalyticsScreenTemplate: View {
  @Environment(\.dynamicTypeSize) private var dts

  var isWide: Bool = false
  var state: HPTemplateState = .loaded

  @State private var range = "12W"

  private var columns: [GridItem] {
    if dts.isAccessibilitySize { return [GridItem(.flexible())] }
    return isWide
      ? [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
      : [GridItem(.flexible()), GridItem(.flexible())]
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: HP.Space.md) {
        HPWorkspaceHeader("Analytics",
                          orgLabel: HPSample.orgIdentity.name,
                          context: "Apr 1 – Jul 14, 2026",
                          identity: HPSample.orgIdentity) {
          HPButton(title: "Export", systemImage: "square.and.arrow.up", variant: .secondary, size: .sm)
        }

        HPCard {
          VStack(alignment: .leading, spacing: HP.Space.sm) {
            Text("Range")
              .font(HP.Font.eyebrow).tracking(HP.Font.eyebrowTracking)
              .foregroundStyle(HP.Color.textMuted)
            HPSegmentedControl(
              options: [(value: "4W", label: "4W"), (value: "12W", label: "12W"),
                        (value: "6M", label: "6M"), (value: "1Y", label: "1Y")],
              selection: $range
            )
          }
        }

        switch state {
        case .loading: HPCard { HPLoadingState(text: "Crunching numbers…") }
        case .error:   HPCard { HPErrorState(message: "We couldn’t load analytics.", onRetry: {}) }
        case .empty:
          HPCard {
            HPEmptyState(title: "Not enough data yet",
                         message: "Log at least two testing sessions to see a trend.",
                         systemImage: "chart.xyaxis.line")
          }
        case .loaded:
          LazyVGrid(columns: columns, spacing: HP.Space.sm) {
            ForEach(HPSample.playerMetrics) { m in
              HPMetricCard(title: m.title, value: m.value, unit: m.unit,
                           delta: m.delta, trend: m.trend, context: m.context,
                           valueColor: m.valueColor)
            }
          }

          HPCard {
            VStack(alignment: .leading, spacing: HP.Space.sm) {
              HPSectionHeader("Exit velocity trend") {
                HPStatusBadge(text: "mph · 12 weeks", kind: .neutral)
              }
              HPChart(points: HPSample.trendPoints, style: .line, height: 180)
            }
          }

          HPCard {
            VStack(alignment: .leading, spacing: HP.Space.sm) {
              HPSectionHeader("Revenue by month") {
                HPStatusBadge(text: "$K", kind: .neutral)
              }
              HPChart(points: HPSample.revenuePoints, style: .bar, height: 180)
            }
          }

          HPCard {
            VStack(alignment: .leading, spacing: HP.Space.sm) {
              HPSectionHeader("Breakdown")
              HPTable(columns: HPSample.paymentColumns,
                      rows: HPSample.paymentRows,
                      layout: dts.isAccessibilitySize ? .stacked : .auto)
            }
          }
        }
      }
      .padding(HP.Space.md)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .background(HP.Color.bg)
  }
}

#Preview("Analytics — iPhone") { HPAnalyticsScreenTemplate() }
#Preview("Analytics — iPad/macOS") { HPAnalyticsScreenTemplate(isWide: true) }
