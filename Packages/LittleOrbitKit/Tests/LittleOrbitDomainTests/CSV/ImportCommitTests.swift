import Foundation
import LittleOrbitDomain
import Testing

/// One all-or-nothing save, and Undo Import that removes exactly what it added (#30 AC 6, D51, D281, D319.1).
@Suite("Import commit and undo (#30)")
@MainActor
struct ImportCommitTests {
    typealias F = ImportFixture  // swiftlint:disable:this type_name

    private let text = """
        Date,Type,Account,Amount,Category,Payee,Description
        2026-10-20,Expense,Everyday Savings,-450,Food › Groceries,Corner Shop,Milk
        2026-10-21,Expense,New Card,-90,Fun › Films,Cinema Hall,Show
        2026-10-22,Refund,Everyday Savings,120,Food,Corner Shop,Returned bottle
        2026-10-23,Expense,Everyday Savings,abc,,,
        """

    private func repository() throws -> FakeLedgerRepository {
        let repository = try FakeLedgerRepository(accounts: F.accounts(), categories: F.categories())
        try repository.savePayee(F.payees()[0])
        return repository
    }

    private func preview(_ useCase: DefaultImportLedgerUseCase) throws -> ImportPreview {
        try F.preview(text, ledger: try useCase.ledger())
    }

    @Test("Commit saves the selected rows with the records they need, and the refund without a link")
    func commit() throws {
        let repository = try repository()
        let useCase = DefaultImportLedgerUseCase(repository: repository)
        let preview = try preview(useCase)
        let receipt = try useCase.commit(preview, selection: preview.defaultSelection, fileName: "bank.csv")
        #expect(receipt.importedCount == 3)
        #expect(receipt.failed == 1)
        #expect(receipt.unlinkedRefundCount == 1)
        #expect(receipt.createdAccounts.map(\.name) == ["New Card"])
        #expect(receipt.createdCategories.map(\.name) == ["Fun", "Films"])
        #expect(receipt.createdPayees.map(\.name) == ["Cinema Hall"])
        let films = try #require(receipt.createdCategories.last)
        #expect(films.parentID == receipt.createdCategories.first?.id)
        let refund = try #require(try repository.transactions().first { $0.isRefund })
        #expect(refund.type == .income)
        #expect(refund.refundOfID == nil)
        #expect(refund.categoryID == F.foodID)
        #expect(try repository.transactions().count == 3)
        #expect(repository.isDefaultSeedPending == false)
    }

    @Test("A failure partway saves nothing")
    func atomic() throws {
        let repository = try repository()
        let useCase = DefaultImportLedgerUseCase(repository: repository)
        let preview = try preview(useCase)
        repository.failsAfterWrites = repository.writes + 2
        #expect(throws: (any Error).self) {
            try useCase.commit(preview, selection: preview.defaultSelection, fileName: "bank.csv")
        }
        #expect(try repository.transactions().isEmpty)
        #expect(try repository.accounts().count == 3)
        #expect(try repository.categories().count == 3)
    }

    @Test("Unticked rows aren't saved and are counted")
    func selection() throws {
        let repository = try repository()
        let useCase = DefaultImportLedgerUseCase(repository: repository)
        let preview = try preview(useCase)
        let receipt = try useCase.commit(preview, selection: [preview.rows[0].id], fileName: "bank.csv")
        #expect(receipt.importedCount == 1)
        #expect(receipt.skippedOther == 2)
        #expect(receipt.createdAccounts.isEmpty)
    }

    @Test("Undo Import removes the transactions and the records the import created")
    func undo() throws {
        let repository = try repository()
        let useCase = DefaultImportLedgerUseCase(repository: repository)
        let preview = try preview(useCase)
        let receipt = try useCase.commit(preview, selection: preview.defaultSelection, fileName: "bank.csv")
        try useCase.undo(receipt)
        #expect(try repository.transactions().isEmpty)
        #expect(try repository.accounts().map(\.name) == F.accounts().map(\.name))
        #expect(try repository.categories().count == 3)
        #expect(try repository.payees().map(\.name) == ["Corner Shop"])
    }

    @Test("Undo Import refuses, changing nothing, once an imported transaction was edited")
    func undoAfterEdit() throws {
        let repository = try repository()
        let useCase = DefaultImportLedgerUseCase(repository: repository)
        let preview = try preview(useCase)
        let receipt = try useCase.commit(preview, selection: preview.defaultSelection, fileName: "bank.csv")
        var edited = try #require(try repository.transactions().first)
        edited.details = "Edited"
        try repository.saveTransaction(edited)
        #expect(throws: ImportUndoError.changedSinceImport) { try useCase.undo(receipt) }
        #expect(try repository.transactions().count == 3)
    }

    @Test("Undo Import refuses, changing nothing, once a refund was linked to an imported expense")
    func undoAfterLinkedRefund() throws {
        let repository = try repository()
        let useCase = DefaultImportLedgerUseCase(repository: repository)
        let preview = try preview(useCase)
        let receipt = try useCase.commit(preview, selection: preview.defaultSelection, fileName: "bank.csv")
        let milk = try #require(try repository.transactions().first { $0.details == "Milk" })
        let refund = Transaction(
            type: .income,
            amount: 50,
            date: F.date(2026, 10, 24),
            timeZoneID: F.zone,
            accountID: milk.accountID,
            categoryID: milk.categoryID,
            details: "Spilt carton",
            refundOfID: milk.id,
            isRefund: true,
        )
        try repository.saveTransaction(refund)
        #expect(throws: ImportUndoError.changedSinceImport) { try useCase.undo(receipt) }
        #expect(try repository.transactions().count == 4)
        let kept = try #require(try repository.transactions().first { $0.id == refund.id })
        #expect(kept.refundOfID == milk.id)
    }

    @Test("Undo Import keeps a created record that something added later uses")
    func undoKeepsUsedRecords() throws {
        let repository = try repository()
        let useCase = DefaultImportLedgerUseCase(repository: repository)
        let preview = try preview(useCase)
        let receipt = try useCase.commit(preview, selection: preview.defaultSelection, fileName: "bank.csv")
        let card = try #require(receipt.createdAccounts.first)
        try repository.saveTransaction(Transaction(type: .expense, amount: 5, timeZoneID: F.zone, accountID: card.id))
        try useCase.undo(receipt)
        #expect(try repository.accounts().contains { $0.id == card.id })
        #expect(try repository.transactions().count == 1)
    }
}
