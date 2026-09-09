import Foundation

public typealias GameSeedV2 = GameSeed
public typealias ScoringCommandV2 = ScoringCommand
public typealias ScoringEventV2 = ScoringEvent
public typealias GameProjectionV2 = GameProjection
public typealias StatSnapshotV2 = StatSnapshot

public struct ScorekeeperAuthorityV2: Codable, Hashable, Sendable {
  public let deviceID: UUID
  public let epoch: Int
  public let serverVersion: Int
  public let leaseExpiresAt: Date?

  public init(deviceID: UUID, epoch: Int, serverVersion: Int, leaseExpiresAt: Date?) {
    self.deviceID = deviceID
    self.epoch = epoch
    self.serverVersion = serverVersion
    self.leaseExpiresAt = leaseExpiresAt
  }
}

public struct ScoringPlayEnvelopeV2: Identifiable, Encodable, Hashable, Sendable {
  public static let schemaVersion = 2

  public let id: UUID
  public let gameID: UUID
  public let commandID: UUID
  public let startingGameVersion: Int
  public let authorityEpoch: Int
  public let rulesVersion: Int
  public let statisticsEnvironmentVersion: String
  public let events: [ScoringEventV2]
  public let projection: GameProjectionV2
  public let snapshot: StatSnapshotV2
  public let projectionHash: String
  public let statisticsHash: String
  public let idempotencyKey: String

  public init(
    play: ScoringPlay,
    gameID: UUID,
    startingGameVersion: Int,
    authorityEpoch: Int,
    rulesVersion: Int,
    statisticsEnvironmentVersion: String,
    projection: GameProjectionV2,
    snapshot: StatSnapshotV2
  ) {
    id = play.id
    self.gameID = gameID
    commandID = play.commandID
    self.startingGameVersion = startingGameVersion
    self.authorityEpoch = authorityEpoch
    self.rulesVersion = rulesVersion
    self.statisticsEnvironmentVersion = statisticsEnvironmentVersion
    events = play.events
    self.projection = projection
    self.snapshot = snapshot
    projectionHash = (try? ScoringContractHasher.hash(projection)) ?? ""
    statisticsHash = (try? ScoringContractHasher.hash(snapshot)) ?? ""
    idempotencyKey = "\(gameID.uuidString.lowercased()):\(commandID.uuidString.lowercased())"
  }

  private enum CodingKeys: String, CodingKey {
    case schemaVersion, id, gameID, commandID, startingGameVersion, authorityEpoch
    case rulesVersion, statisticsEnvironmentVersion, events, projection, snapshot
    case projectionHash, statisticsHash, idempotencyKey
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(Self.schemaVersion, forKey: .schemaVersion)
    try container.encode(id, forKey: .id)
    try container.encode(gameID, forKey: .gameID)
    try container.encode(commandID, forKey: .commandID)
    try container.encode(startingGameVersion, forKey: .startingGameVersion)
    try container.encode(authorityEpoch, forKey: .authorityEpoch)
    try container.encode(rulesVersion, forKey: .rulesVersion)
    try container.encode(statisticsEnvironmentVersion, forKey: .statisticsEnvironmentVersion)
    try container.encode(events.map(ScoringEventTransportV2.init), forKey: .events)
    try container.encode(projection, forKey: .projection)
    try container.encode(snapshot, forKey: .snapshot)
    try container.encode(projectionHash, forKey: .projectionHash)
    try container.encode(statisticsHash, forKey: .statisticsHash)
    try container.encode(idempotencyKey, forKey: .idempotencyKey)
  }
}

private struct ScoringEventTransportV2: Encodable {
  let event: ScoringEvent
  init(_ event: ScoringEvent) { self.event = event }

