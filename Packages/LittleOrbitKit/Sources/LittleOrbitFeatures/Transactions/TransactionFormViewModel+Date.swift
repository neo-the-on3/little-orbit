import Foundation
import LittleOrbitDomain

/// The date row: the record's own day in its stored zone, in the label and the picker (D229.4), and a picked day
/// set in that zone, keeping the time of day (D230.1, D232). New and existing records take the same path.
extension TransactionFormViewModel {
    /// "21 October 2026": the date in full, in the entry's time zone, for VoiceOver (UI Designer, #87 UI3).
    public var dateSpokenText: String {
        var style = Date.FormatStyle(date: .long, time: .omitted, locale: locale)
        style.timeZone = dates.storedTimeZone(timeZoneID)
        return date.formatted(style)
    }

    public var dateText: String {
        text.relativeDate(ownDay, today: TransactionTiming.today(now(), timeZone: timeZone))
    }

    /// The record's own day: its date in its stored zone, which the label and the picker show (D229.4). A zone
    /// that isn't recognised reads as UTC, the same day the lists show.
    public var ownDay: CalendarDay {
        dates.day(of: date, timeZoneID: timeZoneID)
    }

    /// The zone the date picker works in: the device's. `pickerDate` converts to and from the record's own day.
    public var pickerTimeZone: TimeZone { timeZone }

    /// What the date picker shows and sets. It reads as the record's own day in `pickerTimeZone`, so the picker
    /// never shows the device's day for a record stored in another zone (D229.4). Picking a day moves the record
    /// to that day in its stored zone, keeping the zone and the time of day there (D230.1); the moment the picker
    /// hands back is only read for its day.
    public var pickerDate: Date {
        get { dates.noon(on: ownDay, timeZoneID: pickerTimeZone.identifier) }
        set {
            let picked = dates.day(of: newValue, timeZoneID: pickerTimeZone.identifier)
            date = dates.date(date, movedTo: picked, timeZoneID: timeZoneID)
        }
    }
}
