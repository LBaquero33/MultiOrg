import Foundation

public enum ScoringEngine {
  public static func replay(
    seed: GameSeed,
    rules: GameRulesProfile,
    events: [ScoringEvent]
  ) throws -> GameProjection {
    let ordered = events.sorted { $0.sequence < $1.sequence }
    let voided = resolveVoidedPlays(ordered)
    var projection = GameProjection(seed: seed)
    projection.voidedPlayIDs = voided
    projection.version = ordered.map(\ScoringEvent.sequence).max() ?? 0

    var groups: [(UUID, [ScoringEvent])] = []
    for event in ordered {
      if let last = groups.indices.last, groups[last].0 == event.playID {
        groups[last].1.append(event)
      } else {
        groups.append((event.playID, [event]))
      }
    }

    for (playID, group) in groups {
      guard let first = group.first else { continue }
      let isControl = group.contains { event in
        switch event.payload {
        case .playVoided, .playRestored: true
        default: false
        }
      }
      let isVoided = voided.contains(playID)

      if !isVoided || isControl {
        for event in group {
          try apply(event.payload, sequence: event.sequence, seed: seed, rules: rules, to: &projection)
        }
      }

      projection.playSummaries.append(
        PlaySummary(
          id: playID,
          sequence: first.sequence,
          inning: projection.inning,
          half: projection.half,
          text: describe(group, seed: seed),
          scoreAfter: "\(projection.awayScore)–\(projection.homeScore)",
          outsAfter: projection.outs,
          isCorrection: isControl || group.contains {
            if case .overrideApplied = $0.payload { true } else { false }
          },
          isVoided: isVoided
        )
      )
    }

    try validate(projection, rules: rules)
    return projection
  }

