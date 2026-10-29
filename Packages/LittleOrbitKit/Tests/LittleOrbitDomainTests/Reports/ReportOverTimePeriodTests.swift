import Foundation
import LittleOrbitDomain
import Testing

/// The over-time reports' periods (#184 slice 5): Last 6 Months by default, This Year, Last Year and Custom…,
/// each split into calendar months.
@Suite("Over-time report periods: Last 6 Months and month buckets (#184 slice 5)")
struct ReportOverTimePeriodTests {
    typealias F = TransactionFixture  // swiftlint:disable:this type_name

    @Test("Given 25 Oct 2026, Last 6 Months is 1 May–31 Oct 2026, this month included")
    func lastSixMonths() {
        let range = ReportPeriod.lastSixMonths.range(today: F.day(2026, 10, 25))
        #expect(range == .init(start: F.day(2026, 5, 1), end: F.day(2026, 10, 31)))
        #expect(range.shape == .months(6))
        #expect(ReportPeriod.lastSixMonths.length == .sixMonths)
    }

    @Test("‹ steps Last 6 Months back six whole months, across a year end, and › comes back")
    func stepSixMonths() {
        let today = F.day(2026, 10, 25)
        let back = ReportSelection.preset(.lastSixMonths).stepped(by: -1)
        #expect(back.range(today: today) == .init(start: F.day(2025, 11, 1), end: F.day(2026, 4, 30)))
        #expect(back.stepped(by: 1).range(today: today) == ReportPeriod.lastSixMonths.range(today: today))
        #expect(
            ReportPeriod.lastSixMonths.range(today: F.day(2027, 2, 3))
                == .init(start: F.day(2026, 9, 1), end: F.day(2027, 2, 28))
        )
    }

    @Test("The spending reports keep their presets; the over-time reports offer Last 6 Months, This Year, Last Year")
    func presets() {
        #expect(
            ReportPeriod.categoryPresets == [.thisMonth, .lastMonth, .thisQuarter, .lastQuarter, .thisYear, .lastYear]
        )
        #expect(ReportPeriod.overTimePresets == [.lastSixMonths, .thisYear, .lastYear])
    }

    @Test("A range's months: whole months, and a custom range's first and last months only their included days")
    func months() {
        #expect(ReportDayRange.year(2026).months.count == 12)
        let custom = ReportDayRange(start: F.day(2026, 9, 15), end: F.day(2026, 11, 10))
        #expect(
            custom.months == [
                .init(start: F.day(2026, 9, 15), end: F.day(2026, 9, 30)),
                .month(year: 2026, month: 10),
                .init(start: F.day(2026, 11, 1), end: F.day(2026, 11, 10)),
            ]
        )
        #expect(ReportDayRange(start: F.day(2026, 10, 3), end: F.day(2026, 10, 9)).months.count == 1)
    }

    @Test("Whole months that aren't a month, quarter or year are their own shape, and step by their length")
    func monthsShape() {
        let range = ReportDayRange(start: F.day(2025, 12, 1), end: F.day(2026, 2, 28))
        #expect(range.shape == .months(3))
        #expect(range.stepped(by: 1) == .init(start: F.day(2026, 3, 1), end: F.day(2026, 5, 31)))
        #expect(ReportDayRange(start: F.day(2026, 9, 15), end: F.day(2026, 10, 14)).shape == .days)
        #expect(ReportDayRange.quarter(year: 2026, quarter: 4).shape == .quarter(4))
    }
}
