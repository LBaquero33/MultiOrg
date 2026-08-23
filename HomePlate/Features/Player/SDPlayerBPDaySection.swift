import SwiftUI
import UniformTypeIdentifiers

/// Reusable "BP for a day" section for Today / Day Detail.
struct SDPlayerBPDaySection: View {
  @EnvironmentObject private var appState: AppState

  let date: Date

  @State private var isExpanded = false
  @State private var didBP = false
  @State private var activityType = "bp"
  @State private var repsType = "practice"
  @State private var source = "rapsodo"
  @State private var importKind = "data"
  @State private var isImporting = false
  @State private var isImportingVideo = false
  @State private var isWorking = false
  @State private var errorText: String?
  @State private var toastText: String?

  @State private var session: SDBPSession?
  @State private var events: [SDBPEvent] = []

  var body: some View {
    HPCard {
      DisclosureGroup(isExpanded: $isExpanded) {
        VStack(alignment: .leading, spacing: HP.Space.sm) {
          Toggle("Did you train hitting or throw a bullpen today?", isOn: $didBP)
            .font(HP.Font.callout)
            .foregroundStyle(HP.Color.text)
            .tint(HP.Color.accent)
            .onChange(of: didBP) { _, newValue in
              if newValue {
                isExpanded = true
                Task { await loadSession() }
              }
            }

          if didBP {
            VStack(alignment: .leading, spacing: 6) {
              Text("Session")
                .font(HP.Font.eyebrow).tracking(HP.Font.eyebrowTracking)
                .foregroundStyle(HP.Color.textMuted)
              HPSegmentedControl(
                options: [(value: "bp", label: "Hitting"), (value: "bullpen", label: "Bullpen")],
                selection: $activityType
              )
              .onChange(of: activityType) { _, newValue in
                if newValue == "bullpen" { importKind = "video" }
                Task { await loadSession() }
              }
            }

            VStack(alignment: .leading, spacing: 6) {
              Text("Reps type")
                .font(HP.Font.eyebrow).tracking(HP.Font.eyebrowTracking)
                .foregroundStyle(HP.Color.textMuted)
              HPSegmentedControl(
                options: [(value: "practice", label: "Practice"), (value: "game", label: "Game")],
                selection: $repsType
              )
              .onChange(of: repsType) { _, _ in Task { await loadSession() } }
            }

            if activityType == "bp" {
              VStack(alignment: .leading, spacing: 6) {
                Text("Upload method")
                  .font(HP.Font.eyebrow).tracking(HP.Font.eyebrowTracking)
                  .foregroundStyle(HP.Color.textMuted)
                HPSegmentedControl(
                  options: [(value: "data", label: "Data file"), (value: "video", label: "Video")],
                  selection: $importKind
                )
                .onChange(of: importKind) { _, _ in Task { await loadSession() } }
              }
            }

            if activityType == "bp" && importKind == "data" {
              VStack(alignment: .leading, spacing: 6) {
                Text("Data source")
                  .font(HP.Font.eyebrow).tracking(HP.Font.eyebrowTracking)
                  .foregroundStyle(HP.Color.textMuted)
                HPSegmentedControl(
                  options: BPImportSource.allCases.map { (value: $0.rawValue, label: $0.label) },
                  selection: $source
                )
                .onChange(of: source) { _, _ in Task { await loadSession() } }
              }

              HPButton(title: "Import CSV", systemImage: "tablecells",
                       variant: .secondary, size: .md, isLoading: isWorking) {
                isImportingVideo = false
                isImporting = true
              }
              .disabled(isWorking)
            } else {
              Text(activityType == "bullpen"
                   ? "Upload a bullpen video for your coaches."
                   : "Upload a hitting video instead of a data file.")
                .font(HP.Font.callout)
                .foregroundStyle(HP.Color.textMuted)

              HPButton(
                title: activityType == "bullpen" ? "Upload bullpen video" : "Upload hitting video",
                systemImage: "video.badge.plus",
                variant: .secondary,
                size: .md,
                isLoading: isWorking
              ) {
                isImportingVideo = true
                isImporting = true
              }
              .disabled(isWorking)

              if session?.video_path != nil {
                Label("Video uploaded", systemImage: "checkmark.circle.fill")
                  .font(HP.Font.callout.weight(.semibold))
                  .foregroundStyle(HP.Color.success)
              }
            }

            if activityType == "bp" && importKind == "data" {
              if events.isEmpty {
                Text("No BP pitch events imported yet for this date.")
                  .font(HP.Font.callout)
                  .foregroundStyle(HP.Color.textMuted)
              } else {
                let evs = events.compactMap(\.exit_velo)
                let maxEV = evs.max() ?? 0
                let avgEV = avg(evs)
                VStack(alignment: .leading, spacing: 4) {
                  HPStatTile(label: "Events", value: "\(events.count)")
                  HPStatTile(label: "Max EV", value: "\(fmt(maxEV)) mph")
                  HPStatTile(label: "Avg EV", value: "\(fmt(avgEV)) mph")
                }
              }

              if !events.isEmpty {
                Text("First 12 events")
                  .font(HP.Font.eyebrow).tracking(HP.Font.eyebrowTracking)
                  .foregroundStyle(HP.Color.textMuted)
                ForEach(Array(events.prefix(12))) { e in
                  Text("#\(e.pitch_num ?? 0) • EV \(fmt(e.exit_velo ?? 0)) • LA \(fmt(e.launch_angle ?? 0)) • Dist \(fmt(e.distance ?? 0))")
                    .font(HP.Font.caption)
                    .foregroundStyle(HP.Color.textMuted)
                }
              }
            }
          } else {
            Text("BP details stay hidden on off days.")
              .font(HP.Font.caption)
              .foregroundStyle(HP.Color.textMuted)
          }
        }
        .padding(.top, HP.Space.sm)
      } label: {
        Text("Hitting & Bullpens")
          .font(HP.Font.headline)
          .foregroundStyle(HP.Color.text)
      }
      .tint(HP.Color.accent)
    }
    .fileImporter(
      isPresented: $isImporting,
      allowedContentTypes: isImportingVideo
        ? [UTType.movie, UTType.mpeg4Movie, UTType.quickTimeMovie]
        : [UTType.commaSeparatedText, UTType.text, UTType.data],
      allowsMultipleSelection: false
    ) { result in
      switch result {
      case .failure(let err):
        errorText = err.localizedDescription
      case .success(let urls):
        guard let url = urls.first else { return }
        Task {
          if isImportingVideo {
            await importVideo(url: url)
          } else {
            await importCSV(url: url)
          }
        }
      }
    }
    .alert("Error", isPresented: Binding(get: { errorText != nil }, set: { _ in errorText = nil })) {
      Button("OK", role: .cancel) {}
    } message: { Text(errorText ?? "") }
    .hpToast($toastText)
    .task {
      await inferExisting()
    }
  }

