import Foundation
import LittleOrbitDomain
import Testing

/// Dates by order, detection with the region as tie-break, and DST (#30 AC 4, D39, S10–S11, S27).
@Suite("Import date parsing (#30)")
struct ImportDateParserTests {
    @Test("Each order reads its own numeric form, with or without a time")
    func orders() {
        #expect(
            ImportDateParser.wallTime("20/10/2026", order: .dayMonthYear)
                == ImportWallTime(year: 2026, month: 10, day: 20)
        )
        #expect(
            ImportDateParser.wallTime("10/20/2026", order: .monthDayYear)
                == ImportWallTime(year: 2026, month: 10, day: 20)
        )
        #expect(
            ImportDateParser.wallTime("2026-10-20 18:30:05", order: .yearMonthDay)
                == ImportWallTime(year: 2026, month: 10, day: 20, hour: 18, minute: 30, second: 5)
        )
        #expect(
            ImportDateParser.wallTime("2026-10-20T07:15", order: .yearMonthDay)
                == ImportWallTime(year: 2026, month: 10, day: 20, hour: 7, minute: 15)
        )
        #expect(
            ImportDateParser.wallTime("20-10-26 7:05 PM", order: .dayMonthYear)
                == ImportWallTime(year: 2026, month: 10, day: 20, hour: 19, minute: 5)
        )
        #expect(
            ImportDateParser.wallTime("20 Oct 2026", order: .dayMonthYear)
                == ImportWallTime(year: 2026, month: 10, day: 20)
        )
    }

    @Test("Impossible dates aren't read", arguments: ["31/02/2026", "29/02/2025", "2026-13-01", "today", "20/10", ""])
    func impossible(text: String) {
        #expect(ImportDateParser.wallTime(text, order: .dayMonthYear) == nil)
        #expect(ImportDateParser.wallTime(text, order: .yearMonthDay) == nil)
    }

    @Test("A day over 12 settles the order; otherwise the region's order wins and it's flagged ambiguous")
    func detection() {
        let india = Locale(identifier: "en_IN")
        let usa = Locale(identifier: "en_US")
        #expect(ImportDateParser.detect(["01/02/2026", "13/02/2026"], locale: usa).order == .dayMonthYear)
        #expect(ImportDateParser.detect(["01/02/2026", "13/02/2026"], locale: usa).isAmbiguous == false)
        let ambiguous = ImportDateParser.detect(["01/02/2026", "03/04/2026"], locale: india)
        #expect(ambiguous.order == .dayMonthYear)
        #expect(ambiguous.isAmbiguous)
        #expect(ImportDateParser.detect(["01/02/2026"], locale: usa).order == .monthDayYear)
        #expect(ImportDateParser.detect(["2026-10-20"], locale: usa).order == .yearMonthDay)
    }

    @Test("D39: a time in a DST gap moves forward; a repeated hour takes the first occurrence")
    func daylightSaving() throws {
        let newYork = try #require(TimeZone(identifier: "America/New_York"))
        let gap = ImportDateParser.date(
            ImportWallTime(year: 2026, month: 3, day: 8, hour: 2, minute: 30),
            in: newYork,
        )
        let afterGap = ImportDateParser.date(
            ImportWallTime(year: 2026, month: 3, day: 8, hour: 3, minute: 30),
            in: newYork,
        )
        #expect(gap == afterGap)
        let overlap = ImportDateParser.date(
            ImportWallTime(year: 2026, month: 11, day: 1, hour: 1, minute: 30),
            in: newYork,
        )
        // The first 1:30 is still daylight time, UTC−4.
        #expect(overlap == Date(timeIntervalSince1970: 1_793_511_000))
    }
}
