import Foundation

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

enum SDSelectedTeamResolver {
  static func resolve(
    persistedTeamId: UUID?,
    organizationId: UUID,
    seasonId: UUID,
    teams: [SDTeamOperationsTeam]
  ) -> UUID? {
    let authorized = teams.filter {
      $0.org_id == organizationId && $0.season_id == seasonId && $0.is_active
    }
    if let persistedTeamId, authorized.contains(where: { $0.id == persistedTeamId }) {
      return persistedTeamId
    }
    return authorized.first(where: { $0.is_primary })?.id ?? authorized.first?.id
  }
}
