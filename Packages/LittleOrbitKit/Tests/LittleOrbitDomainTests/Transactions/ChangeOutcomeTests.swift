import Foundation
import LittleOrbitDomain
import Testing

@MainActor
extension TransactionChangesUseCase {
    /// Reverts `change` as if nothing had touched its records since: the outcome is read just before.
    func revertNow(_ change: TransactionChange) throws -> TransactionChange {
        let result = try revert(change, expecting: outcome(of: change))
        guard case .reverted(let inverse, _) = result else {
            Issue.record("Expected the change to revert, got \(result)")
            return change
        }
        return inverse
    }
}

/// The stale check behind per-window undo (D187.5, #93 X1–X7): two windows' steps over one store, compared
/// by value on the fields each change touched. A stale step writes nothing.
@MainActor
@Suite("Stale undo steps")
struct ChangeOutcomeTests {
    typealias F = TransactionFixture  // swiftlint:disable:this type_name

    @MainActor
    private struct Setup {
        let repository: FakeLedgerRepository
        let useCases: TransactionUseCases
        var changes: any TransactionChangesUseCase { useCases.changes }

        /// Makes a change the way a window does, and keeps what it left, as the window's step does.
        func step(_ change: TransactionChange) throws -> (TransactionChange, ChangeOutcome) {
            (change, try changes.outcome(of: change))
        }

        func stored(_ id: UUID) throws -> Transaction? {
            try repository.transactions().first { $0.id == id }
        }

        func edit(_ id: UUID, _ body: (inout Transaction) -> Void) throws -> TransactionChange {
            var transaction = try #require(try stored(id))
            body(&transaction)
            return try useCases.saveTransactions.save([transaction])
        }
    }

    private func setup(_ transactions: [Transaction]) throws -> Setup {
        let repository = try FakeLedgerRepository(accounts: F.accounts, transactions: transactions)
        return Setup(
            repository: repository,
            useCases: TransactionUseCases(repository: repository, categoryNames: TestCategoryNames()),
        )
    }

    private var bakery: Transaction { F.expense(450, on: F.date(2026, 10, 18)) }

    @Test("X1: A edits, B edits again; A's Undo is stale, writes nothing, and B's values stay")
    func editThenOtherWindowEdit() throws {
        let corner = bakery
        let setup = try setup([corner])
        let (change, outcome) = try setup.step(try setup.edit(corner.id) { $0.amount = 500 })
        _ = try setup.edit(corner.id) { $0.amount = 650 }
        let writes = setup.repository.writes

        #expect(try setup.changes.check(change, expecting: outcome) == .stale(.changed([corner.id])))
        #expect(try setup.changes.revert(change, expecting: outcome) == .stale(.changed([corner.id])))
        #expect(try setup.stored(corner.id)?.amount == 650)
        #expect(setup.repository.writes == writes, "A stale step writes nothing")
    }

    @Test("X2: A edits, B deletes; A's Undo is stale and doesn't recreate it")
    func editThenOtherWindowDelete() throws {
        let corner = bakery
        let setup = try setup([corner])
        let (change, outcome) = try setup.step(try setup.edit(corner.id) { $0.amount = 500 })
        _ = try setup.changes.remove(ids: [corner.id])

        #expect(try setup.changes.revert(change, expecting: outcome) == .stale(.deleted([corner.id])))
        #expect(try setup.stored(corner.id) == nil)
    }

    @Test("X3: A adds, B edits; A's Undo is stale and doesn't delete it")
    func addThenOtherWindowEdit() throws {
        let corner = bakery
        let setup = try setup([])
        let (change, outcome) = try setup.step(try setup.useCases.saveTransactions.save([corner]))
        _ = try setup.edit(corner.id) { $0.note = "Birthday cake" }

        #expect(try setup.changes.revert(change, expecting: outcome) == .stale(.changed([corner.id])))
        #expect(try setup.stored(corner.id)?.note == "Birthday cake")
    }

