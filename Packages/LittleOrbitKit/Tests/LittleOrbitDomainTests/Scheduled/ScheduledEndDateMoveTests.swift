import Foundation
import LittleOrbitDomain
import Testing

/// D435.1 and D442.1 (Tech Architect B1 on #326): an End date edit that takes a "This occurrence only" move's own day
/// off the rule. Made-up data in `Asia/Kolkata`: Phone Plan, ₹199.00 weekly on Mondays from Mon 12 Oct 2026, from
/// Everyday Savings (INR), with 12 and 19 Oct paid. On Tue 20 Oct one Monday is moved for this occurrence only; on Wed
/// 21 Oct the End date is set to Sat 31 Oct. Every save goes through the use cases and the fake store, as the form's do.
@MainActor
@Suite("An End date edit with a this-only move (D442.1, #326 B1)")
struct ScheduledEndDateMoveTests {
    private typealias Fix = ScheduledFixture
    private static let kolkata = TimeZone(identifier: Fix.zone)!
    static let newEnd = Fix.day(2026, 10, 31)

    /// The example: `key` moved to `movedTo` on 20 Oct, then the End date set to 31 Oct on 21 Oct. Returns the store
    /// and the End date save's Undo step.
    static func example(
        key: CalendarDay,
        movedTo: CalendarDay,
        automatic: Bool = false,
    ) throws -> (repository: FakeScheduleRepository, change: ScheduledItemSaveChange) {
        let repository = FakeScheduleRepository()
        repository.now = Fix.created
        let useCases = repository.useCases()
        var phone = Fix.rent(amount: 199, start: Fix.day(2026, 10, 12), rule: .weekly, automatic: automatic)
        phone.details = "Phone Plan"
        phone.categoryID = nil
        phone.notifiesWhenDue = true
        let saved = try useCases.save(phone, payee: nil).after
        for day in [Fix.day(2026, 10, 12), Fix.day(2026, 10, 19)] {
            _ = try repository.settleScheduledOccurrence(.pay(itemID: saved.id, occurrence: day, postedOn: day))
        }
        repository.now = Fix.date(2026, 10, 20)
        let move = ScheduledOccurrenceSave(occurrence: key, dueDay: movedTo, scope: .thisOccurrence)
        _ = try useCases.update(repository.snapshot.scheduledItems[0], editing: move, payee: nil)
        repository.now = Fix.date(2026, 10, 21)
        var ended = repository.snapshot.scheduledItems[0]
        ended.endDay = newEnd
        let change = try useCases.update(ended, payee: nil)
        return (repository, change)
    }

    private func day(_ transaction: Transaction) -> CalendarDay {
        TransactionCalendar.ownDay(of: transaction.date, timeZoneID: transaction.timeZoneID)
    }

    // MARK: (A) Moved day on or before the new End

    private static let keyA = Fix.day(2026, 11, 2)
    private static let movedA = Fix.day(2026, 10, 23)

    @Test("D442 (A): 2 Nov moved to Fri 23 Oct stays pending and due on 23 Oct after End becomes 31 Oct")
    func movedBeforeTheNewEndStaysDue() throws {
        let (repository, change) = try Self.example(key: Self.keyA, movedTo: Self.movedA)
        // Nothing is removed, so the save shows no notice.
        #expect(change.removed.isEmpty)
        let snapshot = repository.snapshot
        let item = snapshot.scheduledItems[0]
        #expect(item.endDay == Self.newEnd)
        #expect(item.occurrence(on: Self.keyA)?.outcome == .pending)
        #expect(item.dueDay(of: Self.keyA) == Self.movedA)
        // The due list: 23 Oct under 2 Nov's key, then 26 Oct, the rule's last day before the End.
        let due = ScheduleCalendar.dueOccurrences(of: item, through: Fix.day(2026, 11, 30))
        #expect(due.map(\.day) == [Self.movedA, Fix.day(2026, 10, 26)])
        #expect(due.map(\.key) == [Self.keyA, Fix.day(2026, 10, 26)])
        #expect(ScheduleCalendar.nextOccurrence(of: item, after: Fix.day(2026, 10, 21))?.day == Self.movedA)
        // The board: upcoming on 21 Oct, due today on 23 Oct.
        let board = ScheduledBoard.make(snapshot, today: Self.movedA)
        #expect(board.dueToday.contains { $0.key == Self.keyA && $0.day == Self.movedA })
        // Its reminder: 23 Oct at 09:00, under 2 Nov's identifier.
        let reminders = ScheduledReminderPlanner.plan(
            [item],
            now: Fix.date(2026, 10, 21),
            timeZone: Self.kolkata,
            time: .standard,
            limit: 3,
        )
        #expect(reminders.first?.id == ScheduledReminder.identifier(item: item.id, day: Self.keyA))
        #expect(reminders.first?.fireDate == Fix.date(2026, 10, 23, 9))
    }

