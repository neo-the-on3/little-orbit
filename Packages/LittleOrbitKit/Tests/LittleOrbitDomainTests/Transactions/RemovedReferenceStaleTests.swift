import Foundation
import LittleOrbitDomain
import Testing

/// A category merge or delete, or a payee merge, isn't undoable, and it makes stale any step in another window
/// whose Undo or Redo would put a transaction back in the removed category or under the removed payee
/// (D287.4, D187.5, D191.2). The check is by value, on what reverting would write, so a step that doesn't put
/// the removed record back still works, and an archived category isn't removed (D295.7).
@MainActor
@Suite("Stale undo steps: a removed category or payee")
struct RemovedReferenceStaleTests {
    typealias F = TransactionFixture  // swiftlint:disable:this type_name

    private static let groceriesID = UUID(uuidString: "C0000000-0000-4000-8000-000000000001")!
    private static let diningID = UUID(uuidString: "C0000000-0000-4000-8000-000000000002")!
    private static let shoppingID = UUID(uuidString: "C0000000-0000-4000-8000-000000000003")!

    private static var categories: [TransactionCategory] {
        [
            TransactionCategory(id: groceriesID, name: "Groceries", kind: .expense, sortOrder: 0),
            TransactionCategory(id: diningID, name: "Dining Out", kind: .expense, sortOrder: 1),
            TransactionCategory(id: shoppingID, name: "Shopping", kind: .expense, sortOrder: 2),
        ]
    }

    @MainActor
    private struct Setup {
        let repository: FakeLedgerRepository
        let useCases: TransactionUseCases
        let categories: CategoryUseCases
        var changes: any TransactionChangesUseCase { useCases.changes }

        /// A window's step: the change and what it left.
        func step(_ change: TransactionChange) throws -> (TransactionChange, ChangeOutcome) {
            (change, try changes.outcome(of: change))
        }

        func stored(_ id: UUID) throws -> Transaction? {
            try repository.transactions().first { $0.id == id }
        }

        func edit(_ id: UUID, _ body: (inout Transaction) -> Void) throws -> TransactionChange {
            var transaction = try #require(try stored(id))
            body(&transaction)
            return try useCases.saveTransactions.save([transaction])
        }

        /// Undo or Redo, expecting it to work; returns the step to revert next and what it left.
        func revertNow(_ change: TransactionChange, _ outcome: ChangeOutcome) throws -> (
            TransactionChange, ChangeOutcome
        ) {
            guard case .reverted(let inverse, let left) = try changes.revert(change, expecting: outcome) else {
                Issue.record("Expected the step to revert")
                return (change, outcome)
            }
            return (inverse, left)
        }
    }

    private func setup(_ transactions: [Transaction] = [], payees: [Payee] = []) throws -> Setup {
        let repository = try FakeLedgerRepository(
            accounts: F.accounts,
            categories: Self.categories,
            seedPending: false,
        )
        for payee in payees {
            try repository.savePayee(payee)
        }
        for transaction in transactions {
            try repository.saveTransaction(transaction)
        }
        return Setup(
            repository: repository,
            useCases: TransactionUseCases(repository: repository, categoryNames: TestCategoryNames()),
            categories: CategoryUseCases(repository: repository),
        )
    }

    private func spend(_ amount: Decimal, category: UUID? = nil, payee: UUID? = nil) -> Transaction {
        var transaction = F.expense(amount, on: F.date(2026, 10, 18))
        transaction.categoryID = category
        transaction.payeeID = payee
        return transaction
    }

    // MARK: Undo of a delete

