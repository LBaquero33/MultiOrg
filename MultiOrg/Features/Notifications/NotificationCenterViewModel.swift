import Combine
import Foundation

@MainActor
protocol NotificationCenterServicing {
  func listNotifications(
    organizationId: UUID?,
    unreadOnly: Bool,
    limit: Int,
    offset: Int
  ) async throws -> NotificationListResponse
  func unreadNotificationCount(
    organizationId: UUID?
  ) async throws -> NotificationUnreadCountResponse
  func markNotificationRead(notificationId: UUID) async throws -> AppNotification
  func markAllNotificationsRead(
    organizationId: UUID?
  ) async throws -> NotificationMarkAllResponse
  func createOrganizationAnnouncement(
    organizationId: UUID,
    draft: AnnouncementDraft,
    supportMode: Bool,
    idempotencyKey: UUID
  ) async throws -> OrganizationAnnouncementResponse
}

extension SupabaseService: NotificationCenterServicing {}

@MainActor
final class NotificationCenterViewModel: ObservableObject {
  @Published private(set) var notifications: [AppNotification] = []
  @Published private(set) var totalUnread = 0
  @Published private(set) var isLoading = false
  @Published private(set) var isLoadingMore = false
  @Published private(set) var isMarkingAllRead = false
  @Published private(set) var isSendingAnnouncement = false
  @Published private(set) var errorMessage: String?
  @Published private(set) var announcementMessage: String?
  @Published var unreadOnly = false

  private let pageSize = 20
  private var totalAvailable = 0
  private var activeUserId: UUID?
  private var requestToken: UUID?
  private var requestOrganizationId: UUID?
  private var markingReadIds = Set<UUID>()
  private var announcementOperation = AnnouncementOperationState()

  var hasMore: Bool { notifications.count < totalAvailable }

  func resetForUser(_ userId: UUID?) {
    guard activeUserId != userId else { return }
    activeUserId = userId
    clear()
  }

  func organizationChanged() {
    requestToken = nil
    requestOrganizationId = nil
    notifications = []
    totalAvailable = 0
    errorMessage = nil
    unreadOnly = false
    markingReadIds = []
  }

  func refresh(
    organizationId: UUID?,
    service: (any NotificationCenterServicing)?
  ) async {
    guard let service, activeUserId != nil else {
      notifications = []
      totalUnread = 0
      errorMessage = "Notifications are unavailable because the session is not ready."
      return
    }
    let token = UUID()
    requestToken = token
    requestOrganizationId = organizationId
    isLoading = true
    errorMessage = nil
    do {
      let response = try await service.listNotifications(
        organizationId: organizationId,
        unreadOnly: unreadOnly,
        limit: pageSize,
        offset: 0
      )
      guard accepts(token: token, organizationId: organizationId) else { return }
      let count = try await service.unreadNotificationCount(organizationId: organizationId)
      guard accepts(token: token, organizationId: organizationId) else { return }
      notifications = response.notifications
      totalAvailable = response.pagination.total
      totalUnread = count.totalUnread
      isLoading = false
    } catch {
      guard accepts(token: token, organizationId: organizationId) else { return }
      errorMessage = error.localizedDescription
      isLoading = false
    }
  }

  func refreshBadge(service: (any NotificationCenterServicing)?) async {
    guard let service, activeUserId != nil else {
      totalUnread = 0
      return
    }
    do {
      totalUnread = try await service.unreadNotificationCount(
        organizationId: nil
      ).totalUnread
    } catch {
      // The bell remains usable; the full center presents a readable load error.
    }
  }

  func loadMore(
    organizationId: UUID?,
    service: (any NotificationCenterServicing)?
  ) async {
    guard hasMore, !isLoadingMore, let service else { return }
    let token = requestToken
    isLoadingMore = true
    defer { isLoadingMore = false }
    do {
      let response = try await service.listNotifications(
        organizationId: organizationId,
        unreadOnly: unreadOnly,
        limit: pageSize,
        offset: notifications.count
      )
      guard token == requestToken, requestOrganizationId == organizationId else { return }
      var byId = Dictionary(uniqueKeysWithValues: notifications.map { ($0.id, $0) })
      for notification in response.notifications { byId[notification.id] = notification }
      notifications = byId.values.sorted { $0.createdAt > $1.createdAt }
      totalAvailable = response.pagination.total
    } catch {
      guard token == requestToken, requestOrganizationId == organizationId else { return }
      errorMessage = error.localizedDescription
    }
  }

  @discardableResult
  func markRead(
    _ notification: AppNotification,
    service: (any NotificationCenterServicing)?
  ) async -> Bool {
    guard let service else { return false }
    guard !markingReadIds.contains(notification.id) else { return false }
    if !notification.isUnread { return true }
    markingReadIds.insert(notification.id)
    defer { markingReadIds.remove(notification.id) }
    do {
      let updated = try await service.markNotificationRead(notificationId: notification.id)
      if let index = notifications.firstIndex(where: { $0.id == updated.id }) {
        notifications[index] = updated
      }
      totalUnread = max(0, totalUnread - 1)
      return true
    } catch {
      errorMessage = error.localizedDescription
      return false
    }
  }

  func markAllRead(
    organizationId: UUID?,
    service: (any NotificationCenterServicing)?
  ) async {
    guard !isMarkingAllRead, let service else { return }
    isMarkingAllRead = true
    defer { isMarkingAllRead = false }
    do {
      let response = try await service.markAllNotificationsRead(
        organizationId: organizationId
      )
      let now = ISO8601DateFormatter().string(from: Date())
      notifications = notifications.map { $0.markingRead(at: now) }
      totalUnread = max(0, totalUnread - response.updatedCount)
      announcementMessage = response.updatedCount == 0
        ? "No unread notifications in this view."
        : "Marked \(response.updatedCount) notifications read."
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  @discardableResult
  func sendAnnouncement(
    organizationId: UUID,
    draft: AnnouncementDraft,
    supportMode: Bool,
    service: (any NotificationCenterServicing)?
  ) async -> Bool {
    guard draft.isValid else {
      errorMessage = draft.validationError
      return false
    }
    guard let service else {
      errorMessage = "Announcement service is unavailable."
      return false
    }
    guard let key = announcementOperation.begin(
      organizationId: organizationId,
      draft: draft,
      supportMode: supportMode
    ) else { return false }
    isSendingAnnouncement = true
    errorMessage = nil
    announcementMessage = nil
    do {
      let response = try await service.createOrganizationAnnouncement(
        organizationId: organizationId,
        draft: draft,
        supportMode: supportMode,
        idempotencyKey: key
      )
      announcementOperation.finish(success: true)
      isSendingAnnouncement = false
      announcementMessage = response.reused
        ? "Announcement was already sent to \(response.recipientCount) members."
        : "Announcement sent to \(response.recipientCount) members."
      await refreshBadge(service: service)
      return true
    } catch {
      announcementOperation.finish(success: false)
      isSendingAnnouncement = false
      errorMessage = error.localizedDescription
      return false
    }
  }

  func clearMessages() {
    errorMessage = nil
    announcementMessage = nil
  }

  private func clear() {
    requestToken = nil
    requestOrganizationId = nil
    notifications = []
    totalAvailable = 0
    totalUnread = 0
    isLoading = false
    isLoadingMore = false
    isMarkingAllRead = false
    isSendingAnnouncement = false
    errorMessage = nil
    announcementMessage = nil
    unreadOnly = false
    markingReadIds = []
    announcementOperation.clear()
  }

  private func accepts(token: UUID, organizationId: UUID?) -> Bool {
    requestToken == token && requestOrganizationId == organizationId
  }
}
