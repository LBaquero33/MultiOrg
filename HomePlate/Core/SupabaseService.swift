import Foundation
import Supabase

enum SDApplicationErrorCategory: String, Equatable, Sendable {
  case offline
  case unauthorized
  case forbidden
  case serviceUnavailable = "service_unavailable"
  case notDeployed = "feature_not_deployed"
  case staleData = "stale_data"
  case validation
  case unsupportedAction = "unsupported_action"
  case malformedResponse = "malformed_response"
  case serverError = "server_error"
  case unknown
}

struct SDUserFacingError: Equatable, Sendable {
  let category: SDApplicationErrorCategory
  let message: String
  let allowsRetry: Bool
}

struct SDServiceError: LocalizedError, Equatable, Sendable {
  let category: SDApplicationErrorCategory
  let functionName: String?
  let statusCode: Int?

  var errorDescription: String? {
    SDApplicationErrorClassifier.presentation(for: self)?.message
  }
}

enum SDApplicationErrorClassifier {
  static func isCancellation(
    _ error: Error,
    taskIsCancelled: Bool = false
  ) -> Bool {
    taskIsCancelled || error is CancellationError || isCancellation(error as NSError, depth: 0)
  }

  static func presentation(
    for error: Error,
    taskIsCancelled: Bool = false
  ) -> SDUserFacingError? {
    guard !isCancellation(error, taskIsCancelled: taskIsCancelled) else { return nil }

    if let controlled = error as? SDServiceError {
      return presentation(for: controlled.category)
    }
    if error is SDTeamScheduleContractError {
      return presentation(for: .malformedResponse)
    }
    if let functionError = error as? FunctionsError {
      switch functionError {
      case .httpError(let statusCode, _):
        return presentation(for: category(forHTTPStatus: statusCode))
      case .relayError:
        return presentation(for: .serviceUnavailable)
      }
    }
    if let edgeError = error as? SDEdgeFunctionHTTPError {
      if ["unknown_action", "unsupported_action"].contains(edgeError.code) {
        return presentation(for: .unsupportedAction)
      }
      return presentation(for: category(forHTTPStatus: edgeError.statusCode))
    }
    if let urlError = error as? URLError {
      switch urlError.code {
      case .notConnectedToInternet, .networkConnectionLost:
        return presentation(for: .offline)
      case .userAuthenticationRequired, .userCancelledAuthentication:
        return presentation(for: .unauthorized)
      case .timedOut, .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed:
        return presentation(for: .serviceUnavailable)
      default:
        return presentation(for: .serverError)
      }
    }
    if let postgrestError = error as? PostgrestError {
      if postgrestError.code == "42501" { return presentation(for: .forbidden) }
      if postgrestError.code?.hasPrefix("22") == true {
        return presentation(for: .validation)
      }
      return presentation(for: .serverError)
    }
    if error is DecodingError { return presentation(for: .serverError) }
    return presentation(for: .unknown)
  }

  static func alertMessage(
    for error: Error,
    taskIsCancelled: Bool = false
  ) -> String? {
    presentation(for: error, taskIsCancelled: taskIsCancelled)?.message
  }

  static func log(
    _ error: Error,
    functionName: String? = nil,
    statusCode: Int? = nil
  ) {
    #if DEBUG
    let function = functionName ?? "none"
    let status = statusCode.map(String.init) ?? "none"
    print(
      "service_diagnostic function=\(function) status=\(status) "
        + "error_type=\(String(reflecting: type(of: error)))"
    )
    #endif
  }

  private static func category(forHTTPStatus statusCode: Int) -> SDApplicationErrorCategory {
    switch statusCode {
    case 401: .unauthorized
    case 403: .forbidden
    case 404: .notDeployed
    case 408, 429, 502, 503, 504: .serviceUnavailable
    case 400, 409, 422: .validation
    case 500...599: .serverError
    default: .unknown
    }
  }

  private static func presentation(
    for category: SDApplicationErrorCategory
  ) -> SDUserFacingError {
    switch category {
    case .offline:
      SDUserFacingError(category: category, message: "You’re offline. Check your connection and try again.", allowsRetry: true)
    case .unauthorized:
      SDUserFacingError(category: category, message: "Please sign in again to continue.", allowsRetry: false)
    case .forbidden:
      SDUserFacingError(category: category, message: "You don’t have permission to do that.", allowsRetry: false)
    case .serviceUnavailable, .notDeployed:
      SDUserFacingError(category: category, message: "This feature is temporarily unavailable.", allowsRetry: true)
    case .staleData:
      SDUserFacingError(category: category, message: "This information changed. Refresh and try again.", allowsRetry: true)
    case .validation:
      SDUserFacingError(category: category, message: "Check the information and try again.", allowsRetry: false)
    case .unsupportedAction:
      SDUserFacingError(category: category, message: "This action is not available in this version.", allowsRetry: false)
    case .malformedResponse:
      SDUserFacingError(category: category, message: "This feature is temporarily unavailable.", allowsRetry: true)
    case .serverError:
      SDUserFacingError(category: category, message: "Home Plate couldn’t complete the request. Try again.", allowsRetry: true)
    case .unknown:
      SDUserFacingError(category: category, message: "Something went wrong. Try again.", allowsRetry: true)
    }
  }

  private static func isCancellation(_ error: NSError, depth: Int) -> Bool {
    guard depth < 8 else { return false }
    if error.domain == NSURLErrorDomain, error.code == NSURLErrorCancelled { return true }
    if error.domain == "Swift.CancellationError" { return true }
    if let underlying = error.userInfo[NSUnderlyingErrorKey] as? Error,
       isCancellation(underlying as NSError, depth: depth + 1) {
      return true
    }
    if let underlyingErrors = error.userInfo["NSMultipleUnderlyingErrors"] as? [Error],
       underlyingErrors.contains(where: { isCancellation($0 as NSError, depth: depth + 1) }) {
      return true
    }
    return false
  }
}

enum SDAsyncRequestGuard {
  static func accepts<Context: Equatable>(
    responseContext: Context,
    responseToken: UUID,
    activeContext: Context,
    currentToken: UUID?,
    taskIsCancelled: Bool = false
  ) -> Bool {
    !taskIsCancelled && responseContext == activeContext && responseToken == currentToken
  }
}

private enum SessionRestoreError: LocalizedError {
  case missing
  case expired

  var errorDescription: String? {
    switch self {
    case .missing: return "No saved session."
    case .expired: return "Your saved session expired. Please sign in again."
    }
  }
}

@MainActor
final class SupabaseService: ObservableObject {
  let client: SupabaseClient

  private var exerciseLibraryCache: [SDExerciseLibraryItem]?
  private var exerciseLibraryCacheLoadedAt: Date?

  // Realtime listeners (coach)
  private var facilityBookingRequestsChannel: RealtimeChannelV2?
  private var facilityBookingRequestsTask: Task<Void, Never>?

  // Realtime listeners (chat)
  private var chatMessagesChannel: RealtimeChannelV2?
  private var chatMessagesTask: Task<Void, Never>?

  struct FacilityBookingRequest: Sendable, Equatable {
    let bookingId: UUID
    let facilityId: UUID
    let playerId: UUID?
    let isBlock: Bool
    let status: String
    let activityType: String
    let startAt: Date
    let endAt: Date
    let title: String?
  }

  private struct ProfileInsert: Encodable {
    let id: UUID
    let full_name: String?
  }

  private struct ProfileNamePatch: Encodable {
    let full_name: String?
  }

  init(config: SupabaseConfig) {
    self.client = SupabaseClient(
      supabaseURL: config.url,
      supabaseKey: config.anonKey,
      options: .init(
        auth: .init(
          autoRefreshToken: true,
          emitLocalSessionAsInitialSession: true
        )
      )
    )
  }

  // MARK: - Realtime (coach notifications)

  func startFacilityBookingRequestListener(
    onPendingInsert: @escaping @Sendable (FacilityBookingRequest) -> Void
  ) async throws {
    if facilityBookingRequestsChannel != nil { return }

    // Note: Postgres changes are gated by RLS and the table must be added to `supabase_realtime` publication.
    let channel = client.channel("sd_facility_booking_requests")
    facilityBookingRequestsChannel = channel

    let inserts = channel.postgresChange(InsertAction.self, schema: "public", table: "sd_facility_bookings")

    facilityBookingRequestsTask = Task.detached(priority: .background) {

      // Parse ISO8601 timestamps coming from Realtime payloads.
      let iso = ISO8601DateFormatter()
      iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

      func parseUUID(_ v: AnyJSON?) -> UUID? {
        guard let s = v?.stringValue else { return nil }
        return UUID(uuidString: s)
      }
      func parseBool(_ v: AnyJSON?) -> Bool? {
        if let b = v?.boolValue { return b }
        if let s = v?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
          if ["true", "t", "1", "yes", "y", "on"].contains(s) { return true }
          if ["false", "f", "0", "no", "n", "off"].contains(s) { return false }
        }
        return nil
      }
      func parseDate(_ v: AnyJSON?) -> Date? {
        guard let s = v?.stringValue else { return nil }
        return iso.date(from: s)
      }

      for await ins in inserts {
        let rec = ins.record

        let status = rec["status"]?.stringValue?.lowercased() ?? ""
        let isBlock = parseBool(rec["is_block"]) ?? false
        if status != "pending" || isBlock { continue }

        guard
          let bookingId = parseUUID(rec["id"]),
          let facilityId = parseUUID(rec["facility_id"]),
          let startAt = parseDate(rec["start_at"]),
          let endAt = parseDate(rec["end_at"])
        else { continue }

        let playerId = parseUUID(rec["player_id"])
        let activityType = rec["activity_type"]?.stringValue ?? "Request"
        let title = rec["title"]?.stringValue

        let req = FacilityBookingRequest(
          bookingId: bookingId,
          facilityId: facilityId,
          playerId: playerId,
          isBlock: isBlock,
          status: status,
          activityType: activityType,
          startAt: startAt,
          endAt: endAt,
          title: title
        )

        onPendingInsert(req)
      }
    }

