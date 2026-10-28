import Foundation

/// The periods of a scheduled item's rule that already have an occurrence (D426.1, D427.1), so a moved anchor
/// never adds a second occurrence to one. A period is the calendar unit of the rule that holds the day: the
/// month for a monthly rule, the year for a yearly one, the ISO week (Monday first) for a weekly one, and the day
/// itself for a daily one. Any live occurrence counts, whether it's paid, skipped or still open (due or overdue),
/// and it keeps its own date (D427.2). An occurrence on the day itself is that day's own record, so it never
/// takes its period.
struct TakenPeriods {
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    private let unit: ScheduleUnit?
    private let days: [CalendarDay]

    init(_ item: ScheduledItem) {
        if case .every(_, let unit) = item.repeatRule {
            self.unit = unit
        } else {
            self.unit = nil
        }
        days = item.occurrences.filter { $0.deletedAt == nil }.map(\.day)
    }

    /// Whether another occurrence of the item is in `day`'s period.
    func contains(_ day: CalendarDay) -> Bool {
        guard let unit, !days.isEmpty else {
            return false
        }
        return days.contains { $0 != day && Self.samePeriod($0, day, unit) }
    }

    static func samePeriod(_ lhs: CalendarDay, _ rhs: CalendarDay, _ unit: ScheduleUnit) -> Bool {
        switch unit {
        case .day:
            return lhs == rhs
        case .week:
            return week(of: lhs) == week(of: rhs)
        case .month:
            return lhs.year == rhs.year && lhs.month == rhs.month
        case .year:
            return lhs.year == rhs.year
        }
    }

    /// The ISO week-numbering year and week of `day`, worked out in UTC like every other calendar step here.
    private static func week(of day: CalendarDay) -> [Int?] {
        guard let date = calendar.date(from: DateComponents(year: day.year, month: day.month, day: day.day)) else {
            return []
        }
        let parts = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return [parts.yearForWeekOfYear, parts.weekOfYear]
    }
}
