import Foundation

/// The calendar days behind a transaction's date (D229.4, D230.1). The editor shows a record's own day, the day in
/// its stored zone, and a picked day replaces that day, in that zone, keeping the time of day. A stored zone that
/// isn't recognised reads as UTC, as in the lists (`TransactionCalendar.storedTimeZone`).
@MainActor
public protocol TransactionDateUseCase {
    /// The zone a record with this stored zone ID is read in: that zone, or UTC when it isn't recognised.
    func storedTimeZone(_ timeZoneID: String) -> TimeZone
    /// The day `date` falls on in `storedTimeZone(timeZoneID)`.
    func day(of date: Date, timeZoneID: String) -> CalendarDay
    /// Noon on `day` in `storedTimeZone(timeZoneID)`: a moment that reads as `day` there, for a date picker.
    func noon(on day: CalendarDay, timeZoneID: String) -> Date
    /// `date` moved to `day` in `storedTimeZone(timeZoneID)`, keeping its time of day there; unchanged only when
    /// it's already on `day`. See `TransactionCalendar.date(_:movedTo:timeZoneID:)`.
    func date(_ date: Date, movedTo day: CalendarDay, timeZoneID: String) -> Date
}

@MainActor
public struct DefaultTransactionDateUseCase: TransactionDateUseCase {
    public init() {}

    public func storedTimeZone(_ timeZoneID: String) -> TimeZone {
        TransactionCalendar.storedTimeZone(timeZoneID)
    }

    public func day(of date: Date, timeZoneID: String) -> CalendarDay {
        TransactionCalendar.ownDay(of: date, timeZoneID: timeZoneID)
    }

    public func noon(on day: CalendarDay, timeZoneID: String) -> Date {
        let zone = TransactionCalendar.storedTimeZone(timeZoneID)
        // Noon exists on every day in every zone.
        return TransactionCalendar.noon(on: day, timeZoneID: zone.identifier)!
    }

    public func date(_ date: Date, movedTo day: CalendarDay, timeZoneID: String) -> Date {
        TransactionCalendar.date(date, movedTo: day, timeZoneID: timeZoneID)
    }
}
