import Foundation

/// A calendar day in a named time zone. Grouping uses this instead of the device's current zone,
/// so a transaction does not change day when the user travels.
public struct CalendarDay: Hashable, Sendable, Codable, Comparable {
    public var year: Int
    public var month: Int
    public var day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    public static func < (lhs: CalendarDay, rhs: CalendarDay) -> Bool {
        if lhs.year != rhs.year {
            return lhs.year < rhs.year
        }
        if lhs.month != rhs.month {
            return lhs.month < rhs.month
        }
        return lhs.day < rhs.day
    }
}

public struct TransactionDayGroup: Equatable, Sendable {
    public var day: CalendarDay
    public var transactions: [Transaction]

    public init(day: CalendarDay, transactions: [Transaction]) {
        self.day = day
        self.transactions = transactions
    }
}

public enum TransactionCalendar {
    /// The zone a record's own day is read and set in: its stored zone, or UTC when `timeZoneID` isn't a zone
    /// Foundation recognises (an empty or unknown ID). Lists, the editor, refund dating and day changes all use
    /// this one fallback, so a record shows, sorts and is checked on the same day everywhere.
    public static func storedTimeZone(_ timeZoneID: String) -> TimeZone {
        TimeZone(identifier: timeZoneID) ?? utc
    }

    /// The record's own day: `date`'s calendar day in `storedTimeZone(timeZoneID)`.
    public static func ownDay(of date: Date, timeZoneID: String) -> CalendarDay {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = storedTimeZone(timeZoneID)
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return CalendarDay(year: parts.year ?? 1970, month: parts.month ?? 1, day: parts.day ?? 1)
    }

    private static let utc = TimeZone(identifier: "UTC") ?? TimeZone(secondsFromGMT: 0)!

    public static func calendarDay(of date: Date, timeZoneID: String) -> CalendarDay? {
        guard let timeZone = TimeZone(identifier: timeZoneID) else {
            return nil
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = parts.year, let month = parts.month, let day = parts.day else {
            return nil
        }
        return CalendarDay(year: year, month: month, day: day)
    }

    public static func calendarDay(of transaction: Transaction) -> CalendarDay? {
        calendarDay(of: transaction.date, timeZoneID: transaction.timeZoneID)
    }

    /// Noon in `timeZoneID` on `day`. Used when the user picks a date and no time.
    public static func noon(on day: CalendarDay, timeZoneID: String) -> Date? {
        guard let timeZone = TimeZone(identifier: timeZoneID) else {
            return nil
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.date(
            from: DateComponents(
                timeZone: timeZone,
                year: day.year,
                month: day.month,
                day: day.day,
                hour: 12,
                minute: 0,
                second: 0,
            )
        )
    }

    /// Groups by each transaction's own time zone (UTC for one that isn't recognised, `storedTimeZone`). Days are newest first. Device time zone is ignored.
    public static func groups(_ transactions: [Transaction]) -> [TransactionDayGroup] {
        var buckets: [CalendarDay: [Transaction]] = [:]
        for transaction in transactions where transaction.deletedAt == nil {
            buckets[ownDay(of: transaction.date, timeZoneID: transaction.timeZoneID), default: []].append(transaction)
        }
        return buckets.keys.sorted(by: >)
            .map { day in
                let items = (buckets[day] ?? [])
                    .sorted { lhs, rhs in
                        if lhs.date != rhs.date {
                            return lhs.date > rhs.date
                        }
                        return lhs.id.uuidString < rhs.id.uuidString
                    }
                return TransactionDayGroup(day: day, transactions: items)
            }
    }
}
