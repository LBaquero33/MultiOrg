import Foundation
import Testing
@testable import HomePlate

@Suite("Player Development Coach Copilot Phase 11C-11E")
struct PlayerDevelopmentCopilotTests {
  private let orgId = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
  private let otherOrgId = UUID(uuidString: "99999999-9999-4999-8999-999999999999")!
  private let userId = UUID(uuidString: "33333333-3333-4333-8333-333333333333")!
  private let playerId = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!
  private let conversationId = UUID(uuidString: "44444444-4444-4444-8444-444444444444")!

  @Test("Conversation list, quality, provider mode, and pagination decode")
  func conversationListDecodes() throws {
    let response = try JSONDecoder().decode(SDCopilotConversationsResponse.self, from: Data(conversationsJSON.utf8))
    #expect(response.conversations.count == 1)
    #expect(response.conversations[0].playerId == playerId)
    #expect(response.conversations[0].generationMode == .deterministic)
    #expect(response.conversations[0].qualityStatus == .sufficient)
    #expect(response.pagination.hasMore == false)
  }

  @Test("Create conversation response decodes the exact conversation envelope")
  func createConversationEnvelopeDecodes() throws {
    let list = try #require(JSONSerialization.jsonObject(with: Data(conversationsJSON.utf8)) as? [String: Any])
    let conversations = try #require(list["conversations"] as? [[String: Any]])
    let data = try JSONSerialization.data(withJSONObject: ["conversation": try #require(conversations.first)])
    let response = try JSONDecoder().decode(SDCopilotConversationResponse.self, from: data)
    #expect(response.conversation.id == conversationId)
    #expect(response.conversation.organizationId == orgId)
    #expect(response.conversation.audience == .coach)
  }

  @Test("Create conversation request uses the exact public contract")
  func createConversationRequestContract() throws {
    let key = UUID(uuidString: "66666666-6666-4666-8666-666666666666")!
    let request = SDCopilotRequest(
      action: "create_conversation",
      organizationId: orgId,
      audience: .player,
      playerId: playerId,
      title: "Controlled development",
      reportingWindowDays: 90,
      idempotencyKey: key
    )
    let object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])
    #expect(Set(object.keys) == Set([
      "action", "org_id", "audience", "player_id", "title",
      "reporting_window_days", "idempotency_key",
    ]))
    #expect(object["action"] as? String == "create_conversation")
    #expect(object["audience"] as? String == "player")
    #expect(object["reporting_window_days"] as? Int == 90)
    #expect(object["actor_id"] == nil)
  }

  @Test("Structured message sections and immutable citation decode")
  func messageAndCitationDecode() throws {
    let detail = try fixtureDetail()
    let answer = try #require(detail.messages.last?.structuredAnswer)
    #expect(answer.facts.count == 1)
    #expect(answer.calculations.first?.ruleId == "trend.higher_is_better.v1")
    #expect(answer.interpretations.first?.confidence == 0.85)
    #expect(answer.recommendations.first?.requiresHumanApproval == true)
    #expect(answer.proposedActions.first?.requiresApproval == true)
    let citation = try #require(detail.messages.last?.citations?.first)
    #expect(citation.normalizedValue == 91)
    #expect(citation.unit == "mph")
    #expect(citation.sourceProvider == "rapsodo")
    #expect(citation.verificationStatus == "verified")
    #expect(citation.evidenceSnapshot["unit"] == .string("mph"))
  }

  @Test("Unknown generation and quality values fail closed")
  func unknownValues() throws {
    #expect(try JSONDecoder().decode(SDCopilotGenerationMode.self, from: Data(#""future""#.utf8)) == .unknown)
    #expect(try JSONDecoder().decode(SDCopilotQualityStatus.self, from: Data(#""future""#.utf8)) == .unknown)
    #expect(try JSONDecoder().decode(SDCopilotGenerationStatus.self, from: Data(#""future""#.utf8)) == .unknown)
  }

  @Test("Client request contains no actor, system prompt, model, secret, or hidden reasoning")
  func requestAuthority() throws {
    let request = SDCopilotRequest(
      action: "ask",
      organizationId: orgId,
      audience: .coach,
      playerId: playerId,
      conversationId: conversationId,
      question: "What changed?",
      windowStart: "2026-04-18",
      windowEnd: "2026-07-16",
      idempotencyKey: UUID(uuidString: "66666666-6666-4666-8666-666666666666")!
    )
    let object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])
    #expect(object["action"] as? String == "ask")
    #expect(object["question"] as? String == "What changed?")
    #expect(object["audience"] as? String == "coach")
    #expect(object["actor_id"] == nil)
    #expect(object["system_prompt"] == nil)
    #expect(object["model"] == nil)
    #expect(object["api_key"] == nil)
    #expect(object["chain_of_thought"] == nil)
  }

  @Test("Organization, user, and player context token rejects stale responses")
  func contextToken() {
    let token = SDCopilotContextToken(organizationId: orgId, userId: userId, playerId: playerId, audience: .coach)
    #expect(token.accepts(organizationId: orgId, userId: userId, playerId: playerId, audience: .coach))
    #expect(!token.accepts(organizationId: otherOrgId, userId: userId, playerId: playerId, audience: .coach))
    #expect(!token.accepts(organizationId: orgId, userId: UUID(), playerId: playerId, audience: .coach))
    #expect(!token.accepts(organizationId: orgId, userId: userId, playerId: UUID(), audience: .coach))
    #expect(!token.accepts(organizationId: orgId, userId: userId, playerId: playerId, audience: .player))
  }

  @Test("Workspace loads conversations, deterministic questions, drafts, and usage")
  @MainActor
  func workspaceLoad() async throws {
    let client = try MockCopilotClient(detail: fixtureDetail(), conversations: conversationsFixture())
    let model = PlayerDevelopmentCopilotWorkspaceModel()
    await model.load(client: client, organizationId: orgId, userId: userId, playerId: playerId, audience: .coach)
    #expect(model.phase == .loaded)
    #expect(model.conversations.count == 1)
    #expect(model.suggestedQuestions == ["What changed in the last 30 days?"])
    #expect(model.usage?.limits.questionsPerActorHour == 30)
  }

  @Test("Workspace reset clears organization and user scoped state")
  @MainActor
  func workspaceReset() async throws {
    let client = try MockCopilotClient(detail: fixtureDetail(), conversations: conversationsFixture())
    let model = PlayerDevelopmentCopilotWorkspaceModel()
    await model.load(client: client, organizationId: orgId, userId: userId, playerId: playerId, audience: .coach)
    model.reset()
    #expect(model.phase == .idle)
    #expect(model.conversations.isEmpty)
    #expect(model.suggestedQuestions.isEmpty)
    #expect(model.usage == nil)
    #expect(model.presentedConversation == nil)
  }

  @Test("New Conversation loads once and presents only after a concrete result")
  @MainActor
  func newConversationPresentation() async throws {
    let client = try MockCopilotClient(detail: fixtureDetail(), conversations: conversationsFixture())
    client.createDelay = 80_000_000
    let model = PlayerDevelopmentCopilotWorkspaceModel()
    await model.load(client: client, organizationId: orgId, userId: userId, playerId: playerId, audience: .coach)

    let creation = Task { @MainActor in
      await model.createConversation(
        client: client,
        organizationId: orgId,
        userId: userId,
        playerId: playerId,
        audience: .coach,
        title: "Controlled development",
        reportingWindowDays: 90
      )
    }
    try await Task.sleep(nanoseconds: 10_000_000)
    #expect(model.isCreating)
    #expect(model.presentedConversation == nil)
    #expect(client.createCalls.count == 1)
    #expect(!(await model.createConversation(
      client: client,
      organizationId: orgId,
      userId: userId,
      playerId: playerId,
      audience: .coach,
      title: "Duplicate",
      reportingWindowDays: 90
    )))
    #expect(await creation.value)
    #expect(client.createCalls.count == 1)
    #expect(model.presentedConversation?.conversation.id == conversationId)
    #expect(model.presentedConversation?.conversation.audience == .coach)

    model.dismissPresentedConversation()
    #expect(model.presentedConversation == nil)
  }

  @Test("Existing and suggested conversations use the same concrete presentation item")
  @MainActor
  func sharedConversationPresentationItem() async throws {
    let client = try MockCopilotClient(detail: fixtureDetail(), conversations: conversationsFixture())
    let model = PlayerDevelopmentCopilotWorkspaceModel()
    await model.load(client: client, organizationId: orgId, userId: userId, playerId: playerId, audience: .coach)
    let existing = try #require(model.conversations.first)

    #expect(model.presentConversation(
      existing,
      organizationId: orgId,
      userId: userId,
      playerId: playerId,
      audience: .coach
    ))
    #expect(model.presentedConversation?.conversation == existing)
    #expect(model.presentedConversation?.initialQuestion == nil)
    model.dismissPresentedConversation()

    #expect(await model.createConversation(
      client: client,
      organizationId: orgId,
      userId: userId,
      playerId: playerId,
      audience: .coach,
      title: "Controlled development",
      reportingWindowDays: 90,
      initialQuestion: "What changed in the last 30 days?"
    ))
    #expect(model.presentedConversation?.conversation.id == existing.id)
    #expect(model.presentedConversation?.initialQuestion == "What changed in the last 30 days?")
  }

  @Test("Create failure is visible and retries with the same idempotency key")
  @MainActor
  func createConversationRetryIdentity() async throws {
    let client = try MockCopilotClient(detail: fixtureDetail(), conversations: conversationsFixture())
    let model = PlayerDevelopmentCopilotWorkspaceModel()
    await model.load(client: client, organizationId: orgId, userId: userId, playerId: playerId, audience: .coach)
    client.nextCreateError = TestCopilotError.creationFailed

    #expect(!(await model.createConversation(
      client: client,
      organizationId: orgId,
      userId: userId,
      playerId: playerId,
      audience: .coach,
      title: "Controlled development",
      reportingWindowDays: 90
    )))
    #expect(model.errorMessage == "[conversation_create_failed] Conversation creation failed.")
    #expect(model.presentedConversation == nil)
    #expect(await model.createConversation(
      client: client,
      organizationId: orgId,
      userId: userId,
      playerId: playerId,
      audience: .coach,
      title: "Controlled development",
      reportingWindowDays: 90
    ))
    #expect(client.createCalls.count == 2)
    #expect(client.createCalls[0].idempotencyKey == client.createCalls[1].idempotencyKey)
  }

  @Test("Organization or user switching rejects stale creation and clears presentation")
  @MainActor
  func staleConversationCreation() async throws {
    let client = try MockCopilotClient(detail: fixtureDetail(), conversations: conversationsFixture())
    client.createDelay = 80_000_000
    let model = PlayerDevelopmentCopilotWorkspaceModel()
    await model.load(client: client, organizationId: orgId, userId: userId, playerId: playerId, audience: .coach)
    let existing = try #require(model.conversations.first)
    #expect(model.presentConversation(existing, organizationId: orgId, userId: userId, playerId: playerId, audience: .coach))

    let creation = Task { @MainActor in
      await model.createConversation(
        client: client,
        organizationId: orgId,
        userId: userId,
        playerId: playerId,
        audience: .coach,
        title: "Controlled development",
        reportingWindowDays: 90
      )
    }
    try await Task.sleep(nanoseconds: 10_000_000)
    model.reset()
    #expect(!(await creation.value))
    #expect(model.phase == .idle)
    #expect(model.presentedConversation == nil)
  }

  @Test("Concrete conversation routes reject mismatched audience and preserve private player scope")
  @MainActor
  func conversationRouteAudienceScope() async throws {
    let coachClient = try MockCopilotClient(detail: fixtureDetail(), conversations: conversationsFixture())
    let coachModel = PlayerDevelopmentCopilotWorkspaceModel()
    await coachModel.load(client: coachClient, organizationId: orgId, userId: userId, playerId: playerId, audience: .coach)
    let playerConversation = try playerConversationsFixture().conversations[0]
    #expect(!coachModel.presentConversation(
      playerConversation,
      organizationId: orgId,
      userId: userId,
      playerId: playerId,
      audience: .coach
    ))
    #expect(coachModel.presentedConversation == nil)

    let playerClient = try MockCopilotClient(detail: playerDetailFixture(), conversations: playerConversationsFixture())
    let playerModel = PlayerDevelopmentCopilotWorkspaceModel()
    await playerModel.load(client: playerClient, organizationId: orgId, userId: playerId, playerId: playerId, audience: .player)
    #expect(playerModel.presentConversation(
      playerConversation,
      organizationId: orgId,
      userId: playerId,
      playerId: playerId,
      audience: .player
    ))
    #expect(playerModel.presentedConversation?.conversation.audience == .player)
  }

  @Test("Duplicate Send taps are blocked")
  @MainActor
  func duplicateSend() async throws {
    let client = try MockCopilotClient(detail: fixtureDetail(), conversations: conversationsFixture())
    client.askDelay = 80_000_000
    let model = PlayerDevelopmentCopilotConversationModel()
    await model.load(client: client, organizationId: orgId, userId: userId, playerId: playerId, audience: .coach, conversationId: conversationId)
    model.composer = "What changed?"
    let first = Task { @MainActor in
      await model.send(client: client, organizationId: orgId, userId: userId, playerId: playerId, audience: .coach, conversationId: conversationId, window: .trailingDays(90))
    }
    try await Task.sleep(nanoseconds: 10_000_000)
    #expect(model.isSending)
    let duplicate = await model.send(client: client, organizationId: orgId, userId: userId, playerId: playerId, audience: .coach, conversationId: conversationId, window: .trailingDays(90))
    #expect(!duplicate)
    #expect(await first.value)
    #expect(client.askKeys.count == 1)
  }

  @Test("Failed send keeps stable idempotency for Retry")
  @MainActor
  func retryIdentity() async throws {
    let client = try MockCopilotClient(detail: fixtureDetail(), conversations: conversationsFixture())
    let model = PlayerDevelopmentCopilotConversationModel()
    await model.load(client: client, organizationId: orgId, userId: userId, playerId: playerId, audience: .coach, conversationId: conversationId)
    model.composer = "What changed?"
    client.nextAskError = TestCopilotError.providerUnavailable
    let initialSend = await model.send(client: client, organizationId: orgId, userId: userId, playerId: playerId, audience: .coach, conversationId: conversationId, window: .trailingDays(90))
    #expect(!initialSend)
    #expect(model.retryAvailable)
    #expect(await model.send(client: client, organizationId: orgId, userId: userId, playerId: playerId, audience: .coach, conversationId: conversationId, window: .trailingDays(90), retry: true))
    #expect(client.askKeys.count == 2)
    #expect(client.askKeys[0] == client.askKeys[1])
    #expect(client.retryFlags == [false, true])
  }

  @Test("Stable Copilot failure codes have specific safe messages and retry policy")
  func stableFailurePresentations() {
    let expected: [(String, Bool)] = [
      ("unsupported_without_provider", false),
      ("deterministic_intent_unrecognized", false),
      ("evidence_unavailable", false),
      ("structured_output_invalid", true),
      ("invalid_evidence_reference", true),
      ("unsafe_generated_content", true),
      ("persistence_failed", true),
      ("rate_limited", true),
      ("stale_context", false),
    ]
    for (code, retryable) in expected {
      let presentation = SDCopilotFailurePresentation(code: code)
      #expect(presentation.code == code)
      #expect(presentation.isRetryable == retryable)
      #expect(!presentation.message.isEmpty)
      #expect(!presentation.message.localizedCaseInsensitiveContains("database"))
      #expect(!presentation.message.localizedCaseInsensitiveContains("provider response body"))
    }
    let edge = SDEdgeFunctionHTTPError(
      statusCode: 503,
      code: "structured_output_invalid",
      message: "Safe backend message"
    )
    #expect(SDCopilotFailurePresentation(error: edge).code == "structured_output_invalid")
  }

  @Test("Persisted retryable failure restores the original logical operation")
  @MainActor
  func persistedFailureRestoresRetry() async throws {
    let operationKey = "66666666-6666-4666-8666-666666666666"
    let failedJSON = conversationDetailJSON
      .replacingOccurrences(
        of: #""safe_error_code":null,"archived_at":null,"created_at":"2026-07-16T12:00:00Z""#,
        with: #""safe_error_code":null,"idempotency_key":"\#(operationKey)","archived_at":null,"created_at":"2026-07-16T12:00:00Z""#
      )
      .replacingOccurrences(
        of: #""generation_status":"succeeded","safe_error_code":null,"archived_at":null,"created_at":"2026-07-16T12:00:01Z""#,
        with: #""generation_status":"failed","safe_error_code":"structured_output_invalid","idempotency_key":"\#(operationKey)","archived_at":null,"created_at":"2026-07-16T12:00:01Z""#
      )
    let detail = try JSONDecoder().decode(
      SDCopilotConversationDetailResponse.self,
      from: Data(failedJSON.utf8)
    )
    let client = try MockCopilotClient(
      detail: detail,
      conversations: conversationsFixture()
    )
    let model = PlayerDevelopmentCopilotConversationModel()
    await model.load(
      client: client,
      organizationId: orgId,
      userId: userId,
      playerId: playerId,
      audience: .coach,
      conversationId: conversationId
    )
    #expect(model.errorDiagnosticCode == "structured_output_invalid")
    #expect(model.retryAvailable)
    #expect(await model.send(
      client: client,
      organizationId: orgId,
      userId: userId,
      playerId: playerId,
      audience: .coach,
      conversationId: conversationId,
      window: .trailingDays(90),
      retry: true
    ))
    #expect(client.askKeys == [UUID(uuidString: operationKey)!])
    #expect(client.retryFlags == [true])
  }

  @Test("Question composer rejects empty and oversized questions")
  @MainActor
  func composerBounds() async throws {
    let client = try MockCopilotClient(detail: fixtureDetail(), conversations: conversationsFixture())
    let model = PlayerDevelopmentCopilotConversationModel()
    await model.load(client: client, organizationId: orgId, userId: userId, playerId: playerId, audience: .coach, conversationId: conversationId)
    let emptySend = await model.send(client: client, organizationId: orgId, userId: userId, playerId: playerId, audience: .coach, conversationId: conversationId, window: .trailingDays(90))
    #expect(!emptySend)
    model.composer = String(repeating: "x", count: 2_001)
    let oversizedSend = await model.send(client: client, organizationId: orgId, userId: userId, playerId: playerId, audience: .coach, conversationId: conversationId, window: .trailingDays(90))
    #expect(!oversizedSend)
    #expect(client.askKeys.isEmpty)
  }

  @Test("Feedback types and safe titles remain complete")
  func feedbackTypes() {
    #expect(SDCopilotFeedbackType.allCases.count == 8)
    #expect(SDCopilotFeedbackType.wrongEvidence.title == "Wrong evidence")
  }

  @Test("Parent draft keeps generated and edited versions and not-shared lifecycle")
  func parentDraftDecodes() throws {
    let response = try JSONDecoder().decode(SDParentDraftDetailResponse.self, from: Data(parentDraftJSON.utf8))
    #expect(response.draft.status == .reviewed)
    #expect(response.draft.generatedOriginal.currentFocus == "Original focus.")
    #expect(response.draft.editedContent.currentFocus == "Coach-edited focus.")
    #expect(response.draft.approvedAt == nil)
    #expect(response.reviewEvents.last?.eventType == "reviewed")
  }

  @Test("Parent draft actions contain no delivery or recipient fields")
  func parentDraftRequestHasNoDelivery() throws {
    let request = SDCopilotRequest(action: "approve_parent_draft", organizationId: orgId, draftId: UUID())
    let object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])
    #expect(object["delivery"] == nil)
    #expect(object["recipient"] == nil)
    #expect(object["notification"] == nil)
    #expect(object["apns"] == nil)
  }

  @Test("Coach and player presentation audiences remain role separated")
  func audiencePresentation() {
    #expect(SDDevelopmentPresentationAuthorization.isVisible(membership: membership("owner")))
    #expect(SDDevelopmentPresentationAuthorization.isVisible(membership: membership("admin")))
    #expect(SDDevelopmentPresentationAuthorization.isVisible(membership: membership("coach")))
    #expect(!SDDevelopmentPresentationAuthorization.isVisible(membership: membership("parent")))
    #expect(!SDDevelopmentPresentationAuthorization.isVisible(membership: membership("player")))
    #expect(SDDevelopmentPresentationAuthorization.isCopilotVisible(
      membership: membership("coach"), audience: .coach, userId: userId, playerId: playerId
    ))
    #expect(!SDDevelopmentPresentationAuthorization.isCopilotVisible(
      membership: membership("coach"), audience: .player, userId: userId, playerId: playerId
    ))
    #expect(SDDevelopmentPresentationAuthorization.isCopilotVisible(
      membership: membership("player"), audience: .player, userId: playerId, playerId: playerId
    ))
    #expect(!SDDevelopmentPresentationAuthorization.isCopilotVisible(
      membership: membership("parent"), audience: .player, userId: playerId, playerId: playerId
    ))
    #expect(!SDDevelopmentPresentationAuthorization.isCopilotVisible(
      membership: membership("player"), audience: .player, userId: userId, playerId: playerId
    ))
  }

  @Test("Player conversation requests encode player audience and immutable self target")
  func playerRequestAudience() throws {
    let request = SDCopilotRequest(
      action: "create_conversation",
      organizationId: orgId,
      audience: .player,
      playerId: playerId,
      idempotencyKey: UUID()
    )
    let object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])
    #expect(object["audience"] as? String == "player")
    #expect(UUID(uuidString: object["player_id"] as? String ?? "") == playerId)
    #expect(object["created_by"] == nil)
  }

  @Test("Generate My Summary request carries only the selected organization and signed-in player")
  func playerGenerateRequest() throws {
    let request = SDDevelopmentPlayerGenerateRequest(
      organizationId: orgId,
      playerId: playerId,
      windowStart: "2026-04-18",
      windowEnd: "2026-07-16",
      evidenceCutoff: "2026-07-16T12:00:00Z",
      idempotencyKey: UUID(uuidString: "abababab-abab-4bab-8bab-abababababab")!
    )
    let object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])
    #expect(object["action"] as? String == "generate_player_report")
    #expect(UUID(uuidString: object["org_id"] as? String ?? "") == orgId)
    #expect(UUID(uuidString: object["player_id"] as? String ?? "") == playerId)
    #expect(object["audience"] == nil)
    #expect(object["intended_audience"] == nil)
    #expect(object["actor_id"] == nil)
  }

  @Test("Player workspace loads self objective evidence and provider labels")
  @MainActor
  func playerWorkspaceLoads() async throws {
    let client = try MockCopilotClient(
      detail: playerDetailFixture(),
      conversations: playerConversationsFixture()
    )
    let model = PlayerDevelopmentPlayerWorkspaceModel()
    await model.load(
      client: client,
      organizationId: orgId,
      userId: playerId,
      playerId: playerId
    )
    let response = try #require(model.response)
    let evidence = try #require(response.evidencePack.evidence.first)
    #expect(model.phase == .loaded)
    #expect(response.evidencePack.reportType == "player_copilot_self_question")
    #expect(response.suggestedQuestions.contains("What changed in the last 30 days?"))
    #expect(evidence.sourceMetadata["provider"] == .string("rapsodo"))
    #expect(evidence.sourceMetadata["verification_status"] == .string("verified"))
    #expect(evidence.unit == "mph")
    #expect(evidence.observationDate == "2026-07-15T12:00:00Z")
    #expect(model.reports.isEmpty)
    #expect(model.alerts.isEmpty)
    #expect(response.reportsAvailability == "No player-visible summary exists yet.")
    #expect(response.alertsAvailability == "No player-visible objective alert exists right now.")
    #expect(client.workspaceRequests.count == 1)
    #expect(client.workspaceRequests.first?.0 == orgId)
    #expect(client.workspaceRequests.first?.1 == playerId)
  }

  @Test("Player workspace rejects another player before a request")
  @MainActor
  func playerWorkspaceRejectsOtherTarget() async throws {
    let client = try MockCopilotClient(
      detail: playerDetailFixture(),
      conversations: playerConversationsFixture()
    )
    let model = PlayerDevelopmentPlayerWorkspaceModel()
    await model.load(
      client: client,
      organizationId: orgId,
      userId: userId,
      playerId: playerId
    )
    #expect(model.phase == .failed("Player Development is available only for your own profile."))
    #expect(client.workspaceRequests.isEmpty)
  }

  @Test("Player workspace shows only player reports and alerts and Generate My Summary refreshes both")
  @MainActor
  func playerReportsAlertsAndGeneration() async throws {
    let baseClient = try MockCopilotClient(detail: playerDetailFixture(), conversations: playerConversationsFixture())
    let report = playerReport(audience: .player)
    let alert = playerAlert(audience: .player)
    let workspace = SDPlayerDevelopmentWorkspaceResponse(
      evidencePack: baseClient.workspace.evidencePack,
      suggestedQuestions: baseClient.workspace.suggestedQuestions,
      playerVisibleReports: [report],
      reportsAvailability: "1 player summary",
      playerVisibleAlerts: [alert],
      alertsAvailability: "1 player alert"
    )
    let client = try MockCopilotClient(
      detail: playerDetailFixture(),
      conversations: playerConversationsFixture(),
      workspace: workspace
    )
    let model = PlayerDevelopmentPlayerWorkspaceModel()
    await model.load(client: client, organizationId: orgId, userId: playerId, playerId: playerId)
    #expect(model.reports.map(\.audience) == [.player])
    #expect(model.alerts.map(\.audience) == [.player])
    await model.generateSummary(client: client, organizationId: orgId, userId: playerId, playerId: playerId)
    #expect(client.playerGenerationTargets == [playerId])
    #expect(client.playerGenerationKeys.count == 1)
    #expect(model.generationPhase == .succeeded("Your summary is ready."))
    #expect(model.reports.count == 1)
    #expect(model.alerts.count == 1)
  }

  @Test("Player workspace rejects staff report or alert audience before rendering")
  @MainActor
  func playerWorkspaceRejectsStaffRecords() async throws {
    let base = try MockCopilotClient(detail: playerDetailFixture(), conversations: playerConversationsFixture())
    let workspace = SDPlayerDevelopmentWorkspaceResponse(
      evidencePack: base.workspace.evidencePack,
      suggestedQuestions: [],
      playerVisibleReports: [playerReport(audience: .staff)],
      reportsAvailability: "",
      playerVisibleAlerts: [playerAlert(audience: .staff)],
      alertsAvailability: ""
    )
    let client = try MockCopilotClient(detail: playerDetailFixture(), conversations: playerConversationsFixture(), workspace: workspace)
    let model = PlayerDevelopmentPlayerWorkspaceModel()
    await model.load(client: client, organizationId: orgId, userId: playerId, playerId: playerId)
    if case .failed = model.phase {
      #expect(model.reports.isEmpty)
      #expect(model.alerts.isEmpty)
    } else {
      Issue.record("Staff-audience development records were not rejected.")
    }
  }

  @Test("Coach and player histories request separate audiences and player hides staff sections")
  @MainActor
  func workspaceAudienceSeparation() async throws {
    let playerClient = try MockCopilotClient(
      detail: playerDetailFixture(),
      conversations: playerConversationsFixture()
    )
    let playerModel = PlayerDevelopmentCopilotWorkspaceModel()
    await playerModel.load(
      client: playerClient,
      organizationId: orgId,
      userId: playerId,
      playerId: playerId,
      audience: .player
    )
    #expect(playerModel.phase == .loaded)
    #expect(playerModel.conversations.allSatisfy { $0.audience == .player })
    #expect(playerClient.listAudiences == [.player])
    #expect(playerClient.parentDraftListCalls == 0)

    let coachClient = try MockCopilotClient(
      detail: fixtureDetail(),
      conversations: conversationsFixture()
    )
    let coachModel = PlayerDevelopmentCopilotWorkspaceModel()
    await coachModel.load(
      client: coachClient,
      organizationId: orgId,
      userId: userId,
      playerId: playerId,
      audience: .coach
    )
    #expect(coachModel.conversations.allSatisfy { $0.audience == .coach })
    #expect(coachClient.listAudiences == [.coach])
    #expect(coachClient.parentDraftListCalls == 1)

    let playerPolicy = SDCopilotPresentationPolicy(audience: .player)
    #expect(playerPolicy.showsPlayerSafeWorkspace)
    #expect(!playerPolicy.showsStaffReviewControls)
    #expect(!playerPolicy.showsParentDraftControls)
    #expect(!playerPolicy.showsParentDraftUsage)
    #expect(SDCopilotPresentationPolicy(audience: .coach).showsParentDraftControls)
  }

  @Test("Organization and user switching reject stale player workspace responses")
  @MainActor
  func playerWorkspaceStaleResponse() async throws {
    let client = try MockCopilotClient(
      detail: playerDetailFixture(),
      conversations: playerConversationsFixture()
    )
    client.workspaceDelay = 80_000_000
    let model = PlayerDevelopmentPlayerWorkspaceModel()
    let load = Task { @MainActor in
      await model.load(
        client: client,
        organizationId: orgId,
        userId: playerId,
        playerId: playerId
      )
    }
    try await Task.sleep(nanoseconds: 10_000_000)
    model.reset()
    await load.value
    #expect(model.phase == .idle)
    #expect(model.response == nil)
    #expect(model.reports.isEmpty)
    #expect(model.alerts.isEmpty)
    #expect(model.generationPhase == .idle)
  }

  @Test("Player report and alert UI renders evidence without staff or parent controls")
  func playerRecordUIWiring() throws {
    let projectRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    let source = try String(contentsOf: projectRoot.appendingPathComponent("MultiOrg/Features/Player/PlayerDevelopmentPlayerWorkspaceView.swift"), encoding: .utf8)
    #expect(source.contains("Generate My Summary"))
    #expect(source.contains("PlayerDevelopmentPlayerReportDetailView"))
    #expect(source.contains("PlayerDevelopmentPlayerAlertDetailView"))
    #expect(source.contains("Evidence citations"))
    #expect(source.contains("Archive My Summary"))
    #expect(source.contains("Dismiss This Alert"))
    #expect(source.contains("onRetry: { Task { await loadWorkspace() } }"))
    #expect(source.contains("private func loadWorkspace() async"))
    #expect(!source.contains("Approve Report"))
    #expect(!source.contains("Reject Report"))
    #expect(!source.contains("Generate Parent Update"))
  }

  @Test("Player feedback keeps player audience and deterministic recommendations")
  @MainActor
  func playerFeedbackAndRecommendations() async throws {
    let detail = try playerDetailFixture()
    let client = try MockCopilotClient(
      detail: detail,
      conversations: playerConversationsFixture()
    )
    let model = PlayerDevelopmentCopilotConversationModel()
    await model.load(
      client: client,
      organizationId: orgId,
      userId: playerId,
      playerId: playerId,
      audience: .player,
      conversationId: conversationId
    )
    let assistant = try #require(model.messages.last)
    #expect(assistant.promptVersion == "player-copilot-self.v1")
    #expect(assistant.generationMode == .deterministic)
    #expect(assistant.structuredAnswer?.proposedActions.first?.actionType == .reviewMetricWithCoach)
    #expect(assistant.structuredAnswer?.proposedActions.first?.requiresApproval == true)
    await model.submitFeedback(
      client: client,
      organizationId: orgId,
      audience: .player,
      conversationId: conversationId,
      messageId: assistant.id,
      type: .helpful
    )
    #expect(client.feedbackAudiences == [.player])
    #expect(model.successMessage == "Feedback saved.")
  }

  @Test("Mismatched player audience responses fail closed")
  @MainActor
  func mismatchedAudienceFailsClosed() async throws {
    let client = try MockCopilotClient(
      detail: fixtureDetail(),
      conversations: conversationsFixture()
    )
    let model = PlayerDevelopmentCopilotWorkspaceModel()
    await model.load(
      client: client,
      organizationId: orgId,
      userId: playerId,
      playerId: playerId,
      audience: .player
    )
    if case .failed = model.phase {
      #expect(model.conversations.isEmpty)
    } else {
      Issue.record("Coach-audience history was not rejected from Player Copilot.")
    }
  }

  @Test("Assistant clarification binds a response to the exact pending question")
  @MainActor
  func pendingQuestionBinding() async throws {
    let detail = try pendingDetailFixture(playerAudience: true)
    let client = try MockCopilotClient(detail: detail, conversations: playerConversationsFixture())
    let model = PlayerDevelopmentCopilotConversationModel()
    await model.load(client: client, organizationId: orgId, userId: playerId, playerId: playerId, audience: .player, conversationId: conversationId)
    let pending = try #require(model.pendingQuestion)
    #expect(pending.questionType == .clarificationQuestion)
    #expect(pending.choices == ["Hitting", "Pitching"])
    #expect(await model.send(
      client: client,
      organizationId: orgId,
      userId: playerId,
      playerId: playerId,
      audience: .player,
      conversationId: conversationId,
      window: .trailingDays(90),
      responseText: "Hitting",
      responseMode: .answer
    ))
    #expect(client.pendingQuestionIds == [pending.id])
    #expect(client.pendingResponseModes == [.answer])
    #expect(model.pendingQuestion == nil)
  }

  @Test("Organization and user reset clears pending Copilot questions")
  @MainActor
  func pendingQuestionReset() async throws {
    let client = try MockCopilotClient(detail: pendingDetailFixture(playerAudience: true), conversations: playerConversationsFixture())
    let model = PlayerDevelopmentCopilotConversationModel()
    await model.load(client: client, organizationId: orgId, userId: playerId, playerId: playerId, audience: .player, conversationId: conversationId)
    #expect(model.pendingQuestion != nil)
    model.reset()
    #expect(model.pendingQuestion == nil)
    #expect(model.messages.isEmpty)
  }

  @Test("Coach and player question UI exposes all bounded response states")
  func questionUIWiring() throws {
    let projectRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    let source = try String(contentsOf: projectRoot.appendingPathComponent("MultiOrg/Features/Coach/PlayerDevelopmentCopilotView.swift"), encoding: .utf8)
    #expect(source.contains("CopilotQuestionCard"))
    #expect(source.contains("ForEach(pending.choices.prefix(6)"))
    #expect(source.contains("Type your response in the composer below."))
    #expect(source.contains("HPButton(title: \"Skip\""))
    #expect(source.contains("title: \"Use available evidence\""))
    #expect(source.contains("onResponse(\"Skip\", .skip)"))
    #expect(source.contains("onResponse(\"Use available evidence\", .useAvailableEvidence)"))
    #expect(source.contains("This question expired"))
    #expect(source.contains("Superseded by a newer question"))
    #expect(source.contains("pending.isOptional ? \"Optional\" : \"Required\""))
  }

  @Test("Conversation presentation is concrete, nonblank, scrollable, and platform complete")
  func conversationPresentationUIWiring() throws {
    let projectRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    let source = try String(
      contentsOf: projectRoot.appendingPathComponent("MultiOrg/Features/Coach/PlayerDevelopmentCopilotView.swift"),
      encoding: .utf8
    )
    #expect(source.contains("@Published private(set) var presentedConversation: SDCopilotConversationPresentation?"))
    #expect(source.contains("content.fullScreenCover(item: $item)"))
    #expect(source.contains("content.sheet(item: $item)"))
    #expect(source.contains("conversation: route.conversation"))
    #expect(source.contains(".frame(minWidth: 720, minHeight: 680)"))
    #expect(source.contains("ScrollViewReader"))
    #expect(source.contains("copilot-conversation-bottom"))
    #expect(source.contains("title: \"Ask a player-development question\""))
    #expect(source.contains("HPFormField("))
    #expect(source.contains("HPButton(\n                title: \"Send\""))
    #expect(source.contains("Retry conversation"))
    #expect(source.contains("Player Copilot • Private to you"))
    #expect(source.contains("Coach Copilot • Staff workspace"))
    #expect(source.contains("Coach Copilot requires an active coach, administrator, or owner membership"))
    #expect(source.contains("onRetry: canRetryInitialLoad"))
    #expect(source.contains("if case .failed = model.phase"))
    #expect(source.contains("Button(\"Close\") { dismiss() }"))
    #expect(source.contains(".keyboardShortcut(.cancelAction)"))
    #expect(!source.contains("@State private var createdConversation"))
    #expect(!source.contains("Button(\"Back\") { dismiss() }"))
  }

  @Test("Player and coach entry points declare their real presentation context")
  func copilotEntryUIWiring() throws {
    let projectRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    let playerSource = try String(
      contentsOf: projectRoot.appendingPathComponent("MultiOrg/Features/Player/PlayerDevelopmentPlayerWorkspaceView.swift"),
      encoding: .utf8
    )
    let coachAISource = try String(
      contentsOf: projectRoot.appendingPathComponent("MultiOrg/Features/Coach/PlayerDevelopmentAIView.swift"),
      encoding: .utf8
    )
    let coachProfileSource = try String(
      contentsOf: projectRoot.appendingPathComponent("MultiOrg/Features/Coach/CoachPlayerProfileView.swift"),
      encoding: .utf8
    )
    #expect(playerSource.contains("audience: .player"))
    #expect(playerSource.contains("presentationStyle: .pushed"))
    #expect(coachAISource.contains("audience: .coach"))
    #expect(coachAISource.contains("presentationStyle: .modal"))
    #expect(coachAISource.contains(".frame(minWidth: 760, minHeight: 720)"))
    #expect(coachProfileSource.contains("ForEach(Tab.visible(playerDevelopmentAIEnabled:"))
    #expect(coachProfileSource.contains("case developmentAI = \"Development AI\""))
    #expect(coachProfileSource.contains("Includes Player Development AI and Coach Copilot"))
  }

  private func membership(_ role: String) -> SDOrgMembership {
    SDOrgMembership(org_id: orgId, user_id: userId, role: role, status: "active", created_at: nil, created_by: nil)
  }

  private func playerReport(audience: SDDevelopmentRecordAudience) -> SDDevelopmentReport {
    SDDevelopmentReport(
      id: UUID(uuidString: "12121212-1212-4212-8212-121212121212")!,
      organizationId: orgId,
      playerId: playerId,
      teamId: nil,
      reportType: "player_development_summary",
      requestedBy: playerId,
      intendedAudience: "player",
      audience: audience,
      reportingWindowStart: "2026-04-18",
      reportingWindowEnd: "2026-07-16",
      status: .draft,
      qualityStatus: .sufficient,
      structuredContent: SDDevelopmentReportContent(
        overview: "Evidence-backed player summary.",
        positiveTrends: [],
        developmentPriorities: [],
        consistencyAndAttendance: "Attendance is unavailable.",
        dataGaps: [],
        coachReviewQuestions: ["What should I discuss with my coach?"],
        evidenceSummary: []
      ),
      renderedText: "Evidence-backed player summary.",
      generationMode: "deterministic",
      provider: "deterministic_template",
      modelIdentifier: nil,
      generatorVersion: "player-deterministic-template.v1",
      promptVersion: "player-development-self-summary.v1",
      inputCutoff: "2026-07-16T12:00:00Z",
      generatedAt: "2026-07-16T12:00:00Z",
      reviewedAt: nil,
      reviewedBy: nil,
      approvedAt: nil,
      rejectedAt: nil,
      archivedAt: nil,
      coachEdits: [:],
      reviewNotes: nil,
      confidence: 0.85,
      dataFreshness: "current",
      missingDataWarnings: [],
      evidenceFingerprint: String(repeating: "a", count: 64),
      createdAt: "2026-07-16T12:00:00Z",
      updatedAt: "2026-07-16T12:00:00Z"
    )
  }

  private func playerAlert(audience: SDDevelopmentRecordAudience) -> SDDevelopmentAlert {
    SDDevelopmentAlert(
      id: UUID(uuidString: "13131313-1313-4313-8313-131313131313")!,
      organizationId: orgId,
      playerId: playerId,
      reportId: nil,
      audience: audience,
      alertType: "stale_testing",
      severity: .info,
      status: .active,
      firstDetectedAt: "2026-07-16T12:00:00Z",
      lastDetectedAt: "2026-07-16T12:00:00Z",
      evidenceWindowStart: "2026-04-18",
      evidenceWindowEnd: "2026-07-16",
      ruleVersion: "development-alerts.v1",
      explanation: "You may benefit from updated testing.",
      recommendedHumanAction: "Discuss updated testing with your coach.",
      dataFreshness: "stale",
      evidenceQuality: .limited,
      deduplicationKey: "player:stale_testing",
      playerName: "Controlled Player"
    )
  }

  private func fixtureDetail() throws -> SDCopilotConversationDetailResponse {
    try JSONDecoder().decode(SDCopilotConversationDetailResponse.self, from: Data(conversationDetailJSON.utf8))
  }

  private func conversationsFixture() throws -> SDCopilotConversationsResponse {
    try JSONDecoder().decode(SDCopilotConversationsResponse.self, from: Data(conversationsJSON.utf8))
  }

  private func playerConversationsFixture() throws -> SDCopilotConversationsResponse {
    try JSONDecoder().decode(
      SDCopilotConversationsResponse.self,
      from: Data(playerJSON(conversationsJSON).utf8)
    )
  }

  private func playerDetailFixture() throws -> SDCopilotConversationDetailResponse {
    try JSONDecoder().decode(
      SDCopilotConversationDetailResponse.self,
      from: Data(playerJSON(conversationDetailJSON).utf8)
    )
  }

  private func pendingDetailFixture(playerAudience: Bool) throws -> SDCopilotConversationDetailResponse {
    let source = playerAudience ? playerJSON(conversationDetailJSON) : conversationDetailJSON
    var object = try #require(JSONSerialization.jsonObject(with: Data(source.utf8)) as? [String: Any])
    var messages = try #require(object["messages"] as? [[String: Any]])
    var assistant = messages[1]
    let pending: [String: Any] = [
      "id": "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
      "conversation_id": conversationId.uuidString.lowercased(),
      "assistant_message_id": "88888888-8888-4888-8888-888888888888",
      "question_type": "clarification_question",
      "question_text": "Which development area should I focus on?",
      "why_asked": "The request did not identify a development domain.",
      "expected_response_type": "choice",
      "choices": ["Hitting", "Pitching"],
      "related_evidence_ids": [],
      "is_optional": true,
      "may_later_be_saved": false,
      "status": "pending",
      "expires_at": "2099-07-17T12:00:00Z",
      "answered_at": NSNull(),
    ]
    assistant["assistant_turn_type"] = "clarification_question"
    assistant["pending_question"] = pending
    var structured = try #require(assistant["structured_answer"] as? [String: Any])
    structured["assistant_turn_type"] = "clarification_question"
    structured["pending_question"] = [
      "question_type": "clarification_question",
      "why_asked": "The request did not identify a development domain.",
      "expected_response_type": "choice",
      "choices": ["Hitting", "Pitching"],
      "related_evidence_ids": [],
      "is_optional": true,
      "may_later_be_saved": false,
      "expires_at": "2099-07-17T12:00:00Z",
    ]
    assistant["structured_answer"] = structured
    messages[1] = assistant
    object["messages"] = messages
    return try JSONDecoder().decode(
      SDCopilotConversationDetailResponse.self,
      from: JSONSerialization.data(withJSONObject: object)
    )
  }

  private func playerJSON(_ source: String) -> String {
    source
      .replacingOccurrences(of: #""audience":"coach""#, with: #""audience":"player""#)
      .replacingOccurrences(of: #""created_by":"33333333-3333-4333-8333-333333333333""#, with: #""created_by":"22222222-2222-4222-8222-222222222222""#)
      .replacingOccurrences(of: #""actor_id":"33333333-3333-4333-8333-333333333333""#, with: #""actor_id":"22222222-2222-4222-8222-222222222222""#)
      .replacingOccurrences(of: "coach-copilot.v1", with: "player-copilot-self.v1")
      .replacingOccurrences(of: "discuss_metric_with_player", with: "review_metric_with_coach")
  }
}

private struct CopilotCreateCall: Equatable {
  let organizationId: UUID
  let playerId: UUID
  let audience: SDCopilotAudience
  let title: String
  let reportingWindowDays: Int
  let idempotencyKey: UUID
}

@MainActor
private final class MockCopilotClient: PlayerDevelopmentCopilotClient {
  let detail: SDCopilotConversationDetailResponse
  let conversations: SDCopilotConversationsResponse
  let workspace: SDPlayerDevelopmentWorkspaceResponse
  var askDelay: UInt64 = 0
  var createDelay: UInt64 = 0
  var workspaceDelay: UInt64 = 0
  var nextAskError: Error?
  var nextCreateError: Error?
  var askKeys: [UUID] = []
  var createCalls: [CopilotCreateCall] = []
  var retryFlags: [Bool] = []
  var pendingQuestionIds: [UUID?] = []
  var pendingResponseModes: [SDCopilotPendingResponseMode?] = []
  var listAudiences: [SDCopilotAudience] = []
  var feedbackAudiences: [SDCopilotAudience] = []
  var parentDraftListCalls = 0
  var workspaceRequests: [(UUID, UUID)] = []
  var playerGenerationTargets: [UUID] = []
  var playerGenerationKeys: [UUID] = []

  init(
    detail: SDCopilotConversationDetailResponse,
    conversations: SDCopilotConversationsResponse,
    workspace: SDPlayerDevelopmentWorkspaceResponse? = nil
  ) {
    self.detail = detail
    self.conversations = conversations
    self.workspace = workspace ?? (try! JSONDecoder().decode(
        SDPlayerDevelopmentWorkspaceResponse.self,
        from: Data(playerWorkspaceJSON.utf8)
      ))
  }

  func listCopilotConversations(organizationId: UUID, playerId: UUID, audience: SDCopilotAudience, offset: Int, limit: Int) async throws -> SDCopilotConversationsResponse {
    listAudiences.append(audience)
    return conversations
  }
  func createCopilotConversation(organizationId: UUID, playerId: UUID, audience: SDCopilotAudience, title: String, reportingWindowDays: Int, idempotencyKey: UUID) async throws -> SDCopilotConversation {
    createCalls.append(CopilotCreateCall(
      organizationId: organizationId,
      playerId: playerId,
      audience: audience,
      title: title,
      reportingWindowDays: reportingWindowDays,
      idempotencyKey: idempotencyKey
    ))
    if createDelay > 0 { try await Task.sleep(nanoseconds: createDelay) }
    if let error = nextCreateError { nextCreateError = nil; throw error }
    return conversations.conversations[0]
  }
  func copilotConversation(organizationId: UUID, conversationId: UUID, audience: SDCopilotAudience, offset: Int, limit: Int) async throws -> SDCopilotConversationDetailResponse { detail }
  func copilotMessage(organizationId: UUID, conversationId: UUID, messageId: UUID, audience: SDCopilotAudience) async throws -> SDCopilotMessage { detail.messages[1] }
  func archiveCopilotConversation(organizationId: UUID, conversationId: UUID, audience: SDCopilotAudience) async throws -> SDCopilotConversation { conversations.conversations[0] }
  func askCopilot(organizationId: UUID, playerId: UUID, conversationId: UUID, audience: SDCopilotAudience, question: String, window: SDDevelopmentWindow, idempotencyKey: UUID, retry: Bool, pendingQuestionId: UUID?, pendingResponseMode: SDCopilotPendingResponseMode?) async throws -> SDCopilotAskResponse {
    askKeys.append(idempotencyKey); retryFlags.append(retry)
    pendingQuestionIds.append(pendingQuestionId); pendingResponseModes.append(pendingResponseMode)
    if askDelay > 0 { try await Task.sleep(nanoseconds: askDelay) }
    if let error = nextAskError { nextAskError = nil; throw error }
    return SDCopilotAskResponse(userMessage: detail.messages[0], assistantMessage: detail.messages[1], reused: retry, suggestedQuestions: ["What evidence is missing?"], error: nil, message: nil, pendingQuestion: nil)
  }
  func submitCopilotFeedback(organizationId: UUID, conversationId: UUID, messageId: UUID, audience: SDCopilotAudience, type: SDCopilotFeedbackType, note: String?) async throws {
    feedbackAudiences.append(audience)
  }
  func copilotSuggestedQuestions(organizationId: UUID, playerId: UUID, audience: SDCopilotAudience) async throws -> SDCopilotSuggestedQuestionsResponse { SDCopilotSuggestedQuestionsResponse(suggestedQuestions: ["What changed in the last 30 days?"], evidenceQuality: .sufficient) }
  func playerDevelopmentWorkspace(organizationId: UUID, playerId: UUID) async throws -> SDPlayerDevelopmentWorkspaceResponse {
    workspaceRequests.append((organizationId, playerId))
    if workspaceDelay > 0 { try await Task.sleep(nanoseconds: workspaceDelay) }
    return workspace
  }
  func generatePlayerDevelopmentReport(organizationId: UUID, playerId: UUID, window: SDDevelopmentWindow, evidenceCutoff: Date, idempotencyKey: UUID) async throws -> SDDevelopmentGenerateResponse {
    playerGenerationTargets.append(playerId)
    playerGenerationKeys.append(idempotencyKey)
    guard let report = workspace.playerVisibleReports.first else { fatalError("player report fixture missing") }
    return SDDevelopmentGenerateResponse(
      report: report,
      reused: false,
      evidencePack: workspace.evidencePack,
      playerAlerts: workspace.playerVisibleAlerts
    )
  }
  func playerDevelopmentReportDetail(organizationId: UUID, reportId: UUID) async throws -> SDDevelopmentReportDetail { fatalError("not used") }
  func archivePlayerDevelopmentReport(organizationId: UUID, reportId: UUID) async throws -> SDDevelopmentReport { fatalError("not used") }
  func playerDevelopmentAlertDetail(organizationId: UUID, alertId: UUID) async throws -> SDDevelopmentAlertDetail { fatalError("not used") }
  func dismissPlayerDevelopmentAlert(organizationId: UUID, alertId: UUID) async throws -> SDDevelopmentAlert { fatalError("not used") }
  func listParentUpdateDrafts(organizationId: UUID, playerId: UUID) async throws -> [SDParentUpdateDraft] {
    parentDraftListCalls += 1
    return []
  }
  func createParentUpdateDraft(organizationId: UUID, playerId: UUID, conversationId: UUID?, sourceMessageId: UUID?, window: SDDevelopmentWindow, idempotencyKey: UUID) async throws -> SDParentUpdateDraft { fatalError("not used") }
  func parentUpdateDraft(organizationId: UUID, draftId: UUID) async throws -> SDParentDraftDetailResponse { fatalError("not used") }
  func updateParentUpdateDraft(organizationId: UUID, draftId: UUID, content: SDParentUpdateContent?, markReviewed: Bool, note: String?) async throws -> SDParentUpdateDraft { fatalError("not used") }
  func transitionParentUpdateDraft(organizationId: UUID, draftId: UUID, action: String, note: String?) async throws -> SDParentUpdateDraft { fatalError("not used") }
  func copilotUsage(organizationId: UUID, audience: SDCopilotAudience) async throws -> SDCopilotUsage {
    SDCopilotUsage(organizationQuestionsToday: 2, actorQuestionsThisHour: 1, organizationParentDraftsToday: 0, limits: SDCopilotUsageLimits(questionsPerOrganizationDay: 200, questionsPerActorHour: 30, parentDraftsPerOrganizationDay: 50, evidenceRows: 500, conversationMessages: 40, outputCharacters: 16_000))
  }
}

private enum TestCopilotError: LocalizedError {
  case providerUnavailable
  case creationFailed

  var errorDescription: String? {
    switch self {
    case .providerUnavailable:
      "Conversational generation is not configured."
    case .creationFailed:
      "[conversation_create_failed] Conversation creation failed."
    }
  }
}

private let conversationsJSON = #"""
{
  "conversations": [{
    "id":"44444444-4444-4444-8444-444444444444","org_id":"11111111-1111-4111-8111-111111111111","player_id":"22222222-2222-4222-8222-222222222222","created_by":"33333333-3333-4333-8333-333333333333","audience":"coach","title":"Controlled development","status":"active","reporting_window_days":90,"evidence_cutoff":"2026-07-16T12:00:00Z","generation_mode":"deterministic","provider":"deterministic_template","model_identifier":null,"generator_version":"player-development-copilot.v1","archived_at":null,"created_at":"2026-07-16T12:00:00Z","updated_at":"2026-07-16T12:00:00Z","player_name":"Controlled Player","most_recent_question":"What changed?","most_recent_answer_preview":"Maximum exit velocity increased.","quality_status":"sufficient"
  }],
  "total":1,
  "pagination":{"limit":25,"offset":0,"has_more":false}
}
"""#

private let conversationDetailJSON = #"""
{
  "conversation": {
    "id":"44444444-4444-4444-8444-444444444444","org_id":"11111111-1111-4111-8111-111111111111","player_id":"22222222-2222-4222-8222-222222222222","created_by":"33333333-3333-4333-8333-333333333333","audience":"coach","title":"Controlled development","status":"active","reporting_window_days":90,"evidence_cutoff":"2026-07-16T12:00:00Z","generation_mode":"deterministic","provider":"deterministic_template","model_identifier":null,"generator_version":"player-development-copilot.v1","archived_at":null,"created_at":"2026-07-16T12:00:00Z","updated_at":"2026-07-16T12:00:00Z","player_name":"Controlled Player","most_recent_question":null,"most_recent_answer_preview":null,"quality_status":"sufficient"
  },
  "messages": [
    {"id":"55555555-5555-4555-8555-555555555555","conversation_id":"44444444-4444-4444-8444-444444444444","org_id":"11111111-1111-4111-8111-111111111111","player_id":"22222222-2222-4222-8222-222222222222","actor_id":"33333333-3333-4333-8333-333333333333","audience":"coach","role":"user","user_question":"What changed?","structured_answer":null,"rendered_answer":null,"quality_status":"unavailable","evidence_cutoff":"2026-07-16T12:00:00Z","generation_mode":"deterministic","provider":"deterministic_template","model_identifier":null,"prompt_version":"coach-copilot.v1","generator_version":"player-development-copilot.v1","generation_status":"succeeded","safe_error_code":null,"archived_at":null,"created_at":"2026-07-16T12:00:00Z","citations":null},
    {"id":"88888888-8888-4888-8888-888888888888","conversation_id":"44444444-4444-4444-8444-444444444444","org_id":"11111111-1111-4111-8111-111111111111","player_id":"22222222-2222-4222-8222-222222222222","actor_id":null,"audience":"coach","role":"assistant","user_question":null,"structured_answer":{"schema_version":"player_development_copilot_answer.v1","answer":"Maximum exit velocity increased.","answer_quality":"sufficient","facts":[{"text":"The latest value is 91 mph.","evidence_ids":["e1"]}],"calculations":[{"text":"The change is 2 mph.","evidence_ids":["e1"],"rule_id":"trend.higher_is_better.v1"}],"interpretations":[{"text":"The rule classifies improvement.","evidence_ids":["e1"],"confidence":0.85}],"recommendations":[{"text":"Review before changing a program.","evidence_ids":["e1"],"requires_human_approval":true}],"missing_data":[],"follow_up_questions":["What evidence is missing?"],"warnings":[],"proposed_actions":[{"action_type":"discuss_metric_with_player","explanation":"Review the result.","evidence_ids":["e1"],"urgency":"low","confidence":0.8,"requires_approval":true}]},"rendered_answer":"Maximum exit velocity increased.","quality_status":"sufficient","evidence_cutoff":"2026-07-16T12:00:00Z","generation_mode":"deterministic","provider":"deterministic_template","model_identifier":null,"prompt_version":"coach-copilot.v1","generator_version":"player-development-copilot.v1","generation_status":"succeeded","safe_error_code":null,"archived_at":null,"created_at":"2026-07-16T12:00:01Z","citations":[{"id":"77777777-7777-4777-8777-777777777777","message_id":"88888888-8888-4888-8888-888888888888","org_id":"11111111-1111-4111-8111-111111111111","player_id":"22222222-2222-4222-8222-222222222222","audience":"coach","evidence_key":"e1","source_entity_type":"metric_observation","source_record_id":"record-1","canonical_metric_key":"hitting.exit_velocity.max","observed_value":"91","normalized_value":91,"unit":"mph","observed_at":"2026-07-15T12:00:00Z","display_label":"Maximum exit velocity","explanation":"Latest supported measurement.","section_key":"facts","claim_identifier":"facts.0","source_provider":"rapsodo","verification_status":"verified","deterministic_rule_id":"trend.higher_is_better.v1","evidence_snapshot":{"value":91,"unit":"mph"}}]}
  ],
  "total":2,
  "pagination":{"limit":40,"offset":0,"has_more":false}
}
"""#

private let parentDraftJSON = #"""
{
  "draft":{"id":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","org_id":"11111111-1111-4111-8111-111111111111","player_id":"22222222-2222-4222-8222-222222222222","conversation_id":"44444444-4444-4444-8444-444444444444","source_message_id":"88888888-8888-4888-8888-888888888888","created_by":"33333333-3333-4333-8333-333333333333","status":"reviewed","generated_original":{"schema_version":"parent_update_draft.v1","recent_work":"Recent work.","positive_developments":"Positive.","current_focus":"Original focus.","consistency":"Limited.","recent_testing":"Testing.","evidence_limitations":"Limitations.","upcoming_next_steps":"Next."},"edited_content":{"schema_version":"parent_update_draft.v1","recent_work":"Recent work.","positive_developments":"Positive.","current_focus":"Coach-edited focus.","consistency":"Limited.","recent_testing":"Testing.","evidence_limitations":"Limitations.","upcoming_next_steps":"Next."},"generated_rendered_text":"Generated","edited_rendered_text":"Edited","evidence_cutoff":"2026-07-16T12:00:00Z","generation_mode":"deterministic","provider":"deterministic_template","model_identifier":null,"prompt_version":"parent-update.v1","generator_version":"player-development-copilot.v1","reviewed_at":"2026-07-16T12:05:00Z","reviewed_by":"33333333-3333-4333-8333-333333333333","approved_at":null,"approved_by":null,"rejected_at":null,"rejected_by":null,"archived_at":null,"archived_by":null,"created_at":"2026-07-16T12:00:00Z","updated_at":"2026-07-16T12:05:00Z"},
  "review_events":[{"id":"bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb","draft_id":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","org_id":"11111111-1111-4111-8111-111111111111","player_id":"22222222-2222-4222-8222-222222222222","actor_id":"33333333-3333-4333-8333-333333333333","event_type":"reviewed","from_status":"generated","to_status":"reviewed","safe_note":null,"content_snapshot":{"schema_version":"parent_update_draft.v1","recent_work":"Recent work.","positive_developments":"Positive.","current_focus":"Coach-edited focus.","consistency":"Limited.","recent_testing":"Testing.","evidence_limitations":"Limitations.","upcoming_next_steps":"Next."},"created_at":"2026-07-16T12:05:00Z"}]
}
"""#

private let playerWorkspaceJSON = #"""
{
  "evidence_pack": {
    "schema_version":"player_development_evidence_pack.v1",
    "organization_id":"11111111-1111-4111-8111-111111111111",
    "player_id":"22222222-2222-4222-8222-222222222222",
    "player_name":"Controlled Player",
    "report_type":"player_copilot_self_question",
    "window_start":"2026-04-18",
    "window_end":"2026-07-16",
    "evidence_cutoff":"2026-07-16T12:00:00Z",
    "quality_status":"sufficient",
    "data_freshness":"current",
    "coverage":{"testing_entries":1,"metric_observations":1,"daily_logs":1,"program_assignments":1,"bp_sessions":0},
    "trends":[{
      "canonical_metric_key":"hitting.exit_velocity.max",
      "display_name":"Maximum exit velocity",
      "unit":"mph",
      "latest_value":91,
      "prior_value":89,
      "absolute_change":2,
      "percentage_change":2.247,
      "rolling_average":90,
      "recent_window_average":91,
      "prior_window_average":89,
      "best_value":91,
      "worst_value":89,
      "sample_count":2,
      "observation_frequency_days":30,
      "freshness":"current",
      "quality":"sufficient",
      "interpretation":"improvement",
      "rule_id":"trend.higher_is_better.v1",
      "evidence_keys":["e1"]
    }],
    "evidence":[{
      "evidence_key":"e1",
      "section_key":"metrics",
      "source_entity_type":"player_development_import",
      "source_record_id":"record-1",
      "canonical_metric_key":"hitting.exit_velocity.max",
      "raw_observed_value":"91",
      "normalized_numeric_value":91,
      "unit":"mph",
      "observation_date":"2026-07-15T12:00:00Z",
      "comparison_value":89,
      "comparison_period":"prior observation",
      "direction":"improvement",
      "sample_size":2,
      "freshness":"current",
      "quality":"sufficient",
      "deterministic_rule_id":"trend.higher_is_better.v1",
      "display_label":"Maximum exit velocity",
      "explanation":"Latest supported measurement.",
      "source_metadata":{"provider":"rapsodo","verification_status":"verified"},
      "evidence_snapshot":{"value":91,"unit":"mph"}
    }],
    "missing_data_warnings":["No authoritative attendance table is available."],
    "stale_data_warnings":[],
    "unit_conflicts":[],
    "low_sample_warnings":[]
  },
  "suggested_questions":["What changed in the last 30 days?","What did my latest Rapsodo session show?"],
  "player_visible_reports":[],
  "reports_availability":"No player-visible summary exists yet.",
  "player_visible_alerts":[],
  "alerts_availability":"No player-visible objective alert exists right now."
}
"""#
