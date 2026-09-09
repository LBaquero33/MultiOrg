import Combine
import Foundation
import HomePlateScoringCore
import HomePlateScoringStore

public enum LabTab: String, CaseIterable, Identifiable, Sendable {
  case score = "Score"
  case lineups = "Lineups"
  case plays = "Plays"
  case stats = "Stats"

  public var id: String { rawValue }
  public var systemImage: String {
    switch self {
    case .score: "baseball.diamond.bases"
    case .lineups: "tshirt.fill"
    case .plays: "list.bullet.rectangle"
    case .stats: "chart.bar.xaxis"
    }
  }
}

public enum LabSyncState: Equatable, Sendable {
  case starting
  case synced
  case offline(pending: Int)
  case syncing(pending: Int)
  case conflict(String)

  public var label: String {
    switch self {
    case .starting: "STARTING"
    case .synced: "SYNCED"
    case .offline(let pending): pending == 0 ? "OFFLINE" : "OFFLINE · \(pending) UNSYNCED"
    case .syncing(let pending): "SYNCING · \(pending)"
    case .conflict: "SYNC CONFLICT"
    }
  }
}

public struct PendingHalfInningTransition: Equatable, Sendable {
  public let currentLabel: String
  public let nextLabel: String
  public let playLabel: String
}

enum HalfInningConfirmationPolicy {
  static func preview(
    command: ScoringCommand,
    label: String,
    projection: GameProjection,
    seed: GameSeed,
    rules: GameRulesProfile,
    events: [ScoringEvent],
    authorityEpoch: Int
  ) throws -> PendingHalfInningTransition? {
    switch command {
    case .recordPitch, .recordBallInPlay, .advanceRunner:
      break
    default:
      return nil
    }
    let play = try ScoringEngine.makePlay(
      command: command,
      seed: seed,
      rules: rules,
      events: events,
      authorityEpoch: authorityEpoch
    )
    let next = try ScoringEngine.replay(seed: seed, rules: rules, events: events + play.events)
    guard next.inning != projection.inning || next.half != projection.half else { return nil }
    return PendingHalfInningTransition(
      currentLabel: halfLabel(inning: projection.inning, half: projection.half),
      nextLabel: halfLabel(inning: next.inning, half: next.half),
      playLabel: label
    )
  }

  private static func halfLabel(inning: Int, half: GameHalf) -> String {
    "\(half == .top ? "Top" : "Bottom") \(inning)"
  }
}

@MainActor
public final class LabGameController: ObservableObject {
  @Published public private(set) var events: [ScoringEvent] = []
  @Published public private(set) var projection: GameProjection
  @Published public private(set) var snapshot: StatSnapshot?
  @Published public private(set) var syncState: LabSyncState = .starting
  @Published public private(set) var isReady = false
  @Published public private(set) var isBusy = false
  @Published public var selectedTab: LabTab = .score
  @Published public var toastText: String?
  @Published public var errorText: String?
  @Published public private(set) var pendingHalfInning: PendingHalfInningTransition?

  public let seed: GameSeed
  public let rules: GameRulesProfile
  public let environment: StatEnvironment

  private var store: SQLiteEventStore?
  private let server = FakeAuthoritativeScoringServer()
  private let dashboard = InMemoryDashboardPublisher()
  private var syncService: ScoreSyncService?
  private var authorityEpoch = 1
  private var online = true
  private var pendingTransitionCommand: (command: ScoringCommand, label: String)?

  public init(
    seed: GameSeed = DemoGame.seed,
    rules: GameRulesProfile = .nfhs,
    environment: StatEnvironment = .lab2026
  ) {
    self.seed = seed
    self.rules = rules
    self.environment = environment
    projection = GameProjection(seed: seed)
  }

  public var currentBatter: Player? { projection.currentBatter(seed: seed) }
  public var currentPitcher: Player? { projection.currentPitcher(seed: seed) }
  public var canUndo: Bool { ScoringEngine.lastReversiblePlayID(events: events) != nil }
  public var canRedo: Bool { ScoringEngine.lastRedoablePlayID(events: events) != nil }
  public var isOnline: Bool { online }

  public func dismissToast() { toastText = nil }
  public func dismissError() { errorText = nil }

  public func start() async {
    guard !isReady else { return }
    do {
      let directory = try FileManager.default.url(
        for: .applicationSupportDirectory,
        in: .userDomainMask,
        appropriateFor: nil,
        create: true
      ).appendingPathComponent("HomePlateScoringLab", isDirectory: true)
      let localStore = try SQLiteEventStore(url: directory.appendingPathComponent("scoring-ledger.sqlite"))
      store = localStore
      events = try await localStore.loadEvents(gameID: seed.id)
      await server.bootstrap(gameID: seed.id, events: events)
      authorityEpoch = try await server.acquire(gameID: seed.id)
      syncService = ScoreSyncService(store: localStore, server: server)
      if events.isEmpty {
        try await commit(.startGame, automaticallySync: true)
      } else {
        try await refreshDerivedState()
      }
      isReady = true
      try await synchronize()
    } catch {
      errorText = error.localizedDescription
      syncState = .conflict(error.localizedDescription)
      isReady = true
    }
  }

  public func recordPitch(_ result: PitchResult) {
    Task { try? await commitWithFeedback(.recordPitch(result), label: result.title) }
  }

  public func recordBallInPlay(_ command: BallInPlayCommand) async throws {
    try await commitWithFeedback(.recordBallInPlay(command), label: command.result.title)
  }

  public func advanceRunner(_ resolution: RunnerResolution) async throws {
    try await commitWithFeedback(.advanceRunner(resolution), label: "Runner updated")
  }

