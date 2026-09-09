import HomePlateScoringCore
import SwiftUI

public struct ScoringLabRootView: View {
  @StateObject private var controller = LabGameController()
  @State private var ballDraft: BallInPlayDraft?
  @State private var runnerDraft: RunnerResolutionDraft?
  @State private var showingQA = false
  @State private var playBuilderDetent: PresentationDetent = .medium
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  public init() {}

  public var body: some View {
    ZStack(alignment: .top) {
      HPTheme.ColorToken.background.ignoresSafeArea()
      VStack(spacing: 0) {
        commandBar
        if controller.isReady {
          HPScoreboard(seed: controller.seed, projection: controller.projection)
          workspace
          tabBar
        } else {
          Spacer()
          ProgressView("Opening local scoring ledger…")
            .tint(HPTheme.ColorToken.gold)
            .foregroundStyle(HPTheme.ColorToken.textMuted)
          Spacer()
        }
      }
      if let toast = controller.toastText {
        HPToast(toast)
          .padding(.top, 54)
          .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
          .task(id: toast) {
            try? await Task.sleep(for: .seconds(1.35))
            controller.dismissToast()
          }
      }
    }
    .animation(.easeOut(duration: 0.18), value: controller.toastText)
    .task { await controller.start() }
    .alert("Scoring action unavailable", isPresented: errorIsPresented) {
      Button("OK", role: .cancel) { controller.dismissError() }
    } message: {
      Text(controller.errorText ?? "")
    }
    .sheet(item: standaloneRunnerDraft) { draft in
      HPRunnerResolutionSheet(
        draft: draft,
        player: controller.seed.player(draft.runner.playerID),
        onCancel: { runnerDraft = nil },
        onCommit: { resolution in
          commitRunnerResolution(resolution)
        }
      )
      .presentationDetents([.medium, .large])
    }
    .sheet(isPresented: compactPlayBuilderIsPresented) {
      compactPlayBuilderSheet
    }
    .sheet(isPresented: $showingQA) {
      QAConsoleView(controller: controller)
        .presentationDetents([.medium, .large])
    }
  }

  private var isRegularLayout: Bool {
    horizontalSizeClass == .regular && !dynamicTypeSize.isAccessibilitySize
  }

  private var errorIsPresented: Binding<Bool> {
    Binding<Bool>(
      get: { controller.errorText != nil },
      set: { isPresented in
        if !isPresented { controller.dismissError() }
      }
    )
  }

  private var compactPlayBuilderIsPresented: Binding<Bool> {
    Binding(
      get: { !isRegularLayout && ballDraft != nil },
      set: { isPresented in
        if !isPresented { ballDraft = nil }
      }
    )
  }

  private var compactPlayBuilderSheet: some View {
    ScrollView {
      HPPlayBuilder(
        draft: ballDraftBinding,
        projection: controller.projection,
        seed: controller.seed,
        errorFielderID: ballDraftBinding.wrappedValue.fielders.first.flatMap { controller.player(at: $0)?.id },
        onCancel: { ballDraft = nil },
        onCommit: commitBallInPlay
      )
      .padding(.horizontal, 10)
      .padding(.top, 8)
      .padding(.bottom, 18)
    }
    .scrollIndicators(.hidden)
    .background(HPTheme.ColorToken.background.ignoresSafeArea())
    .presentationDragIndicator(.visible)
    .presentationDetents([Self.fieldInputDetent, .medium, .large], selection: $playBuilderDetent)
    .presentationContentInteraction(.scrolls)
    .presentationBackgroundInteraction(
      isFieldInputStep ? .enabled(upThrough: Self.fieldInputDetent) : .disabled
    )
    .interactiveDismissDisabled()
    .onAppear { updatePlayBuilderDetent(for: ballDraft?.step) }
    .onChange(of: ballDraft?.step) { _, step in updatePlayBuilderDetent(for: step) }
    .sheet(item: compactRunnerDraft) { draft in
      HPRunnerResolutionSheet(
        draft: draft,
        player: controller.seed.player(draft.runner.playerID),
        onCancel: { runnerDraft = nil },
        onCommit: commitRunnerResolution
      )
      .presentationDetents([.medium, .large])
    }
  }

  private static let fieldInputDetent = PresentationDetent.height(236)

  private var isFieldInputStep: Bool {
    ballDraft?.step == .fielders
  }

