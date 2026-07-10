import SwiftUI

struct CoachPlayerDailyLogsView: View {
  @EnvironmentObject private var appState: AppState
  let player: Profile

  @State private var logs: [SDDailyLog] = []
  @State private var isLoading = false
  @State private var errorText: String?

  var body: some View {
    List {
      if isLoading {
        HStack(spacing: 10) { ProgressView(); Text("Loading…").foregroundStyle(.secondary) }
      }
      if logs.isEmpty, !isLoading {
        Text("No daily logs yet.")
          .foregroundStyle(.secondary)
      } else {
        Section("Recent days") {
          ForEach(logs) { l in
            NavigationLink {
              CoachPlayerDailyLogDetailView(player: player, dateISO: l.log_date)
            } label: {
              VStack(alignment: .leading, spacing: 4) {
                Text(l.log_date).font(.headline)
                Text(summary(l)).font(.caption).foregroundStyle(.secondary)
              }
              .padding(.vertical, 4)
            }
          }
        }
      }
    }
    .navigationTitle("Daily logs")
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
      logs = try await supabase.listDailyLogs(playerId: player.id, limit: 60)
    } catch {
      errorText = error.localizedDescription
    }
  }

  private func summary(_ l: SDDailyLog) -> String {
    var bits: [String] = []
    if let f = l.feel { bits.append("Feel \(f)") }
    if let v = l.got_video, v { bits.append("Video") }
    if let b = l.ate_breakfast, b { bits.append("Breakfast") }
    if let g = l.hit_daily_goals, g { bits.append("Goals") }
    if let p = l.stuck_to_process, p { bits.append("Process") }
    return bits.isEmpty ? "—" : bits.joined(separator: " • ")
  }
}

private struct CoachPlayerDailyLogDetailView: View {
  @EnvironmentObject private var appState: AppState
  let player: Profile
  let dateISO: String

  @State private var log: SDDailyLog?
  @State private var strength: [SDStrengthLog] = []
  @State private var isLoading = false
  @State private var errorText: String?

  var body: some View {
    List {
      if isLoading {
        HStack(spacing: 10) { ProgressView(); Text("Loading…").foregroundStyle(.secondary) }
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
          Text("No strength logs for this day.").foregroundStyle(.secondary)
        } else {
          ForEach(strength) { s in
            VStack(alignment: .leading, spacing: 4) {
              Text(s.exercise_name).font(.headline)
              if s.no_weight {
                Text("No weight • Sets completed: \(s.sets_completed ?? 0)").font(.caption).foregroundStyle(.secondary)
              } else if let w = s.set_weights_json, !w.isEmpty {
                Text("Weights: " + w.joined(separator: ", ")).font(.caption).foregroundStyle(.secondary)
              } else {
                Text("No weights logged").font(.caption).foregroundStyle(.secondary)
              }
              if let n = s.notes, !n.isEmpty {
                Text(n).font(.caption).foregroundStyle(.secondary)
              }
            }
            .padding(.vertical, 4)
          }
        }
      }
    }
    .navigationTitle(dateISO)
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
      log = try await supabase.fetchDailyLog(playerId: player.id, dateISO: dateISO)
      strength = try await supabase.fetchStrengthLogs(playerId: player.id, dateISO: dateISO)
    } catch {
      errorText = error.localizedDescription
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
        Text("—").foregroundStyle(.secondary)
      }
    }
  }
}

