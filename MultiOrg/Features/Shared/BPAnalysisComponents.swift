import SwiftUI
import Charts

struct HistogramBin: Identifiable {
  let id: Int
  let lower: Double
  let upper: Double
  let count: Int
}

struct HistogramChart: View {
  let values: [Double]
  let binCount: Int
  let xLabel: String

  var body: some View {
    let bins = makeBins(values: values, binCount: binCount)
    if bins.isEmpty {
      ContentUnavailableView("No data", systemImage: "chart.bar", description: Text("Upload a session with this metric to see its distribution."))
    } else {
      Chart(bins) { bin in
        BarMark(
          xStart: .value("Lower bound", bin.lower),
          xEnd: .value("Upper bound", bin.upper),
          y: .value("Swings", bin.count)
        )
        .foregroundStyle(DHDTheme.accent.gradient)
      }
      .chartXAxisLabel(xLabel.isEmpty ? "Value" : xLabel)
      .chartYAxisLabel("Swings")
      .chartYAxis {
        AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
          AxisGridLine()
          AxisValueLabel {
            if let count = value.as(Int.self) { Text("\(count)") }
          }
        }
      }
    }
  }

  private func makeBins(values: [Double], binCount: Int) -> [HistogramBin] {
    let samples = values.filter(\.isFinite)
    guard samples.count >= 2 else { return [] }
    let lower = samples.min() ?? 0
    let upper = samples.max() ?? 0
    guard lower != upper else {
      return [HistogramBin(id: 0, lower: lower - 0.5, upper: upper + 0.5, count: samples.count)]
    }

    let width = (upper - lower) / Double(binCount)
    var counts = Array(repeating: 0, count: binCount)
    for value in samples {
      let index = min(binCount - 1, max(0, Int((value - lower) / width)))
      counts[index] += 1
    }
    return counts.enumerated().map { index, count in
      let start = lower + Double(index) * width
      return HistogramBin(id: index, lower: start, upper: start + width, count: count)
    }
  }
}

struct ScatterChart: View {
  let events: [SDBPEvent]

  var body: some View {
    let points = events.compactMap { event -> (launchAngle: Double, exitVelo: Double)? in
      guard let launchAngle = event.launch_angle, let exitVelo = event.exit_velo,
            launchAngle.isFinite, exitVelo.isFinite else { return nil }
      return (launchAngle, exitVelo)
    }
    if points.isEmpty {
      ContentUnavailableView("No paired data", systemImage: "circle.grid.2x2", description: Text("Exit velocity and launch angle are both required."))
    } else {
      Chart {
        ForEach(Array(points.enumerated()), id: \.offset) { _, point in
          PointMark(
            x: .value("Launch angle", point.launchAngle),
            y: .value("Exit velocity", point.exitVelo)
          )
          .foregroundStyle(contactColor(exitVelo: point.exitVelo, launchAngle: point.launchAngle))
          .symbolSize(34)
        }
      }
      .chartXAxisLabel("Launch angle (degrees)")
      .chartYAxisLabel("Exit velocity (mph)")
    }
  }
}

struct StrikeZoneChart: View {
  let events: [SDBPEvent]
  let mode: String

  private let horizontalRange = -17.0...17.0
  private let verticalRange = 18.0...42.0
  private let columns = 5
  private let rows = 5

