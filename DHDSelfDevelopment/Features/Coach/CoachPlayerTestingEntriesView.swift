import SwiftUI

struct CoachPlayerTestingEntriesView: View {
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
      if entries.isEmpty, !isLoading {
        Text("No testing entries yet.")
          .foregroundStyle(.secondary)
      } else {
        ForEach(entries) { e in
          VStack(alignment: .leading, spacing: 4) {
            Text(e.entry_date).font(.headline)
            Text(summary(e)).font(.caption).foregroundStyle(.secondary)
          }
          .padding(.vertical, 4)
        }
      }
    }
    .navigationTitle("Testing")
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
      entries = try await supabase.listTestingEntries(playerId: player.id)
    } catch {
      errorText = error.localizedDescription
    }
  }

  private func summary(_ e: SDTestingEntry) -> String {
    var parts: [String] = []
    if let v = e.height_in { parts.append("Ht \(fmt(v))") }
    if let v = e.weight_lb { parts.append("Wt \(fmt(v))") }
    if let v = e.squat_1rm { parts.append("Sq \(fmt(v))") }
    if let v = e.bench_1rm { parts.append("Bn \(fmt(v))") }
    if let v = e.deadlift_1rm { parts.append("Dl \(fmt(v))") }
    if let v = e.max_exit_velo { parts.append("MaxEV \(fmt(v))") }
    if let v = e.avg_exit_velo { parts.append("AvgEV \(fmt(v))") }
    return parts.isEmpty ? "—" : parts.joined(separator: " • ")
  }

  private func fmt(_ v: Double) -> String {
    if v.rounded() == v { return String(Int(v)) }
    return String(format: "%.1f", v)
  }
}

