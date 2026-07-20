import Foundation
import Testing
@testable import HomePlate

@Suite("Player Development Imports Phase 11B.2")
struct PlayerDevelopmentImportTests {
  let orgId = UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")!
  let otherOrgId = UUID(uuidString: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb")!
  let userId = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
  let playerId = UUID(uuidString: "44444444-4444-4444-8444-444444444444")!

  @Test("Provider and file shape contracts identify automatic adapters")
  func providerContracts() {
    #expect(SDDevelopmentImportProvider.allCases.count == 7)
    #expect(SDDevelopmentImportProvider.rapsodo.label.contains("automatic detection"))
    #expect(SDDevelopmentImportProvider.trackman.label.contains("automatic detection"))
    #expect(SDDevelopmentImportFileShape.allCases == [.wide, .long])
  }

  @Test("Only active staff sees import navigation")
  func presentationAuthorization() {
    for role in ["owner", "admin", "coach"] {
      #expect(SDDevelopmentImportPresentationAuthorization.isVisible(membership: membership(role)))
    }
    for role in ["parent", "player"] {
      #expect(!SDDevelopmentImportPresentationAuthorization.isVisible(membership: membership(role)))
    }
    #expect(!SDDevelopmentImportPresentationAuthorization.isVisible(membership: membership("coach", status: "disabled")))
    #expect(!SDDevelopmentImportPresentationAuthorization.isVisible(membership: nil))
  }

  @Test("Long mapping encodes every explicit role without actor authority")
  func mappingEncoding() throws {
    let mapping = longMapping()
    let object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(mapping)) as? [String: Any])
    #expect(object["shape"] as? String == "long")
    #expect(object["timezone"] as? String == "America/New_York")
    let columns = try #require(object["columns"] as? [String: Any])
    #expect(columns["player_username"] as? String == "username")
    #expect(columns["observation_date"] as? String == "date")
    #expect(columns["metric"] as? String == "metric")
    #expect(columns["value"] as? String == "value")
    #expect(columns["unit"] as? String == "unit")
    #expect(object["actor_id"] == nil)
  }

  @Test("Exact import job, inspection, preview, and provenance contracts decode")
  func responseDecoding() throws {
    let decoder = JSONDecoder()
    let create = try decoder.decode(SDDevelopmentImportCreateResponse.self, from: Data(createJSON.utf8))
    #expect(create.job.organizationId == orgId)
    #expect(create.job.status == .pending)
    #expect(create.upload.maxFileBytes == 10_485_760)
    let inspection = try decoder.decode(SDDevelopmentImportInspectResponse.self, from: Data(inspectJSON.utf8))
    #expect(inspection.inspection.detectedDelimiter == "comma")
    #expect(inspection.inspection.headers.count == 5)
    let preview = try decoder.decode(SDDevelopmentImportPreviewResponse.self, from: Data(previewJSON.utf8))
    #expect(preview.notice.contains("Preview only"))
    #expect(preview.rows.first?.originalUnit == "km/h")
    #expect(preview.rows.first?.canonicalUnit == "mph")
    #expect(preview.summary.acceptedRows == 1)
  }

  @Test("Unresolved observations group deterministically by authoritative imported-player identity")
  func deterministicUnresolvedPlayerGrouping() throws {
    let sourceKey = "external:rapsodo-player-12345678"
    let rows = (0..<13).map { index in
      SDDevelopmentImportPreviewRow(
        sourceRowNumber: index + 2,
        playerSourceKey: sourceKey,
        playerMatchState: "unmatched",
        playerId: nil,
        playerLabel: "Owen Pincince",
        metricKey: "metric.\(index)",
        metricDisplayName: "Metric \(index)",
        originalValue: "1",
        originalUnit: "mph",
        normalizedValue: 1,
        canonicalUnit: "mph",
        observedAt: "2026-07-01T12:00:00Z",
        acceptanceState: "rejected",
        warnings: [],
        errors: ["missing_player"]
      )
    } + [
      SDDevelopmentImportPreviewRow(
        sourceRowNumber: 20,
        playerSourceKey: "name:alex alpha",
        playerMatchState: "ambiguous",
        playerId: nil,
        playerLabel: "Alex Alpha",
        metricKey: "metric.other",
        metricDisplayName: "Other Metric",
        originalValue: "2",
        originalUnit: "mph",
        normalizedValue: 2,
        canonicalUnit: "mph",
        observedAt: "2026-07-01T12:00:00Z",
        acceptanceState: "rejected",
        warnings: [],
        errors: ["ambiguous_player"]
      ),
    ]
    let laterCandidate = UUID(uuidString: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb")!
    let earlierCandidate = UUID(uuidString: "cccccccc-cccc-4ccc-8ccc-cccccccccccc")!
    let preview = SDDevelopmentImportPreviewResponse(
      notice: "Preview only",
      status: "player_resolution_required",
      summary: SDDevelopmentImportValidationSummary(
        totalRows: 14,
        generatedObservations: 14,
        acceptedRows: 0,
        rejectedRows: 14,
        unmatchedPlayerRows: 13,
        ambiguousPlayerRows: 1,
        warningCount: 0,
        duplicateRows: 0
      ),
      rows: Array(rows.reversed()),
      detectedFileType: "csv",
      detectedDelimiter: "comma",
      headers: ["Player"],
      playerCandidates: [
        SDDevelopmentImportPlayerCandidate(id: laterCandidate, fullName: "Zoe Player", username: "zoe"),
        SDDevelopmentImportPlayerCandidate(id: earlierCandidate, fullName: "Avery Player", username: "avery"),
      ],
      playerCandidatesTruncated: false
    )

    #expect(preview.unresolvedPlayerGroups.map(\.playerLabel) == ["Alex Alpha", "Owen Pincince"])
    let owen = try #require(preview.unresolvedPlayerGroups.last)
    #expect(owen.sourceKey == sourceKey)
    #expect(owen.affectedObservationCount == 13)
    #expect(owen.providerPlayerIDHint == "••••5678")
    #expect(!owen.providerPlayerIDHint!.contains("rapsodo-player"))
    #expect(preview.sortedPlayerCandidates.map(\.id) == [earlierCandidate, laterCandidate])
  }

  @Test("Unknown future job status fails safely")
  func unknownStatus() throws {
    #expect(try JSONDecoder().decode(SDDevelopmentImportStatus.self, from: Data(#""future_state""#.utf8)) == .unknown)
  }

  @Test("Nested Edge error envelope preserves safe 409 code and readable message")
  func nestedImportError() {
    let data = Data(#"{"error":{"code":"job_create_failed","message":"A new import job could not be created."}}"#.utf8)
    let error = SDEdgeFunctionHTTPError.decode(statusCode: 409, data: data)
    #expect(error.code == "job_create_failed")
    #expect(error.message == "A new import job could not be created.")
  }

  @Test("Recognized provider detection exposes version, confidence, mappings, and protected fields")
  @MainActor
  func recognizedDetection() async {
    let client = MockImportClient()
    let model = PlayerDevelopmentImportWorkspaceModel()
    await model.uploadAndInspect(client: client, organizationId: orgId, userId: userId, playerId: playerId, provider: .genericCSV, fileName: "synthetic.csv", data: Data())
    #expect(model.inspection?.detection?.title == "Rapsodo Pitching detected")
    #expect(model.inspection?.detection?.confidence == "high")
    #expect(model.inspection?.detection?.protectedColumns.contains("SO - latitude") == true)
    #expect(model.inspection?.suggestedMapping?.adapterVersion == "rapsodo-pitching.v1")
  }

  @Test("Readable 409 state includes stable code and supports active/completed recovery")
  @MainActor
  func conflictRecovery() async {
    let client = MockImportClient()
    client.nextError = SDEdgeFunctionHTTPError(statusCode: 409, code: "idempotent_import_already_started", message: "Resume its existing job.")
    let model = PlayerDevelopmentImportWorkspaceModel()
    await model.uploadAndInspect(client: client, organizationId: orgId, userId: userId, playerId: playerId, provider: .genericCSV, fileName: "synthetic.csv", data: Data())
    #expect(model.errorCode == "idempotent_import_already_started")
    #expect(model.errorMessage == "[idempotent_import_already_started] Resume its existing job.")
    model.resumeExistingImport(client.job(status: .ready))
    #expect(model.phase == .preview)
    model.viewCompletedImport(client.job(status: .completed))
    #expect(model.phase == .completed)
  }

  @Test("Validation persistence failure keeps the job resumable without another upload or mapping save")
  @MainActor
  func validationPersistenceRecovery() async {
    let client = MockImportClient()
    let model = PlayerDevelopmentImportWorkspaceModel()
    await model.uploadAndInspect(client: client, organizationId: orgId, userId: userId, playerId: playerId, provider: .rapsodo, fileName: "synthetic.csv", data: Data())
    client.validationError = SDEdgeFunctionHTTPError(
      statusCode: 500,
      code: "validation_persistence_failed",
      message: "Validation details could not be saved. Resume Validation to retry safely."
    )
    await model.validate(
      client: client,
      organizationId: orgId,
      userId: userId,
      mapping: longMapping(),
      mappingName: nil
    )
    #expect(model.errorCode == "validation_persistence_failed")
    #expect(model.errorMessage?.contains("Resume Validation") == true)
    #expect(model.recoveryAction == .resumeValidation)
    #expect(client.validateCalls == 1)
    #expect(model.beginValidationResume(try! #require(model.job), organizationId: orgId, userId: userId))
    #expect(model.phase == .validating)
    #expect(model.resumingJobId == client.jobId)
    await model.resumeValidation(client: client, organizationId: orgId, userId: userId)
    #expect(model.phase == .preview)
    #expect(client.validateCalls == 2)
    #expect(client.createKeys.count == 1)
    #expect(client.uploadCalls == 1)
    #expect(client.savedMappingCalls == 1)
    #expect(model.recoveryAction == .none)
  }

  @Test("An existing validating job resumes after app reload without create, upload, or mapping writes")
  @MainActor
  func existingJobRecovery() async {
    let client = MockImportClient()
    let model = PlayerDevelopmentImportWorkspaceModel()
    model.prepareValidationResume(client.job(status: .validating))
    #expect(model.recoveryAction == .resumeValidation)
    #expect(model.beginValidationResume(client.job(status: .validating), organizationId: orgId, userId: userId))
    await model.resumeValidation(client: client, organizationId: orgId, userId: userId)
    #expect(model.phase == .preview)
    #expect(client.validateCalls == 1)
    #expect(client.createKeys.isEmpty)
    #expect(client.uploadCalls == 0)
    #expect(client.savedMappingCalls == 0)
  }

  @Test("Resume controls are tap-safe, visibly wired, and use the exact Edge request contract")
  func resumeControlWiring() throws {
    let projectRoot = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    let components = try String(
      contentsOf: projectRoot.appendingPathComponent("MultiOrg/Core/DHDUIComponents.swift"),
      encoding: .utf8
    )
    let view = try String(
      contentsOf: projectRoot.appendingPathComponent("MultiOrg/Features/Coach/PlayerDevelopmentImportView.swift"),
      encoding: .utf8
    )
    let service = try String(
      contentsOf: projectRoot.appendingPathComponent("MultiOrg/Core/SupabaseService.swift"),
      encoding: .utf8
    )
    #expect(components.components(separatedBy: ".allowsHitTesting(false)").count - 1 >= 2)
    #expect(view.contains("model.beginValidationResume("))
    #expect(view.contains("operationTask = Task"))
    #expect(view.contains("await model.resumeValidation("))
    #expect(view.contains("\"Resuming…\""))
    #expect(view.contains(".disabled(model.isWorking || model.resumingJobId != nil)"))
    #expect(service.contains("let action = \"validate_job\"; let org_id: UUID; let job_id: UUID"))
  }

  @Test("Only resumable validation lifecycle states are eligible")
  @MainActor
  func resumeEligibility() {
    for status in [SDDevelopmentImportStatus.validating, .playerResolutionRequired, .ready] {
      #expect(PlayerDevelopmentImportWorkspaceModel.canResumeValidation(status))
    }
    for status in [SDDevelopmentImportStatus.completed, .completedWithErrors, .archived, .failed] {
      #expect(!PlayerDevelopmentImportWorkspaceModel.canResumeValidation(status))
    }
  }

  @Test("Resume loading is immediate, duplicate starts are blocked, and the existing job is reused")
  @MainActor
  func immediateResumeAndDuplicatePrevention() async {
    let client = MockImportClient()
    let model = PlayerDevelopmentImportWorkspaceModel()
    let existing = client.job(status: .validating)
    #expect(model.beginValidationResume(existing, organizationId: orgId, userId: userId))
    #expect(model.phase == .validating)
    #expect(model.resumingJobId == existing.id)
    #expect(!model.beginValidationResume(existing, organizationId: orgId, userId: userId))
    await model.resumeValidation(client: client, organizationId: orgId, userId: userId)
    #expect(client.validateJobIds == [existing.id])
    #expect(client.getJobIds == [existing.id])
    #expect(client.createKeys.isEmpty)
    #expect(client.uploadCalls == 0)
    #expect(client.savedMappingCalls == 0)
    #expect(client.commitCalls == 0)
  }

  @Test("Resume refreshes the authoritative job and routes ready and player-resolution results to preview")
  @MainActor
  func resumeRefreshAndRouting() async {
    for status in [SDDevelopmentImportStatus.ready, .playerResolutionRequired] {
      let client = MockImportClient()
      client.validationResultStatus = status
      let model = PlayerDevelopmentImportWorkspaceModel()
      #expect(model.beginValidationResume(client.job(status: .validating), organizationId: orgId, userId: userId))
      await model.resumeValidation(client: client, organizationId: orgId, userId: userId)
      #expect(model.phase == .preview)
      #expect(model.preview != nil)
      #expect(model.job?.status == status)
      #expect(model.history.first?.status == status)
      #expect(model.resumingJobId == nil)
    }
  }

  @Test("Resume errors are readable and retry the same existing job")
  @MainActor
  func resumeErrorAndRetry() async {
    let client = MockImportClient()
    let model = PlayerDevelopmentImportWorkspaceModel()
    let existing = client.job(status: .validating)
    client.validationError = SDEdgeFunctionHTTPError(
      statusCode: 500,
      code: "validation_persistence_failed",
      message: "Validation details could not be saved."
    )
    #expect(model.beginValidationResume(existing, organizationId: orgId, userId: userId))
    await model.resumeValidation(client: client, organizationId: orgId, userId: userId)
    #expect(model.errorMessage == "[validation_persistence_failed] Validation details could not be saved.")
    #expect(model.resumeErrorJobId == existing.id)
    #expect(model.resumingJobId == nil)
    #expect(model.beginValidationResume(existing, organizationId: orgId, userId: userId))
    await model.resumeValidation(client: client, organizationId: orgId, userId: userId)
    #expect(client.validateJobIds == [existing.id, existing.id])
    #expect(client.createKeys.isEmpty)
    #expect(client.uploadCalls == 0)
    #expect(model.phase == .preview)
  }

  @Test("Organization or user context changes clear resume state and reject stale results")
  @MainActor
  func staleResumeRejection() async {
    let client = MockImportClient()
    client.validationDelay = 80_000_000
    let model = PlayerDevelopmentImportWorkspaceModel()
    #expect(model.beginValidationResume(client.job(status: .validating), organizationId: orgId, userId: userId))
    let resume = Task { @MainActor in
      await model.resumeValidation(client: client, organizationId: orgId, userId: userId)
    }
    try? await Task.sleep(nanoseconds: 10_000_000)
    model.reset()
    _ = model.beginContext(organizationId: otherOrgId, userId: UUID())
    await resume.value
    #expect(model.job == nil)
    #expect(model.preview == nil)
    #expect(model.history.isEmpty)
    #expect(model.resumingJobId == nil)
    #expect(client.getJobIds.isEmpty)
  }

  @Test("Start Over is limited to non-resumable artifact failures and archives the incomplete job")
  @MainActor
  func boundedStartOver() async {
    let client = MockImportClient()
    let model = PlayerDevelopmentImportWorkspaceModel()
    await model.uploadAndInspect(client: client, organizationId: orgId, userId: userId, playerId: playerId, provider: .rapsodo, fileName: "synthetic.csv", data: Data())
    client.validationError = SDEdgeFunctionHTTPError(
      statusCode: 409,
      code: "file_identity_changed",
      message: "The uploaded file no longer matches the inspected file."
    )
    await model.validate(
      client: client,
      organizationId: orgId,
      userId: userId,
      mapping: longMapping(),
      mappingName: nil
    )
    #expect(model.recoveryAction == .startOver)
    #expect(await model.startOver(client: client, organizationId: orgId, userId: userId))
    #expect(client.archiveCalls == 1)
    #expect(model.phase == .idle)
    #expect(model.job == nil)
    #expect(model.successMessage?.contains("Select the file again") == true)
  }

  @Test("Upload, inspection, mappings, definitions, and history reach mapping state")
  @MainActor
  func uploadAndInspect() async {
    let client = MockImportClient()
    let model = PlayerDevelopmentImportWorkspaceModel()
    await model.uploadAndInspect(client: client, organizationId: orgId, userId: userId, playerId: playerId, provider: .genericCSV, fileName: "synthetic.csv", data: Data("player,date".utf8))
    #expect(model.phase == .mapping)
    #expect(client.uploadCalls == 1)
    #expect(model.inspection?.headers.first == "username")
    await model.loadHistory(client: client, organizationId: orgId, userId: userId, provider: .genericCSV)
    #expect(model.history.count == 1)
    #expect(model.metricDefinitions.count == 1)
    #expect(model.profiles.count == 1)
  }

  @Test("Upload failure is visible and retry succeeds")
  @MainActor
  func uploadFailureRetry() async {
    let client = MockImportClient()
    client.nextError = ImportTestError.readable
    let model = PlayerDevelopmentImportWorkspaceModel()
    await model.uploadAndInspect(client: client, organizationId: orgId, userId: userId, playerId: playerId, provider: .genericCSV, fileName: "synthetic.csv", data: Data())
    #expect(model.phase == .failed(ImportTestError.readable.localizedDescription))
    #expect(model.errorMessage == "Synthetic import failure.")
    await model.uploadAndInspect(client: client, organizationId: orgId, userId: userId, playerId: playerId, provider: .genericCSV, fileName: "synthetic.csv", data: Data())
    #expect(model.phase == .mapping)
    #expect(client.createKeys.count == 2)
    #expect(client.createKeys[0] == client.createKeys[1])
  }

  @Test("Material file changes rotate the pending create operation key")
  @MainActor
  func createOperationRotation() async {
    let client = MockImportClient()
    let model = PlayerDevelopmentImportWorkspaceModel()
    client.nextError = ImportTestError.readable
    await model.uploadAndInspect(client: client, organizationId: orgId, userId: userId, playerId: playerId, provider: .genericCSV, fileName: "synthetic.csv", data: Data("one".utf8))
    client.nextError = ImportTestError.readable
    await model.uploadAndInspect(client: client, organizationId: orgId, userId: userId, playerId: playerId, provider: .genericCSV, fileName: "synthetic.csv", data: Data("two".utf8))
    #expect(client.createKeys.count == 2)
    #expect(client.createKeys[0] != client.createKeys[1])
  }

  @Test("Upload retry resumes the existing job and target without creating a second job")
  @MainActor
  func uploadTargetRetry() async {
    let client = MockImportClient()
    client.failUploadOnce = true
    let model = PlayerDevelopmentImportWorkspaceModel()
    await model.uploadAndInspect(client: client, organizationId: orgId, userId: userId, playerId: playerId, provider: .genericCSV, fileName: "synthetic.csv", data: Data("same".utf8))
    #expect(client.createKeys.count == 1)
    await model.uploadAndInspect(client: client, organizationId: orgId, userId: userId, playerId: playerId, provider: .genericCSV, fileName: "synthetic.csv", data: Data("same".utf8))
    #expect(client.createKeys.count == 1)
    #expect(model.phase == .mapping)
  }

  @Test("Validation saves mapping and renders accepted, rejected, unmatched, and duplicate totals")
  @MainActor
  func validationAndFilters() async {
    let client = MockImportClient()
    let model = PlayerDevelopmentImportWorkspaceModel()
    await model.uploadAndInspect(client: client, organizationId: orgId, userId: userId, playerId: playerId, provider: .genericCSV, fileName: "synthetic.csv", data: Data())
    await model.validate(client: client, organizationId: orgId, userId: userId, mapping: longMapping(), mappingName: "Generic Long")
    #expect(model.phase == .preview)
    #expect(model.preview?.summary.acceptedRows == 1)
    model.previewFilter = "accepted"
    #expect(model.filteredPreviewRows.count == 1)
    model.previewFilter = "unmatched"
    #expect(model.filteredPreviewRows.isEmpty)
    #expect(client.savedMappingName == "Generic Long")
    model.invalidatePreview()
    #expect(model.preview == nil)
    #expect(model.phase == .mapping)
  }

  @Test("Manual player resolution revalidates preview")
  @MainActor
  func manualResolution() async {
    let client = MockImportClient()
    let model = PlayerDevelopmentImportWorkspaceModel()
    await model.uploadAndInspect(client: client, organizationId: orgId, userId: userId, playerId: playerId, provider: .genericCSV, fileName: "synthetic.csv", data: Data())
    #expect(await model.resolve(client: client, organizationId: orgId, userId: userId, sourceKey: "name:fictional avery", playerId: playerId))
    #expect(client.resolutions == ["name:fictional avery": playerId])
    #expect(client.resolutionSourceKeys == ["name:fictional avery"])
    #expect(client.validateCalls == 1)
    #expect(client.getJobIds == [client.jobId])
    #expect(model.job?.status == .ready)
    #expect(model.preview != nil)
  }

  @Test("Bulk player resolution blocks duplicate applies and sends one source-key mutation")
  @MainActor
  func duplicateBulkResolutionPrevention() async {
    let client = MockImportClient()
    client.resolutionDelay = 80_000_000
    let model = PlayerDevelopmentImportWorkspaceModel()
    await model.uploadAndInspect(client: client, organizationId: orgId, userId: userId, playerId: playerId, provider: .rapsodo, fileName: "synthetic.csv", data: Data())
    let first = Task { @MainActor in
      await model.resolve(
        client: client,
        organizationId: orgId,
        userId: userId,
        sourceKey: "external:owen-provider-id",
        playerId: playerId
      )
    }
    try? await Task.sleep(nanoseconds: 10_000_000)
    #expect(model.resolvingSourceKey == "external:owen-provider-id")
    #expect(!(await model.resolve(
      client: client,
      organizationId: orgId,
      userId: userId,
      sourceKey: "external:owen-provider-id",
      playerId: playerId
    )))
    #expect(await first.value)
    #expect(client.resolutionSourceKeys == ["external:owen-provider-id"])
    #expect(client.validateCalls == 1)
    #expect(client.getJobIds == [client.jobId])
    #expect(model.resolvingSourceKey == nil)
  }

  @Test("Explicit confirmation commits once and partial success is retained")
  @MainActor
  func duplicateCommitPrevention() async {
    let client = MockImportClient()
    client.commitJob = client.job(status: .completedWithErrors, accepted: 1, rejected: 1)
    client.commitDelay = 80_000_000
    let model = PlayerDevelopmentImportWorkspaceModel()
    await model.uploadAndInspect(client: client, organizationId: orgId, userId: userId, playerId: playerId, provider: .genericCSV, fileName: "synthetic.csv", data: Data())
    await model.validate(client: client, organizationId: orgId, userId: userId, mapping: longMapping(), mappingName: nil)
    let first = Task { @MainActor in await model.commit(client: client, organizationId: orgId, userId: userId) }
    try? await Task.sleep(nanoseconds: 10_000_000)
    #expect(!(await model.commit(client: client, organizationId: orgId, userId: userId)))
    #expect(await first.value)
    #expect(client.commitCalls == 1)
    #expect(model.phase == .completed)
    #expect(model.job?.status == .completedWithErrors)
    #expect(model.successMessage?.contains("Reports and alerts were not run") == true)
  }

  @Test("Commit failure exposes retry and does not leave loading state")
  @MainActor
  func commitRetry() async {
    let client = MockImportClient()
    let model = PlayerDevelopmentImportWorkspaceModel()
    await model.uploadAndInspect(client: client, organizationId: orgId, userId: userId, playerId: playerId, provider: .genericCSV, fileName: "synthetic.csv", data: Data())
    await model.validate(client: client, organizationId: orgId, userId: userId, mapping: longMapping(), mappingName: nil)
    client.nextError = ImportTestError.readable
    #expect(!(await model.commit(client: client, organizationId: orgId, userId: userId)))
    #expect(model.phase == .preview)
    #expect(await model.commit(client: client, organizationId: orgId, userId: userId))
  }

  @Test("Saved mapping requires exact header fingerprint")
  @MainActor
  func mappingHeaderMismatch() async {
    let client = MockImportClient()
    let model = PlayerDevelopmentImportWorkspaceModel()
    await model.uploadAndInspect(client: client, organizationId: orgId, userId: userId, playerId: playerId, provider: .genericCSV, fileName: "synthetic.csv", data: Data())
    #expect(model.useProfile(client.mappingProfile(headerFingerprint: String(repeating: "f", count: 64))) != nil)
    #expect(model.useProfile(client.mappingProfile(headerFingerprint: String(repeating: "a", count: 64))) == nil)
    #expect(model.errorMessage?.contains("incompatible headers") == true)
  }

  @Test("Saved mappings can be archived without affecting the import job")
  @MainActor
  func mappingArchive() async {
    let client = MockImportClient()
    let model = PlayerDevelopmentImportWorkspaceModel()
    _ = model.beginContext(organizationId: orgId, userId: userId)
    await model.loadHistory(client: client, organizationId: orgId, userId: userId, provider: .genericCSV)
    let profile = try! #require(model.profiles.first)
    await model.archiveProfile(profile, client: client, organizationId: orgId)
    #expect(model.profiles.isEmpty)
    #expect(model.job == nil)
  }

  @Test("Organization and user switches reject stale results and clear import state")
  @MainActor
  func staleResponseRejection() async {
    let client = MockImportClient()
    client.listDelay = 80_000_000
    let model = PlayerDevelopmentImportWorkspaceModel()
    model.beginContext(organizationId: orgId, userId: userId)
    let load = Task { @MainActor in await model.loadHistory(client: client, organizationId: orgId, userId: userId, provider: .genericCSV) }
    try? await Task.sleep(nanoseconds: 10_000_000)
    model.beginContext(organizationId: otherOrgId, userId: userId)
    await load.value
    #expect(model.history.isEmpty)
    model.reset()
    #expect(model.inspection == nil)
    #expect(model.preview == nil)
    #expect(model.contextToken == nil)
  }

  private func membership(_ role: String, status: String = "active") -> SDOrgMembership {
    SDOrgMembership(org_id: orgId, user_id: userId, role: role, status: status, created_at: nil, created_by: nil)
  }

  private func longMapping() -> SDDevelopmentImportMapping {
    SDDevelopmentImportMapping(
      shape: .long,
      timezone: "America/New_York",
      dateFormat: "ISO",
      columns: SDDevelopmentImportColumnMapping(
        playerName: nil,
        playerUsername: "username",
        observationDate: "date",
        metric: "metric",
        value: "value",
        unit: "unit"
      ),
      wideMetrics: nil,
      longMetricKeys: ["exit velocity": "hitting.max_exit_velocity"],
      longSourceUnits: ["exit velocity": "km/h"],
      contextColumns: nil,
      playerResolutions: nil
    )
  }
}

