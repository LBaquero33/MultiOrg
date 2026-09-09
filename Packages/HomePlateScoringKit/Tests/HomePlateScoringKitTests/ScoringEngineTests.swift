import Foundation
import HomePlateScoringCore
import XCTest

final class ScoringEngineTests: XCTestCase {
  private let seed = DemoGame.seed
  private let rules = GameRulesProfile.nfhs

  func testGameMustStartBeforeScoring() throws {
    XCTAssertThrowsError(try make(.recordPitch(.ball), events: [])) { error in
      XCTAssertEqual(error as? ScoringEngineError, .gameNotLive)
    }
  }

  func testFortyGoldenCountAndOutFixturesReplayDeterministically() throws {
    var fixtures: [GoldenFixture] = []
    for outs in 0...2 {
      for strikes in 0...2 {
        for balls in 0...3 {
          fixtures.append(.init(outs: outs, balls: balls, strikes: strikes, extraFouls: 0))
        }
      }
    }
    fixtures.append(contentsOf: (1...4).map {
      GoldenFixture(outs: 0, balls: 0, strikes: 2, extraFouls: $0)
    })
    XCTAssertEqual(fixtures.count, 40)

    for fixture in fixtures {
      var events = try startedEvents()
      for _ in 0..<fixture.outs {
        for _ in 0..<3 { try append(.recordPitch(.calledStrike), to: &events) }
      }
      for _ in 0..<fixture.strikes { try append(.recordPitch(.swingingStrike), to: &events) }
      for _ in 0..<fixture.balls { try append(.recordPitch(.ball), to: &events) }
      for _ in 0..<fixture.extraFouls { try append(.recordPitch(.foul), to: &events) }

      let first = try ScoringEngine.replay(seed: seed, rules: rules, events: events)
      let second = try ScoringEngine.replay(seed: seed, rules: rules, events: events.reversed())
      XCTAssertEqual(first, second, "Replay drifted for fixture \(fixture)")
      XCTAssertEqual(first.outs, fixture.outs)
      XCTAssertEqual(first.balls, fixture.balls)
      XCTAssertEqual(first.strikes, fixture.strikes)
      XCTAssertEqual(first.half, .top)
      XCTAssertEqual(first.inning, 1)
    }
  }

  func testFourBallsAtomicallyWalksBatter() throws {
    var events = try startedEvents()
    for _ in 0..<4 { try append(.recordPitch(.ball), to: &events) }
    let projection = try replay(events)
    let leadoff = seed.away.lineup[0].player.id

    XCTAssertEqual(projection.balls, 0)
    XCTAssertEqual(projection.strikes, 0)
    XCTAssertEqual(projection.bases[.first]?.playerID, leadoff)
    XCTAssertEqual(projection.battingIndexes[.away], 1)
    XCTAssertEqual(Set(events.suffix(3).map(\.playID)).count, 1)
  }

  func testStrikeoutRecordsOutAndAdvancesOrder() throws {
    var events = try startedEvents()
    for _ in 0..<3 { try append(.recordPitch(.swingingStrike), to: &events) }
    let projection = try replay(events)
    XCTAssertEqual(projection.outs, 1)
    XCTAssertEqual(projection.battingIndexes[.away], 1)
    XCTAssertEqual(projection.currentBatter(seed: seed)?.id, seed.away.lineup[1].player.id)
  }

  func testFoulWithTwoStrikesDoesNotStrikeOutBatter() throws {
    var events = try startedEvents()
    try append(.recordPitch(.calledStrike), to: &events)
    try append(.recordPitch(.foul), to: &events)
    for _ in 0..<5 { try append(.recordPitch(.foul), to: &events) }
    let projection = try replay(events)
    XCTAssertEqual(projection.strikes, 2)
    XCTAssertEqual(projection.outs, 0)
    XCTAssertEqual(projection.battingIndexes[.away], 0)
  }

  func testThirdOutAutomaticallyChangesHalfAndClearsBases() throws {
    var events = try startedEvents()
    try append(.recordBallInPlay(.init(contact: .lineDrive, result: .single)), to: &events)
    for _ in 0..<3 {
      for _ in 0..<3 { try append(.recordPitch(.calledStrike), to: &events) }
    }
    let projection = try replay(events)
    XCTAssertEqual(projection.half, .bottom)
    XCTAssertEqual(projection.inning, 1)
    XCTAssertEqual(projection.outs, 0)
    XCTAssertTrue(projection.bases.isEmpty)
  }

  func testHomeRunScoresBatterAndExistingRunner() throws {
    var events = try startedEvents()
    try append(.recordBallInPlay(.init(contact: .lineDrive, result: .single)), to: &events)
    try append(.recordBallInPlay(.init(
      contact: .flyBall,
      result: .homeRun,
      fielderSequence: [.centerField],
      location: .init(x: 0.52, y: 0.12),
      runsBattedIn: 2
    )), to: &events)
    let projection = try replay(events)
    XCTAssertEqual(projection.awayScore, 2)
    XCTAssertEqual(projection.awayHits, 2)
    XCTAssertTrue(projection.bases.isEmpty)
  }

