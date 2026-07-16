import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class PlayerDevelopmentImportWorkspaceModel: ObservableObject {
  enum Phase: Equatable {
    case idle, uploading, mapping, validating, preview, committing, completed
    case failed(String)
  }

  @Published private(set) var phase: Phase = .idle
  @Published private(set) var job: SDDevelopmentImportJob?
  @Published private(set) var inspection: SDDevelopmentImportInspection?
  @Published private(set) var preview: SDDevelopmentImportPreviewResponse?
  @Published private(set) var history: [SDDevelopmentImportJob] = []
  @Published private(set) var profiles: [SDDevelopmentImportMappingProfile] = []
  @Published private(set) var metricDefinitions: [SDDevelopmentMetricDefinition] = []
  @Published private(set) var rowErrors: [SDDevelopmentImportRowError] = []
  @Published private(set) var resumingJobId: UUID?
  @Published private(set) var resumeErrorJobId: UUID?
  @Published private(set) var resolvingSourceKey: String?
  @Published var errorMessage: String?
  @Published private(set) var errorCode: String?
  @Published var successMessage: String?
  @Published var previewFilter = "all"

  private(set) var contextToken: SDDevelopmentImportContextToken?
  private var commitStarted = false
  private var pendingCreateFingerprint: String?
  private var pendingCreateKey: UUID?
  private var pendingUploadFingerprint: String?
  private var pendingUpload: SDDevelopmentImportCreateResponse?

  var isWorking: Bool {
    [.uploading, .validating, .committing].contains(phase) || resolvingSourceKey != nil
  }

  var recoveryAction: SDDevelopmentImportRecoveryAction {
    SDDevelopmentImportRecoveryPolicy.action(
      errorCode: errorCode,
      jobStatus: job?.status
    )
  }

  func reset() {
    contextToken = nil
    phase = .idle
    job = nil
    inspection = nil
    preview = nil
    history = []
    profiles = []
    metricDefinitions = []
    rowErrors = []
    resumingJobId = nil
    resumeErrorJobId = nil
    resolvingSourceKey = nil
    errorMessage = nil
    errorCode = nil
    successMessage = nil
    previewFilter = "all"
    commitStarted = false
    pendingCreateFingerprint = nil
    pendingCreateKey = nil
    pendingUploadFingerprint = nil
    pendingUpload = nil
  }

  func beginContext(organizationId: UUID, userId: UUID) -> SDDevelopmentImportContextToken {
    let token = SDDevelopmentImportContextToken(organizationId: organizationId, userId: userId, nonce: UUID())
    contextToken = token
    return token
  }

  func accepts(_ token: SDDevelopmentImportContextToken) -> Bool { contextToken == token }

  func cancelCurrentOperation() {
    contextToken = nil
    phase = inspection == nil ? .idle : .mapping
    errorMessage = "Import operation canceled."
    commitStarted = false
    pendingCreateFingerprint = nil
    pendingCreateKey = nil
    pendingUploadFingerprint = nil
    pendingUpload = nil
    resumingJobId = nil
    resumeErrorJobId = nil
    resolvingSourceKey = nil
  }

  func invalidatePreview() {
    guard preview != nil else { return }
    preview = nil
    rowErrors = []
    commitStarted = false
    if phase == .preview { phase = .mapping }
  }

  func loadHistory(
    client: any PlayerDevelopmentImportClient,
    organizationId: UUID,
    userId: UUID,
    provider: SDDevelopmentImportProvider
  ) async {
    let token = contextToken ?? beginContext(organizationId: organizationId, userId: userId)
    do {
      let jobs = try await client.listDevelopmentImportJobs(organizationId: organizationId)
      let mappings = try await client.listDevelopmentImportMappings(organizationId: organizationId, provider: provider)
      let definitions = try await client.listDevelopmentMetricDefinitions()
      guard accepts(token) else { return }
      history = jobs
      profiles = mappings
      metricDefinitions = definitions
    } catch is CancellationError {
      return
    } catch {
      guard accepts(token) else { return }
      errorMessage = error.localizedDescription
    }
  }

  func uploadAndInspect(
    client: any PlayerDevelopmentImportClient,
    organizationId: UUID,
    userId: UUID,
    playerId: UUID?,
    provider: SDDevelopmentImportProvider,
    fileName: String,
    data: Data
  ) async {
    guard !isWorking else { return }
    let token = beginContext(organizationId: organizationId, userId: userId)
    phase = .uploading
    errorMessage = nil
    errorCode = nil
    successMessage = nil
    preview = nil
    commitStarted = false
    let createFingerprint = [
      organizationId.uuidString.lowercased(),
      playerId?.uuidString.lowercased() ?? "multi-player",
      provider.rawValue,
      fileName,
      String(data.count),
      String(data.hashValue),
    ].joined(separator: "|")
    do {
      if pendingCreateFingerprint != createFingerprint {
        pendingCreateFingerprint = createFingerprint
        pendingCreateKey = UUID()
        pendingUploadFingerprint = nil
        pendingUpload = nil
      }
      let created: SDDevelopmentImportCreateResponse
      let reusingPendingUpload = pendingUploadFingerprint == createFingerprint && pendingUpload != nil
      if reusingPendingUpload, let pendingUpload {
        created = pendingUpload
      } else {
        created = try await client.createDevelopmentImportJob(
          organizationId: organizationId,
          playerId: playerId,
          provider: provider,
          fileName: fileName,
          idempotencyKey: pendingCreateKey ?? UUID()
        )
        pendingUploadFingerprint = createFingerprint
        pendingUpload = created
      }
      guard accepts(token) else { return }
      job = created.job
      let fileType = (fileName as NSString).pathExtension.lowercased()
      let inspected: SDDevelopmentImportInspectResponse
      if reusingPendingUpload {
        do {
          inspected = try await client.inspectDevelopmentImport(
            organizationId: organizationId,
            jobId: created.job.id
          )
        } catch let edge as SDEdgeFunctionHTTPError where edge.code == "upload_not_found" {
          try await client.uploadDevelopmentImportFile(data, target: created.upload, fileType: fileType)
          inspected = try await client.inspectDevelopmentImport(
            organizationId: organizationId,
            jobId: created.job.id
          )
        }
      } else {
        try await client.uploadDevelopmentImportFile(data, target: created.upload, fileType: fileType)
        guard accepts(token) else { return }
        inspected = try await client.inspectDevelopmentImport(
          organizationId: organizationId,
          jobId: created.job.id
        )
      }
      guard accepts(token) else { return }
      job = inspected.job
      inspection = inspected.inspection
      phase = .mapping
      pendingCreateFingerprint = nil
      pendingCreateKey = nil
      pendingUploadFingerprint = nil
      pendingUpload = nil
    } catch is CancellationError {
      return
    } catch {
      guard accepts(token) else { return }
      phase = .failed(error.localizedDescription)
      if let edge = error as? SDEdgeFunctionHTTPError,
         edge.code == "idempotency_key_conflict" {
        pendingCreateFingerprint = nil
        pendingCreateKey = nil
      }
      present(error)
    }
  }

  func validate(
    client: any PlayerDevelopmentImportClient,
    organizationId: UUID,
    userId: UUID,
    mapping: SDDevelopmentImportMapping,
    mappingName: String?
  ) async {
    guard let job, !isWorking else { return }
    let token = contextToken ?? beginContext(organizationId: organizationId, userId: userId)
    phase = .validating
    errorMessage = nil
    do {
      let savedJob = try await client.saveDevelopmentImportMapping(
        organizationId: organizationId,
        jobId: job.id,
        mapping: mapping,
        mappingName: mappingName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
      )
      guard accepts(token) else { return }
      self.job = savedJob
      let validatedPreview = try await client.validateDevelopmentImport(
        organizationId: organizationId,
        jobId: job.id
      )
      guard accepts(token) else { return }
      preview = validatedPreview
      rowErrors = (try? await client.listDevelopmentImportRowErrors(
        organizationId: organizationId,
        jobId: job.id
      )) ?? []
      guard accepts(token) else { return }
      phase = .preview
    } catch is CancellationError {
      return
    } catch {
      guard accepts(token) else { return }
      phase = .mapping
      present(error)
    }
  }

  static func canResumeValidation(_ status: SDDevelopmentImportStatus) -> Bool {
    [.validating, .playerResolutionRequired, .ready].contains(status)
  }

  @discardableResult
  func beginValidationResume(
    _ existing: SDDevelopmentImportJob,
    organizationId: UUID,
    userId: UUID
  ) -> Bool {
    guard existing.organizationId == organizationId,
          Self.canResumeValidation(existing.status),
          resumingJobId == nil,
          !isWorking else { return false }
    _ = beginContext(organizationId: organizationId, userId: userId)
    job = existing
    preview = nil
    rowErrors = []
    errorMessage = nil
    errorCode = nil
    successMessage = nil
    resumeErrorJobId = nil
    resumingJobId = existing.id
    phase = .validating
    return true
  }

  func resumeValidation(
    client: any PlayerDevelopmentImportClient,
    organizationId: UUID,
    userId: UUID
  ) async {
    guard let job,
          resumingJobId == job.id,
          contextToken?.accepts(organizationId: organizationId, userId: userId) == true,
          phase == .validating else { return }
    let token = contextToken!
    do {
      let validatedPreview = try await client.validateDevelopmentImport(
        organizationId: organizationId,
        jobId: job.id
      )
      guard accepts(token) else { return }
      let refreshedJob = try await client.getDevelopmentImportJob(
        organizationId: organizationId,
        jobId: job.id
      )
      guard accepts(token) else { return }
      preview = validatedPreview
      rowErrors = (try? await client.listDevelopmentImportRowErrors(
        organizationId: organizationId,
        jobId: job.id
      )) ?? []
      guard accepts(token) else { return }
      self.job = refreshedJob
      if let index = history.firstIndex(where: { $0.id == refreshedJob.id }) {
        history[index] = refreshedJob
      } else {
        history.insert(refreshedJob, at: 0)
      }
      resumingJobId = nil
      resumeErrorJobId = nil
      switch refreshedJob.status {
      case .mappingRequired:
        preview = nil
        phase = .mapping
      case .completed, .completedWithErrors:
        phase = .completed
      default:
        phase = .preview
      }
    } catch is CancellationError {
      guard accepts(token) else { return }
      resumingJobId = nil
      phase = .mapping
      return
    } catch {
      guard accepts(token) else { return }
      resumingJobId = nil
      resumeErrorJobId = job.id
      phase = .mapping
      presentResume(error)
    }
  }

  @discardableResult
  func startOver(
    client: any PlayerDevelopmentImportClient,
    organizationId: UUID,
    userId: UUID
  ) async -> Bool {
    guard let job,
          recoveryAction == .startOver,
          !isWorking else { return false }
    let token = contextToken ?? beginContext(organizationId: organizationId, userId: userId)
    do {
      _ = try await client.archiveDevelopmentImport(
        organizationId: organizationId,
        jobId: job.id
      )
      guard accepts(token) else { return false }
      reset()
      _ = beginContext(organizationId: organizationId, userId: userId)
      successMessage = "The incomplete import was archived. Select the file again to start a new import."
      return true
    } catch is CancellationError {
      return false
    } catch {
      guard accepts(token) else { return false }
      present(error)
      return false
    }
  }

  @discardableResult
  func resolve(
    client: any PlayerDevelopmentImportClient,
    organizationId: UUID,
    userId: UUID,
    sourceKey: String,
    playerId: UUID
  ) async -> Bool {
    guard let job, resolvingSourceKey == nil else { return false }
    let token = contextToken ?? beginContext(organizationId: organizationId, userId: userId)
    resolvingSourceKey = sourceKey
    errorMessage = nil
    errorCode = nil
    defer {
      if resolvingSourceKey == sourceKey {
        resolvingSourceKey = nil
      }
    }
    do {
      let resolvedJob = try await client.resolveDevelopmentImportPlayer(
        organizationId: organizationId,
        jobId: job.id,
        sourceKey: sourceKey,
        playerId: playerId
      )
      guard accepts(token) else { return false }
      self.job = resolvedJob
      let validatedPreview = try await client.validateDevelopmentImport(
        organizationId: organizationId,
        jobId: job.id
      )
      guard accepts(token) else { return false }
      preview = validatedPreview
      rowErrors = (try? await client.listDevelopmentImportRowErrors(
        organizationId: organizationId,
        jobId: job.id
      )) ?? []
      guard accepts(token) else { return false }
      if let refreshedJob = try? await client.getDevelopmentImportJob(
        organizationId: organizationId,
        jobId: job.id
      ) {
        guard accepts(token) else { return false }
        self.job = refreshedJob
        if let index = history.firstIndex(where: { $0.id == refreshedJob.id }) {
          history[index] = refreshedJob
        } else {
          history.insert(refreshedJob, at: 0)
        }
      }
      phase = .preview
      return true
    } catch is CancellationError {
      return false
    } catch {
      guard accepts(token) else { return false }
      present(error)
      return false
    }
  }

  @discardableResult
  func commit(
    client: any PlayerDevelopmentImportClient,
    organizationId: UUID,
    userId: UUID
  ) async -> Bool {
    guard let job, !commitStarted, phase == .preview else { return false }
    commitStarted = true
    phase = .committing
    errorMessage = nil
    let token = contextToken ?? beginContext(organizationId: organizationId, userId: userId)
    do {
      let result = try await client.commitDevelopmentImport(organizationId: organizationId, jobId: job.id)
      guard accepts(token) else { return false }
      self.job = result.job
      history.removeAll(where: { $0.id == result.job.id })
      history.insert(result.job, at: 0)
      phase = .completed
      successMessage = result.reused ? "This file was already imported; no duplicate observations were created." : "Import complete. Reports and alerts were not run automatically."
      return true
    } catch {
      guard accepts(token) else { return false }
      commitStarted = false
      phase = .preview
      present(error)
      return false
    }
  }

  func useProfile(_ profile: SDDevelopmentImportMappingProfile) -> SDDevelopmentImportMapping? {
    guard
      profile.headerFingerprint == inspection?.headerFingerprint,
      profile.provider == job?.provider,
      profile.parserVersion == job?.parserVersion
    else {
      errorMessage = "This saved mapping has incompatible headers, provider, or parser version and was not applied."
      return nil
    }
    return profile.mappingConfig
  }

  func archiveProfile(
    _ profile: SDDevelopmentImportMappingProfile,
    client: any PlayerDevelopmentImportClient,
    organizationId: UUID
  ) async {
    do {
      _ = try await client.archiveDevelopmentImportMapping(
        organizationId: organizationId,
        mappingProfileId: profile.id
      )
      profiles.removeAll(where: { $0.id == profile.id })
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  var filteredPreviewRows: [SDDevelopmentImportPreviewRow] {
    guard let rows = preview?.rows, previewFilter != "all" else { return preview?.rows ?? [] }
    return rows.filter {
      if previewFilter == "unmatched" { return $0.playerMatchState == "unmatched" }
      if previewFilter == "ambiguous" { return $0.playerMatchState == "ambiguous" }
      return $0.acceptanceState == previewFilter
    }
  }

  func resumeExistingImport(_ existing: SDDevelopmentImportJob) {
    job = existing
    errorMessage = nil
    errorCode = nil
    phase = existing.status == .ready ? .preview : .mapping
  }

  func prepareValidationResume(_ existing: SDDevelopmentImportJob) {
    guard existing.status == .validating else { return }
    job = existing
    preview = nil
    rowErrors = []
    errorCode = "validation_persistence_failed"
    errorMessage = "[validation_persistence_failed] Validation details were not saved. Resume Validation to retry safely."
    phase = .mapping
  }

  func viewCompletedImport(_ completed: SDDevelopmentImportJob) {
    job = completed
    errorMessage = nil
    errorCode = nil
    phase = .completed
  }

  private func present(_ error: Error) {
    if let edge = error as? SDEdgeFunctionHTTPError {
      errorCode = edge.code
      errorMessage = "[\(edge.code)] \(edge.message)"
    } else {
      errorCode = nil
      errorMessage = error.localizedDescription
    }
  }

  private func presentResume(_ error: Error) {
    if error is SDEdgeFunctionHTTPError {
      present(error)
    } else {
      errorCode = "validation_resume_failed"
      errorMessage = "[validation_resume_failed] \(error.localizedDescription)"
    }
  }
}

struct PlayerDevelopmentImportWorkspaceView: View {
  private enum WorkspaceAnchor: Hashable {
    case mapping
    case preview
  }

  @EnvironmentObject private var appState: AppState
  @Environment(\.dismiss) private var dismiss
  @StateObject private var model = PlayerDevelopmentImportWorkspaceModel()
  let player: Profile?

  @State private var showFileImporter = false
  @State private var provider = SDDevelopmentImportProvider.genericCSV
  @State private var shape = SDDevelopmentImportFileShape.long
  @State private var playerColumn = ""
  @State private var playerColumnRole = "player_name"
  @State private var dateColumn = ""
  @State private var metricColumn = ""
  @State private var valueColumn = ""
  @State private var unitColumn = ""
  @State private var sampleSizeColumn = ""
  @State private var dateFormat = "ISO"
  @State private var timeZone = TimeZone.current.identifier
  @State private var trackManUnitSystem = ""
  @State private var useAutomaticMapping = true
  @State private var mappingName = ""
  @State private var wideMetricKeys: [String: String] = [:]
  @State private var wideUnits: [String: String] = [:]
  @State private var longMetricKeys: [String: String] = [:]
  @State private var longUnits: [String: String] = [:]
  @State private var showCommitConfirmation = false
  @State private var operationTask: Task<Void, Never>?
  @State private var selectedResolutionPlayerIds: [String: UUID] = [:]

  private var contextKey: String {
    "\(appState.activeOrgAuthorizationKey):\(appState.myProfile?.id.uuidString ?? "none")"
  }

  private var mappingDraftKey: String {
    [
      shape.rawValue, playerColumn, playerColumnRole, dateColumn, metricColumn,
      valueColumn, unitColumn, sampleSizeColumn, dateFormat, timeZone,
      wideMetricKeys.sorted(by: { $0.key < $1.key }).description,
      wideUnits.sorted(by: { $0.key < $1.key }).description,
      longMetricKeys.sorted(by: { $0.key < $1.key }).description,
      longUnits.sorted(by: { $0.key < $1.key }).description,
      trackManUnitSystem, String(useAutomaticMapping),
    ].joined(separator: "|")
  }

  var body: some View {
    Group {
      if !SDDevelopmentImportPresentationAuthorization.isVisible(membership: appState.activeOrgMembership) {
        ContentUnavailableView("Staff access required", systemImage: "lock.fill", description: Text("Only active organization owners, admins, and coaches can import player data."))
      } else if let service = appState.supabase, let orgId = appState.activeOrgId, let userId = appState.myProfile?.id {
        workspace(service: service, organizationId: orgId, userId: userId)
      } else {
        ProgressView("Loading organization…")
      }
    }
    .background(DHDTheme.pageBackground)
    .navigationTitle("Import Player Data")
    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
    .fileImporter(
      isPresented: $showFileImporter,
      allowedContentTypes: [.commaSeparatedText, UTType(filenameExtension: "tsv") ?? .plainText],
      allowsMultipleSelection: false,
      onCompletion: handleFileSelection
    )
    .alert("Confirm import", isPresented: $showCommitConfirmation) {
      Button("Cancel", role: .cancel) {}
      Button("Import accepted rows") {
        guard let service = appState.supabase, let orgId = appState.activeOrgId, let userId = appState.myProfile?.id else { return }
        operationTask?.cancel()
        operationTask = Task {
          _ = await model.commit(client: service, organizationId: orgId, userId: userId)
        }
      }
    } message: {
      Text("The server will re-read and revalidate the private file. This does not generate a report, run alerts, or send notifications.")
    }
    .task(id: contextKey) {
      operationTask?.cancel()
      model.reset()
      clearDraft()
      guard let service = appState.supabase, let orgId = appState.activeOrgId, let userId = appState.myProfile?.id else { return }
      _ = model.beginContext(organizationId: orgId, userId: userId)
      await model.loadHistory(client: service, organizationId: orgId, userId: userId, provider: provider)
    }
    .onChange(of: mappingDraftKey) { _, _ in model.invalidatePreview() }
    .onChange(of: provider) { _, nextProvider in
      operationTask?.cancel()
      model.invalidatePreview()
      guard let service = appState.supabase, let orgId = appState.activeOrgId,
            let userId = appState.myProfile?.id else { return }
      _ = model.beginContext(organizationId: orgId, userId: userId)
      operationTask = Task {
        await model.loadHistory(
          client: service,
          organizationId: orgId,
          userId: userId,
          provider: nextProvider
        )
      }
    }
    .onDisappear {
      operationTask?.cancel()
      model.reset()
    }
  }

  private func workspace(service: SupabaseService, organizationId: UUID, userId: UUID) -> some View {
    ScrollViewReader { proxy in
      ScrollView {
        VStack(alignment: .leading, spacing: 14) {
          DHDHeaderCard {
            VStack(alignment: .leading, spacing: 8) {
              Text("Player Development Data Import").font(.title3.weight(.semibold))
              Text(player?.displayName ?? "Multiple organization players").font(.caption).foregroundStyle(Color.white.opacity(0.82))
              Text("Private CSV/TSV upload • explicit player, metric, date, and unit mapping").font(.caption2).foregroundStyle(Color.white.opacity(0.72))
            }.foregroundStyle(.white)
          }.foregroundStyle(.white)

          if let error = model.errorMessage {
            messageCard(error, color: .red, icon: "exclamationmark.triangle.fill")
            conflictRecoveryCard(
              service: service,
              organizationId: organizationId,
              userId: userId
            )
          }
          if let success = model.successMessage { messageCard(success, color: .green, icon: "checkmark.circle.fill") }

          selectCard(service: service, organizationId: organizationId, userId: userId)
          if let inspection = model.inspection { inspectionCard(inspection) }
          if model.inspection != nil && model.phase != .completed {
            mappingCard(service: service, organizationId: organizationId, userId: userId)
              .id(WorkspaceAnchor.mapping)
          }
          if let preview = model.preview {
            previewCard(preview, service: service, organizationId: organizationId, userId: userId)
              .id(WorkspaceAnchor.preview)
          }
          historyCard(
            service: service,
            organizationId: organizationId,
            userId: userId
          )
        }.padding()
      }
      .onChange(of: model.phase) { _, phase in
        let anchor: WorkspaceAnchor?
        switch phase {
        case .mapping: anchor = model.inspection == nil ? nil : .mapping
        case .preview: anchor = .preview
        default: anchor = nil
        }
        guard let anchor else { return }
        withAnimation { proxy.scrollTo(anchor, anchor: .top) }
      }
    }
  }

  private func selectCard(service: SupabaseService, organizationId: UUID, userId: UUID) -> some View {
    DHDCard {
      VStack(alignment: .leading, spacing: 12) {
        DHDSectionHeader("1. Select a private CSV or TSV")
        Picker("Provider", selection: $provider) {
          ForEach(SDDevelopmentImportProvider.allCases) { Text($0.label).tag($0) }
        }
        Text("Only Generic CSV parsing is automatic in Phase 11B.1. Provider labels use the same manual mapper until real fixtures are validated.")
          .font(.caption).foregroundStyle(.secondary)
        Button { showFileImporter = true } label: {
          Label(model.isWorking ? "Uploading…" : "Choose file", systemImage: "doc.badge.plus")
        }.buttonStyle(.borderedProminent).disabled(model.isWorking)
        if model.isWorking {
          Button("Cancel operation", role: .cancel) {
            operationTask?.cancel()
            operationTask = nil
            model.cancelCurrentOperation()
          }
        }
        Text("UTF-8 only • .csv or .tsv • 10 MB • 50,000 rows • 250 columns")
          .font(.caption2).foregroundStyle(.secondary)
      }
    }
  }

  private func inspectionCard(_ inspection: SDDevelopmentImportInspection) -> some View {
    DHDCard {
      VStack(alignment: .leading, spacing: 10) {
        DHDSectionHeader("2. Detect and inspect")
        if let detection = inspection.detection {
          Text(detection.title).font(.headline)
          HStack { badge(detection.confidence.capitalized + " confidence"); badge(detection.adapterVersion) }
          if let name = detection.providerPlayerName { Text("Player candidate: \(name)").font(.caption) }
          if let id = detection.providerPlayerID { Text("Provider player ID: \(id)").font(.caption.monospaced()) }
          if detection.exportType == "trackman_radar" {
            Picker("TrackMan unit system", selection: $trackManUnitSystem) {
              Text("Confirm…").tag("")
              Text("Imperial").tag("imperial")
              Text("Metric").tag("metric")
            }
          }
          if !detection.protectedColumns.isEmpty {
            Text(detection.providerKey == "rapsodo" ? "Sensitive device and location fields were excluded." : "Protected identifiers are excluded from normal display.")
              .font(.caption).foregroundStyle(.secondary)
          }
          if !detection.unsupportedColumns.isEmpty {
            Text("Unsupported or ambiguous: \(detection.unsupportedColumns.joined(separator: ", "))")
              .font(.caption).foregroundStyle(.secondary)
          }
          if detection.automaticMappingSafe {
            HStack {
              Button("Review Import Preview") { useAutomaticMapping = true }
                .buttonStyle(.borderedProminent)
              Button("Adjust Mapping") { useAutomaticMapping = false }
              Button("Use Generic CSV Mapping") { useAutomaticMapping = false; provider = .genericCSV }
            }
          }
        }
        HStack { badge(inspection.detectedFileType.uppercased()); badge(inspection.detectedDelimiter); badge("\(inspection.rowCount) rows") }
        ScrollView(.horizontal) {
          HStack { ForEach(inspection.headers, id: \.self) { Text($0).font(.caption.monospaced()).padding(6).background(DHDTheme.pageBackground).clipShape(RoundedRectangle(cornerRadius: 6)) } }
        }
        if !inspection.providerAdapterActive && provider != .genericCSV {
          Label("Automatic \(provider.label) detection is inactive; confirm every mapping manually.", systemImage: "hand.raised.fill")
            .font(.caption).foregroundStyle(.orange)
        }
      }
    }
  }

  private func mappingCard(service: SupabaseService, organizationId: UUID, userId: UUID) -> some View {
    DHDCard {
      VStack(alignment: .leading, spacing: 12) {
        DHDSectionHeader("3. Map and validate")
        TextField("File time zone", text: $timeZone).textFieldStyle(.roundedBorder)
        if useAutomaticMapping, let suggested = model.inspection?.suggestedMapping,
           model.inspection?.detection?.automaticMappingSafe == true {
          Text("Known columns are mapped automatically. Confirm the player, time zone, units, ignored fields, and preview before import.")
            .font(.caption).foregroundStyle(.secondary)
          ForEach(suggested.wideMetrics ?? [], id: \.column) { metric in
            Text("\(metric.column) → \(metric.metricKey)").font(.caption.monospaced())
          }
        } else {
          Picker("File shape", selection: $shape) { ForEach(SDDevelopmentImportFileShape.allCases) { Text($0.rawValue.capitalized).tag($0) } }.pickerStyle(.segmented)
          mappingPicker("Player column", selection: $playerColumn)
          Picker("Player identifier", selection: $playerColumnRole) {
            Text("Full name").tag("player_name")
            Text("Organization username").tag("player_username")
            Text("Provider external ID").tag("player_external_id")
          }
          mappingPicker("Observation date", selection: $dateColumn)
          Picker("Date format", selection: $dateFormat) {
            Text("ISO date / timestamp").tag("ISO")
            Text("MM/DD/YYYY").tag("MM/DD/YYYY")
          }
          if shape == .long { longMappingEditor } else { wideMappingEditor }
          mappingPicker("Sample size (optional)", selection: $sampleSizeColumn)
        }
        Divider()
        if !model.profiles.isEmpty {
          Menu("Use saved mapping") {
            ForEach(model.profiles) { profile in
              Button(profile.mappingName) { if let mapping = model.useProfile(profile) { apply(mapping) } }
              Button("Archive \(profile.mappingName)", role: .destructive) {
                Task { await model.archiveProfile(profile, client: service, organizationId: organizationId) }
              }
            }
          }
        }
        TextField("Save mapping as (optional)", text: $mappingName).textFieldStyle(.roundedBorder)
        Button {
          operationTask?.cancel()
          operationTask = Task {
            await model.validate(client: service, organizationId: organizationId, userId: userId, mapping: makeMapping(), mappingName: mappingName)
          }
        } label: { Label(model.phase == .validating ? "Validating…" : "Build preview", systemImage: "checklist") }
          .buttonStyle(.borderedProminent).disabled(model.isWorking || !mappingReady)
        Text("Preview only — no player development data has been imported.").font(.caption).foregroundStyle(.secondary)
      }
    }
  }

  private var longMappingEditor: some View {
    VStack(alignment: .leading, spacing: 10) {
      mappingPicker("Metric key / label", selection: $metricColumn)
      mappingPicker("Metric value", selection: $valueColumn)
      mappingPicker("Metric unit", selection: $unitColumn)
      ForEach(longMetricValues, id: \.self) { sourceMetric in
        HStack {
          Text(sourceMetric).font(.caption).frame(maxWidth: .infinity, alignment: .leading)
          Picker("Canonical metric", selection: Binding(get: { longMetricKeys[sourceMetric] ?? sourceMetric }, set: { longMetricKeys[sourceMetric] = $0 })) {
            Text("Unmapped").tag(sourceMetric)
            ForEach(model.metricDefinitions) { Text("\($0.displayName) (\($0.canonicalUnit ?? "unitless"))").tag($0.canonicalKey) }
          }.labelsHidden()
          TextField("Unit", text: Binding(get: { longUnits[sourceMetric] ?? "" }, set: { longUnits[sourceMetric] = $0 })).frame(width: 90).textFieldStyle(.roundedBorder)
        }
      }
    }
  }

  private var wideMappingEditor: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Map each metric column; leave non-metric columns ignored.").font(.caption).foregroundStyle(.secondary)
      ForEach(model.inspection?.headers ?? [], id: \.self) { header in
        if header != playerColumn && header != dateColumn && header != sampleSizeColumn {
          HStack {
            Text(header).font(.caption).frame(maxWidth: .infinity, alignment: .leading)
            Picker("Metric", selection: Binding(get: { wideMetricKeys[header] ?? "" }, set: { wideMetricKeys[header] = $0 })) {
              Text("Ignore").tag("")
              ForEach(model.metricDefinitions) { Text($0.displayName).tag($0.canonicalKey) }
            }.labelsHidden()
            TextField("Source unit", text: Binding(get: { wideUnits[header] ?? "" }, set: { wideUnits[header] = $0 })).frame(width: 100).textFieldStyle(.roundedBorder)
          }
        }
      }
    }
  }

  private func previewCard(_ preview: SDDevelopmentImportPreviewResponse, service: SupabaseService, organizationId: UUID, userId: UUID) -> some View {
    DHDCard {
      VStack(alignment: .leading, spacing: 12) {
        DHDSectionHeader("4. Review preview")
        Text(preview.notice).font(.headline).foregroundStyle(.orange)
        HStack { badge("\(preview.summary.acceptedRows) accepted"); badge("\(preview.summary.rejectedRows) rejected"); badge("\(preview.summary.warningCount) warnings"); badge("\(preview.summary.duplicateRows) duplicates") }
        unresolvedPlayerResolutionSection(
          preview,
          service: service,
          organizationId: organizationId,
          userId: userId
        )
        Picker("Filter", selection: $model.previewFilter) {
          ForEach(["all", "accepted", "warning", "rejected", "unmatched", "ambiguous", "duplicate"], id: \.self) { Text($0.capitalized).tag($0) }
        }.pickerStyle(.segmented)
        ForEach(model.filteredPreviewRows.prefix(100)) { row in
          VStack(alignment: .leading, spacing: 4) {
            HStack { Text("Row \(row.sourceRowNumber)").font(.caption.weight(.semibold)); Spacer(); badge(row.acceptanceState) }
            Text("\(row.playerLabel) • \(row.metricDisplayName ?? row.metricKey ?? "Unmapped metric")").font(.subheadline)
            Text("Original: \(row.originalValue) \(row.originalUnit) → Normalized: \(row.normalizedValue.map { String(format: "%.4f", $0) } ?? "—") \(row.canonicalUnit ?? "")")
              .font(.caption.monospaced()).foregroundStyle(.secondary)
            if !row.errors.isEmpty { Text(row.errors.joined(separator: ", ")).font(.caption).foregroundStyle(.red) }
          }.padding(10).background(DHDTheme.pageBackground).clipShape(RoundedRectangle(cornerRadius: 8))
        }
        if !model.rowErrors.isEmpty {
          DisclosureGroup("Saved validation errors (\(model.rowErrors.count), capped at 100)") {
            ForEach(model.rowErrors.prefix(100)) { error in
              Text("Row \(error.sourceRowNumber): \(error.safeSummary)")
                .font(.caption)
                .foregroundStyle(.secondary)
            }
          }
        }
        Button { showCommitConfirmation = true } label: { Label(model.phase == .committing ? "Importing…" : "Confirm import", systemImage: "square.and.arrow.down") }
          .buttonStyle(.borderedProminent)
          .disabled(model.isWorking || preview.summary.acceptedRows == 0 || model.phase == .completed)
      }
    }
  }

  @ViewBuilder
  private func unresolvedPlayerResolutionSection(
    _ preview: SDDevelopmentImportPreviewResponse,
    service: SupabaseService,
    organizationId: UUID,
    userId: UUID
  ) -> some View {
    let groups = preview.unresolvedPlayerGroups
    if !groups.isEmpty {
      Divider()
      DHDSectionHeader("Resolve imported players") {
        Text("\(groups.count) identities").font(.caption)
      }
      Text("Each selection applies once to every preview observation with the same imported-player identity.")
        .font(.caption)
        .foregroundStyle(.secondary)

      ForEach(groups) { group in
        VStack(alignment: .leading, spacing: 10) {
          HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
              Text(group.playerLabel).font(.headline)
              Text("\(group.affectedObservationCount) affected observation\(group.affectedObservationCount == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(.secondary)
              if let providerID = group.providerPlayerIDHint {
                Text("Provider player ID: \(providerID)")
                  .font(.caption.monospaced())
                  .foregroundStyle(.secondary)
              }
            }
            Spacer()
            badge(group.playerMatchState)
          }

          Picker(
            "Resolve all observations to",
            selection: resolutionSelection(for: group.sourceKey)
          ) {
            Text("Choose a Home Plate player").tag(UUID?.none)
            ForEach(preview.sortedPlayerCandidates) { candidate in
              Text(candidate.username.map { "\(candidate.fullName) (@\($0))" } ?? candidate.fullName)
                .tag(Optional(candidate.id))
            }
          }

          HStack {
            Button("Apply resolution") {
              guard let playerId = selectedResolutionPlayerIds[group.sourceKey] else { return }
              operationTask?.cancel()
              operationTask = Task {
                let applied = await model.resolve(
                  client: service,
                  organizationId: organizationId,
                  userId: userId,
                  sourceKey: group.sourceKey,
                  playerId: playerId
                )
                if applied {
                  selectedResolutionPlayerIds.removeValue(forKey: group.sourceKey)
                }
              }
            }
            .buttonStyle(.borderedProminent)
            .disabled(selectedResolutionPlayerIds[group.sourceKey] == nil || model.isWorking)

            if model.resolvingSourceKey == group.sourceKey {
              ProgressView("Applying to \(group.affectedObservationCount)…")
                .controlSize(.small)
            }
          }
        }
        .padding(12)
        .background(DHDTheme.pageBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
          RoundedRectangle(cornerRadius: 8)
            .stroke(DHDTheme.separator)
            .allowsHitTesting(false)
        )
      }

      if preview.sortedPlayerCandidates.isEmpty {
        Label("No active Home Plate players are available in your authorized scope.", systemImage: "person.crop.circle.badge.exclamationmark")
          .font(.caption)
          .foregroundStyle(.orange)
      } else if preview.playerCandidatesTruncated == true {
        Text("The authorized player list is capped. Refine the organization roster if the player is not shown.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      Divider()
    }
  }

  private func resolutionSelection(for sourceKey: String) -> Binding<UUID?> {
    Binding(
      get: { selectedResolutionPlayerIds[sourceKey] },
      set: { selectedPlayerId in
        if let selectedPlayerId {
          selectedResolutionPlayerIds[sourceKey] = selectedPlayerId
        } else {
          selectedResolutionPlayerIds.removeValue(forKey: sourceKey)
        }
      }
    )
  }

  private func historyCard(
    service: SupabaseService,
    organizationId: UUID,
    userId: UUID
  ) -> some View {
    DHDCard {
      VStack(alignment: .leading, spacing: 10) {
        DHDSectionHeader("Import history")
        if model.history.isEmpty { Text("No imports yet.").foregroundStyle(.secondary) }
        ForEach(model.history) { job in
          VStack(alignment: .leading, spacing: 5) {
            HStack {
              VStack(alignment: .leading, spacing: 2) {
                Text(job.fileName ?? "Import").font(.subheadline.weight(.semibold))
                Text("\(job.provider ?? "generic_csv") • \(job.status.label) • \(job.acceptedRows) accepted / \(job.rejectedRows) rejected")
                  .font(.caption).foregroundStyle(.secondary)
              }
              Spacer()
              if PlayerDevelopmentImportWorkspaceModel.canResumeValidation(job.status) &&
                  !(model.job?.id == job.id && model.preview != nil) {
                Button {
                  operationTask?.cancel()
                  guard model.beginValidationResume(
                    job,
                    organizationId: organizationId,
                    userId: userId
                  ) else { return }
                  operationTask = Task {
                    await model.resumeValidation(
                      client: service,
                      organizationId: organizationId,
                      userId: userId
                    )
                  }
                } label: {
                  HStack(spacing: 5) {
                    if model.resumingJobId == job.id { ProgressView().controlSize(.small) }
                    Text(model.resumingJobId == job.id ? "Resuming…" : "Resume Validation")
                  }
                }
                .font(.caption)
                .disabled(model.isWorking || model.resumingJobId != nil)
              } else if job.status.isFinished && job.status != .archived {
                Button("Archive") { Task { _ = try? await service.archiveDevelopmentImport(organizationId: organizationId, jobId: job.id) } }.font(.caption)
              }
            }
            if model.resumingJobId == job.id {
              Text("Reusing the existing private upload and saved mapping.")
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            if model.resumeErrorJobId == job.id, let error = model.errorMessage {
              Text(error).font(.caption).foregroundStyle(.red)
            }
          }
        }
      }
    }
  }

  private func mappingPicker(_ title: String, selection: Binding<String>) -> some View {
    Picker(title, selection: selection) {
      Text("Not mapped").tag("")
      ForEach(model.inspection?.headers ?? [], id: \.self) { Text($0).tag($0) }
    }
  }

  private var mappingReady: Bool {
    if useAutomaticMapping, let detection = model.inspection?.detection,
       detection.automaticMappingSafe {
      return detection.exportType != "trackman_radar" || !trackManUnitSystem.isEmpty
    }
    let baseReady = !playerColumn.isEmpty && !dateColumn.isEmpty && (shape == .wide ? wideMetricKeys.values.contains(where: { !$0.isEmpty }) : !metricColumn.isEmpty && !valueColumn.isEmpty)
    return baseReady && (model.inspection?.detection?.exportType != "trackman_radar" || !trackManUnitSystem.isEmpty)
  }

  private var longMetricValues: [String] {
    guard shape == .long, let inspection = model.inspection,
          let index = inspection.headers.firstIndex(of: metricColumn), index >= 0 else { return [] }
    return Array(Set(inspection.previewRows.compactMap { index < $0.count ? $0[index].trimmingCharacters(in: .whitespacesAndNewlines) : nil }.filter { !$0.isEmpty })).sorted()
  }

  private func makeMapping() -> SDDevelopmentImportMapping {
    if useAutomaticMapping, var automatic = model.inspection?.suggestedMapping,
       model.inspection?.detection?.automaticMappingSafe == true {
      automatic.timezone = timeZone
      automatic.unitSystem = trackManUnitSystem.nilIfEmpty
      if model.inspection?.detection?.exportType == "trackman_radar" {
        automatic.wideMetrics = automatic.wideMetrics?.map { metric in
          let velocity = ["RelSpeed", "ZoneSpeed", "ExitSpeed"].contains(metric.column)
          let movement = ["InducedVertBreak", "HorzBreak"].contains(metric.column)
          let distance = ["RelHeight", "RelSide", "Extension", "PlateLocHeight", "PlateLocSide", "Distance"].contains(metric.column)
          let unit = velocity ? (trackManUnitSystem == "metric" ? "km/h" : "mph")
            : movement ? (trackManUnitSystem == "metric" ? "cm" : "in")
            : distance ? (trackManUnitSystem == "metric" ? "m" : "ft")
            : metric.sourceUnit
          return SDDevelopmentImportWideMetricMapping(column: metric.column, metricKey: metric.metricKey, sourceUnit: unit)
        }
      }
      return automatic
    }
    var columns = SDDevelopmentImportColumnMapping()
    switch playerColumnRole {
    case "player_username": columns.playerUsername = playerColumn
    case "player_external_id": columns.playerExternalID = playerColumn
    default: columns.playerName = playerColumn
    }
    columns.observationDate = dateColumn
    columns.metric = shape == .long ? metricColumn : nil
    columns.value = shape == .long ? valueColumn : nil
    columns.unit = shape == .long && !unitColumn.isEmpty ? unitColumn : nil
    columns.sampleSize = sampleSizeColumn.nilIfEmpty
    let wide = shape == .wide ? wideMetricKeys.compactMap { header, key in key.isEmpty ? nil : SDDevelopmentImportWideMetricMapping(column: header, metricKey: key, sourceUnit: wideUnits[header]?.nilIfEmpty) } : nil
    let normalizedLongKeys = Dictionary(uniqueKeysWithValues: longMetricKeys.map { (normalizeMappingIdentity($0.key), $0.value) })
    let normalizedLongUnits = Dictionary(uniqueKeysWithValues: longUnits.map { (normalizeMappingIdentity($0.key), $0.value) })
    return SDDevelopmentImportMapping(
      shape: shape, timezone: timeZone, dateFormat: dateFormat, columns: columns,
      wideMetrics: wide, longMetricKeys: normalizedLongKeys.isEmpty ? nil : normalizedLongKeys,
      longSourceUnits: normalizedLongUnits.isEmpty ? nil : normalizedLongUnits,
      contextColumns: nil, playerResolutions: nil,
      adapterVersion: model.inspection?.detection?.adapterVersion,
      detectedExportType: model.inspection?.detection?.exportType,
      unitSystem: trackManUnitSystem.nilIfEmpty
    )
  }

  private func apply(_ mapping: SDDevelopmentImportMapping) {
    shape = mapping.shape
    timeZone = mapping.timezone
    dateFormat = mapping.dateFormat ?? "ISO"
    if let value = mapping.columns.playerExternalID { playerColumn = value; playerColumnRole = "player_external_id" }
    else if let value = mapping.columns.playerUsername { playerColumn = value; playerColumnRole = "player_username" }
    else if let value = mapping.columns.playerName { playerColumn = value; playerColumnRole = "player_name" }
    dateColumn = mapping.columns.observationTimestamp ?? mapping.columns.observationDate ?? ""
    metricColumn = mapping.columns.metric ?? ""
    valueColumn = mapping.columns.value ?? ""
    unitColumn = mapping.columns.unit ?? ""
    sampleSizeColumn = mapping.columns.sampleSize ?? ""
    wideMetricKeys = Dictionary(uniqueKeysWithValues: (mapping.wideMetrics ?? []).map { ($0.column, $0.metricKey) })
    wideUnits = Dictionary(uniqueKeysWithValues: (mapping.wideMetrics ?? []).compactMap { item in item.sourceUnit.map { (item.column, $0) } })
    longMetricKeys = mapping.longMetricKeys ?? [:]
    longUnits = mapping.longSourceUnits ?? [:]
  }

  private func handleFileSelection(_ result: Result<[URL], Error>) {
    guard case .success(let urls) = result, let url = urls.first,
          let service = appState.supabase, let orgId = appState.activeOrgId, let userId = appState.myProfile?.id else {
      if case .failure(let error) = result { model.errorMessage = error.localizedDescription }
      return
    }
    let suffix = url.pathExtension.lowercased()
    guard ["csv", "tsv"].contains(suffix) else { model.errorMessage = "Export spreadsheet files as CSV or TSV."; return }
    let accessing = url.startAccessingSecurityScopedResource()
    defer { if accessing { url.stopAccessingSecurityScopedResource() } }
    do {
      let values = try url.resourceValues(forKeys: [.fileSizeKey])
      guard (values.fileSize ?? 0) <= 10 * 1024 * 1024 else { model.errorMessage = "CSV and TSV files must be 10 MB or smaller."; return }
      let data = try Data(contentsOf: url, options: .mappedIfSafe)
      guard data.count <= 10 * 1024 * 1024 else {
        model.errorMessage = "CSV and TSV files must be 10 MB or smaller."
        return
      }
      operationTask?.cancel()
      operationTask = Task {
        await model.uploadAndInspect(client: service, organizationId: orgId, userId: userId, playerId: player?.id, provider: provider, fileName: url.lastPathComponent, data: data)
      }
    } catch { model.errorMessage = "The selected file could not be read." }
  }

  private func clearDraft() {
    playerColumn = ""; dateColumn = ""; metricColumn = ""; valueColumn = ""; unitColumn = ""; sampleSizeColumn = ""
    wideMetricKeys = [:]; wideUnits = [:]; longMetricKeys = [:]; longUnits = [:]; mappingName = ""
    trackManUnitSystem = ""
    useAutomaticMapping = true
  }

  @ViewBuilder private func conflictRecoveryCard(
    service: SupabaseService,
    organizationId: UUID,
    userId: UUID
  ) -> some View {
    if model.recoveryAction == .resumeValidation {
      DHDCard {
        VStack(alignment: .leading, spacing: 8) {
          Text("Validation was not saved").font(.headline)
          Text("The uploaded file and saved mapping are still available. Retrying replaces the incomplete validation details without importing observations.").font(.caption)
          Button {
            operationTask?.cancel()
            guard let job = model.job,
                  model.beginValidationResume(
                    job,
                    organizationId: organizationId,
                    userId: userId
                  ) else { return }
            operationTask = Task {
              await model.resumeValidation(
                client: service,
                organizationId: organizationId,
                userId: userId
              )
            }
          } label: {
            HStack(spacing: 6) {
              if model.resumingJobId != nil { ProgressView().controlSize(.small) }
              Text(model.resumingJobId != nil ? "Resuming…" : "Resume Validation")
            }
          }
          .disabled(model.isWorking || model.resumingJobId != nil)
        }
      }
    } else if model.recoveryAction == .startOver {
      DHDCard {
        VStack(alignment: .leading, spacing: 8) {
          Text("This upload can no longer be resumed").font(.headline)
          Text("Start Over archives only the incomplete job. No observations are created or removed.").font(.caption)
          Button("Start Over") {
            operationTask?.cancel()
            operationTask = Task {
              if await model.startOver(
                client: service,
                organizationId: organizationId,
                userId: userId
              ) {
                showFileImporter = true
              }
            }
          }
        }
      }
    } else if let code = model.errorCode, ["idempotent_import_already_started", "active_import_exists", "job_not_ready"].contains(code) {
      DHDCard {
        VStack(alignment: .leading, spacing: 8) {
          Text("Import state changed").font(.headline)
          if let active = model.history.first(where: { !$0.status.isFinished }) {
            Button("Resume existing import") { model.resumeExistingImport(active) }
          }
          if code == "job_not_ready" { Text("Refresh import history to use the authoritative next step.").font(.caption) }
        }
      }
    } else if let code = model.errorCode, ["duplicate_file_reused", "completed_import_exists"].contains(code) {
      DHDCard {
        VStack(alignment: .leading, spacing: 8) {
          Text("This file and mapping were already imported.").font(.headline)
          if let completed = model.history.first(where: { $0.status == .completed || $0.status == .completedWithErrors }) {
            Button("View completed import") { model.viewCompletedImport(completed) }
          }
        }
      }
    }
  }

  private func normalizeMappingIdentity(_ value: String) -> String {
    value.folding(
      options: [.diacriticInsensitive, .caseInsensitive],
      locale: Locale(identifier: "en_US_POSIX")
    )
    .lowercased()
    .components(separatedBy: CharacterSet.alphanumerics.inverted)
    .filter { !$0.isEmpty }
    .joined(separator: " ")
  }

  private func badge(_ text: String) -> some View {
    Text(text).font(.caption2.weight(.semibold)).padding(.horizontal, 7).padding(.vertical, 4).background(Color.secondary.opacity(0.12)).clipShape(Capsule())
  }

  private func messageCard(_ text: String, color: Color, icon: String) -> some View {
    DHDCard { Label(text, systemImage: icon).foregroundStyle(color) }
  }
}

private extension String {
  var nilIfEmpty: String? { isEmpty ? nil : self }
}