  private func updatePlayBuilderDetent(for step: BallInPlayStep?) {
    withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.86)) {
      playBuilderDetent = step == .fielders
        ? Self.fieldInputDetent
        : .medium
    }
  }

  private var ballDraftBinding: Binding<BallInPlayDraft> {
    Binding(
      get: { ballDraft ?? BallInPlayDraft() },
      set: { ballDraft = $0 }
    )
  }

  private var standaloneRunnerDraft: Binding<RunnerResolutionDraft?> {
    Binding(
      get: { isRegularLayout || ballDraft == nil ? runnerDraft : nil },
      set: { runnerDraft = $0 }
    )
  }

  private var compactRunnerDraft: Binding<RunnerResolutionDraft?> {
    Binding(
      get: { !isRegularLayout && ballDraft != nil ? runnerDraft : nil },
      set: { runnerDraft = $0 }
    )
  }

  private func commitRunnerResolution(_ resolution: RunnerResolution) {
    runnerDraft = nil
    if ballDraft != nil {
      ballDraft?.appendRunnerResolution(resolution)
    } else {
      Task { try? await controller.advanceRunner(resolution) }
    }
  }

  private func commitBallInPlay(_ command: BallInPlayCommand) {
    Task {
      do {
        try await controller.recordBallInPlay(command)
        ballDraft = nil
      } catch { }
    }
  }

  private var commandBar: some View {
    HStack(spacing: 6) {
      Button { showingQA = true } label: {
        Image(systemName: "slider.horizontal.3")
          .font(.system(size: 16, weight: .semibold))
          .frame(width: 34, height: 34)
          .background(HPTheme.ColorToken.surfaceRaised)
          .clipShape(RoundedRectangle(cornerRadius: 10))
          .frame(width: 44, height: 44)
      }
      .buttonStyle(.plain)
      .foregroundStyle(HPTheme.ColorToken.text)
      .accessibilityLabel("Open QA controls")

      HPStatusBadge(
        controller.projection.status == .final ? "FINAL" : "LIVE",
        kind: controller.projection.status == .final ? .neutral : .success
      )
      Text("\(controller.projection.half == .top ? "TOP" : "BOT") \(controller.projection.inning)")
        .font(HPTheme.FontToken.number(14))
        .foregroundStyle(HPTheme.ColorToken.text)
        .lineLimit(1)
        .minimumScaleFactor(0.85)
      Spacer()
      Button { showingQA = true } label: { HPSyncStatusBanner(state: controller.syncState) }
        .buttonStyle(.plain)
      Button(action: controller.undo) {
        Image(systemName: "arrow.uturn.backward")
          .font(.system(size: 16, weight: .semibold))
          .frame(width: 32, height: 44)
      }
      .buttonStyle(.plain)
      .foregroundStyle(controller.canUndo && controller.pendingHalfInning == nil
        ? HPTheme.ColorToken.text : HPTheme.ColorToken.textMuted.opacity(0.35))
      .disabled(!controller.canUndo || controller.pendingHalfInning != nil)
      .accessibilityLabel("Undo last play")
      Button(action: controller.redo) {
        Image(systemName: "arrow.uturn.forward")
          .font(.system(size: 16, weight: .semibold))
          .frame(width: 32, height: 44)
      }
      .buttonStyle(.plain)
      .foregroundStyle(controller.canRedo && controller.pendingHalfInning == nil
        ? HPTheme.ColorToken.text : HPTheme.ColorToken.textMuted.opacity(0.35))
      .disabled(!controller.canRedo || controller.pendingHalfInning != nil)
      .accessibilityLabel("Redo play")
    }
    .padding(.horizontal, 8)
    .frame(height: HPGameDayLayoutMetrics.commandBarHeight)
    .background(HPTheme.ColorToken.surface)
    .overlay(alignment: .bottom) { Rectangle().fill(HPTheme.ColorToken.border).frame(height: 1) }
  }

  @ViewBuilder private var workspace: some View {
    switch controller.selectedTab {
    case .score:
      ScoreWorkspace(
        controller: controller,
        ballDraft: $ballDraft,
        runnerDraft: $runnerDraft,
        regularLayout: isRegularLayout
      )
    case .lineups:
      LineupsWorkspace(controller: controller, regularLayout: isRegularLayout)
    case .plays:
      PlaysWorkspace(controller: controller)
    case .stats:
      StatisticsWorkspace(controller: controller, regularLayout: isRegularLayout)
    }
  }

  private var tabBar: some View {
    HStack(spacing: 2) {
      ForEach(LabTab.allCases) { tab in
        Button {
          controller.selectedTab = tab
          if tab != .score { ballDraft = nil }
        } label: {
          VStack(spacing: 3) {
            Image(systemName: tab.systemImage).font(.system(size: 18, weight: .semibold))
            Text(tab.rawValue).font(.system(size: 10, weight: .bold))
            Capsule()
              .fill(controller.selectedTab == tab ? HPTheme.ColorToken.gold : Color.clear)
              .frame(width: 24, height: 3)
          }
          .foregroundStyle(controller.selectedTab == tab
            ? HPTheme.ColorToken.text : HPTheme.ColorToken.textMuted)
          .frame(
            maxWidth: .infinity,
            minHeight: HPGameDayLayoutMetrics.tabBarMinimumHeight,
            maxHeight: HPGameDayLayoutMetrics.tabBarMaximumHeight
          )
        }
        .buttonStyle(.plain)
        .disabled(controller.pendingHalfInning != nil && tab != .score)
        .opacity(controller.pendingHalfInning != nil && tab != .score ? 0.42 : 1)
      }
    }
    .padding(.horizontal, 8)
    .background(HPTheme.ColorToken.surface)
    .overlay(alignment: .top) { Rectangle().fill(HPTheme.ColorToken.border).frame(height: 1) }
  }
}

