import Foundation

struct SDParentInvite: Identifiable, Decodable, Equatable {
  let id: UUID
  let email_norm: String
  let child_id: UUID
  let invited_by: UUID?
  let relationship: String?
  let accepted_at: Date?
  let parent_id: UUID?
  let created_at: Date?
}

struct SDParentChildLink: Identifiable, Decodable, Equatable {
  var id: String { "\(parent_id.uuidString)|\(child_id.uuidString)" }
  let parent_id: UUID
  let child_id: UUID
  let relationship: String?
  let can_book: Bool
  let can_pay: Bool
  let created_at: Date?
  let created_by: UUID?
}

struct SDPaymentRequest: Identifiable, Decodable, Equatable {
  let id: UUID
  let payer_id: UUID
  let child_id: UUID
  let status: String
  let plan_name: String?
  let amount_cents: Int?
  let currency: String?
  let notes: String?
  let created_at: Date?
  let updated_at: Date?
}

struct SDParentInviteRequest: Identifiable, Decodable, Equatable {
  let id: UUID
  let email_norm: String
  let child_id: UUID
  let requested_by: UUID
  let relationship: String?
  let status: String
  let coach_note: String?
  let created_at: Date?
  let updated_at: Date?
}
