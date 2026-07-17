import SwiftUI
import Charts

/// Coach-facing overview: header stats + trends (read-only).
struct CoachPlayerOverviewView: View {
  @EnvironmentObject private var appState: AppState
  let player: Profile

  @State private var entries: [SDTestingEntry] = []
  @State private var isLoading = false
  @State private var errorText: String?

  var body: some View {
    HPAnalyticsScreenLayout {
      HPWorkspaceHeader(
        "Player Overview",
        context: overviewContext
      ) {
        if isLoading {
          HPProgressIndicator(style: .spinner)
            .accessibilityLabel("Refreshing player overview")
        }
      }
    } rangeControls: {
      EmptyView()
    } metrics: {
      if let latest = entries.first {
        HPMetricCard(
          title: "Latest test",
          value: latest.entry_date,
          context: "Most recent testing entry"
        )
        if let maxEV = latest.max_exit_velo {
          HPMetricCard(
            title: "Max EV",
            value: fmt(maxEV),
            unit: "mph",
            context: "Latest test"
          )
        }
        if let avgEV = latest.avg_exit_velo {
          HPMetricCard(
            title: "Avg EV",
            value: fmt(avgEV),
            unit: "mph",
            context: "Latest test"
          )
        }
        if let total = strengthTotal(latest) {
          HPMetricCard(
            title: "Strength total",
            value: fmt(total),
            unit: "lb",
            context: "Squat + bench + deadlift"
          )
        }
      }
    } charts: {
      chartContent
    } breakdown: { context in
      if !entries.isEmpty {
        HPCard {
          VStack(alignment: .leading, spacing: HP.Space.sm) {
            HPSectionHeader("Testing history") {
              HPStatusBadge(
                text: "\(entries.count) · newest first",
                kind: .neutral
              )
            }
            HPTable(
              columns: testingColumns,
              rows: testingRows,
              layout: context.tableLayout
            )
          }
        }
      }
    }
    .alert("Error", isPresented: Binding(get: { errorText != nil }, set: { _ in errorText = nil })) {
      Button("OK", role: .cancel) {}
    } message: { Text(errorText ?? "") }
    .task { await reload() }
  }

  @ViewBuilder
  private var chartContent: some View {
    if entries.isEmpty {
      if isLoading {
        HPCard {
          HPLoadingState(text: "Loading player overview…")
        }
      } else {
        HPCard {
          HPEmptyState(
            title: "No testing entries yet",
            message: "Testing trends will appear after results are recorded.",
            systemImage: "chart.xyaxis.line"
          )
        }
      }
    } else if entries.count >= 2 {
      let maxEVPoints = chartPoints(entries) { $0.max_exit_velo }
      let strengthPoints = chartPoints(entries) { strengthTotal($0) }

      HPCard {
        VStack(alignment: .leading, spacing: HP.Space.sm) {
          HPSectionHeader("Max EV trend") {
            HPStatusBadge(
              text: "\(maxEVPoints.count) measurements · mph",
              kind: .neutral
            )
          }
          TrendChart(points: maxEVPoints, yLabel: "mph")
            .frame(height: 240)
        }
      }
      HPCard {
        VStack(alignment: .leading, spacing: HP.Space.sm) {
          HPSectionHeader("Strength trend") {
            HPStatusBadge(
              text: "\(strengthPoints.count) measurements · lb",
              kind: .neutral
            )
          }
          TrendChart(points: strengthPoints, yLabel: "lb")
            .frame(height: 240)
        }
      }
    }
  }

  private var overviewContext: String {
    guard let newest = entries.first, let oldest = entries.last else {
      return "\(player.displayName) · Testing snapshot"
    }
    return "\(player.displayName) · \(entries.count) entries · \(oldest.entry_date) – \(newest.entry_date)"
  }

  private var testingColumns: [HPColumn] {
    [
      HPColumn(title: "Date"),
      HPColumn(title: "Max EV (mph)", alignment: .trailing, numeric: true),
      HPColumn(title: "Avg EV (mph)", alignment: .trailing, numeric: true),
      HPColumn(title: "Strength (lb)", alignment: .trailing, numeric: true),
    ]
  }

  private var testingRows: [HPTableRow] {
    entries.map { entry in
      HPTableRow(id: entry.id, cells: [
        entry.entry_date,
        entry.max_exit_velo.map(fmt) ?? "—",
        entry.avg_exit_velo.map(fmt) ?? "—",
        strengthTotal(entry).map(fmt) ?? "—",
      ])
    }
  }

  private func reload() async {
    guard let supabase = appState.supabase else { return }
    isLoading = true
    defer { isLoading = false }
    do {
      let rows = try await supabase.listTestingEntries(playerId: player.id)
      entries = rows.sorted { $0.entry_date > $1.entry_date }
    } catch {
      errorText = error.localizedDescription
    }
  }

  private func fmt(_ v: Double) -> String {
    if v.rounded() == v { return String(Int(v)) }
    return String(format: "%.1f", v)
  }

  private func strengthTotal(_ e: SDTestingEntry) -> Double? {
    let parts = [e.squat_1rm, e.bench_1rm, e.deadlift_1rm].compactMap { $0 }
    guard !parts.isEmpty else { return nil }
    return parts.reduce(0, +)
  }

  private func chartPoints(_ rows: [SDTestingEntry], value: (SDTestingEntry) -> Double?) -> [TrendPoint] {
    rows.compactMap { row in
      guard let v = value(row) else { return nil }
      guard let d = DateUtils.fromISODate(row.entry_date) else { return nil }
      return TrendPoint(date: d, value: v)
    }
    .sorted { $0.date < $1.date }
  }
}

fileprivate struct TrendPoint: Identifiable {
  let id = UUID()
  let date: Date
  let value: Double
}

fileprivate struct TrendChart: View {
  let points: [TrendPoint]
  let yLabel: String

  var body: some View {
    Chart(points) { p in
      LineMark(
        x: .value("Date", p.date),
        y: .value("Value", p.value)
      )
      .foregroundStyle(HP.Color.primaryGlow)
      .interpolationMethod(.catmullRom)
      PointMark(
        x: .value("Date", p.date),
        y: .value("Value", p.value)
      )
      .foregroundStyle(HP.Color.accent)
    }
    .chartYAxisLabel(yLabel)
    .chartYAxis {
      AxisMarks(position: .leading) { _ in
        AxisGridLine().foregroundStyle(HP.Color.border)
        AxisValueLabel().foregroundStyle(HP.Color.textMuted)
      }
    }
    .chartXAxis {
      AxisMarks { _ in
        AxisValueLabel().foregroundStyle(HP.Color.textMuted)
      }
    }
  }
}