private struct ScoreWorkspace: View {
  @ObservedObject var controller: LabGameController
  @Binding var ballDraft: BallInPlayDraft?
  @Binding var runnerDraft: RunnerResolutionDraft?
  let regularLayout: Bool
  @Environment(\.verticalSizeClass) private var verticalSizeClass

  var body: some View {
    VStack(spacing: 0) {
      HPMatchupStrip(
        batter: controller.currentBatter,
        pitcher: controller.currentPitcher,
        snapshot: controller.snapshot
      )
      if regularLayout {
        HStack(alignment: .top, spacing: 14) {
          field
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
          actionArea
            .frame(width: HPGameDayLayoutMetrics.actionRailWidth)
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
      } else {
        VStack(spacing: 4) {
          field
            .frame(
              maxWidth: .infinity,
              minHeight: HPGameDayLayoutMetrics.compactMinimumFieldHeight,
              maxHeight: .infinity
            )
            .layoutPriority(10)
          actionArea
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, HPGameDayLayoutMetrics.compactHorizontalPadding)
        .padding(.bottom, 4)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private var field: some View {
    HPBaseDiamond(
      seed: controller.seed,
      projection: fieldProjection,
      fieldLayout: fieldLayout,
      selectedFielders: ballDraft?.fielders ?? [],
      selectionEnabled: ballDraft?.step == .fielders,
      onFielderTap: { position in ballDraft?.selectFielder(position) },
      onRunnerDrop: { runner, destination, outcome in
        runnerDraft = .init(
          runner: runner,
          destination: destination,
          outcome: outcome,
          suggestedReason: ballDraft == nil ? .stolenBase : .battedBall
        )
      },
      onRunnerTap: { runner in
        let destination: RunnerDropDestination = runner.base == .third
          ? .home : .base(Base(rawValue: runner.base.rawValue + 1)!)
        runnerDraft = .init(
          runner: runner,
          destination: destination,
          outcome: nil,
          suggestedReason: ballDraft == nil ? .stolenBase : .battedBall
        )
      }
    )
  }

  private var fieldProjection: GameProjection {
    guard let resolutions = ballDraft?.runnerResolutions, !resolutions.isEmpty else {
      return controller.projection
    }
    var preview = controller.projection
    for resolution in resolutions {
      if let from = resolution.fromBase,
         preview.bases[from]?.playerID == resolution.playerID {
        preview.bases[from] = nil
      }
      guard !resolution.isOut, !resolution.scored, let destination = resolution.toBase else { continue }
      preview.bases[destination] = RunnerState(
        playerID: resolution.playerID,
        base: destination,
        responsiblePitcherID: resolution.responsiblePitcherID,
        placedByRule: resolution.reason == .placedRunner
      )
    }
    return preview
  }

  private var fieldLayout: HPFieldLayout {
    guard regularLayout else { return .compactPortrait }
    return verticalSizeClass == .compact ? .regularLandscape : .regularPortrait
  }

  @ViewBuilder private var actionArea: some View {
    if let pending = controller.pendingHalfInning {
      HPHalfInningConfirmationBar(
        pending: pending,
        onCancel: controller.cancelHalfInningConfirmation,
        onConfirm: controller.confirmHalfInning
      )
    } else if regularLayout, ballDraft != nil {
      ScrollView {
        HPPlayBuilder(
          draft: ballDraftBinding,
          projection: controller.projection,
          seed: controller.seed,
          errorFielderID: ballDraftBinding.wrappedValue.fielders.first.flatMap { controller.player(at: $0)?.id },
          onCancel: { ballDraft = nil },
          onCommit: { command in
            Task {
              do {
                try await controller.recordBallInPlay(command)
                ballDraft = nil
              } catch { }
            }
          }
        )
      }
    } else {
      HPPitchActionDock(
        disabled: controller.isBusy || controller.projection.status != .live || ballDraft != nil,
        onPitch: controller.recordPitch,
        onBallInPlay: { ballDraft = BallInPlayDraft() }
      )
    }
  }

  private var ballDraftBinding: Binding<BallInPlayDraft> {
    Binding<BallInPlayDraft>(
      get: { ballDraft ?? BallInPlayDraft() },
      set: { newDraft in ballDraft = newDraft }
    )
  }
}

private struct HPHalfInningConfirmationBar: View {
  let pending: PendingHalfInningTransition
  let onCancel: () -> Void
  let onConfirm: () -> Void

  var body: some View {
    HStack(spacing: 10) {
      Image(systemName: "checkmark.circle.fill")
        .font(.system(size: 21, weight: .bold))
        .foregroundStyle(HPTheme.ColorToken.gold)
      VStack(alignment: .leading, spacing: 2) {
        Text("Confirm inning")
          .font(HPTheme.FontToken.callout.weight(.bold))
          .foregroundStyle(HPTheme.ColorToken.text)
        Text("\(pending.playLabel) ends \(pending.currentLabel) · Next: \(pending.nextLabel)")
          .font(HPTheme.FontToken.caption)
          .foregroundStyle(HPTheme.ColorToken.textMuted)
          .lineLimit(1)
          .minimumScaleFactor(0.72)
      }
      Spacer(minLength: 4)
      Button("Cancel", action: onCancel)
        .buttonStyle(HPSecondaryButtonStyle())
      Button("Confirm Inning", action: onConfirm)
        .buttonStyle(HPPrimaryButtonStyle())
    }
    .padding(8)
    .frame(minHeight: HPGameDayLayoutMetrics.scoringDockHeight)
    .background(HPTheme.ColorToken.surface)
    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    .overlay(RoundedRectangle(cornerRadius: 14).stroke(HPTheme.ColorToken.gold.opacity(0.6)))
    .accessibilityElement(children: .contain)
  }
}

public struct HPLineupList: View {
  let entries: [LineupEntry]
  let currentBatterID: UUID?

  public var body: some View {
    VStack(spacing: 0) {
      ForEach(entries) { entry in
        HStack(spacing: 12) {
          Text("\(entry.battingSlot)")
            .font(HPTheme.FontToken.number(15))
            .foregroundStyle(HPTheme.ColorToken.textMuted)
            .frame(width: 24)
          ZStack {
            Circle().fill(entry.player.isPlaceholder
              ? HPTheme.ColorToken.warning.opacity(0.2)
              : HPTheme.ColorToken.fieldGreen.opacity(0.32))
            Text(entry.player.jerseyNumber)
              .font(HPTheme.FontToken.number(12))
              .foregroundStyle(HPTheme.ColorToken.text)
          }
          .frame(width: 36, height: 36)
          VStack(alignment: .leading, spacing: 2) {
            Text(entry.player.displayName)
              .font(HPTheme.FontToken.callout.weight(.semibold))
              .foregroundStyle(HPTheme.ColorToken.text)
            Text("Bats \(entry.player.bats.rawValue) · Throws \(entry.player.throwsHand.rawValue)")
              .font(HPTheme.FontToken.caption)
              .foregroundStyle(HPTheme.ColorToken.textMuted)
          }
          Spacer()
          if entry.player.id == currentBatterID { HPStatusBadge("AT BAT", kind: .gold) }
          Text(entry.position.rawValue)
            .font(HPTheme.FontToken.badge)
            .foregroundStyle(HPTheme.ColorToken.textTertiary)
            .frame(width: 28)
          Image(systemName: "line.3.horizontal")
            .foregroundStyle(HPTheme.ColorToken.textMuted)
            .accessibilityLabel("Reorder")
        }
        .padding(.vertical, 10)
        if entry.id != entries.last?.id { Divider().overlay(HPTheme.ColorToken.border) }
      }
    }
  }
}

private struct LineupsWorkspace: View {
  @ObservedObject var controller: LabGameController
  let regularLayout: Bool
  @State private var side: TeamSide = .away
  @State private var substitutionPlayer: Player?
  @Environment(\.verticalSizeClass) private var verticalSizeClass

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 14) {
        Picker("Team", selection: $side) {
          Text(controller.seed.away.name).tag(TeamSide.away)
          Text(controller.seed.home.name).tag(TeamSide.home)
        }
        .pickerStyle(.segmented)
        .tint(HPTheme.ColorToken.gold)
        if regularLayout {
          HStack(alignment: .top, spacing: 14) {
            lineupCard.frame(maxWidth: .infinity)
            HPCard {
              VStack(alignment: .leading, spacing: 10) {
                HPSectionLabel("Defensive alignment")
                HPBaseDiamond(
                  seed: controller.seed,
                  projection: alignmentProjection,
                  fieldLayout: verticalSizeClass == .compact ? .regularLandscape : .regularPortrait
                )
              }
            }
            .frame(maxWidth: .infinity)
          }
        } else {
          lineupCard
        }
        HPCard {
          VStack(alignment: .leading, spacing: 10) {
            HPSectionLabel("Bench")
            ForEach(controller.seed.team(side).bench) { player in
              HStack {
                Text("#\(player.jerseyNumber)").font(HPTheme.FontToken.number(14))
                Text(player.displayName).font(HPTheme.FontToken.callout)
                Spacer()
                Button("Substitute") { substitutionPlayer = player }
                  .buttonStyle(HPSecondaryButtonStyle())
              }
              .foregroundStyle(HPTheme.ColorToken.text)
            }
          }
        }
      }
      .padding(14)
    }
    .sheet(item: $substitutionPlayer) { player in
      HPSubstitutionSheet(
        side: side,
        incomingPlayer: player,
        activeLineup: controller.lineup(side),
        onCancel: { substitutionPlayer = nil },
        onCommit: { command in
          substitutionPlayer = nil
          Task { try? await controller.substitute(command) }
        }
      )
      .presentationDetents([.medium, .large])
    }
  }

  private var lineupCard: some View {
    HPCard {
      VStack(alignment: .leading, spacing: 10) {
        HStack {
          HPSectionLabel("Batting order")
          Spacer()
          HPStatusBadge("IN GAME", kind: .success)
        }
        HPLineupList(
          entries: controller.lineup(side),
          currentBatterID: side == controller.projection.offense ? controller.currentBatter?.id : nil
        )
      }
    }
  }

  private var alignmentProjection: GameProjection {
    var value = controller.projection
    value.half = side == .home ? .top : .bottom
    return value
  }
}

private struct HPSubstitutionSheet: View {
  let side: TeamSide
  let incomingPlayer: Player
  let activeLineup: [LineupEntry]
  let onCancel: () -> Void
  let onCommit: (SubstitutionCommand) -> Void
  @State private var outgoingPlayerID: UUID
  @State private var position: DefensivePosition

