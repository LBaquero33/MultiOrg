import Testing
@testable import HomePlate

struct GameScoringInteractionTests {
  @Test func viewerCannotMutate() {
    #expect(!SDLiveScoringAccess.mutationEnabled(
      authorizationAllowsScoring: true, controlState: .viewer
    ))
  }

  @Test func authorizationAndLeaseAreBothRequired() {
    #expect(!SDLiveScoringAccess.mutationEnabled(
      authorizationAllowsScoring: false, controlState: .scorekeeper(expiresAt: nil)
    ))
    #expect(SDLiveScoringAccess.mutationEnabled(
      authorizationAllowsScoring: true, controlState: .scorekeeper(expiresAt: nil)
    ))
  }

  @Test func pendingBallRequiresOutcome() {
    var pending = SDPendingBattedBall()
    #expect(!pending.canCommit)
    pending.outcome = .single
    #expect(pending.canCommit)
  }
}
