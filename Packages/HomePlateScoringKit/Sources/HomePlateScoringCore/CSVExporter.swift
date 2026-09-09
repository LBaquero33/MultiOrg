import Foundation

public struct StatCSVBundle: Sendable {
  public let batting: String
  public let pitching: String
  public let fielding: String
  public let teamTotals: String

  public init(batting: String, pitching: String, fielding: String, teamTotals: String) {
    self.batting = batting
    self.pitching = pitching
    self.fielding = fielding
    self.teamTotals = teamTotals
  }
}

public enum StatTableExporter {
  public static func export(snapshot: StatSnapshot, seed: GameSeed) -> StatCSVBundle {
    StatCSVBundle(
      batting: battingCSV(snapshot: snapshot, seed: seed),
      pitching: pitchingCSV(snapshot: snapshot, seed: seed),
      fielding: fieldingCSV(snapshot: snapshot, seed: seed),
      teamTotals: teamCSV(snapshot: snapshot, seed: seed)
    )
  }

  private static func battingCSV(snapshot: StatSnapshot, seed: GameSeed) -> String {
    let header = metadataHeaders + [
      "team_side", "team_name", "player_id", "player_name", "jersey_number",
      "G", "GS", "PA", "AB", "R", "H", "1B", "2B", "3B", "HR", "RBI",
      "BB", "IBB", "HBP", "SO", "SH", "SF", "ROE", "FC", "GIDP", "SB", "CS",
      "AVG", "OBP", "SLG", "OPS", "ISO", "BABIP", "BB_pct", "K_pct", "K_minus_BB_pct",
      "wOBA", "wRAA", "wRC", "wRC_plus", "OPS_plus"
    ]
    let rows = snapshot.batting.map { line -> [String] in
      let player = seed.player(line.playerID)
      let advanced = line.advanced
      return metadata(snapshot) + [
        line.team.rawValue, seed.team(line.team).name, line.playerID.uuidString.lowercased(),
        player?.displayName ?? "Unknown Player", player?.jerseyNumber ?? "",
        i(line.games), i(line.gamesStarted), i(line.plateAppearances), i(line.atBats), i(line.runs),
        i(line.hits), i(line.singles), i(line.doubles), i(line.triples), i(line.homeRuns),
        i(line.runsBattedIn), i(line.walks), i(line.intentionalWalks), i(line.hitByPitch),
        i(line.strikeouts), i(line.sacrificeBunts), i(line.sacrificeFlies), i(line.reachedOnError),
        i(line.fieldersChoices), i(line.groundedIntoDoublePlay), i(line.stolenBases), i(line.caughtStealing),
        d(advanced?.average), d(advanced?.onBasePercentage), d(advanced?.slugging), d(advanced?.ops),
        d(advanced?.iso), d(advanced?.babip), d(advanced?.walkRate), d(advanced?.strikeoutRate),
        d(advanced?.strikeoutMinusWalkRate), d(advanced?.wOBA), d(advanced?.wRAA),
        d(advanced?.wRC), d(advanced?.wRCPlus), d(advanced?.opsPlus)
      ]
    }
    return encode(header: header, rows: rows)
  }

  private static func pitchingCSV(snapshot: StatSnapshot, seed: GameSeed) -> String {
    let header = metadataHeaders + [
      "team_side", "team_name", "player_id", "player_name", "jersey_number",
      "G", "GS", "W", "L", "SV", "HLD", "BF", "IP", "H", "R", "ER", "BB", "IBB",
      "HBP", "SO", "HR", "WP", "BK", "pitches", "strikes", "first_pitch_strikes",
      "ERA", "WHIP", "strike_pct", "first_pitch_strike_pct", "K_per_9", "BB_per_9",
      "H_per_9", "HR_per_9", "K_pct", "BB_pct", "K_minus_BB_pct", "FIP", "xFIP",
      "ERA_plus", "FIP_minus"
    ]
    let rows = snapshot.pitching.map { line -> [String] in
      let player = seed.player(line.playerID)
      let advanced = line.advanced
      return metadata(snapshot) + [
        line.team.rawValue, seed.team(line.team).name, line.playerID.uuidString.lowercased(),
        player?.displayName ?? "Unknown Player", player?.jerseyNumber ?? "",
        i(line.games), i(line.gamesStarted), i(line.wins), i(line.losses), i(line.saves), i(line.holds),
        i(line.battersFaced), line.inningsPitched, i(line.hitsAllowed), i(line.runsAllowed),
        i(line.earnedRuns), i(line.walks), i(line.intentionalWalks), i(line.hitBatters),
        i(line.strikeouts), i(line.homeRunsAllowed), i(line.wildPitches), i(line.balks),
        i(line.pitches), i(line.strikes), i(line.firstPitchStrikes),
        d(advanced?.earnedRunAverage), d(advanced?.whip), d(advanced?.strikePercentage),
        d(advanced?.firstPitchStrikePercentage), d(advanced?.strikeoutsPerNine),
        d(advanced?.walksPerNine), d(advanced?.hitsPerNine), d(advanced?.homeRunsPerNine),
        d(advanced?.strikeoutRate), d(advanced?.walkRate), d(advanced?.strikeoutMinusWalkRate),
        d(advanced?.fip), d(advanced?.xFip), d(advanced?.eraPlus), d(advanced?.fipMinus)
      ]
    }
    return encode(header: header, rows: rows)
  }