  init(
    side: TeamSide,
    incomingPlayer: Player,
    activeLineup: [LineupEntry],
    onCancel: @escaping () -> Void,
    onCommit: @escaping (SubstitutionCommand) -> Void
  ) {
    self.side = side
    self.incomingPlayer = incomingPlayer
    self.activeLineup = activeLineup
    self.onCancel = onCancel
    self.onCommit = onCommit
    let first = activeLineup.first
    _outgoingPlayerID = State(initialValue: first?.player.id ?? UUID())
    _position = State(initialValue: first?.position ?? .bench)
  }

  var body: some View {
    NavigationStack {
      VStack(alignment: .leading, spacing: 16) {
        HPCard {
          VStack(alignment: .leading, spacing: 6) {
            HPSectionLabel("Incoming player")
            Text("#\(incomingPlayer.jerseyNumber) · \(incomingPlayer.displayName)")
              .font(HPTheme.FontToken.headline)
              .foregroundStyle(HPTheme.ColorToken.text)
          }
        }
        VStack(alignment: .leading, spacing: 8) {
          HPSectionLabel("Replace")
          Picker("Outgoing player", selection: $outgoingPlayerID) {
            ForEach(activeLineup) { entry in
              Text("\(entry.battingSlot). \(entry.player.displayName) · \(entry.position.rawValue)")
                .tag(entry.player.id)
            }
          }
          .pickerStyle(.menu)
          .tint(HPTheme.ColorToken.gold)
          .onChange(of: outgoingPlayerID) { _, playerID in
            position = defensivePosition(for: playerID) ?? position
          }
        }
        VStack(alignment: .leading, spacing: 8) {
          HPSectionLabel("Defensive role")
          Picker("Position", selection: $position) {
            ForEach(DefensivePosition.allCases, id: \.self) { role in
              Text(role.rawValue).tag(role)
            }
          }
          .pickerStyle(.segmented)
        }
        if position == .pitcher {
          Label(
            "The outgoing pitcher's responsible runners remain attached to the ledger.",
            systemImage: "person.badge.shield.checkmark"
          )
          .font(HPTheme.FontToken.caption)
          .foregroundStyle(HPTheme.ColorToken.gold)
        }
        Text("Eligibility, DH/EH and re-entry rules are checked before this change is durably recorded.")
          .font(HPTheme.FontToken.caption)
          .foregroundStyle(HPTheme.ColorToken.textMuted)
        Spacer()
        Button("Commit Substitution") {
          guard let outgoing = activeLineup.first(where: { $0.player.id == outgoingPlayerID }) else { return }
          onCommit(SubstitutionCommand(
            side: side,
            outgoingPlayerID: outgoing.player.id,
            incomingPlayer: incomingPlayer,
            battingSlot: outgoing.battingSlot,
            position: position
          ))
        }
        .buttonStyle(HPPrimaryButtonStyle())
        .disabled(activeLineup.isEmpty)
      }
      .padding(16)
      .background(HPTheme.ColorToken.background)
      .navigationTitle("Substitution")
      .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: onCancel) } }
    }
  }

  private func defensivePosition(for playerID: UUID) -> DefensivePosition? {
    activeLineup.first { entry in entry.player.id == playerID }?.position
  }
}