  public static func makePlay(
    command: ScoringCommand,
    seed: GameSeed,
    rules: GameRulesProfile,
    events: [ScoringEvent],
    authorityEpoch: Int = 1,
    now: Date = Date()
  ) throws -> ScoringPlay {
    let state = try replay(seed: seed, rules: rules, events: events)
    let playID = UUID()
    let commandID = UUID()
    var builder = EventBuilder(
      gameID: seed.id,
      playID: playID,
      commandID: commandID,
      authorityEpoch: authorityEpoch,
      nextSequence: state.version + 1,
      occurredAt: now,
      rulesVersion: rules.version
    )
    var summary = "Scoring action"

    switch command {
    case .startGame:
      guard state.status == .pregame else { throw ScoringEngineError.gameAlreadyStarted }
      builder.append(.gameStarted)
      summary = "Game started"

    case .recordPitch(let result):
      try requireLive(state)
      let matchup = try currentMatchup(state: state, seed: seed)
      builder.append(.pitch(.init(
        offense: state.offense,
        batterID: matchup.batter.id,
        pitcherID: matchup.pitcher.id,
        result: result,
        isFirstPitch: state.balls == 0 && state.strikes == 0
      )))
      summary = result.title

      switch result {
      case .ball where state.balls == 3,
           .intentionalBall where state.balls == 3:
        let forced = forcedWalkResolutions(
          state: state, batterID: matchup.batter.id, pitcherID: matchup.pitcher.id
        )
        let forcedRuns = forced.filter(\RunnerResolution.scored).count
        builder.append(.plateAppearance(.init(
          offense: state.offense, batterID: matchup.batter.id,
          pitcherID: matchup.pitcher.id, result: .walk,
          contact: nil, fielderSequence: [], location: nil,
          runsBattedIn: forcedRuns, errorFielderID: nil, note: "Four balls"
        )))
        forced.forEach { builder.append(.runner(.init(offense: state.offense, resolution: $0))) }
        summary = forcedRuns > 0 ? "Walk · \(forcedRuns) RBI" : "Walk"

      case .calledStrike where state.strikes == 2,
           .swingingStrike where state.strikes == 2:
        builder.append(.plateAppearance(.init(
          offense: state.offense, batterID: matchup.batter.id,
          pitcherID: matchup.pitcher.id, result: .strikeout,
          contact: nil, fielderSequence: [.catcher], location: nil,
          runsBattedIn: 0, errorFielderID: nil, note: result.title
        )))
        summary = result == .calledStrike ? "Strikeout looking" : "Strikeout swinging"

      case .hitByPitch:
        builder.append(.plateAppearance(.init(
          offense: state.offense, batterID: matchup.batter.id,
          pitcherID: matchup.pitcher.id, result: .hitByPitch,
          contact: nil, fielderSequence: [], location: nil,
          runsBattedIn: 0, errorFielderID: nil, note: "Hit by pitch"
        )))
        let forced = forcedWalkResolutions(
          state: state, batterID: matchup.batter.id, pitcherID: matchup.pitcher.id
        )
        forced.forEach { builder.append(.runner(.init(offense: state.offense, resolution: $0))) }

      case .intentionalWalk:
        let forced = forcedWalkResolutions(
          state: state, batterID: matchup.batter.id, pitcherID: matchup.pitcher.id
        )
        let forcedRuns = forced.filter(\RunnerResolution.scored).count
        builder.append(.plateAppearance(.init(
          offense: state.offense, batterID: matchup.batter.id,
          pitcherID: matchup.pitcher.id, result: .intentionalWalk,
          contact: nil, fielderSequence: [], location: nil,
          runsBattedIn: forcedRuns, errorFielderID: nil, note: "Intentional walk"
        )))
        forced.forEach { builder.append(.runner(.init(offense: state.offense, resolution: $0))) }

      case .catcherInterference:
        builder.append(.plateAppearance(.init(
          offense: state.offense, batterID: matchup.batter.id,
          pitcherID: matchup.pitcher.id, result: .catcherInterference,
          contact: nil, fielderSequence: [.catcher], location: nil,
          runsBattedIn: 0, errorFielderID: nil, note: "Catcher interference"
        )))
        let forced = forcedWalkResolutions(
          state: state, batterID: matchup.batter.id, pitcherID: matchup.pitcher.id
        )
        forced.forEach { builder.append(.runner(.init(offense: state.offense, resolution: $0))) }

      default:
        break
      }
      try appendAutomaticHalfEndIfNeeded(
        seed: seed, rules: rules, existing: events, builder: &builder, reason: "Three outs"
      )

    case .recordBallInPlay(let input):
      try requireLive(state)
      guard input.result != .walk, input.result != .intentionalWalk,
            input.result != .hitByPitch, input.result != .strikeout else {
        throw ScoringEngineError.illegalResult
      }
      let matchup = try currentMatchup(state: state, seed: seed)
      builder.append(.pitch(.init(
        offense: state.offense, batterID: matchup.batter.id,
        pitcherID: matchup.pitcher.id, result: .ballInPlay,
        isFirstPitch: state.balls == 0 && state.strikes == 0
      )))

      var resolutions = input.runnerResolutions
      if input.result == .homeRun {
        let existingRunnerIDs = Set(resolutions.map(\RunnerResolution.playerID))
        for runner in state.bases.values.sorted(by: { $0.base > $1.base })
          where !existingRunnerIDs.contains(runner.playerID) {
          resolutions.append(.init(
            playerID: runner.playerID, fromBase: runner.base, toBase: nil,
            scored: true, reason: .battedBall,
            responsiblePitcherID: runner.responsiblePitcherID,
            earned: !runner.placedByRule
          ))
        }
      }

      resolutions.sorted { ($0.fromBase?.rawValue ?? 0) > ($1.fromBase?.rawValue ?? 0) }
        .forEach { builder.append(.runner(.init(offense: state.offense, resolution: $0))) }

      builder.append(.plateAppearance(.init(
        offense: state.offense, batterID: matchup.batter.id,
        pitcherID: matchup.pitcher.id, result: input.result,
        contact: input.contact, fielderSequence: input.fielderSequence,
        location: input.location,
        runsBattedIn: input.runsBattedIn,
        errorFielderID: input.errorFielderID,
        note: input.note
      )))

      if input.result.basesAwarded > 0 {
        if input.result == .homeRun {
          builder.append(.runner(.init(
            offense: state.offense,
            resolution: .init(
              playerID: matchup.batter.id, fromBase: nil, toBase: nil,
              scored: true, reason: .battedBall,
              responsiblePitcherID: matchup.pitcher.id, earned: true
            )
          )))
        } else if let destination = Base(rawValue: input.result.basesAwarded) {
          builder.append(.runner(.init(
            offense: state.offense,
            resolution: .init(
              playerID: matchup.batter.id, fromBase: nil, toBase: destination,
              reason: .battedBall, responsiblePitcherID: matchup.pitcher.id
            )
          )))
        }
      } else if input.result == .reachedOnError || input.result == .fieldersChoice {
        builder.append(.runner(.init(
          offense: state.offense,
          resolution: .init(
            playerID: matchup.batter.id, fromBase: nil, toBase: .first,
            reason: input.result == .reachedOnError ? .fieldingError : .battedBall,
            responsiblePitcherID: matchup.pitcher.id
          )
        )))
      }
      summary = playDescription(input, batter: matchup.batter)
      try appendAutomaticHalfEndIfNeeded(
        seed: seed, rules: rules, existing: events, builder: &builder, reason: "Three outs"
      )

    case .advanceRunner(let resolution):
      try requireLive(state)
      guard state.bases.values.contains(where: { $0.playerID == resolution.playerID }) else {
        throw ScoringEngineError.runnerNotFound
      }
      builder.append(.runner(.init(offense: state.offense, resolution: resolution)))
      let player = seed.player(resolution.playerID)?.shortName ?? "Runner"
      summary = resolution.isOut
        ? "\(player) out · \(resolution.reason.title)"
        : resolution.scored
          ? "\(player) scored · \(resolution.reason.title)"
          : "\(player) to \(resolution.toBase?.label ?? "base") · \(resolution.reason.title)"
      try appendAutomaticHalfEndIfNeeded(
        seed: seed, rules: rules, existing: events, builder: &builder, reason: "Three outs"
      )

    case .substitute(let substitution):
      try requireLive(state)
      try validateSubstitution(substitution, state: state, rules: rules)
      builder.append(.substitution(.init(command: substitution)))
      summary = "\(substitution.incomingPlayer.shortName) entered at \(substitution.position.rawValue)"

    case .override(let override):
      try requireLive(state)
      guard !override.reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw ScoringEngineError.illegalResult
      }
      builder.append(.overrideApplied(override))
      summary = "Audited game override · \(override.reason)"

    case .endHalf(let reason):
      try requireLive(state)
      builder.append(.halfInningEnded(
        previousHalf: state.half, previousInning: state.inning, reason: reason
      ))
      summary = "End of \(state.half.rawValue) \(state.inning)"

    case .endGame(let reason):
      try requireLive(state)
      builder.append(.gameEnded(reason: reason))
      summary = "Game ended · \(reason)"

    case .undo(let targetPlayID, let reason):
      guard events.contains(where: { $0.playID == targetPlayID }) else {
        throw ScoringEngineError.playNotFound
      }
      guard !state.voidedPlayIDs.contains(targetPlayID) else {
        throw ScoringEngineError.illegalResult
      }
      builder.append(.playVoided(targetPlayID: targetPlayID, reason: reason))
      summary = "Undo · \(reason)"

    case .redo(let targetPlayID):
      guard state.voidedPlayIDs.contains(targetPlayID) else {
        throw ScoringEngineError.playNotFound
      }
      builder.append(.playRestored(targetPlayID: targetPlayID))
      summary = "Redo play"
    }

