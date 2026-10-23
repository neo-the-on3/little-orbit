import Foundation
import LittleOrbitDomain
import Testing

/// Undo of a delete that took a linked refund, when another window changed the refund's expense since
/// (D224; Tech Architect's B1 on #125). Two use-case instances on one repository stand in for two windows,
/// each with its own Undo history. A gone expense brings the refund back unlinked. An expense that can't take
/// it back makes the whole step stale ('Can't Undo', D187.5), which writes nothing and never throws.
@MainActor
@Suite("Refund restore after another window's change (#55, B1, D224)")
struct RefundRestoreTests {
    typealias F = TransactionFixture  // swiftlint:disable:this type_name
    typealias R = RefundFixture  // swiftlint:disable:this type_name

    /// How window A deletes the refund: on its own, or with the account it's in.
    enum Delete: CaseIterable {
        case refund
        case account
    }

    /// Expense E (₹5,000, Groceries, Everyday Savings) with refund R (₹2,000, on Rewards Card), which
    /// window A deletes. `others` are further refunds of E that stay.
    private struct Setup {
        let repository: FakeLedgerRepository
        let windowA: DefaultTransactionChangesUseCase
        let windowB: DefaultTransactionChangesUseCase
        let expense: Transaction
        let refund: Transaction
        /// R as stored before window A's delete.
        let stored: Transaction
        let step: TransactionChange
        let outcome: ChangeOutcome
    }

    private func setUp(_ delete: Delete, others: [Decimal] = []) throws -> Setup {
        let expense = R.expense(5_000)
        let refund = R.refund(2_000, of: expense, account: R.cardID)
        let repository = try R.repository([expense, refund] + others.map { R.refund($0, of: expense) })
        let stored = try #require(try repository.stored(refund.id))
        let windowA = DefaultTransactionChangesUseCase(repository: repository)
        let step: TransactionChange =
            switch delete {
            case .refund: try windowA.remove(ids: [refund.id])
            case .account: .removedAccount(try DefaultDeleteAccountUseCase(repository: repository).delete(R.cardID))
            }
        return Setup(
            repository: repository,
            windowA: windowA,
            windowB: DefaultTransactionChangesUseCase(repository: repository),
            expense: expense,
            refund: refund,
            stored: stored,
            step: step,
            outcome: try windowA.outcome(of: step),
        )
    }

    private func expectStale(_ setup: Setup, comment: Comment) throws {
        let before = setup.repository.snapshot
        let result = try setup.windowA.revert(setup.step, expecting: setup.outcome)
        #expect(result == .stale(.changed([setup.expense.id])), comment)
        #expect(setup.repository.snapshot == before, comment)
    }

    @Test(
        "Still fits: an unrelated edit to the expense in window B, and Undo links the refund again",
        arguments: Delete.allCases,
    )
    func restoresWhenItFits(_ delete: Delete) throws {
        let setup = try setUp(delete)
        var expense = try #require(try setup.repository.stored(setup.expense.id))
        expense.note = "weekly shop"
        try setup.repository.saveTransaction(expense)
        guard case .reverted = try setup.windowA.revert(setup.step, expecting: setup.outcome) else {
            Issue.record("Expected Undo to revert")
            return
        }
        #expect(try setup.repository.stored(setup.refund.id)?.refundOfID == setup.expense.id)
    }

    @Test(
        "D224.1: window B deleted the expense; the refund comes back as 'Refund (original deleted)'",
        arguments: Delete.allCases,
    )
    func expenseDeletedRestoresUnlinked(_ delete: Delete) throws {
        let setup = try setUp(delete)
        _ = try setup.windowB.remove(ids: [setup.expense.id])
        guard case .reverted = try setup.windowA.revert(setup.step, expecting: setup.outcome) else {
            Issue.record("Expected Undo to revert with the refund unlinked")
            return
        }
        let restored = try #require(try setup.repository.stored(setup.refund.id))
        #expect(RefundStatus(of: restored) == .originalDeleted)
        #expect(restored.updatedAt != setup.stored.updatedAt)
        #expect(restored == unlinked(setup.stored, at: restored.updatedAt))

        // The same as when the expense is deleted with the refund still there (D19).
        let expense = R.expense(5_000)
        let refund = R.refund(2_000, of: expense, account: R.cardID)
        let control = try R.repository([expense, refund])
        let before = try #require(try control.stored(refund.id))
        _ = try DefaultTransactionChangesUseCase(repository: control).remove(ids: [expense.id])
        let orphan = try #require(try control.stored(refund.id))
        #expect(orphan.updatedAt != before.updatedAt)
        #expect(orphan == unlinked(before, at: orphan.updatedAt))
    }

    private func unlinked(_ refund: Transaction, at updatedAt: Date) -> Transaction {
        var refund = refund
        refund.refundOfID = nil
        refund.updatedAt = updatedAt
        return refund
    }