public struct HPPlayByPlayRow: View {
  let play: PlaySummary

  public var body: some View {
    HStack(alignment: .top, spacing: 12) {
      ZStack {
        Circle().fill(play.isCorrection
          ? HPTheme.ColorToken.warning.opacity(0.18)
          : HPTheme.ColorToken.fieldGreen.opacity(0.28))
        Image(systemName: play.isCorrection ? "arrow.triangle.2.circlepath" : "baseball.fill")
          .font(.system(size: 13, weight: .bold))
          .foregroundStyle(play.isCorrection ? HPTheme.ColorToken.warning : HPTheme.ColorToken.fieldGlow)
      }
      .frame(width: 38, height: 38)
      VStack(alignment: .leading, spacing: 4) {
        HStack {
          Text(play.text)
            .font(HPTheme.FontToken.callout.weight(.semibold))
            .foregroundStyle(play.isVoided ? HPTheme.ColorToken.textMuted : HPTheme.ColorToken.text)
            .strikethrough(play.isVoided)
          Spacer()
          Text(play.scoreAfter)
            .font(HPTheme.FontToken.number(14))
            .foregroundStyle(HPTheme.ColorToken.gold)
        }
        Text("\(play.half.rawValue.capitalized) \(play.inning) · \(play.outsAfter) out\(play.outsAfter == 1 ? "" : "s") · v\(play.sequence)")
          .font(HPTheme.FontToken.caption)
          .foregroundStyle(HPTheme.ColorToken.textMuted)
      }
    }
    .padding(.vertical, 10)
  }
}

