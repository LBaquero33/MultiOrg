import Foundation

public enum TeamSide: String, Codable, CaseIterable, Sendable {
  case away
  case home

  public var opponent: TeamSide { self == .home ? .away : .home }
  public var shortLabel: String { self == .home ? "HOME" : "AWAY" }
}

public enum GameHalf: String, Codable, CaseIterable, Sendable {
  case top
  case bottom

  public var offense: TeamSide { self == .top ? .away : .home }
  public var defense: TeamSide { offense.opponent }
}

public enum GameStatus: String, Codable, Sendable {
  case pregame, live, delayed, suspended, final
}

public enum Base: Int, Codable, CaseIterable, Comparable, Sendable {
  case first = 1
  case second = 2
  case third = 3

  public static func < (lhs: Base, rhs: Base) -> Bool { lhs.rawValue < rhs.rawValue }
  public var label: String { [1: "1B", 2: "2B", 3: "3B"][rawValue] ?? "" }
}

public enum DefensivePosition: String, Codable, CaseIterable, Sendable {
  case pitcher = "P"
  case catcher = "C"
  case firstBase = "1B"
  case secondBase = "2B"
  case thirdBase = "3B"
  case shortstop = "SS"
  case leftField = "LF"
  case centerField = "CF"
  case rightField = "RF"
  case designatedHitter = "DH"
  case extraHitter = "EH"
  case bench = "BN"

  public var number: Int? {
    switch self {
    case .pitcher: 1
    case .catcher: 2
    case .firstBase: 3
    case .secondBase: 4
    case .thirdBase: 5
    case .shortstop: 6
    case .leftField: 7
    case .centerField: 8
    case .rightField: 9
    case .designatedHitter, .extraHitter, .bench: nil
    }
  }
}

public enum Handedness: String, Codable, CaseIterable, Sendable {
  case left = "L"
  case right = "R"
  case switchHitter = "S"
  case unknown = "—"
}

/// Stable, transport-safe metadata for a player's scoring-screen portrait.
///
/// The bundled asset is always available to the offline lab. `remoteURL` and
/// `cacheKey` reserve the contract for a future cached-image source without
/// making the scoring engine or its projections depend on network access.
public struct PlayerPhotoReference: Codable, Hashable, Sendable {
  public var bundledAssetName: String
  public var remoteURL: URL?
  public var cacheKey: String?

  public init(
    bundledAssetName: String,
    remoteURL: URL? = nil,
    cacheKey: String? = nil
  ) {
    self.bundledAssetName = bundledAssetName
    self.remoteURL = remoteURL
    self.cacheKey = cacheKey
  }
}

public struct Player: Identifiable, Codable, Hashable, Sendable {
  public let id: UUID
  public var firstName: String
  public var lastName: String
  public var jerseyNumber: String
  public var bats: Handedness
  public var throwsHand: Handedness
  public var isPlaceholder: Bool
  public var photo: PlayerPhotoReference?

  public init(
    id: UUID = UUID(), firstName: String, lastName: String, jerseyNumber: String,
    bats: Handedness = .right, throwsHand: Handedness = .right,
    isPlaceholder: Bool = false,
    photo: PlayerPhotoReference? = nil
  ) {
    self.id = id
    self.firstName = firstName
    self.lastName = lastName
    self.jerseyNumber = jerseyNumber
    self.bats = bats
    self.throwsHand = throwsHand
    self.isPlaceholder = isPlaceholder
    self.photo = photo
  }

  public var displayName: String {
    let full = "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)
    return full.isEmpty ? "Player #\(jerseyNumber)" : full
  }

  public var shortName: String {
    guard let first = firstName.first else { return lastName }
    return "\(first). \(lastName)"
  }
}

public struct LineupEntry: Identifiable, Codable, Hashable, Sendable {
  public let id: UUID
  public var player: Player
  public var battingSlot: Int
  public var position: DefensivePosition
  public var isStarter: Bool
  public var enteredAtSequence: Int
  public var exitedAtSequence: Int?

  public init(
    id: UUID = UUID(), player: Player, battingSlot: Int,
    position: DefensivePosition, isStarter: Bool = true,
    enteredAtSequence: Int = 0, exitedAtSequence: Int? = nil
  ) {
    self.id = id
    self.player = player
    self.battingSlot = battingSlot
    self.position = position
    self.isStarter = isStarter
    self.enteredAtSequence = enteredAtSequence
    self.exitedAtSequence = exitedAtSequence
  }
}

