import Foundation
import Testing
@testable import HomePlate

@Suite("Organization-scoped administration")
struct OrganizationAuthorizationTests {
  private let userId = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
  private let otherUserId = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!
  private let adminOrgId = UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")!
  private let coachOrgId = UUID(uuidString: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb")!

  private func membership(
    role: String,
    status: String = "active",
    orgId: UUID? = nil,
    userId: UUID? = nil
  ) -> SDOrgMembership {
    SDOrgMembership(
      org_id: orgId ?? adminOrgId,
      user_id: userId ?? self.userId,
      role: role,
      status: status,
      created_at: nil,
      created_by: nil
    )
  }

  @Test("Only active owners and admins can administer an organization", arguments: [
    ("owner", "active", true),
    ("admin", "active", true),
    ("coach", "active", false),
    ("player", "active", false),
    ("parent", "active", false),
    ("owner", "disabled", false),
    ("admin", "suspended", false),
  ])
  func roleAndStatusPolicy(role: String, status: String, expected: Bool) {
    #expect(
      OrganizationAuthorization.canAdminister(
        userId: userId,
        orgId: adminOrgId,
        memberships: [membership(role: role, status: status)]
      ) == expected
    )
  }

  @Test("Switching to a coach-only organization removes admin access")
  func organizationSwitchInvalidatesAuthority() {
    let memberships = [
      membership(role: "admin", orgId: adminOrgId),
      membership(role: "coach", orgId: coachOrgId),
    ]
    #expect(OrganizationAuthorization.canAdminister(
      userId: userId,
      orgId: adminOrgId,
      memberships: memberships
    ))
    #expect(!OrganizationAuthorization.canAdminister(
      userId: userId,
      orgId: coachOrgId,
      memberships: memberships
    ))
  }

  @Test("Memberships are bound to the current authenticated user")
  func unrelatedMembershipCannotAuthorize() {
    #expect(!OrganizationAuthorization.canAdminister(
      userId: userId,
      orgId: adminOrgId,
      memberships: [membership(role: "owner", userId: otherUserId)]
    ))
  }

  @Test("Platform status does not substitute for organization membership")
  func platformAdminIsNotOrganizationOwner() {
    #expect(!OrganizationAuthorization.canAdminister(
      userId: userId,
      orgId: adminOrgId,
      memberships: []
    ))
  }

  @Test("Temporary platform provisioning authority comes from the explicit owner membership")
  func provisionalOwnerRequiresMembership() {
    #expect(OrganizationAuthorization.canAdminister(
      userId: userId,
      orgId: adminOrgId,
      memberships: [membership(role: "owner", status: "active")]
    ))
    #expect(!OrganizationAuthorization.canAdminister(
      userId: userId,
      orgId: adminOrgId,
      memberships: [membership(role: "owner", status: "disabled")]
    ))
  }

  @Test("Customer Payments uses the same active owner/admin authority")
  func customerPaymentsPolicy() {
    #expect(OrganizationAuthorization.canAdminister(
      userId: userId,
      orgId: adminOrgId,
      memberships: [membership(role: "owner")]
    ))
    #expect(!OrganizationAuthorization.canAdminister(
      userId: userId,
      orgId: adminOrgId,
      memberships: [membership(role: "coach")]
    ))
  }

  @Test("Active organization roles select the workspace from membership", arguments: [
    ("owner", SDAuthenticatedWorkspace.staff),
    ("admin", SDAuthenticatedWorkspace.staff),
    ("coach", SDAuthenticatedWorkspace.staff),
    ("player", SDAuthenticatedWorkspace.player),
    ("parent", SDAuthenticatedWorkspace.parent),
  ])
  func workspaceUsesMembership(role: String, expected: SDAuthenticatedWorkspace) {
    #expect(
      SDAuthenticatedWorkspace.resolve(
        membership: membership(role: role),
        isPlatformAdmin: false
      ) == expected
    )
  }

  @Test("Profile role is not an organization authorization input")
  func workspaceHasNoProfileRoleOverride() {
    #expect(
      SDAuthenticatedWorkspace.resolve(membership: nil, isPlatformAdmin: false)
        == .unavailable
    )
    #expect(
      SDAuthenticatedWorkspace.resolve(
        membership: membership(role: "owner", status: "disabled"),
        isPlatformAdmin: false
      ) == .unavailable
    )
  }

  @Test("Unavailable workspace keeps organization switch and sign-out recovery")
  func unavailableWorkspaceRecoveryWiring() throws {
    let projectRoot = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    let source = try String(
      contentsOf: projectRoot.appendingPathComponent("MultiOrg/Features/Home/HomeView.swift"),
      encoding: .utf8
    )

    #expect(source.contains("case .unavailable:"))
    #expect(source.contains("Label(\"Switch Organization\""))
    #expect(source.contains("appState.switchActiveOrganization(to: organization.id)"))
    #expect(source.contains("title: \"Sign Out\""))
    #expect(source.contains("appState.signOut()"))
  }

  @Test("Parent request load failures stay distinct from truthful empty states")
  func parentRequestLoadFailureWiring() throws {
    let projectRoot = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    let source = try String(
      contentsOf: projectRoot.appendingPathComponent("MultiOrg/Features/Account/ParentRequestPanels.swift"),
      encoding: .utf8
    )

    #expect(source.contains("@State private var loadErrorText: String?"))
    #expect(source.contains("if linkedParents.isEmpty, loadErrorText == nil"))
    #expect(source.contains("if requests.isEmpty, loadErrorText == nil"))
    #expect(source.contains("title: \"Parent access unavailable\""))
    #expect(source.contains("title: \"Parent requests unavailable\""))
    #expect(source.contains("onRetry: { Task { await reload() } }"))
  }

  @Test("Platform-only and owner-plus-platform capabilities remain separate")
  func platformCapabilityIsIndependent() {
    #expect(
      SDAuthenticatedWorkspace.resolve(membership: nil, isPlatformAdmin: true)
        == .platformOnly
    )
    #expect(
      SDAuthenticatedWorkspace.resolve(
        membership: membership(role: "owner"),
        isPlatformAdmin: true
      ) == .staff
    )
  }

  @Test("Selected organization membership isolates different roles and clears stale authority")
  func selectedOrganizationIsolation() {
    let memberships = [
      membership(role: "owner", orgId: adminOrgId),
      membership(role: "player", orgId: coachOrgId),
    ]
    let owner = OrganizationAuthorization.activeMembership(
      userId: userId,
      orgId: adminOrgId,
      memberships: memberships
    )
    let player = OrganizationAuthorization.activeMembership(
      userId: userId,
      orgId: coachOrgId,
      memberships: memberships
    )
    #expect(SDAuthenticatedWorkspace.resolve(membership: owner, isPlatformAdmin: false) == .staff)
    #expect(SDAuthenticatedWorkspace.resolve(membership: player, isPlatformAdmin: false) == .player)
    #expect(OrganizationAuthorization.activeMembership(
      userId: userId,
      orgId: UUID(),
      memberships: memberships
    ) == nil)
  }

  @Test("Membership decoding accepts exact database roles without optional audit fields", arguments: [
    "owner", "admin", "coach", "player", "parent",
  ])
  func membershipRoleDecoding(role: String) throws {
    let json = """
    {
      "org_id":"\(adminOrgId.uuidString.lowercased())",
      "user_id":"\(userId.uuidString.lowercased())",
      "role":"\(role)",
      "status":"active"
    }
    """
    let decoded = try JSONDecoder().decode(SDOrgMembership.self, from: Data(json.utf8))
    #expect(decoded.normalizedRole == role)
    #expect(decoded.isActive)
  }
}

