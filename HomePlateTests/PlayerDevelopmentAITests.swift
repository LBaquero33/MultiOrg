import Foundation
import Testing
@testable import HomePlate

@Suite("Player Development AI Phase 11A")
struct PlayerDevelopmentAITests {
  private let orgId = UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")!
  private let otherOrgId = UUID(uuidString: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb")!
  private let userId = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
  private let otherUserId = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!
  private let playerId = UUID(uuidString: "44444444-4444-4444-8444-444444444444")!

  @Test("Exact report, evidence, trend, and alert contracts decode")
  func exactContractsDecode() throws {
    let generated = try fixture()
    #expect(generated.report.organizationId == orgId)
    #expect(generated.report.playerId == playerId)
    #expect(generated.report.status == .draft)
    #expect(generated.report.qualityStatus == .sufficient)
    #expect(generated.report.evidenceFingerprint?.count == 64)
    #expect(generated.evidencePack.evidence.count == 1)
    #expect(generated.evidencePack.trends.first?.canonicalMetricKey == "hitting.max_exit_velocity")
    let alerts = try JSONDecoder().decode(SDDevelopmentAlertsResponse.self, from: Data(alertJSON.utf8))
    #expect(alerts.alerts.first?.severity == .attention)
    #expect(alerts.alerts.first?.status == .active)
  }

  @Test("Unknown report, quality, severity, and alert statuses fail safely")
  func unknownStatuses() throws {
    #expect(try JSONDecoder().decode(SDDevelopmentReportStatus.self, from: Data(#""future""#.utf8)) == .unknown)
    #expect(try JSONDecoder().decode(SDDevelopmentQualityStatus.self, from: Data(#""future""#.utf8)) == .unknown)
    #expect(try JSONDecoder().decode(SDDevelopmentAlertStatus.self, from: Data(#""future""#.utf8)) == .unknown)
    #expect(try JSONDecoder().decode(SDDevelopmentAlertSeverity.self, from: Data(#""future""#.utf8)) == .unknown)
  }

  @Test("Evidence rendering distinguishes empty, missing-data, and evidence states")
  func evidenceRenderingState() throws {
    #expect(SDDevelopmentEvidenceRenderingState.resolve(pack: nil) == .empty)
    let pack = try fixture().evidencePack
    #expect(SDDevelopmentEvidenceRenderingState.resolve(pack: pack) == .evidence(count: 1))
    let empty = try JSONDecoder().decode(
      SDDevelopmentEvidencePackResponse.self,
      from: Data(emptyPackJSON.utf8)
    ).evidencePack
    #expect(SDDevelopmentEvidenceRenderingState.resolve(pack: empty) == .missingData(["No testing entries were available."]))
  }

  @Test("Generation request sends no actor, membership, provider secret, or hidden reasoning")
  func generationRequestAuthority() throws {
    let request = SDDevelopmentGenerateRequest(
      organizationId: orgId,
      playerId: playerId,
      reportType: .playerDevelopmentSummary,
      intendedAudience: "coach",
      windowStart: "2026-04-01",
      windowEnd: "2026-07-15",
      evidenceCutoff: "2026-07-15T12:00:00.000Z",
      idempotencyKey: UUID(uuidString: "88888888-8888-4888-8888-888888888888")!
    )
    let object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])
    #expect(object["action"] as? String == "generate_report")
    #expect((object["org_id"] as? String)?.lowercased() == orgId.uuidString.lowercased())
    #expect((object["player_id"] as? String)?.lowercased() == playerId.uuidString.lowercased())
    #expect(object["report_type"] as? String == "player_development_summary")
    #expect(object["intended_audience"] as? String == "coach")
    #expect(object["window_start"] as? String == "2026-04-01")
    #expect(object["window_end"] as? String == "2026-07-15")
    #expect(object["evidence_cutoff"] as? String == "2026-07-15T12:00:00.000Z")
    #expect((object["idempotency_key"] as? String)?.lowercased() == "88888888-8888-4888-8888-888888888888")
    #expect(object["actor_id"] == nil)
    #expect(object["membership"] == nil)
    #expect(object["provider_secret"] == nil)
    #expect(object["chain_of_thought"] == nil)
  }

  @Test("Owner, admin, and coach presentation is visible; parent/player and inactive staff are hidden")
  func authorizationPresentation() {
    for role in ["owner", "admin", "coach"] {
      #expect(SDDevelopmentPresentationAuthorization.isVisible(membership: membership(role: role)))
    }
    for role in ["parent", "player"] {
      #expect(!SDDevelopmentPresentationAuthorization.isVisible(membership: membership(role: role)))
    }
    #expect(!SDDevelopmentPresentationAuthorization.isVisible(membership: membership(role: "coach", status: "disabled")))
    #expect(!SDDevelopmentPresentationAuthorization.isVisible(membership: nil))
    #expect(SDDevelopmentPresentationAuthorization.isVisible(
      membership: membership(role: "coach"),
      selectedOrganizationId: orgId,
      resourceOrganizationId: orgId
    ))
    #expect(!SDDevelopmentPresentationAuthorization.isVisible(
      membership: membership(role: "coach"),
      selectedOrganizationId: otherOrgId,
      resourceOrganizationId: orgId
    ))
  }

  @Test("Workspace navigation and roster-attention navigation retain typed destinations")
  func navigationDestinations() {
    #expect(SDDevelopmentNavigationDestination.playerWorkspace(playerId) == .playerWorkspace(playerId))
    #expect(SDDevelopmentNavigationDestination.rosterAttention == .rosterAttention)
  }

  @Test("Workspace loads evidence, report history, alerts, and empty-report state")
  @MainActor
  func workspaceLoad() async throws {
    let service = try MockDevelopmentAIClient(fixture: fixture())
    let model = PlayerDevelopmentAIWorkspaceModel()
    await model.load(client: service, organizationId: orgId, userId: userId, playerId: playerId, window: .trailingDays(90))
    #expect(model.phase == .loaded)
    #expect(model.evidencePack?.evidence.count == 1)
    #expect(model.latestReport?.status == .draft)
    #expect(model.alerts.count == 1)
    service.reports = []
    await model.load(client: service, organizationId: orgId, userId: userId, playerId: playerId, window: .trailingDays(90))
    #expect(model.latestReport == nil)
  }

  @Test("Duplicate generation taps are prevented and success clears the completed operation key")
  @MainActor
  func duplicateGenerationPrevention() async throws {
    let service = try MockDevelopmentAIClient(fixture: fixture())
    service.generationDelay = 80_000_000
    let model = PlayerDevelopmentAIWorkspaceModel()
    await model.load(client: service, organizationId: orgId, userId: userId, playerId: playerId, window: .trailingDays(90))
    let first = Task { @MainActor in
      await model.generate(client: service, organizationId: orgId, userId: userId, playerId: playerId, window: .trailingDays(90))
    }
    try await Task.sleep(nanoseconds: 10_000_000)
    #expect(model.isGenerating)
    let duplicate = await model.generate(client: service, organizationId: orgId, userId: userId, playerId: playerId, window: .trailingDays(90))
    #expect(!duplicate)
    #expect(await first.value)
    #expect(!model.isGenerating)
    #expect(service.generationKeys.count == 1)
    let newOperation = model.generationOperation(organizationId: orgId, playerId: playerId, window: .trailingDays(90))
    #expect(newOperation.key != service.generationKeys[0])
  }

  @Test("Empty evidence response decodes and remains an honest unavailable draft")
  func emptyEvidenceGenerationDecodes() throws {
    let generated = try emptyGenerationFixture()
    #expect(generated.report.status == .draft)
    #expect(generated.report.qualityStatus == .unavailable)
    #expect(generated.report.structuredContent.overview.contains("not enough"))
    #expect(generated.evidencePack.evidence.isEmpty)
    #expect(generated.evidencePack.trends.isEmpty)
  }

  @Test("Generation failure is visible and retry reuses the operation key")
  @MainActor
  func generationFailureAndRetry() async throws {
    let service = try MockDevelopmentAIClient(fixture: fixture())
    let model = PlayerDevelopmentAIWorkspaceModel()
    let window = SDDevelopmentWindow(start: "2026-04-01", end: "2026-07-15")
    await model.load(client: service, organizationId: orgId, userId: userId, playerId: playerId, window: window)
    service.nextGenerationError = TestError.readable
    let failed = await model.generate(client: service, organizationId: orgId, userId: userId, playerId: playerId, window: window)
    #expect(!failed)
    #expect(model.errorMessage == "Development data is temporarily unavailable.")
    #expect(model.generationRetryAvailable)
    #expect(!model.isGenerating)
    let retried = await model.generate(client: service, organizationId: orgId, userId: userId, playerId: playerId, window: window)
    #expect(retried)
    #expect(service.generationKeys.count == 2)
    #expect(service.generationKeys[0] == service.generationKeys[1])
    #expect(!model.generationRetryAvailable)
    #expect(model.latestReport != nil)
    #expect(model.reports.count == 1)
  }

  @Test("Backend HTTP failures retain their safe readable messages")
  func backendHTTPFailuresAreReadable() throws {
    for status in [400, 401, 403, 409, 500] {
      let data = Data(
        #"{"error":"development_ai_failed","message":"Player Development AI could not complete the request."}"#.utf8
      )
      let error = SDEdgeFunctionHTTPError.decode(statusCode: status, data: data)
      #expect(error.statusCode == status)
      #expect(error.message == "Player Development AI could not complete the request.")
    }
  }

  @Test("Decorative header overlay cannot intercept Generate Summary taps")
  func headerOverlayHitTesting() throws {
    let projectRoot = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    let source = try String(
      contentsOf: projectRoot.appendingPathComponent("HomePlate/Core/DHDUIComponents.swift"),
      encoding: .utf8
    )
    #expect(source.contains("DHDDiamondPattern(color: DHDTheme.identityText.opacity(0.06))"))
    #expect(source.contains(".allowsHitTesting(false)"))
  }

  @Test("Report detail always exposes an adaptive exit and nonblocking review editor border")
  func reportDetailInteractionWiring() throws {
    let projectRoot = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    let source = try String(
      contentsOf: projectRoot.appendingPathComponent("HomePlate/Features/Coach/PlayerDevelopmentAIView.swift"),
      encoding: .utf8
    )
    let formFieldSource = try String(
      contentsOf: projectRoot.appendingPathComponent("HomePlate/DesignSystem/Components/HPFormField.swift"),
      encoding: .utf8
    )
    #expect(source.contains("@Environment(\\.dismiss) private var dismiss"))
    #expect(source.contains(".navigationBarBackButtonHidden(true)"))
    #expect(source.contains(".accessibilityIdentifier(\"development-report-dismiss\")"))
    #expect(source.contains(".keyboardShortcut(.cancelAction)"))
    #expect(source.contains("label: \"Review notes\""))
    #expect(source.contains("kind: .multiline"))
    #expect(formFieldSource.contains(".strokeBorder(borderColor"))
    #expect(formFieldSource.contains(".allowsHitTesting(false)"))
  }

  @Test("Ambiguous generation retry retains key/cutoff while material changes replace both")
  @MainActor
  func generationIdempotencyMaterial() {
    let model = PlayerDevelopmentAIWorkspaceModel()
    let first = model.generationOperation(organizationId: orgId, playerId: playerId, window: SDDevelopmentWindow(start: "2026-04-01", end: "2026-07-15"))
    let retry = model.generationOperation(organizationId: orgId, playerId: playerId, window: SDDevelopmentWindow(start: "2026-04-01", end: "2026-07-15"))
    #expect(first.key == retry.key)
    #expect(first.cutoff == retry.cutoff)
    let changed = model.generationOperation(organizationId: orgId, playerId: playerId, window: SDDevelopmentWindow(start: "2026-05-01", end: "2026-07-15"))
    #expect(changed.key != first.key)
  }

  @Test("Organization switch rejects a stale response")
  @MainActor
  func organizationSwitchRejectsStaleResult() async throws {
    let service = try MockDevelopmentAIClient(fixture: fixture())
    service.delayByOrganization[orgId] = 100_000_000
    service.delayByOrganization[otherOrgId] = 1_000_000
    let model = PlayerDevelopmentAIWorkspaceModel()
    let old = Task { @MainActor in
      await model.load(client: service, organizationId: orgId, userId: userId, playerId: playerId, window: .trailingDays(90))
    }
    try await Task.sleep(nanoseconds: 5_000_000)
    await model.load(client: service, organizationId: otherOrgId, userId: userId, playerId: playerId, window: .trailingDays(90))
    await old.value
    #expect(model.requestToken?.organizationId == otherOrgId)
    #expect(model.evidencePack?.organizationId == otherOrgId)
  }

  @Test("User switch rejects a stale response")
  @MainActor
  func userSwitchRejectsStaleResult() async throws {
    let service = try MockDevelopmentAIClient(fixture: fixture())
    service.defaultDelay = 30_000_000
    let model = PlayerDevelopmentAIWorkspaceModel()
    let old = Task { @MainActor in
      await model.load(client: service, organizationId: orgId, userId: userId, playerId: playerId, window: .trailingDays(90))
    }
    try await Task.sleep(nanoseconds: 5_000_000)
    service.defaultDelay = 0
    await model.load(client: service, organizationId: orgId, userId: otherUserId, playerId: playerId, window: .trailingDays(90))
    await old.value
    #expect(model.requestToken?.userId == otherUserId)
    #expect(model.acceptsResult(organizationId: orgId, userId: otherUserId))
  }

  @Test("Error state is readable and retry recovers")
  @MainActor
  func errorAndRetry() async throws {
    let service = try MockDevelopmentAIClient(fixture: fixture())
    service.nextBuildError = TestError.readable
    let model = PlayerDevelopmentAIWorkspaceModel()
    await model.load(client: service, organizationId: orgId, userId: userId, playerId: playerId, window: .trailingDays(90))
    #expect(model.phase == .failed("Development data is temporarily unavailable."))
    await model.load(client: service, organizationId: orgId, userId: userId, playerId: playerId, window: .trailingDays(90))
    #expect(model.phase == .loaded)
  }

  @Test("Report approve, reject, and archive actions remain explicit")
  @MainActor
  func reportReviewActions() async throws {
    let service = try MockDevelopmentAIClient(fixture: fixture())
    for action in [SDDevelopmentReviewAction.approve, .reject, .archive] {
      _ = try await service.reviewDevelopmentReport(organizationId: orgId, reportId: service.reports[0].id, action: action, notes: "Reviewed", coachEdits: [:])
    }
    #expect(service.reportActions == [.approve, .reject, .archive])
  }

  @Test("Alert acknowledge, dismiss, and resolve actions remain explicit")
  @MainActor
  func alertReviewActions() async throws {
    let service = try MockDevelopmentAIClient(fixture: fixture())
    let alertId = service.alerts[0].id
    for action in [SDDevelopmentAlertReviewAction.acknowledge, .dismiss, .resolve] {
      _ = try await service.reviewDevelopmentAlert(organizationId: orgId, alertId: alertId, action: action, notes: nil)
    }
    #expect(service.alertActions == [.acknowledge, .dismiss, .resolve])
  }

  @Test("Request token requires both current organization and current user")
  func tokenScope() {
    let token = SDDevelopmentRequestToken(organizationId: orgId, userId: userId, nonce: UUID())
    #expect(token.accepts(organizationId: orgId, userId: userId))
    #expect(!token.accepts(organizationId: otherOrgId, userId: userId))
    #expect(!token.accepts(organizationId: orgId, userId: otherUserId))
  }

  private func membership(role: String, status: String = "active") -> SDOrgMembership {
    SDOrgMembership(org_id: orgId, user_id: userId, role: role, status: status, created_at: nil, created_by: nil)
  }

  private func fixture() throws -> SDDevelopmentGenerateResponse {
    try JSONDecoder().decode(SDDevelopmentGenerateResponse.self, from: Data(generateJSON.utf8))
  }

  private func emptyGenerationFixture() throws -> SDDevelopmentGenerateResponse {
    var object = try #require(JSONSerialization.jsonObject(with: Data(generateJSON.utf8)) as? [String: Any])
    var report = try #require(object["report"] as? [String: Any])
    let emptyPackEnvelope = try #require(
      JSONSerialization.jsonObject(with: Data(emptyPackJSON.utf8)) as? [String: Any]
    )
    report["quality_status"] = "unavailable"
    report["confidence"] = 0
    report["data_freshness"] = "unavailable"
    report["structured_content"] = [
      "overview": "There is not enough recorded development evidence to produce a substantive summary.",
      "positive_trends": [],
      "development_priorities": [],
      "consistency_and_attendance": "Consistency and attendance could not be evaluated from authoritative records.",
      "data_gaps": ["No testing entries were available."],
      "coach_review_questions": [],
      "evidence_summary": [],
    ]
    object["report"] = report
    object["evidence_pack"] = emptyPackEnvelope["evidence_pack"]
    return try JSONDecoder().decode(
      SDDevelopmentGenerateResponse.self,
      from: JSONSerialization.data(withJSONObject: object)
    )
  }

  private var generateJSON: String {
    """
    {
      "report": {
        "id":"66666666-6666-4666-8666-666666666666",
        "org_id":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
        "player_id":"44444444-4444-4444-8444-444444444444",
        "team_id":null,
        "report_type":"player_development_summary",
        "requested_by":"11111111-1111-4111-8111-111111111111",
        "intended_audience":"coach",
        "reporting_window_start":"2026-04-01",
        "reporting_window_end":"2026-07-15",
        "status":"draft",
        "quality_status":"sufficient",
        "structured_content": {
          "overview":"Two comparable exit-velocity observations were reviewed.",
          "positive_trends":[{"title":"Maximum Exit Velocity moved in its preferred direction","explanation":"Changed from 80 to 85 mph.","evidence_keys":["testing:t1:hitting.max_exit_velocity","testing:t2:hitting.max_exit_velocity"]}],
          "development_priorities":[],
          "consistency_and_attendance":"One daily log was available; attendance was not evaluated.",
          "data_gaps":["No authoritative attendance table is available."],
          "coach_review_questions":["Does the recorded context support this trend?"],
          "evidence_summary":[{"label":"Maximum Exit Velocity","explanation":"Observed 85 mph.","evidence_key":"testing:t2:hitting.max_exit_velocity"}]
        },
        "rendered_text":"Two comparable observations were reviewed.",
        "generation_mode":"deterministic",
        "provider":"deterministic_template",
        "model_identifier":null,
        "generator_version":"deterministic-template.v1",
        "prompt_version":"none.deterministic.v1",
        "input_cutoff":"2026-07-15T12:00:00.000Z",
        "generated_at":"2026-07-15T12:00:00.000Z",
        "reviewed_at":null,"reviewed_by":null,"approved_at":null,"rejected_at":null,"archived_at":null,
        "coach_edits":{},"review_notes":null,"confidence":0.85,"data_freshness":"current",
        "missing_data_warnings":["No authoritative attendance table is available."],
        "evidence_fingerprint":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        "created_at":"2026-07-15T12:00:00.000Z","updated_at":"2026-07-15T12:00:00.000Z"
      },
      "reused":false,
      "evidence_pack": {
        "schema_version":"player_development_evidence_pack.v1",
        "organization_id":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
        "player_id":"44444444-4444-4444-8444-444444444444",
        "player_name":"Test Player","report_type":"player_development_summary",
        "window_start":"2026-04-01","window_end":"2026-07-15","evidence_cutoff":"2026-07-15T12:00:00.000Z",
        "quality_status":"sufficient","data_freshness":"current",
        "coverage":{"testing_entries":2,"metric_observations":0,"daily_logs":1,"program_assignments":0,"bp_sessions":0},
        "trends":[{"canonical_metric_key":"hitting.max_exit_velocity","display_name":"Maximum Exit Velocity","unit":"mph","latest_value":85,"prior_value":80,"absolute_change":5,"percentage_change":6.25,"rolling_average":82.5,"recent_window_average":85,"prior_window_average":80,"best_value":85,"worst_value":80,"sample_count":2,"observation_frequency_days":60,"freshness":"current","quality":"sufficient","interpretation":"improvement","rule_id":"trend.higher_is_better.v1","evidence_keys":["testing:t1:hitting.max_exit_velocity","testing:t2:hitting.max_exit_velocity"]}],
        "evidence":[{"evidence_key":"testing:t2:hitting.max_exit_velocity","section_key":"metrics","source_entity_type":"sd_testing_entries","source_record_id":"t2","canonical_metric_key":"hitting.max_exit_velocity","raw_observed_value":"85","normalized_numeric_value":85,"unit":"mph","observation_date":"2026-07-01","comparison_value":null,"comparison_period":null,"direction":null,"sample_size":1,"freshness":"current","quality":"sufficient","deterministic_rule_id":"source_adapter.v1","display_label":"Maximum Exit Velocity","explanation":"Observed 85 mph on 2026-07-01.","source_metadata":{"source_type":"sd_testing_entries"},"evidence_snapshot":{"value":85,"unit":"mph"}}],
        "missing_data_warnings":["No authoritative attendance table is available."],"stale_data_warnings":[],"unit_conflicts":[],"low_sample_warnings":[]
      }
    }
    """
  }

  private var alertJSON: String {
    """
    {"alerts":[{"id":"77777777-7777-4777-8777-777777777777","org_id":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","player_id":"44444444-4444-4444-8444-444444444444","report_id":null,"alert_type":"no_recent_testing","severity":"attention","status":"active","first_detected_at":"2026-07-15T12:00:00Z","last_detected_at":"2026-07-15T12:00:00Z","evidence_window_start":"2026-04-01","evidence_window_end":"2026-07-15","rule_version":"development-alerts.v1","explanation":"No testing entry was recorded.","recommended_human_action":"Confirm whether testing is due.","data_freshness":"unavailable","evidence_quality":"unavailable","deduplication_key":"no_recent_testing:2026-07","player_name":"Test Player"}]}
    """
  }

  private var emptyPackJSON: String {
    """
    {"evidence_pack":{"schema_version":"player_development_evidence_pack.v1","organization_id":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","player_id":"44444444-4444-4444-8444-444444444444","player_name":"Test Player","report_type":"player_development_summary","window_start":"2026-04-01","window_end":"2026-07-15","evidence_cutoff":"2026-07-15T12:00:00Z","quality_status":"unavailable","data_freshness":"unavailable","coverage":{"testing_entries":0,"metric_observations":0,"daily_logs":0,"program_assignments":0,"bp_sessions":0},"trends":[],"evidence":[],"missing_data_warnings":["No testing entries were available."],"stale_data_warnings":[],"unit_conflicts":[],"low_sample_warnings":[]}}
    """
  }
}

