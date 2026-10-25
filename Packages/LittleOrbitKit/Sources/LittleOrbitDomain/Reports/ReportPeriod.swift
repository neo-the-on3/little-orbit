import Foundation

/// The periods the spending report offers for Monday's core (#27, D316): presets only. Quarters and a custom
/// range are a Follow-up to #27.
public enum ReportPeriod: String, CaseIterable, Identifiable, Sendable {
    case thisMonth
    case lastMonth
    case thisYear
    case lastYear

    public var id: String { rawValue }

    /// Whether the period is a calendar month or a calendar year.
    public var length: ReportPeriodLength {
        switch self {
        case .thisMonth, .lastMonth: .month
        case .thisYear, .lastYear: .year
        }
    }

    /// The period's days, both ends included, for `today`. Days are calendar days, so a transaction counts on
    /// its own day in its own stored time zone (D33.3), never the device's.
    public func range(today: CalendarDay) -> ReportDayRange {
        switch self {
        case .thisMonth:
            ReportDayRange.month(year: today.year, month: today.month)
        case .lastMonth where today.month == 1:
            ReportDayRange.month(year: today.year - 1, month: 12)
        case .lastMonth:
            ReportDayRange.month(year: today.year, month: today.month - 1)
        case .thisYear:
            ReportDayRange.year(today.year)
        case .lastYear:
            ReportDayRange.year(today.year - 1)
        }
    }
}

public enum ReportPeriodLength: Sendable, Equatable {
    case month
    case year
}

/// A run of calendar days, `start` through `end`, both included.
public struct ReportDayRange: Equatable, Hashable, Sendable {
    public var start: CalendarDay
    public var end: CalendarDay

    public init(start: CalendarDay, end: CalendarDay) {
        self.start = start
        self.end = end
    }

    public func contains(_ day: CalendarDay) -> Bool {
        start <= day && day <= end
    }

    public static func month(year: Int, month: Int) -> ReportDayRange {
        ReportDayRange(
            start: CalendarDay(year: year, month: month, day: 1),
            end: CalendarDay(year: year, month: month, day: daysInMonth(year: year, month: month)),
        )
    }

    public static func year(_ year: Int) -> ReportDayRange {
        ReportDayRange(
            start: CalendarDay(year: year, month: 1, day: 1),
            end: CalendarDay(year: year, month: 12, day: 31),
        )
    }

    /// Gregorian month lengths, with leap years.
    static func daysInMonth(year: Int, month: Int) -> Int {
        switch month {
        case 2:
            let isLeap = (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
            return isLeap ? 29 : 28
        case 4, 6, 9, 11:
            return 30
        default:
            return 31
        }
    }
}
