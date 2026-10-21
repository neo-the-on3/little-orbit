#if canImport(SwiftUI) && os(macOS)
    import Foundation
    import LittleOrbitDomain
    import LittleOrbitFeatures
    import LittleOrbitPersistence
    import Testing

    /// X8, X8a and X8b on a real `UndoManager` with the system's settings: a full disk on the real use cases
    /// makes the Undo or Redo fail, and every step on both lists stays where it was, unless a queued command
    /// drops the failed one (#93, D191.3, D193). Runs in the macOS CI job; `WindowUndoFailureTests` has the
    /// same cases on the stand-in.
    @MainActor
    @Suite("A failed Undo or Redo on a real UndoManager", .serialized)
    struct RealUndoFailureTests {
        typealias F = TransactionFeatureFixture  // swiftlint:disable:this type_name

        @MainActor
        struct Setup {
            let disk: FullDiskLedgerRepository
            let window: RealWindow
            let rows: [Transaction]
            var manager: UndoManager { window.undoManager }

            func transactions() throws -> [Transaction] { try disk.transactions() }

            func amount(of index: Int) throws -> Decimal? {
                try transactions().first { $0.id == rows[index].id }?.amount
            }
        }

        /// Three steps, each in its own event: "Delete Transaction", "Edit Transaction", "Delete 2 Transactions".
        private func setup() throws -> Setup {
            let rows = (0..<4).map { F.expense(Decimal(100 * ($0 + 1)), on: F.date(2026, 10, 10 + $0)) }
            let disk = FullDiskLedgerRepository(try F.repository(rows))
            let useCases = TransactionUseCases(repository: disk)
            let window = RealWindow(useCases)
            window.history.setScreen(.account(F.savingsID))
            window.record(try useCases.changes.remove(ids: [rows[0].id]))
            var edited = rows[1]
            edited.amount = 950
            window.record(try useCases.saveTransactions.save([edited]))
            window.record(try useCases.changes.remove(ids: [rows[2].id, rows[3].id]))
            return Setup(disk: disk, window: window, rows: rows)
        }

        /// Four steps, each in its own event, the last one undone: Undo has "Delete Transaction", "Edit
        /// Transaction" and "Delete 2 Transactions"; Redo has "Edit 2 Transactions".
        private func withRedo() throws -> Setup {
            let rows = (0..<6).map { F.expense(Decimal(100 * ($0 + 1)), on: F.date(2026, 10, 10 + $0)) }
            let disk = FullDiskLedgerRepository(try F.repository(rows))
            let useCases = TransactionUseCases(repository: disk)
            let window = RealWindow(useCases)
            window.history.setScreen(.account(F.savingsID))
            window.record(try useCases.changes.remove(ids: [rows[0].id]))
            var edited = rows[1]
            edited.amount = 950
            window.record(try useCases.saveTransactions.save([edited]))
            window.record(try useCases.changes.remove(ids: [rows[2].id, rows[3].id]))
            let bulk = rows[4...]
                .map { row in
                    var row = row
                    row.amount = 50
                    return row
                }
            window.record(try useCases.saveTransactions.save(Array(bulk)))
            window.undo()
            return Setup(disk: disk, window: window, rows: rows)
        }

        /// Walks the whole Redo list and then the whole Undo list by name, with every write succeeding.
        private func assertLists(
            _ setup: Setup,
            undo: [String],
            redo: [String],
            sourceLocation: SourceLocation = #_sourceLocation,
        ) {
            setup.disk.isFull = false
            setup.window.history.dismissAlert()
            for name in redo.reversed() {
                #expect(setup.manager.redoActionName == name, sourceLocation: sourceLocation)
                setup.window.redo()
            }
            #expect(!setup.manager.canRedo, "No stand-in or dead Redo entry is left", sourceLocation: sourceLocation)
            // Redo moved its steps back onto Undo newest first.
            for name in (undo + redo.reversed()).reversed() {
                #expect(setup.manager.undoActionName == name, sourceLocation: sourceLocation)
                setup.window.undo()
            }
            #expect(!setup.manager.canUndo, sourceLocation: sourceLocation)
            #expect(setup.window.history.alert == nil, "Every step worked", sourceLocation: sourceLocation)
        }

        static let removedMessage =
            "Something went wrong saving your change. Please try again."
            + "\nThis change was removed from Undo history."

        /// The failed "Delete 2 Transactions" Undo was dropped (X8b), nothing was written, and every other step
        /// is where it was, with no stand-in or dead entry on either list.
        private func assertDropped(
            _ setup: Setup,
            before: [Transaction],
            left: Int = 4,
            sourceLocation: SourceLocation = #_sourceLocation,
        ) throws {
            #expect(try setup.transactions() == before, "Nothing was applied", sourceLocation: sourceLocation)
            #expect(setup.window.history.alert?.title == "Couldn't Make the Change", sourceLocation: sourceLocation)
            #expect(setup.window.history.alert?.message == Self.removedMessage, sourceLocation: sourceLocation)
            #expect(!setup.window.history.canUndo, "Off until the alert is dismissed", sourceLocation: sourceLocation)
            #expect(!setup.window.history.canRedo, sourceLocation: sourceLocation)
            #expect(
                setup.manager.undoActionName == "Edit Transaction in Everyday Savings",
                sourceLocation: sourceLocation,
            )
            #expect(
                setup.manager.redoActionName == "Edit 2 Transactions in Everyday Savings",
                sourceLocation: sourceLocation,
            )
            #expect(
                setup.window.history.undoTitle == "Edit Transaction in Everyday Savings",
                sourceLocation: sourceLocation,
            )
            #expect(
                setup.window.history.redoTitle == "Edit 2 Transactions in Everyday Savings",
                sourceLocation: sourceLocation,
            )
            assertLists(
                setup,
                undo: ["Delete Transaction in Everyday Savings", "Edit Transaction in Everyday Savings"],
                redo: ["Edit 2 Transactions in Everyday Savings"],
                sourceLocation: sourceLocation,
            )
            #expect(
                try setup.transactions().count == left,
                "Only the dropped step is gone",
                sourceLocation: sourceLocation,
            )
        }

        @Test("X8b: a second Cmd-Z with no event between is swallowed, though it would succeed; the failed step goes")
        func queuedUndoSucceeds() throws {
            let setup = try withRedo()
            let before = try setup.transactions()
            setup.disk.isFull = true
            setup.manager.undo()
            setup.disk.isFull = false
            setup.manager.undo()
            setup.window.nextEvent()
            #expect(try setup.amount(of: 1) == 950, "Edit Transaction isn't undone")
            try assertDropped(setup, before: before)
        }

        @Test("X8b: a second Cmd-Z with no event between that would fail too is swallowed the same way")
        func queuedUndoFails() throws {
            let setup = try withRedo()
            let before = try setup.transactions()
            setup.disk.isFull = true
            setup.manager.undo()
            setup.manager.undo()
            setup.window.nextEvent()
            try assertDropped(setup, before: before)
        }

        @Test("X8b: a second Redo with no event between is swallowed; the failed Redo step goes")
        func queuedRedo() throws {
            let setup = try withRedo()
            setup.window.undo()
            let before = try setup.transactions()
            setup.disk.isFull = true
            setup.manager.redo()
            setup.disk.isFull = false
            setup.manager.redo()
            setup.window.nextEvent()
            #expect(try setup.transactions().filter { $0.amount == 50 }.isEmpty, "Edit 2 Transactions isn't redone")
            // The failed step was "Delete 2 Transactions" again, this time on Redo, so its rows stay.
            try assertDropped(setup, before: before, left: 6)
        }

        @Test("X8b: three commands with no event between (failed Undo, Undo, Redo): all swallowed, no dead entry")
        func threeQueued() throws {
            let setup = try withRedo()
            let before = try setup.transactions()
            setup.disk.isFull = true
            setup.manager.undo()
            setup.disk.isFull = false
            setup.manager.undo()
            setup.manager.redo()
            setup.window.nextEvent()
            try assertDropped(setup, before: before)
        }

        @Test("X8b: four commands with no event between (failed Undo, Undo, Redo, Redo): all swallowed, no dead entry")
        func fourQueued() throws {
            let setup = try withRedo()
            let before = try setup.transactions()
            setup.disk.isFull = true
            setup.manager.undo()
            setup.disk.isFull = false
            setup.manager.undo()
            setup.manager.redo()
            setup.manager.redo()
            setup.window.nextEvent()
            try assertDropped(setup, before: before)
        }

        @Test("X8b: while the alert is up, Edit menu Undo and Redo apply nothing and every step stays (X8 kept)")
        func blockedUntilDismissed() throws {
            let setup = try withRedo()
            setup.disk.isFull = true
            setup.window.undo()
            setup.disk.isFull = false
            let before = try setup.transactions()
            #expect(
                setup.window.history.alert?.message
                    == "Something went wrong saving your change. Please try again.",
                "A single failure keeps the step, with no added line",
            )
            // The Edit menu and shake call the window's UndoManager directly.
            setup.window.undo()
            setup.window.redo()
            setup.window.redo()
            setup.window.undo()
            #expect(try setup.transactions() == before)
            #expect(setup.window.history.alert?.message == "Something went wrong saving your change. Please try again.")
            assertLists(
                setup,
                undo: [
                    "Delete Transaction in Everyday Savings", "Edit Transaction in Everyday Savings",
                    "Delete 2 Transactions in Everyday Savings",
                ],
                redo: ["Edit 2 Transactions in Everyday Savings"],
            )
        }

        @Test("X8b: dismissed before the deferred work runs, the block lasts until it has, and the step is back")
        func dismissedEarly() throws {
            let setup = try withRedo()
            setup.disk.isFull = true
            setup.manager.undo()
            setup.disk.isFull = false
            let before = try setup.transactions()
            setup.window.history.dismissAlert()
            #expect(!setup.window.history.canUndo, "Still blocked: the stand-in isn't back")
            #expect(!setup.window.history.canRedo)
            setup.window.history.undo()
            #expect(try setup.transactions() == before)

            setup.window.nextEvent()
            #expect(setup.window.history.canUndo && setup.window.history.canRedo)
            #expect(setup.window.history.alert == nil)
            assertLists(
                setup,
                undo: [
                    "Delete Transaction in Everyday Savings", "Edit Transaction in Everyday Savings",
                    "Delete 2 Transactions in Everyday Savings",
                ],
                redo: ["Edit 2 Transactions in Everyday Savings"],
            )
        }

        @Test("X8b: a Cmd-Z after an early dismissal is still swallowed, and no alert comes back")
        func dismissedEarlyThenQueued() throws {
            let setup = try withRedo()
            let before = try setup.transactions()
            setup.disk.isFull = true
            setup.manager.undo()
            setup.disk.isFull = false
            setup.window.history.dismissAlert()
            setup.manager.undo()
            setup.window.nextEvent()

            #expect(try setup.transactions() == before, "Edit Transaction isn't undone")
            #expect(setup.window.history.alert == nil, "The dismissed alert isn't shown again")
            #expect(setup.window.history.canUndo && setup.window.history.canRedo)
            #expect(setup.manager.undoActionName == "Edit Transaction in Everyday Savings")
            #expect(setup.manager.redoActionName == "Edit 2 Transactions in Everyday Savings")
            assertLists(
                setup,
                undo: ["Delete Transaction in Everyday Savings", "Edit Transaction in Everyday Savings"],
                redo: ["Edit 2 Transactions in Everyday Savings"],
            )
            #expect(try setup.transactions().count == 4)
        }

        @Test("X8: after a failed Undo, it is still the next Undo, the one below it and the Redo step stay")
        func failedUndo() throws {
            let setup = try setup()
            setup.window.undo()
            #expect(setup.manager.redoActionName == "Delete 2 Transactions in Everyday Savings")
            let before = try setup.transactions()

            setup.disk.isFull = true
            setup.window.undo()
            #expect(setup.window.history.alert?.title == "Couldn't Make the Change")
            #expect(try setup.transactions() == before, "Nothing changed or half changed")
            #expect(setup.manager.undoActionName == "Edit Transaction in Everyday Savings")
            #expect(
                setup.manager.redoActionName == "Delete 2 Transactions in Everyday Savings",
                "Redo has the same title",
            )
            #expect(setup.window.history.undoTitle == "Edit Transaction in Everyday Savings")
            #expect(setup.window.history.redoTitle == "Delete 2 Transactions in Everyday Savings")

            setup.disk.isFull = false
            setup.window.history.dismissAlert()
            setup.window.undo()
            #expect(try setup.amount(of: 1) == 200, "The same Undo works")
            #expect(
                setup.manager.undoActionName == "Delete Transaction in Everyday Savings",
                "The step below is still there",
            )
            #expect(setup.manager.redoActionName == "Edit Transaction in Everyday Savings")
            setup.window.redo()
            #expect(try setup.amount(of: 1) == 950)
            #expect(setup.manager.redoActionName == "Delete 2 Transactions in Everyday Savings")
            setup.window.redo()
            #expect(try setup.transactions().map(\.id) == [setup.rows[1].id], "That Redo works")
            #expect(!setup.manager.canRedo)
            #expect(setup.window.history.alert == nil)
        }

        @Test("X8a: after a failed Redo, it and the later Redo step behind it stay, and the Undo list too")
        func failedRedo() throws {
            let setup = try setup()
            setup.window.undo()
            setup.window.undo()
            #expect(setup.manager.redoActionName == "Edit Transaction in Everyday Savings")
            let before = try setup.transactions()

            setup.disk.isFull = true
            setup.window.redo()
            #expect(setup.window.history.alert?.title == "Couldn't Make the Change")
            #expect(try setup.transactions() == before)
            #expect(setup.manager.redoActionName == "Edit Transaction in Everyday Savings")
            #expect(setup.manager.undoActionName == "Delete Transaction in Everyday Savings")

            setup.disk.isFull = false
            setup.window.history.dismissAlert()
            setup.window.redo()
            #expect(try setup.amount(of: 1) == 950, "The same Redo works")
            #expect(
                setup.manager.redoActionName == "Delete 2 Transactions in Everyday Savings",
                "The later Redo step is kept",
            )
            setup.window.redo()
            #expect(try setup.transactions().map(\.id) == [setup.rows[1].id])
            for name in [
                "Delete 2 Transactions in Everyday Savings", "Edit Transaction in Everyday Savings",
                "Delete Transaction in Everyday Savings",
            ] {
                #expect(setup.manager.undoActionName == name)
                setup.window.undo()
            }
            #expect(try setup.transactions().count == 4, "The whole Undo list was kept")
            #expect(!setup.manager.canUndo)
            #expect(setup.window.history.alert == nil)
        }

        @Test("Failing twice in a row still keeps everything, and the next try works")
        func failsTwice() throws {
            let setup = try setup()
            setup.window.undo()
            setup.disk.isFull = true
            setup.window.undo()
            setup.window.history.dismissAlert()
            setup.window.undo()
            #expect(setup.manager.undoActionName == "Edit Transaction in Everyday Savings")
            #expect(setup.manager.redoActionName == "Delete 2 Transactions in Everyday Savings")
            setup.disk.isFull = false
            setup.window.history.dismissAlert()
            setup.window.undo()
            #expect(try setup.amount(of: 1) == 200)
        }
    }
#endif