@MainActor
private final class MockImportClient: PlayerDevelopmentImportClient {
  let orgId = UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")!
  let userId = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
  let playerId = UUID(uuidString: "44444444-4444-4444-8444-444444444444")!
  let jobId = UUID(uuidString: "77777777-7777-4777-8777-777777777777")!
  var uploadCalls = 0
  var failUploadOnce = false
  var uploaded = false
  var createKeys: [UUID] = []
  var commitCalls = 0
  var validateCalls = 0
  var validateJobIds: [UUID] = []
  var getJobIds: [UUID] = []
  var savedMappingCalls = 0
  var archiveCalls = 0
  var savedMappingName: String?
  var resolutions: [String: UUID] = [:]
  var resolutionSourceKeys: [String] = []
  var resolutionDelay: UInt64 = 0
  var nextError: Error?
  var validationError: Error?
  var validationDelay: UInt64 = 0
  var validationResultStatus = SDDevelopmentImportStatus.ready
  var listDelay: UInt64 = 0
  var commitDelay: UInt64 = 0
  lazy var commitJob = job(status: .completed, accepted: 1, rejected: 0)

  func createDevelopmentImportJob(organizationId: UUID, playerId: UUID?, provider: SDDevelopmentImportProvider, fileName: String, idempotencyKey: UUID) async throws -> SDDevelopmentImportCreateResponse {
    createKeys.append(idempotencyKey)
    try failIfNeeded()
    return SDDevelopmentImportCreateResponse(job: job(status: .pending), upload: SDDevelopmentImportUploadTarget(bucket: "player-development-imports", path: "\(orgId)/\(jobId)/file.csv", maxFileBytes: 10_485_760, upsert: false))
  }
  func uploadDevelopmentImportFile(_ data: Data, target: SDDevelopmentImportUploadTarget, fileType: String) async throws {
    if failUploadOnce {
      failUploadOnce = false
      throw ImportTestError.readable
    }
    try failIfNeeded()
    uploadCalls += 1
    uploaded = true
  }
  func inspectDevelopmentImport(organizationId: UUID, jobId: UUID) async throws -> SDDevelopmentImportInspectResponse {
    try failIfNeeded()
    if !uploaded {
      throw SDEdgeFunctionHTTPError(statusCode: 409, code: "upload_not_found", message: "The private upload could not be found.")
    }
    return SDDevelopmentImportInspectResponse(job: job(status: .mappingRequired), inspection: inspection())
  }
  func saveDevelopmentImportMapping(organizationId: UUID, jobId: UUID, mapping: SDDevelopmentImportMapping, mappingName: String?) async throws -> SDDevelopmentImportJob {
    try failIfNeeded(); savedMappingCalls += 1; savedMappingName = mappingName; return job(status: .validating)
  }
  func validateDevelopmentImport(organizationId: UUID, jobId: UUID) async throws -> SDDevelopmentImportPreviewResponse {
    validateCalls += 1
    validateJobIds.append(jobId)
    if let validationError { self.validationError = nil; throw validationError }
    if validationDelay > 0 { try await Task.sleep(nanoseconds: validationDelay) }
    try failIfNeeded()
    return preview()
  }
  func getDevelopmentImportJob(organizationId: UUID, jobId: UUID) async throws -> SDDevelopmentImportJob {
    getJobIds.append(jobId)
    try failIfNeeded()
    return job(status: validationResultStatus)
  }
  func commitDevelopmentImport(organizationId: UUID, jobId: UUID) async throws -> SDDevelopmentImportCommitResponse {
    try failIfNeeded(); commitCalls += 1
    if commitDelay > 0 { try await Task.sleep(nanoseconds: commitDelay) }
    return SDDevelopmentImportCommitResponse(job: commitJob, reused: false)
  }
  func listDevelopmentImportJobs(organizationId: UUID) async throws -> [SDDevelopmentImportJob] {
    if listDelay > 0 { try await Task.sleep(nanoseconds: listDelay) }
    try failIfNeeded(); return [job(status: .completed)]
  }
  func listDevelopmentImportMappings(organizationId: UUID, provider: SDDevelopmentImportProvider) async throws -> [SDDevelopmentImportMappingProfile] { try failIfNeeded(); return [mappingProfile(headerFingerprint: String(repeating: "f", count: 64))] }
  func listDevelopmentMetricDefinitions() async throws -> [SDDevelopmentMetricDefinition] {
    try failIfNeeded()
    return [SDDevelopmentMetricDefinition(id: UUID(), canonicalKey: "hitting.max_exit_velocity", displayName: "Maximum Exit Velocity", category: "hitting", canonicalUnit: "mph", preferredDirection: "higher_is_better", targetMin: nil, targetMax: nil, minimumSampleSize: 2)]
  }
  func resolveDevelopmentImportPlayer(organizationId: UUID, jobId: UUID, sourceKey: String, playerId: UUID) async throws -> SDDevelopmentImportJob {
    try failIfNeeded()
    resolutionSourceKeys.append(sourceKey)
    if resolutionDelay > 0 { try await Task.sleep(nanoseconds: resolutionDelay) }
    resolutions[sourceKey] = playerId
    return job(status: .validating)
  }
  func listDevelopmentImportRowErrors(organizationId: UUID, jobId: UUID) async throws -> [SDDevelopmentImportRowError] { [] }
  func archiveDevelopmentImport(organizationId: UUID, jobId: UUID) async throws -> SDDevelopmentImportJob { try failIfNeeded(); archiveCalls += 1; return job(status: .archived) }
  func archiveDevelopmentImportMapping(organizationId: UUID, mappingProfileId: UUID) async throws -> SDDevelopmentImportMappingProfile {
    try failIfNeeded()
    return mappingProfile()
  }

