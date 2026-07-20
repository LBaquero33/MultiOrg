import Foundation

enum SDOrgAdminAction: String, CaseIterable, Codable, Sendable {
  case teamContext = "team_context"
  case createSeason = "create_season"
  case updateSeason = "update_season"
  case assignTeamSeason = "assign_team_season"
  case assignPlayerTeam = "assign_player_team"
  case unassignPlayerTeam = "unassign_player_team"
  case assignCoachTeam = "assign_coach_team"
  case getPlayerAccess = "get_player_access"
  case setPlayerAccess = "set_player_access"
  case listMembers = "list_members"
  case createUser = "create_user"
  case updateMember = "update_member"
  case setUsername = "set_username"
  case listTeams = "list_teams"
  case createTeam = "create_team"
  case updateTeam = "update_team"
  case assignTeamMember = "assign_team_member"
  case removeTeamMember = "remove_team_member"
}

struct SDSeasonDraft: Equatable, Sendable {
  let organizationId: UUID?
  var name: String
  var startDate: String?
  var endDate: String?
  var lifecycle: SDSeasonLifecycle
  var isDefault: Bool

  enum ValidationIssue: Equatable, Sendable {
    case missingOrganization
    case missingName
    case invalidStartDate
    case invalidEndDate
    case endBeforeStart

    var message: String {
      switch self {
      case .missingOrganization: "Select an organization before creating a season."
      case .missingName: "Enter a season name."
      case .invalidStartDate: "Choose a valid start date."
      case .invalidEndDate: "Choose a valid end date."
      case .endBeforeStart: "End date must be on or after the start date."
      }
    }
  }

  var validationIssue: ValidationIssue? {
    guard organizationId != nil else { return .missingOrganization }
    guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return .missingName
    }
    let start = normalizedDate(startDate)
    let end = normalizedDate(endDate)
    if startDate?.isEmpty == false, start == nil { return .invalidStartDate }
    if endDate?.isEmpty == false, end == nil { return .invalidEndDate }
    if let start, let end, end < start { return .endBeforeStart }
    return nil
  }

  var isValid: Bool { validationIssue == nil }

  private func normalizedDate(_ value: String?) -> String? {
    guard let value, !value.isEmpty else { return nil }
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd"
    formatter.isLenient = false
    guard let date = formatter.date(from: value), formatter.string(from: date) == value else {
      return nil
    }
    return value
  }
}

enum SDOrganizationCapability: String, Codable, Hashable, Sendable {
  case viewTeamCommunication = "view_team_communication"
  case createOrgAnnouncement = "create_org_announcement"
  case viewDeliveryStatus = "view_delivery_status"
  case manageNotificationDelivery = "manage_notification_delivery"
  case viewRegistrationOfferings = "view_registration_offerings"
  case manageRegistrationOfferings = "manage_registration_offerings"
  case reviewRegistrations = "review_registrations"
  case assignRegisteredPlayer = "assign_registered_player"
  case manageSeasonLifecycle = "manage_season_lifecycle"
  case executeSeasonRollover = "execute_season_rollover"
  case viewFinancialOverview = "view_financial_overview"
  case createInvoice = "create_invoice"
  case recordPayment = "record_payment"
  case manageExpenses = "manage_expenses"
  case viewOrgAnalytics = "view_org_analytics"
  case runReports = "run_reports"
  case exportReports = "export_reports"
}

struct SDRegistrationOffering: Identifiable, Codable, Equatable, Sendable {
  let id: UUID
  let organization_id: UUID
  let season_id: UUID
  let team_id: UUID?
  let offering_type: String
  let name: String
  let description: String?
  let opens_at: String
  let closes_at: String
  let capacity: Int?
  let waitlist_capacity: Int?
  let fee_cents: Int
  let deposit_cents: Int
  let state: String
  let visibility: String
  let accepting_submissions: Bool?
}

struct SDRegistrationApplication: Identifiable, Codable, Equatable, Sendable {
  let id: UUID
  let organization_id: UUID
  let season_id: UUID
  let offering_id: UUID
  let applicant_user_id: UUID
  let player_user_id: UUID?
  let guardian_user_id: UUID?
  let state: String
  let fee_cents: Int
  let balance_cents: Int?
  let fee_status: String?
  let submitted_at: String?
  let version: Int
  let created_at: String
}

