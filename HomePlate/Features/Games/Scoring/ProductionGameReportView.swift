import HomePlateScoringCore
import SwiftUI

/// Schema-2 reports must replay the schema-2 ledger, never the legacy reducer.
struct ProductionGameReportView: View {
  @EnvironmentObject private var appState: AppState
  let game: SDGame
  var history = false
  @State private var seed: GameSeed?
  @State private var projection: GameProjection?
  @State private var snapshot: StatSnapshot?
  @State private var failure: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      if let failure {
        Label(failure, systemImage: "exclamationmark.triangle")
        Button("Retry") { Task { await load() } }
      } else if let snapshot, let projection, let seed {
        Text("Server-confirmed ledger · version \(snapshot.gameVersion)")
          .font(.caption).foregroundStyle(.secondary)
        Text("Provisional statistics; not an official postgame certification.")
          .font(.caption).foregroundStyle(.secondary)
        if history {
          ForEach(projection.playSummaries.reversed()) { play in
            VStack(alignment: .leading, spacing: 3) {
              Text("\(play.half == .top ? "Top" : "Bottom") \(play.inning) · \(play.text)")
                .strikethrough(play.isVoided)
              Text("\(play.scoreAfter) · \(play.outsAfter) outs").font(.caption)
            }
          }
          if projection.playSummaries.isEmpty { Text("No server-confirmed plays yet.") }
        } else {
          ForEach(snapshot.teams) { team in
            HStack {
              Text(team.side == .home ? seed.home.name : seed.away.name)
              Spacer()
              Text("R \(team.runs)  H \(team.hits)  E \(team.errors)").monospacedDigit()
            }
          }
          Divider()
          ForEach(snapshot.batting) { line in
            let lineup = line.team == .home ? seed.home.lineup : seed.away.lineup
            let player = lineup.first { $0.player.id == line.playerID }?.player
            VStack(alignment: .leading, spacing: 3) {
              Text(player.map { "\($0.firstName) \($0.lastName)" } ?? "Player")
              Text("PA \(line.plateAppearances)  AB \(line.atBats)  H \(line.hits)  RBI \(line.runsBattedIn)")
                .font(.caption.monospacedDigit())
            }
          }
        }
      } else { ProgressView("Loading confirmed scoring history…") }
    }
    .task(id: "\(appState.myProfile?.id.uuidString ?? ""):\(appState.activeOrgId?.uuidString ?? ""):\(game.game_version)") { await load() }
  }

  @MainActor private func load() async {
    seed = nil; projection = nil; snapshot = nil; failure = nil
    guard let service = appState.supabase, let account = appState.myProfile?.id,
          appState.activeOrgId == game.org_id else { failure = "Select this game's organization to view its report."; return }
    do {
      let lineup = try await service.nativeSavedLineup(gameID: game.id)
      let profiles = try await service.scoringProfilesV2(userIds: lineup.map(\.player_id))
      let loadedSeed = ProductionGameSeedAdapter.makeSeed(game: game, participants: [], profiles: profiles, savedLineup: lineup)
      let events = try await service.listScoringEventsV2(gameId: game.id, organizationId: game.org_id)
      let rules = ProductionGameSeedAdapter.rules(for: game)
      let loadedProjection = try ScoringEngine.replay(seed: loadedSeed, rules: rules, events: events)
      let loadedSnapshot = try StatisticsEngine.derive(seed: loadedSeed, rules: rules, environment: ProductionGameSeedAdapter.statisticsEnvironment, events: events)
      guard appState.myProfile?.id == account, appState.activeOrgId == game.org_id else { return }
      seed = loadedSeed; projection = loadedProjection; snapshot = loadedSnapshot
    } catch { failure = "Could not load the complete scoring ledger. No empty statistics were substituted." }
  }
}