  func job(status: SDDevelopmentImportStatus, accepted: Int = 0, rejected: Int = 0) -> SDDevelopmentImportJob {
    SDDevelopmentImportJob(id: jobId, organizationId: orgId, playerId: playerId, requestedBy: userId, provider: "generic_csv", fileName: "synthetic.csv", originalFileType: "csv", fileSHA256: String(repeating: "a", count: 64), fileSizeBytes: 100, parserVersion: "generic-csv.v1", mappingVersion: "mapping.v1", status: status, rowCount: max(accepted + rejected, 1), acceptedRows: accepted, rejectedRows: rejected, unmatchedPlayerRows: 0, warningCount: 0, safeErrorCode: nil, safeErrorSummary: nil, createdAt: "2026-07-15T12:00:00Z", completedAt: status.isFinished ? "2026-07-15T12:01:00Z" : nil, archivedAt: status == .archived ? "2026-07-15T12:02:00Z" : nil)
  }
  func inspection() -> SDDevelopmentImportInspection {
    SDDevelopmentImportInspection(
      detectedFileType: "csv",
      detectedDelimiter: "comma",
      headers: ["username", "date", "metric", "value", "unit"],
      normalizedHeaders: ["username", "date", "metric", "value", "unit"],
      rowCount: 1,
      previewRows: [["avery", "2026-07-01", "exit velocity", "148", "km/h"]],
      warnings: [],
      headerFingerprint: String(repeating: "f", count: 64),
      providerAdapterActive: true,
      detection: SDDevelopmentImportDetection(
        providerKey: "rapsodo",
        exportType: "rapsodo_pitching",
        adapterVersion: "rapsodo-pitching.v1",
        confidence: "high",
        matchedRequiredSignatures: ["Player ID:", "Pitch ID"],
        matchedOptionalSignatures: ["Release Height"],
        missingSignatures: [],
        warnings: ["timezone_confirmation_required"],
        automaticMappingSafe: true,
        protectedColumns: ["Device Serial Number", "SO - latitude"],
        unsupportedColumns: ["VB (trajectory)"],
        providerPlayerID: "fictional-player",
        providerPlayerName: "Fictional Avery"
      ),
      suggestedMapping: SDDevelopmentImportMapping(
        shape: .wide,
        timezone: "UTC",
        dateFormat: "RAPSODO",
        columns: SDDevelopmentImportColumnMapping(playerExternalID: "__provider_player_id", observationTimestamp: "Date"),
        wideMetrics: [SDDevelopmentImportWideMetricMapping(column: "Velocity", metricKey: "pitching.velocity", sourceUnit: "mph")],
        longMetricKeys: nil,
        longSourceUnits: nil,
        contextColumns: nil,
        playerResolutions: nil,
        adapterVersion: "rapsodo-pitching.v1",
        detectedExportType: "rapsodo_pitching",
        unitSystem: nil
      )
    )
  }
  func preview() -> SDDevelopmentImportPreviewResponse {
    SDDevelopmentImportPreviewResponse(notice: "Preview only — no player development data has been imported.", status: "ready", summary: SDDevelopmentImportValidationSummary(totalRows: 1, generatedObservations: 1, acceptedRows: 1, rejectedRows: 0, unmatchedPlayerRows: 0, ambiguousPlayerRows: 0, warningCount: 0, duplicateRows: 0), rows: [SDDevelopmentImportPreviewRow(sourceRowNumber: 2, playerSourceKey: "username:avery", playerMatchState: "matched", playerId: playerId, playerLabel: "Fictional Avery", metricKey: "hitting.max_exit_velocity", metricDisplayName: "Maximum Exit Velocity", originalValue: "148", originalUnit: "km/h", normalizedValue: 91.96, canonicalUnit: "mph", observedAt: "2026-07-01T12:00:00Z", acceptanceState: "accepted", warnings: [], errors: [])], detectedFileType: "csv", detectedDelimiter: "comma", headers: inspection().headers)
  }
  func mappingProfile(headerFingerprint: String = String(repeating: "f", count: 64)) -> SDDevelopmentImportMappingProfile {
    SDDevelopmentImportMappingProfile(id: UUID(), organizationId: orgId, provider: "generic_csv", mappingName: "Generic Long", headerFingerprint: headerFingerprint, parserVersion: "generic-csv.v1", mappingVersion: "mapping.v1", fileShape: .long, mappingConfig: SDDevelopmentImportMapping(shape: .long, timezone: "UTC", dateFormat: "ISO", columns: SDDevelopmentImportColumnMapping(playerUsername: "username", observationDate: "date", metric: "metric", value: "value", unit: "unit"), wideMetrics: nil, longMetricKeys: nil, longSourceUnits: nil, contextColumns: nil, playerResolutions: nil), isActive: true, createdAt: "2026-07-15T12:00:00Z")
  }
  private func failIfNeeded() throws {
    if let error = nextError { nextError = nil; throw error }
  }
}

