import Foundation
import Supabase

@MainActor
extension SupabaseService {
  struct SDCanonicalEventDraft: Sendable {
    var title: String
    var eventType: SDGameEventType
    var description: String
    var start: Date
    var end: Date
    var arrival: Date?
    var locationName: String
    var venueAddress: String
    var facilityId: UUID?
    var teamId: UUID?
    var visibility: SDEventVisibility
    var opponentName: String = ""
    var gameSite: SDGameSite = .home
    var scheduledInnings: Int = 7
  }

  func listCanonicalEvents(
    organizationId: UUID,
    from start: Date,
    through end: Date
  ) async throws -> [SDCanonicalEvent] {
    try await client
      .from("sd_events")
      .select()
      .eq("org_id", value: organizationId)
      .gte("scheduled_start", value: start)
      .lt("scheduled_start", value: end)
      .order("scheduled_start", ascending: true)
      .execute()
      .value
  }

  func fetchCanonicalEvent(id: UUID, organizationId: UUID) async throws -> SDCanonicalEvent {
    try await client
      .from("sd_events")
      .select()
      .eq("id", value: id)
      .eq("org_id", value: organizationId)
      .single()
      .execute()
      .value
  }

  func createCanonicalEvent(
    organizationId: UUID,
    draft: SDCanonicalEventDraft
  ) async throws -> SDCanonicalEvent {
    let response: SDCanonicalEventMutationResponse = try await invokeAuthenticatedFunction(
      "web-operations",
      body: canonicalEventMutationBody(
        action: "create_event",
        organizationId: organizationId,
        eventId: nil,
        draft: draft
      )
    )
    return response.event
  }

  func updateCanonicalEvent(
    id: UUID,
    organizationId: UUID,
    draft: SDCanonicalEventDraft
  ) async throws -> SDCanonicalEvent {
    let response: SDCanonicalEventMutationResponse = try await invokeAuthenticatedFunction(
      "web-operations",
      body: canonicalEventMutationBody(
        action: "update_event",
        organizationId: organizationId,
        eventId: id,
        draft: draft
      )
    )
    return response.event
  }

  func cancelCanonicalEvent(id: UUID, organizationId: UUID) async throws {
    let _: SDCanonicalEventCancellationResponse = try await invokeAuthenticatedFunction(
      "web-operations",
      body: SDCanonicalEventCancellationRequest(
        action: "cancel_event",
        organization_id: organizationId.uuidString.lowercased(),
        event_id: id.uuidString.lowercased()
      )
    )
  }

  private struct SDCanonicalEventMutationResponse: Decodable {
    let event: SDCanonicalEvent
  }

  private struct SDCanonicalEventCancellationResponse: Decodable {
    let ok: Bool
  }

  private struct SDCanonicalEventCancellationRequest: Encodable {
    let action: String
    let organization_id: String
    let event_id: String
  }

  private struct SDCanonicalEventMutationRequest: Encodable {
    let action: String
    let organization_id: String
    let event_id: String?
    let title: String
    let event_type: String
    let description: String?
    let scheduled_start: String
    let scheduled_end: String
    let arrival_time: String?
    let timezone: String
    let location_name: String?
    let venue_address: String?
    let facility_id: String?
    let team_id: String?
    let opponent_name: String?
    let site: String
    let scheduled_innings: Int
  }

  private func canonicalEventMutationBody(
    action: String,
    organizationId: UUID,
    eventId: UUID?,
    draft: SDCanonicalEventDraft
  ) -> SDCanonicalEventMutationRequest {
    SDCanonicalEventMutationRequest(
      action: action,
      organization_id: organizationId.uuidString.lowercased(),
      event_id: eventId?.uuidString.lowercased(),
      title: draft.title,
      event_type: draft.eventType.rawValue,
      description: draft.description.sdNilIfBlank,
      scheduled_start: ISO8601DateFormatter().string(from: draft.start),
      scheduled_end: ISO8601DateFormatter().string(from: draft.end),
      arrival_time: draft.arrival.map { ISO8601DateFormatter().string(from: $0) },
      timezone: TimeZone.current.identifier,
      location_name: draft.locationName.sdNilIfBlank,
      venue_address: draft.venueAddress.sdNilIfBlank,
      facility_id: draft.facilityId?.uuidString.lowercased(),
      team_id: draft.teamId?.uuidString.lowercased(),
      opponent_name: draft.opponentName.sdNilIfBlank,
      site: draft.gameSite.rawValue,
      scheduled_innings: draft.scheduledInnings
    )
  }

