import Foundation

typealias SDWARRecord = [String: SDJSONValue]

struct SDWARWorkspace: Decodable, Sendable {
  let access: SDWARRecord
  let athletes: [SDWARRecord]
  let staff: [SDWARRecord]
  let profiles: [SDWARRecord]
  let assignments: [SDWARRecord]
  let services: [SDWARRecord]
  let service_trainers: [SDWARRecord]
  let availability: [SDWARRecord]
  let availability_exceptions: [SDWARRecord]
  let appointments: [SDWARRecord]
  let participants: [SDWARRecord]
  let outcomes: [SDWARRecord]
  let packages: [SDWARRecord]
  let ledger: [SDWARRecord]
  let testing_templates: [SDWARRecord]
  let testing_sessions: [SDWARRecord]
  let testing_results: [SDWARRecord]
  let locations: [SDWARRecord]
  let resources: [SDWARRecord]
  let imports: [SDWARRecord]
  let site: SDWARRecord?
  let public_profiles: [SDWARRecord]
  let source_diagnostics: SDWARSourceDiagnostics

  var unavailableSources: [String] { source_diagnostics.unavailable_sources }
  var isManager: Bool {
    access.warBool("is_admin") || access.warString("staff_kind") == "front_desk"
  }
}

struct SDWARSourceDiagnostics: Decodable, Sendable {
  let unavailable_sources: [String]
}

struct SDWARMutationResponse: Decodable, Sendable {
  let athlete: SDWARRecord?
  let assignment: SDWARRecord?
  let availability: SDWARRecord?
  let profile: SDWARRecord?
  let service: SDWARRecord?
  let ledger_entry: SDWARRecord?
  let appointment: SDWARRecord?
  let template: SDWARRecord?
  let session: SDWARRecord?
}

struct SDWARAnalyticsTable: Decodable, Sendable, Identifiable {
  struct Column: Decodable, Sendable {
    let key: String
    let label: String
  }

  let id: String
  let title: String
  let description: String?
  let columns: [Column]
  let rows: [SDWARRecord]
}

struct SDWARAnalyticsResponse: Decodable, Sendable {
  let schema_version: Int
  let model_version: String
  let benchmark_version: String?
  let discipline: String
  let module: String
  let sample_summary: SDWARRecord
  let source_coverage: SDWARRecord
  let summary_metrics: [SDWARRecord]
  let tables: [SDWARAnalyticsTable]
  let charts: [SDWARRecord]
  let guidance: SDWARRecord
  let warnings: [SDJSONValue]
  let unavailable_reasons: [SDWARRecord]
}

extension Dictionary where Key == String, Value == SDJSONValue {
  var warRecordID: String {
    warString("id", fallback: warString("source_hash", fallback: "missing-record-id"))
  }

  func warString(_ key: String, fallback: String = "") -> String {
    self[key]?.stringValue ?? fallback
  }

  func warUUID(_ key: String) -> UUID? {
    UUID(uuidString: warString(key))
  }

  func warBool(_ key: String) -> Bool {
    self[key]?.boolValue ?? false
  }

  func warInt(_ key: String) -> Int? {
    self[key]?.intValue
  }

  func warDisplay(_ key: String, fallback: String = "—") -> String {
    let value = warString(key).trimmingCharacters(in: .whitespacesAndNewlines)
    return value.isEmpty ? fallback : value
  }
}

extension SupabaseService {
  func fetchWARWorkspace(organizationId: UUID) async throws -> SDWARWorkspace {
    try await invokeAuthenticatedFunction(
      "war-operations",
      body: [
        "action": SDJSONValue.string("get_workspace"),
        "org_id": SDJSONValue.string(organizationId.uuidString.lowercased()),
      ]
    )
  }

  func performWARAction(
    organizationId: UUID,
    action: String,
    payload: SDWARRecord = [:]
  ) async throws -> SDWARMutationResponse {
    var body = payload
    body["action"] = .string(action)
    body["org_id"] = .string(organizationId.uuidString.lowercased())
    return try await invokeAuthenticatedFunction("war-operations", body: body)
  }

  func runWARAnalytics(
    organizationId: UUID,
    athleteId: UUID,
    module: String,
    provider: String? = nil
  ) async throws -> SDWARAnalyticsResponse {
    var body: SDWARRecord = [
      "action": .string("run_analysis"),
      "org_id": .string(organizationId.uuidString.lowercased()),
      "player_id": .string(athleteId.uuidString.lowercased()),
      "discipline": .string("performance"),
      "module": .string(module),
      "filters": .object([:]),
    ]
    if let provider, !provider.isEmpty { body["provider"] = .string(provider) }
    return try await invokeAuthenticatedFunction("player-development-analytics", body: body)
  }
}

@MainActor
final class WAROperationsWorkspaceModel: ObservableObject {
  @Published private(set) var workspace: SDWARWorkspace?
  @Published private(set) var analytics: SDWARAnalyticsResponse?
  @Published private(set) var isLoading = false
  @Published private(set) var isSaving = false
  @Published private(set) var isAnalyzing = false
  @Published var loadError: String?
  @Published var operationError: String?
  @Published var confirmation: String?

  private var contextOrganizationId: UUID?

  func load(service: SupabaseService?, organizationId: UUID?) async {
    guard let service, let organizationId else {
      workspace = nil
      loadError = "Select WAR Performance to open this workspace."
      return
    }
    contextOrganizationId = organizationId
    isLoading = true
    loadError = nil
    do {
      let loaded = try await service.fetchWARWorkspace(organizationId: organizationId)
      guard contextOrganizationId == organizationId else { return }
      workspace = loaded
    } catch is CancellationError {
      return
    } catch {
      guard contextOrganizationId == organizationId else { return }
      loadError = SDApplicationErrorClassifier.alertMessage(for: error)
        ?? "WAR operations could not be loaded."
    }
    if contextOrganizationId == organizationId { isLoading = false }
  }

  func mutate(
    service: SupabaseService?,
    organizationId: UUID?,
    action: String,
    payload: SDWARRecord,
    confirmation successMessage: String
  ) async -> Bool {
    guard let service, let organizationId, !isSaving else { return false }
    isSaving = true
    operationError = nil
    do {
      _ = try await service.performWARAction(
        organizationId: organizationId,
        action: action,
        payload: payload
      )
      confirmation = successMessage
      await load(service: service, organizationId: organizationId)
      isSaving = false
      return true
    } catch is CancellationError {
      isSaving = false
      return false
    } catch {
      operationError = SDApplicationErrorClassifier.alertMessage(for: error)
        ?? "That WAR update could not be completed."
      isSaving = false
      return false
    }
  }

  func analyze(
    service: SupabaseService?,
    organizationId: UUID?,
    athleteId: UUID?,
    module: String,
    provider: String?
  ) async {
    guard let service, let organizationId, let athleteId else { return }
    isAnalyzing = true
    operationError = nil
    do {
      analytics = try await service.runWARAnalytics(
        organizationId: organizationId,
        athleteId: athleteId,
        module: module,
        provider: provider
      )
    } catch is CancellationError {
      return
    } catch {
      operationError = SDApplicationErrorClassifier.alertMessage(for: error)
        ?? "The selected WAR analysis could not be generated."
    }
    isAnalyzing = false
  }
}
