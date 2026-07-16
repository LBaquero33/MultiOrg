import SwiftUI

@MainActor
final class PlayerDevelopmentPlayerWorkspaceModel: ObservableObject {
  enum Phase: Equatable { case idle, loading, loaded, failed(String) }
  enum GenerationPhase: Equatable { case idle, generating, succeeded(String), failed(String) }

  @Published private(set) var phase: Phase = .idle
  @Published private(set) var generationPhase: GenerationPhase = .idle
  @Published private(set) var response: SDPlayerDevelopmentWorkspaceResponse?
  @Published private(set) var reports: [SDDevelopmentReport] = []
  @Published private(set) var alerts: [SDDevelopmentAlert] = []
  private var token: SDCopilotContextToken?
  private var generationKey: UUID?

  func reset() {
    token = nil
    response = nil
    reports = []
    alerts = []
    generationPhase = .idle
    generationKey = nil
    phase = .idle
  }

  func load(
    client: any PlayerDevelopmentCopilotClient,
    organizationId: UUID,
    userId: UUID,
    playerId: UUID
  ) async {
    guard userId == playerId else {
      reset()
      phase = .failed("Player Development is available only for your own profile.")
      return
    }
    let requestToken = SDCopilotContextToken(
      organizationId: organizationId,
      userId: userId,
      playerId: playerId,
      audience: .player
    )
    token = requestToken
    response = nil
    phase = .loading
    do {
      let result = try await client.playerDevelopmentWorkspace(
        organizationId: organizationId,
        playerId: playerId
      )
      guard token == requestToken else { return }
      guard result.evidencePack.organizationId == organizationId,
            result.evidencePack.playerId == playerId,
            result.evidencePack.reportType == "player_copilot_self_question",
            result.playerVisibleReports.allSatisfy({
              $0.organizationId == organizationId && $0.playerId == playerId && $0.audience == .player
            }),
            result.playerVisibleAlerts.allSatisfy({
              $0.organizationId == organizationId && $0.playerId == playerId && $0.audience == .player
            }) else {
        throw SDCopilotClientScopeError.invalidResponseScope
      }
      response = result
      reports = result.playerVisibleReports
      alerts = result.playerVisibleAlerts
      phase = .loaded
    } catch is CancellationError {
      return
    } catch {
      guard token == requestToken else { return }
      phase = .failed(error.localizedDescription)
    }
  }

  func generateSummary(
    client: any PlayerDevelopmentCopilotClient,
    organizationId: UUID,
    userId: UUID,
    playerId: UUID,
    window: SDDevelopmentWindow = .trailingDays(90)
  ) async {
    guard userId == playerId else {
      generationPhase = .failed("A player summary can only be generated for your signed-in profile.")
      return
    }
    let requestToken = SDCopilotContextToken(
      organizationId: organizationId,
      userId: userId,
      playerId: playerId,
      audience: .player
    )
    guard token == requestToken, generationPhase != .generating else { return }
    if generationKey == nil { generationKey = UUID() }
    generationPhase = .generating
    do {
      let result = try await client.generatePlayerDevelopmentReport(
        organizationId: organizationId,
        playerId: playerId,
        window: window,
        evidenceCutoff: Date(),
        idempotencyKey: generationKey!
      )
      guard token == requestToken else { return }
      guard result.report.organizationId == organizationId,
            result.report.playerId == playerId,
            result.report.audience == .player,
            result.report.requestedBy == userId,
            (result.playerAlerts ?? []).allSatisfy({
              $0.organizationId == organizationId && $0.playerId == playerId && $0.audience == .player
            }) else {
        throw SDCopilotClientScopeError.invalidResponseScope
      }
      let refreshed = try await client.playerDevelopmentWorkspace(
        organizationId: organizationId,
        playerId: playerId
      )
      guard token == requestToken else { return }
      guard refreshed.playerVisibleReports.allSatisfy({
        $0.organizationId == organizationId && $0.playerId == playerId && $0.audience == .player
      }), refreshed.playerVisibleAlerts.allSatisfy({
        $0.organizationId == organizationId && $0.playerId == playerId && $0.audience == .player
      }) else {
        throw SDCopilotClientScopeError.invalidResponseScope
      }
      response = refreshed
      reports = refreshed.playerVisibleReports
      alerts = refreshed.playerVisibleAlerts
      generationPhase = .succeeded(result.reused ? "Your existing summary was restored." : "Your summary is ready.")
      generationKey = nil
    } catch is CancellationError {
      return
    } catch {
      guard token == requestToken else { return }
      generationPhase = .failed(error.localizedDescription)
    }
  }
}

