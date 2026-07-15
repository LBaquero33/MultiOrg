import Foundation
import Testing
@testable import MultiOrg

@Suite("Notification center foundation")
struct NotificationCenterTests {
  private let userId = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
  private let orgId = UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")!
  private let otherOrgId = UUID(uuidString: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb")!

  @Test("Exact notification JSON decodes and omits internal fields")
  func exactContractDecodes() throws {
    let response = try JSONDecoder().decode(
      NotificationListResponse.self,
      from: Data(listJSON(category: "payment_request_created", route: "payment_request").utf8)
    )
    let notification = try #require(response.notifications.first)
    #expect(notification.organizationId == orgId)
    #expect(notification.category == .paymentRequestCreated)
    #expect(notification.actionPayload.paymentRequestId == UUID(uuidString: "cccccccc-cccc-4ccc-8ccc-cccccccccccc"))
    #expect(response.pagination.hasMore == false)
  }

  @Test("Unknown categories decode without losing the raw value")
  func unknownCategoryDecodes() throws {
    let response = try JSONDecoder().decode(
      NotificationListResponse.self,
      from: Data(listJSON(category: "future_category", route: "notification_detail").utf8)
    )
    #expect(response.notifications.first?.category == .unknown("future_category"))
  }

  @Test("Unknown and malformed routes fall back to notification detail")
  func unknownRouteFallsBack() throws {
    let unknown = try decodeNotification(category: "system", route: "future_route")
    #expect(NotificationRouter.destination(for: unknown) == .detail(unknown.id))

    let malformed = try decodeNotification(
      category: "payment_request_created",
      route: "payment_request",
      payload: "{\"payment_request_id\":\"not-a-uuid\"}",
      relatedEntityId: "also-not-a-uuid"
    )
    #expect(NotificationRouter.destination(for: malformed) == .detail(malformed.id))
  }

  @Test("Inbox requests do not send recipients, actors, or authority claims")
  func inboxRequestExcludesServerAuthority() throws {
    let requests: [any Encodable] = [
      NotificationListRequest(organizationId: orgId, unreadOnly: true, limit: 20, offset: 0),
      NotificationUnreadCountRequest(organizationId: orgId),
      NotificationMarkReadRequest(notificationId: UUID()),
      NotificationMarkAllReadRequest(organizationId: orgId),
    ]
    for request in requests {
      let encoded = try JSONEncoder().encode(AnyEncodable(request))
      let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
      #expect(object["recipient_user_id"] == nil)
      #expect(object["actor_id"] == nil)
      #expect(object["is_platform_admin"] == nil)
      #expect(object["read_at"] == nil)
    }
  }

  @Test("Announcement request sends business input and explicit support context only")
  func announcementRequestContract() throws {
    var draft = AnnouncementDraft()
    draft.title = " Schedule "
    draft.body = " Updated details "
    draft.audience = .players
    let request = OrganizationAnnouncementRequest(
      organizationId: orgId,
      draft: draft,
      supportMode: true,
      idempotencyKey: UUID(uuidString: "99999999-9999-4999-8999-999999999999")!
    )
    let object = try #require(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any]
    )
    #expect(object["title"] as? String == "Schedule")
    #expect(object["body"] as? String == "Updated details")
    #expect(object["audience"] as? String == "players")
    #expect(object["support_mode"] as? Bool == true)
    #expect(object["actor_id"] == nil)
    #expect(object["recipient_user_ids"] == nil)
    #expect(object["authorization_source"] == nil)
  }

  @Test("Announcement validation enforces bounded nonempty content")
  func announcementValidation() {
    var draft = AnnouncementDraft()
    #expect(!draft.isValid)
    draft.title = "Practice"
    draft.body = "Starts at six."
    #expect(draft.isValid)
    draft.title = String(repeating: "t", count: 121)
    #expect(!draft.isValid)
    draft.title = "Practice"
    draft.body = String(repeating: "b", count: 2_001)
    #expect(!draft.isValid)
  }

