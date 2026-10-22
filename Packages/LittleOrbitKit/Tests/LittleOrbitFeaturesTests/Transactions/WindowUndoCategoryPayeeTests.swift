import Foundation
import LittleOrbitDomain
import LittleOrbitFeatures
import LittleOrbitPersistence
import Testing

/// A transaction's category and payee are fields like any other in the stale check (D187.5): if window B
/// changes one that window A's step changed, A's Undo is stale and writes nothing. The category and payee
/// records themselves (their names, a merge) aren't checked: no undo step edits them, and a payee a step
/// created goes on Undo only if nothing uses it and no one renamed it, silently otherwise (D191.4).
@MainActor
@Suite("Stale undo steps: a transaction's category and payee")
struct WindowUndoCategoryPayeeTests {
    typealias F = TransactionFeatureFixture  // swiftlint:disable:this type_name

    @MainActor
    private struct Setup {
        let repository: InMemoryLedgerRepository
        let useCases: TransactionUseCases
        let updates: LedgerUpdates
        let first: TestWindow
        let second: TestWindow
        let categories: [UUID]

        func edit(_ ids: [UUID], in window: TestWindow, _ body: (inout Transaction) -> Void) throws {
            let edited = try repository.transactions()
                .filter { ids.contains($0.id) }
                .map {
                    var transaction = $0
                    body(&transaction)
                    return transaction
                }
            window.history.record(try useCases.saveTransactions.save(edited))
        }
    }

    private func setup(_ transactions: [Transaction]) throws -> Setup {
        let repository = try F.repository(transactions)
        let useCases = TransactionUseCases(repository: repository)
        let updates = LedgerUpdates()
        let categories = try repository.categories().filter { $0.kind == .expense }.map(\.id)
        let setup = Setup(
            repository: repository,
            useCases: useCases,
            updates: updates,
            first: TestWindow(useCases, updates: updates),
            second: TestWindow(useCases, updates: updates),
            categories: categories,
        )
        setup.first.history.setScreen(.account(F.savingsID))
        return setup
    }

