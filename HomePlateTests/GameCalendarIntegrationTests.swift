import Foundation
import Testing
@testable import HomePlate

struct GameCalendarIntegrationTests {
  @Test func canonicalItemRejectsWrongOrganization() {
    let org = UUID()
    let item = fixture(org: org)
    #expect(SDGameAuthorization.canOpen(item: item, activeOrganizationId: org))
    #expect(!SDGameAuthorization.canOpen(item: item, activeOrganizationId: UUID()))
  }

  @Test func notificationRoutesCanonicalGame() throws {
    let game = UUID()
    let data = """
    {
      "game_id": "\(game.uuidString)",
      "organization_id": "\(UUID().uuidString)"
    }
    """.data(using: .utf8)!
    let payload = try JSONDecoder().decode(NotificationActionPayload.self, from: data)
    #expect(payload.gameId == game)
  }

  private func fixture(org: UUID) -> SDGameCalendarItem {
    let now = Date()
    return SDGameCalendarItem(
      event: SDCanonicalEvent(
        id: UUID(), org_id: org, title: "Game", event_type: .game,
        description: nil, scheduled_start: now,
        scheduled_end: now.addingTimeInterval(7_200), arrival_time: nil,
        timezone: "America/New_York", location_name: nil,
        venue_address: nil, facility_id: nil, facility_booking_id: nil,
        team_id: UUID(), visibility: .team, status: .scheduled,
        recurrence: [:], created_by: UUID(), updated_by: UUID(),
        created_at: now, updated_at: now, canceled_at: nil, postponed_at: nil
      ),
      game: nil
    )
  }
}