    @Test("D442 (A): Pay records the kept 23 Oct move once for ₹199.00, and Skip is accepted")
    func movedBeforeTheNewEndPaysAndSkips() throws {
        let snapshot = try Self.example(key: Self.keyA, movedTo: Self.movedA).repository.snapshot
        let id = snapshot.scheduledItems[0].id
        let paid = try LedgerBook.settlingScheduledOccurrence(
            .pay(itemID: id, occurrence: Self.keyA, postedOn: Self.movedA),
            in: snapshot,
            now: Fix.date(2026, 10, 23),
        )
        #expect(paid.transaction?.amount == 199)
        #expect(paid.transaction.map(day) == Self.movedA)
        let again = try LedgerBook.settlingScheduledOccurrence(
            .pay(itemID: id, occurrence: Self.keyA, postedOn: Self.movedA),
            in: paid.snapshot,
            now: Fix.date(2026, 10, 23, 11),
        )
        #expect(again.transaction == nil)
        #expect(again.snapshot.transactions.count == paid.snapshot.transactions.count)
        let skipped = try LedgerBook.settlingScheduledOccurrence(
            .skip(itemID: id, occurrence: Self.keyA),
            in: snapshot,
            now: Fix.date(2026, 10, 23),
        )
        #expect(skipped.snapshot.scheduledItems[0].occurrence(on: Self.keyA)?.outcome == .skipped)
    }

    @Test("D442 (A): catch-up records the kept 23 Oct move once, under 2 Nov, and never again")
    func movedBeforeTheNewEndCatchesUpOnce() throws {
        let repository = try Self.example(key: Self.keyA, movedTo: Self.movedA, automatic: true).repository
        repository.now = Fix.date(2026, 11, 2)
        let useCases = repository.useCases()
        _ = try useCases.catchUp(atLaunch: false)
        let item = repository.snapshot.scheduledItems[0]
        #expect(item.occurrence(on: Self.keyA)?.outcome == .posted)
        #expect(repository.posted(for: item.id).filter { day($0) == Self.movedA }.count == 1)
        let count = repository.posted(for: item.id).count
        _ = try useCases.catchUp(atLaunch: false)
        #expect(repository.posted(for: item.id).count == count)
    }

    // MARK: (B) Moved day after the new End

    private static let keyB = Fix.day(2026, 10, 26)
    private static let movedB = Fix.day(2026, 11, 3)