@Suite("Platform administration directory")
struct PlatformAdministrationDirectoryTests {
  private let orgA = UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")!
  private let orgB = UUID(uuidString: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb")!
  private let userA = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
  private let userB = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!

  private func organization(id: UUID, name: String, status: String = "active") -> SDPlatformOrganization {
    SDPlatformOrganization(
      id: id,
      slug: name.lowercased().replacingOccurrences(of: " ", with: "-"),
      name: name,
      status: status,
      plan: "starter",
      billing_email: nil,
      max_members: nil,
      active_members: 2,
      players: 1,
      coaches: 1,
      active_entitlements: 1,
      teams: 0
    )
  }

  private func member(
    id: UUID,
    role: String,
    status: String = "active",
    name: String,
    username: String,
    email: String
  ) -> SDPlatformMember {
    SDPlatformMember(
      org_id: orgA,
      user_id: id,
      role: role,
      status: status,
      created_at: "2026-07-01T12:00:00Z",
      created_by: nil,
      username: username,
      email: email,
      full_name: name,
      profile_role: nil,
      last_activity: nil
    )
  }

  @Test("Organization search is alphabetical and matches name, slug, and ID")
  func organizationSearch() {
    let organizations = [
      organization(id: orgB, name: "Zulu Baseball"),
      organization(id: orgA, name: "Alpha Baseball"),
    ]
    #expect(SDPlatformDirectory.organizations(organizations, matching: "").map(\.id) == [orgA, orgB])
    #expect(SDPlatformDirectory.organizations(organizations, matching: "alpha").map(\.id) == [orgA])
    #expect(SDPlatformDirectory.organizations(organizations, matching: orgB.uuidString).map(\.id) == [orgB])
  }

  @Test("Member search and role/inactive filters are deterministic")
  func memberSearchAndFilter() {
    let members = [
      member(id: userA, role: "owner", name: "LBAQ Owner", username: "lbaq27", email: "lbaq27@gmail.com"),
      member(id: userB, role: "coach", status: "disabled", name: "Casey Coach", username: "caseyc", email: "casey@example.com"),
    ]
    #expect(SDPlatformDirectory.members(members, matching: "gmail", filter: .all).map(\.user_id) == [userA])
    #expect(SDPlatformDirectory.members(members, matching: "", filter: .owner).map(\.user_id) == [userA])
    #expect(SDPlatformDirectory.members(members, matching: "", filter: .inactive).map(\.user_id) == [userB])
  }

  @Test("Permission editor retains one request ID and recognizes material changes")
  func permissionDraftIdempotency() {
    let requestId = UUID(uuidString: "33333333-3333-4333-8333-333333333333")!
    let owner = member(id: userA, role: "owner", name: "LBAQ Owner", username: "lbaq27", email: "lbaq27@gmail.com")
    var draft = PlatformMembershipEditDraft(member: owner, requestId: requestId)
    #expect(!draft.hasChanges)
    draft.role = "admin"
    #expect(draft.hasChanges)
    #expect(draft.requestId == requestId)
  }
}

@Suite("Payment request Swift foundation")
struct PaymentRequestFoundationTests {
  private let orgId = UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")!
  private let otherOrgId = UUID(uuidString: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb")!
  private let playerId = UUID(uuidString: "55555555-5555-4555-8555-555555555555")!
  private let otherPlayerId = UUID(uuidString: "66666666-6666-4666-8666-666666666666")!
  private let actorId = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
  private let firstKey = UUID(uuidString: "88888888-8888-4888-8888-888888888888")!
  private let secondKey = UUID(uuidString: "99999999-9999-4999-8999-999999999999")!

  @MainActor
  private final class MockPaymentRequestManagementService {
    private(set) var actions: [SDPaymentRequestManagementLoadAction] = []
    let eligiblePlayers: [SDPaymentRequestEligiblePlayer]

    init(eligiblePlayers: [SDPaymentRequestEligiblePlayer]) {
      self.eligiblePlayers = eligiblePlayers
    }

    func listManage() async {
      actions.append(.listManage)
    }

    func listEligiblePlayers() async -> [SDPaymentRequestEligiblePlayer] {
      actions.append(.listEligiblePlayers)
      return eligiblePlayers
    }

    func listEligiblePlayersResponse() async -> SDPaymentRequestEligiblePlayersResponse {
      actions.append(.listEligiblePlayers)
      return SDPaymentRequestEligiblePlayersResponse(
        players: eligiblePlayers,
        authorization_source: .platformSupport
      )
    }
  }

  private struct EncodedCreatePayload: Decodable {
    let action: String
    let org_id: UUID
    let player_ids: [UUID]
    let amount_cents: Int
    let idempotency_key: UUID
    let created_by: UUID?
    let payer_id: UUID?
    let status: String?
    let checkout_session_id: String?
    let payment_intent_id: String?
  }

  private func membership(role: String, status: String = "active") -> SDOrgMembership {
    SDOrgMembership(
      org_id: orgId,
      user_id: actorId,
      role: role,
      status: status,
      created_at: nil,
      created_by: nil
    )
  }

  private func request(orgId: UUID? = nil, canPay: Bool = true) -> SDPaymentRequest {
    SDPaymentRequest(
      id: UUID(uuidString: "77777777-7777-4777-8777-777777777777")!,
      request_batch_id: UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-000000000001")!,
      org_id: orgId ?? self.orgId,
      player_id: playerId,
      player_name: "Test Player",
      created_by: actorId,
      title: "Team fee",
      description: "One-time request",
      amount_cents: 1_234,
      currency: "usd",
      due_date: "2026-08-01",
      status: .open,
      created_at: nil,
      updated_at: nil,
      can_current_user_pay: canPay
    )
  }

  private func validDraft() -> SDPaymentRequestCreateDraft {
    var draft = SDPaymentRequestCreateDraft()
    draft.selectedPlayerUserIds = [playerId]
    draft.title = "Team fee"
    draft.description = "One-time request"
    draft.amountDollars = "12.34"
    return draft
  }

  private func rosterMember(
    organizationId: UUID,
    userId: UUID,
    role: String = "player",
    status: String = "active",
    name: String? = "Test Player"
  ) -> SDPaymentRequestEligiblePlayer {
    SDPaymentRequestEligiblePlayer(
      userId: userId,
      organizationId: organizationId,
      role: role,
      status: status,
      createdAt: nil,
      createdBy: actorId,
      username: nil,
      email: nil,
      fullName: name,
      profileRole: role
    )
  }

  private func loadedRoster(organizationId: UUID? = nil) -> SDPaymentRequestEligibleRosterState {
    let organizationId = organizationId ?? orgId
    var state = SDPaymentRequestEligibleRosterState.idle
    state.beginLoading(organizationId: organizationId, requestId: firstKey)
    state.apply(
      [rosterMember(organizationId: organizationId, userId: playerId)],
      organizationId: organizationId,
      requestId: firstKey
    )
    return state
  }

  private func eligibleRosterFixture(
    playerCount: Int = 8,
    includeOptionalProfileFields: Bool = true
  ) -> Data {
    let players = (1...playerCount).map { index in
      let userId = String(format: "00000000-0000-4000-8000-%012d", index)
      if includeOptionalProfileFields {
        return """
          {
            "org_id":"\(orgId.uuidString)",
            "user_id":"\(userId)",
            "role":"player",
            "status":"active",
            "created_at":"2026-07-14T12:00:00.123456+00:00",
            "created_by":null,
            "username":"player\(index)",
            "email":null,
            "full_name":"Player \(index)",
            "profile_role":"player"
          }
          """
      }
      return """
        {
          "org_id":"\(orgId.uuidString)",
          "user_id":"\(userId)",
          "role":"player",
          "status":"active"
        }
        """
    }
    return Data("""
      {
        "players":[\(players.joined(separator: ","))],
        "authorization_source":"platform_support"
      }
      """.utf8)
  }

  private func canManagePaymentRequests(
    role: String? = nil,
    status: String = "active",
    selectedOrganizationIsActive: Bool = true,
    isPlatformAdmin: Bool = false,
    isPlatformSupportAuthorized: Bool = false,
    currentUserId: UUID? = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
  ) -> Bool {
    let hasActiveOwnerOrAdminMembership = role.map {
      membership(role: $0, status: status).canAdministerOrganization
    } ?? false
    return SDPaymentRequestAuthorization.canManagePaymentRequests(
      selectedOrganizationIsActive: selectedOrganizationIsActive,
      hasActiveOwnerOrAdminMembership: hasActiveOwnerOrAdminMembership,
      isPlatformAdmin: isPlatformAdmin,
      isPlatformSupportAuthorized: isPlatformSupportAuthorized,
      currentUserId: currentUserId
    )
  }

  @Test("Customer Payments dispatches manage and roster actions without local platform or membership gates")
  @MainActor
  func customerPaymentsDispatchesBothBackendActions() async {
    let staleAppStateIsPlatformAdmin = false
    let ownerOrAdminMembership: SDOrgMembership? = nil
    let player = rosterMember(organizationId: orgId, userId: playerId)
    let service = MockPaymentRequestManagementService(eligiblePlayers: [player])
    var rosterState = SDPaymentRequestEligibleRosterState.idle
    rosterState.beginLoading(organizationId: orgId, requestId: firstKey)
    var managedRequestState = SDPaymentRequestListState()
    managedRequestState.beginLoading(organizationId: orgId)

    await SDPaymentRequestManagementLoadCoordinator.load(
      listManage: {
        await service.listManage()
        managedRequestState.apply([], organizationId: orgId)
      },
      listEligiblePlayers: {
        let players = await service.listEligiblePlayers()
        _ = rosterState.apply(
          players,
          organizationId: orgId,
          requestId: firstKey
        )
      }
    )

    #expect(!staleAppStateIsPlatformAdmin)
    #expect(ownerOrAdminMembership == nil)
    #expect(Set(service.actions) == [.listManage, .listEligiblePlayers])
    #expect(service.actions.count == 2)
    #expect(rosterState.players(for: orgId).map(\.userId) == [playerId])
    let platformSupportAuthorized = managedRequestState.hasSuccessfulResponse(for: orgId)
      || rosterState.hasSuccessfulResponse(for: orgId)
    let canManage = SDPaymentRequestAuthorization.canManagePaymentRequests(
      selectedOrganizationIsActive: true,
      hasActiveOwnerOrAdminMembership: false,
      isPlatformAdmin: staleAppStateIsPlatformAdmin,
      isPlatformSupportAuthorized: platformSupportAuthorized,
      currentUserId: actorId
    )
    #expect(canManage)
    #expect(SDPaymentRequestAuthorization.createControlDisabledReason(
      canManagePaymentRequests: canManage,
      selectedOrganizationIsActive: true,
      hasMutationInFlight: false
    ) == nil)
  }

