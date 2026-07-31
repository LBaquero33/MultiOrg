import Foundation

enum SDGameWorkspaceSection: String, CaseIterable, Identifiable, Sendable {
  case overview = "Overview"
  case roster = "Roster"
  case availability = "Availability"
  case lineup = "Lineup"
  case rules = "Rules"
  case liveScore = "Live Score"
  case playByPlay = "Play-by-Play"
  case boxScore = "Box Score"
  case playerStats = "Player Stats"
  case gameNotes = "Game Notes"
  case postgameReview = "Postgame Review"
  var id: String { rawValue }
}

struct SDGameWorkspacePermissions: Equatable, Sendable {
  let canView: Bool
  let canManage: Bool
  let canScore: Bool
  let canFinalize: Bool

  static func resolve(
    game: SDGame?,
    activeOrganizationId: UUID?,
    userId: UUID?,
    membership: SDOrgMembership?,
    participants: [SDEventParticipant]
  ) -> Self {
    guard let game, game.org_id == activeOrganizationId else {
      return .init(canView: false, canManage: false, canScore: false, canFinalize: false)
    }
    let admin = membership?.org_id == game.org_id &&
      membership?.isActive == true &&
      membership?.canAdministerOrganization == true
    let participant = participants.first {
      $0.user_id == userId && $0.event_id == game.event_id
    }
    return .init(
      canView: admin || participant?.can_view == true,
      canManage: admin || participant?.can_edit == true,
      canScore: admin || participant?.can_score == true,
      canFinalize: admin || participant?.role == "assigned_scorekeeper"
    )
  }
}
