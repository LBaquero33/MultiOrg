import CryptoKit
import Foundation
import HomePlateScoringCore

struct HPNativeOfflinePermit: Codable, Sendable {
  let id: UUID; let token: String; let gameID: UUID; let deviceID: UUID
  let authorityEpoch: Int; let packageVersion: Int; let validFrom: String; let validUntil: String
  var isCurrent: Bool {
    let parser = ISO8601DateFormatter(); parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    guard let start = parser.date(from: validFrom), let end = parser.date(from: validUntil) else { return false }
    return start <= Date() && end > Date()
  }
}

struct HPNativeScoringV2Journal: Codable {
  struct Entry: Codable {
    let play: ScoringPlay
    let envelope: [String: SDJSONValue]
    let journal: [String: SDJSONValue]
    let deviceProof: [String: SDJSONValue]
    var accepted = false
  }
  let accountID: UUID
  let organizationID: UUID
  let gameID: UUID
  let deviceID: UUID
  let seed: GameSeed
  let packageHash: String
  let privateKey: Data
  let permit: HPNativeOfflinePermit
  let controlToken: String
  var rules: GameRulesProfile? = nil
  var confirmedEvents: [ScoringEvent]
  var entries: [Entry] = []

  var events: [ScoringEvent] { confirmedEvents + entries.flatMap(\.play.events) }
  var pendingCount: Int { entries.filter { !$0.accepted }.count }
  var canAppend: Bool { permit.isCurrent }

  /// Support export excludes the signing key, permit token and control token.
  func recoveryRecord() throws -> String {
    let value: [String: SDJSONValue] = ["gameID": .string(gameID.uuidString.lowercased()),
      "organizationID": .string(organizationID.uuidString.lowercased()),
      "pendingCommands": .array(entries.filter { !$0.accepted }.map {
        .object(["envelope": .object($0.envelope), "journal": .object($0.journal), "deviceProof": .object($0.deviceProof)])
      })]
    return String(decoding: try Self.encode(value), as: UTF8.self)
  }

  mutating func append(play: ScoringPlay, envelope: ScoringPlayEnvelopeV2, command: ScoringCommand, preconditions: GameProjection) throws {
    guard canAppend, play.events.allSatisfy({ $0.gameID == gameID && $0.authorityEpoch == permit.authorityEpoch }),
          play.events.first?.sequence == (events.last?.sequence ?? 0) + 1 else { throw JournalError.contextChanged }
    var encoded = try Self.object(envelope)
    // Swift's enum-keyed dictionaries encode as alternating arrays. The shared
    // web/SQL contract uses keyed objects; normalize before hashing/signing.
    var projection = try Self.object(envelope.projection)
    projection["battingIndexes"] = .object(Dictionary(uniqueKeysWithValues: envelope.projection.battingIndexes.map { ($0.key.rawValue, .int($0.value)) }))
    projection["bases"] = .object(try Dictionary(uniqueKeysWithValues: envelope.projection.bases.map { (String($0.key.rawValue), .object(try Self.object($0.value))) }))
    projection["inningRuns"] = .object(Dictionary(uniqueKeysWithValues: envelope.projection.inningRuns.map { ($0.key.rawValue, .array($0.value.map(SDJSONValue.int))) }))
    projection["lineups"] = .object(try Dictionary(uniqueKeysWithValues: envelope.projection.lineups.map { side, rows in
      (side.rawValue, .array(try rows.map { row in var value = try Self.object(row); value["active"] = .bool(row.exitedAtSequence == nil); return .object(value) }))
    }))
    var snapshot = try Self.object(envelope.snapshot)
    snapshot["schemaVersion"] = .int(2)
    snapshot["batting"] = .array(try envelope.snapshot.batting.map { line in
      var value = try Self.object(line); value["pa"] = .int(line.plateAppearances); value["ab"] = .int(line.atBats)
      value["rbi"] = .int(line.runsBattedIn); value["hits"] = .int(line.hits); return .object(value)
    })
    encoded["projection"] = .object(projection); encoded["snapshot"] = .object(snapshot)
    encoded["projectionHash"] = .string(try HPNativeScoringCanonical.hash(projection))
    encoded["statisticsHash"] = .string(try HPNativeScoringCanonical.hash(snapshot))
    let sequence = entries.count + 1
    let priorHash = entries.last?.journal["commandHash"]?.stringValue ?? "genesis"
    let fields: [String: SDJSONValue] = ["gameID": .string(gameID.uuidString.lowercased()), "localSequence": .int(sequence),
      "commandID": .string(play.commandID.uuidString.lowercased()), "command": .object(try Self.object(command)),
      "preconditions": .object(try Self.object(preconditions)), "priorCommandHash": .string(priorHash)]
    let commandHash = try HPNativeScoringCanonical.hash(fields)
    let envelopeHash = try HPNativeScoringCanonical.hash(encoded)
    let proof: [String: SDJSONValue] = ["commandHash": .string(commandHash), "envelopeHash": .string(envelopeHash)]
    let signature = try P256.Signing.PrivateKey(rawRepresentation: privateKey).signature(for: Self.encode(proof))
    var journal = fields; journal["commandHash"] = .string(commandHash)
    var signed = proof; signed["signature"] = .string(Self.base64URL(signature.rawRepresentation))
    entries.append(.init(play: play, envelope: encoded, journal: journal, deviceProof: signed))
  }

