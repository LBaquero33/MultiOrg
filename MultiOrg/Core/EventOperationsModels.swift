import Foundation

enum SDEventOperationType: String, Codable, CaseIterable, Sendable {
  case practiceDay = "practice_day"
  case gameDay = "game_day"
  case tournamentDay = "tournament_day"
  case meetingDay = "meeting_day"
  case travelDay = "travel_day"
  case generalEventDay = "general_event_day"

  var label: String {
    switch self {
    case .practiceDay: "Practice Day"
    case .gameDay: "Game Day"
    case .tournamentDay: "Tournament Day"
    case .meetingDay: "Meeting Day"
    case .travelDay: "Travel Day"
    case .generalEventDay: "Event Day"
    }
  }
}

enum SDEventOperationStatus: String, Codable, CaseIterable, Sendable {
  case notStarted = "not_started"
  case ready
  case inProgress = "in_progress"
  case paused
  case completed
  case cancelled

  var label: String { rawValue.replacingOccurrences(of: "_", with: " ").capitalized }
}

enum SDEventAvailabilityStatus: String, Codable, CaseIterable, Identifiable, Sendable {
  case unknown, available, unavailable, tentative, late
  case leavingEarly = "leaving_early"
  var id: String { rawValue }
  var label: String { rawValue.replacingOccurrences(of: "_", with: " ").capitalized }
}

enum SDEventAttendanceStatus: String, Codable, CaseIterable, Identifiable, Sendable {
  case notRecorded = "not_recorded"
  case present, absent, late, excused, injured, partial
  var id: String { rawValue }
  var label: String { rawValue.replacingOccurrences(of: "_", with: " ").capitalized }
}

enum SDEventChecklistPhase: String, Codable, Sendable {
  case preEvent = "pre_event"
  case activeEvent = "active_event"
  case postEvent = "post_event"
}

struct SDEventOperation: Identifiable, Codable, Equatable, Sendable {
  let id: UUID
  let organization_id: UUID
  let season_id: UUID
  let team_id: UUID
  let event_id: UUID
  let operation_type: SDEventOperationType
  let status: SDEventOperationStatus
  let scheduled_start_at: String
  let started_at: String?
  let started_by: UUID?
  let completed_at: String?
  let completed_by: UUID?
  let reopened_at: String?
  let reopened_by: UUID?
  let cancelled_at: String?
  let operational_summary: String?
  let internal_notes: String?
  let attendance_finalized_at: String?
  let version: Int
  let created_at: String?
  let updated_at: String?

  var primaryAction: String {
    switch status {
    case .notStarted: "Prepare"
    case .ready: operation_type == .gameDay ? "Start Game Day" : operation_type == .practiceDay ? "Start Practice" : "Start Check-In"
    case .inProgress: "Complete Event"
    case .paused: "Resume"
    case .completed, .cancelled: "Review Event"
    }
  }
}

struct SDEventOperationParticipant: Identifiable, Codable, Equatable, Sendable {
  let id: UUID
  let event_operation_id: UUID
  let organization_id: UUID?
  let season_id: UUID?
  let team_id: UUID?
  let event_id: UUID?
  let user_id: UUID
  let participant_type: String
  let expected: Bool
  let availability_status: SDEventAvailabilityStatus
  let availability_reason: String?
  let expected_arrival_at: String?
  let expected_departure_at: String?
  let availability_submitted_by: UUID?
  let availability_submitted_at: String?
  let availability_last_changed_at: String?
  let attendance_status: SDEventAttendanceStatus
  let arrival_at: String?
  let departure_at: String?
  let checked_in_by: UUID?
  let attendance_notes: String?
  let private_notes: String?
  let version: Int
  let created_at: String?
  let updated_at: String?
}

struct SDEventOperationChecklistItem: Identifiable, Codable, Equatable, Sendable {
  let id: UUID
  let event_operation_id: UUID
  let organization_id: UUID?
  let phase: SDEventChecklistPhase
  let title: String
  let details: String?
  let assigned_user_id: UUID?
  let due_at: String?
  let completed_at: String?
  let completed_by: UUID?
  let overridden_at: String?
  let overridden_by: UUID?
  let override_reason: String?
  let sort_order: Int?
  let source: String?
  let required: Bool
  let visibility: String
  let version: Int
  let created_at: String?
  let updated_at: String?

