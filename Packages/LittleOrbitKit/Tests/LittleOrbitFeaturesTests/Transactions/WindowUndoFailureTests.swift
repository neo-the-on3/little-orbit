import Foundation
import LittleOrbitDomain
import LittleOrbitFeatures
import LittleOrbitPersistence
import Testing

/// A failed Undo or Redo, here a full disk on the real use cases, writes nothing, and every step stays where
/// it was: the failed one, the rest of its list and the whole other list (#93 X8, X8a, D191.3). The same
/// cases on a real `UndoManager` are in `RealUndoFailureTests`.
@MainActor
@Suite("Window undo history: a failed Undo or Redo keeps every step")
struct WindowUndoFailureTests {
    typealias F = TransactionFeatureFixture  // swiftlint:disable:this type_name

    @MainActor
    struct Setup {
        let disk: FullDiskLedgerRepository
        let window: TestWindow
        let rows: [Transaction]
        var history: WindowUndoHistory { window.history }

        func transactions() throws -> [Transaction] { try disk.transactions() }
    }

    /// Three steps in one window: "Delete Transaction", "Edit Transaction", "Delete 2 Transactions".
    static func setup() throws -> Setup {
        let rows = (0..<4).map { F.expense(Decimal(100 * ($0 + 1)), on: F.date(2026, 10, 10 + $0)) }
        let disk = FullDiskLedgerRepository(try F.repository(rows))
        let useCases = TransactionUseCases(repository: disk)
        let window = TestWindow(useCases)
        window.history.setScreen(.account(F.savingsID))
        window.history.record(try useCases.changes.remove(ids: [rows[0].id]))
        var edited = rows[1]
        edited.amount = 950
        window.history.record(try useCases.saveTransactions.save([edited]))
        window.history.record(try useCases.changes.remove(ids: [rows[2].id, rows[3].id]))
        return Setup(disk: disk, window: window, rows: rows)
    }

    /// Four steps, the last one undone: Undo has "Delete Transaction", "Edit Transaction" and "Delete 2
    /// Transactions"; Redo has "Edit 2 Transactions".
    static func withRedo() throws -> Setup {
        let rows = (0..<6).map { F.expense(Decimal(100 * ($0 + 1)), on: F.date(2026, 10, 10 + $0)) }
        let disk = FullDiskLedgerRepository(try F.repository(rows))
        let useCases = TransactionUseCases(repository: disk)
        let window = TestWindow(useCases)
        window.history.setScreen(.account(F.savingsID))
        window.history.record(try useCases.changes.remove(ids: [rows[0].id]))
        var edited = rows[1]
        edited.amount = 950
        window.history.record(try useCases.saveTransactions.save([edited]))
        window.history.record(try useCases.changes.remove(ids: [rows[2].id, rows[3].id]))
        let bulk = rows[4...]
            .map { row in
                var row = row
                row.amount = 50
                return row
            }
        window.history.record(try useCases.saveTransactions.save(Array(bulk)))
        window.history.undo()
        return Setup(disk: disk, window: window, rows: rows)
    }

    static let failedMessage = "Something went wrong saving your change. Please try again."
    static let removedMessage = failedMessage + "\nThis change was removed from Undo history."