  private static func fieldingCSV(snapshot: StatSnapshot, seed: GameSeed) -> String {
    let header = metadataHeaders + [
      "team_side", "team_name", "player_id", "player_name", "jersey_number", "G", "GS",
      "innings_by_position", "PO", "A", "E", "TC", "DP", "TP", "FPCT", "RF_per_9",
      "PB", "catcher_interference", "steal_attempts", "caught_stealing", "caught_stealing_pct"
    ]
    let rows = snapshot.fielding.map { line -> [String] in
      let player = seed.player(line.playerID)
      let positions = line.inningsByPosition
        .sorted { $0.key.rawValue < $1.key.rawValue }
        .map { "\($0.key.rawValue):\($0.value / 3).\($0.value % 3)" }
        .joined(separator: "|")
      return metadata(snapshot) + [
        line.team.rawValue, seed.team(line.team).name, line.playerID.uuidString.lowercased(),
        player?.displayName ?? "Unknown Player", player?.jerseyNumber ?? "",
        i(line.games), i(line.gamesStarted), positions, i(line.putouts), i(line.assists),
        i(line.errors), i(line.totalChances), i(line.doublePlays), i(line.triplePlays),
        d(line.advanced?.fieldingPercentage), d(line.advanced?.rangeFactorPerNine),
        i(line.passedBalls), i(line.catcherInterference), i(line.stealAttempts),
        i(line.caughtStealing), d(line.advanced?.caughtStealingPercentage)
      ]
    }
    return encode(header: header, rows: rows)
  }

  private static func teamCSV(snapshot: StatSnapshot, seed: GameSeed) -> String {
    let maxInnings = max(1, snapshot.teams.map(\TeamTotals.inningRuns.count).max() ?? 1)
    let inningHeaders = (1...maxInnings).map { "inning_\($0)_runs" }
    let header = metadataHeaders + ["team_side", "team_id", "team_name", "R", "H", "E", "LOB"] + inningHeaders
    let rows = snapshot.teams.map { totals in
      let team = seed.team(totals.side)
      let innings = (0..<maxInnings).map { index in
        index < totals.inningRuns.count ? i(totals.inningRuns[index]) : ""
      }
      return metadata(snapshot) + [
        totals.side.rawValue, team.id.uuidString.lowercased(), team.name,
        i(totals.runs), i(totals.hits), i(totals.errors), i(totals.leftOnBase)
      ] + innings
    }
    return encode(header: header, rows: rows)
  }

  private static let metadataHeaders = [
    "schema_version", "snapshot_status", "organization_id", "season_id", "game_id",
    "game_version", "decision_version", "rules_version", "formula_version", "constants_version",
    "generated_at"
  ]

  private static func metadata(_ snapshot: StatSnapshot) -> [String] {
    [
      snapshot.schemaVersion, snapshot.status.rawValue,
      snapshot.organizationID.uuidString.lowercased(), snapshot.seasonID.uuidString.lowercased(),
      snapshot.gameID.uuidString.lowercased(), i(snapshot.gameVersion), i(snapshot.decisionVersion),
      i(snapshot.rulesVersion), snapshot.formulaVersion, snapshot.constantsVersion,
      ISO8601DateFormatter().string(from: snapshot.generatedAt)
    ]
  }

  private static func encode(header: [String], rows: [[String]]) -> String {
    ([header] + rows).map { $0.map(escape).joined(separator: ",") }.joined(separator: "\r\n") + "\r\n"
  }

  private static func escape(_ value: String) -> String {
    guard value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r") else {
      return value
    }
    return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
  }

  private static func i(_ value: Int) -> String { String(value) }
  private static func d(_ value: Double?) -> String {
    guard let value, value.isFinite else { return "" }
    return String(format: "%.3f", value)
  }
}
