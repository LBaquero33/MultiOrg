import Foundation

struct SDOrg: Identifiable, Decodable, Equatable, Hashable, Sendable {
  let id: UUID
  let slug: String
  let name: String

  var displayName: String { name }
}

/// Server-synchronized organization software subscription state. Timestamps
/// remain strings because PostgREST can return fractional PostgreSQL times.
struct SDOrgSubscription: Identifiable, Decodable, Equatable, Sendable {
  let id: UUID
  let org_id: UUID
  let provider: String
  let provider_subscription_id: String?
  let provider_product_id: String?
  let provider_price_id: String?
  let status: String
  let current_period_start: String?
  let current_period_end: String?
  let cancel_at_period_end: Bool
  let canceled_at: String?
  let updated_at: String?
}

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

enum SDAuthenticatedWorkspace: Equatable, Sendable {
  case staff
  case player
  case parent
  case platformOnly
  case unavailable

  /// Organization workspace selection is derived only from the selected
  /// organization's active membership. Platform administration remains an
  /// independent server-authorized capability and never supplies an org role.
  static func resolve(
    membership: SDOrgMembership?,
    isPlatformAdmin: Bool
  ) -> Self {
    if membership?.isStaff == true { return .staff }
    if membership?.isActive == true {
      switch membership?.normalizedRole {
      case "player": return .player
      case "parent": return .parent
      default: return .unavailable
      }
    }
    return isPlatformAdmin ? .platformOnly : .unavailable
  }
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
  var logo_path: String?
  var terminology: [String: SDJSONValue]
  var feature_flags: [String: SDJSONValue]
  var booking_policy: [String: SDJSONValue]
  var dashboard_layout: [String: SDJSONValue]
  var team_policy: [String: SDJSONValue]
  let created_at: Date?
  let updated_at: Date?

  private enum CodingKeys: String, CodingKey {
    case org_id, display_name, short_name, support_email, website_host
    case primary_color_hex, secondary_color_hex, accent_color_hex, logo_path
    case terminology, feature_flags, booking_policy, dashboard_layout, team_policy
    case created_at, updated_at
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    org_id = try container.decode(UUID.self, forKey: .org_id)
    display_name = try? container.decodeIfPresent(String.self, forKey: .display_name)
    short_name = try? container.decodeIfPresent(String.self, forKey: .short_name)
    support_email = try? container.decodeIfPresent(String.self, forKey: .support_email)
    website_host = try? container.decodeIfPresent(String.self, forKey: .website_host)
    primary_color_hex = (try? container.decode(String.self, forKey: .primary_color_hex)) ?? "#0D2445"
    secondary_color_hex = (try? container.decode(String.self, forKey: .secondary_color_hex)) ?? "#0A3854"
    accent_color_hex = (try? container.decode(String.self, forKey: .accent_color_hex)) ?? "#4D9EF9"
    logo_path = try? container.decodeIfPresent(String.self, forKey: .logo_path)
    terminology = (try? container.decode([String: SDJSONValue].self, forKey: .terminology)) ?? [:]
    feature_flags = (try? container.decode([String: SDJSONValue].self, forKey: .feature_flags)) ?? [:]
    booking_policy = (try? container.decode([String: SDJSONValue].self, forKey: .booking_policy)) ?? [:]
    dashboard_layout = (try? container.decode([String: SDJSONValue].self, forKey: .dashboard_layout)) ?? [:]
    team_policy = (try? container.decode([String: SDJSONValue].self, forKey: .team_policy)) ?? [:]
    created_at = try? container.decode(Date.self, forKey: .created_at)
    updated_at = try? container.decode(Date.self, forKey: .updated_at)
  }

  func term(_ key: String, fallback: String) -> String {
    terminology[key]?.stringValue ?? fallback
  }

  func feature(_ key: String, default defaultValue: Bool = true) -> Bool {
    feature_flags[key]?.boolValue ?? defaultValue
  }

  func bookingInt(_ key: String, default defaultValue: Int) -> Int {
    booking_policy[key]?.intValue ?? defaultValue
  }

  func teamPolicy(_ key: String, default defaultValue: Bool) -> Bool {
    team_policy[key]?.boolValue ?? defaultValue
  }
}