  private var dateISO: String { DateUtils.toISODate(date) }

  private func inferExisting() async {
    // If a hitting or bullpen session exists, restore its input mode.
    guard let supabase = appState.supabase else { return }
    do {
      let sessionAuth = try await supabase.client.auth.session
      let uid = sessionAuth.user.id
      let all = try await supabase.listBPSessions(playerId: uid, limit: 120)
      if all.contains(where: { $0.session_date == dateISO }) {
        didBP = true
        isExpanded = true
        if let s = all.first(where: {
          $0.session_date == dateISO
            && ($0.activity_type ?? "bp") == activityType
            && $0.reps_type == repsType
            && $0.source == activeSource
        }) {
          session = s
          events = try await supabase.fetchBPEvents(sessionId: s.id)
        } else if let s = all.first(where: { $0.session_date == dateISO }) {
          activityType = s.activity_type ?? "bp"
          repsType = s.reps_type
          importKind = s.source == "video" ? "video" : "data"
          if s.source != "video" { source = s.source }
          session = s
          events = try await supabase.fetchBPEvents(sessionId: s.id)
        }
      }
    } catch {
      // ignore
    }
  }

  private func loadSession() async {
    guard didBP else { return }
    guard let supabase = appState.supabase else { return }
    isWorking = true
    defer { isWorking = false }
    do {
      let sessionAuth = try await supabase.client.auth.session
      let uid = sessionAuth.user.id
      let s = try await supabase.upsertBPSession(
        playerId: uid,
        dateISO: dateISO,
        source: activeSource,
        repsType: repsType,
        activityType: activityType,
        orgId: appState.activeOrgId
      )
      session = s
      events = try await supabase.fetchBPEvents(sessionId: s.id)
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
      let s = try await supabase.upsertBPSession(
        playerId: uid,
        dateISO: dateISO,
        source: importResult.source.rawValue,
        repsType: repsType,
        activityType: "bp",
        orgId: appState.activeOrgId
      )
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

  private var activeSource: String {
    activityType == "bullpen" || importKind == "video" ? "video" : source
  }

  private func importVideo(url: URL) async {
    guard let supabase = appState.supabase,
          let organizationId = appState.activeOrgId else { return }
    isWorking = true
    defer { isWorking = false }
    let accessed = url.startAccessingSecurityScopedResource()
    defer { if accessed { url.stopAccessingSecurityScopedResource() } }
    do {
      let values = try url.resourceValues(forKeys: [.fileSizeKey])
      if let size = values.fileSize, size > 262_144_000 {
        throw NSError(
          domain: "HomePlate",
          code: 2,
          userInfo: [NSLocalizedDescriptionKey: "Videos must be 250 MB or smaller."]
        )
      }
      let sourceData = try Data(contentsOf: url)
      let data = try await CompatibleVideoTranscoder.mp4Data(
        from: sourceData,
        sourceExtension: url.pathExtension.lowercased()
      )
      let playerId = try await supabase.client.auth.session.user.id
      let path = try await supabase.uploadPlayerSessionVideo(
        data,
        organizationId: organizationId,
        playerId: playerId,
        fileExtension: "mp4",
        contentType: "video/mp4"
      )
      session = try await supabase.upsertBPSession(
        playerId: playerId,
        dateISO: dateISO,
        source: "video",
        repsType: repsType,
        activityType: activityType,
        videoPath: path,
        orgId: organizationId
      )
      events = []
      toast(activityType == "bullpen" ? "Bullpen video uploaded." : "Hitting video uploaded.")
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
    .filter { $0.exit_velo != nil || $0.launch_angle != nil || $0.distance != nil }
  }

  private func toast(_ text: String) {
    withAnimation { toastText = text }
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
      withAnimation { toastText = nil }
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
