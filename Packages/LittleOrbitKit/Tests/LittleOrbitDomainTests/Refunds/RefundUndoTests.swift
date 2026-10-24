import Foundation
import LittleOrbitDomain
import Testing

/// Refunds through the transaction use cases: the editor's save, delete, and Undo and Redo of both (#55;
/// D19, D33.4, D35.2). Undo restores exactly what the change changed, or nothing.
@MainActor
@Suite("Refund use cases and Undo (#55)")
struct RefundUndoTests {
    typealias F = TransactionFixture  // swiftlint:disable:this type_name
    typealias R = RefundFixture  // swiftlint:disable:this type_name

    // MARK: - Editor save

    @Test("A2a (D35.2): the editor can't create an unlinked refund; it can still edit an existing one (A4)")
    func editorNeedsOriginal() throws {
        let orphan = R.refund(1_200, of: nil)
        let repository = try R.repository([orphan])
        let save = TransactionUseCases(repository: repository, categoryNames: TestCategoryNames()).saveTransactions
        let new = R.refund(2_000, of: nil)
        #expect(throws: LedgerValidationError.refundNeedsOriginal) { try save.save([new]) }
        #expect(try repository.stored(new.id) == nil)
        let stored = try #require(try repository.stored(orphan.id))
        var edited = stored
        edited.note = "store credit"
        #expect(try save.save([edited]) == .replaced([stored]))
    }

    @Test("A5: a rejected save changes no balance and returns no change to undo")
    func rejectedSaveChangesNothing() throws {
        let expense = R.expense(5_000)
        let repository = try R.repository([expense])
        let save = TransactionUseCases(repository: repository, categoryNames: TestCategoryNames()).saveTransactions
        let before = repository.snapshot
        let rejected = [
            R.refund(2_000, of: expense, isRefund: false),
            R.refund(2_000, of: expense, in: R.salaryID),
            R.refund(Decimal(string: "5000.01")!, of: expense),
        ]
        for refund in rejected {
            #expect(throws: LedgerValidationError.self) { try save.save([refund]) }
        }
        #expect(repository.snapshot == before)
        #expect(try repository.balance(of: F.savingsID, today: F.day(2026, 10, 31)) == 5_000)
    }

    @Test("D1, D2: one save moves the expense and its refunds; one Undo reverts all three, one Redo redoes them")
    func categoryChangeUndo() throws {
        var expense = R.expense(5_000)
        let first = R.refund(2_000, of: expense)
        let second = R.refund(500, of: expense)
        let repository = try R.repository([expense, first, second])
        let useCases = TransactionUseCases(repository: repository, categoryNames: TestCategoryNames())
        expense.categoryID = R.diningID
        let change = try useCases.saveTransactions.save([expense])
        #expect(Set(change.transactionIDs) == [expense.id, first.id, second.id])
        #expect(try repository.stored(first.id)?.categoryID == R.diningID)
        let redo = try useCases.changes.revertNow(change)
        for id in [expense.id, first.id, second.id] {
            #expect(try repository.stored(id)?.categoryID == R.groceriesID)
        }
        _ = try useCases.changes.revertNow(redo)
        for id in [expense.id, first.id, second.id] {
            #expect(try repository.stored(id)?.categoryID == R.diningID)
        }
    }

    @Test("G4: Undo of an orphan's category change puts its category back")
    func orphanCategoryUndo() throws {
        let orphan = R.refund(2_000, of: nil)
        let repository = try R.repository([orphan])
        let useCases = TransactionUseCases(repository: repository, categoryNames: TestCategoryNames())
        var edited = try #require(try repository.stored(orphan.id))
        edited.categoryID = R.shoppingID
        let change = try useCases.saveTransactions.save([edited])
        _ = try useCases.changes.revertNow(change)
        #expect(try repository.stored(orphan.id)?.categoryID == R.groceriesID)
    }

    // MARK: - Delete and Undo (AC 4)

    @Test("S20, S21, AC4, v1 Happy 5: Undo of the delete restores the expense and re-links both refunds")
    func deleteAndUndo() throws {
        let expense = R.expense(1_000, in: R.shoppingID)
        let first = R.refund(200, of: expense)
        let second = R.refund(100, of: expense)
        let repository = try R.repository([expense, first, second])
        let changes = TransactionUseCases(repository: repository, categoryNames: TestCategoryNames()).changes
        let removed = try changes.remove(ids: [expense.id])
        for id in [first.id, second.id] {
            let refund = try #require(try repository.stored(id))
            #expect(RefundStatus(of: refund) == .originalDeleted)
            #expect(refund.categoryID == R.shoppingID)
        }
        let redo = try changes.revertNow(removed)
        #expect(redo == .added([expense.id]))
        let restored = try #require(try repository.stored(expense.id))
        #expect(restored.amount == expense.amount)
        #expect(restored.date == expense.date)
        #expect(restored.categoryID == R.shoppingID)
        for id in [first.id, second.id] {
            #expect(RefundStatus(of: try #require(try repository.stored(id))) == .linked(originalID: expense.id))
        }
        // S21: ₹700 is refundable again.
        #expect(expense.amount - LedgerBook.refundedAmount(of: expense.id, in: repository.snapshot) == 700)
        // Redo deletes it again, unlinking both.
        _ = try changes.revertNow(redo)
        #expect(try repository.stored(first.id)?.refundOfID == nil)
        #expect(try repository.stored(second.id)?.refundOfID == nil)
    }

    @Test("B7: Undo of a fully refunded expense's delete isn't blocked by the cap")
    func undoAtFullCap() throws {
        let expense = R.expense(5_000)
        let refunds = [R.refund(3_000, of: expense), R.refund(2_000, of: expense)]
        let repository = try R.repository([expense] + refunds)
        let changes = TransactionUseCases(repository: repository, categoryNames: TestCategoryNames()).changes
        _ = try changes.revertNow(try changes.remove(ids: [expense.id]))
        #expect(LedgerBook.refundedAmount(of: expense.id, in: repository.snapshot) == 5_000)
    }