  var isHandled: Bool { completed_at != nil || overridden_at != nil }
}

struct SDEventOperationNote: Identifiable, Codable, Equatable, Sendable {
  let id: UUID
  let event_operation_id: UUID
  let organization_id: UUID?
  let note_type: String
  let visibility: String
  let subject_player_id: UUID?
  let body: String
  let published_at: String?
  let created_by: UUID?
  let updated_by: UUID?
  let version: Int
  let created_at: String?
  let updated_at: String?
}

struct SDEventOperationDetailResponse: Decodable, Sendable {
  let ok: Bool
  let operation: SDEventOperation?
  let participants: [SDEventOperationParticipant]?
  let checklist: [SDEventOperationChecklistItem]?
  let notes: [SDEventOperationNote]?
  let initialized: Bool?
  let replayed: Bool?
}

struct SDEventOperationSummary: Identifiable, Codable, Equatable, Sendable {
  let id: UUID
  let organization_id: UUID
  let season_id: UUID
  let team_id: UUID
  let event_id: UUID
  let operation_type: SDEventOperationType
  let status: SDEventOperationStatus
  let scheduled_start_at: String
  let attendance_finalized_at: String?
  let version: Int
  let expected_players: Int
  let unresolved_availability: Int
  let unrecorded_attendance: Int
  let checklist_total: Int
  let checklist_completed: Int
}

struct SDEventOperationListResponse: Decodable, Sendable {
  let ok: Bool
  let operations: [SDEventOperationSummary]
}

struct SDEventOperationMutationResponse: Decodable, Sendable {
  let ok: Bool
  let operation: SDEventOperation?
  let participant: SDEventOperationParticipant?
  let participants: [SDEventOperationParticipant]?
  let checklist_item: SDEventOperationChecklistItem?
  let note: SDEventOperationNote?
  let initialized: Bool?
  let replayed: Bool?
  let attention: Bool?
}

struct SDEventOperationAuditEntry: Identifiable, Codable, Equatable, Sendable {
  let id: UUID
  let event_operation_id: UUID
  let actor_id: UUID?
  let action: String
  let target_id: UUID?
  let previous_value: [String: SDJSONValue]?
  let new_value: [String: SDJSONValue]?
  let reason: String?
  let details: [String: SDJSONValue]?
  let created_at: String
}

struct SDEventOperationAuditResponse: Decodable, Sendable {
  let ok: Bool
  let operation: SDEventOperation
  let audit: [SDEventOperationAuditEntry]
}

struct SDEventAvailabilityDraft: Equatable, Sendable {
  var status: SDEventAvailabilityStatus = .unknown
  var reason = ""
  var expectedArrival: Date?
  var expectedDeparture: Date?
}

enum SDEventOperationDateParser {
  static func date(_ value: String?) -> Date? {
    guard let value else { return nil }
    let fractional = ISO8601DateFormatter()
    fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
  }
}

enum SDPracticePlanStatus: String, Codable, CaseIterable, Identifiable, Sendable {
  case draft, ready, published, active, completed, archived
  var id: String { rawValue }
  var label: String { rawValue.capitalized }
}

enum SDPracticeBlockType: String, Codable, CaseIterable, Identifiable, Sendable {
  case arrival, meeting, warmup
  case movementPrep = "movement_prep"
  case throwing
  case armCare = "arm_care"
  case defense, infield, outfield, catching, pitching, hitting, baserunning, strength, conditioning, competition, recovery, cooldown, custom
  var id: String { rawValue }
  var label: String { rawValue.replacingOccurrences(of: "_", with: " ").capitalized }
}

enum SDPracticeExecutionStatus: String, Codable, CaseIterable, Sendable {
  case pending, active, completed, skipped, adjusted
}

