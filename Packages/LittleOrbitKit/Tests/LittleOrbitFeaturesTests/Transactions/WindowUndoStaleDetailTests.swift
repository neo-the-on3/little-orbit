import Foundation
import LittleOrbitDomain
import LittleOrbitFeatures
import LittleOrbitPersistence
import Testing

/// The stale-step details in D189: what a refused step leaves in the window's lists, and what the alert says
/// for a bulk step (#93, QA issue #103).
@MainActor
@Suite("Stale undo steps: Redo and bulk alerts (D189)")
struct WindowUndoStaleDetailTests {
    typealias F = TransactionFeatureFixture  // swiftlint:disable:this type_name

    @MainActor
    private struct Setup {
        let repository: InMemoryLedgerRepository
        let useCases: TransactionUseCases
        let first: TestWindow
        let second: TestWindow

        func stored(_ id: UUID) throws -> Transaction? {
            try repository.transactions().first { $0.id == id }
        }

        func edit(_ id: UUID, in window: TestWindow, _ body: (inout Transaction) -> Void) throws {
            var transaction = try #require(try stored(id))
            body(&transaction)
            window.history.record(try useCases.saveTransactions.save([transaction]))
        }

        /// A bulk edit of every stored transaction's note, from window A.
        func bulkEdit() throws {
            let edited = try repository.transactions()
                .map {
                    var transaction = $0
                    transaction.note = "Groceries"
                    return transaction
                }
            first.history.record(try useCases.saveTransactions.save(edited))
        }
    }

    private func setup(_ transactions: [Transaction]) throws -> Setup {
        let repository = try F.repository(transactions)
        let useCases = TransactionUseCases(repository: repository, categoryNames: CatalogDefaultCategoryNames())
        let updates = LedgerUpdates()
        return Setup(
            repository: repository,
            useCases: useCases,
            first: TestWindow(useCases, updates: updates),
            second: TestWindow(useCases, updates: updates),
        )
    }

    private var three: [Transaction] {
        [
            F.expense(450, on: F.date(2026, 10, 18), account: F.cardID, details: "Corner Bakery"),
            F.expense(900, on: F.date(2026, 10, 17), account: F.cardID, details: "Fuel"),
            F.expense(120, on: F.date(2026, 10, 16), account: F.cardID, details: "Tea"),
        ]
    }

    @Test("D189.1: a stale Undo removes only that step; the window's Redo stays exactly as it was")
    func staleUndoKeepsRedo() throws {
        let rows = three
        let setup = try setup(rows)
        setup.first.history.setScreen(.account(F.cardID))
        try setup.edit(rows[0].id, in: setup.first) { $0.amount = 500 }
        try setup.edit(rows[1].id, in: setup.first) { $0.amount = 950 }
        setup.first.history.undo()
        #expect(setup.first.history.redoTitle == "Edit Transaction in Rewards Card")
        try setup.edit(rows[0].id, in: setup.second) { $0.amount = 650 }

        setup.first.history.undo()
        #expect(setup.first.history.alert?.title == "Can’t Undo Edit Transaction in Rewards Card")
        #expect(!setup.first.history.canUndo)
        #expect(setup.first.history.redoTitle == "Edit Transaction in Rewards Card", "Redo untouched")
        setup.first.history.redo()
        #expect(try setup.stored(rows[1].id)?.amount == 950)
        #expect(try setup.stored(rows[0].id)?.amount == 650)
    }

    @Test("D189.1: a stale Redo removes only that step; the window's Undo stays exactly as it was")
    func staleRedoKeepsUndo() throws {
        let rows = three
        let setup = try setup(rows)
        setup.first.history.setScreen(.account(F.cardID))
        try setup.edit(rows[0].id, in: setup.first) { $0.amount = 500 }
        try setup.edit(rows[1].id, in: setup.first) { $0.amount = 950 }
        setup.first.history.undo()
        try setup.edit(rows[1].id, in: setup.second) { $0.amount = 975 }

        setup.first.history.redo()
        #expect(setup.first.history.alert?.title == "Can’t Redo Edit Transaction in Rewards Card")
        #expect(!setup.first.history.canRedo)
        #expect(setup.first.history.undoTitle == "Edit Transaction in Rewards Card", "Undo untouched")
        setup.first.history.undo()
        #expect(try setup.stored(rows[0].id)?.amount == 450)
        #expect(try setup.stored(rows[1].id)?.amount == 975)
    }

    @Test("D189.2: a bulk step with one stale record names it")
    func bulkStepOneStale() throws {
        let rows = three
        let setup = try setup(rows)
        try setup.bulkEdit()
        try setup.edit(rows[0].id, in: setup.second) { $0.note = "Birthday cake" }
        let before = try setup.repository.transactions()

        setup.first.history.undo()
        #expect(try setup.repository.transactions() == before)
        #expect(setup.first.history.alert?.title == "Can’t Undo Edit 3 Transactions in Rewards Card")
        #expect(
            setup.first.history.alert?.message == "Corner Bakery has changed since then. Nothing was changed."
        )
    }

    @Test("D189.2: a bulk step with one record changed and another deleted gives the count")
    func bulkStepChangedAndDeleted() throws {
        let rows = three
        let setup = try setup(rows)
        try setup.bulkEdit()
        try setup.edit(rows[0].id, in: setup.second) { $0.note = "Birthday cake" }
        setup.second.history.record(try setup.useCases.changes.remove(ids: [rows[2].id]))
        let before = try setup.repository.transactions()

        setup.first.history.undo()
        #expect(try setup.repository.transactions() == before)
        #expect(setup.first.history.alert?.title == "Can’t Undo Edit 3 Transactions in Rewards Card")
        #expect(
            setup.first.history.alert?.message
                == "2 of these transactions have changed or been deleted since then. Nothing was changed."
        )
        #expect(!setup.first.history.canUndo)
    }

    @Test("X12, D189.2: Undo of a bulk edit after B deletes exactly one names it")
    func bulkEditOneDeleted() throws {
        let rows = three
        let setup = try setup(rows)
        try setup.bulkEdit()
        setup.second.history.record(try setup.useCases.changes.remove(ids: [rows[1].id]))
        let before = try setup.repository.transactions()

        setup.first.history.undo()
        #expect(try setup.repository.transactions() == before)
        #expect(setup.first.history.alert?.title == "Can’t Undo Edit 3 Transactions in Rewards Card")
        #expect(setup.first.history.alert?.message == "Fuel has been deleted. Nothing was changed.")
        #expect(!setup.first.history.canUndo)
    }

    @Test("D189.2: Redo of a bulk delete with one record already deleted elsewhere names it")
    func bulkDeleteOneStale() throws {
        let rows = three
        let setup = try setup(rows)
        setup.first.history.setScreen(.account(F.cardID))
        setup.first.history.record(try setup.useCases.changes.remove(ids: rows.map(\.id)))
        setup.first.history.undo()
        setup.second.history.record(try setup.useCases.changes.remove(ids: [rows[1].id]))

        setup.first.history.redo()
        #expect(setup.first.history.alert?.title == "Can’t Redo Delete 3 Transactions in Rewards Card")
        #expect(setup.first.history.alert?.message == "Fuel has been deleted. Nothing was changed.")
        #expect(try setup.repository.transactions().count == 2)
    }
}
