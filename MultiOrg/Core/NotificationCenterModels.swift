import Foundation

enum SDNotificationPreferenceRule {
  static func delivery(
    inAppEnabled: Bool,
    pushEnabled: Bool,
    required: Bool,
    localMinutes: Int,
    quietStartMinutes: Int?,
    quietEndMinutes: Int?
  ) -> (inApp: Bool, push: Bool) {
    let quiet: Bool
    if let start = quietStartMinutes, let end = quietEndMinutes {
      quiet = start < end
        ? localMinutes >= start && localMinutes < end
        : localMinutes >= start || localMinutes < end
    } else {
      quiet = false
    }
    return (required || inAppEnabled, pushEnabled && !quiet)
  }
}

struct SDNotificationDeliveryStatus: Identifiable, Decodable, Equatable, Sendable {
  let id: UUID
  let source_type: String
  let source_id: UUID
  let category: String
  let delivery_state: String
  let preference_decision: String
  let failure_reason: String?
  let attempt_count: Int
  let next_attempt_at: String?
  let delivered_at: String?
  let created_at: String
}

struct SDNotificationDeliveryStatusResponse: Decodable, Sendable {
  let deliveries: [SDNotificationDeliveryStatus]
}

struct SDNotificationPreference: Decodable, Equatable, Sendable {
  let id: UUID
  let user_id: UUID
  let organization_id: UUID?
  let team_id: UUID?
  let subject_player_id: UUID?
  let category: String
  let in_app_enabled: Bool
  let push_enabled: Bool
  let email_ready_enabled: Bool
  let sms_ready_enabled: Bool
  let quiet_hours_start: String?
  let quiet_hours_end: String?
  let timezone: String
  let version: Int
}

struct SDNotificationPreferenceResponse: Decodable, Sendable {
  let preference: SDNotificationPreference
}

struct SDNotificationPreferencesResponse: Decodable, Sendable {
  let preferences: [SDNotificationPreference]
}

struct SDCommunicationAnnouncement: Identifiable, Decodable, Equatable, Sendable {
  let id: UUID
  let organization_id: UUID
  let title: String
  let body: String
  let audience_type: String
  let priority: String
  let acknowledgment_required: Bool
  let status: String
  let publish_at: String
  let expires_at: String?
}

struct SDCommunicationAnnouncementRecipient: Decodable, Equatable, Sendable {
  let read_at: String?
  let acknowledged_at: String?
  let archived_at: String?
  let announcement: SDCommunicationAnnouncement
}

struct SDCommunicationAnnouncementsResponse: Decodable, Sendable {
  let announcements: [SDCommunicationAnnouncementRecipient]
}

enum AppNotificationCategory: Codable, Equatable, Hashable, Sendable {
  case paymentRequestCreated
  case paymentReceived
  case bookingCreated
  case bookingUpdated
  case programAssigned
  case programUpdated
  case messageReceived
  case testingResultAdded
  case organizationAnnouncement
  case teamAnnouncement
  case eventAnnouncement
  case scheduleChange
  case eventReminder
  case attendance
  case availability
  case practicePlan
  case gamePlan
  case lineupAssignment
  case registration
  case paymentNotice
  case resultRecap
  case system
  case unknown(String)

  init(from decoder: Decoder) throws {
    let raw = try decoder.singleValueContainer().decode(String.self)
    self = switch raw {
    case "payment_request_created": .paymentRequestCreated
    case "payment_received": .paymentReceived
    case "booking_created": .bookingCreated
    case "booking_updated": .bookingUpdated
    case "program_assigned": .programAssigned
    case "program_updated": .programUpdated
    case "message_received": .messageReceived
    case "testing_result_added": .testingResultAdded
    case "organization_announcement": .organizationAnnouncement
    case "team_announcement": .teamAnnouncement
    case "event_announcement": .eventAnnouncement
    case "schedule_change": .scheduleChange
    case "event_reminder": .eventReminder
    case "attendance": .attendance
    case "availability": .availability
    case "practice_plan": .practicePlan
    case "game_plan": .gamePlan
    case "lineup_assignment": .lineupAssignment
    case "registration": .registration
    case "payment_notice": .paymentNotice
    case "result_recap": .resultRecap
    case "system": .system
    default: .unknown(raw)
    }
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }

