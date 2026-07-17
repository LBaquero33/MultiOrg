import SwiftUI

struct DHDMonthGridView: View {
  @Binding var visibleMonth: Date
  @Binding var selectedDate: Date

  let scheduledLiftISOs: Set<String>
  let practiceISOs: Set<String>
  let gameISOs: Set<String>

  let isLoading: Bool
  let onPrev: () -> Void
  let onNext: () -> Void
  let onSelect: (Date) -> Void

  private let weekdayLabels = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
  private let spacing = HP.Space.xs
  @State private var measuredWidth: CGFloat = 720

  var body: some View {
    VStack(alignment: .leading, spacing: HP.Space.md) {
      DHDCalendarMonthHeader(
        title: DateUtils.monthTitle(visibleMonth),
        subtitle: "Tap a day to view details",
        onPrevious: onPrev,
        onNext: onNext
      )

      GeometryReader { geo in
        let cellW = (geo.size.width - spacing * 6) / 7
        let cellH = max(44, cellW * 0.92)
        let cellSize = CGSize(width: cellW, height: cellH)
        let cells = makeMonthCells(monthStart: visibleMonth) // Always 42
        let columns = Array(repeating: GridItem(.fixed(cellW), spacing: spacing), count: 7)

        VStack(alignment: .leading, spacing: spacing) {
          LazyVGrid(columns: columns, spacing: spacing) {
            ForEach(weekdayLabels, id: \.self) { day in
              Text(day)
                .font(HP.Font.eyebrow)
                .foregroundStyle(HP.Color.textMuted)
                .frame(width: cellW, height: 18, alignment: .center)
            }
          }

          LazyVGrid(columns: columns, spacing: spacing) {
            ForEach(cells) { cell in
              let iso = DateUtils.toISODate(cell.date)
              let isSelected = DateUtils.toISODate(selectedDate) == iso
              Button {
                selectedDate = cell.date
                onSelect(cell.date)
              } label: {
                DHDCalendarDayCellView(
                  date: cell.date,
                  isInMonth: cell.isInMonth,
                  isToday: iso == DateUtils.toISODate(DateUtils.startOfDayET(Date())),
                  isSelected: isSelected,
                  showGreen: scheduledLiftISOs.contains(iso),
                  showBlue: practiceISOs.contains(iso),
                  showRed: gameISOs.contains(iso),
                  cellSize: cellSize
                )
              }
              // Ensure the full cell is tappable (not just the visible subviews).
              .contentShape(Rectangle())
              .buttonStyle(.plain)
              .opacity(cell.isInMonth ? 1 : 0.72)
            }
          }
        }
        // Explicit width so GeometryReader doesn't collapse inside ScrollView layouts.
        .frame(width: geo.size.width, alignment: .leading)
        .onAppear { measuredWidth = geo.size.width }
        .onChange(of: geo.size.width) { _, width in measuredWidth = width }
      }
      .frame(maxWidth: .infinity)
      .frame(height: gridHeight(forWidth: measuredWidth))

      if isLoading {
        HPLoadingState(text: "Loading calendar…")
          .padding(.top, HP.Space.xs)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private struct MonthCell: Identifiable {
    let id = UUID()
    let date: Date
    let isInMonth: Bool
  }

  private func makeMonthCells(monthStart: Date) -> [MonthCell] {
    let first = DateUtils.startOfMonthET(monthStart)
    let weekday = DateUtils.calendarET.component(.weekday, from: first) // 1=Sun..7=Sat
    let leading = max(0, weekday - 1)
    let gridStart = DateUtils.calendarET.date(byAdding: .day, value: -leading, to: first) ?? first

    // Always 6 rows (42 cells) for consistent calendar height.
    return (0..<42).compactMap { i in
      guard let d = DateUtils.calendarET.date(byAdding: .day, value: i, to: gridStart) else { return nil }
      let inMonth = DateUtils.calendarET.isDate(d, equalTo: first, toGranularity: .month)
      // Keep isInMonth correct even if we always show 42 cells.
      return MonthCell(date: d, isInMonth: inMonth)
    }
  }

  private func gridHeight(forWidth width: CGFloat) -> CGFloat {
    let cellW = (width - spacing * 6) / 7
    let cellH = max(44, cellW * 0.92)
    let weekdayRow: CGFloat = 18
    let totalSpacing = spacing * (1 /*between weekday+grid*/ + 5 /*between 6 rows*/ )
    return weekdayRow + (cellH * 6) + totalSpacing
  }
}
