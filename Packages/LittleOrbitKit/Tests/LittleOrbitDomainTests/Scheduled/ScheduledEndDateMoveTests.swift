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
        let (repository, _) = try Self.example(key: Self.keyA, movedTo: Self.movedA)
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
}
