import Foundation
import LittleOrbitDomain
import Testing

/// A "This occurrence only" move stays due when a rule edit takes its own day off the rule (D435, D436): it becomes
/// pending on its moved day, so the board, catch-up, Pay and Skip, and its reminder all keep it. Made-up data in
/// `Asia/Kolkata`: Phone Plan, ₹199 weekly on Mondays, created Tue 20 Oct 2026, when Mon 26 Oct is moved to Fri 30
/// Oct. On Wed 21 Oct the rule changes.
///
/// The kept move counts against one period: the new rule's period that holds its moved day (D437). Which new
/// occurrences that period stops (Tue 27 Oct after Starts moves to Tuesdays, or 27 Oct for monthly on the 27th) is
/// #316's taken-period check, so only the case that doesn't depend on it is pinned here: monthly on the 1st still
/// creates Sun 1 Nov. #316 gets its own version of this gate.
@Suite("Scheduled moves kept after a rule edit (D435, D436)")
struct ScheduledOrphanedMoveTests {
    private typealias Fix = ScheduledFixture
    private static let kolkata = TimeZone(identifier: Fix.zone)!
    private static let key = Fix.day(2026, 10, 26)
    private static let movedTo = Fix.day(2026, 10, 30)

    /// The example: created and moved on 20 Oct, then `edit` applied to the rule on 21 Oct.
    private func example(
        automatic: Bool = false,
        movedTo: CalendarDay = movedTo,
        edit: (inout ScheduledItem) -> Void,
    ) throws -> LedgerSnapshot {
        var item = Fix.rent(amount: 199, start: Fix.day(2026, 7, 6), rule: .weekly, automatic: automatic)
        item.details = "Phone Plan"
        item.notifiesWhenDue = true
        var snapshot = try LedgerBook.savingScheduledItem(
            item,
            in: Fix.ledger,
            today: Fix.day(2026, 10, 20),
            now: Fix.date(2026, 10, 20, 7),
        )
        let save = ScheduledOccurrenceSave(occurrence: Self.key, dueDay: movedTo, scope: .thisOccurrence)
        snapshot = try LedgerBook.savingScheduledOccurrence(
            snapshot.scheduledItems[0],
            editing: save,
            in: snapshot,
            today: Fix.day(2026, 10, 20),
            now: Fix.date(2026, 10, 20),
        )
        var changed = snapshot.scheduledItems[0]
        edit(&changed)
        return try LedgerBook.savingScheduledItem(
            changed,
            in: snapshot,
            today: Fix.day(2026, 10, 21),
            now: Fix.date(2026, 10, 21),
        )
    }

    private func startsTuesday(_ item: inout ScheduledItem) {
        item.startDay = Fix.day(2026, 10, 27)
    }

    private func monthlyOn27th(_ item: inout ScheduledItem) {
        item.startDay = Fix.day(2026, 10, 27)
        item.repeatRule = .monthly
    }

    private func monthlyOn1st(_ item: inout ScheduledItem) {
        item.startDay = Fix.day(2026, 11, 1)
        item.repeatRule = .monthly
    }

    private func day(_ transaction: Transaction) -> CalendarDay {
        TransactionCalendar.ownDay(of: transaction.date, timeZoneID: transaction.timeZoneID)
    }

    /// Everything D435.1 keeps: pending on its moved day, on the board, next due, paid and skipped by Pay and Skip,
    /// recorded by catch-up, and reminded at 09:00 under 26 Oct's identifier.
    private func expectKeptDue(after edit: (inout ScheduledItem) -> Void) throws {
        let snapshot = try example(edit: edit)
        let item = snapshot.scheduledItems[0]
        #expect(item.occurrence(on: Self.key)?.outcome == .pending)
        #expect(item.dueDay(of: Self.key) == Self.movedTo)
        #expect(ScheduleCalendar.isOccurrence(Self.key, of: item))
        // The board: next due on 28 Oct, due today on 30 Oct.
        #expect(ScheduleCalendar.nextOccurrence(of: item, after: Fix.day(2026, 10, 28))?.day == Self.movedTo)
        let board = ScheduledBoard.make(snapshot, today: Self.movedTo)
        #expect(board.dueToday.contains { $0.key == Self.key && $0.day == Self.movedTo })
        // Pay records it once, on 30 Oct, for ₹199; Skip is accepted too.
        let paid = try LedgerBook.settlingScheduledOccurrence(
            .pay(itemID: item.id, occurrence: Self.key, postedOn: Self.movedTo),
            in: snapshot,
            now: Fix.date(2026, 10, 30),
        )
        #expect(paid.transaction.map(day) == Self.movedTo)
        #expect(paid.transaction?.amount == 199)
        let skipped = try LedgerBook.settlingScheduledOccurrence(
            .skip(itemID: item.id, occurrence: Self.key),
            in: snapshot,
            now: Fix.date(2026, 10, 30),
        )
        #expect(skipped.snapshot.scheduledItems[0].occurrence(on: Self.key)?.outcome == .skipped)
        // Its reminder: 30 Oct at 09:00, by its own day's identifier.
        let reminders = ScheduledReminderPlanner.plan(
            [item],
            now: Fix.date(2026, 10, 28, 8),
            timeZone: Self.kolkata,
            time: .standard,
            limit: 3,
        )
        #expect(reminders.first?.id == ScheduledReminder.identifier(item: item.id, day: Self.key))
        #expect(reminders.first?.fireDate == Fix.date(2026, 10, 30, 9))
    }

    @Test("D435: after Starts moves to Tue 27 Oct, the move to Fri 30 Oct stays due, paid, caught up and reminded")
    func startsEdit() throws {
        try expectKeptDue(after: startsTuesday)
    }