private struct PlaysWorkspace: View {
  @ObservedObject var controller: LabGameController

  var body: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
        ForEach(groupedInnings, id: \.key) { group in
          Section {
            HPCard(elevated: false) {
              VStack(spacing: 0) {
                ForEach(group.value.sorted(by: { $0.sequence > $1.sequence })) { play in
                  HPPlayByPlayRow(play: play)
                  if play.id != group.value.last?.id { Divider().overlay(HPTheme.ColorToken.border) }
                }
              }
            }
          } header: {
            Text(group.key)
              .font(HPTheme.FontToken.eyebrow)
              .foregroundStyle(HPTheme.ColorToken.gold)
              .padding(.vertical, 8)
              .frame(maxWidth: .infinity, alignment: .leading)
              .background(HPTheme.ColorToken.background)
          }
        }
      }
      .padding(.horizontal, 14)
    }
  }

  private var groupedInnings: [(key: String, value: [PlaySummary])] {
    Dictionary(grouping: controller.projection.playSummaries) {
      "\($0.half.rawValue.uppercased()) \($0.inning)"
    }
    .sorted { lhs, rhs in
      (lhs.value.map(\PlaySummary.sequence).max() ?? 0) > (rhs.value.map(\PlaySummary.sequence).max() ?? 0)
    }
  }
}

private enum StatCategory: String, CaseIterable, Identifiable {
  case batting = "Batting"
  case pitching = "Pitching"
  case fielding = "Fielding"
  case team = "Team"
  var id: String { rawValue }
}

