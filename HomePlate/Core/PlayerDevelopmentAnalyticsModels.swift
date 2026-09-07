import Foundation

enum SDPlayerAnalyticsDiscipline: String, Codable, CaseIterable, Identifiable, Sendable {
  case hitting
  case pitching

  var id: String { rawValue }
  var title: String { rawValue.capitalized }
  var sourceRole: String { self == .hitting ? "hitter" : "pitcher" }

  var modules: [(key: String, label: String)] {
    switch self {
    case .hitting:
      [
        ("overview_quality", "Overview & Quality"),
        ("contact_spray", "Contact & Spray"),
        ("swing_decisions", "Swing Decisions"),
        ("count_approach", "Count Approach"),
        ("velocity_exposure", "Velocity Exposure"),
        ("zone_maps", "Zone Maps"),
        ("two_strikes", "Two Strikes"),
      ]
    case .pitching:
      [
        ("overview_arsenal", "Overview & Arsenal"),
        ("velocity_extension", "Velocity & Extension"),
        ("pitch_break_shape", "Pitch Break & Shape"),
        ("release_location", "Release, Arm Slot & Location"),
        ("counts_finish", "Counts & Finish"),
        ("pitch_log", "Pitch Log"),
      ]
    }
  }
}

struct SDPlayerAnalyticsSource: Identifiable, Codable, Equatable, Sendable {
  let id: UUID
  let provider: String
  let fileName: String
  let rowCount: Int
  let completedAt: String
  let selectedSourcePlayerName: String?
  let selectedSourcePlayerRole: String?

  enum CodingKeys: String, CodingKey {
    case id, provider
    case fileName = "file_name"
    case rowCount = "row_count"
    case completedAt = "completed_at"
    case selectedSourcePlayerName = "selected_source_player_name"
    case selectedSourcePlayerRole = "selected_source_player_role"
  }
}

struct SDPlayerAnalyticsSourcesResponse: Codable, Equatable, Sendable {
  let sourceStatus: String
  let sourceMessage: String?
  let sources: [SDPlayerAnalyticsSource]

  enum CodingKeys: String, CodingKey {
    case sources
    case sourceStatus = "source_status"
    case sourceMessage = "source_message"
  }
}

struct SDPlayerAnalyticsMetric: Identifiable, Codable, Equatable, Sendable {
  let key: String
  let label: String
  let value: SDJSONValue
  let unit: String?
  let guidance: String?
  let provisional: Bool?

  var id: String { key }

  var displayValue: String {
    switch value {
    case .double(let number): return Self.number(number)
    case .int(let number): return String(number)
    case .bool(let flag): return flag ? "Yes" : "No"
    case .string(let text): return text
    case .null: return "No data"
    default: return "Available"
    }
  }

  private static func number(_ value: Double) -> String {
    value.rounded() == value ? String(Int(value)) : String(format: "%.2f", value)
  }
}

struct SDPlayerAnalyticsTableColumn: Codable, Equatable, Sendable {
  let key: String
  let label: String
}

struct SDPlayerAnalyticsTable: Identifiable, Codable, Equatable, Sendable {
  let id: String
  let title: String
  let description: String?
  let columns: [SDPlayerAnalyticsTableColumn]
  let rows: [[String: SDJSONValue]]
}

struct SDPlayerAnalyticsChart: Identifiable, Codable, Equatable, Sendable {
  let id: String
  let title: String
  let description: String?
  let type: String
  let x: String?
  let y: String?
  let series: String?
  let data: [[String: SDJSONValue]]
  let options: [String: SDJSONValue]?
}

struct SDPlayerAnalyticsResponse: Codable, Equatable, Sendable {
  struct SampleSummary: Codable, Equatable, Sendable {
    let rows: Int?
    let dates: Int?
    let provider: String?
  }

  struct BenchmarkSummary: Codable, Equatable, Sendable {
    let status: String?
    let cohort: String?
  }

  struct Guidance: Codable, Equatable, Sendable {
    let summary: String?
    let sampleNote: String?

    enum CodingKeys: String, CodingKey {
      case summary
      case sampleNote = "sample_note"
    }
  }

  let schemaVersion: Int
  let modelVersion: String
  let benchmarkVersion: String
  let generatedAt: String
  let discipline: String
  let module: String
  let sampleSummary: SampleSummary
  let benchmarkSummary: BenchmarkSummary
  let summaryMetrics: [SDPlayerAnalyticsMetric]
  let tables: [SDPlayerAnalyticsTable]
  let charts: [SDPlayerAnalyticsChart]
  let guidance: Guidance
  let warnings: [String]
  let cacheStatus: String?

  enum CodingKeys: String, CodingKey {
    case discipline, module, tables, charts, guidance, warnings
    case schemaVersion = "schema_version"
    case modelVersion = "model_version"
    case benchmarkVersion = "benchmark_version"
    case generatedAt = "generated_at"
    case sampleSummary = "sample_summary"
    case benchmarkSummary = "benchmark_summary"
    case summaryMetrics = "summary_metrics"
    case cacheStatus = "cache_status"
  }
}
