import Foundation
import LittleOrbitDomain
import Testing

/// When a form save's Undo or Redo can run, and what it does to the payee it created or unarchived (#197): the item
/// it puts back needs its accounts, category and payee (Tech Architect B1); Redo never picks an archived payee
/// (D351.2); and Undo leaves alone a payee something touched since the save (D362, D363).
@MainActor
@Suite("Scheduled form save: Undo staleness and its payee (#197)")
struct ScheduledItemSaveUndoTests {
    private typealias Fix = ScheduledFixture
    private static let oldShopID = UUID(uuidString: "5C000000-0000-4000-8000-0000000000A1")!
    private static let utilitiesID = UUID(uuidString: "5C000000-0000-4000-8000-0000000000A2")!

    private static func repository() -> FakeScheduleRepository {
        var ledger = Fix.ledger
        ledger.payees.append(Payee(id: oldShopID, name: "Old Shop", isArchived: true, createdAt: Fix.created))
        ledger.categories.append(
            TransactionCategory(id: utilitiesID, name: "Utilities", kind: .expense, createdAt: Fix.created)
        )
        return FakeScheduleRepository(ledger)
    }

    private static var rent: ScheduledItem {
        Fix.rent(start: Fix.day(2026, 11, 1), automatic: false)
    }

    private static func undo(_ change: ScheduledItemSaveChange, in repository: FakeScheduleRepository) throws
        -> ScheduledItemSaveChange
    {
        guard case .reverted(let left) = try repository.revertScheduledItemSave(change, undone: false) else {
            Issue.record("Undo was stale")
            return change
        }
        return left
    }

    /// Something else changes the ledger a minute later, as another window would.
    private static func later(
        _ repository: FakeScheduleRepository,
        _ change: (LedgerSnapshot, Date) throws -> LedgerSnapshot,
    )
        rethrows
    {
        repository.now = repository.now.addingTimeInterval(60)
        repository.snapshot = try change(repository.snapshot, repository.now)
    }

    private static func payee(_ id: UUID?, in repository: FakeScheduleRepository) -> Payee? {
        repository.snapshot.payees.first { $0.id == id }
    }

    // MARK: B1

