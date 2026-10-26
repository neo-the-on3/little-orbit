import Foundation
import LittleOrbitDomain
import LittleOrbitPersistence
import Testing

extension LedgerRepository {
    /// Redo of an Undo Import, as the timing tests measure it (#265): the receipt's created accounts, categories
    /// and payees and its transactions put back, with their ids, in one change.
    func redoImport(_ receipt: ImportReceipt) throws {
        try atomically {
            for account in receipt.createdAccounts {
                try saveAccount(account)
            }
            for category in receipt.createdCategories {
                try saveCategory(category)
            }
            for payee in receipt.createdPayees {
                try savePayee(payee)
            }
            try saveNewTransactions(receipt.transactions)
        }
    }
}

/// The Redo the SwiftData timing tests use puts back what Undo Import took out, on every platform.
@Suite("Redo of an Undo Import (#265 test support)")
@MainActor
struct ImportRedoTests {
    @Test("Redo puts every imported row and created payee back")
    func redoRestoresTheImport() throws {
        let repository = try ImportTimingTests.repository(existing: 50)
        let (preview, ledger) = try ImportTimingTests.preview(repository)
        let receipt = try ledger.commit(preview, selection: preview.defaultSelection, fileName: "redo.csv")
        let imported = Set(try repository.transactions().map(\.id))
        let payees = Set(try repository.payees().map(\.id))
        try ledger.undo(receipt)
        #expect(try repository.transactions().count == 50)
        try repository.redoImport(receipt)
        #expect(Set(try repository.transactions().map(\.id)) == imported)
        #expect(Set(try repository.payees().map(\.id)) == payees)
    }
}
