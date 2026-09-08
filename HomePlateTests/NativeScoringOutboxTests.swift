import XCTest
@testable import HomePlate

final class NativeScoringOutboxTests: XCTestCase {
  func testTerminationRecoveryAndAccountIsolation() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let account = UUID(), org = UUID(), game = UUID()
    let command = SDNativeScoringCommand(id: UUID(), accountId: account, organizationId: org,
      gameId: game, canonicalEventId: UUID(), deviceId: UUID(), expectedVersion: 7, createdAt: Date(),
      events: [.init(id: UUID(), event_type: .pitchThrown, payload: [:]),
        .init(id: UUID(), event_type: .pitchResultRecorded, payload: ["result": .string("ball")])])
    try SDNativeScoringOutbox(directory: directory).save([command], account: account, org: org, game: game)
    let restarted = SDNativeScoringOutbox(directory: directory)
    XCTAssertEqual(try restarted.load(account: account, org: org, game: game), [command])
    XCTAssertEqual(try restarted.load(account: UUID(), org: org, game: game), [])
    XCTAssertThrowsError(try restarted.save([command], account: UUID(), org: org, game: game))
    try restarted.save([], account: account, org: org, game: game)
    XCTAssertEqual(try restarted.load(account: account, org: org, game: game), [])
  }
  func testCorruptJournalFailsClosed() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let account=UUID(), org=UUID(), game=UUID()
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try Data("corrupt".utf8).write(to: directory.appendingPathComponent("\(account)-\(org)-\(game).json"))
    XCTAssertThrowsError(try SDNativeScoringOutbox(directory: directory).load(account: account, org: org, game: game))
  }
}
