@preconcurrency import SQLite3
import Foundation
import HomePlateScoringCore

public enum EventStoreError: Error, LocalizedError, Sendable {
  case openFailed(String)
  case sqlite(String)
  case sequenceConflict(expected: Int, received: Int)
  case decodeFailed

  public var errorDescription: String? {
    switch self {
    case .openFailed(let message): "Could not open the scoring ledger: \(message)"
    case .sqlite(let message): "Scoring ledger error: \(message)"
    case .sequenceConflict(let expected, let received):
      "The next local sequence must be \(expected), not \(received)."
    case .decodeFailed: "A stored scoring event could not be decoded."
    }
  }
}

public actor SQLiteEventStore {
  private let connection: SQLiteConnection
  private let encoder: JSONEncoder
  private let decoder: JSONDecoder

  public init(url: URL) throws {
    connection = try SQLiteConnection(url: url)
    encoder = JSONEncoder()
    decoder = JSONDecoder()
    // Preserve Date's exact floating-point bit pattern so a force-quit/relaunch
    // replay is structurally identical, not merely visually identical.
    encoder.dateEncodingStrategy = .custom { date, encoder in
      var container = encoder.singleValueContainer()
      try container.encode("datebits:\(date.timeIntervalSinceReferenceDate.bitPattern)")
    }
    decoder.dateDecodingStrategy = .custom { decoder in
      let container = try decoder.singleValueContainer()
      if let seconds = try? container.decode(Double.self) {
        return Date(timeIntervalSince1970: seconds)
      }
      // Backward compatibility for ledgers written by the first lab build.
      let encoded = try container.decode(String.self)
      if encoded.hasPrefix("datebits:"),
         let bits = UInt64(encoded.dropFirst("datebits:".count)) {
        return Date(timeIntervalSinceReferenceDate: Double(bitPattern: bits))
      }
      let fractional = ISO8601DateFormatter()
      fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
      if let date = fractional.date(from: encoded) { return date }
      if let date = ISO8601DateFormatter().date(from: encoded) { return date }
      throw EventStoreError.decodeFailed
    }
    try connection.execute("PRAGMA journal_mode=WAL")
    try connection.execute("PRAGMA synchronous=FULL")
    try connection.execute("PRAGMA foreign_keys=ON")
    try connection.execute(Self.schema)
  }

  public func append(_ play: ScoringPlay) throws {
    guard let first = play.events.min(by: { $0.sequence < $1.sequence }) else { return }
    let current = try maximumSequence(gameID: first.gameID)
    let existingIDs = try existingEventIDs(play.events.map(\ScoringEvent.id))
    let newEvents = play.events.filter { !existingIDs.contains($0.id) }
    guard !newEvents.isEmpty else { return }
    let expected = current + 1
    guard newEvents.first?.sequence == expected else {
      throw EventStoreError.sequenceConflict(expected: expected, received: newEvents.first?.sequence ?? -1)
    }

    try connection.execute("BEGIN IMMEDIATE")
    do {
      for event in newEvents {
        let data = try encoder.encode(event)
        try connection.run(
          "INSERT INTO scoring_events(id, game_id, sequence, play_id, encoded, created_at) VALUES(?,?,?,?,?,?)",
          bindings: [
            .text(event.id.uuidString.lowercased()),
            .text(event.gameID.uuidString.lowercased()),
            .integer(Int64(event.sequence)),
            .text(event.playID.uuidString.lowercased()),
            .blob(data),
            .text(ISO8601DateFormatter().string(from: event.occurredAt)),
          ]
        )
        try connection.run(
          "INSERT OR IGNORE INTO scoring_outbox(event_id, game_id, sequence, encoded, state) VALUES(?,?,?,?, 'pending')",
          bindings: [
            .text(event.id.uuidString.lowercased()),
            .text(event.gameID.uuidString.lowercased()),
            .integer(Int64(event.sequence)),
            .blob(data),
          ]
        )
      }
      try connection.execute("COMMIT")
    } catch {
      try? connection.execute("ROLLBACK")
      throw error
    }
  }

  /// Inserts authoritative events without enqueuing them for upload.
  public func importSynced(_ events: [ScoringEvent]) throws {
    let ordered = events.sorted { $0.sequence < $1.sequence }
    try connection.execute("BEGIN IMMEDIATE")
    do {
      for event in ordered {
        let data = try encoder.encode(event)
        try connection.run(
          "INSERT OR IGNORE INTO scoring_events(id, game_id, sequence, play_id, encoded, created_at) VALUES(?,?,?,?,?,?)",
          bindings: [
            .text(event.id.uuidString.lowercased()),
            .text(event.gameID.uuidString.lowercased()),
            .integer(Int64(event.sequence)),
            .text(event.playID.uuidString.lowercased()),
            .blob(data),
            .text(ISO8601DateFormatter().string(from: event.occurredAt)),
          ]
        )
      }
      try connection.execute("COMMIT")
    } catch {
      try? connection.execute("ROLLBACK")
      throw error
    }
  }

  public func loadEvents(gameID: UUID) throws -> [ScoringEvent] {
    let rows = try connection.query(
      "SELECT encoded FROM scoring_events WHERE game_id = ? ORDER BY sequence ASC",
      bindings: [.text(gameID.uuidString.lowercased())]
    )
    return try rows.map { row in
      guard let data = row.first?.blobValue else { throw EventStoreError.decodeFailed }
      return try decoder.decode(ScoringEvent.self, from: data)
    }
  }

  public func pendingEvents(gameID: UUID) throws -> [ScoringEvent] {
    let rows = try connection.query(
      "SELECT encoded FROM scoring_outbox WHERE game_id = ? AND state = 'pending' ORDER BY sequence ASC",
      bindings: [.text(gameID.uuidString.lowercased())]
    )
    return try rows.map { row in
      guard let data = row.first?.blobValue else { throw EventStoreError.decodeFailed }
      return try decoder.decode(ScoringEvent.self, from: data)
    }
  }

  /// Returns unsent events grouped atomically by play, in ledger order.
  public func pendingPlays(gameID: UUID) throws -> [ScoringPlay] {
    let pending = try pendingEvents(gameID: gameID)
    var order: [UUID] = []
    var grouped: [UUID: [ScoringEvent]] = [:]
    for event in pending {
      if grouped[event.playID] == nil { order.append(event.playID) }
      grouped[event.playID, default: []].append(event)
    }
    return order.compactMap { playID in
      guard let events = grouped[playID]?.sorted(by: { $0.sequence < $1.sequence }),
            let first = events.first else { return nil }
      return ScoringPlay(
        id: playID,
        commandID: first.commandID,
        summary: "Pending scoring play",
        events: events
      )
    }
  }

  public func markPlaySynced(playID: UUID) throws {
    let rows = try connection.query(
      "SELECT event_id FROM scoring_outbox WHERE state = 'pending' AND event_id IN "
        + "(SELECT id FROM scoring_events WHERE play_id = ?)",
      bindings: [.text(playID.uuidString.lowercased())]
    )
    try markSynced(eventIDs: rows.compactMap { row in
      row.first?.textValue.flatMap(UUID.init(uuidString:))
    })
  }

  public func markSynced(eventIDs: [UUID]) throws {
    try connection.execute("BEGIN IMMEDIATE")
    do {
      for id in eventIDs {
        try connection.run(
          "UPDATE scoring_outbox SET state = 'synced', synced_at = ? WHERE event_id = ?",
          bindings: [
            .text(ISO8601DateFormatter().string(from: Date())),
            .text(id.uuidString.lowercased()),
          ]
        )
      }
      try connection.execute("COMMIT")
    } catch {
      try? connection.execute("ROLLBACK")
      throw error
    }
  }

  public func pendingCount(gameID: UUID) throws -> Int {
    let rows = try connection.query(
      "SELECT COUNT(*) FROM scoring_outbox WHERE game_id = ? AND state = 'pending'",
      bindings: [.text(gameID.uuidString.lowercased())]
    )
    return Int(rows.first?.first?.integerValue ?? 0)
  }

  public func saveProjection(_ projection: GameProjection, gameID: UUID) throws {
    let data = try encoder.encode(projection)
    try connection.run(
      "INSERT INTO state_snapshots(game_id, game_version, encoded, updated_at) VALUES(?,?,?,?) "
        + "ON CONFLICT(game_id) DO UPDATE SET game_version=excluded.game_version, encoded=excluded.encoded, updated_at=excluded.updated_at",
      bindings: [
        .text(gameID.uuidString.lowercased()),
        .integer(Int64(projection.version)),
        .blob(data),
        .text(ISO8601DateFormatter().string(from: Date())),
      ]
    )
  }

  public func loadProjection(gameID: UUID) throws -> GameProjection? {
    let rows = try connection.query(
      "SELECT encoded FROM state_snapshots WHERE game_id = ? LIMIT 1",
      bindings: [.text(gameID.uuidString.lowercased())]
    )
    guard let data = rows.first?.first?.blobValue else { return nil }
    return try decoder.decode(GameProjection.self, from: data)
  }

  public func saveDashboardSnapshot(_ snapshot: StatSnapshot) throws {
    let data = try encoder.encode(snapshot)
    try connection.run(
      "INSERT OR REPLACE INTO dashboard_snapshots(idempotency_key, game_id, game_version, encoded) VALUES(?,?,?,?)",
      bindings: [
        .text(snapshot.idempotencyKey),
        .text(snapshot.gameID.uuidString.lowercased()),
        .integer(Int64(snapshot.gameVersion)),
        .blob(data),
      ]
    )
  }

  private func maximumSequence(gameID: UUID) throws -> Int {
    let rows = try connection.query(
      "SELECT COALESCE(MAX(sequence), 0) FROM scoring_events WHERE game_id = ?",
      bindings: [.text(gameID.uuidString.lowercased())]
    )
    return Int(rows.first?.first?.integerValue ?? 0)
  }

  private func existingEventIDs(_ ids: [UUID]) throws -> Set<UUID> {
    var found = Set<UUID>()
    for id in ids {
      let rows = try connection.query(
        "SELECT id FROM scoring_events WHERE id = ? LIMIT 1",
        bindings: [.text(id.uuidString.lowercased())]
      )
      if !rows.isEmpty { found.insert(id) }
    }
    return found
  }

  private static let schema = """
    CREATE TABLE IF NOT EXISTS scoring_events(
      id TEXT PRIMARY KEY,
      game_id TEXT NOT NULL,
      sequence INTEGER NOT NULL,
      play_id TEXT NOT NULL,
      encoded BLOB NOT NULL,
      created_at TEXT NOT NULL,
      UNIQUE(game_id, sequence)
    );
    CREATE INDEX IF NOT EXISTS scoring_events_game_sequence
      ON scoring_events(game_id, sequence);
    CREATE TABLE IF NOT EXISTS scoring_outbox(
      event_id TEXT PRIMARY KEY REFERENCES scoring_events(id),
      game_id TEXT NOT NULL,
      sequence INTEGER NOT NULL,
      encoded BLOB NOT NULL,
      state TEXT NOT NULL CHECK(state IN ('pending','synced')),
      synced_at TEXT
    );
    CREATE INDEX IF NOT EXISTS scoring_outbox_pending
      ON scoring_outbox(game_id, state, sequence);
    CREATE TABLE IF NOT EXISTS state_snapshots(
      game_id TEXT PRIMARY KEY,
      game_version INTEGER NOT NULL,
      encoded BLOB NOT NULL,
      updated_at TEXT NOT NULL
    );
    CREATE TABLE IF NOT EXISTS dashboard_snapshots(
      idempotency_key TEXT PRIMARY KEY,
      game_id TEXT NOT NULL,
      game_version INTEGER NOT NULL,
      encoded BLOB NOT NULL
    );
    """
}