struct PlayerDevelopmentPlayerWorkspaceView: View {
  @EnvironmentObject private var appState: AppState
  @StateObject private var model = PlayerDevelopmentPlayerWorkspaceModel()
  let player: Profile

  private var contextKey: String {
    "\(appState.activeOrgAuthorizationKey):\(appState.myProfile?.id.uuidString ?? "none"):\(player.id.uuidString):player-development"
  }

  var body: some View {
    Group {
      if !SDDevelopmentPresentationAuthorization.isCopilotVisible(
        membership: appState.activeOrgMembership,
        audience: .player,
        userId: appState.myProfile?.id,
        playerId: player.id
      ) {
        ContentUnavailableView("Player Development unavailable", systemImage: "lock.fill")
      } else {
        content
      }
    }
    .navigationTitle("Development AI")
    .background(DHDTheme.pageBackground)
    .task(id: contextKey) {
      guard let client = appState.supabase,
            let organizationId = appState.activeOrgId,
            let userId = appState.myProfile?.id else { return }
      await model.load(
        client: client,
        organizationId: organizationId,
        userId: userId,
        playerId: player.id
      )
    }
    .onDisappear { model.reset() }
  }

  @ViewBuilder
  private var content: some View {
    switch model.phase {
    case .idle, .loading:
      ProgressView("Loading your development evidence…")
    case .failed(let message):
      ContentUnavailableView(
        "Development evidence unavailable",
        systemImage: "exclamationmark.triangle.fill",
        description: Text(message)
      )
    case .loaded:
      if let response = model.response {
        workspace(response)
      }
    }
  }

