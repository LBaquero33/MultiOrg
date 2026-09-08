import Foundation

struct SDNativeScoringCommand: Codable, Equatable, Identifiable, Sendable {
  struct Event: Codable, Equatable, Sendable {
    let id: UUID
    let event_type: SDScoringEventType
    let payload: [String: SDJSONValue]
  }
  let id: UUID
  let accountId: UUID
  let organizationId: UUID
  let gameId: UUID
  let canonicalEventId: UUID
  let deviceId: UUID
  let expectedVersion: Int
  let createdAt: Date
  let events: [Event]
}

/// Persist before sending. Unknown responses retain the exact command identity;
/// a new lease never silently rebases or transfers another account's commands.
struct SDNativeScoringOutbox {
  let directory: URL
  static var application: Self {
    Self(directory: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("HomePlate/ScoringOutbox", isDirectory: true))
  }
  private func url(account: UUID, org: UUID, game: UUID) -> URL {
    directory.appendingPathComponent("\(account)-\(org)-\(game).json")
  }
  func load(account: UUID, org: UUID, game: UUID) throws -> [SDNativeScoringCommand] {
    let path = url(account: account, org: org, game: game)
    guard FileManager.default.fileExists(atPath: path.path) else { return [] }
    let commands = try JSONDecoder().decode([SDNativeScoringCommand].self, from: Data(contentsOf: path))
    guard commands.allSatisfy({ $0.accountId == account && $0.organizationId == org && $0.gameId == game }) else {
      throw CocoaError(.fileReadCorruptFile)
    }
    return commands
  }
  func save(_ commands: [SDNativeScoringCommand], account: UUID, org: UUID, game: UUID) throws {
    guard commands.allSatisfy({ $0.accountId == account && $0.organizationId == org && $0.gameId == game }) else {
      throw CocoaError(.fileWriteInvalidFileName)
    }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try JSONEncoder().encode(commands).write(to: url(account: account, org: org, game: game), options: .atomic)
  }
}