private final class SQLiteConnection: @unchecked Sendable {
  private var database: OpaquePointer?

  init(url: URL) throws {
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
    if sqlite3_open_v2(url.path, &database, flags, nil) != SQLITE_OK {
      let message = database.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "Unknown SQLite error"
      sqlite3_close(database)
      database = nil
      throw EventStoreError.openFailed(message)
    }
    sqlite3_busy_timeout(database, 3_000)
  }

  deinit { sqlite3_close(database) }

  func execute(_ sql: String) throws {
    guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
      throw EventStoreError.sqlite(errorMessage)
    }
  }

  func run(_ sql: String, bindings: [SQLiteBinding]) throws {
    let statement = try prepare(sql)
    defer { sqlite3_finalize(statement) }
    try bind(bindings, to: statement)
    guard sqlite3_step(statement) == SQLITE_DONE else {
      throw EventStoreError.sqlite(errorMessage)
    }
  }

  func query(_ sql: String, bindings: [SQLiteBinding]) throws -> [[SQLiteValue]] {
    let statement = try prepare(sql)
    defer { sqlite3_finalize(statement) }
    try bind(bindings, to: statement)
    var rows: [[SQLiteValue]] = []
    while true {
      let result = sqlite3_step(statement)
      if result == SQLITE_DONE { break }
      guard result == SQLITE_ROW else { throw EventStoreError.sqlite(errorMessage) }
      rows.append((0..<sqlite3_column_count(statement)).map { (index: Int32) -> SQLiteValue in
        switch sqlite3_column_type(statement, index) {
        case SQLITE_INTEGER: return .integer(sqlite3_column_int64(statement, index))
        case SQLITE_BLOB:
          let count = Int(sqlite3_column_bytes(statement, index))
          guard let bytes = sqlite3_column_blob(statement, index) else { return .null }
          return .blob(Data(bytes: bytes, count: count))
        case SQLITE_TEXT:
          guard let text = sqlite3_column_text(statement, index) else { return .null }
          return .text(String(cString: text))
        default: return .null
        }
      })
    }
    return rows
  }

  private func prepare(_ sql: String) throws -> OpaquePointer? {
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
      throw EventStoreError.sqlite(errorMessage)
    }
    return statement
  }

  private func bind(_ values: [SQLiteBinding], to statement: OpaquePointer?) throws {
    for (offset, value) in values.enumerated() {
      let index = Int32(offset + 1)
      let result: Int32
      switch value {
      case .integer(let integer): result = sqlite3_bind_int64(statement, index, integer)
      case .text(let text):
        result = sqlite3_bind_text(statement, index, text, -1, SQLITE_TRANSIENT)
      case .blob(let data):
        result = data.withUnsafeBytes { bytes in
          sqlite3_bind_blob(statement, index, bytes.baseAddress, Int32(data.count), SQLITE_TRANSIENT)
        }
      case .null: result = sqlite3_bind_null(statement, index)
      }
      guard result == SQLITE_OK else { throw EventStoreError.sqlite(errorMessage) }
    }
  }

  private var errorMessage: String {
    database.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "Unknown SQLite error"
  }
}

private enum SQLiteBinding {
  case integer(Int64)
  case text(String)
  case blob(Data)
  case null
}

private enum SQLiteValue {
  case integer(Int64)
  case text(String)
  case blob(Data)
  case null

  var integerValue: Int64? { if case .integer(let value) = self { value } else { nil } }
  var textValue: String? { if case .text(let value) = self { value } else { nil } }
  var blobValue: Data? { if case .blob(let value) = self { value } else { nil } }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