    /// Saves a new transaction with a typed payee name in `window`, as the form does.
    private func add(_ transaction: Transaction, payee name: String, in window: TestWindow, _ setup: Setup) throws {
        let resolved = try #require(
            try setup.useCases.saveTransactions.resolvePayee(named: name, createdAt: F.date(2026, 10, 21))
        )
        var transaction = transaction
        transaction.payeeID = resolved.payee.id
        let created = resolved.isNew ? [resolved.payee] : []
        window.history.record(try setup.useCases.saveTransactions.save([transaction], creating: created))
    }

    @Test("N3: A's Undo of a new transaction removes its new payee; Redo brings both back, same IDs")
    func newPayeeUndoAndRedo() throws {
        let setup = try setup([])
        let spend = F.expense(2_500, on: F.date(2026, 10, 21))
        try add(spend, payee: "Trailhead Sports", in: setup.first, setup)
        let payee = try #require(try setup.repository.payees().first { $0.name == "Trailhead Sports" })
        #expect(setup.first.history.undoTitle == "New Transaction in Everyday Savings")

        setup.first.history.undo()
        #expect(setup.first.history.alert == nil)
        #expect(try setup.repository.transactions().isEmpty)
        #expect(try !setup.repository.payees().contains { $0.id == payee.id })

        setup.first.history.redo()
        #expect(try setup.repository.payees().filter { $0.name == "Trailhead Sports" }.map(\.id) == [payee.id])
        #expect(try setup.repository.transactions().map(\.payeeID) == [payee.id])
    }

    @Test("N3c: B renames A's new payee; A's Undo has no alert and keeps it, Redo links to the new name")
    func newPayeeRenamedElsewhere() throws {
        let setup = try setup([])
        try add(F.expense(2_500, on: F.date(2026, 10, 21)), payee: "Trailhead Sports", in: setup.first, setup)
        var payee = try #require(try setup.repository.payees().first { $0.name == "Trailhead Sports" })
        payee.name = "Trailhead Outdoor"
        try setup.repository.savePayee(payee)
        let count = try setup.repository.payees().count

        setup.first.history.undo()
        #expect(setup.first.history.alert == nil)
        #expect(try setup.repository.transactions().isEmpty)
        #expect(try setup.repository.payees().first { $0.id == payee.id }?.name == "Trailhead Outdoor")

        setup.first.history.redo()
        #expect(setup.first.history.alert == nil)
        #expect(try setup.repository.payees().count == count, "no second payee")
        #expect(try setup.repository.transactions().map(\.payeeID) == [payee.id])
    }

    @Test("N3a: B uses A's new payee too; A's Undo keeps it")
    func newPayeeUsedElsewhere() throws {
        let setup = try setup([])
        try add(F.expense(2_500, on: F.date(2026, 10, 21)), payee: "Trailhead Sports", in: setup.first, setup)
        try add(F.expense(900, on: F.date(2026, 10, 21)), payee: "Trailhead Sports", in: setup.second, setup)
        let payee = try #require(try setup.repository.payees().first { $0.name == "Trailhead Sports" })

        setup.first.history.undo()
        #expect(setup.first.history.alert == nil)
        #expect(try setup.repository.transactions().map(\.payeeID) == [payee.id])
        #expect(try setup.repository.payees().contains { $0.id == payee.id })
    }

    private var three: [Transaction] {
        [
            F.expense(450, on: F.date(2026, 10, 18), details: "Corner Bakery"),
            F.expense(900, on: F.date(2026, 10, 17), details: "Fuel"),
            F.expense(120, on: F.date(2026, 10, 16), details: "Tea"),
        ]
    }

    @Test("A bulk-edits the category of 3, B changes one's category; A's Undo is stale and writes nothing")
    func bulkCategoryChangedElsewhere() throws {
        let rows = three
        let setup = try setup(rows)
        try #require(setup.categories.count >= 2)
        try setup.edit(rows.map(\.id), in: setup.first) { $0.categoryID = setup.categories[0] }
        try setup.edit([rows[0].id], in: setup.second) { $0.categoryID = setup.categories[1] }
        let before = try setup.repository.transactions()
        let revision = setup.updates.revision

        setup.first.history.undo()
        #expect(setup.first.history.alert?.title == "Can't Undo Edit 3 Transactions in Everyday Savings")
        #expect(
            setup.first.history.alert?.message == "Corner Bakery was changed in another window. Nothing was changed."
        )
        #expect(try setup.repository.transactions() == before, "Nothing written")
        #expect(setup.updates.revision == revision)
        #expect(!setup.first.history.canUndo)
    }

    @Test("A sets a payee, B changes it; A's Undo is stale and B's payee stays")
    func payeeChangedElsewhere() throws {
        let rows = three
        let setup = try setup(rows)
        let maple = Payee(name: "Maple Noodle Bar")
        let pebble = Payee(name: "Pebble Market")
        try setup.repository.savePayee(maple)
        try setup.repository.savePayee(pebble)
        try setup.edit([rows[1].id], in: setup.first) { $0.payeeID = maple.id }
        try setup.edit([rows[1].id], in: setup.second) { $0.payeeID = pebble.id }
        let before = try setup.repository.transactions()

        setup.first.history.undo()
        #expect(setup.first.history.alert?.title == "Can't Undo Edit Transaction in Everyday Savings")
        #expect(
            setup.first.history.alert?.message
                == "Maple Noodle Bar was changed in another window. Nothing was changed."
        )
        #expect(try setup.repository.transactions() == before)
        #expect(try setup.repository.transactions().first { $0.id == rows[1].id }?.payeeID == pebble.id)
    }

    @Test("A edits an amount, B changes the category; A's Undo works and keeps B's category")
    func categoryNotTouchedByTheStep() throws {
        let rows = three
        let setup = try setup(rows)
        try #require(!setup.categories.isEmpty)
        try setup.edit([rows[0].id], in: setup.first) { $0.amount = 500 }
        try setup.edit([rows[0].id], in: setup.second) { $0.categoryID = setup.categories[0] }

        setup.first.history.undo()
        #expect(setup.first.history.alert == nil)
        let stored = try #require(try setup.repository.transactions().first { $0.id == rows[0].id })
        #expect(stored.amount == 450)
        #expect(stored.categoryID == setup.categories[0])
    }
}
