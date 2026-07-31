import Foundation
import Testing
@testable import HomePlate

struct GameOfficialScoringTests {
  @Test func hitClassificationBuildsBattingAndPitchingLines() {
    let batter = UUID(), pitcher = UUID()
    let event = scoringEvent(type: .ballPutInPlay, payload: [
      "batter_id": .string(batter.uuidString),
      "pitcher_id": .string(pitcher.uuidString),
      "rbi": .int(1),
    ])
    let decision = scoringDecision(event: event, value: "double")
    let stats = SDOfficialScoringEngine.derive(events: [event], decisions: [decision])
    #expect(stats.batting[batter]?.doubles == 1)
    #expect(stats.batting[batter]?.totalBases == 2)
    #expect(stats.batting[batter]?.runsBattedIn == 1)
    #expect(stats.pitching[pitcher]?.hitsAllowed == 1)
  }

  @Test func latestDecisionSupersedesEarlierJudgment() {
    let batter = UUID()
    let event = scoringEvent(type: .ballPutInPlay, payload: ["batter_id": .string(batter.uuidString)])
    let first = scoringDecision(event: event, value: "error", status: "superseded", offset: 0)
    let revised = scoringDecision(event: event, value: "single", offset: 1)
    let stats = SDOfficialScoringEngine.derive(events: [event], decisions: [first, revised])
    #expect(stats.batting[batter]?.singles == 1)
    #expect(stats.batting[batter]?.errorsReached == 0)
  }

  @Test func administrativeOutCreatesNoFakeBattingStats() {
    let event = scoringEvent(type: .administrativeOut, payload: [:])
    let stats = SDOfficialScoringEngine.derive(events: [event], decisions: [])
    #expect(stats.batting.isEmpty)
    #expect(stats.pitching.isEmpty)
  }

  @Test func errorThatShouldHaveEndedInningMakesFollowingRunUnearned() {
    let pitcher = UUID()
    let firstOut = scoringEvent(sequence: 1, type: .runnerOut, payload: [:])
    let secondOut = scoringEvent(sequence: 2, type: .runnerOut, payload: [:])
    let error = scoringEvent(sequence: 3, type: .ballPutInPlay, payload: [:])
    let run = scoringEvent(sequence: 4, type: .runScored, payload: [
      "player_id": .string(UUID().uuidString),
      "responsible_pitcher_id": .string(pitcher.uuidString),
    ])
    let stats = SDOfficialScoringEngine.derive(
      events: [firstOut, secondOut, error, run],
      decisions: [scoringDecision(event: error, value: "error")]
    )
    #expect(stats.pitching[pitcher]?.runsAllowed == 1)
    #expect(stats.pitching[pitcher]?.earnedRuns == 0)
  }

  @Test func placedRunnerIsUnearnedBeforeThreeVirtualOuts() {
    let pitcher = UUID()
    let run = scoringEvent(sequence: 1, type: .runScored, payload: [
      "player_id": .string(UUID().uuidString),
      "responsible_pitcher_id": .string(pitcher.uuidString),
      "placed_by_rule": .bool(true),
    ])
    let stats = SDOfficialScoringEngine.derive(events: [run], decisions: [])
    #expect(stats.pitching[pitcher]?.runsAllowed == 1)
    #expect(stats.pitching[pitcher]?.earnedRuns == 0)
  }

  private func scoringEvent(
    sequence: Int = 1,
    type: SDScoringEventType,
    payload: [String: SDJSONValue]
  ) -> SDScoringEvent {
    SDScoringEvent(
      id: UUID(), org_id: UUID(), game_id: UUID(), game_version: sequence, sequence: sequence,
      event_type: type, actor_user_id: UUID(), actor_device_id: UUID(),
      occurred_at: Date(), payload: payload, ruleset_version: 1,
      idempotency_key: UUID().uuidString, correction_of_event_id: nil,
      supersedes_event_id: nil
    )
  }

  private func scoringDecision(
    event: SDScoringEvent, value: String, status: String = "final", offset: TimeInterval = 0
  ) -> SDGameScoringDecision {
    SDGameScoringDecision(
      id: UUID(), org_id: event.org_id, game_id: event.game_id,
      physical_event_id: event.id, root_decision_id: UUID(), supersedes_decision_id: nil,
      decision_type: "plate_appearance", preliminary_value: nil, final_value: value,
      decision_status: status, rule_reference: "MLB 9", reasoning_note: nil,
      review_requested: false, decision_maker_id: UUID(),
      created_at: Date().addingTimeInterval(offset), finalized_at: Date()
    )
  }
}
