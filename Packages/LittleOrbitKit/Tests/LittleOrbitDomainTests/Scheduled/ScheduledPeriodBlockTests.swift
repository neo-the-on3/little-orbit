import Foundation
import LittleOrbitDomain
import Testing

/// D428.1 and D429 (#312 item 2): for an every-N rule a period is the block of N units counted from the rule's
/// Starts date. Every 2 weeks is two ISO weeks (Monday first) from the week holding the Starts date, every 3 months
/// is three calendar months from the Starts month, and every 3 days is three calendar days from the Starts day. A
/// daily rule's period is its day, so it never skips one. After a Starts edit the blocks re-align to the new Starts,
/// and a new block that overlaps the old block of another occurrence gets no new one (D429.2). An occurrence's old
/// block is the N units from its own day's unit, because each day of a rule is the first unit of its block. Made-up
/// data: Rent ₹25,000 from Everyday Savings, with one record of another day of the item.
@Suite("Every-N rules take their period as N units from the Starts date (D428.1, D429)")
struct ScheduledPeriodBlockTests {
    private typealias Fix = ScheduledFixture

    private static func item(
        _ rule: ScheduleRepeat,
        from start: CalendarDay,
        recording day: CalendarDay,
    ) -> ScheduledItem {
        var item = Fix.rent(start: start, rule: rule)
        item.occurrences = [ScheduledOccurrence(id: UUID(), day: day, outcome: .posted, createdAt: Fix.created)]
        return item
    }

    @Test(
        "Every 2 weeks from Mon 2 Nov: 2–15 Nov is one period, 16–29 Nov the next",
        arguments: [
            // Wed 4 Nov's block is 2–15 Nov, the first one.
            (Fix.day(2026, 11, 4), [Fix.day(2026, 11, 16), Fix.day(2026, 11, 30)]),
            // Tue 10 Nov is in the first block's second week; its own block, 9–22 Nov, overlaps the second too.
            (Fix.day(2026, 11, 10), [Fix.day(2026, 11, 30)]),
            // Mon 16 Nov starts the second block and is that block's own day, so nothing is passed over.
            (Fix.day(2026, 11, 16), [Fix.day(2026, 11, 2), Fix.day(2026, 11, 16), Fix.day(2026, 11, 30)]),
            // Sun 1 Nov's block, 26 Oct–8 Nov, overlaps the first.
            (Fix.day(2026, 11, 1), [Fix.day(2026, 11, 16), Fix.day(2026, 11, 30)]),
            // Fri 23 Oct's block, 19 Oct–1 Nov, ends before the Starts week.
            (Fix.day(2026, 10, 23), [Fix.day(2026, 11, 2), Fix.day(2026, 11, 16), Fix.day(2026, 11, 30)]),
        ],
    )
    func everyTwoWeeks(recorded: CalendarDay, expected: [CalendarDay]) {
        let rent = Self.item(.every(2, .week), from: Fix.day(2026, 11, 2), recording: recorded)
        #expect(ScheduleCalendar.occurrences(of: rent, through: Fix.day(2026, 12, 13)) == expected)
    }

    @Test("Every 2 weeks from a Wednesday: the block starts on that week's Monday")
    func everyTwoWeeksFromMidweek() {
        // From Wed 4 Nov the blocks are Mon 2 Nov–Sun 15 Nov and Mon 16 Nov–Sun 29 Nov.
        let monday = Self.item(.every(2, .week), from: Fix.day(2026, 11, 4), recording: Fix.day(2026, 11, 2))
        #expect(!ScheduleCalendar.isOccurrence(Fix.day(2026, 11, 4), of: monday))
        #expect(ScheduleCalendar.isOccurrence(Fix.day(2026, 11, 18), of: monday))
        let next = Self.item(.every(2, .week), from: Fix.day(2026, 11, 4), recording: Fix.day(2026, 11, 16))
        #expect(ScheduleCalendar.isOccurrence(Fix.day(2026, 11, 4), of: next))
        #expect(!ScheduleCalendar.isOccurrence(Fix.day(2026, 11, 18), of: next))
    }

