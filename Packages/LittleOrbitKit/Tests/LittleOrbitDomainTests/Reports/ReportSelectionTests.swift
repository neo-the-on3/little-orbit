import Foundation
import LittleOrbitDomain
import Testing

@Suite("Report periods: quarters, ‹ › stepping and custom ranges (#184)")
struct ReportSelectionTests {
    typealias F = TransactionFixture  // swiftlint:disable:this type_name

    @Test("Given 25 Oct 2026, This Quarter is 1 Oct–31 Dec 2026 and Last Quarter is 1 Jul–30 Sep 2026")
    func quarters() {
        let today = F.day(2026, 10, 25)
        #expect(
            ReportPeriod.thisQuarter.range(today: today)
                == .init(start: F.day(2026, 10, 1), end: F.day(2026, 12, 31))
        )
        #expect(
            ReportPeriod.lastQuarter.range(today: today) == .init(start: F.day(2026, 7, 1), end: F.day(2026, 9, 30))
        )
        #expect(ReportPeriod.thisQuarter.length == .quarter)
    }

    @Test("Last Quarter in February is the previous year's Q4; Q1 of a leap year ends 31 Mar")
    func quarterEdges() {
        #expect(
            ReportPeriod.lastQuarter.range(today: F.day(2027, 2, 10))
                == .init(start: F.day(2026, 10, 1), end: F.day(2026, 12, 31))
        )
        #expect(ReportDayRange.quarter(year: 2028, quarter: 1).end == F.day(2028, 3, 31))
        #expect(ReportDayRange.quarter(of: 1) == 1)
        #expect(ReportDayRange.quarter(of: 12) == 4)
    }

    @Test("Given October 2026, › shows November 2026 and ‹ goes back to October 2026")
    func stepMonth() {
        let today = F.day(2026, 10, 25)
        let next = ReportSelection.default.stepped(by: 1)
        #expect(next.range(today: today) == .init(start: F.day(2026, 11, 1), end: F.day(2026, 11, 30)))
        #expect(next.stepped(by: -1).range(today: today) == ReportPeriod.thisMonth.range(today: today))
        #expect(next.preset == .thisMonth)
    }

    @Test("Stepping crosses years: back from January is December, a quarter moves 3 months, a year moves 1")
    func stepAcrossYears() {
        let today = F.day(2027, 1, 5)
        #expect(
            ReportSelection.preset(.thisMonth, offset: -1).range(today: today)
                == .init(start: F.day(2026, 12, 1), end: F.day(2026, 12, 31))
        )
        #expect(
            ReportSelection.preset(.thisQuarter, offset: -2).range(today: today)
                == .init(start: F.day(2026, 7, 1), end: F.day(2026, 9, 30))
        )
        #expect(ReportSelection.preset(.lastYear, offset: 1).range(today: today) == .year(2027))
        #expect(ReportSelection.preset(.thisMonth, offset: -14).range(today: today).start == F.day(2025, 11, 1))
    }

    @Test("A custom range keeps both end days, reads an end-first range start first, and doesn't step")
    func custom() {
        let today = F.day(2026, 10, 25)
        let range = ReportDayRange(start: F.day(2026, 9, 15), end: F.day(2026, 10, 14))
        #expect(ReportSelection.custom(range).range(today: today) == range)
        #expect(
            ReportSelection.custom(.init(start: range.end, end: range.start)).range(today: today) == range
        )
        #expect(ReportSelection.custom(range).stepped(by: 1) == .custom(range))
        #expect(range.stepped(by: -1) == range)
        #expect(!ReportSelection.custom(range).canStep)
        #expect(ReportSelection.default.canStep)
        #expect(ReportSelection.custom(range).preset == nil)
    }

    @Test("A range's shape names it: month, quarter, year or days")
    func shapes() {
        #expect(ReportDayRange.month(year: 2026, month: 2).shape == .month)
        #expect(ReportDayRange.quarter(year: 2026, quarter: 4).shape == .quarter(4))
        #expect(ReportDayRange.year(2026).shape == .year)
        #expect(ReportDayRange(start: F.day(2026, 9, 15), end: F.day(2026, 10, 14)).shape == .days)
        #expect(ReportDayRange(start: F.day(2026, 2, 1), end: F.day(2026, 4, 30)).shape == .days)
    }
}
