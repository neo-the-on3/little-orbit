import Foundation
import LittleOrbitDomain
import Testing

/// Budget periods (#25; D24, D26, D60): each starts on the anchor day, or on the last day of a month without it,
/// and ends the day before the next one starts. Days are calendar days, so nothing depends on a time zone.
@Suite("Budget periods (#25)")
struct BudgetScheduleTests {
    private func day(_ year: Int, _ month: Int, _ day: Int) -> CalendarDay {
        CalendarDay(year: year, month: month, day: day)
    }

    private func ranges(_ schedule: BudgetSchedule, count: Int) -> [String] {
        (0..<count)
            .map { index in
                let period = schedule.period(index)
                return "\(text(period.start))–\(text(period.end))"
            }
    }

    private func text(_ day: CalendarDay) -> String {
        "\(day.year)-\(day.month)-\(day.day)"
    }

    @Test("S52, S47: monthly from 31 Jan 2027 runs 31 Jan–27 Feb, 28 Feb–30 Mar, … and the next starts 30 Jun")
    func monthlyFromThe31st() {
        let schedule = BudgetSchedule(startDay: day(2027, 1, 31), recurrence: .monthly)
        #expect(
            ranges(schedule, count: 5) == [
                "2027-1-31–2027-2-27",
                "2027-2-28–2027-3-30",
                "2027-3-31–2027-4-29",
                "2027-4-30–2027-5-30",
                "2027-5-31–2027-6-29",
            ]
        )
        #expect(schedule.period(5).start == day(2027, 6, 30))
    }

    @Test("S59: the same budget through the rest of 2027, and the next one starts 31 Jan 2028")
    func monthlyRestOfYear() {
        let schedule = BudgetSchedule(startDay: day(2027, 1, 31), recurrence: .monthly)
        let starts = (5...12).map { schedule.period($0).start }
        #expect(
            starts == [
                day(2027, 6, 30), day(2027, 7, 31), day(2027, 8, 31), day(2027, 9, 30), day(2027, 10, 31),
                day(2027, 11, 30), day(2027, 12, 31), day(2028, 1, 31),
            ]
        )
        #expect(schedule.period(11).end == day(2028, 1, 30))
    }

    @Test("S48, S53: in a leap year the February period starts 29 Feb")
    func leapYearFebruary() {
        let schedule = BudgetSchedule(startDay: day(2028, 1, 31), recurrence: .monthly)
        #expect(schedule.period(0).end == day(2028, 2, 28))
        #expect(schedule.period(1).start == day(2028, 2, 29))
        #expect(schedule.period(2).start == day(2028, 3, 31))
    }

    @Test("S49: budgets from 29 and 30 Jan 2027 both start February on 28 Feb, then keep their anchor")
    func anchorsKept() {
        for anchor in [29, 30] {
            let schedule = BudgetSchedule(startDay: day(2027, 1, anchor), recurrence: .monthly)
            #expect(schedule.period(1).start == day(2027, 2, 28))
            #expect(schedule.period(2).start == day(2027, 3, anchor))
        }
    }

    @Test("S57: anchored on the 30th from 30 Jan 2027 runs 30 Jan–27 Feb, 28 Feb–29 Mar")
    func anchoredOnThe30th() {
        let schedule = BudgetSchedule(startDay: day(2027, 1, 30), recurrence: .monthly)
        #expect(ranges(schedule, count: 2) == ["2027-1-30–2027-2-27", "2027-2-28–2027-3-29"])
    }

    @Test("S50: yearly from 29 Feb 2028 starts 28 Feb in other years and 29 Feb in 2032")
    func yearlyLeapDay() {
        let schedule = BudgetSchedule(startDay: day(2028, 2, 29), recurrence: .yearly)
        #expect(
            (1...4).map { schedule.period($0).start } == [
                day(2029, 2, 28), day(2030, 2, 28), day(2031, 2, 28), day(2032, 2, 29),
            ]
        )
    }

    @Test("S15: custom every 3 weeks from 2 Nov 2026 still runs on 22 Nov, and a new one starts 23 Nov")
    func customWeeks() {
        let schedule = BudgetSchedule(startDay: day(2026, 11, 2), recurrence: .custom(every: 3, unit: .week))
        #expect(schedule.period(containing: day(2026, 11, 22))?.index == 0)
        #expect(schedule.period(containing: day(2026, 11, 23))?.start == day(2026, 11, 23))
    }

    @Test("S26: fortnightly from 2 Nov 2026 starts new periods on 16 Nov and 30 Nov")
    func fortnightly() {
        let schedule = BudgetSchedule(startDay: day(2026, 11, 2), recurrence: .fortnightly)
        #expect(schedule.period(1).start == day(2026, 11, 16))
        #expect(schedule.period(2).start == day(2026, 11, 30))
        #expect(schedule.period(containing: day(2026, 11, 29))?.index == 1)
    }

    @Test("Weekly, custom days, months and years step from the start day")
    func otherSteps() {
        let weekly = BudgetSchedule(startDay: day(2026, 12, 28), recurrence: .weekly)
        #expect(weekly.period(1).start == day(2027, 1, 4))
        let days = BudgetSchedule(startDay: day(2026, 2, 27), recurrence: .custom(every: 10, unit: .day))
        #expect(days.period(1).start == day(2026, 3, 9))
        let months = BudgetSchedule(startDay: day(2026, 11, 30), recurrence: .custom(every: 3, unit: .month))
        #expect(months.period(1).start == day(2027, 2, 28))
        #expect(months.period(2).start == day(2027, 5, 30))
        let years = BudgetSchedule(startDay: day(2026, 3, 1), recurrence: .custom(every: 2, unit: .year))
        #expect(years.period(1).start == day(2028, 3, 1))
    }

    @Test("S54, S55, S58: boundary days count in the right period")
    func boundaries() {
        let schedule = BudgetSchedule(startDay: day(2027, 1, 31), recurrence: .monthly)
        #expect(schedule.period(containing: day(2027, 2, 27))?.start == day(2027, 1, 31))
        #expect(schedule.period(containing: day(2027, 2, 28))?.start == day(2027, 2, 28))
        #expect(schedule.period(containing: day(2027, 4, 29))?.start == day(2027, 3, 31))
        #expect(schedule.period(containing: day(2027, 4, 30))?.start == day(2027, 4, 30))
        #expect(schedule.period(containing: day(2027, 6, 29))?.start == day(2027, 5, 31))
        #expect(schedule.period(containing: day(2027, 6, 30))?.start == day(2027, 6, 30))
        #expect(schedule.period(containing: day(2030, 3, 15))?.start == day(2030, 2, 28))
    }

    @Test("A day before the start is in no period")
    func beforeStart() {
        let schedule = BudgetSchedule(startDay: day(2026, 11, 1), recurrence: .monthly)
        #expect(schedule.period(containing: day(2026, 10, 31)) == nil)
        #expect(schedule.period(containing: day(2026, 11, 1))?.index == 0)
    }

    @Test("S61, S56: time to the next period counts whole days, and before the start counts to the start")
    func daysUntilNext() {
        let schedule = BudgetSchedule(startDay: day(2027, 1, 31), recurrence: .monthly)
        #expect(schedule.daysUntilNextPeriod(today: day(2027, 2, 27)) == 1)
        #expect(schedule.daysUntilNextPeriod(today: day(2027, 2, 28)) == 31)
        #expect(schedule.daysUntilNextPeriod(today: day(2027, 5, 30)) == 1)
        #expect(schedule.daysUntilNextPeriod(today: day(2027, 6, 29)) == 1)
        #expect(schedule.daysUntilNextPeriod(today: day(2027, 1, 1)) == 30)
    }

    @Test("S60: period lengths are 28, 31, 30, 31 and 30 days")
    func lengths() {
        let schedule = BudgetSchedule(startDay: day(2027, 1, 31), recurrence: .monthly)
        #expect((0..<5).map { schedule.period($0).dayCount } == [28, 31, 30, 31, 30])
    }

    @Test("S16: custom counts 1 and 99 are valid, 0 and 100 aren't")
    func customRange() {
        for unit in BudgetRecurrenceUnit.allCases {
            #expect(BudgetRecurrence.custom(every: 1, unit: unit).isValid)
            #expect(BudgetRecurrence.custom(every: 99, unit: unit).isValid)
            #expect(!BudgetRecurrence.custom(every: 0, unit: unit).isValid)
            #expect(!BudgetRecurrence.custom(every: 100, unit: unit).isValid)
        }
    }
}