struct SDOrgAdminMember: Identifiable, Codable, Equatable, Sendable {
  var id: String { "\(org_id.uuidString):\(user_id.uuidString)" }
  let org_id: UUID
  let user_id: UUID
  var role: String
  var status: String
  // Edge Functions return PostgreSQL timestamps with microseconds and a
  // `+00:00` offset. Keep audit timestamps lossless instead of routing them
  // through Foundation's narrower default Date decoder.
  let created_at: String?
  let created_by: UUID?
  var username: String?
  var email: String?
  var full_name: String?
  var profile_role: String?

  var displayName: String {
    if let full_name {
      let value = full_name.trimmingCharacters(in: .whitespacesAndNewlines)
      if !value.isEmpty { return value }
    }
    if let username {
      let value = username.trimmingCharacters(in: .whitespacesAndNewlines)
      if !value.isEmpty { return "@\(value)" }
    }
    if let email {
      let value = email.trimmingCharacters(in: .whitespacesAndNewlines)
      if !value.isEmpty { return value }
    }
    return "Player \(user_id.uuidString.lowercased().suffix(6))"
  }

  var isAdmin: Bool {
    let normalized = role.lowercased()
    return normalized == "owner" || normalized == "admin"
  }
}

enum SDPaymentRequestPlayerRoster {
  static func organizationChanged(from previous: UUID?, to next: UUID?) -> Bool {
    previous != next
  }

  static func eligiblePlayers(
    from members: [SDPaymentRequestEligiblePlayer],
    organizationId: UUID
  ) -> [SDPaymentRequestEligiblePlayer] {
    var memberByUserId: [UUID: SDPaymentRequestEligiblePlayer] = [:]
    for member in members where member.organizationId == organizationId
      && member.role.lowercased() == "player"
      && member.status.lowercased() == "active" {
      guard let existing = memberByUserId[member.userId] else {
        memberByUserId[member.userId] = member
        continue
      }
      if identityQuality(member) > identityQuality(existing) {
        memberByUserId[member.userId] = member
      }
    }
    return memberByUserId.values.sorted { lhs, rhs in
      let comparison = lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName)
      if comparison == .orderedSame { return lhs.userId.uuidString < rhs.userId.uuidString }
      return comparison == .orderedAscending
    }
  }

  static func search(
    _ players: [SDPaymentRequestEligiblePlayer],
    text: String
  ) -> [SDPaymentRequestEligiblePlayer] {
    let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty else { return players }
    return players.filter {
      $0.displayName.localizedCaseInsensitiveContains(query)
        || $0.userId.uuidString.localizedCaseInsensitiveContains(query)
    }
  }

  static func selectAll(_ players: [SDPaymentRequestEligiblePlayer]) -> Set<UUID> {
    Set(players.map(\.userId))
  }

  static func reconcile(
    selectedPlayerUserIds: Set<UUID>,
    eligiblePlayers: [SDPaymentRequestEligiblePlayer]
  ) -> Set<UUID> {
    selectedPlayerUserIds.intersection(selectAll(eligiblePlayers))
  }

  static func payloadPlayerUserIds(
    selectedPlayerUserIds: Set<UUID>,
    eligiblePlayers: [SDPaymentRequestEligiblePlayer]
  ) -> [UUID] {
    reconcile(selectedPlayerUserIds: selectedPlayerUserIds, eligiblePlayers: eligiblePlayers)
      .sorted { $0.uuidString < $1.uuidString }
  }

  private static func identityQuality(_ member: SDPaymentRequestEligiblePlayer) -> Int {
    if member.fullName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false { return 3 }
    if member.username?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false { return 2 }
    if member.email?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false { return 1 }
    return 0
  }
}

enum SDPaymentRequestRosterResponseContext {
  static func matchesSelectedOrganization(
    responseOrganizationId: UUID,
    selectedOrganizationId: UUID?,
    rosterContextOrganizationId: UUID?
  ) -> Bool {
    responseOrganizationId == selectedOrganizationId
      && responseOrganizationId == rosterContextOrganizationId
  }
}

enum SDPaymentRequestEligibleRosterState: Equatable, Sendable {
  case idle
  case loading(organizationId: UUID, requestId: UUID)
  case loaded(organizationId: UUID, players: [SDPaymentRequestEligiblePlayer])
  case empty(organizationId: UUID)
  case failed(organizationId: UUID, message: String)

  var organizationId: UUID? {
    switch self {
    case .idle:
      nil
    case .loading(let organizationId, _),
         .loaded(let organizationId, _),
         .empty(let organizationId),
         .failed(let organizationId, _):
      organizationId
    }
  }

  var isLoading: Bool {
    if case .loading = self { return true }
    return false
  }

