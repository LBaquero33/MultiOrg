import HomePlateScoringCore
import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

public struct HPScoreboard: View {
  let seed: GameSeed
  let projection: GameProjection
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  public init(seed: GameSeed, projection: GameProjection) {
    self.seed = seed
    self.projection = projection
  }

  public var body: some View {
    VStack(spacing: 0) {
      teamRow(.away)
      Divider().overlay(HPTheme.ColorToken.border)
      teamRow(.home)
      HStack(spacing: 8) {
        countCell("B", projection.balls, accessibility: "Balls")
        countCell("S", projection.strikes, accessibility: "Strikes")
        countCell("O", projection.outs, accessibility: "Outs")
        Spacer(minLength: 2)
        Label("\(projection.pitchCount(projection.defense))", systemImage: "baseball.fill")
          .font(HPTheme.FontToken.number(dynamicTypeSize.isAccessibilitySize ? 13 : 12))
          .foregroundStyle(HPTheme.ColorToken.textTertiary)
          .accessibilityLabel("\(projection.pitchCount(projection.defense)) pitches")
      }
      .padding(.horizontal, 10)
      .frame(height: countRailHeight)
      .background(HPTheme.ColorToken.surfaceRaised.opacity(0.72))
    }
    .frame(height: scoreboardHeight)
    .background(HPTheme.ColorToken.surface)
    .overlay(alignment: .bottom) { Rectangle().fill(HPTheme.ColorToken.border).frame(height: 1) }
    .accessibilityElement(children: .combine)
    .accessibilityLabel(
      "\(seed.away.name) \(projection.awayScore), \(seed.home.name) \(projection.homeScore), "
        + "\(projection.balls) balls, \(projection.strikes) strikes, \(projection.outs) outs"
    )
  }

  private func teamRow(_ side: TeamSide) -> some View {
    let team = seed.team(side)
    return HStack(spacing: 8) {
      ZStack {
        RoundedRectangle(cornerRadius: 7).fill(
          side == .home ? HPTheme.ColorToken.gold.opacity(0.18) : HPTheme.ColorToken.fieldGreen.opacity(0.35)
        )
        Text(team.abbreviation)
          .font(.system(size: 9, weight: .black, design: .rounded))
          .foregroundStyle(side == .home ? HPTheme.ColorToken.gold : HPTheme.ColorToken.fieldGlow)
      }
      .frame(width: 29, height: 24)
      ViewThatFits(in: .horizontal) {
        Text(team.name)
        Text(team.abbreviation)
      }
      .font(.system(size: dynamicTypeSize.isAccessibilitySize ? 14 : 13, weight: .bold))
      .foregroundStyle(HPTheme.ColorToken.text)
      .lineLimit(1)
      .minimumScaleFactor(0.72)
      Spacer(minLength: 4)
      lineValue("R", projection.score(side), emphasized: true)
      lineValue("H", projection.hits(side), emphasized: false)
      lineValue("E", projection.errors(side), emphasized: false)
    }
    .padding(.horizontal, 10)
    .frame(height: teamRowHeight)
  }

  private func lineValue(_ label: String, _ value: Int, emphasized: Bool) -> some View {
    HStack(spacing: 3) {
      Text(label)
        .font(.system(size: 9, weight: .bold, design: .rounded))
        .foregroundStyle(HPTheme.ColorToken.textMuted)
      Text("\(value)")
        .font(HPTheme.FontToken.number(emphasized ? 18 : 15))
        .contentTransition(.numericText())
        .foregroundStyle(emphasized ? HPTheme.ColorToken.gold : HPTheme.ColorToken.textTertiary)
    }
    .frame(width: emphasized ? 37 : 34)
    .accessibilityLabel("\(label) \(value)")
  }