  static func object<T: Encodable>(_ value: T) throws -> [String: SDJSONValue] {
    let raw = try JSONDecoder().decode([String: SDJSONValue].self, from: encode(value))
    return raw.mapValues(normalize)
  }
  private static func normalize(_ value: SDJSONValue) -> SDJSONValue {
    switch value {
    case .string(let string): return .string(UUID(uuidString: string)?.uuidString.lowercased() ?? string)
    case .array(let rows): return .array(rows.map(normalize))
    case .object(let values): return .object(values.mapValues(normalize))
    default: return value
    }
  }
  static func encode<T: Encodable>(_ value: T) throws -> Data {
    let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]; encoder.dateEncodingStrategy = .iso8601
    return try encoder.encode(value)
  }
  static func base64URL(_ data: Data) -> String { data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") }
  static func publicKey(_ key: P256.Signing.PrivateKey) -> [String: SDJSONValue] {
    let bytes = key.publicKey.x963Representation
    return ["kty": .string("EC"), "crv": .string("P-256"), "x": .string(base64URL(bytes.subdata(in: 1..<33))), "y": .string(base64URL(bytes.subdata(in: 33..<65))), "ext": .bool(true)]
  }
  enum JournalError: Error { case contextChanged, invalidReceipt }
}

enum HPNativeScoringCanonical {
  static func hash(_ value: [String: SDJSONValue]) throws -> String {
    let json = try canonical(.object(value))
    var hash: UInt64 = 0xcbf29ce484222325
    for byte in json.utf8 { hash = (hash ^ UInt64(byte)) &* 0x100000001b3 }
    return String(format: "%016llx", hash)
  }
  private static func canonical(_ value: SDJSONValue) throws -> String {
    switch value {
    case .object(let entries):
      let keys = entries.keys.sorted { left, right in
        // JSON.stringify emits integer keys first. Other shared-contract keys
        // use the case-insensitive primary collation of JS localeCompare.
        if let a = UInt32(left), String(a) == left, a < UInt32.max {
          if let b = UInt32(right), String(b) == right, b < UInt32.max { return a < b }
          return true
        }
        if let b = UInt32(right), String(b) == right, b < UInt32.max { return false }
        return left.compare(right, options: [], locale: Locale(identifier: "en_US")) == .orderedAscending
      }
      return "{" + (try keys.map { try canonical(.string($0)) + ":" + canonical(entries[$0]!) }).joined(separator: ",") + "}"
    case .array(let entries): return "[" + (try entries.map(canonical)).joined(separator: ",") + "]"
    default:
      return String(decoding: try HPNativeScoringV2Journal.encode(value), as: UTF8.self)
    }
  }
}

struct HPNativeScoringV2JournalStore {
  let directory: URL
  static var application: Self { .init(directory: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("HomePlate/ScoringV2")) }
  func url(account: UUID, org: UUID, game: UUID) -> URL { directory.appendingPathComponent("\(account)-\(org)-\(game).json") }
  func load(account: UUID, org: UUID, game: UUID, device: UUID) throws -> HPNativeScoringV2Journal? {
    let path = url(account: account, org: org, game: game)
    guard FileManager.default.fileExists(atPath: path.path) else { return nil }
    let value = try JSONDecoder().decode(HPNativeScoringV2Journal.self, from: Data(contentsOf: path))
    guard value.accountID == account, value.organizationID == org, value.gameID == game, value.deviceID == device else { throw HPNativeScoringV2Journal.JournalError.contextChanged }
    return value
  }
  func save(_ journal: HPNativeScoringV2Journal) throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    let path = url(account: journal.accountID, org: journal.organizationID, game: journal.gameID)
    try JSONEncoder().encode(journal).write(to: path, options: .atomic)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path.path)
  }
}

extension SupabaseService {
  struct NativeOfflinePreparation: Decodable {
    struct Authority: Decodable { let controlToken: String; let epoch: Int; let serverVersion: Int }
    let permit: HPNativeOfflinePermit; let authority: Authority
  }
  func prepareNativeOffline(gameID: UUID, deviceID: UUID, packageHash: String, publicKey: [String: SDJSONValue]) async throws -> NativeOfflinePreparation {
    try await invokeAuthenticatedFunction("game-scoring-v2", body: [
      "action": SDJSONValue.string("prepare_offline"), "gameID": .string(gameID.uuidString.lowercased()), "deviceID": .string(deviceID.uuidString.lowercased()),
      "packageHash": .string(packageHash), "packageVersion": .int(1), "publicKey": .object(publicKey),
    ])
  }
  struct NativeOfflineResponse: Decodable {
    struct Receipt: Decodable { let acceptedCommandIDs: [UUID]; let acceptedPlayIDs: [UUID]; let recoveryState: String; let serverVersion: Int }
    let ok: Bool; let receipt: Receipt
  }
  func syncNativeOffline(_ journal: HPNativeScoringV2Journal, entry: HPNativeScoringV2Journal.Entry) async throws -> NativeOfflineResponse {
    try await invokeAuthenticatedFunction("game-scoring-v2", body: [
      "action": SDJSONValue.string("sync_batch"), "batchID": .string(UUID().uuidString),
      "gameID": .string(journal.gameID.uuidString.lowercased()), "deviceID": .string(journal.deviceID.uuidString.lowercased()),
      "permitID": .string(journal.permit.id.uuidString.lowercased()), "permitToken": .string(journal.permit.token),
      "controlToken": .string(journal.controlToken), "packageHash": .string(journal.packageHash),
      "commands": .array([.object(["envelope": .object(entry.envelope), "journal": .object(entry.journal), "deviceProof": .object(entry.deviceProof)])]),
    ])
  }
}
