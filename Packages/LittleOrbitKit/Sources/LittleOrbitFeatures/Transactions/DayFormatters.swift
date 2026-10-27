import Foundation
import Synchronization

/// The date formatters one `TransactionText` uses, one per template, each made once (N5 on #286). Making a
/// `DateFormatter` and reading its template cost about as much as the rest of a register row, and a load made one
/// per row and per day. Each formats in the text's locale and in UTC, as before. A `TransactionText` keeps its
/// locale for its life (a view model makes one at init), so nothing here goes stale. Formatting runs under the lock,
/// so a load can run off the main actor without sharing a formatter between threads.
final class DayFormatters: Sendable {
    private let locale: Locale
    private let formatters = Mutex<[String: DateFormatter]>([:])

    init(locale: Locale) {
        self.locale = locale
    }

    func string(from date: Date, template: String) -> String {
        let locale = locale
        return formatters.withLock { formatters in
            let formatter: DateFormatter
            if let made = formatters[template] {
                formatter = made
            } else {
                formatter = DateFormatter()
                formatter.locale = locale
                formatter.timeZone = TimeZone(identifier: "UTC")
                formatter.setLocalizedDateFormatFromTemplate(template)
                formatters[template] = formatter
            }
            return formatter.string(from: date)
        }
    }
}
