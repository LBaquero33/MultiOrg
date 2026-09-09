import Foundation

public enum SnapshotStatus: String, Codable, Sendable {
  case provisional
  case final
  case corrected
}

public struct BattingAdvanced: Codable, Hashable, Sendable {
  public var average: Double?
  public var onBasePercentage: Double?
  public var slugging: Double?
  public var ops: Double?
  public var iso: Double?
  public var babip: Double?
  public var walkRate: Double?
  public var strikeoutRate: Double?
  public var strikeoutMinusWalkRate: Double?
  public var wOBA: Double?
  public var wRAA: Double?
  public var wRC: Double?
  public var wRCPlus: Double?
  public var opsPlus: Double?
}

public struct BattingLine: Identifiable, Codable, Hashable, Sendable {
  public var id: UUID { playerID }
  public let playerID: UUID
  public let team: TeamSide
  public var games = 1
  public var gamesStarted = 0
  public var plateAppearances = 0
  public var atBats = 0
  public var runs = 0
  public var singles = 0
  public var doubles = 0
  public var triples = 0
  public var homeRuns = 0
  public var runsBattedIn = 0
  public var walks = 0
  public var intentionalWalks = 0
  public var hitByPitch = 0
  public var strikeouts = 0
  public var sacrificeBunts = 0
  public var sacrificeFlies = 0
  public var reachedOnError = 0
  public var fieldersChoices = 0
  public var groundedIntoDoublePlay = 0
  public var stolenBases = 0
  public var caughtStealing = 0
  public var advanced: BattingAdvanced?

  public init(playerID: UUID, team: TeamSide) {
    self.playerID = playerID
    self.team = team
  }

  public var hits: Int { singles + doubles + triples + homeRuns }
  public var totalBases: Int { singles + 2 * doubles + 3 * triples + 4 * homeRuns }
}

public struct PitchingAdvanced: Codable, Hashable, Sendable {
  public var earnedRunAverage: Double?
  public var whip: Double?
  public var strikePercentage: Double?
  public var firstPitchStrikePercentage: Double?
  public var strikeoutsPerNine: Double?
  public var walksPerNine: Double?
  public var hitsPerNine: Double?
  public var homeRunsPerNine: Double?
  public var strikeoutRate: Double?
  public var walkRate: Double?
  public var strikeoutMinusWalkRate: Double?
  public var fip: Double?
  public var xFip: Double?
  public var eraPlus: Double?
  public var fipMinus: Double?
}

public struct PitchingLine: Identifiable, Codable, Hashable, Sendable {
  public var id: UUID { playerID }
  public let playerID: UUID
  public let team: TeamSide
  public var games = 1
  public var gamesStarted = 0
  public var wins = 0
  public var losses = 0
  public var saves = 0
  public var holds = 0
  public var battersFaced = 0
  public var outsRecorded = 0
  public var hitsAllowed = 0
  public var runsAllowed = 0
  public var earnedRuns = 0
  public var walks = 0
  public var intentionalWalks = 0
  public var hitBatters = 0
  public var strikeouts = 0
  public var homeRunsAllowed = 0
  public var wildPitches = 0
  public var balks = 0
  public var pitches = 0
  public var strikes = 0
  public var firstPitches = 0
  public var firstPitchStrikes = 0
  public var flyBalls = 0
  public var advanced: PitchingAdvanced?

  public init(playerID: UUID, team: TeamSide) {
    self.playerID = playerID
    self.team = team
  }

  public var inningsPitched: String { "\(outsRecorded / 3).\(outsRecorded % 3)" }
}

public struct FieldingAdvanced: Codable, Hashable, Sendable {
  public var fieldingPercentage: Double?
  public var rangeFactorPerNine: Double?
  public var caughtStealingPercentage: Double?
}