    /// Who changes the expense after window A's delete: window B through its own save (#128 S23 v1.11), or a
    /// write outside any window (D224.6). Window B has no split use case on main yet, so its split saves the
    /// expense uncategorised through its use case, then writes the lines to the store.
    enum Editor: CaseIterable {
        case windowB
        case outsideWindows
    }

    private func edit(_ setup: Setup, by editor: Editor, _ change: (inout Transaction) -> Void) throws {
        var expense = try #require(try setup.repository.stored(setup.expense.id))
        change(&expense)
        switch editor {
        case .windowB: _ = try DefaultSaveTransactionsUseCase(repository: setup.repository).save([expense])
        case .outsideWindows: try setup.repository.saveTransaction(expense)
        }
    }

    @Test(
        "S23(c) stale: the expense lowered to what its other refunds use",
        arguments: Delete.allCases,
        Editor.allCases,
    )
    func expenseLoweredIsStale(_ delete: Delete, _ editor: Editor) throws {
        let setup = try setUp(delete, others: [3_000])
        try edit(setup, by: editor) { $0.amount = 3_000 }
        try expectStale(setup, comment: "cap")
    }

    @Test(
        "S23(b) stale: the expense moved to an account in another currency",
        arguments: Delete.allCases,
        Editor.allCases,
    )
    func expenseCurrencyIsStale(_ delete: Delete, _ editor: Editor) throws {
        let setup = try setUp(delete)
        try edit(setup, by: editor) {
            $0.accountID = F.usdID
            $0.amount = 60
        }
        try expectStale(setup, comment: "currency")
    }

    @Test("S23(e) stale: the expense split, on V1", arguments: Delete.allCases, Editor.allCases)
    func expenseSplitIsStale(_ delete: Delete, _ editor: Editor) throws {
        let setup = try setUp(delete)
        try edit(setup, by: editor) { $0.categoryID = nil }
        try setup.repository.replaceSplits(
            [
                TransactionSplit(categoryID: R.groceriesID, amount: 3_000),
                TransactionSplit(categoryID: R.diningID, amount: 2_000, sortOrder: 1),
            ],
            for: setup.expense.id,
        )
        try expectStale(setup, comment: "split")
    }

    @Test(
        "D224.2, D33.4: the expense moved to Dining; the refund comes back linked, in Dining",
        arguments: Delete.allCases,
        Editor.allCases,
    )
    func refundTakesCurrentCategory(_ delete: Delete, _ editor: Editor) throws {
        let setup = try setUp(delete)
        try edit(setup, by: editor) { $0.categoryID = R.diningID }
        guard case .reverted = try setup.windowA.revert(setup.step, expecting: setup.outcome) else {
            Issue.record("Expected Undo to revert")
            return
        }
        let restored = try #require(try setup.repository.stored(setup.refund.id))
        #expect(restored.refundOfID == setup.expense.id)
        #expect(restored.categoryID == R.diningID)
    }

    @Test("S23(d) stale: the expense dated after the refund", arguments: Delete.allCases, Editor.allCases)
    func expenseAfterRefundIsStale(_ delete: Delete, _ editor: Editor) throws {
        let setup = try setUp(delete)
        try edit(setup, by: editor) { $0.date = F.date(2026, 10, 11) }
        try expectStale(setup, comment: "date")
    }

    @Test("S23(d), D229: window B moves the expense to 10 Oct in Kolkata, after a refund on 9 Oct in London")
    func crossZoneDateIsStale() throws {
        // E on 9 Oct 12:00 Asia/Kolkata; R on 9 Oct 21:00 Europe/London, linked (same day, D112).
        let london = "Europe/London"
        let expense = R.expense(5_000, on: F.date(2026, 10, 9))
        let refund = R.refund(2_000, of: expense, on: F.date(2026, 10, 9, 21, zone: london), zone: london)
        let repository = try R.repository([expense, refund])
        let windowA = DefaultTransactionChangesUseCase(repository: repository)
        let step = try windowA.remove(ids: [refund.id])
        let outcome = try windowA.outcome(of: step)

        // Window B: 10 Oct 01:00 Kolkata, 30 minutes before the refund's moment but a day after its own day.
        var moved = try #require(try repository.stored(expense.id))
        moved.date = F.date(2026, 10, 10, 1)
        _ = try DefaultSaveTransactionsUseCase(repository: repository).save([moved])
        #expect(refund.date > moved.date)

        let before = repository.snapshot
        #expect(try windowA.revert(step, expecting: outcome) == .stale(.changed([expense.id])))
        #expect(repository.snapshot == before)
    }

    @Test("S23(a) stale: the expense turned into an income", arguments: Delete.allCases, Editor.allCases)
    func expenseNoLongerExpenseIsStale(_ delete: Delete, _ editor: Editor) throws {
        let setup = try setUp(delete)
        try edit(setup, by: editor) {
            $0.type = .income
            $0.categoryID = R.salaryID
        }
        try expectStale(setup, comment: "type")
    }

