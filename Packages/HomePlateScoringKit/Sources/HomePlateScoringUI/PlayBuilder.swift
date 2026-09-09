import HomePlateScoringCore
import SwiftUI

enum BallInPlayStep: String, CaseIterable {
  case contact = "Contact"
  case result = "Result"
  case fielders = "Fielders"
}

struct BallInPlayDraft: Equatable {
  var step: BallInPlayStep = .contact
  var contact: ContactType?
  var result: PlateAppearanceResult?
  var fielders: [DefensivePosition] = []
  var runnerResolutions: [RunnerResolution] = []
  var note = ""

  var breadcrumb: String {
    [contact?.title, result?.title, fieldingText].compactMap { value in
      guard let value, !value.isEmpty else { return nil }
      return value
    }.joined(separator: "  ›  ")
  }

  var fieldingText: String? {
    let numbers = fielders.compactMap(\DefensivePosition.number).map(String.init)
    return numbers.isEmpty ? nil : numbers.joined(separator: "–")
  }

  mutating func selectFielder(_ position: DefensivePosition) {
    if let index = fielders.firstIndex(of: position) {
      fielders.remove(at: index)
    } else {
      fielders.append(position)
    }
  }

  mutating func appendRunnerResolution(_ resolution: RunnerResolution) {
    if let index = runnerResolutions.firstIndex(where: { $0.playerID == resolution.playerID }) {
      let original = runnerResolutions[index]
      runnerResolutions[index] = RunnerResolution(
        playerID: resolution.playerID,
        fromBase: original.fromBase,
        toBase: resolution.toBase,
        scored: resolution.scored,
        isOut: resolution.isOut,
        reason: resolution.reason,
        responsiblePitcherID: resolution.responsiblePitcherID,
        earned: resolution.earned
      )
    } else {
      runnerResolutions.append(resolution)
    }
  }

}

struct HPPlayBuilder: View {
  @Binding var draft: BallInPlayDraft
  let projection: GameProjection
  let seed: GameSeed
  let errorFielderID: UUID?
  let onCancel: () -> Void
  let onCommit: (BallInPlayCommand) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        VStack(alignment: .leading, spacing: 2) {
          HPSectionLabel("Ball in play")
          Text(draft.step.rawValue)
            .font(HPTheme.FontToken.title)
            .foregroundStyle(HPTheme.ColorToken.text)
        }
        Spacer()
        Text("\(stepIndex + 1)/\(BallInPlayStep.allCases.count)")
          .font(HPTheme.FontToken.number(13))
          .foregroundStyle(HPTheme.ColorToken.textMuted)
        Button(action: onCancel) {
          Image(systemName: "xmark").frame(width: 32, height: 32)
        }
        .buttonStyle(.plain)
        .foregroundStyle(HPTheme.ColorToken.textTertiary)
        .accessibilityLabel("Cancel play")
      }

      progress
      if !draft.breadcrumb.isEmpty {
        Text(draft.breadcrumb)
          .font(HPTheme.FontToken.caption)
          .foregroundStyle(HPTheme.ColorToken.gold)
          .lineLimit(2)
      }

      Group {
        switch draft.step {
        case .contact: contactStep
        case .result: resultStep
        case .fielders: fieldersStep
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(14)
    .background(HPTheme.ColorToken.surface)
    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    .overlay(RoundedRectangle(cornerRadius: 18).stroke(HPTheme.ColorToken.borderStrong))
  }

  private var progress: some View {
    GeometryReader { proxy in
      ZStack(alignment: .leading) {
        Capsule().fill(HPTheme.ColorToken.surfaceRaised)
        Capsule().fill(HPTheme.ColorToken.gold)
          .frame(width: proxy.size.width * CGFloat(stepIndex + 1) / CGFloat(BallInPlayStep.allCases.count))
      }
    }
    .frame(height: 4)
  }

  private var contactStep: some View {
    optionGrid(ContactType.allCases, title: \ContactType.title) { contact in
      draft.contact = contact
      draft.step = .result
    }
  }

  private var resultStep: some View {
    let values: [PlateAppearanceResult] = [
      .out, .single, .double, .triple, .homeRun,
      .reachedOnError, .fieldersChoice, .sacrificeBunt, .sacrificeFly,
    ]
    return optionGrid(values, title: \PlateAppearanceResult.title) { result in
      draft.result = result
      draft.step = .fielders
    }
  }

  private var fieldersStep: some View {
    VStack(alignment: .leading, spacing: 10) {
      Label("Tap fielders on the diamond in touch order.", systemImage: "hand.tap")
        .font(HPTheme.FontToken.callout)
        .foregroundStyle(HPTheme.ColorToken.textTertiary)
      if !draft.runnerResolutions.isEmpty {
        Label(
          "\(draft.runnerResolutions.count) runner movement\(draft.runnerResolutions.count == 1 ? "" : "s") attached",
          systemImage: "figure.run"
        )
        .font(HPTheme.FontToken.caption)
        .foregroundStyle(HPTheme.ColorToken.gold)
      }
      if let occupied = blockingRunner {
        Label(
          "Drag \(seed.player(occupied.playerID)?.shortName ?? "the runner") off \(occupied.base.label) before recording.",
          systemImage: "exclamationmark.triangle.fill"
        )
        .font(HPTheme.FontToken.caption)
        .foregroundStyle(HPTheme.ColorToken.warning)
      }
      if draft.fielders.isEmpty {
        Text("No fielders selected")
          .font(HPTheme.FontToken.caption)
          .foregroundStyle(HPTheme.ColorToken.textMuted)
      } else {
        HStack(spacing: 6) {
          ForEach(Array(draft.fielders.enumerated()), id: \.offset) { index, position in
            Text("\(index + 1) · \(position.rawValue)")
              .font(HPTheme.FontToken.badge)
              .foregroundStyle(HPTheme.ColorToken.gold)
              .padding(.horizontal, 8).padding(.vertical, 5)
              .background(HPTheme.ColorToken.gold.opacity(0.12))
              .clipShape(Capsule())
          }
        }
      }
      HStack {
        Button("Back") { draft.step = .result }.buttonStyle(HPSecondaryButtonStyle())
        Button {
          guard let contact = draft.contact, let result = draft.result else { return }
          onCommit(BallInPlayCommand(
            contact: contact,
            result: result,
            fielderSequence: draft.fielders,
            runnerResolutions: draft.runnerResolutions,
            runsBattedIn: draft.runnerResolutions.filter { $0.scored && $0.reason == .battedBall }.count,
            errorFielderID: result == .reachedOnError ? errorFielderID : nil,
            note: draft.note
          ))
        } label: {
          Label("Record Play", systemImage: "checkmark.circle.fill")
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(HPPrimaryButtonStyle())
        .disabled(blockingRunner != nil)
        .opacity(blockingRunner == nil ? 1 : 0.42)
      }
    }
  }

  private var blockingRunner: RunnerState? {
    guard let result = draft.result else { return nil }
    let destination: Base?
    if let base = Base(rawValue: result.basesAwarded) {
      destination = base
    } else if result == .reachedOnError || result == .fieldersChoice {
      destination = .first
    } else {
      destination = nil
    }
    guard let destination, let occupant = projection.bases[destination] else { return nil }
    return draft.runnerResolutions.contains(where: {
      $0.playerID == occupant.playerID && $0.fromBase == destination
    }) ? nil : occupant
  }

  private var stepIndex: Int { BallInPlayStep.allCases.firstIndex(of: draft.step) ?? 0 }

  private func optionGrid<Value: Identifiable>(
    _ values: [Value],
    title: KeyPath<Value, String>,
    action: @escaping (Value) -> Void
  ) -> some View {
    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
      ForEach(values) { value in
        Button(value[keyPath: title]) { action(value) }
          .buttonStyle(HPSecondaryButtonStyle())
      }
    }
  }
}

