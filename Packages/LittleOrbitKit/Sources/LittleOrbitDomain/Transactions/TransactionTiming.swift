import Foundation

/// When a transaction counts toward the current balance (D21).
///
/// A transaction counts once its calendar day, in the time zone it was entered in, is today or earlier.
/// "Today" is the device's calendar day. Later ones are Upcoming: listed at the top of the history with a
/// projected balance, and left out of the current balance until their day.
public enum TransactionTiming {
    public static func today(_ now: Date, timeZone: TimeZone = .current) -> CalendarDay {
        TransactionCalendar.calendarDay(of: now, timeZoneID: timeZone.identifier)
            ?? TransactionCalendar.calendarDay(of: now, timeZoneID: "UTC")!
    }

    /// The transaction's own day, falling back to UTC for an unknown time zone.
    public static func day(of transaction: Transaction) -> CalendarDay {
        TransactionCalendar.calendarDay(of: transaction)
            ?? TransactionCalendar.calendarDay(of: transaction.date, timeZoneID: "UTC")!
    }

    public static func isUpcoming(_ transaction: Transaction, today: CalendarDay) -> Bool {
        day(of: transaction) > today
    }

    public static func dated(upTo today: CalendarDay, _ transactions: [Transaction]) -> [Transaction] {
        transactions.filter { !isUpcoming($0, today: today) }
    }
}