public struct FieldingLine: Identifiable, Codable, Hashable, Sendable {
  public var id: UUID { playerID }
  public let playerID: UUID
  public let team: TeamSide
  public var games = 1
  public var gamesStarted = 0
  public var inningsByPosition: [DefensivePosition: Int] = [:]
  public var putouts = 0
  public var assists = 0
  public var errors = 0
  public var doublePlays = 0
  public var triplePlays = 0
  public var passedBalls = 0
  public var catcherInterference = 0
  public var stealAttempts = 0
  public var caughtStealing = 0
  public var advanced: FieldingAdvanced?

  public init(playerID: UUID, team: TeamSide) {
    self.playerID = playerID
    self.team = team
  }

  public var totalChances: Int { putouts + assists + errors }
}

public struct TeamTotals: Identifiable, Codable, Hashable, Sendable {
  public var id: TeamSide { side }
  public let side: TeamSide
  public var runs: Int
  public var hits: Int
  public var errors: Int
  public var leftOnBase: Int
  public var inningRuns: [Int]
}

public struct StatSnapshot: Identifiable, Codable, Hashable, Sendable {
  public let id: UUID
  public let schemaVersion: String
  public let gameID: UUID
  public let organizationID: UUID
  public let seasonID: UUID
  public let status: SnapshotStatus
  public let gameVersion: Int
  public let decisionVersion: Int
  public let rulesProfileID: UUID
  public let rulesVersion: Int
  public let statEnvironmentID: UUID
  public let formulaVersion: String
  public let constantsVersion: String
  public let generatedAt: Date
  public var batting: [BattingLine]
  public var pitching: [PitchingLine]
  public var fielding: [FieldingLine]
  public var teams: [TeamTotals]
  public var validationIssues: [String]

  public init(
    id: UUID = UUID(), schemaVersion: String = "2.0", gameID: UUID,
    organizationID: UUID, seasonID: UUID, status: SnapshotStatus,
    gameVersion: Int, decisionVersion: Int, rulesProfileID: UUID,
    rulesVersion: Int, statEnvironmentID: UUID, formulaVersion: String,
    constantsVersion: String, generatedAt: Date,
    batting: [BattingLine], pitching: [PitchingLine],
    fielding: [FieldingLine], teams: [TeamTotals],
    validationIssues: [String]
  ) {
    self.id = id; self.schemaVersion = schemaVersion; self.gameID = gameID
    self.organizationID = organizationID; self.seasonID = seasonID
    self.status = status; self.gameVersion = gameVersion
    self.decisionVersion = decisionVersion; self.rulesProfileID = rulesProfileID
    self.rulesVersion = rulesVersion; self.statEnvironmentID = statEnvironmentID
    self.formulaVersion = formulaVersion; self.constantsVersion = constantsVersion
    self.generatedAt = generatedAt; self.batting = batting; self.pitching = pitching
    self.fielding = fielding; self.teams = teams; self.validationIssues = validationIssues
  }

  public var idempotencyKey: String {
    "\(gameID.uuidString.lowercased()):\(gameVersion):\(decisionVersion):\(status.rawValue)"
  }
}

