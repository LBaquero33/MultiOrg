import SwiftUI

/// Reusable presentation anatomy for an evidence-backed analytics workspace.
///
/// Callers provide controls, metric cards, charts, and the accessible breakdown
/// without surrendering ownership of data state or actions. The layout owns the
/// responsive metric grid and passes table policy through the breakdown context.
struct HPAnalyticsScreenLayout<
  Header: View,
  RangeControls: View,
  Metrics: View,
  Charts: View,
  Breakdown: View
>: View {
  private let widthMode: HPScreenWidthMode
  private let header: Header
  private let rangeControls: RangeControls
  private let metrics: Metrics
  private let charts: Charts
  private let breakdown: (HPScreenLayoutContext) -> Breakdown

  init(
    widthMode: HPScreenWidthMode = .automatic,
    @ViewBuilder header: () -> Header,
    @ViewBuilder rangeControls: () -> RangeControls,
    @ViewBuilder metrics: () -> Metrics,
    @ViewBuilder charts: () -> Charts,
    @ViewBuilder breakdown: @escaping (HPScreenLayoutContext) -> Breakdown
  ) {
    self.widthMode = widthMode
    self.header = header()
    self.rangeControls = rangeControls()
    self.metrics = metrics()
    self.charts = charts()
    self.breakdown = breakdown
  }

  var body: some View {
    HPScreenScaffold(widthMode: widthMode) { context in
      VStack(alignment: .leading, spacing: HP.Space.md) {
        header
        rangeControls
        LazyVGrid(
          columns: context.gridColumns(compact: 2, regular: 3),
          spacing: HP.Space.sm
        ) {
          metrics
        }
        charts
        breakdown(context)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }
}

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
  var isWide: Bool = false
  var state: HPTemplateState = .loaded

  @State private var range = "12W"

  var body: some View {
    HPAnalyticsScreenLayout(widthMode: isWide ? .automatic : .compact) {
      HPWorkspaceHeader("Analytics",
                        orgLabel: HPSample.orgIdentity.name,
                        context: "Apr 1 – Jul 14, 2026",
                        identity: HPSample.orgIdentity) {
        HPButton(title: "Export", systemImage: "square.and.arrow.up", variant: .secondary, size: .sm)
      }
    } rangeControls: {
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
    } metrics: {
      if state == .loaded {
        ForEach(HPSample.playerMetrics) { m in
          HPMetricCard(title: m.title, value: m.value, unit: m.unit,
                       delta: m.delta, trend: m.trend, context: m.context,
                       valueColor: m.valueColor)
        }
      }
    } charts: {
      switch state {
      case .loading:
        HPCard { HPLoadingState(text: "Crunching numbers…") }
      case .error:
        HPCard { HPErrorState(message: "We couldn’t load analytics.", onRetry: {}) }
      case .empty:
        HPCard {
          HPEmptyState(title: "Not enough data yet",
                       message: "Log at least two testing sessions to see a trend.",
                       systemImage: "chart.xyaxis.line")
        }
      case .loaded:
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
      }
    } breakdown: { context in
      if state == .loaded {
        HPCard {
          VStack(alignment: .leading, spacing: HP.Space.sm) {
            HPSectionHeader("Breakdown")
            HPTable(columns: HPSample.paymentColumns,
                    rows: HPSample.paymentRows,
                    layout: context.tableLayout)
          }
        }
      }
    }
  }
}

#Preview("Analytics — iPhone") { HPAnalyticsScreenTemplate() }
#Preview("Analytics — iPad/macOS") { HPAnalyticsScreenTemplate(isWide: true) }