    @Test("D436: after the rule becomes monthly on the 27th, the move to Fri 30 Oct stays due the same way")
    func repeatEdit() throws {
        try expectKeptDue(after: monthlyOn27th)
    }

    @Test("D435: catch-up records the kept move once, on 30 Oct, under 26 Oct, and never again")
    func catchUpRecordsItOnce() throws {
        for edit in [startsTuesday, monthlyOn27th] {
            let snapshot = try example(automatic: true, edit: edit)
            let first = LedgerBook.catchingUpScheduledItems(in: snapshot, today: Fix.day(2026, 11, 2), now: .now)
            let kept = first.result.posted.filter { day($0) == Self.movedTo }
            #expect(kept.count == 1)
            #expect(first.result.failedItemIDs.isEmpty)
            #expect(first.snapshot.scheduledItems[0].occurrence(on: Self.key)?.outcome == .posted)
            let again = LedgerBook.catchingUpScheduledItems(
                in: first.snapshot,
                today: Fix.day(2026, 11, 2),
                now: .now,
            )
            #expect(again.result.posted.isEmpty)
        }
    }

    @Test("D435: a move to a day before the edit (Tue 20 Oct) stays due there, overdue on 21 Oct")
    func movedBeforeTheEditDay() throws {
        let snapshot = try example(movedTo: Fix.day(2026, 10, 20), edit: startsTuesday)
        let item = snapshot.scheduledItems[0]
        #expect(item.occurrence(on: Self.key)?.outcome == .pending)
        let board = ScheduledBoard.make(snapshot, today: Fix.day(2026, 10, 21))
        #expect(board.overdue.contains { $0.key == Self.key && $0.day == Fix.day(2026, 10, 20) })
    }

    @Test("A move whose own day stays on the new rule keeps its values as they were, not pending")
    func onTheRuleStaysEdited() throws {
        // Every 2 weeks from 6 Jul still has Mon 26 Oct.
        let snapshot = try example { $0.repeatRule = .every(2, .week) }
        let item = snapshot.scheduledItems[0]
        #expect(item.occurrence(on: Self.key)?.outcome == .edited)
        #expect(ScheduleCalendar.nextOccurrence(of: item, after: Fix.day(2026, 10, 28))?.day == Self.movedTo)
    }

    @Test("A move unchanged by an edit that keeps the rule stays as it was")
    func ruleUnchanged() throws {
        let snapshot = try example { $0.amount = 249 }
        #expect(snapshot.scheduledItems[0].occurrence(on: Self.key)?.outcome == .edited)
    }

    @Test("D437: after the rule becomes monthly on the 1st, 30 Oct stays due, Sun 1 Nov is created, and next 1 Dec")
    func monthlyOnThe1stKeepsNovember() throws {
        try expectKeptDue(after: monthlyOn1st)
        let item = try example(edit: monthlyOn1st).scheduledItems[0]
        let due = ScheduleCalendar.dueOccurrences(of: item, through: Fix.day(2026, 12, 1))
        #expect(due.map(\.day) == [Self.movedTo, Fix.day(2026, 11, 1), Fix.day(2026, 12, 1)])
        #expect(due.map(\.key) == [Self.key, Fix.day(2026, 11, 1), Fix.day(2026, 12, 1)])
    }

    @Test("D433.1 with D435: an All future move kept as pending stays pending, due and reminded after a Starts edit")
    func allFutureKeptMoveThroughStartsEdit() throws {
        // Tue 20 Oct: Mon 19 Oct is skipped, then Mon 26 Oct moves to Fri 23 Oct for all future, into 19 Oct's
        // week, so 23 Oct is kept as pending (D433.1). Wed 21 Oct: Starts becomes Sat 24 Oct.
        var item = Fix.rent(amount: 199, start: Fix.day(2026, 7, 6), rule: .weekly, automatic: false)
        item.notifiesWhenDue = true
        let today = Fix.day(2026, 10, 20)
        var snapshot = try LedgerBook.savingScheduledItem(item, in: Fix.ledger, today: today, now: Fix.created)
        snapshot =
            try LedgerBook.settlingScheduledOccurrence(
                .skip(itemID: item.id, occurrence: Fix.day(2026, 10, 19)),
                in: snapshot,
                now: Fix.date(2026, 10, 20),
            )
            .snapshot
        let friday = Fix.day(2026, 10, 23)
        let save = ScheduledOccurrenceSave(occurrence: Self.key, dueDay: friday, scope: .allFuture)
        snapshot = try LedgerBook.savingScheduledOccurrence(
            snapshot.scheduledItems[0],
            editing: save,
            in: snapshot,
            today: today,
            now: Fix.date(2026, 10, 20),
        )
        #expect(snapshot.scheduledItems[0].occurrence(on: friday)?.outcome == .pending)
        var saturdays = snapshot.scheduledItems[0]
        saturdays.startDay = Fix.day(2026, 10, 24)
        snapshot = try LedgerBook.savingScheduledItem(
            saturdays,
            in: snapshot,
            today: Fix.day(2026, 10, 21),
            now: Fix.date(2026, 10, 21),
        )
        let kept = snapshot.scheduledItems[0]
        #expect(kept.occurrence(on: friday)?.outcome == .pending)
        #expect(kept.dueDay(of: friday) == friday)
        #expect(ScheduleCalendar.nextOccurrence(of: kept, after: Fix.day(2026, 10, 21))?.day == friday)
        let reminders = ScheduledReminderPlanner.plan(
            [kept],
            now: Fix.date(2026, 10, 21, 8),
            timeZone: Self.kolkata,
            time: .standard,
            limit: 3,
        )
        #expect(reminders.first?.id == ScheduledReminder.identifier(item: kept.id, day: friday))
        #expect(reminders.first?.fireDate == Fix.date(2026, 10, 23, 9))
    }
}