struct RunnerResolutionDraft: Identifiable {
  let id = UUID()
  let runner: RunnerState
  let destination: RunnerDropDestination
  let outcome: RunnerDropOutcome?
  let suggestedReason: RunnerAdvanceReason
}

struct HPRunnerResolutionSheet: View {
  let draft: RunnerResolutionDraft
  let player: Player?
  let onCancel: () -> Void
  let onCommit: (RunnerResolution) -> Void

  @State private var isOut: Bool
  @State private var reason: RunnerAdvanceReason = .stolenBase

  init(
    draft: RunnerResolutionDraft,
    player: Player?,
    onCancel: @escaping () -> Void,
    onCommit: @escaping (RunnerResolution) -> Void
  ) {
    self.draft = draft
    self.player = player
    self.onCancel = onCancel
    self.onCommit = onCommit
    _isOut = State(initialValue: draft.outcome == .out)
    _reason = State(initialValue: draft.suggestedReason)
  }

  var body: some View {
    NavigationStack {
      VStack(alignment: .leading, spacing: 18) {
        VStack(alignment: .leading, spacing: 4) {
          HPSectionLabel("Runner decision")
          Text(player?.displayName ?? "Runner")
            .font(HPTheme.FontToken.title)
            .foregroundStyle(HPTheme.ColorToken.text)
          Text("\(draft.runner.base.label) → \(destinationLabel)")
            .font(HPTheme.FontToken.callout)
            .foregroundStyle(HPTheme.ColorToken.textMuted)
        }
        if draft.outcome == nil {
          Picker("Result", selection: $isOut) {
            Text("SAFE").tag(false)
            Text("OUT").tag(true)
          }
          .pickerStyle(.segmented)
        } else {
          HPStatusBadge(isOut ? "OUT" : "SAFE", kind: isOut ? .danger : .success)
        }
        if !isOut {
          VStack(alignment: .leading, spacing: 8) {
            HPSectionLabel("How did the runner advance?")
            #if os(iOS)
            Picker("Reason", selection: $reason) {
              ForEach(safeReasons) { reason in Text(reason.title).tag(reason) }
            }
            .pickerStyle(.wheel)
            .frame(maxHeight: 180)
            #else
            Picker("Reason", selection: $reason) {
              ForEach(safeReasons) { reason in Text(reason.title).tag(reason) }
            }
            .pickerStyle(.menu)
            #endif
          }
        }
        Spacer()
        Button {
          let destinationBase: Base?
          let scored: Bool
          switch draft.destination {
          case .base(let base): destinationBase = base; scored = false
          case .home: destinationBase = nil; scored = !isOut
          }
          onCommit(RunnerResolution(
            playerID: draft.runner.playerID,
            fromBase: draft.runner.base,
            toBase: destinationBase,
            scored: scored,
            isOut: isOut,
            reason: isOut ? .caughtStealing : reason,
            responsiblePitcherID: draft.runner.responsiblePitcherID,
            earned: draft.runner.placedByRule ? false : nil
          ))
        } label: {
          Label("Record Runner", systemImage: "checkmark.circle.fill")
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(HPPrimaryButtonStyle())
      }
      .padding(20)
      .background(HPTheme.ColorToken.background.ignoresSafeArea())
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: onCancel) }
      }
    }
  }

  private var destinationLabel: String {
    switch draft.destination {
    case .base(let base): base.label
    case .home: "Home"
    }
  }

  private var safeReasons: [RunnerAdvanceReason] {
    RunnerAdvanceReason.allCases.filter { ![.caughtStealing, .pickoff].contains($0) }
  }
}
