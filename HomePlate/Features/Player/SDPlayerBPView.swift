import SwiftUI
import UniformTypeIdentifiers

struct SDPlayerBPView: View {
  @EnvironmentObject private var appState: AppState

  @State private var date = Date()
  @State private var repsType = "practice"
  @State private var source = "rapsodo"

  @State private var isImporting = false
  @State private var isWorking = false
  @State private var errorText: String?
  @State private var successText: String?

  @State private var session: SDBPSession?
  @State private var events: [SDBPEvent] = []

  var body: some View {
    NavigationStack {
      HPListScreenLayout {
        HPWorkspaceHeader(
          "BP",
          context: "\(DateUtils.prettyDateTitle(date)) • \(BPImportSource.parse(source).label)"
        )
      } controls: {
        VStack(alignment: .leading, spacing: HP.Space.md) {
          HPCard {
            VStack(alignment: .leading, spacing: HP.Space.sm) {
              HPSectionHeader("Session")
              DatePicker("Date", selection: $date, displayedComponents: .date)
                .tint(HP.Color.accent)
                .onChange(of: date) { _, _ in Task { await loadSession() } }

              VStack(alignment: .leading, spacing: 6) {
                Text("Reps type")
                  .font(HP.Font.eyebrow)
                  .tracking(HP.Font.eyebrowTracking)
                  .foregroundStyle(HP.Color.textMuted)
                HPSegmentedControl(
                  options: [(value: "practice", label: "Practice"),
                            (value: "game", label: "Game")],
                  selection: $repsType
                )
                .onChange(of: repsType) { _, _ in Task { await loadSession() } }
              }

              VStack(alignment: .leading, spacing: 6) {
                Text("Upload type")
                  .font(HP.Font.eyebrow)
                  .tracking(HP.Font.eyebrowTracking)
                  .foregroundStyle(HP.Color.textMuted)
                HPSegmentedControl(
                  options: BPImportSource.allCases.map { (value: $0.rawValue, label: $0.label) },
                  selection: $source
                )
                .onChange(of: source) { _, _ in Task { await loadSession() } }
              }
            }
          }

          HPCard {
            VStack(alignment: .leading, spacing: HP.Space.sm) {
              HPSectionHeader("Upload") {
                HPStatusBadge(
                  text: "\(events.count) \(events.count == 1 ? "event" : "events")",
                  kind: .neutral
                )
              }
              HPButton(title: "Import CSV", systemImage: "square.and.arrow.down",
                       variant: .secondary, size: .md, isLoading: isWorking) {
                isImporting = true
              }
              .disabled(isWorking)
              Text("Upload Rapsodo, HitTrax, or TrackMan CSV files. The source is detected automatically when possible.")
                .font(HP.Font.caption)
                .foregroundStyle(HP.Color.textMuted)
                .fixedSize(horizontal: false, vertical: true)
            }
          }
        }
      } results: { context in
        VStack(alignment: .leading, spacing: HP.Space.md) {
          if !isWorking, !events.isEmpty {
            LazyVGrid(
              columns: context.gridColumns(compact: 2, regular: 3),
              spacing: HP.Space.sm
            ) {
              HPMetricCard(title: "Events", value: "\(events.count)", context: "Imported swings")
              HPMetricCard(title: "Max EV", value: fmt(events.compactMap(\.exit_velo).max() ?? 0),
                           unit: "mph", context: "This session")
              HPMetricCard(title: "Avg EV", value: fmt(avg(events.compactMap(\.exit_velo))),
                           unit: "mph", context: "This session")
            }
          }

          if isWorking {
            HPCard {
              HPLoadingState(text: "Working…")
            }
          } else if events.isEmpty {
            HPCard {
              HPEmptyState(
                title: "No pitch events",
                message: "No pitch events have been imported for this session yet.",
                systemImage: "baseball"
              )
            }
          }

          if !events.isEmpty {
            HPCard {
              VStack(alignment: .leading, spacing: HP.Space.sm) {
                HPSectionHeader("Events (first 20)")
                HPTable(
                  columns: [
                    HPColumn(title: "Pitch"),
                    HPColumn(title: "EV", alignment: .trailing, numeric: true),
                    HPColumn(title: "LA", alignment: .trailing, numeric: true),
                    HPColumn(title: "Distance", alignment: .trailing, numeric: true),
                  ],
                  rows: eventRows,
                  layout: context.tableLayout
                )
              }
            }
          }
        }
      }
      .navigationTitle("BP")
      .toolbar {
        ToolbarItem(placement: .primaryAction) {
          Menu {
            Button {
              Task { await loadSession() }
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
      .fileImporter(
        isPresented: $isImporting,
        allowedContentTypes: [UTType.commaSeparatedText, UTType.text, UTType.data],
        allowsMultipleSelection: false
      ) { result in
        switch result {
        case .failure(let err):
          errorText = err.localizedDescription
        case .success(let urls):
          guard let url = urls.first else { return }
          Task { await importCSV(url: url) }
        }
      }
      .alert("Error", isPresented: Binding(get: { errorText != nil }, set: { _ in errorText = nil })) {
        Button("OK", role: .cancel) {}
      } message: { Text(errorText ?? "") }
      .hpToast($successText)
      .task { await loadSession() }
    }
  }

  private var dateISO: String { DateUtils.toISODate(date) }

  private var eventRows: [HPTableRow] {
    events.prefix(20).map { event in
      HPTableRow(cells: [
        "#\(event.pitch_num ?? 0)",
        fmt(event.exit_velo ?? 0),
        fmt(event.launch_angle ?? 0),
        fmt(event.distance ?? 0),
      ])
    }
  }

  private func loadSession() async {
    guard let supabase = appState.supabase else { return }
    isWorking = true
    defer { isWorking = false }
    do {
      let sessionAuth = try await supabase.client.auth.session
      let uid = sessionAuth.user.id
      session = try await supabase.upsertBPSession(playerId: uid, dateISO: dateISO, source: source, repsType: repsType, orgId: appState.activeOrgId)
      if let session {
        events = try await supabase.fetchBPEvents(sessionId: session.id)
      } else {
        events = []
      }
    } catch {
      errorText = error.localizedDescription
    }
  }

  private func importCSV(url: URL) async {
    guard let supabase = appState.supabase else { return }
    isWorking = true
    defer { isWorking = false }
    do {
      let text = try CSVFileReader.readText(from: url)
      let importResult = try BPImportMapper.map(text: text, selectedSource: BPImportSource.parse(source))
      source = importResult.source.rawValue
      let sessionAuth = try await supabase.client.auth.session
      let uid = sessionAuth.user.id
      let s = try await supabase.upsertBPSession(playerId: uid, dateISO: dateISO, source: importResult.source.rawValue, repsType: repsType, orgId: appState.activeOrgId)
      session = s
      let creates = importResult.rows.enumerated().map { idx, row in
        SDBPEventCreate(
          session_id: s.id,
          pitch_num: row.pitch_num ?? (idx + 1),
          exit_velo: row.exit_velo,
          distance: row.distance,
          launch_angle: row.launch_angle,
          strike_x: row.strike_x,
          strike_z: row.strike_z,
          raw: row.raw
        )
      }
      try await supabase.replaceBPEvents(sessionId: s.id, events: creates)
      events = try await supabase.fetchBPEvents(sessionId: s.id)
      toast("Imported \(events.count) \(importResult.source.label) events.")
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
    // Flexible header matching (Rapsodo exports vary).
    func idx(where predicate: (String) -> Bool) -> Int? {
      header.enumerated().first(where: { predicate($0.element.lowercased()) })?.offset
    }

    let pitchIdx = idx { $0.contains("pitch") && $0.contains("num") } ?? idx { $0 == "pitch_num" }
    let evIdx = idx { $0.contains("exit") && $0.contains("velo") } ?? idx { $0 == "exitvelocity" } ?? idx { $0 == "exit velo" }
    let distIdx = idx { $0.contains("dist") } ?? idx { $0.contains("carry") }
    let laIdx = idx { $0.contains("launch") && $0.contains("angle") } ?? idx { $0 == "launchangle" }
    let xIdx = idx { ($0.contains("plate") || $0.contains("strike")) && $0.contains("x") }
    let zIdx = idx { ($0.contains("plate") || $0.contains("strike")) && ($0.contains("z") || $0.contains("height")) }

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
    .filter { $0.exit_velo != nil || $0.launch_angle != nil || $0.distance != nil }
  }

  private func toast(_ text: String) {
    withAnimation { successText = text }
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
      withAnimation { successText = nil }
    }
  }

  private func avg(_ xs: [Double]) -> Double {
    guard !xs.isEmpty else { return 0 }
    return xs.reduce(0, +) / Double(xs.count)
  }

  private func fmt(_ v: Double) -> String {
    if v == 0 { return "0" }
    if v.rounded() == v { return String(Int(v)) }
    return String(format: "%.1f", v)
  }
}
