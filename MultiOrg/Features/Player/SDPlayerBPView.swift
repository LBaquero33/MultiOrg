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
      List {
        Section("Session") {
          DatePicker("Date", selection: $date, displayedComponents: .date)
            .onChange(of: date) { _, _ in Task { await loadSession() } }
          Picker("Reps type", selection: $repsType) {
            Text("Practice").tag("practice")
            Text("Game").tag("game")
          }
          .onChange(of: repsType) { _, _ in Task { await loadSession() } }
          Picker("Upload type", selection: $source) {
            ForEach(BPImportSource.allCases) { importSource in
              Text(importSource.label).tag(importSource.rawValue)
            }
          }
          .onChange(of: source) { _, _ in Task { await loadSession() } }
        }

        Section("Upload") {
          Button {
            isImporting = true
          } label: {
            Label("Import CSV", systemImage: "square.and.arrow.down")
          }
          .disabled(isWorking)
          Text("Upload Rapsodo, HitTrax, or TrackMan CSV files. The source is detected automatically when possible.")
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        Section("Summary") {
          if isWorking {
            HStack(spacing: 10) { ProgressView(); Text("Working…").foregroundStyle(.secondary) }
          } else if events.isEmpty {
            Text("No pitch events imported yet for this session.")
              .foregroundStyle(.secondary)
          } else {
            let maxEV = events.compactMap(\.exit_velo).max() ?? 0
            let avgEV = avg(events.compactMap(\.exit_velo))
            Text("Events: \(events.count)")
            Text("Max EV: \(fmt(maxEV))")
            Text("Avg EV: \(fmt(avgEV))")
          }
        }

        if !events.isEmpty {
          Section("Events (first 20)") {
            ForEach(Array(events.prefix(20))) { e in
              HStack {
                Text("#\(e.pitch_num ?? 0)").foregroundStyle(.secondary)
                Spacer()
                Text("EV \(fmt(e.exit_velo ?? 0))  LA \(fmt(e.launch_angle ?? 0))  Dist \(fmt(e.distance ?? 0))")
                  .font(.caption)
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
      .overlay(alignment: .top) {
        if let successText {
          Text(successText)
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.thinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .padding(.top, 10)
            .transition(.opacity)
        }
      }
      .task { await loadSession() }
    }
  }

  private var dateISO: String { DateUtils.toISODate(date) }

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
