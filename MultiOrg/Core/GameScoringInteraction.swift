import Foundation

enum SDBattedBallOutcome: String, CaseIterable, Identifiable, Sendable {
  case single, double, triple
  case homeRun = "home_run"
  case error, fieldersChoice = "fielders_choice", out

  var id: String { rawValue }
  var title: String { rawValue.replacingOccurrences(of: "_", with: " ").capitalized }
}

struct SDPendingBattedBall: Equatable, Sendable {
  var outcome: SDBattedBallOutcome?
  var fieldingSequence: [String] = []
  var note = ""

  var canCommit: Bool { outcome != nil }
}

enum SDLiveScoringAccess {
  static func mutationEnabled(
    authorizationAllowsScoring: Bool,
    controlState: SDScorekeeperControlState
  ) -> Bool {
    authorizationAllowsScoring && controlState.canMutate
  }
}