  var rawValue: String {
    switch self {
    case .paymentRequestCreated: "payment_request_created"
    case .paymentReceived: "payment_received"
    case .bookingCreated: "booking_created"
    case .bookingUpdated: "booking_updated"
    case .programAssigned: "program_assigned"
    case .programUpdated: "program_updated"
    case .messageReceived: "message_received"
    case .testingResultAdded: "testing_result_added"
    case .organizationAnnouncement: "organization_announcement"
    case .teamAnnouncement: "team_announcement"
    case .eventAnnouncement: "event_announcement"
    case .scheduleChange: "schedule_change"
    case .eventReminder: "event_reminder"
    case .attendance: "attendance"
    case .availability: "availability"
    case .practicePlan: "practice_plan"
    case .gamePlan: "game_plan"
    case .lineupAssignment: "lineup_assignment"
    case .registration: "registration"
    case .paymentNotice: "payment_notice"
    case .resultRecap: "result_recap"
    case .system: "system"
    case .unknown(let value): value
    }
  }

  var systemImage: String {
    switch self {
    case .paymentRequestCreated: "dollarsign.circle"
    case .paymentReceived: "checkmark.circle.fill"
    case .bookingCreated, .bookingUpdated: "calendar"
    case .programAssigned, .programUpdated: "list.clipboard"
    case .messageReceived: "bubble.left.fill"
    case .testingResultAdded: "chart.bar.doc.horizontal"
    case .organizationAnnouncement: "megaphone.fill"
    case .teamAnnouncement, .eventAnnouncement: "megaphone"
    case .scheduleChange, .eventReminder: "calendar.badge.clock"
    case .attendance, .availability: "person.badge.clock"
    case .practicePlan: "figure.baseball"
    case .gamePlan, .lineupAssignment: "list.number"
    case .registration: "person.crop.circle.badge.plus"
    case .paymentNotice: "creditcard"
    case .resultRecap: "trophy"
    case .system, .unknown: "bell.fill"
    }
  }
}

enum AppNotificationRoute: Codable, Equatable, Hashable, Sendable {
  case paymentRequest
  case payment
  case finance
  case chatConversation
  case organizationAnnouncement
  case teamEvent
  case registration
  case notificationDetail
  case unknown(String)

  init(from decoder: Decoder) throws {
    let raw = try decoder.singleValueContainer().decode(String.self)
    self = switch raw {
    case "payment_request": .paymentRequest
    case "payment": .payment
    case "finance": .finance
    case "chat_conversation": .chatConversation
    case "organization_announcement": .organizationAnnouncement
    case "team_event": .teamEvent
    case "registration": .registration
    case "notification_detail": .notificationDetail
    default: .unknown(raw)
    }
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }

  var rawValue: String {
    switch self {
    case .paymentRequest: "payment_request"
    case .payment: "payment"
    case .finance: "finance"
    case .chatConversation: "chat_conversation"
    case .organizationAnnouncement: "organization_announcement"
    case .teamEvent: "team_event"
    case .registration: "registration"
    case .notificationDetail: "notification_detail"
    case .unknown(let value): value
    }
  }
}

struct NotificationActionPayload: Codable, Equatable, Sendable {
  let paymentRequestId: UUID?
  let paymentId: UUID?
  let announcementId: UUID?
  let organizationId: UUID?
  let conversationId: UUID?
  let messageId: UUID?
  let senderId: UUID?
  let eventId: UUID?
  let teamId: UUID?
  let applicationId: UUID?

  private enum CodingKeys: String, CodingKey {
    case paymentRequestId = "payment_request_id"
    case paymentId = "payment_id"
    case announcementId = "announcement_id"
    case organizationId = "organization_id"
    case conversationId = "conversation_id"
    case messageId = "message_id"
    case senderId = "sender_id"
    case eventId = "event_id"
    case teamId = "team_id"
    case applicationId = "application_id"
  }

