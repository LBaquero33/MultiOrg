import XCTest
@testable import MultiOrg

final class GameFoundationTests: XCTestCase {
  func testLifecycleRetainsCanonicalIdentityAcrossScheduleStates() {
    let eventId = UUID()
    let gameId = UUID()
    XCTAssertNotEqual(eventId, gameId)
    XCTAssertEqual(SDGameLifecycle.postponed.rawValue, "postponed")
    XCTAssertEqual(SDGameLifecycle.suspended.rawValue, "suspended")
    XCTAssertEqual(SDGameLifecycle.noContest.rawValue, "no_contest")
  }

  func testCrossOrganizationCalendarItemIsRejectedLocallyBeforeRouting() {
    let active = UUID()
    let event = SDCanonicalEvent(
      id: UUID(), org_id: UUID(), title: "Game", event_type: .game,
      description: nil, scheduled_start: Date(), scheduled_end: Date().addingTimeInterval(3600),
      arrival_time: nil, timezone: "America/New_York", location_name: nil,
      venue_address: nil, facility_id: nil, facility_booking_id: nil, team_id: nil,
      visibility: .team, status: .scheduled, recurrence: [:], created_by: UUID(),
      updated_by: UUID(), created_at: nil, updated_at: nil, canceled_at: nil, postponed_at: nil
    )
    XCTAssertFalse(SDGameAuthorization.canOpen(item: .init(event: event, game: nil), activeOrganizationId: active))
  }
}
