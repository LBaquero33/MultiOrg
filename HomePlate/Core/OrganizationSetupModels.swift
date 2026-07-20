import Foundation

enum SDOrganizationSetupStep: String, CaseIterable, Codable, Identifiable, Sendable {
  case basics
  case season
  case teams
  case staff
  case playersFamilies = "players_families"
  case registrationFees = "registration_fees"
  case facilities
  case communication
  case firstBaseballAction = "first_baseball_action"
  case reviewLaunch = "review_launch"

  var id: String { rawValue }

  var title: String {
    switch self {
    case .basics: "Organization Basics"
    case .season: "Season"
    case .teams: "Teams"
    case .staff: "Staff"
    case .playersFamilies: "Players & Families"
    case .registrationFees: "Registration & Fees"
    case .facilities: "Facilities"
    case .communication: "Communication"
    case .firstBaseballAction: "First Baseball Action"
    case .reviewLaunch: "Review & Launch"
    }
  }

  var isOptional: Bool {
    switch self {
    case .staff, .playersFamilies, .registrationFees, .facilities,
         .communication, .firstBaseballAction: true
    default: false
    }
  }

  var next: SDOrganizationSetupStep {
    guard let index = Self.allCases.firstIndex(of: self) else { return self }
    return Self.allCases[min(index + 1, Self.allCases.count - 1)]
  }

  var previous: SDOrganizationSetupStep {
    guard let index = Self.allCases.firstIndex(of: self) else { return self }
    return Self.allCases[max(index - 1, 0)]
  }
}

enum SDOrganizationSetupStatus: String, Codable, Sendable {
  case notStarted = "not_started"
  case inProgress = "in_progress"
  case dismissed
  case ready
  case completed
}

enum SDOrganizationSetupStepState: String, Codable, Sendable {
  case notStarted = "not_started"
  case inProgress = "in_progress"
  case complete
  case skipped
  case needsAttention = "needs_attention"
}

struct SDOrganizationSetupSession: Identifiable, Decodable, Equatable, Sendable {
  let id: UUID
  let organization_id: UUID
  let status: SDOrganizationSetupStatus
  let current_step: SDOrganizationSetupStep
  let schema_version: Int
  let version: Int
  let started_by: UUID?
  let assisted_by: UUID?
  let started_at: String?
  let dismissed_at: String?
  let completed_at: String?
  let updated_at: String
  let created_at: String
}

struct SDOrganizationSetupStepRecord: Decodable, Equatable, Sendable {
  let organization_id: UUID
  let step: SDOrganizationSetupStep
  let state: SDOrganizationSetupStepState
  let data_version: Int
  let completed_at: String?
  let updated_at: String
}

struct SDOrganizationSetupDraft: Decodable, Equatable, Sendable {
  let organization_id: UUID
  let step: String
  let draft_key: String
  let payload: [String: SDJSONValue]
  let version: Int
  let updated_at: String
}

struct SDOrganizationSetupOrganization: Decodable, Equatable, Sendable {
  let id: UUID
  let name: String
  let status: String
  let organization_type: String?
  let timezone: String?
  let default_location: String?
  let phone: String?
  let website_host: String?
  let support_email: String?
}

struct SDOrganizationSetupReadinessItem: Identifiable, Decodable, Equatable, Sendable {
  var id: String { key }
  let key: String
  let label: String
  let required: Bool
  let complete: Bool
  let route_step: SDOrganizationSetupStep
}

struct SDOrganizationSetupReadiness: Decodable, Equatable, Sendable {
  let ready: Bool
  let items: [SDOrganizationSetupReadinessItem]
}

struct SDOrganizationSetupSnapshot: Decodable, Sendable {
  let session: SDOrganizationSetupSession?
  let steps: [SDOrganizationSetupStepRecord]
  let drafts: [SDOrganizationSetupDraft]
  let organization: SDOrganizationSetupOrganization
  let seasons: [SDSeason]
  let teams: [SDTeam]
  let readiness: SDOrganizationSetupReadiness
  let test_mode: Bool?
  let assisted: Bool?

  func state(for step: SDOrganizationSetupStep) -> SDOrganizationSetupStepState {
    steps.first(where: { $0.step == step })?.state ?? .notStarted
  }
}

enum SDOrganizationInvitationContext: String, Codable, CaseIterable, Sendable {
  case family
  case staff