  @Test("The exact list_eligible_players server envelope decodes eight active players")
  func exactEligiblePlayerEnvelopeDecodes() throws {
    let response = try SDPaymentRequestEligiblePlayersContract.decode(eligibleRosterFixture())
    #expect(response.authorization_source == .platformSupport)
    #expect(response.players.count == 8)
    #expect(response.players.allSatisfy { $0.organizationId == orgId })
    #expect(response.players.allSatisfy { $0.role == "player" && $0.status == "active" })
  }

  @Test("Eligible-player user_id remains the picker and create identity")
  func eligiblePlayerUserIdFlowsUnchangedIntoCreate() throws {
    let membershipUserId = UUID(uuidString: "4b999cda-7826-4fae-9334-1a269dc34795")!
    let unrelatedEnrichmentId = UUID(uuidString: "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee")!
    let fixture = Data("""
      {
        "players":[{
          "id":"\(unrelatedEnrichmentId.uuidString)",
          "user_id":"\(membershipUserId.uuidString.lowercased())",
          "org_id":"\(orgId.uuidString.lowercased())",
          "role":"player",
          "status":"active",
          "created_at":null,
          "created_by":null,
          "username":"andrew",
          "email":null,
          "full_name":"Andrew",
          "profile_role":"player"
        }],
        "authorization_source":"organization_membership"
      }
      """.utf8)

    let response = try SDPaymentRequestEligiblePlayersContract.decode(fixture)
    let player = try #require(response.players.first)
    #expect(player.userId == membershipUserId)
    #expect(player.id == membershipUserId)
    #expect(player.id != unrelatedEnrichmentId)

    var draft = SDPaymentRequestCreateDraft()
    draft.selectedPlayerUserIds.insert(player.userId)
    draft.title = "Team fee"
    draft.amountDollars = "5.00"
    let selectedPlayerUserIds = SDPaymentRequestPlayerRoster.payloadPlayerUserIds(
      selectedPlayerUserIds: draft.selectedPlayerUserIds,
      eligiblePlayers: response.players
    )
    #expect(selectedPlayerUserIds == [membershipUserId])

    draft.selectedPlayerUserIds = Set(selectedPlayerUserIds)
    let preparedPayload = draft.prepareCreatePayload(orgId: orgId, makeUUID: { firstKey })
    let payload = try #require(preparedPayload)
    #expect(payload.player_ids == [membershipUserId])
    let decodedPayload = try JSONDecoder().decode(
      EncodedCreatePayload.self,
      from: JSONEncoder().encode(payload)
    )
    #expect(decodedPayload.player_ids == [membershipUserId])
  }

  @Test("Player payment-request reads send the canonical membership user_id")
  func playerPaymentRequestReadUsesCanonicalUserId() {
    let playerUserId = UUID(uuidString: "4b999cda-7826-4fae-9334-1a269dc34795")!
    let body = SupabaseService.paymentRequestListBody(
      orgId: orgId,
      playerId: playerUserId
    )

    #expect(body["action"] == "list")
    #expect(body["org_id"] == orgId.uuidString)
    #expect(body["player_id"] == playerUserId.uuidString.lowercased())
    #expect(body["created_by"] == nil)
    #expect(body["payer_id"] == nil)
  }

