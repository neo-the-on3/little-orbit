import Foundation
import LittleOrbitDomain
import LittleOrbitFeatures
import LittleOrbitPersistence
import Testing

/// A category merge or delete, or a payee merge, clears the history of the window it's made in (D287.4). In
/// every other window, a step whose Undo or Redo would put a transaction back in the removed category or under
/// the removed payee is stale: it shows the existing “Can’t Undo” or “Can’t Redo” alert, writes nothing and is
/// removed. The message names the removed record with the existing D228 string, “Groceries has been deleted.”,
/// and a bulk step with more than one such transaction counts them (D306.1 as amended, D189.2). Other steps are
/// unaffected (D287.4, D187.5).
@MainActor
@Suite("Stale undo steps: a category or payee removed in another window")
struct WindowUndoRemovedReferenceTests {
    typealias F = TransactionFeatureFixture  // swiftlint:disable:this type_name

    @MainActor
    private struct Setup {
        let repository: InMemoryLedgerRepository
        let useCases: TransactionUseCases
        let categories: CategoryUseCases
        let updates: LedgerUpdates
        /// The windows' reads, counted.
        let reads: CountingLedgerReads
        let first: TestWindow
        let second: TestWindow

        func edit(_ id: UUID, in window: TestWindow, _ body: (inout Transaction) -> Void) throws {
            var transaction = try #require(try repository.transactions().first { $0.id == id })
            body(&transaction)
            window.history.record(try useCases.saveTransactions.save([transaction]))
        }

        func delete(_ id: UUID, in window: TestWindow) throws {
            window.history.record(try useCases.changes.remove(ids: [id]))
        }

        func stored(_ id: UUID) throws -> Transaction? {
            try repository.transactions().first { $0.id == id }
        }
    }

    private func setup(_ transactions: [Transaction], payees: [Payee] = []) throws -> Setup {
        let repository = try F.repository()
        for payee in payees {
            try repository.savePayee(payee)
        }
        for transaction in transactions {
            try repository.saveTransaction(transaction)
        }
        var useCases = TransactionUseCases(repository: repository, categoryNames: CatalogDefaultCategoryNames())
        let reads = CountingLedgerReads(useCases.loadLedger)
        useCases.loadLedger = reads
        let updates = LedgerUpdates()
        let setup = Setup(
            repository: repository,
            useCases: useCases,
            categories: CategoryUseCases(repository: repository),
            updates: updates,
            reads: reads,
            first: TestWindow(useCases, updates: updates),
            second: TestWindow(useCases, updates: updates),
        )
        setup.first.history.setScreen(.account(F.savingsID))
        return setup
    }

    private var bakery: Transaction {
        F.expense(450, on: F.date(2026, 10, 18), category: DefaultCategoryID.groceries, details: "Corner Bakery")
    }

    @Test("B deletes the category of a transaction A deleted; A's Undo names it, writes nothing and is removed")
    func undoDeleteAfterCategoryDelete() throws {
        let corner = bakery
        let setup = try setup([corner])
        try setup.delete(corner.id, in: setup.first)
        try setup.categories.deleteCategory.delete(
            DefaultCategoryID.groceries,
            choice: .move(targetID: DefaultCategoryID.shopping),
        )
        setup.second.history.clearAfterRemoval()
        let revision = setup.updates.revision

        setup.first.history.undo()
        #expect(setup.first.history.alert?.title == "Can’t Undo Delete Transaction in Everyday Savings")
        #expect(setup.first.history.alert?.message == "Groceries has been deleted. Nothing was changed.")
        #expect(try setup.stored(corner.id) == nil, "Nothing restored")
        #expect(setup.updates.revision == revision, "Nothing written")
        #expect(!setup.first.history.canUndo)
        #expect(!setup.first.history.canRedo)
    }

