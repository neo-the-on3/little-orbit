import Foundation

/// Due days of scheduled items (#26), worked out on calendar days only, so a DST change or a time zone change
/// never skips or doubles a day (S23, S24).
///
/// Monthly and yearly occurrences count from the start day: the n-th one is the start's month plus n steps, on
/// the anchor day, or the month's last day when the month is shorter (D24). So 31 Jan gives 28 Feb, then 31 Mar,
/// and a yearly 29 Feb gives 28 Feb in other years. A skip or a payment never moves the anchor.
public enum ScheduleCalendar {
    /// The most occurrences one walk looks at, so a broken item can never loop for long (a daily item for 270 years).
    static let walkLimit = 100_000

    /// The `index`-th occurrence of a rule starting on `start` (0 is `start` itself), with no end date applied.
    public static func occurrence(
        _ index: Int,
        from start: CalendarDay,
        repeating rule: ScheduleRepeat,
    ) -> CalendarDay? {
        guard index >= 0, isValid(start) else {
            return nil
        }
        switch rule {
        case .never:
            return index == 0 ? start : nil
        case .every(let count, let unit):
            guard ScheduleRepeat.countRange.contains(count) else {
                return nil
            }
            let steps = index * count
            switch unit {
            case .day:
                return adding(days: steps, to: start)
            case .week:
                return adding(days: steps * 7, to: start)
            case .month:
                let months = (start.month - 1) + steps
                let year = start.year + months / 12
                let month = months % 12 + 1
                return CalendarDay(year: year, month: month, day: min(start.day, daysIn(year: year, month: month)))
            case .year:
                let year = start.year + steps
                return CalendarDay(
                    year: year,
                    month: start.month,
                    day: min(start.day, daysIn(year: year, month: start.month)),
                )
            }
        }
    }

    /// The item's occurrences, in order, from its creation day and `resumesOn` (if set) through `through`, and
    /// never after its end.
    public static func occurrences(of item: ScheduledItem, through last: CalendarDay) -> [CalendarDay] {
        var days: [CalendarDay] = []
        walk(item) { day in
            guard day <= last else {
                return false
            }
            days.append(day)
            return true
        }
        return days
    }

    /// The item's first `count` occurrences on or after `first`, within its end date.
    public static func occurrences(of item: ScheduledItem, from first: CalendarDay, count: Int) -> [CalendarDay] {
        var days: [CalendarDay] = []
        guard count > 0 else {
            return days
        }
        walk(item) { day in
            if day >= first {
                days.append(day)
            }
            return days.count < count
        }
        return days
    }

    /// The first occurrence on or after `first` that `isOpen` accepts, within the item's end date.
    public static func firstOccurrence(
        of item: ScheduledItem,
        onOrAfter first: CalendarDay,
        where isOpen: (CalendarDay) -> Bool,
    ) -> CalendarDay? {
        var found: CalendarDay?
        walk(item) { day in
            if day >= first && isOpen(day) {
                found = day
                return false
            }
            return true
        }
        return found
    }

    /// The days still to pay or skip through `last`: the rule's occurrences that aren't settled, and the pending
    /// days kept from before an edit (D336.1), oldest first.
    public static func dueDays(of item: ScheduledItem, through last: CalendarDay) -> [CalendarDay] {
        let settled = item.settledDays
        let ruled = occurrences(of: item, through: last).filter { !settled.contains($0) }
        let pending = item.pendingDays.filter { $0 <= last }
        guard !pending.isEmpty else {
            return ruled
        }
        return Array(Set(ruled + pending)).sorted()
    }

    /// Whether `day` is one of the item's occurrences: on its rule, or pending from before an edit.
    public static func isOccurrence(_ day: CalendarDay, of item: ScheduledItem) -> Bool {
        if item.occurrence(on: day)?.outcome == .pending {
            return true
        }
        var found = false
        walk(item) { candidate in
            if candidate == day {
                found = true
            }
            return candidate < day
        }
        return found
    }

    /// Calls `body` with each occurrence in order until it returns `false`, the end date passes or the rule ends.
    /// Days before the item's creation day or `resumesOn` are passed over (D114, D336.2, D337.1).
    private static func walk(_ item: ScheduledItem, _ body: (CalendarDay) -> Bool) {
        let floor = max(item.creationDay, item.resumesOn ?? item.creationDay)
        var index = 0
        while index < walkLimit, let day = occurrence(index, from: item.startDay, repeating: item.repeatRule) {
            index += 1
            if let end = item.endDay, day > end {
                return
            }
            if day < floor {
                continue
            }
            if !body(day) {
                return
            }
        }
    }

    /// Whether `day` is a real calendar day (no 30 Feb, no month 13).
    public static func isValid(_ day: CalendarDay) -> Bool {
        (1...12).contains(day.month) && day.day >= 1 && day.day <= daysIn(year: day.year, month: day.month)
            && (1...9999).contains(day.year)
    }

    /// The occurrence fell on the month's last day because the anchor day doesn't exist in that month (D24).
    public static func isShortened(_ day: CalendarDay, of item: ScheduledItem) -> Bool {
        guard case .every(_, let unit) = item.repeatRule, unit == .month || unit == .year else {
            return false
        }
        return day.day < item.startDay.day
    }

    public static func daysIn(year: Int, month: Int) -> Int {
        switch month {
        case 1, 3, 5, 7, 8, 10, 12:
            return 31
        case 4, 6, 9, 11:
            return 30
        case 2:
            let leap = (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
            return leap ? 29 : 28
        default:
            return 0
        }
    }

    /// `days` after `day`, counted on the Gregorian calendar in UTC, where every day is 24 hours.
    public static func adding(days: Int, to day: CalendarDay) -> CalendarDay? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        guard let start = calendar.date(from: DateComponents(year: day.year, month: day.month, day: day.day)),
            let moved = calendar.date(byAdding: .day, value: days, to: start)
        else {
            return nil
        }
        let parts = calendar.dateComponents([.year, .month, .day], from: moved)
        guard let year = parts.year, let month = parts.month, let dayOfMonth = parts.day else {
            return nil
        }
        return CalendarDay(year: year, month: month, day: dayOfMonth)
    }

    private static let utc = TimeZone(identifier: "UTC") ?? TimeZone(secondsFromGMT: 0)!
}
