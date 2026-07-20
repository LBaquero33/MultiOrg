import Foundation
import Testing
@testable import HomePlate

@Suite("Player Copilot response contract")
struct PlayerDevelopmentCopilotResponseContractTests {
  private let requestId = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"

  @Test("Valid canonical answer decodes legacy inline citations safely")
  func validSuccessPayload() throws {
    let response = try SDCopilotResponseContract.decode(
      SDCopilotAskResponse.self,
      from: canonicalSuccessData(answerJSON: askResponseJSON()),
      statusCode: 200,
      contentType: "application/json",
      requestId: requestId,
      canonicalPayloadKey: .answer
    )
    let citation = try #require(response.assistantMessage.citations?.first)
    #expect(citation.persistedId == nil)
    #expect(citation.messageId == nil)
    #expect(citation.organizationId == nil)
    #expect(citation.playerId == nil)
    #expect(citation.audience == nil)
    #expect(citation.id.contains("evidence-1"))
    #expect(response.assistantMessage.renderedAnswer == "Your latest supported result is available.")
  }

  @Test("Missing canonical answer produces a controlled diagnostic")
  func missingAnswer() throws {
    let data = Data(#"{"ok":true,"data":null,"error":null,"request_id":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}"#.utf8)
    let error = try contractError(data: data, statusCode: 200)
    #expect(error.diagnosticCode == "copilot_incomplete_response")
    #expect(error.diagnostic?.missingKey == "answer")
    #expect(error.localizedDescription == "Copilot received an incomplete response. Please try again.")
  }

  @Test("Null canonical answer produces a controlled diagnostic")
  func nullAnswer() throws {
    let data = Data(#"{"ok":true,"answer":null,"error":null,"request_id":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}"#.utf8)
    let error = try contractError(data: data, statusCode: 200)
    #expect(error.diagnosticCode == "copilot_incomplete_response")
    #expect(error.diagnostic?.missingKey == "answer")
  }

  @Test("Canonical backend error decodes separately from success")
  func backendErrorPayload() throws {
    let data = canonicalFailureData(code: "provider_timeout", retryable: true)
    let error = try contractError(data: data, statusCode: 503)
    #expect(error.diagnosticCode == "provider_timeout")
    #expect(error.isRetryable)
    #expect(error.requestId == requestId)
  }

  @Test("Legacy non-2xx JSON is never decoded as success")
  func nonSuccessLegacyJSON() throws {
    let data = Data(#"{"error":"rate_limited","message":"Try again later."}"#.utf8)
    let error = try contractError(data: data, statusCode: 429)
    #expect(error.diagnosticCode == "rate_limited")
    #expect(error.isRetryable)
  }

  @Test("Empty response body is controlled and retryable")
  func emptyResponseBody() throws {
    let error = try contractError(data: Data(), statusCode: 200)
    #expect(error.diagnosticCode == "copilot_empty_response")
    #expect(error.isRetryable)
  }

  @Test("Malformed JSON is controlled and retains only a redacted body")
  func malformedJSON() throws {
    let error = try contractError(data: Data("{private player text".utf8), statusCode: 200)
    #expect(error.diagnosticCode == "copilot_malformed_response")
    #expect(error.diagnostic?.redactedBody == "<non-json body: 20 bytes>")
    #expect(error.diagnostic?.redactedBody.contains("private player text") == false)
  }

  @Test("Retryable failure can be followed by a successful canonical retry")
  func retrySuccess() throws {
    let failure = try contractError(
      data: canonicalFailureData(code: "provider_timeout", retryable: true),
      statusCode: 503
    )
    #expect(failure.isRetryable)
    let retried = try SDCopilotResponseContract.decode(
      SDCopilotAskResponse.self,
      from: canonicalSuccessData(answerJSON: askResponseJSON()),
      statusCode: 200,
      contentType: "application/json",
      requestId: requestId,
      canonicalPayloadKey: .answer
    )
    #expect(retried.assistantMessage.generationStatus == .succeeded)
  }

  @Test("Historical messages from the older schema remain readable")
  func historicalOlderSchema() throws {
    let json = """
    {
      "conversation": \(conversationJSON()),
      "messages": [\(userMessageJSON()), \(assistantMessageJSON(includeLegacyInlineCitation: false))],
      "total": 2,
      "pagination": {"limit":40,"offset":0,"has_more":false}
    }
    """
    let detail = try SDCopilotResponseContract.decode(
      SDCopilotConversationDetailResponse.self,
      from: Data(json.utf8),
      statusCode: 200,
      contentType: "application/json",
      requestId: requestId
    )
    let assistant = try #require(detail.messages.last)
    #expect(assistant.assistantTurnType == nil)
    #expect(assistant.inReplyToQuestionId == nil)
    #expect(assistant.pendingQuestion == nil)
    #expect(assistant.citations?.first?.persistedId != nil)
  }

  private func contractError(data: Data, statusCode: Int) throws -> SDCopilotResponseContractError {
    do {
      let _: SDCopilotAskResponse = try SDCopilotResponseContract.decode(
        SDCopilotAskResponse.self,
        from: data,
        statusCode: statusCode,
        contentType: "application/json",
        requestId: requestId,
        canonicalPayloadKey: .answer
      )
      Issue.record("Expected the response contract to reject the payload.")
      throw TestContractError.expectedFailure
    } catch let error as SDCopilotResponseContractError {
      return error
    }
  }

  private func canonicalSuccessData(answerJSON: String) -> Data {
    Data("""
    {"ok":true,"answer":\(answerJSON),"data":null,"error":null,"request_id":"\(requestId)"}
    """.utf8)
  }

  private func canonicalFailureData(code: String, retryable: Bool) -> Data {
    Data("""
    {"ok":false,"answer":null,"data":null,"error":{"code":"\(code)","message":"Safe failure.","retryable":\(retryable)},"request_id":"\(requestId)"}
    """.utf8)
  }

  private func askResponseJSON() -> String {
    """
    {
      "user_message": \(userMessageJSON()),
      "assistant_message": \(assistantMessageJSON(includeLegacyInlineCitation: true)),
      "reused": false,
      "suggested_questions": ["What changed?"],
      "error": null,
      "message": null,
      "pending_question": null
    }
    """
  }

  private func conversationJSON() -> String {
    """
    {"id":"44444444-4444-4444-8444-444444444444","org_id":"11111111-1111-4111-8111-111111111111","player_id":"22222222-2222-4222-8222-222222222222","created_by":"22222222-2222-4222-8222-222222222222","audience":"player","title":"Player Copilot","status":"active","reporting_window_days":90,"evidence_cutoff":"2026-07-17T12:00:00Z","generation_mode":"deterministic","provider":"deterministic_template","model_identifier":null,"generator_version":"player-development-copilot.v1","archived_at":null,"created_at":"2026-07-17T12:00:00Z","updated_at":"2026-07-17T12:00:00Z"}
    """
  }

  private func userMessageJSON() -> String {
    """
    {"id":"55555555-5555-4555-8555-555555555555","conversation_id":"44444444-4444-4444-8444-444444444444","org_id":"11111111-1111-4111-8111-111111111111","player_id":"22222222-2222-4222-8222-222222222222","actor_id":"22222222-2222-4222-8222-222222222222","audience":"player","role":"user","user_question":"What changed?","structured_answer":null,"rendered_answer":null,"quality_status":"unavailable","evidence_cutoff":"2026-07-17T12:00:00Z","generation_mode":"deterministic","provider":"deterministic_template","model_identifier":null,"prompt_version":"player-copilot.v1","generator_version":"player-development-copilot.v1","generation_status":"succeeded","safe_error_code":null,"archived_at":null,"created_at":"2026-07-17T12:00:00Z","citations":null}
    """
  }

  private func assistantMessageJSON(includeLegacyInlineCitation: Bool) -> String {
    let scope = includeLegacyInlineCitation
      ? ""
      : #""id":"77777777-7777-4777-8777-777777777777","message_id":"88888888-8888-4888-8888-888888888888","org_id":"11111111-1111-4111-8111-111111111111","player_id":"22222222-2222-4222-8222-222222222222","audience":"player","#
    return """
    {"id":"88888888-8888-4888-8888-888888888888","conversation_id":"44444444-4444-4444-8444-444444444444","org_id":"11111111-1111-4111-8111-111111111111","player_id":"22222222-2222-4222-8222-222222222222","actor_id":null,"audience":"player","role":"assistant","user_question":null,"structured_answer":null,"rendered_answer":"Your latest supported result is available.","quality_status":"sufficient","evidence_cutoff":"2026-07-17T12:00:00Z","generation_mode":"deterministic","provider":"deterministic_template","model_identifier":null,"prompt_version":"player-copilot.v1","generator_version":"player-development-copilot.v1","generation_status":"succeeded","safe_error_code":null,"archived_at":null,"created_at":"2026-07-17T12:00:01Z","citations":[{\(scope)"evidence_key":"evidence-1","source_entity_type":"metric_observation","source_record_id":"record-1","canonical_metric_key":"hitting.exit_velocity.max","observed_value":"91","normalized_value":91,"unit":"mph","observed_at":"2026-07-17T12:00:00Z","display_label":"Maximum exit velocity","explanation":"Latest supported measurement.","section_key":"facts","claim_identifier":"facts.0","source_provider":"rapsodo","verification_status":"verified","deterministic_rule_id":"trend.higher_is_better.v1","evidence_snapshot":{"unit":"mph"}}]}
    """
  }
}

private enum TestContractError: Error {
  case expectedFailure
}

@Suite("Player Development AI platform vault")
struct PlayerDevelopmentPlatformVaultTests {
  @Test("The authoritative feature defaults off when no row is available")
  func defaultOff() {
    #expect(!SDPlatformFeatureGate.playerDevelopmentCopilotEnabled(in: []))
  }

  @Test("Disabled state removes the player route and rejects stale navigation")
  func disabledPlayerRoute() {
    let inventory = HPAppNavigationInventory.player(
      chatEnabled: true,
      facilitiesEnabled: true,
      testingEnabled: true,
      analysisEnabled: true,
      developmentAIEnabled: false,
      facilitiesTitle: "Facilities",
      testingTitle: "Testing"
    )
    #expect(inventory.destination(forWorkspaceKey: HPAppNavigationDestination.playerDevelopment.rawValue) == nil)
    #expect(inventory.normalizedRegularSelection(.playerDevelopment) == .playerToday)
  }

  @Test("Enabled state restores Player Copilot navigation")
  func enabledPlayerRoute() throws {
    let inventory = HPAppNavigationInventory.player(
      chatEnabled: true,
      facilitiesEnabled: true,
      testingEnabled: true,
      analysisEnabled: true,
      developmentAIEnabled: true,
      facilitiesTitle: "Facilities",
      testingTitle: "Testing"
    )
    #expect(inventory.destination(forWorkspaceKey: HPAppNavigationDestination.playerDevelopment.rawValue) == .playerDevelopment)
  }

  @Test("Disabled state removes Coach AI and enabled state restores it")
  func coachRouteToggle() {
    #expect(!CoachPlayerProfileView.Tab.visible(playerDevelopmentAIEnabled: false).contains(.developmentAI))
    #expect(CoachPlayerProfileView.Tab.visible(playerDevelopmentAIEnabled: true).contains(.developmentAI))
  }

  @Test("Only an explicit enabled server row opens the feature")
  func explicitServerEnable() {
    let enabled = SDPlatformFeatureFlag(
      key: SDPlatformFeatureKey.playerDevelopmentCopilot,
      enabled: true,
      description: "Enables AI-assisted coach and player Copilot experiences across Home Plate.",
      updated_at: nil,
      updated_by: nil
    )
    let unrelated = SDPlatformFeatureFlag(
      key: "unrelated_feature",
      enabled: true,
      description: "Unrelated",
      updated_at: nil,
      updated_by: nil
    )
    #expect(SDPlatformFeatureGate.playerDevelopmentCopilotEnabled(in: [enabled]))
    #expect(!SDPlatformFeatureGate.playerDevelopmentCopilotEnabled(in: [unrelated]))
  }

  @Test("Feature-disabled failures are controlled and non-retryable")
  func disabledFailurePresentation() {
    let presentation = SDCopilotFailurePresentation(
      code: "feature_disabled",
      fallbackMessage: "Internal backend detail"
    )
    #expect(presentation.message == "Player Development AI and Copilot are currently disabled by Home Plate.")
    #expect(!presentation.isRetryable)
  }
}
