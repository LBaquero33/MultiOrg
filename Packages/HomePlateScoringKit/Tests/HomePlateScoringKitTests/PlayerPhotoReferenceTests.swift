import Foundation
import HomePlateScoringCore
import XCTest

final class PlayerPhotoReferenceTests: XCTestCase {
  func testPlayerDecodesLegacyPayloadWithoutPhotoReference() throws {
    let legacyJSON = Data(
      """
      {
        "id": "8A20FFB1-1097-492B-A2CA-6D73F2BB0E0A",
        "firstName": "Legacy",
        "lastName": "Player",
        "jerseyNumber": "17",
        "bats": "R",
        "throwsHand": "L",
        "isPlaceholder": false
      }
      """.utf8
    )

    let player = try JSONDecoder().decode(Player.self, from: legacyJSON)

    XCTAssertEqual(player.displayName, "Legacy Player")
    XCTAssertNil(player.photo)
  }

  func testPlayerPhotoReferenceRoundTripsAllSources() throws {
    let player = Player(
      id: UUID(uuidString: "8A20FFB1-1097-492B-A2CA-6D73F2BB0E0A")!,
      firstName: "Casey",
      lastName: "Rivera",
      jerseyNumber: "8",
      bats: .switchHitter,
      throwsHand: .right,
      photo: .init(
        bundledAssetName: "hp_headshot_08",
        remoteURL: URL(string: "https://example.invalid/players/casey-rivera.jpg"),
        cacheKey: "player-8-v2"
      )
    )

    let decoded = try JSONDecoder().decode(
      Player.self,
      from: JSONEncoder().encode(player)
    )

    XCTAssertEqual(decoded, player)
    XCTAssertEqual(decoded.photo?.bundledAssetName, "hp_headshot_08")
    XCTAssertEqual(decoded.photo?.cacheKey, "player-8-v2")
  }

  func testDemoRostersUseTwentyDistinctBundledHeadshots() {
    let players =
      DemoGame.seed.away.lineup.map(\.player)
      + DemoGame.seed.away.bench
      + DemoGame.seed.home.lineup.map(\.player)
      + DemoGame.seed.home.bench
    let names = players.compactMap { $0.photo?.bundledAssetName }

    XCTAssertEqual(players.count, 20)
    XCTAssertEqual(names.count, players.count)
    XCTAssertEqual(Set(names).count, players.count)
    XCTAssertEqual(Set(names), Set((1...20).map { String(format: "hp_headshot_%02d", $0) }))
  }
}
