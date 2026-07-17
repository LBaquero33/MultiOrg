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
        HPStateScreenLayout { _ in
          HPCard {
            HPEmptyState(
              title: "Player Development unavailable",
              message: "Player Development is available only for your signed-in player profile.",
              systemImage: "lock.fill"
            )
          }
        }
      } else {
        content
      }
    }
    .navigationTitle("Development AI")
    .background(HP.Color.bg)
    .task(id: contextKey) {
      await loadWorkspace()
    }
    .onDisappear { model.reset() }
  }

  @ViewBuilder
  private var content: some View {
    switch model.phase {
    case .idle, .loading:
      HPStateScreenLayout { _ in
        HPCard {
          HPLoadingState(text: "Loading your development evidence…")
        }
      }
    case .failed(let message):
      HPStateScreenLayout { _ in
        HPCard {
          HPErrorState(
            title: "Development evidence unavailable",
            message: message,
            onRetry: { Task { await loadWorkspace() } }
          )
        }
      }
    case .loaded:
      if let response = model.response {
        workspace(response)
      }
    }
  }

  private func loadWorkspace() async {
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

  private func workspace(_ response: SDPlayerDevelopmentWorkspaceResponse) -> some View {
    let pack = response.evidencePack
    return HPWorkspaceScreenLayout {
      HPWorkspaceHeader(
        "Development AI",
        orgLabel: activeOrganizationName,
        context: "\(pack.dataFreshness.capitalized) data • Player-only workspace"
      )
    } attention: {
      VStack(alignment: .leading, spacing: HP.Space.md) {
        HPCard {
          VStack(alignment: .leading, spacing: HP.Space.sm) {
            HPSectionHeader("Player Copilot")
            NavigationLink {
              PlayerDevelopmentCopilotWorkspaceView(
                player: player,
                audience: .player,
                presentationStyle: .pushed
              )
            } label: {
              HStack(spacing: HP.Space.sm) {
                Image(systemName: "bubble.left.and.text.bubble.right.fill")
                  .foregroundStyle(HP.Color.accent)
                Text("Open Player Copilot")
                  .font(HP.Font.headline)
                  .foregroundStyle(HP.Color.text)
                  .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                  .font(.caption.weight(.semibold))
                  .foregroundStyle(HP.Color.textMuted)
              }
              .frame(minHeight: 44)
              .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Text("Your Player Copilot conversations are private and separate from coach conversations unless a future sharing action is explicitly used.")
              .font(HP.Font.caption)
              .foregroundStyle(HP.Color.textMuted)
              .fixedSize(horizontal: false, vertical: true)
          }
        }
        HPSectionHeader("Data coverage")
      }
    } metrics: {
      HPMetricCard(title: "Testing results", value: pack.coverage.testingEntries.formatted(), context: "Available entries")
      HPMetricCard(title: "Imported metrics", value: pack.coverage.metricObservations.formatted(), context: "Objective observations")
      HPMetricCard(title: "Daily logs", value: pack.coverage.dailyLogs.formatted(), context: "Available logs")
      HPMetricCard(title: "Assigned programs", value: pack.coverage.programAssignments.formatted(), context: "Program assignments")
      HPMetricCard(title: "BP sessions", value: pack.coverage.bpSessions.formatted(), context: "Batting-practice sessions")
      HPMetricCard(title: "Freshness", value: pack.dataFreshness.capitalized, context: "Supported evidence")
    } supporting: {
      VStack(alignment: .leading, spacing: HP.Space.md) {
        HPCard {
          VStack(alignment: .leading, spacing: HP.Space.sm) {
            HPSectionHeader("Recent objective trends")
            if pack.trends.isEmpty {
              mutedText("No supported comparison is available in this window.")
            }
            ForEach(pack.trends) { trend in
              VStack(alignment: .leading, spacing: 4) {
                Text(trend.displayName).font(HP.Font.headline).foregroundStyle(HP.Color.text)
                Text("Latest: \(trend.latestValue.formatted())\(trend.unit.map { " \($0)" } ?? "")")
                  .font(HP.Font.callout).foregroundStyle(HP.Color.text)
                Text("\(trend.interpretation.capitalized) • \(trend.sampleCount) samples • \(trend.freshness.capitalized)")
                  .font(HP.Font.caption)
                  .foregroundStyle(HP.Color.textMuted)
              }
              .frame(maxWidth: .infinity, alignment: .leading)
            }
          }
        }

        HPCard {
          VStack(alignment: .leading, spacing: HP.Space.sm) {
            HPSectionHeader("Testing and imported evidence")
            if pack.evidence.isEmpty {
              mutedText("No player-visible objective evidence is available.")
            }
            ForEach(pack.evidence) { evidence in
              VStack(alignment: .leading, spacing: 4) {
                Text(evidence.displayLabel).font(HP.Font.headline).foregroundStyle(HP.Color.text)
                if let value = evidence.normalizedNumericValue ?? Double(evidence.rawObservedValue ?? "") {
                  Text("\(value.formatted())\(evidence.unit.map { " \($0)" } ?? "")")
                    .font(HP.Font.callout).foregroundStyle(HP.Color.text)
                } else {
                  Text(evidence.explanation)
                    .font(HP.Font.callout).foregroundStyle(HP.Color.text)
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
                .font(HP.Font.caption)
                .foregroundStyle(HP.Color.textMuted)
              }
              .frame(maxWidth: .infinity, alignment: .leading)
            }
          }
        }

        HPCard {
          VStack(alignment: .leading, spacing: HP.Space.sm) {
            HPSectionHeader("Freshness and data gaps")
            warningRows(pack.missingDataWarnings + pack.staleDataWarnings + pack.unitConflicts + pack.lowSampleWarnings)
          }
        }

        HPCard {
          VStack(alignment: .leading, spacing: HP.Space.sm) {
            HPSectionHeader("Player-visible reports")
            HPButton(
              title: model.generationPhase == .generating ? "Generating…" : "Generate My Summary",
              systemImage: "sparkles",
              variant: .primary,
              size: .md,
              isLoading: model.generationPhase == .generating,
              fullWidth: true
            ) {
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
            }
            .disabled(model.generationPhase == .generating)
            switch model.generationPhase {
            case .succeeded(let message):
              Label(message, systemImage: "checkmark.circle.fill").foregroundStyle(HP.Color.success)
            case .failed(let message):
              VStack(alignment: .leading, spacing: 6) {
                Label(message, systemImage: "exclamationmark.triangle.fill").foregroundStyle(HP.Color.danger)
                Text("Choose Generate My Summary again to retry the same safe request.")
                  .font(HP.Font.caption).foregroundStyle(HP.Color.textMuted)
              }
            default: EmptyView()
            }
            if model.reports.isEmpty {
              mutedText(response.reportsAvailability)
            } else {
              ForEach(model.reports) { report in
                NavigationLink {
                  PlayerDevelopmentPlayerReportDetailView(reportId: report.id, playerId: player.id)
                } label: {
                  HStack(alignment: .center, spacing: HP.Space.sm) {
                    VStack(alignment: .leading, spacing: 4) {
                      Text("My Development Summary").font(HP.Font.headline).foregroundStyle(HP.Color.text)
                      Text("\(report.reportingWindowStart) – \(report.reportingWindowEnd)")
                        .font(HP.Font.caption).foregroundStyle(HP.Color.textMuted)
                      Text("\(report.provider.capitalized) • \(report.dataFreshness.capitalized) • \(report.status.rawValue.capitalized)")
                        .font(HP.Font.caption).foregroundStyle(HP.Color.textMuted)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.right")
                      .font(.caption.weight(.semibold))
                      .foregroundStyle(HP.Color.textMuted)
                  }
                  .frame(minHeight: 44)
                  .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
              }
            }
          }
        }

        HPCard {
          VStack(alignment: .leading, spacing: HP.Space.sm) {
            HPSectionHeader("Player-visible alerts")
            if model.alerts.isEmpty {
              mutedText(response.alertsAvailability)
            } else {
              ForEach(model.alerts) { alert in
                NavigationLink {
                  PlayerDevelopmentPlayerAlertDetailView(alertId: alert.id, playerId: player.id)
                } label: {
                  HStack(alignment: .center, spacing: HP.Space.sm) {
                    VStack(alignment: .leading, spacing: 4) {
                      Text(alert.explanation).font(HP.Font.headline).foregroundStyle(HP.Color.text)
                      Text("\(alert.dataFreshness.capitalized) • \(alert.evidenceQuality.rawValue.capitalized)")
                        .font(HP.Font.caption).foregroundStyle(HP.Color.textMuted)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.right")
                      .font(.caption.weight(.semibold))
                      .foregroundStyle(HP.Color.textMuted)
                  }
                  .frame(minHeight: 44)
                  .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
              }
            }
          }
        }

        HPCard {
          VStack(alignment: .leading, spacing: HP.Space.sm) {
            HPSectionHeader("Suggested questions")
            ForEach(response.suggestedQuestions, id: \.self) { question in
              Text(question)
                .font(HP.Font.callout)
                .foregroundStyle(HP.Color.text)
                .fixedSize(horizontal: false, vertical: true)
            }
          }
        }
      }
    }
  }

  private var activeOrganizationName: String {
    appState.availableOrganizations.first(where: { $0.id == appState.activeOrgId })?.name
      ?? appState.activeOrgSettings?.display_name
      ?? appState.activeOrgSettings?.short_name
      ?? "Home Plate"
  }

  private func mutedText(_ text: String) -> some View {
    Text(text)
      .font(HP.Font.callout)
      .foregroundStyle(HP.Color.textMuted)
      .fixedSize(horizontal: false, vertical: true)
  }

  @ViewBuilder
  private func warningRows(_ warnings: [String]) -> some View {
    if warnings.isEmpty {
      mutedText("No current warning was produced for the supported sources.")
    } else {
      ForEach(warnings, id: \.self) { warning in
        Label(warning, systemImage: "exclamationmark.triangle")
          .font(HP.Font.callout)
          .foregroundStyle(HP.Color.text)
          .fixedSize(horizontal: false, vertical: true)
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
      if isLoading {
        HPStateScreenLayout { _ in
          HPCard {
            HPLoadingState(text: "Loading your summary…")
          }
        }
      }
      else if let errorMessage {
        HPStateScreenLayout { _ in
          HPCard {
            HPErrorState(title: "Summary unavailable", message: errorMessage)
          }
        }
      } else if let detail {
        reportDetail(detail)
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

  private func reportDetail(_ detail: SDDevelopmentReportDetail) -> some View {
    HPDetailScreenLayout {
      HPWorkspaceHeader(
        "My Summary",
        orgLabel: "Player Development",
        context: "Player-visible development report"
      )
    } metrics: {
      HPMetricCard(
        title: "Evidence state",
        value: detail.report.qualityStatus.rawValue.capitalized,
        context: "Report quality"
      )
      HPMetricCard(
        title: "Freshness",
        value: detail.report.dataFreshness.capitalized,
        context: "Evidence recency"
      )
      HPMetricCard(
        title: "Provider",
        value: detail.report.provider.capitalized,
        context: "Generation source"
      )
      HPMetricCard(
        title: "Verification",
        value: detail.report.evidenceFingerprint == nil ? "Limited" : "Recorded",
        context: detail.report.evidenceFingerprint == nil ? nil : "Evidence fingerprint recorded"
      )
    } details: {
      VStack(alignment: .leading, spacing: HP.Space.md) {
        HPCard {
          VStack(alignment: .leading, spacing: HP.Space.sm) {
            HPSectionHeader("Summary")
            Text(detail.report.structuredContent.overview)
              .font(HP.Font.callout)
              .foregroundStyle(HP.Color.text)
              .fixedSize(horizontal: false, vertical: true)
          }
        }

        reportSections("Supported improvements", detail.report.structuredContent.positiveTrends)
        reportSections("Worth discussing", detail.report.structuredContent.developmentPriorities)

        HPCard {
          VStack(alignment: .leading, spacing: HP.Space.sm) {
            HPSectionHeader("Interpretation and recommendations")
            Text("Deterministic calculations are based on the cited measurements. Interpretations do not explain why a change occurred.")
              .font(HP.Font.callout)
              .foregroundStyle(HP.Color.text)
              .fixedSize(horizontal: false, vertical: true)
            ForEach(detail.report.structuredContent.coachReviewQuestions, id: \.self) { question in
              Text(question)
                .font(HP.Font.callout)
                .foregroundStyle(HP.Color.text)
                .fixedSize(horizontal: false, vertical: true)
            }
          }
        }

        HPCard {
          VStack(alignment: .leading, spacing: HP.Space.sm) {
            HPSectionHeader("Missing evidence")
            if detail.report.structuredContent.dataGaps.isEmpty {
              Text("No supported data gap was recorded.")
                .font(HP.Font.callout)
                .foregroundStyle(HP.Color.textMuted)
            } else {
              ForEach(detail.report.structuredContent.dataGaps, id: \.self) { gap in
                Label(gap, systemImage: "info.circle")
                  .font(HP.Font.callout)
                  .foregroundStyle(HP.Color.text)
                  .fixedSize(horizontal: false, vertical: true)
              }
            }
          }
        }
      }
    } related: { _ in
      HPCard {
        VStack(alignment: .leading, spacing: HP.Space.sm) {
          HPSectionHeader("Evidence citations")
          if detail.evidence.isEmpty {
            Text("No player-visible citations are available.")
              .font(HP.Font.callout)
              .foregroundStyle(HP.Color.textMuted)
          }
          ForEach(detail.evidence) { evidence in
            VStack(alignment: .leading, spacing: 4) {
              Text(evidence.displayLabel).font(HP.Font.headline).foregroundStyle(HP.Color.text)
              Text(evidence.explanation)
                .font(HP.Font.callout).foregroundStyle(HP.Color.text)
              Text("\(evidence.observationDate ?? "Date unavailable") • \(evidence.quality.rawValue.capitalized)")
                .font(HP.Font.caption).foregroundStyle(HP.Color.textMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
          }
        }
      }
    } primaryAction: {
      if detail.report.status == .draft {
        HPCard {
          HPButton(
            title: "Archive My Summary",
            variant: .destructive,
            size: .lg,
            isLoading: isArchiving,
            fullWidth: true
          ) { Task { await archive() } }
          .disabled(isArchiving)
        }
      }
    }
  }

  private func reportSections(_ title: String, _ sections: [SDDevelopmentReportSection]) -> some View {
    HPCard {
      VStack(alignment: .leading, spacing: HP.Space.sm) {
        HPSectionHeader(title)
        if sections.isEmpty {
          Text("No supported item is available.")
            .font(HP.Font.callout)
            .foregroundStyle(HP.Color.textMuted)
        }
        ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
          VStack(alignment: .leading, spacing: 4) {
            Text(section.title).font(HP.Font.headline).foregroundStyle(HP.Color.text)
            Text(section.explanation)
              .font(HP.Font.callout).foregroundStyle(HP.Color.text)
            Text("\(section.evidenceKeys.count) citation\(section.evidenceKeys.count == 1 ? "" : "s")")
              .font(HP.Font.caption).foregroundStyle(HP.Color.textMuted)
          }
          .frame(maxWidth: .infinity, alignment: .leading)
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
      if isLoading {
        HPStateScreenLayout { _ in
          HPCard {
            HPLoadingState(text: "Loading alert evidence…")
          }
        }
      }
      else if let errorMessage {
        HPStateScreenLayout { _ in
          HPCard {
            HPErrorState(title: "Alert unavailable", message: errorMessage)
          }
        }
      } else if let detail {
        alertDetail(detail)
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

  private func alertDetail(_ detail: SDDevelopmentAlertDetail) -> some View {
    HPDetailScreenLayout {
      HPWorkspaceHeader(
        "Development Alert",
        orgLabel: "Player Development",
        context: "Player-visible objective alert"
      )
    } metrics: {
      HPMetricCard(
        title: "Freshness",
        value: detail.alert.dataFreshness.capitalized,
        context: "Evidence recency"
      )
      HPMetricCard(
        title: "Evidence quality",
        value: detail.alert.evidenceQuality.rawValue.capitalized,
        context: "Supported evidence"
      )
    } details: {
      HPCard {
        VStack(alignment: .leading, spacing: HP.Space.sm) {
          HPSectionHeader("Objective alert")
          Text(detail.alert.explanation)
            .font(HP.Font.callout)
            .foregroundStyle(HP.Color.text)
            .fixedSize(horizontal: false, vertical: true)
          Text(detail.alert.recommendedHumanAction)
            .font(HP.Font.callout)
            .foregroundStyle(HP.Color.textMuted)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
    } related: { _ in
      HPCard {
        VStack(alignment: .leading, spacing: HP.Space.sm) {
          HPSectionHeader("Evidence")
          if detail.evidence.isEmpty {
            Text("No player-visible evidence is available.")
              .font(HP.Font.callout)
              .foregroundStyle(HP.Color.textMuted)
          }
          ForEach(detail.evidence) { evidence in
            VStack(alignment: .leading, spacing: 4) {
              Text(evidence.displayLabel).font(HP.Font.headline).foregroundStyle(HP.Color.text)
              Text(evidence.explanation)
                .font(HP.Font.callout).foregroundStyle(HP.Color.text)
              Text(evidence.observationDate ?? "Date unavailable")
                .font(HP.Font.caption).foregroundStyle(HP.Color.textMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
          }
        }
      }
    } primaryAction: {
      if detail.alert.status == .active || detail.alert.status == .acknowledged {
        HPCard {
          HPButton(
            title: "Dismiss This Alert",
            variant: .secondary,
            size: .lg,
            isLoading: isDismissing,
            fullWidth: true
          ) { Task { await dismissAlert() } }
          .disabled(isDismissing)
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