public enum StatisticsEngine {
  public static func derive(
    seed: GameSeed,
    rules: GameRulesProfile,
    environment: StatEnvironment,
    events: [ScoringEvent],
    decisionVersion: Int = 0
  ) throws -> StatSnapshot {
    let effective = effectiveEvents(events)
    let projection = try ScoringEngine.replay(seed: seed, rules: rules, events: events)
    var batting: [UUID: BattingLine] = [:]
    var pitching: [UUID: PitchingLine] = [:]
    var fielding: [UUID: FieldingLine] = [:]
    var leftOnBase: [TeamSide: Int] = [.home: 0, .away: 0]

    for event in effective {
      switch event.payload {
      case .pitch(let pitch):
        let side = pitch.offense.opponent
        var line = pitching[pitch.pitcherID] ?? PitchingLine(playerID: pitch.pitcherID, team: side)
        line.pitches += 1
        if pitch.result.isStrike { line.strikes += 1 }
        if pitch.isFirstPitch {
          line.firstPitches += 1
          if pitch.result.isStrike { line.firstPitchStrikes += 1 }
        }
        if pitch.result == .balk { line.balks += 1 }
        pitching[pitch.pitcherID] = line

      case .plateAppearance(let appearance):
        var batter = batting[appearance.batterID]
          ?? BattingLine(playerID: appearance.batterID, team: appearance.offense)
        applyBatting(appearance, to: &batter)
        batting[appearance.batterID] = batter

        let defense = appearance.offense.opponent
        var pitcher = pitching[appearance.pitcherID]
          ?? PitchingLine(playerID: appearance.pitcherID, team: defense)
        applyPitching(appearance, to: &pitcher)
        pitching[appearance.pitcherID] = pitcher

        applyFielding(
          appearance,
          defense: defense,
          seed: seed,
          fielding: &fielding
        )

      case .runner(let runner):
        if runner.resolution.scored {
          var batter = batting[runner.resolution.playerID]
            ?? BattingLine(playerID: runner.resolution.playerID, team: runner.offense)
          batter.runs += 1
          batting[runner.resolution.playerID] = batter
          if let pitcherID = runner.resolution.responsiblePitcherID {
            var pitcher = pitching[pitcherID]
              ?? PitchingLine(playerID: pitcherID, team: runner.offense.opponent)
            pitcher.runsAllowed += 1
            if runner.resolution.earned != false { pitcher.earnedRuns += 1 }
            pitching[pitcherID] = pitcher
          }
        }
        if runner.resolution.reason == .stolenBase {
          var batter = batting[runner.resolution.playerID]
            ?? BattingLine(playerID: runner.resolution.playerID, team: runner.offense)
          batter.stolenBases += 1
          batting[runner.resolution.playerID] = batter
        }
        if runner.resolution.reason == .caughtStealing || runner.resolution.reason == .pickoff {
          var batter = batting[runner.resolution.playerID]
            ?? BattingLine(playerID: runner.resolution.playerID, team: runner.offense)
          batter.caughtStealing += 1
          batting[runner.resolution.playerID] = batter
          if let pitcherID = runner.resolution.responsiblePitcherID {
            var pitcher = pitching[pitcherID]
              ?? PitchingLine(playerID: pitcherID, team: runner.offense.opponent)
            pitcher.outsRecorded += runner.resolution.isOut ? 1 : 0
            pitching[pitcherID] = pitcher
          }
        }

      case .halfInningEnded:
        let prefix = effective.filter { $0.sequence < event.sequence }
        if let prior = try? ScoringEngine.replay(seed: seed, rules: rules, events: prefix) {
          leftOnBase[prior.offense, default: 0] += prior.bases.count
        }

      default:
        break
      }
    }

    batting = batting.mapValues { advancedBatting($0, environment: environment) }
    pitching = pitching.mapValues { advancedPitching($0, environment: environment) }
    fielding = fielding.mapValues { advancedFielding($0) }

    if projection.status == .final {
      leftOnBase[projection.offense, default: 0] += projection.bases.count
    }

    let teams = TeamSide.allCases.map { side in
      TeamTotals(
        side: side,
        runs: projection.score(side),
        hits: projection.hits(side),
        errors: projection.errors(side),
        leftOnBase: leftOnBase[side, default: 0],
        inningRuns: projection.inningRuns[side] ?? []
      )
    }

    let issues = validate(
      projection: projection,
      batting: Array(batting.values),
      pitching: Array(pitching.values),
      teams: teams
    )

    return StatSnapshot(
      id: UUID(), schemaVersion: "hp-stats-v1", gameID: seed.id,
      organizationID: seed.organizationID, seasonID: seed.seasonID,
      status: projection.status == .final ? .final : .provisional,
      gameVersion: projection.version, decisionVersion: decisionVersion,
      rulesProfileID: rules.id, rulesVersion: rules.version,
      statEnvironmentID: environment.id,
      formulaVersion: environment.formulaVersion,
      constantsVersion: environment.constantsVersion,
      generatedAt: Date(),
      batting: batting.values.sorted { playerName($0.playerID, seed) < playerName($1.playerID, seed) },
      pitching: pitching.values.sorted { playerName($0.playerID, seed) < playerName($1.playerID, seed) },
      fielding: fielding.values.sorted { playerName($0.playerID, seed) < playerName($1.playerID, seed) },
      teams: teams,
      validationIssues: issues
    )
  }

