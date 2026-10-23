import Foundation
import LittleOrbitDomain
import Testing

/// `SplitTransactionUseCase` over the fake repository: saves and removals are one Undo step (#34, D64, D97.2).
@MainActor
@Suite("Split transaction use case")
struct SplitTransactionUseCaseTests {
    typealias F = TransactionFixture  // swiftlint:disable:this type_name

    private struct Setup {
        let repository: FakeLedgerRepository
        let useCases: TransactionUseCases
        let first: UUID
        let second: UUID
        let third: UUID
    }

    private func setup(_ transactions: [Transaction] = []) throws -> Setup {
        let repository = try FakeLedgerRepository(accounts: F.accounts, transactions: transactions)
        try repository.seedDefaultCategories()
        let ids = try repository.categories().filter { $0.kind == .expense && $0.parentID == nil }.map(\.id)
        return Setup(
            repository: repository,
            useCases: TransactionUseCases(repository: repository),
            first: ids[0],
            second: ids[1],
            third: ids[2],
        )
    }

    private func line(_ category: UUID, _ amount: Decimal, _ order: Double, id: UUID = UUID()) -> TransactionSplit {
        TransactionSplit(id: id, categoryID: category, amount: amount, sortOrder: order)
    }

    private func lines(_ id: UUID, in setup: Setup) throws -> [SplitLineValue] {
        SplitLineValue.of(try setup.repository.splits(for: id))
    }

    @Test("A new split saves with its lines as .added; Undo deletes it with them")
    func newSplit() throws {
        let setup = try setup()
        let expense = F.expense(90, on: F.date(2026, 10, 20))
        let change = try setup.useCases.splits.save(
            expense,
            lines: [line(setup.first, 40, 0), line(setup.second, 50, 1)],
        )
        #expect(change == .added([expense.id]))
        #expect(try lines(expense.id, in: setup).count == 2)
        _ = try setup.useCases.changes.revertNow(change)
        #expect(try setup.repository.transactions().isEmpty)
        #expect(try setup.repository.splits(for: expense.id).isEmpty)
    }

    @Test("A split saved with a payee the form just created is one step; Undo removes the payee too (D191.4)")
    func newPayee() throws {
        let setup = try setup()
        let payee = Payee(name: "Green Basket", createdAt: F.date(2026, 10, 20))
        try setup.repository.savePayee(payee)
        var expense = F.expense(90, on: F.date(2026, 10, 20))
        expense.payeeID = payee.id
        let change = try setup.useCases.splits.save(
            expense,
            lines: [line(setup.first, 40, 0), line(setup.second, 50, 1)],
            creating: [payee],
        )
        #expect(change == .saved(.added([expense.id]), creating: [try #require(try setup.repository.payees().first)]))
        _ = try setup.useCases.changes.revertNow(change)
        #expect(try setup.repository.transactions().isEmpty)
        #expect(try setup.repository.payees().allSatisfy { $0.deletedAt != nil })
    }

    @Test("lines(of:) gives the live lines in order, and none for a transaction that isn't split")
    func readLines() throws {
        let expense = F.expense(90, on: F.date(2026, 10, 20))
        let plain = F.expense(10, on: F.date(2026, 10, 20))
        let setup = try setup([expense, plain])
        let saved = [line(setup.second, 50, 1), line(setup.first, 40, 0)]
        _ = try setup.useCases.splits.save(expense, lines: saved)
        #expect(try setup.useCases.splits.lines(of: expense.id).map(\.id) == [saved[1].id, saved[0].id])
        #expect(try setup.useCases.splits.lines(of: plain.id).isEmpty)
    }

    @Test("Editing the lines and the total is one step; Undo restores both, line IDs and creation dates included")
    func editLines() throws {
        let expense = F.expense(90, on: F.date(2026, 10, 20))
        let setup = try setup([expense])
        let original = [line(setup.first, 40, 0), line(setup.second, 50, 1)]
        _ = try setup.useCases.splits.save(expense, lines: original)
        let storedLines = try setup.repository.splits(for: expense.id)
        var edited = try #require(try setup.repository.transactions().first)
        edited.amount = 120
        let change = try setup.useCases.splits.save(
            edited,
            lines: [line(setup.first, 40, 0, id: original[0].id), line(setup.third, 80, 1)],
        )
        guard case .restoringLines(let before, .replaced) = change else {
            Issue.record("Expected .restoringLines around .replaced, got \(change)")
            return
        }
        #expect(SplitLineValue.of(before[expense.id] ?? []) == SplitLineValue.of(storedLines))
        let kept = try #require(try setup.repository.splits(for: expense.id).first { $0.id == original[0].id })
        #expect(kept.createdAt == storedLines.first { $0.id == original[0].id }?.createdAt)
        _ = try setup.useCases.changes.revertNow(change)
        #expect(try lines(expense.id, in: setup) == SplitLineValue.of(storedLines))
        #expect(try setup.repository.transactions().first?.amount == 90)
    }

