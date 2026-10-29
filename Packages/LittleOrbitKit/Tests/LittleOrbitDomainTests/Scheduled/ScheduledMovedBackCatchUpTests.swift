import Foundation
import LittleOrbitDomain
import Testing

/// D447: on an automatic item, catch-up doesn't record an overdue payment a save moved back to its scheduled day
/// while that save's notice is showing, so the notice's Undo puts the move back with no record. After OK, or on the
/// next normal catch-up, it's recorded as usual, once. Made-up data in `Asia/Kolkata`, as Product Manager's gate
/// check (G): Water Bill, ₹600.00 weekly on Mondays from Mon 12 Oct 2026, recorded automatically from Everyday
/// Savings (INR). Catch-up records 12 and 19 Oct on Sat 24 Oct, when Mon 26 Oct is moved to Tue 3 Nov for this
/// occurrence only. On Wed 28 Oct the End date is set to Sat 31 Oct, so 26 Oct is back on its own day, overdue.
@MainActor
@Suite("Catch-up and an overdue payment moved back to its day (D447)")
struct ScheduledMovedBackCatchUpTests {
    private typealias Fix = ScheduledFixture
    private static let key = Fix.day(2026, 10, 26)
    private static let movedTo = Fix.day(2026, 11, 3)
    private static let earlier = [Fix.day(2026, 10, 12), Fix.day(2026, 10, 19)]

    private static func example() throws -> (repository: FakeScheduleRepository, change: ScheduledItemSaveChange) {
        let repository = FakeScheduleRepository()
        repository.now = Fix.created
        let useCases = repository.useCases()
        var water = Fix.rent(amount: 600, start: Fix.day(2026, 10, 12), rule: .weekly, automatic: true)
        water.details = "Water Bill"
        _ = try useCases.save(water, payee: nil)
        repository.now = Fix.date(2026, 10, 24)
        #expect(try useCases.catchUp(atLaunch: false).posted.count == 2)
        let move = ScheduledOccurrenceSave(occurrence: key, dueDay: movedTo, scope: .thisOccurrence)
        _ = try useCases.update(repository.snapshot.scheduledItems[0], editing: move, payee: nil)
        repository.now = Fix.date(2026, 10, 28)
        // Nothing is due on 28 Oct before the End date save: 26 Oct is due on 3 Nov.
        #expect(try useCases.catchUp(atLaunch: false).posted.isEmpty)
        var ended = repository.snapshot.scheduledItems[0]
        ended.endDay = Fix.day(2026, 10, 31)
        return (repository, try useCases.update(ended, payee: nil))
    }

    private func days(_ repository: FakeScheduleRepository) -> [CalendarDay] {
        repository.posted(for: repository.snapshot.scheduledItems[0].id)
            .map { TransactionCalendar.ownDay(of: $0.date, timeZoneID: $0.timeZoneID) }
            .sorted()
    }

    @Test("D447.1, D447.2: the save reports 26 Oct; a held catch-up records nothing; Undo restores 3 Nov, unrecorded")
    func heldWhileTheNoticeShowsThenUndo() throws {
        let (repository, change) = try Self.example()
        #expect(
            change.removed == [.init(reason: .movedBackToScheduledDay, key: Self.key, dueDay: Self.movedTo)]
        )
        #expect(
            ScheduleCalendar.dueOccurrences(of: change.after, through: Fix.day(2026, 10, 28)).last?.day == Self.key
        )
        let useCases = repository.useCases()
        #expect(try useCases.catchUp(atLaunch: false, holding: [change.itemID]).posted.isEmpty)
        #expect(repository.snapshot.scheduledItems[0] == change.after)
        // The notice's Undo: the move is back, with no record and no End date.
        repository.now = Fix.date(2026, 10, 28, 11)
        guard case .reverted = try repository.revertScheduledItemSave(change, undone: false) else {
            Issue.record("Undo was stale")
            return
        }
        let item = repository.snapshot.scheduledItems[0]
        #expect(item.endDay == nil)
        #expect(item.occurrence(on: Self.key)?.outcome == .edited)
        #expect(item.dueDay(of: Self.key) == Self.movedTo)
        // The next normal catch-up has nothing to record: 26 Oct is due on 3 Nov again.
        #expect(try useCases.catchUp(atLaunch: false).posted.isEmpty)
        #expect(days(repository) == Self.earlier)
    }

    @Test("D447.3: after OK, catch-up records 26 Oct once, ₹600.00 dated 26 Oct, and never again")
    func recordedOnceAfterOK() throws {
        let (repository, change) = try Self.example()
        let useCases = repository.useCases()
        #expect(try useCases.catchUp(atLaunch: false, holding: [change.itemID]).posted.isEmpty)
        // OK: the hold is gone, so this catch-up is a normal one.
        let caughtUp = try useCases.catchUp(atLaunch: false)
        #expect(caughtUp.posted.map(\.amount) == [600])
        #expect(repository.snapshot.scheduledItems[0].occurrence(on: Self.key)?.outcome == .posted)
        #expect(days(repository) == Self.earlier + [Self.key])
        #expect(try useCases.catchUp(atLaunch: false).posted.isEmpty)
        #expect(try useCases.catchUp(atLaunch: true).posted.isEmpty)
        #expect(days(repository) == Self.earlier + [Self.key])
    }

    @Test("D447: the hold is only for the item whose notice shows; another automatic item still records")
    func holdsOnlyThatItem() throws {
        let (repository, change) = try Self.example()
        var rent = Fix.rent(amount: 25_000, start: Fix.day(2026, 10, 20), rule: .monthly, automatic: true)
        rent.createdAt = Fix.created
        repository.snapshot = try LedgerBook.savingScheduledItem(
            rent,
            in: repository.snapshot,
            today: Fix.day(2026, 10, 1),
            now: Fix.created,
        )
        let held = try repository.useCases().catchUp(atLaunch: false, holding: [change.itemID])
        #expect(held.posted.map(\.amount) == [25_000])
        #expect(days(repository) == Self.earlier)
    }
}