    @Test("A deletes a transaction, B deletes its category; A's Undo is stale and restores nothing")
    func undoDeleteAfterCategoryDelete() throws {
        let bakery = spend(450, category: Self.groceriesID)
        let setup = try setup([bakery])
        let (change, outcome) = try setup.step(try setup.changes.remove(ids: [bakery.id]))
        try setup.categories.deleteCategory.delete(Self.groceriesID, choice: .move(targetID: Self.shoppingID))
        let writes = setup.repository.writes

        #expect(
            try setup.changes.check(change, expecting: outcome)
                == .stale(.referenceRemoved([bakery.id], removed: [.category(Self.groceriesID)]))
        )
        #expect(
            try setup.changes.revert(change, expecting: outcome)
                == .stale(.referenceRemoved([bakery.id], removed: [.category(Self.groceriesID)]))
        )
        #expect(try setup.stored(bakery.id) == nil)
        #expect(setup.repository.writes == writes, "A stale step writes nothing")
    }

    @Test("A deletes, B deletes the category leaving its transactions uncategorised; A's Undo is stale")
    func undoDeleteAfterLeaveUncategorised() throws {
        let bakery = spend(450, category: Self.groceriesID)
        let setup = try setup([bakery])
        let (change, outcome) = try setup.step(try setup.changes.remove(ids: [bakery.id]))
        try setup.categories.deleteCategory.delete(Self.groceriesID, choice: .leaveUncategorised)

        #expect(
            try setup.changes.revert(change, expecting: outcome)
                == .stale(.referenceRemoved([bakery.id], removed: [.category(Self.groceriesID)]))
        )
        #expect(try setup.stored(bakery.id) == nil)
    }

    @Test("A deletes, B merges its category into another; A's Undo is stale")
    func undoDeleteAfterCategoryMerge() throws {
        let bakery = spend(450, category: Self.groceriesID)
        let setup = try setup([bakery])
        let (change, outcome) = try setup.step(try setup.changes.remove(ids: [bakery.id]))
        try setup.categories.mergeCategories.merge(Self.groceriesID, into: Self.diningID)

        #expect(
            try setup.changes.revert(change, expecting: outcome)
                == .stale(.referenceRemoved([bakery.id], removed: [.category(Self.groceriesID)]))
        )
    }

    @Test("A deletes, B merges its payee into another; A's Undo is stale and restores nothing")
    func undoDeleteAfterPayeeMerge() throws {
        let parcel = Payee(name: "Parcel Point")
        let parcelIn = Payee(name: "PARCELPOINT.IN")
        let order = spend(1_200, payee: parcelIn.id)
        let setup = try setup([order], payees: [parcel, parcelIn])
        let (change, outcome) = try setup.step(try setup.changes.remove(ids: [order.id]))
        try setup.categories.managePayees.merge([parcelIn.id], into: parcel.id)

        #expect(
            try setup.changes.revert(change, expecting: outcome)
                == .stale(.referenceRemoved([order.id], removed: [.payee(parcelIn.id)]))
        )
        #expect(try setup.stored(order.id) == nil)
    }

    @Test("A bulk-deletes 3, B deletes one's category; the whole Undo is stale and restores none (D161.2)")
    func bulkUndoAllOrNothing() throws {
        let rows = [
            spend(450, category: Self.groceriesID),
            spend(900, category: Self.diningID),
            spend(120),
        ]
        let setup = try setup(rows)
        let (change, outcome) = try setup.step(try setup.changes.remove(ids: rows.map(\.id)))
        try setup.categories.deleteCategory.delete(Self.groceriesID, choice: .leaveUncategorised)

        #expect(
            try setup.changes.revert(change, expecting: outcome)
                == .stale(.referenceRemoved([rows[0].id], removed: [.category(Self.groceriesID)]))
        )
        #expect(try setup.repository.transactions().isEmpty)
    }

    @Test("A deletes a transaction whose split line uses a category B then deletes; A's Undo is stale")
    func undoDeleteWithSplitLine() throws {
        let order = spend(1_000)
        let setup = try setup([order])
        try setup.repository.replaceSplits(
            [
                TransactionSplit(transactionID: order.id, categoryID: Self.groceriesID, amount: 600, sortOrder: 0),
                TransactionSplit(transactionID: order.id, categoryID: Self.diningID, amount: 400, sortOrder: 1),
            ],
            for: order.id,
        )
        let (change, outcome) = try setup.step(try setup.changes.remove(ids: [order.id]))
        try setup.categories.deleteCategory.delete(Self.diningID, choice: .move(targetID: Self.shoppingID))

        #expect(
            try setup.changes.revert(change, expecting: outcome)
                == .stale(.referenceRemoved([order.id], removed: [.category(Self.diningID)]))
        )
        #expect(try setup.stored(order.id) == nil)
    }

    @Test("A deletes an account, B deletes a category one of its transactions used; Undo Delete Account is stale")
    func undoAccountDeleteAfterCategoryDelete() throws {
        let bakery = spend(450, category: Self.groceriesID)
        let setup = try setup([bakery])
        let removed = try DefaultDeleteAccountUseCase(repository: setup.repository).delete(F.savingsID)
        let (change, outcome) = try setup.step(.removedAccount(removed))
        try setup.categories.deleteCategory.delete(Self.groceriesID, choice: .leaveUncategorised)

        #expect(
            try setup.changes.revert(change, expecting: outcome)
                == .stale(.referenceRemoved([bakery.id], removed: [.category(Self.groceriesID)]))
        )
        #expect(try !setup.repository.accounts().contains { $0.id == F.savingsID })
    }

    @Test("A deletes a transaction, B archives its category; A's Undo works: archiving removes nothing (D295.7)")
    func undoDeleteAfterArchive() throws {
        let bakery = spend(450, category: Self.groceriesID)
        let setup = try setup([bakery])
        let (change, outcome) = try setup.step(try setup.changes.remove(ids: [bakery.id]))
        try setup.categories.archiveCategory.archive(Self.groceriesID)

        _ = try setup.revertNow(change, outcome)
        #expect(try setup.stored(bakery.id)?.categoryID == Self.groceriesID)
    }

    // MARK: Undo and Redo of an edit

    @Test("A recategorises Groceries → Dining Out, B deletes Groceries; A's Undo is stale")
    func undoEditBackToDeletedCategory() throws {
        let bakery = spend(450, category: Self.groceriesID)
        let setup = try setup([bakery])
        let (change, outcome) = try setup.step(try setup.edit(bakery.id) { $0.categoryID = Self.diningID })
        try setup.categories.deleteCategory.delete(Self.groceriesID, choice: .move(targetID: Self.shoppingID))
        let writes = setup.repository.writes

        #expect(
            try setup.changes.revert(change, expecting: outcome)
                == .stale(.referenceRemoved([bakery.id], removed: [.category(Self.groceriesID)]))
        )
        #expect(try setup.stored(bakery.id)?.categoryID == Self.diningID)
        #expect(setup.repository.writes == writes)
    }

    @Test("A changes the payee, B merges the old payee away; A's Undo is stale and keeps the new payee")
    func undoEditBackToMergedPayee() throws {
        let maple = Payee(name: "Maple Noodle Bar")
        let pebble = Payee(name: "Pebble Market")
        let slice = Payee(name: "Slice House")
        let lunch = spend(300, payee: maple.id)
        let setup = try setup([lunch], payees: [maple, pebble, slice])
        let (change, outcome) = try setup.step(try setup.edit(lunch.id) { $0.payeeID = pebble.id })
        try setup.categories.managePayees.merge([maple.id], into: slice.id)

        #expect(
            try setup.changes.revert(change, expecting: outcome)
                == .stale(.referenceRemoved([lunch.id], removed: [.payee(maple.id)]))
        )
        #expect(try setup.stored(lunch.id)?.payeeID == pebble.id)
    }

    @Test("A edits the amount, B deletes the category moving it on; A's Undo works and keeps B's category")
    func untouchedCategoryIsNotStale() throws {
        let bakery = spend(450, category: Self.groceriesID)
        let setup = try setup([bakery])
        let (change, outcome) = try setup.step(try setup.edit(bakery.id) { $0.amount = 500 })
        try setup.categories.deleteCategory.delete(Self.groceriesID, choice: .move(targetID: Self.shoppingID))

        _ = try setup.revertNow(change, outcome)
        let stored = try #require(try setup.stored(bakery.id))
        #expect(stored.amount == 450)
        #expect(stored.categoryID == Self.shoppingID)
    }

    @Test("A recategorises, undoes, then B deletes the category A's Redo would set; A's Redo is stale")
    func redoToDeletedCategory() throws {
        let bakery = spend(450, category: Self.groceriesID)
        let setup = try setup([bakery])
        let (change, outcome) = try setup.step(try setup.edit(bakery.id) { $0.categoryID = Self.diningID })
        let (redo, left) = try setup.revertNow(change, outcome)
        try setup.categories.deleteCategory.delete(Self.diningID, choice: .move(targetID: Self.shoppingID))

        #expect(
            try setup.changes.revert(redo, expecting: left)
                == .stale(.referenceRemoved([bakery.id], removed: [.category(Self.diningID)]))
        )
        #expect(try setup.stored(bakery.id)?.categoryID == Self.groceriesID)
    }

    @Test("A step whose transaction B changed reports the change first, not the removed category")
    func changedComesFirst() throws {
        let bakery = spend(450, category: Self.groceriesID)
        let setup = try setup([bakery])
        let (change, outcome) = try setup.step(try setup.edit(bakery.id) { $0.categoryID = Self.diningID })
        try setup.categories.deleteCategory.delete(Self.groceriesID, choice: .leaveUncategorised)
        _ = try setup.edit(bakery.id) { $0.categoryID = Self.shoppingID }

        #expect(try setup.changes.revert(change, expecting: outcome) == .stale(.changed([bakery.id])))
    }

    // MARK: What was removed

    @Test(
        "A deletes a transaction, B deletes its category and merges its payee away; both are reported, category first"
    )
    func categoryAndPayeeBothRemoved() throws {
        let maple = Payee(name: "Maple Noodle Bar")
        let slice = Payee(name: "Slice House")
        let lunch = spend(300, category: Self.diningID, payee: maple.id)
        let setup = try setup([lunch], payees: [maple, slice])
        let (change, outcome) = try setup.step(try setup.changes.remove(ids: [lunch.id]))
        try setup.categories.managePayees.merge([maple.id], into: slice.id)
        try setup.categories.deleteCategory.delete(Self.diningID, choice: .leaveUncategorised)

        #expect(
            try setup.changes.revert(change, expecting: outcome)
                == .stale(.referenceRemoved([lunch.id], removed: [.category(Self.diningID), .payee(maple.id)]))
        )
        #expect(try setup.stored(lunch.id) == nil)
    }

    // MARK: A linked refund (D306.3)

    @Test("A deletes a linked refund, B deletes its category moving the expense on; A's Undo is stale, not relinked")
    func deletedRefundWhoseCategoryWasDeleted() throws {
        let expense = spend(5_000, category: Self.groceriesID)
        var refund = spend(2_000, category: Self.groceriesID)
        refund.type = .income
        refund.refundOfID = expense.id
        refund.isRefund = true
        let setup = try setup([expense, refund])
        let (change, outcome) = try setup.step(try setup.changes.remove(ids: [refund.id]))
        try setup.categories.deleteCategory.delete(Self.groceriesID, choice: .move(targetID: Self.shoppingID))
        #expect(try setup.stored(expense.id)?.categoryID == Self.shoppingID, "The expense lives on, moved")
        let writes = setup.repository.writes

        // The check reads the refund's own stored category, so Undo doesn't relink it into the expense's
        // current one: that would write a category the user never chose (D306.3).
        #expect(
            try setup.changes.revert(change, expecting: outcome)
                == .stale(.referenceRemoved([refund.id], removed: [.category(Self.groceriesID)]))
        )
        #expect(try setup.stored(refund.id) == nil, "Nothing restored or relinked")
        #expect(try setup.stored(expense.id)?.categoryID == Self.shoppingID)
        #expect(setup.repository.writes == writes, "A stale step writes nothing")
    }

    // MARK: Names for the alert (NB8)

    @Test("The names an Undo step keeps come from the categories and payees alone, by id")
    func recordNamesByID() throws {
        let maple = Payee(name: "Maple Noodle Bar")
        let setup = try setup([spend(450, category: Self.groceriesID, payee: maple.id)], payees: [maple])
        let names = try setup.useCases.loadLedger.recordNames(
            categoryIDs: [Self.groceriesID, UUID()],
            payeeIDs: [maple.id],
        )
        #expect(names == [Self.groceriesID: "Groceries", maple.id: "Maple Noodle Bar"])
        try setup.categories.mergeCategories.merge(Self.groceriesID, into: Self.diningID)
        #expect(try setup.useCases.loadLedger.recordNames(categoryIDs: [Self.groceriesID], payeeIDs: []).isEmpty)
    }
}