private struct StatisticsWorkspace: View {
  @ObservedObject var controller: LabGameController
  let regularLayout: Bool
  @State private var category: StatCategory = .batting
  @State private var side: TeamSide = .away
  @State private var advanced = false
  @State private var exportFiles: [URL] = []

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 12) {
        HStack {
          HPStatusBadge(
            controller.snapshot?.status.rawValue.uppercased() ?? "PROVISIONAL",
            kind: controller.snapshot?.status == .final ? .success : .warning
          )
          Spacer()
          Button {
            exportFiles = (try? controller.exportFiles()) ?? []
          } label: {
            Label("Prepare CSVs", systemImage: "square.and.arrow.up")
          }
          .buttonStyle(HPSecondaryButtonStyle())
        }
        if !exportFiles.isEmpty {
          HPCard(elevated: false) {
            VStack(alignment: .leading, spacing: 8) {
              HPSectionLabel("Four CSV exports ready")
              ForEach(exportFiles, id: \.self) { url in
                ShareLink(item: url) {
                  Label(url.lastPathComponent, systemImage: "doc.text")
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(HPSecondaryButtonStyle())
              }
            }
          }
        }
        Picker("Team", selection: $side) {
          Text(controller.seed.away.name).tag(TeamSide.away)
          Text(controller.seed.home.name).tag(TeamSide.home)
        }
        .pickerStyle(.segmented)
        .tint(HPTheme.ColorToken.gold)
        Picker("Category", selection: $category) {
          ForEach(StatCategory.allCases) { category in Text(category.rawValue).tag(category) }
        }
        .pickerStyle(.segmented)
        .tint(HPTheme.ColorToken.gold)
        if category != .team {
          Picker("Detail", selection: $advanced) {
            Text("Standard").tag(false)
            Text("Advanced").tag(true)
          }
          .pickerStyle(.segmented)
          .tint(HPTheme.ColorToken.gold)
        }
        statContent
        if advanced {
          HPCard(elevated: false) {
            Label(
              "\(controller.environment.name) · \(controller.environment.constantsVersion)",
              systemImage: "checkmark.seal.fill"
            )
            .font(HPTheme.FontToken.caption)
            .foregroundStyle(HPTheme.ColorToken.textMuted)
          }
        }
      }
      .padding(14)
    }
  }

  @ViewBuilder private var statContent: some View {
    switch category {
    case .batting:
      ForEach(controller.snapshot?.batting.filter { $0.team == side } ?? []) { line in
        PlayerStatCard(
          player: controller.seed.player(line.playerID),
          values: advanced ? battingAdvanced(line) : [
            ("PA", "\(line.plateAppearances)"), ("AB", "\(line.atBats)"),
            ("H", "\(line.hits)"), ("RBI", "\(line.runsBattedIn)"),
            ("BB", "\(line.walks)"), ("SO", "\(line.strikeouts)"),
          ]
        )
      }
    case .pitching:
      ForEach(controller.snapshot?.pitching.filter { $0.team == side } ?? []) { line in
        PlayerStatCard(
          player: controller.seed.player(line.playerID),
          values: advanced ? pitchingAdvanced(line) : [
            ("IP", line.inningsPitched), ("P", "\(line.pitches)"),
            ("H", "\(line.hitsAllowed)"), ("ER", "\(line.earnedRuns)"),
            ("BB", "\(line.walks)"), ("SO", "\(line.strikeouts)"),
          ]
        )
      }
    case .fielding:
      ForEach(controller.snapshot?.fielding.filter { $0.team == side } ?? []) { line in
        PlayerStatCard(
          player: controller.seed.player(line.playerID),
          values: advanced ? [
            ("FPCT", format(line.advanced?.fieldingPercentage)),
            ("RF/9", format(line.advanced?.rangeFactorPerNine)),
            ("CS%", format(line.advanced?.caughtStealingPercentage)),
          ] : [
            ("PO", "\(line.putouts)"), ("A", "\(line.assists)"),
            ("E", "\(line.errors)"), ("TC", "\(line.totalChances)"),
            ("DP", "\(line.doublePlays)"), ("PB", "\(line.passedBalls)"),
          ]
        )
      }
    case .team:
      if let totals = controller.snapshot?.teams.first(where: { $0.side == side }) {
        HPCard {
          VStack(alignment: .leading, spacing: 14) {
            Text(controller.seed.team(side).name)
              .font(HPTheme.FontToken.title).foregroundStyle(HPTheme.ColorToken.text)
            StatGrid(values: [
              ("RUNS", "\(totals.runs)"), ("HITS", "\(totals.hits)"),
              ("ERRORS", "\(totals.errors)"), ("LOB", "\(totals.leftOnBase)"),
            ])
          }
        }
      }
    }
  }

  private func battingAdvanced(_ line: BattingLine) -> [(String, String)] {
    let a = line.advanced
    return [
      ("AVG", format(a?.average)), ("OBP", format(a?.onBasePercentage)),
      ("SLG", format(a?.slugging)), ("OPS", format(a?.ops)),
      ("wOBA", format(a?.wOBA)), ("wRC+", format(a?.wRCPlus, decimals: 0)),
    ]
  }

  private func pitchingAdvanced(_ line: PitchingLine) -> [(String, String)] {
    let a = line.advanced
    return [
      ("ERA", format(a?.earnedRunAverage)), ("WHIP", format(a?.whip)),
      ("K/9", format(a?.strikeoutsPerNine)), ("BB/9", format(a?.walksPerNine)),
      ("FIP", format(a?.fip)), ("xFIP", format(a?.xFip)),
    ]
  }

  private func format(_ value: Double?, decimals: Int = 3) -> String {
    guard let value, value.isFinite else { return "Not configured" }
    return String(format: "%.*f", decimals, value)
  }
}

