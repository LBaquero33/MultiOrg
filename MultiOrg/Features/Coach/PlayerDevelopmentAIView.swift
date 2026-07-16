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
    "\(appState.activeOrgAuthorizationKey):\(appState.myProfile?.id.uuidString ?? "none"):\(player.id.uuidString):\(reportingDays)"
  }

  var body: some View {
    Group {
      if !SDDevelopmentPresentationAuthorization.isVisible(membership: appState.activeOrgMembership) {
        ContentUnavailableView(
          "Staff access required",
          systemImage: "lock.fill",
          description: Text("Player Development AI is available only to active organization owners, admins, and coaches.")
        )
      } else if let service = appState.supabase,
                let organizationId = appState.activeOrgId,
                let userId = appState.myProfile?.id {
        workspace(service: service, organizationId: organizationId, userId: userId)
      } else {
        ProgressView("Loading organization…")
      }
    }
    .background(DHDTheme.pageBackground)
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
  }

  private func workspace(
    service: SupabaseService,
    organizationId: UUID,
    userId: UUID
  ) -> some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 14) {
        header(service: service, organizationId: organizationId, userId: userId)

        if case .loading = model.phase {
          DHDCard {
            HStack(spacing: 10) {
              ProgressView()
              Text("Building evidence view…")
              Spacer()
            }
          }
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
          DHDCard {
            Label(message, systemImage: "checkmark.circle.fill")
              .foregroundStyle(.green)
          }
        }

        if let pack = model.evidencePack {
          coverageCard(pack)
          trendCard(pack)
        }

        latestReportCard(organizationId: organizationId)
        alertsCard(service: service, organizationId: organizationId, userId: userId)
        historyCard(organizationId: organizationId)
      }
      .padding()
    }
    .task(id: contextKey) {
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
    DHDHeaderCard {
      VStack(alignment: .leading, spacing: 12) {
        HStack {
          VStack(alignment: .leading, spacing: 3) {
            Text("Player Development AI")
              .font(.title3.weight(.semibold))
            Text(player.displayName)
              .font(.caption)
              .foregroundStyle(Color.white.opacity(0.82))
          }
          Spacer()
          if model.isGenerating { ProgressView().tint(.white) }
        }

        HStack(spacing: 10) {
          Picker("Window", selection: $reportingDays) {
            Text("30 days").tag(30)
            Text("90 days").tag(90)
            Text("180 days").tag(180)
            Text("1 year").tag(365)
          }
          .labelsHidden()
          .pickerStyle(.menu)

          Button {
            Task {
              _ = await model.generate(
                client: service,
                organizationId: organizationId,
                userId: userId,
                playerId: player.id,
                window: window
              )
            }
          } label: {
            Label(model.isGenerating ? "Generating…" : "Generate Summary", systemImage: "sparkles")
          }
          .buttonStyle(.borderedProminent)
          .disabled(model.isGenerating || model.mutationInFlight)

          Button { showDataImport = true } label: {
            Label("Import Data", systemImage: "square.and.arrow.down")
          }
          .buttonStyle(.bordered)
          .disabled(model.isGenerating || model.mutationInFlight)

          Button { showCoachCopilot = true } label: {
            Label("Coach Copilot", systemImage: "bubble.left.and.text.bubble.right.fill")
          }
          .buttonStyle(.bordered)
          .disabled(model.isGenerating || model.mutationInFlight)
        }
      }
      .foregroundStyle(.white)
    }
  }

  private func coverageCard(_ pack: SDDevelopmentEvidencePack) -> some View {
    DHDCard {
      VStack(alignment: .leading, spacing: 10) {
        DHDSectionHeader("Evidence coverage") {
          HStack {
            qualityBadge(pack.qualityStatus)
            DHDStatusBadge(text: pack.dataFreshness.capitalized, color: freshnessColor(pack.dataFreshness))
          }
        }
        HStack(spacing: 18) {
          coverageValue("Testing", pack.coverage.testingEntries)
          coverageValue("Metrics", pack.coverage.metricObservations)
          coverageValue("Daily logs", pack.coverage.dailyLogs)
          coverageValue("Programs", pack.coverage.programAssignments)
          coverageValue("BP", pack.coverage.bpSessions)
        }
        if !pack.missingDataWarnings.isEmpty || !pack.staleDataWarnings.isEmpty || !pack.unitConflicts.isEmpty {
          Divider()
          ForEach(pack.missingDataWarnings + pack.staleDataWarnings + pack.unitConflicts, id: \.self) { warning in
            Label(warning, systemImage: "info.circle")
              .font(.footnote)
              .foregroundStyle(DHDTheme.textSecondary)
          }
        }
      }
    }
  }

  private func coverageValue(_ title: String, _ count: Int) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text("\(count)").font(.headline)
      Text(title).font(.caption).foregroundStyle(DHDTheme.textSecondary)
    }
  }

  private func trendCard(_ pack: SDDevelopmentEvidencePack) -> some View {
    DHDCard {
      VStack(alignment: .leading, spacing: 10) {
        DHDSectionHeader("Deterministic trends") {
          Text("\(pack.trends.count)")
            .font(.caption.weight(.semibold))
        }
        if pack.trends.isEmpty {
          Text("No supported comparable trends are available for this window.")
            .foregroundStyle(DHDTheme.textSecondary)
        } else {
          ForEach(pack.trends) { trend in
            HStack(alignment: .top) {
              VStack(alignment: .leading, spacing: 3) {
                Text(trend.displayName).font(.subheadline.weight(.semibold))
                Text("Latest \(format(trend.latestValue))\(trend.unit.map { " \($0)" } ?? "") • \(trend.sampleCount) sample\(trend.sampleCount == 1 ? "" : "s")")
                  .font(.caption)
                  .foregroundStyle(DHDTheme.textSecondary)
              }
              Spacer()
              DHDStatusBadge(text: trend.interpretation.replacingOccurrences(of: "_", with: " ").capitalized, color: trendColor(trend.interpretation))
            }
            if trend.id != pack.trends.last?.id { Divider() }
          }
        }
      }
    }
  }

  private func latestReportCard(organizationId: UUID) -> some View {
    DHDCard {
      VStack(alignment: .leading, spacing: 10) {
        DHDSectionHeader("Latest report") {
          if let report = model.latestReport { reportStatusBadge(report.status) }
        }
        if let report = model.latestReport {
          Text(report.structuredContent.overview)
            .font(.body)
          reportSections("Positive trends", report.structuredContent.positiveTrends)
          reportSections("Development priorities", report.structuredContent.developmentPriorities)
          Text(report.structuredContent.consistencyAndAttendance)
            .font(.footnote)
            .foregroundStyle(DHDTheme.textSecondary)
          NavigationLink {
            DevelopmentReportDetailView(organizationId: organizationId, reportId: report.id) {
              model.replaceReport($0)
            }
            .environmentObject(appState)
          } label: {
            Label("Review report and evidence", systemImage: "doc.text.magnifyingglass")
          }
        } else if model.phase == .loaded {
          Text("No deterministic report has been generated for this player.")
            .foregroundStyle(DHDTheme.textSecondary)
        }
      }
    }
  }

  @ViewBuilder
  private func reportSections(_ title: String, _ sections: [SDDevelopmentReportSection]) -> some View {
    if !sections.isEmpty {
      Text(title).font(.subheadline.weight(.semibold))
      ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
        VStack(alignment: .leading, spacing: 2) {
          Text(section.title).font(.subheadline)
          Text(section.explanation).font(.caption).foregroundStyle(DHDTheme.textSecondary)
          Text("Evidence: \(section.evidenceKeys.joined(separator: ", "))")
            .font(.caption2.monospaced())
            .foregroundStyle(DHDTheme.textSecondary)
        }
      }
    }
  }

  private func alertsCard(service: SupabaseService, organizationId: UUID, userId: UUID) -> some View {
    DHDCard {
      VStack(alignment: .leading, spacing: 10) {
        DHDSectionHeader("Development alerts") {
          Button("Run detection") {
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
          .disabled(model.mutationInFlight || model.isGenerating)
        }
        if model.alerts.isEmpty {
          Text("No persisted development alerts for this player.")
            .foregroundStyle(DHDTheme.textSecondary)
        } else {
          ForEach(model.alerts) { alert in
            Button {
              selectedAlert = alert
            } label: {
              HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                  Text(alert.alertType.replacingOccurrences(of: "_", with: " ").capitalized)
                    .font(.subheadline.weight(.semibold))
                  Text(alert.explanation)
                    .font(.caption)
                    .foregroundStyle(DHDTheme.textSecondary)
                    .multilineTextAlignment(.leading)
                }
                Spacer()
                DHDStatusBadge(text: alert.severity.rawValue.capitalized, color: severityColor(alert.severity))
              }
            }
            .buttonStyle(.plain)
          }
        }
      }
    }
  }

  private func historyCard(organizationId: UUID) -> some View {
    DHDCard {
      VStack(alignment: .leading, spacing: 10) {
        DHDSectionHeader("Report history") { Text("\(model.reports.count)").font(.caption) }
        if model.reports.isEmpty {
          Text("Report history is empty.").foregroundStyle(DHDTheme.textSecondary)
        } else {
          ForEach(model.reports) { report in
            NavigationLink {
              DevelopmentReportDetailView(organizationId: organizationId, reportId: report.id) {
                model.replaceReport($0)
              }
              .environmentObject(appState)
            } label: {
              HStack {
                VStack(alignment: .leading, spacing: 2) {
                  Text(report.reportType.replacingOccurrences(of: "_", with: " ").capitalized)
                  Text("\(report.reportingWindowStart) – \(report.reportingWindowEnd)")
                    .font(.caption)
                    .foregroundStyle(DHDTheme.textSecondary)
                }
                Spacer()
                reportStatusBadge(report.status)
              }
            }
          }
        }
      }
    }
  }

  private func errorCard(
    _ message: String,
    retryTitle: String = "Retry",
    retry: @escaping () -> Void
  ) -> some View {
    DHDCard {
      VStack(alignment: .leading, spacing: 8) {
        Label(message, systemImage: "exclamationmark.triangle.fill")
          .foregroundStyle(.orange)
        Button(retryTitle, action: retry)
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
      if hasCurrentAccess {
        ScrollView {
          VStack(alignment: .leading, spacing: 14) {
            if isLoading && detail == nil { ProgressView("Loading report…") }
            if let errorMessage {
              DHDCard { Label(errorMessage, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange) }
            }
            if let detail {
              reportHeader(detail.report)
              contentCard(detail.report)
              evidenceCard(detail.evidence)
              reviewCard(detail.report)
              auditCard(detail.reviewHistory)
            }
          }
          .padding()
        }
      } else {
        ContentUnavailableView(
          "Report unavailable",
          systemImage: "lock.fill",
          description: Text("Return to the report's active organization with staff access.")
        )
      }
    }
    .background(DHDTheme.pageBackground)
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
    .task(id: contextKey) {
      guard hasCurrentAccess else {
        detail = nil
        errorMessage = nil
        return
      }
      await load()
    }
  }

  private func reportHeader(_ report: SDDevelopmentReport) -> some View {
    DHDHeaderCard {
      VStack(alignment: .leading, spacing: 6) {
        HStack {
          Text(report.reportType.replacingOccurrences(of: "_", with: " ").capitalized)
            .font(.title3.weight(.semibold))
          Spacer()
          reportStatusBadge(report.status)
        }
        Text("Window \(report.reportingWindowStart) – \(report.reportingWindowEnd)")
        Text("Evidence cutoff \(report.inputCutoff)")
          .font(.caption)
        HStack {
          qualityBadge(report.qualityStatus)
          DHDStatusBadge(text: report.generationMode.capitalized, color: DHDTheme.accent)
          Text("\(report.generatorVersion) • \(report.promptVersion)")
            .font(.caption2.monospaced())
        }
        if let fingerprint = report.evidenceFingerprint {
          Text("Evidence SHA-256 \(fingerprint)")
            .font(.caption2.monospaced())
            .textSelection(.enabled)
        }
      }
      .foregroundStyle(.white)
    }
  }

  private func contentCard(_ report: SDDevelopmentReport) -> some View {
    DHDCard {
      VStack(alignment: .leading, spacing: 10) {
        DHDSectionHeader("Structured draft") { EmptyView() }
        Text(report.structuredContent.overview)
        section("Positive trends", report.structuredContent.positiveTrends)
        section("Development priorities", report.structuredContent.developmentPriorities)
        Text("Consistency and attendance").font(.headline)
        Text(report.structuredContent.consistencyAndAttendance)
        if !report.structuredContent.dataGaps.isEmpty {
          Text("Data gaps").font(.headline)
          ForEach(report.structuredContent.dataGaps, id: \.self) { Text("• \($0)") }
        }
        if !report.structuredContent.coachReviewQuestions.isEmpty {
          Text("Coach review questions").font(.headline)
          ForEach(report.structuredContent.coachReviewQuestions, id: \.self) { Text("• \($0)") }
        }
      }
    }
  }

  @ViewBuilder
  private func section(_ title: String, _ rows: [SDDevelopmentReportSection]) -> some View {
    if !rows.isEmpty {
      Text(title).font(.headline)
      ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
        VStack(alignment: .leading, spacing: 3) {
          Text(row.title).font(.subheadline.weight(.semibold))
          Text(row.explanation)
          Text("Evidence \(row.evidenceKeys.joined(separator: ", "))")
            .font(.caption2.monospaced())
            .foregroundStyle(DHDTheme.textSecondary)
        }
      }
    }
  }

  private func evidenceCard(_ evidence: [SDDevelopmentEvidence]) -> some View {
    DHDCard {
      VStack(alignment: .leading, spacing: 10) {
        DHDSectionHeader("Evidence snapshots") { Text("\(evidence.count)").font(.caption) }
        if evidence.isEmpty {
          Text("No source evidence was available for this draft.")
            .foregroundStyle(DHDTheme.textSecondary)
        } else {
          ForEach(evidence) { item in
            VStack(alignment: .leading, spacing: 3) {
              HStack {
                Text(item.displayLabel).font(.subheadline.weight(.semibold))
                Spacer()
                qualityBadge(item.quality)
              }
              Text(item.explanation).font(.caption)
              Text("\(item.sourceEntityType) • \(item.sourceRecordId) • \(item.deterministicRuleId ?? "source")")
                .font(.caption2.monospaced())
                .foregroundStyle(DHDTheme.textSecondary)
            }
            if item.id != evidence.last?.id { Divider() }
          }
        }
      }
    }
  }

  private func reviewCard(_ report: SDDevelopmentReport) -> some View {
    DHDCard {
      VStack(alignment: .leading, spacing: 10) {
        DHDSectionHeader("Coach review") { EmptyView() }
        TextEditor(text: $notes)
          .frame(minHeight: 80)
          .overlay(
            RoundedRectangle(cornerRadius: 8)
              .stroke(DHDTheme.separator)
              .allowsHitTesting(false)
          )
        HStack {
          Button("Mark reviewed") { Task { await review(.review) } }
            .disabled(isMutating || !report.status.isReviewable)
          Button("Approve") { Task { await review(.approve) } }
            .buttonStyle(.borderedProminent)
            .disabled(isMutating || !report.status.isReviewable)
          Button("Reject", role: .destructive) { Task { await review(.reject) } }
            .disabled(isMutating || !report.status.isReviewable)
          Button("Archive") { Task { await review(.archive) } }
            .disabled(isMutating || !report.status.canArchive)
          if isMutating { ProgressView().controlSize(.small) }
        }
      }
    }
  }

  private func auditCard(_ history: [SDDevelopmentReviewEvent]) -> some View {
    DHDCard {
      VStack(alignment: .leading, spacing: 8) {
        DHDSectionHeader("Review history") { Text("\(history.count)").font(.caption) }
        if history.isEmpty { Text("No review events.").foregroundStyle(DHDTheme.textSecondary) }
        ForEach(history) { event in
          Text("\(event.eventType.capitalized): \(event.fromStatus ?? "—") → \(event.toStatus) • \(event.createdAt)")
            .font(.caption)
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
        if hasCurrentAccess {
          alertForm
        } else {
          ContentUnavailableView(
            "Alert unavailable",
            systemImage: "lock.fill",
            description: Text("Return to the alert's active organization with staff access.")
          )
        }
      }
      .navigationTitle("Development alert")
      .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
      .task(id: contextKey) {
        guard hasCurrentAccess else {
          detail = nil
          errorMessage = nil
          return
        }
        await loadDetail()
      }
    }
  }

  private var alertForm: some View {
    Form {
        if isLoading { ProgressView("Loading evidence…") }
        Section("Alert") {
          LabeledContent("Type", value: current.alertType.replacingOccurrences(of: "_", with: " ").capitalized)
          LabeledContent("Severity", value: current.severity.rawValue.capitalized)
          LabeledContent("Status", value: current.status.rawValue.capitalized)
          LabeledContent("Window", value: "\(current.evidenceWindowStart) – \(current.evidenceWindowEnd)")
          LabeledContent("First detected", value: current.firstDetectedAt)
          LabeledContent("Last detected", value: current.lastDetectedAt)
          LabeledContent("Freshness", value: current.dataFreshness.capitalized)
          LabeledContent("Evidence quality", value: current.evidenceQuality.rawValue.capitalized)
          Text(current.explanation)
        }
        Section("Recommended human review") { Text(current.recommendedHumanAction) }
        Section("Evidence") {
          if let evidence = detail?.evidence, !evidence.isEmpty {
            ForEach(evidence) { item in
              VStack(alignment: .leading, spacing: 3) {
                Text(item.displayLabel).font(.subheadline.weight(.semibold))
                Text(item.explanation).font(.caption)
                Text("\(item.sourceEntityType) • \(item.sourceRecordId)")
                  .font(.caption2.monospaced())
                  .foregroundStyle(DHDTheme.textSecondary)
              }
            }
          } else if !isLoading {
            Text("This alert is based on an explicit missing-data rule or has no measurement snapshot.")
              .foregroundStyle(DHDTheme.textSecondary)
          }
        }
        if let history = detail?.reviewHistory, !history.isEmpty {
          Section("Review history") {
            ForEach(history) { event in
              Text("\(event.eventType.capitalized): \(event.fromStatus ?? "—") → \(event.toStatus) • \(event.createdAt)")
                .font(.caption)
            }
          }
        }
        Section("Review notes") { TextEditor(text: $notes).frame(minHeight: 70) }
        if let errorMessage { Section { Text(errorMessage).foregroundStyle(.orange) } }
        Section {
          Button("Acknowledge") { Task { await update(.acknowledge) } }
          Button("Dismiss") { Task { await update(.dismiss) } }
          Button("Resolve") { Task { await update(.resolve) } }
          Button("Archive") { Task { await update(.archive) } }
        }
        .disabled(isWorking || [.dismissed, .resolved, .archived].contains(current.status))
    }
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
        if SDDevelopmentPresentationAuthorization.isVisible(membership: appState.activeOrgMembership) {
          rosterList
        } else {
          ContentUnavailableView(
            "Staff access required",
            systemImage: "lock.fill",
            description: Text("Roster Attention is available only to active organization staff.")
          )
        }
      }
      .navigationTitle("Roster Attention")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
        ToolbarItem(placement: .primaryAction) {
          Picker("Severity", selection: $severity) {
            Text("All").tag("all")
            Text("High").tag("high")
            Text("Attention").tag("attention")
            Text("Info").tag("info")
          }
        }
      }
      .task(id: "\(appState.activeOrgAuthorizationKey):\(appState.myProfile?.id.uuidString ?? "none")") {
        guard SDDevelopmentPresentationAuthorization.isVisible(membership: appState.activeOrgMembership),
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
    List {
        if model.isLoading { ProgressView("Loading roster attention…") }
        if let error = model.errorMessage {
          Section { Text(error).foregroundStyle(.orange) }
        }
        Section("Reports awaiting review") {
          Text("\(model.response?.reportsAwaitingReview.count ?? 0)")
            .font(.title2.weight(.semibold))
        }
        Section("Active and reviewed alerts") {
          if !model.isLoading && filteredAlerts.isEmpty {
            Text("No supported alerts match this filter.")
              .foregroundStyle(DHDTheme.textSecondary)
          }
          ForEach(filteredAlerts) { alert in
            if let profile = player(alert.playerId) {
              NavigationLink {
                PlayerDevelopmentAIWorkspaceView(player: profile)
                  .environmentObject(appState)
              } label: {
                rosterRow(alert, playerName: profile.displayName)
              }
            } else {
              rosterRow(alert, playerName: alert.playerName ?? "Player")
            }
          }
        }
      }
      .searchable(text: $search, prompt: "Search players")
  }

  private func player(_ id: UUID) -> Profile? { players.first(where: { $0.id == id }) }

  private func rosterRow(_ alert: SDDevelopmentAlert, playerName: String) -> some View {
    HStack(alignment: .top) {
      VStack(alignment: .leading, spacing: 3) {
        Text(playerName).font(.headline)
        Text(alert.alertType.replacingOccurrences(of: "_", with: " ").capitalized)
          .font(.subheadline)
        Text("Freshness: \(alert.dataFreshness) • Confidence: \(alert.evidenceQuality.rawValue)")
          .font(.caption)
          .foregroundStyle(DHDTheme.textSecondary)
      }
      Spacer()
      DHDStatusBadge(text: alert.severity.rawValue.capitalized, color: severityColor(alert.severity))
    }
  }
}