  private func workspace(_ response: SDPlayerDevelopmentWorkspaceResponse) -> some View {
    let pack = response.evidencePack
    return List {
      Section {
        NavigationLink {
          PlayerDevelopmentCopilotWorkspaceView(
            player: player,
            audience: .player,
            presentationStyle: .pushed
          )
        } label: {
          Label("Open Player Copilot", systemImage: "bubble.left.and.text.bubble.right.fill")
        }
        Text("Your Player Copilot conversations are private and separate from coach conversations unless a future sharing action is explicitly used.")
          .font(.footnote)
          .foregroundStyle(DHDTheme.textSecondary)
      }

      Section("Data coverage") {
        coverageRow("Testing results", count: pack.coverage.testingEntries)
        coverageRow("Imported metrics", count: pack.coverage.metricObservations)
        coverageRow("Daily logs", count: pack.coverage.dailyLogs)
        coverageRow("Assigned programs", count: pack.coverage.programAssignments)
        coverageRow("Batting-practice sessions", count: pack.coverage.bpSessions)
        LabeledContent("Freshness", value: pack.dataFreshness.capitalized)
      }

      Section("Recent objective trends") {
        if pack.trends.isEmpty {
          Text("No supported comparison is available in this window.")
            .foregroundStyle(DHDTheme.textSecondary)
        }
        ForEach(pack.trends) { trend in
          VStack(alignment: .leading, spacing: 4) {
            Text(trend.displayName).font(.headline)
            Text("Latest: \(trend.latestValue.formatted())\(trend.unit.map { " \($0)" } ?? "")")
            Text("\(trend.interpretation.capitalized) • \(trend.sampleCount) samples • \(trend.freshness.capitalized)")
              .font(.caption)
              .foregroundStyle(DHDTheme.textSecondary)
          }
        }
      }

      Section("Testing and imported evidence") {
        if pack.evidence.isEmpty {
          Text("No player-visible objective evidence is available.")
            .foregroundStyle(DHDTheme.textSecondary)
        }
        ForEach(pack.evidence) { evidence in
          VStack(alignment: .leading, spacing: 4) {
            Text(evidence.displayLabel).font(.headline)
            if let value = evidence.normalizedNumericValue ?? Double(evidence.rawObservedValue ?? "") {
              Text("\(value.formatted())\(evidence.unit.map { " \($0)" } ?? "")")
            } else {
              Text(evidence.explanation)
            }
            HStack {
              Text(evidence.observationDate ?? "Date unavailable")
              if let provider = evidence.sourceMetadata["provider"]?.stringValue ?? evidence.sourceMetadata["source_system"]?.stringValue {
                Text(provider.capitalized)
              }
              if let verification = evidence.sourceMetadata["verification_status"]?.stringValue {
                Text(verification.replacingOccurrences(of: "_", with: " ").capitalized)
              }
            }
            .font(.caption)
            .foregroundStyle(DHDTheme.textSecondary)
          }
        }
      }

      Section("Freshness and data gaps") {
        warningRows(pack.missingDataWarnings + pack.staleDataWarnings + pack.unitConflicts + pack.lowSampleWarnings)
      }

      Section("Player-visible reports") {
        Button {
          guard let client = appState.supabase,
                let organizationId = appState.activeOrgId,
                let userId = appState.myProfile?.id else { return }
          Task {
            await model.generateSummary(
              client: client,
              organizationId: organizationId,
              userId: userId,
              playerId: player.id
            )
          }
        } label: {
          Label(model.generationPhase == .generating ? "Generating…" : "Generate My Summary", systemImage: "sparkles")
        }
        .disabled(model.generationPhase == .generating)
        switch model.generationPhase {
        case .succeeded(let message):
          Label(message, systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed(let message):
          VStack(alignment: .leading, spacing: 6) {
            Label(message, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
            Text("Choose Generate My Summary again to retry the same safe request.")
              .font(.caption).foregroundStyle(DHDTheme.textSecondary)
          }
        default: EmptyView()
        }
        if model.reports.isEmpty {
          Text(response.reportsAvailability).foregroundStyle(DHDTheme.textSecondary)
        } else {
          ForEach(model.reports) { report in
            NavigationLink {
              PlayerDevelopmentPlayerReportDetailView(reportId: report.id, playerId: player.id)
            } label: {
              VStack(alignment: .leading, spacing: 4) {
                Text("My Development Summary").font(.headline)
                Text("\(report.reportingWindowStart) – \(report.reportingWindowEnd)")
                  .font(.caption).foregroundStyle(DHDTheme.textSecondary)
                Text("\(report.provider.capitalized) • \(report.dataFreshness.capitalized) • \(report.status.rawValue.capitalized)")
                  .font(.caption2).foregroundStyle(DHDTheme.textSecondary)
              }
            }
          }
        }
      }

      Section("Player-visible alerts") {
        if model.alerts.isEmpty {
          Text(response.alertsAvailability).foregroundStyle(DHDTheme.textSecondary)
        } else {
          ForEach(model.alerts) { alert in
            NavigationLink {
              PlayerDevelopmentPlayerAlertDetailView(alertId: alert.id, playerId: player.id)
            } label: {
              VStack(alignment: .leading, spacing: 4) {
                Text(alert.explanation).font(.headline)
                Text("\(alert.dataFreshness.capitalized) • \(alert.evidenceQuality.rawValue.capitalized)")
                  .font(.caption).foregroundStyle(DHDTheme.textSecondary)
              }
            }
          }
        }
      }

      Section("Suggested questions") {
        ForEach(response.suggestedQuestions, id: \.self) { question in
          Text(question)
        }
      }
    }
  }

  private func coverageRow(_ label: String, count: Int) -> some View {
    LabeledContent(label, value: count.formatted())
  }

  @ViewBuilder
  private func warningRows(_ warnings: [String]) -> some View {
    if warnings.isEmpty {
      Text("No current warning was produced for the supported sources.")
        .foregroundStyle(DHDTheme.textSecondary)
    } else {
      ForEach(warnings, id: \.self) { warning in
        Label(warning, systemImage: "exclamationmark.triangle")
      }
    }
  }
}

private struct PlayerDevelopmentPlayerReportDetailView: View {
  @EnvironmentObject private var appState: AppState
  @Environment(\.dismiss) private var dismiss
  @State private var detail: SDDevelopmentReportDetail?
  @State private var errorMessage: String?
  @State private var isLoading = true
  @State private var isArchiving = false
  let reportId: UUID
  let playerId: UUID

  var body: some View {
    Group {
      if isLoading { ProgressView("Loading your summary…") }
      else if let errorMessage {
        ContentUnavailableView("Summary unavailable", systemImage: "exclamationmark.triangle", description: Text(errorMessage))
      } else if let detail {
        List {
          Section("Summary") {
            Text(detail.report.structuredContent.overview)
            LabeledContent("Evidence state", value: detail.report.qualityStatus.rawValue.capitalized)
            LabeledContent("Freshness", value: detail.report.dataFreshness.capitalized)
            LabeledContent("Provider", value: detail.report.provider.capitalized)
            LabeledContent("Verification", value: detail.report.evidenceFingerprint == nil ? "Limited" : "Evidence fingerprint recorded")
          }
          reportSections("Supported improvements", detail.report.structuredContent.positiveTrends)
          reportSections("Worth discussing", detail.report.structuredContent.developmentPriorities)
          Section("Interpretation and recommendations") {
            Text("Deterministic calculations are based on the cited measurements. Interpretations do not explain why a change occurred.")
            ForEach(detail.report.structuredContent.coachReviewQuestions, id: \.self) { Text($0) }
          }
          Section("Missing evidence") {
            if detail.report.structuredContent.dataGaps.isEmpty {
              Text("No supported data gap was recorded.")
            } else {
              ForEach(detail.report.structuredContent.dataGaps, id: \.self) { Label($0, systemImage: "info.circle") }
            }
          }
          Section("Evidence citations") {
            if detail.evidence.isEmpty { Text("No player-visible citations are available.") }
            ForEach(detail.evidence) { evidence in
              VStack(alignment: .leading, spacing: 4) {
                Text(evidence.displayLabel).font(.headline)
                Text(evidence.explanation)
                Text("\(evidence.observationDate ?? "Date unavailable") • \(evidence.quality.rawValue.capitalized)")
                  .font(.caption).foregroundStyle(DHDTheme.textSecondary)
              }
            }
          }
          if detail.report.status == .draft {
            Section {
              Button("Archive My Summary", role: .destructive) { Task { await archive() } }
                .disabled(isArchiving)
            }
          }
        }
      }
    }
    .navigationTitle("My Summary")
    .toolbar {
      ToolbarItem(placement: .cancellationAction) {
        Button("Back") { dismiss() }
        #if os(macOS)
        .keyboardShortcut(.cancelAction)
        #endif
      }
    }
    .task(id: "\(appState.activeOrgAuthorizationKey):\(appState.myProfile?.id.uuidString ?? "none"):\(reportId)") { await load() }
  }

  @ViewBuilder
  private func reportSections(_ title: String, _ sections: [SDDevelopmentReportSection]) -> some View {
    Section(title) {
      if sections.isEmpty { Text("No supported item is available.") }
      ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
        VStack(alignment: .leading, spacing: 4) {
          Text(section.title).font(.headline)
          Text(section.explanation)
          Text("\(section.evidenceKeys.count) citation\(section.evidenceKeys.count == 1 ? "" : "s")")
            .font(.caption).foregroundStyle(DHDTheme.textSecondary)
        }
      }
    }
  }

  private func load() async {
    guard let service = appState.supabase,
          let organizationId = appState.activeOrgId,
          let userId = appState.myProfile?.id,
          userId == playerId else { return }
    let token = SDCopilotContextToken(organizationId: organizationId, userId: userId, playerId: playerId, audience: .player)
    isLoading = true
    errorMessage = nil
    do {
      let result = try await service.playerDevelopmentReportDetail(organizationId: organizationId, reportId: reportId)
      guard token.accepts(organizationId: appState.activeOrgId, userId: appState.myProfile?.id, playerId: playerId, audience: .player),
            result.report.organizationId == organizationId,
            result.report.playerId == playerId,
            result.report.audience == .player,
            result.report.requestedBy == userId,
            result.reviewHistory.isEmpty else {
        throw SDCopilotClientScopeError.invalidResponseScope
      }
      detail = result
    } catch { errorMessage = error.localizedDescription }
    isLoading = false
  }

  private func archive() async {
    guard let service = appState.supabase, let organizationId = appState.activeOrgId else { return }
    isArchiving = true
    defer { isArchiving = false }
    do {
      let report = try await service.archivePlayerDevelopmentReport(organizationId: organizationId, reportId: reportId)
      guard report.organizationId == organizationId, report.playerId == playerId, report.audience == .player else {
        throw SDCopilotClientScopeError.invalidResponseScope
      }
      await load()
    } catch { errorMessage = error.localizedDescription }
  }
}

private struct PlayerDevelopmentPlayerAlertDetailView: View {
  @EnvironmentObject private var appState: AppState
  @Environment(\.dismiss) private var dismiss
  @State private var detail: SDDevelopmentAlertDetail?
  @State private var errorMessage: String?
  @State private var isLoading = true
  @State private var isDismissing = false
  let alertId: UUID
  let playerId: UUID