    try await channel.subscribeWithError()
  }

  func stopFacilityBookingRequestListener() async {
    facilityBookingRequestsTask?.cancel()
    facilityBookingRequestsTask = nil
    if let channel = facilityBookingRequestsChannel {
      facilityBookingRequestsChannel = nil
      await client.removeChannel(channel)
    }
  }

  // MARK: - Realtime (chat)

  struct ChatMessageInsert: Sendable, Equatable {
    let messageId: UUID
    let organizationId: UUID
    let channelId: UUID
    let senderId: UUID?
    let body: String
    let createdAt: Date
  }

  func startChatMessageListener(
    organizationId: UUID,
    onInsert: @escaping @Sendable (ChatMessageInsert) -> Void
  ) async throws {
    if chatMessagesChannel != nil { return }

    let channel = client.channel("sd_chat_messages_\(organizationId.uuidString.lowercased())")
    chatMessagesChannel = channel

    let inserts = channel.postgresChange(
      InsertAction.self,
      schema: "public",
      table: "sd_chat_messages",
      filter: .eq("org_id", value: organizationId)
    )

    chatMessagesTask = Task.detached(priority: .background) {

      let iso = ISO8601DateFormatter()
      iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

      func parseUUID(_ v: AnyJSON?) -> UUID? {
        guard let s = v?.stringValue else { return nil }
        return UUID(uuidString: s)
      }
      func parseDate(_ v: AnyJSON?) -> Date? {
        guard let s = v?.stringValue else { return nil }
        return iso.date(from: s)
      }

      for await ins in inserts {
        let rec = ins.record
        guard
          let messageId = parseUUID(rec["id"]),
          let messageOrganizationId = parseUUID(rec["org_id"]),
          let channelId = parseUUID(rec["channel_id"]),
          let createdAt = parseDate(rec["created_at"]),
          let body = rec["body"]?.stringValue
        else { continue }

        let senderId = parseUUID(rec["sender_id"])
        guard messageOrganizationId == organizationId else { continue }
        onInsert(ChatMessageInsert(
          messageId: messageId,
          organizationId: messageOrganizationId,
          channelId: channelId,
          senderId: senderId,
          body: body,
          createdAt: createdAt
        ))
      }
    }

    try await channel.subscribeWithError()
  }

  func stopChatMessageListener() async {
    chatMessagesTask?.cancel()
    chatMessagesTask = nil
    if let channel = chatMessagesChannel {
      chatMessagesChannel = nil
      await client.removeChannel(channel)
    }
  }

  func restoreSessionIfAny() async throws {
    guard let storedSession = client.auth.currentSession else {
      throw SessionRestoreError.missing
    }

    // Do not refresh an expired token on the blocking launch path. A stalled
    // refresh can hold the auth client lock and prevent the public org list and
    // login requests from starting. Clear it locally and let the user sign in.
    guard !storedSession.isExpired else {
      Task { try? await client.auth.signOut(scope: .local) }
      throw SessionRestoreError.expired
    }
  }

  // MARK: - Orgs (multi-org)

  func listOrgs() async throws -> [SDOrg] {
    try await client
      .from("sd_orgs")
      .select("id, slug, name")
      .order("name", ascending: true)
      .execute()
      .value
  }

  func listMyOrgMemberships() async throws -> [SDOrgMembership] {
    let session = try await client.auth.session
    let uid = session.user.id
    return try await client
      .from("sd_org_memberships")
      // Authorization must not depend on optional audit timestamp decoding.
      // The selected-org role path needs only these authoritative columns.
      .select("org_id,user_id,role,status")
      .eq("user_id", value: uid.uuidString)
      .eq("status", value: "active")
      .execute()
      .value
  }

  func listOrgMemberships(orgId: UUID) async throws -> [SDOrgMembership] {
    try await client
      .from("sd_org_memberships")
      .select("org_id,user_id,role,status,created_at,created_by")
      .eq("org_id", value: orgId.uuidString)
      .order("created_at", ascending: false)
      .execute()
      .value
  }

  func fetchOrgSettings(orgId: UUID) async throws -> SDOrgSettings? {
    let rows: [SDOrgSettings] = try await client
      .from("sd_org_settings")
      .select("org_id,display_name,short_name,support_email,website_host,primary_color_hex,secondary_color_hex,accent_color_hex,logo_path,terminology,feature_flags,booking_policy,dashboard_layout,team_policy,created_at,updated_at")
      .eq("org_id", value: orgId.uuidString)
      .limit(1)
      .execute()
      .value
    return rows.first
  }

  /// The Stripe webhook is the writer for this table. The client only reads
  /// its latest synchronized state for the active organization.
  func fetchLatestOrgSubscription(orgId: UUID) async throws -> SDOrgSubscription? {
    let rows: [SDOrgSubscription] = try await client
      .from("sd_org_subscriptions")
      .select("id,org_id,provider,provider_subscription_id,provider_product_id,provider_price_id,status,current_period_start,current_period_end,cancel_at_period_end,canceled_at,updated_at")
      .eq("org_id", value: orgId.uuidString)
      .eq("provider", value: "stripe")
      .order("updated_at", ascending: false)
      .limit(1)
      .execute()
      .value
    return rows.first
  }

  struct SDOrgSettingsUpsert: Encodable {
    let org_id: UUID
    let display_name: String?
    let short_name: String?
    let support_email: String?
    let website_host: String?
    let primary_color_hex: String
    let secondary_color_hex: String
    let accent_color_hex: String
    let logo_path: String?
    let terminology: [String: SDJSONValue]
    let feature_flags: [String: SDJSONValue]
    let booking_policy: [String: SDJSONValue]
    let dashboard_layout: [String: SDJSONValue]
    let team_policy: [String: SDJSONValue]
  }

  func upsertOrgSettings(_ settings: SDOrgSettingsUpsert) async throws -> SDOrgSettings {
    try await client
      .from("sd_org_settings")
      .upsert(settings, onConflict: "org_id")
      .select("org_id,display_name,short_name,support_email,website_host,primary_color_hex,secondary_color_hex,accent_color_hex,logo_path,terminology,feature_flags,booking_policy,dashboard_layout,team_policy,created_at,updated_at")
      .single()
      .execute()
      .value
  }

  struct OrgAdminMembersResponse: Decodable, Sendable {
    let members: [SDOrgAdminMember]
  }

  struct OrgAdminOKResponse: Decodable, Sendable {
    let ok: Bool?
    let user_id: UUID?
  }

  func adminListOrgMembers(orgId: UUID) async throws -> [SDOrgAdminMember] {
    let response: OrgAdminMembersResponse = try await client.functions.invoke(
      "org_admin",
      options: FunctionInvokeOptions(
        body: [
          "action": SDOrgAdminAction.listMembers.rawValue,
          "org_id": orgId.uuidString,
        ]
      )
    )
    return response.members
  }

  func adminCreateOrgUser(orgId: UUID,
                          email: String,
                          username: String,
                          password: String,
                          fullName: String?,
                          role: String) async throws -> UUID? {
    var body: [String: String] = [
      "action": SDOrgAdminAction.createUser.rawValue,
      "org_id": orgId.uuidString,
      "email": email,
      "username": username,
      "password": password,
      "role": role,
    ]
    if let fullName, !fullName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      body["full_name"] = fullName
    }
    let response: OrgAdminOKResponse = try await client.functions.invoke(
      "org_admin",
      options: FunctionInvokeOptions(body: body)
    )
    return response.user_id
  }

  func adminUpdateOrgMember(orgId: UUID, userId: UUID, role: String, status: String) async throws {
    let _: OrgAdminOKResponse = try await client.functions.invoke(
      "org_admin",
      options: FunctionInvokeOptions(
        body: [
          "action": SDOrgAdminAction.updateMember.rawValue,
          "org_id": orgId.uuidString,
          "user_id": userId.uuidString,
          "role": role,
          "status": status,
        ]
      )
    )
  }

  func adminSetOrgUsername(orgId: UUID, userId: UUID, username: String) async throws {
    let _: OrgAdminOKResponse = try await client.functions.invoke(
      "org_admin",
      options: FunctionInvokeOptions(
        body: [
          "action": SDOrgAdminAction.setUsername.rawValue,
          "org_id": orgId.uuidString,
          "user_id": userId.uuidString,
          "username": username,
        ]
      )
    )
  }

  struct OrgTeamsResponse: Decodable, Sendable {
    let teams: [SDTeam]
    let members: [SDTeamMember]
    let roster: [Profile]
  }

  func adminListTeams(orgId: UUID) async throws -> OrgTeamsResponse {
    try await invokeAuthenticatedFunction(
      "org_admin",
      body: ["action": SDOrgAdminAction.listTeams.rawValue, "org_id": orgId.uuidString]
    )
  }

  func adminCreateTeam(
    orgId: UUID,
    name: String,
    colorHex: String?,
    description: String?,
    seasonId: UUID? = nil,
    ageGroup: String? = nil,
    competitiveLevel: String? = nil,
    rosterCapacity: Int? = nil,
    requestId: UUID = UUID()
  ) async throws {
    let _: OrgAdminOKResponse = try await invokeAuthenticatedFunction("org_admin", body: [
      "action": SDOrgAdminAction.createTeam.rawValue, "org_id": orgId.uuidString, "name": name,
      "color_hex": colorHex ?? "", "description": description ?? "",
      "season_id": seasonId?.uuidString ?? "",
      "age_group": ageGroup ?? "", "competitive_level": competitiveLevel ?? "",
      "roster_capacity": rosterCapacity.map(String.init) ?? "",
      "request_id": requestId.uuidString,
    ])
  }

  func adminUpdateTeam(
    orgId: UUID,
    teamId: UUID,
    name: String,
    colorHex: String?,
    description: String?,
    seasonId: UUID?,
    ageGroup: String?,
    competitiveLevel: String?,
    rosterCapacity: Int?,
    isActive: Bool
  ) async throws {
    let _: OrgAdminOKResponse = try await invokeAuthenticatedFunction("org_admin", body: [
      "action": SDOrgAdminAction.updateTeam.rawValue,
      "org_id": orgId.uuidString,
      "team_id": teamId.uuidString,
      "name": name,
      "color_hex": colorHex ?? "",
      "description": description ?? "",
      "season_id": seasonId?.uuidString ?? "",
      "age_group": ageGroup ?? "",
      "competitive_level": competitiveLevel ?? "",
      "roster_capacity": rosterCapacity.map(String.init) ?? "",
      "is_active": isActive ? "true" : "false",
      "request_id": UUID().uuidString,
    ])
  }

  func fetchTeamOperationsContext(orgId: UUID) async throws -> SDTeamOperationsContext {
    try await invokeAuthenticatedFunction(
      "org_admin",
      body: ["action": SDOrgAdminAction.teamContext.rawValue, "org_id": orgId.uuidString]
    )
  }

  private struct TodayRequest: Encodable, Sendable {
    let organization_id: UUID
    let season_id: UUID?
    let team_id: UUID?
    let child_id: UUID?
    let local_date: String
    let timezone: String
    let context_token: String
  }

  /// Role, household scope, capabilities, redaction, mission priority, and
  /// primary actions are resolved by the authenticated Today aggregation.
  /// Existing scheduling and Phase 12 operation stores remain authoritative.
  func today(
    organizationId: UUID,
    seasonId: UUID?,
    teamId: UUID?,
    childId: UUID? = nil,
    date: Date = Date(),
    timezone: TimeZone = .current,
    contextToken: String
  ) async throws -> SDTodayResponse {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timezone
    let components = calendar.dateComponents([.year, .month, .day], from: date)
    let localDate = String(
      format: "%04d-%02d-%02d",
      locale: Locale(identifier: "en_US_POSIX"),
      components.year ?? 0,
      components.month ?? 0,
      components.day ?? 0
    )
    return try await invokeAuthenticatedFunction(
      "today",
      body: TodayRequest(
        organization_id: organizationId,
        season_id: seasonId,
        team_id: teamId,
        child_id: childId,
        local_date: localDate,
        timezone: timezone.identifier,
        context_token: contextToken
      )
    )
  }

  private struct TeamScheduleListRequest: Encodable, Sendable {
    let action = "list"
    let request_id: UUID
    let organization_id: UUID
    let season_id: UUID?
    let team_id: UUID?
    let player_id: UUID?
    let range_start: String
    let range_end: String
  }

  func listTeamEvents(
    organizationId: UUID,
    seasonId: UUID? = nil,
    teamId: UUID?,
    playerId: UUID? = nil,
    rangeStart: Date,
    rangeEnd: Date,
    diagnosticScreen: String = "Schedule",
    actorRole: String? = nil,
    capabilityResolved: Bool? = nil,
    cacheFallbackAvailable: Bool = false
  ) async throws -> [SDTeamEvent] {
    let formatter = ISO8601DateFormatter()
    let requestID = UUID()
    let startedAt = Date()
    do {
      let response: SDTeamScheduleResponse = try await invokeAuthenticatedFunction(
        "team-scheduling",
        body: TeamScheduleListRequest(
          request_id: requestID,
          organization_id: organizationId,
          season_id: seasonId,
          team_id: teamId,
          player_id: playerId,
          range_start: formatter.string(from: rangeStart),
          range_end: formatter.string(from: rangeEnd)
        )
      )
      if response.schema_version == SDTeamScheduleResponse.currentSchemaVersion {
        guard response.context?.organization_id == organizationId,
              teamId == nil || response.context?.team_id == teamId,
              seasonId == nil || response.context?.season_id == seasonId else {
          throw SDTeamScheduleContractError.contextMismatch
        }
      }
      SDTeamRuntimeDiagnostics.record(
        requestID: requestID,
        screen: diagnosticScreen,
        action: "list",
        organizationPresent: true,
        seasonPresent: seasonId != nil,
        teamPresent: teamId != nil,
        actorRole: actorRole,
        capabilityResolved: capabilityResolved,
        statusCode: 200,
        backendCode: nil,
        backendStage: "build_response",
        schemaVersion: response.schema_version,
        rowCount: response.events.count,
        discardedRowCount: response.discarded_event_count,
        decodeStage: "publish_state",
        cacheFallbackUsed: false,
        elapsedMilliseconds: Int(Date().timeIntervalSince(startedAt) * 1_000),
        cancelled: false,
        superseded: false
      )
      return response.events
    } catch {
      let cancelled = SDApplicationErrorClassifier.isCancellation(
        error,
        taskIsCancelled: Task.isCancelled
      )
      let edge = error as? SDEdgeFunctionHTTPError
      let service = error as? SDServiceError
      SDTeamRuntimeDiagnostics.record(
        requestID: requestID,
        screen: diagnosticScreen,
        action: "list",
        organizationPresent: true,
        seasonPresent: seasonId != nil,
        teamPresent: teamId != nil,
        actorRole: actorRole,
        capabilityResolved: capabilityResolved,
        statusCode: edge?.statusCode ?? service?.statusCode,
        backendCode: edge?.code ?? service?.category.rawValue,
        backendStage: edge == nil && service == nil ? "decode_payload" : "execute_query",
        schemaVersion: nil,
        rowCount: nil,
        decodeStage: "decode_payload",
        cacheFallbackUsed: cacheFallbackAvailable && !cancelled,
        elapsedMilliseconds: Int(Date().timeIntervalSince(startedAt) * 1_000),
        cancelled: cancelled,
        superseded: Task.isCancelled
      )
      throw error
    }
  }

  private struct TeamEventConflictPayload: Encodable, Sendable {
    let start_at: String
    let end_at: String
    let facility_id: UUID?
    let coach_ids: [UUID]
  }

  private struct TeamEventConflictRequest: Encodable, Sendable {
    let action = "conflicts"
    let organization_id: UUID
    let season_id: UUID
    let team_id: UUID
    let event_id: UUID?
    let event: TeamEventConflictPayload
  }

  func teamEventConflicts(
    organizationId: UUID,
    seasonId: UUID,
    teamId: UUID,
    eventId: UUID? = nil,
    startAt: Date,
    endAt: Date,
    facilityId: UUID?,
    coachIds: [UUID] = []
  ) async throws -> [SDTeamEventConflict] {
    let formatter = ISO8601DateFormatter()
    let response: SDTeamEventConflictsResponse = try await invokeAuthenticatedFunction(
      "team-scheduling",
      body: TeamEventConflictRequest(
        organization_id: organizationId,
        season_id: seasonId,
        team_id: teamId,
        event_id: eventId,
        event: TeamEventConflictPayload(
          start_at: formatter.string(from: startAt),
          end_at: formatter.string(from: endAt),
          facility_id: facilityId,
          coach_ids: coachIds
        )
      )
    )
    return response.conflicts
  }

  private struct TeamEventPayload: Encodable, Sendable {
    let event_type: String
    let title: String
    let description: String?
    let status: String
    let start_at: String
    let end_at: String
    let arrival_at: String?
    let timezone: String
    let all_day: Bool
    let location_name: String?
    let address: String?
    let facility_id: UUID?
    let visibility: String
    let notes: String?
    let subtype: [String: SDJSONValue]
    let coach_ids: [UUID]
  }

  private struct TeamEventRecurrencePayload: Encodable, Sendable {
    let frequency: String
    let interval: Int
    let weekdays: [Int]?
    let ends_on: String?
    let occurrence_count: Int?
  }

  private struct TeamEventMutationRequest: Encodable, Sendable {
    let action: String
    let organization_id: UUID
    let season_id: UUID
    let team_id: UUID
    let event_id: UUID?
    let request_id: UUID
    let event: TeamEventPayload
    let recurrence: TeamEventRecurrencePayload?
    let reason: String?
    let override_reason: String?
  }

  func saveTeamEvent(
    organizationId: UUID,
    seasonId: UUID,
    teamId: UUID,
    eventId: UUID? = nil,
    draft: SDTeamEventDraft,
    publish: Bool,
    overrideReason: String? = nil,
    coachIds: [UUID] = [],
    actionOverride: String? = nil,
    reason: String? = nil
  ) async throws -> [SDTeamEvent] {
    let formatter = ISO8601DateFormatter()
    var subtype: [String: SDJSONValue] = [:]
    switch draft.type {
    case .practice:
      subtype = [
        "objectives": .array(draft.objectives.split(separator: ",").map { .string($0.trimmingCharacters(in: .whitespaces)) }),
        "dress_code": .string(draft.dressCode),
        "equipment_notes": .string(draft.equipmentNotes),
        "practice_plan_status": .string("not_started")
      ]
    case .game:
      subtype = [
        "opponent": .string(draft.opponent),
        "venue_side": .string(draft.venueSide),
        "game_status": .string("scheduled"),
        "uniform": .string(draft.uniform)
      ]
    case .tournament:
      subtype = [
        "tournament_name": .string(draft.tournamentName),
        "host": .string(draft.tournamentHost),
        "tournament_start_date": .string(DateUtils.toISODate(draft.startAt)),
        "tournament_end_date": .string(DateUtils.toISODate(draft.endAt))
      ]
    case .meeting:
      subtype = ["meeting_type": .string(draft.meetingType), "virtual_link": .string(draft.virtualLink)]
    case .travel:
      subtype = [
        "destination": .string(draft.destination),
        "transportation_notes": .string(draft.transportationNotes),
        "lodging_notes": .string(draft.lodgingNotes)
      ]
    case .custom:
      break
    }
    let payload = TeamEventPayload(
      event_type: draft.type.rawValue,
      title: draft.title,
      description: draft.description.sdNilIfBlank,
      status: eventId == nil
        ? (publish ? SDTeamEventStatus.scheduled.rawValue : SDTeamEventStatus.draft.rawValue)
        : (draft.status == .draft && publish ? SDTeamEventStatus.scheduled.rawValue : draft.status.rawValue),
      start_at: formatter.string(from: draft.startAt),
      end_at: formatter.string(from: draft.endAt),
      arrival_at: draft.arrivalAt.map(formatter.string),
      timezone: draft.timezone,
      all_day: draft.allDay,
      location_name: draft.locationName.sdNilIfBlank,
      address: draft.address.sdNilIfBlank,
      facility_id: draft.facilityId,
      visibility: draft.visibility.rawValue,
      notes: draft.notes.sdNilIfBlank,
      subtype: subtype,
      coach_ids: coachIds
    )
    let response: SDTeamEventResponse = try await invokeAuthenticatedFunction(
      "team-scheduling",
      body: TeamEventMutationRequest(
        action: actionOverride ?? (eventId == nil ? "create" : "update"),
        organization_id: organizationId,
        season_id: seasonId,
        team_id: teamId,
        event_id: eventId,
        request_id: UUID(),
        event: payload,
        recurrence: draft.repeats && eventId == nil ? TeamEventRecurrencePayload(
          frequency: draft.recurrenceFrequency,
          interval: draft.recurrenceInterval,
          weekdays: draft.recurrenceFrequency == "weekly" ? draft.recurrenceWeekdays.sorted() : nil,
          ends_on: draft.recurrenceUsesEndDate ? DateUtils.toISODate(draft.recurrenceEndDate) : nil,
          occurrence_count: draft.recurrenceUsesEndDate ? nil : draft.occurrenceCount
        ) : nil,
        reason: reason,
        override_reason: overrideReason
      )
    )
    if let events = response.events { return events }
    return response.event.map { [$0] } ?? []
  }

  private struct EventOperationParticipantVersion: Encodable, Sendable {
    let participant_id: UUID
    let expected_version: Int
  }

  private struct EventOperationRequest: Encodable, Sendable {
    let action: String
    let organization_id: UUID
    var event_id: UUID? = nil
    var team_id: UUID? = nil
    var event_ids: [UUID]? = nil
    var player_id: UUID? = nil
    var request_id: UUID? = nil
    var expected_version: Int? = nil
    var status: String? = nil
    var participant_id: UUID? = nil
    var participant_ids: [UUID]? = nil
    var participants: [EventOperationParticipantVersion]? = nil
    var participant_version: Int? = nil
    var attendance_status: String? = nil
    var availability_status: String? = nil
    var reason: String? = nil
    var override_reason: String? = nil
    var correction_reason: String? = nil
    var expected_arrival_at: String? = nil
    var expected_departure_at: String? = nil
    var arrival_at: String? = nil
    var departure_at: String? = nil
    var attendance_notes: String? = nil
    var private_notes: String? = nil
    var item_id: UUID? = nil
    var item_version: Int? = nil
    var completed: Bool? = nil
    var note_id: UUID? = nil
    var note_version: Int? = nil
    var note_type: String? = nil
    var visibility: String? = nil
    var body: String? = nil
    var operational_summary: String? = nil
  }

  func eventOperation(
    organizationId: UUID,
    eventId: UUID,
    playerId: UUID? = nil
  ) async throws -> SDEventOperationDetailResponse {
    try await invokeAuthenticatedFunction(
      "event-operations",
      body: EventOperationRequest(
        action: "get",
        organization_id: organizationId,
        event_id: eventId,
        player_id: playerId
      )
    )
  }

  func listEventOperations(
    organizationId: UUID,
    teamId: UUID,
    eventIds: [UUID]
  ) async throws -> [SDEventOperationSummary] {
    let response: SDEventOperationListResponse = try await invokeAuthenticatedFunction(
      "event-operations",
      body: EventOperationRequest(
        action: "list",
        organization_id: organizationId,
        team_id: teamId,
        event_ids: eventIds
      )
    )
    return response.operations
  }

  func initializeEventOperation(
    organizationId: UUID,
    eventId: UUID,
    requestId: UUID = UUID()
  ) async throws -> SDEventOperationDetailResponse {
    try await invokeAuthenticatedFunction(
      "event-operations",
      body: EventOperationRequest(
        action: "initialize",
        organization_id: organizationId,
        event_id: eventId,
        request_id: requestId
      )
    )
  }

  func transitionEventOperation(
    organizationId: UUID,
    eventId: UUID,
    expectedVersion: Int,
    status: SDEventOperationStatus,
    reason: String? = nil,
    summary: String? = nil,
    requestId: UUID = UUID()
  ) async throws -> SDEventOperationMutationResponse {
    try await invokeAuthenticatedFunction(
      "event-operations",
      body: EventOperationRequest(
        action: "transition",
        organization_id: organizationId,
        event_id: eventId,
        request_id: requestId,
        expected_version: expectedVersion,
        status: status.rawValue,
        reason: reason,
        operational_summary: summary
      )
    )
  }

  func updateEventAvailability(
    organizationId: UUID,
    eventId: UUID,
    playerId: UUID,
    participantVersion: Int?,
    draft: SDEventAvailabilityDraft,
    overrideReason: String? = nil,
    requestId: UUID = UUID()
  ) async throws -> SDEventOperationMutationResponse {
    let formatter = ISO8601DateFormatter()
    return try await invokeAuthenticatedFunction(
      "event-operations",
      body: EventOperationRequest(
        action: "availability",
        organization_id: organizationId,
        event_id: eventId,
        player_id: playerId,
        request_id: requestId,
        participant_version: participantVersion,
        availability_status: draft.status.rawValue,
        reason: draft.reason.sdNilIfBlank,
        override_reason: overrideReason,
        expected_arrival_at: draft.expectedArrival.map(formatter.string),
        expected_departure_at: draft.expectedDeparture.map(formatter.string)
      )
    )
  }

  func updateEventAttendance(
    organizationId: UUID,
    eventId: UUID,
    participantId: UUID,
    participantVersion: Int,
    status: SDEventAttendanceStatus,
    arrivalAt: Date? = nil,
    departureAt: Date? = nil,
    attendanceNotes: String? = nil,
    privateNotes: String? = nil,
    correctionReason: String? = nil,
    requestId: UUID = UUID()
  ) async throws -> SDEventOperationMutationResponse {
    let formatter = ISO8601DateFormatter()
    return try await invokeAuthenticatedFunction(
      "event-operations",
      body: EventOperationRequest(
        action: "attendance",
        organization_id: organizationId,
        event_id: eventId,
        request_id: requestId,
        participant_id: participantId,
        participant_version: participantVersion,
        attendance_status: status.rawValue,
        correction_reason: correctionReason,
        arrival_at: arrivalAt.map(formatter.string),
        departure_at: departureAt.map(formatter.string),
        attendance_notes: attendanceNotes,
        private_notes: privateNotes
      )
    )
  }

  func bulkUpdateEventAttendance(
    organizationId: UUID,
    eventId: UUID,
    participants: [SDEventOperationParticipant],
    status: SDEventAttendanceStatus,
    correctionReason: String? = nil,
    requestId: UUID = UUID()
  ) async throws -> SDEventOperationMutationResponse {
    try await invokeAuthenticatedFunction(
      "event-operations",
      body: EventOperationRequest(
        action: "attendance_bulk",
        organization_id: organizationId,
        event_id: eventId,
        request_id: requestId,
        participants: participants.map {
          EventOperationParticipantVersion(
            participant_id: $0.id,
            expected_version: $0.version
          )
        },
        attendance_status: status.rawValue,
        correction_reason: correctionReason
      )
    )
  }

  func updateEventChecklist(
    organizationId: UUID,
    eventId: UUID,
    itemId: UUID,
    itemVersion: Int,
    completed: Bool,
    overrideReason: String? = nil,
    requestId: UUID = UUID()
  ) async throws -> SDEventOperationMutationResponse {
    try await invokeAuthenticatedFunction(
      "event-operations",
      body: EventOperationRequest(
        action: "checklist",
        organization_id: organizationId,
        event_id: eventId,
        request_id: requestId,
        override_reason: overrideReason,
        item_id: itemId,
        item_version: itemVersion,
        completed: completed
      )
    )
  }

  func finalizeEventAttendance(
    organizationId: UUID,
    eventId: UUID,
    expectedVersion: Int,
    reason: String? = nil,
    requestId: UUID = UUID()
  ) async throws -> SDEventOperationMutationResponse {
    try await invokeAuthenticatedFunction(
      "event-operations",
      body: EventOperationRequest(
        action: "finalize_attendance",
        organization_id: organizationId,
        event_id: eventId,
        request_id: requestId,
        expected_version: expectedVersion,
        reason: reason
      )
    )
  }

  func addEventOperationNote(
    organizationId: UUID,
    eventId: UUID,
    type: String,
    visibility: String,
    body: String,
    playerId: UUID? = nil,
    requestId: UUID = UUID()
  ) async throws -> SDEventOperationMutationResponse {
    try await invokeAuthenticatedFunction(
      "event-operations",
      body: EventOperationRequest(
        action: "note",
        organization_id: organizationId,
        event_id: eventId,
        player_id: playerId,
        request_id: requestId,
        note_type: type,
        visibility: visibility,
        body: body
      )
    )
  }

  func updateEventOperationNote(
    organizationId: UUID,
    eventId: UUID,
    note: SDEventOperationNote,
    visibility: String,
    body: String,
    requestId: UUID = UUID()
  ) async throws -> SDEventOperationMutationResponse {
    try await invokeAuthenticatedFunction(
      "event-operations",
      body: EventOperationRequest(
        action: "note_update",
        organization_id: organizationId,
        event_id: eventId,
        request_id: requestId,
        note_id: note.id,
        note_version: note.version,
        note_type: note.note_type,
        visibility: visibility,
        body: body
      )
    )
  }

  func reconcileEventParticipants(
    organizationId: UUID,
    eventId: UUID,
    expectedVersion: Int,
    reason: String,
    requestId: UUID = UUID()
  ) async throws -> SDEventOperationMutationResponse {
    try await invokeAuthenticatedFunction(
      "event-operations",
      body: EventOperationRequest(
        action: "reconcile_participants",
        organization_id: organizationId,
        event_id: eventId,
        request_id: requestId,
        expected_version: expectedVersion,
        reason: reason
      )
    )
  }

  func eventOperationAuditHistory(
    organizationId: UUID,
    eventId: UUID
  ) async throws -> SDEventOperationAuditResponse {
    try await invokeAuthenticatedFunction(
      "event-operations",
      body: EventOperationRequest(
        action: "audit_history",
        organization_id: organizationId,
        event_id: eventId
      )
    )
  }

  private struct PracticePlanningRequest: Encodable, Sendable {
    let action: String
    let organization_id: UUID
    var event_id: UUID? = nil
    var team_id: UUID? = nil
    var season_id: UUID? = nil
    var player_id: UUID? = nil
    var template_id: UUID? = nil
    var include_archived: Bool? = nil
    var request_id: UUID? = nil
    var data: [String: SDJSONValue]? = nil
  }

  func practicePlan(
    organizationId: UUID,
    eventId: UUID,
    playerId: UUID? = nil
  ) async throws -> SDPracticePlanDetailResponse {
    try await invokeAuthenticatedFunction(
      "practice-planning",
      body: PracticePlanningRequest(
        action: "fetch_plan",
        organization_id: organizationId,
        event_id: eventId,
        player_id: playerId
      )
    )
  }

  func practiceTemplates(
    organizationId: UUID,
    eventId: UUID,
    teamId: UUID,
    includeArchived: Bool = false
  ) async throws -> [SDPracticePlanTemplate] {
    let response: SDPracticeTemplateListResponse = try await invokeAuthenticatedFunction(
      "practice-planning",
      body: PracticePlanningRequest(
        action: "list_templates",
        organization_id: organizationId,
        event_id: eventId,
        team_id: teamId,
        include_archived: includeArchived
      )
    )
    return response.templates
  }

  func priorPracticePlans(
    organizationId: UUID,
    eventId: UUID,
    teamId: UUID
  ) async throws -> [SDPracticePriorPlan] {
    let response: SDPracticePriorPlanListResponse = try await invokeAuthenticatedFunction(
      "practice-planning",
      body: PracticePlanningRequest(
        action: "list_prior_practices",
        organization_id: organizationId,
        event_id: eventId,
        team_id: teamId
      )
    )
    return response.plans
  }

  func practicePlanSummaries(
    organizationId: UUID,
    seasonId: UUID,
    teamId: UUID
  ) async throws -> [SDPracticePlanSummary] {
    let response: SDPracticePlanSummaryListResponse = try await invokeAuthenticatedFunction(
      "practice-planning",
      body: PracticePlanningRequest(
        action: "list_plan_summaries",
        organization_id: organizationId,
        team_id: teamId,
        season_id: seasonId
      )
    )
    return response.plans
  }

  func practicePlanHistory(
    organizationId: UUID,
    eventId: UUID
  ) async throws -> [SDPracticePlanSnapshot] {
    let response: SDPracticePlanHistoryResponse = try await invokeAuthenticatedFunction(
      "practice-planning",
      body: PracticePlanningRequest(
        action: "fetch_plan_history",
        organization_id: organizationId,
        event_id: eventId
      )
    )
    return response.snapshots
  }

  func mutatePracticePlan(
    action: String,
    organizationId: UUID,
    eventId: UUID,
    data: [String: SDJSONValue] = [:],
    requestId: UUID = UUID()
  ) async throws -> SDPracticeMutationResponse {
    try await invokeAuthenticatedFunction(
      "practice-planning",
      body: PracticePlanningRequest(
        action: action,
        organization_id: organizationId,
        event_id: eventId,
        request_id: requestId,
        data: data
      )
    )
  }

  private struct GameOperationsRequest: Encodable, Sendable {
    let action: String
    let organization_id: UUID
    var event_id: UUID? = nil
    var team_id: UUID? = nil
    var season_id: UUID? = nil
    var player_id: UUID? = nil
    var rule_profile_id: UUID? = nil
    var request_id: UUID? = nil
    var data: [String: SDJSONValue]? = nil
  }

  func gamePlan(
    organizationId: UUID,
    eventId: UUID,
    playerId: UUID? = nil
  ) async throws -> SDGamePlanDetailResponse {
    try await invokeAuthenticatedFunction(
      "game-operations",
      body: GameOperationsRequest(
        action: "fetch_game_plan",
        organization_id: organizationId,
        event_id: eventId,
        player_id: playerId
      )
    )
  }

  func gameRuleProfiles(
    organizationId: UUID,
    eventId: UUID,
    teamId: UUID,
    seasonId: UUID
  ) async throws -> [SDGameRuleProfile] {
    let response: SDGameRuleProfileListResponse = try await invokeAuthenticatedFunction(
      "game-operations",
      body: GameOperationsRequest(
        action: "list_rule_profiles",
        organization_id: organizationId,
        event_id: eventId,
        team_id: teamId,
        season_id: seasonId
      )
    )
    return response.rule_profiles
  }

  func gamePlanHistory(
    organizationId: UUID,
    eventId: UUID
  ) async throws -> [SDGamePlanSnapshot] {
    let response: SDGamePlanHistoryResponse = try await invokeAuthenticatedFunction(
      "game-operations",
      body: GameOperationsRequest(
        action: "fetch_game_plan_history",
        organization_id: organizationId,
        event_id: eventId
      )
    )
    return response.snapshots
  }

  func gamePlanSummaries(
    organizationId: UUID,
    seasonId: UUID,
    teamId: UUID
  ) async throws -> [SDGamePlanSummary] {
    let response: SDGamePlanSummaryListResponse = try await invokeAuthenticatedFunction(
      "game-operations",
      body: GameOperationsRequest(
        action: "list_game_plan_summaries",
        organization_id: organizationId,
        team_id: teamId,
        season_id: seasonId
      )
    )
    return response.plans
  }

  func priorGamePlans(
    organizationId: UUID,
    eventId: UUID,
    teamId: UUID
  ) async throws -> [SDGamePriorPlan] {
    let response: SDGamePriorPlanListResponse = try await invokeAuthenticatedFunction(
      "game-operations",
      body: GameOperationsRequest(
        action: "fetch_prior_game_plans",
        organization_id: organizationId,
        event_id: eventId,
        team_id: teamId
      )
    )
    return response.plans
  }

  func mutateGamePlan(
    action: String,
    organizationId: UUID,
    eventId: UUID,
    data: [String: SDJSONValue] = [:],
    requestId: UUID = UUID()
  ) async throws -> SDGameMutationResponse {
    try await invokeAuthenticatedFunction(
      "game-operations",
      body: GameOperationsRequest(
        action: action,
        organization_id: organizationId,
        event_id: eventId,
        request_id: requestId,
        data: data
      )
    )
  }

  private struct SeasonMutationResponse: Decodable, Sendable {
    let season: SDSeason
  }

  private struct TeamMutationResponse: Decodable, Sendable {
    let team: SDTeam
  }

  private struct SeasonMutationRequest: Encodable, Sendable {
    let action: String
    let org_id: String
    let season_id: String?
    let name: String
    let start_date: String?
    let end_date: String?
    let status: String
    let is_default: Bool
    let request_id: String
  }

  func adminSaveSeason(
    orgId: UUID,
    seasonId: UUID? = nil,
    name: String,
    startDate: String?,
    endDate: String?,
    status: SDSeasonLifecycle,
    isDefault: Bool,
    requestId: UUID = UUID()
  ) async throws -> SDSeason {
    let response: SeasonMutationResponse = try await invokeAuthenticatedFunction(
      "org_admin",
      body: SeasonMutationRequest(
        action: (seasonId == nil ? SDOrgAdminAction.createSeason : .updateSeason).rawValue,
        org_id: orgId.uuidString,
        season_id: seasonId?.uuidString,
        name: name,
        start_date: startDate,
        end_date: endDate,
        status: status.rawValue,
        is_default: isDefault,
        request_id: requestId.uuidString
      )
    )
    return response.season
  }

  func adminAssignTeamToSeason(orgId: UUID, teamId: UUID, seasonId: UUID) async throws {
    let _: TeamMutationResponse = try await invokeAuthenticatedFunction("org_admin", body: [
      "action": SDOrgAdminAction.assignTeamSeason.rawValue,
      "org_id": orgId.uuidString,
      "team_id": teamId.uuidString,
      "season_id": seasonId.uuidString,
      "request_id": UUID().uuidString,
    ])
  }

  func adminAssignPlayerToTeam(
    orgId: UUID,
    playerId: UUID,
    teamId: UUID,
    reason: String?
  ) async throws {
    struct Response: Decodable { let membership: SDPlayerTeamMembership }
    let _: Response = try await invokeAuthenticatedFunction("org_admin", body: [
      "action": SDOrgAdminAction.assignPlayerTeam.rawValue,
      "org_id": orgId.uuidString,
      "player_id": playerId.uuidString,
      "team_id": teamId.uuidString,
      "assignment_reason": reason ?? "",
      "request_id": UUID().uuidString,
    ])
  }

  func adminUnassignPlayerFromTeam(
    orgId: UUID,
    playerId: UUID,
    reason: String?,
    requestId: UUID = UUID()
  ) async throws {
    let _: OrgAdminOKResponse = try await invokeAuthenticatedFunction("org_admin", body: [
      "action": SDOrgAdminAction.unassignPlayerTeam.rawValue,
      "org_id": orgId.uuidString,
      "player_id": playerId.uuidString,
      "assignment_reason": reason ?? "",
      "request_id": requestId.uuidString,
    ])
  }

  private struct CoachAssignmentMutationRequest: Encodable, Sendable {
    let action: String
    let org_id: String
    let coach_id: String
    let team_id: String
    let responsibilities: [String]
    let is_primary: Bool
    let organization_wide_access: Bool
    let request_id: String
  }

  func adminAssignCoachToTeam(
    orgId: UUID,
    coachId: UUID,
    teamId: UUID,
    responsibilities: Set<SDTeamResponsibility>,
    isPrimary: Bool,
    organizationWideAccess: Bool
  ) async throws -> SDCoachTeamAssignment {
    struct Response: Decodable { let assignment: SDCoachTeamAssignment }
    let response: Response = try await invokeAuthenticatedFunction(
      "org_admin",
      body: CoachAssignmentMutationRequest(
        action: SDOrgAdminAction.assignCoachTeam.rawValue,
        org_id: orgId.uuidString,
        coach_id: coachId.uuidString,
        team_id: teamId.uuidString,
        responsibilities: responsibilities.map(\.rawValue).sorted(),
        is_primary: isPrimary,
        organization_wide_access: organizationWideAccess,
        request_id: UUID().uuidString
      )
    )
    return response.assignment
  }

  func adminAssignTeam(orgId: UUID, teamId: UUID?, memberId: UUID) async throws {
    if let teamId {
      let _: OrgAdminOKResponse = try await invokeAuthenticatedFunction("org_admin", body: [
        "action": SDOrgAdminAction.assignTeamMember.rawValue, "org_id": orgId.uuidString,
        "team_id": teamId.uuidString, "member_id": memberId.uuidString
      ])
    } else {
      let _: OrgAdminOKResponse = try await invokeAuthenticatedFunction("org_admin", body: [
        "action": SDOrgAdminAction.removeTeamMember.rawValue, "org_id": orgId.uuidString, "member_id": memberId.uuidString
      ])
    }
  }

  func adminFetchPlayerAccess(orgId: UUID, playerId: UUID) async throws -> SDAdminPlayerAccess {
    struct Response: Decodable { let entitlement: SDAdminPlayerAccess }
    let response: Response = try await invokeAuthenticatedFunction("org_admin", body: [
      "action": SDOrgAdminAction.getPlayerAccess.rawValue,
      "org_id": orgId.uuidString,
      "player_id": playerId.uuidString,
    ])
    return response.entitlement
  }

  func adminSetPlayerAccess(orgId: UUID, playerId: UUID, isActive: Bool) async throws -> SDAdminPlayerAccess {
    struct Response: Decodable { let entitlement: SDAdminPlayerAccess }
    let response: Response = try await invokeAuthenticatedFunction("org_admin", body: [
      "action": SDOrgAdminAction.setPlayerAccess.rawValue,
      "org_id": orgId.uuidString,
      "player_id": playerId.uuidString,
      "is_active": isActive ? "true" : "false",
    ])
    return response.entitlement
  }

  /// Edge Functions do not automatically refresh the bearer token in every
  /// long-running desktop session. Refresh first, then explicitly install the
  /// current access token so authorized team/admin calls cannot drift into 401.
  private func invokeAuthenticatedFunction<Response: Decodable, Body: Encodable>(
    _ name: String,
    body: Body
  ) async throws -> Response {
    do {
      let session = try await client.auth.session
      client.functions.setAuth(token: session.accessToken)
      return try await client.functions.invoke(
        name,
        options: FunctionInvokeOptions(body: body)
      )
    } catch {
      if SDApplicationErrorClassifier.isCancellation(error, taskIsCancelled: Task.isCancelled) {
        throw CancellationError()
      }
      if let functionError = error as? FunctionsError {
        switch functionError {
        case .httpError(let statusCode, let data):
          SDApplicationErrorClassifier.log(
            error,
            functionName: name,
            statusCode: statusCode
          )
          if statusCode == 404 {
            throw SDServiceError(
              category: .notDeployed,
              functionName: name,
              statusCode: statusCode
            )
          }
          let decoded = SDEdgeFunctionHTTPError.decode(statusCode: statusCode, data: data)
          if ["unknown_action", "unsupported_action"].contains(decoded.code) {
            throw SDServiceError(
              category: .unsupportedAction,
              functionName: name,
              statusCode: statusCode
            )
          }
          throw decoded
        case .relayError:
          SDApplicationErrorClassifier.log(error, functionName: name)
          throw SDServiceError(
            category: .serviceUnavailable,
            functionName: name,
            statusCode: nil
          )
        }
      }
      SDApplicationErrorClassifier.log(error, functionName: name)
      throw error
    }
  }

  private struct OrgBillingURLResponse: Decodable {
    let url: String
  }

  private struct StripeConnectOnboardingResponse: Decodable {
    let url: String
    let expires_at: Int
  }

  struct StripeConnectAccountStatus: Decodable, Equatable, Sendable {
    enum State: String, Decodable, Sendable {
      case notConnected = "not_connected"
      case onboardingIncomplete = "onboarding_incomplete"
      case requirementsDue = "requirements_due"
      case ready
      case restricted
    }

    let status: State
    let details_submitted: Bool
    let charges_enabled: Bool
    let payouts_enabled: Bool
    let currently_due: [String]
    let past_due: [String]
    let eventually_due: [String]
    let disabled_reason: String?
    let last_synced_at: String?
  }

  private enum OrgBillingURLError: LocalizedError {
    case invalidHostedURL
    case invalidConnectURL

    var errorDescription: String? {
      switch self {
      case .invalidHostedURL:
        return "Home Plate returned an invalid billing link. Please try again."
      case .invalidConnectURL:
        return "Home Plate returned an invalid Stripe setup link. Please try again."
      }
    }
  }

  func createOrgSubscriptionCheckout(orgId: UUID) async throws -> URL {
    let response: OrgBillingURLResponse = try await invokeAuthenticatedFunction(
      "create-org-subscription-checkout",
      body: ["org_id": orgId.uuidString]
    )
    return try validatedStripeHostedURL(response.url)
  }

  func createOrgBillingPortal(orgId: UUID) async throws -> URL {
    let response: OrgBillingURLResponse = try await invokeAuthenticatedFunction(
      "create-org-billing-portal",
      body: ["org_id": orgId.uuidString]
    )
    return try validatedStripeHostedURL(response.url)
  }

  func createStripeConnectOnboardingLink(orgId: UUID) async throws -> URL {
    let response: StripeConnectOnboardingResponse = try await invokeAuthenticatedFunction(
      "create-stripe-connect-onboarding-link",
      body: ["org_id": orgId.uuidString]
    )
    guard response.expires_at > Int(Date().timeIntervalSince1970),
          let url = URL(string: response.url),
          url.scheme?.lowercased() == "https",
          url.host?.lowercased() == "connect.stripe.com" else {
      throw OrgBillingURLError.invalidConnectURL
    }
    return url
  }

  func getStripeConnectAccountStatus(orgId: UUID) async throws -> StripeConnectAccountStatus {
    try await invokeAuthenticatedFunction(
      "get-stripe-connect-account-status",
      body: ["org_id": orgId.uuidString]
    )
  }

  private func validatedStripeHostedURL(_ rawValue: String) throws -> URL {
    guard let url = URL(string: rawValue),
          url.scheme?.lowercased() == "https",
          let host = url.host?.lowercased(),
          host == "checkout.stripe.com" || host == "billing.stripe.com" else {
      throw OrgBillingURLError.invalidHostedURL
    }
    return url
  }

  func platformAdminDashboard() async throws -> SDPlatformDashboard {
    try await invokeAuthenticatedFunction(
      "platform_admin",
      body: ["action": "dashboard"]
    )
  }

  func platformFeatureFlags() async throws -> [SDPlatformFeatureFlag] {
    try await client
      .from("sd_platform_feature_flags")
      .select("key,enabled,description,updated_at,updated_by")
      .order("key")
      .execute()
      .value
  }

  func platformAdminFeatureFlags() async throws -> [SDPlatformFeatureFlag] {
    struct Request: Encodable { let action = "list_platform_feature_flags" }
    let response: SDPlatformFeatureFlagsResponse = try await invokeAuthenticatedFunction(
      "platform_admin",
      body: Request()
    )
    return response.feature_flags
  }

  func platformSetFeatureFlag(
    key: String,
    enabled: Bool,
    requestId: UUID
  ) async throws -> SDPlatformFeatureFlag {
    struct Request: Encodable {
      let action = "update_platform_feature_flag"
      let key: String
      let enabled: Bool
      let request_id: UUID
    }
    let response: SDPlatformFeatureFlagResponse = try await invokeAuthenticatedFunction(
      "platform_admin",
      body: Request(key: key, enabled: enabled, request_id: requestId)
    )
    return response.feature_flag
  }

  private func requirePlayerDevelopmentCopilotEnabled() async throws {
    let flags: [SDPlatformFeatureFlag]
    do {
      flags = try await platformFeatureFlags()
    } catch {
      throw SDPlatformFeatureDisabledError.playerDevelopmentCopilot
    }
    guard SDPlatformFeatureGate.playerDevelopmentCopilotEnabled(in: flags) else {
      throw SDPlatformFeatureDisabledError.playerDevelopmentCopilot
    }
  }

  /// Checks server-authorized platform access without decoding organization
  /// billing rows. Permission visibility must not depend on optional legacy
  /// fields in the dashboard payload.
  func verifyPlatformAdminAccess() async throws {
    struct AuthorizationResponse: Decodable {}
    let _: AuthorizationResponse = try await invokeAuthenticatedFunction(
      "platform_admin",
      body: ["action": "dashboard"]
    )
  }

  func platformCreateOrganization(
    name: String,
    slug: String,
    plan: String,
    billingEmail: String?,
    maxMembers: Int?
  ) async throws -> SDPlatformOrganization {
    struct Response: Decodable { let organization: SDPlatformOrganization }
    let payload = SDPlatformOrganizationCreatePayload(
      name: name,
      slug: slug,
      plan: plan,
      billing_email: billingEmail,
      max_members: maxMembers
    )
    let response: Response = try await invokeAuthenticatedFunction("platform_admin", body: payload)
    return response.organization
  }

  func platformUpdateOrganization(_ organization: SDPlatformOrganization) async throws {
    struct Response: Decodable { let organization: SDPlatformOrganization }
    let _: Response = try await invokeAuthenticatedFunction("platform_admin", body: [
      "action": "update_organization", "org_id": organization.id.uuidString,
      "name": organization.name, "slug": organization.slug, "status": organization.status,
      "plan": organization.plan, "billing_email": organization.billing_email ?? "",
      "max_members": String(organization.max_members ?? 0)
    ])
  }

  func platformOrganizationMembers(orgId: UUID) async throws -> SDPlatformMembersResponse {
    struct Request: Encodable {
      let action = "list_members"
      let org_id: UUID
    }
    return try await invokeAuthenticatedFunction(
      "platform_admin",
      body: Request(org_id: orgId)
    )
  }

  func platformUpdateMembership(
    orgId: UUID,
    userId: UUID,
    role: String,
    status: String,
    reason: String?,
    requestId: UUID
  ) async throws -> SDPlatformMembershipUpdateResponse {
    struct Request: Encodable {
      let action = "update_membership"
      let org_id: UUID
      let user_id: UUID
      let role: String
      let status: String
      let reason: String?
      let request_id: UUID
    }
    return try await invokeAuthenticatedFunction(
      "platform_admin",
      body: Request(
        org_id: orgId,
        user_id: userId,
        role: role,
        status: status,
        reason: reason,
        request_id: requestId
      )
    )
  }

  func platformSearchUsers(query: String) async throws -> [SDPlatformUserDirectoryEntry] {
    struct Request: Encodable {
      let action = "search_users"
      let query: String
    }
    let response: SDPlatformUserSearchResponse = try await invokeAuthenticatedFunction(
      "platform_admin",
      body: Request(query: query)
    )
    return response.users
  }

  func platformAdministrators() async throws -> [SDPlatformAdministrator] {
    struct Request: Encodable { let action = "list_platform_admins" }
    let response: SDPlatformAdministratorsResponse = try await invokeAuthenticatedFunction(
      "platform_admin",
      body: Request()
    )
    return response.administrators
  }

  func platformSetAdministrator(
    userId: UUID,
    granted: Bool,
    reason: String?,
    requestId: UUID
  ) async throws {
    struct Request: Encodable {
      let action: String
      let user_id: UUID
      let reason: String?
      let request_id: UUID
    }
    struct Response: Decodable { let ok: Bool }
    let _: Response = try await invokeAuthenticatedFunction(
      "platform_admin",
      body: Request(
        action: granted ? "grant_platform_admin" : "revoke_platform_admin",
        user_id: userId,
        reason: reason,
        request_id: requestId
      )
    )
  }

  func platformAuditHistory() async throws -> [SDPlatformAuditEntry] {
    struct Request: Encodable { let action = "audit_log" }
    let response: SDPlatformAuditResponse = try await invokeAuthenticatedFunction(
      "platform_admin",
      body: Request()
    )
    return response.entries
  }

  struct OrgLoginResponse: Decodable, Sendable {
    let access_token: String
    let refresh_token: String
    let active_org_id: UUID
  }

  func orgLogin(orgSlug: String, identifier: String, password: String) async throws -> OrgLoginResponse {
    try await client.functions.invoke(
      "org_login",
      options: FunctionInvokeOptions(
        body: [
          "org_slug": orgSlug,
          "identifier": identifier,
          "password": password,
        ]
      )
    )
  }

  /// Installs the session returned by the server-side organization login and
  /// immediately reads it back. This prevents the UI from entering its
  /// authenticated branch before Supabase has a usable local session.
  func installSession(accessToken: String, refreshToken: String) async throws {
    _ = try await client.auth.setSession(accessToken: accessToken, refreshToken: refreshToken)
    _ = try await client.auth.session
  }

  func signIn(email: String, password: String) async throws {
    _ = try await client.auth.signIn(email: email, password: password)
  }

  func signUp(email: String, password: String) async throws {
    _ = try await client.auth.signUp(email: email, password: password)
  }

  /// Ensures a `public.profiles` row exists for the current user.
  ///
  /// Important: This client code must never update `profiles.role` because the database
  /// explicitly blocks role changes unless the request is made with `service_role`.
  func ensureMyProfileExists(fullName: String?) async throws {
    let session = try await client.auth.session
    let uid = session.user.id
    let cleanName: String?
    if let fullName {
      let trimmed = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
      cleanName = trimmed.isEmpty ? nil : trimmed
    } else {
      cleanName = nil
    }

    // 1) Try insert (role defaults to 'player' in DB).
    // If the row already exists, Postgres will throw a constraint error; we ignore and continue to fetch.
    do {
      _ = try await client
        .from("profiles")
        .insert(ProfileInsert(id: uid, full_name: cleanName))
        .execute()
    } catch {
      // Intentionally ignore; we always follow up with a fetch.
    }

    // 2) If we have a non-empty name, try to patch it (safe: does not touch role).
    if let cleanName {
      do {
        _ = try await client
          .from("profiles")
          .update(ProfileNamePatch(full_name: cleanName))
          .eq("id", value: uid.uuidString)
          .execute()
      } catch {
        // Ignore; caller will still fetch and surface any remaining error.
      }
    }
  }

  func fetchMyProfile() async throws -> Profile {
    let session = try await client.auth.session
    let uid = session.user.id
    return try await client
      .from("profiles")
      .select("id, role, full_name, avatar_path")
      .eq("id", value: uid.uuidString)
      .single()
      .execute()
      .value
  }

  // MARK: - Chat

  func listChatChannels(organizationId: UUID) async throws -> [SDChatChannel] {
    // RLS determines what the caller can see (memberships + announcements).
    return try await client
      .from("sd_chat_channels")
      .select("id,org_id,channel_type,title,audience,created_by,is_archived,pinned_rank,created_at,updated_at")
      .eq("org_id", value: organizationId.uuidString)
      .eq("is_archived", value: false)
      .execute()
      .value
  }

  func chatChannel(channelId: UUID, organizationId: UUID) async throws -> SDChatChannel {
    try await client
      .from("sd_chat_channels")
      .select("id,org_id,channel_type,title,audience,created_by,is_archived,pinned_rank,created_at,updated_at")
      .eq("id", value: channelId.uuidString)
      .eq("org_id", value: organizationId.uuidString)
      .eq("is_archived", value: false)
      .single()
      .execute()
      .value
  }

  func listMyChatMemberships(organizationId: UUID) async throws -> [SDChatMembership] {
    let session = try await client.auth.session
    let uid = session.user.id
    return try await client
      .from("sd_chat_memberships")
      .select("org_id,channel_id,user_id,member_role,joined_at,last_read_at,last_read_message_id,muted")
      .eq("org_id", value: organizationId.uuidString)
      .eq("user_id", value: uid.uuidString)
      .execute()
      .value
  }

  func listChatMemberships(
    channelIds: [UUID],
    organizationId: UUID
  ) async throws -> [SDChatMembership] {
    guard !channelIds.isEmpty else { return [] }
    let idList = channelIds.map(\.uuidString).joined(separator: ",")
    return try await client
      .from("sd_chat_memberships")
      .select("org_id,channel_id,user_id,member_role,joined_at,last_read_at,last_read_message_id,muted")
      .eq("org_id", value: organizationId.uuidString)
      .filter("channel_id", operator: "in", value: "(\(idList))")
      .execute()
      .value
  }

  func listChatLastMessages(channelIds: [UUID]) async throws -> [SDChatLastMessageRow] {
    guard !channelIds.isEmpty else { return [] }
    let idList = channelIds.map(\.uuidString).joined(separator: ",")
    return try await client
      .from("sd_chat_channel_last_message")
      .select("channel_id,body_preview,message_created_at,message_id")
      .filter("channel_id", operator: "in", value: "(\(idList))")
      .execute()
      .value
  }

  func getOrCreateDM(otherUserId: UUID, orgId: UUID? = nil) async throws -> UUID {
    // PostgREST returns scalar results for scalar-returning RPCs (uuid -> JSON string).
    // Decode directly as UUID.
    let ch: UUID
    if let orgId {
      ch = try await client
        .rpc("sd_get_or_create_dm", params: ["other_user_id": otherUserId.uuidString, "target_org_id": orgId.uuidString])
        .execute()
        .value
    } else {
      ch = try await client
        .rpc("sd_get_or_create_dm", params: ["other_user_id": otherUserId.uuidString])
        .execute()
        .value
    }
    return ch
  }

  func createGroup(title: String?, memberIds: [UUID], orgId: UUID? = nil) async throws -> UUID {
    let session = try await client.auth.session
    let uid = session.user.id

    struct Insert: Encodable {
      let org_id: UUID?
      let channel_type: String
      let title: String?
      let created_by: UUID
    }
    let cleanedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines)
    let finalTitle = (cleanedTitle?.isEmpty == false) ? cleanedTitle : nil

    let channel: SDChatChannel = try await client
      .from("sd_chat_channels")
      .insert(Insert(org_id: orgId, channel_type: "group", title: finalTitle, created_by: uid))
      .select("id,org_id,channel_type,title,audience,created_by,is_archived,pinned_rank,created_at,updated_at")
      .single()
      .execute()
      .value

    struct M: Encodable {
      let org_id: UUID?
      let channel_id: UUID
      let user_id: UUID
      let member_role: String
      let last_read_at: String?
    }
    let nowISO = ISO8601DateFormatter().string(from: Date())
    var rows: [M] = []
    rows.append(M(org_id: orgId, channel_id: channel.id, user_id: uid, member_role: "admin", last_read_at: nowISO))
    for mid in memberIds where mid != uid {
      rows.append(M(org_id: orgId, channel_id: channel.id, user_id: mid, member_role: "member", last_read_at: nil))
    }

    if !rows.isEmpty {
      _ = try await client
        .from("sd_chat_memberships")
        .upsert(rows, onConflict: "channel_id,user_id")
        .execute()
    }

    return channel.id
  }

  func listChatMessages(
    channelId: UUID,
    organizationId: UUID,
    before: Date?,
    limit: Int = 60
  ) async throws -> [SDChatMessage] {
    var q = client
      .from("sd_chat_messages")
      .select("id,org_id,channel_id,sender_id,body,created_at,edited_at,deleted_at")
      .eq("org_id", value: organizationId.uuidString)
      .eq("channel_id", value: channelId.uuidString)
      .is("deleted_at", value: nil)

    if let before {
      let iso = ISO8601DateFormatter().string(from: before)
      q = q.filter("created_at", operator: "lt", value: iso)
    }

    return try await q
      .order("created_at", ascending: false)
      .order("id", ascending: false)
      .limit(limit)
      .execute()
      .value
  }

  func sendChatMessage(
    channelId: UUID,
    body: String,
    clientMessageId: UUID
  ) async throws -> SDChatSendResponse {
    let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty {
      throw NSError(domain: "chat", code: 2, userInfo: [NSLocalizedDescriptionKey: "Message is empty."])
    }
    return try await client
      .rpc("sd_send_chat_message", params: [
        "p_channel_id": channelId.uuidString.lowercased(),
        "p_body": trimmed,
        "p_client_message_id": clientMessageId.uuidString.lowercased(),
      ])
      .execute()
      .value
  }

  func markChatConversationRead(
    channelId: UUID,
    throughMessageId: UUID
  ) async throws -> SDChatReadResult {
    try await client
      .rpc("sd_mark_chat_conversation_read", params: [
        "p_channel_id": channelId.uuidString.lowercased(),
        "p_through_message_id": throughMessageId.uuidString.lowercased(),
      ])
      .execute()
      .value
  }

  func listPlayerProfiles() async throws -> [Profile] {
    try await client
      .from("profiles")
      .select("id, role, full_name, avatar_path")
      .order("full_name", ascending: true, nullsFirst: false)
      .execute()
      .value
  }

  // MARK: - Chat user directory

  /// Directory used for starting chats.
  ///
  /// - Coaches: can see all profiles (coach policy already allows it).
  /// - Players/Parents: we intentionally scope to coaches only (via `role='coach'`)
  ///   to avoid exposing all users to each other.
  func listAllProfilesForDirectory() async throws -> [Profile] {
    try await client
      .from("profiles")
      .select("id, role, full_name, avatar_path")
      .order("full_name", ascending: true, nullsFirst: false)
      .execute()
      .value
  }

  func listCoachProfilesForDirectory() async throws -> [Profile] {
    try await client
      .from("profiles")
      .select("id, role, full_name, avatar_path")
      .eq("role", value: "coach")
      .order("full_name", ascending: true, nullsFirst: false)
      .execute()
      .value
  }

  func fetchActiveProgramNames(playerIds: [UUID]) async throws -> [UUID: String] {
    guard !playerIds.isEmpty else { return [:] }

    // Pull active assignments and join template name via FK relationship.
    struct Row: Decodable {
      let player_id: UUID
      let template: Template?
      struct Template: Decodable { let name: String }
    }

    let idList = playerIds.map(\.uuidString).joined(separator: ",")
    let rows: [Row] = try await client
      .from("sd_program_assignments")
      .select("player_id,template:sd_program_templates(name)")
      .is("ended_at", value: nil)
      .filter("player_id", operator: "in", value: "(\(idList))")
      .execute()
      .value

    var out: [UUID: String] = [:]
    for r in rows {
      if let name = r.template?.name, !name.isEmpty {
        out[r.player_id] = name
      }
    }
    return out
  }

  func fetchLatestTestDates(playerIds: [UUID]) async throws -> [UUID: String] {
    guard !playerIds.isEmpty else { return [:] }

    struct Row: Decodable {
      let player_id: UUID
      let entry_date: String
    }

    let idList = playerIds.map(\.uuidString).joined(separator: ",")
    let rows: [Row] = try await client
      .from("sd_testing_entries")
      .select("player_id,entry_date")
      .filter("player_id", operator: "in", value: "(\(idList))")
      .order("entry_date", ascending: false)
      .limit(1200) // safety; enough for typical rosters
      .execute()
      .value

    // First row per player_id is latest because we sort desc.
    var out: [UUID: String] = [:]
    for r in rows where out[r.player_id] == nil {
      out[r.player_id] = r.entry_date
    }
    return out
  }

  // MARK: - Access entitlement

  func fetchAccessEntitlement(userId: UUID) async throws -> SDAccessEntitlement? {
    let rows: [SDAccessEntitlement] = try await client
      .from("sd_access_entitlements")
      .select("user_id,is_active,source,current_period_end,created_at,updated_at")
      .eq("user_id", value: userId.uuidString)
      .limit(1)
      .execute()
      .value
    return rows.first
  }

  struct AppleSubscriptionVerificationResponse: Decodable, Sendable {
    let status: String
    let current_period_end: String?
    let persisted: Bool
    let entitlement_synchronized: Bool
    let access_is_active: Bool
    let idempotent: Bool
  }

  private struct AppleSubscriptionVerificationErrorBody: Decodable {
    let error: String?
    let message: String?
  }

  struct AppleSubscriptionSynchronizationError: LocalizedError {
    let code: String

    var errorDescription: String? {
      switch code {
      case "app_account_token_mismatch":
        return PlayerSubscriptionFailure.tokenMismatch.message
      case "apple_transaction_replay", "apple_transaction_replay_conflict",
           "apple_transaction_reassigned", "apple_original_transaction_reassigned",
           "apple_transaction_lineage_conflict", "apple_transaction_context_mismatch",
           "player_subscription_context_conflict":
        return "This Apple purchase is already associated with a different account or a newer subscription period. Contact support."
      case "actor_profile_missing", "actor_membership_missing", "actor_membership_not_active",
           "actor_role_not_allowed", "target_profile_missing", "target_membership_missing",
           "target_membership_not_active", "target_role_not_player", "parent_link_missing",
           "parent_can_pay_false", "organization_context_mismatch":
        return "This account is not allowed to purchase access for the selected player."
      case "product_id_mismatch", "bundle_id_mismatch", "environment_mismatch",
           "apple_transaction_identifiers_missing", "apple_transaction_invalid":
        return "Apple returned subscription details that do not match this Home Plate app. Contact support."
      case "missing_auth", "invalid_auth":
        return "Your sign-in expired. Sign in again, then restore the purchase."
      default:
        return PlayerSubscriptionFailure.backendSynchronizationFailed.message
      }
    }

    var subscriptionFailure: PlayerSubscriptionFailure {
      if code == "app_account_token_mismatch" { return .tokenMismatch }
      return PlayerSubscriptionFailure(
        code: code.isEmpty ? PlayerSubscriptionFailure.backendSynchronizationFailed.code : code,
        message: errorDescription ?? PlayerSubscriptionFailure.backendSynchronizationFailed.message
      )
    }
  }

  func verifyApplePlayerSubscription(
    purchase: PlayerSubscriptionStore.VerifiedPurchase,
    context: ApplePlayerPurchaseContext
  ) async throws -> AppleSubscriptionVerificationResponse {
    do {
      return try await invokeAuthenticatedFunction(
        "verify-apple-player-subscription",
        body: [
          "org_id": context.organizationId.uuidString.lowercased(),
          "player_id": context.playerId.uuidString.lowercased(),
          "app_account_token": context.appAccountToken.uuidString.lowercased(),
          "transaction_id": String(purchase.id),
          "original_transaction_id": String(purchase.originalTransactionID),
          "product_id": purchase.productID,
          "bundle_id": Bundle.main.bundleIdentifier ?? "",
          "purchase_date_ms": String(Int64(purchase.purchaseDate.timeIntervalSince1970 * 1_000)),
          "expires_date_ms": String(Int64((purchase.expirationDate?.timeIntervalSince1970 ?? 0) * 1_000)),
          "revocation_date_ms": String(Int64((purchase.revocationDate?.timeIntervalSince1970 ?? 0) * 1_000)),
          "environment": purchase.environment,
        ]
      )
    } catch let FunctionsError.httpError(_, data) {
      let response = try? JSONDecoder().decode(AppleSubscriptionVerificationErrorBody.self, from: data)
      let code = response?.error?.trimmingCharacters(in: .whitespacesAndNewlines)
      throw AppleSubscriptionSynchronizationError(
        code: code?.isEmpty == false ? code! : "apple_subscription_sync_failed"
      )
    }
  }

  // MARK: - Facilities scheduling

  func listFacilities(orgId: UUID? = nil, includeInactive: Bool = false) async throws -> [SDFacility] {
    var q = client
      .from("sd_facilities")
      .select()

    if let orgId {
      q = q.eq("org_id", value: orgId.uuidString)
    }
    if !includeInactive {
      q = q.eq("is_active", value: true)
    }

    return try await q
      .order("sort_order", ascending: true)
      .execute()
      .value
  }

  func listFacilityBookings(dayStart: Date, dayEnd: Date, orgId: UUID? = nil) async throws -> [SDFacilityBooking] {
    // Pull bookings that overlap [dayStart, dayEnd).
    let startISO = ISO8601DateFormatter().string(from: dayStart)
    let endISO = ISO8601DateFormatter().string(from: dayEnd)
    var q = client
      .from("sd_facility_bookings")
      .select()
      .lt("start_at", value: endISO)
      .gt("end_at", value: startISO)

    if let orgId {
      q = q.eq("org_id", value: orgId.uuidString)
    }

    return try await q
      .order("start_at", ascending: true)
      .execute()
      .value
  }

  func listFacilityBookings(rangeStart: Date, rangeEnd: Date, orgId: UUID? = nil) async throws -> [SDFacilityBooking] {
    // Pull bookings that overlap [rangeStart, rangeEnd).
    let startISO = ISO8601DateFormatter().string(from: rangeStart)
    let endISO = ISO8601DateFormatter().string(from: rangeEnd)
    var q = client
      .from("sd_facility_bookings")
      .select()
      .lt("start_at", value: endISO)
      .gt("end_at", value: startISO)

    if let orgId {
      q = q.eq("org_id", value: orgId.uuidString)
    }

    return try await q
      .order("start_at", ascending: true)
      .execute()
      .value
  }

  func createFacilityBooking(facilityId: UUID,
                            playerId: UUID?,
                            isBlock: Bool,
                            status: String,
                            activityType: String,
                            startAt: Date,
                            endAt: Date,
                            coachId: UUID?,
                            title: String?,
                            notes: String?,
                            spanFacilityId: UUID? = nil,
                            orgId: UUID? = nil) async throws -> SDFacilityBooking {
    let session = try await client.auth.session
    let uid = session.user.id
    struct Insert: Encodable {
      let org_id: UUID?
      let facility_id: UUID
      let span_facility_id: UUID?
      let player_id: UUID?
      let created_by: UUID
      let is_block: Bool
      let status: String
      let activity_type: String
      let start_at: String
      let end_at: String
      let coach_id: UUID?
      let title: String?
      let notes: String?
    }
    let fmt = ISO8601DateFormatter()
    return try await client
      .from("sd_facility_bookings")
      .insert(Insert(
        org_id: orgId,
        facility_id: facilityId,
        span_facility_id: spanFacilityId,
        player_id: playerId,
        created_by: uid,
        is_block: isBlock,
        status: status,
        activity_type: activityType,
        start_at: fmt.string(from: startAt),
        end_at: fmt.string(from: endAt),
        coach_id: coachId,
        title: title,
        notes: notes
      ))
      .select()
      .single()
      .execute()
      .value
  }

  func updateFacilityBooking(id: UUID,
                             facilityId: UUID,
                             status: String,
                             activityType: String,
                             startAt: Date,
                             endAt: Date,
                             coachId: UUID?,
                             approved: Bool,
                             title: String?,
                             notes: String?,
                             spanFacilityId: UUID? = nil,
                             orgId: UUID? = nil) async throws -> SDFacilityBooking {
    let session = try await client.auth.session
    let uid = session.user.id
    struct Patch: Encodable {
      let org_id: UUID?
      let facility_id: UUID
      let span_facility_id: UUID?
      let status: String
      let activity_type: String
      let start_at: String
      let end_at: String
      let coach_id: UUID?
      let approved_by: UUID?
      let approved_at: String?
      let title: String?
      let notes: String?
    }
    let fmt = ISO8601DateFormatter()
    let approvedAt = approved ? fmt.string(from: Date()) : nil
    return try await client
      .from("sd_facility_bookings")
      .update(Patch(
        org_id: orgId,
        facility_id: facilityId,
        span_facility_id: spanFacilityId,
        status: status,
        activity_type: activityType,
        start_at: fmt.string(from: startAt),
        end_at: fmt.string(from: endAt),
        coach_id: coachId,
        approved_by: approved ? uid : nil,
        approved_at: approvedAt,
        title: title,
        notes: notes
      ))
      .eq("id", value: id.uuidString)
      .select()
      .single()
      .execute()
      .value
  }

  struct SDFacilityUpsert: Encodable {
    let id: UUID?
    let org_id: UUID
    let name: String
    let is_active: Bool
    let sort_order: Int
    let resource_type: String
    let color_hex: String?
    let capacity: Int
    let metadata: [String: SDJSONValue]
  }

  func createFacility(_ facility: SDFacilityUpsert) async throws -> SDFacility {
    try await client
      .from("sd_facilities")
      .insert(facility)
      .select()
      .single()
      .execute()
      .value
  }

  func updateFacility(_ facility: SDFacilityUpsert) async throws -> SDFacility {
    guard let id = facility.id else {
      throw NSError(domain: "SupabaseService", code: 10, userInfo: [NSLocalizedDescriptionKey: "Facility id is required."])
    }
    return try await client
      .from("sd_facilities")
      .update(facility)
      .eq("id", value: id.uuidString)
      .select()
      .single()
      .execute()
      .value
  }

  func deleteFacility(id: UUID) async throws {
    _ = try await client
      .from("sd_facilities")
      .delete()
      .eq("id", value: id.uuidString)
      .execute()
  }

  // MARK: - Parent linking

  func listMyParentInvites() async throws -> [SDParentInvite] {
    try await client
      .from("sd_parent_invites")
      .select("id,email_norm,child_id,invited_by,relationship,accepted_at,parent_id,created_at")
      .is("accepted_at", value: nil)
      .order("created_at", ascending: false)
      .execute()
      .value
  }

  func acceptParentInvite(inviteId: UUID) async throws {
    let session = try await client.auth.session
    let uid = session.user.id
    struct Patch: Encodable {
      let parent_id: UUID
      let accepted_at: Date
    }
    _ = try await client
      .from("sd_parent_invites")
      .update(Patch(parent_id: uid, accepted_at: Date()))
      .eq("id", value: inviteId.uuidString)
      .execute()
  }

  func listMyParentChildLinks(orgId: UUID) async throws -> [SDParentChildLink] {
    try await client
      .from("sd_parent_child_links")
      .select("org_id,parent_id,child_id,relationship,can_book,can_pay,created_at,created_by")
      .eq("org_id", value: orgId.uuidString)
      .execute()
      .value
  }

  func listMyParentLinksAsChild() async throws -> [SDParentChildLink] {
    let session = try await client.auth.session
    let uid = session.user.id
    return try await client
      .from("sd_parent_child_links")
      .select("org_id,parent_id,child_id,relationship,can_book,can_pay,created_at,created_by")
      .eq("child_id", value: uid.uuidString)
      .execute()
      .value
  }

  func listProfiles(ids: [UUID]) async throws -> [Profile] {
    guard !ids.isEmpty else { return [] }
    let idList = ids.map(\.uuidString).joined(separator: ",")
    return try await client
      .from("profiles")
      .select("id, role, full_name, avatar_path")
      .filter("id", operator: "in", value: "(\(idList))")
      .execute()
      .value
  }

  // MARK: - Parent code (player -> parent linking)

  struct SDParentCodeRow: Decodable, Equatable {
    let child_id: UUID
    let parent_code: String
  }

  func fetchMyParentCode() async throws -> String? {
    let session = try await client.auth.session
    let uid = session.user.id
    do {
      let row: SDParentCodeRow = try await client
        .from("sd_parent_codes")
        .select("child_id,parent_code")
        .eq("child_id", value: uid.uuidString)
        .single()
        .execute()
        .value
      let code = row.parent_code.trimmingCharacters(in: .whitespacesAndNewlines)
      return code.isEmpty ? nil : code
    } catch {
      // If the row doesn't exist yet (older projects), treat as missing.
      return nil
    }
  }

  // MARK: - Profile details (Account)

  struct SDProfileDetails: Identifiable, Decodable, Equatable {
    let id: UUID
    let role: String
    let full_name: String?
    let avatar_path: String?
    let phone: String?
    let grad_year: Int?
    let primary_position: String?
    let bats: String?
    let throws_hand: String?
    let school: String?
    let team: String?
    let height_in: Int?
    let weight_lb: Int?
    let notes: String?
    let professional_title: String?
    let bio: String?
    let specialties: String?
    let website: String?
    let years_experience: Int?

    private enum CodingKeys: String, CodingKey {
      case id, role, full_name, avatar_path, phone, grad_year, primary_position, bats, school, team, height_in, weight_lb, notes
      case professional_title, bio, specialties, website, years_experience
      case throws_hand = "throws"
    }
  }

  func fetchMyProfileDetails() async throws -> SDProfileDetails {
    let session = try await client.auth.session
    let uid = session.user.id
    return try await client
      .from("profiles")
      .select("id,role,full_name,avatar_path,phone,grad_year,primary_position,bats,throws,school,team,height_in,weight_lb,notes,professional_title,bio,specialties,website,years_experience")
      .eq("id", value: uid.uuidString)
      .single()
      .execute()
      .value
  }

  struct SDProfileDetailsPatch: Encodable {
    let full_name: String?
    let avatar_path: String?
    let phone: String?
    let grad_year: Int?
    let primary_position: String?
    let bats: String?
    let throws_hand: String?
    let school: String?
    let team: String?
    let height_in: Int?
    let weight_lb: Int?
    let notes: String?
    let professional_title: String?
    let bio: String?
    let specialties: String?
    let website: String?
    let years_experience: Int?

    private enum CodingKeys: String, CodingKey {
      case full_name, avatar_path, phone, grad_year, primary_position, bats, school, team, height_in, weight_lb, notes
      case professional_title, bio, specialties, website, years_experience
      case throws_hand = "throws"
    }
  }

  func updateMyProfileDetails(_ patch: SDProfileDetailsPatch) async throws {
    let session = try await client.auth.session
    let uid = session.user.id
    _ = try await client
      .from("profiles")
      .update(patch)
      .eq("id", value: uid.uuidString)
      .execute()
  }

  func uploadMyAvatarJPEG(_ jpegData: Data) async throws -> String {
    let session = try await client.auth.session
    let uid = session.user.id
    // Storage RLS compares the first path segment to auth.uid()::text, which
    // PostgreSQL renders in lowercase. Foundation's UUID string is uppercase.
    let path = "\(uid.uuidString.lowercased())/avatar.jpg"
    _ = try await client
      .storage
      .from("avatars")
      .upload(path, data: jpegData, options: FileOptions(contentType: "image/jpeg", upsert: true))
    return path
  }

  func publicAvatarURL(path: String) -> URL? {
    do {
      return try client.storage.from("avatars").getPublicURL(path: path, cacheNonce: nil)
    } catch {
      return nil
    }
  }

  func uploadOrganizationLogoJPEG(orgId: UUID, jpegData: Data) async throws -> String {
    let path = "\(orgId.uuidString)/logo.jpg"
    _ = try await client
      .storage
      .from("org-assets")
      .upload(path, data: jpegData, options: FileOptions(contentType: "image/jpeg", upsert: true))
    return path
  }

  func publicOrganizationLogoURL(path: String) -> URL? {
    do {
      return try client.storage.from("org-assets").getPublicURL(path: path, cacheNonce: nil)
    } catch {
      return nil
    }
  }

  // MARK: - Player → Parent request flow

  func listMyParentInviteRequests() async throws -> [SDParentInviteRequest] {
    let session = try await client.auth.session
    let uid = session.user.id
    return try await client
      .from("sd_parent_invite_requests")
      .select("id,email_norm,child_id,requested_by,relationship,status,coach_note,created_at,updated_at")
      .eq("child_id", value: uid.uuidString)
      .order("created_at", ascending: false)
      .execute()
      .value
  }

  func createParentInviteRequest(orgId: UUID, parentEmail: String, relationship: String?) async throws -> SDParentInviteRequest {
    let session = try await client.auth.session
    let uid = session.user.id

    let emailNorm = parentEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if emailNorm.isEmpty {
      throw NSError(domain: "SupabaseService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Email is required."])
    }

    struct Insert: Encodable {
      let org_id: UUID
      let email_norm: String
      let child_id: UUID
      let requested_by: UUID
      let relationship: String?
      let status: String
    }

    return try await client
      .from("sd_parent_invite_requests")
      .insert(Insert(org_id: orgId, email_norm: emailNorm, child_id: uid, requested_by: uid, relationship: relationship, status: "requested"))
      .select("id,email_norm,child_id,requested_by,relationship,status,coach_note,created_at,updated_at")
      .single()
      .execute()
      .value
  }

  func cancelParentInviteRequest(requestId: UUID) async throws {
    struct Patch: Encodable { let status: String }
    _ = try await client
      .from("sd_parent_invite_requests")
      .update(Patch(status: "cancelled"))
      .eq("id", value: requestId.uuidString)
      .execute()
  }

  func coachListParentInviteRequests(childId: UUID? = nil, status: String? = nil) async throws -> [SDParentInviteRequest] {
    var q = client
      .from("sd_parent_invite_requests")
      .select("id,email_norm,child_id,requested_by,relationship,status,coach_note,created_at,updated_at")

    if let childId {
      q = q.eq("child_id", value: childId.uuidString)
    }
    if let status {
      q = q.eq("status", value: status)
    }

    return try await q
      .order("created_at", ascending: false)
      .execute()
      .value
  }

  func coachUpdateParentInviteRequestStatus(requestId: UUID, status: String, coachNote: String?) async throws {
    struct Patch: Encodable {
      let status: String
      let coach_note: String?
    }
    _ = try await client
      .from("sd_parent_invite_requests")
      .update(Patch(status: status, coach_note: coachNote))
      .eq("id", value: requestId.uuidString)
      .execute()
  }

  // MARK: - Coach → Parent invites

  func coachCreateParentInvite(orgId: UUID, childId: UUID, parentEmail: String, relationship: String?) async throws -> SDParentInvite {
    let session = try await client.auth.session
    let uid = session.user.id

    let emailNorm = parentEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if emailNorm.isEmpty { throw NSError(domain: "SupabaseService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Email is required."]) }

    struct Insert: Encodable {
      let org_id: UUID
      let email_norm: String
      let child_id: UUID
      let invited_by: UUID
      let relationship: String?
    }
    return try await client
      .from("sd_parent_invites")
      .insert(Insert(org_id: orgId, email_norm: emailNorm, child_id: childId, invited_by: uid, relationship: relationship))
      .select("id,email_norm,child_id,invited_by,relationship,accepted_at,parent_id,created_at")
      .single()
      .execute()
      .value
  }

  func coachListParentInvites(childId: UUID) async throws -> [SDParentInvite] {
    try await client
      .from("sd_parent_invites")
      .select("id,email_norm,child_id,invited_by,relationship,accepted_at,parent_id,created_at")
      .eq("child_id", value: childId.uuidString)
      .order("created_at", ascending: false)
      .execute()
      .value
  }

  func coachListParentLinks(childId: UUID) async throws -> [SDParentChildLink] {
    try await client
      .from("sd_parent_child_links")
      .select("org_id,parent_id,child_id,relationship,can_book,can_pay,created_at,created_by")
      .eq("child_id", value: childId.uuidString)
      .execute()
      .value
  }

  // MARK: - Internal payment requests (Stripe Payments Phase 1B-1)

  private func invokePaymentRequestFunction<Response: Decodable, Body: Encodable>(
    body: Body
  ) async throws -> Response {
    do {
      return try await invokeAuthenticatedFunction("payment_requests", body: body)
    } catch let error as FunctionsError {
      switch error {
      case .httpError(let statusCode, let data):
        throw SDEdgeFunctionHTTPError.decode(statusCode: statusCode, data: data)
      case .relayError:
        throw error
      }
    }
  }

  private nonisolated static func paymentRequestTopLevelJSONKeys(_ data: Data) -> [String] {
    guard let object = try? JSONSerialization.jsonObject(with: data),
          let dictionary = object as? [String: Any] else { return [] }
    return dictionary.keys.sorted()
  }

  func listEligiblePaymentRequestPlayersResponse(
    orgId: UUID
  ) async throws -> SDPaymentRequestEligiblePlayersResponse {
    let action = "list_eligible_players"
    let body = ["action": action, "org_id": orgId.uuidString]
    #if DEBUG
    print("[PaymentRequestRoster] action_sent=\(action) org_id=\(orgId.uuidString)")
    #endif

    let session = try await client.auth.session
    client.functions.setAuth(token: session.accessToken)
    do {
      let response: SDPaymentRequestEligiblePlayersResponse = try await client.functions.invoke(
        "payment_requests",
        options: FunctionInvokeOptions(body: body),
        decode: { @Sendable data, httpResponse in
          let topLevelKeys = Self.paymentRequestTopLevelJSONKeys(data)
          #if DEBUG
          print(
            "[PaymentRequestRoster] org_id=\(orgId.uuidString) "
              + "http_result=\(httpResponse.statusCode) "
              + "raw_top_level_json_keys=\(topLevelKeys.joined(separator: ","))"
          )
          #endif
          let decoded = try SDPaymentRequestEligiblePlayersContract.decode(data)
          #if DEBUG
          print(
            "[PaymentRequestRoster] org_id=\(orgId.uuidString) "
              + "decoded_player_count=\(decoded.players.count)"
          )
          #endif
          return decoded
        }
      )
      return response
    } catch let error as FunctionsError {
      switch error {
      case .httpError(let statusCode, let data):
        #if DEBUG
        let topLevelKeys = Self.paymentRequestTopLevelJSONKeys(data)
        print(
          "[PaymentRequestRoster] org_id=\(orgId.uuidString) "
            + "http_result=\(statusCode) "
            + "raw_top_level_json_keys=\(topLevelKeys.joined(separator: ","))"
        )
        #endif
        SDApplicationErrorClassifier.log(
          error,
          functionName: "payment_requests",
          statusCode: statusCode
        )
        if statusCode == 404 {
          throw SDServiceError(
            category: .notDeployed,
            functionName: "payment_requests",
            statusCode: statusCode
          )
        }
        throw SDEdgeFunctionHTTPError.decode(statusCode: statusCode, data: data)
      case .relayError:
        #if DEBUG
        print("[PaymentRequestRoster] org_id=\(orgId.uuidString) http_result=relay_error")
        #endif
        throw SDServiceError(
          category: .serviceUnavailable,
          functionName: "payment_requests",
          statusCode: nil
        )
      }
    } catch {
      if SDApplicationErrorClassifier.isCancellation(error, taskIsCancelled: Task.isCancelled) {
        throw CancellationError()
      }
      throw error
    }
  }

  func listEligiblePaymentRequestPlayers(
    orgId: UUID
  ) async throws -> [SDPaymentRequestEligiblePlayer] {
    try await listEligiblePaymentRequestPlayersResponse(orgId: orgId).players
  }

  nonisolated static func paymentRequestListBody(
    orgId: UUID,
    playerId: UUID? = nil
  ) -> [String: String] {
    var body = [
      "action": "list",
      "org_id": orgId.uuidString,
    ]
    if let playerId { body["player_id"] = playerId.uuidString.lowercased() }
    return body
  }

  func listPaymentRequests(orgId: UUID, playerId: UUID? = nil) async throws -> [SDPaymentRequest] {
    let body = Self.paymentRequestListBody(orgId: orgId, playerId: playerId)
    let response: SDPaymentRequestListResponse = try await invokePaymentRequestFunction(body: body)
    return response.requests
  }

  func listManagedPaymentRequests(orgId: UUID) async throws -> [SDPaymentRequest] {
    let response: SDPaymentRequestListResponse = try await invokePaymentRequestFunction(
      body: [
        "action": "list_manage",
        "org_id": orgId.uuidString,
      ]
    )
    return response.requests
  }

  func createPaymentRequests(
    payload: SDPaymentRequestCreatePayload
  ) async throws -> SDPaymentRequestCreateResponse {
    try await invokePaymentRequestFunction(body: payload)
  }

  func cancelPaymentRequest(orgId: UUID, requestId: UUID) async throws -> SDPaymentRequest {
    let response: SDPaymentRequestSingleResponse = try await invokePaymentRequestFunction(
      body: [
        "action": "cancel",
        "org_id": orgId.uuidString,
        "request_id": requestId.uuidString,
      ]
    )
    return response.request
  }

  // MARK: - Player Development AI (Phase 11A deterministic foundation)

  private func invokePlayerDevelopmentAI<Request: Encodable, Response: Decodable>(
    _ request: Request
  ) async throws -> Response {
    try await requirePlayerDevelopmentCopilotEnabled()
    do {
      return try await invokeAuthenticatedFunction("player-development-ai", body: request)
    } catch let error as FunctionsError {
      switch error {
      case .httpError(let statusCode, let data):
        throw SDEdgeFunctionHTTPError.decode(statusCode: statusCode, data: data)
      case .relayError:
        throw error
      }
    }
  }

  func buildDevelopmentEvidencePack(
    organizationId: UUID,
    playerId: UUID,
    reportType: SDDevelopmentReportType = .playerDevelopmentSummary,
    window: SDDevelopmentWindow,
    evidenceCutoff: Date = Date()
  ) async throws -> SDDevelopmentEvidencePack {
    let response: SDDevelopmentEvidencePackResponse = try await invokePlayerDevelopmentAI(
      SDDevelopmentPlayerRequest(
        action: "build_evidence_pack",
        organizationId: organizationId,
        playerId: playerId,
        reportType: reportType.rawValue,
        windowStart: window.start,
        windowEnd: window.end,
        evidenceCutoff: Self.developmentISO8601String(evidenceCutoff)
      )
    )
    return response.evidencePack
  }

  func generateDevelopmentReport(
    organizationId: UUID,
    playerId: UUID,
    reportType: SDDevelopmentReportType = .playerDevelopmentSummary,
    intendedAudience: String = "coach",
    window: SDDevelopmentWindow,
    evidenceCutoff: Date,
    idempotencyKey: UUID
  ) async throws -> SDDevelopmentGenerateResponse {
    try await invokePlayerDevelopmentAI(
      SDDevelopmentGenerateRequest(
        organizationId: organizationId,
        playerId: playerId,
        reportType: reportType,
        intendedAudience: intendedAudience,
        windowStart: window.start,
        windowEnd: window.end,
        evidenceCutoff: Self.developmentISO8601String(evidenceCutoff),
        idempotencyKey: idempotencyKey
      )
    )
  }

  func generatePlayerDevelopmentReport(
    organizationId: UUID,
    playerId: UUID,
    window: SDDevelopmentWindow,
    evidenceCutoff: Date,
    idempotencyKey: UUID
  ) async throws -> SDDevelopmentGenerateResponse {
    try await invokePlayerDevelopmentAI(
      SDDevelopmentPlayerGenerateRequest(
        organizationId: organizationId,
        playerId: playerId,
        windowStart: window.start,
        windowEnd: window.end,
        evidenceCutoff: Self.developmentISO8601String(evidenceCutoff),
        idempotencyKey: idempotencyKey
      )
    )
  }

  func listDevelopmentReports(
    organizationId: UUID,
    playerId: UUID
  ) async throws -> [SDDevelopmentReport] {
    let response: SDDevelopmentReportsResponse = try await invokePlayerDevelopmentAI(
      SDDevelopmentPlayerRequest(
        action: "list_player_reports",
        organizationId: organizationId,
        playerId: playerId,
        reportType: nil,
        windowStart: nil,
        windowEnd: nil,
        evidenceCutoff: nil
      )
    )
    return response.reports
  }

  func developmentReportDetail(
    organizationId: UUID,
    reportId: UUID
  ) async throws -> SDDevelopmentReportDetail {
    struct Request: Encodable {
      let action = "get_report"
      let org_id: UUID
      let report_id: UUID
    }
    return try await invokePlayerDevelopmentAI(
      Request(org_id: organizationId, report_id: reportId)
    )
  }

  func playerDevelopmentReportDetail(
    organizationId: UUID,
    reportId: UUID
  ) async throws -> SDDevelopmentReportDetail {
    try await invokePlayerDevelopmentAI(
      SDDevelopmentReportResourceRequest(
        action: "get_player_report",
        organizationId: organizationId,
        reportId: reportId
      )
    )
  }

  func archivePlayerDevelopmentReport(
    organizationId: UUID,
    reportId: UUID
  ) async throws -> SDDevelopmentReport {
    let response: SDDevelopmentReportResponse = try await invokePlayerDevelopmentAI(
      SDDevelopmentReportResourceRequest(
        action: "archive_player_report",
        organizationId: organizationId,
        reportId: reportId
      )
    )
    return response.report
  }

  func reviewDevelopmentReport(
    organizationId: UUID,
    reportId: UUID,
    action: SDDevelopmentReviewAction,
    notes: String?,
    coachEdits: [String: SDJSONValue] = [:]
  ) async throws -> SDDevelopmentReport {
    let response: SDDevelopmentReportResponse = try await invokePlayerDevelopmentAI(
      SDDevelopmentReportReviewRequest(
        organizationId: organizationId,
        reportId: reportId,
        reviewAction: action,
        reviewNotes: notes,
        coachEdits: coachEdits
      )
    )
    return response.report
  }

  func listDevelopmentAlerts(
    organizationId: UUID,
    playerId: UUID
  ) async throws -> [SDDevelopmentAlert] {
    let response: SDDevelopmentAlertsResponse = try await invokePlayerDevelopmentAI(
      SDDevelopmentPlayerRequest(
        action: "list_player_alerts",
        organizationId: organizationId,
        playerId: playerId,
        reportType: nil,
        windowStart: nil,
        windowEnd: nil,
        evidenceCutoff: nil
      )
    )
    return response.alerts
  }

  func developmentAlertDetail(
    organizationId: UUID,
    alertId: UUID
  ) async throws -> SDDevelopmentAlertDetail {
    struct Request: Encodable {
      let action = "get_alert"
      let org_id: UUID
      let alert_id: UUID
    }
    return try await invokePlayerDevelopmentAI(
      Request(org_id: organizationId, alert_id: alertId)
    )
  }

  func playerDevelopmentAlertDetail(
    organizationId: UUID,
    alertId: UUID
  ) async throws -> SDDevelopmentAlertDetail {
    try await invokePlayerDevelopmentAI(
      SDDevelopmentAlertResourceRequest(
        action: "get_player_alert",
        organizationId: organizationId,
        alertId: alertId
      )
    )
  }

  func dismissPlayerDevelopmentAlert(
    organizationId: UUID,
    alertId: UUID
  ) async throws -> SDDevelopmentAlert {
    let response: SDDevelopmentAlertResponse = try await invokePlayerDevelopmentAI(
      SDDevelopmentAlertResourceRequest(
        action: "dismiss_player_alert",
        organizationId: organizationId,
        alertId: alertId
      )
    )
    return response.alert
  }

  func runDevelopmentAlertDetection(
    organizationId: UUID,
    playerId: UUID,
    window: SDDevelopmentWindow,
    evidenceCutoff: Date = Date()
  ) async throws -> SDDevelopmentAlertDetectionResponse {
    try await invokePlayerDevelopmentAI(
      SDDevelopmentPlayerRequest(
        action: "run_alert_detection",
        organizationId: organizationId,
        playerId: playerId,
        reportType: SDDevelopmentReportType.developmentAlertReview.rawValue,
        windowStart: window.start,
        windowEnd: window.end,
        evidenceCutoff: Self.developmentISO8601String(evidenceCutoff)
      )
    )
  }

  func reviewDevelopmentAlert(
    organizationId: UUID,
    alertId: UUID,
    action: SDDevelopmentAlertReviewAction,
    notes: String?
  ) async throws -> SDDevelopmentAlert {
    let response: SDDevelopmentAlertResponse = try await invokePlayerDevelopmentAI(
      SDDevelopmentAlertReviewRequest(
        organizationId: organizationId,
        alertId: alertId,
        reviewAction: action,
        reviewNotes: notes
      )
    )
    return response.alert
  }

  func developmentRosterAttention(
    organizationId: UUID
  ) async throws -> SDDevelopmentRosterAttentionResponse {
    try await invokePlayerDevelopmentAI(
      SDDevelopmentOrganizationRequest(action: "roster_attention", organizationId: organizationId)
    )
  }

  private static func developmentISO8601String(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: date)
  }

  // MARK: - Player Development Imports (Phase 11B.1)

  private func invokePlayerDevelopmentImports<Request: Encodable, Response: Decodable>(
    _ request: Request
  ) async throws -> Response {
    do {
      return try await invokeAuthenticatedFunction("player-development-imports", body: request)
    } catch let error as FunctionsError {
      switch error {
      case .httpError(let statusCode, let data):
        throw SDEdgeFunctionHTTPError.decode(statusCode: statusCode, data: data)
      case .relayError:
        throw error
      }
    }
  }

  func createDevelopmentImportJob(
    organizationId: UUID,
    playerId: UUID?,
    provider: SDDevelopmentImportProvider,
    fileName: String,
    idempotencyKey: UUID
  ) async throws -> SDDevelopmentImportCreateResponse {
    struct Request: Encodable {
      let action = "create_job"
      let org_id: UUID
      let player_id: UUID?
      let provider: String
      let file_name: String
      let idempotency_key: UUID
    }
    return try await invokePlayerDevelopmentImports(Request(
      org_id: organizationId,
      player_id: playerId,
      provider: provider.rawValue,
      file_name: fileName,
      idempotency_key: idempotencyKey
    ))
  }

  func uploadDevelopmentImportFile(
    _ data: Data,
    target: SDDevelopmentImportUploadTarget,
    fileType: String
  ) async throws {
    let contentType = fileType.lowercased() == "tsv" ? "text/tab-separated-values" : "text/csv"
    _ = try await client.storage.from(target.bucket).upload(
      target.path,
      data: data,
      options: FileOptions(contentType: contentType, upsert: false)
    )
  }

  func inspectDevelopmentImport(
    organizationId: UUID,
    jobId: UUID
  ) async throws -> SDDevelopmentImportInspectResponse {
    struct Request: Encodable { let action = "inspect_file"; let org_id: UUID; let job_id: UUID }
    return try await invokePlayerDevelopmentImports(Request(org_id: organizationId, job_id: jobId))
  }

  func saveDevelopmentImportMapping(
    organizationId: UUID,
    jobId: UUID,
    mapping: SDDevelopmentImportMapping,
    mappingName: String?
  ) async throws -> SDDevelopmentImportJob {
    struct Request: Encodable {
      let action = "save_mapping"
      let org_id: UUID
      let job_id: UUID
      let mapping: SDDevelopmentImportMapping
      let mapping_name: String?
    }
    let response: SDDevelopmentImportJobResponse = try await invokePlayerDevelopmentImports(
      Request(org_id: organizationId, job_id: jobId, mapping: mapping, mapping_name: mappingName)
    )
    return response.job
  }

  func validateDevelopmentImport(
    organizationId: UUID,
    jobId: UUID
  ) async throws -> SDDevelopmentImportPreviewResponse {
    struct Request: Encodable { let action = "validate_job"; let org_id: UUID; let job_id: UUID; let limit = 100 }
    return try await invokePlayerDevelopmentImports(Request(org_id: organizationId, job_id: jobId))
  }

  func getDevelopmentImportJob(
    organizationId: UUID,
    jobId: UUID
  ) async throws -> SDDevelopmentImportJob {
    struct Request: Encodable { let action = "get_job"; let org_id: UUID; let job_id: UUID }
    let response: SDDevelopmentImportJobResponse = try await invokePlayerDevelopmentImports(
      Request(org_id: organizationId, job_id: jobId)
    )
    return response.job
  }

  func commitDevelopmentImport(
    organizationId: UUID,
    jobId: UUID
  ) async throws -> SDDevelopmentImportCommitResponse {
    struct Request: Encodable { let action = "commit_job"; let org_id: UUID; let job_id: UUID }
    return try await invokePlayerDevelopmentImports(Request(org_id: organizationId, job_id: jobId))
  }

  func listDevelopmentImportJobs(organizationId: UUID) async throws -> [SDDevelopmentImportJob] {
    struct Request: Encodable { let action = "list_jobs"; let org_id: UUID; let limit = 100 }
    let response: SDDevelopmentImportJobsResponse = try await invokePlayerDevelopmentImports(Request(org_id: organizationId))
    return response.jobs
  }

  func listDevelopmentImportMappings(
    organizationId: UUID,
    provider: SDDevelopmentImportProvider
  ) async throws -> [SDDevelopmentImportMappingProfile] {
    struct Request: Encodable { let action = "list_mappings"; let org_id: UUID; let provider: String }
    let response: SDDevelopmentImportMappingsResponse = try await invokePlayerDevelopmentImports(
      Request(org_id: organizationId, provider: provider.rawValue)
    )
    return response.mappings
  }

  func archiveDevelopmentImportMapping(
    organizationId: UUID,
    mappingProfileId: UUID
  ) async throws -> SDDevelopmentImportMappingProfile {
    struct Request: Encodable {
      let action = "archive_mapping"
      let org_id: UUID
      let mapping_profile_id: UUID
    }
    let response: SDDevelopmentImportMappingResponse = try await invokePlayerDevelopmentImports(
      Request(org_id: organizationId, mapping_profile_id: mappingProfileId)
    )
    return response.mapping
  }

  func listDevelopmentMetricDefinitions() async throws -> [SDDevelopmentMetricDefinition] {
    try await client.from("sd_development_metric_definitions")
      .select("id,canonical_key,display_name,category,canonical_unit,preferred_direction,target_min,target_max,minimum_sample_size")
      .eq("status", value: "active")
      .in("data_type", values: ["number", "duration"])
      .order("category")
      .order("display_name")
      .execute()
      .value
  }

  func resolveDevelopmentImportPlayer(
    organizationId: UUID,
    jobId: UUID,
    sourceKey: String,
    playerId: UUID
  ) async throws -> SDDevelopmentImportJob {
    struct Request: Encodable {
      let action = "resolve_player"
      let org_id: UUID
      let job_id: UUID
      let source_key: String
      let player_id: UUID
    }
    let response: SDDevelopmentImportJobResponse = try await invokePlayerDevelopmentImports(
      Request(org_id: organizationId, job_id: jobId, source_key: sourceKey, player_id: playerId)
    )
    return response.job
  }

  func listDevelopmentImportRowErrors(
    organizationId: UUID,
    jobId: UUID
  ) async throws -> [SDDevelopmentImportRowError] {
    struct Request: Encodable {
      let action = "list_row_errors"
      let org_id: UUID
      let job_id: UUID
      let limit = 100
    }
    let response: SDDevelopmentImportErrorsResponse = try await invokePlayerDevelopmentImports(
      Request(org_id: organizationId, job_id: jobId)
    )
    return response.errors
  }

  func archiveDevelopmentImport(
    organizationId: UUID,
    jobId: UUID
  ) async throws -> SDDevelopmentImportJob {
    struct Request: Encodable { let action = "archive_job"; let org_id: UUID; let job_id: UUID }
    let response: SDDevelopmentImportJobResponse = try await invokePlayerDevelopmentImports(Request(org_id: organizationId, job_id: jobId))
    return response.job
  }

  // MARK: - Player Development Coach Copilot (Phase 11C-11E)

  private func invokePlayerDevelopmentCopilot<Response: Decodable>(
    _ request: SDCopilotRequest,
    canonicalPayloadKey: SDCopilotCanonicalPayloadKey = .data
  ) async throws -> Response {
    try await requirePlayerDevelopmentCopilotEnabled()
    var correlatedRequest = request
    let requestId = request.clientRequestId ?? UUID()
    correlatedRequest.clientRequestId = requestId
    let requestIdText = requestId.uuidString.lowercased()
    do {
      let session = try await client.auth.session
      client.functions.setAuth(token: session.accessToken)
      return try await client.functions.invoke(
        "player-development-copilot",
        options: FunctionInvokeOptions(
          headers: ["x-client-request-id": requestIdText],
          body: correlatedRequest
        ),
        decode: { @Sendable data, httpResponse in
          let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type")
          Self.logCopilotResponseReceived(
            data: data,
            statusCode: httpResponse.statusCode,
            contentType: contentType,
            requestId: requestIdText
          )
          do {
            return try SDCopilotResponseContract.decode(
              Response.self,
              from: data,
              statusCode: httpResponse.statusCode,
              contentType: contentType,
              requestId: requestIdText,
              canonicalPayloadKey: canonicalPayloadKey
            )
          } catch {
            Self.logCopilotResponseFailure(error)
            throw error
          }
        }
      )
    } catch let error as FunctionsError {
      switch error {
      case .httpError(let statusCode, let data):
        Self.logCopilotResponseReceived(
          data: data,
          statusCode: statusCode,
          contentType: nil,
          requestId: requestIdText
        )
        do {
          return try SDCopilotResponseContract.decode(
            Response.self,
            from: data,
            statusCode: statusCode,
            contentType: nil,
            requestId: requestIdText,
            canonicalPayloadKey: canonicalPayloadKey
          )
        } catch {
          Self.logCopilotResponseFailure(error)
          throw error
        }
      case .relayError:
        throw error
      }
    }
  }

  private nonisolated static func logCopilotResponseFailure(_ error: Error) {
    #if DEBUG
    guard let response = error as? SDCopilotResponseContractError else {
      print("[PlayerCopilotResponse] diagnostic_code=transport_error detail=\(error.localizedDescription)")
      return
    }
    if let diagnostic = response.diagnostic {
      print(
        "[PlayerCopilotResponse] request_id=\(diagnostic.requestId) "
          + "http_status=\(diagnostic.statusCode) "
          + "content_type=\(diagnostic.contentType ?? "missing") "
          + "diagnostic_code=\(response.diagnosticCode) "
          + "decoding_case=\(diagnostic.decodingCase) "
          + "missing_key=\(diagnostic.missingKey ?? "none") "
          + "coding_path=\(diagnostic.codingPath) "
          + "detail=\(diagnostic.debugDescription) "
          + "redacted_body=\(diagnostic.redactedBody)"
      )
    } else {
      print(
        "[PlayerCopilotResponse] request_id=\(response.requestId) "
          + "diagnostic_code=\(response.diagnosticCode) "
          + "detail=\(response.localizedDescription)"
      )
    }
    #endif
  }

  private nonisolated static func logCopilotResponseReceived(
    data: Data,
    statusCode: Int,
    contentType: String?,
    requestId: String
  ) {
    #if DEBUG
    print(
      "[PlayerCopilotResponse] request_id=\(requestId) "
        + "http_status=\(statusCode) "
        + "content_type=\(contentType ?? "missing") "
        + "redacted_body=\(SDCopilotResponseContract.redactedBody(from: data))"
    )
    #endif
  }

  func listCopilotConversations(
    organizationId: UUID,
    playerId: UUID,
    audience: SDCopilotAudience,
    offset: Int = 0,
    limit: Int = 25
  ) async throws -> SDCopilotConversationsResponse {
    try await invokePlayerDevelopmentCopilot(
      SDCopilotRequest(
        action: "list_conversations",
        organizationId: organizationId,
        audience: audience,
        playerId: playerId,
        limit: limit,
        offset: offset
      )
    )
  }

  func createCopilotConversation(
    organizationId: UUID,
    playerId: UUID,
    audience: SDCopilotAudience,
    title: String,
    reportingWindowDays: Int,
    idempotencyKey: UUID
  ) async throws -> SDCopilotConversation {
    let response: SDCopilotConversationResponse = try await invokePlayerDevelopmentCopilot(
      SDCopilotRequest(
        action: "create_conversation",
        organizationId: organizationId,
        audience: audience,
        playerId: playerId,
        title: title,
        reportingWindowDays: reportingWindowDays,
        idempotencyKey: idempotencyKey
      )
    )
    return response.conversation
  }

  func copilotConversation(
    organizationId: UUID,
    conversationId: UUID,
    audience: SDCopilotAudience,
    offset: Int = 0,
    limit: Int = 40
  ) async throws -> SDCopilotConversationDetailResponse {
    try await invokePlayerDevelopmentCopilot(
      SDCopilotRequest(
        action: "get_conversation",
        organizationId: organizationId,
        audience: audience,
        conversationId: conversationId,
        limit: limit,
        offset: offset
      )
    )
  }

  func archiveCopilotConversation(
    organizationId: UUID,
    conversationId: UUID,
    audience: SDCopilotAudience
  ) async throws -> SDCopilotConversation {
    let response: SDCopilotConversationResponse = try await invokePlayerDevelopmentCopilot(
      SDCopilotRequest(
        action: "archive_conversation",
        organizationId: organizationId,
        audience: audience,
        conversationId: conversationId
      )
    )
    return response.conversation
  }

  func copilotMessage(
    organizationId: UUID,
    conversationId: UUID,
    messageId: UUID,
    audience: SDCopilotAudience
  ) async throws -> SDCopilotMessage {
    let response: SDCopilotMessageResponse = try await invokePlayerDevelopmentCopilot(
      SDCopilotRequest(
        action: "get_message",
        organizationId: organizationId,
        audience: audience,
        conversationId: conversationId,
        messageId: messageId,
        limit: 100,
        offset: 0
      )
    )
    return response.message
  }

  func askCopilot(
    organizationId: UUID,
    playerId: UUID,
    conversationId: UUID,
    audience: SDCopilotAudience,
    question: String,
    window: SDDevelopmentWindow,
    idempotencyKey: UUID,
    retry: Bool = false,
    pendingQuestionId: UUID? = nil,
    pendingResponseMode: SDCopilotPendingResponseMode? = nil
  ) async throws -> SDCopilotAskResponse {
    try await invokePlayerDevelopmentCopilot(
      SDCopilotRequest(
        action: retry ? "retry_message" : "ask",
        organizationId: organizationId,
        audience: audience,
        playerId: playerId,
        conversationId: conversationId,
        question: question,
        windowStart: window.start,
        windowEnd: window.end,
        idempotencyKey: idempotencyKey,
        pendingQuestionId: pendingQuestionId,
        pendingResponseMode: pendingResponseMode
      ),
      canonicalPayloadKey: .answer
    )
  }

  func submitCopilotFeedback(
    organizationId: UUID,
    conversationId: UUID,
    messageId: UUID,
    audience: SDCopilotAudience,
    type: SDCopilotFeedbackType,
    note: String?
  ) async throws {
    let _: SDCopilotFeedbackResponse = try await invokePlayerDevelopmentCopilot(
      SDCopilotRequest(
        action: "submit_feedback",
        organizationId: organizationId,
        audience: audience,
        conversationId: conversationId,
        messageId: messageId,
        feedbackType: type,
        note: note
      )
    )
  }

  func copilotSuggestedQuestions(
    organizationId: UUID,
    playerId: UUID,
    audience: SDCopilotAudience
  ) async throws -> SDCopilotSuggestedQuestionsResponse {
    try await invokePlayerDevelopmentCopilot(
      SDCopilotRequest(
        action: "suggested_questions",
        organizationId: organizationId,
        audience: audience,
        playerId: playerId
      )
    )
  }

  func playerDevelopmentWorkspace(
    organizationId: UUID,
    playerId: UUID
  ) async throws -> SDPlayerDevelopmentWorkspaceResponse {
    try await invokePlayerDevelopmentCopilot(
      SDCopilotRequest(
        action: "get_player_workspace",
        organizationId: organizationId,
        audience: .player,
        playerId: playerId
      )
    )
  }

  func listParentUpdateDrafts(
    organizationId: UUID,
    playerId: UUID
  ) async throws -> [SDParentUpdateDraft] {
    let response: SDParentDraftsResponse = try await invokePlayerDevelopmentCopilot(
      SDCopilotRequest(
        action: "list_parent_drafts",
        organizationId: organizationId,
        playerId: playerId
      )
    )
    return response.drafts
  }

  func createParentUpdateDraft(
    organizationId: UUID,
    playerId: UUID,
    conversationId: UUID?,
    sourceMessageId: UUID?,
    window: SDDevelopmentWindow,
    idempotencyKey: UUID
  ) async throws -> SDParentUpdateDraft {
    let response: SDParentDraftResponse = try await invokePlayerDevelopmentCopilot(
      SDCopilotRequest(
        action: "create_parent_draft",
        organizationId: organizationId,
        playerId: playerId,
        conversationId: conversationId,
        sourceMessageId: sourceMessageId,
        windowStart: window.start,
        windowEnd: window.end,
        idempotencyKey: idempotencyKey
      )
    )
    return response.draft
  }

  func parentUpdateDraft(
    organizationId: UUID,
    draftId: UUID
  ) async throws -> SDParentDraftDetailResponse {
    try await invokePlayerDevelopmentCopilot(
      SDCopilotRequest(
        action: "get_parent_draft",
        organizationId: organizationId,
        draftId: draftId
      )
    )
  }

  func updateParentUpdateDraft(
    organizationId: UUID,
    draftId: UUID,
    content: SDParentUpdateContent?,
    markReviewed: Bool,
    note: String?
  ) async throws -> SDParentUpdateDraft {
    let response: SDParentDraftResponse = try await invokePlayerDevelopmentCopilot(
      SDCopilotRequest(
        action: "update_parent_draft",
        organizationId: organizationId,
        draftId: draftId,
        note: note,
        content: content,
        markReviewed: markReviewed
      )
    )
    return response.draft
  }

  func transitionParentUpdateDraft(
    organizationId: UUID,
    draftId: UUID,
    action: String,
    note: String?
  ) async throws -> SDParentUpdateDraft {
    let response: SDParentDraftResponse = try await invokePlayerDevelopmentCopilot(
      SDCopilotRequest(
        action: action,
        organizationId: organizationId,
        draftId: draftId,
        note: note
      )
    )
    return response.draft
  }

  func copilotUsage(
    organizationId: UUID,
    audience: SDCopilotAudience
  ) async throws -> SDCopilotUsage {
    let response: SDCopilotUsageResponse = try await invokePlayerDevelopmentCopilot(
      SDCopilotRequest(action: "get_usage", organizationId: organizationId, audience: audience)
    )
    return response.usage
  }

  // MARK: - In-app notification center

  private func invokeNotificationCenter<Request: Encodable, Response: Decodable>(
    _ request: Request
  ) async throws -> Response {
    do {
      return try await invokeAuthenticatedFunction("notification-center", body: request)
    } catch let error as FunctionsError {
      switch error {
      case .httpError(let statusCode, let data):
        throw SDEdgeFunctionHTTPError.decode(statusCode: statusCode, data: data)
      case .relayError:
        throw error
      }
    }
  }

  func listNotifications(
    organizationId: UUID?,
    unreadOnly: Bool,
    limit: Int = 20,
    offset: Int = 0
  ) async throws -> NotificationListResponse {
    try await invokeNotificationCenter(NotificationListRequest(
      organizationId: organizationId,
      unreadOnly: unreadOnly,
      limit: limit,
      offset: offset
    ))
  }

  func unreadNotificationCount(
    organizationId: UUID? = nil
  ) async throws -> NotificationUnreadCountResponse {
    try await invokeNotificationCenter(NotificationUnreadCountRequest(
      organizationId: organizationId
    ))
  }

  func markNotificationRead(
    notificationId: UUID
  ) async throws -> AppNotification {
    let response: NotificationSingleResponse = try await invokeNotificationCenter(
      NotificationMarkReadRequest(notificationId: notificationId)
    )
    return response.notification
  }

  func getNotification(notificationId: UUID) async throws -> AppNotification {
    let response: NotificationSingleResponse = try await invokeNotificationCenter(
      NotificationGetRequest(notificationId: notificationId)
    )
    return response.notification
  }

  func registerPushDevice(_ request: PushDeviceRegisterRequest) async throws -> PushDevice {
    let response: PushDeviceResponse = try await invokeAuthenticatedFunction(
      "push-device-registration", body: request
    )
    return response.device
  }

  func unregisterPushDevice(_ request: PushDeviceUnregisterRequest) async throws {
    let _: PushDeviceUnregisterResponse = try await invokeAuthenticatedFunction(
      "push-device-registration", body: request
    )
  }

  func markAllNotificationsRead(
    organizationId: UUID? = nil
  ) async throws -> NotificationMarkAllResponse {
    try await invokeNotificationCenter(NotificationMarkAllReadRequest(
      organizationId: organizationId
    ))
  }

  func createOrganizationAnnouncement(
    organizationId: UUID,
    draft: AnnouncementDraft,
    supportMode: Bool,
    idempotencyKey: UUID
  ) async throws -> OrganizationAnnouncementResponse {
    if !supportMode {
      struct AnnouncementPayload: Encodable {
        let title: String
        let body: String
        let audience_type: String
        let audience_filter: [String: String]
        let priority = "normal"
        let visibility = "audience"
        let acknowledgment_required = false
      }
      struct Request: Encodable {
        let action = "publish_announcement"
        let organization_id: String
        let request_id: String
        let announcement: AnnouncementPayload
      }
      struct Published: Decodable { let id: UUID }
      struct Result: Decodable {
        let announcement: Published
        let recipient_count: Int?
        let created_notifications: Int?
        let replayed: Bool?
      }
      struct Response: Decodable { let result: Result }
      let audienceType = switch draft.audience {
      case .all: "organization"
      case .players: "players"
      case .parents: "parents"
      case .coaches, .staff: "team_staff"
      }
      let response: Response = try await invokeAuthenticatedFunction(
        "communication",
        body: Request(
          organization_id: organizationId.uuidString.lowercased(),
          request_id: idempotencyKey.uuidString.lowercased(),
          announcement: AnnouncementPayload(
            title: draft.cleanedTitle,
            body: draft.cleanedBody,
            audience_type: audienceType,
            audience_filter: [:]
          )
        )
      )
      return OrganizationAnnouncementResponse(
        announcementId: response.result.announcement.id,
        createdCount: response.result.created_notifications ?? 0,
        recipientCount: response.result.recipient_count ?? 0,
        reused: response.result.replayed ?? false,
        authorizationSource: .organizationMembership
      )
    }
    return try await invokeNotificationCenter(OrganizationAnnouncementRequest(
      organizationId: organizationId,
      draft: draft,
      supportMode: supportMode,
      idempotencyKey: idempotencyKey
    ))
  }

  // MARK: - Organization operations (Phase 12F-12I)

  private struct OrganizationOperationsRequest: Encodable {
    let action: String
    let organization_id: String
    let dry_run: Bool?
    let limit: Int?
    let filters: [String: String]?

    init(
      action: String,
      organizationId: UUID,
      dryRun: Bool? = nil,
      limit: Int? = nil,
      filters: [String: String]? = nil
    ) {
      self.action = action
      organization_id = organizationId.uuidString.lowercased()
      dry_run = dryRun
      self.limit = limit
      self.filters = filters
    }
  }

  func communicationAnnouncements(
    organizationId: UUID
  ) async throws -> SDCommunicationAnnouncementsResponse {
    try await invokeAuthenticatedFunction(
      "communication",
      body: OrganizationOperationsRequest(action: "announcements", organizationId: organizationId)
    )
  }

  func communicationDeliveryStatus(
    organizationId: UUID
  ) async throws -> SDNotificationDeliveryStatusResponse {
    try await invokeAuthenticatedFunction(
      "communication",
      body: OrganizationOperationsRequest(action: "delivery_status", organizationId: organizationId)
    )
  }

  func setNotificationPreference(
    organizationId: UUID,
    category: String,
    inAppEnabled: Bool,
    pushEnabled: Bool,
    quietHoursStart: String?,
    quietHoursEnd: String?,
    timezone: String,
    expectedVersion: Int?
  ) async throws -> SDNotificationPreference {
    struct Preference: Encodable {
      let in_app_enabled: Bool
      let push_enabled: Bool
      let email_ready_enabled = false
      let sms_ready_enabled = false
      let quiet_hours_start: String?
      let quiet_hours_end: String?
      let timezone: String
    }
    struct Request: Encodable {
      let action = "set_preference"
      let organization_id: String
      let category: String
      let preference: Preference
      let expected_version: Int?
    }
    let response: SDNotificationPreferenceResponse = try await invokeAuthenticatedFunction(
      "communication",
      body: Request(
        organization_id: organizationId.uuidString.lowercased(),
        category: category,
        preference: Preference(
          in_app_enabled: inAppEnabled,
          push_enabled: pushEnabled,
          quiet_hours_start: quietHoursStart,
          quiet_hours_end: quietHoursEnd,
          timezone: timezone
        ),
        expected_version: expectedVersion
      )
    )
    return response.preference
  }

  func notificationPreferences(
    organizationId: UUID
  ) async throws -> [SDNotificationPreference] {
    let response: SDNotificationPreferencesResponse = try await invokeAuthenticatedFunction(
      "communication",
      body: OrganizationOperationsRequest(action: "preferences", organizationId: organizationId)
    )
    return response.preferences
  }

  func dryRunOperationalNotificationIntents(
    organizationId: UUID,
    limit: Int = 25
  ) async throws {
    struct Response: Decodable { let dry_run: Bool }
    let _: Response = try await invokeAuthenticatedFunction(
      "communication",
      body: OrganizationOperationsRequest(
        action: "process_event_intents",
        organizationId: organizationId,
        dryRun: true,
        limit: limit
      )
    )
  }

  func registrationOfferings(
    organizationId: UUID
  ) async throws -> SDRegistrationOfferingsResponse {
    try await invokeAuthenticatedFunction(
      "registration",
      body: OrganizationOperationsRequest(action: "offerings", organizationId: organizationId)
    )
  }

  func registrationApplications(
    organizationId: UUID
  ) async throws -> SDRegistrationApplicationsResponse {
    try await invokeAuthenticatedFunction(
      "registration",
      body: OrganizationOperationsRequest(action: "applications", organizationId: organizationId)
    )
  }

  func saveRegistrationDraft(
    organizationId: UUID,
    offering: SDRegistrationOffering,
    playerId: UUID?,
    jerseyNumber: String,
    positionPreference: String
  ) async throws -> SDRegistrationApplication {
    struct Application: Encodable {
      let season_id: String
      let offering_id: String
      let player_user_id: String?
      let jersey_number_request: String?
      let position_preference: String?
      let answers: [String: String] = [:]
      let sensitive_answers: [String: String] = [:]
      let consent_metadata: [String: String] = [:]
    }
    struct Request: Encodable {
      let action = "save_draft"
      let organization_id: String
      let application: Application
    }
    let response: SDRegistrationApplicationResponse = try await invokeAuthenticatedFunction(
      "registration",
      body: Request(
        organization_id: organizationId.uuidString.lowercased(),
        application: Application(
          season_id: offering.season_id.uuidString.lowercased(),
          offering_id: offering.id.uuidString.lowercased(),
          player_user_id: playerId?.uuidString.lowercased(),
          jersey_number_request: jerseyNumber.sdNilIfBlank,
          position_preference: positionPreference.sdNilIfBlank
        )
      )
    )
    return response.application
  }

  func submitRegistration(
    organizationId: UUID,
    application: SDRegistrationApplication,
    requestId: UUID = UUID()
  ) async throws -> SDRegistrationApplication {
    struct Request: Encodable {
      let action = "submit"
      let organization_id: String
      let application_id: String
      let expected_version: Int
      let request_id: String
    }
    let response: SDRegistrationCommandResponse = try await invokeAuthenticatedFunction(
      "registration",
      body: Request(
        organization_id: organizationId.uuidString.lowercased(),
        application_id: application.id.uuidString.lowercased(),
        expected_version: application.version,
        request_id: requestId.uuidString.lowercased()
      )
    )
    return response.result.application
  }

  func reviewRegistration(
    organizationId: UUID,
    application: SDRegistrationApplication,
    action: String,
    notes: String,
    requestId: UUID = UUID()
  ) async throws -> SDRegistrationApplication {
    struct Request: Encodable {
      let action = "review"
      let organization_id: String
      let application_id: String
      let review_action: String
      let notes: String
      let expected_version: Int
      let request_id: String
    }
    let response: SDRegistrationCommandResponse = try await invokeAuthenticatedFunction(
      "registration",
      body: Request(
        organization_id: organizationId.uuidString.lowercased(),
        application_id: application.id.uuidString.lowercased(),
        review_action: action,
        notes: notes,
        expected_version: application.version,
        request_id: requestId.uuidString.lowercased()
      )
    )
    return response.result.application
  }

  func organizationAnalytics(
    organizationId: UUID,
    filters: [String: String] = [:]
  ) async throws -> SDOrganizationAnalyticsResponse {
    try await invokeAuthenticatedFunction(
      "organization-analytics",
      body: OrganizationOperationsRequest(
        action: "dashboard",
        organizationId: organizationId,
        filters: filters
      )
    )
  }

  func organizationReport(
    organizationId: UUID,
    reportType: String,
    filters: [String: String] = [:]
  ) async throws -> SDOrganizationReportExport {
    struct Request: Encodable {
      let action = "export"
      let organization_id: String
      let report_type: String
      let filters: [String: String]
    }
    return try await invokeAuthenticatedFunction(
      "organization-analytics",
      body: Request(
        organization_id: organizationId.uuidString.lowercased(),
        report_type: reportType,
        filters: filters
      )
    )
  }

  // MARK: - Read-only organization finance dashboard

  private func invokeFinanceDashboard<Request: Encodable, Response: Decodable>(
    _ request: Request
  ) async throws -> Response {
    do {
      return try await invokeAuthenticatedFunction("finance-dashboard", body: request)
    } catch let error as FunctionsError {
      switch error {
      case .httpError(let statusCode, let data):
        throw SDEdgeFunctionHTTPError.decode(statusCode: statusCode, data: data)
      case .relayError:
        throw error
      }
    }
  }

  func financeOverview(
    orgId: UUID,
    range: FinanceDateRangeSelection,
    supportMode: Bool
  ) async throws -> FinanceOverviewResponse {
    try await invokeFinanceDashboard(FinanceDashboardRequest(
      action: "overview",
      organizationId: orgId,
      range: range,
      supportMode: supportMode
    ))
  }

  func financeRecentPayments(
    orgId: UUID,
    range: FinanceDateRangeSelection,
    supportMode: Bool
  ) async throws -> FinanceRecentPaymentsResponse {
    try await invokeFinanceDashboard(FinanceDashboardRequest(
      action: "recent_payments",
      organizationId: orgId,
      range: range,
      supportMode: supportMode
    ))
  }

  func financePaymentRequests(
    orgId: UUID,
    range: FinanceDateRangeSelection,
    filter: FinancePaymentRequestFilter,
    supportMode: Bool
  ) async throws -> FinancePaymentRequestsResponse {
    try await invokeFinanceDashboard(FinanceDashboardRequest(
      action: "payment_requests",
      organizationId: orgId,
      range: range,
      filter: filter,
      supportMode: supportMode
    ))
  }

  func financeExpenses(
    orgId: UUID,
    range: FinanceDateRangeSelection,
    supportMode: Bool
  ) async throws -> FinanceExpensesResponse {
    try await invokeFinanceDashboard(FinanceDashboardRequest(
      action: "expenses",
      organizationId: orgId,
      range: range,
      supportMode: supportMode
    ))
  }

  func createFinanceExpense(
    _ request: FinanceExpenseMutationRequest
  ) async throws -> FinanceExpenseMutationResponse {
    try await invokeFinanceDashboard(request)
  }

  func updateFinanceExpense(
    _ request: FinanceExpenseMutationRequest
  ) async throws -> FinanceExpenseMutationResponse {
    try await invokeFinanceDashboard(request)
  }

  func archiveFinanceExpense(
    _ request: FinanceExpenseMutationRequest
  ) async throws -> FinanceExpenseMutationResponse {
    try await invokeFinanceDashboard(request)
  }

  func financeRefunds(
    orgId: UUID,
    range: FinanceDateRangeSelection,
    supportMode: Bool
  ) async throws -> FinanceRefundsResponse {
    try await invokeFinanceDashboard(FinanceDashboardRequest(
      action: "refunds",
      organizationId: orgId,
      range: range,
      supportMode: supportMode
    ))
  }

  // MARK: - Payment-request Checkout (Stripe Payments Phase 1B-2)

  func createPaymentRequestCheckout(
    paymentRequestId: UUID
  ) async throws -> SDPaymentCheckoutResponse {
    do {
      return try await invokeAuthenticatedFunction(
        "create-payment-request-checkout",
        body: ["payment_request_id": paymentRequestId.uuidString]
      )
    } catch let error as FunctionsError {
      switch error {
      case .httpError(let statusCode, let data):
        throw SDEdgeFunctionHTTPError.decode(statusCode: statusCode, data: data)
      case .relayError:
        throw error
      }
    }
  }

  // MARK: - SD Program (iOS-native tables)

  func listMyCoachTemplates() async throws -> [SDProgramTemplate] {
    let session = try await client.auth.session
    let uid = session.user.id
    return try await client
      .from("sd_program_templates")
      .select()
      .eq("coach_id", value: uid.uuidString)
      .order("created_at", ascending: false)
      .execute()
      .value
  }

  func createProgramTemplate(
    name: String,
    kind: SDProgramKind = .strength,
    weeks: Int,
    liftWeekdays: [Int],
    orgId: UUID? = nil
  ) async throws -> SDProgramTemplate {
    let session = try await client.auth.session
    let uid = session.user.id
    struct Insert: Encodable {
      let org_id: UUID?
      let coach_id: UUID
      let name: String
      let program_kind: String
      let weeks: Int
      let lift_weekdays: [Int]
    }
    return try await client
      .from("sd_program_templates")
      .insert(
        Insert(
          org_id: orgId,
          coach_id: uid,
          name: name,
          program_kind: kind.rawValue,
          weeks: weeks,
          lift_weekdays: liftWeekdays
        )
      )
      .select()
      .single()
      .execute()
      .value
  }

  func upsertProgramDay(templateId: UUID, week: Int, dayIndex: Int, exercises: [SDExercise]) async throws -> SDProgramDay {
    struct Upsert: Encodable {
      let template_id: UUID
      let week: Int
      let day_index: Int
      let exercises: [SDExercise]
    }
    return try await client
      .from("sd_program_days")
      .upsert(Upsert(template_id: templateId, week: week, day_index: dayIndex, exercises: exercises),
              onConflict: "template_id,week,day_index")
      .select()
      .single()
      .execute()
      .value
  }

  func fetchProgramDays(templateId: UUID) async throws -> [SDProgramDay] {
    try await client
      .from("sd_program_days")
      .select()
      .eq("template_id", value: templateId.uuidString)
      .order("week", ascending: true)
      .order("day_index", ascending: true)
      .execute()
      .value
  }

  func duplicateProgramTemplate(_ template: SDProgramTemplate) async throws -> SDProgramTemplate {
    let duplicate = try await createProgramTemplate(
      name: "\(template.name) Copy",
      kind: template.kind,
      weeks: template.weeks,
      liftWeekdays: template.lift_weekdays,
      orgId: template.org_id
    )
    do {
      let sourceDays = try await fetchProgramDays(templateId: template.id)
      for day in sourceDays {
        let copiedExercises = day.exercises.map {
          SDExercise(id: UUID(), name: $0.name, sets: $0.sets, reps: $0.reps, unit: $0.unit, notes: $0.notes)
        }
        _ = try await upsertProgramDay(
          templateId: duplicate.id,
          week: day.week,
          dayIndex: day.day_index,
          exercises: copiedExercises
        )
      }
      return duplicate
    } catch {
      // Never leave a misleading, partially copied template behind.
      try? await deleteProgramTemplate(id: duplicate.id)
      throw error
    }
  }

  func deleteProgramTemplate(id: UUID) async throws {
    _ = try await client
      .from("sd_program_templates")
      .delete()
      .eq("id", value: id.uuidString)
      .execute()
  }

  func assignProgram(templateId: UUID, playerId: UUID, startDateISO: String, notes: String?, orgId: UUID? = nil) async throws -> SDProgramAssignment {
    let session = try await client.auth.session
    let coachId = session.user.id
    struct Insert: Encodable {
      let org_id: UUID?
      let player_id: UUID
      let coach_id: UUID
      let template_id: UUID
      let start_date: String
      let notes: String?
    }
    return try await client
      .from("sd_program_assignments")
      .insert(Insert(org_id: orgId, player_id: playerId, coach_id: coachId, template_id: templateId, start_date: startDateISO, notes: notes))
      .select()
      .single()
      .execute()
      .value
  }

  func endAssignment(assignmentId: UUID) async throws {
    struct Patch: Encodable { let ended_at: Date }
    _ = try await client
      .from("sd_program_assignments")
      .update(Patch(ended_at: Date()))
      .eq("id", value: assignmentId.uuidString)
      .execute()
  }

  func fetchActiveAssignment(playerId: UUID) async throws -> SDProgramAssignment? {
    try await fetchActiveAssignments(playerId: playerId).first
  }

  func fetchActiveAssignments(playerId: UUID) async throws -> [SDProgramAssignment] {
    try await client
      .from("sd_program_assignments")
      .select()
      .eq("player_id", value: playerId.uuidString)
      .is("ended_at", value: nil)
      .order("created_at", ascending: false)
      .execute()
      .value
  }

  func fetchTemplate(id: UUID) async throws -> SDProgramTemplate {
    try await client
      .from("sd_program_templates")
      .select()
      .eq("id", value: id.uuidString)
      .single()
      .execute()
      .value
  }

  // MARK: - Coach exercise library (autocomplete)

  private func normalizeExerciseName(_ name: String) -> (name: String, norm: String)? {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty { return nil }
    let norm = trimmed.lowercased()
    return (trimmed, norm)
  }

  func listExerciseLibrary(forceRefresh: Bool = false) async throws -> [SDExerciseLibraryItem] {
    if !forceRefresh, let cached = exerciseLibraryCache { return cached }
    let session = try await client.auth.session
    let uid = session.user.id
    let rows: [SDExerciseLibraryItem] = try await client
      .from("sd_exercise_library")
      .select()
      .eq("coach_id", value: uid.uuidString)
      .order("last_used_at", ascending: false)
      .limit(500)
      .execute()
      .value
    exerciseLibraryCache = rows
    exerciseLibraryCacheLoadedAt = Date()
    return rows
  }

  /// Upserts a set of exercise names into the coach's exercise library, incrementing usage_count.
  func upsertExerciseLibrary(names: [String]) async throws {
    let session = try await client.auth.session
    let uid = session.user.id

    let cleaned = names.compactMap(normalizeExerciseName)
    if cleaned.isEmpty { return }

    // Load cache to allow usage_count increment.
    let existing = try await listExerciseLibrary(forceRefresh: false)
    var byNorm: [String: SDExerciseLibraryItem] = [:]
    for item in existing { byNorm[item.name_norm] = item }

    struct Upsert: Encodable {
      let coach_id: UUID
      let name: String
      let name_norm: String
      let usage_count: Int
      let last_used_at: Date
    }

    let now = Date()
    let upserts: [Upsert] = cleaned.map { c in
      let prior = byNorm[c.norm]?.usage_count ?? 0
      return Upsert(coach_id: uid, name: c.name, name_norm: c.norm, usage_count: prior + 1, last_used_at: now)
    }

    _ = try await client
      .from("sd_exercise_library")
      .upsert(upserts, onConflict: "coach_id,name_norm")
      .execute()

    // Refresh cache (best-effort).
    exerciseLibraryCache = nil
    _ = try? await listExerciseLibrary(forceRefresh: true)
  }

  // MARK: - Daily log + Strength

  func upsertDailyLog(playerId: UUID, dateISO: String, payload: [String: AnyEncodable], orgId: UUID? = nil) async throws -> SDDailyLog {
    struct Upsert: Encodable {
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
    }
    func get<T>(_ key: String) -> T? { payload[key]?.value as? T }
    let row = Upsert(
      org_id: orgId,
      player_id: playerId,
      log_date: dateISO,
      comments: get("comments"),
      feel: get("feel"),
      got_video: get("got_video"),
      ate_breakfast: get("ate_breakfast"),
      hit_daily_goals: get("hit_daily_goals"),
      stuck_to_process: get("stuck_to_process"),
      fell_short: get("fell_short"),
      excelled: get("excelled")
    )
    return try await client
      .from("sd_daily_logs")
      .upsert(row, onConflict: orgId == nil ? "player_id,log_date" : "org_id,player_id,log_date")
      .select()
      .single()
      .execute()
      .value
  }

  func fetchDailyLog(playerId: UUID, dateISO: String) async throws -> SDDailyLog? {
    let rows: [SDDailyLog] = try await client
      .from("sd_daily_logs")
      .select()
      .eq("player_id", value: playerId.uuidString)
      .eq("log_date", value: dateISO)
      .limit(1)
      .execute()
      .value
    return rows.first
  }

  func listDailyLogs(playerId: UUID, limit: Int = 60) async throws -> [SDDailyLog] {
    try await client
      .from("sd_daily_logs")
      .select()
      .eq("player_id", value: playerId.uuidString)
      .order("log_date", ascending: false)
      .limit(limit)
      .execute()
      .value
  }

  func upsertStrengthLog(playerId: UUID, dateISO: String, assignmentId: UUID?, templateId: UUID?, week: Int?, dayIndex: Int?, exerciseName: String, noWeight: Bool, setWeights: [String]?, setsCompleted: Int?, notes: String?, orgId: UUID? = nil) async throws -> SDStrengthLog {
    struct Upsert: Encodable {
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
    }
    // Uniqueness is not enforced at DB level for logs; we emulate upsert by deleting existing row for that exercise/date.
    var deleteQuery = client
      .from("sd_strength_logs")
      .delete()
      .eq("player_id", value: playerId.uuidString)
      .eq("log_date", value: dateISO)
      .eq("exercise_name", value: exerciseName)
    if let orgId {
      deleteQuery = deleteQuery.eq("org_id", value: orgId.uuidString)
    }
    _ = try await deleteQuery
      .execute()
    return try await client
      .from("sd_strength_logs")
      .insert(Upsert(org_id: orgId, player_id: playerId, log_date: dateISO, assignment_id: assignmentId, template_id: templateId, week: week, day_index: dayIndex, exercise_name: exerciseName, no_weight: noWeight, set_weights_json: setWeights, sets_completed: setsCompleted, notes: notes))
      .select()
      .single()
      .execute()
      .value
  }

  func fetchStrengthLogs(playerId: UUID, dateISO: String) async throws -> [SDStrengthLog] {
    try await client
      .from("sd_strength_logs")
      .select()
      .eq("player_id", value: playerId.uuidString)
      .eq("log_date", value: dateISO)
      .order("created_at", ascending: true)
      .execute()
      .value
  }

  // MARK: - Testing

  func upsertTestingEntry(_ entry: SDTestingEntryCreate) async throws -> SDTestingEntry {
    return try await client
      .from("sd_testing_entries")
      .upsert(entry, onConflict: entry.org_id == nil ? "player_id,entry_date" : "org_id,player_id,entry_date")
      .select()
      .single()
      .execute()
      .value
  }

  func listTestingEntries(playerId: UUID) async throws -> [SDTestingEntry] {
    try await client
      .from("sd_testing_entries")
      .select()
      .eq("player_id", value: playerId.uuidString)
      .order("entry_date", ascending: false)
      .execute()
      .value
  }

  // MARK: - BP

  func upsertBPSession(playerId: UUID, dateISO: String, source: String, repsType: String, orgId: UUID? = nil) async throws -> SDBPSession {
    struct Upsert: Encodable {
      let org_id: UUID?
      let player_id: UUID
      let session_date: String
      let source: String
      let reps_type: String
    }
    return try await client
      .from("sd_bp_sessions")
      .upsert(Upsert(org_id: orgId, player_id: playerId, session_date: dateISO, source: source, reps_type: repsType),
              onConflict: orgId == nil ? "player_id,session_date,source,reps_type" : "org_id,player_id,session_date,source,reps_type")
      .select()
      .single()
      .execute()
      .value
  }

  func coachReplaceBPEvents(playerId: UUID, dateISO: String, source: String, repsType: String, events: [SDBPEventCreate]) async throws -> UUID {
    // NOTE: Coaches cannot write to sd_bp_* via RLS; this goes through an Edge Function using service_role.
    struct Payload: Encodable {
      let player_id: String
      let session_date: String
      let source: String
      let reps_type: String
      let events: [CoachEvent]
    }
    struct CoachEvent: Encodable {
      let pitch_num: Int?
      let exit_velo: Double?
      let distance: Double?
      let launch_angle: Double?
      let strike_x: Double?
      let strike_z: Double?
      let raw: [String: String]
    }
    struct Resp: Decodable {
      let session_id: String
      let event_count: Int
    }

    let body = Payload(
      player_id: playerId.uuidString,
      session_date: dateISO,
      source: source,
      reps_type: repsType,
      events: events.map {
        CoachEvent(
          pitch_num: $0.pitch_num,
          exit_velo: $0.exit_velo,
          distance: $0.distance,
          launch_angle: $0.launch_angle,
          strike_x: $0.strike_x,
          strike_z: $0.strike_z,
          raw: $0.raw
        )
      }
    )

    let resp: Resp = try await client.functions.invoke(
      "coach_import_bp",
      options: FunctionInvokeOptions(body: body)
    )
    guard let uuid = UUID(uuidString: resp.session_id) else {
      throw NSError(domain: "SupabaseService", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid session id."])
    }
    return uuid
  }

  func replaceBPEvents(sessionId: UUID, events: [SDBPEventCreate]) async throws {
    _ = try await client
      .from("sd_bp_events")
      .delete()
      .eq("session_id", value: sessionId.uuidString)
      .execute()
    if events.isEmpty { return }
    _ = try await client
      .from("sd_bp_events")
      .insert(events)
      .execute()
  }

  func fetchBPEvents(sessionId: UUID) async throws -> [SDBPEvent] {
    try await client
      .from("sd_bp_events")
      .select()
      .eq("session_id", value: sessionId.uuidString)
      .order("pitch_num", ascending: true)
      .execute()
      .value
  }

  func listBPSessions(playerId: UUID, limit: Int = 60) async throws -> [SDBPSession] {
    try await client
      .from("sd_bp_sessions")
      .select()
      .eq("player_id", value: playerId.uuidString)
      .order("session_date", ascending: false)
      .limit(limit)
      .execute()
      .value
  }

  // MARK: - Onboarding

  func fetchOnboarding(playerId: UUID) async throws -> SDPlayerOnboarding? {
    let rows: [SDPlayerOnboarding] = try await client
      .from("sd_player_onboarding")
      .select()
      .eq("player_id", value: playerId.uuidString)
      .limit(1)
      .execute()
      .value
    return rows.first
  }

  func upsertOnboarding(playerId: UUID,
                        improveFocus: String,
                        improvePlan: String?,
                        dailyGoals: String?,
                        completed: Bool,
                        orgId: UUID? = nil) async throws -> SDPlayerOnboarding {
    struct Upsert: Encodable {
      let org_id: UUID?
      let player_id: UUID
      let improve_focus: String
      let improve_plan: String?
      let daily_goals: String?
      let completed_at: String?
    }
    let completedAt: String? = completed ? ISO8601DateFormatter().string(from: Date()) : nil
    return try await client
      .from("sd_player_onboarding")
      .upsert(
        Upsert(org_id: orgId,
               player_id: playerId,
               improve_focus: improveFocus,
               improve_plan: improvePlan,
               daily_goals: dailyGoals,
               completed_at: completedAt),
        onConflict: "player_id"
      )
      .select()
      .single()
      .execute()
      .value
  }

  func coachResetOnboarding(playerId: UUID) async throws {
    _ = try await client
      .rpc("sd_reset_onboarding", params: ["target_player_id": playerId.uuidString])
      .execute()
  }

  // MARK: - Organization setup (Phase 12Z)

  private struct OrganizationSetupRequest: Encodable {
    let action: String
    let organization_id: String
    let request_id: String?
    let expected_version: Int?
    let step: String?
    let draft_key: String?
    let setup_test_run_id: String?
    let basics: [String: SDJSONValue]?
    let season: [String: SDJSONValue]?
    let team: [String: SDJSONValue]?
    let teams: [String: SDJSONValue]?
    let draft: [String: SDJSONValue]?
    let registration: [String: SDJSONValue]?
    let facility: [String: SDJSONValue]?
    let communication: [String: SDJSONValue]?
    let event: [String: SDJSONValue]?
  }

  private func organizationSetupRequest(
    action: String,
    organizationId: UUID,
    requestId: UUID? = nil,
    expectedVersion: Int? = nil,
    step: SDOrganizationSetupStep? = nil,
    draftKey: String? = nil,
    setupTestRunId: UUID? = nil,
    field: String? = nil,
    payload: [String: SDJSONValue]? = nil,
    mutating: Bool = true
  ) -> OrganizationSetupRequest {
    OrganizationSetupRequest(
      action: action,
      organization_id: organizationId.uuidString.lowercased(),
      request_id: mutating ? (requestId ?? UUID()).uuidString.lowercased() : nil,
      expected_version: expectedVersion,
      step: step?.rawValue,
      draft_key: draftKey,
      setup_test_run_id: setupTestRunId?.uuidString.lowercased(),
      basics: field == "basics" ? payload : nil,
      season: field == "season" ? payload : nil,
      team: field == "team" ? payload : nil,
      teams: field == "teams" ? payload : nil,
      draft: field == "draft" ? payload : nil,
      registration: field == "registration" ? payload : nil,
      facility: field == "facility" ? payload : nil,
      communication: field == "communication" ? payload : nil,
      event: field == "event" ? payload : nil
    )
  }

  func organizationSetup(organizationId: UUID) async throws -> SDOrganizationSetupSnapshot {
    try await invokeAuthenticatedFunction(
      "organization-setup",
      body: organizationSetupRequest(
        action: "get",
        organizationId: organizationId,
        mutating: false
      )
    )
  }

  func mutateOrganizationSetup(
    action: String,
    organizationId: UUID,
    requestId: UUID,
    expectedVersion: Int?,
    step: SDOrganizationSetupStep? = nil,
    draftKey: String? = nil,
    setupTestRunId: UUID? = nil,
    field: String? = nil,
    payload: [String: SDJSONValue]? = nil
  ) async throws -> SDOrganizationSetupSnapshot {
    let response: SDOrganizationSetupMutationResponse = try await invokeAuthenticatedFunction(
      "organization-setup",
      body: organizationSetupRequest(
        action: action,
        organizationId: organizationId,
        requestId: requestId,
        expectedVersion: expectedVersion,
        step: step,
        draftKey: draftKey,
        setupTestRunId: setupTestRunId,
        field: field,
        payload: payload
      )
    )
    return response.setup
  }

  func previewOrganizationSetupTestReset(
    organizationId: UUID,
    setupTestRunId: UUID
  ) async throws -> SDOrganizationSetupResetPreview {
    struct Response: Decodable { let preview: SDOrganizationSetupResetPreview }
    let response: Response = try await invokeAuthenticatedFunction(
      "organization-setup",
      body: organizationSetupRequest(
        action: "preview_test_data_reset",
        organizationId: organizationId,
        setupTestRunId: setupTestRunId,
        mutating: true
      )
    )
    return response.preview
  }

  private struct OrganizationInvitationRequest: Encodable, Sendable {
    let action: String
    var organization_id: UUID? = nil
    var invitation_context: SDOrganizationInvitationContext? = nil
    var link_id: UUID? = nil
    var token: String? = nil
    var intended_team_id: UUID? = nil
    var intended_responsibilities: [String]? = nil
    var expires_in_days: Int? = nil
  }

  func organizationInvitationLinks(organizationId: UUID) async throws -> [SDOrganizationInvitationLink] {
    struct Response: Decodable, Sendable { let links: [SDOrganizationInvitationLink] }
    let response: Response = try await invokeAuthenticatedFunction(
      "organization-invitations",
      body: OrganizationInvitationRequest(action: "list", organization_id: organizationId)
    )
    return response.links
  }

  func generateOrganizationInvitationLink(
    organizationId: UUID,
    context: SDOrganizationInvitationContext,
    rotating: Bool,
    teamId: UUID? = nil,
    responsibilities: [SDStaffResponsibility] = []
  ) async throws -> SDOrganizationInvitationLinkMutation {
    try await invokeAuthenticatedFunction(
      "organization-invitations",
      body: OrganizationInvitationRequest(
        action: rotating ? "rotate" : "generate",
        organization_id: organizationId,
        invitation_context: context,
        intended_team_id: teamId,
        intended_responsibilities: responsibilities.map(\.rawValue),
        expires_in_days: 30
      )
    )
  }

  func revokeOrganizationInvitationLink(
    organizationId: UUID,
    linkId: UUID
  ) async throws -> SDOrganizationInvitationLinkMutation {
    try await invokeAuthenticatedFunction(
      "organization-invitations",
      body: OrganizationInvitationRequest(action: "revoke", organization_id: organizationId, link_id: linkId)
    )
  }

  func validateOrganizationInvitation(token: String) async throws -> SDOrganizationInvitationValidation {
    struct Response: Decodable, Sendable { let invitation: SDOrganizationInvitationValidation }
    do {
      let response: Response = try await client.functions.invoke(
        "organization-invitations",
        options: FunctionInvokeOptions(body: OrganizationInvitationRequest(action: "validate", token: token))
      )
      return response.invitation
    } catch let error as FunctionsError {
      switch error {
      case .httpError(let statusCode, let data): throw SDEdgeFunctionHTTPError.decode(statusCode: statusCode, data: data)
      case .relayError: throw SDServiceError(category: .serviceUnavailable, functionName: "organization-invitations", statusCode: nil)
      }
    }
  }

  func acceptOrganizationInvitation(token: String) async throws -> SDOrganizationInvitationValidation {
    struct Response: Decodable, Sendable { let invitation: SDOrganizationInvitationValidation }
    let response: Response = try await invokeAuthenticatedFunction(
      "organization-invitations",
      body: OrganizationInvitationRequest(action: "accept", token: token)
    )
    return response.invitation
  }

  func signOut() async throws {
    try await client.auth.signOut()
  }
}

// MARK: - Encodable helpers

struct AnyEncodable: Encodable {
  let value: Any
  init(_ value: Any) { self.value = value }
  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    switch value {
    case let v as String: try container.encode(v)
    case let v as Int: try container.encode(v)
    case let v as Double: try container.encode(v)
    case let v as Bool: try container.encode(v)
    case Optional<Any>.none: try container.encodeNil()
    default:
      let context = EncodingError.Context(codingPath: encoder.codingPath, debugDescription: "Unsupported type")
      throw EncodingError.invalidValue(value, context)
    }
  }
}

struct SDTestingEntryCreate: Encodable {
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
}

struct SDBPEventCreate: Encodable {
  let session_id: UUID
  let pitch_num: Int?
  let exit_velo: Double?
  let distance: Double?
  let launch_angle: Double?
  let strike_x: Double?
  let strike_z: Double?
  let raw: [String: String]
}

extension SupabaseService: PlayerDevelopmentAIClient, PlayerDevelopmentImportClient, PlayerDevelopmentCopilotClient {}
