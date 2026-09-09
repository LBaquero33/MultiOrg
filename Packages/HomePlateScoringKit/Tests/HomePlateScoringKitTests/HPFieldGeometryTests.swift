import CoreGraphics
import HomePlateScoringCore
@testable import HomePlateScoringUI
import XCTest

final class HPFieldGeometryTests: XCTestCase {
  private let compactCanvas = CGSize(width: 393, height: 393 / 0.88)

  func testCompactBaseCoordinatesExposeTheSpecifiedEnlargedDiamond() {
    XCTAssertEqual(HPFieldGeometry.home, HPNormalizedPoint(x: 0.50, y: 0.88))
    XCTAssertEqual(HPFieldGeometry.firstBase, HPNormalizedPoint(x: 0.78, y: 0.64))
    XCTAssertEqual(HPFieldGeometry.secondBase, HPNormalizedPoint(x: 0.50, y: 0.40))
    XCTAssertEqual(HPFieldGeometry.thirdBase, HPNormalizedPoint(x: 0.22, y: 0.64))
    XCTAssertEqual(HPFieldGeometry.firstBase.x - HPFieldGeometry.thirdBase.x, 0.56, accuracy: 0.000_001)
  }

  func testRightFoulEndpointIsCollinearWithHomeAndFirstBase() {
    let geometry = HPFieldGeometry()
    XCTAssertEqual(geometry.rightFoulEndpoint.x, 1, accuracy: 0.000_001)
    XCTAssertEqual(crossProduct(
      origin: HPFieldGeometry.home,
      middle: HPFieldGeometry.firstBase,
      endpoint: geometry.rightFoulEndpoint
    ), 0, accuracy: 0.000_001)
  }

  func testLeftFoulEndpointIsCollinearWithHomeAndThirdBase() {
    let geometry = HPFieldGeometry()
    XCTAssertEqual(geometry.leftFoulEndpoint.x, 0, accuracy: 0.000_001)
    XCTAssertEqual(crossProduct(
      origin: HPFieldGeometry.home,
      middle: HPFieldGeometry.thirdBase,
      endpoint: geometry.leftFoulEndpoint
    ), 0, accuracy: 0.000_001)
  }

  func testEveryBaseFoulEndpointAndDefensiveMarkerIsInsideCanvas() {
    for layout in HPFieldLayout.allCases {
      let geometry = HPFieldGeometry(layout: layout)
      let points = [
        HPFieldGeometry.home,
        HPFieldGeometry.firstBase,
        HPFieldGeometry.secondBase,
        HPFieldGeometry.thirdBase,
        geometry.leftFoulEndpoint,
        geometry.rightFoulEndpoint,
      ] + Array(geometry.defensivePositions.values)

      for point in points {
        XCTAssertTrue(point.isInsideCanvas, "\(point) escaped the \(layout.rawValue) canvas")
      }
    }
  }

  func testInteractiveTargetsRemainAtLeast44PointsAndInsideCanvas() {
    let canvases: [(HPFieldLayout, CGSize)] = [
      (.compactPortrait, compactCanvas),
      (.regularPortrait, CGSize(width: 768, height: 768)),
      (.regularLandscape, CGSize(width: 1024, height: 800)),
    ]

    for (layout, size) in canvases {
      let geometry = HPFieldGeometry(layout: layout)
      let points = [
        HPFieldGeometry.home,
        HPFieldGeometry.firstBase,
        HPFieldGeometry.secondBase,
        HPFieldGeometry.thirdBase,
      ] + Array(geometry.defensivePositions.values)

      for point in points {
        let target = geometry.hitTargetRect(centeredAt: point, in: size)
        XCTAssertEqual(target.width, 44, accuracy: 0.000_001)
        XCTAssertEqual(target.height, 44, accuracy: 0.000_001)
        XCTAssertGreaterThanOrEqual(target.minX, 0)
        XCTAssertGreaterThanOrEqual(target.minY, 0)
        XCTAssertLessThanOrEqual(target.maxX, size.width)
        XCTAssertLessThanOrEqual(target.maxY, size.height)
      }
    }
  }

  func testPhotoMarkersClearAllBasesAtCompactAcceptanceSize() {
    let geometry = HPFieldGeometry(layout: .compactPortrait)
    let basePoints = [
      HPFieldGeometry.home,
      HPFieldGeometry.firstBase,
      HPFieldGeometry.secondBase,
      HPFieldGeometry.thirdBase,
    ]
    let requiredCenterSpacing = (
      HPFieldGeometry.markerVisualDiameter + HPFieldGeometry.baseVisualDiameter
    ) / 2 + HPFieldGeometry.minimumMarkerToBaseClearance

    for (position, normalizedMarker) in geometry.defensivePositions {
      let marker = geometry.canvasPoint(normalizedMarker, in: compactCanvas)
      for normalizedBase in basePoints {
        let base = geometry.canvasPoint(normalizedBase, in: compactCanvas)
        XCTAssertGreaterThanOrEqual(
          hypot(marker.x - base.x, marker.y - base.y),
          requiredCenterSpacing,
          "\(position.rawValue) overlaps a neighboring base beyond the allowed padding"
        )
      }
    }
  }

