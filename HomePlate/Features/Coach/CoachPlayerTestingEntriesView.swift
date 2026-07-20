import SwiftUI

struct CoachPlayerTestingEntriesView: View {
  @EnvironmentObject private var appState: AppState
  let player: Profile

  @State private var entries: [SDTestingEntry] = []
  @State private var isLoading = false
  @State private var errorText: String?

  var body: some View {
    HPListScreenLayout {
      HPWorkspaceHeader(
        "Testing",
        orgLabel: activeOrganizationName,
        context: player.displayName
      )
    } controls: {
      HPCard {
        HStack(spacing: HP.Space.sm) {
          Image(systemName: "list.bullet.clipboard")
            .foregroundStyle(HP.Color.accent)
            .accessibilityHidden(true)
          Text("\(entries.count) \(entries.count == 1 ? "entry" : "entries")")
            .font(HP.Font.callout)
            .foregroundStyle(HP.Color.text)
          Spacer(minLength: 0)
          if isLoading {
            HPProgressIndicator(style: .spinner)
              .accessibilityLabel("Loading testing entries")
          }
        }
      }
    } results: { context in
      HPCard {
        VStack(alignment: .leading, spacing: HP.Space.sm) {
          HPSectionHeader("Entries") {
            HPStatusBadge(text: "\(entries.count)", kind: .neutral)
          }

          if isLoading {
            HPLoadingState(text: "Loading…")
          }

          if entries.isEmpty, !isLoading {
            HPEmptyState(
              title: "No testing entries yet",
              message: "Testing entries for \(player.displayName) will appear here.",
              systemImage: "list.bullet.clipboard"
            )
          } else if !entries.isEmpty {
            HPTable(
              columns: [
                HPColumn(title: "Date"),
                HPColumn(title: "Measurements"),
              ],
              rows: entryRows,
              layout: context.tableLayout
            )
          }
        }
      }
    }
    .navigationTitle("Testing")
    .alert("Error", isPresented: Binding(get: { errorText != nil }, set: { _ in errorText = nil })) {
      Button("OK", role: .cancel) {}
    } message: { Text(errorText ?? "") }
    .task { await reload() }
  }

  private var activeOrganizationName: String {
    if let organizationId = appState.activeOrgId,
       let organization = appState.availableOrganizations.first(where: { $0.id == organizationId }) {
      return organization.displayName
    }
    return appState.activeOrgSettings?.display_name
      ?? appState.activeOrgSettings?.short_name
      ?? "Home Plate"
  }

  private var entryRows: [HPTableRow] {
    entries.map { entry in
      HPTableRow(
        id: entry.id,
        cells: [entry.entry_date, summary(entry)]
      )
    }
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