  var body: some View {
    Group {
      if isLoading { ProgressView("Loading alert evidence…") }
      else if let errorMessage {
        ContentUnavailableView("Alert unavailable", systemImage: "exclamationmark.triangle", description: Text(errorMessage))
      } else if let detail {
        List {
          Section("Objective alert") {
            Text(detail.alert.explanation)
            Text(detail.alert.recommendedHumanAction).foregroundStyle(DHDTheme.textSecondary)
            LabeledContent("Freshness", value: detail.alert.dataFreshness.capitalized)
            LabeledContent("Evidence quality", value: detail.alert.evidenceQuality.rawValue.capitalized)
          }
          Section("Evidence") {
            if detail.evidence.isEmpty { Text("No player-visible evidence is available.") }
            ForEach(detail.evidence) { evidence in
              VStack(alignment: .leading, spacing: 4) {
                Text(evidence.displayLabel).font(.headline)
                Text(evidence.explanation)
                Text(evidence.observationDate ?? "Date unavailable")
                  .font(.caption).foregroundStyle(DHDTheme.textSecondary)
              }
            }
          }
          if detail.alert.status == .active || detail.alert.status == .acknowledged {
            Section {
              Button("Dismiss This Alert") { Task { await dismissAlert() } }
                .disabled(isDismissing)
            }
          }
        }
      }
    }
    .navigationTitle("Development Alert")
    .toolbar {
      ToolbarItem(placement: .cancellationAction) {
        Button("Back") { dismiss() }
        #if os(macOS)
        .keyboardShortcut(.cancelAction)
        #endif
      }
    }
    .task(id: "\(appState.activeOrgAuthorizationKey):\(appState.myProfile?.id.uuidString ?? "none"):\(alertId)") { await load() }
  }

