import Foundation
import HomePlateScoringCore

enum ProductionGameSeedAdapter {
  static func makeSeed(
    game: SDGame,
    participants: [SDEventParticipant],
    profiles: [SDScoringProfileV2],
    savedLineup: [SupabaseService.NativeSavedLineup] = []
  ) -> GameSeed {
    let profileByID = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0) })
    let participantPlayerIDs: [UUID] = participants.compactMap { participant -> UUID? in
      guard participant.participant_type == "player" else { return nil }
      return participant.player_id ?? participant.user_id
    }
    let organizationPlayerIDs = savedLineup.isEmpty ? Array(Set<UUID>(participantPlayerIDs)).sorted { $0.uuidString < $1.uuidString } : savedLineup.map(\.player_id)
    var organizationLineup = lineup(
      ids: organizationPlayerIDs,
      gameID: game.id,
      side: game.site == .away ? .away : .home,
      profiles: profileByID,
      placeholderName: game.site == .away ? game.away_team_name : game.home_team_name
    )
    if !savedLineup.isEmpty {
      organizationLineup = savedLineup.enumerated().map { index, row in
        let profile = profileByID[row.player_id]
        let names = (profile?.full_name ?? "Player \(index + 1)").split(separator: " ").map(String.init)
        return LineupEntry(player: Player(id: row.player_id, firstName: names.first ?? "Player", lastName: names.dropFirst().joined(separator: " "), jerseyNumber: String(index + 1)),
          battingSlot: row.batting_order, position: DefensivePosition(rawValue: row.position_code.uppercased()) ?? .extraHitter)
      }
    }
    let organizationIsHome = game.site != .away
    let home = TeamConfiguration(
      id: organizationIsHome ? game.team_id : game.opponent_team_id ?? stableID(game.id, "opponent-home"),
      name: game.home_team_name,
      abbreviation: abbreviation(game.home_team_name),
      lineup: organizationIsHome ? organizationLineup : placeholderLineup(game: game, side: .home)
    )
    let away = TeamConfiguration(
      id: organizationIsHome ? game.opponent_team_id ?? stableID(game.id, "opponent-away") : game.team_id,
      name: game.away_team_name,
      abbreviation: abbreviation(game.away_team_name),
      lineup: organizationIsHome ? placeholderLineup(game: game, side: .away) : organizationLineup
    )
    return GameSeed(
      id: game.id,
      organizationID: game.org_id,
      seasonID: game.season_id ?? stableID(game.id, "season"),
      scheduledAt: game.created_at ?? Date(),
      venue: game.venue_name ?? "Venue to be confirmed",
      home: home,
      away: away
    )
  }

  static func rules(for game: SDGame) -> GameRulesProfile {
    var rules = GameRulesProfile.nfhs
    rules.version = game.ruleset_version ?? 1
    rules.scheduledInnings = game.scheduled_innings
    rules.sourceName = "Home Plate ruleset snapshot"
    rules.sourceVersion = "game-\(rules.version)"
    let resolved = SDResolvedBaseballRules.resolve([game.ruleset_snapshot])
    rules.outsPerHalf = resolved.outsPerHalf
    rules.tiesAllowed = resolved.tiesAllowed
    rules.extraInningsAllowed = resolved.extraInningsAllowed
    rules.continuousBatting = resolved.continuousBatting
    rules.stealingAllowed = resolved.stealingAllowed
    rules.leadoffsAllowed = resolved.leadoffsAllowed
    rules.droppedThirdStrike = resolved.droppedThirdStrike
    rules.runCap = resolved.runCap
    rules.timeLimitMinutes = resolved.timeLimitMinutes
    rules.noNewInningAfterLimit = resolved.noNewInning
    rules.placedRunnerBase = resolved.placedRunnerBase.flatMap(Base.init(rawValue:))
    // Do not inherit NFHS mercy rules when the organization has not configured them.
    if case .array(let rows) = game.ruleset_snapshot["mercy_thresholds"] {
      rules.mercyThresholds = rows.compactMap { value in
        guard case .object(let row) = value, let inning = row.int("after_inning"),
              let difference = row.int("run_difference"), inning > 0, difference > 0 else { return nil }
        return MercyThreshold(afterInning: inning, runDifference: difference)
      }
    } else { rules.mercyThresholds = [] }
    return rules
  }

  static var statisticsEnvironment: StatEnvironment {
    StatEnvironment(
      name: "Home Plate game statistics",
      formulaVersion: "hp-sabermetrics-v2",
      constantsVersion: "not-configured",
      walkWeight: nil, hitByPitchWeight: nil, singleWeight: nil,
      doubleWeight: nil, tripleWeight: nil, homeRunWeight: nil,
      wOBAScale: nil, leagueWOBA: nil, leagueRunsPerPlateAppearance: nil,
      fipConstant: nil, leagueERA: nil, leagueOBP: nil, leagueSLG: nil,
      leagueFIP: nil, leagueHRPerFlyBall: nil, parkFactor: nil
    )
  }

  private static let positions: [DefensivePosition] = [
    .pitcher, .catcher, .firstBase, .secondBase, .thirdBase,
    .shortstop, .leftField, .centerField, .rightField,
  ]

  private static func lineup(
    ids: [UUID], gameID: UUID, side: TeamSide,
    profiles: [UUID: SDScoringProfileV2], placeholderName: String
  ) -> [LineupEntry] {
    (0..<9).map { index in
      let compact = String(gameID.uuidString.replacingOccurrences(of: "-", with: "").prefix(10))
      let placeholder = UUID(uuidString: "00000000-0000-4000-8000-\(compact)\(side == .home ? "1" : "2")\(index)")!
      let id = ids.indices.contains(index) ? ids[index] : placeholder
      let profile = profiles[id]
      let names = (profile?.full_name ?? "\(placeholderName) Player \(index + 1)")
        .split(separator: " ").map(String.init)
      return LineupEntry(
        player: Player(
          id: id,
          firstName: names.first ?? "Player",
          lastName: names.dropFirst().joined(separator: " "),
          jerseyNumber: String(index + 1),
          isPlaceholder: profile == nil,
          photo: profile?.avatarURL.map {
            PlayerPhotoReference(bundledAssetName: "", remoteURL: $0, cacheKey: id.uuidString)
          }
        ),
        battingSlot: index + 1,
        position: positions[index]
      )
    }
  }

  private static func placeholderLineup(game: SDGame, side: TeamSide) -> [LineupEntry] {
    lineup(ids: [], gameID: game.id, side: side, profiles: [:], placeholderName: side == .home ? game.home_team_name : game.away_team_name)
  }

  private static func abbreviation(_ name: String) -> String {
    let initials = name.split(separator: " ").compactMap(\.first)
    return String(initials.isEmpty ? Array(name.prefix(3)) : Array(initials.prefix(3))).uppercased()
  }

  private static func stableID(_ namespace: UUID, _ value: String) -> UUID {
    var hashOne: UInt64 = 14_695_981_039_346_656_037
    var hashTwo: UInt64 = 10_995_116_282_11
    for byte in "\(namespace.uuidString.lowercased()):\(value)".utf8 {
      hashOne = (hashOne ^ UInt64(byte)) &* 1_099_511_628_211
      hashTwo = (hashTwo &* 1_099_511_628_211) ^ UInt64(byte)
    }
    var bytes = withUnsafeBytes(of: hashOne.bigEndian, Array.init)
      + withUnsafeBytes(of: hashTwo.bigEndian, Array.init)
    bytes[6] = (bytes[6] & 0x0F) | 0x40
    bytes[8] = (bytes[8] & 0x3F) | 0x80
    return bytes.withUnsafeBufferPointer { buffer in
      UUID(uuidString: NSUUID(uuidBytes: buffer.baseAddress!).uuidString)!
    }
  }
}