  private static func applyBatting(_ event: PlateAppearanceEvent, to line: inout BattingLine) {
    guard event.result != .foul else { return }
    line.plateAppearances += 1
    line.runsBattedIn += event.runsBattedIn
    switch event.result {
    case .single: line.atBats += 1; line.singles += 1
    case .double: line.atBats += 1; line.doubles += 1
    case .triple: line.atBats += 1; line.triples += 1
    case .homeRun: line.atBats += 1; line.homeRuns += 1
    case .walk: line.walks += 1
    case .intentionalWalk: line.walks += 1; line.intentionalWalks += 1
    case .hitByPitch: line.hitByPitch += 1
    case .strikeout: line.atBats += 1; line.strikeouts += 1
    case .sacrificeBunt: line.sacrificeBunts += 1
    case .sacrificeFly: line.sacrificeFlies += 1
    case .reachedOnError: line.atBats += 1; line.reachedOnError += 1
    case .fieldersChoice: line.atBats += 1; line.fieldersChoices += 1
    case .out: line.atBats += 1
    case .catcherInterference, .foul: break
    }
  }

  private static func applyPitching(_ event: PlateAppearanceEvent, to line: inout PitchingLine) {
    guard event.result != .foul else { return }
    line.battersFaced += 1
    if event.result.recordsBatterOut { line.outsRecorded += 1 }
    if event.result.isHit { line.hitsAllowed += 1 }
    if event.result == .homeRun { line.homeRunsAllowed += 1 }
    if event.result == .walk || event.result == .intentionalWalk { line.walks += 1 }
    if event.result == .intentionalWalk { line.intentionalWalks += 1 }
    if event.result == .hitByPitch { line.hitBatters += 1 }
    if event.result == .strikeout { line.strikeouts += 1 }
    if event.contact == .flyBall || event.contact == .popup { line.flyBalls += 1 }
  }

  private static func applyFielding(
    _ event: PlateAppearanceEvent,
    defense: TeamSide,
    seed: GameSeed,
    fielding: inout [UUID: FieldingLine]
  ) {
    if event.result.recordsBatterOut, let last = event.fielderSequence.last,
       let putoutPlayer = player(at: last, side: defense, seed: seed) {
      var line = fielding[putoutPlayer.id]
        ?? FieldingLine(playerID: putoutPlayer.id, team: defense)
      line.putouts += 1
      fielding[putoutPlayer.id] = line
      for position in event.fielderSequence.dropLast() {
        guard let assister = player(at: position, side: defense, seed: seed) else { continue }
        var assistLine = fielding[assister.id] ?? FieldingLine(playerID: assister.id, team: defense)
        assistLine.assists += 1
        fielding[assister.id] = assistLine
      }
    }
    if event.result == .reachedOnError, let fielderID = event.errorFielderID {
      var line = fielding[fielderID] ?? FieldingLine(playerID: fielderID, team: defense)
      line.errors += 1
      fielding[fielderID] = line
    }
    if event.result == .catcherInterference,
       let catcher = player(at: .catcher, side: defense, seed: seed) {
      var line = fielding[catcher.id] ?? FieldingLine(playerID: catcher.id, team: defense)
      line.catcherInterference += 1
      line.errors += 1
      fielding[catcher.id] = line
    }
  }