  @Test("Announcement retry keeps its key and changed material rotates it")
  func announcementIdempotency() throws {
    var draft = AnnouncementDraft()
    draft.title = "Practice"
    draft.body = "Starts at six."
    var state = AnnouncementOperationState()
    let firstKey = UUID(uuidString: "99999999-9999-4999-8999-999999999991")!
    let retryKey = UUID(uuidString: "99999999-9999-4999-8999-999999999992")!
    #expect(state.begin(organizationId: orgId, draft: draft, supportMode: false, key: firstKey) == firstKey)
    #expect(state.begin(organizationId: orgId, draft: draft, supportMode: false, key: retryKey) == nil)
    state.finish(success: false)
    #expect(state.begin(organizationId: orgId, draft: draft, supportMode: false, key: retryKey) == firstKey)
    state.finish(success: false)
    draft.body = "Starts at seven."
    #expect(state.begin(organizationId: orgId, draft: draft, supportMode: false, key: retryKey) == retryKey)
    state.finish(success: true)
  }

  @Test("User switching clears notifications and badge state")
  @MainActor
  func userSwitchClearsState() async {
    let service = MockNotificationCenterService(orgId: orgId)
    let viewModel = NotificationCenterViewModel()
    viewModel.resetForUser(userId)
    await viewModel.refresh(organizationId: nil, service: service)
    #expect(viewModel.notifications.count == 1)
    #expect(viewModel.totalUnread == 1)
    viewModel.resetForUser(UUID())
    #expect(viewModel.notifications.isEmpty)
    #expect(viewModel.totalUnread == 0)
  }

  @Test("Opening notification marks it read once and decrements the badge")
  @MainActor
  func openingMarksRead() async throws {
    let service = MockNotificationCenterService(orgId: orgId)
    let viewModel = NotificationCenterViewModel()
    viewModel.resetForUser(userId)
    await viewModel.refresh(organizationId: nil, service: service)
    let notification = try #require(viewModel.notifications.first)
    #expect(await viewModel.markRead(notification, service: service))
    #expect(viewModel.notifications.first?.isUnread == false)
    #expect(viewModel.totalUnread == 0)
    #expect(await viewModel.markRead(try #require(viewModel.notifications.first), service: service))
    #expect(service.markReadCalls == 1)
  }

  @Test("Organization switching rejects a stale notification response")
  @MainActor
  func staleOrganizationResponseIsIgnored() async throws {
    let service = MockNotificationCenterService(orgId: orgId)
    service.slowOrganizationId = orgId
    let viewModel = NotificationCenterViewModel()
    viewModel.resetForUser(userId)
    let oldRequest = Task { @MainActor in
      await viewModel.refresh(organizationId: self.orgId, service: service)
    }
    try await Task.sleep(nanoseconds: 10_000_000)
    await viewModel.refresh(organizationId: otherOrgId, service: service)
    await oldRequest.value
    #expect(viewModel.notifications.first?.organizationId == otherOrgId)
  }

  @Test("Announcement submission prevents concurrent double send")
  @MainActor
  func doubleSendIsPrevented() async throws {
    let service = MockNotificationCenterService(orgId: orgId)
    service.announcementDelayNanoseconds = 80_000_000
    let viewModel = NotificationCenterViewModel()
    viewModel.resetForUser(userId)
    var draft = AnnouncementDraft()
    draft.title = "Practice"
    draft.body = "Starts at six."
    let first = Task { @MainActor in
      await viewModel.sendAnnouncement(
        organizationId: self.orgId,
        draft: draft,
        supportMode: false,
        service: service
      )
    }
    try await Task.sleep(nanoseconds: 10_000_000)
    let second = await viewModel.sendAnnouncement(
      organizationId: orgId,
      draft: draft,
      supportMode: false,
      service: service
    )
    #expect(!second)
    #expect(await first.value)
    #expect(service.announcementCalls == 1)
  }

  private func decodeNotification(
    category: String,
    route: String,
    payload: String = "{\"payment_request_id\":\"cccccccc-cccc-4ccc-8ccc-cccccccccccc\"}",
    relatedEntityId: String = "cccccccc-cccc-4ccc-8ccc-cccccccccccc"
  ) throws -> AppNotification {
    let response = try JSONDecoder().decode(
      NotificationListResponse.self,
      from: Data(listJSON(
        category: category,
        route: route,
        payload: payload,
        relatedEntityId: relatedEntityId
      ).utf8)
    )
    return try #require(response.notifications.first)
  }

