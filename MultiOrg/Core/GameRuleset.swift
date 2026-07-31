import Foundation

struct SDGameRuleset: Identifiable, Codable, Equatable, Sendable {
  let id: UUID
  let org_id: UUID
  let name: String
  let scope_type: String
  let scope_id: UUID?
  let parent_ruleset_id: UUID?
  let source_name: String?
  let source_version: String?
  let is_active: Bool
}

struct SDGameRulesetVersion: Identifiable, Codable, Equatable, Sendable {
  let id: UUID
  let org_id: UUID
  let ruleset_id: UUID
  let version: Int
  let configuration: [String: SDJSONValue]
  let resolved_configuration: [String: SDJSONValue]
}

struct SDResolvedBaseballRules: Equatable, Sendable {
  var scheduledInnings: Int = 7
  var maxInnings: Int?
  var tiesAllowed = true
  var extraInningsAllowed = true
  var outsPerHalf = 3
  var runCap: Int?
  var batterLimit: Int?
  var lineupMode = "fixed"
  var lineupSize: Int?
  var continuousBatting = false
  var defenderCount = 9
  var outfielderCount = 3
  var stealingAllowed = true
  var leadoffsAllowed = true
  var droppedThirdStrike = true
  var mercyThresholds: [[String: Int]] = []
  var timeLimitMinutes: Int?
  var noNewInning = false
  var placedRunnerBase: Int?
  var pitching: [String: SDJSONValue] = [:]

  static func resolve(_ hierarchy: [[String: SDJSONValue]]) -> Self {
    hierarchy.reduce(into: Self()) { rules, values in
      rules.apply(values)
    }
  }

  mutating func apply(_ values: [String: SDJSONValue]) {
    scheduledInnings = values.int("scheduled_innings") ?? scheduledInnings
    maxInnings = values.int("maximum_innings") ?? maxInnings
    tiesAllowed = values.bool("ties_allowed") ?? tiesAllowed
    extraInningsAllowed = values.bool("extra_innings_allowed") ?? extraInningsAllowed
    outsPerHalf = values.int("outs_per_half") ?? outsPerHalf
    runCap = values.int("run_cap") ?? runCap
    batterLimit = values.int("batter_limit") ?? batterLimit
    lineupMode = values.string("lineup_mode") ?? lineupMode
    lineupSize = values.int("lineup_size") ?? lineupSize
    continuousBatting = values.bool("continuous_batting") ?? continuousBatting
    defenderCount = values.int("defender_count") ?? defenderCount
    outfielderCount = values.int("outfielder_count") ?? outfielderCount
    stealingAllowed = values.bool("stealing_allowed") ?? stealingAllowed
    leadoffsAllowed = values.bool("leadoffs_allowed") ?? leadoffsAllowed
    droppedThirdStrike = values.bool("dropped_third_strike") ?? droppedThirdStrike
    timeLimitMinutes = values.int("time_limit_minutes") ?? timeLimitMinutes
    noNewInning = values.bool("no_new_inning") ?? noNewInning
    placedRunnerBase = values.int("placed_runner_base") ?? placedRunnerBase
    if case .object(let pitchingValue) = values["pitching"] { pitching = pitchingValue }
  }
}
