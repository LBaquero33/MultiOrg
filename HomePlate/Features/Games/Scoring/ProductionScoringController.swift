import Combine
import CryptoKit
import Foundation
import Network
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
  private var queuedThirdOut: (ScoringCommand, String, GameVideoTimestamp)?
  private var videoClock: GameVideoClockAnchor?
  private var syncingVideoMarkers = false
  private func captureTime() -> GameVideoTimestamp {
    (try? videoClock?.timestamp(at: ProcessInfo.processInfo.systemUptime)) ?? .init(enteredAt: Date(), uncertaintyMilliseconds: nil)
  }
  private var pollTask: Task<Void, Never>?
  private var synchronizing = false
  private let networkMonitor = NWPathMonitor()
  private var syncFailures = 0
  private var nextSyncUptime: TimeInterval = 0
  init(game: SDGame, participants: [SDEventParticipant], canScore: Bool) {
    self.game = game; self.participants = participants; self.canScore = canScore
    rules = ProductionGameSeedAdapter.rules(for: game)
    let initial = ProductionGameSeedAdapter.makeSeed(game: game, participants: participants, profiles: [])
    seed = initial; projection = GameProjection(seed: initial)
  }
  deinit { pollTask?.cancel(); networkMonitor.cancel() }
  var canMutate: Bool { canScore && currentContext() && journal?.canAppend == true && !isBusy && (!isConflict || journal?.recoveryReason != nil) }
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
    Task { [weak self] in self?.videoClock = try? await service.gameVideoClockAnchor() }
    do {
      if var saved = try HPNativeScoringV2JournalStore.application.load(account: accountID, org: game.org_id, game: game.id, device: deviceID) {
        if !saved.permit.isCurrent && saved.recoveryReason == nil {
          saved.recoveryReason = "Offline permission expired. Local recovery only — not official until staff reconciliation."
          try HPNativeScoringV2JournalStore.application.save(saved)
        }
        journal = saved; seed = saved.seed; events = saved.events
        if let savedRules = saved.rules { rules = savedRules }
        authority = .init(deviceID: deviceID, epoch: saved.permit.authorityEpoch, serverVersion: saved.confirmedEvents.last?.sequence ?? 0, leaseExpiresAt: nil)
        try refreshDerivedState()
        syncState = saved.recoveryReason.map { .conflict($0) } ?? .offline(pending: saved.pendingCount)
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
      Task { await synchronize() }
      beginPolling()
    } catch {
      errorText = "Could not prepare scoring safely. \(error.localizedDescription)"
      syncState = .conflict(errorText!); isReady = true
    }
  }
  func recordPitch(_ result: PitchResult) { let time = captureTime(); Task { await commit(.recordPitch(result), label: result.title, timestamp: time) } }
  func recordBallInPlay(_ command: BallInPlayCommand) { let time = captureTime(); Task { await commit(.recordBallInPlay(command), label: command.result.title, timestamp: time) } }
  func advanceRunner(_ resolution: RunnerResolution) { let time = captureTime(); Task { await commit(.advanceRunner(resolution), label: resolution.isOut ? "Runner out" : resolution.scored ? "Run scored" : "Runner advanced", timestamp: time) } }
  func endGame() { Task { await commit(.endGame(reason: "Scorekeeper ended game"), label: "Game marked final") } }
  func undo() { guard let id = ScoringEngine.lastReversiblePlayID(events: events) else { return }; Task { await commit(.undo(playID: id, reason: "Scorekeeper undo"), label: "Play undone") } }
  func redo() { guard let id = ScoringEngine.lastRedoablePlayID(events: events) else { return }; Task { await commit(.redo(playID: id), label: "Play restored") } }
  func confirmHalfInning() {
    guard let queuedThirdOut else { return }; self.queuedThirdOut = nil; pendingHalfInning = nil
    Task { do { try await commitImmediately(queuedThirdOut.0, label: "Inning confirmed · \(queuedThirdOut.1)", timestamp: queuedThirdOut.2) } catch { errorText = error.localizedDescription } }
  }
  func cancelHalfInning() { queuedThirdOut = nil; pendingHalfInning = nil; toastText = "Third-out play cancelled" }
  func dismissError() { errorText = nil }
  private func commit(_ command: ScoringCommand, label: String, timestamp: GameVideoTimestamp? = nil) async {
    guard canMutate else { return }
    do {
      let preview = try ScoringEngine.makePlay(command: command, seed: seed, rules: rules, events: events, authorityEpoch: journal!.permit.authorityEpoch)
      let next = try ScoringEngine.replay(seed: seed, rules: rules, events: events + preview.events)
      if next.half != projection.half || next.inning != projection.inning { queuedThirdOut = (command, label, timestamp ?? captureTime()); pendingHalfInning = "Confirm end of \(projection.half == .top ? "Top" : "Bottom") \(projection.inning)"; return }
      try await commitImmediately(command, label: label, timestamp: timestamp)
    } catch { errorText = error.localizedDescription }
  }
  private func commitImmediately(_ command: ScoringCommand, label: String, timestamp: GameVideoTimestamp? = nil) async throws {
    guard canMutate, var saved = journal else { return }
    isBusy = true
    do {
      let time = timestamp ?? captureTime()
      let play = try ScoringEngine.makePlay(command: command, seed: seed, rules: rules, events: events, authorityEpoch: saved.permit.authorityEpoch, now: time.enteredAt)
      let nextEvents = events + play.events
      let next = try ScoringEngine.replay(seed: seed, rules: rules, events: nextEvents)
      let stats = try StatisticsEngine.derive(seed: seed, rules: rules, environment: environment, events: nextEvents)
      let envelope = ScoringPlayEnvelopeV2(play: play, gameID: game.id, startingGameVersion: play.events.first!.sequence - 1, authorityEpoch: saved.permit.authorityEpoch, rulesVersion: rules.version, statisticsEnvironmentVersion: environment.formulaVersion, projection: next, snapshot: stats)
      try saved.append(play: play, envelope: envelope, command: command, preconditions: projection, captureTimestamp: time)
      // One atomic file contains the exact signed envelope AND projected history.
      // A disk error leaves both the screen and server unchanged.
      try HPNativeScoringV2JournalStore.application.save(saved)
      journal = saved; events = nextEvents; projection = next; snapshot = stats; toastText = label
      isBusy = false
      Task { await synchronize() }
    } catch { isBusy = false; throw error }
  }
  private func refreshDerivedState() throws {
    projection = try ScoringEngine.replay(seed: seed, rules: rules, events: events)
    snapshot = try StatisticsEngine.derive(seed: seed, rules: rules, environment: environment, events: events)
  }
  func synchronize() async {
    guard !synchronizing, !isConflict, currentContext(), let service, let saved = journal else { return }
    guard saved.recoveryReason == nil else { syncState = .conflict(saved.recoveryReason!); return }
    guard saved.permit.isCurrent else { protectRecovery("Offline permission expired. Local recovery only — not official until staff reconciliation."); return }
    guard ProcessInfo.processInfo.systemUptime >= nextSyncUptime else { return }
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
        syncFailures = 0; nextSyncUptime = 0
      } catch {
        if Self.requiresReconciliation(error) {
          protectRecovery("Scoring authority changed. Continue in local recovery only — these plays are not official until staff reconciliation.")
        } else {
          syncFailures += 1
          nextSyncUptime = ProcessInfo.processInfo.systemUptime + min(60, pow(2, Double(min(syncFailures, 6))))
          syncState = .offline(pending: journal?.pendingCount ?? 0)
        }
        return
      }
    }
    syncState = (journal?.pendingCount ?? 0) == 0 ? .synced : .offline(pending: journal?.pendingCount ?? 0)
  }
  static func requiresReconciliation(_ error: Error) -> Bool {
    guard let category = SDApplicationErrorClassifier.presentation(for: error)?.category else { return false }
    return [.forbidden, .validation, .staleData, .malformedResponse].contains(category)
  }
  private func protectRecovery(_ reason: String) {
    guard var saved = journal else { return }
    do {
      saved.recoveryReason = reason
      try HPNativeScoringV2JournalStore.application.save(saved)
      journal = saved; syncState = .conflict(reason)
    } catch {
      syncState = .conflict("Local storage failed. Scoring is paused; the last successfully saved plays remain preserved.")
      errorText = error.localizedDescription
    }
  }
  private func beginPolling() {
    pollTask?.cancel()
    networkMonitor.pathUpdateHandler = { [weak self] path in
      guard path.status == .satisfied else { return }
      Task { @MainActor [weak self] in
        self?.nextSyncUptime = 0
        await self?.synchronize()
      }
    }
    networkMonitor.start(queue: DispatchQueue(label: "homeplate.scoring.connectivity"))
    pollTask = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(5))
        guard let self, self.currentContext() else { return }
        if self.journal != nil {
          await self.synchronize()
          // Media delivery is independent: errors never alter scoring state.
          await self.synchronizeCaptureMarkers()
          if self.videoClock == nil || ProcessInfo.processInfo.systemUptime - (self.videoClock?.monotonicSeconds ?? 0) > 60,
            let service = self.service, let refreshed = try? await service.gameVideoClockAnchor() { self.videoClock = refreshed }
        }
        else if let service = self.service {
          do { let remote = try await service.listScoringEventsV2(gameId: self.game.id, organizationId: self.game.org_id)
            guard self.currentContext() else { return }; self.events = remote; try self.refreshDerivedState()
          } catch { self.syncState = .offline(pending: 0) }
        }
      }
    }
  }
  private func synchronizeCaptureMarkers() async {
    guard !syncingVideoMarkers, currentContext(), let service, let saved = journal else { return }
    syncingVideoMarkers = true; defer { syncingVideoMarkers = false }
    for entry in saved.entries where entry.accepted && entry.captureMarkerSynced != true {
      guard currentContext(), let marker = entry.captureMarker else { continue }
      do {
        try await service.saveGameCaptureMarker(marker)
        guard currentContext(), var updated = journal,
          let index = updated.entries.firstIndex(where: { $0.play.id == entry.play.id }) else { return }
        updated.entries[index].captureMarkerSynced = true
        try HPNativeScoringV2JournalStore.application.save(updated); journal = updated
      } catch { return }
    }
  }
}