  private static func advancedBatting(
    _ line: BattingLine,
    environment: StatEnvironment
  ) -> BattingLine {
    var result = line
    let pa = Double(line.plateAppearances)
    let ab = Double(line.atBats)
    let hits = Double(line.hits)
    let average = ratio(hits, ab)
    let obpDenominator = Double(line.atBats + line.walks + line.hitByPitch + line.sacrificeFlies)
    let obp = ratio(Double(line.hits + line.walks + line.hitByPitch), obpDenominator)
    let slg = ratio(Double(line.totalBases), ab)
    let ops = (obp != nil && slg != nil) ? obp! + slg! : nil
    let babip = ratio(
      Double(line.hits - line.homeRuns),
      Double(line.atBats - line.strikeouts - line.homeRuns + line.sacrificeFlies)
    )
    var wOBA: Double?
    var wRAA: Double?
    var wRC: Double?
    var wRCPlus: Double?
    var opsPlus: Double?
    if environment.isCalibrated {
      let denominator = Double(
        line.atBats + line.walks - line.intentionalWalks + line.sacrificeFlies + line.hitByPitch
      )
      wOBA = ratio(
        Double(line.walks - line.intentionalWalks) * environment.walkWeight!
          + Double(line.hitByPitch) * environment.hitByPitchWeight!
          + Double(line.singles) * environment.singleWeight!
          + Double(line.doubles) * environment.doubleWeight!
          + Double(line.triples) * environment.tripleWeight!
          + Double(line.homeRuns) * environment.homeRunWeight!,
        denominator
      )
      if let wOBA {
        wRAA = ((wOBA - environment.leagueWOBA!) / environment.wOBAScale!) * pa
        wRC = wRAA! + environment.leagueRunsPerPlateAppearance! * pa
        if pa > 0 {
          wRCPlus = 100 * ((wRAA! / pa + environment.leagueRunsPerPlateAppearance!)
            / (environment.leagueRunsPerPlateAppearance! * environment.parkFactor!))
        }
      }
      if let obp, let slg {
        opsPlus = 100 * ((obp / environment.leagueOBP!) + (slg / environment.leagueSLG!) - 1)
      }
    }
    result.advanced = BattingAdvanced(
      average: average, onBasePercentage: obp, slugging: slg, ops: ops,
      iso: (slg != nil && average != nil) ? slg! - average! : nil,
      babip: babip, walkRate: ratio(Double(line.walks), pa),
      strikeoutRate: ratio(Double(line.strikeouts), pa),
      strikeoutMinusWalkRate: pa > 0
        ? Double(line.strikeouts - line.walks) / pa : nil,
      wOBA: wOBA, wRAA: wRAA, wRC: wRC, wRCPlus: wRCPlus, opsPlus: opsPlus
    )
    return result
  }

  private static func advancedPitching(
    _ line: PitchingLine,
    environment: StatEnvironment
  ) -> PitchingLine {
    var result = line
    let innings = Double(line.outsRecorded) / 3
    let bf = Double(line.battersFaced)
    let era = innings > 0 ? 9 * Double(line.earnedRuns) / innings : nil
    let fip = innings > 0 && environment.fipConstant != nil
      ? (13 * Double(line.homeRunsAllowed) + 3 * Double(line.walks + line.hitBatters)
          - 2 * Double(line.strikeouts)) / innings + environment.fipConstant!
      : nil
    let expectedHomeRuns = Double(line.flyBalls) * (environment.leagueHRPerFlyBall ?? 0)
    let xFip = innings > 0 && environment.fipConstant != nil && environment.leagueHRPerFlyBall != nil
      ? (13 * expectedHomeRuns + 3 * Double(line.walks + line.hitBatters)
          - 2 * Double(line.strikeouts)) / innings + environment.fipConstant!
      : nil
    result.advanced = PitchingAdvanced(
      earnedRunAverage: era,
      whip: innings > 0 ? Double(line.walks + line.hitsAllowed) / innings : nil,
      strikePercentage: ratio(Double(line.strikes), Double(line.pitches)),
      firstPitchStrikePercentage: ratio(Double(line.firstPitchStrikes), Double(line.firstPitches)),
      strikeoutsPerNine: innings > 0 ? 9 * Double(line.strikeouts) / innings : nil,
      walksPerNine: innings > 0 ? 9 * Double(line.walks) / innings : nil,
      hitsPerNine: innings > 0 ? 9 * Double(line.hitsAllowed) / innings : nil,
      homeRunsPerNine: innings > 0 ? 9 * Double(line.homeRunsAllowed) / innings : nil,
      strikeoutRate: ratio(Double(line.strikeouts), bf),
      walkRate: ratio(Double(line.walks), bf),
      strikeoutMinusWalkRate: bf > 0 ? Double(line.strikeouts - line.walks) / bf : nil,
      fip: fip,
      xFip: xFip,
      eraPlus: era.flatMap { value in
        value > 0 && environment.leagueERA != nil
          ? 100 * environment.leagueERA! * (environment.parkFactor ?? 1) / value : nil
      },
      fipMinus: fip.flatMap { value in
        environment.leagueFIP != nil && environment.leagueFIP! > 0
          ? 100 * value / (environment.leagueFIP! * (environment.parkFactor ?? 1)) : nil
      }
    )
    return result
  }