  var errorMessage: String? {
    if case .failed(_, let message) = self { return message }
    return nil
  }

  var shouldShowRetry: Bool {
    switch self {
    case .empty, .failed:
      true
    case .idle, .loading, .loaded:
      false
    }
  }

  var debugLabel: String {
    switch self {
    case .idle: "idle"
    case .loading: "loading"
    case .loaded(_, let players): "loaded(\(players.count))"
    case .empty: "empty"
    case .failed: "failed"
    }
  }

  func players(for organizationId: UUID?) -> [SDPaymentRequestEligiblePlayer] {
    guard let organizationId,
          case .loaded(let loadedOrganizationId, let players) = self,
          loadedOrganizationId == organizationId else { return [] }
    return players
  }

  func hasSuccessfulResponse(for organizationId: UUID?) -> Bool {
    guard let organizationId else { return false }
    switch self {
    case .loaded(let loadedOrganizationId, _), .empty(let loadedOrganizationId):
      return loadedOrganizationId == organizationId
    case .idle, .loading, .failed:
      return false
    }
  }

  mutating func beginLoading(organizationId: UUID, requestId: UUID) {
    self = .loading(organizationId: organizationId, requestId: requestId)
  }

  @discardableResult
  mutating func apply(
    _ players: [SDPaymentRequestEligiblePlayer],
    organizationId: UUID,
    requestId: UUID
  ) -> Bool {
    guard case .loading(let loadingOrganizationId, let loadingRequestId) = self,
          loadingOrganizationId == organizationId,
          loadingRequestId == requestId else { return false }
    self = players.isEmpty
      ? .empty(organizationId: organizationId)
      : .loaded(organizationId: organizationId, players: players)
    return true
  }

  @discardableResult
  mutating func fail(message: String, organizationId: UUID, requestId: UUID) -> Bool {
    guard case .loading(let loadingOrganizationId, let loadingRequestId) = self,
          loadingOrganizationId == organizationId,
          loadingRequestId == requestId else { return false }
    self = .failed(organizationId: organizationId, message: message)
    return true
  }

  mutating func finishLoadingIfNeeded(organizationId: UUID, requestId: UUID) {
    guard case .loading(let loadingOrganizationId, let loadingRequestId) = self,
          loadingOrganizationId == organizationId,
          loadingRequestId == requestId else { return }
    self = .idle
  }
}

struct SDTeam: Identifiable, Codable, Equatable, Sendable {
  let id: UUID
  let org_id: UUID
  let season_id: UUID?
  let name: String
  let color_hex: String?
  let age_group: String?
  let competitive_level: String?
  let roster_capacity: Int?
  let roster_count: Int?
  let description: String?
  let is_active: Bool
  let sort_order: Int
  let created_at: String?
  let updated_at: String?
}

struct SDTeamMember: Identifiable, Codable, Equatable, Sendable {
  var id: String { "\(org_id.uuidString):\(player_id.uuidString)" }
  let org_id: UUID
  let team_id: UUID
  let player_id: UUID
  let assigned_by: UUID?
  let assigned_at: String?

  var member_id: UUID { player_id }
}

struct SDAdminPlayerAccess: Decodable, Equatable, Sendable {
  let org_id: UUID?
  let user_id: UUID
  let is_active: Bool
  let source: String?
  let updated_at: String?
}

struct SDPlatformOrganization: Identifiable, Codable, Equatable, Sendable {
  let id: UUID
  let slug: String
  let name: String
  let status: String
  let plan: String
  let billing_email: String?
  let max_members: Int?
  let active_members: Int
  let players: Int
  let coaches: Int
  let active_entitlements: Int
  let teams: Int

  init(
    id: UUID,
    slug: String,
    name: String,
    status: String,
    plan: String,
    billing_email: String?,
    max_members: Int?,
    active_members: Int,
    players: Int,
    coaches: Int,
    active_entitlements: Int,
    teams: Int
  ) {
    self.id = id
    self.slug = slug
    self.name = name
    self.status = status
    self.plan = plan
    self.billing_email = billing_email
    self.max_members = max_members
    self.active_members = active_members
    self.players = players
    self.coaches = coaches
    self.active_entitlements = active_entitlements
    self.teams = teams
  }