private struct PlayerStatCard: View {
  let player: Player?
  let values: [(String, String)]

  var body: some View {
    HPCard {
      VStack(alignment: .leading, spacing: 12) {
        HStack {
          Text("#\(player?.jerseyNumber ?? "—")")
            .font(HPTheme.FontToken.number(14))
            .foregroundStyle(HPTheme.ColorToken.gold)
          Text(player?.displayName ?? "Unknown Player")
            .font(HPTheme.FontToken.headline)
            .foregroundStyle(HPTheme.ColorToken.text)
        }
        StatGrid(values: values)
      }
    }
  }
}

private struct StatGrid: View {
  let values: [(String, String)]

  var body: some View {
    LazyVGrid(columns: [GridItem(.adaptive(minimum: 82), spacing: 8)], spacing: 8) {
      ForEach(Array(values.enumerated()), id: \.offset) { _, item in
        VStack(spacing: 3) {
          Text(item.0).font(HPTheme.FontToken.eyebrow).foregroundStyle(HPTheme.ColorToken.textMuted)
          Text(item.1)
            .font(HPTheme.FontToken.number(item.1.count > 8 ? 12 : 18))
            .foregroundStyle(item.1 == "Not configured" ? HPTheme.ColorToken.warning : HPTheme.ColorToken.text)
        }
        .frame(maxWidth: .infinity, minHeight: 58)
        .background(HPTheme.ColorToken.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
      }
    }
  }
}

private struct QAStatusCard: View {
  @ObservedObject var controller: LabGameController

  var body: some View {
    HPCard(elevated: false) {
      VStack(alignment: .leading, spacing: 8) {
        HPSectionLabel("Scoring lab status")
        HStack {
          Label("Ledger v\(controller.projection.version)", systemImage: "externaldrive.fill")
          Spacer()
          HPSyncStatusBanner(state: controller.syncState)
        }
        .font(HPTheme.FontToken.caption)
        .foregroundStyle(HPTheme.ColorToken.textMuted)
        Text("Local SQLite/WAL · authority epoch active · mock dashboard publishing")
          .font(HPTheme.FontToken.caption)
          .foregroundStyle(HPTheme.ColorToken.textMuted)
      }
    }
  }
}

private struct QAConsoleView: View {
  @ObservedObject var controller: LabGameController
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 14) {
          HPCard {
            VStack(alignment: .leading, spacing: 12) {
              HPSectionLabel("Connectivity simulator")
              Toggle("Server online", isOn: Binding(
                get: { controller.isOnline },
                set: { isOnline in controller.setOnline(isOnline) }
              ))
              .tint(HPTheme.ColorToken.gold)
              .foregroundStyle(HPTheme.ColorToken.text)
              HPSyncStatusBanner(state: controller.syncState)
              Button("Simulate scorer takeover", action: controller.simulateTakeover)
                .buttonStyle(HPSecondaryButtonStyle())
            }
          }
          HPCard {
            VStack(alignment: .leading, spacing: 9) {
              HPSectionLabel("Deterministic ledger")
              qaRow("Game version", "\(controller.projection.version)")
              qaRow("Immutable events", "\(controller.events.count)")
              qaRow("Rules", "\(controller.rules.name) v\(controller.rules.version)")
              qaRow("Stats", controller.environment.constantsVersion)
              qaRow("Validation", controller.snapshot?.validationIssues.isEmpty == false
                ? controller.snapshot!.validationIssues.joined(separator: ", ") : "Reconciled")
            }
          }
          HPCard {
            VStack(alignment: .leading, spacing: 10) {
              HPSectionLabel("Game control")
              Button("Mark Game Final", action: controller.endGame)
                .buttonStyle(HPSecondaryButtonStyle())
                .disabled(controller.projection.status == .final)
              Text("This affects only the fictional local lab game.")
                .font(HPTheme.FontToken.caption)
                .foregroundStyle(HPTheme.ColorToken.textMuted)
            }
          }
        }
        .padding(16)
      }
      .background(HPTheme.ColorToken.background)
      .navigationTitle("Scoring QA")
      .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
    }
  }

  private func qaRow(_ label: String, _ value: String) -> some View {
    HStack(alignment: .top) {
      Text(label).font(HPTheme.FontToken.caption).foregroundStyle(HPTheme.ColorToken.textMuted)
      Spacer()
      Text(value).font(HPTheme.FontToken.callout.weight(.semibold)).foregroundStyle(HPTheme.ColorToken.text)
        .multilineTextAlignment(.trailing)
    }
  }
}
