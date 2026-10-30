import Foundation
@main struct NativeContractHarness {
  static func main() throws {
    try testDeepLinks(); try testOrganizationRoles(); try testScoringJournal(); try testRecoveryPolicies()
    print("PASS: deep links, selected-org roles, durable journal, restart reconciliation, and recovery policies")
  }
  static func expect(_ value: @autoclosure () -> Bool, _ message: String) throws {
    if !value() { throw HarnessFailure.assertion(message) }
  }
  static func testDeepLinks() throws {
    let event = HPCalendarLinkRoute(url: URL(string: "homeplate://calendar/event/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa?organization=bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb")!)
    try expect(event?.source == .event && event?.organizationId == UUID(uuidString: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"), "event route")
    let booking = HPCalendarLinkRoute(url: URL(string: "homeplate://calendar/booking/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa?organization=bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb")!)
    try expect(booking?.source == .booking, "booking route")
    try expect(HPCalendarLinkRoute(url: URL(string: "homeplate://calendar/event/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa?organization=bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb&ORGANIZATION=cccccccc-cccc-4ccc-8ccc-cccccccccccc")!) == nil, "calendar duplicate query rejected")
    try expect(HPCalendarLinkRoute(url: URL(string: "homeplate://calendar/event/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa/extra?organization=bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb")!) == nil, "calendar invalid path rejected")
    let team = HPTeamWorkspaceRoute(url: URL(string: "homeplate://team/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa?organization_id=bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb")!)
    try expect(team?.teamId == UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"), "team route")
    try expect(HPTeamWorkspaceRoute(url: URL(string: "homeplate://team/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa/extra?organization_id=bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb")!) == nil, "team invalid path rejected")
    try expect(HPTeamWorkspaceRoute(url: URL(string: "homeplate://team?organization_id=bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb&ORGANIZATION_ID=cccccccc-cccc-4ccc-8ccc-cccccccccccc&team_id=aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")!) == nil, "team duplicate query rejected")
    let parent = SDParentInviteRedemption(url: URL(string: "homeplate://parent-invite/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa?token=0123456789abcdef0123456789abcdef")!)
    try expect(parent?.token == "0123456789abcdef0123456789abcdef", "parent invite token")
    try expect(SDParentInviteRedemption(url: URL(string: "homeplate://parent-invite/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa?token=bad")!) == nil, "invalid parent token rejected")
    try expect(SDParentInviteRedemption(url: URL(string: "homeplate://parent-invite/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa?token=0123456789abcdef0123456789abcdef&TOKEN=0123456789abcdef0123456789abcdef")!) == nil, "duplicate parent token rejected")
  }
  static func testOrganizationRoles() throws {
    let user = UUID(), coachOrg = UUID(), parentOrg = UUID()
    let memberships = [
      SDOrgMembership(org_id: coachOrg, user_id: user, role: "coach", status: "active", created_at: nil, created_by: nil),
      SDOrgMembership(org_id: parentOrg, user_id: user, role: "parent", status: "active", created_at: nil, created_by: nil),
    ]
    let coach = OrganizationAuthorization.activeMembership(userId: user, orgId: coachOrg, memberships: memberships)
    let parent = OrganizationAuthorization.activeMembership(userId: user, orgId: parentOrg, memberships: memberships)
    try expect(SDChatAuthorization.canComposeAnnouncement(membership: coach), "coach capability")
    try expect(!SDChatAuthorization.canComposeAnnouncement(membership: parent), "parent has no inherited coach capability")
  }
  static func testScoringJournal() throws {
    let org = UUID(), game = UUID(), actor = UUID(), device = UUID()
    let base = SDGameState(), rules = SDResolvedBaseballRules()
    var journal = SDGameScoringJournal(organizationId: org, gameId: game, actorUserId: actor, deviceId: device, authorityVerifiedAt: Date(), authorityEpoch: 9, baseServerVersion: 0, baseState: base, commands: [], conflictReason: nil)
    journal.enqueue(events: [(.pitchThrown, [:]), (.pitchResultRecorded, ["result": .string("called_strike")])])
    try expect(journal.commands.count == 1 && journal.commands[0].events.count == 2, "pitch and result form one command")
    let commandId = journal.commands[0].id, eventIds = journal.commands[0].events.map(\.id)
    let store = SDGameScoringJournalStore(rootDirectory: URL(fileURLWithPath: "work/remediation/native-journal-testdata", isDirectory: true))
    try store.save(journal)
    guard let reopened = try store.load(organizationId: org, gameId: game, deviceId: device) else { throw HarnessFailure.assertion("journal load") }
    try expect(reopened.commands.first?.id == commandId && reopened.commands.first?.events.map(\.id) == eventIds, "stable persisted command and event IDs")
    let projection = try reopened.projection(from: base, rules: rules)
    try expect(projection.version == 2 && projection.pitchCount == 1 && projection.strikes == 1, "provisional reducer projection")
    var invalid = SDGameScoringJournal(organizationId: org, gameId: game, actorUserId: actor, deviceId: device, authorityVerifiedAt: Date(), authorityEpoch: 9, baseServerVersion: 0, baseState: base, commands: [], conflictReason: nil)
    invalid.enqueue(events: [(.pitchResultRecorded, [:]), (.pitchThrown, [:])])
    try expect(invalid.hasConflict && invalid.commands.isEmpty, "invalid compound command freezes")
    let command = reopened.commands[0]
    let accepted = command.events.enumerated().map { index, value in
      SDScoringEvent(id: value.id, org_id: org, game_id: game, game_version: index + 1, sequence: index + 1, event_type: value.type, actor_user_id: actor, actor_device_id: device, occurred_at: command.createdAt, payload: value.payload, ruleset_version: nil, idempotency_key: "native:\(command.id.uuidString.lowercased()):\(index)", correction_of_event_id: nil, supersedes_event_id: nil)
    }
    let serverState = try SDGameReducer.replay(accepted, rules: rules)
    var afterRestart = reopened
    try afterRestart.reconcilePersistedCommands(against: accepted, serverState: serverState, rules: rules)
    try expect(afterRestart.commands.isEmpty && afterRestart.baseServerVersion == 2 && afterRestart.baseState == serverState, "restart reconciles exactly accepted event IDs")
    var diverged = reopened; var newerHead = serverState; newerHead.version += 1
    do { try diverged.reconcilePersistedCommands(against: [], serverState: newerHead, rules: rules); throw HarnessFailure.assertion("diverged server head accepted") }
    catch SDGameScoringJournalError.serverHeadChanged { }
    try store.remove(organizationId: org, gameId: game, deviceId: device)
  }
  static func testRecoveryPolicies() throws {
    let offline = URLError(.notConnectedToInternet)
    let wrapped = NSError(domain: "test.transport", code: 1, userInfo: [NSUnderlyingErrorKey: offline])
    let forbidden = NSError(domain: "test.authorization", code: 403)
    try expect(SDScorekeepingFailureDisposition.classify(offline) == .retryTransport, "offline failure preserves provisional journal")
    try expect(SDScorekeepingFailureDisposition.classify(wrapped) == .retryTransport, "wrapped offline failure preserves provisional journal")
    try expect(SDScorekeepingFailureDisposition.classify(forbidden) == .freezeForReview, "authoritative failure freezes for review")
    try expect(SDLegacyScoringCommandPolicy.canSendOnlineOnly(eventCount: 1), "legacy single-event command remains supported")
    try expect(!SDLegacyScoringCommandPolicy.canSendOnlineOnly(eventCount: 2), "legacy compound command blocked before partial write")
  }
}
enum HarnessFailure: Error { case assertion(String) }