struct SDRegistrationOfferingsResponse: Decodable, Sendable {
  let offerings: [SDRegistrationOffering]
}

struct SDRegistrationApplicationsResponse: Decodable, Sendable {
  let applications: [SDRegistrationApplication]
}

struct SDRegistrationApplicationResponse: Decodable, Sendable {
  let application: SDRegistrationApplication
}

struct SDRegistrationCommandResult: Decodable, Sendable {
  let application: SDRegistrationApplication
  let replayed: Bool?
}

struct SDRegistrationCommandResponse: Decodable, Sendable {
  let result: SDRegistrationCommandResult
}

// MARK: - Phase 12Y role-scoped Today aggregation

enum SDTodayRole: String, Codable, CaseIterable, Sendable {
  case coach, player, parent, owner, admin

  var isOrganizationAdministrator: Bool { self == .owner || self == .admin }
}

enum SDTodayServiceAvailability: String, Codable, CaseIterable, Sendable {
  case available, loading, stale, unavailable, unauthorized, offline
}

struct SDTodayServiceState: Codable, Equatable, Sendable {
  let state: SDTodayServiceAvailability
  let message: String?
  let as_of: String?

  static let available = Self(state: .available, message: nil, as_of: nil)

  var preservesAuthoritativeEmptyState: Bool { state == .available }
}

enum SDTodayUrgency: String, Codable, CaseIterable, Sendable {
  case urgent, important, informational

  var rank: Int {
    switch self {
    case .urgent: 0
    case .important: 1
    case .informational: 2
    }
  }
}

struct SDTodayAction: Codable, Equatable, Identifiable, Sendable {
  let id: String
  let label: String
  let route: String
  let capability: String?
}

struct SDTodayMission: Codable, Equatable, Identifiable, Sendable {
  let id: String
  let source_type: String
  let source_id: UUID
  let mission_type: String
  let title: String
  let subtitle: String?
  let status: String
  let start_at: String?
  let arrival_at: String?
  let end_at: String?
  let location: String?
  let team_id: UUID?
  let team_name: String?
  let season_id: UUID?
  let child_id: UUID?
  let child_name: String?
  let urgency: SDTodayUrgency
  let is_current: Bool
  let is_next: Bool
  let requires_review: Bool
  let operation_state: String?
  let plan_state: String?
  let availability_unresolved: Int?
  let attendance_unresolved: Int?
  let lineup_mode: String?
  let eh_count: Int?
  let batting_slot: Int?
  let offensive_role: String?
  let defensive_assignment: String?
  let pitcher_catcher_assignment: String?
  let primary_action: SDTodayAction?
  let secondary_actions: [SDTodayAction]
  let attention_count: Int
  let deep_link: String?

  var arrivalDate: Date? { SDTodayDateParser.date(arrival_at) }
  var startDate: Date? { SDTodayDateParser.date(start_at) }
  var endDate: Date? { SDTodayDateParser.date(end_at) }
}

struct SDTodayAttentionItem: Codable, Equatable, Identifiable, Sendable {
  let id: String
  let source_type: String
  let source_id: UUID?
  let category: String
  let severity: SDTodayUrgency
  let title: String
  let detail: String?
  let due_at: String?
  let action: SDTodayAction?
  let deep_link: String?
}

struct SDTodaySummaryItem: Codable, Equatable, Identifiable, Sendable {
  let category: String
  let label: String
  let value: String
  let status: String?
  let as_of: String?
  let action: SDTodayAction?
  var id: String { category }
}

struct SDTodayContext: Codable, Equatable, Sendable {
  let organization_id: UUID
  let organization_name: String
  let role: SDTodayRole
  let season_id: UUID?
  let season_name: String?
  let team_id: UUID?
  let team_name: String?
  let child_id: UUID?
  let child_name: String?
  let local_date: String
  let timezone: String
  let scope_type: String
  let context_token: String
}