  private static func advancedFielding(_ line: FieldingLine) -> FieldingLine {
    var result = line
    let innings = Double(line.inningsByPosition.values.reduce(0, +)) / 3
    result.advanced = FieldingAdvanced(
      fieldingPercentage: ratio(Double(line.putouts + line.assists), Double(line.totalChances)),
      rangeFactorPerNine: innings > 0 ? 9 * Double(line.putouts + line.assists) / innings : nil,
      caughtStealingPercentage: ratio(Double(line.caughtStealing), Double(line.stealAttempts))
    )
    return result
  }

  private static func validate(
    projection: GameProjection,
    batting: [BattingLine],
    pitching: [PitchingLine],
    teams: [TeamTotals]
  ) -> [String] {
    var issues: [String] = []
    for line in batting {
      let expectedPA = line.atBats + line.walks + line.hitByPitch
        + line.sacrificeBunts + line.sacrificeFlies
      if expectedPA > line.plateAppearances { issues.append("batting_pa_reconciliation") }
      if line.hits > line.atBats { issues.append("hits_exceed_at_bats") }
    }
    for line in pitching where line.earnedRuns > line.runsAllowed {
      issues.append("earned_runs_exceed_runs")
    }
    if teams.first(where: { $0.side == .home })?.runs != projection.homeScore
      || teams.first(where: { $0.side == .away })?.runs != projection.awayScore {
      issues.append("team_score_reconciliation")
    }
    return Array(Set(issues)).sorted()
  }

  private static func effectiveEvents(_ events: [ScoringEvent]) -> [ScoringEvent] {
    var voided = Set<UUID>()
    for event in events.sorted(by: { $0.sequence < $1.sequence }) {
      switch event.payload {
      case .playVoided(let target, _): voided.insert(target)
      case .playRestored(let target): voided.remove(target)
      default: break
      }
    }
    return events.sorted(by: { $0.sequence < $1.sequence }).filter { event in
      if voided.contains(event.playID) { return false }
      switch event.payload {
      case .playVoided, .playRestored: return false
      default: return true
      }
    }
  }

  private static func player(
    at position: DefensivePosition,
    side: TeamSide,
    seed: GameSeed
  ) -> Player? {
    seed.team(side).lineup.first(where: { $0.position == position && $0.exitedAtSequence == nil })?.player
  }

  private static func playerName(_ id: UUID, _ seed: GameSeed) -> String {
    seed.player(id)?.displayName ?? id.uuidString
  }

  private static func ratio(_ numerator: Double, _ denominator: Double) -> Double? {
    denominator > 0 ? numerator / denominator : nil
  }
}

public protocol StatSnapshotPublisher: Sendable {
  func publish(_ snapshot: StatSnapshot) async throws
}

public actor InMemoryDashboardPublisher: StatSnapshotPublisher {
  private var snapshotsByKey: [String: StatSnapshot] = [:]
  private var latestByGame: [UUID: StatSnapshot] = [:]

  public init() {}

  public func publish(_ snapshot: StatSnapshot) async throws {
    snapshotsByKey[snapshot.idempotencyKey] = snapshot
    if let existing = latestByGame[snapshot.gameID], existing.gameVersion > snapshot.gameVersion {
      return
    }
    latestByGame[snapshot.gameID] = snapshot
  }

  public func latest(gameID: UUID) -> StatSnapshot? { latestByGame[gameID] }
  public func publicationCount() -> Int { snapshotsByKey.count }
}
