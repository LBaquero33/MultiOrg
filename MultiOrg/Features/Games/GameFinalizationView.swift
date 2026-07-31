import SwiftUI

struct GameFinalizationView: View {
  @EnvironmentObject private var appState: AppState

  let game: SDGame
  let permissions: SDGameWorkspacePermissions
  let onFinalized: () async -> Void

  @State private var events: [SDScoringEvent] = []
  @State private var decisions: [SDGameScoringDecision] = []
  @State private var state = SDGameState()
  @State private var statistics = SDOfficialGameStatistics()
  @State private var report = SDGameValidationReport(
    issues: [], gameVersion: 0, homeScore: 0, awayScore: 0, unresolvedDecisionCount: 0
  )
  @State private var controlToken: String?
  @State private var isLoading = true
  @State private var isFinalizing = false
  @State private var correctionDecision: SDGameScoringDecision?
  @State private var correctionValue = ""
  @State private var correctionReason = ""
  @State private var errorText: String?
  @State private var successText: String?

  private let deviceId = SDGameDeviceIdentity.current

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text(game.status == .final ? "Final game record" : "Finalization checklist")
          .font(.headline)
        Spacer()
        if isLoading || isFinalizing { ProgressView() }
      }

      score

      if report.issues.isEmpty {
        Label("Ledger and official statistics are ready.", systemImage: "checkmark.seal.fill")
          .foregroundStyle(.green)
      } else {
        ForEach(report.issues) { issue in
          Label(issue.message, systemImage: "exclamationmark.triangle.fill")
            .font(.footnote).foregroundStyle(issue.blocking ? .orange : DHDTheme.textSecondary)
        }
      }

      if game.status == .final {
        finalDecisionHistory
      } else if permissions.canFinalize {
        Button {
          Task { await finalize() }
        } label: {
          Label("Finalize official game", systemImage: "checkmark.seal")
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .disabled(!report.canFinalize || controlToken == nil || isFinalizing)
      } else {
        Label("Only an organization administrator or assigned scorekeeper can finalize.",
              systemImage: "lock.fill")
          .font(.footnote).foregroundStyle(DHDTheme.textSecondary)
      }
    }
    .task(id: game.game_version) { await load() }
    .sheet(item: $correctionDecision) { decision in
      correctionSheet(decision)
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 360)
        #endif
    }
    .alert("Game finalization", isPresented: Binding(
      get: { errorText != nil }, set: { if !$0 { errorText = nil } }
    )) { Button("OK", role: .cancel) {} } message: { Text(errorText ?? "") }
    .alert("Game updated", isPresented: Binding(
      get: { successText != nil }, set: { if !$0 { successText = nil } }
    )) { Button("OK", role: .cancel) {} } message: { Text(successText ?? "") }
  }

  private var score: some View {
    HStack {
      teamScore(game.away_team_name, report.awayScore)
      Text("–").font(.title2).foregroundStyle(DHDTheme.textSecondary)
      teamScore(game.home_team_name, report.homeScore)
    }
  }

  private func teamScore(_ team: String, _ value: Int) -> some View {
    VStack(spacing: 2) {
      Text(team).font(.caption).lineLimit(1)
      Text("\(value)").font(.title2.bold())
    }
    .frame(maxWidth: .infinity)
  }

  @ViewBuilder
  private var finalDecisionHistory: some View {
    if decisions.isEmpty {
      Text("No official scorer decisions require correction.")
        .foregroundStyle(DHDTheme.textSecondary)
    }
    ForEach(currentDecisions) { decision in
      HStack {
        VStack(alignment: .leading, spacing: 2) {
          Text(decision.decision_type.replacingOccurrences(of: "_", with: " ").capitalized)
          Text(decision.effectiveValue?.replacingOccurrences(of: "_", with: " ").capitalized ?? "Pending")
            .font(.caption).foregroundStyle(DHDTheme.textSecondary)
        }
        Spacer()
        if permissions.canFinalize {
          Button("Correct") {
            correctionValue = decision.effectiveValue ?? ""
            correctionReason = ""
            correctionDecision = decision
          }
        }
      }
      Divider()
    }
  }

  private var currentDecisions: [SDGameScoringDecision] {
    decisions.filter { $0.decision_status != "superseded" }
  }

  private func correctionSheet(_ decision: SDGameScoringDecision) -> some View {
    NavigationStack {
      Form {
        TextField("Official result", text: $correctionValue)
        TextField("Reason for correction", text: $correctionReason, axis: .vertical)
      }
      .navigationTitle("Correct Scoring Decision")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { correctionDecision = nil }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Apply Correction") {
            Task { await correct(decision) }
          }
          .disabled(
            correctionValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            correctionReason.trimmingCharacters(in: .whitespacesAndNewlines).count < 3
          )
        }
      }
    }
  }

  private func load() async {
    guard let service = appState.supabase, let orgId = appState.activeOrgId else { return }
    isLoading = true
    defer { isLoading = false }
    do {
      async let eventLoad = service.listScoringEvents(gameId: game.id, organizationId: orgId)
      async let decisionLoad = service.listGameScoringDecisions(gameId: game.id, organizationId: orgId)
      events = try await eventLoad
      decisions = try await decisionLoad
      state = try SDGameReducer.replay(
        events, rules: SDResolvedBaseballRules.resolve([game.ruleset_snapshot])
      )
      statistics = SDOfficialScoringEngine.derive(events: events, decisions: decisions)
      report = SDGameFinalizationValidator.validate(
        game: game, state: state, events: events, statistics: statistics
      )
      if game.status != .final, permissions.canFinalize {
        let lease = try await service.acquireScorekeepingControl(
          gameId: game.id, deviceId: deviceId, sessionId: "authenticated-app-session"
        )
        controlToken = lease.state == .liveScorekeeper ? lease.control_token : nil
      }
    } catch {
      errorText = error.localizedDescription
    }
  }

  private func finalize() async {
    guard let service = appState.supabase, let token = controlToken, report.canFinalize else {
      errorText = "No active scorekeeping control is available for finalization."
      return
    }
    isFinalizing = true
    defer { isFinalizing = false }
    do {
      let key = "\(game.id.uuidString.lowercased()):final:\(state.version)"
      _ = try await service.finalizeGame(
        gameId: game.id, expectedVersion: state.version, deviceId: deviceId,
        controlToken: token, idempotencyKey: key,
        statistics: statistics, validation: report
      )
      controlToken = nil
      successText = "The official game record is final."
      await onFinalized()
    } catch {
      errorText = error.localizedDescription
    }
  }

  private func correct(_ decision: SDGameScoringDecision) async {
    guard let service = appState.supabase else { return }
    do {
      let replacement = SDGameScoringDecision(
        id: UUID(), org_id: decision.org_id, game_id: decision.game_id,
        physical_event_id: decision.physical_event_id,
        root_decision_id: decision.root_decision_id,
        supersedes_decision_id: decision.id, decision_type: decision.decision_type,
        preliminary_value: nil,
        final_value: correctionValue.trimmingCharacters(in: .whitespacesAndNewlines),
        decision_status: "final", rule_reference: decision.rule_reference,
        reasoning_note: correctionReason.trimmingCharacters(in: .whitespacesAndNewlines),
        review_requested: false,
        decision_maker_id: appState.myProfile?.id ?? decision.decision_maker_id,
        created_at: Date(), finalized_at: Date()
      )
      let correctedStatistics = SDOfficialScoringEngine.derive(
        events: events, decisions: decisions + [replacement]
      )
      let correctedReport = SDGameFinalizationValidator.validate(
        game: game, state: state, events: events, statistics: correctedStatistics
      )
      guard correctedReport.canFinalize else {
        errorText = correctedReport.issues.map(\.message).joined(separator: "\n")
        return
      }
      let key = "\(game.id.uuidString.lowercased()):correct:\(decision.id.uuidString.lowercased()):\(UUID().uuidString.lowercased())"
      _ = try await service.correctFinalGameDecision(
        gameId: game.id, supersededDecisionId: decision.id,
        replacementValue: correctionValue.trimmingCharacters(in: .whitespacesAndNewlines),
        reason: correctionReason.trimmingCharacters(in: .whitespacesAndNewlines),
        idempotencyKey: key, statistics: correctedStatistics, validation: correctedReport
      )
      correctionDecision = nil
      successText = "The correction was appended to the official record."
      await load()
      await onFinalized()
    } catch {
      errorText = error.localizedDescription
    }
  }
}