    @Test("D442 (B): 26 Oct moved to Tue 3 Nov is removed when End becomes 31 Oct, and the save reports it")
    func movedAfterTheNewEndIsRemoved() throws {
        let (repository, change) = try Self.example(key: Self.keyB, movedTo: Self.movedB)
        #expect(change.removed == [.init(reason: .movedBackToScheduledDay, key: Self.keyB, dueDay: Self.movedB)])
        // The notice names the scheduled day it went back to (D444.1).
        #expect(change.removed.first?.shownDay == Self.keyB)
        let snapshot = repository.snapshot
        let item = snapshot.scheduledItems[0]
        #expect(item.endDay == Self.newEnd)
        #expect(item.occurrence(on: Self.keyB) == nil)
        // 3 Nov is gone: not due, not upcoming, no reminder.
        let due = ScheduleCalendar.dueOccurrences(of: item, through: Fix.day(2026, 11, 30))
        #expect(!due.contains { $0.day == Self.movedB })
        #expect(ScheduledBoard.make(snapshot, today: Self.movedB).dueToday.isEmpty)
        let reminders = ScheduledReminderPlanner.plan(
            [item],
            now: Fix.date(2026, 10, 21),
            timeZone: Self.kolkata,
            time: .standard,
            limit: 3,
        )
        #expect(!reminders.contains { $0.fireDate == Fix.date(2026, 11, 3, 9) })
        // It takes no period, so the rule's own Mon 26 Oct is due as normal, for ₹199.00 (D442.3).
        #expect(due.map(\.day) == [Self.keyB])
        #expect(item.resolved(for: Self.keyB).amount == 199)
        _ = try LedgerBook.settlingScheduledOccurrence(
            .pay(itemID: item.id, occurrence: Self.keyB, postedOn: Self.keyB),
            in: snapshot,
            now: Fix.date(2026, 10, 26),
        )
        #expect(throws: LedgerValidationError.notAnOccurrence) {
            try LedgerBook.settlingScheduledOccurrence(
                .skip(itemID: item.id, occurrence: Fix.day(2026, 11, 2)),
                in: snapshot,
                now: Fix.date(2026, 11, 3),
            )
        }
    }

    @Test("D442 (B), D447: no 3 Nov payment; 26 Oct waits while the notice shows and is recorded once after OK")
    func movedAfterTheNewEndIsNotCaughtUp() throws {
        let (repository, change) = try Self.example(key: Self.keyB, movedTo: Self.movedB, automatic: true)
        repository.now = Fix.date(2026, 11, 4)
        let id = repository.snapshot.scheduledItems[0].id
        let paid = [Fix.day(2026, 10, 12), Fix.day(2026, 10, 19)]
        // While the save's notice shows, catch-up holds the item (D447.1).
        #expect(try repository.useCases().catchUp(atLaunch: false, holding: [change.itemID]).posted.isEmpty)
        #expect(repository.posted(for: id).map(day) == paid)
        // After OK, the next catch-up records 26 Oct once, and never 3 Nov (D447.3).
        _ = try repository.useCases().catchUp(atLaunch: false)
        #expect(repository.posted(for: id).map(day) == paid + [Self.keyB])
        _ = try repository.useCases().catchUp(atLaunch: false)
        #expect(repository.posted(for: id).map(day) == paid + [Self.keyB])
    }

    @Test("D442 (B): Undo of the End date save restores 3 Nov, due with its move, and no End date")
    func undoRestoresTheRemovedMove() throws {
        let (repository, change) = try Self.example(key: Self.keyB, movedTo: Self.movedB)
        repository.now = Fix.date(2026, 10, 21, 11)
        guard case .reverted = try repository.revertScheduledItemSave(change, undone: false) else {
            Issue.record("Undo was stale")
            return
        }
        let item = repository.snapshot.scheduledItems[0]
        #expect(item.endDay == nil)
        #expect(item.occurrence(on: Self.keyB)?.outcome == .edited)
        #expect(item.dueDay(of: Self.keyB) == Self.movedB)
        let due = ScheduleCalendar.dueOccurrences(of: item, through: Fix.day(2026, 11, 3))
        #expect(due.contains { $0.key == Self.keyB && $0.day == Self.movedB })
        let reminders = ScheduledReminderPlanner.plan(
            [item],
            now: Fix.date(2026, 10, 21, 11),
            timeZone: Self.kolkata,
            time: .standard,
            limit: 3,
        )
        #expect(reminders.contains { $0.id == ScheduledReminder.identifier(item: item.id, day: Self.keyB) })
    }

    @Test("D444.1 (E): Mon 2 Nov moved to Tue 3 Nov is removed when End becomes 31 Oct, shown on 3 Nov; Undo restores")
    func movedWithItsOwnDayPastTheEndIsRemoved() throws {
        let key = Fix.day(2026, 11, 2)
        let movedTo = Fix.day(2026, 11, 3)
        let (repository, change) = try Self.example(key: key, movedTo: movedTo)
        #expect(change.removed == [.init(reason: .movedRemoved, key: key, dueDay: movedTo)])
        #expect(change.removed.first?.shownDay == movedTo)
        let item = repository.snapshot.scheduledItems[0]
        #expect(item.occurrence(on: key) == nil)
        #expect(
            ScheduleCalendar.dueOccurrences(of: item, through: Fix.day(2026, 11, 30)).map(\.day) == [
                Fix.day(2026, 10, 26)
            ]
        )
        let reminders = ScheduledReminderPlanner.plan(
            [item],
            now: Fix.date(2026, 10, 21),
            timeZone: Self.kolkata,
            time: .standard,
            limit: 3,
        )
        #expect(!reminders.contains { $0.id == ScheduledReminder.identifier(item: item.id, day: key) })
        repository.now = Fix.date(2026, 10, 21, 11)
        guard case .reverted = try repository.revertScheduledItemSave(change, undone: false) else {
            Issue.record("Undo was stale")
            return
        }
        let restored = repository.snapshot.scheduledItems[0]
        #expect(restored.endDay == nil)
        #expect(restored.dueDay(of: key) == movedTo)
    }

    // MARK: D443: a move made past an End that's already set

    @Test("D443: 26 Oct moved past an End already set (to Tue 3 Nov) stays due; the next item save removes it")
    func movePastAnExistingEndStaysDueUntilTheNextSave() throws {
        let repository = FakeScheduleRepository()
        repository.now = Fix.created
        let useCases = repository.useCases()
        var phone = Fix.rent(
            amount: 199,
            start: Fix.day(2026, 10, 12),
            rule: .weekly,
            end: Self.newEnd,
            automatic: false,
        )
        phone.details = "Phone Plan"
        phone.notifiesWhenDue = true
        let id = try useCases.save(phone, payee: nil).after.id
        for day in [Fix.day(2026, 10, 12), Fix.day(2026, 10, 19)] {
            _ = try repository.settleScheduledOccurrence(.pay(itemID: id, occurrence: day, postedOn: day))
        }
        // Tue 20 Oct: the move is saved and isn't refused or removed (D443.1).
        repository.now = Fix.date(2026, 10, 20)
        let move = ScheduledOccurrenceSave(occurrence: Self.keyB, dueDay: Self.movedB, scope: .thisOccurrence)
        let moved = try useCases.update(repository.snapshot.scheduledItems[0], editing: move, payee: nil)
        #expect(moved.removed.isEmpty)
        var item = repository.snapshot.scheduledItems[0]
        #expect(item.occurrence(on: Self.keyB)?.outcome == .edited)
        #expect(ScheduleCalendar.dueOccurrences(of: item, through: Fix.day(2026, 11, 30)).map(\.day) == [Self.movedB])
        let reminders = ScheduledReminderPlanner.plan(
            [item],
            now: Fix.date(2026, 10, 20),
            timeZone: Self.kolkata,
            time: .standard,
            limit: 3,
        )
        #expect(reminders.first?.fireDate == Fix.date(2026, 11, 3, 9))
        // Wed 21 Oct: an unrelated save, the amount to ₹209.00, removes it and reports it (D443.2).
        repository.now = Fix.date(2026, 10, 21)
        var dearer = item
        dearer.amount = 209
        let change = try useCases.update(dearer, payee: nil)
        #expect(change.removed == [.init(reason: .movedBackToScheduledDay, key: Self.keyB, dueDay: Self.movedB)])
        item = repository.snapshot.scheduledItems[0]
        #expect(item.occurrence(on: Self.keyB) == nil)
        #expect(ScheduleCalendar.dueOccurrences(of: item, through: Fix.day(2026, 11, 30)).map(\.day) == [Self.keyB])
        // Undo puts the move back, due on 3 Nov.
        guard case .reverted = try repository.revertScheduledItemSave(change, undone: false) else {
            Issue.record("Undo was stale")
            return
        }
        #expect(repository.snapshot.scheduledItems[0].dueDay(of: Self.keyB) == Self.movedB)
    }

    @Test(
        "D443: a save that can't report removals (the store's plain save) removes nothing for an End it didn't change"
    )
    func unreportedSaveRemovesNothing() throws {
        let (repository, _) = try Self.example(key: Self.keyA, movedTo: Self.movedA)
        var item = repository.snapshot.scheduledItems[0]
        // 26 Oct moved to Tue 3 Nov after the End is set, then a plain save of the amount.
        let move = ScheduledOccurrenceSave(occurrence: Self.keyB, dueDay: Self.movedB, scope: .thisOccurrence)
        _ = try repository.useCases().update(item, editing: move, payee: nil)
        item = repository.snapshot.scheduledItems[0]
        item.amount = 209
        try repository.useCases().save(item)
        #expect(repository.snapshot.scheduledItems[0].dueDay(of: Self.keyB) == Self.movedB)
    }
}