  private func countCell(_ label: String, _ value: Int, accessibility: String) -> some View {
    HStack(spacing: 3) {
      Text(label).font(.system(size: 10, weight: .black, design: .rounded))
        .foregroundStyle(HPTheme.ColorToken.textMuted)
      Text("\(value)").font(HPTheme.FontToken.number(13)).foregroundStyle(HPTheme.ColorToken.text)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("\(accessibility) \(value)")
  }

  private var teamRowHeight: CGFloat { dynamicTypeSize.isAccessibilitySize ? 41 : 34 }
  private var countRailHeight: CGFloat { dynamicTypeSize.isAccessibilitySize ? 28 : 24 }
  private var scoreboardHeight: CGFloat {
    dynamicTypeSize.isAccessibilitySize
      ? HPGameDayLayoutMetrics.accessibilityScoreboardHeight
      : HPGameDayLayoutMetrics.scoreboardHeight
  }
}

public struct HPMatchupStrip: View {
  let batter: Player?
  let pitcher: Player?
  let snapshot: StatSnapshot?

  public init(batter: Player?, pitcher: Player?, snapshot: StatSnapshot?) {
    self.batter = batter
    self.pitcher = pitcher
    self.snapshot = snapshot
  }

  public var body: some View {
    HStack(spacing: 7) {
      matchupCard(label: "AT BAT", player: batter, stat: batterStat, alignTrailing: false)
      Image(systemName: "diamond.fill")
        .font(.system(size: 8, weight: .bold))
        .foregroundStyle(HPTheme.ColorToken.gold)
        .accessibilityHidden(true)
      matchupCard(label: "ON MOUND", player: pitcher, stat: pitcherStat, alignTrailing: true)
    }
    .padding(.horizontal, 10)
    .frame(height: HPGameDayLayoutMetrics.matchupHeight)
    .background(HPTheme.ColorToken.background)
    .overlay(alignment: .bottom) { Rectangle().fill(HPTheme.ColorToken.border.opacity(0.7)).frame(height: 1) }
  }

  private func matchupCard(
    label: String,
    player: Player?,
    stat: String,
    alignTrailing: Bool
  ) -> some View {
    HStack(spacing: 7) {
      if alignTrailing {
        matchupText(label: label, player: player, stat: stat, alignment: .trailing)
      }
      ZStack(alignment: .bottomTrailing) {
        HPPlayerAvatar(player: player, size: 38, emphasized: true)
        if let number = player?.jerseyNumber {
          Text(number)
            .font(.system(size: 8, weight: .black, design: .rounded))
            .foregroundStyle(HPTheme.ColorToken.goldText)
            .padding(.horizontal, 4)
            .frame(minHeight: 14)
            .background(HPTheme.ColorToken.gold)
            .clipShape(Capsule())
            .offset(x: 3, y: 2)
        }
      }
      if !alignTrailing {
        matchupText(label: label, player: player, stat: stat, alignment: .leading)
      }
    }
    .frame(maxWidth: .infinity)
    .accessibilityElement(children: .combine)
  }

  private func matchupText(
    label: String,
    player: Player?,
    stat: String,
    alignment: HorizontalAlignment
  ) -> some View {
    VStack(alignment: alignment, spacing: 0) {
      Text(label)
        .font(.system(size: 8, weight: .black, design: .rounded))
        .tracking(0.45)
        .foregroundStyle(HPTheme.ColorToken.gold)
      Text(player?.shortName ?? "Not assigned")
        .font(.system(size: 12, weight: .bold))
        .foregroundStyle(HPTheme.ColorToken.text)
        .lineLimit(1)
        .minimumScaleFactor(0.75)
      Text(stat)
        .font(.system(size: 9, weight: .medium, design: .monospaced))
        .foregroundStyle(HPTheme.ColorToken.textMuted)
        .lineLimit(1)
        .minimumScaleFactor(0.72)
    }
  }

  private var batterStat: String {
    guard let batter, let line = snapshot?.batting.first(where: { $0.playerID == batter.id }) else {
      return "0 for 0"
    }
    return "\(line.hits) for \(line.atBats) · \(line.runsBattedIn) RBI"
  }

