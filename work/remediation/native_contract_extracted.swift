import Foundation

struct SDOrgMembership: Identifiable, Codable, Equatable, Sendable {
  var id: String { "\(org_id.uuidString):\(user_id.uuidString)" }
  let org_id: UUID
  let user_id: UUID
  let role: String
  let status: String
  let created_at: Date?
  let created_by: UUID?

  var normalizedRole: String { role.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
  var normalizedStatus: String { status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
  var isActive: Bool { normalizedStatus == "active" }
  var isOwner: Bool { normalizedRole == "owner" }
  var isCoach: Bool { normalizedRole == "coach" }
  var isAdmin: Bool { normalizedRole == "admin" }
  var canAdministerOrganization: Bool { isActive && (isOwner || isAdmin) }
  var isStaff: Bool { isActive && (isOwner || isAdmin || isCoach) }
}

enum OrganizationAuthorization {
  static func activeMembership(
    userId: UUID?,
    orgId: UUID?,
    memberships: [SDOrgMembership]
  ) -> SDOrgMembership? {
    guard let userId, let orgId else { return nil }
    return memberships.first {
      $0.user_id == userId && $0.org_id == orgId && $0.isActive
    }
  }

  static func canAdminister(
    userId: UUID?,
    orgId: UUID?,
    memberships: [SDOrgMembership]
  ) -> Bool {
    activeMembership(userId: userId, orgId: orgId, memberships: memberships)?
      .canAdministerOrganization == true
  }
}

enum SDChatAuthorization {
  static func canComposeAnnouncement(membership: SDOrgMembership?) -> Bool {
    membership?.isStaff == true
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

enum SDGameLifecycle: String, Codable, CaseIterable, Sendable {
  case draft, scheduled, pregame, live, delayed, suspended, postponed, canceled
  case final, forfeit
  case noContest = "no_contest"
}

enum HPTeamWorkspaceSection: String, CaseIterable, Codable, Equatable, Sendable {
  case overview
  case players
  case schedule
  case development
  case staff
  case settings
  case communication
  case documents
}

struct HPTeamWorkspaceRoute: Equatable, Sendable {
  let organizationId: UUID
  let teamId: UUID
  let section: HPTeamWorkspaceSection

  init?(url: URL) {
    guard url.scheme?.lowercased() == "homeplate",
          ["team", "currentteam", "current-team", "current_team"].contains(url.host?.lowercased() ?? "") else {
      return nil
    }
    guard let values = HPDeepLinkQueryValues(url: url) else { return nil }
    let pathComponents = url.pathComponents.filter { $0 != "/" }
    guard pathComponents.count <= 1 else { return nil }
    let pathTeamId = pathComponents.first.flatMap(UUID.init(uuidString:))
    guard let organizationId = values["organization_id"].flatMap(UUID.init(uuidString:)),
          let teamId = values["team_id"].flatMap(UUID.init(uuidString:)) ?? pathTeamId else {
      return nil
    }
    self.organizationId = organizationId
    self.teamId = teamId
    section = values["section"].flatMap(HPTeamWorkspaceSection.init(rawValue:)) ?? .overview
  }
}

enum HPCalendarLinkSource: String, Equatable, Sendable {
  case event
  case booking
}

enum HPCalendarLinkError: Error {
  case unavailable
}

struct HPCalendarLinkRoute: Identifiable, Equatable, Sendable {
  let source: HPCalendarLinkSource
  let sourceId: UUID
  let organizationId: UUID

  var id: String { "\(organizationId.uuidString):\(source.rawValue):\(sourceId.uuidString)" }

  init?(url: URL) {
    guard url.scheme?.lowercased() == "homeplate",
          url.host?.lowercased() == "calendar",
          let values = HPDeepLinkQueryValues(url: url) else { return nil }
    let path = url.pathComponents.filter { $0 != "/" }
    guard path.count == 2,
          let source = HPCalendarLinkSource(rawValue: path[0].lowercased()),
          let sourceId = UUID(uuidString: path[1]),
          let organizationId = values["organization"].flatMap(UUID.init(uuidString:)) else {
      return nil
    }
    self.source = source
    self.sourceId = sourceId
    self.organizationId = organizationId
  }
}

private struct HPDeepLinkQueryValues {
  let values: [String: String]

  subscript(_ key: String) -> String? { values[key] }

  init?(url: URL) {
    guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
    var parsed: [String: String] = [:]
    for item in components.queryItems ?? [] {
      guard let value = item.value else { return nil }
      let key = item.name.lowercased()
      guard parsed[key] == nil else { return nil }
      parsed[key] = value
    }
    values = parsed
  }
}

struct SDParentInviteRedemption: Identifiable, Equatable, Sendable {
  let inviteId: UUID
  let token: String

  var id: String { inviteId.uuidString.lowercased() }

  init?(url: URL) {
    guard url.scheme?.lowercased() == "homeplate",
          url.host?.lowercased() == "parent-invite",
          let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
    let path = url.pathComponents.filter { $0 != "/" }
    guard path.count == 1, let inviteId = UUID(uuidString: path[0]) else { return nil }
    var token: String?
    for item in components.queryItems ?? [] {
      guard item.name.lowercased() == "token", token == nil,
            let value = item.value,
            (32...128).contains(value.count),
            value.utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) })
      else { return nil }
      token = value.lowercased()
    }
    guard let token else { return nil }
    self.inviteId = inviteId
    self.token = token
  }
}
