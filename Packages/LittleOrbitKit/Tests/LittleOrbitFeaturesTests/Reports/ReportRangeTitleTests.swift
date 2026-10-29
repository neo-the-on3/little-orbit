import Foundation
import LittleOrbitDomain
import LittleOrbitFeatures
import Testing

/// A custom range's title (UI Designer's answer 6 on #321): months only when both ends are whole months, such as
/// “Sep – Nov 2026”, and full dates otherwise. This changes slice 1's custom ranges, which always showed full
/// dates. Made-up data only.
@MainActor
@Suite("Custom range titles (#184 slice 5, answer 6)")
struct ReportRangeTitleTests {
    typealias S = SpendingFixture  // swiftlint:disable:this type_name

    static func plain(_ text: String) -> String { SpendingReportFiltersTests.plain(text) }

    static func title(from start: Date, to end: Date) async -> String {
        let model = S.model(FakeSpendingReportUseCase(snapshot: S.snapshot([S.expense("100", S.rent, 10, 1)])))
        await model.load()
        await model.selectCustomRange(from: start, to: end)
        return plain(model.periodTitle)
    }

    @Test("Given a custom 1 Sep – 30 Nov 2026, when the spending report shows, then its title is Sep – Nov 2026")
    func wholeMonths() async {
        let title = await Self.title(from: S.date(9, 1), to: S.date(11, 30))
        // ICU versions spell September “Sep” or “Sept”.
        #expect(title.hasPrefix("Sep"))
        #expect(title.hasSuffix(" – Nov 2026"))
        #expect(!title.contains("1 "))
        #expect(!title.contains("30"))
    }

    @Test("Given a custom range that ends before a month's last day, then its title has full dates")
    func partEnd() async {
        let title = await Self.title(from: S.date(9, 1), to: S.date(11, 29))
        #expect(title.hasPrefix("1 Sep"))
        #expect(title.hasSuffix(" – 29 Nov 2026"))
    }

    @Test("Given a custom range that starts after a month's first day, then its title has full dates")
    func partStart() async {
        let title = await Self.title(from: S.date(9, 2), to: S.date(11, 30))
        #expect(title.hasPrefix("2 Sep"))
        #expect(title.hasSuffix(" – 30 Nov 2026"))
    }

    @Test("Given whole months across a new year, then the title names both years: Nov 2026 – Feb 2027")
    func acrossYears() async {
        let title = await Self.title(from: S.date(11, 1), to: S.date(2, 28, year: 2027))
        #expect(title == "Nov 2026 – Feb 2027")
    }

    @Test("Given a custom range of one whole month or a whole quarter, then it's titled as that month or quarter")
    func onePeriod() async {
        #expect(await Self.title(from: S.date(10, 1), to: S.date(10, 31)) == "October 2026")
        #expect(await Self.title(from: S.date(10, 1), to: S.date(12, 31)) == "Oct – Dec 2026")
    }
}
