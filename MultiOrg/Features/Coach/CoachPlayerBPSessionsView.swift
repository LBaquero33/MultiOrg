import SwiftUI

struct CoachPlayerBPSessionsView: View {
  @EnvironmentObject private var appState: AppState
  let player: Profile

  @State private var sessions: [SDBPSession] = []
  @State private var isLoading = false
  @State private var errorText: String?

  var body: some View {
    List {
      if isLoading {
        HStack(spacing: 10) { ProgressView(); Text("Loading…").foregroundStyle(.secondary) }
      }
      if sessions.isEmpty, !isLoading {
        Text("No BP sessions yet.")
          .foregroundStyle(.secondary)
      } else {
        Section("Sessions") {
          ForEach(sessions) { s in
            NavigationLink {
              CoachPlayerBPSessionDetailView(session: s)
            } label: {
              VStack(alignment: .leading, spacing: 2) {
                Text("\(s.session_date) • \(s.reps_type.capitalized)").font(.headline)
                Text(s.source.capitalized).font(.caption).foregroundStyle(.secondary)
              }
              .padding(.vertical, 4)
            }
          }
        }
      }
    }
    .navigationTitle("BP")
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
      sessions = try await supabase.listBPSessions(playerId: player.id, limit: 120)
    } catch {
      errorText = error.localizedDescription
    }
  }
}

private struct CoachPlayerBPSessionDetailView: View {
  @EnvironmentObject private var appState: AppState
  let session: SDBPSession

  @State private var events: [SDBPEvent] = []
  @State private var isLoading = false
  @State private var errorText: String?

  var body: some View {
    List {
      Section("Summary") {
        if isLoading {
          HStack(spacing: 10) { ProgressView(); Text("Loading…").foregroundStyle(.secondary) }
        } else if events.isEmpty {
          Text("No events.")
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
        Section("Events (first 30)") {
          ForEach(Array(events.prefix(30))) { e in
            Text("EV \(fmt(e.exit_velo ?? 0)) • LA \(fmt(e.launch_angle ?? 0)) • Dist \(fmt(e.distance ?? 0))")
              .font(.caption)
          }
        }
      }
    }
    .navigationTitle(session.session_date)
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
      events = try await supabase.fetchBPEvents(sessionId: session.id)
    } catch {
      errorText = error.localizedDescription
    }
  }

  private func avg(_ xs: [Double]) -> Double { xs.isEmpty ? 0 : xs.reduce(0, +) / Double(xs.count) }
  private func fmt(_ v: Double) -> String { v.rounded() == v ? String(Int(v)) : String(format: "%.1f", v) }
}