struct SDTodayResponse: Codable, Equatable, Sendable {
  let context: SDTodayContext
  let missions: [SDTodayMission]
  let attention_items: [SDTodayAttentionItem]
  let summaries: [SDTodaySummaryItem]
  let primary_action: SDTodayAction?
  let secondary_actions: [SDTodayAction]
  let services: [String: SDTodayServiceState]
  let capabilities: [String]
  let generated_at: String
  let as_of: String

  func service(_ name: String) -> SDTodayServiceState {
    services[name] ?? SDTodayServiceState(
      state: .unavailable,
      message: "This section is temporarily unavailable.",
      as_of: nil
    )
  }
}

enum SDTodayDateParser {
  static func date(_ value: String?) -> Date? {
    guard let value else { return nil }
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
  }
}

enum SDTodayMissionOrdering {
  static func ordered(_ missions: [SDTodayMission], now: Date = Date()) -> [SDTodayMission] {
    missions.sorted { left, right in
      let leftKey = key(left, now: now)
      let rightKey = key(right, now: now)
      if leftKey.priority != rightKey.priority { return leftKey.priority < rightKey.priority }
      if leftKey.date != rightKey.date { return leftKey.date < rightKey.date }
      return left.id < right.id
    }
  }

  private static func key(_ mission: SDTodayMission, now: Date) -> (priority: Int, date: Date) {
    let status = mission.status.lowercased()
    if mission.is_current || ["in_progress", "active", "paused"].contains(mission.operation_state?.lowercased() ?? "") {
      return (0, mission.arrivalDate ?? mission.startDate ?? .distantFuture)
    }
    if !["cancelled", "postponed"].contains(status),
       let arrival = mission.arrivalDate,
       arrival <= now,
       (mission.endDate ?? mission.startDate ?? .distantPast) >= now {
      return (1, arrival)
    }
    if mission.is_next { return (2, mission.arrivalDate ?? mission.startDate ?? .distantFuture) }
    if !["completed", "cancelled", "postponed"].contains(status),
       (mission.startDate ?? .distantPast) >= now {
      return (3, mission.arrivalDate ?? mission.startDate ?? .distantFuture)
    }
    if mission.requires_review { return (4, mission.startDate ?? .distantFuture) }
    return (5, mission.startDate ?? .distantFuture)
  }
}

enum SDTodayAttentionOrdering {
  static func ordered(_ items: [SDTodayAttentionItem]) -> [SDTodayAttentionItem] {
    items.sorted {
      if $0.severity.rank != $1.severity.rank { return $0.severity.rank < $1.severity.rank }
      let leftDate = SDTodayDateParser.date($0.due_at) ?? .distantFuture
      let rightDate = SDTodayDateParser.date($1.due_at) ?? .distantFuture
      if leftDate != rightDate { return leftDate < rightDate }
      return $0.id < $1.id
    }
  }
}

enum SDTodayPrimaryActionResolver {
  static func coachAction(
    eventType: String,
    eventStatus: String,
    operationState: String?,
    planState: String?,
    unresolvedAvailability: Int,
    unresolvedAttendance: Int,
    capabilities: Set<String>
  ) -> SDTodayAction? {
    func action(_ id: String, _ label: String, _ capability: String) -> SDTodayAction? {
      guard capabilities.contains(capability) else { return nil }
      return SDTodayAction(id: id, label: label, route: "event", capability: capability)
    }
    if eventStatus == "cancelled" || eventStatus == "postponed" { return action("review_event", "Review Event", "view_event_operation") }
    if operationState == "completed" {
      if unresolvedAttendance > 0 { return action("resolve_attendance", "Resolve Attendance", "manage_event_attendance") }
      return action("review_completed", "Review Completed Event", "view_event_operation")
    }
    if operationState == "in_progress" { return action("complete_event", "Complete Event", "complete_event_operation") }
    if operationState == "paused" {
      return action(eventType == "game" ? "resume_game" : "resume_practice", eventType == "game" ? "Resume Game Day" : "Resume Practice", eventType == "game" ? "manage_game" : "manage_practice")
    }
    if unresolvedAvailability > 0 { return action("review_availability", "Review Availability", "manage_event_availability") }
    if eventType == "practice", planState == nil { return action("prepare_practice", "Prepare Practice", "create_practice_plan") }
    if eventType == "practice", ["draft", "ready"].contains(planState ?? "") { return action("review_practice", "Review Practice Plan", "edit_practice_plan") }
    if eventType == "practice", planState == "published" { return action("start_practice", "Start Practice", "start_event_operation") }
    if eventType == "game", planState == nil { return action("prepare_game", "Prepare Game", "create_game_plan") }
    if eventType == "game", ["draft", "ready"].contains(planState ?? "") { return action("build_lineup", "Build Lineup", "manage_batting_order") }
    if eventType == "game", planState == "published" { return action("start_game", "Start Game Day", "start_event_operation") }
    return action("start_check_in", "Start Check-In", "start_event_operation")
  }
}