public struct TeamConfiguration: Identifiable, Codable, Hashable, Sendable {
  public let id: UUID
  public var name: String
  public var abbreviation: String
  public var lineup: [LineupEntry]
  public var bench: [Player]

  public init(
    id: UUID = UUID(), name: String, abbreviation: String,
    lineup: [LineupEntry], bench: [Player] = []
  ) {
    self.id = id
    self.name = name
    self.abbreviation = abbreviation
    self.lineup = lineup.sorted { $0.battingSlot < $1.battingSlot }
    self.bench = bench
  }

  public func player(_ id: UUID) -> Player? {
    lineup.first(where: { $0.player.id == id })?.player ?? bench.first(where: { $0.id == id })
  }

  public var activePitcher: Player? {
    lineup.first(where: { $0.exitedAtSequence == nil && $0.position == .pitcher })?.player
  }
}

public struct GameSeed: Identifiable, Codable, Hashable, Sendable {
  public let id: UUID
  public var organizationID: UUID
  public var seasonID: UUID
  public var scheduledAt: Date
  public var venue: String
  public var home: TeamConfiguration
  public var away: TeamConfiguration

  public init(
    id: UUID = UUID(), organizationID: UUID = UUID(), seasonID: UUID = UUID(),
    scheduledAt: Date = Date(), venue: String,
    home: TeamConfiguration, away: TeamConfiguration
  ) {
    self.id = id
    self.organizationID = organizationID
    self.seasonID = seasonID
    self.scheduledAt = scheduledAt
    self.venue = venue
    self.home = home
    self.away = away
  }

  public func team(_ side: TeamSide) -> TeamConfiguration { side == .home ? home : away }
  public func player(_ id: UUID) -> Player? { home.player(id) ?? away.player(id) }
}

public struct RunnerState: Identifiable, Codable, Hashable, Sendable {
  public var id: UUID { playerID }
  public let playerID: UUID
  public var base: Base
  public let responsiblePitcherID: UUID?
  public let placedByRule: Bool

  public init(
    playerID: UUID, base: Base, responsiblePitcherID: UUID?, placedByRule: Bool = false
  ) {
    self.playerID = playerID
    self.base = base
    self.responsiblePitcherID = responsiblePitcherID
    self.placedByRule = placedByRule
  }
}

public enum PitchResult: String, Codable, CaseIterable, Identifiable, Sendable {
  case ball
  case calledStrike = "called_strike"
  case swingingStrike = "swinging_strike"
  case foul
  case ballInPlay = "ball_in_play"
  case hitByPitch = "hit_by_pitch"
  case intentionalBall = "intentional_ball"
  case intentionalWalk = "intentional_walk"
  case catcherInterference = "catcher_interference"
  case balk
  case illegalPitch = "illegal_pitch"

  public var id: String { rawValue }
  public var title: String {
    switch self {
    case .calledStrike: "Called Strike"
    case .swingingStrike: "Swing & Miss"
    case .ballInPlay: "Ball in Play"
    case .hitByPitch: "Hit By Pitch"
    case .intentionalBall: "Intentional Ball"
    case .intentionalWalk: "Intentional Walk"
    case .catcherInterference: "C. Interference"
    case .illegalPitch: "Illegal Pitch"
    default: rawValue.capitalized
    }
  }

  public var isStrike: Bool {
    self == .calledStrike || self == .swingingStrike || self == .foul || self == .ballInPlay
  }
}

public enum ContactType: String, Codable, CaseIterable, Identifiable, Sendable {
  case groundBall = "ground_ball"
  case hardGroundBall = "hard_ground_ball"
  case lineDrive = "line_drive"
  case flyBall = "fly_ball"
  case popup
  case bunt

  public var id: String { rawValue }
  public var title: String { rawValue.replacingOccurrences(of: "_", with: " ").capitalized }
}

public enum PlateAppearanceResult: String, Codable, CaseIterable, Identifiable, Sendable {
  case out
  case single
  case double
  case triple
  case homeRun = "home_run"
  case walk
  case intentionalWalk = "intentional_walk"
  case hitByPitch = "hit_by_pitch"
  case strikeout
  case reachedOnError = "reached_on_error"
  case fieldersChoice = "fielders_choice"
  case sacrificeBunt = "sacrifice_bunt"
  case sacrificeFly = "sacrifice_fly"
  case catcherInterference = "catcher_interference"
  case foul

