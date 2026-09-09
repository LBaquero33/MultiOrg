import Foundation
import HomePlateScoringCore

public enum ServerSyncError: Error, Equatable, LocalizedError, Sendable {
  case offline
  case staleVersion(server: Int, clientExpected: Int)
  case authorityConflict(serverEpoch: Int, clientEpoch: Int)
  case nonSequentialEvent(expected: Int, received: Int)

  public var errorDescription: String? {
    switch self {
    case .offline: "The simulated scoring server is offline."
    case .staleVersion(let server, let expected):
      "Server version \(server) does not match client expectation \(expected)."
    case .authorityConflict(let server, let client):
      "Scorekeeper authority changed from epoch \(client) to \(server). Manual reconciliation is required."
    case .nonSequentialEvent(let expected, let received):
      "The server expected sequence \(expected), not \(received)."
    }
  }
}

public struct SyncReport: Equatable, Sendable {
  public let uploaded: Int
  public let serverVersion: Int
  public let authorityEpoch: Int

  public init(uploaded: Int, serverVersion: Int, authorityEpoch: Int) {
    self.uploaded = uploaded
    self.serverVersion = serverVersion
    self.authorityEpoch = authorityEpoch
  }
}

public actor FakeAuthoritativeScoringServer {
  private struct ServerGame: Sendable {
    var authorityEpoch = 1
    var events: [ScoringEvent] = []
  }

  private var games: [UUID: ServerGame] = [:]
  private var online = true

  public init() {}

  public func setOnline(_ online: Bool) { self.online = online }
  public func isOnline() -> Bool { online }

  public func acquire(gameID: UUID) throws -> Int {
    guard online else { throw ServerSyncError.offline }
    if games[gameID] == nil { games[gameID] = ServerGame() }
    return games[gameID]!.authorityEpoch
  }

  public func bootstrap(gameID: UUID, events: [ScoringEvent], authorityEpoch: Int = 1) {
    guard games[gameID] == nil else { return }
    games[gameID] = ServerGame(
      authorityEpoch: authorityEpoch,
      events: events.sorted { $0.sequence < $1.sequence }
    )
  }

  public func forceTakeover(gameID: UUID) throws -> Int {
    guard online else { throw ServerSyncError.offline }
    var game = games[gameID] ?? ServerGame()
    game.authorityEpoch += 1
    games[gameID] = game
    return game.authorityEpoch
  }

  public func version(gameID: UUID) -> Int {
    games[gameID]?.events.map(\ScoringEvent.sequence).max() ?? 0
  }

  public func authorityEpoch(gameID: UUID) -> Int {
    games[gameID]?.authorityEpoch ?? 1
  }

  public func append(
    gameID: UUID,
    events incoming: [ScoringEvent],
    expectedVersion: Int,
    authorityEpoch: Int
  ) throws -> [ScoringEvent] {
    guard online else { throw ServerSyncError.offline }
    var game = games[gameID] ?? ServerGame()
    guard authorityEpoch == game.authorityEpoch else {
      throw ServerSyncError.authorityConflict(
        serverEpoch: game.authorityEpoch,
        clientEpoch: authorityEpoch
      )
    }

    let existingIDs = Set(game.events.map(\ScoringEvent.id))
    let newEvents = incoming.filter { !existingIDs.contains($0.id) }
    if newEvents.isEmpty { return incoming }
    let serverVersion = game.events.map(\ScoringEvent.sequence).max() ?? 0
    guard serverVersion == expectedVersion else {
      throw ServerSyncError.staleVersion(server: serverVersion, clientExpected: expectedVersion)
    }
    var next = serverVersion + 1
    for event in newEvents.sorted(by: { $0.sequence < $1.sequence }) {
      guard event.sequence == next else {
        throw ServerSyncError.nonSequentialEvent(expected: next, received: event.sequence)
      }
      game.events.append(event)
      next += 1
    }
    games[gameID] = game
    return incoming
  }

  public func events(gameID: UUID) throws -> [ScoringEvent] {
    guard online else { throw ServerSyncError.offline }
    return games[gameID]?.events.sorted { $0.sequence < $1.sequence } ?? []
  }
}

public actor ScoreSyncService {
  private let store: SQLiteEventStore
  private let server: FakeAuthoritativeScoringServer

  public init(store: SQLiteEventStore, server: FakeAuthoritativeScoringServer) {
    self.store = store
    self.server = server
  }

  public func sync(gameID: UUID, authorityEpoch: Int) async throws -> SyncReport {
    let pending = try await store.pendingEvents(gameID: gameID)
    let serverVersion = await server.version(gameID: gameID)
    guard !pending.isEmpty else {
      return SyncReport(
        uploaded: 0,
        serverVersion: serverVersion,
        authorityEpoch: await server.authorityEpoch(gameID: gameID)
      )
    }
    let firstSequence = pending.map(\ScoringEvent.sequence).min() ?? 1
    _ = try await server.append(
      gameID: gameID,
      events: pending,
      expectedVersion: firstSequence - 1,
      authorityEpoch: authorityEpoch
    )
    try await store.markSynced(eventIDs: pending.map(\ScoringEvent.id))
    return SyncReport(
      uploaded: pending.count,
      serverVersion: await server.version(gameID: gameID),
      authorityEpoch: authorityEpoch
    )
  }
}
