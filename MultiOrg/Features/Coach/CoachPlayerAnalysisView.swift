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
    HPAnalyticsScreenLayout {
      HPWorkspaceHeader(
        "BP Analysis",
        context: "\(DateUtils.toISODate(startDate)) – \(DateUtils.toISODate(endDate))"
      )
    } rangeControls: {
      filterCard
    } metrics: {
      if !isLoading, !events.isEmpty {
        summaryMetrics
      }
    } charts: {
      if let errorText {
        HPCard {
          HPErrorState(
            message: errorText,
            onRetry: { Task { await reload() } }
          )
        }
      }
      if isLoading {
        HPCard {
          HPLoadingState(text: "Loading analysis…")
        }
      }
      if events.isEmpty, !isLoading, errorText == nil {
        HPCard {
          HPEmptyState(
            title: "No BP events found",
            message: "No BP events were found in this date range.",
            systemImage: "chart.xyaxis.line"
          )
        }
      }
      if !events.isEmpty {
        analysisCard("Exit Velo (histogram)", badge: "mph") {
          HistogramChart(values: events.compactMap(\.exit_velo), binCount: 12, xLabel: "mph")
            .frame(height: 220)
        }
        analysisCard("Distance (histogram)", badge: "source-reported units") {
          HistogramChart(
            values: events.compactMap(\.distance),
            binCount: 12,
            xLabel: "Source-reported distance"
          )
            .frame(height: 220)
        }
        analysisCard("Launch Angle (histogram)", badge: "degrees") {
          HistogramChart(values: events.compactMap(\.launch_angle), binCount: 12, xLabel: "°")
            .frame(height: 220)
        }
        analysisCard("EV vs Launch Angle", badge: "mph × degrees") {
          ScatterChart(events: events)
            .frame(height: 260)
        }
        analysisCard("Strike zone") {
          VStack(alignment: .leading, spacing: HP.Space.sm) {
            HPSegmentedControl(
              options: [(value: "point", label: "Points"),
                        (value: "density", label: "Density")],
              selection: $strikeMode
            )
            StrikeZoneChart(events: events, mode: strikeMode)
              .frame(height: 320)
          }
        }
      }
    } breakdown: { context in
      if !events.isEmpty {
        analysisCard("Event breakdown", badge: "\(min(50, events.count)) of \(events.count)") {
          HPTable(
            columns: eventTableColumns,
            rows: eventTableRows,
            layout: context.tableLayout
          )
        }
        if !strikeZoneTableRows.isEmpty {
          analysisCard(
            "Strike-zone breakdown",
            badge: "All \(strikeZoneTableRows.count) · in"
          ) {
            VStack(alignment: .leading, spacing: HP.Space.sm) {
              Text("Catcher view · all normalized pitch locations shown")
                .font(HP.Font.caption)
                .foregroundStyle(HP.Color.textMuted)
              HPTable(
                columns: strikeZoneTableColumns,
                rows: strikeZoneTableRows,
                layout: context.tableLayout
              )
            }
          }
        }
        analysisCard("Contact quality") {
          ContactQualitySummary(events: events)
        }
        analysisCard("Ball flight") {
          BallFlightSummary(events: events)
        }
      }
    }
    .task { await reload() }
  }

  private var filterCard: some View {
    HPCard {
      VStack(alignment: .leading, spacing: HP.Space.md) {
        HPSectionHeader("Filters")

        VStack(alignment: .leading, spacing: HP.Space.sm) {
          DatePicker("Start", selection: $startDate, displayedComponents: .date)
            .onChange(of: startDate) { _, _ in Task { await reload() } }
          DatePicker("End", selection: $endDate, displayedComponents: .date)
            .onChange(of: endDate) { _, _ in Task { await reload() } }
        }
        .font(HP.Font.callout)
        .foregroundStyle(HP.Color.text)
        .tint(HP.Color.accent)

        VStack(alignment: .leading, spacing: 6) {
          Text("Reps type")
            .font(HP.Font.eyebrow)
            .tracking(HP.Font.eyebrowTracking)
            .foregroundStyle(HP.Color.textMuted)
          HPSegmentedControl(
            options: [(value: "all", label: "All"),
                      (value: "practice", label: "Practice"),
                      (value: "game", label: "Game")],
            selection: $repsType
          )
          .onChange(of: repsType) { _, _ in Task { await reload() } }
        }

        VStack(alignment: .leading, spacing: 6) {
          Text("Source")
            .font(HP.Font.eyebrow)
            .tracking(HP.Font.eyebrowTracking)
            .foregroundStyle(HP.Color.textMuted)
          HPSegmentedControl(
            options: [(value: "all", label: "All"),
                      (value: "rapsodo", label: "Rapsodo"),
                      (value: "hitrax", label: "HitTrax"),
                      (value: "trackman", label: "TrackMan")],
            selection: $source
          )
          .onChange(of: source) { _, _ in Task { await reload() } }
        }
      }
    }
  }

  @ViewBuilder
  private var summaryMetrics: some View {
    let exitVelocities = events.compactMap(\.exit_velo)
    let launchAngles = events.compactMap(\.launch_angle)
    let distances = events.compactMap(\.distance)

    HPMetricCard(title: "Sessions", value: "\(sessions.count)", context: "Selected range")
    HPMetricCard(title: "Events", value: "\(events.count)", context: "Tracked swings")
    if let maximum = exitVelocities.max() {
      HPMetricCard(title: "Max EV", value: fmt(maximum), unit: "mph", context: "Selected range")
    }
    if !exitVelocities.isEmpty {
      HPMetricCard(title: "Avg EV", value: fmt(avg(exitVelocities)), unit: "mph", context: "Selected range")
    }
    if let maximum = distances.max() {
      HPMetricCard(
        title: "Max distance",
        value: fmt(maximum),
        unit: "source units",
        context: "Provider-reported units · selected range"
      )
    }
    if !launchAngles.isEmpty {
      HPMetricCard(title: "Avg launch angle", value: fmt(avg(launchAngles)), unit: "°", context: "Selected range")
    }
  }

  private func analysisCard<Content: View>(
    _ title: String,
    badge: String? = nil,
    @ViewBuilder content: () -> Content
  ) -> some View {
    HPCard {
      VStack(alignment: .leading, spacing: HP.Space.sm) {
        HPSectionHeader(title) {
          if let badge {
            HPStatusBadge(text: badge, kind: .neutral)
          }
        }
        content()
      }
    }
  }

  private var eventTableColumns: [HPColumn] {
    [
      HPColumn(title: "Date"),
      HPColumn(title: "Session"),
      HPColumn(title: "Pitch", alignment: .trailing, numeric: true),
      HPColumn(title: "EV (mph)", alignment: .trailing, numeric: true),
      HPColumn(title: "LA (°)", alignment: .trailing, numeric: true),
      HPColumn(title: "Distance (source units)", alignment: .trailing, numeric: true),
    ]
  }

  private var eventTableRows: [HPTableRow] {
    let sessionsById = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0) })
    return deterministicEvents(sessionsById: sessionsById).prefix(50).map { event in
      let session = sessionsById[event.session_id]
      let sessionLabel = session.map {
        "\($0.source.capitalized) · \($0.reps_type.capitalized)"
      } ?? "Unavailable"
      return HPTableRow(id: event.id, cells: [
        session?.session_date ?? "—",
        sessionLabel,
        event.pitch_num.map(String.init) ?? "—",
        event.exit_velo.map(fmt) ?? "—",
        event.launch_angle.map(fmt) ?? "—",
        event.distance.map(fmt) ?? "—",
      ])
    }
  }

  private var strikeZoneTableColumns: [HPColumn] {
    [
      HPColumn(title: "Date"),
      HPColumn(title: "Pitch", alignment: .trailing, numeric: true),
      HPColumn(title: "Zone X (in)", alignment: .trailing, numeric: true),
      HPColumn(title: "Zone Z (in)", alignment: .trailing, numeric: true),
      HPColumn(title: "EV (mph)", alignment: .trailing, numeric: true),
    ]
  }

  private var strikeZoneTableRows: [HPTableRow] {
    let sessionsById = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0) })
    return deterministicEvents(sessionsById: sessionsById).compactMap { event -> HPTableRow? in
      guard let coordinates = normalizedStrikeZoneCoordinates(for: event) else { return nil }
      return HPTableRow(id: event.id, cells: [
        sessionsById[event.session_id]?.session_date ?? "—",
        event.pitch_num.map(String.init) ?? "—",
        fmt(coordinates.x),
        fmt(coordinates.z),
        event.exit_velo.map(fmt) ?? "—",
      ])
    }
  }

  private func normalizedStrikeZoneCoordinates(
    for event: SDBPEvent
  ) -> (x: Double, z: Double)? {
    guard let rawX = event.strike_x, let rawZ = event.strike_z,
          rawX.isFinite, rawZ.isFinite else { return nil }
    let x = abs(rawX) <= 3 ? rawX * 12 : rawX
    let z = abs(rawZ) <= 6 ? rawZ * 12 : rawZ
    guard (-17.0...17.0).contains(x), (18.0...42.0).contains(z) else { return nil }
    return (x, z)
  }

  private func deterministicEvents(
    sessionsById: [UUID: SDBPSession]
  ) -> [SDBPEvent] {
    events.sorted { left, right in
      let leftSession = sessionsById[left.session_id]
      let rightSession = sessionsById[right.session_id]
      let leftDate = leftSession?.session_date ?? ""
      let rightDate = rightSession?.session_date ?? ""
      if leftDate != rightDate { return leftDate > rightDate }

      let leftSource = leftSession?.source ?? ""
      let rightSource = rightSession?.source ?? ""
      if leftSource != rightSource { return leftSource < rightSource }

      let leftType = leftSession?.reps_type ?? ""
      let rightType = rightSession?.reps_type ?? ""
      if leftType != rightType { return leftType < rightType }

      let leftPitch = left.pitch_num ?? .max
      let rightPitch = right.pitch_num ?? .max
      if leftPitch != rightPitch { return leftPitch < rightPitch }

      return left.id.uuidString < right.id.uuidString
    }
  }

  private func reload() async {
    errorText = nil
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