  private enum CodingKeys: String, CodingKey {
    case id, gameID, playID, commandID, authorityEpoch, sequence, occurredAt, rulesVersion, payload
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(event.id, forKey: .id)
    try container.encode(event.gameID, forKey: .gameID)
    try container.encode(event.playID, forKey: .playID)
    try container.encode(event.commandID, forKey: .commandID)
    try container.encode(event.authorityEpoch, forKey: .authorityEpoch)
    try container.encode(event.sequence, forKey: .sequence)
    try container.encode(ISO8601DateFormatter().string(from: event.occurredAt), forKey: .occurredAt)
    try container.encode(event.rulesVersion, forKey: .rulesVersion)
    try container.encode(ScoringPayloadTransportV2(event.payload), forKey: .payload)
  }
}

private struct ScoringPayloadTransportV2: Encodable {
  let payload: ScoringEventPayload
  init(_ payload: ScoringEventPayload) { self.payload = payload }

  private enum Keys: String, CodingKey {
    case type, offense, batterID, pitcherID, result, isFirstPitch, contact
    case fielderSequence, runsBattedIn, errorFielderID, note, resolution
    case half, inning, reason, playID, details
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: Keys.self)
    switch payload {
    case .gameStarted:
      try container.encode("game_started", forKey: .type)
    case .pitch(let value):
      try container.encode("pitch", forKey: .type)
      try container.encode(value.offense, forKey: .offense)
      try container.encode(value.batterID, forKey: .batterID)
      try container.encode(value.pitcherID, forKey: .pitcherID)
      try container.encode(value.result, forKey: .result)
      try container.encode(value.isFirstPitch, forKey: .isFirstPitch)
    case .plateAppearance(let value):
      try container.encode("plate_appearance", forKey: .type)
      try container.encode(value.offense, forKey: .offense)
      try container.encode(value.batterID, forKey: .batterID)
      try container.encode(value.pitcherID, forKey: .pitcherID)
      try container.encode(value.result, forKey: .result)
      try container.encodeIfPresent(value.contact, forKey: .contact)
      try container.encode(value.fielderSequence, forKey: .fielderSequence)
      try container.encode(value.runsBattedIn, forKey: .runsBattedIn)
      try container.encodeIfPresent(value.errorFielderID, forKey: .errorFielderID)
      try container.encode(value.note, forKey: .note)
    case .runner(let value):
      try container.encode("runner", forKey: .type)
      try container.encode(value.offense, forKey: .offense)
      try container.encode(value.resolution, forKey: .resolution)
    case .halfInningEnded(let half, let inning, let reason):
      try container.encode("half_inning_ended", forKey: .type)
      try container.encode(half, forKey: .half)
      try container.encode(inning, forKey: .inning)
      try container.encode(reason, forKey: .reason)
    case .gameEnded(let reason):
      try container.encode("game_ended", forKey: .type)
      try container.encode(reason, forKey: .reason)
    case .playVoided(let playID, let reason):
      try container.encode("play_voided", forKey: .type)
      try container.encode(playID, forKey: .playID)
      try container.encode(reason, forKey: .reason)
    case .playRestored(let playID):
      try container.encode("play_restored", forKey: .type)
      try container.encode(playID, forKey: .playID)
    case .substitution(let value):
      try container.encode("substitution", forKey: .type)
      try container.encode(value, forKey: .details)
    case .overrideApplied(let value):
      try container.encode("override_applied", forKey: .type)
      try container.encode(value, forKey: .details)
    }
  }
}

public enum ScoringContractHasher {
  public static func hash<T: Encodable>(_ value: T) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(value)
    var hash: UInt64 = 14_695_981_039_346_656_037
    for byte in data {
      hash ^= UInt64(byte)
      hash &*= 1_099_511_628_211
    }
    return String(hash, radix: 16).leftPadding(toLength: 16, withPad: "0")
  }
}

private extension String {
  func leftPadding(toLength: Int, withPad character: Character) -> String {
    guard count < toLength else { return self }
    return String(repeating: String(character), count: toLength - count) + self
  }
}