  var title: String { self == .family ? "Family Invite Link" : "Coach Invite Link" }
  var invitedRole: String { self == .family ? "Parent or guardian" : "Coach or staff" }
}

enum SDOrganizationInvitationURL {
  static func token(from url: URL) -> String? {
    guard url.scheme?.lowercased() == "homeplate",
          url.host?.lowercased() == "invite" else { return nil }
    let components = url.pathComponents.filter { $0 != "/" }
    guard components.count == 1 else { return nil }
    let token = components[0]
    guard (40...100).contains(token.count),
          token.unicodeScalars.allSatisfy({ scalar in
            switch scalar.value {
            case 45, 48...57, 65...90, 95, 97...122: true
            default: false
            }
          }) else { return nil }
    return token
  }
}

struct SDOrganizationInvitationLink: Identifiable, Decodable, Equatable, Sendable {
  let id: UUID
  let organization_id: UUID
  let organization_name: String
  let invitation_context: SDOrganizationInvitationContext
  let intended_role: String
  let intended_team_id: UUID?
  let intended_responsibilities: [String]
  let expires_at: String
  let revoked_at: String?
  let accepted_at: String?
  let last_rotated_at: String?
  let use_count: Int
  let token_version: Int

  var isActive: Bool {
    revoked_at == nil && (SDTeamEventDateParser.date(expires_at) ?? .distantPast) > Date()
  }
}

struct SDOrganizationInvitationLinkMutation: Decodable, Sendable {
  let link: SDOrganizationInvitationLink
  let invitation_url: String?
}

struct SDOrganizationInvitationValidation: Decodable, Equatable, Sendable {
  let organization_id: UUID
  let organization_name: String
  let invitation_context: SDOrganizationInvitationContext
  let intended_role: String
  let intended_team_id: UUID?
  let intended_responsibilities: [String]
  let expires_at: String
  let accepted: Bool?
}

struct SDPendingTeamDraft: Identifiable, Equatable, Sendable {
  let id: UUID
  var existingTeamId: UUID?
  var name = ""
  var ageGroup = ""
  var level = ""
  var rosterCapacity = ""

  init(id: UUID = UUID(), existingTeamId: UUID? = nil) {
    self.id = id
    self.existingTeamId = existingTeamId
  }

  var validationError: String? {
    if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Enter a team name." }
    if !rosterCapacity.isEmpty, (Int(rosterCapacity) ?? 0) <= 0 { return "Roster capacity must be a positive whole number." }
    return nil
  }
}

enum SDStaffResponsibility: String, CaseIterable, Identifiable, Codable, Sendable {
  case headCoach = "head_coach"
  case assistantCoach = "assistant_coach"
  case teamManager = "team_manager"
  case hittingCoach = "hitting_coach"
  case pitchingCoach = "pitching_coach"
  case catchingCoach = "catching_coach"
  case strengthCoach = "strength_coach"
  case evaluator
  case readOnly = "read_only"

  var id: String { rawValue }
  var title: String { rawValue.split(separator: "_").map { $0.capitalized }.joined(separator: " ") }
}

struct SDStaffInviteDraft: Identifiable, Equatable, Sendable {
  let id: UUID
  var email = ""
  var displayName = ""
  var responsibility: SDStaffResponsibility = .headCoach
  var teamId: UUID?

  init(id: UUID = UUID()) { self.id = id }

