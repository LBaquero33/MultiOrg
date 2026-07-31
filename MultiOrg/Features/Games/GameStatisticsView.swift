import SwiftUI

struct GameStatisticsView: View {
  @EnvironmentObject private var appState: AppState
  let game: SDGame
  let mode: Mode

  enum Mode { case boxScore, players, decisions }

  @State private var statistics = SDOfficialGameStatistics()
  @State private var events: [SDScoringEvent] = []
  @State private var decisions: [SDGameScoringDecision] = []
  @State private var errorText: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      if mode == .boxScore { boxScore }
      if mode == .players { playerLines }
      if mode == .decisions { decisionHistory }
      if statistics.unresolvedDecisionCount > 0 {
        Label("\(statistics.unresolvedDecisionCount) scoring decisions need review", systemImage: "exclamationmark.triangle")
          .foregroundStyle(.orange)
      }
    }
    .task(id: game.game_version) { await load() }
    .alert("Statistics unavailable", isPresented: Binding(
      get: { errorText != nil }, set: { if !$0 { errorText = nil } }
    )) { Button("OK", role: .cancel) {} } message: { Text(errorText ?? "") }
  }

  private var boxScore: some View {
    VStack(alignment: .leading, spacing: 8) {
      statRow("Away", score: score.away)
      statRow("Home", score: score.home)
      Divider()
      detail("Hits", "\(statistics.batting.values.reduce(0) { $0 + $1.hits })")
      detail("Errors", "\(statistics.fielding.values.reduce(0) { $0 + $1.errors })")
    }
  }

  private var playerLines: some View {
    VStack(alignment: .leading, spacing: 8) {
      ForEach(statistics.batting.values.sorted(by: { $0.playerId.uuidString < $1.playerId.uuidString }), id: \.playerId) { line in
        VStack(alignment: .leading, spacing: 3) {
          Text(line.playerId.uuidString.prefix(8)).font(.headline)
          Text("PA \(line.plateAppearances)  AB \(line.atBats)  H \(line.hits)  TB \(line.totalBases)  RBI \(line.runsBattedIn)")
            .font(.caption.monospacedDigit())
            .foregroundStyle(DHDTheme.textSecondary)
        }
        Divider()
      }
      if statistics.batting.isEmpty {
        Text("No official player statistics yet.").foregroundStyle(DHDTheme.textSecondary)
      }
    }
  }

  private var decisionHistory: some View {
    VStack(alignment: .leading, spacing: 8) {
      ForEach(decisions) { decision in
        HStack {
          VStack(alignment: .leading) {
            Text(decision.decision_type.replacingOccurrences(of: "_", with: " ").capitalized)
            Text(decision.effectiveValue?.replacingOccurrences(of: "_", with: " ").capitalized ?? "Pending")
              .font(.caption).foregroundStyle(DHDTheme.textSecondary)
          }
          Spacer()
          DHDStatusBadge(
            text: decision.decision_status.capitalized,
            color: decision.decision_status == "final" ? .green : .orange
          )
        }
      }
      if decisions.isEmpty {
        Text("No scorer judgments recorded.").foregroundStyle(DHDTheme.textSecondary)
      }
    }
  }

  private var score: (home: Int, away: Int) {
    let state = (try? SDGameReducer.replay(
      events, rules: SDResolvedBaseballRules.resolve([game.ruleset_snapshot])
    )) ?? SDGameState()
    return (state.homeScore, state.awayScore)
  }

  private func statRow(_ team: String, score: Int) -> some View {
    HStack { Text(team).font(.headline); Spacer(); Text("\(score)").font(.title2.bold()) }
  }

  private func detail(_ label: String, _ value: String) -> some View {
    HStack { Text(label); Spacer(); Text(value).fontWeight(.semibold) }
  }

  private func load() async {
    guard let service = appState.supabase, let orgId = appState.activeOrgId else { return }
    do {
      async let eventLoad = service.listScoringEvents(gameId: game.id, organizationId: orgId)
      async let decisionLoad = service.listGameScoringDecisions(gameId: game.id, organizationId: orgId)
      events = try await eventLoad
      decisions = try await decisionLoad
      statistics = SDOfficialScoringEngine.derive(events: events, decisions: decisions)
    } catch { errorText = error.localizedDescription }
  }
}
