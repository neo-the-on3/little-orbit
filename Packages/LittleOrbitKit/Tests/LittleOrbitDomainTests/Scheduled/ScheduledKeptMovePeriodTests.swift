import Foundation
import LittleOrbitDomain
import Testing

/// D437.1: after a rule edit, an occurrence "This occurrence only" moved, whose own day is no longer on the rule and
/// that's kept pending on its moved day (D435, D436, built in #317), counts against exactly one period: the one of
/// the new rule, with its unit, N and alignment, that holds the moved day. It never counts against a pre-edit period
/// or two periods. Made-up data: Phone Plan ₹199 weekly on Mondays, Mon 26 Oct moved to Fri 30 Oct, from Everyday
/// Savings.
@Suite("A kept moved occurrence takes one period of the new rule (D437.1)")
struct ScheduledKeptMovePeriodTests {
    private typealias Fix = ScheduledFixture

    /// The item after a rule edit to `rule` from `start`, with `key` kept pending on `movedTo`.
    private static func phone(
        from start: CalendarDay,
        rule: ScheduleRepeat,
        key: CalendarDay = Fix.day(2026, 10, 26),
        movedTo: CalendarDay = Fix.day(2026, 10, 30),
    ) -> ScheduledItem {
        var item = Fix.rent(amount: 199, start: start, rule: rule, automatic: false)
        var edit = ScheduledOccurrenceEdit()
        edit.set(.day, from: item, day: movedTo)
        item.occurrences = [
            ScheduledOccurrence(id: UUID(), day: key, outcome: .pending, edit: edit, createdAt: Fix.created)
        ]
        return item
    }

    @Test("D437.3 check 1: Starts changed to Tue 27 Oct: no Tue 27 Oct, and Tue 3 Nov is next")
    func startsChangedToTuesday() {
        let phone = Self.phone(from: Fix.day(2026, 10, 27), rule: .weekly)
        #expect(!ScheduleCalendar.isOccurrence(Fix.day(2026, 10, 27), of: phone))
        #expect(
            ScheduleCalendar.occurrences(of: phone, through: Fix.day(2026, 11, 10))
                == [Fix.day(2026, 11, 3), Fix.day(2026, 11, 10)]
        )
        #expect(
            ScheduleCalendar.nextOccurrence(of: phone, after: Fix.day(2026, 10, 21))?.day == Fix.day(2026, 10, 30)
        )
    }

    @Test("D437.3 check 2: changed to monthly on the 27th: no 27 Oct, and 27 Nov is created")
    func monthlyOnThe27th() {
        let phone = Self.phone(from: Fix.day(2026, 10, 27), rule: .monthly)
        #expect(
            ScheduleCalendar.occurrences(of: phone, through: Fix.day(2026, 12, 31))
                == [Fix.day(2026, 11, 27), Fix.day(2026, 12, 27)]
        )
    }

    @Test("D437: changed to monthly on the 1st: Sun 1 Nov is created, then 1 Dec, so November keeps its payment")
    func monthlyOnThe1st() {
        let phone = Self.phone(from: Fix.day(2026, 10, 1), rule: .monthly)
        #expect(
            ScheduleCalendar.occurrences(of: phone, through: Fix.day(2026, 12, 31))
                == [Fix.day(2026, 11, 1), Fix.day(2026, 12, 1)]
        )
    }

    @Test("D437: changed to monthly on the 5th: 30 Oct takes October, and 5 Nov is created")
    func monthlyOnThe5th() {
        let phone = Self.phone(from: Fix.day(2026, 10, 5), rule: .monthly)
        #expect(
            ScheduleCalendar.occurrences(of: phone, through: Fix.day(2026, 11, 30)) == [Fix.day(2026, 11, 5)]
        )
    }

    @Test("D437.1: every 2 weeks from Tue 20 Oct: 30 Oct takes only 19 Oct–1 Nov, so Tue 3 Nov is created")
    func everyTwoWeeksOneBlock() {
        let phone = Self.phone(from: Fix.day(2026, 10, 20), rule: .every(2, .week))
        #expect(
            ScheduleCalendar.occurrences(of: phone, through: Fix.day(2026, 11, 17))
                == [Fix.day(2026, 11, 3), Fix.day(2026, 11, 17)]
        )
    }

    @Test(
        "D437: moved to Wed 4 Nov, Starts changed to Tue 27 Oct: 4 Nov takes 2–8 Nov, so 27 Oct is due and 3 Nov isn't"
    )
    func movedIntoTheNextPeriod() {
        let phone = Self.phone(from: Fix.day(2026, 10, 27), rule: .weekly, movedTo: Fix.day(2026, 11, 4))
        #expect(
            ScheduleCalendar.occurrences(of: phone, through: Fix.day(2026, 11, 10))
                == [Fix.day(2026, 10, 27), Fix.day(2026, 11, 10)]
        )
        #expect(
            ScheduleCalendar.dueOccurrences(of: phone, through: Fix.day(2026, 11, 10)).map(\.day)
                == [Fix.day(2026, 10, 27), Fix.day(2026, 11, 4), Fix.day(2026, 11, 10)]
        )
    }

    @Test("D437: moved to Wed 4 Nov, rule changed to Wednesdays: 4 Nov is the move, not a second Wednesday occurrence")
    func movedOntoANewRuleDay() {
        let phone = Self.phone(from: Fix.day(2026, 10, 28), rule: .weekly, movedTo: Fix.day(2026, 11, 4))
        #expect(
            ScheduleCalendar.occurrences(of: phone, through: Fix.day(2026, 11, 11))
                == [Fix.day(2026, 10, 28), Fix.day(2026, 11, 11)]
        )
        #expect(
            ScheduleCalendar.dueOccurrences(of: phone, through: Fix.day(2026, 11, 11)).map(\.day)
                == [Fix.day(2026, 10, 28), Fix.day(2026, 11, 4), Fix.day(2026, 11, 11)]
        )
    }

    @Test(
        "A pending move whose own day is still on the rule keeps its own period, so 1 Nov stays when 1 Dec waits on 30 Nov"
    )
    func pendingMoveOnTheRuleKeepsItsKey() {
        let rent = Self.phone(
            from: Fix.day(2026, 8, 1),
            rule: .monthly,
            key: Fix.day(2026, 12, 1),
            movedTo: Fix.day(2026, 11, 30),
        )
        #expect(ScheduleCalendar.isOccurrence(Fix.day(2026, 11, 1), of: rent))
        #expect(ScheduleCalendar.isOccurrence(Fix.day(2026, 12, 1), of: rent))
    }

    @Test("An occurrence with its own values whose day left the rule takes no period")
    func orphanedEditTakesNothing() {
        var phone = Fix.rent(amount: 199, start: Fix.day(2026, 10, 27), rule: .weekly, automatic: false)
        var edit = ScheduledOccurrenceEdit()
        edit.set(.day, from: phone, day: Fix.day(2026, 10, 30))
        let orphan = ScheduledOccurrence(
            id: UUID(),
            day: Fix.day(2026, 10, 26),
            outcome: .edited,
            edit: edit,
            createdAt: Fix.created,
        )
        phone.occurrences = [orphan]
        #expect(ScheduleCalendar.isOccurrence(Fix.day(2026, 10, 27), of: phone))
    }
}
