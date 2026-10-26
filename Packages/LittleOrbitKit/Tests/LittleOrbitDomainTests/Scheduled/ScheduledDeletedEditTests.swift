import Foundation
import LittleOrbitDomain
import Testing

/// #258: an Edit form opened before its item was deleted elsewhere, say in another window, never saves the item
/// back. A new item still saves, and an edit of a stored item still keeps its settled occurrences. Made-up data.
@MainActor
@Suite("Scheduled edit of a deleted item (#258)")
struct ScheduledDeletedEditTests {
    private typealias Fix = ScheduledFixture

    /// A manual Rent, monthly on the 1st from 1 Aug, created on 1 Jul, with August paid; today is 20 Oct.
    private func rentScene() throws -> (FakeScheduleRepository, ScheduledItem) {
        let repository = FakeScheduleRepository()
        repository.now = Fix.created
        let rent = Fix.rent(automatic: false)
        try repository.useCases().save(rent)
        repository.now = Fix.date(2026, 10, 20)
        try repository.useCases().payNow(itemID: rent.id, occurrence: Fix.day(2026, 8, 1))
        return (repository, rent)
    }

    @Test("LedgerBook: an update of an ID that isn't stored throws missingScheduledItem")
    func ledgerRefusesAMissingID() throws {
        let snapshot = Fix.ledger
        #expect(throws: LedgerValidationError.missingScheduledItem) {
            try LedgerBook.updatingScheduledItem(
                Fix.rent(),
                in: snapshot,
                today: Fix.day(2026, 10, 20),
                now: Fix.date(2026, 10, 20),
            )
        }
    }

    @Test("Deleted, then the open form's edit is saved: it throws, writes nothing and the item stays deleted")
    func editAfterDeleteWritesNothing() throws {
        let (repository, rent) = try rentScene()
        let useCases = repository.useCases()
        // The form's copy, loaded before the delete.
        var edited = try #require(repository.snapshot.scheduledItems.first { $0.id == rent.id })
        try useCases.delete(id: rent.id)
        let afterDelete = repository.snapshot
        let saves = repository.saves
        edited.amount = 26_000
        edited.details = "Rent, new flat"
        #expect(throws: LedgerValidationError.missingScheduledItem) {
            try useCases.update(edited)
        }
        #expect(repository.snapshot == afterDelete)
        #expect(repository.saves == saves)
        #expect(repository.snapshot.scheduledItems.isEmpty)
        #expect(try useCases.listing().item(rent.id) == nil)
        // The payment it recorded before the delete is kept, and nothing else was posted.
        #expect(repository.snapshot.transactions.count == 1)
    }

    @Test("An update of a stored item saves the change and keeps its settled occurrences")
    func editOfAStoredItemSaves() throws {
        let (repository, rent) = try rentScene()
        var edited = try #require(repository.snapshot.scheduledItems.first { $0.id == rent.id })
        edited.occurrences = []
        edited.amount = 26_000
        try repository.useCases().update(edited)
        let stored = try #require(repository.snapshot.scheduledItems.first { $0.id == rent.id })
        #expect(stored.amount == 26_000)
        #expect(stored.occurrences.map(\.day) == [Fix.day(2026, 8, 1)])
        #expect(stored.occurrences.map(\.outcome) == [.posted])
        #expect(stored.createdAt == Fix.created)
        #expect(repository.snapshot.scheduledItems.count == 1)
    }

    @Test("A new item still saves as a new item")
    func newItemStillSaves() throws {
        let (repository, rent) = try rentScene()
        repository.now = Fix.date(2026, 10, 20)
        let gym = Fix.rent(amount: 1_500, start: Fix.day(2026, 11, 5))
        try repository.useCases().save(gym)
        #expect(repository.snapshot.scheduledItems.map(\.id) == [rent.id, gym.id])
        let stored = try #require(repository.snapshot.scheduledItems.last)
        #expect(stored.createdAt == Fix.date(2026, 10, 20))
        #expect(stored.occurrences.isEmpty)
    }
}
