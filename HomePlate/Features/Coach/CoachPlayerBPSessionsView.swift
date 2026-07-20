import SwiftUI

struct CoachPlayerBPSessionsView: View {
  @EnvironmentObject private var appState: AppState
  let player: Profile

  @State private var sessions: [SDBPSession] = []
  @State private var isLoading = false
  @State private var errorText: String?

  var body: some View {
    HPListScreenLayout {
      HPWorkspaceHeader(
        "BP sessions",
        context: player.displayName
      )
    } controls: {
      HPCard {
        HStack(spacing: HP.Space.sm) {
          Image(systemName: "baseball.diamond.bases")
            .foregroundStyle(HP.Color.accent)
            .accessibilityHidden(true)
          Text("\(sessions.count) \(sessions.count == 1 ? "session" : "sessions")")
            .font(HP.Font.callout)
            .foregroundStyle(HP.Color.text)
          Spacer(minLength: 0)
          if isLoading {
            HPProgressIndicator(style: .spinner)
              .accessibilityLabel("Loading BP sessions")
          }
        }
      }
    } results: { _ in
      HPCard {
        VStack(alignment: .leading, spacing: HP.Space.sm) {
          HPSectionHeader("Sessions") {
            HPStatusBadge(text: "\(sessions.count)", kind: .neutral)
          }

          if isLoading {
            HPLoadingState(text: "Loading…")
          }

          if sessions.isEmpty, !isLoading {
            HPEmptyState(
              title: "No BP sessions yet",
              message: "Batting-practice sessions for \(player.displayName) will appear here.",
              systemImage: "baseball.diamond.bases"
            )
          } else if !sessions.isEmpty {
            VStack(alignment: .leading, spacing: HP.Space.xs) {
              ForEach(sessions) { session in
                NavigationLink {
                  CoachPlayerBPSessionDetailView(session: session)
                } label: {
                  HStack(spacing: HP.Space.sm) {
                    VStack(alignment: .leading, spacing: 2) {
                      Text("\(session.session_date) • \(session.reps_type.capitalized)")
                        .font(HP.Font.headline)
                        .foregroundStyle(HP.Color.text)
                        .fixedSize(horizontal: false, vertical: true)
                      Text(session.source.capitalized)
                        .font(HP.Font.caption)
                        .foregroundStyle(HP.Color.textMuted)
                    }
                    Spacer(minLength: HP.Space.sm)
                    Image(systemName: "chevron.right")
                      .font(.caption.weight(.semibold))
                      .foregroundStyle(HP.Color.textMuted)
                      .accessibilityHidden(true)
                  }
                  .frame(minHeight: 44)
                  .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                  "\(session.session_date), \(session.reps_type.capitalized), \(session.source.capitalized)"
                )
              }
            }
          }
        }
      }
    }
    .navigationTitle("BP")
    .alert("Error", isPresented: Binding(get: { errorText != nil }, set: { _ in errorText = nil }))
    {
      Button("OK", role: .cancel) {}
    } message: {
      Text(errorText ?? "")
    }
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
    HPDetailScreenLayout {
      HPWorkspaceHeader(
        "BP session",
        context:
          "\(session.session_date) • \(session.reps_type.capitalized) • \(session.source.capitalized)"
      )
    } metrics: {
      if !events.isEmpty {
        HPMetricCard(
          title: "Events",
          value: "\(events.count)",
          context: "Imported swings"
        )
        HPMetricCard(
          title: "Max EV",
          value: fmt(events.compactMap(\.exit_velo).max() ?? 0),
          unit: "mph",
          context: "This session"
        )
        HPMetricCard(
          title: "Avg EV",
          value: fmt(avg(events.compactMap(\.exit_velo))),
          unit: "mph",
          context: "This session"
        )
      }
    } details: {
      HPCard {
        VStack(alignment: .leading, spacing: HP.Space.sm) {
          HPSectionHeader("Summary")
          if isLoading {
            HPLoadingState(text: "Loading…")
          } else if events.isEmpty {
            HPEmptyState(
              title: "No events",
              message: "No pitch events are available for this BP session.",
              systemImage: "baseball"
            )
          } else {
            HPStatTile(label: "Date", value: session.session_date)
            HPStatTile(label: "Reps type", value: session.reps_type.capitalized)
            HPStatTile(label: "Source", value: session.source.capitalized)
          }
        }
      }
    } related: { context in
      if !events.isEmpty {
        HPCard {
          VStack(alignment: .leading, spacing: HP.Space.sm) {
            HPSectionHeader("Events (first 30)")
            HPTable(
              columns: [
                HPColumn(title: "Exit velocity", alignment: .trailing, numeric: true),
                HPColumn(title: "Launch angle", alignment: .trailing, numeric: true),
                HPColumn(title: "Distance", alignment: .trailing, numeric: true),
              ],
              rows: eventRows,
              layout: context.tableLayout
            )
          }
        }
      }
    } primaryAction: {
      EmptyView()
    }
    .navigationTitle(session.session_date)
    .alert("Error", isPresented: Binding(get: { errorText != nil }, set: { _ in errorText = nil }))
    {
      Button("OK", role: .cancel) {}
    } message: {
      Text(errorText ?? "")
    }
    .task { await reload() }
  }

  private var eventRows: [HPTableRow] {
    Array(events.prefix(30)).map { event in
      HPTableRow(
        id: event.id,
        cells: [
          fmt(event.exit_velo ?? 0),
          fmt(event.launch_angle ?? 0),
          fmt(event.distance ?? 0),
        ]
      )
    }
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
  private func fmt(_ v: Double) -> String {
    v.rounded() == v ? String(Int(v)) : String(format: "%.1f", v)
  }
}