  func listGames(organizationId: UUID, eventIds: [UUID]? = nil) async throws -> [SDGame] {
    var query = client.from("sd_games").select().eq("org_id", value: organizationId)
    if let eventIds, !eventIds.isEmpty {
      query = query.in("event_id", values: eventIds)
    }
    return try await query.execute().value
  }

  func fetchGame(id: UUID, organizationId: UUID) async throws -> SDGame {
    try await client
      .from("sd_games")
      .select()
      .eq("id", value: id)
      .eq("org_id", value: organizationId)
      .single()
      .execute()
      .value
  }

  func fetchGameForEvent(eventId: UUID, organizationId: UUID) async throws -> SDGame {
    try await client
      .from("sd_games")
      .select()
      .eq("event_id", value: eventId)
      .eq("org_id", value: organizationId)
      .single()
      .execute()
      .value
  }

  func createGame(_ request: SDCreateGameRequest) async throws -> SDGame {
    try await client.rpc("sd_create_game", params: request).single().execute().value
  }

  func listEventParticipants(eventId: UUID, organizationId: UUID) async throws -> [SDEventParticipant] {
    try await client
      .from("sd_event_participants")
      .select()
      .eq("event_id", value: eventId)
      .eq("org_id", value: organizationId)
      .execute()
      .value
  }

  func listEventAttendance(eventId: UUID, organizationId: UUID) async throws -> [SDEventAttendance] {
    try await client
      .from("sd_event_attendance")
      .select()
      .eq("event_id", value: eventId)
      .eq("org_id", value: organizationId)
      .execute()
      .value
  }

  func listGameAttendanceRoster(
    eventIds: [UUID],
    organizationId: UUID
  ) async throws -> [SDGameAttendanceRosterRow] {
    guard !eventIds.isEmpty else { return [] }
    struct Params: Encodable {
      let p_org_id: UUID
      let p_event_ids: [UUID]
    }
    return try await client
      .rpc(
        "sd_game_attendance_roster",
        params: Params(p_org_id: organizationId, p_event_ids: eventIds)
      )
      .execute()
      .value
  }

  func setExpectedGameAttendance(
    eventId: UUID,
    organizationId: UUID,
    playerId: UUID,
    attending: Bool
  ) async throws -> SDEventAttendance {
    struct Upsert: Encodable {
      let org_id: UUID
      let event_id: UUID
      let player_id: UUID
      let availability: String
      let expected_attendance: Bool
      let response_author_id: UUID
      let responded_at: Date
    }

    return try await client
      .from("sd_event_attendance")
      .upsert(
        Upsert(
          org_id: organizationId,
          event_id: eventId,
          player_id: playerId,
          availability: attending ? "available" : "unavailable",
          expected_attendance: attending,
          response_author_id: playerId,
          responded_at: Date()
        ),
        onConflict: "event_id,player_id"
      )
      .select()
      .single()
      .execute()
      .value
  }

  func listScoringEvents(gameId: UUID, organizationId: UUID) async throws -> [SDScoringEvent] {
    try await client.from("sd_game_scoring_events").select()
      .eq("game_id", value: gameId).eq("org_id", value: organizationId)
      .order("sequence", ascending: true).execute().value
  }

