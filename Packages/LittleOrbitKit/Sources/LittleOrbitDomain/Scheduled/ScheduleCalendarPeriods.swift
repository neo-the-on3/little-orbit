import Foundation

/// The periods of a scheduled item's rule that already have an occurrence (D426.1, D427.1), so a moved anchor
/// never adds a second occurrence to one. A real occurrence counts, whether it's paid, skipped or still open (due or
/// overdue), and it keeps its own date (D427.2). A day of the rule with its own real record is that occurrence, so
/// it's never passed over, even in a period another one holds: a move the user made is kept (D433.1).
///
/// A period is a block of the rule's N units counted from its Starts date (D428.1): the calendar day, the ISO week
/// (Monday first), the calendar month or the calendar year, so a single-unit rule's period is that calendar unit
/// (D429.3). After a Starts edit the blocks re-align to the new Starts date, and a block that overlaps the old block
/// of another occurrence is taken too (D429.2). Each day of a rule is in the first unit of its block, so an
/// occurrence's old block is the N units from its own day's unit.
///
/// The held blocks are worked out once, when the walk starts, so each walked day costs one lookup and a walk's cost
/// grows with the history, not its square (#316 review).
///
/// Calendar days are already the device's days (`TransactionTiming.today` reads the device time zone, as the rest
/// of scheduling does), so the units are counted on the days themselves and no time zone applies here.
struct TakenPeriods {
    private let count: Int
    private let unit: ScheduleUnit?
    private let origin: Int
    /// The first unit of each block an occurrence holds.
    private var held: Set<Int> = []
    /// The days with a real record of their own.
    private var own: Set<CalendarDay> = []
    /// How many times a record was looked at, so a test can keep the walk's cost linear.
    private(set) var looks = 0

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
        guard let unit else {
            return
        }
        for day in Self.realDays(of: item) {
            looks += 1
            own.insert(day)
            // Its old block, the N units from its own day's unit, overlaps at most two blocks (D429.2).
            let index = Self.index(of: day, in: unit)
            held.insert(block(of: index))
            held.insert(block(of: index + count - 1))
        }
    }

    /// The days of the item's real occurrences: posted, skipped and pending records that aren't deleted.
    static func realDays(of item: ScheduledItem) -> [CalendarDay] {
        item.occurrences
            .filter { record in
                record.deletedAt == nil
                    && (record.outcome == .posted || record.outcome == .skipped || record.outcome == .pending)
            }
            .map(\.day)
    }

    /// Whether `day` has no record of its own and another occurrence of the item holds its block.
    mutating func contains(_ day: CalendarDay) -> Bool {
        guard let unit, !held.isEmpty, !own.contains(day) else {
            return false
        }
        looks += 1
        return held.contains(block(of: Self.index(of: day, in: unit)))
    }

    /// The first unit of the block that holds unit `index`.
    private func block(of index: Int) -> Int {
        origin + Self.floorDivide(index - origin, by: count) * count
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
