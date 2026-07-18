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
  let enabled: Bool
  let organizationId: UUID?
  let environmentAllowed: Bool

  var isConfigured: Bool { enabled && organizationId != nil && environmentAllowed }

  func allows(organizationId requestedId: UUID, hasAuthority: Bool) -> Bool {
    isConfigured && organizationId == requestedId && hasAuthority
  }

  static func current(
    environment: [String: String] = ProcessInfo.processInfo.environment,
    bundle: Bundle = .main
  ) -> Self {
    func value(_ key: String) -> String? {
      environment[key] ?? bundle.object(forInfoDictionaryKey: key) as? String
    }
    let enabled = value("HOME_PLATE_SETUP_TEST_MODE")?.lowercased() == "true"
    let organizationId = value("HOME_PLATE_SETUP_TEST_ORGANIZATION_ID").flatMap(UUID.init(uuidString:))
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