private enum TestError: LocalizedError {
  case readable
  var errorDescription: String? { "Development data is temporarily unavailable." }
}

@MainActor
private final class MockDevelopmentAIClient: PlayerDevelopmentAIClient {
  var pack: SDDevelopmentEvidencePack
  var reports: [SDDevelopmentReport]
  var alerts: [SDDevelopmentAlert]
  var generationKeys: [UUID] = []
  var reportActions: [SDDevelopmentReviewAction] = []
  var alertActions: [SDDevelopmentAlertReviewAction] = []
  var generationDelay: UInt64 = 0
  var defaultDelay: UInt64 = 0
  var delayByOrganization: [UUID: UInt64] = [:]
  var nextBuildError: Error?
  var nextGenerationError: Error?

  init(fixture: SDDevelopmentGenerateResponse) throws {
    pack = fixture.evidencePack
    reports = [fixture.report]
    alerts = try JSONDecoder().decode(
      SDDevelopmentAlertsResponse.self,
      from: Data("""
      {"alerts":[{"id":"77777777-7777-4777-8777-777777777777","org_id":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","player_id":"44444444-4444-4444-8444-444444444444","report_id":null,"alert_type":"no_recent_testing","severity":"attention","status":"active","first_detected_at":"2026-07-15T12:00:00Z","last_detected_at":"2026-07-15T12:00:00Z","evidence_window_start":"2026-04-01","evidence_window_end":"2026-07-15","rule_version":"development-alerts.v1","explanation":"No testing entry was recorded.","recommended_human_action":"Confirm whether testing is due.","data_freshness":"unavailable","evidence_quality":"unavailable","deduplication_key":"no_recent_testing:2026-07","player_name":"Test Player"}]}
      """.utf8)
    ).alerts
  }

