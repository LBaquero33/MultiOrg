import Foundation

enum AppleCalendarSyncSource: String, Codable, Sendable {
  case event
  case booking
}

struct AppleCalendarEventEdit: Equatable, Sendable {
  let eventId: UUID
  let title: String
  let startAt: Date
  let endAt: Date
  let location: String?
  let notes: String?
}

enum AppleCalendarSyncPolicy {
  static func allowsInboundEdit(source: AppleCalendarSyncSource, canEditHomePlateEvent: Bool) -> Bool {
    source == .event && canEditHomePlateEvent
  }

  static func shouldMirrorBooking(status: String) -> Bool {
    status.lowercased() == "approved"
  }

  static func shouldMirrorEvent(status: SDTeamEventStatus) -> Bool {
    status == .scheduled || status == .confirmed
  }
}
