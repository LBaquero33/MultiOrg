import Foundation
import Testing
@testable import HomePlate

struct GameScoringReducerTests {
  @Test func pitchesAndRunCapReplayDeterministically() throws {
    let events = [
      event(1, .gameStarted),
      event(2, .pitchThrown),
      event(3, .pitchResultRecorded, ["result": .string("ball")]),
      event(4, .runScored, ["team": .string("away"), "half_runs": .int(5)]),
      event(5, .halfInningEnded),
    ]
    let rules = SDResolvedBaseballRules.resolve([["run_cap": .int(5)]])
    let first = try SDGameReducer.replay(events, rules: rules)
    let second = try SDGameReducer.replay(events, rules: rules)
    #expect(first == second)
    #expect(first.awayScore == 1)
    #expect(first.outs == 0)
    #expect(first.half == "bottom")
  }

  @Test func automaticOutDoesNotCreatePitchOrStrikeout() throws {
    let state = try SDGameReducer.replay(
      [event(1, .administrativeOut)], rules: .init()
    )
    #expect(state.outs == 1)
    #expect(state.pitchCount == 0)
    #expect(state.strikes == 0)
  }

  @Test func staleSequenceRejected() {
    #expect(throws: SDGameReducerError.nonSequentialVersion) {
      try SDGameReducer.replay([event(2, .gameStarted)], rules: .init())
    }
  }

  private func event(
    _ version: Int, _ type: SDScoringEventType,
    _ payload: [String: SDJSONValue] = [:]
  ) -> SDScoringEvent {
    SDScoringEvent(
      id: UUID(), org_id: UUID(), game_id: UUID(), game_version: version,
      sequence: version, event_type: type, actor_user_id: UUID(),
      actor_device_id: UUID(), occurred_at: Date(), payload: payload,
      ruleset_version: 1, idempotency_key: "event-\(version)",
      correction_of_event_id: nil, supersedes_event_id: nil
    )
  }
}
