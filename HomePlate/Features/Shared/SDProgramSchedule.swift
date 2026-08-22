import Foundation

struct SDProgramSchedule {
  struct DayContext: Equatable {
    let isScheduled: Bool
    let week: Int?
    let dayIndex: Int?
    let nextLiftDateISO: String?
    let isInProgramWindow: Bool
  }

  static func context(for date: Date, assignment: SDProgramAssignment, template: SDProgramTemplate) -> DayContext {
    guard let start = DateUtils.fromISODate(assignment.start_date) else {
      return DayContext(isScheduled: false, week: nil, dayIndex: nil, nextLiftDateISO: nil, isInProgramWindow: false)
    }
    let date0 = DateUtils.startOfDayET(date)
    let start0 = DateUtils.startOfDayET(start)
    if date0 < start0 {
      let nextISO = DateUtils.toISODate(start0)
      return DayContext(isScheduled: false, week: nil, dayIndex: nil, nextLiftDateISO: nextISO, isInProgramWindow: false)
    }

    let weekdays = scheduledWeekdays(for: template)
    guard !weekdays.isEmpty else {
      return DayContext(isScheduled: false, week: nil, dayIndex: nil, nextLiftDateISO: nil, isInProgramWindow: false)
    }
    let daysPerWeek = weekdays.count
    let maxLifts = template.weeks * daysPerWeek

    // Count scheduled lifts from start0 to date0 (inclusive).
    var liftNumber = 0
    var d = start0
    while d <= date0 {
      let wd = DateUtils.weekdayIndexMonToSun(d)
      if weekdays.contains(wd) {
        liftNumber += 1
      }
      guard let next = DateUtils.calendarET.date(byAdding: .day, value: 1, to: d) else { break }
      d = next
    }

    let wdToday = DateUtils.weekdayIndexMonToSun(date0)
    let isLiftWeekday = weekdays.contains(wdToday)
    let inWindow = liftNumber <= maxLifts

    if isLiftWeekday, liftNumber >= 1, inWindow {
      let week = ((liftNumber - 1) / daysPerWeek) + 1
      let dayIndex = ((liftNumber - 1) % daysPerWeek) + 1
      return DayContext(isScheduled: true, week: week, dayIndex: dayIndex, nextLiftDateISO: nil, isInProgramWindow: true)
    }

    // Find next lift date within program window.
    var liftCountSoFar = liftNumber
    var nextDate = date0
    while liftCountSoFar < maxLifts {
      guard let next = DateUtils.calendarET.date(byAdding: .day, value: 1, to: nextDate) else { break }
      nextDate = next
      let wd = DateUtils.weekdayIndexMonToSun(nextDate)
      if weekdays.contains(wd) {
        liftCountSoFar += 1
        return DayContext(isScheduled: false, week: nil, dayIndex: nil, nextLiftDateISO: DateUtils.toISODate(nextDate), isInProgramWindow: true)
      }
    }

    return DayContext(isScheduled: false, week: nil, dayIndex: nil, nextLiftDateISO: nil, isInProgramWindow: false)
  }

  static func scheduledDate(
    week: Int,
    dayIndex: Int,
    assignment: SDProgramAssignment,
    template: SDProgramTemplate
  ) -> Date? {
    guard week >= 1,
          dayIndex >= 1,
          let start = DateUtils.fromISODate(assignment.start_date) else { return nil }
    let weekdays = scheduledWeekdays(for: template)
    guard dayIndex <= weekdays.count, week <= max(1, template.weeks) else { return nil }

    let targetSlot = ((week - 1) * weekdays.count) + dayIndex
    var cursor = DateUtils.startOfDayET(start)
    var matchedSlots = 0
    var safety = 0
    while safety < 500 {
      if weekdays.contains(DateUtils.weekdayIndexMonToSun(cursor)) {
        matchedSlots += 1
        if matchedSlots == targetSlot { return cursor }
      }
      guard let next = DateUtils.calendarET.date(byAdding: .day, value: 1, to: cursor) else { return nil }
      cursor = next
      safety += 1
    }
    return nil
  }

  private static func scheduledWeekdays(for template: SDProgramTemplate) -> [Int] {
    Array(Set(template.lift_weekdays.filter { (1...7).contains($0) })).sorted()
  }
}
