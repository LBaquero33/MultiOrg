import Foundation

enum SDOfficialScoringClassification: String, Codable, CaseIterable, Sendable {
  case single, double, triple
  case homeRun = "home_run"
  case walk
  case intentionalWalk = "intentional_walk"
  case hitByPitch = "hit_by_pitch"
  case strikeout
  case sacrificeBunt = "sacrifice_bunt"
  case sacrificeFly = "sacrifice_fly"
  case fieldersChoice = "fielders_choice"
  case error
  case stolenBase = "stolen_base"
  case caughtStealing = "caught_stealing"
  case defensiveIndifference = "defensive_indifference"
  case wildPitch = "wild_pitch"
  case passedBall = "passed_ball"
  case balk, putout, assist
  case doublePlay = "double_play"
  case triplePlay = "triple_play"
}

struct SDGameScoringDecision: Identifiable, Codable, Equatable, Sendable {
  let id: UUID
  let org_id: UUID
  let game_id: UUID
  let physical_event_id: UUID
  let root_decision_id: UUID
  let supersedes_decision_id: UUID?
  let decision_type: String
  let preliminary_value: String?
  let final_value: String?
  let decision_status: String
  let rule_reference: String?
  let reasoning_note: String?
  let review_requested: Bool
  let decision_maker_id: UUID
  let created_at: Date
  let finalized_at: Date?

  var effectiveValue: String? { final_value ?? preliminary_value }
}

struct SDBattingLine: Equatable, Sendable {
  let playerId: UUID
  var plateAppearances = 0
  var atBats = 0
  var runs = 0
  var singles = 0
  var doubles = 0
  var triples = 0
  var homeRuns = 0
  var runsBattedIn = 0
  var walks = 0
  var intentionalWalks = 0
  var hitByPitch = 0
  var strikeouts = 0
  var sacrificeBunts = 0
  var sacrificeFlies = 0
  var stolenBases = 0
  var caughtStealing = 0
  var errorsReached = 0
  var fieldersChoices = 0

  var hits: Int { singles + doubles + triples + homeRuns }
  var totalBases: Int { singles + 2 * doubles + 3 * triples + 4 * homeRuns }
}

struct SDPitchingLine: Equatable, Sendable {
  let playerId: UUID
  var battersFaced = 0
  var outsRecorded = 0
  var hitsAllowed = 0
  var runsAllowed = 0
  var earnedRuns = 0
  var walks = 0
  var strikeouts = 0
  var pitches = 0

  var inningsPitched: String { "\(outsRecorded / 3).\(outsRecorded % 3)" }
}

struct SDFieldingLine: Equatable, Sendable {
  let playerId: UUID
  var putouts = 0
  var assists = 0
  var errors = 0
  var doublePlays = 0
  var triplePlays = 0
}

struct SDOfficialGameStatistics: Equatable, Sendable {
  var batting: [UUID: SDBattingLine] = [:]
  var pitching: [UUID: SDPitchingLine] = [:]
  var fielding: [UUID: SDFieldingLine] = [:]
  var unresolvedDecisionCount = 0
  var validationIssues: [String] = []
}

enum SDOfficialScoringEngine {
  static func derive(
    events: [SDScoringEvent],
    decisions: [SDGameScoringDecision]
  ) -> SDOfficialGameStatistics {
    var result = SDOfficialGameStatistics()
    let latest = latestDecisions(decisions)
    let earnedRunResults = SDEarnedRunReconstructor.reconstruct(
      events: events,
      decisionsByEvent: latest
    )
    result.unresolvedDecisionCount = latest.values.filter { $0.decision_status != "final" }.count

    for event in events.sorted(by: { $0.sequence < $1.sequence }) {
      if event.event_type == .pitchThrown, let pitcher = event.payload.uuid("pitcher_id") {
        mutatePitching(&result, player: pitcher) { $0.pitches += 1 }
      }
      if event.event_type == .runScored, let runner = event.payload.uuid("player_id") {
        mutateBatting(&result, player: runner) { $0.runs += 1 }
        if let pitcher = event.payload.uuid("responsible_pitcher_id") {
          mutatePitching(&result, player: pitcher) {
            $0.runsAllowed += 1
            if earnedRunResults[event.id] == true { $0.earnedRuns += 1 }
          }
        }
      }
      guard let decision = latest[event.id],
            let raw = decision.effectiveValue,
            let classification = SDOfficialScoringClassification(rawValue: raw) else { continue }
      apply(classification, event: event, to: &result)
    }
    result.validationIssues = validate(result)
    return result
  }

  static func latestDecisions(
    _ decisions: [SDGameScoringDecision]
  ) -> [UUID: SDGameScoringDecision] {
    Dictionary(grouping: decisions.filter { $0.decision_status != "superseded" }, by: \.physical_event_id)
      .compactMapValues { $0.max(by: { $0.created_at < $1.created_at }) }
  }

  static func validate(_ stats: SDOfficialGameStatistics) -> [String] {
    var issues: [String] = []
    for line in stats.batting.values {
      if line.hits != line.singles + line.doubles + line.triples + line.homeRuns {
        issues.append("hits_do_not_reconcile")
      }
      if line.totalBases < line.hits { issues.append("total_bases_do_not_reconcile") }
    }
    for line in stats.pitching.values where line.earnedRuns > line.runsAllowed {
      issues.append("earned_runs_exceed_runs")
    }
    if stats.unresolvedDecisionCount > 0 { issues.append("unresolved_scoring_decisions") }
    return Array(Set(issues)).sorted()
  }