  private var pitcherStat: String {
    guard let pitcher, let line = snapshot?.pitching.first(where: { $0.playerID == pitcher.id }) else {
      return "0 P · 0 K"
    }
    return "\(line.pitches) P · \(line.strikeouts) K"
  }
}

public enum RunnerDropDestination: Hashable, Sendable {
  case base(Base)
  case home
}

public enum RunnerDropOutcome: Hashable, Sendable {
  case safe
  case out
}

public struct HPBaseDiamond: View {
  let seed: GameSeed
  let projection: GameProjection
  let fieldLayout: HPFieldLayout
  let selectedFielders: [DefensivePosition]
  let ballLocation: BallLocation?
  let selectionEnabled: Bool
  let locationEnabled: Bool
  let onFielderTap: (DefensivePosition) -> Void
  let onLocationTap: (BallLocation) -> Void
  let onRunnerDrop: (RunnerState, RunnerDropDestination, RunnerDropOutcome) -> Void
  let onRunnerTap: (RunnerState) -> Void

  @State private var draggingRunnerID: UUID?
  @State private var dragTranslation: CGSize = .zero
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  public init(
    seed: GameSeed,
    projection: GameProjection,
    fieldLayout: HPFieldLayout = .compactPortrait,
    selectedFielders: [DefensivePosition] = [],
    ballLocation: BallLocation? = nil,
    selectionEnabled: Bool = false,
    locationEnabled: Bool = false,
    onFielderTap: @escaping (DefensivePosition) -> Void = { _ in },
    onLocationTap: @escaping (BallLocation) -> Void = { _ in },
    onRunnerDrop: @escaping (RunnerState, RunnerDropDestination, RunnerDropOutcome) -> Void = { _, _, _ in },
    onRunnerTap: @escaping (RunnerState) -> Void = { _ in }
  ) {
    self.seed = seed
    self.projection = projection
    self.fieldLayout = fieldLayout
    self.selectedFielders = selectedFielders
    self.ballLocation = ballLocation
    self.selectionEnabled = selectionEnabled
    self.locationEnabled = locationEnabled
    self.onFielderTap = onFielderTap
    self.onLocationTap = onLocationTap
    self.onRunnerDrop = onRunnerDrop
    self.onRunnerTap = onRunnerTap
  }