enum SDSeasonLifecycle: String, CaseIterable, Codable, Identifiable, Sendable {
  case planning
  case registrationOpen = "registration_open"
  case rosterBuilding = "roster_building"
  case active
  case playoffs
  case completed
  case archived

  var id: String { rawValue }

  var label: String {
    switch self {
    case .planning: "Planning"
    case .registrationOpen: "Registration Open"
    case .rosterBuilding: "Roster Building"
    case .active: "Active"
    case .playoffs: "Playoffs"
    case .completed: "Completed"
    case .archived: "Archived"
    }
  }

  func canTransition(to target: SDSeasonLifecycle) -> Bool {
    switch (self, target) {
    case (.planning, .registrationOpen), (.planning, .archived),
         (.registrationOpen, .rosterBuilding), (.registrationOpen, .planning),
         (.rosterBuilding, .active), (.rosterBuilding, .registrationOpen),
         (.active, .playoffs), (.active, .completed),
         (.playoffs, .completed), (.completed, .archived): true
    default: false
    }
  }
}

struct SDSeason: Identifiable, Codable, Equatable, Sendable {
  let id: UUID
  let organization_id: UUID
  let name: String
  let start_date: String?
  let end_date: String?
  let status: SDSeasonLifecycle
  let is_default: Bool
  let created_by: UUID?
  let updated_by: UUID?
  let created_at: String?
  let updated_at: String?
}

enum SDTeamResponsibility: String, CaseIterable, Codable, Identifiable, Sendable {
  case headCoach = "head_coach"
  case assistantCoach = "assistant_coach"
  case hittingCoach = "hitting_coach"
  case pitchingCoach = "pitching_coach"
  case catchingCoach = "catching_coach"
  case strengthCoach = "strength_coach"
  case teamManager = "team_manager"
  case evaluator
  case readOnly = "read_only"

  var id: String { rawValue }

  var label: String {
    switch self {
    case .headCoach: "Head Coach"
    case .assistantCoach: "Assistant Coach"
    case .hittingCoach: "Hitting Coach"
    case .pitchingCoach: "Pitching Coach"
    case .catchingCoach: "Catching Coach"
    case .strengthCoach: "Strength Coach"
    case .teamManager: "Team Manager"
    case .evaluator: "Evaluator"
    case .readOnly: "Read Only"
    }
  }
}