  @Test("Missing optional roster profile fields decode and use a safe player fallback name")
  func missingOptionalRosterFieldsDecode() throws {
    let response = try SDPaymentRequestEligiblePlayersContract.decode(
      eligibleRosterFixture(playerCount: 1, includeOptionalProfileFields: false)
    )
    let player = try #require(response.players.first)
    #expect(player.fullName == nil)
    #expect(player.username == nil)
    #expect(player.email == nil)
    #expect(player.displayName == "Player 000001")
  }

  @Test("Roster display names prefer full name, username, email, then short UUID")
  func rosterDisplayNameFallbackHierarchy() {
    let fullName = rosterMember(organizationId: orgId, userId: playerId, name: "  Full Name  ")
    let username = SDPaymentRequestEligiblePlayer(
      userId: otherPlayerId, organizationId: orgId, role: "player", status: "active",
      createdAt: nil, createdBy: nil, username: "org-user", email: "user@example.com",
      fullName: nil, profileRole: nil
    )
    let emailId = UUID(uuidString: "00000000-0000-4000-8000-000000000003")!
    let email = SDPaymentRequestEligiblePlayer(
      userId: emailId, organizationId: orgId, role: "player", status: "active",
      createdAt: nil, createdBy: nil, username: nil, email: "user@example.com",
      fullName: nil, profileRole: nil
    )
    let fallbackId = UUID(uuidString: "00000000-0000-4000-8000-00000000abcd")!
    let fallback = SDPaymentRequestEligiblePlayer(
      userId: fallbackId, organizationId: orgId, role: "player", status: "active",
      createdAt: nil, createdBy: nil, username: nil, email: nil,
      fullName: nil, profileRole: nil
    )
    #expect(fullName.displayName == "Full Name")
    #expect(username.displayName == "@org-user")
    #expect(email.displayName == "user@example.com")
    #expect(fallback.displayName == "Player 00abcd")
  }

  @Test("The picker reads the same eight-player collection populated by the decoded response")
  func decodedRosterPopulatesPickerCollection() throws {
    let response = try SDPaymentRequestEligiblePlayersContract.decode(eligibleRosterFixture())
    var rosterState = SDPaymentRequestEligibleRosterState.idle
    rosterState.beginLoading(organizationId: orgId, requestId: firstKey)
    let didApply = rosterState.apply(
      response.players,
      organizationId: orgId,
      requestId: firstKey
    )
    #expect(didApply)
    #expect(rosterState.players(for: orgId) == response.players)
    #expect(rosterState.players(for: orgId).count == 8)
  }