  var body: some View {
    let points = normalizedPoints
    if points.isEmpty {
      ContentUnavailableView("No strike-zone data", systemImage: "rectangle.grid.3x2", description: Text("Upload pitch location columns to populate this chart."))
    } else {
      VStack(alignment: .leading, spacing: 8) {
        Text(mode == "density" ? "Contact quality by pitch location" : "Pitch locations")
          .font(.subheadline.weight(.semibold))
        GeometryReader { geometry in
          Canvas { context, size in
            drawZone(in: &context, size: size, points: points)
          }
        }
        .accessibilityLabel(mode == "density" ? "Strike-zone contact-quality heat map" : "Strike-zone pitch location chart")
        Text("Catcher view. Color intensity reflects \(mode == "density" ? "average exit velocity" : "each tracked pitch").")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
  }

  private var normalizedPoints: [StrikeZonePoint] {
    events.compactMap { event in
      guard let rawX = event.strike_x, let rawZ = event.strike_z,
            rawX.isFinite, rawZ.isFinite else { return nil }
      let x = abs(rawX) <= 3 ? rawX * 12 : rawX
      let z = abs(rawZ) <= 6 ? rawZ * 12 : rawZ
      guard horizontalRange.contains(x), verticalRange.contains(z) else { return nil }
      return StrikeZonePoint(x: x, z: z, exitVelo: event.exit_velo)
    }
  }

  private func drawZone(in context: inout GraphicsContext, size: CGSize, points: [StrikeZonePoint]) {
    let plotRect = CGRect(x: 22, y: 12, width: max(1, size.width - 44), height: max(1, size.height - 30))
    let cellWidth = plotRect.width / CGFloat(columns)
    let cellHeight = plotRect.height / CGFloat(rows)
    let bins = heatBins(points)
    let maxCount = max(1, bins.map(\.count).max() ?? 1)

    context.fill(Path(plotRect), with: .color(DHDTheme.cardBackground.opacity(0.65)))
    for row in 0..<rows {
      for column in 0..<columns {
        let rect = CGRect(
          x: plotRect.minX + CGFloat(column) * cellWidth,
          y: plotRect.minY + CGFloat(row) * cellHeight,
          width: cellWidth,
          height: cellHeight
        )
        let bin = bins.first { $0.column == column && $0.row == row }
        if mode == "density", let bin, bin.count > 0 {
          let score = qualityScore(bin: bin, maxCount: maxCount)
          context.fill(Path(rect.insetBy(dx: 1, dy: 1)), with: .color(heatColor(score)))
        }
        context.stroke(Path(rect), with: .color(DHDTheme.separator.opacity(0.8)), lineWidth: 1)
      }
    }

    if mode != "density" {
      for point in points {
        let location = pointLocation(point, in: plotRect)
        let marker = CGRect(x: location.x - 4, y: location.y - 4, width: 8, height: 8)
        context.fill(Path(ellipseIn: marker), with: .color(contactColor(exitVelo: point.exitVelo ?? 0, launchAngle: 15)))
      }
    }
    context.stroke(Path(plotRect), with: .color(DHDTheme.textPrimary.opacity(0.8)), lineWidth: 2)
  }

  private func heatBins(_ points: [StrikeZonePoint]) -> [StrikeZoneHeatBin] {
    var values: [String: StrikeZoneHeatBin] = [:]
    for point in points {
      let xFraction = (point.x - horizontalRange.lowerBound) / (horizontalRange.upperBound - horizontalRange.lowerBound)
      let zFraction = (point.z - verticalRange.lowerBound) / (verticalRange.upperBound - verticalRange.lowerBound)
      let column = min(columns - 1, max(0, Int(xFraction * Double(columns))))
      let row = min(rows - 1, max(0, rows - 1 - Int(zFraction * Double(rows))))
      let key = "\(column)-\(row)"
      var bin = values[key] ?? StrikeZoneHeatBin(column: column, row: row, count: 0, exitVeloTotal: 0, exitVeloCount: 0)
      bin.count += 1
      if let exitVelo = point.exitVelo {
        bin.exitVeloTotal += exitVelo
        bin.exitVeloCount += 1
      }
      values[key] = bin
    }
    return Array(values.values)
  }

  private func qualityScore(bin: StrikeZoneHeatBin, maxCount: Int) -> Double {
    if bin.exitVeloCount > 0 {
      return min(1, max(0.12, ((bin.exitVeloTotal / Double(bin.exitVeloCount)) - 55) / 45))
    }
    return max(0.12, Double(bin.count) / Double(maxCount))
  }

  private func pointLocation(_ point: StrikeZonePoint, in rect: CGRect) -> CGPoint {
    let xFraction = (point.x - horizontalRange.lowerBound) / (horizontalRange.upperBound - horizontalRange.lowerBound)
    let zFraction = (point.z - verticalRange.lowerBound) / (verticalRange.upperBound - verticalRange.lowerBound)
    return CGPoint(x: rect.minX + rect.width * xFraction, y: rect.maxY - rect.height * zFraction)
  }

  private func heatColor(_ score: Double) -> Color {
    Color(red: 0.10 + 0.80 * score, green: 0.22 + 0.56 * score, blue: 0.42 - 0.25 * score)
  }
}

struct ContactQualitySummary: View {
  let events: [SDBPEvent]

  var body: some View {
    let counts = categories
    if counts.isEmpty {
      Text("Exit velocity and launch angle are required for contact-quality labels.")
        .foregroundStyle(.secondary)
    } else {
      Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
        GridRow {
          Text("Type").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
          Text("Swings").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
          Text("Rate").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
        }
        ForEach(counts) { item in
          GridRow {
            Text(item.label)
            Text("\(item.count)")
            Text(rateLabel(item.count))
          }
        }
      }
    }
  }

  private var total: Int { max(1, events.filter { $0.exit_velo != nil && $0.launch_angle != nil }.count) }

  private var categories: [ContactQualityCount] {
    let pairs = events.compactMap { event -> (Double, Double)? in
      guard let exitVelo = event.exit_velo, let launchAngle = event.launch_angle else { return nil }
      return (exitVelo, launchAngle)
    }
    guard !pairs.isEmpty else { return [] }
    let damage = pairs.filter { exitVelo, launchAngle in exitVelo >= 85 && (8...32).contains(launchAngle) }.count
    let hardHit = pairs.filter { exitVelo, _ in exitVelo >= 85 }.count
    let sweetSpot = pairs.filter { _, launchAngle in (8...32).contains(launchAngle) }.count
    let topped = pairs.filter { _, launchAngle in launchAngle < 0 }.count
    let underneath = pairs.filter { _, launchAngle in launchAngle > 40 }.count
    let flarePop = pairs.filter { exitVelo, launchAngle in exitVelo < 75 && launchAngle > 35 }.count
    let hardGrounder = pairs.filter { exitVelo, launchAngle in exitVelo >= 85 && launchAngle < 0 }.count
    return [
      ContactQualityCount(label: "Damage swing", count: damage),
      ContactQualityCount(label: "Hard hit", count: hardHit),
      ContactQualityCount(label: "Sweet spot", count: sweetSpot),
      ContactQualityCount(label: "Topped", count: topped),
      ContactQualityCount(label: "Underneath", count: underneath),
      ContactQualityCount(label: "Flare / pop", count: flarePop),
      ContactQualityCount(label: "Hard grounder", count: hardGrounder)
    ]
  }

  private func rateLabel(_ count: Int) -> String {
    let rate = Int((Double(count) / Double(total) * 100).rounded())
    return "\(rate)%"
  }
}

struct BallFlightSummary: View {
  let events: [SDBPEvent]