  func testLayoutAspectRatiosMatchAdaptiveDesignContract() {
    XCTAssertEqual(HPFieldLayout.compactPortrait.aspectRatio, 0.88, accuracy: 0.000_001)
    XCTAssertEqual(HPFieldLayout.regularPortrait.aspectRatio, 1.0, accuracy: 0.000_001)
    XCTAssertEqual(HPFieldLayout.regularLandscape.aspectRatio, 1.28, accuracy: 0.000_001)
  }

  func testCompactChromeAndFieldMeetAcceptanceMeasurements() {
    XCTAssertLessThanOrEqual(HPGameDayLayoutMetrics.scoreboardHeight, 96)
    XCTAssertLessThanOrEqual(HPGameDayLayoutMetrics.accessibilityScoreboardHeight, 112)
    XCTAssertEqual(HPGameDayLayoutMetrics.commandBarHeight, 44)
    XCTAssertEqual(HPGameDayLayoutMetrics.matchupHeight, 52)
    XCTAssertEqual(HPGameDayLayoutMetrics.scoringDockHeight, 72)
    XCTAssertEqual(HPGameDayLayoutMetrics.actionRailWidth, 350)
    XCTAssertGreaterThanOrEqual(
      HPGameDayLayoutMetrics.compactFieldHeight(atScreenWidth: 393),
      390
    )
  }

  func testCanvasRoundTripDoesNotDrift() {
    let geometry = HPFieldGeometry()
    let canvasPoint = geometry.canvasPoint(HPFieldGeometry.firstBase, in: compactCanvas)
    XCTAssertEqual(
      geometry.normalizedPoint(for: canvasPoint, in: compactCanvas),
      HPFieldGeometry.firstBase
    )
  }

  func testBallInPlayFlowContainsOnlyContactResultAndFielders() {
    XCTAssertEqual(BallInPlayStep.allCases, [.contact, .result, .fielders])
    XCTAssertNil(BallInPlayCommand(contact: .groundBall, result: .single).location)
  }

  func testPendingRunnerMovementReplacesEarlierDragForSameRunner() {
    let runner = RunnerState(
      playerID: UUID(),
      base: .first,
      responsiblePitcherID: UUID()
    )
    var draft = BallInPlayDraft()
    draft.appendRunnerResolution(.init(
      playerID: runner.playerID,
      fromBase: .first,
      toBase: .second,
      reason: .battedBall,
      responsiblePitcherID: runner.responsiblePitcherID
    ))
    draft.appendRunnerResolution(.init(
      playerID: runner.playerID,
      fromBase: .second,
      toBase: .third,
      reason: .battedBall,
      responsiblePitcherID: runner.responsiblePitcherID
    ))

    XCTAssertEqual(draft.runnerResolutions.count, 1)
    XCTAssertEqual(draft.runnerResolutions[0].fromBase, .first)
    XCTAssertEqual(draft.runnerResolutions[0].toBase, .third)
  }

  func testThirdOutRequiresConfirmationButEarlierPitchDoesNot() throws {
    let seed = DemoGame.seed
    let rules = GameRulesProfile.nfhs
    var events: [ScoringEvent] = []

    func append(_ command: ScoringCommand) throws {
      let play = try ScoringEngine.makePlay(
        command: command,
        seed: seed,
        rules: rules,
        events: events
      )
      events.append(contentsOf: play.events)
    }

    try append(.startGame)
    for _ in 0..<2 {
      for _ in 0..<3 { try append(.recordPitch(.calledStrike)) }
    }
    try append(.recordPitch(.calledStrike))
    try append(.recordPitch(.calledStrike))
    let projection = try ScoringEngine.replay(seed: seed, rules: rules, events: events)

    XCTAssertNil(try HalfInningConfirmationPolicy.preview(
      command: .recordPitch(.ball),
      label: "Ball",
      projection: projection,
      seed: seed,
      rules: rules,
      events: events,
      authorityEpoch: 1
    ))
    let pending = try HalfInningConfirmationPolicy.preview(
      command: .recordPitch(.calledStrike),
      label: "Called Strike",
      projection: projection,
      seed: seed,
      rules: rules,
      events: events,
      authorityEpoch: 1
    )
    XCTAssertEqual(pending?.currentLabel, "Top 1")
    XCTAssertEqual(pending?.nextLabel, "Bottom 1")
  }

  private func crossProduct(
    origin: HPNormalizedPoint,
    middle: HPNormalizedPoint,
    endpoint: HPNormalizedPoint
  ) -> CGFloat {
    (middle.x - origin.x) * (endpoint.y - origin.y)
      - (middle.y - origin.y) * (endpoint.x - origin.x)
  }
}