enum SDTeamCapability: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
  case viewTeam = "view_team"
  case manageRoster = "manage_roster"
  case manageSchedule = "manage_schedule"
  case manageAttendance = "manage_attendance"
  case managePractice = "manage_practice"
  case manageGame = "manage_game"
  case messageTeam = "message_team"
  case viewDevelopment = "view_development"
  case editDevelopment = "edit_development"
  case manageStaff = "manage_staff"
  case viewDocuments = "view_documents"
  case manageDocuments = "manage_documents"
  case viewTeamSchedule = "view_team_schedule"
  case createTeamEvent = "create_team_event"
  case editTeamEvent = "edit_team_event"
  case cancelTeamEvent = "cancel_team_event"
  case managePracticeEvent = "manage_practice_event"
  case manageGameEvent = "manage_game_event"
  case manageTournamentEvent = "manage_tournament_event"
  case manageMeetingEvent = "manage_meeting_event"
  case manageTravelEvent = "manage_travel_event"
  case viewEventOperation = "view_event_operation"
  case startEventOperation = "start_event_operation"
  case manageEventAttendance = "manage_event_attendance"
  case manageEventAvailability = "manage_event_availability"
  case manageEventChecklist = "manage_event_checklist"
  case addTeamEventNotes = "add_team_event_notes"
  case addPrivatePlayerNotes = "add_private_player_notes"
  case completeEventOperation = "complete_event_operation"
  case reopenEventOperation = "reopen_event_operation"
  case viewPracticePlan = "view_practice_plan"
  case createPracticePlan = "create_practice_plan"
  case editPracticePlan = "edit_practice_plan"
  case publishPracticePlan = "publish_practice_plan"
  case archivePracticePlan = "archive_practice_plan"
  case managePracticeTemplates = "manage_practice_templates"
  case assignPracticePlayers = "assign_practice_players"
  case assignPracticeCoaches = "assign_practice_coaches"
  case assignPracticeGroups = "assign_practice_groups"
  case managePracticeEquipment = "manage_practice_equipment"
  case viewStartedPracticeSnapshot = "view_started_practice_snapshot"
  case modifyActivePracticePlan = "modify_active_practice_plan"
  case executePracticeBlocks = "execute_practice_blocks"
  case completePracticePlan = "complete_practice_plan"
  case reopenPracticePlan = "reopen_practice_plan"
  case viewGamePlan = "view_game_plan"
  case createGamePlan = "create_game_plan"
  case editGamePlan = "edit_game_plan"
  case publishGamePlan = "publish_game_plan"
  case archiveGamePlan = "archive_game_plan"
  case configureGameRules = "configure_game_rules"
  case manageBattingOrder = "manage_batting_order"
  case manageDefensivePlan = "manage_defensive_plan"
  case managePitcherCatcherPlan = "manage_pitcher_catcher_plan"
  case manageGameStaff = "manage_game_staff"
  case manageGameChecklist = "manage_game_checklist"
  case viewStartedGameSnapshot = "view_started_game_snapshot"
  case modifyActiveGamePlan = "modify_active_game_plan"
  case recordGameResult = "record_game_result"
  case completeGameOperation = "complete_game_operation"
  case reopenGameOperation = "reopen_game_operation"

  var id: String { rawValue }

  var label: String {
    rawValue.replacingOccurrences(of: "_", with: " ").capitalized
  }
}

struct SDPlayerTeamMembership: Identifiable, Codable, Equatable, Sendable {
  let id: UUID
  let player_id: UUID
  let organization_id: UUID
  let season_id: UUID
  let team_id: UUID
  let started_at: String
  let ended_at: String?
  let active: Bool
  let assignment_reason: String?
  let transfer_metadata: [String: SDJSONValue]?
  let created_by: UUID?
  let created_at: String?
  let updated_at: String?
}

struct SDCoachTeamAssignment: Identifiable, Codable, Equatable, Sendable {
  let id: UUID
  let coach_id: UUID
  let organization_id: UUID
  let season_id: UUID
  let team_id: UUID
  let is_primary: Bool
  let organization_wide_access: Bool
  let started_at: String
  let ended_at: String?
  let active: Bool
  let created_by: UUID?
  let created_at: String?
  let updated_at: String?
  let responsibilities: [SDTeamResponsibility]
  let capabilities: [SDTeamCapability]
}

struct SDTeamOperationsTeam: Identifiable, Codable, Equatable, Sendable {
  let id: UUID
  let org_id: UUID
  let season_id: UUID
  let name: String
  let color_hex: String?
  let description: String?
  let age_group: String?
  let competitive_level: String?
  let roster_capacity: Int?
  let is_active: Bool
  let sort_order: Int
  let created_by: UUID?
  let created_at: String?
  let updated_at: String?
  let is_primary: Bool
  let roster_count: Int
  let staff_count: Int
  let capabilities: [SDTeamCapability]

  var capabilitySet: Set<SDTeamCapability> { Set(capabilities) }
}

