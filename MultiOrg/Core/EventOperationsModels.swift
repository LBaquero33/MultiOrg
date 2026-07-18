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
