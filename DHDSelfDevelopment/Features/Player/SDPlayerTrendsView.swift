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
      List {
        if isLoading {
          HStack(spacing: 10) { ProgressView(); Text("Loading…").foregroundStyle(.secondary) }
        }

        Section("Snapshot") {
          if let latest = entries.first {
            HStack {
              VStack(alignment: .leading, spacing: 4) {
                Text("Latest test").font(.caption).foregroundStyle(.secondary)
                Text(latest.entry_date).font(.headline)
              }
              Spacer()
            }
            if let maxEV = latest.max_exit_velo {
              MetricPill(title: "Max EV (mph)", value: fmt(maxEV))
            }
            if let avgEV = latest.avg_exit_velo {
              MetricPill(title: "Avg EV (mph)", value: fmt(avgEV))
            }
            let strength = strengthTotal(latest)
            if let strength {
              MetricPill(title: "Strength total", value: fmt(strength))
            }
          } else {
            Text("Add your first Testing entry to see improvement trends.")
              .foregroundStyle(.secondary)
          }
        }

        if !entries.isEmpty {
          Section("Max EV trend") {
            TrendChart(
              points: chartPoints(entries) { $0.max_exit_velo },
              yLabel: "mph"
            )
            .frame(height: 240)
          }

          Section("Strength trend") {
            TrendChart(
              points: chartPoints(entries) { strengthTotal($0) },
              yLabel: "lb"
            )
            .frame(height: 240)
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
      .alert("Error", isPresented: Binding(get: { errorText != nil }, set: { _ in errorText = nil })) {
        Button("OK", role: .cancel) {}
      } message: {
        Text(errorText ?? "")
      }
      .task { await reload() }
    }
  }

  private func reload() async {
    guard let supabase = appState.supabase else { return }
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

private struct MetricPill: View {
  let title: String
  let value: String

  var body: some View {
    HStack {
      VStack(alignment: .leading, spacing: 2) {
        Text(title).font(.caption).foregroundStyle(.secondary)
        Text(value).font(.title3.weight(.semibold))
      }
      Spacer()
    }
    .padding(.vertical, 6)
  }
}

private struct TrendChart: View {
  let points: [TrendPoint]
  let yLabel: String

  var body: some View {
    if points.count < 2 {
      Text("Add another entry to see a trend line.")
        .foregroundStyle(.secondary)
    } else {
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
}
