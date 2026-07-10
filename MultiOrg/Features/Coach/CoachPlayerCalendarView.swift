import SwiftUI
import UniformTypeIdentifiers

/// Coach-facing calendar for a player (month grid + day tap -> view-only day details).
struct CoachPlayerCalendarView: View {
  @EnvironmentObject private var appState: AppState
  let player: Profile

  @State private var assignment: SDProgramAssignment?
  @State private var template: SDProgramTemplate?
  @State private var bpSessions: [SDBPSession] = []
  @State private var isLoading = false
  @State private var errorText: String?

  @State private var visibleMonth: Date = DateUtils.startOfMonthET(Date())
  @State private var scheduledLiftISOs: Set<String> = []
  @State private var practiceISOs: Set<String> = []
  @State private var gameISOs: Set<String> = []
  @State private var selectedDate: Date = DateUtils.startOfDayET(Date())
  @State private var daySheet: DaySheet?

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 14) {
        DHDMonthGridView(
          visibleMonth: $visibleMonth,
          selectedDate: $selectedDate,
          scheduledLiftISOs: scheduledLiftISOs,
          practiceISOs: practiceISOs,
          gameISOs: gameISOs,
          isLoading: isLoading,
          onPrev: {
            visibleMonth = DateUtils.startOfMonthET(DateUtils.addMonthsET(visibleMonth, value: -1))
            rebuildMonthGrid()
          },
          onNext: {
            visibleMonth = DateUtils.startOfMonthET(DateUtils.addMonthsET(visibleMonth, value: 1))
            rebuildMonthGrid()
          },
          onSelect: { d in
            let sd = DateUtils.startOfDayET(d)
            selectedDate = sd
            daySheet = DaySheet(date: sd)
          }
        )

        Text("Green = scheduled lift day. Blue = BP/practice. Red = game reps.")
          .font(.footnote)
          .foregroundStyle(DHDTheme.textSecondary)
          .padding(.top, 2)
      }
      .padding(DHDTheme.pagePadding)
      .frame(maxWidth: .infinity, alignment: .leading)
      .frame(maxHeight: .infinity, alignment: .topLeading)
    }
    .alert("Error", isPresented: Binding(get: { errorText != nil }, set: { _ in errorText = nil })) {
      Button("OK", role: .cancel) {}
    } message: { Text(errorText ?? "") }
    .task { await reload() }
    #if os(macOS)
    .dhdFloatingModal(item: $daySheet, width: 920, height: 680) { s in
      NavigationStack {
        CoachPlayerDayDetailView(player: player, date: s.date)
          .navigationTitle(DateUtils.toISODate(s.date))
          .toolbar {
            ToolbarItem(placement: .cancellationAction) {
              Button("Close") { daySheet = nil }
            }
          }
      }
    }
    #else
    .sheet(item: $daySheet) { s in
      NavigationStack {
        CoachPlayerDayDetailView(player: player, date: s.date)
          .navigationTitle(DateUtils.toISODate(s.date))
          .navigationBarTitleDisplayMode(.inline)
      }
    }
    #endif
  }

  private func reload() async {
    guard let supabase = appState.supabase else { return }
    isLoading = true
    defer { isLoading = false }
    do {
      assignment = try await supabase.fetchActiveAssignment(playerId: player.id)
      if let assignment {
        template = try await supabase.fetchTemplate(id: assignment.template_id)
      } else {
        template = nil
      }
      bpSessions = try await supabase.listBPSessions(playerId: player.id, limit: 365)
      rebuildMonthGrid()
    } catch {
      errorText = error.localizedDescription
    }
  }

  private func rebuildMonthGrid() {
    scheduledLiftISOs = scheduledLiftSet(for: visibleMonth)
    practiceISOs = Set(bpSessions.filter { $0.reps_type == "practice" }.map(\.session_date))
    gameISOs = Set(bpSessions.filter { $0.reps_type == "game" }.map(\.session_date))
  }

  private func scheduledLiftSet(for monthStart: Date) -> Set<String> {
    guard let assignment, let template else { return [] }
    let first = DateUtils.startOfMonthET(monthStart)
    let days = DateUtils.daysInMonthET(first)
    var out: Set<String> = []
    for i in 0..<days {
      guard let d = DateUtils.calendarET.date(byAdding: .day, value: i, to: first) else { continue }
      if SDProgramSchedule.context(for: d, assignment: assignment, template: template).isScheduled {
        out.insert(DateUtils.toISODate(d))
      }
    }
    return out
  }
}

private struct DaySheet: Identifiable {
  let id = UUID()
  let date: Date
}

private struct CoachPlayerDayDetailView: View {
  let player: Profile
  let date: Date

  var body: some View {
    CoachPlayerDailyLogDetailView(player: player, dateISO: DateUtils.toISODate(date))
  }
}

private struct CoachPlayerDailyLogDetailView: View {
  @EnvironmentObject private var appState: AppState
  let player: Profile
  let dateISO: String

  @State private var log: SDDailyLog?
  @State private var strength: [SDStrengthLog] = []
  @State private var sessions: [SDBPSession] = []
  @State private var bpEvents: [SDBPEvent] = []
  @State private var isLoading = false
  @State private var errorText: String?
  @State private var toastText: String?

