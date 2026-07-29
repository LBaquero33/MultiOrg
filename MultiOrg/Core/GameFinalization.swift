import Foundation

struct SDGameValidationIssue: Identifiable, Codable, Equatable, Sendable {
  let code: String
  let message: String
  let blocking: Bool

  var id: String { code }
}

struct SDGameValidationReport: Codable, Equatable, Sendable {
  let issues: [SDGameValidationIssue]
  let gameVersion: Int
  let homeScore: Int
  let awayScore: Int
  let unresolvedDecisionCount: Int

  var canFinalize: Bool { !issues.contains(where: \.blocking) }

  var json: [String: SDJSONValue] {
    [
      "issues": .array(issues.map {
        .object([
          "code": .string($0.code),
          "message": .string($0.message),
          "blocking": .bool($0.blocking),
        ])
      }),
      "game_version": .int(gameVersion),
      "home_score": .int(homeScore),
      "away_score": .int(awayScore),
      "unresolved_decision_count": .int(unresolvedDecisionCount),
    ]
  }
}

struct SDGameFinalization: Identifiable, Codable, Equatable, Sendable {
  let id: UUID
  let org_id: UUID
  let game_id: UUID
  let final_game_version: Int
  let final_scoring_event_id: UUID
  let finalized_by: UUID
  let actor_device_id: UUID
  let idempotency_key: String
  let validation: [String: SDJSONValue]
  let created_at: Date
}

struct SDGameCorrection: Identifiable, Codable, Equatable, Sendable {
  let id: UUID
  let org_id: UUID
  let game_id: UUID
  let decision_id: UUID
  let superseded_decision_id: UUID
  let corrected_by: UUID
  let reason: String
  let idempotency_key: String
  let created_at: Date
}

struct SDGameAuditEntry: Identifiable, Codable, Equatable, Sendable {
  let id: UUID
  let org_id: UUID
  let game_id: UUID
  let action: String
  let actor_user_id: UUID?
  let actor_device_id: UUID?
  let game_version: Int?
  let details: [String: SDJSONValue]
  let created_at: Date
}

enum SDGameFinalizationValidator {
  static func validate(
    game: SDGame,
    state: SDGameState,
    events: [SDScoringEvent],
    statistics: SDOfficialGameStatistics
  ) -> SDGameValidationReport {
    var issues: [SDGameValidationIssue] = []

    if state.version != (events.map(\.game_version).max() ?? 0) {
      issues.append(blocking("version_mismatch", "The replayed game version does not match the event ledger."))
    }
    if !events.contains(where: { $0.event_type == .gameEnded }) {
      issues.append(blocking("game_end_not_recorded", "Record the end of the game before finalizing."))
    }
    if state.status != .final {
      issues.append(blocking("game_not_ended", "The scoring ledger has not reached a final game state."))
    }
    if state.outs < 0 || state.outs > 3 {
      issues.append(blocking("outs_invalid", "The current out count is invalid."))
    }
    if !(0...3).contains(state.balls) || !(0...2).contains(state.strikes) {
      issues.append(blocking("count_invalid", "The current ball-strike count is invalid."))
    }
    if state.bases.keys.contains(where: { !(1...3).contains($0) }) {
      issues.append(blocking("base_state_invalid", "A runner is assigned to an invalid base."))
    }
    if !state.pendingRegulation.isEmpty {
      issues.append(blocking("pending_rule_action", "Resolve pending game-rule actions before finalizing."))
    }
    if statistics.unresolvedDecisionCount > 0 {
      issues.append(blocking("unresolved_scoring_decisions", "Resolve all official scoring decisions."))
    }
    for code in statistics.validationIssues {
      issues.append(blocking(code, code.replacingOccurrences(of: "_", with: " ").capitalized))
    }
    if game.game_version > state.version {
      issues.append(blocking("server_version_ahead", "Reload the game before finalizing."))
    }

    return SDGameValidationReport(
      issues: unique(issues),
      gameVersion: state.version,
      homeScore: state.homeScore,
      awayScore: state.awayScore,
      unresolvedDecisionCount: statistics.unresolvedDecisionCount
    )
  }

  private static func blocking(_ code: String, _ message: String) -> SDGameValidationIssue {
    .init(code: code, message: message, blocking: true)
  }

  private static func unique(_ issues: [SDGameValidationIssue]) -> [SDGameValidationIssue] {
    var seen = Set<String>()
    return issues.filter { seen.insert($0.code).inserted }
  }
}

extension SDOfficialGameStatistics {
  var persistenceJSON: [String: SDJSONValue] {
    [
      "batting": .object(Dictionary(uniqueKeysWithValues: batting.map {
        ($0.key.uuidString.lowercased(), $0.value.json)
      })),
      "pitching": .object(Dictionary(uniqueKeysWithValues: pitching.map {
        ($0.key.uuidString.lowercased(), $0.value.json)
      })),
      "fielding": .object(Dictionary(uniqueKeysWithValues: fielding.map {
        ($0.key.uuidString.lowercased(), $0.value.json)
      })),
      "team_totals": .object([
        "runs": .int(batting.values.reduce(0) { $0 + $1.runs }),
        "hits": .int(batting.values.reduce(0) { $0 + $1.hits }),
        "errors": .int(fielding.values.reduce(0) { $0 + $1.errors }),
      ]),
    ]
  }
}

private extension SDBattingLine {
  var json: SDJSONValue {
    .object([
      "plate_appearances": .int(plateAppearances), "at_bats": .int(atBats),
      "runs": .int(runs), "hits": .int(hits), "total_bases": .int(totalBases),
      "rbi": .int(runsBattedIn), "walks": .int(walks),
      "strikeouts": .int(strikeouts),
    ])
  }
}

private extension SDPitchingLine {
  var json: SDJSONValue {
    .object([
      "batters_faced": .int(battersFaced), "outs_recorded": .int(outsRecorded),
      "hits_allowed": .int(hitsAllowed), "runs_allowed": .int(runsAllowed),
      "earned_runs": .int(earnedRuns), "walks": .int(walks),
      "strikeouts": .int(strikeouts), "pitches": .int(pitches),
    ])
  }
}

private extension SDFieldingLine {
  var json: SDJSONValue {
    .object([
      "putouts": .int(putouts), "assists": .int(assists), "errors": .int(errors),
      "double_plays": .int(doublePlays), "triple_plays": .int(triplePlays),
    ])
  }
}