    return ScoringPlay(id: playID, commandID: commandID, summary: summary, events: builder.events)
  }

  public static func lastReversiblePlayID(events: [ScoringEvent]) -> UUID? {
    let voided = resolveVoidedPlays(events.sorted { $0.sequence < $1.sequence })
    return Dictionary(grouping: events, by: \ScoringEvent.playID)
      .values
      .filter { group in
        guard let first = group.first, !voided.contains(first.playID) else { return false }
        return group.contains { event in
          switch event.payload {
          case .pitch, .plateAppearance, .runner, .substitution, .overrideApplied: true
          default: false
          }
        }
      }
      .compactMap { $0.max(by: { $0.sequence < $1.sequence }) }
      .max(by: { $0.sequence < $1.sequence })?.playID
  }

  public static func lastRedoablePlayID(events: [ScoringEvent]) -> UUID? {
    let voided = resolveVoidedPlays(events.sorted { $0.sequence < $1.sequence })
    return events
      .filter { voided.contains($0.playID) }
      .max(by: { $0.sequence < $1.sequence })?.playID
  }

  private static func apply(
    _ payload: ScoringEventPayload,
    sequence: Int,
    seed: GameSeed,
    rules: GameRulesProfile,
    to state: inout GameProjection
  ) throws {
    switch payload {
    case .gameStarted:
      state.status = .live

    case .pitch(let pitch):
      if pitch.offense.opponent == .home { state.homePitchCount += 1 }
      else { state.awayPitchCount += 1 }
      switch pitch.result {
      case .ball, .intentionalBall:
        state.balls = min(4, state.balls + 1)
      case .calledStrike, .swingingStrike:
        state.strikes = min(3, state.strikes + 1)
      case .foul:
        state.strikes = min(2, state.strikes + 1)
      default:
        break
      }

    case .plateAppearance(let appearance):
      if appearance.result.recordsBatterOut { state.outs += 1 }
      if appearance.result.isHit {
        if appearance.offense == .home { state.homeHits += 1 } else { state.awayHits += 1 }
      }
      if appearance.result == .reachedOnError {
        if appearance.offense.opponent == .home { state.homeErrors += 1 }
        else { state.awayErrors += 1 }
      }
      state.balls = 0
      state.strikes = 0
      state.battingIndexes[appearance.offense, default: 0] += 1

    case .runner(let event):
      let resolution = event.resolution
      if let from = resolution.fromBase {
        guard state.bases[from]?.playerID == resolution.playerID else {
          throw ScoringEngineError.runnerNotFound
        }
        state.bases[from] = nil
      } else {
        for base in Base.allCases where state.bases[base]?.playerID == resolution.playerID {
          state.bases[base] = nil
        }
      }
      if resolution.isOut {
        state.outs += 1
      } else if resolution.scored {
        if event.offense == .home { state.homeScore += 1 } else { state.awayScore += 1 }
        ensureInningSlot(&state.inningRuns, side: event.offense, inning: state.inning)
        state.inningRuns[event.offense]![state.inning - 1] += 1
      } else if let destination = resolution.toBase {
        if let occupant = state.bases[destination], occupant.playerID != resolution.playerID {
          throw ScoringEngineError.destinationOccupied
        }
        state.bases[destination] = RunnerState(
          playerID: resolution.playerID,
          base: destination,
          responsiblePitcherID: resolution.responsiblePitcherID,
          placedByRule: resolution.reason == .placedRunner
        )
      }

    case .substitution(let event):
      var lineup = state.lineups[event.command.side] ?? seed.team(event.command.side).lineup
      guard let outgoingIndex = lineup.firstIndex(where: {
        $0.player.id == event.command.outgoingPlayerID && $0.exitedAtSequence == nil
      }) else { throw ScoringEngineError.substitutionInvalid("The outgoing player is not active.") }
      lineup[outgoingIndex].exitedAtSequence = sequence
      lineup.append(LineupEntry(
        player: event.command.incomingPlayer,
        battingSlot: event.command.battingSlot,
        position: event.command.position,
        isStarter: false,
        enteredAtSequence: sequence
      ))
      state.lineups[event.command.side] = lineup

    case .halfInningEnded:
      state.balls = 0
      state.strikes = 0
      state.outs = 0
      state.bases = [:]
      if state.half == .top {
        state.half = .bottom
      } else {
        state.half = .top
        state.inning += 1
      }

    case .overrideApplied(let override):
      if let inning = override.inning { state.inning = max(1, inning) }
      if let half = override.half { state.half = half }
      if let balls = override.balls { state.balls = balls }
      if let strikes = override.strikes { state.strikes = strikes }
      if let outs = override.outs { state.outs = outs }
      if let score = override.homeScore { state.homeScore = max(0, score) }
      if let score = override.awayScore { state.awayScore = max(0, score) }

    case .gameEnded:
      state.status = .final

    case .playVoided, .playRestored:
      break
    }
  }

  private static func validate(_ state: GameProjection, rules: GameRulesProfile) throws {
    guard (0...4).contains(state.balls), (0...3).contains(state.strikes) else {
      throw ScoringEngineError.invalidCount
    }
    guard (0...rules.outsPerHalf).contains(state.outs) else {
      throw ScoringEngineError.invalidOuts
    }
    let ids = state.bases.values.map(\RunnerState.playerID)
    guard Set(ids).count == ids.count else { throw ScoringEngineError.invalidBaseState }
  }

  private static func resolveVoidedPlays(_ events: [ScoringEvent]) -> Set<UUID> {
    var voided = Set<UUID>()
    for event in events {
      switch event.payload {
      case .playVoided(let target, _): voided.insert(target)
      case .playRestored(let target): voided.remove(target)
      default: break
      }
    }
    return voided
  }

  private static func currentMatchup(
    state: GameProjection,
    seed: GameSeed
  ) throws -> (batter: Player, pitcher: Player) {
    guard let batter = state.currentBatter(seed: seed) else { throw ScoringEngineError.missingBatter }
    guard let pitcher = state.currentPitcher(seed: seed) else { throw ScoringEngineError.missingPitcher }
    return (batter, pitcher)
  }

  private static func requireLive(_ state: GameProjection) throws {
    if state.status == .final { throw ScoringEngineError.gameFinal }
    guard state.status == .live else { throw ScoringEngineError.gameNotLive }
  }

  private static func forcedWalkResolutions(
    state: GameProjection,
    batterID: UUID,
    pitcherID: UUID
  ) -> [RunnerResolution] {
    var results: [RunnerResolution] = []
    if let third = state.bases[.third], state.bases[.second] != nil, state.bases[.first] != nil {
      results.append(.init(
        playerID: third.playerID, fromBase: .third, toBase: nil, scored: true,
        reason: .forced, responsiblePitcherID: third.responsiblePitcherID,
        earned: !third.placedByRule
      ))
    }
    if let second = state.bases[.second], state.bases[.first] != nil {
      results.append(.init(
        playerID: second.playerID, fromBase: .second, toBase: .third,
        reason: .forced, responsiblePitcherID: second.responsiblePitcherID
      ))
    }
    if let first = state.bases[.first] {
      results.append(.init(
        playerID: first.playerID, fromBase: .first, toBase: .second,
        reason: .forced, responsiblePitcherID: first.responsiblePitcherID
      ))
    }
    results.append(.init(
      playerID: batterID, fromBase: nil, toBase: .first,
      reason: .forced, responsiblePitcherID: pitcherID
    ))
    return results
  }

  private static func appendAutomaticHalfEndIfNeeded(
    seed: GameSeed,
    rules: GameRulesProfile,
    existing: [ScoringEvent],
    builder: inout EventBuilder,
    reason: String
  ) throws {
    let provisional = try replay(seed: seed, rules: rules, events: existing + builder.events)
    let halfRuns = provisional.inningRuns[provisional.offense]?[safe: provisional.inning - 1] ?? 0
    if provisional.outs >= rules.outsPerHalf || rules.runCap.map({ halfRuns >= $0 }) == true {
      builder.append(.halfInningEnded(
        previousHalf: provisional.half,
        previousInning: provisional.inning,
        reason: provisional.outs >= rules.outsPerHalf ? reason : "Run cap reached"
      ))
    }
  }

  private static func validateSubstitution(
    _ substitution: SubstitutionCommand,
    state: GameProjection,
    rules: GameRulesProfile
  ) throws {
    let lineup = state.lineups[substitution.side] ?? []
    guard lineup.contains(where: {
      $0.player.id == substitution.outgoingPlayerID && $0.exitedAtSequence == nil
    }) else { throw ScoringEngineError.substitutionInvalid("The outgoing player is not active.") }
    guard !lineup.contains(where: {
      $0.player.id == substitution.incomingPlayer.id && $0.exitedAtSequence == nil
    }) else { throw ScoringEngineError.substitutionInvalid("The incoming player is already active.") }
    if !rules.extraHitterAllowed && substitution.position == .extraHitter {
      throw ScoringEngineError.substitutionInvalid("The active rules profile does not allow an extra hitter.")
    }
    if !rules.designatedHitterAllowed && substitution.position == .designatedHitter {
      throw ScoringEngineError.substitutionInvalid("The active rules profile does not allow a designated hitter.")
    }
  }

  private static func describe(_ events: [ScoringEvent], seed: GameSeed) -> String {
    for event in events.reversed() {
      switch event.payload {
      case .gameStarted: return "Game started"
      case .pitch(let pitch): return pitch.result.title
      case .plateAppearance(let appearance):
        return "\(seed.player(appearance.batterID)?.shortName ?? "Batter") · \(appearance.result.title)"
      case .runner(let runner):
        let name = seed.player(runner.resolution.playerID)?.shortName ?? "Runner"
        if runner.resolution.isOut { return "\(name) out · \(runner.resolution.reason.title)" }
        if runner.resolution.scored { return "\(name) scored" }
        return "\(name) to \(runner.resolution.toBase?.label ?? "base")"
      case .substitution(let change): return "\(change.command.incomingPlayer.shortName) entered"
      case .halfInningEnded(let half, let inning, _): return "End of \(half.rawValue) \(inning)"
      case .overrideApplied(let override): return "Game override · \(override.reason)"
      case .playVoided(_, let reason): return "Undo · \(reason)"
      case .playRestored: return "Redo play"
      case .gameEnded(let reason): return "Game ended · \(reason)"
      }
    }
    return "Scoring action"
  }

  private static func playDescription(_ input: BallInPlayCommand, batter: Player) -> String {
    let sequence = input.fielderSequence.compactMap(\DefensivePosition.number).map(String.init).joined(separator: "–")
    return sequence.isEmpty
      ? "\(batter.shortName) · \(input.result.title)"
      : "\(batter.shortName) · \(input.result.title) · \(sequence)"
  }

  private static func ensureInningSlot(
    _ inningRuns: inout [TeamSide: [Int]],
    side: TeamSide,
    inning: Int
  ) {
    var values = inningRuns[side] ?? []
    while values.count < inning { values.append(0) }
    inningRuns[side] = values
  }
}

private struct EventBuilder {
  let gameID: UUID
  let playID: UUID
  let commandID: UUID
  let authorityEpoch: Int
  var nextSequence: Int
  let occurredAt: Date
  let rulesVersion: Int
  var events: [ScoringEvent] = []

  mutating func append(_ payload: ScoringEventPayload) {
    events.append(ScoringEvent(
      gameID: gameID,
      playID: playID,
      commandID: commandID,
      authorityEpoch: authorityEpoch,
      sequence: nextSequence,
      occurredAt: occurredAt,
      rulesVersion: rulesVersion,
      payload: payload
    ))
    nextSequence += 1
  }
}

private extension Array {
  subscript(safe index: Int) -> Element? {
    indices.contains(index) ? self[index] : nil
  }
}
