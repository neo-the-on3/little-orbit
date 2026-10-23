import Foundation
import LittleOrbitDomain
import LittleOrbitFeatures
import LittleOrbitPersistence
import Testing

/// Two windows, each with its own history, over the one shared store (#93 W1–W10 and X1–X10, D187). A step
/// whose records another window changed since is stale: Undo or Redo changes nothing, says why, and drops it.
@MainActor
@Suite("Two windows, two undo histories")
struct WindowUndoTwoWindowTests {
    typealias F = TransactionFeatureFixture  // swiftlint:disable:this type_name

    @MainActor
    private struct Setup {
        let repository: InMemoryLedgerRepository
        let useCases: TransactionUseCases
        let updates: LedgerUpdates
        /// Windows A and B.
        let first: TestWindow
        let second: TestWindow

        func stored(_ id: UUID) throws -> Transaction? {
            try repository.transactions().first { $0.id == id }
        }

        /// An edit saved from `window`, as the entry sheet does.
        func edit(_ id: UUID, in window: TestWindow, _ body: (inout Transaction) -> Void) throws {
            var transaction = try #require(try stored(id))
            body(&transaction)
            window.history.record(try useCases.saveTransactions.save([transaction]))
        }

        func delete(_ ids: [UUID], in window: TestWindow) throws -> UUID {
            window.history.record(try useCases.changes.remove(ids: ids))
        }
    }

    private func setup(_ transactions: [Transaction] = []) throws -> Setup {
        let repository = try F.repository(transactions)
        let useCases = TransactionUseCases(repository: repository)
        let updates = LedgerUpdates()
        return Setup(
            repository: repository,
            useCases: useCases,
            updates: updates,
            first: TestWindow(useCases, updates: updates),
            second: TestWindow(useCases, updates: updates),
        )
    }

    private var bakery: Transaction {
        F.expense(450, on: F.date(2026, 10, 18), account: F.cardID, details: "Corner Bakery")
    }

    // MARK: - One history per window (W1–W10)

    @Test("W1, W3: a delete in A is only in A's Undo; each window's Undo moves only its own history")
    func twoWindows() throws {
        let corner = bakery
        let fuel = F.expense(900, on: F.date(2026, 10, 18))
        let setup = try setup([corner, fuel])
        setup.first.history.setScreen(.account(F.cardID))
        setup.second.history.setScreen(.account(F.savingsID))
        _ = try setup.delete([corner.id], in: setup.first)
        #expect(setup.first.history.undoTitle == "Delete Transaction in Rewards Card")
        #expect(!setup.second.history.canUndo, "B has no change of its own")

        try setup.edit(fuel.id, in: setup.second) { $0.amount = 950 }
        #expect(setup.second.history.undoTitle == "Edit Transaction in Everyday Savings")
        setup.second.history.undo()
        #expect(try setup.stored(fuel.id)?.amount == 900)
        #expect(try setup.stored(corner.id) == nil, "A's delete is untouched")
        #expect(setup.first.history.undoTitle == "Delete Transaction in Rewards Card")
        #expect(!setup.first.history.canRedo)
        setup.first.history.undo()
        #expect(try setup.stored(corner.id) != nil)
        #expect(setup.second.history.redoTitle == "Edit Transaction in Everyday Savings")
    }

    @Test("W6: the name says where the change happened, in every window and on every screen (D198)")
    func namesPerWindow() throws {
        let corner = bakery
        let setup = try setup([corner])
        setup.first.history.setScreen(.account(F.savingsID))
        setup.second.history.setScreen(.account(F.cardID))
        _ = try setup.delete([corner.id], in: setup.second)
        #expect(setup.second.history.undoTitle == "Delete Transaction in Rewards Card")
        setup.second.history.setScreen(.account(F.savingsID))
        #expect(setup.second.history.undoTitle == "Delete Transaction in Rewards Card")
        #expect(setup.second.undoManager.undoActionName == "Delete Transaction in Rewards Card", "The Edit menu too")
        #expect(!setup.first.history.canUndo)
    }

    @Test("W7: every change, Undo and Redo in one window tells every window to reload")
    func liveData() throws {
        let corner = bakery
        let setup = try setup([corner])
        let start = setup.updates.revision
        _ = try setup.delete([corner.id], in: setup.first)
        setup.first.history.undo()
        setup.first.history.redo()
        #expect(setup.updates.revision == start + 3)
    }