  func buildDevelopmentEvidencePack(organizationId: UUID, playerId: UUID, reportType: SDDevelopmentReportType, window: SDDevelopmentWindow, evidenceCutoff: Date) async throws -> SDDevelopmentEvidencePack {
    if let error = nextBuildError { nextBuildError = nil; throw error }
    let delay = delayByOrganization[organizationId] ?? defaultDelay
    if delay > 0 { try await Task.sleep(nanoseconds: delay) }
    if organizationId == pack.organizationId { return pack }
    return try remapPackOrganization(organizationId)
  }

  func generateDevelopmentReport(organizationId: UUID, playerId: UUID, reportType: SDDevelopmentReportType, intendedAudience: String, window: SDDevelopmentWindow, evidenceCutoff: Date, idempotencyKey: UUID) async throws -> SDDevelopmentGenerateResponse {
    generationKeys.append(idempotencyKey)
    if generationDelay > 0 { try await Task.sleep(nanoseconds: generationDelay) }
    if let error = nextGenerationError { nextGenerationError = nil; throw error }
    return SDDevelopmentGenerateResponse(report: reports[0], reused: false, evidencePack: pack, playerAlerts: nil)
  }

  func listDevelopmentReports(organizationId: UUID, playerId: UUID) async throws -> [SDDevelopmentReport] {
    let delay = delayByOrganization[organizationId] ?? defaultDelay
    if delay > 0 { try await Task.sleep(nanoseconds: delay) }
    return reports
  }

