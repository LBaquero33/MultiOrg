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
    List {
      if isLoading {
        HStack(spacing: 10) { ProgressView(); Text("Loading…").foregroundStyle(.secondary) }
      }

      Section("Snapshot") {
        if let latest = entries.first {
          Text("Latest test: \(latest.entry_date)")
            .font(.headline)
          if let maxEV = latest.max_exit_velo {
            Text("Max EV: \(fmt(maxEV)) mph").font(.subheadline).foregroundStyle(.secondary)
          }
          if let avgEV = latest.avg_exit_velo {
            Text("Avg EV: \(fmt(avgEV)) mph").font(.subheadline).foregroundStyle(.secondary)
          }
          if let total = strengthTotal(latest) {
            Text("Strength total: \(fmt(total))").font(.subheadline).foregroundStyle(.secondary)
          }
        } else {
          Text("No testing entries yet.")
            .foregroundStyle(.secondary)
        }
      }

      if entries.count >= 2 {
        Section("Max EV trend") {
          TrendChart(points: chartPoints(entries) { $0.max_exit_velo }, yLabel: "mph")
            .frame(height: 240)
        }
        Section("Strength trend") {
          TrendChart(points: chartPoints(entries) { strengthTotal($0) }, yLabel: "lb")
            .frame(height: 240)
        }
      }
    }
    #if os(macOS)
    .listStyle(.inset)
    #else
    .listStyle(.insetGrouped)
    #endif
    .dhdPageBackground()
    .alert("Error", isPresented: Binding(get: { errorText != nil }, set: { _ in errorText = nil })) {
      Button("OK", role: .cancel) {}
    } message: { Text(errorText ?? "") }
    .task { await reload() }
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
      .interpolationMethod(.catmullRom)
      PointMark(
        x: .value("Date", p.date),
        y: .value("Value", p.value)
      )
    }
    .chartYAxisLabel(yLabel)
  }
}
