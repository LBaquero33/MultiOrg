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

    let daysPerWeek = max(1, template.lift_weekdays.count)
    let maxLifts = template.weeks * daysPerWeek

    // Count scheduled lifts from start0 to date0 (inclusive).
    var liftNumber = 0
    var d = start0
    while d <= date0 {
      let wd = DateUtils.weekdayIndexMonToSun(d)
      if template.lift_weekdays.contains(wd) {
        liftNumber += 1
      }
      guard let next = DateUtils.calendarET.date(byAdding: .day, value: 1, to: d) else { break }
      d = next
    }

    let wdToday = DateUtils.weekdayIndexMonToSun(date0)
    let isLiftWeekday = template.lift_weekdays.contains(wdToday)
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
      if template.lift_weekdays.contains(wd) {
        liftCountSoFar += 1
        return DayContext(isScheduled: false, week: nil, dayIndex: nil, nextLiftDateISO: DateUtils.toISODate(nextDate), isInProgramWindow: true)
      }
    }

    return DayContext(isScheduled: false, week: nil, dayIndex: nil, nextLiftDateISO: nil, isInProgramWindow: false)
  }
}