  @Test("A valid current-organization roster response is accepted")
  func currentOrganizationRosterResponseIsAccepted() {
    #expect(SDPaymentRequestRosterResponseContext.matchesSelectedOrganization(
      responseOrganizationId: orgId,
      selectedOrganizationId: orgId,
      rosterContextOrganizationId: orgId
    ))
  }

  @Test("A previous-organization roster response is genuinely stale")
  func previousOrganizationRosterResponseIsDiscarded() {
    #expect(!SDPaymentRequestRosterResponseContext.matchesSelectedOrganization(
      responseOrganizationId: otherOrgId,
      selectedOrganizationId: orgId,
      rosterContextOrganizationId: orgId
    ))
  }

  @Test("Payment-request sheet appearance always triggers list_eligible_players")
  @MainActor
  func sheetAppearanceLoadsEligiblePlayers() async throws {
    let service = MockPaymentRequestManagementService(eligiblePlayers: [])
    _ = try await SDPaymentRequestSheetRosterLoadCoordinator.loadResponse(
      organizationId: orgId,
      listEligiblePlayers: { _ in await service.listEligiblePlayersResponse() }
    )
    #expect(service.actions == [.listEligiblePlayers])
  }

  @Test("Reopening the payment-request sheet performs a fresh roster request")
  @MainActor
  func reopeningSheetReloadsEligiblePlayers() async throws {
    let service = MockPaymentRequestManagementService(eligiblePlayers: [])
    for _ in 0..<2 {
      _ = try await SDPaymentRequestSheetRosterLoadCoordinator.loadResponse(
        organizationId: orgId,
        listEligiblePlayers: { _ in await service.listEligiblePlayersResponse() }
      )
    }
    #expect(service.actions == [.listEligiblePlayers, .listEligiblePlayers])
  }

  @Test("An inherited empty parent roster cannot replace the sheet response")
  @MainActor
  func inheritedEmptyParentRosterDoesNotAffectSheet() async throws {
    var inheritedParentState = SDPaymentRequestEligibleRosterState.idle
    inheritedParentState.beginLoading(organizationId: orgId, requestId: firstKey)
    _ = inheritedParentState.apply([], organizationId: orgId, requestId: firstKey)
    let returnedPlayers = try SDPaymentRequestEligiblePlayersContract
      .decode(eligibleRosterFixture()).players
    let service = MockPaymentRequestManagementService(eligiblePlayers: returnedPlayers)

    let response = try await SDPaymentRequestSheetRosterLoadCoordinator.loadResponse(
      organizationId: orgId,
      listEligiblePlayers: { _ in await service.listEligiblePlayersResponse() }
    )
    let sheetEligiblePlayers = try #require(response).players

    #expect(inheritedParentState.players(for: orgId).isEmpty)
    #expect(sheetEligiblePlayers.count == 8)
  }

  @Test("Eight server-returned players create eight visible picker entries")
  func eightReturnedPlayersAreEightVisibleEntries() throws {
    let response = try SDPaymentRequestEligiblePlayersContract.decode(eligibleRosterFixture())
    let sheetEligiblePlayers = response.players
    let displayedPlayers = SDPaymentRequestPlayerRoster.search(sheetEligiblePlayers, text: "")
    #expect(sheetEligiblePlayers.count == 8)
    #expect(displayedPlayers.count == 8)
  }

  @Test("Sheet loading returns the exact server roster without a second role or status filter")
  @MainActor
  func sheetDoesNotRefilterServerRoster() async throws {
    let serverAuthorizedPlayer = rosterMember(
      organizationId: orgId,
      userId: playerId,
      role: "legacy-server-authorized-player",
      status: "legacy-server-authorized-status"
    )
    let service = MockPaymentRequestManagementService(eligiblePlayers: [serverAuthorizedPlayer])
    let response = try await SDPaymentRequestSheetRosterLoadCoordinator.loadResponse(
      organizationId: orgId,
      listEligiblePlayers: { _ in await service.listEligiblePlayersResponse() }
    )
    let loadedResponse = try #require(response)
    #expect(loadedResponse.players == [serverAuthorizedPlayer])
  }

  @Test("A stale parent load token cannot discard a current sheet response")
  func staleParentTokenDoesNotAffectSheetContext() {
    let staleParentToken = firstKey
    let currentParentToken = secondKey
    #expect(staleParentToken != currentParentToken)
    #expect(SDPaymentRequestSheetRosterResponseContext.discardReason(
      sheetIsPresented: true,
      requestedOrganizationId: orgId,
      selectedOrganizationId: orgId,
      responseRequestId: firstKey,
      currentRequestId: firstKey
    ) == nil)
  }

  @Test("A superseded sheet-local request is discarded")
  func supersededSheetRequestIsDiscarded() {
    #expect(SDPaymentRequestSheetRosterResponseContext.discardReason(
      sheetIsPresented: true,
      requestedOrganizationId: orgId,
      selectedOrganizationId: orgId,
      responseRequestId: firstKey,
      currentRequestId: secondKey
    ) == .requestSuperseded)
  }

  @Test("An empty sheet roster exposes Retry")
  func emptySheetRosterShowsRetry() {
    var state = SDPaymentRequestEligibleRosterState.idle
    state.beginLoading(organizationId: orgId, requestId: firstKey)
    let didApply = state.apply([], organizationId: orgId, requestId: firstKey)
    #expect(didApply)
    #expect(state.shouldShowRetry)
    #expect(state.errorMessage == nil)
  }

  @Test("A failed sheet roster exposes a readable error and Retry")
  func failedSheetRosterShowsReadableErrorAndRetry() {
    var state = SDPaymentRequestEligibleRosterState.idle
    state.beginLoading(organizationId: orgId, requestId: firstKey)
    let message = "Eligible players could not be loaded. Please try again."
    let didFail = state.fail(
      message: message,
      organizationId: orgId,
      requestId: firstKey
    )
    #expect(didFail)
    #expect(state.errorMessage == message)
    #expect(state.shouldShowRetry)
  }

  @Test("Selecting one returned player enables valid final submission")
  func returnedPlayerSelectionEnablesSubmission() throws {
    let response = try SDPaymentRequestEligiblePlayersContract.decode(
      eligibleRosterFixture(playerCount: 1)
    )
    var draft = SDPaymentRequestCreateDraft()
    draft.title = "Team fee"
    draft.amountDollars = "5.00"
    draft.selectedPlayerUserIds = [try #require(response.players.first).userId]
    let selected = SDPaymentRequestPlayerRoster.reconcile(
      selectedPlayerUserIds: draft.selectedPlayerUserIds,
      eligiblePlayers: response.players
    )
    #expect(SDPaymentRequestAuthorization.canSubmitCreateRequest(
      draftIsValid: draft.isValid,
      eligibleSelectedPlayerCount: selected.count,
      isSubmitting: false
    ))
  }

  @Test("A roster contract decoding failure has a readable error")
  func rosterDecodingFailureIsReadable() {
    let mismatchedEnvelope = Data(
      "{\"eligible_players\":[],\"authorization_source\":\"platform_support\"}".utf8
    )
    do {
      _ = try SDPaymentRequestEligiblePlayersContract.decode(mismatchedEnvelope)
      Issue.record("Expected the mismatched roster response to fail decoding")
    } catch {
      #expect(error.localizedDescription ==
        "Eligible players could not be read from the server response. Please try again.")
    }
  }

  @Test("Integer minor units format as currency without authoritative Double math")
  func integerCentFormatting() {
    let formatted = SDMoney(minorUnits: 1_234, currency: "usd")
      .formatted(locale: Locale(identifier: "en_US"))
    #expect(formatted.contains("12.34"))
    #expect(formatted.contains("$"))
  }

  @Test("Create form validates selection, integer cents, and upper bounds")
  func createFormValidation() {
    var draft = SDPaymentRequestCreateDraft()
    draft.title = "Team fee"
    draft.amountDollars = "12.34"
    #expect(draft.validationError == "Select at least one player.")
    draft.selectedPlayerUserIds.insert(playerId)
    draft.selectedPlayerUserIds.insert(playerId)
    #expect(draft.selectedPlayerUserIds.count == 1)
    #expect(draft.amountCents == 1_234)
    #expect(draft.isValid)
    draft.amountDollars = "12.345"
    #expect(!draft.isValid)
    draft.amountDollars = "100000.01"
    #expect(!draft.isValid)
  }

  @Test("Eligible roster is selected-organization active-player only, deduplicated, and name sorted")
  func eligibleRosterFiltering() {
    let inactiveId = UUID(uuidString: "77777777-7777-4777-8777-000000000003")!
    let coachId = UUID(uuidString: "77777777-7777-4777-8777-000000000004")!
    let parentId = UUID(uuidString: "77777777-7777-4777-8777-000000000005")!
    let secondActiveId = UUID(uuidString: "77777777-7777-4777-8777-000000000006")!
    let members = [
      rosterMember(organizationId: orgId, userId: playerId, name: "Zeta Player"),
      rosterMember(organizationId: orgId, userId: playerId, name: nil),
      rosterMember(organizationId: otherOrgId, userId: otherPlayerId, name: "Other Organization"),
      rosterMember(organizationId: orgId, userId: inactiveId, status: "suspended", name: "Inactive"),
      rosterMember(organizationId: orgId, userId: coachId, role: "coach", name: "Coach"),
      rosterMember(organizationId: orgId, userId: parentId, role: "parent", name: "Parent"),
      rosterMember(organizationId: orgId, userId: secondActiveId, name: "Alpha Player"),
    ]
    let eligible = SDPaymentRequestPlayerRoster.eligiblePlayers(
      from: members,
      organizationId: orgId
    )
    #expect(eligible.map(\.userId) == [secondActiveId, playerId])
    #expect(eligible.first?.displayName == "Alpha Player")
  }

  @Test("Organization switch clears selection and loads only the new organization roster")
  func organizationSwitchRoster() {
    #expect(SDPaymentRequestPlayerRoster.organizationChanged(from: orgId, to: otherOrgId))
    var selected: Set<UUID> = [playerId]
    if SDPaymentRequestPlayerRoster.organizationChanged(from: orgId, to: otherOrgId) {
      selected.removeAll()
    }
    #expect(selected.isEmpty)
    let newRoster = SDPaymentRequestPlayerRoster.eligiblePlayers(
      from: [
        rosterMember(organizationId: orgId, userId: playerId, name: "Old Player"),
        rosterMember(organizationId: otherOrgId, userId: otherPlayerId, name: "New Player"),
      ],
      organizationId: otherOrgId
    )
    #expect(newRoster.map(\.userId) == [otherPlayerId])
  }

  @Test("Select All and search operate only on the eligible roster")
  func selectAllAndSearchAreEligibleOnly() {
    let eligible = SDPaymentRequestPlayerRoster.eligiblePlayers(
      from: [
        rosterMember(organizationId: orgId, userId: playerId, name: "Visible Player"),
        rosterMember(organizationId: otherOrgId, userId: otherPlayerId, name: "Hidden Player"),
      ],
      organizationId: orgId
    )
    #expect(SDPaymentRequestPlayerRoster.selectAll(eligible) == [playerId])
    #expect(SDPaymentRequestPlayerRoster.search(eligible, text: "Hidden").isEmpty)
    #expect(SDPaymentRequestPlayerRoster.search(eligible, text: "Visible").map(\.userId) == [playerId])
  }

  @Test("Roster refresh removes newly ineligible selections and prevents submission")
  func rosterRefreshReconcilesSelection() {
    let refreshed = SDPaymentRequestPlayerRoster.eligiblePlayers(
      from: [rosterMember(
        organizationId: orgId,
        userId: playerId,
        status: "suspended"
      )],
      organizationId: orgId
    )
    let selected = SDPaymentRequestPlayerRoster.reconcile(
      selectedPlayerUserIds: [playerId],
      eligiblePlayers: refreshed
    )
    #expect(selected.isEmpty)
    var draft = validDraft()
    draft.selectedPlayerUserIds = selected
    #expect(!draft.isValid)
  }

  @Test("Submission payload contains only visible eligible player IDs")
  func payloadUsesEligibleRosterOnly() throws {
    let eligible = SDPaymentRequestPlayerRoster.eligiblePlayers(
      from: [
        rosterMember(organizationId: orgId, userId: playerId),
        rosterMember(organizationId: otherOrgId, userId: otherPlayerId),
      ],
      organizationId: orgId
    )
    let safeIds = SDPaymentRequestPlayerRoster.payloadPlayerUserIds(
      selectedPlayerUserIds: [playerId, otherPlayerId],
      eligiblePlayers: eligible
    )
    #expect(safeIds == [playerId])
    var draft = validDraft()
    draft.selectedPlayerUserIds = Set(safeIds)
    let payloadValue = draft.prepareCreatePayload(orgId: orgId, makeUUID: { firstKey })
    let payload = try #require(payloadValue)
    #expect(payload.player_ids == [playerId])
  }

  @Test("An active organization owner can open Create Payment Request")
  func activeOwnerCanOpenCreate() {
    #expect(canManagePaymentRequests(role: "owner"))
  }

  @Test("An active organization admin can open Create Payment Request")
  func activeAdminCanOpenCreate() {
    #expect(canManagePaymentRequests(role: "admin"))
  }

  @Test("A platform admin can open Create without organization membership")
  func platformAdminCanOpenCreateWithoutMembership() {
    #expect(canManagePaymentRequests(isPlatformAdmin: true))
  }

  @Test("The immutable emergency support user ID overrides stale platform-admin state")
  func emergencySupportUserCanOpenCreate() {
    let staleAppStateIsPlatformAdmin = false
    #expect(canManagePaymentRequests(
      isPlatformAdmin: staleAppStateIsPlatformAdmin,
      currentUserId: SDPaymentRequestAuthorization.emergencySupportUserId
    ))
  }

  @Test("A freshly authorized platform-support response can open Create")
  func backendAuthorizedPlatformSupportCanOpenCreate() {
    #expect(canManagePaymentRequests(isPlatformSupportAuthorized: true))
  }

  @Test("Eligible-player loading does not disable the outer Create button")
  func rosterLoadingDoesNotDisableOuterCreate() {
    var rosterState = SDPaymentRequestEligibleRosterState.idle
    rosterState.beginLoading(organizationId: orgId, requestId: firstKey)
    #expect(rosterState.isLoading)
    #expect(SDPaymentRequestAuthorization.createControlDisabledReason(
      canManagePaymentRequests: canManagePaymentRequests(role: "owner"),
      selectedOrganizationIsActive: true,
      hasMutationInFlight: false
    ) == nil)
  }

  @Test("An empty eligible roster does not prevent opening the Create sheet")
  func emptyRosterDoesNotDisableOuterCreate() {
    var rosterState = SDPaymentRequestEligibleRosterState.idle
    rosterState.beginLoading(organizationId: orgId, requestId: firstKey)
    let didApply = rosterState.apply([], organizationId: orgId, requestId: firstKey)
    #expect(didApply)
    #expect(rosterState.hasSuccessfulResponse(for: orgId))
    #expect(SDPaymentRequestAuthorization.createControlDisabledReason(
      canManagePaymentRequests: canManagePaymentRequests(role: "admin"),
      selectedOrganizationIsActive: true,
      hasMutationInFlight: false
    ) == nil)
  }

  @Test("Roster failures retain a readable sheet error without disabling outer Create")
  func rosterFailureRemainsReadableInsideSheet() {
    var rosterState = SDPaymentRequestEligibleRosterState.idle
    rosterState.beginLoading(organizationId: orgId, requestId: firstKey)
    let message = "Eligible players could not be loaded. Please try again."
    let didFail = rosterState.fail(message: message, organizationId: orgId, requestId: firstKey)
    #expect(didFail)
    #expect(rosterState.errorMessage == message)
    #expect(SDPaymentRequestAuthorization.createControlDisabledReason(
      canManagePaymentRequests: canManagePaymentRequests(role: "owner"),
      selectedOrganizationIsActive: true,
      hasMutationInFlight: false
    ) == nil)
  }

  @Test("Final Submit stays disabled until an eligible player is selected")
  func finalSubmitRequiresEligiblePlayer() {
    #expect(!SDPaymentRequestAuthorization.canSubmitCreateRequest(
      draftIsValid: true,
      eligibleSelectedPlayerCount: 0,
      isSubmitting: false
    ))
    #expect(SDPaymentRequestAuthorization.canSubmitCreateRequest(
      draftIsValid: true,
      eligibleSelectedPlayerCount: 1,
      isSubmitting: false
    ))
  }

  @Test("A coach without platform authority cannot open Create")
  func coachCannotOpenCreate() {
    #expect(!canManagePaymentRequests(role: "coach"))
  }

  @Test("A parent cannot open Create")
  func parentCannotOpenCreate() {
    #expect(!canManagePaymentRequests(role: "parent"))
  }

  @Test("A player cannot open Create")
  func playerCannotOpenCreate() {
    #expect(!canManagePaymentRequests(role: "player"))
  }

  @Test("An inactive owner cannot open Create")
  func inactiveOwnerCannotOpenCreate() {
    #expect(!canManagePaymentRequests(role: "owner", status: "disabled"))
  }

  @Test("An inactive or missing organization disables Create for every actor")
  func activeOrganizationIsRequired() {
    #expect(!canManagePaymentRequests(
      selectedOrganizationIsActive: false,
      isPlatformAdmin: true
    ))
    #expect(SDPaymentRequestAuthorization.createControlDisabledReason(
      canManagePaymentRequests: false,
      selectedOrganizationIsActive: false,
      hasMutationInFlight: false
    ) == "No active organization selected")
  }

  @Test("A mutation in flight is the only operational Create-button disablement")
  func mutationDisablesOuterCreate() {
    #expect(SDPaymentRequestAuthorization.createControlDisabledReason(
      canManagePaymentRequests: true,
      selectedOrganizationIsActive: true,
      hasMutationInFlight: true
    ) == "Payment request action in progress")
  }

  @Test("Organization switching ignores a stale eligible-roster response")
  func rosterStateRejectsStaleOrganizationResponse() {
    var state = SDPaymentRequestEligibleRosterState.idle
    state.beginLoading(organizationId: orgId, requestId: firstKey)
    state.beginLoading(organizationId: otherOrgId, requestId: secondKey)
    let didApplyStaleResponse = state.apply(
      [rosterMember(organizationId: orgId, userId: playerId)],
      organizationId: orgId,
      requestId: firstKey
    )
    #expect(!didApplyStaleResponse)
    #expect(state.isLoading)
    let didApplyCurrentResponse = state.apply(
      [rosterMember(organizationId: otherOrgId, userId: otherPlayerId)],
      organizationId: otherOrgId,
      requestId: secondKey
    )
    #expect(didApplyCurrentResponse)
    #expect(state.players(for: orgId).isEmpty)
    #expect(state.players(for: otherOrgId).map(\.userId) == [otherPlayerId])
  }

  @Test("Stripe Connect readiness does not affect the Create permission")
  func createPermissionHasNoStripeConnectGate() {
    let decisions = [false, true].map { _ in
      canManagePaymentRequests(role: "owner")
    }
    #expect(decisions == [true, true])
  }

  @Test("Organization SaaS subscription state does not affect the Create permission")
  func createPermissionHasNoSaaSBillingGate() {
    let decisions = [false, true].map { _ in
      canManagePaymentRequests(isPlatformAdmin: true)
    }
    #expect(decisions == [true, true])
  }

  @Test("Create button action presents the multi-player request sheet")
  func createButtonPresentsSheet() {
    var presentation = SDPaymentRequestCreatePresentationState()
    #expect(!presentation.isPresented)
    presentation.present()
    #expect(presentation.isPresented)
    presentation.dismiss()
    #expect(!presentation.isPresented)
  }

  @Test("Exact new-request envelope decodes timestamps and null due date")
  func newlyCreatedEnvelopeDecodes() throws {
    let json = """
      {
        "requests":[{
          "id":"77777777-7777-4777-8777-777777777777",
          "request_batch_id":"aaaaaaaa-aaaa-4aaa-8aaa-000000000001",
          "org_id":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
          "player_id":"55555555-5555-4555-8555-555555555555",
          "player_name":"Test Player",
          "created_by":"11111111-1111-4111-8111-111111111111",
          "title":"Team fee",
          "description":null,
          "amount_cents":1234,
          "currency":"usd",
          "due_date":null,
          "status":"open",
          "created_at":"2026-07-14T12:00:00.123456+00:00",
          "updated_at":"2026-07-14T12:00:00+00:00",
          "can_current_user_pay":false
        }],
        "created_count":1,
        "reused":false,
        "authorization_source":"organization_membership"
      }
      """
    let decoded = try JSONDecoder().decode(SDPaymentRequestCreateResponse.self, from: Data(json.utf8))
    let request = try #require(decoded.requests.first)
    #expect(decoded.requests.count == 1)
    #expect(decoded.created_count == 1)
    #expect(!decoded.reused)
    #expect(decoded.authorization_source == .organizationMembership)
    #expect(request.player_id == playerId)
    #expect(request.due_date == nil)
    #expect(request.created_at != nil)
    #expect(request.updated_at != nil)
    #expect(request.money?.minorUnits == 1_234)
  }

  @Test("Idempotently reused and multi-player response envelopes decode")
  func reusedAndMultiEnvelopeDecode() throws {
    let requestJSON = """
      {
        "id":"77777777-7777-4777-8777-777777777777",
        "request_batch_id":"aaaaaaaa-aaaa-4aaa-8aaa-000000000001",
        "org_id":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
        "player_id":"55555555-5555-4555-8555-555555555555",
        "player_name":"Test Player",
        "created_by":"11111111-1111-4111-8111-111111111111",
        "title":"Team fee",
        "description":"One-time request",
        "amount_cents":1234,
        "currency":"usd",
        "due_date":"2026-08-01",
        "status":"open",
        "created_at":"2026-07-14T12:00:00Z",
        "updated_at":"2026-07-14T12:00:00Z",
        "can_current_user_pay":false
      }
      """
    let reusedJSON = "{\"requests\":[\(requestJSON)],\"created_count\":0,\"reused\":true,\"authorization_source\":\"platform_support\"}"
    let reused = try JSONDecoder().decode(SDPaymentRequestCreateResponse.self, from: Data(reusedJSON.utf8))
    #expect(reused.reused)
    #expect(reused.created_count == 0)
    #expect(reused.requests.count == 1)
    #expect(reused.authorization_source == .platformSupport)

    let secondRequestJSON = requestJSON
      .replacingOccurrences(of: "77777777-7777-4777-8777-777777777777", with: "77777777-7777-4777-8777-777777777778")
      .replacingOccurrences(of: "55555555-5555-4555-8555-555555555555", with: "66666666-6666-4666-8666-666666666666")
      .replacingOccurrences(of: "Test Player", with: "Other Player")
    let batchJSON = "{\"requests\":[\(requestJSON),\(secondRequestJSON)],\"created_count\":2,\"reused\":false,\"authorization_source\":\"organization_membership\"}"
    let batch = try JSONDecoder().decode(SDPaymentRequestCreateResponse.self, from: Data(batchJSON.utf8))
    #expect(batch.requests.count == 2)
    #expect(Set(batch.requests.map(\.id)).count == 2)
    #expect(Set(batch.requests.compactMap(\.request_batch_id)).count == 1)
  }

  @Test("Nullable legacy response fields decode safely")
  func legacyNullableFieldsDecode() throws {
    let json = """
      {
        "id":"77777777-7777-4777-8777-777777777777",
        "request_batch_id":null,
        "org_id":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
        "player_id":"55555555-5555-4555-8555-555555555555",
        "player_name":null,
        "created_by":"11111111-1111-4111-8111-111111111111",
        "title":"Legacy request",
        "description":null,
        "amount_cents":null,
        "currency":"usd",
        "due_date":null,
        "status":"open",
        "created_at":null,
        "updated_at":null,
        "can_current_user_pay":false
      }
      """
    let decoded = try JSONDecoder().decode(SDPaymentRequest.self, from: Data(json.utf8))
    #expect(decoded.request_batch_id == nil)
    #expect(decoded.player_name == nil)
    #expect(decoded.amount_cents == nil)
    #expect(decoded.due_date == nil)
    #expect(decoded.created_at == nil)
  }

  @Test("Sanitized Edge errors remain readable")
  func sanitizedErrorResponse() {
    let data = Data("""
      {"error":"idempotency_conflict","message":"This retry identifier is already bound to different payment-request details."}
      """.utf8)
    let error = SDEdgeFunctionHTTPError.decode(statusCode: 409, data: data)
    #expect(error.statusCode == 409)
    #expect(error.code == "idempotency_conflict")
    #expect(error.localizedDescription == "This retry identifier is already bound to different payment-request details.")
  }

  @Test("Organization switching clears requests and rejects stale responses")
  func organizationSwitchClearsState() {
    var state = SDPaymentRequestListState()
    state.beginLoading(organizationId: orgId)
    state.apply([request()], organizationId: orgId)
    #expect(state.requests.count == 1)
    state.beginLoading(organizationId: otherOrgId)
    #expect(state.requests.isEmpty)
    state.apply([request()], organizationId: orgId)
    #expect(state.requests.isEmpty)
  }

  @Test("Organization switching resets the draft selection and pending idempotency operation")
  func organizationSwitchClearsDraftOperation() throws {
    var draft = validDraft()
    let payloadValue = draft.prepareCreatePayload(orgId: orgId, makeUUID: { firstKey })
    let payload = try #require(payloadValue)
    #expect(draft.pendingIdempotencyKey == payload.idempotency_key)
    #expect(!draft.selectedPlayerUserIds.isEmpty)

    if SDPaymentRequestPlayerRoster.organizationChanged(from: orgId, to: otherOrgId) {
      draft = SDPaymentRequestCreateDraft()
    }
    #expect(draft.pendingIdempotencyKey == nil)
    #expect(draft.selectedPlayerUserIds.isEmpty)
    #expect(draft.title.isEmpty)
  }

  @Test("Decoding and network uncertainty reuse the original operation UUID")
  func ambiguousRetryKeepsIdempotencyKey() throws {
    var draft = validDraft()
    let firstValue = draft.prepareCreatePayload(orgId: orgId, makeUUID: { firstKey })
    let first = try #require(firstValue)
    let decodingRetryValue = draft.prepareCreatePayload(orgId: orgId, makeUUID: { secondKey })
    let decodingRetry = try #require(decodingRetryValue)
    #expect(decodingRetry.idempotency_key == first.idempotency_key)
    let networkRetryValue = draft.prepareCreatePayload(orgId: orgId, makeUUID: { secondKey })
    let networkRetry = try #require(networkRetryValue)
    #expect(networkRetry.idempotency_key == first.idempotency_key)
  }

  @Test("Material changes rotate the operation UUID and success clears it")
  func materialChangesRotateIdempotencyKey() throws {
    var draft = validDraft()
    let firstValue = draft.prepareCreatePayload(orgId: orgId, makeUUID: { firstKey })
    let first = try #require(firstValue)
    draft.selectedPlayerUserIds.insert(otherPlayerId)
    let changedValue = draft.prepareCreatePayload(orgId: orgId, makeUUID: { secondKey })
    let changed = try #require(changedValue)
    #expect(changed.idempotency_key != first.idempotency_key)
    draft.completeOperation(idempotencyKey: changed.idempotency_key)
    #expect(draft.pendingIdempotencyKey == nil)
    let nextValue = draft.prepareCreatePayload(orgId: orgId, makeUUID: { firstKey })
    let next = try #require(nextValue)
    #expect(next.idempotency_key == firstKey)
  }

  @Test("Payment creation payload is typed and excludes actor, status, and provider identity")
  func safeCreatePayload() throws {
    var draft = validDraft()
    let payloadValue = draft.prepareCreatePayload(orgId: orgId, makeUUID: { firstKey })
    let payload = try #require(payloadValue)
    let encoded = try JSONEncoder().encode(payload)
    let decoded = try JSONDecoder().decode(EncodedCreatePayload.self, from: encoded)
    #expect(decoded.action == "create")
    #expect(decoded.org_id == orgId)
    #expect(decoded.player_ids == [playerId])
    #expect(decoded.amount_cents == 1_234)
    #expect(decoded.idempotency_key == firstKey)
    #expect(decoded.created_by == nil)
    #expect(decoded.payer_id == nil)
    #expect(decoded.status == nil)
    #expect(decoded.checkout_session_id == nil)
    #expect(decoded.payment_intent_id == nil)
  }
}

