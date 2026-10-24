#if canImport(SwiftUI) && os(macOS)
    import Foundation
    import LittleOrbitDomain
    @testable import LittleOrbitFeatures
    import LittleOrbitPersistence
    import Testing

    /// Each Undo and Redo moves exactly one step on a window's real `UndoManager`, which groups by event
    /// (Tester's #87 recheck, bug 1). Runs in the macOS CI job.
    @MainActor
    @Suite("One step per Undo with grouping by event", .serialized, .timeLimit(.minutes(2)))
    struct TransactionUndoEventGroupingTests {
        typealias F = TransactionFeatureFixture  // swiftlint:disable:this type_name

        private func add(_ amount: Decimal, _ useCases: TransactionUseCases) throws -> TransactionChange {
            try useCases.saveTransactions.save([F.expense(amount, on: F.date(2026, 10, 18))])
        }

        /// Why each step goes in its own event: with grouping by event, groups begun at level 0 in one event sit
        /// inside that event's automatic group, so one `undo()` undoes them all.
        @Test("With grouping by event, two groups begun in one event are undone together")
        func siblingGroupsShareTheEvent() {
            let undoManager = UndoManager()
            #expect(undoManager.groupsByEvent)
            let target = NSObject()
            var undone: [String] = []
            undoManager.beginUndoGrouping()
            undoManager.registerUndo(withTarget: target) { _ in undone.append("first") }
            undoManager.endUndoGrouping()
            undoManager.beginUndoGrouping()
            undoManager.registerUndo(withTarget: target) { _ in undone.append("second") }
            undoManager.endUndoGrouping()
            #expect(undoManager.groupingLevel == 1, "The event's automatic group is still open")
            undoManager.undo()
            #expect(undone == ["second", "first"])
        }

        @Test("Three adds, then one Undo reverts exactly one add; Redo puts it back (Tech Architect)")
        func threeAddsOneUndo() throws {
            let repository = try F.repository([])
            let useCases = TransactionUseCases(repository: repository, categoryNames: CatalogDefaultCategoryNames())
            let window = RealWindow(useCases)
            for amount in [15, 20, 30] as [Decimal] {
                window.record(try add(amount, useCases))
            }

            window.undo()
            #expect(try repository.transactions().map(\.amount).sorted() == [15, 20])
            #expect(window.undoManager.undoActionName == "New Transaction in Everyday Savings")
            #expect(window.undoManager.redoActionName == "New Transaction in Everyday Savings")

            // The toolbar Undo, then Redo from the menu.
            window.history.undo()
            window.nextEvent()
            #expect(try repository.transactions().map(\.amount) == [15])
            window.redo()
            #expect(try repository.transactions().map(\.amount).sorted() == [15, 20])
            #expect(window.undoManager.canRedo, "The third add can still be redone")
            window.redo()
            #expect(try repository.transactions().count == 3)
            #expect(!window.undoManager.canRedo)
        }

        @Test("Two deletes, then one Undo restores only the second (Tester's iPhone repro)")
        func twoDeletesOneUndo() throws {
            let income = F.income(250, on: F.date(2026, 10, 17))
            let cafe = F.expense(120, on: F.date(2026, 10, 18), details: "Cafe Orbit")
            let repository = try F.repository([income, cafe])
            let useCases = TransactionUseCases(repository: repository, categoryNames: CatalogDefaultCategoryNames())
            let window = RealWindow(useCases)
            window.history.setScreen(.account(F.savingsID))
            window.record(try useCases.changes.remove(ids: [income.id]))
            window.record(try useCases.changes.remove(ids: [cafe.id]))

            window.history.undo()
            window.nextEvent()
            #expect(try repository.transactions().map(\.id) == [cafe.id])
            #expect(window.history.undoTitle == "Delete Transaction in Everyday Savings")
            #expect(window.undoManager.undoActionName == "Delete Transaction in Everyday Savings")
            window.history.redo()
            window.nextEvent()
            #expect(try repository.transactions().isEmpty)
        }

        @Test("Three adds and a bulk delete, then one Undo brings back only the deleted rows (Tester's iPad repro)")
        func bulkDeleteAfterAdds() throws {
            let repository = try F.repository([])
            let useCases = TransactionUseCases(repository: repository, categoryNames: CatalogDefaultCategoryNames())
            let window = RealWindow(useCases)
            for amount in [15, 20, 30] as [Decimal] {
                window.record(try add(amount, useCases))
            }
            let two = try repository.transactions().filter { $0.amount != 15 }.map(\.id)
            window.record(try useCases.changes.remove(ids: two))

            window.undo()
            #expect(try repository.transactions().count == 3)
            #expect(window.undoManager.undoActionName == "New Transaction in Everyday Savings")
            window.redo()
            #expect(try repository.transactions().map(\.amount) == [15])
        }

        @Test("W3: two windows, two histories; Cmd-Z in one moves only that window, by exactly one step")
        func twoWindows() throws {
            let repository = try F.repository([])
            let useCases = TransactionUseCases(repository: repository, categoryNames: CatalogDefaultCategoryNames())
            let updates = LedgerUpdates()
            let first = RealWindow(useCases, updates: updates)
            let second = RealWindow(useCases, updates: updates)
            first.history.setScreen(.account(F.savingsID))
            second.history.setScreen(.account(F.walletID))
            for amount in [15, 20] as [Decimal] {
                first.record(try add(amount, useCases))
            }
            second.record(try add(30, useCases))

            first.undo()
            #expect(try repository.transactions().map(\.amount).sorted() == [15, 30])
            #expect(first.undoManager.undoActionName == "New Transaction in Everyday Savings")
            #expect(first.undoManager.redoActionName == "New Transaction in Everyday Savings")
            #expect(second.undoManager.undoActionName == "New Transaction in Everyday Savings")
            #expect(!second.undoManager.canRedo)

            second.undo()
            #expect(try repository.transactions().map(\.amount) == [15])
            #expect(!second.undoManager.canUndo)
            #expect(first.undoManager.canUndo && first.undoManager.canRedo, "The first window is unchanged")
        }
    }
#endif
