import Foundation

/// The periods of a scheduled item's rule that already have an occurrence (D426.1, D427.1), so a moved anchor
/// never adds a second occurrence to one. Any live occurrence counts, whether it's paid, skipped or still open (due
/// or overdue), and it keeps its own date (D427.2). An occurrence on the day itself is that day's own record, so it
/// never takes its period.
///
/// A period is a block of the rule's N units counted from its Starts date (D428.1): the calendar day, the ISO week
/// (Monday first), the calendar month or the calendar year, so a single-unit rule's period is that calendar unit
/// (D429.3). After a Starts edit the blocks re-align to the new Starts date, and a block that overlaps the old block
/// of another occurrence is taken too (D429.2). Each day of a rule is in the first unit of its block, so an
/// occurrence's old block is the N units from its own day's unit.
///
/// Calendar days are already the device's days (`TransactionTiming.today` reads the device time zone, as the rest
/// of scheduling does), so the units are counted on the days themselves and no time zone applies here.
struct TakenPeriods {
    private let count: Int
    private let unit: ScheduleUnit?
    private let origin: Int
    private let days: [CalendarDay]

    init(_ item: ScheduledItem) {
        if case .every(let count, let unit) = item.repeatRule, count >= 1 {
            self.count = count
            self.unit = unit
            origin = Self.index(of: item.startDay, in: unit)
        } else {
            count = 1
            unit = nil
            origin = 0
        }
        days = item.occurrences.filter { $0.deletedAt == nil }.map(\.day)
    }

    /// Whether another occurrence of the item is in `day`'s block, or its own block overlaps `day`'s.
    func contains(_ day: CalendarDay) -> Bool {
        guard let unit, !days.isEmpty else {
            return false
        }
        let first = origin + Self.floorDivide(Self.index(of: day, in: unit) - origin, by: count) * count
        let last = first + count - 1
        return days.contains { other in
            let held = Self.index(of: other, in: unit)
            return other != day && held <= last && held + count - 1 >= first
        }
    }

    /// The number of `unit`s from a fixed origin to the one that holds `day`.
    static func index(of day: CalendarDay, in unit: ScheduleUnit) -> Int {
        switch unit {
        case .day:
            return dayNumber(day)
        case .week:
            // Julian day 0 is a Monday, so ISO weeks start where the day number is a multiple of 7.
            return floorDivide(dayNumber(day), by: 7)
        case .month:
            return day.year * 12 + day.month - 1
        case .year:
            return day.year
        }
    }

    /// The Julian day number of `day` on the Gregorian calendar.
    static func dayNumber(_ day: CalendarDay) -> Int {
        let shift = (14 - day.month) / 12
        let year = day.year + 4800 - shift
        let month = day.month + 12 * shift - 3
        return day.day + (153 * month + 2) / 5 + 365 * year + year / 4 - year / 100 + year / 400 - 32045
    }

    private static func floorDivide(_ value: Int, by divisor: Int) -> Int {
        let quotient = value / divisor
        return value % divisor < 0 ? quotient - 1 : quotient
    }
}
