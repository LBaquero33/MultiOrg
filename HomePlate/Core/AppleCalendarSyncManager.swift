#if os(iOS)
import EventKit
import Foundation

@MainActor
final class AppleCalendarSyncManager: ObservableObject {
  static let shared = AppleCalendarSyncManager()

  @Published private(set) var statusText = "Not synchronized"
  @Published private(set) var hasExternalChanges = false

  private struct Link: Codable {
    let organizationId: UUID
    let source: AppleCalendarSyncSource
    let sourceId: UUID
    var eventIdentifier: String
    var baseline: String
  }

  private let eventStore = EKEventStore()
  private let defaultsKey = "homeplate.apple-calendar-links.v1"

  private init() {
    NotificationCenter.default.addObserver(
      forName: .EKEventStoreChanged,
      object: eventStore,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor in
        self?.hasExternalChanges = true
        self?.statusText = "Calendar changes ready to synchronize"
      }
    }
  }

  var hasFullAccess: Bool {
    if #available(iOS 17.0, *) {
      return EKEventStore.authorizationStatus(for: .event) == .fullAccess
    }
    return EKEventStore.authorizationStatus(for: .event) == .authorized
  }

  func requestAccess() async throws -> Bool {
    if #available(iOS 17.0, *) {
      return try await eventStore.requestFullAccessToEvents()
    }
    return try await withCheckedThrowingContinuation { continuation in
      eventStore.requestAccess(to: .event) { granted, error in
        if let error { continuation.resume(throwing: error) }
        else { continuation.resume(returning: granted) }
      }
    }
  }

  func pendingEventEdits(
    events: [SDTeamEvent],
    organizationId: UUID,
    canEdit: (SDTeamEvent) -> Bool
  ) -> [AppleCalendarEventEdit] {
    let links = loadLinks()
    let eventsById = Dictionary(uniqueKeysWithValues: events.map { ($0.id, $0) })
    return links.compactMap { _, link in
      guard link.organizationId == organizationId,
            link.source == .event,
            let source = eventsById[link.sourceId],
            AppleCalendarSyncPolicy.allowsInboundEdit(
              source: link.source,
              canEditHomePlateEvent: canEdit(source)
            ),
            let calendarEvent = eventStore.event(withIdentifier: link.eventIdentifier),
            fingerprint(calendarEvent) != link.baseline else { return nil }
      return AppleCalendarEventEdit(
        eventId: source.id,
        title: calendarEvent.title ?? source.title,
        startAt: calendarEvent.startDate,
        endAt: calendarEvent.endDate,
        location: calendarEvent.location,
        notes: calendarEvent.notes
      )
    }
  }

  func synchronize(
    events: [SDTeamEvent],
    bookings: [SDFacilityBooking],
    organizationId: UUID,
    facilityName: (UUID) -> String
  ) async throws {
    guard try await requestAccess() else {
      statusText = "Calendar access is off"
      throw AppleCalendarSyncError.accessDenied
    }
    let calendar = try calendarForHomePlate()
    var links = loadLinks()

    for source in events {
      let key = linkKey(organizationId: organizationId, source: .event, sourceId: source.id)
      if AppleCalendarSyncPolicy.shouldMirrorEvent(status: source.status) {
        let calendarEvent = eventStore.event(withIdentifier: links[key]?.eventIdentifier ?? "") ?? EKEvent(eventStore: eventStore)
        calendarEvent.calendar = calendar
        calendarEvent.title = source.title
        calendarEvent.startDate = source.startDate
        calendarEvent.endDate = source.endDate
        calendarEvent.location = source.address ?? source.location_name
        calendarEvent.notes = source.description ?? source.notes
        calendarEvent.url = sourceURL(organizationId: organizationId, source: .event, sourceId: source.id)
        try eventStore.save(calendarEvent, span: .thisEvent, commit: false)
        links[key] = Link(
          organizationId: organizationId,
          source: .event,
          sourceId: source.id,
          eventIdentifier: calendarEvent.eventIdentifier,
          baseline: fingerprint(calendarEvent)
        )
      } else {
        try removeLinkedEvent(key: key, links: &links)
      }
    }

    for source in bookings {
      let key = linkKey(organizationId: organizationId, source: .booking, sourceId: source.id)
      if AppleCalendarSyncPolicy.shouldMirrorBooking(status: source.status) {
        let calendarEvent = eventStore.event(withIdentifier: links[key]?.eventIdentifier ?? "") ?? EKEvent(eventStore: eventStore)
        calendarEvent.calendar = calendar
        calendarEvent.title = source.title?.isEmpty == false ? source.title : source.activity_type.capitalized
        calendarEvent.startDate = source.start_at
        calendarEvent.endDate = source.end_at
        calendarEvent.location = facilityName(source.facility_id)
        calendarEvent.notes = source.notes
        calendarEvent.url = sourceURL(organizationId: organizationId, source: .booking, sourceId: source.id)
        try eventStore.save(calendarEvent, span: .thisEvent, commit: false)
        links[key] = Link(
          organizationId: organizationId,
          source: .booking,
          sourceId: source.id,
          eventIdentifier: calendarEvent.eventIdentifier,
          baseline: fingerprint(calendarEvent)
        )
      } else {
        try removeLinkedEvent(key: key, links: &links)
      }
    }

    try eventStore.commit()
    saveLinks(links)
    hasExternalChanges = false
    statusText = "Synchronized with Apple Calendar"
  }

  private func calendarForHomePlate() throws -> EKCalendar {
    if let existing = eventStore.calendars(for: .event).first(where: { $0.title == "Home Plate" && $0.allowsContentModifications }) {
      return existing
    }
    guard let source = eventStore.defaultCalendarForNewEvents?.source
      ?? eventStore.sources.first(where: { $0.sourceType == .calDAV })
      ?? eventStore.sources.first(where: { $0.sourceType == .local }) else {
      throw AppleCalendarSyncError.noWritableCalendar
    }
    let calendar = EKCalendar(for: .event, eventStore: eventStore)
    calendar.title = "Home Plate"
    calendar.source = source
    try eventStore.saveCalendar(calendar, commit: true)
    return calendar
  }

  private func removeLinkedEvent(key: String, links: inout [String: Link]) throws {
    guard let link = links.removeValue(forKey: key),
          let event = eventStore.event(withIdentifier: link.eventIdentifier) else { return }
    try eventStore.remove(event, span: .thisEvent, commit: false)
  }

  private func sourceURL(organizationId: UUID, source: AppleCalendarSyncSource, sourceId: UUID) -> URL? {
    URL(string: "homeplate://calendar/\(source.rawValue)/\(sourceId.uuidString.lowercased())?organization=\(organizationId.uuidString.lowercased())")
  }

  private func fingerprint(_ event: EKEvent) -> String {
    [
      event.title ?? "",
      String(event.startDate.timeIntervalSince1970),
      String(event.endDate.timeIntervalSince1970),
      event.location ?? "",
      event.notes ?? "",
    ].joined(separator: "|")
  }

  private func linkKey(organizationId: UUID, source: AppleCalendarSyncSource, sourceId: UUID) -> String {
    "\(organizationId.uuidString.lowercased()):\(source.rawValue):\(sourceId.uuidString.lowercased())"
  }

  private func loadLinks() -> [String: Link] {
    guard let data = UserDefaults.standard.data(forKey: defaultsKey),
          let value = try? JSONDecoder().decode([String: Link].self, from: data) else { return [:] }
    return value
  }

  private func saveLinks(_ links: [String: Link]) {
    guard let data = try? JSONEncoder().encode(links) else { return }
    UserDefaults.standard.set(data, forKey: defaultsKey)
  }
}

enum AppleCalendarSyncError: LocalizedError {
  case accessDenied
  case noWritableCalendar

  var errorDescription: String? {
    switch self {
    case .accessDenied: "Allow Calendar access in Settings to synchronize Home Plate."
    case .noWritableCalendar: "No writable Apple Calendar is available on this device."
    }
  }
}
#endif
