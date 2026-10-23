import Foundation
import LittleOrbitDomain
import LittleOrbitPersistence
import Testing

@testable import LittleOrbitFeatures

/// D198 on a refund delete whose expense another window then changes (D224, Tech Architect's B1 on #125):
/// the step keeps its name, whether Undo brings the refund back unlinked, linked, or can't.
@MainActor
@Suite("Undo name of a refund delete (#55, D198, D224)")
struct RefundUndoStepNameTests {
    private let savings = Account(name: "Everyday Savings", type: .savings, currencyCode: "INR")
    private let groceries = TransactionCategory(name: "Groceries", kind: .expense)

    enum WindowB: CaseIterable {
        case deletesExpense
        case lowersExpense
    }

    @Test("The step stays Delete Transaction in Everyday Savings after window B's change", arguments: WindowB.allCases)
    func keepsName(_ windowB: WindowB) throws {
        let date = Date(timeIntervalSince1970: 1_791_590_400)
        let expense = Transaction(
            type: .expense,
            amount: 5_000,
            date: date,
            timeZoneID: "Asia/Kolkata",
            accountID: savings.id,
            categoryID: groceries.id,
        )
        let refund = Transaction(
            type: .income,
            amount: 2_000,
            date: date,
            timeZoneID: "Asia/Kolkata",
            accountID: savings.id,
            categoryID: groceries.id,
            refundOfID: expense.id,
            isRefund: true,
        )
        let repository = InMemoryLedgerRepository()
        try repository.saveAccount(savings)
        try repository.saveCategory(groceries)
        try repository.saveTransaction(expense)
        try repository.saveTransaction(refund)
        let windowA = DefaultTransactionChangesUseCase(repository: repository)
        let step = try windowA.remove(ids: [refund.id])
        let outcome = try windowA.outcome(of: step)
        let name = UndoActionTitle.stepName(of: step, impact: try windowA.impact(of: step))
        #expect(name == "Delete Transaction in Everyday Savings")

        switch windowB {
        case .deletesExpense:
            _ = try DefaultTransactionChangesUseCase(repository: repository).remove(ids: [expense.id])
        case .lowersExpense:
            var lowered = expense
            lowered.amount = 1_000
            try repository.saveTransaction(lowered)
        }
        #expect(UndoActionTitle.stepName(of: step, impact: try windowA.impact(of: step)) == name)
        let result = try windowA.revert(step, expecting: outcome)
        switch windowB {
        case .deletesExpense:
            guard case .reverted = result else {
                Issue.record("Expected Undo to bring the refund back unlinked")
                return
            }
        case .lowersExpense:
            #expect(result == .stale(.changed([expense.id])))
        }
    }

    @Test("D224.2, D229: the cross-zone 'dated after' step is stale in window A's history and removed")
    func crossZoneStepIsRemoved() throws {
        let london = "Europe/London"
        let kolkata = "Asia/Kolkata"
        let expense = Transaction(
            type: .expense,
            amount: 5_000,
            date: Self.date("2026-10-09T12:00:00+05:30"),
            timeZoneID: kolkata,
            accountID: savings.id,
            categoryID: groceries.id,
        )
        let refund = Transaction(
            type: .income,
            amount: 2_000,
            date: Self.date("2026-10-09T21:00:00+01:00"),
            timeZoneID: london,
            accountID: savings.id,
            categoryID: groceries.id,
            refundOfID: expense.id,
            isRefund: true,
        )
        let repository = InMemoryLedgerRepository()
        try repository.saveAccount(savings)
        try repository.saveCategory(groceries)
        try repository.saveTransaction(expense)
        try repository.saveTransaction(refund)
        let useCases = TransactionUseCases(repository: repository)
        let windowA = TestWindow(useCases)
        windowA.history.record(try useCases.changes.remove(ids: [refund.id]))

        var moved = expense
        moved.date = Self.date("2026-10-10T01:00:00+05:30")
        _ = try useCases.saveTransactions.save([moved])
        let before = try repository.transactions()

        windowA.history.undo()
        #expect(windowA.history.alert?.title == "Can’t Undo Delete Transaction in Everyday Savings")
        #expect(!windowA.history.canUndo)
        #expect(!windowA.undoManager.canRedo)
        #expect(try repository.transactions() == before)
    }

    private static func date(_ text: String) -> Date {
        ISO8601DateFormatter().date(from: text)!
    }
}
