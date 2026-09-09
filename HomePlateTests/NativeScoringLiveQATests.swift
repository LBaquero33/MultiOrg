import CryptoKit
import Foundation
import HomePlateScoringCore
import XCTest
@testable import HomePlate

@MainActor final class NativeScoringLiveQATests: XCTestCase {
  func testSignedOfflineCommandsReachAuthoritativeQALedger() async throws {
    let env = ProcessInfo.processInfo.environment
    guard let access = env["HOMEPLATE_QA_ACCESS_TOKEN"], let refresh = env["HOMEPLATE_QA_REFRESH_TOKEN"],
          let gameID = env["HOMEPLATE_QA_GAME_ID"].flatMap(UUID.init(uuidString:)) else {
      throw XCTSkip("Requires an explicitly provisioned guarded QA game and ephemeral QA session.")
    }
    let orgID = UUID(uuidString: "00000000-0000-4000-8000-0000000000aa")!
    let config = try SupabaseConfig.fromInfoPlist().get()
    XCTAssertEqual(config.url.host, "kbulbvngysflfhaqpvtv.supabase.co")
    let service = SupabaseService(config: config)
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
    // A walk, hit and strikeout are generated locally before synchronization.
    let commands: [ScoringCommand] = [.startGame, .recordPitch(.ball), .recordPitch(.ball), .recordPitch(.ball), .recordPitch(.ball),
      .recordBallInPlay(.init(contact: .flyBall, result: .homeRun)),
      .recordPitch(.calledStrike), .recordPitch(.calledStrike), .recordPitch(.swingingStrike)]
    for command in commands {
      let prior = try ScoringEngine.replay(seed: seed, rules: .nfhs, events: journal.events)
      let play = try ScoringEngine.makePlay(command: command, seed: seed, rules: .nfhs, events: journal.events, authorityEpoch: prepared.permit.authorityEpoch)
      let next = try ScoringEngine.replay(seed: seed, rules: .nfhs, events: journal.events + play.events)
      let stats = try StatisticsEngine.derive(seed: seed, rules: .nfhs, environment: ProductionGameSeedAdapter.statisticsEnvironment, events: journal.events + play.events)
      try journal.append(play: play, envelope: .init(play: play, gameID: gameID, startingGameVersion: prior.version, authorityEpoch: prepared.permit.authorityEpoch,
        rulesVersion: 1, statisticsEnvironmentVersion: "native-qa", projection: next, snapshot: stats), command: command, preconditions: prior)
    }
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
    XCTAssertEqual(final.outs, 1)
    XCTAssertEqual(final.awayHits, 1)
    XCTAssertEqual(final.awayScore, 2)
  }
}
