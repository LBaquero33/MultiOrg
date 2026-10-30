import Foundation

struct SDQueuedScoringEvent: Codable, Equatable, Sendable, Identifiable {
  let id: UUID
  let type: SDScoringEventType
  let payload: [String: SDJSONValue]
}

struct SDQueuedScoringCommand: Codable, Equatable, Sendable, Identifiable {
  let id: UUID
  let expectedVersion: Int
  let events: [SDQueuedScoringEvent]
  let createdAt: Date
}

struct SDGameScoringJournal: Codable, Equatable, Sendable {
  let organizationId: UUID
  let gameId: UUID
  let actorUserId: UUID
  let deviceId: UUID
  let authorityVerifiedAt: Date
  let authorityEpoch: Int
  var baseServerVersion: Int
  var baseState: SDGameState
  var commands: [SDQueuedScoringCommand]
  var conflictReason: String?

  var hasConflict: Bool { conflictReason != nil }
  var hasPendingCommands: Bool { !commands.isEmpty }

  func matches(
    organizationId: UUID, gameId: UUID, actorUserId: UUID, deviceId: UUID, authorityEpoch: Int
  ) -> Bool {
    self.organizationId == organizationId && self.gameId == gameId
      && self.actorUserId == actorUserId && self.deviceId == deviceId
      && self.authorityEpoch == authorityEpoch
  }

  func projection(from serverState: SDGameState, rules: SDResolvedBaseballRules) throws -> SDGameState {
    guard !hasConflict, serverState.version == baseServerVersion else {
      throw SDGameScoringJournalError.serverHeadChanged
    }
    return try commands.reduce(serverState) { initialState, command in
      try command.events.enumerated().reduce(initialState) { state, indexedEvent in
        let (index, value) = indexedEvent
        let event = SDScoringEvent(
          id: value.id,
          org_id: organizationId,
          game_id: gameId,
          game_version: command.expectedVersion + index + 1,
          sequence: command.expectedVersion + index + 1,
          event_type: value.type,
          actor_user_id: actorUserId,
          actor_device_id: deviceId,
          occurred_at: command.createdAt,
          payload: value.payload,
          ruleset_version: nil,
          idempotency_key: "native:\(command.id.uuidString.lowercased()):\(index)",
          correction_of_event_id: nil,
          supersedes_event_id: nil
        )
        return try SDGameReducer.apply(event, to: state, rules: rules)
      }
    }
  }

  mutating func enqueue(
    id: UUID = UUID(), events: [(SDScoringEventType, [String: SDJSONValue])], now: Date = Date()
  ) {
    guard !events.isEmpty, events.count <= 2,
          events.count != 2 || (events[0].0 == .pitchThrown
            && [.pitchResultRecorded, .ballPutInPlay].contains(events[1].0)) else {
      conflictReason = "This scoring action cannot be safely journaled."
      return
    }
    let expectedVersion = baseServerVersion + commands.reduce(0) { $0 + $1.events.count }
    commands.append(SDQueuedScoringCommand(
      id: id,
      expectedVersion: expectedVersion,
      events: events.map { SDQueuedScoringEvent(id: UUID(), type: $0.0, payload: $0.1) },
      createdAt: now
    ))
  }

  mutating func acknowledge(
    _ command: SDQueuedScoringCommand,
    with serverEvents: [SDScoringEvent],
    rules: SDResolvedBaseballRules
  ) throws {
    guard commands.first?.id == command.id,
          serverEvents.count == command.events.count else {
      throw SDGameScoringJournalError.serverHeadChanged
    }
    let projected = try serverEvents.reduce(baseState) { state, event in
      try SDGameReducer.apply(event, to: state, rules: rules)
    }
    guard zip(command.events, serverEvents).enumerated().allSatisfy({ indexed in
      let (index, pair) = indexed
      let (local, remote) = pair
      return local.id == remote.id && remote.actor_user_id == actorUserId
        && remote.actor_device_id == deviceId
        && remote.org_id == organizationId && remote.game_id == gameId
        && remote.game_version == command.expectedVersion + index + 1
        && remote.event_type == local.type && remote.payload == local.payload
        && remote.idempotency_key == "native:\(command.id.uuidString.lowercased()):\(index)"
    }) else {
      throw SDGameScoringJournalError.serverHeadChanged
    }
    baseState = projected
    baseServerVersion = projected.version
    commands.removeFirst()
  }

  mutating func reconcilePersistedCommands(
    against serverEvents: [SDScoringEvent],
    serverState: SDGameState,
    rules: SDResolvedBaseballRules
  ) throws {
    guard !hasConflict, serverState.version >= baseServerVersion else {
      throw SDGameScoringJournalError.serverHeadChanged
    }
    for command in commands {
      let matchingEvents = command.events.compactMap { queued in
        serverEvents.first(where: { $0.id == queued.id })
      }
      if matchingEvents.count == command.events.count {
        try acknowledge(command, with: matchingEvents, rules: rules)
      } else if !matchingEvents.isEmpty {
        throw SDGameScoringJournalError.serverHeadChanged
      } else {
        break
      }
    }
    if commands.isEmpty {
      baseState = serverState
      baseServerVersion = serverState.version
    } else if baseServerVersion != serverState.version {
      throw SDGameScoringJournalError.serverHeadChanged
    }
  }

  mutating func freeze(_ reason: String) { conflictReason = reason }
}

enum SDGameScoringJournalError: Error, Equatable {
  case serverHeadChanged
  case identityMismatch
  case persistenceFailed
}

struct SDGameScoringJournalStore: Sendable {
  let rootDirectory: URL

  static var applicationSupport: Self {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        .appendingPathComponent("Library/Application Support", isDirectory: true)
    return Self(rootDirectory: base.appendingPathComponent("HomePlate/ScoringJournal", isDirectory: true))
  }

  func load(organizationId: UUID, gameId: UUID, deviceId: UUID) throws -> SDGameScoringJournal? {
    let url = fileURL(organizationId: organizationId, gameId: gameId, deviceId: deviceId)
    guard FileManager.default.fileExists(atPath: url.path) else { return nil }
    do { return try JSONDecoder().decode(SDGameScoringJournal.self, from: Data(contentsOf: url)) }
    catch { throw SDGameScoringJournalError.persistenceFailed }
  }

  func save(_ journal: SDGameScoringJournal) throws {
    let url = fileURL(
      organizationId: journal.organizationId, gameId: journal.gameId, deviceId: journal.deviceId
    )
    do {
      try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true
      )
      let data = try JSONEncoder().encode(journal)
      try data.write(to: url, options: .atomic)
      #if os(iOS)
      try FileManager.default.setAttributes(
        [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
        ofItemAtPath: url.path
      )
      #endif
    } catch { throw SDGameScoringJournalError.persistenceFailed }
  }

  func remove(organizationId: UUID, gameId: UUID, deviceId: UUID) throws {
    let url = fileURL(organizationId: organizationId, gameId: gameId, deviceId: deviceId)
    do {
      if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    } catch { throw SDGameScoringJournalError.persistenceFailed }
  }

  private func fileURL(organizationId: UUID, gameId: UUID, deviceId: UUID) -> URL {
    rootDirectory
      .appendingPathComponent(organizationId.uuidString.lowercased(), isDirectory: true)
      .appendingPathComponent(deviceId.uuidString.lowercased(), isDirectory: true)
      .appendingPathComponent("\(gameId.uuidString.lowercased()).json")
  }
}
