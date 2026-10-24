import Foundation
import LittleOrbitDomain
import Testing

/// Undo and Redo of changes to split lines restore the lines exactly, IDs included (#34, Tech Architect's
/// ruling on #124). The edits are made through the repository and recorded as `.restoringLines`.
@MainActor
@Suite("Split-aware Undo")
struct SplitUndoTests {
    typealias F = TransactionFixture  // swiftlint:disable:this type_name

    private struct Ledger {
        let repository: FakeLedgerRepository
        let changes: any TransactionChangesUseCase
        let categories: [UUID]
    }

    private func ledger(_ transactions: [Transaction] = []) throws -> Ledger {
        let repository = try FakeLedgerRepository(accounts: F.accounts, transactions: transactions)
        try repository.seedDefaultCategories()
        let categories = try repository.categories().filter { $0.kind == .expense && $0.parentID == nil }.map(\.id)
        return Ledger(
            repository: repository,
            changes: TransactionUseCases(repository: repository).changes,
            categories: categories,
        )
    }

    private func line(_ category: UUID, _ amount: Decimal, _ order: Double, id: UUID = UUID()) -> TransactionSplit {
        TransactionSplit(id: id, categoryID: category, amount: amount, note: "line \(Int(order))", sortOrder: order)
    }

    /// Saves `transaction` with `lines` the way a split edit does, and returns the change for Undo.
    private func edit(_ transaction: Transaction, lines: [TransactionSplit], in ledger: Ledger) throws
        -> TransactionChange
    {
        let repository = ledger.repository
        return try repository.atomically {
            let stored = try #require(try repository.transactions().first { $0.id == transaction.id })
            let before = try repository.splits(for: transaction.id)
            try repository.replaceSplits([], for: transaction.id)
            try repository.saveTransaction(transaction)
            if !lines.isEmpty {
                try repository.replaceSplits(lines, for: transaction.id)
            }
            return .restoringLines([transaction.id: before], .replaced([stored]))
        }
    }

    private func values(_ id: UUID, in ledger: Ledger) throws -> [SplitLineValue] {
        SplitLineValue.of(try ledger.repository.splits(for: id))
    }

    @Test("Editing a split's lines, then Undo, restores the old lines with their IDs; Redo reapplies the edit")
    func editLines() throws {
        let expense = F.expense(90, on: F.date(2026, 10, 20))
        let ledger = try ledger([expense])
        let (first, second, third) = (ledger.categories[0], ledger.categories[1], ledger.categories[2])
        let original = [line(first, 40, 0), line(second, 50, 1)]
        try ledger.repository.replaceSplits(original, for: expense.id)
        let before = try values(expense.id, in: ledger)
        var edited = try #require(try ledger.repository.transactions().first)
        edited.amount = 100
        let change = try edit(
            edited,
            lines: [line(first, 30, 0, id: original[0].id), line(third, 70, 1)],
            in: ledger,
        )
        let after = try values(expense.id, in: ledger)
        #expect(after.map(\.amount) == [30, 70])

        let inverse = try ledger.changes.revertNow(change)
        #expect(try values(expense.id, in: ledger) == before)
        #expect(try ledger.repository.transactions().first?.amount == 90)

        _ = try ledger.changes.revertNow(inverse)
        #expect(try values(expense.id, in: ledger) == after)
        #expect(try ledger.repository.transactions().first?.amount == 100)
    }

    @Test("Turning a normal transaction into a split, then Undo, gives back its category and no lines")
    func makeSplit() throws {
        let ledger = try ledger()
        let (first, second) = (ledger.categories[0], ledger.categories[1])
        var expense = F.expense(90, on: F.date(2026, 10, 20))
        expense.categoryID = first
        try ledger.repository.saveTransaction(expense)
        var split = try #require(try ledger.repository.transactions().first)
        split.categoryID = nil
        let lines = [line(first, 40, 0), line(second, 50, 1)]
        let change = try edit(split, lines: lines, in: ledger)
        #expect(try ledger.repository.splits(for: expense.id).count == 2)

        let inverse = try ledger.changes.revertNow(change)
        #expect(try ledger.repository.splits(for: expense.id).isEmpty)
        #expect(try ledger.repository.transactions().first?.categoryID == first)

        _ = try ledger.changes.revertNow(inverse)
        #expect(try values(expense.id, in: ledger) == SplitLineValue.of(lines))
        #expect(try ledger.repository.transactions().first?.categoryID == nil)
    }

    @Test("A split edit whose lines another window changed since is stale and writes nothing")
    func staleLines() throws {
        let expense = F.expense(90, on: F.date(2026, 10, 20))
        let ledger = try ledger([expense])
        let (first, second) = (ledger.categories[0], ledger.categories[1])
        try ledger.repository.replaceSplits([line(first, 40, 0), line(second, 50, 1)], for: expense.id)
        let edited = try #require(try ledger.repository.transactions().first)
        let change = try edit(edited, lines: [line(first, 45, 0), line(second, 45, 1)], in: ledger)
        let outcome = try ledger.changes.outcome(of: change)
        let elsewhere = [line(first, 10, 0), line(second, 80, 1)]
        try ledger.repository.replaceSplits(elsewhere, for: expense.id)
        #expect(try ledger.changes.check(change, expecting: outcome) == .stale(.changed([expense.id])))
        #expect(try ledger.changes.revert(change, expecting: outcome) == .stale(.changed([expense.id])))
        #expect(try values(expense.id, in: ledger) == SplitLineValue.of(elsewhere))
    }

