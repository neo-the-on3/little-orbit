import Foundation
import LittleOrbitDomain
import Testing

/// The default transaction use cases over a fake repository.
@MainActor
@Suite("Transaction use cases")
struct TransactionUseCasesTests {
    typealias F = TransactionFixture  // swiftlint:disable:this type_name

    private func repository(_ transactions: [Transaction] = []) throws -> FakeLedgerRepository {
        try FakeLedgerRepository(accounts: F.accounts, transactions: transactions)
    }

    @Test("The entry ledger seeds the default categories once; the plain ledger never writes")
    func ledgerSeeding() throws {
        let repository = try repository()
        let useCases = TransactionUseCases(repository: repository)
        #expect(try useCases.loadLedger.ledger().categories.isEmpty)
        let seeded = try useCases.loadLedger.ledgerForEntry().categories
        #expect(!seeded.isEmpty)
        #expect(try useCases.loadLedger.ledgerForEntry().categories.count == seeded.count)
    }

    @Test("History for a missing account is nil; for a live one it carries the account and its rows")
    func history() throws {
        let repository = try repository([F.expense(500, on: F.date(2026, 10, 19))])
        let history = TransactionUseCases(repository: repository).accountHistory
        #expect(try history.history(of: UUID(), today: F.day(2026, 10, 20)) == nil)
        let page = try #require(try history.history(of: F.savingsID, today: F.day(2026, 10, 20)))
        #expect(page.account.id == F.savingsID)
        #expect(page.history.currentBalance == 9_500)
        #expect(page.ledger.accounts.count == F.accounts.count)
    }

    @Test("Saving returns .added for new transactions and .replaced with the stored versions for edits")
    func saveChanges() throws {
        let original = F.expense(500, on: F.date(2026, 10, 19))
        let repository = try repository([original])
        let save = TransactionUseCases(repository: repository).saveTransactions
        let new = F.expense(20, on: F.date(2026, 10, 20))
        #expect(try save.save([new]) == .added([new.id]))
        var edited = try #require(try repository.transactions().first { $0.id == original.id })
        let stored = edited
        edited.amount = 600
        #expect(try save.save([edited]) == .replaced([stored]))
    }

    @Test("Payees resolve by name, case-insensitively, and a new name saves one payee")
    func resolvePayee() throws {
        let repository = try repository()
        let save = TransactionUseCases(repository: repository).saveTransactions
        let when = F.date(2026, 10, 20)
        #expect(try save.resolvePayee(named: "   ", createdAt: when) == nil)
        let corner = try #require(try save.resolvePayee(named: " Corner Shop ", createdAt: when))
        #expect(corner.name == "Corner Shop")
        #expect(try save.resolvePayee(named: "corner shop", createdAt: when)?.id == corner.id)
        #expect(try repository.payees().count == 1)
    }

    @Test("Remove, undo and redo round-trip through the change and its inverse (D19)")
    func removeAndRevert() throws {
        let spend = F.expense(500, on: F.date(2026, 10, 19))
        let repository = try repository([spend])
        let changes = TransactionUseCases(repository: repository).changes
        let removed = try changes.remove(ids: [spend.id])
        #expect(try repository.transactions().isEmpty)
        #expect(try changes.revertNow(removed) == .added([spend.id]))
        #expect(try repository.transactions().map(\.id) == [spend.id])
        _ = try changes.revertNow(.added([spend.id]))
        #expect(try repository.transactions().isEmpty)
    }

    // MARK: - All or nothing