  public func confirmHalfInning() {
    guard let pendingTransitionCommand else { return }
    self.pendingTransitionCommand = nil
    pendingHalfInning = nil
    Task {
      try? await commitImmediatelyWithFeedback(
        pendingTransitionCommand.command,
        label: "Inning confirmed · \(pendingTransitionCommand.label)"
      )
    }
  }

  public func cancelHalfInningConfirmation() {
    pendingTransitionCommand = nil
    pendingHalfInning = nil
    toastText = "Third-out play cancelled"
  }

  public func applyOverride(_ override: GameOverride) async throws {
    try await commitWithFeedback(.override(override), label: "Override recorded")
  }

  public func substitute(_ command: SubstitutionCommand) async throws {
    try await commitWithFeedback(
      .substitute(command),
      label: "\(command.incomingPlayer.shortName) entered"
    )
  }

  public func undo() {
    guard let target = ScoringEngine.lastReversiblePlayID(events: events) else { return }
    Task { try? await commitWithFeedback(.undo(playID: target, reason: "Scorekeeper undo"), label: "Play undone") }
  }

  public func redo() {
    guard let target = ScoringEngine.lastRedoablePlayID(events: events) else { return }
    Task { try? await commitWithFeedback(.redo(playID: target), label: "Play restored") }
  }

  public func endGame() {
    Task { try? await commitWithFeedback(.endGame(reason: "Scorekeeper ended game"), label: "Game marked final") }
  }

  public func setOnline(_ online: Bool) {
    self.online = online
    Task {
      await server.setOnline(online)
      if online {
        do { try await synchronize() }
        catch { syncState = .conflict(error.localizedDescription) }
      } else {
        let pending = (try? await store?.pendingCount(gameID: seed.id)) ?? 0
        syncState = .offline(pending: pending)
      }
    }
  }

  public func simulateTakeover() {
    Task {
      do {
        _ = try await server.forceTakeover(gameID: seed.id)
        try await synchronize()
      } catch {
        syncState = .conflict(error.localizedDescription)
        errorText = error.localizedDescription
      }
    }
  }

  public func exportFiles() throws -> [URL] {
    guard let snapshot else { return [] }
    let bundle = StatTableExporter.export(snapshot: snapshot, seed: seed)
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("HomePlate-Stats-\(seed.id.uuidString.prefix(8))", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let files = [
      ("batting.csv", bundle.batting),
      ("pitching.csv", bundle.pitching),
      ("fielding.csv", bundle.fielding),
      ("team_totals.csv", bundle.teamTotals),
    ]
    return try files.map { name, text in
      let url = directory.appendingPathComponent(name)
      try text.data(using: .utf8)?.write(to: url, options: .atomic)
      return url
    }
  }

  public func lineup(_ side: TeamSide) -> [LineupEntry] {
    (projection.lineups[side] ?? seed.team(side).lineup)
      .filter { $0.exitedAtSequence == nil }
      .sorted { $0.battingSlot < $1.battingSlot }
  }

  public func player(at position: DefensivePosition, side: TeamSide? = nil) -> Player? {
    let teamSide = side ?? projection.defense
    return lineup(teamSide).first(where: { $0.position == position })?.player
  }

  private func commitWithFeedback(_ command: ScoringCommand, label: String) async throws {
    if try queuesHalfInningTransition(command, label: label) { return }
    try await commitImmediatelyWithFeedback(command, label: label)
  }

  private func commitImmediatelyWithFeedback(_ command: ScoringCommand, label: String) async throws {
    do {
      try await commit(command, automaticallySync: online)
      toastText = label
    } catch {
      errorText = error.localizedDescription
      throw error
    }
  }

  private func queuesHalfInningTransition(_ command: ScoringCommand, label: String) throws -> Bool {
    guard pendingTransitionCommand == nil else { return true }
    guard let pending = try HalfInningConfirmationPolicy.preview(
      command: command,
      label: label,
      projection: projection,
      seed: seed,
      rules: rules,
      events: events,
      authorityEpoch: authorityEpoch
    ) else { return false }

    pendingTransitionCommand = (command, label)
    pendingHalfInning = pending
    return true
  }

  private func commit(_ command: ScoringCommand, automaticallySync: Bool) async throws {
    guard let store else { throw EventStoreError.openFailed("Store is not ready") }
    isBusy = true
    defer { isBusy = false }
    let play = try ScoringEngine.makePlay(
      command: command,
      seed: seed,
      rules: rules,
      events: events,
      authorityEpoch: authorityEpoch
    )
    try await store.append(play)
    events = try await store.loadEvents(gameID: seed.id)
    try await refreshDerivedState()
    if automaticallySync {
      try await synchronize()
    } else {
      syncState = .offline(pending: try await store.pendingCount(gameID: seed.id))
    }
  }

  private func refreshDerivedState() async throws {
    projection = try ScoringEngine.replay(seed: seed, rules: rules, events: events)
    let derived = try StatisticsEngine.derive(
      seed: seed, rules: rules, environment: environment, events: events
    )
    snapshot = derived
    try await store?.saveProjection(projection, gameID: seed.id)
    try await store?.saveDashboardSnapshot(derived)
    try await dashboard.publish(derived)
  }

  private func synchronize() async throws {
    guard online, let store, let syncService else { return }
    let pending = try await store.pendingCount(gameID: seed.id)
    syncState = .syncing(pending: pending)
    let report = try await syncService.sync(gameID: seed.id, authorityEpoch: authorityEpoch)
    syncState = .synced
    if report.uploaded > 0 { toastText = "\(report.uploaded) event\(report.uploaded == 1 ? "" : "s") synced" }
  }
}
