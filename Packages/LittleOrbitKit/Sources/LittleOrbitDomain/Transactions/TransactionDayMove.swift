import Foundation

extension TransactionCalendar {
    /// `date` moved to `day` in the zone `storedTimeZone(timeZoneID)`, keeping its time of day there (D230.1).
    ///
    /// The result is on `day` when read in that zone, whatever zone the device is in, so a record keeps its
    /// stored zone and its place within the day. When that time of day doesn't exist on `day` (a daylight-saving
    /// gap), the result is the first valid moment after the gap. When it exists twice (the clocks go back), the
    /// result is the first of the two. `date` comes back unchanged only when it's already on `day`; an unknown
    /// zone uses UTC, so a pick always lands.
    ///
    /// It knows nothing about transactions, so the single editor (#131) and a bulk Date change can share it.
    public static func date(_ date: Date, movedTo day: CalendarDay, timeZoneID: String) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = storedTimeZone(timeZoneID)
        let time = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        guard time.year != day.year || time.month != day.month || time.day != day.day else {
            return date
        }
        // Noon is never in a daylight-saving gap, and the day's first moment comes from it. In a zone whose clocks
        // jump at midnight (America/Santiago), that first moment is 01:00.
        let noon = calendar.date(from: DateComponents(year: day.year, month: day.month, day: day.day, hour: 12))!
        let start = calendar.startOfDay(for: noon)
        let moved = moment(at: time, onDayStarting: start, in: calendar, keepingFractionOf: date)
        // Whatever the zone's rules, the result is on the picked day.
        return calendar.isDate(moved, inSameDayAs: noon) ? moved : start
    }

    private static func moment(
        at time: DateComponents,
        onDayStarting start: Date,
        in calendar: Calendar,
        keepingFractionOf date: Date,
    ) -> Date {
        let wanted = DateComponents(hour: time.hour, minute: time.minute, second: time.second)
        let first = calendar.nextDate(after: start.addingTimeInterval(-1), matching: wanted, matchingPolicy: .nextTime)
        if let first, calendar.isDate(first, inSameDayAs: start) {
            let read = calendar.dateComponents([.hour, .minute, .second], from: first)
            guard read.hour == time.hour, read.minute == time.minute, read.second == time.second else {
                return gapEnd(on: start, in: calendar) ?? first
            }
            // Keep the fraction of a second too, so nothing but the day moves.
            let seconds = date.timeIntervalSinceReferenceDate
            return first.addingTimeInterval(seconds - seconds.rounded(.down))
        }
        return gapEnd(on: start, in: calendar) ?? start
    }

    /// A gap: the clocks jump past the wanted time on the day starting at `start`, so the first valid moment
    /// after it is the moment they jump to.
    private static func gapEnd(on start: Date, in calendar: Calendar) -> Date? {
        guard let jump = calendar.timeZone.nextDaylightSavingTimeTransition(after: start),
            calendar.isDate(jump, inSameDayAs: start)
        else {
            return nil
        }
        return jump
    }
}