  func appendScoringEvent(
    game: SDGame,
    scoringEventId: UUID,
    expectedVersion: Int,
    type: SDScoringEventType,
    deviceId: UUID,
    controlToken: String,
    payload: [String: SDJSONValue],
    idempotencyKey: String
  ) async throws -> SDScoringEvent {
    struct Parameters: Encodable {
      let p_game_id: UUID
      let p_canonical_event_id: UUID
      let p_scoring_event_id: UUID
      let p_expected_version: Int
      let p_event_type: String
      let p_actor_device_id: UUID
      let p_control_token: String
      let p_payload: [String: SDJSONValue]
      let p_idempotency_key: String
    }
    return try await client.rpc("sd_append_game_scoring_event", params: Parameters(
      p_game_id: game.id, p_canonical_event_id: game.event_id,
      p_scoring_event_id: scoringEventId, p_expected_version: expectedVersion,
      p_event_type: type.rawValue, p_actor_device_id: deviceId,
      p_control_token: controlToken,
      p_payload: payload, p_idempotency_key: idempotencyKey
    )).single().execute().value
  }

  func appendNativeScoringCommand(_ command: SDNativeScoringCommand, controlToken: String) async throws -> [SDScoringEvent] {
    struct Parameters: Encodable {
      let p_game_id: UUID; let p_canonical_event_id: UUID; let p_expected_version: Int
      let p_actor_device_id: UUID; let p_control_token: String; let p_command_id: UUID
      let p_events: [SDNativeScoringCommand.Event]
    }
    return try await client.rpc("sd_append_native_scoring_command", params: Parameters(
      p_game_id: command.gameId, p_canonical_event_id: command.canonicalEventId,
      p_expected_version: command.expectedVersion, p_actor_device_id: command.deviceId,
      p_control_token: controlToken, p_command_id: command.id, p_events: command.events
    )).execute().value
  }

  func acquireScorekeepingControl(
    gameId: UUID, deviceId: UUID, sessionId: String
  ) async throws -> SDScorekeeperLease {
    struct P: Encodable { let p_game_id: UUID; let p_device_id: UUID; let p_authenticated_session_id: String }
    return try await client.rpc("sd_acquire_scorekeeping_control", params: P(
      p_game_id: gameId, p_device_id: deviceId, p_authenticated_session_id: sessionId
    )).single().execute().value
  }

  func renewScorekeepingControl(gameId: UUID, deviceId: UUID, token: String) async throws -> Bool {
    struct P: Encodable { let p_game_id: UUID; let p_device_id: UUID; let p_control_token: String }
    return try await client.rpc("sd_renew_scorekeeping_control", params: P(
      p_game_id: gameId, p_device_id: deviceId, p_control_token: token
    )).single().execute().value
  }

  func releaseScorekeepingControl(gameId: UUID, deviceId: UUID, token: String) async throws {
    struct P: Encodable { let p_game_id: UUID; let p_device_id: UUID; let p_control_token: String }
    _ = try await client.rpc("sd_release_scorekeeping_control", params: P(
      p_game_id: gameId, p_device_id: deviceId, p_control_token: token
    )).execute()
  }

  func requestScorekeepingControl(gameId: UUID, deviceId: UUID) async throws -> SDControlRequestLease {
    struct P: Encodable { let p_game_id: UUID; let p_device_id: UUID }
    return try await client.rpc("sd_request_scorekeeping_control", params: P(
      p_game_id: gameId, p_device_id: deviceId
    )).single().execute().value
  }

  func resolveScorekeepingControlRequest(
    requestId: UUID, approve: Bool, activeDeviceId: UUID, token: String
  ) async throws -> Bool {
    struct P: Encodable {
      let p_request_id: UUID
      let p_approve: Bool
      let p_active_device_id: UUID
      let p_control_token: String
    }
    return try await client.rpc("sd_resolve_scorekeeping_control_request", params: P(
      p_request_id: requestId, p_approve: approve,
      p_active_device_id: activeDeviceId, p_control_token: token
    )).single().execute().value
  }

  func markGameLiveDevice(gameId: UUID, deviceId: UUID, state: SDLiveDeviceState) async throws {
    struct P: Encodable { let p_game_id: UUID; let p_device_id: UUID; let p_state: String }
    _ = try await client.rpc("sd_mark_game_live_device", params: P(
      p_game_id: gameId, p_device_id: deviceId, p_state: state.rawValue
    )).execute()
  }