struct SDPracticePlan: Identifiable, Codable, Equatable, Sendable {
  let id: UUID
  let organization_id: UUID
  let season_id: UUID
  let team_id: UUID
  let event_id: UUID
  let event_operation_id: UUID?
  let source_template_id: UUID?
  let source_plan_id: UUID?
  let title: String
  let objectives: [String]
  let coach_notes: String?
  let status: SDPracticePlanStatus
  let is_primary: Bool
  let version: Int
  let published_version: Int?
  let published_at: String?
  let published_by: UUID?
  let current_snapshot_id: UUID?
  let archived_at: String?
  let updated_at: String?
}

struct SDPracticePlanBlock: Identifiable, Codable, Equatable, Sendable {
  let id: UUID
  let practice_plan_id: UUID
  let parent_block_id: UUID?
  let title: String
  let block_type: SDPracticeBlockType
  let sequence_index: Int
  let start_offset_minutes: Int
  let duration_minutes: Int
  let parallel_group_key: String?
  let station_name: String?
  let facility_id: UUID?
  let location_area: String?
  let objectives: [String]
  let instructions: String?
  let coaching_points: String?
  let equipment_notes: String?
  let visibility: String
  let required: Bool
  let version: Int
  let archived_at: String?
}

struct SDPracticePlanGroup: Identifiable, Codable, Equatable, Sendable {
  let id: UUID
  let practice_plan_id: UUID
  let name: String
  let description: String?
  let sort_order: Int
  let color_token: String?
  let active: Bool
  let version: Int
}

struct SDPracticePlanAssignment: Identifiable, Codable, Equatable, Sendable {
  let id: UUID
  let practice_plan_id: UUID
  let assignment_type: String
  let user_id: UUID?
  let group_id: UUID?
  let block_id: UUID?
  let assignment_role: String?
  let is_lead: Bool
  let version: Int
}

struct SDPracticeEquipmentRequirement: Identifiable, Codable, Equatable, Sendable {
  let id: UUID
  let practice_plan_id: UUID
  let block_id: UUID?
  let name: String
  let quantity: Int
  let required: Bool
  let prepared: Bool
  let notes: String?
  let visibility: String
  let version: Int
}

struct SDPracticeBlockExecution: Identifiable, Codable, Equatable, Sendable {
  let id: UUID
  let practice_plan_id: UUID
  let source_block_id: UUID
  let parent_block_id: UUID?
  let title: String
  let sequence_index: Int
  let planned_duration_minutes: Int
  let actual_duration_minutes: Int?
  let status: SDPracticeExecutionStatus
  let actual_started_at: String?
  let actual_completed_at: String?
  let adjustment_reason: String?
  let version: Int
}

struct SDPracticeValidationIssue: Codable, Equatable, Identifiable, Sendable {
  let code: String
  let planned_minutes: Int?
  let event_minutes: Int?
  var id: String { code }
  var label: String { code.replacingOccurrences(of: "_", with: " ").capitalized }
}

struct SDPracticePlanValidation: Codable, Equatable, Sendable {
  let blocking_errors: [SDPracticeValidationIssue]
  let readiness_warnings: [SDPracticeValidationIssue]
  let notices: [SDPracticeValidationIssue]
  let total_duration_minutes: Int
  let event_duration_minutes: Int
  let valid: Bool
}

struct SDPracticePlanDetailResponse: Decodable, Sendable {
  let ok: Bool
  let plan: SDPracticePlan?
  let blocks: [SDPracticePlanBlock]
  let groups: [SDPracticePlanGroup]
  let assignments: [SDPracticePlanAssignment]
  let equipment: [SDPracticeEquipmentRequirement]
  let executions: [SDPracticeBlockExecution]
  let validation: SDPracticePlanValidation?
}

struct SDPracticeMutationResponse: Decodable, Sendable {
  let ok: Bool
  let plan: SDPracticePlan?
  let block: SDPracticePlanBlock?
  let execution: SDPracticeBlockExecution?
  let group_id: UUID?
  let equipment_id: UUID?
  let template_id: UUID?
  let replayed: Bool?
}