    @Test("A bulk delete that fails partway deletes nothing")
    func bulkDeleteIsAtomic() throws {
        let first = F.expense(100, on: F.date(2026, 10, 18))
        let second = F.expense(200, on: F.date(2026, 10, 19))
        let repository = try repository([first, second])
        let before = repository.snapshot
        repository.failsAfterWrites = 1
        let changes = TransactionUseCases(repository: repository).changes
        #expect(throws: FakeLedgerRepository.WriteFailure.self) {
            try changes.remove(ids: [first.id, second.id])
        }
        #expect(repository.snapshot == before)
        #expect(repository.atomicChanges == 1)
    }

    @Test("A bulk save that fails partway saves nothing")
    func bulkSaveIsAtomic() throws {
        let stored = F.expense(100, on: F.date(2026, 10, 18))
        let repository = try repository([stored])
        let before = repository.snapshot
        var edited = try #require(try repository.transactions().first)
        edited.amount = 150
        repository.failsAfterWrites = 1
        let save = TransactionUseCases(repository: repository).saveTransactions
        #expect(throws: FakeLedgerRepository.WriteFailure.self) {
            try save.save([edited, F.expense(20, on: F.date(2026, 10, 20))])
        }
        #expect(repository.snapshot == before)
    }

    @Test("An Undo that fails partway restores nothing, and the change can be undone again")
    func undoIsAtomic() throws {
        let first = F.expense(100, on: F.date(2026, 10, 18))
        let second = F.expense(200, on: F.date(2026, 10, 19))
        let repository = try repository([first, second])
        try repository.saveAttachment(
            Attachment(transactionID: first.id, fileName: "receipt.jpg", contentType: "image/jpeg")
        )
        let changes = TransactionUseCases(repository: repository).changes
        let removed = try changes.remove(ids: [first.id, second.id])
        let afterDelete = repository.snapshot

        // The first transaction comes back, then its attachment fails.
        repository.failsAfterWrites = repository.writes + 1
        #expect(throws: FakeLedgerRepository.WriteFailure.self) {
            try changes.revertNow(removed)
        }
        #expect(repository.snapshot == afterDelete)

        repository.failsAfterWrites = nil
        #expect(try changes.revertNow(removed) == .added([first.id, second.id]))
        #expect(
            try repository.transactions().map(\.id).sorted { $0.uuidString < $1.uuidString }
                == [first.id, second.id].sorted { $0.uuidString < $1.uuidString }
        )
        #expect(try repository.attachments(for: first.id).count == 1)
    }

    @Test("Reverting an edit that fails partway keeps the edited versions")
    func revertEditIsAtomic() throws {
        let one = F.expense(100, on: F.date(2026, 10, 18))
        let two = F.expense(200, on: F.date(2026, 10, 19))
        let repository = try repository([one, two])
        let save = TransactionUseCases(repository: repository).saveTransactions
        var edits = try repository.transactions()
        for index in edits.indices {
            edits[index].amount += 1
        }
        let change = try save.save(edits)
        let afterEdit = repository.snapshot
        repository.failsAfterWrites = repository.writes + 1
        #expect(throws: FakeLedgerRepository.WriteFailure.self) {
            try TransactionUseCases(repository: repository).changes.revertNow(change)
        }
        #expect(repository.snapshot == afterEdit)
    }

    @Test("A bulk delete is one Undo step: Undo restores all with their IDs and attachments, Redo deletes all")
    func bulkDeleteUndoAndRedo() throws {
        let items = (0..<5).map { F.expense(Decimal(100 * ($0 + 1)), on: F.date(2026, 10, 10 + $0)) }
        let repository = try repository(items)
        for item in items {
            try repository.saveAttachment(
                Attachment(transactionID: item.id, fileName: "receipt.jpg", contentType: "image/jpeg")
            )
        }
        let before = repository.snapshot
        let changes = TransactionUseCases(repository: repository).changes
        let removed = try changes.remove(ids: items.map(\.id))
        #expect(removed.transactionIDs == items.map(\.id))
        #expect(try repository.transactions().isEmpty)

        // A failure partway through Undo leaves everything deleted, and Undo can run again.
        let afterDelete = repository.snapshot
        repository.failsAfterWrites = repository.writes + 3
        #expect(throws: FakeLedgerRepository.WriteFailure.self) { try changes.revertNow(removed) }
        #expect(repository.snapshot == afterDelete)

        repository.failsAfterWrites = nil
        let redo = try changes.revertNow(removed)
        #expect(redo == .added(items.map(\.id)))
        #expect(Set(try repository.transactions().map(\.id)) == Set(items.map(\.id)))
        for item in items {
            #expect(try repository.attachments(for: item.id).count == 1)
        }
        #expect(try repository.transactions().map(\.amount).sorted() == before.transactions.map(\.amount).sorted())

        _ = try changes.revertNow(redo)
        #expect(try repository.transactions().isEmpty)
        #expect(try items.allSatisfy { try repository.attachments(for: $0.id).isEmpty })
    }

    @Test("A change's impact lists the accounts and transactions it touches (D165.1)")
    func affectedAccounts() throws {
        let lunch = F.expense(100, on: F.date(2026, 10, 18))
        let move = F.transfer(50, on: F.date(2026, 10, 19), from: F.walletID, to: F.usdID, received: 1)
        let repository = try repository([lunch, move])
        let changes = TransactionUseCases(repository: repository).changes
        func names(_ change: TransactionChange) throws -> Set<String> {
            Set(try changes.impact(of: change).accounts.map(\.name))
        }
        #expect(try names(.added([lunch.id])) == ["Everyday Savings"])
        #expect(try names(.replaced([move])) == ["Corner Wallet", "USD Wallet"])
        #expect(try changes.impact(of: .added([lunch.id])).transactionIDs == [lunch.id])
        #expect(try changes.impact(of: .added([lunch.id])).accountIDs == [F.savingsID])
        #expect(try changes.impact(of: .added([lunch.id])).transfers.isEmpty)
        let removed = try changes.remove(ids: [lunch.id])
        #expect(try names(removed) == ["Everyday Savings"])
    }

    @Test("A transfer's impact gives its source and destination in each version, the current one last (D166)")
    func transferAccounts() throws {
        let move = F.transfer(50, on: F.date(2026, 10, 19), from: F.walletID, to: F.usdID, received: 1)
        let repository = try repository([move])
        let changes = TransactionUseCases(repository: repository).changes
        var edited = move
        edited.amount = 60
        try repository.saveTransaction(edited)
        let leg = TransferImpact(transactionID: move.id, sourceAccountID: F.walletID, destinationAccountID: F.usdID)
        let impact = try changes.impact(of: .replaced([move]))
        #expect(impact.transfers == [leg, leg])
        #expect(impact.accountIDs == [F.walletID, F.usdID])
        let deleted = try changes.remove(ids: [move.id])
        #expect(try changes.impact(of: deleted).transfers == [leg])
    }

    @Test("A transfer moved to another account lists the accounts before and after (D166.3)")
    func transferChangedAccounts() throws {
        let move = F.transfer(50, on: F.date(2026, 10, 19), from: F.walletID, to: F.usdID, received: 1)
        let repository = try repository([move])
        let changes = TransactionUseCases(repository: repository).changes
        var edited = move
        edited.transferAccountID = F.savingsID
        edited.destinationAmount = nil
        try repository.saveTransaction(edited)
        let impact = try changes.impact(of: .replaced([move]))
        #expect(Set(impact.accounts.map(\.name)) == ["Corner Wallet", "USD Wallet", "Everyday Savings"])
        #expect(impact.accountIDs == [F.walletID, F.usdID, F.savingsID])
        #expect(impact.transfers.map(\.destinationAccountID) == [F.usdID, F.savingsID])
    }

    @Test("In a bulk change each transfer counts its own two accounts (D166.4)")
    func bulkWithTransfer() throws {
        let lunch = F.expense(100, on: F.date(2026, 10, 18), account: F.walletID)
        let move = F.transfer(50, on: F.date(2026, 10, 19), from: F.walletID, to: F.usdID, received: 1)
        let repository = try repository([lunch, move])
        let changes = TransactionUseCases(repository: repository).changes
        let impact = try changes.impact(of: try changes.remove(ids: [lunch.id, move.id]))
        #expect(Set(impact.accounts.map(\.name)) == ["Corner Wallet", "USD Wallet"])
        #expect(impact.transactionIDs == [lunch.id, move.id])
        #expect(impact.transfers.map(\.transactionID) == [move.id])
    }

    @Test("A whole-account change has no transaction impact; the account is in the change (#93)")
    func accountChangeImpact() throws {
        let changes = TransactionUseCases(repository: try repository()).changes
        #expect(try changes.impact(of: .addedAccount(F.walletID)) == ChangeImpact())
    }

    @Test("Deleting an account is one Undo step: Undo restores it with its transactions, Redo deletes it again (#93)")
    func removeAccountUndoAndRedo() throws {
        var items = (0..<11).map { F.expense(Decimal($0 + 1), on: F.date(2026, 10, 1 + $0), account: F.walletID) }
        items.append(F.transfer(50, on: F.date(2026, 10, 15), from: F.savingsID, to: F.walletID))
        let other = F.expense(7, on: F.date(2026, 10, 16))
        let repository = try repository(items + [other])
        try repository.saveAttachment(
            Attachment(transactionID: items[0].id, fileName: "receipt.jpg", contentType: "image/jpeg")
        )
        let before = repository.snapshot
        let changes = TransactionUseCases(repository: repository).changes
        // The one account delete (Tech Architect, #87): the same use case with or without Undo.
        let delete = AccountUseCases(repository: repository).deleteAccount

        let removed = TransactionChange.removedAccount(try delete.delete(F.walletID))
        #expect(removed.accountIDs == [F.walletID])
        guard case .removedAccount(let account) = removed else {
            Issue.record("Expected an account removal")
            return
        }
        #expect(account.transactions.count == 12)
        #expect(try repository.accounts().map(\.id).contains(F.walletID) == false)
        #expect(try repository.transactions().map(\.id) == [other.id])

        // All or nothing: a failure partway through Undo restores nothing.
        let afterDelete = repository.snapshot
        repository.failsAfterWrites = repository.writes + 4
        #expect(throws: FakeLedgerRepository.WriteFailure.self) { try changes.revertNow(removed) }
        #expect(repository.snapshot == afterDelete)
        repository.failsAfterWrites = nil

        let redo = try changes.revertNow(removed)
        #expect(redo == .addedAccount(F.walletID))
        #expect(Set(try repository.transactions().map(\.id)) == Set(before.transactions.map(\.id)))
        #expect(try repository.attachments(for: items[0].id).count == 1)
        #expect(try repository.accounts().first { $0.id == F.walletID }?.name == "Corner Wallet")

        let again = try changes.revertNow(redo)
        #expect(again.accountIDs == [F.walletID])
        #expect(try repository.transactions().map(\.id) == [other.id])
    }

    @Test("Deleting an account that's gone reports it")
    func removeMissingAccount() throws {
        let delete = AccountUseCases(repository: try repository()).deleteAccount
        #expect(throws: AccountUseCaseError.accountNotFound) { try delete.delete(UUID()) }
    }
}
