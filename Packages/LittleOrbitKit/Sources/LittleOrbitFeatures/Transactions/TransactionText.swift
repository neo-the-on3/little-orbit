import Foundation
import LittleOrbitDomain

/// Dates and labels shared by the history, the entry sheet and the macOS table.
struct TransactionText {
    let locale: Locale
    /// Made once per text, so rows don't each make a `DateFormatter` (N5).
    private let formatters: DayFormatters

    init(locale: Locale) {
        self.locale = locale
        formatters = DayFormatters(locale: locale)
    }

    static let uncategorised = "Uncategorised"
    static let transfer = "Transfer"

    /// "Today · Tue, 20 Oct", "Yesterday · Mon, 19 Oct", "Sun, 18 Oct", or "Wed, 31 Dec 2025" in another year.
    func dayTitle(_ day: CalendarDay, today: CalendarDay) -> String {
        let template = day.year == today.year ? "EEEdMMM" : "EEEdMMMyyyy"
        let text = format(day, template: template)
        if day == today {
            return "Today · \(text)"
        }
        if day == Self.adding(-1, to: today) {
            return "Yesterday · \(text)"
        }
        return text
    }

    /// "3 Nov", with the year when it isn't this year. Used on Upcoming rows.
    func shortDate(_ day: CalendarDay, today: CalendarDay) -> String {
        format(day, template: day.year == today.year ? "dMMM" : "dMMMyyyy")
    }

    /// "20 Oct 2026", as in the macOS Date column.
    func fullDate(_ day: CalendarDay) -> String {
        format(day, template: "dMMMyyyy")
    }

    /// The entry sheet's Date row: Today, Yesterday, Tomorrow, or "3 Nov 2026".
    func relativeDate(_ day: CalendarDay, today: CalendarDay) -> String {
        switch day {
        case today: "Today"
        case Self.adding(-1, to: today): "Yesterday"
        case Self.adding(1, to: today): "Tomorrow"
        default: fullDate(day)
        }
    }

    func format(_ day: CalendarDay, template: String) -> String {
        guard let date = TransactionCalendar.noon(on: day, timeZoneID: "UTC") else {
            return "\(day.year)-\(day.month)-\(day.day)"
        }
        return formatters.string(from: date, template: template)
    }

    static func adding(_ days: Int, to day: CalendarDay) -> CalendarDay {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let start = calendar.date(from: DateComponents(year: day.year, month: day.month, day: day.day, hour: 12))!
        let moved = calendar.date(byAdding: .day, value: days, to: start)!
        let parts = calendar.dateComponents([.year, .month, .day], from: moved)
        return CalendarDay(year: parts.year!, month: parts.month!, day: parts.day!)
    }

    static func trimmed(_ text: String?) -> String? {
        guard let text else {
            return nil
        }
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
