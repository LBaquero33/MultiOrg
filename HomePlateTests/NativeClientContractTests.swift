import Foundation
import Testing
@testable import HomePlate

@Suite("Cross-platform native client contracts")
struct NativeClientContractTests {
  @Test("Calendar links require a unique query key and an explicit organization")
  func calendarLinkValidation() {
    let valid = HPCalendarLinkRoute(url: URL(string:
      "homeplate://calendar/event/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa?organization=bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"
    )!)
    #expect(valid?.source == .event)
    #expect(valid?.organizationId == UUID(uuidString: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"))
    #expect(HPCalendarLinkRoute(url: URL(string:
      "homeplate://calendar/event/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa?organization=bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb&ORGANIZATION=cccccccc-cccc-4ccc-8ccc-cccccccccccc"
    )!) == nil)
  }

  @Test("Parent invitation redemption requires an id and opaque token")
  func parentInviteLinkValidation() {
    #expect(SDParentInviteRedemption(url: URL(string:
      "homeplate://parent-invite/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa?token=0123456789abcdef0123456789abcdef"
    )!) != nil)
    #expect(SDParentInviteRedemption(url: URL(string:
      "homeplate://parent-invite/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa?token=bad"
    )!) == nil)
  }

  @Test("Announcement controls derive authority from the selected organization")
  func organizationScopedAnnouncementAuthority() {
    let userId = UUID()
    let organizationA = UUID()
    let organizationB = UUID()
    func membership(_ organization: UUID, _ role: String) -> SDOrgMembership {
      SDOrgMembership(
        org_id: organization, user_id: userId, role: role, status: "active",
        created_at: nil, created_by: nil
      )
    }
    let memberships = [membership(organizationA, "coach"), membership(organizationB, "parent")]
    let coach = OrganizationAuthorization.activeMembership(
      userId: userId, orgId: organizationA, memberships: memberships
    )
    let parent = OrganizationAuthorization.activeMembership(
      userId: userId, orgId: organizationB, memberships: memberships
    )
    #expect(SDChatAuthorization.canComposeAnnouncement(membership: coach))
    #expect(!SDChatAuthorization.canComposeAnnouncement(membership: parent))
  }

  @Test("Offline scoring journals preserve command and event IDs as provisional state")
  func durableScoringJournalProjection() throws {
    let organizationId = UUID()
    let gameId = UUID()
    let actorId = UUID()
    let deviceId = UUID()
    let base = SDGameState()
    var journal = SDGameScoringJournal(
      organizationId: organizationId, gameId: gameId, actorUserId: actorId,
      deviceId: deviceId, authorityVerifiedAt: Date(), authorityEpoch: 7,
      baseServerVersion: base.version, baseState: base, commands: [], conflictReason: nil
    )
    journal.enqueue(events: [
      (.pitchThrown, [:]),
      (.pitchResultRecorded, ["result": .string("called_strike")]),
    ])
    let encoded = try JSONEncoder().encode(journal)
    let reopened = try JSONDecoder().decode(SDGameScoringJournal.self, from: encoded)
    #expect(reopened.commands.map(\.id) == journal.commands.map(\.id))
    #expect(reopened.commands.flatMap(\.events).map(\.id) == journal.commands.flatMap(\.events).map(\.id))
    let projected = try reopened.projection(from: base, rules: SDResolvedBaseballRules())
    #expect(projected.version == 2)
    #expect(projected.pitchCount == 1)
    #expect(projected.strikes == 1)
  }

  @Test("Journal rejects non-atomic compound scoring actions")
  func invalidCompoundJournalCommandIsFrozen() {
    var journal = SDGameScoringJournal(
      organizationId: UUID(), gameId: UUID(), actorUserId: UUID(), deviceId: UUID(),
      authorityVerifiedAt: Date(), authorityEpoch: 1, baseServerVersion: 0,
      baseState: SDGameState(), commands: [], conflictReason: nil
    )
    journal.enqueue(events: [(.pitchResultRecorded, [:]), (.pitchThrown, [:])])
    #expect(journal.hasConflict)
    #expect(journal.commands.isEmpty)
  }

  @Test("Journal reconciles a committed command after a process restart")
  func reconcileAmbiguousAcceptance() throws {
    let organizationId = UUID()
    let gameId = UUID()
    let actorId = UUID()
    let deviceId = UUID()
    let base = SDGameState()
    var journal = SDGameScoringJournal(
      organizationId: organizationId, gameId: gameId, actorUserId: actorId,
      deviceId: deviceId, authorityVerifiedAt: Date(), authorityEpoch: 3,
      baseServerVersion: 0, baseState: base, commands: [], conflictReason: nil
    )
    journal.enqueue(events: [(.pitchThrown, [:])])
    let command = try #require(journal.commands.first)
    let queued = try #require(command.events.first)
    let event = SDScoringEvent(
      id: queued.id, org_id: organizationId, game_id: gameId,
      game_version: 1, sequence: 1, event_type: queued.type,
      actor_user_id: actorId, actor_device_id: deviceId, occurred_at: command.createdAt,
      payload: queued.payload, ruleset_version: nil,
      idempotency_key: "native:\(command.id.uuidString.lowercased()):0",
      correction_of_event_id: nil, supersedes_event_id: nil
    )
    var serverState = base
    serverState.version = 1
    serverState.pitchCount = 1
    try journal.reconcilePersistedCommands(
      against: [event], serverState: serverState, rules: SDResolvedBaseballRules()
    )
    #expect(journal.commands.isEmpty)
    #expect(journal.baseServerVersion == 1)
    #expect(journal.baseState == serverState)
  }
}