  func forceScorekeepingTakeover(
    gameId: UUID, deviceId: UUID, sessionId: String
  ) async throws -> SDScorekeeperLease {
    struct P: Encodable { let p_game_id: UUID; let p_device_id: UUID; let p_authenticated_session_id: String }
    return try await client.rpc("sd_force_scorekeeping_takeover", params: P(
      p_game_id: gameId, p_device_id: deviceId, p_authenticated_session_id: sessionId
    )).single().execute().value
  }

  func listGameScoringDecisions(gameId: UUID, organizationId: UUID) async throws -> [SDGameScoringDecision] {
    try await client.from("sd_game_scoring_decisions").select()
      .eq("game_id", value: gameId).eq("org_id", value: organizationId)
      .order("created_at", ascending: true).execute().value
  }

  func appendGameScoringDecision(
    gameId: UUID,
    physicalEventId: UUID,
    rootDecisionId: UUID,
    supersedesDecisionId: UUID?,
    type: String,
    preliminaryValue: String?,
    finalValue: String?,
    status: String,
    ruleReference: String?,
    reasoningNote: String?,
    reviewRequested: Bool
  ) async throws -> SDGameScoringDecision {
    struct P: Encodable {
      let p_game_id: UUID
      let p_physical_event_id: UUID
      let p_root_decision_id: UUID
      let p_supersedes_decision_id: UUID?
      let p_decision_type: String
      let p_preliminary_value: String?
      let p_final_value: String?
      let p_decision_status: String
      let p_rule_reference: String?
      let p_reasoning_note: String?
      let p_review_requested: Bool
    }
    return try await client.rpc("sd_append_game_scoring_decision", params: P(
      p_game_id: gameId, p_physical_event_id: physicalEventId,
      p_root_decision_id: rootDecisionId, p_supersedes_decision_id: supersedesDecisionId,
      p_decision_type: type, p_preliminary_value: preliminaryValue,
      p_final_value: finalValue, p_decision_status: status,
      p_rule_reference: ruleReference, p_reasoning_note: reasoningNote,
      p_review_requested: reviewRequested
    )).single().execute().value
  }

  func finalizeGame(
    gameId: UUID,
    expectedVersion: Int,
    deviceId: UUID,
    controlToken: String,
    idempotencyKey: String,
    statistics: SDOfficialGameStatistics,
    validation: SDGameValidationReport
  ) async throws -> SDGameFinalization {
    struct P: Encodable {
      let p_game_id: UUID
      let p_expected_version: Int
      let p_actor_device_id: UUID
      let p_control_token: String
      let p_idempotency_key: String
      let p_statistics: [String: SDJSONValue]
      let p_validation: [String: SDJSONValue]
    }
    return try await client.rpc("sd_finalize_game", params: P(
      p_game_id: gameId, p_expected_version: expectedVersion,
      p_actor_device_id: deviceId, p_control_token: controlToken,
      p_idempotency_key: idempotencyKey,
      p_statistics: statistics.persistenceJSON, p_validation: validation.json
    )).single().execute().value
  }

  func listGameAudit(gameId: UUID, organizationId: UUID) async throws -> [SDGameAuditEntry] {
    try await client.from("sd_game_audit_log").select()
      .eq("game_id", value: gameId).eq("org_id", value: organizationId)
      .order("created_at", ascending: true).execute().value
  }

  func correctFinalGameDecision(
    gameId: UUID,
    supersededDecisionId: UUID,
    replacementValue: String,
    reason: String,
    idempotencyKey: String,
    statistics: SDOfficialGameStatistics,
    validation: SDGameValidationReport
  ) async throws -> SDGameCorrection {
    struct P: Encodable {
      let p_game_id: UUID
      let p_superseded_decision_id: UUID
      let p_replacement_value: String
      let p_reason: String
      let p_idempotency_key: String
      let p_statistics: [String: SDJSONValue]
      let p_validation: [String: SDJSONValue]
    }
    return try await client.rpc("sd_correct_final_game_decision", params: P(
      p_game_id: gameId, p_superseded_decision_id: supersededDecisionId,
      p_replacement_value: replacementValue, p_reason: reason,
      p_idempotency_key: idempotencyKey,
      p_statistics: statistics.persistenceJSON, p_validation: validation.json
    )).single().execute().value
  }
}
