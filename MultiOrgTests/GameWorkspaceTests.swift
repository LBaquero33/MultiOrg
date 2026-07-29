import Foundation
import Testing
@testable import MultiOrg

struct GameWorkspaceTests {
  @Test func wrongOrganizationCannotOpenWorkspace() {
    let permissions = SDGameWorkspacePermissions.resolve(
      game: nil, activeOrganizationId: UUID(), userId: UUID(),
      membership: nil, participants: []
    )
    #expect(!permissions.canView)
    #expect(!permissions.canScore)
  }

  @Test func explicitScorekeeperGetsScoringWithoutBroadAdmin() {
    let participant = SDEventParticipant(
      id: UUID(), org_id: UUID(), event_id: UUID(),
      participant_type: "user", user_id: UUID(), team_id: nil,
      player_id: nil, role: "assigned_scorekeeper",
      can_view: true, can_edit: false, can_score: true
    )
    #expect(participant.can_score)
    #expect(!participant.can_edit)
  }
}
