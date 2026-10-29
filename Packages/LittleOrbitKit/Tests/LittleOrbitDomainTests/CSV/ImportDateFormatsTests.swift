import Foundation
import LittleOrbitDomain
import Testing

/// More date layouts (#189 I15, D387.6): month names in English and in the device's language, full or short and
/// in any case; compact year-first dates; two-digit years in 2000–2099. Reading never depends on the region.
@Suite("Import date formats (#189 I15)")
struct ImportDateFormatsTests {
    private static let fifthOfNovember = ImportWallTime(year: 2026, month: 11, day: 5)
    private static let german = ImportMonthNames(preferredLanguage: "de-DE")

    @Test(
        "I15: each layout reads as 5 Nov 2026 under every order",
        arguments: ["5 Nov 2026", "Nov 5, 2026", "20261105", "05-Nov-26"],
    )
    func layouts(text: String) {
        for order in ImportDateOrder.allCases {
            #expect(ImportDateParser.wallTime(text, order: order, months: .english) == Self.fifthOfNovember)
        }
    }

    @Test(
        "English month names are read full or short, in any case",
        arguments: ["5 NOVEMBER 2026", "5 november 2026", "5 nov 2026", "NOV 5, 2026", "2026 Nov 5"],
    )
    func englishAnyCase(text: String) {
        #expect(ImportDateParser.wallTime(text, order: .dayMonthYear, months: .english) == Self.fifthOfNovember)
    }

    @Test(
        "I15: with the language set to German, German names read too, full or short, with or without dots",
        arguments: [
            ("5. Nov. 2026", 11), ("5 November 2026", 11), ("5. Okt. 2026", 10), ("5 Oktober 2026", 10),
            ("5. März 2026", 3), ("5. MÄRZ 2026", 3), ("5 Mär 2026", 3), ("5. Dez. 2026", 12),
            ("5. Januar 2026", 1), ("5 Sept. 2026", 9), ("Mai 5, 2026", 5),
        ],
    )
    func german(text: String, month: Int) {
        for order in ImportDateOrder.allCases {
            #expect(
                ImportDateParser.wallTime(text, order: order, months: Self.german)
                    == ImportWallTime(year: 2026, month: month, day: 5)
            )
        }
    }

    @Test(
        "Short names whose only form ends in a dot read too (French)",
        arguments: [("5 févr. 2026", 2), ("5 FÉVR 2026", 2), ("5 juil. 2026", 7), ("5 décembre 2026", 12)],
    )
    func french(text: String, month: Int) {
        let french = ImportMonthNames(preferredLanguage: "fr-FR")
        #expect(ImportDateParser.wallTime(text, order: .dayMonthYear, months: french)?.month == month)
    }

    @Test("German names aren't read when the language is English", arguments: ["5. Okt. 2026", "5 Dezember 2026"])
    func germanNeedsGerman(text: String) {
        #expect(ImportDateParser.wallTime(text, order: .dayMonthYear, months: .english) == nil)
    }

    @Test("English names still read when the language is German")
    func englishWithGerman() {
        #expect(ImportDateParser.wallTime("Oct 5, 2026", order: .monthDayYear, months: Self.german)?.month == 10)
        #expect(ImportDateParser.wallTime("5 December 2026", order: .dayMonthYear, months: Self.german)?.month == 12)
    }

    @Test("I15: only the language counts, never the region")
    func regionIndependent() {
        #expect(ImportMonthNames(preferredLanguage: "de-CH") == Self.german)
        #expect(ImportMonthNames(preferredLanguage: "de-IN") == Self.german)
        #expect(ImportMonthNames(preferredLanguage: "de-AT") == Self.german)
        #expect(ImportMonthNames(preferredLanguage: "de") == Self.german)
        #expect(ImportMonthNames(preferredLanguage: "en-IN") == .english)
        #expect(ImportMonthNames(preferredLanguage: "en-US") == .english)
        #expect(ImportMonthNames(preferredLanguage: nil) == .english)
        // The region still only breaks ties between numeric orders; a named date reads the same everywhere.
        for locale in [Locale(identifier: "de_DE"), Locale(identifier: "de_CH"), Locale(identifier: "en_US")] {
            let detection = ImportDateParser.detect(["5. Okt. 2026"], locale: locale, months: Self.german)
            let read = ImportDateParser.wallTime("5. Okt. 2026", order: detection.order, months: Self.german)
            #expect(read == ImportWallTime(year: 2026, month: 10, day: 5))
        }
    }

    @Test("The device's month names follow its first preferred language")
    func device() {
        #expect(ImportMonthNames.device == ImportMonthNames(preferredLanguage: Locale.preferredLanguages.first))
    }

    @Test("Compact dates are year first, with an optional time")
    func compact() {
        #expect(
            ImportDateParser.wallTime("20261105 18:30", order: .dayMonthYear, months: .english)
                == ImportWallTime(year: 2026, month: 11, day: 5, hour: 18, minute: 30)
        )
        #expect(
            ImportDateParser.wallTime("20240229", order: .monthDayYear, months: .english)
                == ImportWallTime(year: 2024, month: 2, day: 29)
        )
    }

    @Test(
        "Compact text that isn't a year-first date isn't read",
        arguments: ["05112026", "20261305", "20250229", "2026110", "202611050", "2026115a"],
    )
    func compactImpossible(text: String) {
        for order in ImportDateOrder.allCases {
            #expect(ImportDateParser.wallTime(text, order: order, months: .english) == nil)
        }
    }

    @Test(
        "Two-digit years are 2000–2099",
        arguments: [("05-Nov-00", 2000), ("05-Nov-26", 2026), ("05-Nov-99", 2099)],
    )
    func twoDigitYears(text: String, year: Int) {
        #expect(ImportDateParser.wallTime(text, order: .dayMonthYear, months: .english)?.year == year)
        #expect(ImportDateParser.wallTime("05/11/\(text.suffix(2))", order: .dayMonthYear)?.year == year)
    }

    @Test("A file of these layouts reads through the generic format with the settings' month names")
    func throughFormat() throws {
        let text = """
            Date,Amount,Description
            5. Okt. 2026,-120.50,Bakery run
            20261105,-80.00,Bus pass
            "Nov 6, 2026",-15.00,Tea
            """
        let table = try CSVReader.read(text)
        var settings = ImportFixture.settings(table.header, order: .dayMonthYear)
        settings.monthNames = Self.german
        let rows = GenericCSVFormat().rows(from: table, settings: settings)
        let expected = [
            ImportFixture.date(2026, 10, 5),
            ImportFixture.date(2026, 11, 5),
            ImportFixture.date(2026, 11, 6),
        ]
        #expect(rows.map(\.date) == expected)
        settings.monthNames = .english
        #expect(GenericCSVFormat().rows(from: table, settings: settings).first?.date == nil)
    }

    @Test("Read settings use the device's month names unless told otherwise")
    func settingsDefault() {
        let settings = ImportFixture.settings(["Date"])
        #expect(settings.monthNames == .device)
    }
}