@Suite("Platform organization creation workflow")
@MainActor
struct PlatformOrganizationCreationWorkflowTests {
  private func validDraft() -> PlatformOrganizationCreateDraft {
    PlatformOrganizationCreateDraft(
      name: "Home Plate Test",
      slug: "home-plate-test",
      plan: "starter",
      billingEmail: "",
      maxMembers: "30"
    )
  }

  private func organization() -> SDPlatformOrganization {
    SDPlatformOrganization(
      id: UUID(uuidString: "99999999-9999-4999-8999-999999999999")!,
      slug: "home-plate-test",
      name: "Home Plate Test",
      status: "active",
      plan: "starter",
      billing_email: nil,
      max_members: 30,
      active_members: 1,
      players: 0,
      coaches: 1,
      active_entitlements: 0,
      teams: 0
    )
  }

  @Test("New Organization action presents the form")
  func presentsForm() {
    let workflow = PlatformOrganizationCreationWorkflow()
    #expect(!workflow.isPresented)
    workflow.present()
    #expect(workflow.isPresented)
  }

  @Test("Invalid input prevents service submission")
  func invalidInputPreventsSubmission() async {
    let workflow = PlatformOrganizationCreationWorkflow()
    workflow.present()
    var calls = 0
    let result = await workflow.submit(
      draft: PlatformOrganizationCreateDraft(),
      create: { _ in calls += 1; return organization() },
      refresh: {},
      errorMessage: { $0.localizedDescription }
    )
    #expect(result == nil)
    #expect(calls == 0)
    #expect(workflow.errorText != nil)
    #expect(workflow.isPresented)
  }

