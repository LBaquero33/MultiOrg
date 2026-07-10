import Foundation

enum DateUtils {
  static let calendarET: Calendar = {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "America/New_York") ?? .current
    return cal
  }()

  static func startOfDayET(_ date: Date) -> Date {
    calendarET.startOfDay(for: date)
  }

  static func toISODate(_ date: Date) -> String {
    let df = DateFormatter()
    df.calendar = calendarET
    df.timeZone = calendarET.timeZone
    df.dateFormat = "yyyy-MM-dd"
    return df.string(from: date)
  }

  static func fromISODate(_ s: String) -> Date? {
    let df = DateFormatter()
    df.calendar = calendarET
    df.timeZone = calendarET.timeZone
    df.dateFormat = "yyyy-MM-dd"
    return df.date(from: s)
  }

  static func startOfMonthET(_ date: Date) -> Date {
    let comps = calendarET.dateComponents([.year, .month], from: date)
    return calendarET.date(from: comps).map(startOfDayET) ?? startOfDayET(date)
  }

  static func addMonthsET(_ date: Date, value: Int) -> Date {
    calendarET.date(byAdding: .month, value: value, to: date) ?? date
  }

  static func daysInMonthET(_ date: Date) -> Int {
    guard let range = calendarET.range(of: .day, in: .month, for: date) else { return 30 }
    return range.count
  }

  static func monthTitle(_ date: Date) -> String {
    let df = DateFormatter()
    df.calendar = calendarET
    df.timeZone = calendarET.timeZone
    df.dateFormat = "MMMM yyyy"
    return df.string(from: date)
  }

  static func prettyDateTitle(_ date: Date) -> String {
    let df = DateFormatter()
    df.calendar = calendarET
    df.timeZone = calendarET.timeZone
    df.dateFormat = "EEE, MMM d, yyyy"
    return df.string(from: date)
  }

  // Weekday 1..7 (Mon..Sun)
  static func weekdayIndexMonToSun(_ date: Date) -> Int {
    let weekday = calendarET.component(.weekday, from: date) // 1=Sun..7=Sat
    // Convert to Mon..Sun: Mon=1..Sun=7
    switch weekday {
    case 1: return 7
    default: return weekday - 1
    }
  }
}