    @Test("W8, W9: a closed window's history goes with it; a new window starts empty")
    func windowLifetime() throws {
        let corner = bakery
        let fuel = F.expense(900, on: F.date(2026, 10, 18))
        let setup = try setup([corner, fuel])
        var closing: TestWindow? = TestWindow(setup.useCases, updates: setup.updates)
        weak let closed = closing?.history
        _ = try setup.delete([corner.id], in: try #require(closing))
        _ = try setup.delete([fuel.id], in: setup.first)
        closing = nil
        #expect(closed == nil)
        #expect(setup.first.history.undoTitle == "Delete Transaction in Everyday Savings")
        #expect(!TestWindow(setup.useCases).history.canUndo)
        #expect(!TestWindow(setup.useCases).history.canRedo)
    }

    @Test("W10: a change made outside any window isn't in any window's Undo")
    func outsideAnyWindow() throws {
        let setup = try setup([])
        _ = try setup.useCases.saveTransactions.save([bakery])
        #expect(!setup.first.history.canUndo)
        #expect(!setup.second.history.canUndo)
    }

    // MARK: - Stale steps (X1–X10)

    @Test("X1, X10: A edits, B edits again; A's Undo keeps its name, changes nothing, says why, and is gone")
    func editedInAnotherWindow() throws {
        let corner = bakery
        let tea = F.expense(20, on: F.date(2026, 10, 18))
        let setup = try setup([corner, tea])
        setup.first.history.setScreen(.account(F.cardID))
        _ = try setup.delete([tea.id], in: setup.first)
        try setup.edit(corner.id, in: setup.first) { $0.amount = 500 }
        try setup.edit(corner.id, in: setup.second) { $0.amount = 650 }

        #expect(setup.first.history.undoTitle == "Edit Transaction in Rewards Card", "Not hidden ahead of time")
        let start = setup.updates.revision
        setup.first.history.undo()
        #expect(try setup.stored(corner.id)?.amount == 650)
        #expect(setup.first.history.alert?.title == "Can’t Undo Edit Transaction in Rewards Card")
        #expect(
            setup.first.history.alert?.message == "Corner Bakery has changed since then. Nothing was changed."
        )
        #expect(setup.first.history.undoTitle == "Delete Transaction in Everyday Savings", "The step below is next")
        #expect(!setup.first.history.canRedo)
        #expect(setup.updates.revision == start, "Nothing was written")
        #expect(setup.second.history.undoTitle == "Edit Transaction in Rewards Card", "B's own step is fine")
    }

