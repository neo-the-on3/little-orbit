import Foundation
import LittleOrbitDomain
import Testing

/// D384.7 (#254): normal transaction Undo and Undo Import keep and remove the same created payees, by the one
/// “touched since” rule (D362). Redo of a normal Undo that kept a touched payee uses it as it is, and the next
/// Undo keeps it again. Undo Import has no Redo (out of scope on #254). Made-up data.
@Suite("Undo and Undo Import share the touched-since rule (D384)")
@MainActor
struct ImportUndoSameRuleTests {
    typealias F = ImportFixture  // swiftlint:disable:this type_name

    enum Touch: CaseIterable {
        case none, renamed, defaultCategorySet, archived, archivedAndUnarchived, givenAndTakenOff

        var keeps: Bool { self != .none }
    }

    private static let text = """
        Date,Amount,Account,Payee,Description
        2026-10-22,-320,Everyday Savings,Lantern Tea House,Tea
        """

    private func expense(_ amount: Decimal) -> Transaction {
        Transaction(
            type: .expense,
            amount: amount,
            date: F.date(2026, 10, 22),
            timeZoneID: F.zone,
            accountID: F.savingsID,
        )
    }

    /// Something done to the payee after the change that created it, as the user would do it.
    private func apply(_ touch: Touch, to id: UUID, in repository: FakeLedgerRepository) throws {
        func stored() throws -> Payee { try #require(try repository.payees().first { $0.id == id }) }
        var payee = try stored()
        switch touch {
        case .none:
            return
        case .renamed:
            payee.name = "Lantern Tea House & Café"
            try repository.savePayee(payee)
        case .defaultCategorySet:
            payee.defaultCategoryID = F.foodID
            try repository.savePayee(payee)
        case .archived, .archivedAndUnarchived:
            payee.isArchived = true
            try repository.savePayee(payee)
            if touch == .archivedAndUnarchived {
                payee = try stored()
                payee.isArchived = false
                try repository.savePayee(payee)
            }
        case .givenAndTakenOff:
            var mine = expense(80)
            mine.payeeID = id
            try repository.saveTransaction(mine)
            var stored = try #require(try repository.transactions().first { $0.id == mine.id })
            stored.payeeID = nil
            try repository.saveTransaction(stored)
        }
    }

    /// Normal Undo of a save that created the payee: whether the payee is still there after.
    private func keptByUndo(_ touch: Touch) throws -> Bool {
        let repository = try FakeLedgerRepository(accounts: F.accounts(), categories: F.categories())
        let useCases = TransactionUseCases(repository: repository, categoryNames: TestCategoryNames())
        let resolved = try #require(
            try useCases.saveTransactions.resolvePayee(named: "Lantern Tea House", createdAt: F.date(2026, 10, 22))
        )
        var spend = expense(320)
        spend.payeeID = resolved.payee.id
        let change = try useCases.saveTransactions.save([spend], creating: [resolved.payee])
        try apply(touch, to: resolved.payee.id, in: repository)
        let outcome = try useCases.changes.outcome(of: change)
        guard case .reverted = try useCases.changes.revert(change, expecting: outcome) else {
            Issue.record("the Undo went stale")
            return true
        }
        #expect(try !repository.transactions().contains { $0.id == spend.id })
        return try repository.payees().contains { $0.id == resolved.payee.id }
    }

    /// Undo Import of an import that created the payee: whether the payee is still there after.
    private func keptByUndoImport(_ touch: Touch) throws -> Bool {
        let repository = try FakeLedgerRepository(accounts: F.accounts(), categories: F.categories())
        let useCase = DefaultImportLedgerUseCase(repository: repository)
        let preview = try F.preview(Self.text, ledger: try useCase.ledger())
        let receipt = try useCase.commit(preview, selection: preview.defaultSelection, fileName: "riverstone_oct.csv")
        let payee = try #require(receipt.createdPayees.first)
        try apply(touch, to: payee.id, in: repository)
        #expect(try useCase.payeesUndoRemoves(receipt) == (touch.keeps ? 0 : 1))
        try useCase.undo(receipt)
        #expect(try !repository.transactions().contains { receipt.transactions.map(\.id).contains($0.id) })
        return try repository.payees().contains { $0.id == payee.id }
    }

    @Test("Check 7: both Undos keep a touched payee and remove an untouched one", arguments: Touch.allCases)
    func sameRule(_ touch: Touch) throws {
        let byUndo = try keptByUndo(touch)
        let byUndoImport = try keptByUndoImport(touch)
        #expect(byUndo == byUndoImport, "\(touch)")
        #expect(byUndoImport == touch.keeps, "\(touch)")
    }

    @Test("Redo after an Undo that kept a renamed payee uses it as it is; the next Undo keeps it again")
    func redoKeepsTheTouchedPayee() throws {
        let repository = try FakeLedgerRepository(accounts: F.accounts(), categories: F.categories())
        let useCases = TransactionUseCases(repository: repository, categoryNames: TestCategoryNames())
        let resolved = try #require(
            try useCases.saveTransactions.resolvePayee(named: "Lantern Tea House", createdAt: F.date(2026, 10, 22))
        )
        var spend = expense(320)
        spend.payeeID = resolved.payee.id
        let change = try useCases.saveTransactions.save([spend], creating: [resolved.payee])
        try apply(.renamed, to: resolved.payee.id, in: repository)
        func revert(_ change: TransactionChange) throws -> TransactionChange {
            let outcome = try useCases.changes.outcome(of: change)
            guard case .reverted(let inverse, _) = try useCases.changes.revert(change, expecting: outcome) else {
                Issue.record("the step went stale")
                return change
            }
            return inverse
        }
        let undone = try revert(change)
        #expect(try repository.payees().map(\.name) == ["Lantern Tea House & Café"])
        let redone = try revert(undone)
        #expect(try repository.payees().map(\.id) == [resolved.payee.id])
        #expect(try repository.transactions().map(\.payeeID) == [resolved.payee.id])
        _ = try revert(redone)
        #expect(try repository.transactions().isEmpty)
        #expect(try repository.payees().map(\.name) == ["Lantern Tea House & Café"])
    }
}