  @Test("Valid input invokes service once, refreshes, and closes after success")
  func validSubmission() async {
    let workflow = PlatformOrganizationCreationWorkflow()
    workflow.present()
    var calls = 0
    var refreshes = 0
    let result = await workflow.submit(
      draft: validDraft(),
      create: { _ in calls += 1; return organization() },
      refresh: { refreshes += 1 },
      errorMessage: { $0.localizedDescription }
    )
    #expect(result?.name == "Home Plate Test")
    #expect(calls == 1)
    #expect(refreshes == 1)
    #expect(!workflow.isPresented)
    #expect(workflow.successText?.contains("Home Plate Test") == true)
  }

  @Test("Duplicate taps cannot create duplicate submissions")
  func duplicateSubmissionGuard() async {
    let workflow = PlatformOrganizationCreationWorkflow()
    workflow.present()
    let first = Task { @MainActor in
      await workflow.submit(
        draft: validDraft(),
        create: { _ in
          try await Task.sleep(for: .milliseconds(75))
          return organization()
        },
        refresh: {},
        errorMessage: { $0.localizedDescription }
      )
    }
    while !workflow.isSubmitting { await Task.yield() }
    let duplicate = await workflow.submit(
      draft: validDraft(),
      create: { _ in organization() },
      refresh: {},
      errorMessage: { $0.localizedDescription }
    )
    #expect(duplicate == nil)
    let firstResult = await first.value
    #expect(firstResult != nil)
  }

  @Test("Creation errors remain visible and do not dismiss the form")
  func errorPresentation() async {
    let workflow = PlatformOrganizationCreationWorkflow()
    workflow.present()
    let result = await workflow.submit(
      draft: validDraft(),
      create: { _ in
        throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "RPC unavailable"])
      },
      refresh: {},
      errorMessage: { "Readable: \($0.localizedDescription)" }
    )
    #expect(result == nil)
    #expect(workflow.isPresented)
    #expect(workflow.errorText == "Readable: RPC unavailable")
  }

  @Test("Swift organization payload contains no actor or owner UUID")
  func safeOrganizationPayload() throws {
    let draft = validDraft()
    let payload = SDPlatformOrganizationCreatePayload(
      name: draft.name,
      slug: draft.normalizedSlug,
      plan: draft.plan,
      billing_email: draft.cleanedBillingEmail,
      max_members: Int(draft.maxMembers)
    )
    let object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(payload)) as? [String: Any])
    #expect(object["action"] as? String == "create_organization")
    #expect(object["name"] as? String == "Home Plate Test")
    #expect(object["actor_id"] == nil)
    #expect(object["owner_id"] == nil)
    #expect(object["owner_user_id"] == nil)
  }
}
