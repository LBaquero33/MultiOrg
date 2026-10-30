import XCTest
@testable import HomePlateScoringCore

final class GameVideoTimingTests: XCTestCase {
  func testMonotonicClockIgnoresWallClockAndTracksUncertainty() throws {
    let anchor = try GameVideoClockAnchor(serverDate: Date(timeIntervalSince1970: 100), sent: 10, received: 10.2)
    let time = try anchor.timestamp(at: 20.2)
    XCTAssertEqual(time.enteredAt.timeIntervalSince1970, 110.1, accuracy: 0.0001)
    XCTAssertEqual(time.uncertaintyMilliseconds!, 101, accuracy: 0.0001)
    XCTAssertThrowsError(try anchor.timestamp(at: 0))
  }
  func testAdministrativeCorrectionDoesNotCreateBoundary() {
    let event = ScoringEvent(gameID: UUID(), playID: UUID(), commandID: UUID(), authorityEpoch: 1, sequence: 1, rulesVersion: 1,
      payload: .playVoided(targetPlayID: UUID(), reason: "Correction"))
    let play = ScoringPlay(id: event.playID, commandID: event.commandID, summary: "Undo", events: [event])
    XCTAssertNil(GameVideoCaptureMarker.make(play: play, timestamp: .init(enteredAt: Date(), uncertaintyMilliseconds: nil)))
  }
  func testPitchMarkersBecomeOneCompletedClipOnWalkAndStrikeout() throws {
    for (pitch, count) in [(PitchResult.ball, 4), (.calledStrike, 3)] {
      var events = try ScoringEngine.makePlay(command: .startGame, seed: DemoGame.seed, rules: .nfhs, events: []).events
      for number in 1...count {
        let date = Date(timeIntervalSince1970: Double(number) * 10)
        let play = try ScoringEngine.makePlay(command: .recordPitch(pitch), seed: DemoGame.seed, rules: .nfhs, events: events, now: date)
        let marker = try XCTUnwrap(GameVideoCaptureMarker.make(play: play, timestamp: .init(enteredAt: date, uncertaintyMilliseconds: 5)))
        XCTAssertEqual(marker.completedPlay, number == count)
        XCTAssertEqual(marker.playID, play.id)
        XCTAssertEqual(marker.timestamp.enteredAt, date)
        events += play.events
      }
    }
  }
}
