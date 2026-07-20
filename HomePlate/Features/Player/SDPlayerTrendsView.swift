import SwiftUI
import Charts

fileprivate struct TrendPoint: Identifiable {
  let id = UUID()
  let date: Date
  let value: Double
}

struct SDPlayerTrendsView: View {
  @EnvironmentObject private var appState: AppState

  @State private var entries: [SDTestingEntry] = []
  @State private var isLoading = false
  @State private var errorText: String?

  var body: some View {
    NavigationStack {
      HPAnalyticsScreenLayout {
        HPWorkspaceHeader("Trends", context: trendContext)
      } rangeControls: {
        if isLoading {
          HPCard {
            HStack(spacing: HP.Space.xs) {
              HPProgressIndicator(style: .spinner)
              Text("Refreshing testing trends…")
                .font(HP.Font.caption)
                .foregroundStyle(HP.Color.textMuted)
            }
            .accessibilityElement(children: .combine)
          }
        }
      } metrics: {
        if let latest = entries.first {
          HPMetricCard(title: "Latest test", value: latest.entry_date,
                       context: "Most recent entry")
          if let maxEV = latest.max_exit_velo {
            HPMetricCard(title: "Max EV", value: fmt(maxEV), unit: "mph",
                         context: "Latest test")
          }
          if let avgEV = latest.avg_exit_velo {
            HPMetricCard(title: "Avg EV", value: fmt(avgEV), unit: "mph",
                         context: "Latest test")
          }
          if let strength = strengthTotal(latest) {
            HPMetricCard(title: "Strength total", value: fmt(strength), unit: "lb",
                         context: "Squat + bench + deadlift")
          }
        }
      } charts: {
        chartContent
      } breakdown: { context in
        if !entries.isEmpty {
          HPCard {
            VStack(alignment: .leading, spacing: HP.Space.sm) {
              HPSectionHeader("Testing history") {
                HPStatusBadge(text: "Newest first", kind: .neutral)
              }
              HPTable(
                columns: [
                  HPColumn(title: "Date"),
                  HPColumn(title: "Max EV", alignment: .trailing, numeric: true),
                  HPColumn(title: "Strength", alignment: .trailing, numeric: true),
                ],
                rows: breakdownRows,
                layout: context.tableLayout
              )
            }
          }
        }
      }
      .navigationTitle("Trends")
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Menu {
            Button {
              Task { await reload() }
            } label: {
              Label("Refresh", systemImage: "arrow.clockwise")
            }
            Button(role: .destructive) {
              Task { await appState.signOut() }
            } label: {
              Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
            }
          } label: {
            Image(systemName: "ellipsis.circle")
          }
        }
      }
      .task { await reload() }
    }
  }

  @ViewBuilder
  private var chartContent: some View {
    if errorText != nil {
      HPCard {
        HPErrorState(
          message: "We couldn’t load testing trends. Check your connection and try again.",
          onRetry: { Task { await reload() } }
        )
      }
    }

    if entries.isEmpty {
      if isLoading {
        HPCard { HPLoadingState(text: "Loading testing trends…") }
      } else if errorText == nil {
        HPCard {
          HPEmptyState(
            title: "Not enough data yet",
            message: "Add your first Testing entry to see improvement trends.",
            systemImage: "chart.xyaxis.line"
          )
        }
      }
    } else {
      HPCard {
        VStack(alignment: .leading, spacing: HP.Space.sm) {
          HPSectionHeader("Max EV trend") {
            HPStatusBadge(text: "mph · all entries", kind: .neutral)
          }
          TrendChart(
            points: chartPoints(entries) { $0.max_exit_velo },
            yLabel: "mph"
          )
          .frame(height: 240)
        }
      }

      HPCard {
        VStack(alignment: .leading, spacing: HP.Space.sm) {
          HPSectionHeader("Strength trend") {
            HPStatusBadge(text: "lb · all entries", kind: .neutral)
          }
          TrendChart(
            points: chartPoints(entries) { strengthTotal($0) },
            yLabel: "lb"
          )
          .frame(height: 240)
        }
      }
    }
  }

  private var trendContext: String {
    guard let newest = entries.first, let oldest = entries.last else {
      return "Testing history and progress"
    }
    return "\(entries.count) entries · \(oldest.entry_date) – \(newest.entry_date)"
  }

  private var breakdownRows: [HPTableRow] {
    entries.map { entry in
      HPTableRow(cells: [
        entry.entry_date,
        entry.max_exit_velo.map { "\(fmt($0)) mph" } ?? "—",
        strengthTotal(entry).map { "\(fmt($0)) lb" } ?? "—",
      ])
    }
  }

  private func reload() async {
    guard let supabase = appState.supabase else { return }
    errorText = nil
    isLoading = true
    defer { isLoading = false }
    do {
      let session = try await supabase.client.auth.session
      let uid = session.user.id
      let rows = try await supabase.listTestingEntries(playerId: uid)
      // Newest first (same as Shiny uses for "Latest test" UI).
      entries = rows.sorted { $0.entry_date > $1.entry_date }
    } catch {
      errorText = error.localizedDescription
    }
  }

  private func fmt(_ value: Double) -> String {
    if value.rounded() == value { return String(Int(value)) }
    return String(format: "%.1f", value)
  }

  private func strengthTotal(_ entry: SDTestingEntry) -> Double? {
    let parts = [entry.squat_1rm, entry.bench_1rm, entry.deadlift_1rm].compactMap { $0 }
    guard !parts.isEmpty else { return nil }
    return parts.reduce(0, +)
  }

  private func chartPoints(
    _ rows: [SDTestingEntry],
    value: (SDTestingEntry) -> Double?
  ) -> [TrendPoint] {
    rows.compactMap { row in
      guard let value = value(row) else { return nil }
      guard let date = DateUtils.fromISODate(row.entry_date) else { return nil }
      return TrendPoint(date: date, value: value)
    }
    .sorted { $0.date < $1.date }
  }
}

private struct TrendChart: View {
  let points: [TrendPoint]
  let yLabel: String

  var body: some View {
    if points.count < 2 {
      HPEmptyState(
        title: "One more test needed",
        message: "Add another entry to see a trend line.",
        systemImage: "chart.xyaxis.line"
      )
    } else {
      Chart(points) { point in
        LineMark(
          x: .value("Date", point.date),
          y: .value("Value", point.value)
        )
        .foregroundStyle(HP.Color.primaryGlow)
        .interpolationMethod(.catmullRom)
        PointMark(
          x: .value("Date", point.date),
          y: .value("Value", point.value)
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
}