  var body: some View {
    let groups = flightGroups
    if groups.isEmpty {
      Text("Launch angle and exit velocity are required for a ball-flight table.")
        .foregroundStyle(.secondary)
    } else {
      Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
        GridRow {
          Text("Type").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
          Text("Count").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
          Text("Avg EV").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
          Text("Max EV").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
          Text("Avg LA").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
          Text("Avg dist.").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
        }
        ForEach(groups) { group in
          GridRow {
            Text(group.label)
            Text("\(group.events.count)")
            Text(number(group.events.compactMap(\.exit_velo)))
            Text(number(group.events.compactMap(\.exit_velo).max()))
            Text(number(group.events.compactMap(\.launch_angle)))
            Text(number(group.events.compactMap(\.distance)))
          }
        }
      }
    }
  }

  private var flightGroups: [BallFlightGroup] {
    let all = events.filter { $0.launch_angle != nil }
    let rules: [(String, (Double) -> Bool)] = [
      ("Ground ball", { $0 < 10 }),
      ("Line drive", { $0 >= 10 && $0 < 25 }),
      ("Fly ball", { $0 >= 25 && $0 <= 50 }),
      ("Pop-up", { $0 > 50 })
    ]
    return rules.map { label, matches in
      BallFlightGroup(label: label, events: all.filter { matches($0.launch_angle ?? 0) })
    }
  }

  private func number(_ values: [Double]) -> String {
    guard !values.isEmpty else { return "—" }
    return String(format: "%.1f", values.reduce(0, +) / Double(values.count))
  }

  private func number(_ value: Double?) -> String {
    guard let value else { return "—" }
    return String(format: "%.1f", value)
  }
}

private struct StrikeZonePoint {
  let x: Double
  let z: Double
  let exitVelo: Double?
}

private struct StrikeZoneHeatBin {
  let column: Int
  let row: Int
  var count: Int
  var exitVeloTotal: Double
  var exitVeloCount: Int
}

private struct ContactQualityCount: Identifiable {
  let label: String
  let count: Int
  var id: String { label }
}

private struct BallFlightGroup: Identifiable {
  let label: String
  let events: [SDBPEvent]
  var id: String { label }
}

private func contactColor(exitVelo: Double, launchAngle: Double) -> Color {
  if exitVelo >= 85 && (8...32).contains(launchAngle) { return .green }
  if exitVelo >= 85 { return .orange }
  return DHDTheme.accent
}