  func testUndoAndRedoAreAppendOnlyAndReproduceState() throws {
    var events = try startedEvents()
    try append(.recordBallInPlay(.init(contact: .lineDrive, result: .single)), to: &events)
    let hitPlayID = try XCTUnwrap(ScoringEngine.lastReversiblePlayID(events: events))
    let afterHit = try replay(events)

    try append(.undo(playID: hitPlayID, reason: "Official scorer correction"), to: &events)
    let afterUndo = try replay(events)
    XCTAssertNil(afterUndo.bases[.first])
    XCTAssertEqual(afterUndo.awayHits, 0)
    XCTAssertTrue(afterUndo.voidedPlayIDs.contains(hitPlayID))

    let redoID = try XCTUnwrap(ScoringEngine.lastRedoablePlayID(events: events))
    try append(.redo(playID: redoID), to: &events)
    let afterRedo = try replay(events)
    XCTAssertEqual(afterRedo.bases, afterHit.bases)
    XCTAssertEqual(afterRedo.awayHits, afterHit.awayHits)
    XCTAssertGreaterThan(events.count, afterHit.version)
  }

  func testPitcherChangeKeepsExistingRunnerResponsibility() throws {
    var events = try startedEvents()
    try append(.recordBallInPlay(.init(contact: .lineDrive, result: .single)), to: &events)
    let oldPitcher = try XCTUnwrap(replay(events).bases[.first]?.responsiblePitcherID)
    let incoming = try XCTUnwrap(seed.home.bench.first)
    let outgoing = try XCTUnwrap(seed.home.activePitcher)
    try append(.substitute(.init(
      side: .home,
      outgoingPlayerID: outgoing.id,
      incomingPlayer: incoming,
      battingSlot: 9,
      position: .pitcher,
      reason: "Pitching change"
    )), to: &events)
    let projection = try replay(events)

    XCTAssertEqual(projection.currentPitcher(seed: seed)?.id, incoming.id)
    XCTAssertEqual(projection.bases[.first]?.responsiblePitcherID, oldPitcher)
  }

  func testStatisticsAndAllFourRFC4180ExportsReconcile() throws {
    var events = try startedEvents()
    try append(.recordBallInPlay(.init(
      contact: .groundBall,
      result: .out,
      fielderSequence: [.shortstop, .firstBase],
      location: .init(x: 0.43, y: 0.48)
    )), to: &events)
    for _ in 0..<4 { try append(.recordPitch(.ball), to: &events) }
    let snapshot = try StatisticsEngine.derive(
      seed: seed, rules: rules, environment: .lab2026, events: events
    )
    let exports = StatTableExporter.export(snapshot: snapshot, seed: seed)

    XCTAssertTrue(snapshot.validationIssues.isEmpty, snapshot.validationIssues.joined(separator: ", "))
    XCTAssertEqual(snapshot.teams.first(where: { $0.side == .away })?.hits, 0)
    XCTAssertEqual(snapshot.batting.reduce(0) { $0 + $1.walks }, 1)
    for csv in [exports.batting, exports.pitching, exports.fielding, exports.teamTotals] {
      XCTAssertTrue(csv.hasSuffix("\r\n"))
      XCTAssertFalse(csv.lowercased().contains("nan"))
      XCTAssertFalse(csv.lowercased().contains("infinity"))
      XCTAssertTrue(csv.contains(seed.id.uuidString.lowercased()))
    }
    XCTAssertTrue(exports.batting.hasPrefix("schema_version,snapshot_status"))
    XCTAssertTrue(exports.teamTotals.contains("inning_1_runs"))
  }

  func testDashboardPublisherIsIdempotentBySnapshotVersion() async throws {
    let events = try startedEvents()
    let snapshot = try StatisticsEngine.derive(
      seed: seed, rules: rules, environment: .lab2026, events: events
    )
    let publisher = InMemoryDashboardPublisher()
    try await publisher.publish(snapshot)
    try await publisher.publish(snapshot)
    let publicationCount = await publisher.publicationCount()
    let latest = await publisher.latest(gameID: seed.id)
    XCTAssertEqual(publicationCount, 1)
    XCTAssertEqual(latest?.idempotencyKey, snapshot.idempotencyKey)
  }

  private func startedEvents() throws -> [ScoringEvent] {
    try make(.startGame, events: []).events
  }

  private func make(_ command: ScoringCommand, events: [ScoringEvent]) throws -> ScoringPlay {
    try ScoringEngine.makePlay(command: command, seed: seed, rules: rules, events: events)
  }

  private func append(_ command: ScoringCommand, to events: inout [ScoringEvent]) throws {
    events.append(contentsOf: try make(command, events: events).events)
  }

  private func replay(_ events: [ScoringEvent]) throws -> GameProjection {
    try ScoringEngine.replay(seed: seed, rules: rules, events: events)
  }
}

private struct GoldenFixture: CustomStringConvertible {
  let outs: Int
  let balls: Int
  let strikes: Int
  let extraFouls: Int
  var description: String { "outs=\(outs), balls=\(balls), strikes=\(strikes), fouls=\(extraFouls)" }
}