  init(
    paymentRequestId: UUID? = nil,
    paymentId: UUID? = nil,
    announcementId: UUID? = nil,
    organizationId: UUID? = nil,
    conversationId: UUID? = nil,
    messageId: UUID? = nil,
    senderId: UUID? = nil,
    eventId: UUID? = nil,
    teamId: UUID? = nil,
    applicationId: UUID? = nil
  ) {
    self.paymentRequestId = paymentRequestId
    self.paymentId = paymentId
    self.announcementId = announcementId
    self.organizationId = organizationId
    self.conversationId = conversationId
    self.messageId = messageId
    self.senderId = senderId
    self.eventId = eventId
    self.teamId = teamId
    self.applicationId = applicationId
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    paymentRequestId = Self.uuid(container: container, key: .paymentRequestId)
    paymentId = Self.uuid(container: container, key: .paymentId)
    announcementId = Self.uuid(container: container, key: .announcementId)
    organizationId = Self.uuid(container: container, key: .organizationId)
    conversationId = Self.uuid(container: container, key: .conversationId)
    messageId = Self.uuid(container: container, key: .messageId)
    senderId = Self.uuid(container: container, key: .senderId)
    eventId = Self.uuid(container: container, key: .eventId)
    teamId = Self.uuid(container: container, key: .teamId)
    applicationId = Self.uuid(container: container, key: .applicationId)
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encodeIfPresent(paymentRequestId, forKey: .paymentRequestId)
    try container.encodeIfPresent(paymentId, forKey: .paymentId)
    try container.encodeIfPresent(announcementId, forKey: .announcementId)
    try container.encodeIfPresent(organizationId, forKey: .organizationId)
    try container.encodeIfPresent(conversationId, forKey: .conversationId)
    try container.encodeIfPresent(messageId, forKey: .messageId)
    try container.encodeIfPresent(senderId, forKey: .senderId)
    try container.encodeIfPresent(eventId, forKey: .eventId)
    try container.encodeIfPresent(teamId, forKey: .teamId)
    try container.encodeIfPresent(applicationId, forKey: .applicationId)
  }

  private static func uuid(
    container: KeyedDecodingContainer<CodingKeys>,
    key: CodingKeys
  ) -> UUID? {
    guard let raw = try? container.decodeIfPresent(String.self, forKey: key) else { return nil }
    return UUID(uuidString: raw)
  }
}

struct AppNotification: Identifiable, Decodable, Equatable, Sendable {
  let id: UUID
  let organizationId: UUID
  let organizationName: String
  let category: AppNotificationCategory
  let title: String
  let body: String
  let relatedEntityType: String?
  let relatedEntityId: String?
  let actionRoute: AppNotificationRoute?
  let actionPayload: NotificationActionPayload
  let createdAt: String
  let readAt: String?

  private enum CodingKeys: String, CodingKey {
    case id
    case organizationId = "org_id"
    case organizationName = "organization_name"
    case category, title, body
    case relatedEntityType = "related_entity_type"
    case relatedEntityId = "related_entity_id"
    case actionRoute = "action_route"
    case actionPayload = "action_payload"
    case createdAt = "created_at"
    case readAt = "read_at"
  }

  var isUnread: Bool { readAt == nil }

  var createdDate: Date? {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = formatter.date(from: createdAt) { return date }
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: createdAt)
  }

  func markingRead(at timestamp: String) -> AppNotification {
    AppNotification(
      id: id,
      organizationId: organizationId,
      organizationName: organizationName,
      category: category,
      title: title,
      body: body,
      relatedEntityType: relatedEntityType,
      relatedEntityId: relatedEntityId,
      actionRoute: actionRoute,
      actionPayload: actionPayload,
      createdAt: createdAt,
      readAt: readAt ?? timestamp
    )
  }
}

struct NotificationPagination: Decodable, Equatable, Sendable {
  let limit: Int
  let offset: Int
  let total: Int
  let hasMore: Bool

