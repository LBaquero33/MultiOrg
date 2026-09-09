import HomePlateScoringCore
import HomePlateScoringUI
import SwiftUI

struct ProductionLiveScoringView: View {
  @EnvironmentObject private var appState: AppState
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass
  @StateObject private var controller: ProductionScoringController
  @State private var showingResults = false
  @State private var selectedResult: PlateAppearanceResult?
  @State private var selectedFielders: [DefensivePosition] = []
  @State private var attachedRunnerResolutions: [RunnerResolution] = []
  @State private var safeRunnerDraft: SafeRunnerDraft?
  @State private var tapRunner: RunnerState?

  init(game: SDGame, participants: [SDEventParticipant], canScore: Bool) {
    _controller = StateObject(wrappedValue: ProductionScoringController(
      game: game, participants: participants, canScore: canScore
    ))
  }

  var body: some View {
    ZStack(alignment: .top) {
      Color(hex: 0x0F110C).ignoresSafeArea()
      if controller.isReady {
        VStack(spacing: 0) {
          commandBar
          if let record = controller.recoveryRecord {
            ShareLink(item: record) { Label("Export saved plays for recovery", systemImage: "square.and.arrow.up") }
              .font(.caption).padding(8)
          }
          HPScoreboard(seed: controller.seed, projection: controller.projection)
          HPMatchupStrip(
            batter: controller.currentBatter,
            pitcher: controller.currentPitcher,
            snapshot: controller.snapshot
          )
          workspace
        }
      } else {
        ProgressView("Opening the durable scoring ledger…")
          .tint(Color(hex: 0xD6B370))
          .foregroundStyle(Color(hex: 0xECE8DD))
          .frame(maxWidth: .infinity, minHeight: 480)
      }
      if let toast = controller.toastText {
        Text(toast)
          .font(.caption.bold())
          .foregroundStyle(Color(hex: 0xECE8DD))
          .padding(.horizontal, 14).padding(.vertical, 8)
          .background(Color(hex: 0x262B21))
          .clipShape(Capsule())
          .padding(.top, 48)
          .task(id: toast) {
            try? await Task.sleep(for: .seconds(1.25))
            controller.toastText = nil
          }
      }
    }
    .task {
      if let service = appState.supabase, let account = appState.myProfile?.id {
        await controller.start(service: service, accountID: account) {
          appState.myProfile?.id == account && appState.activeOrgId == controller.game.org_id
        }
      }
    }
    .sheet(isPresented: $showingResults) { resultSheet }
    .sheet(item: $safeRunnerDraft) { draft in safeRunnerSheet(draft) }
    .confirmationDialog("Runner actions", isPresented: Binding(
      get: { tapRunner != nil }, set: { if !$0 { tapRunner = nil } }
    )) {
      if let runner = tapRunner {
        if let destination = nextDestination(after: runner.base) {
          Button("SAFE at \(destinationLabel(destination))") {
            safeRunnerDraft = SafeRunnerDraft(runner: runner, destination: destination)
            tapRunner = nil
          }
          Button("OUT advancing") {
            resolveRunner(runner, destination: destination, outcome: .out, reason: .caughtStealing)
            tapRunner = nil
          }
        }
      }
      Button("Cancel", role: .cancel) { tapRunner = nil }
    } message: { Text("The tap menu is the accessible alternative to dragging.") }
    .alert("Scoring action unavailable", isPresented: Binding(
      get: { controller.errorText != nil },
      set: { if !$0 { controller.dismissError() } }
    )) { Button("OK", role: .cancel) {} } message: { Text(controller.errorText ?? "") }
  }

  private var commandBar: some View {
    HStack(spacing: 8) {
      Text(controller.projection.status == .final ? "FINAL" : "LIVE")
        .font(.system(size: 10, weight: .black, design: .rounded))
        .foregroundStyle(.white)
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(controller.projection.status == .final ? Color.gray : Color(hex: 0x2E7D57))
        .clipShape(Capsule())
      Text("\(controller.projection.half == .top ? "TOP" : "BOT") \(controller.projection.inning)")
        .font(.system(size: 13, weight: .black, design: .monospaced))
        .foregroundStyle(Color(hex: 0xECE8DD))
      Spacer()
      HPSyncStatusBanner(state: controller.syncState)
      Button(action: controller.undo) { Image(systemName: "arrow.uturn.backward").frame(width: 30, height: 44) }
        .disabled(!controller.canMutate || !controller.canUndo || controller.pendingHalfInning != nil)
        .accessibilityLabel("Undo last play")
      Button(action: controller.redo) { Image(systemName: "arrow.uturn.forward").frame(width: 30, height: 44) }
        .disabled(!controller.canMutate || !controller.canRedo || controller.pendingHalfInning != nil)
        .accessibilityLabel("Redo last play")
    }
    .buttonStyle(.plain)
    .foregroundStyle(Color(hex: 0xECE8DD))
    .padding(.horizontal, 8)
    .frame(height: 44)
    .background(Color(hex: 0x1A1E16))
  }