private enum ImportTestError: LocalizedError {
  case readable
  var errorDescription: String? { "Synthetic import failure." }
}

private let createJSON = #"{"job":{"id":"77777777-7777-4777-8777-777777777777","org_id":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","player_id":"44444444-4444-4444-8444-444444444444","requested_by":"11111111-1111-4111-8111-111111111111","provider":"generic_csv","file_name":"synthetic.csv","original_file_type":"csv","file_sha256":null,"file_size_bytes":null,"parser_version":"generic-csv.v1","mapping_version":null,"status":"pending","row_count":0,"accepted_rows":0,"rejected_rows":0,"unmatched_player_rows":0,"warning_count":0,"safe_error_code":null,"safe_error_summary":null,"created_at":"2026-07-15T12:00:00Z","completed_at":null,"archived_at":null},"upload":{"bucket":"player-development-imports","path":"a/b/c.csv","max_file_bytes":10485760,"upsert":false}}"#
private let inspectJSON = #"{"job":{"id":"77777777-7777-4777-8777-777777777777","org_id":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","player_id":"44444444-4444-4444-8444-444444444444","requested_by":"11111111-1111-4111-8111-111111111111","provider":"generic_csv","file_name":"synthetic.csv","original_file_type":"csv","file_sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","file_size_bytes":100,"parser_version":"generic-csv.v1","mapping_version":null,"status":"mapping_required","row_count":1,"accepted_rows":0,"rejected_rows":0,"unmatched_player_rows":0,"warning_count":0,"safe_error_code":null,"safe_error_summary":null,"created_at":"2026-07-15T12:00:00Z","completed_at":null,"archived_at":null},"inspection":{"detected_file_type":"csv","detected_delimiter":"comma","headers":["player","date","metric","value","unit"],"normalized_headers":["player","date","metric","value","unit"],"row_count":1,"preview_rows":[["A","2026-01-01","hitting.max_exit_velocity","100","km/h"]],"warnings":[],"header_fingerprint":"ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff","provider_adapter_active":true}}"#
private let previewJSON = #"{"notice":"Preview only — no player development data has been imported.","status":"ready","summary":{"totalRows":1,"generatedObservations":1,"acceptedRows":1,"rejectedRows":0,"unmatchedPlayerRows":0,"ambiguousPlayerRows":0,"warningCount":0,"duplicateRows":0},"rows":[{"sourceRowNumber":2,"playerSourceKey":"name:fictional avery","playerMatchState":"matched","playerId":"44444444-4444-4444-8444-444444444444","playerLabel":"Fictional Avery","metricKey":"hitting.max_exit_velocity","metricDisplayName":"Maximum Exit Velocity","originalValue":"100","originalUnit":"km/h","normalizedValue":62.137,"canonicalUnit":"mph","observedAt":"2026-01-01T12:00:00Z","acceptanceState":"accepted","warnings":[],"errors":[]}],"detected_file_type":"csv","detected_delimiter":"comma","headers":["player","date","metric","value","unit"]}"#
