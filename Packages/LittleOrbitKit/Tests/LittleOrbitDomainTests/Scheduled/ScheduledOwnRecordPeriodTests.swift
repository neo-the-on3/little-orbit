import Foundation
import LittleOrbitDomain
import Testing

/// D433.1 and D437.1 (#316 review): a day of the rule with its own record is that occurrence, so it's never passed
/// over, even when another occurrence of the item holds its period. An occurrence the user moved is kept where they
/// put it, so a move into a period that already has one never drops it. Days with no record of their own are still
/// passed over in a held period (D426.1). Made-up data: Rent ₹25,000 monthly, from Everyday Savings.
@Suite("A day with its own record is never passed over (D433.1)")
struct ScheduledOwnRecordPeriodTests {
    private typealias Fix = ScheduledFixture

    private static func rent(
        from start: CalendarDay,
        rule: ScheduleRepeat = .monthly,
        records: [(CalendarDay, ScheduledOutcome)],
    ) -> ScheduledItem {
        var item = Fix.rent(start: start, rule: rule, automatic: false)
        item.occurrences = records.map { day, outcome in
            ScheduledOccurrence(id: UUID(), day: day, outcome: outcome, createdAt: Fix.created)
        }
        return item
    }

    @Test("1 Oct paid, then 31 Oct pending on its own day on a rule from 31 Oct: 31 Oct is due, then 30 Nov")
    func pendingDayInHeldMonth() {
        let rent = Self.rent(
            from: Fix.day(2026, 10, 31),
            records: [(Fix.day(2026, 10, 1), .posted), (Fix.day(2026, 10, 31), .pending)],
        )
        let next = ScheduleCalendar.firstOccurrence(of: rent, onOrAfter: Fix.day(2026, 10, 20)) { !rent.isSettled($0) }
        #expect(next == Fix.day(2026, 10, 31))
        #expect(
            ScheduleCalendar.occurrences(of: rent, through: Fix.day(2026, 12, 31))
                == [Fix.day(2026, 10, 31), Fix.day(2026, 11, 30), Fix.day(2026, 12, 31)]
        )
        #expect(
            ScheduleCalendar.dueDays(of: rent, through: Fix.day(2026, 11, 30)) == [
                Fix.day(2026, 10, 31), Fix.day(2026, 11, 30),
            ]
        )
    }

    @Test("1 Oct and 5 Oct both paid on a rule from the 5th: 5 Oct stays an occurrence, and 5 Nov is next")
    func settledDayInHeldMonth() {
        let rent = Self.rent(
            from: Fix.day(2026, 8, 5),
            records: [(Fix.day(2026, 10, 1), .posted), (Fix.day(2026, 10, 5), .skipped)],
        )
        #expect(ScheduleCalendar.isOccurrence(Fix.day(2026, 10, 5), of: rent))
        #expect(
            ScheduleCalendar.occurrences(of: rent, through: Fix.day(2026, 11, 30)).suffix(2) == [
                Fix.day(2026, 10, 5), Fix.day(2026, 11, 5),
            ]
        )
        #expect(
            ScheduleCalendar.dueDays(of: rent, through: Fix.day(2026, 11, 30)).suffix(1) == [Fix.day(2026, 11, 5)]
        )
    }

    @Test("Every 3 months from 20 Mar with 15 Jan skipped and 20 Mar pending: 20 Mar is due, then 20 Jun")
    func everyThreeMonthsPendingDay() {
        let water = Self.rent(
            from: Fix.day(2027, 3, 20),
            rule: .every(3, .month),
            records: [(Fix.day(2027, 1, 15), .skipped), (Fix.day(2027, 3, 20), .pending)],
        )
        #expect(
            ScheduleCalendar.occurrences(of: water, through: Fix.day(2027, 9, 30))
                == [Fix.day(2027, 3, 20), Fix.day(2027, 6, 20), Fix.day(2027, 9, 20)]
        )
    }

    @Test("A day with no record of its own is still passed over in a held month (D426.1)")
    func dayWithoutRecordStillPassedOver() {
        let rent = Self.rent(from: Fix.day(2026, 8, 5), records: [(Fix.day(2026, 10, 1), .posted)])
        #expect(!ScheduleCalendar.isOccurrence(Fix.day(2026, 10, 5), of: rent))
    }

    @Test("A deleted record on the day is not its own record")
    func deletedOwnRecord() {
        var rent = Self.rent(
            from: Fix.day(2026, 8, 5),
            records: [(Fix.day(2026, 10, 1), .posted), (Fix.day(2026, 10, 5), .pending)],
        )
        rent.occurrences[1].deletedAt = Fix.created
        #expect(
            !ScheduleCalendar.occurrences(of: rent, through: Fix.day(2026, 10, 31)).contains(Fix.day(2026, 10, 5))
        )
    }
}
