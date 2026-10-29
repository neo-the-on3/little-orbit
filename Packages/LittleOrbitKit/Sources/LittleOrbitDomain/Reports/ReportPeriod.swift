import Foundation

/// The preset periods the reports offer: months and years from #27's core (D316), quarters from the Follow-up to
/// #27 (#184), and Last 6 Months for the over-time reports (#184 slice 5). A custom range and ‹ › stepping are
/// `ReportSelection`.
public enum ReportPeriod: String, CaseIterable, Identifiable, Sendable {
    case thisMonth
    case lastMonth
    case thisQuarter
    case lastQuarter
    case thisYear
    case lastYear
    /// This month and the five before it.
    case lastSixMonths

    public var id: String { rawValue }

    /// The category and payee reports' presets.
    public static let categoryPresets: [ReportPeriod] = [
        .thisMonth, .lastMonth, .thisQuarter, .lastQuarter, .thisYear, .lastYear,
    ]

    /// The over-time reports' presets, Last 6 Months first, as their default (UI Designer's slice 5 spec).
    public static let overTimePresets: [ReportPeriod] = [.lastSixMonths, .thisYear, .lastYear]

    /// Whether the period is a calendar month or a calendar year.
    public var length: ReportPeriodLength {
        switch self {
        case .thisMonth, .lastMonth: .month
        case .thisQuarter, .lastQuarter: .quarter
        case .thisYear, .lastYear: .year
        case .lastSixMonths: .sixMonths
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
        case .thisQuarter:
            ReportDayRange.quarter(year: today.year, quarter: ReportDayRange.quarter(of: today.month))
        case .lastQuarter:
            ReportDayRange.quarter(year: today.year, quarter: ReportDayRange.quarter(of: today.month)).stepped(by: -1)
        case .thisYear:
            ReportDayRange.year(today.year)
        case .lastYear:
            ReportDayRange.year(today.year - 1)
        case .lastSixMonths:
            ReportDayRange.months(endingIn: today.year, today.month, count: 6)
        }
    }
}

public enum ReportPeriodLength: Sendable, Equatable {
    case month
    case quarter
    case year
    case sixMonths
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

    /// Calendar quarter `quarter` (1 to 4) of `year`: Q4 is 1 Oct to 31 Dec.
    public static func quarter(year: Int, quarter: Int) -> ReportDayRange {
        let first = (quarter - 1) * 3 + 1
        return ReportDayRange(
            start: CalendarDay(year: year, month: first, day: 1),
            end: CalendarDay(year: year, month: first + 2, day: daysInMonth(year: year, month: first + 2)),
        )
    }

    /// The quarter, 1 to 4, that `month` is in.
    public static func quarter(of month: Int) -> Int {
        (month - 1) / 3 + 1
    }

    /// `count` whole calendar months, the last one `month` of `year`.
    public static func months(endingIn year: Int, _ month: Int, count: Int) -> ReportDayRange {
        let first = Self.month(year, month, plus: -(count - 1))
        return ReportDayRange(
            start: CalendarDay(year: first.year, month: first.month, day: 1),
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
