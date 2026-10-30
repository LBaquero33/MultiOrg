import SwiftUI
import Supabase

struct LiveGameScoringView: View {
  @EnvironmentObject private var appState: AppState

  let game: SDGame
  let participants: [SDEventParticipant]

  @State private var state = SDGameState()
  @State private var serverState = SDGameState()
  @State private var journal: SDGameScoringJournal?
  @State private var journalLoadFailed = false
  @State private var authorityWasVerified = false
  @State private var journalProtocolAvailable = false
  @State private var reconciliationStatus: String?
  @State private var rules = SDResolvedBaseballRules()
  @State private var controlState: SDScorekeeperControlState = .disconnected
  @State private var controlToken: String?
  @State private var pendingRequest: SDControlRequestLease?
  @State private var pendingBall = SDPendingBattedBall()
  @State private var showingBallInPlay = false
  @State private var isLoading = true
  @State private var isSubmitting = false
  @State private var errorText: String?

  private let deviceId = SDGameDeviceIdentity.current
  private let journalStore = SDGameScoringJournalStore.applicationSupport

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      liveHeader
      scoreStrip
      if let reconciliationStatus {
        Label(reconciliationStatus, systemImage: "clock.arrow.circlepath")
          .font(.footnote.weight(.semibold))
          .foregroundStyle(.orange)
      }
      if game.scoring_schema_version == 2 {
        Text("This game uses the advanced scoring ledger. Open Game Hub on the web to score it; this screen remains view-only.")
          .font(.callout)
        Link("Open Game Hub", destination: URL(string: "https://www.homeplateapps.com/app/games/\(game.id.uuidString.lowercased())")!)
      }
      ViewThatFits(in: .horizontal) {
        HStack(alignment: .top, spacing: 14) {
          field.frame(minWidth: 310)
          actionPanel.frame(minWidth: 240, maxWidth: 280)
        }
        VStack(alignment: .leading, spacing: 14) {
          field
          actionPanel
        }
      }
      .frame(maxWidth: .infinity, alignment: .top)
      if !canMutate {
        viewerBanner
      }
    }
    .task(id: game.id) { await start() }
    .task(id: controlToken) { await heartbeatLoop() }
    .onDisappear {
      guard let token = controlToken else { return }
      Task { await release(token: token) }
    }
    .sheet(isPresented: $showingBallInPlay) {
      ballInPlaySheet
        #if os(macOS)
        .frame(minWidth: 500, minHeight: 430)
        #endif
    }
    .alert("Live scoring", isPresented: Binding(
      get: { errorText != nil }, set: { if !$0 { errorText = nil } }
    )) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(errorText ?? "")
    }
  }

  private var canScore: Bool {
    SDGameAuthorization.canScore(
      game: game,
      userId: appState.myProfile?.id,
      membership: appState.activeOrgMembership,
      participants: participants
    )
  }

  private var canMutate: Bool {
    game.scoring_schema_version != 2 && canScore && appState.activeOrgId == game.org_id && !isSubmitting && !journalLoadFailed && (controlState.canMutate
      || (authorityWasVerified && journalProtocolAvailable && journal?.hasConflict == false))
  }

  private var liveHeader: some View {
    HStack(spacing: 10) {
      Circle()
        .fill(controlState.canMutate ? Color.green : Color.orange)
        .frame(width: 10, height: 10)
      VStack(alignment: .leading, spacing: 2) {
        Text(controlState.canMutate ? "Live scorekeeper" : "Live viewer")
          .font(.headline)
        Text("\(journal?.commands.isEmpty == false ? "PROVISIONAL • \(journal?.commands.count ?? 0) pending play(s)" : "Server version \(serverState.version)") • \(state.half.capitalized) \(state.inning)")
          .font(.caption)
          .foregroundStyle(DHDTheme.textSecondary)
      }
      Spacer()
      if isLoading || isSubmitting { ProgressView() }
      if canScore && !controlState.canMutate {
        Button("Request control") { Task { await requestControl() } }
          .buttonStyle(.borderedProminent)
      }
    }
  }

  private var scoreStrip: some View {
    HStack(spacing: 0) {
      scoreCell(game.away_team_name, state.awayScore)
      Divider().frame(height: 48)
      scoreCell(game.home_team_name, state.homeScore)
      Divider().frame(height: 48)
      statCell("Count", "\(state.balls)-\(state.strikes)")
      statCell("Outs", "\(state.outs)")
      statCell("Pitches", "\(state.pitchCount)")
    }
    .padding(.vertical, 8)
    .background(DHDTheme.surfaceElevated)
    .clipShape(RoundedRectangle(cornerRadius: 8))
  }

  private func scoreCell(_ name: String, _ score: Int) -> some View {
    VStack(spacing: 2) {
      Text(name).font(.caption).lineLimit(1)
      Text("\(score)").font(.title.bold())
    }
    .frame(maxWidth: .infinity)
  }

  private func statCell(_ label: String, _ value: String) -> some View {
    VStack(spacing: 2) {
      Text(label).font(.caption).foregroundStyle(DHDTheme.textSecondary)
      Text(value).font(.title3.bold())
    }
    .frame(maxWidth: .infinity)
  }

  private var field: some View {
    ZStack {
      RoundedRectangle(cornerRadius: 8)
        .fill(Color.green.opacity(0.15))
      Diamond()
        .stroke(Color.green.opacity(0.6), lineWidth: 2)
        .padding(70)
      baseTarget(2, alignment: .top)
      baseTarget(3, alignment: .leading)
      baseTarget(1, alignment: .trailing)
      baseTarget(0, alignment: .bottom)
    }
    .frame(minWidth: 310, idealWidth: 460, maxWidth: .infinity, minHeight: 340)
  }

  private func baseTarget(_ base: Int, alignment: Alignment) -> some View {
    let runner = state.bases[base]
    return VStack(spacing: 3) {
      Image(systemName: runner == nil ? "diamond" : "figure.run")
        .font(.title2)
      Text(baseName(base)).font(.caption.bold())
    }
    .frame(width: 78, height: 64)
    .background(runner == nil ? DHDTheme.cardSurface : DHDTheme.accent.opacity(0.25))
    .clipShape(RoundedRectangle(cornerRadius: 8))
    .overlay(RoundedRectangle(cornerRadius: 8).stroke(DHDTheme.separator))
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
    .padding(18)
    .draggable(runner.map { "\($0.playerId.uuidString)|\(base)" } ?? "")
    .dropDestination(for: String.self) { values, _ in
      guard canMutate, base > 0, let first = values.first else { return false }
      let parts = first.split(separator: "|")
      guard parts.count == 2, let player = UUID(uuidString: String(parts[0])),
            let from = Int(parts[1]) else { return false }
      Task { await advanceRunner(player: player, from: from, to: base) }
      return true
    }
  }

  private var actionPanel: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Pitch").font(.headline)
      actionGrid([
        ("Ball", "circle", SDScoringEventType.pitchResultRecorded, ["result": .string("ball")]),
        ("Strike", "s.circle", .pitchResultRecorded, ["result": .string("called_strike")]),
        ("Swinging", "figure.baseball", .pitchResultRecorded, ["result": .string("swinging_strike")]),
        ("Foul", "arrow.turn.up.left", .pitchResultRecorded, ["result": .string("foul")]),
      ])
      Button {
        pendingBall = SDPendingBattedBall()
        showingBallInPlay = true
      } label: {
        Label("Ball in play", systemImage: "baseball.fill")
          .frame(maxWidth: .infinity)
      }
      .buttonStyle(.borderedProminent)
      .disabled(!canMutate)
      Divider()
      Text("Game").font(.headline)
      Button("Record out") {
        Task { await commit(.administrativeOut, payload: [:]) }
      }
      .disabled(!canMutate)
      Button("End half inning") {
        Task { await commit(.halfInningEnded, payload: [:]) }
      }
      .disabled(!canMutate)
      Button("End game", role: .destructive) {
        Task { await commit(.gameEnded, payload: [:]) }
      }
      .disabled(!canMutate || state.status == .final)
      Button("Add home run") {
        Task { await commit(.runScored, payload: ["team": .string("home")]) }
      }
      .disabled(!canMutate)
      Button("Add away run") {
        Task { await commit(.runScored, payload: ["team": .string("away")]) }
      }
      .disabled(!canMutate)
    }
    .frame(minWidth: 190, idealWidth: 240, maxWidth: 280)
  }

  private func actionGrid(
    _ actions: [(String, String, SDScoringEventType, [String: SDJSONValue])]
  ) -> some View {
    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
      ForEach(Array(actions.enumerated()), id: \.offset) { _, action in
        Button {
          Task {
            await commit([(.pitchThrown, [:]), (action.2, action.3)])
          }
        } label: {
          Label(action.0, systemImage: action.1)
            .frame(maxWidth: .infinity, minHeight: 34)
        }
        .buttonStyle(.bordered)
        .disabled(!canMutate)
      }
    }
  }

  private var viewerBanner: some View {
    HStack {
      Image(systemName: "lock.fill")
      Text(journal?.hasPendingCommands == true
        ? "These plays are provisional on this device and are not official until the server accepts them."
        : pendingRequest == nil
          ? "Scoring controls are locked on this device."
          : "Control requested. This screen will remain live while you wait.")
    }
    .font(.footnote.weight(.semibold))
    .foregroundStyle(.orange)
  }

  private var ballInPlaySheet: some View {
    NavigationStack {
      Form {
        Section("Result") {
          Picker("Outcome", selection: $pendingBall.outcome) {
            Text("Select…").tag(nil as SDBattedBallOutcome?)
            ForEach(SDBattedBallOutcome.allCases) { outcome in
              Text(outcome.title).tag(outcome as SDBattedBallOutcome?)
            }
          }
        }
        Section("Official scoring") {
          TextField("Fielding sequence (example: 6-3)", text: Binding(
            get: { pendingBall.fieldingSequence.joined(separator: "-") },
            set: { pendingBall.fieldingSequence = $0.split(separator: "-").map(String.init) }
          ))
          TextField("Note", text: $pendingBall.note, axis: .vertical)
        }
      }
      .navigationTitle("Ball in Play")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { showingBallInPlay = false }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Record") {
            guard let outcome = pendingBall.outcome else { return }
            showingBallInPlay = false
            Task {
              await commit(.ballPutInPlay, payload: [
                "outcome": .string(outcome.rawValue),
                "fielding_sequence": .array(pendingBall.fieldingSequence.map(SDJSONValue.string)),
                "note": .string(pendingBall.note),
              ])
            }
          }
          .disabled(!pendingBall.canCommit)
        }
      }
    }
  }

  private func start() async {
    guard let service = appState.supabase, let orgId = appState.activeOrgId,
          let actorId = appState.myProfile?.id else { isLoading = false; return }
    guard orgId == game.org_id else {
      isLoading = false
      controlState = .viewer
      reconciliationStatus = "Select this game's organization to score it."
      return
    }
    rules = SDResolvedBaseballRules.resolve([game.ruleset_snapshot])
    do {
      journal = try journalStore.load(organizationId: orgId, gameId: game.id, deviceId: deviceId)
    } catch {
      journalLoadFailed = true
      controlState = .reconciliationRequired
      reconciliationStatus = "Saved scoring data could not be read. Scoring is locked to protect it."
      isLoading = false
      return
    }
    do {
      let events = try await service.listScoringEvents(gameId: game.id, organizationId: orgId)
      serverState = try SDGameReducer.replay(events, rules: rules)
      state = serverState
      if canScore && game.scoring_schema_version != 2 {
        if let stored = journal {
          guard stored.actorUserId == actorId, stored.organizationId == orgId,
                stored.gameId == game.id, stored.deviceId == deviceId else {
            freezeJournal("This device or account changed. Review the saved plays before continuing.")
            isLoading = false
            return
          }
          var existing = stored
          do {
            try existing.reconcilePersistedCommands(
              against: events, serverState: serverState, rules: rules
            )
            try journalStore.save(existing)
            journal = existing
          } catch {
            freezeJournal("The server game changed while plays were pending. Review before continuing.")
            isLoading = false
            return
          }
          let lease = try await service.acquireNativeScorekeepingControl(
            gameId: game.id, deviceId: deviceId,
            sessionId: try await service.authenticatedScoringSessionIdentifier(),
            expectedAuthorityEpoch: existing.authorityEpoch
          )
          guard lease.state != .reconciliationRequired,
                lease.authority_epoch == existing.authorityEpoch,
                lease.active_user_id == actorId, lease.active_device_id == deviceId else {
            freezeJournal("Scoring authority changed. Pending plays are frozen for explicit review.")
            isLoading = false
            return
          }
          journalProtocolAvailable = true
          authorityWasVerified = existing.authorityVerifiedAt <= Date()
          apply(lease)
          try await reconcilePendingCommands(service: service)
        } else {
          let sessionId: String
          do {
            sessionId = try await service.authenticatedScoringSessionIdentifier()
          } catch SDScoringSessionIdentifierError.missingJWTSessionIdentifier {
            let legacyLease = try await service.acquireScorekeepingControl(
              gameId: game.id, deviceId: deviceId,
              sessionId: try await service.legacyScoringSessionIdentifier()
            )
            journalProtocolAvailable = false
            authorityWasVerified = false
            apply(legacyLease)
            isLoading = false
            return
          }
          let lease: SDScorekeeperLease
          do {
            lease = try await service.acquireNativeScorekeepingControl(
              gameId: game.id, deviceId: deviceId,
              sessionId: sessionId, expectedAuthorityEpoch: nil
            )
          } catch let error where isJournalEndpointMissing(error) {
            // Compatibility with older online deployments only. This lease
            // cannot authorize offline provisional entry because it has no epoch.
            lease = try await service.acquireScorekeepingControl(
              gameId: game.id, deviceId: deviceId, sessionId: sessionId
            )
            journalProtocolAvailable = false
            authorityWasVerified = false
            apply(lease)
            isLoading = false
            return
          }
          guard lease.state != .reconciliationRequired,
                let epoch = lease.authority_epoch,
                lease.active_user_id == actorId, lease.active_device_id == deviceId else {
            apply(lease)
            isLoading = false
            return
          }
          journalProtocolAvailable = true
          authorityWasVerified = true
          journal = SDGameScoringJournal(
            organizationId: orgId, gameId: game.id, actorUserId: actorId,
            deviceId: deviceId, authorityVerifiedAt: Date(), authorityEpoch: epoch,
            baseServerVersion: serverState.version, baseState: serverState,
            commands: [], conflictReason: nil
          )
          if let journal { try journalStore.save(journal) }
          apply(lease)
        }
      } else {
        controlState = .viewer
        if journal?.hasPendingCommands == true {
          freezeJournal("Your scoring role changed. Pending plays are frozen for explicit review.")
        }
        try? await service.markGameLiveDevice(gameId: game.id, deviceId: deviceId, state: .liveViewer)
      }
    } catch {
      controlState = .disconnected
      if let existing = journal, existing.actorUserId == actorId,
         existing.organizationId == orgId, existing.gameId == game.id,
         existing.deviceId == deviceId, existing.authorityVerifiedAt <= Date(),
         !existing.hasConflict {
        journalProtocolAvailable = true
        authorityWasVerified = true
        state = (try? existing.projection(from: existing.baseState, rules: rules)) ?? existing.baseState
        reconciliationStatus = "Offline provisional entry: not official until server reconciliation."
      } else {
        errorText = error.localizedDescription
      }
    }
    isLoading = false
  }

  private func apply(_ lease: SDScorekeeperLease) {
    controlToken = lease.control_token
    switch lease.state {
    case .liveScorekeeper: controlState = .scorekeeper(expiresAt: lease.lease_expires_at)
    case .reconciliationRequired: controlState = .reconciliationRequired
    case .disconnected: controlState = .disconnected
    case .requestingControl: controlState = .requesting
    case .liveViewer: controlState = .viewer
    }
  }

  private func commit(_ type: SDScoringEventType, payload: [String: SDJSONValue]) async {
    await commit([(type, payload)])
  }

  private func commit(_ eventValues: [(SDScoringEventType, [String: SDJSONValue])]) async {
    guard canMutate else { return }
    isSubmitting = true
    defer { isSubmitting = false }
    do {
      guard let existing = journal else {
        guard let service = appState.supabase, let token = controlToken else {
          throw SDGameScoringJournalError.identityMismatch
        }
        guard SDLegacyScoringCommandPolicy.canSendOnlineOnly(eventCount: eventValues.count) else {
          reconciliationStatus = "This app version cannot safely record a multi-event play. Update before recording it."
          return
        }
        // Legacy protocol is supported online only. Keep command IDs stable
        // for this request and do not queue when its epoch contract is absent.
        for (index, value) in eventValues.enumerated() {
          let eventId = UUID()
          let event = try await service.appendScoringEvent(
            game: game, scoringEventId: eventId, expectedVersion: state.version,
            type: value.0, deviceId: deviceId, controlToken: token, payload: value.1,
            idempotencyKey: "native:\(eventId.uuidString.lowercased()):\(index)"
          )
          state = try SDGameReducer.apply(event, to: state, rules: rules)
          serverState = state
        }
        return
      }
      var updated = existing
      updated.enqueue(events: eventValues)
      guard !updated.hasConflict else { throw SDGameScoringJournalError.identityMismatch }
      _ = try updated.projection(from: updated.baseState, rules: rules)
      try journalStore.save(updated)
      journal = updated
      state = try updated.projection(from: updated.baseState, rules: rules)
      if let service = appState.supabase, let token = controlToken, journalProtocolAvailable {
        await reconcilePendingCommands(service: service, token: token)
      } else {
        reconciliationStatus = "PROVISIONAL: saved locally; not official until server reconciliation."
      }
    } catch {
      reconciliationStatus = "This play could not be saved safely. No official score was changed."
    }
  }

  private func reconcilePendingCommands(service: SupabaseService, token: String? = nil) async {
    guard var current = journal, let actorId = appState.myProfile?.id else { return }
    let epoch = current.authorityEpoch
    let activeToken: String
    if let token { activeToken = token }
    else if let controlToken { activeToken = controlToken }
    else { return }
    guard current.matches(
      organizationId: game.org_id, gameId: game.id, actorUserId: actorId,
      deviceId: deviceId, authorityEpoch: epoch
    ) else {
      freezeJournal("Scoring identity changed. Pending plays are frozen for explicit review.")
      return
    }
    do {
      for command in current.commands {
        let accepted: [SDScoringEvent]
        do {
          accepted = try await service.appendNativeScoringJournalCommand(
            game: game, command: command, actorDeviceId: deviceId,
            controlToken: activeToken, authorityEpoch: epoch
          )
        } catch {
          if isNativeAppendEndpointMissing(error), command.events.count == 1 {
            guard let event = command.events.first else {
              throw SDGameScoringJournalError.serverHeadChanged
            }
            let legacy = try await service.appendScoringEvent(
              game: game, scoringEventId: event.id,
              expectedVersion: command.expectedVersion, type: event.type,
              deviceId: deviceId, controlToken: activeToken, payload: event.payload,
              idempotencyKey: "native:\(command.id.uuidString.lowercased()):0"
            )
            accepted = [legacy]
          } else {
          let remote = try await service.listScoringEvents(gameId: game.id, organizationId: game.org_id)
          let matches = command.events.compactMap { queued in remote.first(where: { $0.id == queued.id }) }
          if matches.count == command.events.count {
            accepted = matches
          } else if matches.isEmpty {
            // Retry the exact persisted command IDs and payload only while the
            // current verified lease remains available.
            accepted = try await service.appendNativeScoringJournalCommand(
              game: game, command: command, actorDeviceId: deviceId,
              controlToken: activeToken, authorityEpoch: epoch
            )
          } else {
            throw SDGameScoringJournalError.serverHeadChanged
          }
          }
        }
        try current.acknowledge(command, with: accepted, rules: rules)
        try journalStore.save(current)
        journal = current
      }
      serverState = current.baseState
      state = current.baseState
      reconciliationStatus = nil
      if current.commands.isEmpty {
        try journalStore.remove(organizationId: current.organizationId, gameId: current.gameId, deviceId: current.deviceId)
        journal = current
      }
    } catch {
      if isRetryableScoringTransportFailure(error),
         current.hasConflict == false {
        // A lost response or unavailable server does not prove divergence.
        // Preserve the durable commands as provisional and reacquire against
        // the same verified epoch when connectivity returns.
        controlToken = nil
        controlState = .disconnected
        reconciliationStatus = "PROVISIONAL: connection lost. Saved plays remain queued and are not official. Reconnect to reconcile."
      } else {
        freezeJournal("The server game or scoring authority diverged. Pending plays need explicit review.")
      }
    }
  }

  private func freezeJournal(_ message: String) {
    if var current = journal {
      current.freeze(message)
      try? journalStore.save(current)
      journal = current
    }
    authorityWasVerified = false
    controlToken = nil
    controlState = .reconciliationRequired
    reconciliationStatus = message
  }

  private func isRetryableScoringTransportFailure(_ error: Error) -> Bool {
    if let functionsError = error as? FunctionsError,
       case let .httpError(statusCode, _) = functionsError {
      return statusCode == 408 || statusCode == 429 || statusCode >= 500
    }
    if let functionsError = error as? FunctionsError,
       case .relayError = functionsError {
      return true
    }
    return SDScorekeepingFailureDisposition.classify(error) == .retryTransport
  }

  private func isJournalEndpointMissing(_ error: Error) -> Bool {
    let description = error.localizedDescription.lowercased()
    return description.contains("pgrst202")
      || (description.contains("sd_acquire_native_scorekeeping_control")
        && (description.contains("not found") || description.contains("does not exist")
          || description.contains("could not find")))
  }

  private func isNativeAppendEndpointMissing(_ error: Error) -> Bool {
    let description = error.localizedDescription.lowercased()
    return description.contains("pgrst202")
      || (description.contains("sd_append_native_journal_command")
        && (description.contains("not found") || description.contains("does not exist")
          || description.contains("could not find")))
  }

  private func advanceRunner(player: UUID, from: Int, to: Int) async {
    await commit(.runnerAdvanced, payload: [
      "player_id": .string(player.uuidString),
      "from_base": .int(from),
      "to_base": .int(to),
    ])
  }

  private func requestControl() async {
    guard let service = appState.supabase else { return }
    do {
      pendingRequest = try await service.requestScorekeepingControl(gameId: game.id, deviceId: deviceId)
      controlState = .requesting
      try? await service.markGameLiveDevice(gameId: game.id, deviceId: deviceId, state: .requestingControl)
    } catch { errorText = error.localizedDescription }
  }

  private func heartbeatLoop() async {
    guard let service = appState.supabase else { return }
    while !Task.isCancelled {
      try? await Task.sleep(for: .seconds(SDScorekeeperLeasePolicy.heartbeatInterval))
      guard !Task.isCancelled else { break }
      if let token = controlToken, controlState.canMutate {
        do {
          let renewed = try await service.renewScorekeepingControl(
            gameId: game.id, deviceId: deviceId, token: token
          )
          if renewed { continue }
          controlToken = nil
          controlState = .viewer
        } catch {
          controlToken = nil
          controlState = .disconnected
        }
      }
      guard canScore, journalProtocolAvailable, let current = journal,
            !current.hasConflict, let actorId = appState.myProfile?.id else { continue }
      do {
        let lease = try await service.acquireNativeScorekeepingControl(
          gameId: game.id, deviceId: deviceId,
          sessionId: try await service.authenticatedScoringSessionIdentifier(),
          expectedAuthorityEpoch: current.authorityEpoch
        )
        guard lease.state != .reconciliationRequired,
              lease.authority_epoch == current.authorityEpoch,
              lease.active_user_id == actorId, lease.active_device_id == deviceId else {
          freezeJournal("Scoring authority changed. Pending plays are frozen for explicit review.")
          continue
        }
        apply(lease)
        if current.hasPendingCommands { await reconcilePendingCommands(service: service) }
      } catch {
        controlToken = nil
        controlState = .disconnected
      }
    }
  }

  private func reloadEvents() async {
    guard let service = appState.supabase, let orgId = appState.activeOrgId else { return }
    if let events = try? await service.listScoringEvents(gameId: game.id, organizationId: orgId),
       let replayed = try? SDGameReducer.replay(events, rules: rules) {
      state = replayed
    }
  }

  private func release(token: String) async {
    try? await appState.supabase?.releaseScorekeepingControl(
      gameId: game.id, deviceId: deviceId, token: token
    )
  }

  private func baseName(_ base: Int) -> String {
    switch base { case 1: "1B"; case 2: "2B"; case 3: "3B"; default: "Home" }
  }
}

private struct Diamond: Shape {
  func path(in rect: CGRect) -> Path {
    var path = Path()
    path.move(to: CGPoint(x: rect.midX, y: rect.minY))
    path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
    path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
    path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
    path.closeSubpath()
    return path
  }
}

enum SDGameDeviceIdentity {
  static var current: UUID {
    let key = "homeplate.gameScoring.deviceId"
    if let raw = UserDefaults.standard.string(forKey: key), let id = UUID(uuidString: raw) {
      return id
    }
    let id = UUID()
    UserDefaults.standard.set(id.uuidString, forKey: key)
    return id
  }
}