struct SDPracticePlanTemplate: Identifiable, Codable, Equatable, Sendable {
  let id: UUID
  let organization_id: UUID
  let season_id: UUID?
  let team_id: UUID?
  let name: String
  let description: String?
  let objectives: [String]
  let snapshot: [String: SDJSONValue]
  let active: Bool
  let version: Int
  let archived_at: String?
}

struct SDPracticeTemplateListResponse: Decodable, Sendable {
  let ok: Bool
  let templates: [SDPracticePlanTemplate]
}

struct SDPracticePriorPlan: Identifiable, Codable, Equatable, Sendable {
  let id: UUID
  let event_id: UUID
  let title: String
  let status: SDPracticePlanStatus
  let objectives: [String]
  let updated_at: String?
}

struct SDPracticePriorPlanListResponse: Decodable, Sendable {
  let ok: Bool
  let plans: [SDPracticePriorPlan]
}

struct SDPracticePlanSummary: Identifiable, Codable, Equatable, Sendable {
  let id: UUID
  let organization_id: UUID
  let season_id: UUID
  let team_id: UUID
  let event_id: UUID
  let title: String
  let status: SDPracticePlanStatus
  let version: Int
  let published_version: Int?
  let published_at: String?
  let updated_at: String?
}

struct SDPracticePlanSummaryListResponse: Decodable, Sendable {
  let ok: Bool
  let plans: [SDPracticePlanSummary]
}

struct SDPracticePlanSnapshot: Identifiable, Codable, Equatable, Sendable {
  let id: UUID
  let practice_plan_id: UUID
  let event_operation_id: UUID?
  let snapshot_type: String
  let plan_version: Int
  let snapshot: [String: SDJSONValue]
  let reason: String?
  let created_by: UUID?
  let created_at: String
}

struct SDPracticePlanHistoryResponse: Decodable, Sendable {
  let ok: Bool
  let plan: SDPracticePlan
  let snapshots: [SDPracticePlanSnapshot]
}

enum SDGamePlanStatus: String, Codable, CaseIterable, Identifiable, Sendable {
  case draft, ready, published, active, completed, archived
  var id: String { rawValue }
  var label: String { rawValue.capitalized }
}

enum SDGameLineupMode: String, Codable, CaseIterable, Identifiable, Sendable {
  case standardNine = "standard_nine"
  case standardNineWithDH = "standard_nine_with_dh"
  case standardNineWithOneEH = "standard_nine_with_one_eh"
  case standardNineWithMultipleEH = "standard_nine_with_multiple_eh"
  case continuousBattingOrder = "continuous_batting_order"
  case batEntireAvailableRoster = "bat_entire_available_roster"
  case custom

  var id: String { rawValue }
  var label: String {
    switch self {
    case .standardNine: "Standard Nine"
    case .standardNineWithDH: "Standard Nine + DH"
    case .standardNineWithOneEH: "Standard Nine + One EH"
    case .standardNineWithMultipleEH: "Standard Nine + Multiple EH"
    case .continuousBattingOrder: "Continuous Batting Order"
    case .batEntireAvailableRoster: "Bat Entire Available Roster"
    case .custom: "Custom"
    }
  }

  var initializationAction: String {
    switch self {
    case .standardNine: "initialize_standard_nine"
    case .standardNineWithDH: "initialize_dh"
    case .standardNineWithOneEH: "initialize_one_eh"
    case .standardNineWithMultipleEH: "initialize_multiple_eh"
    case .continuousBattingOrder: "initialize_continuous_order"
    case .batEntireAvailableRoster: "initialize_bat_entire_roster"
    case .custom: "reconcile_batting_order"
    }
  }
}

enum SDGameOffensiveRole: String, Codable, CaseIterable, Identifiable, Sendable {
  case hitter, eh, dh
  case pitcherBatting = "pitcher_batting"
  case offensiveOnly = "offensive_only"
  case substitute
  case courtesyRunner = "courtesy_runner"
  case bench, custom
  var id: String { rawValue }
  var label: String {
    switch self {
    case .eh: "Extra Hitter"
    case .dh: "Designated Hitter"
    default: rawValue.replacingOccurrences(of: "_", with: " ").capitalized
    }
  }
}

