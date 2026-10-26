import Foundation
import LittleOrbitDomain
import Testing

/// #264, D391: an Edit form opened before its transaction was deleted elsewhere, say in another window, never saves
/// it back, nor the payee typed into it. A plain, split or transfer edit is refused and writes nothing; an edit of a
/// stored transaction and a new one still save. Made-up data.
@MainActor
@Suite("Transaction edit of a deleted transaction (#264)")
struct TransactionDeletedEditTests {
    typealias F = TransactionFixture  // swiftlint:disable:this type_name

    private func scene(_ transactions: [Transaction]) throws -> (FakeLedgerRepository, TransactionUseCases) {
        let repository = try FakeLedgerRepository(accounts: F.accounts, transactions: transactions)
        return (repository, TransactionUseCases(repository: repository, categoryNames: TestCategoryNames()))
    }

    /// The form's copy, loaded before the delete, then deleted through the use cases.
    private func deleteKeepingCopy(
        _ id: UUID,
        in repository: FakeLedgerRepository,
        _ useCases: TransactionUseCases,
    ) throws -> Transaction {
        let copy = try #require(try repository.transactions().first { $0.id == id })
        _ = try useCases.changes.remove(ids: [id])
        return copy
    }

    @Test("LedgerBook: an update of an ID that isn't stored throws missingTransaction")
    func ledgerRefusesAMissingID() throws {
        let (repository, _) = try scene([])
        #expect(throws: LedgerValidationError.missingTransaction) {
            try LedgerBook.updatingTransaction(
                F.expense(450, on: F.date(2026, 10, 19)),
                in: repository.snapshot,
                now: .now,
            )
        }
    }

    @Test("Plain: the edit throws, writes nothing and the transaction stays deleted")
    func plainEditAfterDelete() throws {
        let bakery = F.expense(450, on: F.date(2026, 10, 19))
        let (repository, useCases) = try scene([bakery])
        var edited = try deleteKeepingCopy(bakery.id, in: repository, useCases)
        let afterDelete = repository.snapshot
        edited.amount = 480
        #expect(throws: LedgerValidationError.missingTransaction) {
            try useCases.saveTransactions.update(edited)
        }
        #expect(repository.snapshot == afterDelete)
        #expect(try repository.transactions().isEmpty)
    }

    @Test("A typed payee resolved with the edit isn't created when the edit is refused (D391.1)")
    func typedPayeeNotCreated() throws {
        let bakery = F.expense(450, on: F.date(2026, 10, 19))
        let (repository, useCases) = try scene([bakery])
        let edited = try deleteKeepingCopy(bakery.id, in: repository, useCases)
        let afterDelete = repository.snapshot
        #expect(throws: LedgerValidationError.missingTransaction) {
            try useCases.saveTransactions.update(edited, payeeNamed: "Harbor Café", createdAt: F.date(2026, 10, 20))
        }
        #expect(repository.snapshot == afterDelete)
        #expect(try repository.payees().isEmpty)
    }

    @Test("Split: the edit throws and writes neither the transaction nor a split line")
    func splitEditAfterDelete() throws {
        let groceries = F.expense(600, on: F.date(2026, 10, 19))
        let (repository, useCases) = try scene([groceries])
        try repository.replaceSplits(
            [
                TransactionSplit(transactionID: groceries.id, amount: 400),
                TransactionSplit(transactionID: groceries.id, amount: 200),
            ],
            for: groceries.id,
        )
        var edited = try deleteKeepingCopy(groceries.id, in: repository, useCases)
        #expect(repository.snapshot.splits.isEmpty)
        let afterDelete = repository.snapshot
        edited.note = "Weekly shop"
        #expect(throws: LedgerValidationError.missingTransaction) {
            try useCases.saveTransactions.update(edited)
        }
        #expect(repository.snapshot == afterDelete)
        #expect(repository.snapshot.splits.isEmpty)
    }

    @Test("Transfer: deleted from either side, or with either account, the edit throws and neither half comes back")
    func transferEditAfterDelete() throws {
        for removal in ["source", "destination", "source account", "destination account"] {
            let move = F.transfer(2_000, on: F.date(2026, 10, 19))
            let (repository, useCases) = try scene([move])
            var edited = try #require(try repository.transactions().first { $0.id == move.id })
            switch removal {
            case "source account": try repository.deleteAccount(id: F.savingsID)
            case "destination account": try repository.deleteAccount(id: F.walletID)
            // One record holds both halves: a delete from either account's history removes it.
            default: _ = try useCases.changes.remove(ids: [move.id])
            }
            let afterDelete = repository.snapshot
            edited.amount = 2_500
            edited.details = "Cash for the week"
            #expect(throws: LedgerValidationError.missingTransaction, "\(removal)") {
                try useCases.saveTransactions.update(edited)
            }
            #expect(repository.snapshot == afterDelete, "\(removal)")
            #expect(try repository.transactions().isEmpty, "\(removal)")
        }
    }

    @Test("An edit of a stored transaction saves as .replaced, and a new one still saves as new")
    func editAndAddStillSave() throws {
        let bakery = F.expense(450, on: F.date(2026, 10, 19))
        let (repository, useCases) = try scene([bakery])
        var edited = try #require(try repository.transactions().first { $0.id == bakery.id })
        let stored = edited
        edited.amount = 480
        #expect(try useCases.saveTransactions.update(edited) == .replaced([stored]))
        #expect(try repository.transactions().map(\.amount) == [480])

        let renamed = try #require(try repository.transactions().first { $0.id == bakery.id })
        let change = try useCases.saveTransactions.update(
            renamed,
            payeeNamed: "Corner Bakery",
            createdAt: F.date(2026, 10, 20),
        )
        let payee = try #require(try repository.payees().first)
        #expect(payee.name == "Corner Bakery")
        #expect(try repository.transactions().first?.payeeID == payee.id)
        guard case .createdPayees(let created, .replaced) = change else {
            Issue.record("Expected the created payee to go with the change, got \(change)")
            return
        }
        #expect(created.map(\.id) == [payee.id])

        let new = F.expense(20, on: F.date(2026, 10, 20))
        #expect(try useCases.saveTransactions.save([new]) == .added([new.id]))
        #expect(try repository.transactions().count == 2)
    }
}
