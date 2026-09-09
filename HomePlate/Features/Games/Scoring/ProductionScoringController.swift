import Combine
import CryptoKit
import Foundation
import HomePlateScoringCore
import HomePlateScoringUI

@MainActor final class ProductionScoringController: ObservableObject {
  @Published private(set) var seed: GameSeed
  @Published private(set) var projection: GameProjection
  @Published private(set) var snapshot: StatSnapshot?
  @Published private(set) var events: [ScoringEvent] = []
  @Published private(set) var authority: ScorekeeperAuthorityV2?
  @Published private(set) var syncState: LabSyncState = .starting
  @Published private(set) var isReady = false
  @Published private(set) var isBusy = false
  @Published var toastText: String?
  @Published var errorText: String?
  @Published private(set) var pendingHalfInning: String?
  let game: SDGame
  let participants: [SDEventParticipant]
  let canScore: Bool
  private(set) var rules: GameRulesProfile
  let environment = ProductionGameSeedAdapter.statisticsEnvironment
  private let deviceID = SDGameDeviceIdentity.current
  private var service: SupabaseService?
  private var journal: HPNativeScoringV2Journal?
  private var currentContext: () -> Bool = { false }
  private var queuedThirdOut: (ScoringCommand, String)?
  private var pollTask: Task<Void, Never>?
  private var synchronizing = false
  init(game: SDGame, participants: [SDEventParticipant], canScore: Bool) {
    self.game = game; self.participants = participants; self.canScore = canScore
    rules = ProductionGameSeedAdapter.rules(for: game)
    let initial = ProductionGameSeedAdapter.makeSeed(game: game, participants: participants, profiles: [])
    seed = initial; projection = GameProjection(seed: initial)
  }
  deinit { pollTask?.cancel() }
  var canMutate: Bool { canScore && currentContext() && journal?.canAppend == true && !isBusy && !isConflict }
  var currentBatter: Player? { projection.currentBatter(seed: seed) }
  var currentPitcher: Player? { projection.currentPitcher(seed: seed) }
  var canUndo: Bool { ScoringEngine.lastReversiblePlayID(events: events) != nil }
  var canRedo: Bool { ScoringEngine.lastRedoablePlayID(events: events) != nil }
  var recoveryRecord: String? {
    guard currentContext(), let journal, journal.pendingCount > 0 else { return nil }
    return try? journal.recoveryRecord()
  }
  var canRefreshPermission: Bool {
    canScore && currentContext() && journal?.pendingCount == 0 && !isBusy && !synchronizing && projection.status != .final
  }
  func refreshPermission() async {
    guard canRefreshPermission, let service, let saved = journal else { return }
    isBusy = true; defer { isBusy = false }
    do {
      let remote = try await service.listScoringEventsV2(gameId: game.id, organizationId: game.org_id)
      guard currentContext(), remote.starts(with: saved.events, by: { $0.id == $1.id }) else {
        throw HPNativeScoringV2Journal.JournalError.contextChanged
      }
      let key = P256.Signing.PrivateKey()
      let packageHash = try HPNativeScoringCanonical.hash(["gameID": .string(game.id.uuidString.lowercased()), "version": .int(remote.last?.sequence ?? 0)])
      let prepared = try await service.prepareNativeOffline(gameID: game.id, deviceID: deviceID, packageHash: packageHash, publicKey: HPNativeScoringV2Journal.publicKey(key))
      guard currentContext(), prepared.permit.gameID == game.id, prepared.permit.deviceID == deviceID,
            prepared.authority.serverVersion == (remote.last?.sequence ?? 0) else { throw HPNativeScoringV2Journal.JournalError.contextChanged }
      var updated = HPNativeScoringV2Journal(accountID: saved.accountID, organizationID: saved.organizationID, gameID: saved.gameID, deviceID: saved.deviceID,
        seed: saved.seed, packageHash: packageHash, privateKey: key.rawRepresentation, permit: prepared.permit, controlToken: prepared.authority.controlToken, confirmedEvents: remote)
      updated.rules = rules
      try HPNativeScoringV2JournalStore.application.save(updated)
      journal = updated; events = remote; try refreshDerivedState(); syncState = .synced
    } catch {
      syncState = .conflict("Could not refresh scoring permission. Saved history remains protected; try again when authorized and connected.")
    }
  }
  private var isConflict: Bool { if case .conflict = syncState { true } else { false } }
  func start(service: SupabaseService, accountID: UUID, currentContext: @escaping () -> Bool) async {
    guard !isReady else { return }
    self.service = service; self.currentContext = currentContext
    do {
      if let saved = try HPNativeScoringV2JournalStore.application.load(account: accountID, org: game.org_id, game: game.id, device: deviceID) {
        journal = saved; seed = saved.seed; events = saved.events
        if let savedRules = saved.rules { rules = savedRules }
        authority = .init(deviceID: deviceID, epoch: saved.permit.authorityEpoch, serverVersion: saved.confirmedEvents.last?.sequence ?? 0, leaseExpiresAt: nil)
        try refreshDerivedState()
        syncState = saved.permit.isCurrent ? .offline(pending: saved.pendingCount) : .conflict("Offline permission expired. Local history is preserved; reconnect for staff reconciliation.")
      } else {
        let lineup = try await service.nativeSavedLineup(gameID: game.id)
        guard !canScore || (!lineup.isEmpty && lineup.contains { $0.position_code.uppercased() == "P" }) else {
          throw SDServiceError(category: .validation, functionName: "Save a lineup with a pitcher before scoring", statusCode: 422)
        }
        let profiles = try await service.scoringProfilesV2(userIds: Array(Set(lineup.map(\.player_id))))
        guard currentContext() else { throw HPNativeScoringV2Journal.JournalError.contextChanged }
        seed = ProductionGameSeedAdapter.makeSeed(game: game, participants: participants, profiles: profiles, savedLineup: lineup)
        events = try await service.listScoringEventsV2(gameId: game.id, organizationId: game.org_id)
        if canScore {
          let key = P256.Signing.PrivateKey()
          let packageHash = try ScoringContractHasher.hash(["seed": SDJSONValue.object(HPNativeScoringV2Journal.object(seed)), "events": .array(try events.map { .object(try HPNativeScoringV2Journal.object($0)) })])
          let prepared = try await service.prepareNativeOffline(gameID: game.id, deviceID: deviceID, packageHash: packageHash, publicKey: HPNativeScoringV2Journal.publicKey(key))
          guard currentContext(), prepared.permit.gameID == game.id, prepared.permit.deviceID == deviceID,
                prepared.authority.serverVersion == (events.last?.sequence ?? 0) else { throw HPNativeScoringV2Journal.JournalError.contextChanged }
          var saved = HPNativeScoringV2Journal(accountID: accountID, organizationID: game.org_id, gameID: game.id, deviceID: deviceID, seed: seed, packageHash: packageHash, privateKey: key.rawRepresentation, permit: prepared.permit, controlToken: prepared.authority.controlToken, confirmedEvents: events)
          saved.rules = rules
          try HPNativeScoringV2JournalStore.application.save(saved)
          journal = saved
          authority = .init(deviceID: deviceID, epoch: prepared.permit.authorityEpoch, serverVersion: prepared.authority.serverVersion, leaseExpiresAt: nil)
        }
        try refreshDerivedState(); syncState = .synced
      }
      isReady = true
      if events.isEmpty && canMutate { try await commitImmediately(.startGame, label: "Game started") }
      await synchronize()
      beginPolling()
    } catch {
      errorText = "Could not prepare scoring safely. \(error.localizedDescription)"
      syncState = .conflict(errorText!); isReady = true
    }
  }
  func recordPitch(_ result: PitchResult) { Task { await commit(.recordPitch(result), label: result.title) } }
  func recordBallInPlay(_ command: BallInPlayCommand) { Task { await commit(.recordBallInPlay(command), label: command.result.title) } }
  func advanceRunner(_ resolution: RunnerResolution) { Task { await commit(.advanceRunner(resolution), label: resolution.isOut ? "Runner out" : resolution.scored ? "Run scored" : "Runner advanced") } }
  func endGame() { Task { await commit(.endGame(reason: "Scorekeeper ended game"), label: "Game marked final") } }
  func undo() { guard let id = ScoringEngine.lastReversiblePlayID(events: events) else { return }; Task { await commit(.undo(playID: id, reason: "Scorekeeper undo"), label: "Play undone") } }
  func redo() { guard let id = ScoringEngine.lastRedoablePlayID(events: events) else { return }; Task { await commit(.redo(playID: id), label: "Play restored") } }
  func confirmHalfInning() {
    guard let queuedThirdOut else { return }; self.queuedThirdOut = nil; pendingHalfInning = nil
    Task { do { try await commitImmediately(queuedThirdOut.0, label: "Inning confirmed · \(queuedThirdOut.1)") } catch { errorText = error.localizedDescription } }
  }
  func cancelHalfInning() { queuedThirdOut = nil; pendingHalfInning = nil; toastText = "Third-out play cancelled" }
  func dismissError() { errorText = nil }
  private func commit(_ command: ScoringCommand, label: String) async {
    guard canMutate else { return }
    do {
      let preview = try ScoringEngine.makePlay(command: command, seed: seed, rules: rules, events: events, authorityEpoch: journal!.permit.authorityEpoch)
      let next = try ScoringEngine.replay(seed: seed, rules: rules, events: events + preview.events)
      if next.half != projection.half || next.inning != projection.inning { queuedThirdOut = (command, label); pendingHalfInning = "Confirm end of \(projection.half == .top ? "Top" : "Bottom") \(projection.inning)"; return }
      try await commitImmediately(command, label: label)
    } catch { errorText = error.localizedDescription }
  }
  private func commitImmediately(_ command: ScoringCommand, label: String) async throws {
    guard canMutate, var saved = journal else { return }
    isBusy = true
    do {
      let play = try ScoringEngine.makePlay(command: command, seed: seed, rules: rules, events: events, authorityEpoch: saved.permit.authorityEpoch)
      let nextEvents = events + play.events
      let next = try ScoringEngine.replay(seed: seed, rules: rules, events: nextEvents)
      let stats = try StatisticsEngine.derive(seed: seed, rules: rules, environment: environment, events: nextEvents)
      let envelope = ScoringPlayEnvelopeV2(play: play, gameID: game.id, startingGameVersion: play.events.first!.sequence - 1, authorityEpoch: saved.permit.authorityEpoch, rulesVersion: rules.version, statisticsEnvironmentVersion: environment.formulaVersion, projection: next, snapshot: stats)
      try saved.append(play: play, envelope: envelope, command: command, preconditions: projection)
      // One atomic file contains the exact signed envelope AND projected history.
      // A disk error leaves both the screen and server unchanged.
      try HPNativeScoringV2JournalStore.application.save(saved)
      journal = saved; events = nextEvents; projection = next; snapshot = stats; toastText = label
      isBusy = false
      await synchronize()
    } catch { isBusy = false; throw error }
  }
  private func refreshDerivedState() throws {
    projection = try ScoringEngine.replay(seed: seed, rules: rules, events: events)
    snapshot = try StatisticsEngine.derive(seed: seed, rules: rules, environment: environment, events: events)
  }
  func synchronize() async {
    guard !synchronizing, !isConflict, currentContext(), let service, let saved = journal else { return }
    guard saved.permit.isCurrent else { syncState = .conflict("Offline permission expired. Local plays are preserved for review."); return }
    synchronizing = true; defer { synchronizing = false }
    for entry in saved.entries where !entry.accepted {
      guard currentContext() else { return }
      syncState = .syncing(pending: journal?.pendingCount ?? 0)
      do {
        let response = try await service.syncNativeOffline(saved, entry: entry)
        guard currentContext() else { return }
        guard response.ok, response.receipt.recoveryState == "synced",
              response.receipt.acceptedCommandIDs == [entry.play.commandID], response.receipt.acceptedPlayIDs == [entry.play.id] else {
          syncState = .conflict("Server could not accept the saved play. Local history is protected; no commands were rebased."); return
        }
        // Re-read current state: more plays may have been saved while awaiting network.
        guard var updated = journal, let index = updated.entries.firstIndex(where: { $0.play.id == entry.play.id }) else { throw HPNativeScoringV2Journal.JournalError.invalidReceipt }
        updated.entries[index].accepted = true
        try HPNativeScoringV2JournalStore.application.save(updated); journal = updated
      } catch {
        if Self.requiresReconciliation(error) {
          syncState = .conflict("Scoring permission or server validation changed. Local plays are preserved; further scoring is paused for review.")
        } else {
          syncState = .offline(pending: journal?.pendingCount ?? 0)
        }
        return
      }
    }
    syncState = (journal?.pendingCount ?? 0) == 0 ? .synced : .offline(pending: journal?.pendingCount ?? 0)
  }
  static func requiresReconciliation(_ error: Error) -> Bool {
    guard let category = SDApplicationErrorClassifier.presentation(for: error)?.category else { return true }
    return ![.offline, .serviceUnavailable, .serverError].contains(category)
  }
  private func beginPolling() {
    pollTask?.cancel()
    pollTask = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(5))
        guard let self, self.currentContext() else { return }
        if self.journal != nil { await self.synchronize() }
        else if let service = self.service {
          do { let remote = try await service.listScoringEventsV2(gameId: self.game.id, organizationId: self.game.org_id)
            guard self.currentContext() else { return }; self.events = remote; try self.refreshDerivedState()
          } catch { self.syncState = .offline(pending: 0) }
        }
      }
    }
  }
}
