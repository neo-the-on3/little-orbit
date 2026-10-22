import Foundation
import LittleOrbitDomain
import Testing

/// A payee created by typing its name in a save comes and goes with that save on Undo and Redo (D191.4, #93
/// N3–N3c).
@MainActor
@Suite("Payees created by a save, on Undo and Redo")
struct PayeeUndoTests {
    typealias F = TransactionFixture  // swiftlint:disable:this type_name

    @MainActor
    private struct Ledger {
        let repository: FakeLedgerRepository
        let useCases: TransactionUseCases

        /// Saves `transaction` with a payee named `name`, as the form does, and returns the change to undo.
        func save(_ transaction: Transaction, payee name: String) throws -> TransactionChange {
            let resolved = try #require(
                try useCases.saveTransactions.resolvePayee(named: name, createdAt: F.date(2026, 10, 21))
            )
            var transaction = transaction
            transaction.payeeID = resolved.payee.id
            let created = resolved.isNew ? [resolved.payee] : []
            return try useCases.saveTransactions.save([transaction], creating: created)
        }

        /// Undo or Redo: reverts `change` and returns what's left to revert next.
        func revert(_ change: TransactionChange) throws -> TransactionChange {
            let outcome = try useCases.changes.outcome(of: change)
            guard case .reverted(let inverse, _) = try useCases.changes.revert(change, expecting: outcome) else {
                Issue.record("the change went stale")
                return change
            }
            return inverse
        }

