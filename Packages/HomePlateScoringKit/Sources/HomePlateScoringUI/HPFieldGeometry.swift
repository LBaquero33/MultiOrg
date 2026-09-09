import CoreGraphics
import HomePlateScoringCore

/// The presentation modes supported by the game-day field.
///
/// `aspectRatio` is expressed as width divided by height so it can be passed
/// directly to SwiftUI's `aspectRatio(_:contentMode:)` modifier.
public enum HPFieldLayout: String, CaseIterable, Sendable {
  case compactPortrait
  case regularPortrait
  case regularLandscape

  public var aspectRatio: CGFloat {
    switch self {
    case .compactPortrait: 0.88
    case .regularPortrait: 1.0
    case .regularLandscape: 1.28
    }
  }
}

/// A canvas-independent coordinate in the closed 0...1 field coordinate space.
public struct HPNormalizedPoint: Hashable, Sendable {
  public let x: CGFloat
  public let y: CGFloat

  public init(x: CGFloat, y: CGFloat) {
    self.x = x
    self.y = y
  }

  public var isInsideCanvas: Bool {
    (0...1).contains(x) && (0...1).contains(y)
  }

  public func point(in size: CGSize) -> CGPoint {
    CGPoint(x: x * size.width, y: y * size.height)
  }
}

/// One deterministic source for every point used by field artwork and interaction.
///
/// The base coordinates intentionally make the visible infield 56% of the canvas
/// width. Foul endpoints are derived from the home-to-corner-base rays, which keeps
/// the painted line, base, runner anchor, and batted-ball coordinate system aligned.
public struct HPFieldGeometry: Sendable {
  public static let home = HPNormalizedPoint(x: 0.50, y: 0.88)
  public static let firstBase = HPNormalizedPoint(x: 0.78, y: 0.64)
  public static let secondBase = HPNormalizedPoint(x: 0.50, y: 0.40)
  public static let thirdBase = HPNormalizedPoint(x: 0.22, y: 0.64)

  /// The visible photo treatment is 38 points, while the tappable target remains 44.
  public static let markerVisualDiameter: CGFloat = 38
  public static let baseVisualDiameter: CGFloat = 18
  public static let minimumInteractiveTarget: CGFloat = 44
  public static let minimumMarkerToBaseClearance: CGFloat = 4

  public let layout: HPFieldLayout

  public init(layout: HPFieldLayout = .compactPortrait) {
    self.layout = layout
  }

  public var aspectRatio: CGFloat { layout.aspectRatio }

  public func basePoint(_ base: Base) -> HPNormalizedPoint {
    switch base {
    case .first: Self.firstBase
    case .second: Self.secondBase
    case .third: Self.thirdBase
    }
  }

  /// The point where the home-to-third ray reaches the left canvas boundary.
  public var leftFoulEndpoint: HPNormalizedPoint {
    Self.rayEndpoint(from: Self.home, through: Self.thirdBase, boundaryX: 0)
  }

  /// The point where the home-to-first ray reaches the right canvas boundary.
  public var rightFoulEndpoint: HPNormalizedPoint {
    Self.rayEndpoint(from: Self.home, through: Self.firstBase, boundaryX: 1)
  }

  /// Positions are intentionally separated from the enlarged base anchors so a
  /// 38-point photo marker remains readable without covering a base on the
  /// canonical 393-point compact field.
  public var defensivePositions: [DefensivePosition: HPNormalizedPoint] {
    [
      .pitcher: HPNormalizedPoint(x: 0.50, y: 0.63),
      // Offset the catcher slightly into foul territory so the photo, home
      // plate, and batter's boxes remain independently readable.
      .catcher: HPNormalizedPoint(x: 0.61, y: 0.92),
      .firstBase: HPNormalizedPoint(x: 0.83, y: 0.51),
      .secondBase: HPNormalizedPoint(x: 0.65, y: 0.49),
      .shortstop: HPNormalizedPoint(x: 0.35, y: 0.49),
      .thirdBase: HPNormalizedPoint(x: 0.17, y: 0.51),
      .leftField: HPNormalizedPoint(x: 0.19, y: 0.31),
      .centerField: HPNormalizedPoint(x: 0.50, y: 0.22),
      .rightField: HPNormalizedPoint(x: 0.81, y: 0.31),
    ]
  }

  public func defensivePoint(_ position: DefensivePosition) -> HPNormalizedPoint? {
    defensivePositions[position]
  }

  public func canvasPoint(_ point: HPNormalizedPoint, in size: CGSize) -> CGPoint {
    point.point(in: size)
  }

  public func canvasPoint(for base: Base, in size: CGSize) -> CGPoint {
    basePoint(base).point(in: size)
  }

  public func normalizedPoint(for point: CGPoint, in size: CGSize, clamped: Bool = true) -> HPNormalizedPoint {
    guard size.width > 0, size.height > 0 else { return Self.home }
    let rawX = point.x / size.width
    let rawY = point.y / size.height
    return HPNormalizedPoint(
      x: clamped ? min(max(rawX, 0), 1) : rawX,
      y: clamped ? min(max(rawY, 0), 1) : rawY
    )
  }

  /// Returns an exact minimum-size target, shifting edge-adjacent anchors just
  /// enough to keep the full interactive rectangle within the field canvas.
  public func hitTargetRect(
    centeredAt point: HPNormalizedPoint,
    in size: CGSize,
    minimumSide: CGFloat = HPFieldGeometry.minimumInteractiveTarget
  ) -> CGRect {
    let side = max(0, min(minimumSide, min(size.width, size.height)))
    let half = side / 2
    let raw = canvasPoint(point, in: size)
    let center = CGPoint(
      x: min(max(raw.x, half), max(half, size.width - half)),
      y: min(max(raw.y, half), max(half, size.height - half))
    )
    return CGRect(x: center.x - half, y: center.y - half, width: side, height: side)
  }

  /// A field-relative drop radius that never falls below the accessibility hit target.
  public func runnerDropRadius(in size: CGSize) -> CGFloat {
    max(Self.minimumInteractiveTarget, min(size.width, size.height) * 0.145)
  }

  private static func rayEndpoint(
    from origin: HPNormalizedPoint,
    through point: HPNormalizedPoint,
    boundaryX: CGFloat
  ) -> HPNormalizedPoint {
    let horizontalDelta = point.x - origin.x
    precondition(abs(horizontalDelta) > .ulpOfOne, "A foul ray needs a non-vertical direction")
    let scale = (boundaryX - origin.x) / horizontalDelta
    return HPNormalizedPoint(
      x: boundaryX,
      y: origin.y + scale * (point.y - origin.y)
    )
  }
}