  private func listJSON(
    category: String,
    route: String,
    payload: String = "{\"payment_request_id\":\"cccccccc-cccc-4ccc-8ccc-cccccccccccc\"}",
    relatedEntityId: String = "cccccccc-cccc-4ccc-8ccc-cccccccccccc"
  ) -> String {
    """
    {
      "notifications": [{
        "id": "dddddddd-dddd-4ddd-8ddd-dddddddddddd",
        "org_id": "\(orgId.uuidString.lowercased())",
        "organization_name": "Marist Baseball",
        "category": "\(category)",
        "title": "Payment request",
        "body": "A new request is ready.",
        "related_entity_type": "payment_request",
        "related_entity_id": "\(relatedEntityId)",
        "action_route": "\(route)",
        "action_payload": \(payload),
        "created_at": "2026-07-15T12:00:00.123456+00:00",
        "read_at": null
      }],
      "pagination": {"limit": 20, "offset": 0, "total": 1, "has_more": false}
    }
    """
  }
}

private struct AnyEncodable: Encodable {
  private let encodeValue: (Encoder) throws -> Void

  init(_ value: any Encodable) {
    encodeValue = value.encode
  }

  func encode(to encoder: Encoder) throws {
    try encodeValue(encoder)
  }
}

@MainActor
private final class MockNotificationCenterService: NotificationCenterServicing {
  let defaultOrganizationId: UUID
  var slowOrganizationId: UUID?
  var announcementDelayNanoseconds: UInt64 = 0
  var markReadCalls = 0
  var announcementCalls = 0
  private var isRead = false

  init(orgId: UUID) {
    defaultOrganizationId = orgId
  }

  func listNotifications(
    organizationId: UUID?,
    unreadOnly: Bool,
    limit: Int,
    offset: Int
  ) async throws -> NotificationListResponse {
    if organizationId == slowOrganizationId {
      try await Task.sleep(nanoseconds: 80_000_000)
    }
    let orgId = organizationId ?? defaultOrganizationId
    let notification = AppNotification(
      id: UUID(uuidString: "dddddddd-dddd-4ddd-8ddd-dddddddddddd")!,
      organizationId: orgId,
      organizationName: "Organization",
      category: .system,
      title: "Update",
      body: "Details",
      relatedEntityType: nil,
      relatedEntityId: nil,
      actionRoute: .notificationDetail,
      actionPayload: NotificationActionPayload(),
      createdAt: "2026-07-15T12:00:00Z",
      readAt: isRead ? "2026-07-15T12:01:00Z" : nil
    )
    let values = unreadOnly && isRead ? [] : [notification]
    return NotificationListResponse(
      notifications: values,
      pagination: NotificationPagination(limit: limit, offset: offset, total: values.count, hasMore: false)
    )
  }

  func unreadNotificationCount(organizationId: UUID?) async throws -> NotificationUnreadCountResponse {
    NotificationUnreadCountResponse(
      totalUnread: isRead ? 0 : 1,
      organizationId: organizationId,
      organizationUnread: organizationId == nil ? nil : (isRead ? 0 : 1)
    )
  }

  func markNotificationRead(notificationId: UUID) async throws -> AppNotification {
    markReadCalls += 1
    isRead = true
    return AppNotification(
      id: notificationId,
      organizationId: defaultOrganizationId,
      organizationName: "Organization",
      category: .system,
      title: "Update",
      body: "Details",
      relatedEntityType: nil,
      relatedEntityId: nil,
      actionRoute: .notificationDetail,
      actionPayload: NotificationActionPayload(),
      createdAt: "2026-07-15T12:00:00Z",
      readAt: "2026-07-15T12:01:00Z"
    )
  }

  func markAllNotificationsRead(organizationId: UUID?) async throws -> NotificationMarkAllResponse {
    let changed = isRead ? 0 : 1
    isRead = true
    return NotificationMarkAllResponse(updatedCount: changed, organizationId: organizationId)
  }

  func createOrganizationAnnouncement(
    organizationId: UUID,
    draft: AnnouncementDraft,
    supportMode: Bool,
    idempotencyKey: UUID
  ) async throws -> OrganizationAnnouncementResponse {
    announcementCalls += 1
    if announcementDelayNanoseconds > 0 {
      try await Task.sleep(nanoseconds: announcementDelayNanoseconds)
    }
    return OrganizationAnnouncementResponse(
      announcementId: UUID(),
      createdCount: 1,
      recipientCount: 1,
      reused: false,
      authorizationSource: supportMode ? .platformSupport : .organizationMembership
    )
  }
}