    @Test("NB3: Undo of a new split whose lines another window changed since is stale and deletes nothing")
    func staleAddedSplit() throws {
        let ledger = try ledger()
        let (first, second) = (ledger.categories[0], ledger.categories[1])
        let expense = F.expense(90, on: F.date(2026, 10, 20))
        try ledger.repository.saveTransaction(expense)
        try ledger.repository.replaceSplits([line(first, 40, 0), line(second, 50, 1)], for: expense.id)
        let change = TransactionChange.added([expense.id])
        let outcome = try ledger.changes.outcome(of: change)
        #expect(try ledger.changes.check(change, expecting: outcome) == .current)
        try ledger.repository.replaceSplits([line(first, 10, 0), line(second, 80, 1)], for: expense.id)
        #expect(try ledger.changes.revert(change, expecting: outcome) == .stale(.changed([expense.id])))
        #expect(try ledger.repository.transactions().contains { $0.id == expense.id })
    }

    @Test("B1: Redo of a bulk delete's Undo reads every line once to keep and to check, not once a row")
    func bulkRedoReadsLinesOnce() throws {
        let ledger = try ledger()
        let (first, second) = (ledger.categories[0], ledger.categories[1])
        let splitA = F.expense(90, on: F.date(2026, 10, 20))
        let splitB = F.expense(60, on: F.date(2026, 10, 21))
        let plain = F.expense(30, on: F.date(2026, 10, 22))
        for transaction in [splitA, splitB, plain] {
            try ledger.repository.saveTransaction(transaction)
        }
        try ledger.repository.replaceSplits([line(first, 40, 0), line(second, 50, 1)], for: splitA.id)
        try ledger.repository.replaceSplits([line(first, 20, 0), line(second, 40, 1)], for: splitB.id)
        let linesA = try values(splitA.id, in: ledger)
        let linesB = try values(splitB.id, in: ledger)
        let ids = [splitA.id, splitB.id, plain.id]
        let delete = try ledger.changes.remove(ids: ids)
        let deleteOutcome = try ledger.changes.outcome(of: delete)

        guard case .reverted(let redo, let redoOutcome) = try ledger.changes.revert(delete, expecting: deleteOutcome)
        else {
            Issue.record("Undo of the delete was stale")
            return
        }
        #expect(redoOutcome.splitLines == [splitA.id: linesA, splitB.id: linesB])

        ledger.repository.splitReads = []
        #expect(try ledger.changes.outcome(of: redo) == redoOutcome)
        #expect(ledger.repository.splitReads == [nil])
        ledger.repository.splitReads = []
        #expect(try ledger.changes.check(redo, expecting: redoOutcome) == .current)
        #expect(ledger.repository.splitReads == [nil])

        guard case .reverted = try ledger.changes.revert(redo, expecting: redoOutcome) else {
            Issue.record("Redo of the delete was stale")
            return
        }
        #expect(try ledger.repository.transactions().allSatisfy { !ids.contains($0.id) })
    }

    @Test("B1: Redo of a bulk delete's Undo is stale for just the split whose lines another window changed")
    func bulkRedoStaleLines() throws {
        let ledger = try ledger()
        let (first, second) = (ledger.categories[0], ledger.categories[1])
        let splitA = F.expense(90, on: F.date(2026, 10, 20))
        let splitB = F.expense(60, on: F.date(2026, 10, 21))
        for transaction in [splitA, splitB] {
            try ledger.repository.saveTransaction(transaction)
        }
        try ledger.repository.replaceSplits([line(first, 40, 0), line(second, 50, 1)], for: splitA.id)
        try ledger.repository.replaceSplits([line(first, 20, 0), line(second, 40, 1)], for: splitB.id)
        let delete = try ledger.changes.remove(ids: [splitA.id, splitB.id])
        let deleteOutcome = try ledger.changes.outcome(of: delete)
        guard case .reverted(let redo, let redoOutcome) = try ledger.changes.revert(delete, expecting: deleteOutcome)
        else {
            Issue.record("Undo of the delete was stale")
            return
        }
        try ledger.repository.replaceSplits([line(first, 10, 0), line(second, 50, 1)], for: splitB.id)

        ledger.repository.splitReads = []
        #expect(try ledger.changes.revert(redo, expecting: redoOutcome) == .stale(.changed([splitB.id])))
        #expect(ledger.repository.splitReads == [nil])
        #expect(try ledger.repository.transactions().count == 2)
    }

    @Test("The change still names the transaction edit, and lists the lines it replaced")
    func changeShape() {
        let id = UUID()
        let lines = [TransactionSplit(transactionID: id, amount: 1)]
        let version = Transaction(id: id)
        let change = TransactionChange.restoringLines([id: lines], .replaced([version]))
        #expect(change.core == .replaced([version]))
        #expect(change.transactionIDs == [id])
        #expect(change.replacedLines == [id: lines])
        #expect(TransactionChange.saved(change, creating: []).replacedLines == [id: lines])
    }
}
