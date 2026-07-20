import SwiftUI
import Charts

/// A data point for `HPChart`.
struct HPChartPoint: Identifiable {
  let id = UUID()
  let x: String
  let y: Double
}

enum HPChartStyle { case line, bar }

/// Thin, tokenized wrapper over **native Swift Charts**. Line/area or bar, with
/// a designed empty state and Reduce-Motion-aware appearance.
struct HPChart: View {
  let points: [HPChartPoint]
  var style: HPChartStyle = .line
  var height: CGFloat = 180

  var body: some View {
    if points.isEmpty {
      HPEmptyState(title: "No data yet",
                   message: "This chart populates once data is available.",
                   systemImage: "chart.xyaxis.line")
    } else {
      Chart(points) { point in
        if style == .bar {
          BarMark(
            x: .value("Category", point.x),
            y: .value("Value", point.y)
          )
          .foregroundStyle(HP.Color.accent.gradient)
        } else {
          AreaMark(
            x: .value("Category", point.x),
            y: .value("Value", point.y)
          )
          .foregroundStyle(LinearGradient(colors: [HP.Color.primaryGlow.opacity(0.30), .clear],
                                          startPoint: .top, endPoint: .bottom))
          .interpolationMethod(.catmullRom)
          LineMark(
            x: .value("Category", point.x),
            y: .value("Value", point.y)
          )
          .foregroundStyle(HP.Color.primaryGlow)
          .interpolationMethod(.catmullRom)
        }
      }
      .chartYAxis {
        AxisMarks(position: .leading) { _ in
          AxisGridLine().foregroundStyle(HP.Color.border)
          AxisValueLabel().foregroundStyle(HP.Color.textMuted)
        }
      }
      .chartXAxis {
        AxisMarks { _ in
          AxisValueLabel().foregroundStyle(HP.Color.textMuted)
        }
      }
      .frame(height: height)
    }
  }
}