    @Test("Only the stale step goes: A's older edit still undoes after the alert")
    func otherStepsUnaffected() throws {
        let corner = bakery
        let fuel = F.expense(900, on: F.date(2026, 10, 17), category: DefaultCategoryID.transport, details: "Fuel")
        let setup = try setup([corner, fuel])
        try setup.edit(fuel.id, in: setup.first) { $0.amount = 950 }
        try setup.delete(corner.id, in: setup.first)
        try setup.categories.mergeCategories.merge(DefaultCategoryID.groceries, into: DefaultCategoryID.food)

        setup.first.history.undo()
        #expect(setup.first.history.alert?.title == "Can’t Undo Delete Transaction in Everyday Savings")
        setup.first.history.dismissAlert()
        #expect(setup.first.history.undoTitle == "Edit Transaction in Everyday Savings")

        setup.first.history.undo()
        #expect(setup.first.history.alert == nil)
        #expect(try setup.stored(fuel.id)?.amount == 900)
        #expect(try setup.stored(corner.id) == nil)
    }

    @Test("B merges away the payee A's Undo would put back; A's Undo can't, names it and keeps the new payee")
    func undoEditAfterPayeeMerge() throws {
        let maple = Payee(name: "Maple Noodle Bar")
        let pebble = Payee(name: "Pebble Market")
        let slice = Payee(name: "Slice House")
        let lunch = F.expense(300, on: F.date(2026, 10, 18), payee: maple.id)
        let setup = try setup([lunch], payees: [maple, pebble, slice])
        try setup.edit(lunch.id, in: setup.first) { $0.payeeID = pebble.id }
        try setup.categories.managePayees.merge([maple.id], into: slice.id)

        setup.first.history.undo()
        #expect(setup.first.history.alert?.title == "Can’t Undo Edit Transaction in Everyday Savings")
        #expect(setup.first.history.alert?.message == "Maple Noodle Bar has been deleted. Nothing was changed.")
        #expect(try setup.stored(lunch.id)?.payeeID == pebble.id)
        #expect(!setup.first.history.canUndo)
    }

    @Test("B deletes the category A's Redo would set; A's Redo can't and Undo stays empty")
    func redoAfterCategoryDelete() throws {
        let corner = bakery
        let setup = try setup([corner])
        try setup.edit(corner.id, in: setup.first) { $0.categoryID = DefaultCategoryID.shopping }
        setup.first.history.undo()
        #expect(try setup.stored(corner.id)?.categoryID == DefaultCategoryID.groceries)
        try setup.categories.deleteCategory.delete(DefaultCategoryID.shopping, choice: .leaveUncategorised)

        setup.first.history.redo()
        #expect(setup.first.history.alert?.title == "Can’t Redo Edit Transaction in Everyday Savings")
        #expect(setup.first.history.alert?.message == "Shopping has been deleted. Nothing was changed.")
        #expect(try setup.stored(corner.id)?.categoryID == DefaultCategoryID.groceries)
        #expect(!setup.first.history.canRedo)
        #expect(!setup.first.history.canUndo)
    }