struct SDGamePlan: Identifiable, Codable, Equatable, Sendable {
  let id: UUID
  let organization_id: UUID
  let season_id: UUID
  let team_id: UUID
  let event_id: UUID
  let event_operation_id: UUID?
  let title: String
  let status: SDGamePlanStatus
  let lineup_mode: SDGameLineupMode
  let rule_profile_id: UUID?
  let scheduled_innings: Int?
  let batting_order_locked: Bool
  let defense_plan_locked: Bool
  let is_primary: Bool
  let published_version: Int?
  let published_at: String?
  let published_by: UUID?
  let current_snapshot_id: UUID?
  let internal_strategy_notes: String?
  let player_reminders: String?
  let parent_reminders: String?
  let archived_at: String?
  let version: Int
  let created_at: String?
  let updated_at: String?
}

struct SDGameRuleProfile: Identifiable, Codable, Equatable, Sendable {
  let id: UUID
  let organization_id: UUID
  let season_id: UUID?
  let team_id: UUID?
  let tournament_event_id: UUID?
  let event_id: UUID?
  let name: String
  let innings: Int?
  let minimum_batting_slots: Int?
  let maximum_batting_slots: Int?
  let continuous_batting_order_allowed: Bool?
  let bat_entire_roster_allowed: Bool?
  let dh_allowed: Bool?
  let eh_allowed: Bool?
  let maximum_eh: Int?
  let defensive_only_players_allowed: Bool?
  let offensive_only_players_allowed: Bool?
  let reentry_policy: String?
  let courtesy_runner_policy: String?
  let pitcher_reentry_policy: String?
  let defensive_player_count: Int?
  let required_positions: [String]
  let custom_position_labels: [String]
  let notes: String?
  let active: Bool
  let version: Int
}

struct SDGameEligibility: Identifiable, Codable, Equatable, Sendable {
  let id: UUID
  let game_plan_id: UUID
  let player_id: UUID
  let status: String
  let exclusion_reason: String?
  let source_participant_version: Int?
  let version: Int
}

struct SDGameBattingEntry: Identifiable, Codable, Equatable, Sendable {
  let id: UUID
  let game_plan_id: UUID
  let player_id: UUID
  let batting_slot: Int?
  let offensive_role: SDGameOffensiveRole
  let role_label: String?
  let active: Bool
  let starter: Bool
  let eligible: Bool
  let source: String
  let notes: String?
  let version: Int
}

struct SDGameDefensiveAssignment: Identifiable, Codable, Equatable, Sendable {
  let id: UUID
  let game_plan_id: UUID
  let player_id: UUID
  let inning_number: Int
  let inning_half: String
  let position_code: String
  let position_label: String?
  let assignment_type: String
  let starter: Bool
  let planned: Bool
  let active: Bool
  let notes: String?
  let version: Int
}

struct SDGamePitcherCatcherPlan: Identifiable, Codable, Equatable, Sendable {
  let id: UUID
  let game_plan_id: UUID
  let player_id: UUID
  let role_type: String
  let sequence_index: Int
  let planned_start_inning: Int?
  let planned_end_inning: Int?
  let manual_pitch_limit: Int?
  let pairing_player_id: UUID?
  let notes: String?
  let status: String
  let version: Int
}

struct SDGameStaffAssignment: Identifiable, Codable, Equatable, Sendable {
  let id: UUID
  let game_plan_id: UUID
  let staff_user_id: UUID
  let responsibility_code: String
  let responsibility_label: String?
  let notes: String?
  let active: Bool
  let version: Int
}

struct SDGameResult: Identifiable, Codable, Equatable, Sendable {
  let id: UUID
  let game_plan_id: UUID
  let team_score: Int?
  let opponent_score: Int?
  let outcome: String
  let innings_played: Int?
  let ended_early: Bool
  let end_reason: String?
  let result_status: String
  let result_notes: String?
  let recorded_by: UUID?
  let recorded_at: String?
  let verified_by: UUID?
  let verified_at: String?
  let version: Int
}