  private static func apply(
    _ classification: SDOfficialScoringClassification,
    event: SDScoringEvent,
    to result: inout SDOfficialGameStatistics
  ) {
    let batter = event.payload.uuid("batter_id")
    let pitcher = event.payload.uuid("pitcher_id")
    let fielder = event.payload.uuid("fielder_id")
    if let batter {
      mutateBatting(&result, player: batter) { line in
        switch classification {
        case .single: line.plateAppearances += 1; line.atBats += 1; line.singles += 1
        case .double: line.plateAppearances += 1; line.atBats += 1; line.doubles += 1
        case .triple: line.plateAppearances += 1; line.atBats += 1; line.triples += 1
        case .homeRun: line.plateAppearances += 1; line.atBats += 1; line.homeRuns += 1
        case .walk: line.plateAppearances += 1; line.walks += 1
        case .intentionalWalk: line.plateAppearances += 1; line.walks += 1; line.intentionalWalks += 1
        case .hitByPitch: line.plateAppearances += 1; line.hitByPitch += 1
        case .strikeout: line.plateAppearances += 1; line.atBats += 1; line.strikeouts += 1
        case .sacrificeBunt: line.plateAppearances += 1; line.sacrificeBunts += 1
        case .sacrificeFly: line.plateAppearances += 1; line.sacrificeFlies += 1
        case .fieldersChoice: line.plateAppearances += 1; line.atBats += 1; line.fieldersChoices += 1
        case .error: line.plateAppearances += 1; line.atBats += 1; line.errorsReached += 1
        case .stolenBase: line.stolenBases += 1
        case .caughtStealing: line.caughtStealing += 1
        default: break
        }
        line.runsBattedIn += event.payload.int("rbi") ?? 0
      }
    }
    if let pitcher {
      mutatePitching(&result, player: pitcher) { line in
        switch classification {
        case .single, .double, .triple, .homeRun: line.battersFaced += 1; line.hitsAllowed += 1
        case .walk, .intentionalWalk: line.battersFaced += 1; line.walks += 1
        case .strikeout: line.battersFaced += 1; line.strikeouts += 1; line.outsRecorded += 1
        case .hitByPitch, .error, .fieldersChoice, .sacrificeBunt, .sacrificeFly:
          line.battersFaced += 1
        default: break
        }
      }
    }
    if let fielder {
      mutateFielding(&result, player: fielder) { line in
        switch classification {
        case .putout: line.putouts += 1
        case .assist: line.assists += 1
        case .error: line.errors += 1
        case .doublePlay: line.doublePlays += 1
        case .triplePlay: line.triplePlays += 1
        default: break
        }
      }
    }
  }

  private static func mutateBatting(
    _ stats: inout SDOfficialGameStatistics, player: UUID, _ body: (inout SDBattingLine) -> Void
  ) {
    var line = stats.batting[player] ?? SDBattingLine(playerId: player)
    body(&line)
    stats.batting[player] = line
  }

  private static func mutatePitching(
    _ stats: inout SDOfficialGameStatistics, player: UUID, _ body: (inout SDPitchingLine) -> Void
  ) {
    var line = stats.pitching[player] ?? SDPitchingLine(playerId: player)
    body(&line)
    stats.pitching[player] = line
  }

  private static func mutateFielding(
    _ stats: inout SDOfficialGameStatistics, player: UUID, _ body: (inout SDFieldingLine) -> Void
  ) {
    var line = stats.fielding[player] ?? SDFieldingLine(playerId: player)
    body(&line)
    stats.fielding[player] = line
  }
}

enum SDEarnedRunReconstructor {
  static func reconstruct(
    events: [SDScoringEvent],
    decisionsByEvent: [UUID: SDGameScoringDecision]
  ) -> [UUID: Bool] {
    var earnedByRunEvent: [UUID: Bool] = [:]
    var virtualOuts = 0

    for event in events.sorted(by: { $0.sequence < $1.sequence }) {
      if event.event_type == .halfInningEnded {
        virtualOuts = 0
        continue
      }

      if event.event_type == .runScored {
        let placedRunner = event.payload.bool("placed_by_rule") ?? false
        earnedByRunEvent[event.id] = !placedRunner && virtualOuts < 3
      }

      if event.event_type == .runnerOut || event.event_type == .administrativeOut {
        virtualOuts += max(1, event.payload.int("outs_recorded") ?? 1)
        continue
      }

      guard let raw = decisionsByEvent[event.id]?.effectiveValue,
            let classification = SDOfficialScoringClassification(rawValue: raw) else {
        continue
      }
      virtualOuts += virtualOutValue(for: classification)
    }
    return earnedByRunEvent
  }

  private static func virtualOutValue(
    for classification: SDOfficialScoringClassification
  ) -> Int {
    switch classification {
    case .error, .strikeout, .sacrificeBunt, .sacrificeFly, .putout:
      return 1
    case .doublePlay:
      return 2
    case .triplePlay:
      return 3
    default:
      return 0
    }
  }
}
