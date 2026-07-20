import SwiftUI

@MainActor
final class PlayerDevelopmentAIWorkspaceModel: ObservableObject {
  enum Phase: Equatable {
    case idle
    case loading
    case loaded
    case failed(String)
  }

  @Published private(set) var phase: Phase = .idle
  @Published private(set) var evidencePack: SDDevelopmentEvidencePack?
  @Published private(set) var reports: [SDDevelopmentReport] = []
  @Published private(set) var alerts: [SDDevelopmentAlert] = []
  @Published private(set) var isGenerating = false
  @Published private(set) var mutationInFlight = false
  @Published private(set) var generationRetryAvailable = false
  @Published var successMessage: String?
  @Published var errorMessage: String?

  private(set) var requestToken: SDDevelopmentRequestToken?
  private var generationMaterial: String?
  private var generationKey: UUID?
  private var generationCutoff: Date?

  var latestReport: SDDevelopmentReport? { reports.first }

  func reset() {
    requestToken = nil
    phase = .idle
    evidencePack = nil
    reports = []
    alerts = []
    isGenerating = false
    mutationInFlight = false
    generationRetryAvailable = false
    successMessage = nil
    errorMessage = nil
    clearGenerationOperation()
  }

  func load(
    client: any PlayerDevelopmentAIClient,
    organizationId: UUID,
    userId: UUID,
    playerId: UUID,
    window: SDDevelopmentWindow
  ) async {
    let token = SDDevelopmentRequestToken(
      organizationId: organizationId,
      userId: userId,
      nonce: UUID()
    )
    requestToken = token
    phase = .loading
    generationRetryAvailable = false
    errorMessage = nil
    do {
      let packTask = Task { @MainActor in
        try await client.buildDevelopmentEvidencePack(
          organizationId: organizationId,
          playerId: playerId,
          reportType: .playerDevelopmentSummary,
          window: window,
          evidenceCutoff: Date()
        )
      }
      let reportsTask = Task { @MainActor in
        try await client.listDevelopmentReports(
          organizationId: organizationId,
          playerId: playerId
        )
      }
      let alertsTask = Task { @MainActor in
        try await client.listDevelopmentAlerts(
          organizationId: organizationId,
          playerId: playerId
        )
      }
      defer {
        packTask.cancel()
        reportsTask.cancel()
        alertsTask.cancel()
      }
      let result = try await (packTask.value, reportsTask.value, alertsTask.value)
      guard requestToken == token else { return }
      evidencePack = result.0
      reports = result.1
      alerts = result.2
      phase = .loaded
    } catch is CancellationError {
      return
    } catch {
      guard requestToken == token else { return }
      phase = .failed(error.localizedDescription)
      errorMessage = error.localizedDescription
    }
  }

  func acceptsResult(organizationId: UUID?, userId: UUID?) -> Bool {
    requestToken?.accepts(organizationId: organizationId, userId: userId) == true
  }

  func generationOperation(
    organizationId: UUID,
    playerId: UUID,
    window: SDDevelopmentWindow,
    reportType: SDDevelopmentReportType = .playerDevelopmentSummary
  ) -> (key: UUID, cutoff: Date) {
    let material = [
      organizationId.uuidString.lowercased(),
      playerId.uuidString.lowercased(),
      reportType.rawValue,
      window.start,
      window.end,
    ].joined(separator: "|")
    if generationMaterial != material || generationKey == nil || generationCutoff == nil {
      generationMaterial = material
      generationKey = UUID()
      generationCutoff = Date()
    }
    return (generationKey!, generationCutoff!)
  }

  @discardableResult
  func generate(
    client: any PlayerDevelopmentAIClient,
    organizationId: UUID,
    userId: UUID,
    playerId: UUID,
    window: SDDevelopmentWindow
  ) async -> Bool {
    guard !isGenerating, !mutationInFlight else { return false }
    let operation = generationOperation(
      organizationId: organizationId,
      playerId: playerId,
      window: window
    )
    isGenerating = true
    generationRetryAvailable = false
    successMessage = nil
    errorMessage = nil
    defer { isGenerating = false }
    do {
      let response = try await client.generateDevelopmentReport(
        organizationId: organizationId,
        playerId: playerId,
        reportType: .playerDevelopmentSummary,
        intendedAudience: "coach",
        window: window,
        evidenceCutoff: operation.cutoff,
        idempotencyKey: operation.key
      )
      guard acceptsResult(organizationId: organizationId, userId: userId) else { return false }
      evidencePack = response.evidencePack
      reports.removeAll(where: { $0.id == response.report.id })
      reports.insert(response.report, at: 0)
      successMessage = response.reused ? "Existing deterministic draft restored." : "Deterministic draft generated for coach review."
      generationRetryAvailable = false
      clearGenerationOperation()
      phase = .loaded
      return true
    } catch is CancellationError {
      return false
    } catch {
      errorMessage = error.localizedDescription
      generationRetryAvailable = true
      return false
    }
  }