    @Test("X4: A deletes a transaction, B deletes its account; A's Undo restores nothing into a missing account")
    func deleteThenOtherWindowDeletesAccount() throws {
        let corner = bakery
        let setup = try setup([corner])
        let (change, outcome) = try setup.step(try setup.changes.remove(ids: [corner.id]))
        try setup.repository.deleteAccount(id: F.savingsID)

        #expect(try setup.changes.revert(change, expecting: outcome) == .stale(.accountDeleted([F.savingsID])))
        #expect(try setup.repository.transactions().isEmpty)
    }

    @Test("An edit whose account was deleted elsewhere names the account, not the transaction")
    func editThenOtherWindowDeletesAccount() throws {
        let corner = bakery
        let setup = try setup([corner])
        let (change, outcome) = try setup.step(try setup.edit(corner.id) { $0.amount = 500 })
        try setup.repository.deleteAccount(id: F.savingsID)

        #expect(try setup.changes.revert(change, expecting: outcome) == .stale(.accountDeleted([F.savingsID])))
        #expect(try setup.repository.transactions().isEmpty)
    }

    @Test("X5: A bulk-edits 5, B edits 2 of them; A's Undo changes none of the 5 and names the 2")
    func bulkEditIsAllOrNothing() throws {
        let five = (1...5).map { F.expense(Decimal($0 * 100), on: F.date(2026, 10, $0)) }
        let setup = try setup(five)
        let edited = try five.map { original in
            var transaction = try #require(try setup.stored(original.id))
            transaction.note = "Groceries"
            return transaction
        }
        let (change, outcome) = try setup.step(try setup.useCases.saveTransactions.save(edited))
        _ = try setup.edit(five[1].id) { $0.note = "Rent" }
        _ = try setup.edit(five[3].id) { $0.note = "Fuel" }
        let before = try setup.repository.transactions()

        #expect(
            try setup.changes.revert(change, expecting: outcome) == .stale(.changed([five[1].id, five[3].id]))
        )
        #expect(try setup.repository.transactions() == before)
    }

    @Test("D189.2: a bulk step with one record changed and one deleted elsewhere reports both")
    func bulkEditChangedAndDeleted() throws {
        let three = (1...3).map { F.expense(Decimal($0 * 100), on: F.date(2026, 10, $0)) }
        let setup = try setup(three)
        let edited = try three.map { original in
            var transaction = try #require(try setup.stored(original.id))
            transaction.note = "Groceries"
            return transaction
        }
        let (change, outcome) = try setup.step(try setup.useCases.saveTransactions.save(edited))
        _ = try setup.edit(three[0].id) { $0.note = "Rent" }
        _ = try setup.changes.remove(ids: [three[2].id])
        let before = try setup.repository.transactions()

        #expect(
            try setup.changes.revert(change, expecting: outcome)
                == .stale(.changedAndDeleted(changed: [three[0].id], deleted: [three[2].id]))
        )
        #expect(try setup.repository.transactions() == before)
    }

    @Test("X6: A undoes a delete, B edits the restored row; A's Redo is stale and deletes nothing")
    func redoAfterOtherWindowEdit() throws {
        let corner = bakery
        let setup = try setup([corner])
        let (change, outcome) = try setup.step(try setup.changes.remove(ids: [corner.id]))
        guard case .reverted(let redo, let left) = try setup.changes.revert(change, expecting: outcome) else {
            Issue.record("Undo should work")
            return
        }
        _ = try setup.edit(corner.id) { $0.amount = 475 }

        #expect(try setup.changes.revert(redo, expecting: left) == .stale(.changed([corner.id])))
        #expect(try setup.stored(corner.id)?.amount == 475)
    }

    @Test("X7: B edits and undoes its edit; the values match again, so A's Undo works")
    func otherWindowUndidItsEdit() throws {
        let corner = bakery
        let setup = try setup([corner])
        let (change, outcome) = try setup.step(try setup.edit(corner.id) { $0.amount = 500 })
        let (other, otherOutcome) = try setup.step(try setup.edit(corner.id) { $0.amount = 650 })
        guard case .reverted = try setup.changes.revert(other, expecting: otherOutcome) else {
            Issue.record("B's Undo should work")
            return
        }

        #expect(try setup.changes.check(change, expecting: outcome) == .current)
        guard case .reverted(let redo, _) = try setup.changes.revert(change, expecting: outcome) else {
            Issue.record("A's Undo should work")
            return
        }
        #expect(try setup.stored(corner.id)?.amount == 450)
        #expect(redo.transactionIDs == [corner.id])
    }

    @Test("Another window's change to a field this step didn't touch keeps the step current, and its value")
    func untouchedFieldsKeepTheirValues() throws {
        let corner = bakery
        let setup = try setup([corner])
        let (change, outcome) = try setup.step(try setup.edit(corner.id) { $0.amount = 500 })
        _ = try setup.edit(corner.id) { $0.note = "Birthday cake" }

        guard case .reverted = try setup.changes.revert(change, expecting: outcome) else {
            Issue.record("The amount wasn't touched elsewhere, so Undo should work")
            return
        }
        let stored = try #require(try setup.stored(corner.id))
        #expect(stored.amount == 450)
        #expect(stored.note == "Birthday cake")
    }

    @Test("Redo of an account delete is stale if another window added a transaction to the account")
    func accountRedoKeepsOtherWindowsTransactions() throws {
        let corner = bakery
        let setup = try setup([corner])
        let account = try #require(F.accounts.first { $0.id == F.savingsID })
        try setup.repository.deleteAccount(id: account.id)
        let removed = TransactionChange.removedAccount(
            RemovedAccount(account: account, transactions: [RemovedTransaction(transaction: corner)])
        )
        // Stands in for the window's own delete: undoing it restores the account and its transaction.
        guard
            case .reverted(let redo, let left) = try setup.changes.revert(
                removed,
                expecting: try setup.changes.outcome(of: removed),
            )
        else {
            Issue.record("Undo should work")
            return
        }
        let other = F.expense(99, on: F.date(2026, 10, 19))
        _ = try setup.useCases.saveTransactions.save([other])

        #expect(try setup.changes.revert(redo, expecting: left) == .stale(.changed([other.id])))
        #expect(try setup.repository.transactions().count == 2)
    }

    @Test("A real write failure throws, writes nothing, and the same step can be tried again")
    func failureIsNotStale() throws {
        let corner = bakery
        let setup = try setup([corner])
        let (change, outcome) = try setup.step(try setup.changes.remove(ids: [corner.id]))
        setup.repository.failsAfterWrites = setup.repository.writes
        #expect(throws: FakeLedgerRepository.WriteFailure.self) {
            try setup.changes.revert(change, expecting: outcome)
        }
        #expect(try setup.repository.transactions().isEmpty)
        setup.repository.failsAfterWrites = nil
        guard case .reverted = try setup.changes.revert(change, expecting: outcome) else {
            Issue.record("The retry should work")
            return
        }
        #expect(try setup.stored(corner.id) != nil)
    }
}

@Suite("Transaction fields")
struct TransactionFieldTests {
    @Test("Every field compares and copies its own value, and only that")
    func everyFieldCopies() {
        let before = Transaction(type: .expense, amount: 1, accountID: UUID())
        let after = Transaction(
            id: before.id,
            type: .transfer,
            amount: 2,
            date: before.date.addingTimeInterval(60),
            timeZoneID: "UTC",
            accountID: UUID(),
            categoryID: UUID(),
            payeeID: UUID(),
            details: "Corner Bakery",
            note: "Cake",
            transferAccountID: UUID(),
            destinationAmount: 3,
            scheduledTemplateID: UUID(),
            scheduledOccurrenceDate: before.date,
            status: .pending,
            tagIDs: [UUID()],
            refundOfID: UUID(),
            isRefund: true,
            createdAt: before.createdAt,
        )
        #expect(TransactionField.changed(from: before, to: after) == Set(TransactionField.allCases))
        for field in TransactionField.allCases {
            var copy = before
            field.copy(from: after, into: &copy)
            #expect(field.matches(copy, after), "\(field)")
            #expect(TransactionField.changed(from: before, to: copy) == [field], "\(field)")
        }
    }
}
