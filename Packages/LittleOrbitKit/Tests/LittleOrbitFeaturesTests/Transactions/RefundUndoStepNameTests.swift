import Foundation
import LittleOrbitDomain
import LittleOrbitPersistence
import Testing

@testable import LittleOrbitFeatures

/// D198 on a refund delete whose expense another window then changes (D224, Tech Architect's B1 on #125):
/// the step keeps its name, whether Undo brings the refund back unlinked, linked, or can't. When it can't, the
/// message names the changed expense, which the step doesn't hold, as the ledger has it now (#128 S23, D228.4).
@MainActor
@Suite("Undo name and stale message of a refund delete (#55, D198, D224, D228.4)")
struct RefundUndoStepNameTests {
    private let savings = Account(name: "Everyday Savings", type: .savings, currencyCode: "INR")
    private let groceries = TransactionCategory(name: "Groceries", kind: .expense)
    private let cash = Account(name: "Orbit Cash", type: .cash, currencyCode: "INR")
    private let shopping = TransactionCategory(name: "Shopping", kind: .expense)
    private let trailhead = Payee(name: "Trailhead Sports")

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
        // The expense has no payee or description: never the account's name (D228.4).
        #expect(windowA.history.alert?.message == "The transaction has changed since then. Nothing was changed.")
        #expect(!windowA.history.canUndo)
        #expect(!windowA.undoManager.canRedo)
        #expect(try repository.transactions() == before)
    }

    @Test("S23(d): B moves Trailhead Sports after R1, and A's Undo names Trailhead Sports")
    func refundDeleteNamesExpense() throws {
        let s23 = try fixture(refundAccount: savings)
        let useCases = TransactionUseCases(repository: s23.repository)
        let windowA = TestWindow(useCases)
        windowA.history.record(try useCases.changes.remove(ids: [s23.refund.id]))

        try move(s23.expense, using: useCases)
        let before = try s23.repository.transactions()
        windowA.history.undo()

        #expect(windowA.history.alert?.title == "Can’t Undo Delete Transaction in Everyday Savings")
        #expect(
            windowA.history.alert?.message == "Trailhead Sports has changed since then. Nothing was changed."
        )
        #expect(!windowA.history.canUndo)
        #expect(try s23.repository.transactions() == before)
    }

    @Test("S23(d) on an account delete: A's Undo names Trailhead Sports, not the deleted account")
    func accountDeleteNamesExpense() throws {
        let s23 = try fixture(refundAccount: cash)
        let useCases = TransactionUseCases(repository: s23.repository)
        let windowA = TestWindow(useCases)
        windowA.history.record(
            .removedAccount(try AccountUseCases(repository: s23.repository).deleteAccount.delete(cash.id))
        )

        try move(s23.expense, using: useCases)
        windowA.history.undo()

        #expect(
            windowA.history.alert?.message == "Trailhead Sports has changed since then. Nothing was changed."
        )
        #expect(!windowA.history.canUndo)
    }

    @Test("D228.4: an account delete's Undo never names the account for a changed, unnamed expense")
    func accountDeleteNeverNamesAccount() throws {
        let s23 = try fixture(refundAccount: cash, named: false)
        let useCases = TransactionUseCases(repository: s23.repository)
        let windowA = TestWindow(useCases)
        windowA.history.record(
            .removedAccount(try AccountUseCases(repository: s23.repository).deleteAccount.delete(cash.id))
        )

        try move(s23.expense, using: useCases)
        windowA.history.undo()

        let message = try #require(windowA.history.alert?.message)
        #expect(message == "The transaction has changed since then. Nothing was changed.")
        #expect(!message.contains(cash.name))
        #expect(!message.contains(savings.name))
    }

    @Test("S23(d) with an unnamed expense: A's Undo reads “The transaction has changed since then.”")
    func unnamedExpense() throws {
        let s23 = try fixture(refundAccount: savings, named: false)
        let useCases = TransactionUseCases(repository: s23.repository)
        let windowA = TestWindow(useCases)
        windowA.history.record(try useCases.changes.remove(ids: [s23.refund.id]))

        try move(s23.expense, using: useCases)
        windowA.history.undo()

        #expect(windowA.history.alert?.message == "The transaction has changed since then. Nothing was changed.")
    }

    /// Trailhead Sports, ₹1,000.00 Shopping on 17 Oct 2026 in Everyday Savings, and its refund R1, ₹300.00 on
    /// 20 Oct 2026, in Asia/Kolkata.
    private func fixture(
        refundAccount: Account,
        named: Bool = true,
    ) throws -> Fixture {
        let payee = named ? trailhead : nil
        let repository = InMemoryLedgerRepository()
        try repository.saveAccount(savings)
        if refundAccount.id != savings.id {
            try repository.saveAccount(refundAccount)
        }
        try repository.saveCategory(shopping)
        if let payee {
            try repository.savePayee(payee)
        }
        let expense = Transaction(
            type: .expense,
            amount: 1_000,
            date: Self.date("2026-10-17T12:00:00+05:30"),
            timeZoneID: "Asia/Kolkata",
            accountID: savings.id,
            categoryID: shopping.id,
            payeeID: payee?.id,
        )
        let refund = Transaction(
            type: .income,
            amount: 300,
            date: Self.date("2026-10-20T12:00:00+05:30"),
            timeZoneID: "Asia/Kolkata",
            accountID: refundAccount.id,
            categoryID: shopping.id,
            details: "R1 Trailhead refund",
            refundOfID: expense.id,
            isRefund: true,
        )
        try repository.saveTransaction(expense)
        try repository.saveTransaction(refund)
        return Fixture(repository: repository, expense: expense, refund: refund)
    }

    private struct Fixture {
        let repository: InMemoryLedgerRepository
        let expense: Transaction
        let refund: Transaction
    }

    /// Window B moves the expense to 21 Oct, after its refund (S23(d)).
    private func move(_ expense: Transaction, using useCases: TransactionUseCases) throws {
        var moved = expense
        moved.date = Self.date("2026-10-21T12:00:00+05:30")
        _ = try useCases.saveTransactions.save([moved])
    }

    private static func date(_ text: String) -> Date {
        ISO8601DateFormatter().date(from: text)!
    }
}