    @Test("X2: A edits, B deletes; A's Undo doesn't bring it back")
    func deletedInAnotherWindow() throws {
        let corner = bakery
        let setup = try setup([corner])
        try setup.edit(corner.id, in: setup.first) { $0.amount = 500 }
        _ = try setup.delete([corner.id], in: setup.second)
        setup.first.history.undo()
        #expect(try setup.stored(corner.id) == nil)
        #expect(
            setup.first.history.alert?.message == "Corner Bakery has been deleted. Nothing was changed."
        )
        #expect(!setup.first.history.canUndo)
    }

    @Test("X3: A adds, B edits; A's Undo doesn't delete it")
    func addThenEditedElsewhere() throws {
        let corner = bakery
        let setup = try setup([])
        setup.first.history.record(try setup.useCases.saveTransactions.save([corner]))
        try setup.edit(corner.id, in: setup.second) { $0.note = "Birthday cake" }
        setup.first.history.undo()
        #expect(try setup.stored(corner.id)?.note == "Birthday cake")
        #expect(setup.first.history.alert?.title == "Can’t Undo New Transaction in Rewards Card")
        #expect(
            setup.first.history.alert?.message == "Corner Bakery has changed since then. Nothing was changed."
        )
    }

    @Test("X4, D187.9: A deletes a transaction, B deletes its account; A restores nothing into a missing account")
    func accountDeletedInAnotherWindow() throws {
        let corner = bakery
        let setup = try setup([corner])
        setup.first.history.setScreen(.account(F.cardID))
        _ = try setup.delete([corner.id], in: setup.first)
        setup.second.history.record(try WindowUndoHistoryTests.deleteAccount(setup.repository, F.cardID))
        #expect(setup.first.history.undoTitle == "Delete Transaction in Rewards Card", "Only B's steps collapse")

        setup.first.history.undo()
        #expect(try setup.repository.transactions().isEmpty)
        #expect(!(try setup.repository.accounts().contains { $0.id == F.cardID }))
        #expect(setup.first.history.alert?.title == "Can’t Undo Delete Transaction in Rewards Card")
        #expect(
            setup.first.history.alert?.message == "Rewards Card has been deleted. Nothing was changed."
        )
        #expect(setup.second.history.undoTitle == "Delete Account Rewards Card")
    }

    @Test("X5: A bulk-edits 5, B edits 2; A's Undo changes none of the 5")
    func bulkEditAllOrNothing() throws {
        let five = (1...5).map { F.expense(Decimal($0 * 10), on: F.date(2026, 10, $0)) }
        let setup = try setup(five)
        setup.first.history.setScreen(.account(F.savingsID))
        let edited = try setup.repository.transactions()
            .map {
                var transaction = $0
                transaction.note = "Groceries"
                return transaction
            }
        setup.first.history.record(try setup.useCases.saveTransactions.save(edited))
        try setup.edit(five[0].id, in: setup.second) { $0.note = "Rent" }
        try setup.edit(five[2].id, in: setup.second) { $0.note = "Fuel" }
        let before = try setup.repository.transactions()

        setup.first.history.undo()
        #expect(try setup.repository.transactions() == before)
        #expect(setup.first.history.alert?.title == "Can’t Undo Edit 5 Transactions in Everyday Savings")
        #expect(
            setup.first.history.alert?.message
                == "2 of these transactions have changed or been deleted since then. Nothing was changed."
        )
    }

    @Test("X6: A undoes a delete, B edits the restored row; A's Redo deletes nothing")
    func redoAfterEditElsewhere() throws {
        let corner = bakery
        let setup = try setup([corner])
        setup.first.history.setScreen(.account(F.cardID))
        _ = try setup.delete([corner.id], in: setup.first)
        setup.first.history.undo()
        try setup.edit(corner.id, in: setup.second) { $0.amount = 475 }

        #expect(setup.first.history.redoTitle == "Delete Transaction in Rewards Card")
        setup.first.history.redo()
        #expect(try setup.stored(corner.id)?.amount == 475)
        #expect(setup.first.history.alert?.title == "Can’t Redo Delete Transaction in Rewards Card")
        #expect(
            setup.first.history.alert?.message == "Corner Bakery has changed since then. Nothing was changed."
        )
        #expect(!setup.first.history.canRedo)
    }

    @Test("D228.1: a change made on the store, with no window, makes A's Undo stale with the same message")
    func changedOutsideAnyWindow() throws {
        let corner = bakery
        let setup = try setup([corner])
        setup.first.history.setScreen(.account(F.cardID))
        try setup.edit(corner.id, in: setup.first) { $0.amount = 500 }
        var changed = try #require(try setup.stored(corner.id))
        changed.amount = 650
        try setup.repository.saveTransaction(changed)

        setup.first.history.undo()
        #expect(try setup.stored(corner.id)?.amount == 650, "Nothing was changed")
        #expect(setup.first.history.alert?.title == "Can’t Undo Edit Transaction in Rewards Card")
        let message = try #require(setup.first.history.alert?.message)
        #expect(message == "Corner Bakery has changed since then. Nothing was changed.")
        #expect(!message.contains("window"))
        #expect(!setup.first.history.canUndo, "The step is removed")
    }

    @Test("X4a, D203: A deletes in Household Card, B renames it Home Card and deletes it; A's alert keeps the name")
    func accountRenamedThenDeletedElsewhere() throws {
        let bluebird = F.expense(1_200, on: F.date(2026, 10, 18), account: F.cardID, details: "Bluebird Hardware")
        let setup = try setup([bluebird])
        var card = try #require(try setup.repository.accounts().first { $0.id == F.cardID })
        card.name = "Household Card"
        try setup.repository.saveAccount(card)
        setup.first.history.setScreen(.account(F.cardID))
        _ = try setup.delete([bluebird.id], in: setup.first)
        card.name = "Home Card"
        try setup.repository.saveAccount(card)
        setup.second.history.record(try WindowUndoHistoryTests.deleteAccount(setup.repository, F.cardID))

        setup.first.history.undo()
        #expect(try setup.repository.transactions().isEmpty, "Nothing is restored into a missing account")
        #expect(setup.first.history.alert?.title == "Can’t Undo Delete Transaction in Household Card")
        #expect(
            setup.first.history.alert?.message == "Household Card has been deleted. Nothing was changed."
        )
        #expect(!setup.first.history.canUndo, "The step is removed")
    }

    @Test("D228.4: an unnamed transfer that changed since reads “The transfer has changed since then.”")
    func unnamedTransferChanged() throws {
        let transfer = F.transfer(2_000, on: F.date(2026, 10, 18))
        let setup = try setup([transfer])
        try setup.edit(transfer.id, in: setup.first) { $0.amount = 2_500 }
        try setup.edit(transfer.id, in: setup.second) { $0.amount = 3_000 }

        setup.first.history.undo()
        #expect(try setup.stored(transfer.id)?.amount == 3_000)
        #expect(setup.first.history.alert?.message == "The transfer has changed since then. Nothing was changed.")
    }

    @Test("D228.4: an unnamed transaction deleted since reads “The transaction has been deleted.”")
    func unnamedTransactionDeleted() throws {
        let unnamed = F.expense(300, on: F.date(2026, 10, 18))
        let setup = try setup([unnamed])
        try setup.edit(unnamed.id, in: setup.first) { $0.amount = 350 }
        _ = try setup.delete([unnamed.id], in: setup.second)

        setup.first.history.undo()
        #expect(try setup.stored(unnamed.id) == nil)
        #expect(
            setup.first.history.alert?.message == "The transaction has been deleted. Nothing was changed."
        )
    }

    @Test("D228.4: a deleted account the step couldn't name reads “The account has been deleted.”")
    func unnamedAccountDeleted() throws {
        let corner = bakery
        let setup = try setup([corner])
        // The step's accounts couldn't be read when it was recorded, so it has no account name to give.
        let unreadable = TransactionUseCases(
            loadLedger: setup.useCases.loadLedger,
            accountHistory: setup.useCases.accountHistory,
            saveTransactions: setup.useCases.saveTransactions,
            changes: UnreadablePlaceChanges(base: setup.useCases.changes),
            duplicate: setup.useCases.duplicate,
            splits: setup.useCases.splits,
        )
        let window = TestWindow(unreadable, updates: setup.updates)
        _ = try setup.delete([corner.id], in: window)
        window.history.dismissAlert()
        setup.second.history.record(try WindowUndoHistoryTests.deleteAccount(setup.repository, F.cardID))

        window.history.undo()
        #expect(try setup.repository.transactions().isEmpty)
        #expect(window.history.alert?.message == "The account has been deleted. Nothing was changed.")
        #expect(!window.history.canUndo)
    }

    @Test("X7: B edits and undoes its edit; the values match what A left, so A's Undo works")
    func otherWindowUndidItsChange() throws {
        let corner = bakery
        let setup = try setup([corner])
        try setup.edit(corner.id, in: setup.first) { $0.amount = 500 }
        try setup.edit(corner.id, in: setup.second) { $0.amount = 650 }
        setup.second.history.undo()
        setup.first.history.undo()
        #expect(setup.first.history.alert == nil)
        #expect(try setup.stored(corner.id)?.amount == 450)
        #expect(setup.first.history.redoTitle == "Edit Transaction in Rewards Card")
    }

    @Test("Another window's change to a field A didn't touch keeps A's Undo working, and keeps that value")
    func untouchedField() throws {
        let corner = bakery
        let setup = try setup([corner])
        try setup.edit(corner.id, in: setup.first) { $0.amount = 500 }
        try setup.edit(corner.id, in: setup.second) { $0.note = "Birthday cake" }
        setup.first.history.undo()
        #expect(setup.first.history.alert == nil)
        #expect(try setup.stored(corner.id)?.amount == 450)
        #expect(try setup.stored(corner.id)?.note == "Birthday cake")
    }

    @Test("X9: A's delete toast, then B deletes the account; the toast's Undo says why, closes and changes nothing")
    func toastAfterAccountDeletedElsewhere() throws {
        let corner = bakery
        let setup = try setup([corner])
        setup.first.history.setScreen(.account(F.cardID))
        let step = try setup.delete([corner.id], in: setup.first)
        setup.first.history.showToast("Deleted Corner Bakery −₹450.00", for: step)
        setup.second.history.record(try WindowUndoHistoryTests.deleteAccount(setup.repository, F.cardID))

        setup.first.history.undoToast()
        #expect(setup.first.history.toast == nil)
        #expect(
            setup.first.history.alert?.message == "Rewards Card has been deleted. Nothing was changed."
        )
        #expect(try setup.repository.transactions().isEmpty)
        #expect(setup.first.announcements.isEmpty)
    }

    // MARK: - D228.4: the account or the transaction

    @Test("D228.4: B adds a transaction to an account A's Redo would delete again; the message names the account")
    func redoAccountDeleteNamesAccount() throws {
        let setup = try setup([bakery])
        setup.first.history.record(
            .removedAccount(try AccountUseCases(repository: setup.repository).deleteAccount.delete(F.cardID))
        )
        setup.first.history.undo()
        let added = F.expense(120, on: F.date(2026, 10, 19), account: F.cardID, details: "Pebble Market")
        setup.second.history.record(try setup.useCases.saveTransactions.save([added]))
        let before = try setup.repository.transactions()

        setup.first.history.redo()
        #expect(setup.first.history.alert?.title == "Can’t Redo Delete Account Rewards Card")
        #expect(setup.first.history.alert?.message == "Rewards Card has changed since then. Nothing was changed.")
        #expect(try setup.repository.transactions() == before)
        #expect(!setup.first.history.canRedo)
    }

    @Test("D228.4: B changes a transaction A's account-delete Redo holds; the message names the transaction")
    func redoAccountDeleteNamesChangedTransaction() throws {
        let corner = bakery
        let setup = try setup([corner])
        setup.first.history.record(
            .removedAccount(try AccountUseCases(repository: setup.repository).deleteAccount.delete(F.cardID))
        )
        setup.first.history.undo()
        try setup.edit(corner.id, in: setup.second) { $0.amount = 500 }

        setup.first.history.redo()
        #expect(setup.first.history.alert?.title == "Can’t Redo Delete Account Rewards Card")
        #expect(setup.first.history.alert?.message == "Corner Bakery has changed since then. Nothing was changed.")
        #expect(!setup.first.history.canRedo)
    }
}