struct SDTeamOperationsContext: Decodable, Equatable, Sendable {
  let seasons: [SDSeason]
  let teams: [SDTeamOperationsTeam]
  let player_memberships: [SDPlayerTeamMembership]
  let coach_assignments: [SDCoachTeamAssignment]
  let people: [Profile]
  let can_access_all_teams: Bool

  var activeSeason: SDSeason? {
    seasons.first(where: { $0.is_default })
      ?? seasons.first(where: { $0.status == .active })
      ?? seasons.first
  }

  func players(for teamId: UUID) -> [Profile] {
    let playerIds = Set(
      player_memberships
        .filter { $0.team_id == teamId && $0.active && $0.ended_at == nil }
        .map(\.player_id)
    )
    return people.filter { playerIds.contains($0.id) }.sorted {
      $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
    }
  }

  func staff(for teamId: UUID) -> [Profile] {
    let coachIds = Set(
      coach_assignments
        .filter { $0.team_id == teamId && $0.active && $0.ended_at == nil }
        .map(\.coach_id)
    )
    return people.filter { coachIds.contains($0.id) }.sorted {
      $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
    }
  }
}

/// Declares the context a root workspace is allowed to consume. A selected
/// team is deliberately not part of organization-scoped workspace identity.
enum HPWorkspaceScope: String, CaseIterable, Codable, Equatable, Sendable {
  case organization
  case selectedTeam = "selected_team"
  case allAssignedTeams = "all_assigned_teams"
  case scheduleFilter = "schedule_filter"
  case selectedPlayer = "selected_player"
  case selectedChild = "selected_child"
  case platform
  case account
}

struct HPTeamContext: Equatable, Sendable {
  let organizationId: UUID
  let seasonId: UUID
  let teamId: UUID
  let teamName: String
  let ageGroup: String?
  let level: String?
  let isActive: Bool
  let selectionSource: SDTeamSelectionSource
  let actorCapabilities: Set<SDTeamCapability>
  let availableTeamCount: Int
  let updatedAt: Date
  let contextToken: UUID
}

enum HPWorkspaceCacheKey {
  static let schemaVersion = 1

  static func organization(
    userId: UUID,
    organizationId: UUID,
    action: String
  ) -> String {
    ["organization", "v\(schemaVersion)", userId.uuidString, organizationId.uuidString, action]
      .map { $0.lowercased() }
      .joined(separator: ":")
  }

  static func selectedTeam(
    userId: UUID,
    organizationId: UUID,
    seasonId: UUID,
    teamId: UUID,
    action: String
  ) -> String {
    [
      "team", "v\(schemaVersion)", userId.uuidString, organizationId.uuidString,
      seasonId.uuidString, teamId.uuidString, action,
    ]
    .map { $0.lowercased() }
    .joined(separator: ":")
  }

  static func schedule(
    userId: UUID,
    organizationId: UUID,
    seasonId: UUID?,
    visibleTeamFilterId: UUID?,
    action: String
  ) -> String {
    [
      "schedule", "v\(schemaVersion)", userId.uuidString, organizationId.uuidString,
      seasonId?.uuidString ?? "all-seasons", visibleTeamFilterId?.uuidString ?? "all-teams", action,
    ]
    .map { $0.lowercased() }
    .joined(separator: ":")
  }
}

enum HPTeamSelectionPersistence {
  static let schemaVersion = 2

  static func key(userId: UUID, organizationId: UUID) -> String {
    "homePlate.selectedTeam.v\(schemaVersion).\(userId.uuidString.lowercased()).\(organizationId.uuidString.lowercased())"
  }