  public var body: some View {
    GeometryReader { proxy in
      let size = proxy.size
      ZStack {
        FieldCanvas(geometry: geometry)
        if locationEnabled {
          Color.clear
            .contentShape(Rectangle())
            .gesture(SpatialTapGesture().onEnded { value in
              let location = geometry.normalizedPoint(for: value.location, in: size)
              HPFieldHaptics.selection()
              onLocationTap(BallLocation(x: location.x, y: location.y))
            })
        }
        ForEach(fieldPositions(in: size), id: \.position) { item in
          if let player = player(at: item.position) {
            let selectionNumber = selectedFielders.firstIndex(of: item.position).map { $0 + 1 }
            HPPlayerMarker(
              player: player,
              position: item.position,
              selectionNumber: selectionNumber,
              isSelectable: selectionEnabled,
              quieted: selectionEnabled && selectionNumber == nil,
              emphasized: item.position == .pitcher
            ) {
              if selectionEnabled {
                HPFieldHaptics.selection()
                onFielderTap(item.position)
              }
            }
            .position(item.point)
          }
        }
        ForEach(Base.allCases, id: \.self) { base in
          baseView(base)
            .position(point(for: .base(base), size: size))
        }
        homePlate
          .position(point(for: .home, size: size))
        if let draggingRunnerID,
           let runner = projection.bases.values.first(where: { $0.playerID == draggingRunnerID }) {
          ForEach(eligibleDestinations(from: runner.base), id: \.self) { destination in
            runnerDropTarget(destination)
              .position(point(for: destination, size: size))
              .transition(reduceMotion ? .opacity : .scale.combined(with: .opacity))
          }
        }
        ForEach(projection.bases.values.sorted(by: { $0.base < $1.base })) { runner in
          HPBaseRunner(player: seed.player(runner.playerID), base: runner.base) {
            onRunnerTap(runner)
          }
          .position(point(for: .base(runner.base), size: size))
          .offset(draggingRunnerID == runner.playerID ? dragTranslation : .zero)
          .highPriorityGesture(
            DragGesture(minimumDistance: 4)
              .onChanged { value in
                draggingRunnerID = runner.playerID
                dragTranslation = value.translation
              }
              .onEnded { value in
                let final = CGPoint(
                  x: point(for: .base(runner.base), size: size).x + value.translation.width,
                  y: point(for: .base(runner.base), size: size).y + value.translation.height
                )
                if let destination = nearestDestination(to: final, from: runner.base, size: size) {
                  let outcome: RunnerDropOutcome = final.x <= self.point(for: destination, size: size).x
                    ? .safe : .out
                  outcome == .out ? HPFieldHaptics.impact() : HPFieldHaptics.selection()
                  onRunnerDrop(runner, destination, outcome)
                }
                draggingRunnerID = nil
                dragTranslation = .zero
              }
          )
        }
        if let ballLocation {
          let point = geometry.canvasPoint(
            HPNormalizedPoint(x: ballLocation.x, y: ballLocation.y),
            in: size
          )
          Path { path in
            path.move(to: self.point(for: .home, size: size))
            path.addLine(to: point)
          }
          .stroke(HPTheme.ColorToken.gold.opacity(0.7), style: StrokeStyle(lineWidth: 2, dash: [6, 5]))
          Circle()
            .fill(HPTheme.ColorToken.gold)
            .frame(width: 15, height: 15)
            .overlay(Circle().stroke(HPTheme.ColorToken.goldText, lineWidth: 2))
            .shadow(color: HPTheme.ColorToken.gold.opacity(0.65), radius: 8)
            .position(point)
            .accessibilityLabel("Batted ball location")
        }
      }
      .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
      .overlay(RoundedRectangle(cornerRadius: 18).stroke(HPTheme.ColorToken.borderStrong))
      .animation(.easeInOut(duration: reduceMotion ? 0.12 : 0.25), value: projection.bases)
    }
    .aspectRatio(geometry.aspectRatio, contentMode: .fit)
  }

  private var geometry: HPFieldGeometry { HPFieldGeometry(layout: fieldLayout) }

  private func fieldPositions(in size: CGSize) -> [(position: DefensivePosition, point: CGPoint)] {
    DefensivePosition.allCases.compactMap { position in
      guard let normalized = geometry.defensivePoint(position) else { return nil }
      let target = geometry.hitTargetRect(centeredAt: normalized, in: size)
      return (position, CGPoint(x: target.midX, y: target.midY))
    }
  }

  private func player(at position: DefensivePosition) -> Player? {
    let entries = projection.lineups[projection.defense] ?? seed.team(projection.defense).lineup
    return entries.first(where: { $0.exitedAtSequence == nil && $0.position == position })?.player
  }

  private func point(for destination: RunnerDropDestination, size: CGSize) -> CGPoint {
    switch destination {
    case .base(let base): geometry.canvasPoint(for: base, in: size)
    case .home: geometry.canvasPoint(HPFieldGeometry.home, in: size)
    }
  }

  private func nearestDestination(
    to point: CGPoint,
    from current: Base,
    size: CGSize
  ) -> RunnerDropDestination? {
    let destinations = eligibleDestinations(from: current)
    return destinations.min { lhs, rhs in
      distance(point, self.point(for: lhs, size: size)) < distance(point, self.point(for: rhs, size: size))
    }.flatMap { destination in
      distance(point, self.point(for: destination, size: size)) < geometry.runnerDropRadius(in: size)
        ? destination : nil
    }
  }

  private func eligibleDestinations(from current: Base) -> [RunnerDropDestination] {
    Base.allCases
      .filter { $0.rawValue > current.rawValue && projection.bases[$0] == nil }
      .map(RunnerDropDestination.base) + [.home]
  }