  @ViewBuilder private var workspace: some View {
    if horizontalSizeClass == .regular {
      HStack(alignment: .top, spacing: 14) {
        field.frame(maxWidth: .infinity)
        actionRail.frame(width: 350)
      }
      .padding(12)
    } else {
      VStack(spacing: 8) {
        field.frame(minHeight: 390)
        actionRail
      }
      .padding(.horizontal, 6).padding(.vertical, 8)
    }
  }

  private var field: some View {
    HPBaseDiamond(
      seed: controller.seed,
      projection: controller.projection,
      fieldLayout: horizontalSizeClass == .regular ? .regularLandscape : .compactPortrait,
      selectedFielders: selectedFielders,
      selectionEnabled: selectedResult != nil,
      locationEnabled: false,
      onFielderTap: toggleFielder,
      onRunnerDrop: { runner, destination, outcome in
        if outcome == .safe { safeRunnerDraft = SafeRunnerDraft(runner: runner, destination: destination) }
        else { resolveRunner(runner, destination: destination, outcome: .out, reason: .caughtStealing) }
      },
      onRunnerTap: { tapRunner = $0 }
    )
    .aspectRatio(horizontalSizeClass == .regular ? 1.28 : 0.88, contentMode: .fit)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  @ViewBuilder private var actionRail: some View {
    VStack(spacing: 10) {
      if let pending = controller.pendingHalfInning {
        VStack(alignment: .leading, spacing: 10) {
          Text("HALF INNING COMPLETE")
            .font(.system(size: 10, weight: .black, design: .rounded))
            .tracking(0.8).foregroundStyle(Color(hex: 0xD6B370))
          Text(pending).font(.headline).foregroundStyle(Color(hex: 0xECE8DD))
          Text("The third-out play has not been committed yet. Confirm after checking the result and score.")
            .font(.caption).foregroundStyle(Color(hex: 0xA6A394))
          Button("Confirm inning", action: controller.confirmHalfInning)
            .buttonStyle(GoldButtonStyle())
            .disabled(!controller.canMutate)
          Button("Edit third-out play", role: .cancel, action: controller.cancelHalfInning)
            .font(.caption.bold()).foregroundStyle(Color(hex: 0xA6A394))
        }
        .padding(14).background(Color(hex: 0x1A1E16)).clipShape(RoundedRectangle(cornerRadius: 16))
      } else if let result = selectedResult {
        VStack(alignment: .leading, spacing: 10) {
          HStack {
            VStack(alignment: .leading, spacing: 2) {
              Text("BALL IN PLAY").font(.system(size: 10, weight: .black)).foregroundStyle(Color(hex: 0xD6B370))
              Text(result.title).font(.title3.bold()).foregroundStyle(Color(hex: 0xECE8DD))
            }
            Spacer()
            Button("Cancel", action: resetPlayBuilder).font(.caption.bold())
          }
          Text("Tap fielders in touch order. Drag any existing runners to SAFE or OUT before recording.")
            .font(.caption).foregroundStyle(Color(hex: 0xA6A394))
          Text(selectedFielders.isEmpty ? "Waiting for fielders" : selectedFielders.enumerated().map { "\($0.offset + 1). \($0.element.rawValue)" }.joined(separator: "  →  "))
            .font(.caption.monospaced()).foregroundStyle(Color(hex: 0xD6B370))
            .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
            .padding(.horizontal, 10).background(Color(hex: 0x262B21)).clipShape(RoundedRectangle(cornerRadius: 10))
          Button("Record play") { recordBallInPlay(result) }
            .buttonStyle(GoldButtonStyle())
            .disabled(!controller.canMutate || (result.recordsBatterOut && selectedFielders.isEmpty))
        }
        .padding(12).background(Color(hex: 0x1A1E16)).clipShape(RoundedRectangle(cornerRadius: 16))
      } else {
        HPPitchActionDock(
          disabled: !controller.canMutate,
          onPitch: controller.recordPitch,
          onBallInPlay: { showingResults = true }
        )
      }
    }
  }

  private var resultSheet: some View {
    NavigationStack {
      ScrollView {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
          ForEach(playResults) { result in
            Button(result.title) {
              selectedResult = result
              selectedFielders = []
              attachedRunnerResolutions = []
              showingResults = false
            }
            .buttonStyle(ResultButtonStyle())
          }
        }
        .padding(14)
      }
      .background(Color(hex: 0x0F110C))
      .navigationTitle("Play result")
      .toolbar { Button("Cancel") { showingResults = false } }
    }
    .presentationDetents([.height(280)])
    .presentationBackgroundInteraction(.enabled)
  }