  @State private var isImporting = false
  @State private var importSource = "rapsodo"
  @State private var importRepsType = "practice"

  var body: some View {
    List {
      if isLoading {
        HStack(spacing: 10) { ProgressView(); Text("Loading…").foregroundStyle(DHDTheme.textSecondary) }
      }

      Section("Self assessment") {
        row("Got video", log?.got_video)
        row("Ate breakfast", log?.ate_breakfast)
        row("Hit daily goals", log?.hit_daily_goals)
        row("Stuck to process", log?.stuck_to_process)
        if let t = log?.fell_short, !t.isEmpty { Text("Fell short: \(t)") }
        if let t = log?.excelled, !t.isEmpty { Text("Excelled: \(t)") }
      }

      if let c = log?.comments, !c.isEmpty || log?.feel != nil {
        Section("Lift note") {
          if let f = log?.feel { Text("Feel: \(f)") }
          if let c = log?.comments, !c.isEmpty { Text(c) }
        }
      }

      Section("Strength logs") {
        if strength.isEmpty {
          Text("No strength logs for this day.").foregroundStyle(DHDTheme.textSecondary)
        } else {
          ForEach(strength) { s in
            VStack(alignment: .leading, spacing: 4) {
              Text(s.exercise_name).font(.headline)
              if s.no_weight {
                Text("No weight • Sets completed: \(s.sets_completed ?? 0)").font(.caption).foregroundStyle(DHDTheme.textSecondary)
              } else if let w = s.set_weights_json, !w.isEmpty {
                Text("Weights: " + w.joined(separator: ", ")).font(.caption).foregroundStyle(DHDTheme.textSecondary)
              } else {
                Text("No weights logged").font(.caption).foregroundStyle(DHDTheme.textSecondary)
              }
              if let n = s.notes, !n.isEmpty {
                Text(n).font(.caption).foregroundStyle(DHDTheme.textSecondary)
              }
            }
            .padding(.vertical, 4)
          }
        }
      }

      Section("BP sessions") {
        // Coach import UI (server-side), replaces events for the selected day/type.
        VStack(alignment: .leading, spacing: 10) {
          HStack(spacing: 10) {
            Picker("Type", selection: $importRepsType) {
              Text("Practice").tag("practice")
              Text("Game").tag("game")
            }
            .pickerStyle(.menu)

            Picker("Source", selection: $importSource) {
              Text("Rapsodo").tag("rapsodo")
              Text("HitTrax").tag("hitrax")
            }
            .pickerStyle(.menu)

            Spacer()

            Button {
              isImporting = true
            } label: {
              Label("Upload CSV…", systemImage: "square.and.arrow.up")
            }
          }

          Text("Uploading replaces BP events for this date/source/type.")
            .font(.caption)
            .foregroundStyle(DHDTheme.textSecondary)
        }

        if sessions.isEmpty {
          Text("No BP session for this day.").foregroundStyle(DHDTheme.textSecondary)
        } else {
          ForEach(sessions) { s in
            VStack(alignment: .leading, spacing: 4) {
              Text("\(s.source.uppercased()) • \(s.reps_type)")
                .font(.headline)
              Text("Events: \(bpEvents.count)")
                .font(.caption)
                .foregroundStyle(DHDTheme.textSecondary)
            }
          }
        }
      }
    }
    .dhdPageBackground()
    .navigationTitle(dateISO)
    .dhdToast($toastText)
    .alert("Error", isPresented: Binding(get: { errorText != nil }, set: { _ in errorText = nil })) {
      Button("OK", role: .cancel) {}
    } message: { Text(errorText ?? "") }
    .fileImporter(
      isPresented: $isImporting,
      allowedContentTypes: [UTType.commaSeparatedText, UTType.text, UTType.data],
      allowsMultipleSelection: false
    ) { result in
      switch result {
      case .failure(let err):
        isImporting = false
        errorText = err.localizedDescription
      case .success(let urls):
        isImporting = false
        guard let url = urls.first else { return }
        Task { await importCSV(url: url) }
      }
    }
    .task { await reload() }
  }

  private func reload() async {
    guard let supabase = appState.supabase else { return }
    isLoading = true
    defer { isLoading = false }
    do {
      log = try await supabase.fetchDailyLog(playerId: player.id, dateISO: dateISO)
      strength = try await supabase.fetchStrengthLogs(playerId: player.id, dateISO: dateISO)
      let all = try await supabase.listBPSessions(playerId: player.id, limit: 365)
      sessions = all.filter { $0.session_date == dateISO }
      bpEvents = []
      for s in sessions {
        let ev = try await supabase.fetchBPEvents(sessionId: s.id)
        bpEvents.append(contentsOf: ev)
      }
    } catch {
      errorText = error.localizedDescription
    }
  }

