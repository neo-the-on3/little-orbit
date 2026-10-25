import Foundation

/// One budget period: `start` through `end`, both included. Index 0 is the period starting on the start day.
public struct BudgetPeriod: Hashable, Sendable {
    public var index: Int
    public var start: CalendarDay
    public var end: CalendarDay

    public init(index: Int, start: CalendarDay, end: CalendarDay) {
        self.index = index
        self.start = start
        self.end = end
    }

    /// How many days the period has.
    public var dayCount: Int {
        end.dayNumber - start.dayNumber + 1
    }

    public func contains(_ day: CalendarDay) -> Bool {
        start <= day && day <= end
    }
}

/// When a budget's periods start and end (#25; D24, D26, D60).
///
/// - Day and week steps add whole days to the start day.
/// - Month and year steps keep the start day as the anchor. A month without that day starts on its last day,
///   and the anchor comes back the month after (31 Jan → 28 Feb → 31 Mar). A yearly 29 Feb starts on 28 Feb in
///   other years. A period never rolls into the next month.
/// - Each period ends the day before the next one starts, so there's no gap or overlap.
///
/// Periods are calendar days. A transaction counts on its own calendar day in its stored time zone (#11), and
/// "today" is the device's calendar day (`TransactionTiming.today`).
public struct BudgetSchedule: Hashable, Sendable {
    public var startDay: CalendarDay
    public var recurrence: BudgetRecurrence

    public init(startDay: CalendarDay, recurrence: BudgetRecurrence) {
        self.startDay = startDay
        self.recurrence = recurrence
    }

    /// The period at `index`, 0 or more.
    public func period(_ index: Int) -> BudgetPeriod {
        let start = start(ofPeriod: index)
        let next = self.start(ofPeriod: index + 1)
        return BudgetPeriod(index: index, start: start, end: next.adding(days: -1))
    }

    /// The period `day` falls in, or `nil` before the start day. Also `nil` for a step below 1, which no saved or
    /// restored budget has (`LedgerBook.validateStoredBudgets`), so a bad value from anywhere can't loop forever.
    public func period(containing day: CalendarDay) -> BudgetPeriod? {
        let step = recurrence.step.count
        guard day >= startDay, step >= 1 else {
            return nil
        }
        var index: Int
        switch recurrence.step.unit {
        case .day:
            index = (day.dayNumber - startDay.dayNumber) / step
        case .week:
            index = (day.dayNumber - startDay.dayNumber) / (step * 7)
        case .month:
            index = max(0, (day.monthNumber - startDay.monthNumber) / step)
        case .year:
            index = max(0, (day.year - startDay.year) / step)
        }
        // Month and year estimates can be one off near the anchor day.
        while index > 0 && start(ofPeriod: index) > day {
            index -= 1
        }
        while start(ofPeriod: index + 1) <= day {
            index += 1
        }
        return period(index)
    }

    /// Whole days from `today` to the next period's start, or to the start day before the budget has started.
    public func daysUntilNextPeriod(today: CalendarDay) -> Int {
        guard let current = period(containing: today) else {
            return startDay.dayNumber - today.dayNumber
        }
        return current.end.dayNumber + 1 - today.dayNumber
    }

    /// The day the period at `index` starts.
    public func start(ofPeriod index: Int) -> CalendarDay {
        let count = recurrence.step.count * index
        switch recurrence.step.unit {
        case .day:
            return startDay.adding(days: count)
        case .week:
            return startDay.adding(days: count * 7)
        case .month:
            let month = startDay.monthNumber + count
            return CalendarDay.clamped(year: month / 12, month: month % 12 + 1, day: startDay.day)
        case .year:
            return CalendarDay.clamped(year: startDay.year + count, month: startDay.month, day: startDay.day)
        }
    }
}

extension CalendarDay {
    /// Days since 1 Jan 1970 in the proleptic Gregorian calendar, with no time zone involved.
    public var dayNumber: Int {
        // Howard Hinnant's days_from_civil.
        let shiftedYear = month <= 2 ? year - 1 : year
        let era = (shiftedYear >= 0 ? shiftedYear : shiftedYear - 399) / 400
        let yearOfEra = shiftedYear - era * 400
        let shiftedMonth = month > 2 ? month - 3 : month + 9
        let dayOfYear = (153 * shiftedMonth + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146_097 + dayOfEra - 719_468
    }

    /// The calendar day `dayNumber` days after 1 Jan 1970.
    public init(dayNumber: Int) {
        // Howard Hinnant's civil_from_days.
        let shifted = dayNumber + 719_468
        let era = (shifted >= 0 ? shifted : shifted - 146_096) / 146_097
        let dayOfEra = shifted - era * 146_097
        let yearOfEra = (dayOfEra - dayOfEra / 1_460 + dayOfEra / 36_524 - dayOfEra / 146_096) / 365
        let dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
        let shiftedMonth = (5 * dayOfYear + 2) / 153
        let day = dayOfYear - (153 * shiftedMonth + 2) / 5 + 1
        let month = shiftedMonth < 10 ? shiftedMonth + 3 : shiftedMonth - 9
        let year = yearOfEra + era * 400 + (month <= 2 ? 1 : 0)
        self.init(year: year, month: month, day: day)
    }

    public func adding(days: Int) -> CalendarDay {
        CalendarDay(dayNumber: dayNumber + days)
    }

    /// `day` in that month, or the month's last day when it has fewer days.
    static func clamped(year: Int, month: Int, day: Int) -> CalendarDay {
        CalendarDay(year: year, month: month, day: min(day, daysInMonth(year: year, month: month)))
    }

    static func daysInMonth(year: Int, month: Int) -> Int {
        switch month {
        case 2:
            let leap = (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
            return leap ? 29 : 28
        case 4, 6, 9, 11:
            return 30
        default:
            return 31
        }
    }

    /// Months since year 0, for month steps.
    var monthNumber: Int {
        year * 12 + month - 1
    }
}
