import SwiftUI

struct LiveGameScoringView: View {
  @EnvironmentObject private var appState: AppState

  let game: SDGame
  let participants: [SDEventParticipant]

  @State private var state = SDGameState()
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

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      liveHeader
      scoreStrip
      HStack(alignment: .top, spacing: 14) {
        field
        actionPanel
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
    SDLiveScoringAccess.mutationEnabled(
      authorizationAllowsScoring: canScore,
      controlState: controlState
    ) && !isSubmitting
  }

  private var liveHeader: some View {
    HStack(spacing: 10) {
      Circle()
        .fill(controlState.canMutate ? Color.green : Color.orange)
        .frame(width: 10, height: 10)
      VStack(alignment: .leading, spacing: 2) {
        Text(controlState.canMutate ? "Live scorekeeper" : "Live viewer")
          .font(.headline)
        Text("Version \(state.version) • \(state.half.capitalized) \(state.inning)")
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
    .background(runner == nil ? DHDTheme.surface : DHDTheme.accent.opacity(0.25))
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
            await commit(.pitchThrown, payload: [:])
            await commit(action.2, payload: action.3)
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
      Text(pendingRequest == nil
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
    guard let service = appState.supabase, let orgId = appState.activeOrgId else { return }
    rules = SDResolvedBaseballRules.resolve([game.ruleset_snapshot])
    do {
      let events = try await service.listScoringEvents(gameId: game.id, organizationId: orgId)
      state = try SDGameReducer.replay(events, rules: rules)
      if canScore {
        let lease = try await service.acquireScorekeepingControl(
          gameId: game.id, deviceId: deviceId, sessionId: "authenticated-app-session"
        )
        apply(lease)
      } else {
        controlState = .viewer
        try? await service.markGameLiveDevice(gameId: game.id, deviceId: deviceId, state: .liveViewer)
      }
    } catch {
      controlState = .viewer
      errorText = error.localizedDescription
    }
    isLoading = false
  }

  private func apply(_ lease: SDScorekeeperLease) {
    controlToken = lease.control_token
    controlState = lease.state == .liveScorekeeper
      ? .scorekeeper(expiresAt: lease.lease_expires_at)
      : .viewer
  }

  private func commit(_ type: SDScoringEventType, payload: [String: SDJSONValue]) async {
    guard canMutate, let service = appState.supabase, let token = controlToken else { return }
    isSubmitting = true
    defer { isSubmitting = false }
    do {
      let id = UUID()
      let event = try await service.appendScoringEvent(
        game: game, scoringEventId: id, expectedVersion: state.version,
        type: type, deviceId: deviceId, controlToken: token, payload: payload,
        idempotencyKey: "\(game.id.uuidString.lowercased()):\(id.uuidString.lowercased())"
      )
      state = try SDGameReducer.apply(event, to: state, rules: rules)
    } catch {
      await reloadEvents()
      errorText = error.localizedDescription
    }
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
    while !Task.isCancelled, let token = controlToken, controlState.canMutate {
      try? await Task.sleep(for: .seconds(SDScorekeeperLeasePolicy.heartbeatInterval))
      guard !Task.isCancelled else { break }
      do {
        let renewed = try await service.renewScorekeepingControl(
          gameId: game.id, deviceId: deviceId, token: token
        )
        if !renewed {
          controlToken = nil
          controlState = .viewer
          break
        }
      } catch {
        controlToken = nil
        controlState = .disconnected
        break
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

private enum SDGameDeviceIdentity {
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
