import Foundation
import LittleOrbitDomain
import Testing

@testable import LittleOrbitFeatures

/// N5 on #286: `TransactionText` makes each `DateFormatter` once. The text is the same as a new formatter per call
/// gave, in every locale and template it uses, and the same from several threads at once.
@Suite("Transaction dates: one formatter per template")
struct TransactionTextFormatterTests {
    static let locales = ["en_GB", "en_US", "de_DE", "ja_JP", "ar_EG", "hi_IN"].map(Locale.init(identifier:))
    static let templates = ["EEEdMMM", "EEEdMMMyyyy", "dMMM", "dMMMyyyy"]
    static let days = [
        CalendarDay(year: 2026, month: 10, day: 27),
        CalendarDay(year: 2026, month: 1, day: 1),
        CalendarDay(year: 2025, month: 12, day: 31),
        CalendarDay(year: 2024, month: 2, day: 29),
        CalendarDay(year: 1999, month: 7, day: 4),
    ]

    /// The text as it was made before: a new formatter for each call.
    static func uncached(_ day: CalendarDay, template: String, locale: Locale) -> String {
        guard let date = TransactionCalendar.noon(on: day, timeZoneID: "UTC") else {
            return "\(day.year)-\(day.month)-\(day.day)"
        }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter.string(from: date)
    }

    @Test("Every locale, template and day reads as with a new formatter, the second time too")
    func sameText() {
        for locale in Self.locales {
            let text = TransactionText(locale: locale)
            for _ in 0..<2 {
                for template in Self.templates {
                    for day in Self.days {
                        #expect(
                            text.format(day, template: template)
                                == Self.uncached(day, template: template, locale: locale),
                            "\(locale.identifier) \(template) \(day)",
                        )
                    }
                }
            }
        }
    }

    @Test("Day titles, short and full dates match the uncached text")
    func helpers() {
        let locale = Locale(identifier: "en_GB")
        let text = TransactionText(locale: locale)
        let today = CalendarDay(year: 2026, month: 10, day: 27)
        let lastYear = CalendarDay(year: 2025, month: 3, day: 9)
        #expect(
            text.dayTitle(today, today: today) == "Today · "
                + Self.uncached(today, template: "EEEdMMM", locale: locale)
        )
        #expect(
            text.dayTitle(lastYear, today: today) == Self.uncached(lastYear, template: "EEEdMMMyyyy", locale: locale)
        )
        #expect(
            text.shortDate(lastYear, today: today) == Self.uncached(lastYear, template: "dMMMyyyy", locale: locale)
        )
        #expect(text.fullDate(today) == Self.uncached(today, template: "dMMMyyyy", locale: locale))
    }

    @Test("The same text from many threads at once")
    func concurrent() async {
        let locale = Locale(identifier: "de_DE")
        let text = TransactionText(locale: locale)
        let expected = Self.days.map { Self.uncached($0, template: "EEEdMMMyyyy", locale: locale) }
        let results = await withTaskGroup(of: [String].self) { group in
            for _ in 0..<16 {
                group.addTask {
                    (0..<50).flatMap { _ in Self.days.map { text.format($0, template: "EEEdMMMyyyy") } }
                }
            }
            return await group.reduce(into: []) { $0.append($1) }
        }
        #expect(results.count == 16)
        for result in results {
            #expect(result == Array((0..<50).map { _ in expected }.joined()))
        }
    }
}
