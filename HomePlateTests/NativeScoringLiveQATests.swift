import CryptoKit
import Foundation
import HomePlateScoringCore
import XCTest
import AVFoundation
import Supabase
@testable import HomePlate

@MainActor final class NativeScoringLiveQATests: XCTestCase {
  func testLiveTrainingWorkspaceDecodes() async throws {
    let env = ProcessInfo.processInfo.environment
    guard let access = env["HOMEPLATE_QA_ACCESS_TOKEN"], let refresh = env["HOMEPLATE_QA_REFRESH_TOKEN"] else { throw XCTSkip("Guarded QA session required") }
    let service = SupabaseService(config: try SupabaseConfig.fromInfoPlist().get(), authStorage: QAAuthMemoryStorage())
    _ = try await service.client.auth.setSession(accessToken: access, refreshToken: refresh)
    let workspace = try await service.trainingWorkspace(organizationId: UUID(uuidString: "00000000-0000-4000-8000-0000000000aa")!)
    XCTAssertFalse(workspace.athletes.isEmpty)
    XCTAssertFalse(workspace.appointments.isEmpty)
  }
  func testChatFileVideoUploadFailureRetryAndPlayback() async throws {
    let env = ProcessInfo.processInfo.environment
    guard let access = env["HOMEPLATE_QA_ACCESS_TOKEN"], let refresh = env["HOMEPLATE_QA_REFRESH_TOKEN"],
          let channel = env["HOMEPLATE_QA_CHANNEL_ID"].flatMap(UUID.init(uuidString:)),
          let encoded = env["HOMEPLATE_QA_VIDEO_BASE64"], let video = Data(base64Encoded: encoded) else {
      throw XCTSkip("Requires guarded synthetic media and private QA channel")
    }
    let org = UUID(uuidString: "00000000-0000-4000-8000-0000000000aa")!
    let config = try SupabaseConfig.fromInfoPlist().get()
    XCTAssertEqual(config.url.host, "kbulbvngysflfhaqpvtv.supabase.co")
    let transport = URLSessionConfiguration.ephemeral
    transport.protocolClasses = [QAOfflineTransport.self]
    let service = SupabaseService(config: config, session: URLSession(configuration: transport), authStorage: QAAuthMemoryStorage())
    _ = try await service.client.auth.setSession(accessToken: access, refreshToken: refresh)
    let qaChannel = try await service.chatChannel(channelId: channel, organizationId: org)
    XCTAssertEqual(qaChannel.org_id, org)
    defer { QAOfflineTransport.state.set(false) }
    for (original, mime, bytes) in [("QA original.txt", "text/plain", Data("Synthetic Home Plate iPhone upload verification".utf8)), ("QA original.mp4", "video/mp4", video)] {
      let name = try HPUploadNaming.filename(original: original, stem: "QA Renamed iPhone \(UUID().uuidString.prefix(8))")
      let upload = UUID(), message = UUID()
      QAOfflineTransport.state.set(true)
      do { _ = try await service.uploadChatAttachment(bytes, organizationId: org, channelId: channel, fileName: name, contentType: mime, uploadId: upload, originalFilename: original); XCTFail("Offline upload unexpectedly succeeded") } catch {}
      QAOfflineTransport.state.set(false)
      let path = try await service.uploadChatAttachment(bytes, organizationId: org, channelId: channel, fileName: name, contentType: mime, uploadId: upload, originalFilename: original)
      let duplicate = try await service.uploadChatAttachment(bytes, organizationId: org, channelId: channel, fileName: name, contentType: mime, uploadId: upload, originalFilename: original)
      XCTAssertEqual(path, duplicate)
      let sent = try await service.sendChatMessage(channelId: channel, body: "[QA] \(name)", clientMessageId: message)
      let replay = try await service.sendChatMessage(channelId: channel, body: "[QA] \(name)", clientMessageId: message)
      XCTAssertEqual(sent.message.id, replay.message.id)
      let attached = try await service.createChatAttachment(messageId: sent.message.id, storagePath: path, fileName: name, mimeType: mime, byteSize: bytes.count, isImage: false)
      let rows = try await service.listChatAttachments(messageIds: [sent.message.id])
      XCTAssertEqual(rows.count, 1); XCTAssertEqual(rows.first?.id, attached.id)
      XCTAssertEqual(rows.first?.file_name, name)
      let url = try await service.signedChatAttachmentURL(path: path)
      let (downloaded, response) = try await URLSession.shared.data(from: url)
      XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
      XCTAssertEqual(SHA256.hash(data: downloaded), SHA256.hash(data: bytes))
      if mime == "video/mp4" {
        let asset = AVURLAsset(url: url)
        let playable = try await asset.load(.isPlayable)
        let duration = try await asset.load(.duration)
        XCTAssertTrue(playable); XCTAssertGreaterThan(duration.seconds, 0)
      }
    }
  }
  func testSavedJournalSurvivesTransportFailureAndReconnect() async throws {
    let env = ProcessInfo.processInfo.environment
    guard let path = env["HOMEPLATE_QA_RESUME_JOURNAL"],
      let access = env["HOMEPLATE_QA_ACCESS_TOKEN"], let refresh = env["HOMEPLATE_QA_REFRESH_TOKEN"] else {
      throw XCTSkip("Requires guarded QA journal and ephemeral session")
    }
    let journal = try JSONDecoder().decode(HPNativeScoringV2Journal.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
    XCTAssertEqual(journal.organizationID.uuidString.lowercased(), "00000000-0000-4000-8000-0000000000aa")
    XCTAssertEqual(journal.gameID.uuidString.lowercased(), env["HOMEPLATE_QA_GAME_ID"])
    let config = try SupabaseConfig.fromInfoPlist().get()
    XCTAssertEqual(config.url.host, "kbulbvngysflfhaqpvtv.supabase.co")
    let transport = URLSessionConfiguration.ephemeral
    transport.protocolClasses = [QAOfflineTransport.self]
    let service = SupabaseService(config: config, session: URLSession(configuration: transport), authStorage: QAAuthMemoryStorage())
    let session = try await service.client.auth.setSession(accessToken: access, refreshToken: refresh)
    XCTAssertEqual(session.user.id, journal.accountID)
    defer { QAOfflineTransport.state.set(false) }
    let entry = try XCTUnwrap(journal.entries.last)
    QAOfflineTransport.state.set(true)
    do { _ = try await service.syncNativeOffline(journal, entry: entry); XCTFail("Network failure was not injected") }
    catch { XCTAssertFalse(ProductionScoringController.requiresReconciliation(error)) }
    let restored = try JSONDecoder().decode(HPNativeScoringV2Journal.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
    XCTAssertEqual(restored.events, journal.events)
    XCTAssertEqual(restored.pendingCount, journal.pendingCount)
    QAOfflineTransport.state.set(false)
    let receipt = try await service.syncNativeOffline(restored, entry: entry)
    XCTAssertEqual(receipt.receipt.acceptedCommandIDs, [entry.play.commandID])
    let remote = try await service.listScoringEventsV2(gameId: journal.gameID, organizationId: journal.organizationID)
    XCTAssertEqual(remote.map(\.id), journal.events.map(\.id))
    XCTAssertEqual(journal.entries.count, 132)
    let final = try ScoringEngine.replay(seed: journal.seed, rules: .nfhs, events: remote)
    XCTAssertEqual(final.inning, 8)
    XCTAssertEqual(final.awayScore, 2)
    XCTAssertEqual(final.homeScore, 0)
    XCTAssertEqual(final.awayHits, 1)
  }
  func testSignedOfflineCommandsReachAuthoritativeQALedger() async throws {
    let env = ProcessInfo.processInfo.environment
    guard let access = env["HOMEPLATE_QA_ACCESS_TOKEN"], let refresh = env["HOMEPLATE_QA_REFRESH_TOKEN"],
          let gameID = env["HOMEPLATE_QA_GAME_ID"].flatMap(UUID.init(uuidString:)) else {
      throw XCTSkip("Requires an explicitly provisioned guarded QA game and ephemeral QA session.")
    }
    let orgID = UUID(uuidString: "00000000-0000-4000-8000-0000000000aa")!
    let config = try SupabaseConfig.fromInfoPlist().get()
    XCTAssertEqual(config.url.host, "kbulbvngysflfhaqpvtv.supabase.co")
    let transport = URLSessionConfiguration.ephemeral
    transport.protocolClasses = [QAOfflineTransport.self]
    let service = SupabaseService(config: config, session: URLSession(configuration: transport), authStorage: QAAuthMemoryStorage())
    defer { QAOfflineTransport.state.set(false) }
    let session = try await service.client.auth.setSession(accessToken: access, refreshToken: refresh)
    let game: SDGame = try await service.client.from("sd_games").select().eq("id", value: gameID).eq("org_id", value: orgID).single().execute().value
    XCTAssertEqual(game.org_id, orgID); XCTAssertEqual(game.scoring_schema_version, 2)
    guard game.game_version == 0 else { throw XCTSkip("Canary already contains plays; provision a new QA game.") }
    let lineup = try await service.nativeSavedLineup(gameID: gameID)
    XCTAssertFalse(lineup.isEmpty)
    let profiles = try await service.scoringProfilesV2(userIds: lineup.map(\.player_id))
    let seed = ProductionGameSeedAdapter.makeSeed(game: game, participants: [], profiles: profiles, savedLineup: lineup)
    let key = P256.Signing.PrivateKey(), device = UUID()
    let prepared = try await service.prepareNativeOffline(gameID: gameID, deviceID: device, packageHash: "native-qa-contract-v1", publicKey: HPNativeScoringV2Journal.publicKey(key))
    var journal = HPNativeScoringV2Journal(accountID: session.user.id, organizationID: orgID, gameID: gameID, deviceID: device, seed: seed,
      packageHash: "native-qa-contract-v1", privateKey: key.rawRepresentation, permit: prepared.permit, controlToken: prepared.authority.controlToken, confirmedEvents: [])
    // Complete seven innings locally, rebuilding the durable store after every
    // command. No scoring upload occurs until the entire offline game is saved.
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let commands: [ScoringCommand] = [.startGame, .recordPitch(.ball), .recordPitch(.ball), .recordPitch(.ball), .recordPitch(.ball),
      .recordBallInPlay(.init(contact: .flyBall, result: .homeRun)),
      ] + Array(repeating: [ScoringCommand.recordPitch(.calledStrike), .recordPitch(.calledStrike), .recordPitch(.swingingStrike)], count: 42).flatMap { $0 }
    for command in commands {
      try autoreleasepool {
      let prior = try ScoringEngine.replay(seed: seed, rules: .nfhs, events: journal.events)
      let play = try ScoringEngine.makePlay(command: command, seed: seed, rules: .nfhs, events: journal.events, authorityEpoch: prepared.permit.authorityEpoch)
      let next = try ScoringEngine.replay(seed: seed, rules: .nfhs, events: journal.events + play.events)
      let stats = try StatisticsEngine.derive(seed: seed, rules: .nfhs, environment: ProductionGameSeedAdapter.statisticsEnvironment, events: journal.events + play.events)
      try journal.append(play: play, envelope: .init(play: play, gameID: gameID, startingGameVersion: prior.version, authorityEpoch: prepared.permit.authorityEpoch,
        rulesVersion: 1, statisticsEnvironmentVersion: "native-qa", projection: next, snapshot: stats), command: command, preconditions: prior)
      try HPNativeScoringV2JournalStore(directory: directory).save(journal)
      journal = try XCTUnwrap(HPNativeScoringV2JournalStore(directory: directory).load(account: session.user.id, org: orgID, game: gameID, device: device))
      }
    }
    let pendingBeforeDisconnect = journal.pendingCount
    QAOfflineTransport.state.set(true)
    do {
      _ = try await service.syncNativeOffline(journal, entry: XCTUnwrap(journal.entries.first))
      XCTFail("Disconnected transport must not accept a play")
    } catch {
      XCTAssertFalse(ProductionScoringController.requiresReconciliation(error))
    }
    journal = try XCTUnwrap(HPNativeScoringV2JournalStore(directory: directory).load(account: session.user.id, org: orgID, game: gameID, device: device))
    XCTAssertEqual(journal.pendingCount, pendingBeforeDisconnect)
    QAOfflineTransport.state.set(false)
    for entry in journal.entries {
      let receipt = try await service.syncNativeOffline(journal, entry: entry)
      XCTAssertEqual(receipt.receipt.recoveryState, "synced")
      XCTAssertEqual(receipt.receipt.acceptedPlayIDs, [entry.play.id])
      XCTAssertEqual(receipt.receipt.acceptedCommandIDs, [entry.play.commandID])
      let duplicate = try await service.syncNativeOffline(journal, entry: entry)
      XCTAssertEqual(duplicate.receipt.acceptedCommandIDs, [entry.play.commandID])
    }
    let remote = try await service.listScoringEventsV2(gameId: gameID, organizationId: orgID)
    XCTAssertEqual(remote.map(\.id), journal.events.map(\.id))
    let final = try ScoringEngine.replay(seed: seed, rules: .nfhs, events: remote)
    XCTAssertEqual(final.balls, 0)
    XCTAssertEqual(final.strikes, 0)
    XCTAssertEqual(final.inning, 8)
    XCTAssertEqual(final.awayHits, 1)
    XCTAssertEqual(final.awayScore, 2)
  }
}

// Scope the network failure to this test's own URLSession, never the Mac,
// other Simulators, or the user's app session.
private final class QAAuthMemoryStorage: AuthLocalStorage, @unchecked Sendable {
  private let lock = NSLock()
  private var values: [String: Data] = [:]
  func store(key: String, value: Data) throws { lock.lock(); defer { lock.unlock() }; values[key] = value }
  func retrieve(key: String) throws -> Data? { lock.lock(); defer { lock.unlock() }; return values[key] }
  func remove(key: String) throws { lock.lock(); defer { lock.unlock() }; values.removeValue(forKey: key) }
}

private final class QAOfflineTransport: URLProtocol, @unchecked Sendable {
  final class State: @unchecked Sendable {
    private let lock = NSLock()
    private var disconnected = false
    func set(_ value: Bool) { lock.lock(); defer { lock.unlock() }; disconnected = value }
    func get() -> Bool { lock.lock(); defer { lock.unlock() }; return disconnected }
  }
  static let state = State()
  override class func canInit(with request: URLRequest) -> Bool {
    state.get() && request.url?.host == "kbulbvngysflfhaqpvtv.supabase.co"
  }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() { client?.urlProtocol(self, didFailWithError: URLError(.networkConnectionLost)) }
  override func stopLoading() {}
}