  private enum CodingKeys: String, CodingKey {
    case id, slug, name, status, plan, billing_email, max_members
    case active_members, players, coaches, active_entitlements, teams
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(UUID.self, forKey: .id)
    slug = (try? container.decode(String.self, forKey: .slug)) ?? id.uuidString.lowercased()
    name = (try? container.decode(String.self, forKey: .name)) ?? "Organization"
    status = (try? container.decodeIfPresent(String.self, forKey: .status)) ?? "active"
    plan = (try? container.decodeIfPresent(String.self, forKey: .plan)) ?? "starter"
    billing_email = try? container.decodeIfPresent(String.self, forKey: .billing_email)
    max_members = Self.decodeOptionalInt(container, key: .max_members)
    active_members = Self.decodeInt(container, key: .active_members)
    players = Self.decodeInt(container, key: .players)
    coaches = Self.decodeInt(container, key: .coaches)
    active_entitlements = Self.decodeInt(container, key: .active_entitlements)
    teams = Self.decodeInt(container, key: .teams)
  }

  private static func decodeInt(
    _ container: KeyedDecodingContainer<CodingKeys>,
    key: CodingKeys
  ) -> Int {
    decodeOptionalInt(container, key: key) ?? 0
  }

  private static func decodeOptionalInt(
    _ container: KeyedDecodingContainer<CodingKeys>,
    key: CodingKeys
  ) -> Int? {
    if let value = try? container.decodeIfPresent(Int.self, forKey: key) { return value }
    if let value = try? container.decodeIfPresent(String.self, forKey: key) { return Int(value) }
    return nil
  }
}

struct SDPlatformDashboard: Decodable, Sendable {
  let organizations: [SDPlatformOrganization]
  let ownerless_organizations: [SDPlatformOrganization]
  let unmanaged_organizations: [SDPlatformOrganization]

  private enum CodingKeys: String, CodingKey {
    case organizations, ownerless_organizations, unmanaged_organizations
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    organizations = try container.decode([SDPlatformOrganization].self, forKey: .organizations)
    ownerless_organizations = (try? container.decode(
      [SDPlatformOrganization].self,
      forKey: .ownerless_organizations
    )) ?? []
    unmanaged_organizations = (try? container.decode(
      [SDPlatformOrganization].self,
      forKey: .unmanaged_organizations
    )) ?? []
  }
}

enum SDPlatformFeatureKey {
  static let playerDevelopmentCopilot = "player_development_copilot"
}

struct SDPlatformFeatureFlag: Identifiable, Codable, Equatable, Sendable {
  var id: String { key }
  let key: String
  let enabled: Bool
  let description: String
  let updated_at: String?
  let updated_by: UUID?
}

struct SDPlatformFeatureFlagsResponse: Decodable, Sendable {
  let feature_flags: [SDPlatformFeatureFlag]
}

struct SDPlatformFeatureFlagResponse: Decodable, Sendable {
  let feature_flag: SDPlatformFeatureFlag
}

enum SDPlatformFeatureGate {
  static let playerDevelopmentCopilotDefault = false

  static func playerDevelopmentCopilotEnabled(
    in flags: [SDPlatformFeatureFlag]
  ) -> Bool {
    flags.first(where: {
      $0.key == SDPlatformFeatureKey.playerDevelopmentCopilot
    })?.enabled ?? playerDevelopmentCopilotDefault
  }
}

enum SDPlatformFeatureDisabledError: LocalizedError, Equatable {
  case playerDevelopmentCopilot

  var errorDescription: String? {
    "Player Development AI and Copilot are currently disabled by Home Plate."
  }
}

struct SDPlatformMember: Identifiable, Codable, Equatable, Sendable {
  var id: String { "\(org_id.uuidString):\(user_id.uuidString)" }
  let org_id: UUID
  let user_id: UUID
  let role: String
  let status: String
  let created_at: String?
  let created_by: UUID?
  let username: String?
  let email: String?
  let full_name: String?
  let profile_role: String?
  let last_activity: String?

  var displayName: String {
    for candidate in [full_name, username.map { "@\($0)" }, email] {
      let value = candidate?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      if !value.isEmpty { return value }
    }
    return "User \(user_id.uuidString.lowercased().prefix(8))"
  }

