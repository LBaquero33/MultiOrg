import Testing
@testable import MultiOrg

struct GameRulesetTests {
  @Test func hierarchyResolvesDeterministically() {
    let rules = SDResolvedBaseballRules.resolve([
      ["scheduled_innings": .int(9), "defender_count": .int(9)],
      ["scheduled_innings": .int(6), "continuous_batting": .bool(true)],
      ["run_cap": .int(5), "outfielder_count": .int(4)],
    ])
    #expect(rules.scheduledInnings == 6)
    #expect(rules.runCap == 5)
    #expect(rules.continuousBatting)
    #expect(rules.defenderCount == 9)
    #expect(rules.outfielderCount == 4)
  }

  @Test(arguments: [(9, 9), (7, 9), (6, 10), (5, 8)])
  func representativeCompetitionShapes(innings: Int, defenders: Int) {
    let rules = SDResolvedBaseballRules.resolve([
      ["scheduled_innings": .int(innings), "defender_count": .int(defenders)]
    ])
    #expect(rules.scheduledInnings == innings)
    #expect(rules.defenderCount == defenders)
  }
}