  public var id: String { rawValue }
  public var title: String { rawValue.replacingOccurrences(of: "_", with: " ").capitalized }
  public var isHit: Bool { [.single, .double, .triple, .homeRun].contains(self) }
  public var basesAwarded: Int {
    switch self { case .single: 1; case .double: 2; case .triple: 3; case .homeRun: 4; default: 0 }
  }
  public var recordsBatterOut: Bool {
    self == .out || self == .strikeout || self == .sacrificeBunt || self == .sacrificeFly
  }
}

public enum RunnerAdvanceReason: String, Codable, CaseIterable, Identifiable, Sendable {
  case battedBall = "batted_ball"
  case forced
  case stolenBase = "stolen_base"
  case caughtStealing = "caught_stealing"
  case pickoff
  case defensiveIndifference = "defensive_indifference"
  case wildPitch = "wild_pitch"
  case passedBall = "passed_ball"
  case balk
  case fieldingError = "fielding_error"
  case courtesyRunner = "courtesy_runner"
  case placedRunner = "placed_runner"
  case other

  public var id: String { rawValue }
  public var title: String { rawValue.replacingOccurrences(of: "_", with: " ").capitalized }
}

public struct BallLocation: Codable, Hashable, Sendable {
  public var x: Double
  public var y: Double

  public init(x: Double, y: Double) {
    self.x = min(1, max(0, x))
    self.y = min(1, max(0, y))
  }
}

public struct RunnerResolution: Identifiable, Codable, Hashable, Sendable {
  public let id: UUID
  public let playerID: UUID
  public let fromBase: Base?
  public let toBase: Base?
  public let scored: Bool
  public let isOut: Bool
  public let reason: RunnerAdvanceReason
  public let responsiblePitcherID: UUID?
  public let earned: Bool?

  public init(
    id: UUID = UUID(), playerID: UUID, fromBase: Base?, toBase: Base?,
    scored: Bool = false, isOut: Bool = false,
    reason: RunnerAdvanceReason, responsiblePitcherID: UUID? = nil,
    earned: Bool? = nil
  ) {
    self.id = id
    self.playerID = playerID
    self.fromBase = fromBase
    self.toBase = toBase
    self.scored = scored
    self.isOut = isOut
    self.reason = reason
    self.responsiblePitcherID = responsiblePitcherID
    self.earned = earned
  }
}

public struct BallInPlayCommand: Codable, Hashable, Sendable {
  public var contact: ContactType
  public var result: PlateAppearanceResult
  public var fielderSequence: [DefensivePosition]
  public var location: BallLocation?
  public var runnerResolutions: [RunnerResolution]
  public var runsBattedIn: Int
  public var errorFielderID: UUID?
  public var note: String

  public init(
    contact: ContactType, result: PlateAppearanceResult,
    fielderSequence: [DefensivePosition] = [],
    location: BallLocation? = nil,
    runnerResolutions: [RunnerResolution] = [], runsBattedIn: Int = 0,
    errorFielderID: UUID? = nil, note: String = ""
  ) {
    self.contact = contact
    self.result = result
    self.fielderSequence = fielderSequence
    self.location = location
    self.runnerResolutions = runnerResolutions
    self.runsBattedIn = runsBattedIn
    self.errorFielderID = errorFielderID
    self.note = note
  }
}

public struct SubstitutionCommand: Codable, Hashable, Sendable {
  public var side: TeamSide
  public var outgoingPlayerID: UUID
  public var incomingPlayer: Player
  public var battingSlot: Int
  public var position: DefensivePosition
  public var reason: String

  public init(
    side: TeamSide,
    outgoingPlayerID: UUID,
    incomingPlayer: Player,
    battingSlot: Int,
    position: DefensivePosition,
    reason: String = "In-game substitution"
  ) {
    self.side = side
    self.outgoingPlayerID = outgoingPlayerID
    self.incomingPlayer = incomingPlayer
    self.battingSlot = battingSlot
    self.position = position
    self.reason = reason
  }
}