  private func importCSV(url: URL) async {
    guard let supabase = appState.supabase else { return }
    isLoading = true
    defer { isLoading = false }
    do {
      let data = try Data(contentsOf: url)
      guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
        throw NSError(domain: "CSV", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not read file as text."])
      }
      let rows = CSV.parse(text: text)

      if importSource != "rapsodo" {
        throw NSError(domain: "CSV", code: 3, userInfo: [NSLocalizedDescriptionKey: "HitTrax mapping is not enabled yet. Use Rapsodo for now."])
      }

      // Rapsodo exports often include metadata lines before the actual header.
      // Detect the real header row so we don't import all-null events.
      guard let table = CSV.asTableDetectingHeader(
        rows: rows,
        requiredColumns: ["ExitVelocity", "LaunchAngle", "Distance"]
      ) else {
        throw NSError(domain: "CSV", code: 2, userInfo: [NSLocalizedDescriptionKey: "Empty CSV."])
      }

      let mapped = mapRapsodo(header: table.header, rows: table.body)
      let creates: [SDBPEventCreate] = mapped.enumerated().map { idx, r in
        SDBPEventCreate(
          session_id: UUID(), // placeholder; Edge Function ignores this field
          pitch_num: r.pitch_num ?? (idx + 1),
          exit_velo: r.exit_velo,
          distance: r.distance,
          launch_angle: r.launch_angle,
          strike_x: r.strike_x,
          strike_z: r.strike_z,
          raw: r.raw
        )
      }

      // Sanity check: if we couldn't map any core metric columns, fail fast with a helpful message.
      let mappedMetricCount = creates.reduce(0) { acc, e in
        acc + ((e.exit_velo != nil || e.distance != nil || e.launch_angle != nil) ? 1 : 0)
      }
      if mappedMetricCount == 0 {
        throw NSError(
          domain: "CSV",
          code: 4,
          userInfo: [NSLocalizedDescriptionKey: "Could not detect Rapsodo columns for ExitVelocity/Distance/LaunchAngle. Please verify this is a Rapsodo hitting export CSV."]
        )
      }

      _ = try await supabase.coachReplaceBPEvents(
        playerId: player.id,
        dateISO: dateISO,
        source: importSource,
        repsType: importRepsType,
        events: creates
      )
      toastText = "Imported \(creates.count) BP events."
      await reload()
    } catch {
      errorText = error.localizedDescription
    }
  }

  private struct MappedRow {
    var pitch_num: Int?
    var exit_velo: Double?
    var distance: Double?
    var launch_angle: Double?
    var strike_x: Double?
    var strike_z: Double?
    var raw: [String: String]
  }

  private func mapRapsodo(header: [String], rows: [[String]]) -> [MappedRow] {
    func idx(where predicate: (String) -> Bool) -> Int? {
      header.enumerated().first(where: { predicate($0.element.lowercased()) })?.offset
    }

    let pitchIdx = idx { $0.contains("pitch") && $0.contains("num") } ?? idx { $0 == "pitch_num" }
    let evIdx = idx { $0.contains("exit") && $0.contains("velo") } ?? idx { $0 == "exitvelocity" } ?? idx { $0 == "exit velo" }
    let distIdx = idx { $0.contains("dist") } ?? idx { $0.contains("carry") }
    let laIdx = idx { $0.contains("launch") && $0.contains("angle") } ?? idx { $0 == "launchangle" }

    // Strike-zone coordinates: accept common aliases.
    let xIdx = idx { $0.contains("strikezonex") } ?? idx { ($0.contains("plate") || $0.contains("strike")) && $0.contains("side") }
      ?? idx { ($0.contains("plate") || $0.contains("strike")) && $0.contains("x") }
    let zIdx = idx { $0.contains("strikezoney") } ?? idx { ($0.contains("plate") || $0.contains("strike")) && ($0.contains("height") || $0.contains("z")) }

    func asDouble(_ s: String) -> Double? {
      let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
      if t.isEmpty { return nil }
      return Double(t)
    }
    func asInt(_ s: String) -> Int? {
      let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
      if t.isEmpty { return nil }
      return Int(t)
    }

    return rows.map { r in
      var raw: [String: String] = [:]
      for (i, h) in header.enumerated() {
        if i < r.count {
          let v = r[i].trimmingCharacters(in: .whitespacesAndNewlines)
          if !v.isEmpty { raw[h] = v }
        }
      }
      return MappedRow(
        pitch_num: pitchIdx.flatMap { $0 < r.count ? asInt(r[$0]) : nil },
        exit_velo: evIdx.flatMap { $0 < r.count ? asDouble(r[$0]) : nil },
        distance: distIdx.flatMap { $0 < r.count ? asDouble(r[$0]) : nil },
        launch_angle: laIdx.flatMap { $0 < r.count ? asDouble(r[$0]) : nil },
        strike_x: xIdx.flatMap { $0 < r.count ? asDouble(r[$0]) : nil },
        strike_z: zIdx.flatMap { $0 < r.count ? asDouble(r[$0]) : nil },
        raw: raw
      )
    }
  }

  @ViewBuilder private func row(_ label: String, _ value: Bool?) -> some View {
    HStack {
      Text(label)
      Spacer()
      if value == true {
        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
      } else if value == false {
        Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
      } else {
        Text("—").foregroundStyle(DHDTheme.textSecondary)
      }
    }
  }
}
