import Foundation

struct SDChatChannel: Identifiable, Decodable, Equatable {
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

struct SDChatMembership: Identifiable, Decodable, Equatable {
  var id: String { "\(channel_id.uuidString):\(user_id.uuidString)" }
  let org_id: UUID?
  let channel_id: UUID
  let user_id: UUID
  let member_role: String
  let joined_at: Date?
  let last_read_at: Date?
  let muted: Bool

  var isAdmin: Bool { member_role.lowercased() == "admin" }
}

struct SDChatMessage: Identifiable, Decodable, Equatable {
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

struct SDChatLastMessageRow: Identifiable, Decodable, Equatable {
  var id: UUID { channel_id }
  let channel_id: UUID
  let body_preview: String?
  let message_created_at: Date?
}