    @Test("An edit that leaves the lines as they were is a plain .replaced")
    func unchangedLines() throws {
        let expense = F.expense(90, on: F.date(2026, 10, 20))
        let setup = try setup([expense])
        let original = [line(setup.first, 40, 0), line(setup.second, 50, 1)]
        _ = try setup.useCases.splits.save(expense, lines: original)
        var edited = try #require(try setup.repository.transactions().first)
        edited.note = "Weekly shop"
        let change = try setup.useCases.splits.save(edited, lines: original)
        guard case .replaced = change else {
            Issue.record("Expected .replaced, got \(change)")
            return
        }
    }

    @Test("Turning a normal transaction into a split and back to one category both undo exactly")
    func makeAndUnmakeSplit() throws {
        var expense = F.expense(90, on: F.date(2026, 10, 20))
        let setup = try setup()
        expense.categoryID = setup.first
        _ = try setup.useCases.splits.save(expense, lines: [])
        var split = expense
        split.categoryID = nil
        let made = try setup.useCases.splits.save(
            split,
            lines: [line(setup.first, 40, 0), line(setup.second, 50, 1)],
        )
        _ = try setup.useCases.changes.revertNow(made)
        #expect(try setup.repository.splits(for: expense.id).isEmpty)
        #expect(try setup.repository.transactions().first?.categoryID == setup.first)
    }

    @Test("Lines that break a D64 rule write nothing and name the rule")
    func invalidLinesWriteNothing() throws {
        let expense = F.expense(90, on: F.date(2026, 10, 20))
        let setup = try setup([expense])
        #expect(throws: LedgerValidationError.splitRuleBroken(.linesDoNotMatchTotal)) {
            try setup.useCases.splits.save(expense, lines: [line(setup.first, 40, 0), line(setup.second, 55, 1)])
        }
        #expect(try setup.repository.splits(for: expense.id).isEmpty)
        #expect(try setup.repository.transactions().first == expense)
    }

    @Test("Removing a split is a save with no lines and the kept category; Undo restores the lines")
    func removeSplit() throws {
        let expense = F.expense(1_000, on: F.date(2026, 10, 20))
        let setup = try setup([expense])
        let original = [line(setup.first, 400, 0), line(setup.second, 600, 1)]
        _ = try setup.useCases.splits.save(expense, lines: original)
        var kept = expense
        kept.categoryID = SplitRemoval.keptCategory(
            of: original,
            type: .expense,
            in: try setup.repository.categories(),
        )
        let change = try setup.useCases.splits.save(kept, lines: [])
        #expect(try setup.repository.transactions().first?.categoryID == setup.second)
        #expect(try setup.repository.splits(for: expense.id).isEmpty)
        _ = try setup.useCases.changes.revertNow(change)
        #expect(try lines(expense.id, in: setup) == SplitLineValue.of(original))
        #expect(try setup.repository.transactions().first?.categoryID == nil)
    }

    @Test("On Schema V1 a split expense can't take a refund, (D35.6)")
    func splitExpenseRefund() throws {
        let expense = F.expense(1_000, on: F.date(2026, 10, 20))
        let setup = try setup([expense])
        _ = try setup.useCases.splits.save(expense, lines: [line(setup.first, 400, 0), line(setup.second, 600, 1)])
        let refund = Transaction(
            type: .income,
            amount: 100,
            date: F.date(2026, 10, 21),
            timeZoneID: F.india,
            accountID: F.savingsID,
            refundOfID: expense.id,
            isRefund: true,
        )
        #expect(throws: LedgerValidationError.refundOriginalIsSplit) {
            try setup.repository.saveTransaction(refund)
        }
    }
}