  static func legacyKey(userId: UUID, organizationId: UUID, seasonId: UUID) -> String {
    "homePlate.selectedTeam.\(userId.uuidString.lowercased()).\(organizationId.uuidString.lowercased()).\(seasonId.uuidString.lowercased())"
  }
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
    let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
    let values = Dictionary(
      uniqueKeysWithValues: (components?.queryItems ?? []).compactMap { item in
        item.value.map { (item.name.lowercased(), $0) }
      }
    )
    let pathTeamId = url.pathComponents.dropFirst().first.flatMap(UUID.init(uuidString:))
    guard let organizationId = values["organization_id"].flatMap(UUID.init(uuidString:)),
          let teamId = values["team_id"].flatMap(UUID.init(uuidString:)) ?? pathTeamId else {
      return nil
    }
    self.organizationId = organizationId
    self.teamId = teamId
    section = values["section"].flatMap(HPTeamWorkspaceSection.init(rawValue:)) ?? .overview
  }
}

enum SDSelectedTeamResolver {
  struct Resolution: Equatable, Sendable {
    let teamId: UUID?
    let source: SDTeamSelectionSource
  }

  static func resolve(
    explicitTeamId: UUID?,
    persistedTeamId: UUID?,
    organizationId: UUID,
    seasonId: UUID,
    teams: [SDTeamOperationsTeam]
  ) -> Resolution {
    let authorized = teams.filter {
      $0.org_id == organizationId && $0.season_id == seasonId && $0.is_active
    }
    if let explicitTeamId, authorized.contains(where: { $0.id == explicitTeamId }) {
      return Resolution(teamId: explicitTeamId, source: .explicit)
    }
    if let persistedTeamId, authorized.contains(where: { $0.id == persistedTeamId }) {
      return Resolution(teamId: persistedTeamId, source: .persisted)
    }
    if let primary = authorized.first(where: { $0.is_primary }) {
      return Resolution(teamId: primary.id, source: .primaryAssignment)
    }
    if let first = authorized.first {
      return Resolution(teamId: first.id, source: .firstActiveTeam)
    }
    return Resolution(teamId: nil, source: .none)
  }

  static func resolve(
    persistedTeamId: UUID?,
    organizationId: UUID,
    seasonId: UUID,
    teams: [SDTeamOperationsTeam]
  ) -> UUID? {
    resolve(
      explicitTeamId: nil,
      persistedTeamId: persistedTeamId,
      organizationId: organizationId,
      seasonId: seasonId,
      teams: teams
    ).teamId
  }
}

enum SDTeamSelectionSource: String, Equatable, Sendable {
  case explicit
  case persisted
  case primaryAssignment = "primary_assignment"
  case firstActiveTeam = "first_active_team"
  case derivedPlayer = "derived_player"
  case derivedChild = "derived_child"
  case none
}

enum SDTeamWorkspaceIssue: Equatable, Sendable {
  case noTeams
  case noAuthorizedTeams
  case noCurrentAssignment
  case permission
  case serviceUnavailable
  case offline
  case staleData
  case unknown

  init(error: Error) {
    switch SDApplicationErrorClassifier.presentation(for: error)?.category {
    case .offline: self = .offline
    case .unauthorized, .forbidden: self = .permission
    case .serviceUnavailable, .notDeployed, .unsupportedAction: self = .serviceUnavailable
    case .staleData: self = .staleData
    default: self = .unknown
    }
  }

  var title: String {
    switch self {
    case .noTeams: "No teams yet"
    case .noAuthorizedTeams: "No authorized teams"
    case .noCurrentAssignment: "No current team assignment"
    case .permission: "Team access is restricted"
    case .serviceUnavailable: "Team service unavailable"
    case .offline: "You’re offline"
    case .staleData: "Team information may be out of date"
    case .unknown: "Team information couldn’t be loaded"
    }
  }

  var message: String {
    switch self {
    case .noTeams: "Create a team to begin organizing the season."
    case .noAuthorizedTeams: "Ask an organization administrator to grant team access."
    case .noCurrentAssignment: "Choose a team or ask an administrator to add an assignment."
    case .permission: "You don’t have permission to view this team."
    case .serviceUnavailable: "This feature is temporarily unavailable."
    case .offline: "Check your connection and try again."
    case .staleData: "Showing the last available team information. Try refreshing."
    case .unknown: "Home Plate couldn’t load team information. Try again."
    }
  }

  var allowsRetry: Bool {
    ![.noTeams, .noAuthorizedTeams, .noCurrentAssignment, .permission].contains(self)
  }
}
