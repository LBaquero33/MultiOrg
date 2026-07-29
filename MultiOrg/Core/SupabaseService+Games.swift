import Foundation
import Supabase

@MainActor
extension SupabaseService {
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
      let p_payload: [String: SDJSONValue]
      let p_idempotency_key: String
    }
    return try await client.rpc("sd_append_game_scoring_event", params: Parameters(
      p_game_id: game.id, p_canonical_event_id: game.event_id,
      p_scoring_event_id: scoringEventId, p_expected_version: expectedVersion,
      p_event_type: type.rawValue, p_actor_device_id: deviceId,
      p_payload: payload, p_idempotency_key: idempotencyKey
    )).single().execute().value
  }
}