    @Test("B1: Undo of an edit is stale once the old category is deleted, and writes nothing")
    func undoStaleAfterOldCategoryDeleted() throws {
        let repository = Self.repository()
        let useCases = repository.useCases()
        var item = try useCases.save(Self.rent, payee: nil).after
        item.categoryID = Self.utilitiesID
        let change = try useCases.save(item, payee: nil)
        try Self.later(repository) {
            try LedgerBook.deletingCategory(id: Fix.housingID, reassigningTo: nil, in: $0, now: $1)
        }
        let before = repository.snapshot
        #expect(
            try repository.revertScheduledItemSave(change, undone: false) == .stale(.scheduledItemChanged(item.id))
        )
        #expect(repository.snapshot == before)
    }

    @Test("B1: Undo of an edit is stale once the old payee is deleted, and writes nothing")
    func undoStaleAfterOldPayeeDeleted() throws {
        let repository = Self.repository()
        let useCases = repository.useCases()
        var item = Self.rent
        item.payeeID = Fix.bakeryID
        item = try useCases.save(item, payee: nil).after
        let change = try useCases.save(item, payee: .create("Gym Co"))
        try Self.later(repository) { try LedgerBook.deletingPayee(id: Fix.bakeryID, in: $0, now: $1) }
        let before = repository.snapshot
        #expect(
            try repository.revertScheduledItemSave(change, undone: false) == .stale(.scheduledItemChanged(item.id))
        )
        #expect(repository.snapshot == before)
    }

    @Test("B1: Redo of a new item is stale once its category is deleted, and writes nothing")
    func redoNewStaleAfterCategoryDeleted() throws {
        let repository = Self.repository()
        let change = try repository.useCases().save(Self.rent, payee: .create("Gym Co"))
        let undone = try Self.undo(change, in: repository)
        try Self.later(repository) {
            try LedgerBook.deletingCategory(id: Fix.housingID, reassigningTo: nil, in: $0, now: $1)
        }
        let before = repository.snapshot
        #expect(
            try repository.revertScheduledItemSave(undone, undone: true) == .stale(.scheduledItemChanged(change.itemID))
        )
        #expect(repository.snapshot == before)
    }

    @Test("B1: Redo of a new item is stale once its account is deleted, and writes nothing")
    func redoNewStaleAfterAccountDeleted() throws {
        let repository = Self.repository()
        let change = try repository.useCases().save(Self.rent, payee: nil)
        let undone = try Self.undo(change, in: repository)
        try Self.later(repository) { try LedgerBook.deletingAccount(id: Fix.savingsID, in: $0, now: $1) }
        let before = repository.snapshot
        #expect(
            try repository.revertScheduledItemSave(undone, undone: true) == .stale(.scheduledItemChanged(change.itemID))
        )
        #expect(repository.snapshot == before)
    }

    @Test("B1: Redo puts back the payee it created itself, so that one being gone isn't stale")
    func redoRecreatesItsOwnPayee() throws {
        let repository = Self.repository()
        let change = try repository.useCases().save(Self.rent, payee: .create("Gym Co"))
        let undone = try Self.undo(change, in: repository)
        #expect(Self.payee(change.createdPayee?.id, in: repository) == nil)
        guard case .reverted = try repository.revertScheduledItemSave(undone, undone: true) else {
            Issue.record("Redo was stale")
            return
        }
        #expect(Self.payee(change.createdPayee?.id, in: repository)?.name == "Gym Co")
    }

    @Test("D351.2: Redo never takes an archived payee of the same name, and makes no second one: it's stale")
    func redoIgnoresArchivedTwin() throws {
        let repository = Self.repository()
        let change = try repository.useCases().save(Self.rent, payee: .create("Gym Co"))
        let undone = try Self.undo(change, in: repository)
        try Self.later(repository) { snapshot, now in
            try LedgerBook.savingPayee(
                Payee(name: "gym co", isArchived: true, createdAt: now),
                in: snapshot,
                now: now,
            )
        }
        let before = repository.snapshot
        #expect(
            try repository.revertScheduledItemSave(undone, undone: true) == .stale(.scheduledItemChanged(change.itemID))
        )
        #expect(repository.snapshot == before)
        #expect(repository.snapshot.payees.filter { $0.name.lowercased() == "gym co" }.count == 1)
    }

    // MARK: D362

    @Test("D362: Undo removes an untouched created payee")
    func untouchedCreatedPayeeRemoved() throws {
        let repository = Self.repository()
        let change = try repository.useCases().save(Self.rent, payee: .create("Gym Co"))
        repository.now = repository.now.addingTimeInterval(60)
        _ = try Self.undo(change, in: repository)
        #expect(Self.payee(change.createdPayee?.id, in: repository) == nil)
    }

    @Test("D362: a created payee assigned to another item and then unassigned is kept by Undo")
    func assignedThenUnassignedKept() throws {
        let repository = Self.repository()
        let useCases = repository.useCases()
        let change = try useCases.save(Self.rent, payee: .create("Gym Co"))
        let gymID = try #require(change.createdPayee?.id)
        repository.now = repository.now.addingTimeInterval(60)
        var other = Fix.rent(start: Fix.day(2026, 11, 5), automatic: false)
        other.payeeID = gymID
        other = try useCases.save(other, payee: nil).after
        repository.now = repository.now.addingTimeInterval(60)
        other.payeeID = nil
        _ = try useCases.save(other, payee: nil)
        let undone = try Self.undo(change, in: repository)
        #expect(Self.payee(gymID, in: repository)?.name == "Gym Co")
        #expect(!repository.snapshot.scheduledItems.contains { $0.id == change.itemID })
        // Redo uses the kept payee, and the next Undo keeps it too.
        guard case .reverted(let redone) = try repository.revertScheduledItemSave(undone, undone: true) else {
            Issue.record("Redo was stale")
            return
        }
        #expect(repository.snapshot.scheduledItems.first { $0.id == change.itemID }?.payeeID == gymID)
        _ = try Self.undo(redone, in: repository)
        #expect(Self.payee(gymID, in: repository) != nil)
    }

    @Test("D362: a created payee given to a transaction and taken off again is kept by Undo")
    func usedByTransactionKept() throws {
        let repository = Self.repository()
        let change = try repository.useCases().save(Self.rent, payee: .create("Gym Co"))
        let gymID = try #require(change.createdPayee?.id)
        let spend = Transaction(
            type: .expense,
            amount: 500,
            date: Fix.date(2026, 10, 20),
            accountID: Fix.savingsID,
            payeeID: gymID,
        )
        try Self.later(repository) { try LedgerBook.savingTransaction(spend, in: $0, now: $1) }
        var unassigned = spend
        unassigned.payeeID = nil
        try Self.later(repository) { try LedgerBook.savingTransaction(unassigned, in: $0, now: $1) }
        _ = try Self.undo(change, in: repository)
        #expect(Self.payee(gymID, in: repository) != nil)
    }

    @Test("D362: a created payee renamed since the save is kept by Undo")
    func renamedKept() throws {
        let repository = Self.repository()
        let change = try repository.useCases().save(Self.rent, payee: .create("Gym Co"))
        var renamed = try #require(change.createdPayee)
        renamed.name = "Gym Company"
        try Self.later(repository) { try LedgerBook.savingPayee(renamed, in: $0, now: $1) }
        _ = try Self.undo(change, in: repository)
        #expect(Self.payee(renamed.id, in: repository)?.name == "Gym Company")
        #expect(repository.snapshot.scheduledItems.isEmpty)
    }

    // MARK: D363

    @Test("D363: Undo archives again an unarchived payee nothing touched, and Redo unarchives it again")
    func untouchedUnarchivedArchivedAgain() throws {
        let repository = Self.repository()
        let change = try repository.useCases().save(Self.rent, payee: .unarchive(Self.oldShopID))
        repository.now = repository.now.addingTimeInterval(60)
        let undone = try Self.undo(change, in: repository)
        #expect(Self.payee(Self.oldShopID, in: repository)?.isArchived == true)
        repository.now = repository.now.addingTimeInterval(60)
        guard case .reverted(let redone) = try repository.revertScheduledItemSave(undone, undone: true) else {
            Issue.record("Redo was stale")
            return
        }
        #expect(Self.payee(Self.oldShopID, in: repository)?.isArchived == false)
        repository.now = repository.now.addingTimeInterval(60)
        _ = try Self.undo(redone, in: repository)
        #expect(Self.payee(Self.oldShopID, in: repository)?.isArchived == true)
    }

    @Test("D363: an unarchived payee assigned to another item since the save stays unarchived after Undo")
    func assignedUnarchivedStays() throws {
        let repository = Self.repository()
        let useCases = repository.useCases()
        let change = try useCases.save(Self.rent, payee: .unarchive(Self.oldShopID))
        repository.now = repository.now.addingTimeInterval(60)
        var other = Fix.rent(start: Fix.day(2026, 11, 5), automatic: false)
        other.payeeID = Self.oldShopID
        other = try useCases.save(other, payee: nil).after
        repository.now = repository.now.addingTimeInterval(60)
        other.payeeID = nil
        _ = try useCases.save(other, payee: nil)
        let undone = try Self.undo(change, in: repository)
        #expect(Self.payee(Self.oldShopID, in: repository)?.isArchived == false)
        guard case .reverted(let redone) = try repository.revertScheduledItemSave(undone, undone: true) else {
            Issue.record("Redo was stale")
            return
        }
        _ = try Self.undo(redone, in: repository)
        #expect(Self.payee(Self.oldShopID, in: repository)?.isArchived == false)
    }

    @Test("D363: an unarchived payee renamed since the save stays unarchived after Undo")
    func renamedUnarchivedStays() throws {
        let repository = Self.repository()
        let change = try repository.useCases().save(Self.rent, payee: .unarchive(Self.oldShopID))
        var renamed = try #require(Self.payee(Self.oldShopID, in: repository))
        renamed.name = "Old Shop Ltd"
        try Self.later(repository) { try LedgerBook.savingPayee(renamed, in: $0, now: $1) }
        _ = try Self.undo(change, in: repository)
        #expect(Self.payee(Self.oldShopID, in: repository)?.isArchived == false)
        #expect(Self.payee(Self.oldShopID, in: repository)?.name == "Old Shop Ltd")
    }
}