  var normalizedEmail: String { email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
  var hasValidEmail: Bool {
    normalizedEmail.range(of: #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#, options: .regularExpression) != nil
  }
}

enum SDRegistrationSetupChoice: String, CaseIterable, Identifiable, Sendable {
  case configureNow = "Configure Now"
  case later = "Later"
  case no = "No"
  var id: String { rawValue }
}

enum SDOrganizationSetupTimeCodec {
  static func timeZoneDisplayName(identifier: String, locale: Locale = .current) -> String? {
    guard let zone = TimeZone(identifier: identifier) else { return nil }
    return zone.localizedName(for: .standard, locale: locale) ?? identifier
  }

  static func instant(
    date: Date,
    time: Date,
    timeZoneIdentifier: String,
    calendar base: Calendar = Calendar(identifier: .gregorian)
  ) -> Date? {
    guard let zone = TimeZone(identifier: timeZoneIdentifier) else { return nil }
    var displayCalendar = base
    displayCalendar.timeZone = zone
    let day = displayCalendar.dateComponents([.year, .month, .day], from: date)
    let clock = displayCalendar.dateComponents([.hour, .minute], from: time)
    var components = DateComponents()
    components.timeZone = zone
    components.year = day.year
    components.month = day.month
    components.day = day.day
    components.hour = clock.hour
    components.minute = clock.minute
    return displayCalendar.date(from: components)
  }

  static func isoUTC(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.string(from: date)
  }

  static func validates(arrival: Date, start: Date, end: Date) -> Bool {
    arrival <= start && start < end
  }
}

struct SDOrganizationSetupMutationResponse: Decodable, Sendable {
  let setup: SDOrganizationSetupSnapshot
  let entity_id: UUID?
  let replayed: Bool?
}

struct SDOrganizationSetupResetPreview: Decodable, Sendable {
  struct Candidate: Identifiable, Decodable, Sendable {
    var id: String { "\(entity_type):\(entity_id.uuidString)" }
    let entity_type: String
    let entity_id: UUID
    let setup_test_run_id: UUID?
    let created_at: String
  }
  let candidates: [Candidate]
  let protected_history_preserved: Bool
  let full_organization_reset_available: Bool
}

struct SDOrganizationSetupTestConfiguration: Equatable, Sendable {
  static let maristOrganizationId = UUID(
    uuidString: "800e22ae-2a9d-4109-9e11-1360eeaa8ea7"
  )!

  let enabled: Bool
  let organizationId: UUID?
  let environmentAllowed: Bool

  var isConfigured: Bool { enabled && organizationId != nil && environmentAllowed }

  func allows(organizationId requestedId: UUID, hasAuthority: Bool) -> Bool {
    isConfigured && organizationId == Self.maristOrganizationId &&
      requestedId == Self.maristOrganizationId && hasAuthority
  }

  static func current(
    environment: [String: String] = ProcessInfo.processInfo.environment,
    bundle: Bundle = .main
  ) -> Self {
    func value(_ key: String) -> String? {
      environment[key] ?? bundle.object(forInfoDictionaryKey: key) as? String
    }
    let enabled = value("HOME_PLATE_SETUP_TEST_MODE")?.lowercased() == "true"
    let organizationId = value("HOME_PLATE_SETUP_TEST_ORGANIZATION_ID")
      .flatMap(UUID.init(uuidString:)) ?? Self.maristOrganizationId
    let appEnvironment = value("HOME_PLATE_ENVIRONMENT")?.lowercased() ?? ""
    return Self(
      enabled: enabled,
      organizationId: organizationId,
      environmentAllowed: ["local", "development", "staging", "testflight"].contains(appEnvironment)
    )
  }
}

enum SDOrganizationSetupRequestGuard {
  static func accepts(
    responseOrganizationId: UUID,
    responseToken: UUID,
    activeOrganizationId: UUID?,
    currentToken: UUID?,
    taskIsCancelled: Bool
  ) -> Bool {
    !taskIsCancelled && responseOrganizationId == activeOrganizationId && responseToken == currentToken
  }
}

enum SDOrganizationSetupErrorMapper {
  static func message(for error: Error) -> String? {
    if SDApplicationErrorClassifier.isCancellation(error, taskIsCancelled: Task.isCancelled) { return nil }
    if let edge = error as? SDEdgeFunctionHTTPError {
      switch edge.code {
      case "stale_setup_version":
        return "This setup changed in another window. Refresh to keep your entries and continue from the latest version."
      case "setup_access_required", "setup_management_required", "organization_membership_required":
        return "You no longer have permission to manage organization setup."
      case "organization_name_and_timezone_required":
        return "Enter an organization name and choose a valid timezone."
      case "season_name_required":
        return "Enter a season name."
      case "team_name_and_season_required", "at_least_one_team_required":
        return "Add at least one named team to the selected season."
      case "valid_event_scope_and_time_required":
        return "Choose a team and valid arrival, start, and end times."
      case "invitation_expired", "invitation_revoked":
        return "This invitation link has expired. Generate a new link."
      default:
        break
      }
    }
    if let category = SDApplicationErrorClassifier.presentation(for: error)?.category {
      switch category {
      case .notDeployed, .serviceUnavailable: return "Organization setup is not available in this environment. Your entries are still here."
      case .offline: return "You’re offline. Your entries are still here; reconnect and try again."
      case .forbidden: return "You no longer have permission to manage this organization."
      case .validation: return "We could not save this step. Check the highlighted entries; your work is still here."
      default: break
      }
    }
    return "We could not save this step. Your entries are still here. Try again."
  }
}
