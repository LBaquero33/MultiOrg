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
}