  private func distance(_ lhs: CGPoint, _ rhs: CGPoint) -> CGFloat {
    hypot(lhs.x - rhs.x, lhs.y - rhs.y)
  }

  private func baseView(_ base: Base) -> some View {
    ZStack {
      Color.clear.frame(width: 44, height: 44)
      RoundedRectangle(cornerRadius: 3)
        .fill(HPTheme.ColorToken.text)
        .frame(width: 18, height: 18)
        .rotationEffect(.degrees(45))
        .shadow(color: .black.opacity(0.5), radius: 4, y: 2)
    }
    .contentShape(Rectangle())
    .accessibilityLabel(base.label)
  }

  private var homePlate: some View {
    ZStack {
      Color.clear.frame(width: 44, height: 44)
      HomePlateGlyph()
        .fill(HPTheme.ColorToken.text)
        .frame(width: 22, height: 21)
        .shadow(color: .black.opacity(0.5), radius: 4, y: 2)
    }
    .contentShape(Rectangle())
    .accessibilityLabel("Home plate")
  }

  private func runnerDropTarget(_ destination: RunnerDropDestination) -> some View {
    HStack(spacing: 0) {
      Text("SAFE")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(HPTheme.ColorToken.success.opacity(0.88))
      Text("OUT")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(HPTheme.ColorToken.danger.opacity(0.9))
    }
    .font(HPTheme.FontToken.badge)
    .foregroundStyle(Color.white)
    .frame(width: 112, height: 52)
    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    .overlay(RoundedRectangle(cornerRadius: 12).stroke(HPTheme.ColorToken.text.opacity(0.85), lineWidth: 2))
    .shadow(color: .black.opacity(0.48), radius: 7, y: 3)
    .accessibilityElement(children: .combine)
    .accessibilityLabel("\(destinationLabel(destination)) drop target. Left half safe, right half out.")
  }

  private func destinationLabel(_ destination: RunnerDropDestination) -> String {
    switch destination {
    case .base(let base): base.label
    case .home: "Home"
    }
  }
}

private struct HomePlateGlyph: Shape {
  func path(in rect: CGRect) -> Path {
    var path = Path()
    path.move(to: CGPoint(x: rect.minX, y: rect.minY))
    path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
    path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.55))
    path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
    path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.55))
    path.closeSubpath()
    return path
  }
}

public struct HPPlayerMarker: View {
  let player: Player
  let position: DefensivePosition
  let selectionNumber: Int?
  let isSelectable: Bool
  let quieted: Bool
  let emphasized: Bool
  let action: () -> Void

  public init(
    player: Player,
    position: DefensivePosition,
    selectionNumber: Int? = nil,
    isSelectable: Bool = false,
    quieted: Bool = false,
    emphasized: Bool = false,
    action: @escaping () -> Void = {}
  ) {
    self.player = player
    self.position = position
    self.selectionNumber = selectionNumber
    self.isSelectable = isSelectable
    self.quieted = quieted
    self.emphasized = emphasized
    self.action = action
  }

