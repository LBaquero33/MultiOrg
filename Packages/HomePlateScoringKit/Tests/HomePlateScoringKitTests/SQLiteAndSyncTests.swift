import Foundation
import HomePlateScoringCore
import HomePlateScoringStore
import XCTest

final class SQLiteAndSyncTests: XCTestCase {
  private let seed = DemoGame.seed
  private let rules = GameRulesProfile.nfhs

  func testWALLedgerPersistsEventsAndProjectionAcrossReopen() async throws {
    let location = temporaryDatabaseURL()
    defer { removeDatabaseFamily(location) }
    let firstStore = try SQLiteEventStore(url: location)
    let start = try make(.startGame, events: [])
    try await firstStore.append(start)
    let events = try await firstStore.loadEvents(gameID: seed.id)
    let pitch = try make(.recordPitch(.ball), events: events)
    try await firstStore.append(pitch)
    let projection = try ScoringEngine.replay(
      seed: seed, rules: rules, events: events + pitch.events
    )
    try await firstStore.saveProjection(projection, gameID: seed.id)

    let reopened = try SQLiteEventStore(url: location)
    let restoredEvents = try await reopened.loadEvents(gameID: seed.id)
    let restoredProjection = try await reopened.loadProjection(gameID: seed.id)
    let restoredPendingCount = try await reopened.pendingCount(gameID: seed.id)
    XCTAssertEqual(restoredEvents, events + pitch.events)
    XCTAssertEqual(restoredProjection, projection)
    XCTAssertEqual(restoredPendingCount, restoredEvents.count)
  }

  func testDuplicateAtomicPlayDeliveryIsIdempotent() async throws {
    let location = temporaryDatabaseURL()
    defer { removeDatabaseFamily(location) }
    let store = try SQLiteEventStore(url: location)
    let start = try make(.startGame, events: [])
    try await store.append(start)
    try await store.append(start)
    let restored = try await store.loadEvents(gameID: seed.id)
    let pendingCount = try await store.pendingCount(gameID: seed.id)
    XCTAssertEqual(restored, start.events)
    XCTAssertEqual(pendingCount, start.events.count)
  }

  func testSequenceConflictRejectsDivergentLocalHistory() async throws {
    let location = temporaryDatabaseURL()
    defer { removeDatabaseFamily(location) }
    let store = try SQLiteEventStore(url: location)
    try await store.append(try make(.startGame, events: []))
    let conflictingStart = try make(.startGame, events: [])
    do {
      try await store.append(conflictingStart)
      XCTFail("Expected a sequence conflict")
    } catch let error as EventStoreError {
      guard case .sequenceConflict(expected: 2, received: 1) = error else {
        return XCTFail("Unexpected store error: \(error)")
      }
    }
  }

  func testOrderedOutboxSyncAndDuplicateRetry() async throws {
    let location = temporaryDatabaseURL()
    defer { removeDatabaseFamily(location) }
    let store = try SQLiteEventStore(url: location)
    var events: [ScoringEvent] = []
    for command in [ScoringCommand.startGame, .recordPitch(.ball), .recordPitch(.calledStrike)] {
      let play = try make(command, events: events)
      try await store.append(play)
      events.append(contentsOf: play.events)
    }
    let server = FakeAuthoritativeScoringServer()
    let service = ScoreSyncService(store: store, server: server)
    let first = try await service.sync(gameID: seed.id, authorityEpoch: 1)
    let retry = try await service.sync(gameID: seed.id, authorityEpoch: 1)
    let pendingCount = try await store.pendingCount(gameID: seed.id)
    let serverEvents = try await server.events(gameID: seed.id)

    XCTAssertEqual(first.uploaded, events.count)
    XCTAssertEqual(first.serverVersion, events.count)
    XCTAssertEqual(retry.uploaded, 0)
    XCTAssertEqual(pendingCount, 0)
    XCTAssertEqual(serverEvents, events)
  }

  func testOfflineKeepsOutboxPendingForRecovery() async throws {
    let location = temporaryDatabaseURL()
    defer { removeDatabaseFamily(location) }
    let store = try SQLiteEventStore(url: location)
    let start = try make(.startGame, events: [])
    try await store.append(start)
    let server = FakeAuthoritativeScoringServer()
    await server.setOnline(false)
    let service = ScoreSyncService(store: store, server: server)
    do {
      _ = try await service.sync(gameID: seed.id, authorityEpoch: 1)
      XCTFail("Expected offline sync failure")
    } catch {
      XCTAssertEqual(error as? ServerSyncError, .offline)
    }
    let pendingCount = try await store.pendingCount(gameID: seed.id)
    XCTAssertEqual(pendingCount, start.events.count)
  }

  func testAuthorityTakeoverStopsCompetingScorerHistory() async throws {
    let location = temporaryDatabaseURL()
    defer { removeDatabaseFamily(location) }
    let store = try SQLiteEventStore(url: location)
    let start = try make(.startGame, events: [])
    try await store.append(start)
    let server = FakeAuthoritativeScoringServer()
    _ = try await server.forceTakeover(gameID: seed.id)
    let service = ScoreSyncService(store: store, server: server)
    do {
      _ = try await service.sync(gameID: seed.id, authorityEpoch: 1)
      XCTFail("Expected authority conflict")
    } catch {
      XCTAssertEqual(error as? ServerSyncError, .authorityConflict(serverEpoch: 2, clientEpoch: 1))
    }
    let pendingCount = try await store.pendingCount(gameID: seed.id)
    XCTAssertEqual(pendingCount, start.events.count)
  }

  private func make(_ command: ScoringCommand, events: [ScoringEvent]) throws -> ScoringPlay {
    try ScoringEngine.makePlay(command: command, seed: seed, rules: rules, events: events)
  }

  private func temporaryDatabaseURL() -> URL {
    FileManager.default.temporaryDirectory
      .appendingPathComponent("homeplate-scoring-tests-\(UUID().uuidString)", isDirectory: true)
      .appendingPathComponent("ledger.sqlite")
  }

  private func removeDatabaseFamily(_ database: URL) {
    try? FileManager.default.removeItem(at: database.deletingLastPathComponent())
  }
}
