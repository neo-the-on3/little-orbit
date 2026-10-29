import Foundation
import LittleOrbitDomain
import Testing

/// Whether a file's dates need an order picked at all (#189 I15, D453.3): when no date could be read two ways,
/// such as only named months or compact dates, there's nothing to choose.
@Suite("Import date order need (#189 I15, D453.3)")
struct ImportDateOrderNeedTests {
    private static let usa = Locale(identifier: "en_US")
    private static let german = ImportMonthNames(preferredLanguage: "de-DE")

    @Test(
        "Named-month and compact dates don't need an order",
        arguments: [
            ["5 Nov 2026", "20261105", "Nov 6, 2026"],
            ["5 Nov 2026", "Nov 6, 2026", "20261107", "08-Nov-26"],
            ["20261105 18:30", "2026 Nov 6"],
            ["5. Okt. 2026", "6 Dezember 2026", "", "  "],
        ],
    )
    func orderFree(samples: [String]) {
        let detection = ImportDateParser.detect(samples, locale: Self.usa, months: Self.german)
        #expect(!detection.ordersMatter)
        #expect(!detection.isAmbiguous)
        #expect(detection.candidates.count == 3)
    }

    @Test(
        "One numeric, unreadable or missing date means the order matters",
        arguments: [
            ["5 Nov 2026", "05/11/2026"],
            ["20261105", "2026-11-05"],
            ["5 Nov 2026", "today"],
            ["05/11/2026", "06/11/2026"],
            [],
            ["", " "],
        ],
    )
    func orderMatters(samples: [String]) {
        let detection = ImportDateParser.detect(samples, locale: Self.usa, months: Self.german)
        #expect(detection.ordersMatter)
    }

    @Test("A numeric file that several orders read is still ambiguous")
    func numericAmbiguous() {
        let detection = ImportDateParser.detect(["01/02/2026", "03/04/2026"], locale: Self.usa, months: .english)
        #expect(detection.ordersMatter)
        #expect(detection.isAmbiguous)
    }

    @Test("A detection built without saying so needs an order, as before")
    func defaultNeedsOrder() {
        let detection = ImportDateDetection(order: .dayMonthYear, candidates: [.dayMonthYear, .monthDayYear])
        #expect(detection.ordersMatter)
        #expect(detection.isAmbiguous)
    }
}