  public var body: some View {
    Button(action: action) {
      VStack(spacing: 2) {
        ZStack(alignment: .topTrailing) {
          HPPlayerAvatar(player: player, size: 38, emphasized: emphasized)
            .overlay(
              Circle().stroke(
                selectionNumber == nil ? Color.clear : HPTheme.ColorToken.gold,
                lineWidth: selectionNumber == nil ? 0 : 3
              )
            )
          Text(player.jerseyNumber)
            .font(.system(size: 8, weight: .black, design: .rounded))
            .foregroundStyle(HPTheme.ColorToken.goldText)
            .padding(.horizontal, 4)
            .frame(minHeight: 14)
            .background(HPTheme.ColorToken.gold)
            .clipShape(Capsule())
            .offset(x: 4, y: 25)
          if let selectionNumber {
            Text("\(selectionNumber)")
              .font(.system(size: 9, weight: .black, design: .rounded))
              .foregroundStyle(HPTheme.ColorToken.goldText)
              .frame(width: 16, height: 16)
              .background(HPTheme.ColorToken.gold)
              .clipShape(Circle())
              .offset(x: 5, y: -5)
          }
        }
        HStack(spacing: 3) {
          Text(position.rawValue).fontWeight(.black).foregroundStyle(HPTheme.ColorToken.gold)
          Text(player.lastName).fontWeight(.bold).foregroundStyle(HPTheme.ColorToken.text)
        }
        .font(.system(size: 8.5, design: .rounded))
        .lineLimit(1)
        .minimumScaleFactor(0.72)
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(Color.black.opacity(0.68))
        .clipShape(Capsule())
      }
      .frame(width: 68, height: 60)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .allowsHitTesting(isSelectable)
    .opacity(quieted ? 0.62 : 1)
    .accessibilityLabel("\(player.displayName), \(position.rawValue)")
    .accessibilityHint(isSelectable ? "Select fielder" : "Defensive player")
  }
}

public struct HPBaseRunner: View {
  let player: Player?
  let base: Base
  let action: () -> Void

  public var body: some View {
    Button(action: action) {
      VStack(spacing: 0) {
        Image(systemName: "figure.run")
          .font(.system(size: 15, weight: .bold))
        Text("#\(player?.jerseyNumber ?? "—")")
          .font(.system(size: 9, weight: .black, design: .rounded))
      }
      .foregroundStyle(HPTheme.ColorToken.goldText)
      .frame(width: 43, height: 43)
      .background(HPTheme.ColorToken.gold)
      .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
      .overlay(RoundedRectangle(cornerRadius: 11).stroke(HPTheme.ColorToken.text, lineWidth: 2))
      .shadow(color: HPTheme.ColorToken.gold.opacity(0.45), radius: 9)
    }
    .buttonStyle(.plain)
    .accessibilityLabel("\(player?.displayName ?? "Runner") on \(base.label)")
    .accessibilityHint("Double tap for runner options or drag to a base")
  }
}

private struct FieldCanvas: View {
  let geometry: HPFieldGeometry