public struct GameOverride: Codable, Hashable, Sendable {
  public var inning: Int?
  public var half: GameHalf?
  public var balls: Int?
  public var strikes: Int?
  public var outs: Int?
  public var homeScore: Int?
  public var awayScore: Int?
  public var reason: String

  public init(
    inning: Int? = nil, half: GameHalf? = nil, balls: Int? = nil,
    strikes: Int? = nil, outs: Int? = nil, homeScore: Int? = nil,
    awayScore: Int? = nil, reason: String
  ) {
    self.inning = inning
    self.half = half
    self.balls = balls
    self.strikes = strikes
    self.outs = outs
    self.homeScore = homeScore
    self.awayScore = awayScore
    self.reason = reason
  }
}

public enum ScoringCommand: Codable, Hashable, Sendable {
  case startGame
  case recordPitch(PitchResult)
  case recordBallInPlay(BallInPlayCommand)
  case advanceRunner(RunnerResolution)
  case substitute(SubstitutionCommand)
  case override(GameOverride)
  case endHalf(reason: String)
  case endGame(reason: String)
  case undo(playID: UUID, reason: String)
  case redo(playID: UUID)
}

public struct PitchEvent: Codable, Hashable, Sendable {
  public let offense: TeamSide
  public let batterID: UUID
  public let pitcherID: UUID
  public let result: PitchResult
  public let isFirstPitch: Bool

  public init(offense: TeamSide, batterID: UUID, pitcherID: UUID, result: PitchResult, isFirstPitch: Bool) {
    self.offense = offense; self.batterID = batterID; self.pitcherID = pitcherID
    self.result = result; self.isFirstPitch = isFirstPitch
  }
}

public struct PlateAppearanceEvent: Codable, Hashable, Sendable {
  public let offense: TeamSide
  public let batterID: UUID
  public let pitcherID: UUID
  public let result: PlateAppearanceResult
  public let contact: ContactType?
  public let fielderSequence: [DefensivePosition]
  public let location: BallLocation?
  public let runsBattedIn: Int
  public let errorFielderID: UUID?
  public let note: String

  public init(offense: TeamSide, batterID: UUID, pitcherID: UUID, result: PlateAppearanceResult, contact: ContactType?, fielderSequence: [DefensivePosition], location: BallLocation? = nil, runsBattedIn: Int, errorFielderID: UUID?, note: String) {
    self.offense = offense; self.batterID = batterID; self.pitcherID = pitcherID
    self.result = result; self.contact = contact; self.fielderSequence = fielderSequence
    self.location = location; self.runsBattedIn = runsBattedIn
    self.errorFielderID = errorFielderID; self.note = note
  }
}

public struct RunnerEvent: Codable, Hashable, Sendable {
  public let offense: TeamSide
  public let resolution: RunnerResolution

  public init(offense: TeamSide, resolution: RunnerResolution) {
    self.offense = offense; self.resolution = resolution
  }
}

public struct SubstitutionEvent: Codable, Hashable, Sendable {
  public let command: SubstitutionCommand

  public init(command: SubstitutionCommand) { self.command = command }
}

public enum ScoringEventPayload: Codable, Hashable, Sendable {
  case gameStarted
  case pitch(PitchEvent)
  case plateAppearance(PlateAppearanceEvent)
  case runner(RunnerEvent)
  case substitution(SubstitutionEvent)
  case halfInningEnded(previousHalf: GameHalf, previousInning: Int, reason: String)
  case overrideApplied(GameOverride)
  case playVoided(targetPlayID: UUID, reason: String)
  case playRestored(targetPlayID: UUID)
  case gameEnded(reason: String)
}

public struct ScoringEvent: Identifiable, Codable, Hashable, Sendable {
  public let id: UUID
  public let gameID: UUID
  public let playID: UUID
  public let commandID: UUID
  public let authorityEpoch: Int
  public let sequence: Int
  public let occurredAt: Date
  public let rulesVersion: Int
  public let payload: ScoringEventPayload

  public init(
    id: UUID = UUID(), gameID: UUID, playID: UUID, commandID: UUID,
    authorityEpoch: Int, sequence: Int, occurredAt: Date = Date(),
    rulesVersion: Int, payload: ScoringEventPayload
  ) {
    self.id = id
    self.gameID = gameID
    self.playID = playID
    self.commandID = commandID
    self.authorityEpoch = authorityEpoch
    self.sequence = sequence
    self.occurredAt = occurredAt
    self.rulesVersion = rulesVersion
    self.payload = payload
  }
}

