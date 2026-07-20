import Foundation

struct SDChatChannel: Identifiable, Decodable, Equatable, Sendable {
  let id: UUID
  let org_id: UUID?
  let channel_type: String
  let title: String?
  let audience: String?
  let created_by: UUID?
  let is_archived: Bool
  let pinned_rank: Int?
  let created_at: Date?
  let updated_at: Date?

  var isDM: Bool { channel_type.lowercased() == "dm" }
  var isGroup: Bool { channel_type.lowercased() == "group" }
  var isAnnouncement: Bool { channel_type.lowercased() == "announcement" }
}

struct SDChatMembership: Identifiable, Decodable, Equatable, Sendable {
  var id: String { "\(channel_id.uuidString):\(user_id.uuidString)" }
  let org_id: UUID?
  let channel_id: UUID
  let user_id: UUID
  let member_role: String
  let joined_at: Date?
  let last_read_at: Date?
  let last_read_message_id: UUID?
  let muted: Bool

  var isAdmin: Bool { member_role.lowercased() == "admin" }
}

struct SDChatMessage: Identifiable, Decodable, Equatable, Sendable {
  let id: UUID
  let org_id: UUID?
  let channel_id: UUID
  let sender_id: UUID?
  let body: String
  let created_at: Date
  let edited_at: Date?
  let deleted_at: Date?

  var isDeleted: Bool { deleted_at != nil }
}

struct SDChatLastMessageRow: Identifiable, Decodable, Equatable, Sendable {
  var id: UUID { channel_id }
  let channel_id: UUID
  let body_preview: String?
  let message_created_at: Date?
  let message_id: UUID?
}

struct SDChatSendResponse: Decodable, Equatable, Sendable {
  let message: SDChatMessage
  let reused: Bool
}

struct SDChatReadResult: Decodable, Equatable, Sendable {
  let organizationId: UUID
  let conversationId: UUID
  let throughMessageId: UUID
  let lastReadAt: Date
  let lastReadMessageId: UUID?
  let notificationsMarkedRead: Int

  private enum CodingKeys: String, CodingKey {
    case organizationId = "organization_id"
    case conversationId = "conversation_id"
    case throughMessageId = "through_message_id"
    case lastReadAt = "last_read_at"
    case lastReadMessageId = "last_read_message_id"
    case notificationsMarkedRead = "notifications_marked_read"
  }
}

struct ChatReadUpdate: Equatable, Sendable {
  let organizationId: UUID
  let conversationId: UUID
  let throughMessageId: UUID
  let lastReadAt: Date
  let lastReadMessageId: UUID?
}

struct ChatReadCursor: Equatable, Sendable {
  let at: Date
  let messageId: UUID?

  static func later(_ lhs: ChatReadCursor?, _ rhs: ChatReadCursor?) -> ChatReadCursor? {
    guard let lhs else { return rhs }
    guard let rhs else { return lhs }
    if lhs.at != rhs.at { return lhs.at > rhs.at ? lhs : rhs }
    // The migration backfills historical timestamp cursors that covered a
    // message. Any remaining nil is the minimum tie-breaker at that timestamp.
    guard let lhsId = lhs.messageId else { return rhs }
    guard let rhsId = rhs.messageId else { return lhs }
    return lhsId.uuidString.lowercased() >= rhsId.uuidString.lowercased()
      ? lhs : rhs
  }
}

enum ChatSendStatus: Equatable, Sendable {
  case idle
  case sending
  case sent
  case failed
}

/// Retains a stable client operation UUID across ambiguous failures. A new UUID
/// is created only after success or when the channel/body material changes.
struct ChatSendOperationState: Equatable, Sendable {
  private(set) var clientMessageId: UUID?
  private(set) var material: String?
  private(set) var status = ChatSendStatus.idle

  mutating func begin(
    channelId: UUID,
    body: String,
    key: UUID = UUID()
  ) -> UUID? {
    guard status != .sending else { return nil }
    let cleanedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
    let nextMaterial = [
      channelId.uuidString.lowercased(),
      cleanedBody,
    ].joined(separator: "\u{1f}")
    if material != nextMaterial || clientMessageId == nil {
      material = nextMaterial
      clientMessageId = key
    }
    status = .sending
    return clientMessageId
  }

  mutating func finish(success: Bool) {
    status = success ? .sent : .failed
    if success {
      clientMessageId = nil
      material = nil
    }
  }

  mutating func clear() {
    clientMessageId = nil
    material = nil
    status = .idle
  }
}

enum ChatContextGuard {
  static func accepts(
    responseOrganizationId: UUID,
    responseToken: UUID,
    activeOrganizationId: UUID?,
    currentToken: UUID?
  ) -> Bool {
    responseOrganizationId == activeOrganizationId && responseToken == currentToken
  }
}

enum ChatConversationSearch {
  static func matches(title: String, preview: String, query: String) -> Bool {
    let cleaned = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !cleaned.isEmpty else { return true }
    return title.lowercased().contains(cleaned) || preview.lowercased().contains(cleaned)
  }
}

enum ChatUnreadState {
  static func isUnread(
    lastMessageAt: Date?,
    lastMessageId: UUID?,
    lastReadAt: Date?,
    lastReadMessageId: UUID?
  ) -> Bool {
    guard let lastMessageAt else { return false }
    guard let lastReadAt else { return true }
    if lastMessageAt != lastReadAt {
      return lastMessageAt > lastReadAt
    }
    // The migration backfills historical cursors that covered messages. A
    // remaining nil read UUID is the minimum value at the same timestamp.
    guard let lastMessageId else { return false }
    guard let lastReadMessageId else { return true }
    return lastMessageId.uuidString.lowercased() >
      lastReadMessageId.uuidString.lowercased()
  }
}

enum ChatForegroundPresentationPolicy {
  static func shouldPresent(
    notificationOrganizationId: UUID,
    notificationConversationId: UUID,
    activeOrganizationId: UUID?,
    activeConversationId: UUID?
  ) -> Bool {
    notificationOrganizationId != activeOrganizationId ||
      notificationConversationId != activeConversationId
  }
}