  private enum CodingKeys: String, CodingKey {
    case limit, offset, total
    case hasMore = "has_more"
  }
}

struct NotificationListResponse: Decodable, Equatable, Sendable {
  let notifications: [AppNotification]
  let pagination: NotificationPagination
}

struct NotificationUnreadCountResponse: Decodable, Equatable, Sendable {
  let totalUnread: Int
  let organizationId: UUID?
  let organizationUnread: Int?

  private enum CodingKeys: String, CodingKey {
    case totalUnread = "total_unread"
    case organizationId = "organization_id"
    case organizationUnread = "organization_unread"
  }
}

struct NotificationSingleResponse: Decodable, Equatable, Sendable {
  let notification: AppNotification
}

struct NotificationMarkAllResponse: Decodable, Equatable, Sendable {
  let updatedCount: Int
  let organizationId: UUID?

  private enum CodingKeys: String, CodingKey {
    case updatedCount = "updated_count"
    case organizationId = "organization_id"
  }
}

enum AnnouncementAudience: String, CaseIterable, Codable, Identifiable, Sendable {
  case all
  case players
  case parents
  case coaches
  case staff

  var id: String { rawValue }

  var title: String {
    switch self {
    case .all: "All Active Members"
    case .players: "Players"
    case .parents: "Parents"
    case .coaches: "Coaches"
    case .staff: "Staff / Admins"
    }
  }
}

enum NotificationAuthorizationSource: String, Decodable, Equatable, Sendable {
  case organizationMembership = "organization_membership"
  case platformSupport = "platform_support"
}

struct AnnouncementDraft: Equatable, Sendable {
  static let maximumTitleLength = 120
  static let maximumBodyLength = 2_000

  var title = ""
  var body = ""
  var audience = AnnouncementAudience.all

  var cleanedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }
  var cleanedBody: String { body.trimmingCharacters(in: .whitespacesAndNewlines) }

  var validationError: String? {
    guard !cleanedTitle.isEmpty, cleanedTitle.count <= Self.maximumTitleLength else {
      return "Enter a title up to \(Self.maximumTitleLength) characters."
    }
    guard !cleanedBody.isEmpty, cleanedBody.count <= Self.maximumBodyLength else {
      return "Enter a message up to \(Self.maximumBodyLength) characters."
    }
    return nil
  }

  var isValid: Bool { validationError == nil }
}

struct NotificationListRequest: Encodable, Equatable, Sendable {
  let action = "list"
  let org_id: String?
  let unread_only: Bool
  let limit: Int
  let offset: Int

  init(organizationId: UUID?, unreadOnly: Bool, limit: Int, offset: Int) {
    org_id = organizationId?.uuidString.lowercased()
    unread_only = unreadOnly
    self.limit = limit
    self.offset = offset
  }
}

struct NotificationUnreadCountRequest: Encodable, Equatable, Sendable {
  let action = "unread_count"
  let org_id: String?

  init(organizationId: UUID?) {
    org_id = organizationId?.uuidString.lowercased()
  }
}

struct NotificationMarkReadRequest: Encodable, Equatable, Sendable {
  let action = "mark_read"
  let notification_id: String

  init(notificationId: UUID) {
    notification_id = notificationId.uuidString.lowercased()
  }
}

struct NotificationGetRequest: Encodable, Equatable, Sendable {
  let action = "get"
  let notification_id: String

  init(notificationId: UUID) {
    notification_id = notificationId.uuidString.lowercased()
  }
}

struct NotificationMarkAllReadRequest: Encodable, Equatable, Sendable {
  let action = "mark_all_read"
  let org_id: String?

  init(organizationId: UUID?) {
    org_id = organizationId?.uuidString.lowercased()
  }
}

struct OrganizationAnnouncementRequest: Encodable, Equatable, Sendable {
  let action = "create_announcement"
  let org_id: String
  let title: String
  let body: String
  let audience: AnnouncementAudience
  let support_mode: Bool
  let idempotency_key: String