    /// Each list after a failed "Delete 2 Transactions" Undo was dropped (X8b): every other step where it was.
    static func expectDropped(_ setup: Setup, sourceLocation: SourceLocation = #_sourceLocation) throws {
        let manager = setup.window.undoManager
        #expect(
            manager.undoNames == ["Delete Transaction in Everyday Savings", "Edit Transaction in Everyday Savings"],
            sourceLocation: sourceLocation,
        )
        #expect(
            manager.redoNames == ["Edit 2 Transactions in Everyday Savings"],
            "No dead entry",
            sourceLocation: sourceLocation,
        )
        #expect(setup.history.undoTitle == "Edit Transaction in Everyday Savings", sourceLocation: sourceLocation)
        #expect(setup.history.redoTitle == "Edit 2 Transactions in Everyday Savings", sourceLocation: sourceLocation)
        #expect(setup.history.alert?.message == removedMessage, sourceLocation: sourceLocation)
    }

    @Test("X8b: a Cmd-Z queued behind a failed Undo is swallowed, even if it could succeed; the failed step goes")
    func queuedUndoSucceeds() throws {
        let setup = try Self.withRedo()
        let manager = setup.window.undoManager
        let before = try setup.transactions()
        // Two Cmd-Z presses handled before the deferred work runs.
        manager.afterAction = {}
        setup.disk.isFull = true
        manager.undo()
        setup.disk.isFull = false
        manager.undo()
        setup.window.settle()

        #expect(try setup.transactions() == before, "Edit Transaction isn't undone")
        try Self.expectDropped(setup)
        #expect(!setup.history.canUndo && !setup.history.canRedo, "Off until the alert is dismissed")
        setup.history.dismissAlert()
        #expect(setup.history.canUndo && setup.history.canRedo)
        setup.history.undo()
        #expect(try setup.transactions().first { $0.id == setup.rows[1].id }?.amount == 200)
    }

    @Test("X8b: a queued Cmd-Z that would fail too is swallowed the same way, without trying to write")
    func queuedUndoFails() throws {
        let setup = try Self.withRedo()
        let manager = setup.window.undoManager
        let before = try setup.transactions()
        manager.afterAction = {}
        setup.disk.isFull = true
        manager.undo()
        manager.undo()
        setup.window.settle()

        #expect(try setup.transactions() == before)
        #expect(setup.history.alert?.title == "Couldn't Make the Change")
        try Self.expectDropped(setup)
    }

    @Test("X8b: a Redo queued behind a failed Redo is swallowed; the failed step goes")
    func queuedRedo() throws {
        let setup = try Self.withRedo()
        let manager = setup.window.undoManager
        setup.history.undo()
        let before = try setup.transactions()
        manager.afterAction = {}
        setup.disk.isFull = true
        manager.redo()
        setup.disk.isFull = false
        manager.redo()
        setup.window.settle()

        #expect(try setup.transactions() == before, "Edit 2 Transactions isn't redone")
        try Self.expectDropped(setup)
    }

    @Test("X8b: three queued commands (failed Undo, Undo, Redo) are all swallowed, with no dead entry")
    func threeQueued() throws {
        let setup = try Self.withRedo()
        let manager = setup.window.undoManager
        let before = try setup.transactions()
        manager.afterAction = {}
        setup.disk.isFull = true
        manager.undo()
        setup.disk.isFull = false
        manager.undo()
        manager.redo()
        setup.window.settle()

        #expect(try setup.transactions() == before)
        try Self.expectDropped(setup)
    }

    @Test("X8b: four queued commands (failed Undo, Undo, Redo, Redo) are all swallowed, with no dead entry")
    func fourQueued() throws {
        let setup = try Self.withRedo()
        let manager = setup.window.undoManager
        let before = try setup.transactions()
        manager.afterAction = {}
        setup.disk.isFull = true
        manager.undo()
        setup.disk.isFull = false
        manager.undo()
        manager.redo()
        manager.redo()
        setup.window.settle()

        #expect(try setup.transactions() == before)
        try Self.expectDropped(setup)
        setup.history.dismissAlert()
        manager.redo()
        #expect(try setup.transactions().filter { $0.amount == 50 }.count == 2, "Redo is Edit 2 Transactions")
    }

    @Test("X8b: until the alert is dismissed, Cmd-Z and Redo apply nothing, and the steps stay where they were")
    func blockedUntilDismissed() throws {
        let setup = try Self.withRedo()
        let manager = setup.window.undoManager
        setup.disk.isFull = true
        manager.undo()
        setup.disk.isFull = false
        let before = try setup.transactions()
        #expect(setup.history.alert?.message == Self.failedMessage, "A single failure keeps the step (X8)")
        #expect(!setup.history.canUndo && !setup.history.canRedo)
        manager.undo()
        manager.redo()
        manager.redo()
        setup.history.undo()
        #expect(try setup.transactions() == before)
        #expect(
            manager.undoNames == [
                "Delete Transaction in Everyday Savings", "Edit Transaction in Everyday Savings",
                "Delete 2 Transactions in Everyday Savings",
            ]
        )
        #expect(manager.redoNames == ["Edit 2 Transactions in Everyday Savings"])
        #expect(setup.history.alert?.message == Self.failedMessage, "Nothing was dropped")
        setup.history.dismissAlert()
        manager.undo()
        #expect(try setup.transactions().count == 5, "Delete 2 Transactions is undone")
    }

    @Test("X8b: dismissed before the deferred work runs, the block lasts until it has, and the step is back")
    func dismissedEarly() throws {
        let setup = try Self.withRedo()
        let manager = setup.window.undoManager
        manager.afterAction = {}
        setup.disk.isFull = true
        manager.undo()
        setup.disk.isFull = false
        let before = try setup.transactions()
        setup.history.dismissAlert()
        #expect(!setup.history.canUndo && !setup.history.canRedo, "Still blocked: the stand-in isn't back")
        setup.history.undo()
        #expect(try setup.transactions() == before)

        setup.window.settle()
        #expect(setup.history.canUndo && setup.history.canRedo)
        #expect(setup.history.alert == nil)
        #expect(
            manager.undoNames == [
                "Delete Transaction in Everyday Savings", "Edit Transaction in Everyday Savings",
                "Delete 2 Transactions in Everyday Savings",
            ]
        )
        #expect(manager.redoNames == ["Edit 2 Transactions in Everyday Savings"])
    }

    @Test("X8b: a Cmd-Z after an early dismissal is still swallowed, and no alert comes back")
    func dismissedEarlyThenQueued() throws {
        let setup = try Self.withRedo()
        let manager = setup.window.undoManager
        let before = try setup.transactions()
        manager.afterAction = {}
        setup.disk.isFull = true
        manager.undo()
        setup.disk.isFull = false
        setup.history.dismissAlert()
        manager.undo()
        setup.window.settle()

        #expect(try setup.transactions() == before, "Edit Transaction isn't undone")
        #expect(setup.history.alert == nil, "The dismissed alert isn't shown again")
        #expect(
            manager.undoNames == ["Delete Transaction in Everyday Savings", "Edit Transaction in Everyday Savings"]
        )
        #expect(manager.redoNames == ["Edit 2 Transactions in Everyday Savings"], "No dead entry")
        #expect(setup.history.canUndo && setup.history.canRedo)
    }

    @Test("Typing in a field before the failed step is back: the stand-in goes, the typing isn't redone")
    func typingInTheGap() throws {
        let setup = try Self.withRedo()
        let manager = setup.window.undoManager
        manager.afterAction = {}
        setup.disk.isFull = true
        manager.undo()
        manager.registerTyping()
        setup.window.settle()
        #expect(
            manager.undoNames == [
                "Delete Transaction in Everyday Savings", "Edit Transaction in Everyday Savings", "Typing",
            ]
        )
        #expect(manager.redoNames.isEmpty, "Typing clears Redo, as on the real UndoManager")
        // Spot check (c): the alert says the failed step is gone.
        #expect(setup.history.alert?.title == "Couldn't Make the Change")
        #expect(setup.history.alert?.message == Self.removedMessage)
        #expect(setup.history.alert?.message.hasSuffix("This change was removed from Undo history.") == true)
    }

    @Test("X8: a failed Undo keeps the step as the next Undo, the Undo below it and the Redo step")
    func failedUndo() throws {
        let setup = try Self.setup()
        setup.history.undo()
        #expect(setup.history.redoTitle == "Delete 2 Transactions in Everyday Savings")
        let before = try setup.transactions()

        setup.disk.isFull = true
        setup.history.undo()
        #expect(setup.history.alert?.title == "Couldn't Make the Change")
        #expect(try setup.transactions() == before, "Nothing changed or half changed")
        #expect(setup.history.undoTitle == "Edit Transaction in Everyday Savings")
        #expect(setup.history.redoTitle == "Delete 2 Transactions in Everyday Savings")
        #expect(setup.window.undoManager.undoCount == 2)

        setup.disk.isFull = false
        setup.history.dismissAlert()
        setup.history.undo()
        #expect(try setup.transactions().first { $0.id == setup.rows[1].id }?.amount == 200)
        #expect(setup.history.redoTitle == "Edit Transaction in Everyday Savings")
        setup.history.redo()
        setup.history.redo()
        #expect(try setup.transactions().map(\.id) == [setup.rows[1].id])
        #expect(try setup.transactions().first?.amount == 950)
        #expect(setup.history.alert == nil)
        #expect(setup.history.undoTitle == "Delete 2 Transactions in Everyday Savings")
    }

    @Test("X8a: a failed Redo keeps it, the later Redo step behind it and the whole Undo list")
    func failedRedo() throws {
        let setup = try Self.setup()
        setup.history.undo()
        setup.history.undo()
        #expect(setup.history.redoTitle == "Edit Transaction in Everyday Savings")
        let before = try setup.transactions()

        setup.disk.isFull = true
        setup.history.redo()
        #expect(setup.history.alert?.title == "Couldn't Make the Change")
        #expect(try setup.transactions() == before)
        #expect(setup.history.redoTitle == "Edit Transaction in Everyday Savings")
        #expect(setup.history.undoTitle == "Delete Transaction in Everyday Savings")
        #expect(setup.window.undoManager.undoCount == 1)

        setup.disk.isFull = false
        setup.history.dismissAlert()
        setup.history.redo()
        #expect(try setup.transactions().first { $0.id == setup.rows[1].id }?.amount == 950)
        #expect(
            setup.history.redoTitle == "Delete 2 Transactions in Everyday Savings",
            "The later Redo step is still there",
        )
        setup.history.redo()
        #expect(try setup.transactions().map(\.id) == [setup.rows[1].id])
        setup.history.undo()
        setup.history.undo()
        setup.history.undo()
        #expect(try setup.transactions().count == 4)
        #expect(!setup.history.canUndo)
        #expect(setup.history.alert == nil)
    }

    @Test("A stale step is still removed, and the other list is left as it was (D189.1)")
    func staleStepStillGoes() throws {
        let setup = try Self.setup()
        setup.history.undo()
        // Another window edits the transaction the "Edit Transaction" step changed.
        var other = try #require(try setup.transactions().first { $0.id == setup.rows[1].id })
        other.amount = 777
        try setup.disk.saveTransaction(other)

        setup.history.undo()
        #expect(setup.history.alert?.title == "Can't Undo Edit Transaction in Everyday Savings")
        #expect(setup.history.undoTitle == "Delete Transaction in Everyday Savings")
        #expect(setup.history.redoTitle == "Delete 2 Transactions in Everyday Savings")
    }
}
