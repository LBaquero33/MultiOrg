import SwiftUI
import Charts

struct HistogramBin: Identifiable {
  let id = UUID()
  let label: String
  let count: Int
}

struct HistogramChart: View {
  let values: [Double]
  let binCount: Int
  let xLabel: String

  var body: some View {
    let bins = makeBins(values: values, binCount: binCount)
    if bins.isEmpty {
      Text("No data.")
        .foregroundStyle(.secondary)
    } else {
      Chart(bins) { b in
        BarMark(
          x: .value("Bin", b.label),
          y: .value("Count", b.count)
        )
        .foregroundStyle(Color.accentColor.opacity(0.8))
      }
      .chartXAxis {
        AxisMarks(values: .automatic(desiredCount: min(6, binCount))) { _ in
          AxisGridLine()
          AxisValueLabel()
        }
      }
      .chartYAxisLabel("Count")
    }
  }

  private func makeBins(values: [Double], binCount: Int) -> [HistogramBin] {
    let xs = values
    guard xs.count >= 2 else { return [] }
    let minV = xs.min() ?? 0
    let maxV = xs.max() ?? 0
    if minV == maxV { return [HistogramBin(label: fmt(minV), count: xs.count)] }
    let span = maxV - minV
    let w = span / Double(binCount)
    var counts = Array(repeating: 0, count: binCount)
    for x in xs {
      let idx = min(binCount - 1, max(0, Int((x - minV) / w)))
      counts[idx] += 1
    }
    return counts.enumerated().map { i, c in
      let a = minV + (Double(i) * w)
      let b = a + w
      return HistogramBin(label: "\(fmt(a))–\(fmt(b))", count: c)
    }
  }

  private func fmt(_ v: Double) -> String {
    if v.rounded() == v { return String(Int(v)) }
    return String(format: "%.1f", v)
  }
}

struct ScatterChart: View {
  let events: [SDBPEvent]

  var body: some View {
    let pts = events.compactMap { e -> (la: Double, ev: Double)? in
      guard let la = e.launch_angle, let ev = e.exit_velo else { return nil }
      return (la: la, ev: ev)
    }
    if pts.isEmpty {
      Text("No EV/LA pairs.")
        .foregroundStyle(.secondary)
    } else {
      Chart {
        ForEach(Array(pts.enumerated()), id: \.offset) { _, p in
          PointMark(
            x: .value("Launch Angle", p.la),
            y: .value("Exit Velo", p.ev)
          )
          .foregroundStyle(Color.accentColor.opacity(0.7))
        }
      }
      .chartXAxisLabel("Launch angle (°)")
      .chartYAxisLabel("Exit velo (mph)")
    }
  }
}

struct StrikeZonePlotly: View {
  let events: [SDBPEvent]
  let mode: String // point|density

  var body: some View {
    let pts = events.compactMap { e -> (x: Double, y: Double, ev: Double?)? in
      guard let x = e.strike_x, let y = e.strike_z else { return nil }
      if !x.isFinite || !y.isFinite { return nil }
      if x < -25 || x > 25 || y < 0 || y > 60 { return nil }
      return (x: x, y: y, ev: e.exit_velo)
    }
    if pts.isEmpty {
      Text("No strike-zone locations found in this date range.")
        .foregroundStyle(.secondary)
    } else {
      let x = pts.map { $0.x }
      let y = pts.map { $0.y }
      let ev = pts.map { $0.ev ?? 0 }
      let payload: [String: Any] = [
        "kind": "strike_zone",
        "mode": mode,
        "title": "Strike Zone Heatmap (catcher view)",
        "x": x,
        "y": y,
        "ev": ev
      ]
      PlotlyChartView(payloadJSON: json(payload), height: 320)
        .frame(maxWidth: .infinity, minHeight: 320)
    }
  }

  private func json(_ obj: [String: Any]) -> String {
    guard let data = try? JSONSerialization.data(withJSONObject: obj, options: []) else { return "{}" }
    return String(data: data, encoding: .utf8) ?? "{}"
  }
}