        func payee(named name: String) throws -> Payee? {
            try repository.payees().first { $0.name == name }
        }
    }

    private func ledger(_ transactions: [Transaction] = []) throws -> Ledger {
        let repository = try FakeLedgerRepository(accounts: F.accounts, transactions: transactions)
        return Ledger(repository: repository, useCases: TransactionUseCases(repository: repository))
    }

    @Test("N3: Undo removes the new transaction and its unused new payee; Redo puts both back, same IDs")
    func unreferenced() throws {
        let ledger = try ledger()
        let spend = F.expense(2_500, on: F.date(2026, 10, 21))
        let added = try ledger.save(spend, payee: "Trailhead Sports")
        let payee = try #require(try ledger.payee(named: "Trailhead Sports"))

        let undone = try ledger.revert(added)
        #expect(try ledger.repository.transactions().isEmpty)
        #expect(try ledger.repository.payees().isEmpty)
        #expect(ledger.repository.atomicChanges == 2, "the count and the delete are in the revert's one change")

        let redone = try ledger.revert(undone)
        #expect(try ledger.repository.payees().map(\.id) == [payee.id])
        #expect(try ledger.repository.transactions().map(\.payeeID) == [payee.id])
        #expect(try ledger.repository.transactions().map(\.id) == [spend.id])

        // Undo again removes it again: Redo handed the payee back to the change.
        _ = try ledger.revert(redone)
        #expect(try ledger.repository.payees().isEmpty)
    }

    @Test("N3a: a new payee another transaction uses by Undo stays, and Redo uses it as it is")
    func referencedElsewhere() throws {
        let ledger = try ledger()
        let added = try ledger.save(F.expense(2_500, on: F.date(2026, 10, 21)), payee: "Trailhead Sports")
        let payee = try #require(try ledger.payee(named: "Trailhead Sports"))
        // Another window picks the same payee for its own transaction.
        _ = try ledger.save(F.expense(900, on: F.date(2026, 10, 21)), payee: "trailhead sports")

        let undone = try ledger.revert(added)
        #expect(try ledger.repository.payees().map(\.id) == [payee.id])
        #expect(try ledger.repository.transactions().count == 1)
        guard case .removed = undone else {
            Issue.record("Redo has no payee to put back: \(undone)")
            return
        }
        _ = try ledger.revert(undone)
        #expect(try ledger.repository.transactions().map(\.payeeID) == [payee.id, payee.id])
        #expect(try ledger.repository.payees().count == 1)
    }

    @Test("N3c: renamed in another window, the payee stays; Undo succeeds and Redo links to the new name")
    func renamedElsewhere() throws {
        let ledger = try ledger()
        let spend = F.expense(2_500, on: F.date(2026, 10, 21))
        let added = try ledger.save(spend, payee: "Trailhead Sports")
        var payee = try #require(try ledger.payee(named: "Trailhead Sports"))
        payee.name = "Trailhead Outdoor"
        try ledger.repository.savePayee(payee)

        let undone = try ledger.revert(added)
        #expect(try ledger.repository.transactions().isEmpty)
        #expect(try ledger.repository.payees().map(\.name) == ["Trailhead Outdoor"])

        _ = try ledger.revert(undone)
        #expect(try ledger.repository.payees().map(\.id) == [payee.id], "no second payee")
        #expect(try ledger.repository.transactions().map(\.payeeID) == [payee.id])
    }

    @Test("N7: a save with a category sets the payee's default; Undo still removes it, and Redo brings both back")
    func withCategory() throws {
        let ledger = try ledger()
        try ledger.repository.seedDefaultCategories()
        let category = try #require(try ledger.repository.categories().first { $0.kind == .expense }).id
        var spend = F.expense(2_500, on: F.date(2026, 10, 21))
        spend.categoryID = category
        let added = try ledger.save(spend, payee: "Trailhead Sports")
        #expect(try ledger.payee(named: "Trailhead Sports")?.defaultCategoryID == category)

        let undone = try ledger.revert(added)
        #expect(try ledger.repository.payees().isEmpty)
        let redone = try ledger.revert(undone)
        #expect(try ledger.payee(named: "Trailhead Sports")?.defaultCategoryID == category)
        _ = try ledger.revert(redone)
        #expect(try ledger.repository.payees().isEmpty, "Redo handed back the payee as stored after it")
    }

    @Test("N7: a payee whose default category another window changed stays on Undo")
    func defaultCategoryEditedElsewhere() throws {
        let ledger = try ledger()
        try ledger.repository.seedDefaultCategories()
        let category = try #require(try ledger.repository.categories().first { $0.kind == .expense }).id
        let added = try ledger.save(F.expense(2_500, on: F.date(2026, 10, 21)), payee: "Trailhead Sports")
        var payee = try #require(try ledger.payee(named: "Trailhead Sports"))
        payee.defaultCategoryID = category
        try ledger.repository.savePayee(payee)

        _ = try ledger.revert(added)
        #expect(try ledger.repository.transactions().isEmpty)
        #expect(try ledger.repository.payees().map(\.defaultCategoryID) == [category])
    }

    @Test("Redo puts the payee back with the same ID and name, before the transaction that uses it")
    func redoKeepsTheID() throws {
        let ledger = try ledger()
        let added = try ledger.save(F.expense(2_500, on: F.date(2026, 10, 21)), payee: "Trailhead Sports")
        let original = try #require(try ledger.payee(named: "Trailhead Sports")).id
        let undone = try ledger.revert(added)

        _ = try ledger.revert(undone)
        let payees = try ledger.repository.payees()
        #expect(payees.map(\.id) == [original])
        #expect(payees.map(\.name) == ["Trailhead Sports"])
    }

    @Test("N3d: Redo after another window typed the same name, in any case, links to that payee (D192)")
    func redoAfterSameNameElsewhere() throws {
        let ledger = try ledger()
        let added = try ledger.save(F.expense(2_500, on: F.date(2026, 10, 21)), payee: "Trailhead Sports")
        let undone = try ledger.revert(added)
        #expect(try ledger.repository.payees().isEmpty, "Undo removed the payee (N3)")
        _ = try ledger.save(F.expense(900, on: F.date(2026, 10, 21)), payee: "trailhead sports")
        let other = try #require(try ledger.repository.payees().first).id

        _ = try ledger.revert(undone)
        #expect(try ledger.repository.payees().map(\.id) == [other], "The original isn't recreated")
        #expect(try ledger.repository.payees().map(\.name) == ["trailhead sports"], "B's spelling stays")
        #expect(try ledger.repository.transactions().map(\.payeeID) == [other, other])
    }

    @Test("N3b: a bulk edit that set a new payee follows the same rule")
    func bulkEdit() throws {
        let first = F.expense(500, on: F.date(2026, 10, 20))
        let second = F.expense(700, on: F.date(2026, 10, 21))
        let ledger = try ledger([first, second])
        let resolved = try #require(
            try ledger.useCases.saveTransactions.resolvePayee(
                named: "Trailhead Sports",
                createdAt: F.date(2026, 10, 21),
            )
        )
        let edited = [first, second]
            .map { transaction in
                var transaction = transaction
                transaction.payeeID = resolved.payee.id
                return transaction
            }
        let change = try ledger.useCases.saveTransactions.save(edited, creating: [resolved.payee])

        let undone = try ledger.revert(change)
        #expect(try ledger.repository.payees().isEmpty)
        #expect(try ledger.repository.transactions().allSatisfy { $0.payeeID == nil })

        _ = try ledger.revert(undone)
        #expect(try ledger.repository.payees().map(\.id) == [resolved.payee.id])
        #expect(try ledger.repository.transactions().allSatisfy { $0.payeeID == resolved.payee.id })
    }

    @Test("A failed revert keeps the payee and the transaction: one change, all or nothing")
    func allOrNothing() throws {
        let ledger = try ledger()
        let added = try ledger.save(F.expense(2_500, on: F.date(2026, 10, 21)), payee: "Trailhead Sports")
        let writes = ledger.repository.writes
        // The transaction's delete passes; the payee's fails.
        ledger.repository.failsAfterWrites = writes + 1
        let outcome = try ledger.useCases.changes.outcome(of: added)
        #expect(throws: (any Error).self) { try ledger.useCases.changes.revert(added, expecting: outcome) }
        #expect(try ledger.repository.transactions().count == 1)
        #expect(try ledger.repository.payees().count == 1)
    }

    @Test("Only transactions reference payees today; the count skips deleted ones")
    func referenceCount() throws {
        let ledger = try ledger()
        let spend = F.expense(2_500, on: F.date(2026, 10, 21))
        _ = try ledger.save(spend, payee: "Trailhead Sports")
        let payee = try #require(try ledger.payee(named: "Trailhead Sports"))
        #expect(try ledger.repository.payeeReferenceCount(payee.id) == 1)
        try ledger.repository.deleteTransaction(id: spend.id)
        #expect(try ledger.repository.payeeReferenceCount(payee.id) == 0)
    }
}
