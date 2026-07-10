import Foundation

struct SDProgramTemplate: Identifiable, Decodable, Equatable {
  let id: UUID
  let org_id: UUID?
  let coach_id: UUID
  let name: String
  let weeks: Int
  let lift_weekdays: [Int]
  let created_at: Date?
  let updated_at: Date?
}

struct SDProgramAssignment: Identifiable, Decodable, Equatable {
  let id: UUID
  let org_id: UUID?
  let player_id: UUID
  let coach_id: UUID
  let template_id: UUID
  let start_date: String
  let ended_at: Date?
  let notes: String?
  let created_at: Date?
  let updated_at: Date?
}

struct SDProgramDay: Identifiable, Decodable, Equatable {
  let id: UUID
  let template_id: UUID
  let week: Int
  let day_index: Int
  let exercises: [SDExercise]
  let created_at: Date?
  let updated_at: Date?
}

struct SDExercise: Codable, Hashable, Equatable, Identifiable {
  var id: UUID
  var name: String
  var sets: Int?
  var reps: String?
  var unit: String?
  var notes: String?

  init(id: UUID = UUID(), name: String, sets: Int?, reps: String?, unit: String?, notes: String?) {
    self.id = id
    self.name = name
    self.sets = sets
    self.reps = reps
    self.unit = unit
    self.notes = notes
  }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
    name = (try? c.decode(String.self, forKey: .name)) ?? ""
    sets = try? c.decodeIfPresent(Int.self, forKey: .sets)
    reps = try? c.decodeIfPresent(String.self, forKey: .reps)
    unit = try? c.decodeIfPresent(String.self, forKey: .unit)
    notes = try? c.decodeIfPresent(String.self, forKey: .notes)
  }
}

struct SDExerciseLibraryItem: Identifiable, Decodable, Equatable {
  let id: UUID
  let org_id: UUID?
  let coach_id: UUID
  let name: String
  let name_norm: String
  let usage_count: Int
  let last_used_at: Date?
  let created_at: Date?
  let updated_at: Date?
}

struct SDFacility: Identifiable, Decodable, Equatable {
  let id: UUID
  let org_id: UUID?
  let name: String
  let is_active: Bool
  let sort_order: Int
  let resource_type: String?
  let color_hex: String?
  let capacity: Int?
  let created_at: Date?
  let updated_at: Date?
}

struct SDFacilityBooking: Identifiable, Decodable, Equatable {
  let id: UUID
  let org_id: UUID?
  let facility_id: UUID
  let span_facility_id: UUID?
  let player_id: UUID?
  let created_by: UUID
  let is_block: Bool
  let status: String
  let activity_type: String
  let start_at: Date
  let end_at: Date
  let coach_id: UUID?
  let approved_by: UUID?
  let approved_at: Date?
  let title: String?
  let notes: String?
  let created_at: Date?
  let updated_at: Date?
}

struct SDDailyLog: Identifiable, Decodable, Equatable {
  let id: UUID
  let org_id: UUID?
  let player_id: UUID
  let log_date: String
  let comments: String?
  let feel: Int?
  let got_video: Bool?
  let ate_breakfast: Bool?
  let hit_daily_goals: Bool?
  let stuck_to_process: Bool?
  let fell_short: String?
  let excelled: String?
  let created_at: Date?
  let updated_at: Date?
}

struct SDStrengthLog: Identifiable, Decodable, Equatable {
  let id: UUID
  let org_id: UUID?
  let player_id: UUID
  let log_date: String
  let assignment_id: UUID?
  let template_id: UUID?
  let week: Int?
  let day_index: Int?
  let exercise_name: String
  let no_weight: Bool
  let set_weights_json: [String]?
  let sets_completed: Int?
  let notes: String?
  let created_at: Date?
  let updated_at: Date?
}

struct SDTestingEntry: Identifiable, Decodable, Equatable {
  let id: UUID
  let org_id: UUID?
  let player_id: UUID
  let entry_date: String
  let height_in: Double?
  let weight_lb: Double?
  let squat_1rm: Double?
  let bench_1rm: Double?
  let deadlift_1rm: Double?
  let max_exit_velo: Double?
  let avg_exit_velo: Double?
  let hip_er_diff: Double?
  let hip_ir_diff: Double?
  let shoulder_ir_diff: Double?
  let shoulder_er_diff: Double?
  let notes: String?
  let created_at: Date?
  let updated_at: Date?
}

struct SDBPSession: Identifiable, Decodable, Equatable {
  let id: UUID
  let org_id: UUID?
  let player_id: UUID
  let session_date: String
  let source: String
  let reps_type: String
  let created_at: Date?
  let updated_at: Date?
}

struct SDBPEvent: Identifiable, Decodable, Equatable {
  let id: UUID
  let session_id: UUID
  let pitch_num: Int?
  let exit_velo: Double?
  let distance: Double?
  let launch_angle: Double?
  let strike_x: Double?
  let strike_z: Double?
  let created_at: Date?
}

struct SDPlayerOnboarding: Identifiable, Decodable, Equatable {
  var id: UUID { player_id }
  let org_id: UUID?
  let player_id: UUID
  let improve_focus: String
  let improve_plan: String?
  let daily_goals: String?
  let completed_at: Date?
  let created_at: Date?
  let updated_at: Date?

  var isComplete: Bool { completed_at != nil }
}

struct SDAccessEntitlement: Identifiable, Decodable, Equatable {
  var id: UUID { user_id }
  let org_id: UUID?
  let user_id: UUID
  let is_active: Bool
  let source: String?
  let current_period_end: Date?
  let created_at: Date?
  let updated_at: Date?
}