  private func safeRunnerSheet(_ draft: SafeRunnerDraft) -> some View {
    NavigationStack {
      List(safeReasons) { reason in
        Button(reason.title) {
          resolveRunner(draft.runner, destination: draft.destination, outcome: .safe, reason: reason)
          safeRunnerDraft = nil
        }
      }
      .navigationTitle("Runner is SAFE")
      .safeAreaInset(edge: .top) {
        Text("How did the runner advance?")
          .font(.caption)
          .foregroundStyle(Color(hex: 0xA6A394))
      }
      .toolbar { Button("Cancel") { safeRunnerDraft = nil } }
    }
    .presentationDetents([.medium])
  }

  private func toggleFielder(_ position: DefensivePosition) {
    if let index = selectedFielders.firstIndex(of: position) { selectedFielders.remove(at: index) }
    else { selectedFielders.append(position) }
  }

  private func recordBallInPlay(_ result: PlateAppearanceResult) {
    controller.recordBallInPlay(BallInPlayCommand(
      contact: result == .sacrificeBunt ? .bunt : result.recordsBatterOut ? .groundBall : .lineDrive,
      result: result,
      fielderSequence: selectedFielders,
      runnerResolutions: attachedRunnerResolutions,
      runsBattedIn: attachedRunnerResolutions.filter { $0.scored && $0.reason == .battedBall }.count,
      errorFielderID: result == .reachedOnError ? selectedFielders.first.flatMap(playerID(at:)) : nil
    ))
    resetPlayBuilder()
  }

  private func resolveRunner(
    _ runner: RunnerState,
    destination: RunnerDropDestination,
    outcome: RunnerDropOutcome,
    reason: RunnerAdvanceReason
  ) {
    let resolution = RunnerResolution(
      playerID: runner.playerID,
      fromBase: runner.base,
      toBase: destination.base,
      scored: destination == .home && outcome == .safe,
      isOut: outcome == .out,
      reason: selectedResult == nil ? reason : .battedBall,
      responsiblePitcherID: runner.responsiblePitcherID
    )
    if selectedResult != nil {
      attachedRunnerResolutions.removeAll { $0.playerID == runner.playerID }
      attachedRunnerResolutions.append(resolution)
    } else {
      controller.advanceRunner(resolution)
    }
  }

  private func playerID(at position: DefensivePosition) -> UUID? {
    controller.projection.lineups[controller.projection.defense]?
      .first(where: { $0.position == position && $0.exitedAtSequence == nil })?.player.id
  }
  private func resetPlayBuilder() { selectedResult = nil; selectedFielders = []; attachedRunnerResolutions = [] }
  private func nextDestination(after base: Base) -> RunnerDropDestination? { base == .third ? .home : Base(rawValue: base.rawValue + 1).map(RunnerDropDestination.base) }
  private func destinationLabel(_ destination: RunnerDropDestination) -> String { destination == .home ? "Home" : destination.base?.label ?? "Base" }

  private let playResults: [PlateAppearanceResult] = [
    .out, .single, .double, .triple, .homeRun,
    .reachedOnError, .fieldersChoice, .sacrificeBunt, .sacrificeFly,
  ]
  private let safeReasons: [RunnerAdvanceReason] = [
    .stolenBase, .defensiveIndifference, .wildPitch, .passedBall,
    .balk, .fieldingError, .other,
  ]
}

private struct SafeRunnerDraft: Identifiable {
  let id = UUID()
  let runner: RunnerState
  let destination: RunnerDropDestination
}

private extension RunnerDropDestination {
  var base: Base? { if case .base(let base) = self { base } else { nil } }
}

private struct GoldButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.headline).frame(maxWidth: .infinity, minHeight: 48)
      .foregroundStyle(Color(hex: 0x11130E))
      .background(Color(hex: 0xD6B370).opacity(configuration.isPressed ? 0.8 : 1))
      .clipShape(RoundedRectangle(cornerRadius: 12))
  }
}

private struct ResultButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.caption.bold()).foregroundStyle(Color(hex: 0xECE8DD))
      .frame(maxWidth: .infinity, minHeight: 56)
      .background(Color(hex: 0x262B21).opacity(configuration.isPressed ? 0.7 : 1))
      .clipShape(RoundedRectangle(cornerRadius: 12))
  }
}