  var body: some View {
    Canvas { context, size in
      let rect = CGRect(origin: .zero, size: size)
      context.fill(Path(roundedRect: rect, cornerRadius: 18), with: .linearGradient(
        Gradient(colors: [Color(hex: 0x123B2B), Color(hex: 0x0E251B)]),
        startPoint: .zero,
        endPoint: CGPoint(x: size.width, y: size.height)
      ))
      for index in 0..<9 {
        let width = size.width / 9
        let stripe = CGRect(x: CGFloat(index) * width, y: 0, width: width, height: size.height)
        context.fill(Path(stripe), with: .color(Color.white.opacity(index.isMultiple(of: 2) ? 0.018 : 0)))
      }

      let home = geometry.canvasPoint(HPFieldGeometry.home, in: size)
      let first = geometry.canvasPoint(for: .first, in: size)
      let second = geometry.canvasPoint(for: .second, in: size)
      let third = geometry.canvasPoint(for: .third, in: size)
      let leftFoul = geometry.canvasPoint(geometry.leftFoulEndpoint, in: size)
      let rightFoul = geometry.canvasPoint(geometry.rightFoulEndpoint, in: size)

      var leftTerritory = Path()
      leftTerritory.move(to: leftFoul)
      leftTerritory.addLine(to: home)
      leftTerritory.addLine(to: CGPoint(x: 0, y: size.height))
      leftTerritory.closeSubpath()
      context.fill(leftTerritory, with: .color(Color.black.opacity(0.25)))

      var rightTerritory = Path()
      rightTerritory.move(to: rightFoul)
      rightTerritory.addLine(to: home)
      rightTerritory.addLine(to: CGPoint(x: size.width, y: size.height))
      rightTerritory.closeSubpath()
      context.fill(rightTerritory, with: .color(Color.black.opacity(0.25)))

      var warningTrack = Path()
      warningTrack.move(to: CGPoint(x: size.width * 0.035, y: size.height * 0.43))
      warningTrack.addQuadCurve(
        to: CGPoint(x: size.width * 0.965, y: size.height * 0.43),
        control: CGPoint(x: size.width * 0.50, y: size.height * -0.13)
      )
      context.stroke(warningTrack, with: .color(HPTheme.ColorToken.clay.opacity(0.58)), lineWidth: 7)
      context.stroke(warningTrack, with: .color(HPTheme.ColorToken.text.opacity(0.25)), lineWidth: 1)

      var infield = Path()
      infield.move(to: home); infield.addLine(to: first); infield.addLine(to: second)
      infield.addLine(to: third); infield.closeSubpath()
      context.fill(infield, with: .linearGradient(
        Gradient(colors: [HPTheme.ColorToken.clayLight, HPTheme.ColorToken.clay]),
        startPoint: second,
        endPoint: home
      ))
      context.fill(
        Path(ellipseIn: CGRect(
          x: size.width * 0.385, y: size.height * 0.47,
          width: size.width * 0.23, height: size.height * 0.27
        )),
        with: .color(Color(hex: 0x1B563D))
      )

      for base in Base.allCases {
        let point = geometry.canvasPoint(for: base, in: size)
        context.fill(
          Path(ellipseIn: CGRect(x: point.x - 18, y: point.y - 14, width: 36, height: 28)),
          with: .color(HPTheme.ColorToken.clayLight.opacity(0.92))
        )
      }

      let mound = geometry.canvasPoint(HPNormalizedPoint(x: 0.50, y: 0.63), in: size)
      context.fill(
        Path(ellipseIn: CGRect(x: mound.x - 25, y: mound.y - 14, width: 50, height: 28)),
        with: .color(HPTheme.ColorToken.clayLight)
      )
      context.stroke(
        Path { path in
          path.move(to: CGPoint(x: mound.x - 7, y: mound.y))
          path.addLine(to: CGPoint(x: mound.x + 7, y: mound.y))
        },
        with: .color(HPTheme.ColorToken.text.opacity(0.88)),
        lineWidth: 2
      )

      var basePath = Path()
      basePath.move(to: home); basePath.addLine(to: first); basePath.addLine(to: second)
      basePath.addLine(to: third); basePath.addLine(to: home)
      context.stroke(basePath, with: .color(HPTheme.ColorToken.text.opacity(0.86)), lineWidth: 2.2)

      var foulLeft = Path(); foulLeft.move(to: home); foulLeft.addLine(to: leftFoul)
      var foulRight = Path(); foulRight.move(to: home); foulRight.addLine(to: rightFoul)
      context.stroke(foulLeft, with: .color(HPTheme.ColorToken.text.opacity(0.82)), lineWidth: 1.5)
      context.stroke(foulRight, with: .color(HPTheme.ColorToken.text.opacity(0.82)), lineWidth: 1.5)

      let boxWidth = max(8, size.width * 0.026)
      let boxHeight = max(18, size.height * 0.052)
      for direction in [-1.0, 1.0] {
        let box = CGRect(
          x: home.x + CGFloat(direction) * size.width * 0.037 - boxWidth / 2,
          y: home.y - boxHeight * 0.58,
          width: boxWidth,
          height: boxHeight
        )
        context.stroke(Path(roundedRect: box, cornerRadius: 1), with: .color(HPTheme.ColorToken.text.opacity(0.62)), lineWidth: 1)
      }
    }
  }
}

@MainActor private enum HPFieldHaptics {
  static func selection() {
    #if canImport(UIKit)
    UISelectionFeedbackGenerator().selectionChanged()
    #endif
  }

  static func impact() {
    #if canImport(UIKit)
    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    #endif
  }
}

public struct HPSyncStatusBanner: View {
  let state: LabSyncState