  func developmentReportDetail(organizationId: UUID, reportId: UUID) async throws -> SDDevelopmentReportDetail {
    SDDevelopmentReportDetail(report: reports[0], evidence: pack.evidence, reviewHistory: [])
  }

  func reviewDevelopmentReport(organizationId: UUID, reportId: UUID, action: SDDevelopmentReviewAction, notes: String?, coachEdits: [String: SDJSONValue]) async throws -> SDDevelopmentReport {
    reportActions.append(action)
    return reports[0]
  }

  func listDevelopmentAlerts(organizationId: UUID, playerId: UUID) async throws -> [SDDevelopmentAlert] {
    let delay = delayByOrganization[organizationId] ?? defaultDelay
    if delay > 0 { try await Task.sleep(nanoseconds: delay) }
    return alerts
  }

  func developmentAlertDetail(organizationId: UUID, alertId: UUID) async throws -> SDDevelopmentAlertDetail {
    SDDevelopmentAlertDetail(alert: alerts[0], evidence: [], reviewHistory: [])
  }

  func runDevelopmentAlertDetection(organizationId: UUID, playerId: UUID, window: SDDevelopmentWindow, evidenceCutoff: Date) async throws -> SDDevelopmentAlertDetectionResponse {
    SDDevelopmentAlertDetectionResponse(alerts: alerts, detectedCount: alerts.count)
  }