  var normalizedRole: String { role.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
  var normalizedStatus: String { status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
  var isActive: Bool { normalizedStatus == "active" }
  var badges: [String] {
    switch normalizedRole {
    case "owner": ["Owner", "Admin", "Coach"]
    case "admin": ["Admin", "Coach"]
    case "coach": ["Coach"]
    case "player": ["Player"]
    case "parent": ["Parent"]
    default: []
    }
  }
}

enum SDPlatformMemberFilter: String, CaseIterable, Identifiable, Sendable {
  case all
  case owner
  case admin
  case coach
  case player
  case parent
  case inactive

  var id: String { rawValue }
  var title: String { rawValue.capitalized }
}

enum SDPlatformDirectory {
  static func organizations(
    _ organizations: [SDPlatformOrganization],
    matching query: String
  ) -> [SDPlatformOrganization] {
    let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
    return organizations.filter { organization in
      needle.isEmpty
        || organization.name.localizedCaseInsensitiveContains(needle)
        || organization.slug.localizedCaseInsensitiveContains(needle)
        || organization.id.uuidString.localizedCaseInsensitiveContains(needle)
    }.sorted {
      let comparison = $0.name.localizedCaseInsensitiveCompare($1.name)
      return comparison == .orderedSame
        ? $0.id.uuidString < $1.id.uuidString
        : comparison == .orderedAscending
    }
  }

  static func members(
    _ members: [SDPlatformMember],
    matching query: String,
    filter: SDPlatformMemberFilter
  ) -> [SDPlatformMember] {
    let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
    return members.filter { member in
      let matchesFilter: Bool = switch filter {
      case .all: true
      case .inactive: !member.isActive
      default: member.normalizedRole == filter.rawValue
      }
      guard matchesFilter else { return false }
      return needle.isEmpty
        || member.displayName.localizedCaseInsensitiveContains(needle)
        || member.username?.localizedCaseInsensitiveContains(needle) == true
        || member.email?.localizedCaseInsensitiveContains(needle) == true
    }.sorted {
      let comparison = $0.displayName.localizedCaseInsensitiveCompare($1.displayName)
      return comparison == .orderedSame
        ? $0.user_id.uuidString < $1.user_id.uuidString
        : comparison == .orderedAscending
    }
  }
}

struct SDPlatformMembersResponse: Decodable, Sendable {
  let organization: SDPlatformOrganizationSummary
  let members: [SDPlatformMember]
}

struct SDPlatformOrganizationSummary: Decodable, Equatable, Sendable {
  let id: UUID
  let slug: String
  let name: String
  let status: String
}

struct SDPlatformUsernameReference: Decodable, Equatable, Sendable {
  let username: String
  let org_id: UUID
}

struct SDPlatformUserDirectoryEntry: Identifiable, Decodable, Equatable, Sendable {
  var id: UUID { user_id }
  let user_id: UUID
  let email: String?
  let full_name: String?
  let usernames: [SDPlatformUsernameReference]
  let created_at: String?
  let last_activity: String?

  var displayName: String {
    let name = full_name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if !name.isEmpty { return name }
    let address = email?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if !address.isEmpty { return address }
    return "User \(user_id.uuidString.lowercased().prefix(8))"
  }
}

struct SDPlatformUserSearchResponse: Decodable, Sendable {
  let users: [SDPlatformUserDirectoryEntry]
}

struct SDPlatformAdministrator: Identifiable, Decodable, Equatable, Sendable {
  var id: UUID { user_id }
  let user_id: UUID
  let granted_at: String?
  let granted_by: UUID?
  let notes: String?
  let email: String?
  let full_name: String?
  let last_activity: String?

  var displayName: String {
    full_name?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
      ? full_name!
      : email ?? user_id.uuidString.lowercased()
  }
}

struct SDPlatformAdministratorsResponse: Decodable, Sendable {
  let administrators: [SDPlatformAdministrator]
}

struct SDPlatformMembershipUpdateResponse: Decodable, Sendable {
  let membership: SDPlatformMembershipRecord
  let idempotent_replay: Bool
}

struct SDPlatformMembershipRecord: Decodable, Equatable, Sendable {
  let org_id: UUID
  let user_id: UUID
  let role: String
  let status: String
}

struct SDPlatformAuditEntry: Identifiable, Decodable, Equatable, Sendable {
  let id: UUID
  let actor_id: UUID?
  let action: String
  let target_type: String
  let target_id: String?
  let org_id: UUID?
  let details: [String: SDJSONValue]
  let created_at: String?
}

struct SDPlatformAuditResponse: Decodable, Sendable {
  let entries: [SDPlatformAuditEntry]
}

struct SDPlatformOrganizationCreatePayload: Encodable, Equatable, Sendable {
  let action = "create_organization"
  let name: String
  let slug: String
  let plan: String
  let billing_email: String?
  let max_members: Int?
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
