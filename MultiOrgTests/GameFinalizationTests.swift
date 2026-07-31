import Foundation
import Testing
@testable import MultiOrg

struct GameFinalizationTests {
  @Test func endedGameWithReconciledStatisticsCanFinalize() throws {
    let game = makeGame(version: 2)
    let events = [event(1, .gameStarted, game: game), event(2, .gameEnded, game: game)]
    let state = try SDGameReducer.replay(events, rules: .init())
    let stats = SDOfficialScoringEngine.derive(events: events, decisions: [])
    let report = SDGameFinalizationValidator.validate(
      game: game, state: state, events: events, statistics: stats
    )
    #expect(report.canFinalize)
    #expect(report.issues.isEmpty)
    #expect(report.json["issues"] == .array([]))
  }

  @Test func missingGameEndBlocksFinalization() throws {
    let game = makeGame(version: 1)
    let events = [event(1, .gameStarted, game: game)]
    let state = try SDGameReducer.replay(events, rules: .init())
    let report = SDGameFinalizationValidator.validate(
      game: game, state: state, events: events,
      statistics: SDOfficialScoringEngine.derive(events: events, decisions: [])
    )
    #expect(!report.canFinalize)
    #expect(report.issues.contains(where: { $0.code == "game_end_not_recorded" }))
  }

  @Test func unresolvedOfficialDecisionBlocksFinalization() throws {
    let game = makeGame(version: 2)
    let physicalEvent = event(1, .ballPutInPlay, game: game)
    let end = event(2, .gameEnded, game: game)
    let decision = SDGameScoringDecision(
      id: UUID(), org_id: game.org_id, game_id: game.id,
      physical_event_id: physicalEvent.id, root_decision_id: UUID(),
      supersedes_decision_id: nil, decision_type: "plate_appearance",
      preliminary_value: "single", final_value: nil, decision_status: "preliminary",
      rule_reference: nil, reasoning_note: nil, review_requested: true,
      decision_maker_id: UUID(), created_at: Date(), finalized_at: nil
    )
    let state = try SDGameReducer.replay([physicalEvent, end], rules: .init())
    let stats = SDOfficialScoringEngine.derive(events: [physicalEvent, end], decisions: [decision])
    let report = SDGameFinalizationValidator.validate(
      game: game, state: state, events: [physicalEvent, end], statistics: stats
    )
    #expect(!report.canFinalize)
    #expect(report.issues.contains(where: { $0.code == "unresolved_scoring_decisions" }))
  }

  @Test func serverVersionAheadRequiresReload() throws {
    let game = makeGame(version: 3)
    let events = [event(1, .gameStarted, game: game), event(2, .gameEnded, game: game)]
    let state = try SDGameReducer.replay(events, rules: .init())
    let report = SDGameFinalizationValidator.validate(
      game: game, state: state, events: events,
      statistics: SDOfficialScoringEngine.derive(events: events, decisions: [])
    )
    #expect(report.issues.contains(where: { $0.code == "server_version_ahead" }))
  }

  private func makeGame(version: Int) -> SDGame {
    SDGame(
      id: UUID(), event_id: UUID(), org_id: UUID(), season_id: nil, team_id: UUID(),
      opponent_name: "Visitors", opponent_org_id: nil, opponent_team_id: nil,
      site: .home, venue_name: "Home Plate", scheduled_innings: 7,
      ruleset_id: nil, ruleset_version: 1, ruleset_snapshot: [:],
      assigned_scorekeeper_id: UUID(), status: .live, live_status: "live",
      home_team_name: "Home", away_team_name: "Away", lineup_ready: true,
      game_version: version, finalized_at: nil, created_at: Date(), updated_at: Date()
    )
  }

  private func event(
    _ version: Int, _ type: SDScoringEventType, game: SDGame
  ) -> SDScoringEvent {
    SDScoringEvent(
      id: UUID(), org_id: game.org_id, game_id: game.id, game_version: version,
      sequence: version, event_type: type, actor_user_id: UUID(),
      actor_device_id: UUID(), occurred_at: Date(), payload: [:],
      ruleset_version: 1, idempotency_key: "event-\(version)",
      correction_of_event_id: nil, supersedes_event_id: nil
    )
  }
}
