import SwiftUI

struct DHDCalendarEventKinds: OptionSet, Equatable {
  let rawValue: Int

  static let scheduledLift = DHDCalendarEventKinds(rawValue: 1 << 0)
  static let practice = DHDCalendarEventKinds(rawValue: 1 << 1)
  static let game = DHDCalendarEventKinds(rawValue: 1 << 2)
}

struct DHDCalendarDayPresentation: Equatable {
  let isSelected: Bool
  let isToday: Bool
  let isDisabled: Bool
  let events: DHDCalendarEventKinds
}

struct DHDStatusDot: View {
  let color: Color
  var systemImage = "circle.fill"

  var body: some View {
    Image(systemName: systemImage)
      .font(.system(size: HP.Space.xs, weight: .bold))
      .foregroundStyle(color)
      .frame(width: HP.Space.xs, height: HP.Space.xs)
      .accessibilityHidden(true)
      .allowsHitTesting(false)
  }
}

struct DHDCalendarDayCellView: View {
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  let date: Date
  let isInMonth: Bool
  let isToday: Bool
  let isSelected: Bool
  let showGreen: Bool
  let showBlue: Bool
  let showRed: Bool
  let cellSize: CGSize

  var presentation: DHDCalendarDayPresentation {
    var events: DHDCalendarEventKinds = []
    if showGreen { events.insert(.scheduledLift) }
    if showBlue { events.insert(.practice) }
    if showRed { events.insert(.game) }
    return DHDCalendarDayPresentation(
      isSelected: isSelected,
      isToday: isToday,
      isDisabled: !isInMonth,
      events: events
    )
  }

  var body: some View {
    let dayNum = DateUtils.calendarET.component(.day, from: date)
    let base = min(cellSize.width, cellSize.height)
    let cellPad: CGFloat = dynamicTypeSize.isAccessibilitySize
      ? max(4, min(7, base * 0.12))
      : max(6, min(10, base * 0.18))

    VStack(alignment: .leading, spacing: 4) {
      HStack(alignment: .top, spacing: 2) {
        Text("\(dayNum)")
          .font(dayNumberFont)
          .monospacedDigit()
          .lineLimit(1)
          .layoutPriority(1)
          .foregroundStyle(dayNumberColor)
        Spacer(minLength: 0)
        if isToday { todayMark }
      }

      Spacer(minLength: 0)

      HStack(spacing: 4) {
        if showGreen { DHDStatusDot(color: HP.Color.success, systemImage: "circle.fill") }
        if showBlue { DHDStatusDot(color: HP.Color.info, systemImage: "diamond.fill") }
        if showRed { DHDStatusDot(color: HP.Color.danger, systemImage: "square.fill") }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .allowsHitTesting(false)
    }
    .padding(cellPad)
    .frame(width: cellSize.width, height: cellSize.height)
    .background(
      RoundedRectangle(cornerRadius: HP.Radius.md, style: .continuous)
        .fill(cellBackground)
    )
    .overlay(
      RoundedRectangle(cornerRadius: HP.Radius.md, style: .continuous)
        .strokeBorder(selectionStroke, lineWidth: isSelected ? 2 : 1)
        .allowsHitTesting(false)
    )
    .opacity(isInMonth ? 1 : 0.48)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(accessibilityDateLabel)
    .accessibilityValue(accessibilityValue)
    .accessibilityAddTraits(isSelected ? .isSelected : [])
    .accessibilityRespondsToUserInteraction(isInMonth)
  }

  private var dayNumberFont: Font {
    dynamicTypeSize.isAccessibilitySize
      ? HP.Font.caption.weight(.semibold)
      : HP.Font.callout.weight(.semibold)
  }

  private var dayNumberColor: Color {
    if isSelected { return HP.Color.text }
    return isInMonth ? HP.Color.text : HP.Color.textMuted
  }

  private var cellBackground: Color {
    isSelected ? HP.Color.accent.opacity(0.16) : HP.Color.surfaceRaised
  }

  private var selectionStroke: Color {
    if isSelected { return HP.Color.focusRing }
    if isToday { return HP.Color.accent.opacity(0.72) }
    return HP.Color.border
  }

  private var todayMark: some View {
    Circle()
      .strokeBorder(HP.Color.focusRing, lineWidth: 1.5)
      .background(Circle().fill(HP.Color.accent.opacity(0.20)))
      .frame(width: 10, height: 10)
      .allowsHitTesting(false)
      .accessibilityHidden(true)
  }

  private var accessibilityDateLabel: String {
    date.formatted(date: .long, time: .omitted)
  }

  private var accessibilityValue: String {
    var values: [String] = []
    if isToday { values.append("Today") }
    if isSelected { values.append("Selected") }
    if !isInMonth { values.append("Outside current month") }
    if showGreen { values.append("Scheduled lift") }
    if showBlue { values.append("Practice") }
    if showRed { values.append("Game") }
    return values.joined(separator: ", ")
  }
}

/// Home Plate calendar header for calendar consumers as they move to the
/// universal foundation. Its callbacks are direct pass-throughs and contain no
/// month math, selection state, or scheduling behavior.
struct DHDCalendarMonthHeader: View {
  let title: String
  var subtitle = "Select a day to view details"
  let onPrevious: () -> Void
  let onNext: () -> Void

  var body: some View {
    HStack(spacing: HP.Space.sm) {
      DHDCalendarNavigationButton(
        title: "Previous month",
        systemImage: "chevron.left",
        action: onPrevious
      )

      Spacer(minLength: HP.Space.xs)

      VStack(spacing: 2) {
        Text(title)
          .font(HP.Font.headline)
          .foregroundStyle(HP.Color.text)
          .multilineTextAlignment(.center)
          .fixedSize(horizontal: false, vertical: true)
        Text(subtitle)
          .font(HP.Font.caption)
          .foregroundStyle(HP.Color.textMuted)
          .multilineTextAlignment(.center)
          .fixedSize(horizontal: false, vertical: true)
      }
      .accessibilityElement(children: .combine)
      .accessibilityAddTraits(.isHeader)

      Spacer(minLength: HP.Space.xs)

      DHDCalendarNavigationButton(
        title: "Next month",
        systemImage: "chevron.right",
        action: onNext
      )
    }
    .padding(HP.Space.md)
    .background(
      RoundedRectangle(cornerRadius: HP.Radius.lg, style: .continuous)
        .fill(HP.Color.surfaceRaised)
    )
    .overlay(
      RoundedRectangle(cornerRadius: HP.Radius.lg, style: .continuous)
        .strokeBorder(HP.Color.border, lineWidth: 1)
        .allowsHitTesting(false)
    )
  }
}

struct DHDCalendarNavigationButton: View {
  let title: String
  let systemImage: String
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Image(systemName: systemImage)
        .font(HP.Font.headline)
        .foregroundStyle(HP.Color.text)
        .frame(width: 44, height: 44)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .background(
      RoundedRectangle(cornerRadius: HP.Radius.md, style: .continuous)
        .fill(HP.Color.surface)
    )
    .overlay(
      RoundedRectangle(cornerRadius: HP.Radius.md, style: .continuous)
        .strokeBorder(HP.Color.borderStrong, lineWidth: 1)
        .allowsHitTesting(false)
    )
    .accessibilityLabel(title)
  }
}
