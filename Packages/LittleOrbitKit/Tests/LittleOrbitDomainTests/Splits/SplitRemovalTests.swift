import Foundation
import LittleOrbitDomain
import Testing

/// Removing a split keeps the largest line's category, and its refunds follow (#34, D97.2, D112).
@Suite("Split removal")
struct SplitRemovalTests {
    private let account = Account(name: "Everyday Savings", type: .savings, currencyCode: "INR")
    private let groceries = TransactionCategory(name: "Groceries", kind: .expense)
    private let household = TransactionCategory(name: "Household", kind: .expense)
    private let now = Date(timeIntervalSinceReferenceDate: 815_000_000)

    private func splitExpense(_ first: Decimal, _ second: Decimal) throws -> (LedgerSnapshot, Transaction) {
        var snapshot = LedgerSnapshot(accounts: [account], categories: [groceries, household])
        let expense = Transaction(type: .expense, amount: first + second, accountID: account.id)
        snapshot = try LedgerBook.savingTransaction(expense, in: snapshot, now: now)
        snapshot = try LedgerBook.replacingSplits(
            [
                TransactionSplit(categoryID: groceries.id, amount: first, sortOrder: 0),
                TransactionSplit(categoryID: household.id, amount: second, sortOrder: 1),
            ],
            for: expense.id,
            in: snapshot,
            now: now,
        )
        return (snapshot, expense)
    }

    private func refund(_ amount: Decimal, of expense: Transaction, category: UUID) -> Transaction {
        Transaction(
            type: .income,
            amount: amount,
            accountID: account.id,
            categoryID: category,
            refundOfID: expense.id,
            isRefund: true,
        )
    }

    @Test("The largest line is kept, and the first on a tie (D97.2, S47)")
    func keptLine() {
        let first = TransactionSplit(categoryID: groceries.id, amount: 500, sortOrder: 0)
        let second = TransactionSplit(categoryID: household.id, amount: 500, sortOrder: 1)
        let third = TransactionSplit(categoryID: UUID(), amount: 600, sortOrder: 2)
        #expect(SplitRemoval.keptLine(of: [second, first]) == first)
        #expect(SplitRemoval.keptLine(of: [first, second, third]) == third)
        #expect(SplitRemoval.keptLine(of: []) == nil)
    }

    @Test("Saving with no lines and the kept category keeps Groceries; both refunds stay linked in Groceries (S12)")
    func refundsFollowTheKeptCategory() throws {
        var (snapshot, expense) = try splitExpense(600, 400)
        let onGroceries = refund(100, of: expense, category: groceries.id)
        let onHousehold = refund(100, of: expense, category: household.id)
        // Schema V1 can't link a refund to a split expense (D35.6), so these are written straight into the
        // snapshot, the way stored data could hold them.
        snapshot.transactions += [onGroceries, onHousehold]
        var kept = expense
        kept.categoryID = SplitRemoval.keptCategory(
            of: snapshot.splitsVisible(for: expense.id),
            type: expense.type,
            in: snapshot.categories,
        )
        var removed = try LedgerBook.replacingSplits([], for: expense.id, in: snapshot, now: now)
        removed = try LedgerBook.savingTransaction(kept, in: removed, now: now)
        #expect(removed.splitsVisible(for: expense.id).isEmpty)
        let stored = try #require(removed.transactions.first { $0.id == expense.id })
        #expect(stored.categoryID == groceries.id)
        #expect(stored.amount == 1_000)
        let refunds = removed.transactions.filter { $0.refundOfID == expense.id }
        #expect(refunds.count == 2)
        #expect(refunds.allSatisfy { $0.categoryID == groceries.id && $0.isRefund })
    }

    @Test("A stored split that breaks D64 still has a kept category (one line, a ₹0 line, no category, repeats)")
    func keptCategoryOnInvalidSplit() {
        let expenseID = UUID()
        let invalidSets: [[TransactionSplit]] = [
            [TransactionSplit(transactionID: expenseID, categoryID: groceries.id, amount: 90)],
            [
                TransactionSplit(transactionID: expenseID, categoryID: groceries.id, amount: 90, sortOrder: 0),
                TransactionSplit(transactionID: expenseID, categoryID: household.id, amount: 0, sortOrder: 1),
            ],
            [
                TransactionSplit(transactionID: expenseID, amount: 60, sortOrder: 0),
                TransactionSplit(transactionID: expenseID, categoryID: household.id, amount: 10, sortOrder: 1),
            ],
            [
                TransactionSplit(transactionID: expenseID, categoryID: groceries.id, amount: 0, sortOrder: 0),
                TransactionSplit(transactionID: expenseID, categoryID: groceries.id, amount: 0, sortOrder: 1),
            ],
        ]
        let expected: [UUID?] = [groceries.id, groceries.id, nil, groceries.id]
        for (lines, category) in zip(invalidSets, expected) {
            #expect(SplitRemoval.keptCategory(of: lines, type: .expense, in: [groceries, household]) == category)
        }
    }

    @Test("A deleted category, or one of the other kind, leaves the transaction uncategorised")
    func keptCategoryNotLive() {
        var deleted = household
        deleted.deletedAt = now
        let salary = TransactionCategory(name: "Salary", kind: .income)
        let lines = [
            TransactionSplit(categoryID: groceries.id, amount: 400, sortOrder: 0),
            TransactionSplit(categoryID: household.id, amount: 600, sortOrder: 1),
        ]
        #expect(SplitRemoval.keptCategory(of: lines, type: .expense, in: [groceries, deleted]) == nil)
        #expect(SplitRemoval.keptCategory(of: lines, type: .expense, in: [groceries]) == nil)
        let income = [TransactionSplit(categoryID: salary.id, amount: 400, sortOrder: 0)]
        #expect(SplitRemoval.keptCategory(of: income, type: .expense, in: [salary]) == nil)
        #expect(SplitRemoval.keptCategory(of: income, type: .income, in: [salary]) == salary.id)
        #expect(SplitRemoval.keptCategory(of: [], type: .expense, in: [groceries]) == nil)
    }
}
