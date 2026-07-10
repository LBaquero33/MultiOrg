import SwiftUI

struct DHDStatusDot: View {
  let color: Color
  var body: some View {
    Circle().fill(color).frame(width: DHDTheme.calendarDotSize, height: DHDTheme.calendarDotSize)
  }
}

struct DHDCalendarDayCellView: View {
  let date: Date
  let isInMonth: Bool
  let isToday: Bool
  let isSelected: Bool
  let showGreen: Bool
  let showBlue: Bool
  let showRed: Bool
  let cellSize: CGSize

  var body: some View {
    let dayNum = DateUtils.calendarET.component(.day, from: date)
    // Fit multi-digit day numbers even when the grid is narrow (e.g., windowed iPad / Split View).
    let base = min(cellSize.width, cellSize.height)
    let dayFontSize = min(18, max(11, base * 0.34))
    let cellPad: CGFloat = max(6, min(10, base * 0.18))
    VStack(alignment: .leading, spacing: 6) {
      HStack(alignment: .top) {
        Text("\(dayNum)")
          // Use an explicit font size (instead of Dynamic Type) so day numbers never clip.
          // We still cap Dynamic Type below as an extra safeguard for accessibility settings.
          .font(.system(size: dayFontSize, weight: DHDTheme.calendarDayNumberWeight, design: .default))
          .monospacedDigit()
          .lineLimit(1)
          .allowsTightening(true)
          .minimumScaleFactor(0.35)
          .layoutPriority(1)
          .foregroundStyle(isInMonth ? DHDTheme.textPrimary : DHDTheme.textSecondary.opacity(0.95))
        Spacer()
        if isToday { todayMark }
      }
      Spacer(minLength: 0)
      HStack(spacing: 4) {
        if showGreen { DHDStatusDot(color: .green) }
        if showBlue { DHDStatusDot(color: .blue) }
        if showRed { DHDStatusDot(color: .red) }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(cellPad)
    .frame(width: cellSize.width, height: cellSize.height)
    .background(
      RoundedRectangle(cornerRadius: DHDTheme.calendarCellCornerRadius)
        .fill(DHDTheme.surfaceElevated)
    )
    .overlay(
      RoundedRectangle(cornerRadius: DHDTheme.calendarCellCornerRadius)
        .strokeBorder(selectionStroke, lineWidth: isSelected ? 2 : 1)
    )
  }

  private var selectionStroke: Color {
    if isSelected { return DHDTheme.accent.opacity(0.85) }
    return DHDTheme.separator.opacity(0.35)
  }

  private var todayMark: some View {
    Circle()
      .strokeBorder(DHDTheme.accent.opacity(0.95), lineWidth: 1.5)
      .background(Circle().fill(DHDTheme.accent.opacity(0.20)))
      .frame(width: 10, height: 10)
  }
}