    @Test("A bulk delete with two transactions in the removed category counts them (D189.2)")
    func bulkCount() throws {
        let rows = [
            bakery,
            F.expense(120, on: F.date(2026, 10, 16), category: DefaultCategoryID.groceries, details: "Tea"),
            F.expense(900, on: F.date(2026, 10, 17), category: DefaultCategoryID.transport, details: "Fuel"),
        ]
        let setup = try setup(rows)
        setup.first.history.record(try setup.useCases.changes.remove(ids: rows.map(\.id)))
        try setup.categories.deleteCategory.delete(DefaultCategoryID.groceries, choice: .leaveUncategorised)

        setup.first.history.undo()
        #expect(setup.first.history.alert?.title == "Can’t Undo Delete 3 Transactions in Everyday Savings")
        #expect(
            setup.first.history.alert?.message
                == "2 of these transactions have changed or been deleted since then. Nothing was changed."
        )
        #expect(try setup.repository.transactions().isEmpty, "All or nothing (D161.2)")
    }

    @Test("B merges away the category of a transaction A deleted; the alert names the merged-away category")
    func mergedAwayCategoryIsNamed() throws {
        let corner = bakery
        let setup = try setup([corner])
        try setup.delete(corner.id, in: setup.first)
        try setup.categories.mergeCategories.merge(DefaultCategoryID.groceries, into: DefaultCategoryID.food)

        setup.first.history.undo()
        #expect(setup.first.history.alert?.message == "Groceries has been deleted. Nothing was changed.")
    }

    @Test("One transaction in a bulk step, with its category and payee both removed: the category is named")
    func oneOfABulkStepNamesTheFirstRemovedRecord() throws {
        let maple = Payee(name: "Maple Noodle Bar")
        let slice = Payee(name: "Slice House")
        var corner = bakery
        corner.payeeID = maple.id
        let fuel = F.expense(900, on: F.date(2026, 10, 17), category: DefaultCategoryID.transport, details: "Fuel")
        let setup = try setup([corner, fuel], payees: [maple, slice])
        setup.first.history.record(try setup.useCases.changes.remove(ids: [corner.id, fuel.id]))
        try setup.categories.managePayees.merge([maple.id], into: slice.id)
        try setup.categories.deleteCategory.delete(DefaultCategoryID.groceries, choice: .leaveUncategorised)

        setup.first.history.undo()
        #expect(setup.first.history.alert?.title == "Can’t Undo Delete 2 Transactions in Everyday Savings")
        #expect(setup.first.history.alert?.message == "Groceries has been deleted. Nothing was changed.")
        #expect(try setup.repository.transactions().isEmpty, "All or nothing (D161.2)")
    }

    @Test("A stale step whose transaction changed keeps the “has changed since then” wording")
    func changedKeepsItsWording() throws {
        let corner = bakery
        let setup = try setup([corner])
        try setup.edit(corner.id, in: setup.first) { $0.categoryID = DefaultCategoryID.shopping }
        try setup.categories.deleteCategory.delete(DefaultCategoryID.groceries, choice: .leaveUncategorised)
        try setup.edit(corner.id, in: setup.second) { $0.categoryID = DefaultCategoryID.transport }

        setup.first.history.undo()
        #expect(setup.first.history.alert?.message == "Corner Bakery has changed since then. Nothing was changed.")
    }

    @Test("A's archived category isn't removed: A's Undo restores the transaction in it (D295.7)")
    func archiveKeepsSteps() throws {
        let corner = bakery
        let setup = try setup([corner])
        try setup.delete(corner.id, in: setup.first)
        try setup.categories.archiveCategory.archive(DefaultCategoryID.groceries)

        setup.first.history.undo()
        #expect(setup.first.history.alert == nil)
        #expect(try setup.stored(corner.id)?.categoryID == DefaultCategoryID.groceries)
    }

    @Test("The window that merges clears its own history; the other window keeps its steps (D287.4)")
    func onlyTheMergingWindowClears() throws {
        let corner = bakery
        let fuel = F.expense(900, on: F.date(2026, 10, 17), category: DefaultCategoryID.transport, details: "Fuel")
        let setup = try setup([corner, fuel])
        try setup.edit(fuel.id, in: setup.first) { $0.amount = 950 }
        try setup.edit(corner.id, in: setup.second) { $0.categoryID = DefaultCategoryID.transport }
        try setup.categories.mergeCategories.merge(DefaultCategoryID.groceries, into: DefaultCategoryID.food)
        setup.second.history.clearAfterRemoval()

        #expect(!setup.second.history.canUndo)
        #expect(setup.first.history.undoTitle == "Edit Transaction in Everyday Savings")
        setup.first.history.undo()
        #expect(setup.first.history.alert == nil)
        #expect(try setup.stored(fuel.id)?.amount == 900)
    }

    // MARK: The names a step keeps (NB8, NB9)

    @Test("A removed category no one can name keeps the step's “has changed since then” wording")
    func noNameKeepsTheStepsWording() throws {
        let corner = bakery
        let setup = try setup([corner])
        setup.reads.losesNames = true
        try setup.delete(corner.id, in: setup.first)
        try setup.categories.deleteCategory.delete(DefaultCategoryID.groceries, choice: .leaveUncategorised)

        setup.first.history.undo()
        #expect(setup.first.history.alert?.title == "Can’t Undo Delete Transaction in Everyday Savings")
        #expect(setup.first.history.alert?.message == "Corner Bakery has changed since then. Nothing was changed.")
        #expect(try setup.stored(corner.id) == nil)
    }

    @Test("A step's names follow a rename through Undo and Redo: the alert names the category as last seen")
    func namesRefreshAfterUndoAndRedo() throws {
        let corner = bakery
        let setup = try setup([corner])
        try setup.edit(corner.id, in: setup.first) { $0.categoryID = DefaultCategoryID.shopping }
        try setup.categories.saveCategory.rename(DefaultCategoryID.groceries, to: "Fresh Produce")
        setup.first.history.undo()
        #expect(setup.first.history.alert == nil)
        #expect(try setup.stored(corner.id)?.categoryID == DefaultCategoryID.groceries)
        setup.first.history.redo()
        #expect(setup.first.history.alert == nil)
        try setup.categories.mergeCategories.merge(DefaultCategoryID.groceries, into: DefaultCategoryID.food)

        setup.first.history.undo()
        #expect(setup.first.history.alert?.message == "Fresh Produce has been deleted. Nothing was changed.")
        #expect(try setup.stored(corner.id)?.categoryID == DefaultCategoryID.shopping)
    }

    @Test("Keeping names reads only category and payee names, once per kept step and per Undo or Redo")
    func namesAreReadNarrowly() throws {
        let corner = bakery
        let setup = try setup([corner])
        try setup.edit(corner.id, in: setup.first) { $0.amount = 500 }
        #expect(setup.reads.nameReads == 1)
        setup.first.history.undo()
        setup.first.history.redo()
        #expect(setup.reads.nameReads == 3)
        #expect(setup.reads.ledgerReads == 0, "No whole-store read for the names")
    }

    @Test("A change with no Undo step kept, in a window with no UndoManager, reads no names")
    func noStepNoNames() throws {
        let corner = bakery
        let setup = try setup([corner])
        let detached = WindowUndoHistory(
            changes: setup.useCases.changes,
            loadLedger: setup.useCases.loadLedger,
            updates: setup.updates,
        )
        var edited = try #require(try setup.stored(corner.id))
        edited.amount = 500
        detached.record(try setup.useCases.saveTransactions.save([edited]))
        #expect(!detached.canUndo)
        #expect(setup.reads.nameReads == 0)
        #expect(setup.reads.ledgerReads == 0)
    }
}

/// The window's ledger reads, counted, over the real use case. With `losesNames` set, the names can't be read,
/// as when the store fails, so a step keeps none.
@MainActor
final class CountingLedgerReads: LoadTransactionLedgerUseCase {
    struct Unreadable: Error {}

    private let base: any LoadTransactionLedgerUseCase
    var losesNames = false
    private(set) var ledgerReads = 0
    private(set) var nameReads = 0

    init(_ base: any LoadTransactionLedgerUseCase) {
        self.base = base
    }

    func ledger() throws -> TransactionLedger {
        ledgerReads += 1
        return try base.ledger()
    }

    func ledgerForEntry() throws -> TransactionLedger {
        try base.ledgerForEntry()
    }

    func recordNames(categoryIDs: Set<UUID>, payeeIDs: Set<UUID>) throws -> [UUID: String] {
        nameReads += 1
        if losesNames {
            throw Unreadable()
        }
        return try base.recordNames(categoryIDs: categoryIDs, payeeIDs: payeeIDs)
    }
}