/// After a backup restore replaces the ledger (#40, #99), no window can undo a step made against the old data.
@MainActor
@Suite("Undo after the ledger is replaced")
struct LedgerReplacedUndoTests {
    typealias F = TransactionFeatureFixture  // swiftlint:disable:this type_name

    @Test("ledgerReplaced() clears every window's Undo and Redo and reloads every window")
    func restoreClearsEveryWindow() throws {
        let lunch = F.expense(250, on: F.date(2026, 10, 18))
        let tea = F.expense(20, on: F.date(2026, 10, 18))
        let repository = try F.repository([lunch, tea])
        let useCases = TransactionUseCases(repository: repository)
        let updates = LedgerUpdates()
        let first = TestWindow(useCases, updates: updates)
        let second = TestWindow(useCases, updates: updates)
        first.history.record(try useCases.changes.remove(ids: [lunch.id]))
        second.history.record(try useCases.changes.remove(ids: [tea.id]))
        second.history.undo()
        let revision = updates.revision

        updates.ledgerReplaced()
        #expect(!first.history.canUndo && !first.history.canRedo)
        #expect(!second.history.canUndo && !second.history.canRedo)
        #expect(updates.revision == revision + 1)
    }
}

/// The real changes use case, except that the accounts a change touches can't be read when it's recorded.
@MainActor
private struct UnreadablePlaceChanges: TransactionChangesUseCase {
    struct Failure: Error {}

    let base: any TransactionChangesUseCase

    func remove(ids: [UUID]) throws -> TransactionChange { try base.remove(ids: ids) }

    func outcome(of change: TransactionChange) throws -> ChangeOutcome { try base.outcome(of: change) }

    func check(_ change: TransactionChange, expecting outcome: ChangeOutcome) throws -> ChangeCheck {
        try base.check(change, expecting: outcome)
    }

    func revert(_ change: TransactionChange, expecting outcome: ChangeOutcome) throws -> RevertResult {
        try base.revert(change, expecting: outcome)
    }

    func impact(of _: TransactionChange) throws -> ChangeImpact { throw Failure() }
}
