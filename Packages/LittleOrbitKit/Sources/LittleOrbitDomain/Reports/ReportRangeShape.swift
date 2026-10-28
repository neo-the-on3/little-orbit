import Foundation

/// What a run of days is, so a title can name it: “October 2026”, “Q4 2026”, “2026”, or its two end days.
public enum ReportRangeShape: Equatable, Sendable {
    case month
    case quarter(Int)
    case year
    case days
}

extension ReportDayRange {
    /// A whole calendar month, quarter or year, else just days. A custom range that is exactly a month is a month.
    public var shape: ReportRangeShape {
        guard start.year == end.year, start.day == 1,
            end.day == Self.daysInMonth(year: end.year, month: end.month)
        else {
            return .days
        }
        switch (start.month, end.month) {
        case (let first, let last) where first == last:
            return .month
        case (1, 12):
            return .year
        case (let first, let last) where last == first + 2 && (first - 1) % 3 == 0:
            return .quarter(Self.quarter(of: first))
        default:
            return .days
        }
    }

    /// The same length of calendar period `steps` periods later (earlier when negative): a month moves by months,
    /// a quarter by quarters, a year by years. Any other range moves by its own number of days.
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
        case .days:
            let length = dayCount
            return ReportDayRange(start: start.adding(days: steps * length), end: end.adding(days: steps * length))
        }
    }

    /// How many days it covers, both ends included.
    public var dayCount: Int {
        end.dayNumber - start.dayNumber + 1
    }

    static func month(_ year: Int, _ month: Int, plus months: Int) -> (year: Int, month: Int) {
        let index = year * 12 + (month - 1) + months
        let newYear = index >= 0 ? index / 12 : (index - 11) / 12
        return (newYear, index - newYear * 12 + 1)
    }
}
