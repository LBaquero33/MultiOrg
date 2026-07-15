import SwiftUI
import Charts

/// Coach-facing Analysis (read-only) for a player; same logic as player Analysis but parameterized by playerId.
struct CoachPlayerAnalysisView: View {
  let player: Profile

  var body: some View {
    BPAnalysisView(playerId: player.id)
  }
}

/// Shared analysis view used by both player + coach.
struct BPAnalysisView: View {
  @EnvironmentObject private var appState: AppState

  let playerId: UUID

  @State private var startDate: Date = DateUtils.calendarET.date(byAdding: .day, value: -30, to: Date()) ?? Date()
  @State private var endDate: Date = Date()
  @State private var repsType: String = "all"
  @State private var source: String = "all"
  @State private var strikeMode: String = "point"

  @State private var sessions: [SDBPSession] = []
  @State private var events: [SDBPEvent] = []
  @State private var isLoading = false
  @State private var errorText: String?

  var body: some View {
    List {
      Section("Filters") {
        DatePicker("Start", selection: $startDate, displayedComponents: .date)
          .onChange(of: startDate) { _, _ in Task { await reload() } }
        DatePicker("End", selection: $endDate, displayedComponents: .date)
          .onChange(of: endDate) { _, _ in Task { await reload() } }
        Picker("Reps type", selection: $repsType) {
          Text("All").tag("all")
          Text("Practice").tag("practice")
          Text("Game").tag("game")
        }
        .onChange(of: repsType) { _, _ in Task { await reload() } }
        Picker("Source", selection: $source) {
          Text("All").tag("all")
          Text("Rapsodo").tag("rapsodo")
          Text("HitTrax").tag("hitrax")
          Text("TrackMan").tag("trackman")
        }
        .onChange(of: source) { _, _ in Task { await reload() } }
      }

      Section("Summary") {
        if isLoading {
          HStack(spacing: 10) { ProgressView(); Text("Loading…").foregroundStyle(.secondary) }
        } else if events.isEmpty {
          Text("No BP events found in this date range.")
            .foregroundStyle(.secondary)
        } else {
          let evs = events.compactMap(\.exit_velo)
          let las = events.compactMap(\.launch_angle)
          let dists = events.compactMap(\.distance)
          Text("Sessions: \(sessions.count)")
          Text("Events: \(events.count)")
          if let maxEV = evs.max() { Text("Max EV: \(fmt(maxEV)) mph") }
          if !evs.isEmpty { Text("Avg EV: \(fmt(avg(evs))) mph") }
          if let maxDist = dists.max() { Text("Max distance: \(fmt(maxDist))") }
          if !las.isEmpty { Text("Avg launch angle: \(fmt(avg(las)))") }
        }
      }

      if !events.isEmpty {
        Section("Exit Velo (histogram)") {
          HistogramChart(values: events.compactMap(\.exit_velo), binCount: 12, xLabel: "mph")
            .frame(height: 220)
        }
        Section("Distance (histogram)") {
          HistogramChart(values: events.compactMap(\.distance), binCount: 12, xLabel: "")
            .frame(height: 220)
        }
        Section("Launch Angle (histogram)") {
          HistogramChart(values: events.compactMap(\.launch_angle), binCount: 12, xLabel: "°")
            .frame(height: 220)
        }
        Section("Contact quality") {
          ContactQualitySummary(events: events)
        }
        Section("Ball flight") {
          BallFlightSummary(events: events)
        }
        Section("EV vs Launch Angle") {
          ScatterChart(events: events)
            .frame(height: 260)
        }
        Section("Strike zone") {
          Picker("View", selection: $strikeMode) {
            Text("Points").tag("point")
            Text("Density").tag("density")
          }
          .pickerStyle(.segmented)
          StrikeZoneChart(events: events, mode: strikeMode)
            .frame(height: 320)
        }
      }
    }
    #if os(macOS)
    .listStyle(.inset)
    #else
    .listStyle(.insetGrouped)
    #endif
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
      let allSessions = try await supabase.listBPSessions(playerId: playerId, limit: 365)
      let startISO = DateUtils.toISODate(DateUtils.startOfDayET(startDate))
      let endISO = DateUtils.toISODate(DateUtils.startOfDayET(endDate))

      let filteredSessions = allSessions.filter { s in
        if s.session_date < startISO || s.session_date > endISO { return false }
        if repsType != "all", s.reps_type != repsType { return false }
        if source != "all", s.source != source { return false }
        return true
      }

      sessions = filteredSessions
      if filteredSessions.isEmpty {
        events = []
        return
      }

      var allEvents: [SDBPEvent] = []
      try await withThrowingTaskGroup(of: [SDBPEvent].self) { group in
        for s in filteredSessions {
          group.addTask { try await supabase.fetchBPEvents(sessionId: s.id) }
        }
        for try await ev in group {
          allEvents.append(contentsOf: ev)
        }
      }
      events = allEvents
    } catch {
      errorText = error.localizedDescription
    }
  }

  private func avg(_ xs: [Double]) -> Double {
    guard !xs.isEmpty else { return 0 }
    return xs.reduce(0, +) / Double(xs.count)
  }

  private func fmt(_ v: Double) -> String {
    if v.rounded() == v { return String(Int(v)) }
    return String(format: "%.1f", v)
  }
}
