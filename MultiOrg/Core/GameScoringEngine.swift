import Foundation

enum SDScoringEventType: String, Codable, CaseIterable, Sendable {
  case gameStarted = "game_started"
  case lineupSubmitted = "lineup_submitted"
  case defensiveAlignmentSet = "defensive_alignment_set"
  case pitchThrown = "pitch_thrown"
  case pitchResultRecorded = "pitch_result_recorded"
  case ballPutInPlay = "ball_put_in_play"
  case runnerAdvanced = "runner_advanced"
  case runnerOut = "runner_out"
  case batterReached = "batter_reached"
  case runScored = "run_scored"
  case fieldingTouch = "fielding_touch"
  case scoringDecisionAssigned = "scoring_decision_assigned"
  case substitutionEntered = "substitution_entered"
  case positionChanged = "position_changed"
  case injuryRecorded = "injury_recorded"
  case ejectionRecorded = "ejection_recorded"
  case administrativeOut = "administrative_out"
  case halfInningEnded = "half_inning_ended"
  case gameDelayed = "game_delayed"
  case gameSuspended = "game_suspended"
  case gameResumed = "game_resumed"
  case gameEnded = "game_ended"
  case scoringDecisionRevised = "scoring_decision_revised"
  case gameFinalized = "game_finalized"
}

struct SDScoringEvent: Identifiable, Codable, Equatable, Sendable {
  let id: UUID
  let org_id: UUID
  let game_id: UUID
  let game_version: Int
  let sequence: Int
  let event_type: SDScoringEventType
  let actor_user_id: UUID
  let actor_device_id: UUID
  let occurred_at: Date
  let payload: [String: SDJSONValue]
  let ruleset_version: Int?
  let idempotency_key: String
  let correction_of_event_id: UUID?
  let supersedes_event_id: UUID?
}

struct SDBaseRunner: Codable, Equatable, Sendable {
  let playerId: UUID
  let responsiblePitcherId: UUID?
  let placedByRule: Bool
}

struct SDGameState: Codable, Equatable, Sendable {
  var version = 0
  var inning = 1
  var half = "top"
  var homeScore = 0
  var awayScore = 0
  var balls = 0
  var strikes = 0
  var outs = 0
  var bases: [Int: SDBaseRunner] = [:]
  var currentBatterId: UUID?
  var currentPitcherId: UUID?
  var pitchCount = 0
  var battingOrder: [UUID] = []
  var defensiveAlignment: [String: UUID] = [:]
  var status: SDGameLifecycle = .pregame
  var pendingRegulation: [String] = []
}

enum SDGameReducerError: Error, Equatable {
  case nonSequentialVersion
  case invalidBase
  case occupiedBase
}

enum SDGameReducer {
  static func replay(_ events: [SDScoringEvent], rules: SDResolvedBaseballRules) throws -> SDGameState {
    try events.sorted { $0.sequence < $1.sequence }.reduce(SDGameState()) {
      try apply($1, to: $0, rules: rules)
    }
  }

  static func apply(
    _ event: SDScoringEvent,
    to current: SDGameState,
    rules: SDResolvedBaseballRules
  ) throws -> SDGameState {
    guard event.game_version == current.version + 1 else { throw SDGameReducerError.nonSequentialVersion }
    var state = current
    state.version = event.game_version
    switch event.event_type {
    case .gameStarted:
      state.status = .live
    case .pitchThrown:
      state.pitchCount += 1
    case .pitchResultRecorded:
      switch event.payload.string("result") {
      case "ball":
        state.balls += 1
        if state.balls >= 4 { state.balls = 0; state.strikes = 0 }
      case "called_strike", "swinging_strike":
        state.strikes += 1
        if state.strikes >= 3 { state.outs += 1; state.balls = 0; state.strikes = 0 }
      case "foul":
        state.strikes = min(2, state.strikes + 1)
      default: break
      }
    case .runnerAdvanced, .batterReached:
      guard let player = event.payload.uuid("player_id"),
            let destination = event.payload.int("to_base"), (1...3).contains(destination) else {
        throw SDGameReducerError.invalidBase
      }
      if state.bases[destination] != nil { throw SDGameReducerError.occupiedBase }
      if let from = event.payload.int("from_base") { state.bases[from] = nil }
      state.bases[destination] = SDBaseRunner(
        playerId: player, responsiblePitcherId: event.payload.uuid("responsible_pitcher_id"),
        placedByRule: event.payload.bool("placed_by_rule") ?? false
      )
    case .runnerOut, .administrativeOut:
      state.outs += 1
      if let base = event.payload.int("from_base") { state.bases[base] = nil }
    case .runScored:
      if let base = event.payload.int("from_base") { state.bases[base] = nil }
      if event.payload.string("team") == "home" { state.homeScore += 1 } else { state.awayScore += 1 }
    case .halfInningEnded:
      state.outs = 0; state.balls = 0; state.strikes = 0; state.bases = [:]
      if state.half == "top" { state.half = "bottom" } else { state.half = "top"; state.inning += 1 }
    case .gameDelayed: state.status = .delayed
    case .gameSuspended: state.status = .suspended
    case .gameResumed: state.status = .live
    case .gameEnded: state.status = .final
    case .lineupSubmitted:
      state.battingOrder = event.payload.uuidArray("player_ids")
    case .defensiveAlignmentSet:
      state.defensiveAlignment = event.payload.uuidMap("positions")
    default: break
    }
    if let cap = rules.runCap, event.payload.int("half_runs") == cap {
      state.pendingRegulation.append("run_cap_reached")
    }
    return state
  }
}

extension Dictionary where Key == String, Value == SDJSONValue {
  func int(_ key: String) -> Int? { guard case .int(let value) = self[key] else { return nil }; return value }
  func string(_ key: String) -> String? { guard case .string(let value) = self[key] else { return nil }; return value }
  func bool(_ key: String) -> Bool? { guard case .bool(let value) = self[key] else { return nil }; return value }
  func uuid(_ key: String) -> UUID? { string(key).flatMap(UUID.init(uuidString:)) }
  func uuidArray(_ key: String) -> [UUID] {
    guard case .array(let values) = self[key] else { return [] }
    return values.compactMap { if case .string(let raw) = $0 { UUID(uuidString: raw) } else { nil } }
  }
  func uuidMap(_ key: String) -> [String: UUID] {
    guard case .object(let values) = self[key] else { return [:] }
    return values.reduce(into: [:]) { result, pair in
      if case .string(let raw) = pair.value { result[pair.key] = UUID(uuidString: raw) }
    }
  }
}
