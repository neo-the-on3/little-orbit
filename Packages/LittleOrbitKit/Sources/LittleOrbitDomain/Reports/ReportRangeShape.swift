import Foundation

/// What a run of days is, so a title can name it: “October 2026”, “Q4 2026”, “2026”, “May – Oct 2026”, or its
/// two end days.
public enum ReportRangeShape: Equatable, Sendable {
    case month
    case quarter(Int)
    case year
    /// Whole calendar months that aren't one month, a quarter or a year, such as Last 6 Months (#184 slice 5).
    case months(Int)
    case days
}

extension ReportDayRange {
    /// A whole calendar month, quarter or year, else whole months, else just days. A custom range that is exactly
    /// a month is a month.
    public var shape: ReportRangeShape {
        guard start <= end, start.day == 1, end.day == Self.daysInMonth(year: end.year, month: end.month) else {
            return .days
        }
        let count = (end.year - start.year) * 12 + end.month - start.month + 1
        guard start.year == end.year else {
            return .months(count)
        }
        switch (start.month, end.month) {
        case (let first, let last) where first == last:
            return .month
        case (1, 12):
            return .year
        case (let first, let last) where last == first + 2 && (first - 1) % 3 == 0:
            return .quarter(Self.quarter(of: first))
        default:
            return .months(count)
        }
    }

    /// The same calendar period `steps` periods later (earlier when negative): a month moves by months, a quarter
    /// by quarters, a year by years. Any other range doesn't step, and comes back unchanged.
    public func stepped(by steps: Int) -> ReportDayRange {
        switch shape {
        case .month:
            let (year, month) = Self.month(start.year, start.month, plus: steps)
            return .month(year: year, month: month)
        case .quarter:
            let (year, month) = Self.month(start.year, start.month, plus: steps * 3)
            return .quarter(year: year, quarter: Self.quarter(of: month))
        case .year:
            return .year(start.year + steps)
        case .months(let count):
            let (year, month) = Self.month(end.year, end.month, plus: steps * count)
            return .months(endingIn: year, month, count: count)
        case .days:
            return self
        }
    }

    /// The range's calendar months, oldest first, each cut to the range: a custom range's first and last months
    /// count only their included days (UI Designer's slice 5 spec).
    public var months: [ReportDayRange] {
        var result: [ReportDayRange] = []
        var (year, month) = (start.year, start.month)
        while CalendarDay(year: year, month: month, day: 1) <= end {
            let whole = ReportDayRange.month(year: year, month: month)
            result.append(ReportDayRange(start: max(whole.start, start), end: min(whole.end, end)))
            (year, month) = Self.month(year, month, plus: 1)
        }
        return result
    }

    static func month(_ year: Int, _ month: Int, plus months: Int) -> (year: Int, month: Int) {
        let index = year * 12 + (month - 1) + months
        let newYear = index >= 0 ? index / 12 : (index - 11) / 12
        return (newYear, index - newYear * 12 + 1)
    }
}