struct SDGameRecap: Identifiable, Codable, Equatable, Sendable {
  let id: UUID
  let game_plan_id: UUID
  let visibility: String
  let subject_player_id: UUID?
  let body: String
  let follow_up_items: [String]
  let published_at: String?
  let version: Int
}

struct SDGameValidationFinding: Identifiable, Codable, Equatable, Sendable {
  let code: String
  let severity: String
  let actual: Int?
  let expected: Int?
  var id: String { "\(severity):\(code)" }
  var label: String { code.replacingOccurrences(of: "_", with: " ").capitalized }
}

struct SDGamePlanValidation: Codable, Equatable, Sendable {
  let blocking_errors: [SDGameValidationFinding]
  let readiness_warnings: [SDGameValidationFinding]
  let notices: [SDGameValidationFinding]
  let valid: Bool
  let batting_count: Int
  let eh_count: Int
}

struct SDGamePlanDetailResponse: Decodable, Sendable {
  let ok: Bool
  let plan: SDGamePlan?
  let rule_profile: SDGameRuleProfile?
  let eligibility: [SDGameEligibility]?
  let batting_order: [SDGameBattingEntry]?
  let defense: [SDGameDefensiveAssignment]?
  let pitcher_catcher: [SDGamePitcherCatcherPlan]?
  let staff: [SDGameStaffAssignment]?
  let recaps: [SDGameRecap]?
  let result: SDGameResult?
  let validation: SDGamePlanValidation?
  let capabilities: [SDTeamCapability]?
}

struct SDGamePlanSnapshot: Identifiable, Codable, Equatable, Sendable {
  let id: UUID
  let game_plan_id: UUID
  let event_operation_id: UUID?
  let snapshot_type: String
  let plan_version: Int
  let snapshot: [String: SDJSONValue]
  let reason: String?
  let created_by: UUID?
  let created_at: String
}

struct SDGamePlanHistoryResponse: Decodable, Sendable {
  let ok: Bool
  let plan: SDGamePlan
  let snapshots: [SDGamePlanSnapshot]
}

struct SDGamePlanSummary: Identifiable, Codable, Equatable, Sendable {
  let id: UUID
  let organization_id: UUID
  let season_id: UUID
  let team_id: UUID
  let event_id: UUID
  let title: String
  let status: SDGamePlanStatus
  let lineup_mode: SDGameLineupMode
  let version: Int
  let published_version: Int?
  let published_at: String?
  let updated_at: String?
}

struct SDGamePlanSummaryListResponse: Decodable, Sendable {
  let ok: Bool
  let plans: [SDGamePlanSummary]
}

struct SDGamePriorPlan: Identifiable, Codable, Equatable, Sendable {
  let id: UUID
  let event_id: UUID
  let title: String
  let status: SDGamePlanStatus
  let lineup_mode: SDGameLineupMode
  let published_version: Int?
  let updated_at: String?
}

struct SDGamePriorPlanListResponse: Decodable, Sendable {
  let ok: Bool
  let plans: [SDGamePriorPlan]
}

struct SDGameRuleProfileListResponse: Decodable, Sendable {
  let ok: Bool
  let rule_profiles: [SDGameRuleProfile]
}

struct SDGameMutationResponse: Decodable, Sendable {
  let ok: Bool
  let plan: SDGamePlan?
  let snapshot: SDGamePlanSnapshot?
  let started_snapshot: SDGamePlanSnapshot?
  let completion_snapshot: SDGamePlanSnapshot?
  let result: SDGameResult?
  let batting_entry_id: UUID?
  let defensive_assignment_id: UUID?
  let pitcher_catcher_id: UUID?
  let staff_assignment_id: UUID?
  let adjustment_id: UUID?
  let recap_id: UUID?
  let rule_profile_id: UUID?
  let initialized: Bool?
  let replayed: Bool?
  let capabilities: [SDTeamCapability]?
}