  func runAlertDetection(
    client: any PlayerDevelopmentAIClient,
    organizationId: UUID,
    userId: UUID,
    playerId: UUID,
    window: SDDevelopmentWindow
  ) async {
    guard !mutationInFlight, !isGenerating else { return }
    mutationInFlight = true
    generationRetryAvailable = false
    defer { mutationInFlight = false }
    do {
      let response = try await client.runDevelopmentAlertDetection(
        organizationId: organizationId,
        playerId: playerId,
        window: window,
        evidenceCutoff: Date()
      )
      guard acceptsResult(organizationId: organizationId, userId: userId) else { return }
      alerts = response.alerts
      successMessage = "Alert review completed. \(response.detectedCount) supported alert\(response.detectedCount == 1 ? "" : "s") found."
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  func replaceReport(_ report: SDDevelopmentReport) {
    reports.removeAll(where: { $0.id == report.id })
    reports.insert(report, at: 0)
  }

  func replaceAlert(_ alert: SDDevelopmentAlert) {
    if let index = alerts.firstIndex(where: { $0.id == alert.id }) {
      alerts[index] = alert
    } else {
      alerts.insert(alert, at: 0)
    }
  }

  private func clearGenerationOperation() {
    generationMaterial = nil
    generationKey = nil
    generationCutoff = nil
  }
}

struct PlayerDevelopmentAIWorkspaceView: View {
  @EnvironmentObject private var appState: AppState
  @StateObject private var model = PlayerDevelopmentAIWorkspaceModel()
  let player: Profile

  @State private var reportingDays = 90
  @State private var selectedAlert: SDDevelopmentAlert?
  @State private var showDataImport = false
  @State private var showCoachCopilot = false

  private var window: SDDevelopmentWindow { .trailingDays(reportingDays) }
  private var contextKey: String {
    "\(appState.activeOrgAuthorizationKey):\(appState.myProfile?.id.uuidString ?? "none"):\(player.id.uuidString):\(reportingDays):\(appState.isPlayerDevelopmentCopilotEnabled)"
  }

  var body: some View {
    Group {
      if !appState.isPlayerDevelopmentCopilotEnabled {
        HPStateScreenLayout { _ in
          HPCard {
            HPEmptyState(
              title: "Feature unavailable",
              message: "Player Development AI and Copilot are currently disabled by Home Plate.",
              systemImage: "lock.fill"
            )
          }
        }
      } else if !SDDevelopmentPresentationAuthorization.isVisible(membership: appState.activeOrgMembership) {
        HPStateScreenLayout { _ in
          HPCard {
            HPEmptyState(
              title: "Staff access required",
              message: "Player Development AI is available only to active organization owners, admins, and coaches.",
              systemImage: "lock.fill"
            )
          }
        }
      } else if let service = appState.supabase,
                let organizationId = appState.activeOrgId,
                let userId = appState.myProfile?.id {
        workspace(service: service, organizationId: organizationId, userId: userId)
      } else {
        HPStateScreenLayout { _ in
          HPCard { HPLoadingState(text: "Loading organization…") }
        }
      }
    }
    .background(HP.Color.bg)
    .onDisappear { model.reset() }
    .sheet(isPresented: $showDataImport, onDismiss: {
      guard let service = appState.supabase,
            let organizationId = appState.activeOrgId,
            let userId = appState.myProfile?.id else { return }
      Task {
        await model.load(
          client: service,
          organizationId: organizationId,
          userId: userId,
          playerId: player.id,
          window: window
        )
      }
    }) {
      NavigationStack {
        PlayerDevelopmentImportWorkspaceView(player: player)
          .environmentObject(appState)
      }
      #if os(macOS)
      .onExitCommand { showDataImport = false }
      #endif
    }
    .sheet(isPresented: $showCoachCopilot) {
      NavigationStack {
        PlayerDevelopmentCopilotWorkspaceView(
          player: player,
          audience: .coach,
          presentationStyle: .modal
        )
          .environmentObject(appState)
      }
      #if os(macOS)
      .frame(minWidth: 760, minHeight: 720)
      #endif
    }
    .onChange(of: appState.isPlayerDevelopmentCopilotEnabled) { _, enabled in
      if !enabled {
        showCoachCopilot = false
        showDataImport = false
        model.reset()
      }
    }
  }

  private func workspace(
    service: SupabaseService,
    organizationId: UUID,
    userId: UUID
  ) -> some View {
    HPWorkspaceScreenLayout {
      header(service: service, organizationId: organizationId, userId: userId)
    } attention: {
      VStack(alignment: .leading, spacing: HP.Space.md) {
        workspaceControls

        if case .loading = model.phase {
          HPCard { HPLoadingState(text: "Building evidence view…") }
        }

        if let message = model.errorMessage {
          errorCard(
            message,
            retryTitle: model.generationRetryAvailable ? "Retry Generate Summary" : "Retry"
          ) {
            Task {
              if model.generationRetryAvailable {
                _ = await model.generate(
                  client: service,
                  organizationId: organizationId,
                  userId: userId,
                  playerId: player.id,
                  window: window
                )
              } else {
                await model.load(
                  client: service,
                  organizationId: organizationId,
                  userId: userId,
                  playerId: player.id,
                  window: window
                )
              }
            }
          }
        }
        if let message = model.successMessage {
          HPCard {
            Label(message, systemImage: "checkmark.circle.fill")
              .font(HP.Font.callout)
              .foregroundStyle(HP.Color.success)
              .fixedSize(horizontal: false, vertical: true)
          }
        }
        if let pack = model.evidencePack {
          evidenceStatusCard(pack)
        }
      }
    } metrics: {
      if let pack = model.evidencePack {
        coverageMetrics(pack)
      }
    } supporting: {
      VStack(alignment: .leading, spacing: HP.Space.md) {
        if let pack = model.evidencePack {
          trendCard(pack)
        }
        latestReportCard(organizationId: organizationId)
        alertsCard(service: service, organizationId: organizationId, userId: userId)
        historyCard(organizationId: organizationId)
      }
    }
    .task(id: contextKey) {
      guard appState.isPlayerDevelopmentCopilotEnabled else {
        model.reset()
        return
      }
      model.reset()
      await model.load(
        client: service,
        organizationId: organizationId,
        userId: userId,
        playerId: player.id,
        window: window
      )
    }
    .sheet(item: $selectedAlert) { alert in
      DevelopmentAlertDetailView(
        alert: alert,
        organizationId: organizationId,
        onUpdated: { model.replaceAlert($0) }
      )
      .environmentObject(appState)
    }
  }

  private func header(service: SupabaseService, organizationId: UUID, userId: UUID) -> some View {
    HPWorkspaceHeader(
      "Player Development AI",
      orgLabel: activeOrganizationName,
      context: "\(player.displayName) • Trailing \(reportingDays)-day evidence window"
    ) {
      HPButton(
        title: model.isGenerating ? "Generating…" : "Generate Summary",
        systemImage: "sparkles",
        variant: .primary,
        size: .sm,
        isLoading: model.isGenerating,
        action: {
          Task {
            _ = await model.generate(
              client: service,
              organizationId: organizationId,
              userId: userId,
              playerId: player.id,
              window: window
            )
          }
        }
      )
      .disabled(model.isGenerating || model.mutationInFlight)
    }
  }

  private var activeOrganizationName: String {
    if let organizationId = appState.activeOrgId,
       let organization = appState.availableOrganizations.first(where: { $0.id == organizationId }) {
      return organization.displayName
    }
    return appState.activeOrgSettings?.display_name
      ?? appState.activeOrgSettings?.short_name
      ?? "Home Plate"
  }

  private var workspaceControls: some View {
    HPCard {
      VStack(alignment: .leading, spacing: HP.Space.sm) {
        HPSectionHeader("Workspace controls")
        ViewThatFits(in: .horizontal) {
          HStack(spacing: HP.Space.sm) {
            reportingWindowPicker
            importButton
            copilotButton
          }
          VStack(alignment: .leading, spacing: HP.Space.sm) {
            reportingWindowPicker
            importButton(fullWidth: true)
            copilotButton(fullWidth: true)
          }
        }
      }
    }
  }

  private var reportingWindowPicker: some View {
    Picker("Window", selection: $reportingDays) {
      Text("30 days").tag(30)
      Text("90 days").tag(90)
      Text("180 days").tag(180)
      Text("1 year").tag(365)
    }
    .pickerStyle(.menu)
    .tint(HP.Color.accent)
    .frame(minHeight: 44)
  }

  private var importButton: some View {
    importButton(fullWidth: false)
  }

  private func importButton(fullWidth: Bool) -> some View {
    HPButton(
      title: "Import Data",
      systemImage: "square.and.arrow.down",
      variant: .secondary,
      size: .md,
      fullWidth: fullWidth,
      action: { showDataImport = true }
    )
    .disabled(model.isGenerating || model.mutationInFlight)
  }

  private var copilotButton: some View {
    copilotButton(fullWidth: false)
  }

  private func copilotButton(fullWidth: Bool) -> some View {
    HPButton(
      title: "Coach Copilot",
      systemImage: "bubble.left.and.text.bubble.right.fill",
      variant: .secondary,
      size: .md,
      fullWidth: fullWidth,
      action: { showCoachCopilot = true }
    )
    .disabled(model.isGenerating || model.mutationInFlight)
  }

  private func evidenceStatusCard(_ pack: SDDevelopmentEvidencePack) -> some View {
    HPCard {
      VStack(alignment: .leading, spacing: HP.Space.sm) {
        HPSectionHeader("Evidence status") {
          ViewThatFits(in: .horizontal) {
            HStack(spacing: HP.Space.xs) {
              qualityBadge(pack.qualityStatus)
              freshnessBadge(pack.dataFreshness)
            }
            VStack(alignment: .leading, spacing: HP.Space.xs) {
              qualityBadge(pack.qualityStatus)
              freshnessBadge(pack.dataFreshness)
            }
          }
        }
        if !pack.missingDataWarnings.isEmpty || !pack.staleDataWarnings.isEmpty || !pack.unitConflicts.isEmpty {
          Divider().overlay(HP.Color.border)
          ForEach(pack.missingDataWarnings + pack.staleDataWarnings + pack.unitConflicts, id: \.self) { warning in
            Label(warning, systemImage: "info.circle")
              .font(HP.Font.caption)
              .foregroundStyle(HP.Color.textMuted)
              .fixedSize(horizontal: false, vertical: true)
          }
        }
      }
    }
  }

  @ViewBuilder
  private func coverageMetrics(_ pack: SDDevelopmentEvidencePack) -> some View {
    HPMetricCard(title: "Testing", value: pack.coverage.testingEntries.formatted(), context: "Evidence entries")
    HPMetricCard(title: "Metrics", value: pack.coverage.metricObservations.formatted(), context: "Objective observations")
    HPMetricCard(title: "Daily logs", value: pack.coverage.dailyLogs.formatted(), context: "Available logs")
    HPMetricCard(title: "Programs", value: pack.coverage.programAssignments.formatted(), context: "Assignments")
    HPMetricCard(title: "BP", value: pack.coverage.bpSessions.formatted(), context: "Batting-practice sessions")
  }

  private func trendCard(_ pack: SDDevelopmentEvidencePack) -> some View {
    HPCard {
      VStack(alignment: .leading, spacing: HP.Space.sm) {
        HPSectionHeader("Deterministic trends") {
          HPStatusBadge(text: "\(pack.trends.count)", kind: .neutral)
        }
        if pack.trends.isEmpty {
          Text("No supported comparable trends are available for this window.")
            .font(HP.Font.callout)
            .foregroundStyle(HP.Color.textMuted)
        } else {
          ForEach(pack.trends) { trend in
            ViewThatFits(in: .horizontal) {
              HStack(alignment: .top, spacing: HP.Space.sm) {
                trendSummary(trend)
                Spacer(minLength: 0)
                trendBadge(trend.interpretation)
              }
              VStack(alignment: .leading, spacing: HP.Space.xs) {
                trendSummary(trend)
                trendBadge(trend.interpretation)
              }
            }
            if trend.id != pack.trends.last?.id { Divider().overlay(HP.Color.border) }
          }
        }
      }
    }
  }

  private func trendSummary(_ trend: SDDevelopmentTrend) -> some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(trend.displayName)
        .font(HP.Font.headline)
        .foregroundStyle(HP.Color.text)
      Text("Latest \(format(trend.latestValue))\(trend.unit.map { " \($0)" } ?? "") • \(trend.sampleCount) sample\(trend.sampleCount == 1 ? "" : "s")")
        .font(HP.Font.caption)
        .foregroundStyle(HP.Color.textMuted)
        .fixedSize(horizontal: false, vertical: true)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func latestReportCard(organizationId: UUID) -> some View {
    HPCard {
      VStack(alignment: .leading, spacing: HP.Space.sm) {
        HPSectionHeader("Latest report") {
          if let report = model.latestReport { reportStatusBadge(report.status) }
        }
        if let report = model.latestReport {
          Text(report.structuredContent.overview)
            .font(HP.Font.callout)
            .foregroundStyle(HP.Color.text)
            .fixedSize(horizontal: false, vertical: true)
          reportSections("Positive trends", report.structuredContent.positiveTrends)
          reportSections("Development priorities", report.structuredContent.developmentPriorities)
          Text(report.structuredContent.consistencyAndAttendance)
            .font(HP.Font.caption)
            .foregroundStyle(HP.Color.textMuted)
            .fixedSize(horizontal: false, vertical: true)
          NavigationLink {
            DevelopmentReportDetailView(organizationId: organizationId, reportId: report.id) {
              model.replaceReport($0)
            }
            .environmentObject(appState)
          } label: {
            HStack(spacing: HP.Space.sm) {
              Image(systemName: "doc.text.magnifyingglass")
                .foregroundStyle(HP.Color.accent)
              Text("Review report and evidence")
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
        } else if model.phase == .loaded {
          Text("No deterministic report has been generated for this player.")
            .font(HP.Font.callout)
            .foregroundStyle(HP.Color.textMuted)
        }
      }
    }
  }

  @ViewBuilder
  private func reportSections(_ title: String, _ sections: [SDDevelopmentReportSection]) -> some View {
    if !sections.isEmpty {
      Text(title)
        .font(HP.Font.headline)
        .foregroundStyle(HP.Color.text)
      ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
        VStack(alignment: .leading, spacing: 3) {
          Text(section.title)
            .font(HP.Font.callout.weight(.semibold))
            .foregroundStyle(HP.Color.text)
          Text(section.explanation)
            .font(HP.Font.caption)
            .foregroundStyle(HP.Color.textMuted)
          Text("Evidence: \(section.evidenceKeys.joined(separator: ", "))")
            .font(HP.Font.caption.monospaced())
            .foregroundStyle(HP.Color.textMuted)
            .textSelection(.enabled)
        }
      }
    }
  }

  private func alertsCard(service: SupabaseService, organizationId: UUID, userId: UUID) -> some View {
    HPCard {
      VStack(alignment: .leading, spacing: HP.Space.sm) {
        HPSectionHeader("Development alerts") {
          HPButton(
            title: "Run detection",
            systemImage: "waveform.path.ecg",
            variant: .secondary,
            size: .sm,
            action: {
              Task {
                await model.runAlertDetection(
                  client: service,
                  organizationId: organizationId,
                  userId: userId,
                  playerId: player.id,
                  window: window
                )
              }
            }
          )
          .disabled(model.mutationInFlight || model.isGenerating)
        }
        if model.alerts.isEmpty {
          Text("No persisted development alerts for this player.")
            .font(HP.Font.callout)
            .foregroundStyle(HP.Color.textMuted)
        } else {
          ForEach(model.alerts) { alert in
            Button {
              selectedAlert = alert
            } label: {
              ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: HP.Space.sm) {
                  alertSummary(alert)
                  Spacer(minLength: 0)
                  severityBadge(alert.severity)
                }
                VStack(alignment: .leading, spacing: 3) {
                  alertSummary(alert)
                  severityBadge(alert.severity)
                }
              }
              .frame(minHeight: 44)
              .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
          }
        }
      }
    }
  }

  private func alertSummary(_ alert: SDDevelopmentAlert) -> some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(alert.alertType.replacingOccurrences(of: "_", with: " ").capitalized)
        .font(HP.Font.headline)
        .foregroundStyle(HP.Color.text)
      Text(alert.explanation)
        .font(HP.Font.caption)
        .foregroundStyle(HP.Color.textMuted)
        .multilineTextAlignment(.leading)
        .fixedSize(horizontal: false, vertical: true)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func historyCard(organizationId: UUID) -> some View {
    HPCard {
      VStack(alignment: .leading, spacing: HP.Space.sm) {
        HPSectionHeader("Report history") {
          HPStatusBadge(text: "\(model.reports.count)", kind: .neutral)
        }
        if model.reports.isEmpty {
          Text("Report history is empty.")
            .font(HP.Font.callout)
            .foregroundStyle(HP.Color.textMuted)
        } else {
          ForEach(model.reports) { report in
            NavigationLink {
              DevelopmentReportDetailView(organizationId: organizationId, reportId: report.id) {
                model.replaceReport($0)
              }
              .environmentObject(appState)
            } label: {
              ViewThatFits(in: .horizontal) {
                HStack(spacing: HP.Space.sm) {
                  historySummary(report)
                  Spacer(minLength: 0)
                  reportStatusBadge(report.status)
                }
                VStack(alignment: .leading, spacing: 2) {
                  historySummary(report)
                  reportStatusBadge(report.status)
                }
              }
              .frame(minHeight: 44)
              .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
          }
        }
      }
    }
  }

  private func historySummary(_ report: SDDevelopmentReport) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(report.reportType.replacingOccurrences(of: "_", with: " ").capitalized)
        .font(HP.Font.headline)
        .foregroundStyle(HP.Color.text)
      Text("\(report.reportingWindowStart) – \(report.reportingWindowEnd)")
        .font(HP.Font.caption)
        .foregroundStyle(HP.Color.textMuted)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func errorCard(
    _ message: String,
    retryTitle: String = "Retry",
    retry: @escaping () -> Void
  ) -> some View {
    HPCard {
      VStack(alignment: .leading, spacing: HP.Space.sm) {
        Label("Something went wrong", systemImage: "exclamationmark.triangle.fill")
          .font(HP.Font.headline)
          .foregroundStyle(HP.Color.danger)
        Text(message)
          .font(HP.Font.callout)
          .foregroundStyle(HP.Color.textMuted)
          .fixedSize(horizontal: false, vertical: true)
        HPButton(
          title: retryTitle,
          systemImage: "arrow.clockwise",
          variant: .secondary,
          size: .md,
          action: retry
        )
      }
    }
  }
}

struct DevelopmentReportDetailView: View {
  @EnvironmentObject private var appState: AppState
  @Environment(\.dismiss) private var dismiss
  let organizationId: UUID
  let reportId: UUID
  let onUpdated: (SDDevelopmentReport) -> Void

  @State private var detail: SDDevelopmentReportDetail?
  @State private var notes = ""
  @State private var isLoading = false
  @State private var isMutating = false
  @State private var errorMessage: String?

  private var hasCurrentAccess: Bool {
    SDDevelopmentPresentationAuthorization.isVisible(
      membership: appState.activeOrgMembership,
      selectedOrganizationId: appState.activeOrgId,
      resourceOrganizationId: organizationId
    )
  }

  private var contextKey: String {
    "\(reportId.uuidString):\(appState.activeOrgAuthorizationKey)"
  }

  var body: some View {
    Group {
      if !appState.isPlayerDevelopmentCopilotEnabled {
        HPStateScreenLayout { _ in
          HPCard {
            HPEmptyState(
              title: "Feature unavailable",
              message: "Player Development AI and Copilot are currently disabled by Home Plate.",
              systemImage: "lock.fill"
            )
          }
        }
      } else if hasCurrentAccess {
        reportWorkspace
      } else {
        HPStateScreenLayout { _ in
          HPCard {
            HPEmptyState(
              title: "Report unavailable",
              message: "Return to the report's active organization with staff access.",
              systemImage: "lock.fill"
            )
          }
        }
      }
    }
    .background(HP.Color.bg)
    .navigationTitle("Development report")
    .navigationBarBackButtonHidden(true)
    .toolbar {
      ToolbarItem(placement: .cancellationAction) {
        Button {
          dismiss()
        } label: {
#if os(macOS)
          Label("Close", systemImage: "xmark")
#else
          Label("Back", systemImage: "chevron.backward")
#endif
        }
#if os(macOS)
        .keyboardShortcut(.cancelAction)
#endif
        .accessibilityIdentifier("development-report-dismiss")
      }
    }
    .task(id: "\(contextKey):\(appState.isPlayerDevelopmentCopilotEnabled)") {
      guard appState.isPlayerDevelopmentCopilotEnabled, hasCurrentAccess else {
        detail = nil
        errorMessage = nil
        return
      }
      await load()
    }
  }

  private var reportWorkspace: some View {
    HPDetailScreenLayout {
      if let report = detail?.report {
        reportHeader(report)
      } else {
        HPWorkspaceHeader(
          "Development report",
          orgLabel: "Player Development",
          context: "Loading report identity and evidence"
        )
      }
    } metrics: {
      if let report = detail?.report {
        reportMetrics(report)
      }
    } details: {
      VStack(alignment: .leading, spacing: HP.Space.md) {
        if isLoading && detail == nil {
          HPCard { HPLoadingState(text: "Loading report…") }
        }
        if let errorMessage {
          HPCard { HPErrorState(title: "Report unavailable", message: errorMessage) }
        }
        if let detail {
          metadataCard(detail.report)
          contentCard(detail.report)
        }
      }
    } related: { context in
      VStack(alignment: .leading, spacing: HP.Space.md) {
        if let detail {
          evidenceCard(detail.evidence)
          reviewCard(detail.report, context: context)
          auditCard(detail.reviewHistory)
        }
      }
    } primaryAction: {
      EmptyView()
    }
  }

  private func reportHeader(_ report: SDDevelopmentReport) -> some View {
    HPWorkspaceHeader(
      report.reportType.replacingOccurrences(of: "_", with: " ").capitalized,
      orgLabel: "Player Development",
      context: "Window \(report.reportingWindowStart) – \(report.reportingWindowEnd)"
    )
  }

  @ViewBuilder
  private func reportMetrics(_ report: SDDevelopmentReport) -> some View {
    HPMetricCard(title: "Status", value: report.status.rawValue.capitalized, context: "Coach review lifecycle")
    HPMetricCard(title: "Quality", value: report.qualityStatus.rawValue.capitalized, context: "Evidence quality")
    HPMetricCard(title: "Mode", value: report.generationMode.capitalized, context: "Generation mode")
    HPMetricCard(title: "Evidence", value: detail?.evidence.count.formatted() ?? "0", context: "Cited snapshots")
  }

  private func metadataCard(_ report: SDDevelopmentReport) -> some View {
    HPCard {
      VStack(alignment: .leading, spacing: HP.Space.sm) {
        HPSectionHeader("Report provenance") {
          ViewThatFits(in: .horizontal) {
            HStack(spacing: HP.Space.xs) {
              reportStatusBadge(report.status)
              qualityBadge(report.qualityStatus)
              HPStatusBadge(text: report.generationMode.capitalized, kind: .gold)
            }
            VStack(alignment: .leading, spacing: HP.Space.xs) {
              reportStatusBadge(report.status)
              qualityBadge(report.qualityStatus)
              HPStatusBadge(text: report.generationMode.capitalized, kind: .gold)
            }
          }
        }
        developmentMetadataRow("Reporting window", value: "\(report.reportingWindowStart) – \(report.reportingWindowEnd)")
        developmentMetadataRow("Evidence cutoff", value: report.inputCutoff)
        developmentMetadataRow("Generator", value: "\(report.generatorVersion) • \(report.promptVersion)")
        if let fingerprint = report.evidenceFingerprint {
          VStack(alignment: .leading, spacing: 3) {
            Text("EVIDENCE SHA-256")
              .font(HP.Font.eyebrow)
              .tracking(HP.Font.eyebrowTracking)
              .foregroundStyle(HP.Color.textMuted)
            Text(fingerprint)
              .font(HP.Font.caption.monospaced())
              .foregroundStyle(HP.Color.text)
              .textSelection(.enabled)
              .fixedSize(horizontal: false, vertical: true)
          }
        }
      }
    }
  }

  private func contentCard(_ report: SDDevelopmentReport) -> some View {
    HPCard {
      VStack(alignment: .leading, spacing: HP.Space.sm) {
        HPSectionHeader("Structured draft")
        Text(report.structuredContent.overview)
          .font(HP.Font.callout)
          .foregroundStyle(HP.Color.text)
          .fixedSize(horizontal: false, vertical: true)
        section("Positive trends", report.structuredContent.positiveTrends)
        section("Development priorities", report.structuredContent.developmentPriorities)
        Text("Consistency and attendance").font(HP.Font.headline).foregroundStyle(HP.Color.text)
        Text(report.structuredContent.consistencyAndAttendance)
          .font(HP.Font.callout)
          .foregroundStyle(HP.Color.text)
          .fixedSize(horizontal: false, vertical: true)
        if !report.structuredContent.dataGaps.isEmpty {
          Text("Data gaps").font(HP.Font.headline).foregroundStyle(HP.Color.text)
          ForEach(report.structuredContent.dataGaps, id: \.self) {
            Text("• \($0)")
              .font(HP.Font.callout)
              .foregroundStyle(HP.Color.text)
              .fixedSize(horizontal: false, vertical: true)
          }
        }
        if !report.structuredContent.coachReviewQuestions.isEmpty {
          Text("Coach review questions").font(HP.Font.headline).foregroundStyle(HP.Color.text)
          ForEach(report.structuredContent.coachReviewQuestions, id: \.self) {
            Text("• \($0)")
              .font(HP.Font.callout)
              .foregroundStyle(HP.Color.text)
              .fixedSize(horizontal: false, vertical: true)
          }
        }
      }
    }
  }

  @ViewBuilder
  private func section(_ title: String, _ rows: [SDDevelopmentReportSection]) -> some View {
    if !rows.isEmpty {
      Text(title).font(HP.Font.headline).foregroundStyle(HP.Color.text)
      ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
        VStack(alignment: .leading, spacing: 3) {
          Text(row.title).font(HP.Font.callout.weight(.semibold)).foregroundStyle(HP.Color.text)
          Text(row.explanation)
            .font(HP.Font.callout)
            .foregroundStyle(HP.Color.text)
            .fixedSize(horizontal: false, vertical: true)
          Text("Evidence \(row.evidenceKeys.joined(separator: ", "))")
            .font(HP.Font.caption.monospaced())
            .foregroundStyle(HP.Color.textMuted)
            .textSelection(.enabled)
        }
      }
    }
  }

  private func evidenceCard(_ evidence: [SDDevelopmentEvidence]) -> some View {
    HPCard {
      VStack(alignment: .leading, spacing: HP.Space.sm) {
        HPSectionHeader("Evidence snapshots") {
          HPStatusBadge(text: "\(evidence.count)", kind: .neutral)
        }
        if evidence.isEmpty {
          Text("No source evidence was available for this draft.")
            .font(HP.Font.callout)
            .foregroundStyle(HP.Color.textMuted)
        } else {
          ForEach(evidence) { item in
            ViewThatFits(in: .horizontal) {
              HStack(alignment: .top, spacing: HP.Space.sm) {
                evidenceSummary(item)
                Spacer(minLength: 0)
                qualityBadge(item.quality)
              }
              VStack(alignment: .leading, spacing: HP.Space.xs) {
                evidenceSummary(item)
                qualityBadge(item.quality)
              }
            }
            if item.id != evidence.last?.id { Divider().overlay(HP.Color.border) }
          }
        }
      }
    }
  }

  private func evidenceSummary(_ item: SDDevelopmentEvidence) -> some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(item.displayLabel).font(HP.Font.headline).foregroundStyle(HP.Color.text)
      Text(item.explanation)
        .font(HP.Font.caption)
        .foregroundStyle(HP.Color.text)
        .fixedSize(horizontal: false, vertical: true)
      Text("\(item.sourceEntityType) • \(item.sourceRecordId) • \(item.deterministicRuleId ?? "source")")
        .font(HP.Font.caption.monospaced())
        .foregroundStyle(HP.Color.textMuted)
        .textSelection(.enabled)
        .fixedSize(horizontal: false, vertical: true)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func reviewCard(_ report: SDDevelopmentReport, context: HPScreenLayoutContext) -> some View {
    HPCard {
      VStack(alignment: .leading, spacing: HP.Space.sm) {
        HPSectionHeader("Coach review")
        HPFormField(
          label: "Review notes",
          text: $notes,
          kind: .multiline,
          placeholder: "Add coach review notes"
        )
        if context.isAccessibilitySize || !context.isRegularWidth {
          VStack(alignment: .leading, spacing: HP.Space.sm) {
            reviewButtons(report, fullWidth: true)
          }
        } else {
          HStack(spacing: HP.Space.sm) {
            reviewButtons(report)
          }
        }
        if isMutating { HPLoadingState(text: "Updating report…") }
      }
    }
  }

  @ViewBuilder
  private func reviewButtons(_ report: SDDevelopmentReport, fullWidth: Bool = false) -> some View {
    HPButton(
      title: "Mark reviewed",
      variant: .secondary,
      size: .md,
      fullWidth: fullWidth,
      action: { Task { await review(.review) } }
    )
    .disabled(isMutating || !report.status.isReviewable)
    HPButton(
      title: "Approve",
      variant: .primary,
      size: .md,
      fullWidth: fullWidth,
      action: { Task { await review(.approve) } }
    )
    .disabled(isMutating || !report.status.isReviewable)
    HPButton(
      title: "Reject",
      variant: .destructive,
      size: .md,
      fullWidth: fullWidth,
      action: { Task { await review(.reject) } }
    )
    .disabled(isMutating || !report.status.isReviewable)
    HPButton(
      title: "Archive",
      variant: .secondary,
      size: .md,
      fullWidth: fullWidth,
      action: { Task { await review(.archive) } }
    )
    .disabled(isMutating || !report.status.canArchive)
  }

  private func auditCard(_ history: [SDDevelopmentReviewEvent]) -> some View {
    HPCard {
      VStack(alignment: .leading, spacing: HP.Space.sm) {
        HPSectionHeader("Review history") {
          HPStatusBadge(text: "\(history.count)", kind: .neutral)
        }
        if history.isEmpty {
          Text("No review events.")
            .font(HP.Font.callout)
            .foregroundStyle(HP.Color.textMuted)
        }
        ForEach(history) { event in
          Text("\(event.eventType.capitalized): \(event.fromStatus ?? "—") → \(event.toStatus) • \(event.createdAt)")
            .font(HP.Font.caption)
            .foregroundStyle(HP.Color.text)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
    }
  }

  private func load() async {
    guard hasCurrentAccess, let service = appState.supabase else { return }
    isLoading = true
    defer { isLoading = false }
    do {
      detail = try await service.developmentReportDetail(organizationId: organizationId, reportId: reportId)
      notes = detail?.report.reviewNotes ?? ""
    } catch { errorMessage = error.localizedDescription }
  }

  private func review(_ action: SDDevelopmentReviewAction) async {
    guard hasCurrentAccess, let service = appState.supabase, !isMutating else { return }
    isMutating = true
    defer { isMutating = false }
    do {
      let updated = try await service.reviewDevelopmentReport(
        organizationId: organizationId,
        reportId: reportId,
        action: action,
        notes: notes,
        coachEdits: [:]
      )
      onUpdated(updated)
      await load()
    } catch { errorMessage = error.localizedDescription }
  }
}

struct DevelopmentAlertDetailView: View {
  @EnvironmentObject private var appState: AppState
  @Environment(\.dismiss) private var dismiss
  @State private var current: SDDevelopmentAlert
  @State private var notes = ""
  @State private var isWorking = false
  @State private var isLoading = false
  @State private var detail: SDDevelopmentAlertDetail?
  @State private var errorMessage: String?
  let organizationId: UUID
  let onUpdated: (SDDevelopmentAlert) -> Void

  private var hasCurrentAccess: Bool {
    SDDevelopmentPresentationAuthorization.isVisible(
      membership: appState.activeOrgMembership,
      selectedOrganizationId: appState.activeOrgId,
      resourceOrganizationId: organizationId
    )
  }

  private var contextKey: String {
    "\(current.id.uuidString):\(appState.activeOrgAuthorizationKey)"
  }

  init(alert: SDDevelopmentAlert, organizationId: UUID, onUpdated: @escaping (SDDevelopmentAlert) -> Void) {
    _current = State(initialValue: alert)
    self.organizationId = organizationId
    self.onUpdated = onUpdated
  }

  var body: some View {
    NavigationStack {
      Group {
        if !appState.isPlayerDevelopmentCopilotEnabled {
          HPStateScreenLayout { _ in
            HPCard {
              HPEmptyState(
                title: "Feature unavailable",
                message: "Player Development AI and Copilot are currently disabled by Home Plate.",
                systemImage: "lock.fill"
              )
            }
          }
        } else if hasCurrentAccess {
          alertDetail
        } else {
          HPStateScreenLayout { _ in
            HPCard {
              HPEmptyState(
                title: "Alert unavailable",
                message: "Return to the alert's active organization with staff access.",
                systemImage: "lock.fill"
              )
            }
          }
        }
      }
      .background(HP.Color.bg)
      .navigationTitle("Development alert")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Done") { dismiss() }
            #if os(macOS)
            .keyboardShortcut(.cancelAction)
            #endif
        }
      }
      .task(id: "\(contextKey):\(appState.isPlayerDevelopmentCopilotEnabled)") {
        guard appState.isPlayerDevelopmentCopilotEnabled, hasCurrentAccess else {
          detail = nil
          errorMessage = nil
          return
        }
        await loadDetail()
      }
    }
  }

  private var alertDetail: some View {
    HPDetailScreenLayout {
      HPWorkspaceHeader(
        "Development alert",
        orgLabel: "Player Development",
        context: "\(current.evidenceWindowStart) – \(current.evidenceWindowEnd)"
      )
    } metrics: {
      HPMetricCard(title: "Severity", value: current.severity.rawValue.capitalized, context: "Review priority")
      HPMetricCard(title: "Status", value: current.status.rawValue.capitalized, context: "Review lifecycle")
      HPMetricCard(title: "Freshness", value: current.dataFreshness.capitalized, context: "Evidence recency")
      HPMetricCard(title: "Quality", value: current.evidenceQuality.rawValue.capitalized, context: "Evidence quality")
    } details: {
      VStack(alignment: .leading, spacing: HP.Space.md) {
        if isLoading { HPCard { HPLoadingState(text: "Loading evidence…") } }
        if let errorMessage {
          HPCard { HPErrorState(title: "Alert evidence unavailable", message: errorMessage) }
        }
        alertSummaryCard
        recommendationCard
        alertEvidenceCard
        if let history = detail?.reviewHistory, !history.isEmpty {
          alertHistoryCard(history)
        }
        HPCard {
          HPFormField(
            label: "Review notes",
            text: $notes,
            kind: .multiline,
            placeholder: "Add review notes"
          )
        }
      }
    } related: { context in
      reviewActionCard(context)
    } primaryAction: {
      EmptyView()
    }
  }

  private var alertSummaryCard: some View {
    HPCard {
      VStack(alignment: .leading, spacing: HP.Space.sm) {
        HPSectionHeader("Alert") {
          ViewThatFits(in: .horizontal) {
            HStack(spacing: HP.Space.xs) {
              severityBadge(current.severity)
              HPStatusBadge(text: current.status.rawValue.capitalized, kind: .neutral)
            }
            VStack(alignment: .leading, spacing: HP.Space.xs) {
              severityBadge(current.severity)
              HPStatusBadge(text: current.status.rawValue.capitalized, kind: .neutral)
            }
          }
        }
        developmentMetadataRow("Type", value: current.alertType.replacingOccurrences(of: "_", with: " ").capitalized)
        developmentMetadataRow("Window", value: "\(current.evidenceWindowStart) – \(current.evidenceWindowEnd)")
        developmentMetadataRow("First detected", value: current.firstDetectedAt)
        developmentMetadataRow("Last detected", value: current.lastDetectedAt)
        Text(current.explanation)
          .font(HP.Font.callout)
          .foregroundStyle(HP.Color.text)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }

  private var recommendationCard: some View {
    HPCard {
      VStack(alignment: .leading, spacing: HP.Space.sm) {
        HPSectionHeader("Recommended human review")
        Text(current.recommendedHumanAction)
          .font(HP.Font.callout)
          .foregroundStyle(HP.Color.text)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }

  private var alertEvidenceCard: some View {
    HPCard {
      VStack(alignment: .leading, spacing: HP.Space.sm) {
        HPSectionHeader("Evidence") {
          HPStatusBadge(text: "\(detail?.evidence.count ?? 0)", kind: .neutral)
        }
        if let evidence = detail?.evidence, !evidence.isEmpty {
          ForEach(evidence) { item in
            VStack(alignment: .leading, spacing: 3) {
              Text(item.displayLabel).font(HP.Font.headline).foregroundStyle(HP.Color.text)
              Text(item.explanation)
                .font(HP.Font.caption)
                .foregroundStyle(HP.Color.text)
                .fixedSize(horizontal: false, vertical: true)
              Text("\(item.sourceEntityType) • \(item.sourceRecordId)")
                .font(HP.Font.caption.monospaced())
                .foregroundStyle(HP.Color.textMuted)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            }
          }
        } else if !isLoading {
          Text("This alert is based on an explicit missing-data rule or has no measurement snapshot.")
            .font(HP.Font.callout)
            .foregroundStyle(HP.Color.textMuted)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
    }
  }

  private func alertHistoryCard(_ history: [SDDevelopmentAlertEvent]) -> some View {
    HPCard {
      VStack(alignment: .leading, spacing: HP.Space.sm) {
        HPSectionHeader("Review history") {
          HPStatusBadge(text: "\(history.count)", kind: .neutral)
        }
        ForEach(history) { event in
          Text("\(event.eventType.capitalized): \(event.fromStatus ?? "—") → \(event.toStatus) • \(event.createdAt)")
            .font(HP.Font.caption)
            .foregroundStyle(HP.Color.text)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
    }
  }

  private func reviewActionCard(_ context: HPScreenLayoutContext) -> some View {
    HPCard {
      VStack(alignment: .leading, spacing: HP.Space.sm) {
        HPSectionHeader("Review actions")
        if context.isAccessibilitySize || !context.isRegularWidth {
          VStack(alignment: .leading, spacing: HP.Space.sm) {
            alertReviewButtons(fullWidth: true)
          }
        } else {
          HStack(spacing: HP.Space.sm) {
            alertReviewButtons()
          }
        }
        if isWorking { HPLoadingState(text: "Updating alert…") }
      }
      .disabled(isWorking || [.dismissed, .resolved, .archived].contains(current.status))
    }
  }

  @ViewBuilder
  private func alertReviewButtons(fullWidth: Bool = false) -> some View {
    HPButton(
      title: "Acknowledge",
      variant: .primary,
      size: .md,
      fullWidth: fullWidth,
      action: { Task { await update(.acknowledge) } }
    )
    HPButton(
      title: "Dismiss",
      variant: .secondary,
      size: .md,
      fullWidth: fullWidth,
      action: { Task { await update(.dismiss) } }
    )
    HPButton(
      title: "Resolve",
      variant: .secondary,
      size: .md,
      fullWidth: fullWidth,
      action: { Task { await update(.resolve) } }
    )
    HPButton(
      title: "Archive",
      variant: .secondary,
      size: .md,
      fullWidth: fullWidth,
      action: { Task { await update(.archive) } }
    )
  }

  private func update(_ action: SDDevelopmentAlertReviewAction) async {
    guard hasCurrentAccess, let service = appState.supabase, !isWorking else { return }
    isWorking = true
    defer { isWorking = false }
    do {
      current = try await service.reviewDevelopmentAlert(
        organizationId: organizationId,
        alertId: current.id,
        action: action,
        notes: notes
      )
      onUpdated(current)
      await loadDetail()
    } catch { errorMessage = error.localizedDescription }
  }

  private func loadDetail() async {
    guard hasCurrentAccess, let service = appState.supabase else { return }
    isLoading = true
    defer { isLoading = false }
    do {
      detail = try await service.developmentAlertDetail(
        organizationId: organizationId,
        alertId: current.id
      )
      current = detail?.alert ?? current
    } catch {
      errorMessage = error.localizedDescription
    }
  }
}

@MainActor
final class DevelopmentRosterAttentionModel: ObservableObject {
  @Published private(set) var response: SDDevelopmentRosterAttentionResponse?
  @Published private(set) var isLoading = false
  @Published var errorMessage: String?
  private var token: SDDevelopmentRequestToken?

  func load(client: any PlayerDevelopmentAIClient, organizationId: UUID, userId: UUID) async {
    let request = SDDevelopmentRequestToken(organizationId: organizationId, userId: userId, nonce: UUID())
    token = request
    isLoading = true
    errorMessage = nil
    do {
      let result = try await client.developmentRosterAttention(organizationId: organizationId)
      guard token == request else { return }
      response = result
    } catch is CancellationError {
      return
    } catch {
      guard token == request else { return }
      errorMessage = error.localizedDescription
      response = nil
    }
    if token == request { isLoading = false }
  }

  func reset() {
    token = nil
    response = nil
    isLoading = false
    errorMessage = nil
  }
}

struct DevelopmentRosterAttentionView: View {
  @EnvironmentObject private var appState: AppState
  @Environment(\.dismiss) private var dismiss
  @StateObject private var model = DevelopmentRosterAttentionModel()
  @State private var search = ""
  @State private var severity = "all"
  let players: [Profile]

  private var filteredAlerts: [SDDevelopmentAlert] {
    let query = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return (model.response?.alerts ?? []).filter { alert in
      (severity == "all" || alert.severity.rawValue == severity) &&
        (query.isEmpty || (alert.playerName ?? player(alert.playerId)?.displayName ?? "").lowercased().contains(query))
    }
  }

  var body: some View {
    NavigationStack {
      Group {
        if !appState.isPlayerDevelopmentCopilotEnabled {
          HPStateScreenLayout { _ in
            HPCard {
              HPEmptyState(
                title: "Feature unavailable",
                message: "Player Development AI and Copilot are currently disabled by Home Plate.",
                systemImage: "lock.fill"
              )
            }
          }
        } else if SDDevelopmentPresentationAuthorization.isVisible(membership: appState.activeOrgMembership) {
          rosterList
        } else {
          HPStateScreenLayout { _ in
            HPCard {
              HPEmptyState(
                title: "Staff access required",
                message: "Roster Attention is available only to active organization staff.",
                systemImage: "lock.fill"
              )
            }
          }
        }
      }
      .background(HP.Color.bg)
      .navigationTitle("Roster Attention")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Done") { dismiss() }
            #if os(macOS)
            .keyboardShortcut(.cancelAction)
            #endif
        }
      }
      .task(id: "\(appState.activeOrgAuthorizationKey):\(appState.myProfile?.id.uuidString ?? "none"):\(appState.isPlayerDevelopmentCopilotEnabled)") {
        guard appState.isPlayerDevelopmentCopilotEnabled,
              SDDevelopmentPresentationAuthorization.isVisible(membership: appState.activeOrgMembership),
              let service = appState.supabase,
              let organizationId = appState.activeOrgId,
              let userId = appState.myProfile?.id else {
          model.reset()
          return
        }
        await model.load(client: service, organizationId: organizationId, userId: userId)
      }
    }
  }

  private var rosterList: some View {
    HPListScreenLayout {
      HPWorkspaceHeader(
        "Roster Attention",
        orgLabel: activeOrganizationName,
        context: "Reports awaiting review and evidence-supported player alerts"
      )
    } controls: {
      HPCard {
        VStack(alignment: .leading, spacing: HP.Space.sm) {
          HPSearchBar(text: $search, placeholder: "Search players")
          Picker("Severity", selection: $severity) {
            Text("All").tag("all")
            Text("High").tag("high")
            Text("Attention").tag("attention")
            Text("Info").tag("info")
          }
          .pickerStyle(.menu)
          .tint(HP.Color.accent)
          .frame(minHeight: 44)
          Text("\(filteredAlerts.count) matching alert\(filteredAlerts.count == 1 ? "" : "s")")
            .font(HP.Font.caption)
            .foregroundStyle(HP.Color.textMuted)
        }
      }
    } results: { context in
      VStack(alignment: .leading, spacing: HP.Space.md) {
        if model.isLoading { HPCard { HPLoadingState(text: "Loading roster attention…") } }
        if let error = model.errorMessage {
          HPCard { HPErrorState(title: "Roster attention unavailable", message: error) }
        }
        HPMetricCard(
          title: "Reports awaiting review",
          value: (model.response?.reportsAwaitingReview.count ?? 0).formatted(),
          context: "Coach review queue"
        )
        HPCard {
          VStack(alignment: .leading, spacing: HP.Space.sm) {
            HPSectionHeader("Active and reviewed alerts") {
              HPStatusBadge(text: "\(filteredAlerts.count)", kind: .neutral)
            }
            if !model.isLoading && filteredAlerts.isEmpty {
              Text("No supported alerts match this filter.")
                .font(HP.Font.callout)
                .foregroundStyle(HP.Color.textMuted)
            }
            ForEach(filteredAlerts) { alert in
              if let profile = player(alert.playerId) {
                NavigationLink {
                  PlayerDevelopmentAIWorkspaceView(player: profile)
                    .environmentObject(appState)
                } label: {
                  rosterRow(alert, playerName: profile.displayName, context: context)
                }
                .buttonStyle(.plain)
              } else {
                rosterRow(alert, playerName: alert.playerName ?? "Player", context: context)
              }
            }
          }
        }
      }
    }
  }

  private var activeOrganizationName: String {
    if let organizationId = appState.activeOrgId,
       let organization = appState.availableOrganizations.first(where: { $0.id == organizationId }) {
      return organization.displayName
    }
    return appState.activeOrgSettings?.display_name
      ?? appState.activeOrgSettings?.short_name
      ?? "Home Plate"
  }

  private func player(_ id: UUID) -> Profile? { players.first(where: { $0.id == id }) }

  private func rosterRow(
    _ alert: SDDevelopmentAlert,
    playerName: String,
    context: HPScreenLayoutContext
  ) -> some View {
    let summary = VStack(alignment: .leading, spacing: 3) {
      Text(playerName).font(HP.Font.headline).foregroundStyle(HP.Color.text)
      Text(alert.alertType.replacingOccurrences(of: "_", with: " ").capitalized)
        .font(HP.Font.callout)
        .foregroundStyle(HP.Color.text)
      Text("Freshness: \(alert.dataFreshness) • Confidence: \(alert.evidenceQuality.rawValue)")
        .font(HP.Font.caption)
        .foregroundStyle(HP.Color.textMuted)
        .fixedSize(horizontal: false, vertical: true)
    }
    .frame(maxWidth: .infinity, alignment: .leading)

    return Group {
      if context.isAccessibilitySize || !context.isRegularWidth {
        VStack(alignment: .leading, spacing: HP.Space.xs) {
          summary
          severityBadge(alert.severity)
        }
      } else {
        HStack(alignment: .top, spacing: HP.Space.sm) {
          summary
          Spacer(minLength: 0)
          severityBadge(alert.severity)
        }
      }
    }
    .frame(minHeight: 44)
    .contentShape(Rectangle())
  }
}

private func developmentMetadataRow(_ label: String, value: String) -> some View {
  ViewThatFits(in: .horizontal) {
    HStack(alignment: .firstTextBaseline, spacing: HP.Space.sm) {
      Text(label)
        .font(HP.Font.caption)
        .foregroundStyle(HP.Color.textMuted)
      Spacer(minLength: HP.Space.sm)
      Text(value)
        .font(HP.Font.callout.weight(.semibold))
        .foregroundStyle(HP.Color.text)
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
    }
    VStack(alignment: .leading, spacing: 3) {
      Text(label)
        .font(HP.Font.caption)
        .foregroundStyle(HP.Color.textMuted)
      Text(value)
        .font(HP.Font.callout.weight(.semibold))
        .foregroundStyle(HP.Color.text)
        .fixedSize(horizontal: false, vertical: true)
    }
  }
  .padding(.vertical, 6)
  .accessibilityElement(children: .combine)
}

private func qualityBadge(_ quality: SDDevelopmentQualityStatus) -> some View {
  HPStatusBadge(text: quality.rawValue.capitalized, kind: qualityKind(quality))
}

private func reportStatusBadge(_ status: SDDevelopmentReportStatus) -> some View {
  HPStatusBadge(text: status.rawValue.capitalized, kind: reportStatusKind(status))
}

private func freshnessBadge(_ freshness: String) -> some View {
  HPStatusBadge(text: freshness.capitalized, kind: freshnessKind(freshness))
}

private func trendBadge(_ interpretation: String) -> some View {
  HPStatusBadge(
    text: interpretation.replacingOccurrences(of: "_", with: " ").capitalized,
    kind: trendKind(interpretation)
  )
}

private func severityBadge(_ severity: SDDevelopmentAlertSeverity) -> some View {
  HPStatusBadge(text: severity.rawValue.capitalized, kind: severityKind(severity))
}

private func qualityKind(_ quality: SDDevelopmentQualityStatus) -> HPStatusKind {
  switch quality {
  case .sufficient: return .success
  case .limited, .stale: return .warning
  case .conflicting: return .danger
  case .unavailable, .unknown: return .neutral
  }
}

private func reportStatusKind(_ status: SDDevelopmentReportStatus) -> HPStatusKind {
  switch status {
  case .approved: return .success
  case .failed, .rejected: return .danger
  case .requested, .generating: return .info
  case .draft, .reviewed: return .gold
  case .archived, .unknown: return .neutral
  }
}

private func freshnessKind(_ freshness: String) -> HPStatusKind {
  switch freshness.lowercased() {
  case "current": return .success
  case "aging": return .warning
  case "stale": return .danger
  default: return .neutral
  }
}

private func trendKind(_ interpretation: String) -> HPStatusKind {
  switch interpretation {
  case "improvement": return .success
  case "regression": return .warning
  case "stable": return .gold
  default: return .neutral
  }
}

private func severityKind(_ severity: SDDevelopmentAlertSeverity) -> HPStatusKind {
  switch severity {
  case .high: return .danger
  case .attention: return .warning
  case .info: return .gold
  case .unknown: return .neutral
  }
}

private func format(_ value: Double) -> String {
  value.formatted(.number.precision(.fractionLength(0...2)))
}