private func qualityBadge(_ quality: SDDevelopmentQualityStatus) -> some View {
  DHDStatusBadge(text: quality.rawValue.capitalized, color: qualityColor(quality))
}

private func reportStatusBadge(_ status: SDDevelopmentReportStatus) -> some View {
  DHDStatusBadge(text: status.rawValue.capitalized, color: status == .approved ? .green : status == .failed || status == .rejected ? .red : DHDTheme.accent)
}

private func qualityColor(_ quality: SDDevelopmentQualityStatus) -> Color {
  switch quality {
  case .sufficient: return .green
  case .limited, .stale: return .orange
  case .conflicting: return .red
  case .unavailable, .unknown: return DHDTheme.textSecondary
  }
}

private func freshnessColor(_ freshness: String) -> Color {
  switch freshness.lowercased() {
  case "current": return .green
  case "aging": return .orange
  case "stale": return .red
  default: return DHDTheme.textSecondary
  }
}

private func trendColor(_ interpretation: String) -> Color {
  switch interpretation {
  case "improvement": return .green
  case "regression": return .orange
  case "stable": return DHDTheme.accent
  default: return DHDTheme.textSecondary
  }
}

private func severityColor(_ severity: SDDevelopmentAlertSeverity) -> Color {
  switch severity {
  case .high: return .red
  case .attention: return .orange
  case .info: return DHDTheme.accent
  case .unknown: return DHDTheme.textSecondary
  }
}

private func format(_ value: Double) -> String {
  value.formatted(.number.precision(.fractionLength(0...2)))
}