  private func load() async {
    guard let service = appState.supabase,
          let organizationId = appState.activeOrgId,
          let userId = appState.myProfile?.id,
          userId == playerId else { return }
    let token = SDCopilotContextToken(organizationId: organizationId, userId: userId, playerId: playerId, audience: .player)
    isLoading = true
    errorMessage = nil
    do {
      let result = try await service.playerDevelopmentAlertDetail(organizationId: organizationId, alertId: alertId)
      guard token.accepts(organizationId: appState.activeOrgId, userId: appState.myProfile?.id, playerId: playerId, audience: .player),
            result.alert.organizationId == organizationId,
            result.alert.playerId == playerId,
            result.alert.audience == .player,
            result.reviewHistory.isEmpty else {
        throw SDCopilotClientScopeError.invalidResponseScope
      }
      detail = result
    } catch { errorMessage = error.localizedDescription }
    isLoading = false
  }

  private func dismissAlert() async {
    guard let service = appState.supabase, let organizationId = appState.activeOrgId else { return }
    isDismissing = true
    defer { isDismissing = false }
    do {
      let alert = try await service.dismissPlayerDevelopmentAlert(organizationId: organizationId, alertId: alertId)
      guard alert.organizationId == organizationId, alert.playerId == playerId, alert.audience == .player else {
        throw SDCopilotClientScopeError.invalidResponseScope
      }
      await load()
    } catch { errorMessage = error.localizedDescription }
  }
}
