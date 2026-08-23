import Foundation
import Testing
@testable import HomePlate

@Suite("Apple Calendar synchronization policy")
struct AppleCalendarSyncPolicyTests {
  @Test("bookings mirror only after approval and never accept inbound edits")
  func bookingPolicy() {
    #expect(AppleCalendarSyncPolicy.shouldMirrorBooking(status: "approved"))
    #expect(!AppleCalendarSyncPolicy.shouldMirrorBooking(status: "pending"))
    #expect(!AppleCalendarSyncPolicy.shouldMirrorBooking(status: "denied"))
    #expect(!AppleCalendarSyncPolicy.allowsInboundEdit(source: .booking, canEditHomePlateEvent: true))
  }

  @Test("only authorized event edits can flow back to Home Plate")
  func eventPolicy() {
    #expect(AppleCalendarSyncPolicy.allowsInboundEdit(source: .event, canEditHomePlateEvent: true))
    #expect(!AppleCalendarSyncPolicy.allowsInboundEdit(source: .event, canEditHomePlateEvent: false))
    #expect(AppleCalendarSyncPolicy.shouldMirrorEvent(status: .scheduled))
    #expect(AppleCalendarSyncPolicy.shouldMirrorEvent(status: .confirmed))
    #expect(!AppleCalendarSyncPolicy.shouldMirrorEvent(status: .cancelled))
  }
}
