import Foundation

struct SDOrg: Identifiable, Decodable, Equatable, Hashable, Sendable {
  let id: UUID
  let slug: String
  let name: String

  var displayName: String { name }
}

struct SDOrgMembership: Identifiable, Codable, Equatable, Sendable {
  var id: String { "\(org_id.uuidString):\(user_id.uuidString)" }
  let org_id: UUID
  let user_id: UUID
  let role: String
  let status: String
  let created_at: Date?
  let created_by: UUID?

  var isOwner: Bool { role.lowercased() == "owner" }
  var isCoach: Bool { role.lowercased() == "coach" }
  var isAdmin: Bool { isOwner }
  var isStaff: Bool { isOwner || isCoach }
}

struct SDOrgSettings: Identifiable, Codable, Equatable, Sendable {
  var id: UUID { org_id }
  let org_id: UUID
  var display_name: String?
  var short_name: String?
  var support_email: String?
  var website_host: String?
  var primary_color_hex: String
  var secondary_color_hex: String
  var accent_color_hex: String
  var terminology: [String: SDJSONValue]
  var feature_flags: [String: SDJSONValue]
  var booking_policy: [String: SDJSONValue]
  var dashboard_layout: [String: SDJSONValue]
  let created_at: Date?
  let updated_at: Date?

  func term(_ key: String, fallback: String) -> String {
    terminology[key]?.stringValue ?? fallback
  }

  func feature(_ key: String, default defaultValue: Bool = true) -> Bool {
    feature_flags[key]?.boolValue ?? defaultValue
  }

  func bookingInt(_ key: String, default defaultValue: Int) -> Int {
    booking_policy[key]?.intValue ?? defaultValue
  }
}

struct SDOrgAdminMember: Identifiable, Codable, Equatable, Sendable {
  var id: String { "\(org_id.uuidString):\(user_id.uuidString)" }
  let org_id: UUID
  let user_id: UUID
  var role: String
  var status: String
  let created_at: Date?
  let created_by: UUID?
  var username: String?
  var email: String?
  var full_name: String?
  var profile_role: String?

  var displayName: String {
    if let full_name, !full_name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      return full_name
    }
    if let username, !username.isEmpty { return "@\(username)" }
    if let email, !email.isEmpty { return email }
    return user_id.uuidString
  }

  var isAdmin: Bool {
    let normalized = role.lowercased()
    return normalized == "owner" || normalized == "coach"
  }
}

enum SDJSONValue: Codable, Equatable, Hashable, Sendable {
  case string(String)
  case bool(Bool)
  case int(Int)
  case double(Double)
  case object([String: SDJSONValue])
  case array([SDJSONValue])
  case null

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if container.decodeNil() {
      self = .null
    } else if let value = try? container.decode(Bool.self) {
      self = .bool(value)
    } else if let value = try? container.decode(Int.self) {
      self = .int(value)
    } else if let value = try? container.decode(Double.self) {
      self = .double(value)
    } else if let value = try? container.decode(String.self) {
      self = .string(value)
    } else if let value = try? container.decode([String: SDJSONValue].self) {
      self = .object(value)
    } else if let value = try? container.decode([SDJSONValue].self) {
      self = .array(value)
    } else {
      self = .null
    }
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .string(let value):
      try container.encode(value)
    case .bool(let value):
      try container.encode(value)
    case .int(let value):
      try container.encode(value)
    case .double(let value):
      try container.encode(value)
    case .object(let value):
      try container.encode(value)
    case .array(let value):
      try container.encode(value)
    case .null:
      try container.encodeNil()
    }
  }

  var stringValue: String? {
    switch self {
    case .string(let value): return value
    case .int(let value): return String(value)
    case .double(let value): return String(value)
    case .bool(let value): return value ? "true" : "false"
    default: return nil
    }
  }

  var boolValue: Bool? {
    switch self {
    case .bool(let value):
      return value
    case .string(let value):
      let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
      if ["true", "1", "yes", "y", "on"].contains(normalized) { return true }
      if ["false", "0", "no", "n", "off"].contains(normalized) { return false }
      return nil
    default:
      return nil
    }
  }

  var intValue: Int? {
    switch self {
    case .int(let value): return value
    case .double(let value): return Int(value)
    case .string(let value): return Int(value.trimmingCharacters(in: .whitespacesAndNewlines))
    default: return nil
    }
  }
}