  init(
    organizationId: UUID,
    draft: AnnouncementDraft,
    supportMode: Bool,
    idempotencyKey: UUID
  ) {
    org_id = organizationId.uuidString.lowercased()
    title = draft.cleanedTitle
    body = draft.cleanedBody
    audience = draft.audience
    support_mode = supportMode
    idempotency_key = idempotencyKey.uuidString.lowercased()
  }
}

struct OrganizationAnnouncementResponse: Decodable, Equatable, Sendable {
  let announcementId: UUID
  let createdCount: Int
  let recipientCount: Int
  let reused: Bool
  let authorizationSource: NotificationAuthorizationSource

  private enum CodingKeys: String, CodingKey {
    case announcementId = "announcement_id"
    case createdCount = "created_count"
    case recipientCount = "recipient_count"
    case reused
    case authorizationSource = "authorization_source"
  }
}

struct AnnouncementOperationState: Equatable, Sendable {
  private(set) var idempotencyKey: UUID?
  private(set) var material: String?
  private(set) var isInFlight = false

  mutating func begin(
    organizationId: UUID,
    draft: AnnouncementDraft,
    supportMode: Bool,
    key: UUID = UUID()
  ) -> UUID? {
    guard !isInFlight else { return nil }
    let nextMaterial = [
      organizationId.uuidString.lowercased(),
      draft.cleanedTitle,
      draft.cleanedBody,
      draft.audience.rawValue,
      supportMode.description,
    ].joined(separator: "\u{1f}")
    if material != nextMaterial || idempotencyKey == nil {
      material = nextMaterial
      idempotencyKey = key
    }
    isInFlight = true
    return idempotencyKey
  }

  mutating func finish(success: Bool) {
    isInFlight = false
    if success {
      idempotencyKey = nil
      material = nil
    }
  }

  mutating func clear() {
    idempotencyKey = nil
    material = nil
    isInFlight = false
  }
}

enum NotificationDestination: Equatable, Sendable {
  case paymentRequest(UUID)
  case payment(paymentId: UUID?, paymentRequestId: UUID?)
  case finance(UUID)
  case chatConversation(conversationId: UUID, messageId: UUID)
  case announcement(UUID)
  case teamEvent(UUID)
  case registration(UUID?)
  case detail(UUID)
}

enum NotificationRouter {
  static func destination(for notification: AppNotification) -> NotificationDestination {
    switch notification.actionRoute {
    case .paymentRequest:
      guard let id = notification.actionPayload.paymentRequestId ??
        notification.relatedEntityId.flatMap(UUID.init(uuidString:)) else {
        return .detail(notification.id)
      }
      return .paymentRequest(id)
    case .payment:
      guard notification.actionPayload.paymentId != nil ||
        notification.actionPayload.paymentRequestId != nil else {
        return .detail(notification.id)
      }
      return .payment(
        paymentId: notification.actionPayload.paymentId,
        paymentRequestId: notification.actionPayload.paymentRequestId
      )
    case .finance:
      return .finance(notification.organizationId)
    case .chatConversation:
      guard let conversationId = notification.actionPayload.conversationId,
            let messageId = notification.actionPayload.messageId,
            notification.actionPayload.organizationId == nil ||
              notification.actionPayload.organizationId == notification.organizationId else {
        return .detail(notification.id)
      }
      return .chatConversation(conversationId: conversationId, messageId: messageId)
    case .organizationAnnouncement:
      guard let id = notification.actionPayload.announcementId ??
        notification.relatedEntityId.flatMap(UUID.init(uuidString:)) else {
        return .detail(notification.id)
      }
      return .announcement(id)
    case .teamEvent:
      guard let id = notification.actionPayload.eventId ??
        notification.relatedEntityId.flatMap(UUID.init(uuidString:)) else {
        return .detail(notification.id)
      }
      return .teamEvent(id)
    case .registration:
      return .registration(notification.actionPayload.applicationId)
    case .notificationDetail, .unknown, .none:
      return .detail(notification.id)
    }
  }
}