    @Test(
        "Every 3 months from 5 Jan 2027: Jan–Mar is one period, Apr–Jun the next",
        arguments: [
            (Fix.day(2027, 1, 1), [Fix.day(2027, 4, 5), Fix.day(2027, 7, 5)]),
            (Fix.day(2027, 3, 31), [Fix.day(2027, 7, 5)]),
            (Fix.day(2027, 4, 1), [Fix.day(2027, 1, 5), Fix.day(2027, 7, 5)]),
            // 28 Dec 2026's block, Dec–Feb, overlaps Jan–Mar.
            (Fix.day(2026, 12, 28), [Fix.day(2027, 4, 5), Fix.day(2027, 7, 5)]),
            // 5 Oct 2026's block, Oct–Dec, ends before it.
            (Fix.day(2026, 10, 5), [Fix.day(2027, 1, 5), Fix.day(2027, 4, 5), Fix.day(2027, 7, 5)]),
        ],
    )
    func everyThreeMonths(recorded: CalendarDay, expected: [CalendarDay]) {
        let rent = Self.item(.every(3, .month), from: Fix.day(2027, 1, 5), recording: recorded)
        #expect(ScheduleCalendar.occurrences(of: rent, through: Fix.day(2027, 9, 30)) == expected)
    }

    @Test("Every 3 months from 5 Feb: the blocks start in February, not on calendar quarters")
    func everyThreeMonthsFromStartsMonth() {
        // Blocks Feb–Apr, May–Jul, Aug–Oct. 1 Apr's block, Apr–Jun, overlaps the first two.
        let rent = Self.item(.every(3, .month), from: Fix.day(2027, 2, 5), recording: Fix.day(2027, 4, 1))
        #expect(ScheduleCalendar.occurrences(of: rent, through: Fix.day(2027, 10, 31)) == [Fix.day(2027, 8, 5)])
        // 1 Feb is in the first block's own month, so only 5 Feb is passed over.
        let early = Self.item(.every(3, .month), from: Fix.day(2027, 2, 5), recording: Fix.day(2027, 2, 1))
        #expect(
            ScheduleCalendar.occurrences(of: early, through: Fix.day(2027, 10, 31))
                == [Fix.day(2027, 5, 5), Fix.day(2027, 8, 5)]
        )
    }

    @Test(
        "Every 3 days from 4 Nov: 4–6 Nov is one period, 7–9 Nov the next",
        arguments: [
            (Fix.day(2026, 11, 4), [Fix.day(2026, 11, 4), Fix.day(2026, 11, 7), Fix.day(2026, 11, 10)]),
            (Fix.day(2026, 11, 5), [Fix.day(2026, 11, 10)]),
            (Fix.day(2026, 11, 8), [Fix.day(2026, 11, 4)]),
            (Fix.day(2026, 11, 3), [Fix.day(2026, 11, 7), Fix.day(2026, 11, 10)]),
            (Fix.day(2026, 11, 1), [Fix.day(2026, 11, 4), Fix.day(2026, 11, 7), Fix.day(2026, 11, 10)]),
        ],
    )
    func everyThreeDays(recorded: CalendarDay, expected: [CalendarDay]) {
        let rent = Self.item(.every(3, .day), from: Fix.day(2026, 11, 4), recording: recorded)
        #expect(ScheduleCalendar.occurrences(of: rent, through: Fix.day(2026, 11, 12)) == expected)
    }

    @Test("Daily: each calendar day is its own period, so a record on another day never passes one over")
    func daily() {
        let days = (4...7).map { Fix.day(2026, 11, $0) }
        for recorded in [Fix.day(2026, 11, 3), Fix.day(2026, 11, 5)] {
            let rent = Self.item(.daily, from: Fix.day(2026, 11, 4), recording: recorded)
            #expect(ScheduleCalendar.occurrences(of: rent, through: Fix.day(2026, 11, 7)) == days)
        }
    }

    @Test("Every 2 years from 1 Mar 2027: 2027–2028 is one period")
    func everyTwoYears() {
        let rent = Self.item(.every(2, .year), from: Fix.day(2027, 3, 1), recording: Fix.day(2027, 1, 15))
        #expect(
            ScheduleCalendar.occurrences(of: rent, through: Fix.day(2031, 12, 31))
                == [Fix.day(2029, 3, 1), Fix.day(2031, 3, 1)]
        )
        let earlier = Self.item(.every(2, .year), from: Fix.day(2027, 3, 1), recording: Fix.day(2025, 6, 1))
        #expect(ScheduleCalendar.isOccurrence(Fix.day(2027, 3, 1), of: earlier))
    }

    @Test("D429.3: a single-unit rule keeps its calendar unit, so a record in the month before never takes this one")
    func singleUnitDoesNotRealign() {
        let rent = Self.item(.monthly, from: Fix.day(2027, 2, 10), recording: Fix.day(2027, 1, 15))
        #expect(ScheduleCalendar.isOccurrence(Fix.day(2027, 2, 10), of: rent))
    }
}
