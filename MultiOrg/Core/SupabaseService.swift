import Foundation
import Supabase

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
    let channelId: UUID
    let senderId: UUID?
    let body: String
    let createdAt: Date
  }

  func startChatMessageListener(
    onInsert: @escaping @Sendable (ChatMessageInsert) -> Void
  ) async throws {
    if chatMessagesChannel != nil { return }

    let channel = client.channel("sd_chat_messages")
    chatMessagesChannel = channel

    let inserts = channel.postgresChange(InsertAction.self, schema: "public", table: "sd_chat_messages")

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
          let channelId = parseUUID(rec["channel_id"]),
          let createdAt = parseDate(rec["created_at"]),
          let body = rec["body"]?.stringValue
        else { continue }

        let senderId = parseUUID(rec["sender_id"])
        onInsert(ChatMessageInsert(messageId: messageId, channelId: channelId, senderId: senderId, body: body, createdAt: createdAt))
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
      .select("org_id,user_id,role,status,created_at,created_by")
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
          "action": "list_members",
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
      "action": "create_user",
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
          "action": "update_member",
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
          "action": "set_username",
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
      body: ["action": "list_teams", "org_id": orgId.uuidString]
    )
  }

  func adminCreateTeam(orgId: UUID, name: String, colorHex: String?, description: String?) async throws {
    let _: OrgAdminOKResponse = try await invokeAuthenticatedFunction("org_admin", body: [
      "action": "create_team", "org_id": orgId.uuidString, "name": name,
      "color_hex": colorHex ?? "", "description": description ?? ""
    ])
  }

  func adminAssignTeam(orgId: UUID, teamId: UUID?, memberId: UUID) async throws {
    if let teamId {
      let _: OrgAdminOKResponse = try await invokeAuthenticatedFunction("org_admin", body: [
        "action": "assign_team_member", "org_id": orgId.uuidString,
        "team_id": teamId.uuidString, "member_id": memberId.uuidString
      ])
    } else {
      let _: OrgAdminOKResponse = try await invokeAuthenticatedFunction("org_admin", body: [
        "action": "remove_team_member", "org_id": orgId.uuidString, "member_id": memberId.uuidString
      ])
    }
  }

  func adminFetchPlayerAccess(orgId: UUID, playerId: UUID) async throws -> SDAdminPlayerAccess {
    struct Response: Decodable { let entitlement: SDAdminPlayerAccess }
    let response: Response = try await invokeAuthenticatedFunction("org_admin", body: [
      "action": "get_player_access",
      "org_id": orgId.uuidString,
      "player_id": playerId.uuidString,
    ])
    return response.entitlement
  }

  func adminSetPlayerAccess(orgId: UUID, playerId: UUID, isActive: Bool) async throws -> SDAdminPlayerAccess {
    struct Response: Decodable { let entitlement: SDAdminPlayerAccess }
    let response: Response = try await invokeAuthenticatedFunction("org_admin", body: [
      "action": "set_player_access",
      "org_id": orgId.uuidString,
      "player_id": playerId.uuidString,
      "is_active": isActive ? "true" : "false",
    ])
    return response.entitlement
  }

  /// Edge Functions do not automatically refresh the bearer token in every
  /// long-running desktop session. Refresh first, then explicitly install the
  /// current access token so authorized team/admin calls cannot drift into 401.
  private func invokeAuthenticatedFunction<Response: Decodable>(
    _ name: String,
    body: [String: String]
  ) async throws -> Response {
    let session = try await client.auth.session
    client.functions.setAuth(token: session.accessToken)
    return try await client.functions.invoke(
      name,
      options: FunctionInvokeOptions(body: body)
    )
  }

  private struct OrgBillingURLResponse: Decodable {
    let url: String
  }

  private enum OrgBillingURLError: LocalizedError {
    case invalidHostedURL

    var errorDescription: String? {
      "Home Plate returned an invalid billing link. Please try again."
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
    var body: [String: String] = [
      "action": "create_organization",
      "name": name,
      "slug": slug,
      "plan": plan,
    ]
    if let billingEmail { body["billing_email"] = billingEmail }
    if let maxMembers { body["max_members"] = String(maxMembers) }
    let response: Response = try await invokeAuthenticatedFunction("platform_admin", body: body)
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

  func listChatChannels() async throws -> [SDChatChannel] {
    // RLS determines what the caller can see (memberships + announcements).
    return try await client
      .from("sd_chat_channels")
      .select("id,org_id,channel_type,title,audience,created_by,is_archived,pinned_rank,created_at,updated_at")
      .eq("is_archived", value: false)
      .execute()
      .value
  }

  func listMyChatMemberships() async throws -> [SDChatMembership] {
    let session = try await client.auth.session
    let uid = session.user.id
    return try await client
      .from("sd_chat_memberships")
      .select("org_id,channel_id,user_id,member_role,joined_at,last_read_at,muted")
      .eq("user_id", value: uid.uuidString)
      .execute()
      .value
  }

  func listChatMemberships(channelIds: [UUID]) async throws -> [SDChatMembership] {
    guard !channelIds.isEmpty else { return [] }
    let idList = channelIds.map(\.uuidString).joined(separator: ",")
    return try await client
      .from("sd_chat_memberships")
      .select("org_id,channel_id,user_id,member_role,joined_at,last_read_at,muted")
      .filter("channel_id", operator: "in", value: "(\(idList))")
      .execute()
      .value
  }

  func listChatLastMessages(channelIds: [UUID]) async throws -> [SDChatLastMessageRow] {
    guard !channelIds.isEmpty else { return [] }
    let idList = channelIds.map(\.uuidString).joined(separator: ",")
    return try await client
      .from("sd_chat_channel_last_message")
      .select("channel_id,body_preview,message_created_at")
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

  func listChatMessages(channelId: UUID, before: Date?, limit: Int = 60) async throws -> [SDChatMessage] {
    var q = client
      .from("sd_chat_messages")
      .select("id,org_id,channel_id,sender_id,body,created_at,edited_at,deleted_at")
      .eq("channel_id", value: channelId.uuidString)
      .is("deleted_at", value: nil)

    if let before {
      let iso = ISO8601DateFormatter().string(from: before)
      q = q.filter("created_at", operator: "lt", value: iso)
    }

    return try await q
      .order("created_at", ascending: false)
      .limit(limit)
      .execute()
      .value
  }

  func sendChatMessage(channelId: UUID, body: String) async throws -> SDChatMessage {
    let session = try await client.auth.session
    let uid = session.user.id
    struct Insert: Encodable {
      let org_id: UUID?
      let channel_id: UUID
      let sender_id: UUID
      let body: String
    }
    let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty {
      throw NSError(domain: "chat", code: 2, userInfo: [NSLocalizedDescriptionKey: "Message is empty."])
    }
    return try await client
      .from("sd_chat_messages")
      .insert(Insert(org_id: nil, channel_id: channelId, sender_id: uid, body: trimmed))
      .select("id,org_id,channel_id,sender_id,body,created_at,edited_at,deleted_at")
      .single()
      .execute()
      .value
  }

  func upsertMyChatReadState(channelId: UUID, lastReadAt: Date) async throws {
    let session = try await client.auth.session
    let uid = session.user.id
    struct Upsert: Encodable {
      let channel_id: UUID
      let user_id: UUID
      let last_read_at: String
    }
    let iso = ISO8601DateFormatter().string(from: lastReadAt)
    _ = try await client
      .from("sd_chat_memberships")
      .upsert(Upsert(channel_id: channelId, user_id: uid, last_read_at: iso), onConflict: "channel_id,user_id")
      .execute()
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
    let access_may_be_active: Bool
  }

  private struct AppleSubscriptionVerificationErrorBody: Decodable {
    let error: String?
  }

  private struct AppleSubscriptionVerificationError: LocalizedError {
    let code: String
    var errorDescription: String? {
      "Apple purchase verification was rejected (\(code)). Retry verification, or contact support if it continues."
    }
  }

  func verifyApplePlayerSubscription(
    signedTransaction: String,
    context: PlayerSubscriptionContext
  ) async throws -> AppleSubscriptionVerificationResponse {
    do {
      return try await invokeAuthenticatedFunction(
        "verify-apple-player-subscription",
        body: [
          "signed_transaction_info": signedTransaction,
          "org_id": context.orgId.uuidString,
          "player_id": context.playerId.uuidString,
          "billing_user_id": context.billingUserId.uuidString,
          "app_account_token": context.appAccountToken.uuidString,
        ]
      )
    } catch let FunctionsError.httpError(_, data) {
      let response = try? JSONDecoder().decode(AppleSubscriptionVerificationErrorBody.self, from: data)
      let code = response?.error?.trimmingCharacters(in: .whitespacesAndNewlines)
      throw AppleSubscriptionVerificationError(code: code?.isEmpty == false ? code! : "apple_verification_failed")
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

  func listMyParentChildLinks() async throws -> [SDParentChildLink] {
    try await client
      .from("sd_parent_child_links")
      .select("parent_id,child_id,relationship,can_book,can_pay,created_at,created_by")
      .execute()
      .value
  }

  func listMyParentLinksAsChild() async throws -> [SDParentChildLink] {
    let session = try await client.auth.session
    let uid = session.user.id
    return try await client
      .from("sd_parent_child_links")
      .select("parent_id,child_id,relationship,can_book,can_pay,created_at,created_by")
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
      .select("parent_id,child_id,relationship,can_book,can_pay,created_at,created_by")
      .eq("child_id", value: childId.uuidString)
      .execute()
      .value
  }

  // MARK: - Payment requests (manual for now)

  func listMyPaymentRequests(childId: UUID) async throws -> [SDPaymentRequest] {
    try await client
      .from("sd_payment_requests")
      .select("id,payer_id,child_id,status,plan_name,amount_cents,currency,notes,created_at,updated_at")
      .eq("child_id", value: childId.uuidString)
      .order("created_at", ascending: false)
      .execute()
      .value
  }

  func createPaymentRequest(childId: UUID, planName: String?, amountCents: Int?, currency: String?, notes: String?) async throws -> SDPaymentRequest {
    let session = try await client.auth.session
    let uid = session.user.id
    struct Insert: Encodable {
      let payer_id: UUID
      let child_id: UUID
      let status: String
      let plan_name: String?
      let amount_cents: Int?
      let currency: String?
      let notes: String?
    }
    return try await client
      .from("sd_payment_requests")
      .insert(Insert(payer_id: uid, child_id: childId, status: "requested", plan_name: planName, amount_cents: amountCents, currency: currency, notes: notes))
      .select("id,payer_id,child_id,status,plan_name,amount_cents,currency,notes,created_at,updated_at")
      .single()
      .execute()
      .value
  }

  func coachUpdatePaymentRequestStatus(requestId: UUID, status: String) async throws {
    struct Patch: Encodable { let status: String }
    _ = try await client
      .from("sd_payment_requests")
      .update(Patch(status: status))
      .eq("id", value: requestId.uuidString)
      .execute()
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