  func reviewDevelopmentAlert(organizationId: UUID, alertId: UUID, action: SDDevelopmentAlertReviewAction, notes: String?) async throws -> SDDevelopmentAlert {
    alertActions.append(action)
    return alerts[0]
  }

  func generatePlayerDevelopmentReport(organizationId: UUID, playerId: UUID, window: SDDevelopmentWindow, evidenceCutoff: Date, idempotencyKey: UUID) async throws -> SDDevelopmentGenerateResponse {
    SDDevelopmentGenerateResponse(report: reports[0], reused: false, evidencePack: pack, playerAlerts: alerts)
  }

  func playerDevelopmentReportDetail(organizationId: UUID, reportId: UUID) async throws -> SDDevelopmentReportDetail {
    SDDevelopmentReportDetail(report: reports[0], evidence: pack.evidence, reviewHistory: [])
  }

  func archivePlayerDevelopmentReport(organizationId: UUID, reportId: UUID) async throws -> SDDevelopmentReport { reports[0] }

  func playerDevelopmentAlertDetail(organizationId: UUID, alertId: UUID) async throws -> SDDevelopmentAlertDetail {
    SDDevelopmentAlertDetail(alert: alerts[0], evidence: [], reviewHistory: [])
  }

  func dismissPlayerDevelopmentAlert(organizationId: UUID, alertId: UUID) async throws -> SDDevelopmentAlert { alerts[0] }

  func developmentRosterAttention(organizationId: UUID) async throws -> SDDevelopmentRosterAttentionResponse {
    SDDevelopmentRosterAttentionResponse(alerts: alerts, reportsAwaitingReview: reports)
  }

  private func remapPackOrganization(_ organizationId: UUID) throws -> SDDevelopmentEvidencePack {
    let data = try JSONEncoder().encode(pack)
    var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    object["organization_id"] = organizationId.uuidString.lowercased()
    return try JSONDecoder().decode(SDDevelopmentEvidencePack.self, from: JSONSerialization.data(withJSONObject: object))
  }
}
