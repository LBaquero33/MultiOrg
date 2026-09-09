import CryptoKit
import Foundation
import HomePlateScoringCore
import Testing
@testable import HomePlate

struct NativeScoringV2JournalTests {
  @Test @MainActor func authoritativeRejectionsPauseInsteadOfLookingOffline() {
    for category in [SDApplicationErrorCategory.unauthorized, .forbidden, .validation, .staleData, .malformedResponse] {
      #expect(ProductionScoringController.requiresReconciliation(SDServiceError(category: category, functionName: nil, statusCode: nil)))
    }
    #expect(!ProductionScoringController.requiresReconciliation(URLError(.notConnectedToInternet)))
    #expect(!ProductionScoringController.requiresReconciliation(URLError(.timedOut)))
  }
  @Test func durableCompoundPlaysAndAccountIsolation() throws {
    let seed = DemoGame.seed, key = P256.Signing.PrivateKey(), account = UUID(), device = UUID()
    let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let permit = HPNativeOfflinePermit(id: UUID(), token: "test-only", gameID: seed.id, deviceID: device, authorityEpoch: 4, packageVersion: 1,
      validFrom: formatter.string(from: Date().addingTimeInterval(-60)), validUntil: formatter.string(from: Date().addingTimeInterval(3600)))
    var journal = HPNativeScoringV2Journal(accountID: account, organizationID: seed.organizationID, gameID: seed.id, deviceID: device, seed: seed,
      packageHash: "test-package", privateKey: key.rawRepresentation, permit: permit, controlToken: "test-only", confirmedEvents: [])
    for command in [ScoringCommand.startGame, .recordPitch(.ball), .recordPitch(.calledStrike)] {
      let prior = try ScoringEngine.replay(seed: seed, rules: .nfhs, events: journal.events)
      let play = try ScoringEngine.makePlay(command: command, seed: seed, rules: .nfhs, events: journal.events, authorityEpoch: 4)
      let next = try ScoringEngine.replay(seed: seed, rules: .nfhs, events: journal.events + play.events)
      let snapshot = try StatisticsEngine.derive(seed: seed, rules: .nfhs, environment: .lab2026, events: journal.events + play.events)
      let envelope = ScoringPlayEnvelopeV2(play: play, gameID: seed.id, startingGameVersion: prior.version, authorityEpoch: 4, rulesVersion: 1, statisticsEnvironmentVersion: "test", projection: next, snapshot: snapshot)
      try journal.append(play: play, envelope: envelope, command: command, preconditions: prior)
    }
    #expect(journal.pendingCount == 3)
    let recovery = try journal.recoveryRecord()
    #expect(!recovery.contains("test-only"))
    #expect(!recovery.contains("privateKey"))
    #expect(!recovery.contains(key.rawRepresentation.base64EncodedString()))
    #expect(journal.entries[0].journal["priorCommandHash"] == .string("genesis"))
    #expect(journal.entries[1].journal["priorCommandHash"] == journal.entries[0].journal["commandHash"])
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = HPNativeScoringV2JournalStore(directory: directory)
    try store.save(journal)
    let restored = try #require(try store.load(account: account, org: seed.organizationID, game: seed.id, device: device))
    #expect(restored.events == journal.events)
    #expect(restored.entries.map(\.envelope) == journal.entries.map(\.envelope))
    #expect(try store.load(account: UUID(), org: seed.organizationID, game: seed.id, device: device) == nil)
    #expect(throws: HPNativeScoringV2Journal.JournalError.self) { try store.load(account: account, org: seed.organizationID, game: seed.id, device: UUID()) }
    let encoded = journal.entries[0].envelope
    guard case .object(let projection) = encoded["projection"], case .object = projection["bases"],
      case .object(let snapshot) = encoded["snapshot"] else { Issue.record("Shared transport must contain keyed objects"); return }
    #expect(snapshot["schemaVersion"] == .int(2))
    #expect(encoded["gameID"] == .string(seed.id.uuidString.lowercased()))
    #expect(encoded["projectionHash"] == .string(try HPNativeScoringCanonical.hash(projection)))
    #expect(encoded["statisticsHash"] == .string(try HPNativeScoringCanonical.hash(snapshot)))
    let fixture: [String: SDJSONValue] = ["publicKey": .object(HPNativeScoringV2Journal.publicKey(key)),
      "commands": .array(journal.entries.map { .object(["envelope": .object($0.envelope), "journal": .object($0.journal), "deviceProof": .object($0.deviceProof)]) })]
    print("NATIVE_V2_FIXTURE=" + (try HPNativeScoringV2Journal.encode(fixture)).base64EncodedString())
  }
}