public struct ScoringPlay: Identifiable, Codable, Hashable, Sendable {
  public let id: UUID
  public let commandID: UUID
  public let summary: String
  public let events: [ScoringEvent]

  public init(id: UUID, commandID: UUID, summary: String, events: [ScoringEvent]) {
    self.id = id
    self.commandID = commandID
    self.summary = summary
    self.events = events
  }
}

public struct PlaySummary: Identifiable, Codable, Hashable, Sendable {
  public let id: UUID
  public let sequence: Int
  public let inning: Int
  public let half: GameHalf
  public let text: String
  public let scoreAfter: String
  public let outsAfter: Int
  public let isCorrection: Bool
  public let isVoided: Bool
}

public struct GameProjection: Codable, Hashable, Sendable {
  public var version = 0
  public var status: GameStatus = .pregame
  public var inning = 1
  public var half: GameHalf = .top
  public var balls = 0
  public var strikes = 0
  public var outs = 0
  public var homeScore = 0
  public var awayScore = 0
  public var homeHits = 0
  public var awayHits = 0
  public var homeErrors = 0
  public var awayErrors = 0
  public var homePitchCount = 0
  public var awayPitchCount = 0
  public var battingIndexes: [TeamSide: Int] = [.home: 0, .away: 0]
  public var bases: [Base: RunnerState] = [:]
  public var inningRuns: [TeamSide: [Int]] = [.home: [], .away: []]
  public var lineups: [TeamSide: [LineupEntry]] = [:]
  public var voidedPlayIDs: Set<UUID> = []
  public var playSummaries: [PlaySummary] = []

  public init(seed: GameSeed? = nil) {
    if let seed {
      lineups = [.home: seed.home.lineup, .away: seed.away.lineup]
    }
  }

  public var offense: TeamSide { half.offense }
  public var defense: TeamSide { half.defense }
  public var scoreText: String { "\(awayScore)–\(homeScore)" }
  public func score(_ side: TeamSide) -> Int { side == .home ? homeScore : awayScore }
  public func hits(_ side: TeamSide) -> Int { side == .home ? homeHits : awayHits }
  public func errors(_ side: TeamSide) -> Int { side == .home ? homeErrors : awayErrors }
  public func pitchCount(_ side: TeamSide) -> Int { side == .home ? homePitchCount : awayPitchCount }

  public func currentBatter(seed: GameSeed) -> Player? {
    let order = (lineups[offense] ?? seed.team(offense).lineup)
      .filter { $0.exitedAtSequence == nil }
      .sorted { $0.battingSlot < $1.battingSlot }
    guard !order.isEmpty else { return nil }
    let index = (battingIndexes[offense] ?? 0) % order.count
    return order[index].player
  }

  public func currentPitcher(seed: GameSeed) -> Player? {
    let order = lineups[defense] ?? seed.team(defense).lineup
    return order.first(where: { $0.exitedAtSequence == nil && $0.position == .pitcher })?.player
      ?? seed.team(defense).activePitcher
  }
}

public enum ScoringEngineError: Error, Equatable, LocalizedError, Sendable {
  case gameAlreadyStarted
  case gameNotLive
  case gameFinal
  case missingBatter
  case missingPitcher
  case invalidCount
  case invalidOuts
  case invalidBaseState
  case runnerNotFound
  case destinationOccupied
  case illegalResult
  case playNotFound
  case substitutionInvalid(String)

  public var errorDescription: String? {
    switch self {
    case .gameAlreadyStarted: "The game has already started."
    case .gameNotLive: "Start the game before scoring."
    case .gameFinal: "A final game cannot be changed without a correction."
    case .missingBatter: "The batting team has no active batter."
    case .missingPitcher: "The defensive team has no active pitcher."
    case .invalidCount: "The ball-strike count is invalid."
    case .invalidOuts: "The out count is invalid."
    case .invalidBaseState: "The requested play creates an invalid base state."
    case .runnerNotFound: "The selected runner is not on that base."
    case .destinationOccupied: "The destination base is occupied."
    case .illegalResult: "That result is not legal in the current state."
    case .playNotFound: "The selected play could not be found."
    case .substitutionInvalid(let message): message
    }
  }
}