    @Test("D4: an expense moved to Dining and deleted comes back in Dining with its refunds re-linked")
    func movedThenDeleted() throws {
        var expense = R.expense(5_000)
        let refund = R.refund(2_000, of: expense)
        let repository = try R.repository([expense, refund])
        let useCases = TransactionUseCases(repository: repository, categoryNames: TestCategoryNames())
        expense.categoryID = R.diningID
        _ = try useCases.saveTransactions.save([expense])
        _ = try useCases.changes.revertNow(try useCases.changes.remove(ids: [expense.id]))
        #expect(try repository.stored(expense.id)?.categoryID == R.diningID)
        let stored = try #require(try repository.stored(refund.id))
        #expect(stored.refundOfID == expense.id)
        #expect(stored.categoryID == R.diningID)
    }

    @Test("v1 Edge 7: delete the expense, then the orphan, then Undo twice: both back, the refund re-linked")
    func undoTwice() throws {
        let expense = R.expense(5_000)
        let refund = R.refund(2_000, of: expense)
        let repository = try R.repository([expense, refund])
        let changes = TransactionUseCases(repository: repository, categoryNames: TestCategoryNames()).changes
        let first = try changes.remove(ids: [expense.id])
        let firstOutcome = try changes.outcome(of: first)
        let second = try changes.remove(ids: [refund.id])
        _ = try changes.revertNow(second)
        #expect(try repository.stored(refund.id)?.refundOfID == nil)
        guard case .reverted = try changes.revert(first, expecting: firstOutcome) else {
            Issue.record("Expected the first delete to revert")
            return
        }
        #expect(try repository.stored(refund.id)?.refundOfID == expense.id)
    }

    @Test("v1 Edge 8: when the Undo step is gone, the orphan stays unlinked; nothing re-links it by itself")
    func noAutomaticRelink() throws {
        let expense = R.expense(5_000)
        let refund = R.refund(2_000, of: expense)
        let repository = try R.repository([expense, refund])
        let useCases = TransactionUseCases(repository: repository, categoryNames: TestCategoryNames())
        _ = try useCases.changes.remove(ids: [expense.id])
        _ = try useCases.saveTransactions.save([R.expense(100, in: R.diningID)])
        // Saving an expense with the same id again (say, from a file) doesn't claim the orphan either.
        try repository.saveTransaction(expense)
        #expect(try repository.stored(refund.id)?.refundOfID == nil)
    }

    @Test("Undo is stale and writes nothing when the orphan was changed since; the step is never half applied")
    func staleWhenOrphanChanged() throws {
        let expense = R.expense(5_000)
        let refund = R.refund(2_000, of: expense)
        let repository = try R.repository([expense, refund])
        let changes = TransactionUseCases(repository: repository, categoryNames: TestCategoryNames()).changes
        let removed = try changes.remove(ids: [expense.id])
        let outcome = try changes.outcome(of: removed)
        var orphan = try #require(try repository.stored(refund.id))
        orphan.categoryID = R.shoppingID
        try repository.saveTransaction(orphan)
        let before = repository.snapshot
        #expect(try changes.revert(removed, expecting: outcome) == .stale(.changed([refund.id])))
        #expect(repository.snapshot == before)
    }

    @Test("A bulk delete of an expense and its refund, in either order, comes back linked on Undo")
    func bulkDeleteWithRefund() throws {
        for refundFirst in [false, true] {
            let expense = R.expense(5_000)
            let refund = R.refund(2_000, of: expense)
            let repository = try R.repository([expense, refund])
            let changes = TransactionUseCases(repository: repository, categoryNames: TestCategoryNames()).changes
            let ids = refundFirst ? [refund.id, expense.id] : [expense.id, refund.id]
            let removed = try changes.remove(ids: ids)
            #expect(try repository.transactions().isEmpty)
            _ = try changes.revertNow(removed)
            #expect(try repository.stored(refund.id)?.refundOfID == expense.id)
        }
    }

    @Test("v1 Edge 1, v1 Edge 9: deleting many expenses at once and Undo re-links every refund to its own")
    func bulkDeleteManyExpenses() throws {
        let expenses = (0..<1_000).map { _ in R.expense(50) }
        let refunds = expenses.map { R.refund(20, of: $0) } + [R.refund(10, of: expenses[0])]
        let repository = try R.repository(expenses + refunds)
        let changes = TransactionUseCases(repository: repository, categoryNames: TestCategoryNames()).changes
        let removed = try changes.remove(ids: expenses.map(\.id))
        #expect(try repository.transactions().allSatisfy { $0.refundOfID == nil })
        _ = try changes.revertNow(removed)
        for refund in refunds {
            #expect(try repository.stored(refund.id)?.refundOfID == refund.refundOfID)
        }
    }

    @Test("Undo of an account delete re-links refunds in other accounts to its expenses")
    func accountDeleteUndo() throws {
        let expense = R.expense(5_000, account: R.cardID)
        let refund = R.refund(2_000, of: expense, account: F.savingsID)
        let repository = try R.repository([expense, refund])
        let changes = TransactionUseCases(repository: repository, categoryNames: TestCategoryNames()).changes
        let removed = TransactionChange.removedAccount(
            try DefaultDeleteAccountUseCase(repository: repository).delete(R.cardID)
        )
        #expect(try repository.stored(refund.id)?.refundOfID == nil)
        _ = try changes.revertNow(removed)
        #expect(try repository.stored(refund.id)?.refundOfID == expense.id)
    }
}