    // MARK: - S22 (D224.1) around the unlinked restore

    @Test("S22: the expense deleted outside any window; the refund comes back unlinked", arguments: Delete.allCases)
    func expenseDeletedOutsideWindows(_ delete: Delete) throws {
        let setup = try setUp(delete)
        try setup.repository.deleteTransaction(id: setup.expense.id)
        guard case .reverted = try setup.windowA.revert(setup.step, expecting: setup.outcome) else {
            Issue.record("Expected Undo to revert with the refund unlinked")
            return
        }
        let restored = try #require(try setup.repository.stored(setup.refund.id))
        #expect(RefundStatus(of: restored) == .originalDeleted)
        #expect(restored == unlinked(setup.stored, at: restored.updatedAt))
    }

    @Test("S22: window A's Redo deletes the unlinked refund again", arguments: Delete.allCases)
    func redoDeletesAgain(_ delete: Delete) throws {
        let setup = try setUp(delete)
        _ = try setup.windowB.remove(ids: [setup.expense.id])
        guard
            case .reverted(let redo, let redoOutcome) = try setup.windowA.revert(setup.step, expecting: setup.outcome)
        else {
            Issue.record("Expected Undo to revert")
            return
        }
        guard case .reverted = try setup.windowA.revert(redo, expecting: redoOutcome) else {
            Issue.record("Expected Redo to delete the refund again")
            return
        }
        #expect(try setup.repository.stored(setup.refund.id) == nil)
        #expect(try setup.repository.stored(setup.expense.id) == nil)
    }

    @Test(
        "S22, v1 Edge 8: window B's later Undo of the expense delete doesn't link the refund again",
        arguments: Delete.allCases,
    )
    func laterExpenseUndoLeavesUnlinked(_ delete: Delete) throws {
        let setup = try setUp(delete)
        let expenseDelete = try setup.windowB.remove(ids: [setup.expense.id])
        let expenseOutcome = try setup.windowB.outcome(of: expenseDelete)
        guard case .reverted = try setup.windowA.revert(setup.step, expecting: setup.outcome) else {
            Issue.record("Expected window A's Undo to revert")
            return
        }
        guard case .reverted = try setup.windowB.revert(expenseDelete, expecting: expenseOutcome) else {
            Issue.record("Expected window B's Undo to bring the expense back")
            return
        }
        #expect(try setup.repository.stored(setup.expense.id) != nil)
        let refund = try #require(try setup.repository.stored(setup.refund.id))
        #expect(RefundStatus(of: refund) == .originalDeleted)
    }

    // MARK: - Bulk steps (D224.4)

    /// Window A deletes three refunds in one step, of E1, E2 and E3; window B then deletes E1, and lowers
    /// E3 below what its other refund uses if `lowerThird`.
    private struct BulkUndo {
        let repository: FakeLedgerRepository
        let result: RevertResult
        let expenses: [Transaction]
    }

    private func bulkUndo(lowerThird: Bool) throws -> BulkUndo {
        let expenses = [R.expense(5_000), R.expense(5_000), R.expense(5_000)]
        let refunds = expenses.map { R.refund(2_000, of: $0) }
        let repository = try R.repository(expenses + refunds + [R.refund(3_000, of: expenses[2])])
        let windowA = DefaultTransactionChangesUseCase(repository: repository)
        let step = try windowA.remove(ids: refunds.map(\.id))
        let outcome = try windowA.outcome(of: step)
        _ = try DefaultTransactionChangesUseCase(repository: repository).remove(ids: [expenses[0].id])
        if lowerThird {
            var third = try #require(try repository.stored(expenses[2].id))
            third.amount = 3_000
            try repository.saveTransaction(third)
        }
        let before = repository.snapshot
        let result = try windowA.revert(step, expecting: outcome)
        if case .stale = result {
            #expect(repository.snapshot == before)
        }
        return BulkUndo(repository: repository, result: result, expenses: expenses)
    }

    @Test("D224.4: a bulk Undo brings one refund back unlinked and links the one whose expense still fits")
    func mixedBulkRestores() throws {
        let undo = try bulkUndo(lowerThird: false)
        guard case .reverted = undo.result else {
            Issue.record("Expected Undo to revert")
            return
        }
        let expenses = undo.expenses
        let restored = try undo.repository.transactions().filter { $0.isRefund && $0.amount == 2_000 }
        #expect(Set(restored.map(\.refundOfID)) == [nil, expenses[1].id, expenses[2].id])
    }

    @Test("D224.4: one refund that no longer fits makes the whole bulk Undo stale, the orphan's too")
    func mixedBulkIsStale() throws {
        let undo = try bulkUndo(lowerThird: true)
        #expect(undo.result == .stale(.changed([undo.expenses[2].id])))
        #expect(try undo.repository.transactions().filter { $0.isRefund && $0.amount == 2_000 }.isEmpty)
    }
}
