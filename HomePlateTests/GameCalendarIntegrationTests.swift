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

  @Test func onlyActivePlayersCanRespondToGames() {
    let org = UUID()
    let player = UUID()
    let event = fixture(org: org).event
    let playerMembership = SDOrgMembership(
      org_id: org, user_id: player, role: "player", status: "active",
      created_at: nil, created_by: nil
    )
    let coachMembership = SDOrgMembership(
      org_id: org, user_id: player, role: "coach", status: "active",
      created_at: nil, created_by: nil
    )
    let inactiveMembership = SDOrgMembership(
      org_id: org, user_id: player, role: "player", status: "inactive",
      created_at: nil, created_by: nil
    )

    #expect(SDGameAttendanceAuthorization.canRespond(
      event: event, userId: player, membership: playerMembership
    ))
    #expect(!SDGameAttendanceAuthorization.canRespond(
      event: event, userId: player, membership: coachMembership
    ))
    #expect(!SDGameAttendanceAuthorization.canRespond(
      event: event, userId: player, membership: inactiveMembership
    ))
  }

  @Test func coachUpcomingEventsUseCanonicalScheduleAndTeamScope() {
    let org = UUID()
    let selectedTeam = UUID()
    let otherTeam = UUID()
    let now = Date()
    let organizationEvent = canonicalEvent(
      org: org,
      team: nil,
      start: now.addingTimeInterval(600)
    )
    let selectedTeamEvent = canonicalEvent(
      org: org,
      team: selectedTeam,
      start: now.addingTimeInterval(1_200)
    )
    let otherTeamEvent = canonicalEvent(
      org: org,
      team: otherTeam,
      start: now.addingTimeInterval(1_800)
    )
    let canceledEvent = canonicalEvent(
      org: org,
      team: selectedTeam,
      start: now.addingTimeInterval(2_400),
      status: .canceled
    )
    let pastEvent = canonicalEvent(
      org: org,
      team: selectedTeam,
      start: now.addingTimeInterval(-600)
    )

    let scoped = SDCoachUpcomingEventFilter.visibleEvents(
      from: [otherTeamEvent, canceledEvent, selectedTeamEvent, pastEvent, organizationEvent],
      now: now,
      selectedTeamId: selectedTeam
    )
    #expect(scoped.map(\.id) == [organizationEvent.id, selectedTeamEvent.id])

    let allTeams = SDCoachUpcomingEventFilter.visibleEvents(
      from: [otherTeamEvent, selectedTeamEvent, organizationEvent],
      now: now,
      selectedTeamId: nil
    )
    #expect(allTeams.map(\.id) == [organizationEvent.id, selectedTeamEvent.id, otherTeamEvent.id])
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


  private func canonicalEvent(
    org: UUID,
    team: UUID?,
    start: Date,
    status: SDGameLifecycle = .scheduled
  ) -> SDCanonicalEvent {
    SDCanonicalEvent(
      id: UUID(), org_id: org, title: "Event", event_type: .practice,
      description: nil, scheduled_start: start,
      scheduled_end: start.addingTimeInterval(3_600), arrival_time: nil,
      timezone: "America/New_York", location_name: nil,
      venue_address: nil, facility_id: nil, facility_booking_id: nil,
      team_id: team, visibility: team == nil ? .organization : .team, status: status,
      recurrence: [:], created_by: UUID(), updated_by: UUID(),
      created_at: start, updated_at: start,
      canceled_at: status == .canceled ? start : nil, postponed_at: nil
    )
  }
}
