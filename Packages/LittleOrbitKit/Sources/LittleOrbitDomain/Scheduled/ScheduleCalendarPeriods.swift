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
/// occurrence's old block is the N units from its own day's unit. An occurrence whose own day is no longer on the
/// rule and that's due on another day takes only the one block of the current rule that holds the day it's due
/// (D437.1), so it never counts against a pre-edit period or two periods.
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
        for holder in Self.holders(of: item) {
            looks += 1
            own.insert(holder.key)
            let index = Self.index(of: holder.day, in: unit)
            held.insert(block(of: index))
            if !holder.isMoved {
                // Its old block, the N units from its own day's unit, overlaps at most two blocks (D429.2).
                held.insert(block(of: index + count - 1))
            }
        }
    }

    /// A real occurrence: its own day (its key), and the day whose period it holds.
    struct Holder {
        var key: CalendarDay
        var day: CalendarDay
        /// Its own day left the rule and it's due on another day, so it holds only that day's block (D437.1).
        var isMoved: Bool
    }

    /// The item's real occurrences, none deleted: posted, skipped and pending records, and ones with their own values
    /// (D45) while their day is still on the rule. A record left behind by a rule edit takes no period (#316
    /// review). One whose day left the rule and that's due on another day holds the period of that day (D437.1).
    static func holders(of item: ScheduledItem) -> [Holder] {
        let live = item.occurrences.filter { $0.deletedAt == nil }
        let checked = live.filter { $0.outcome == .edited || $0.edit?.has(.day) == true }
        let ruled = ruleDays(of: item, through: checked.map(\.day).max())
        return live.compactMap { record in
            let onRule = ruled.contains(record.day)
            switch record.outcome {
            case .edited:
                return onRule ? Holder(key: record.day, day: record.day, isMoved: false) : nil
            case .posted, .skipped, .pending:
                guard !onRule, record.edit?.has(.day) == true, let due = record.edit?.day, due != record.day else {
                    return Holder(key: record.day, day: record.day, isMoved: false)
                }
                return Holder(key: record.day, day: due, isMoved: true)
            }
        }
    }

    /// The rule's days from its Starts date through `last` and its end date, worked out once per walk.
    private static func ruleDays(of item: ScheduledItem, through last: CalendarDay?) -> Set<CalendarDay> {
        guard let last else {
            return []
        }
        let limit = item.endDay.map { min($0, last) } ?? last
        var days: Set<CalendarDay> = []
        var index = 0
        while index < ScheduleCalendar.walkLimit,
            let day = ScheduleCalendar.occurrence(index, from: item.startDay, repeating: item.repeatRule), day <= limit
        {
            days.insert(day)
            index += 1
        }
        return days
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