  public init(state: LabSyncState) { self.state = state }

  public var body: some View {
    HPStatusBadge(state.label, kind: kind)
      .help(message)
  }

  private var kind: HPBadgeKind {
    switch state {
    case .synced: .success
    case .starting, .syncing: .info
    case .offline: .warning
    case .conflict: .danger
    }
  }

  private var message: String {
    if case .conflict(let message) = state { return message }
    return state.label
  }
}

public struct HPPitchActionDock: View {
  let disabled: Bool
  let onPitch: (PitchResult) -> Void
  let onBallInPlay: () -> Void

  public init(
    disabled: Bool,
    onPitch: @escaping (PitchResult) -> Void,
    onBallInPlay: @escaping () -> Void
  ) {
    self.disabled = disabled
    self.onPitch = onPitch
    self.onBallInPlay = onBallInPlay
  }

  public var body: some View {
    HStack(spacing: 5) {
      pitchButton("B", "Ball", .ball)
      pitchButton("ꓘ", "Called", .calledStrike)
      pitchButton("K", "Swing", .swingingStrike)
      pitchButton("F", "Foul", .foul)
      Button {
        HPFieldHaptics.selection()
        onBallInPlay()
      } label: {
        dockLabel(glyph: "baseball.fill", label: "In Play", systemImage: true)
      }
      .buttonStyle(HPDockButtonStyle(primary: true))
      .accessibilityLabel("Ball in play")

      Menu {
        Button("Hit By Pitch") { record(.hitByPitch) }
        Button("Intentional Ball") { record(.intentionalBall) }
        Button("Intentional Walk") { record(.intentionalWalk) }
        Button("Catcher Interference") { record(.catcherInterference) }
        Button("Balk") { record(.balk) }
        Button("Illegal Pitch") { record(.illegalPitch) }
      } label: {
        dockLabel(glyph: "ellipsis", label: "More", systemImage: true)
      }
      .buttonStyle(HPDockButtonStyle(primary: false))
      .accessibilityLabel("More scoring actions")
    }
    .padding(6)
    .frame(height: HPGameDayLayoutMetrics.scoringDockHeight)
    .background(HPTheme.ColorToken.surface)
    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    .overlay(RoundedRectangle(cornerRadius: 14).stroke(HPTheme.ColorToken.border))
    .disabled(disabled)
    .opacity(disabled ? 0.45 : 1)
  }

  private func pitchButton(_ glyph: String, _ label: String, _ result: PitchResult) -> some View {
    Button { record(result) } label: {
      dockLabel(glyph: glyph, label: label, systemImage: false)
    }
    .buttonStyle(HPDockButtonStyle(primary: false))
    .accessibilityLabel(result.title)
  }

  private func dockLabel(glyph: String, label: String, systemImage: Bool) -> some View {
    VStack(spacing: 2) {
      if systemImage {
        Image(systemName: glyph).font(.system(size: 15, weight: .bold))
      } else {
        Text(glyph).font(.system(size: 16, weight: .black, design: .rounded))
      }
      Text(label)
        .font(.system(size: 8, weight: .bold))
        .lineLimit(1)
        .minimumScaleFactor(0.72)
    }
    .frame(maxWidth: .infinity, minHeight: 52)
  }

  private func record(_ result: PitchResult) {
    HPFieldHaptics.selection()
    onPitch(result)
  }
}

private struct HPDockButtonStyle: ButtonStyle {
  let primary: Bool

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .foregroundStyle(primary ? HPTheme.ColorToken.goldText : HPTheme.ColorToken.text)
      .background(primary ? HPTheme.ColorToken.gold : HPTheme.ColorToken.surfaceRaised)
      .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .stroke(primary ? HPTheme.ColorToken.gold.opacity(0.9) : HPTheme.ColorToken.borderStrong)
      )
      .scaleEffect(configuration.isPressed ? 0.97 : 1)
      .animation(.easeOut(duration: 0.10), value: configuration.isPressed)
  }
}
