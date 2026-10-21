#if canImport(SwiftUI) && os(macOS)
    import Foundation
    import LittleOrbitDomain
    @testable import LittleOrbitFeatures
    import LittleOrbitPersistence
    import Testing

    /// Each window's history on its own real `UndoManager`, as the macOS Edit menu, Cmd-Z and the iOS shake
    /// alert read it (#93: D161, D187, D198). Runs in the macOS CI job.
    @MainActor
    @Suite("Undo names on a real UndoManager", .serialized)
    struct TransactionUndoNameTests {
        typealias F = TransactionFeatureFixture  // swiftlint:disable:this type_name

        private func setup(_ transactions: [Transaction]) throws -> (InMemoryLedgerRepository, TransactionUseCases) {
            let repository = try F.repository(transactions)
            return (repository, TransactionUseCases(repository: repository))
        }

        /// Undo and Redo through the `UndoManager` keep the user's name for the whole cycle.
        private func assertCycle(
            _ window: RealWindow,
            _ name: String,
            sourceLocation: SourceLocation = #_sourceLocation,
        ) {
            #expect(window.undoManager.undoActionName == name, sourceLocation: sourceLocation)
            window.undo()
            #expect(
                window.undoManager.redoActionName == name,
                "Redo names the user's action",
                sourceLocation: sourceLocation,
            )
            window.redo()
            #expect(window.undoManager.undoActionName == name, sourceLocation: sourceLocation)
            #expect(!window.undoManager.canRedo, sourceLocation: sourceLocation)
        }

        @Test("Undo and Redo through the UndoManager restore and delete again")
        func deleteRestoresAndRedoes() throws {
            let lunch = F.expense(250, on: F.date(2026, 10, 18))
            let (repository, useCases) = try setup([lunch])
            let window = RealWindow(useCases)
            window.record(try useCases.changes.remove(ids: [lunch.id]))
            window.undo()
            #expect(try repository.transactions().map(\.id) == [lunch.id])
            window.redo()
            #expect(try repository.transactions().isEmpty)
        }

        @Test("Each change keeps its name through Undo and Redo")
        func names() throws {
            let items = (0..<5).map { F.expense(Decimal($0 + 1), on: F.date(2026, 10, 10 + $0)) }
            let move = F.transfer(500, on: F.date(2026, 10, 19), from: F.savingsID, to: F.walletID)
            let (repository, useCases) = try setup(items + [move])
            let window = RealWindow(useCases)
            window.history.setScreen(.account(F.savingsID))

            window.record(try useCases.changes.remove(ids: [items[0].id]))
            assertCycle(window, "Delete Transaction in Everyday Savings")
            window.record(try useCases.changes.remove(ids: items.dropFirst().map(\.id)))
            assertCycle(window, "Delete 4 Transactions in Everyday Savings")
            window.record(try useCases.saveTransactions.save([F.expense(9, on: F.now)]))
            assertCycle(window, "New Transaction in Everyday Savings")
            var moved = try #require(try repository.transactions().first { $0.id == move.id })
            moved.amount = 600
            window.record(try useCases.saveTransactions.save([moved]))
            assertCycle(window, "Edit Transfer from Everyday Savings to Corner Wallet")
        }

        @Test("A bulk edit is one named step")
        func bulkEdit() throws {
            let items = (0..<5).map { F.expense(Decimal($0 + 1), on: F.date(2026, 10, 10 + $0)) }
            let (repository, useCases) = try setup(items)
            let window = RealWindow(useCases)
            window.history.setScreen(.account(F.savingsID))
            window.record(
                try useCases.saveTransactions.save(
                    try repository.transactions()
                        .map {
                            var item = $0
                            item.amount += 1
                            return item
                        }
                )
            )
            assertCycle(window, "Edit 5 Transactions in Everyday Savings")
        }

        /// Each window's Edit menu offers only its own steps (W1).
        @Test("Two windows, two histories: only the window that made the change offers it")
        func twoWindows() throws {
            let fuel = F.expense(900, on: F.date(2026, 10, 18), account: F.cardID)
            let (repository, useCases) = try setup([fuel])
            let first = RealWindow(useCases)
            let second = RealWindow(useCases)
            first.history.setScreen(.account(F.cardID))
            second.history.setScreen(.account(F.savingsID))
            first.record(try useCases.changes.remove(ids: [fuel.id]))
            #expect(first.undoManager.undoActionName == "Delete Transaction in Rewards Card")
            #expect(!second.undoManager.canUndo)

            second.undo()
            #expect(try repository.transactions().isEmpty, "The other window's Undo does nothing")
            first.undo()
            #expect(try repository.transactions().map(\.id) == [fuel.id])
            #expect(first.undoManager.redoActionName == "Delete Transaction in Rewards Card")
            #expect(!second.undoManager.canRedo)
        }

        @Test("Deleting an account is one named step")
        func deleteAccount() throws {
            let (repository, useCases) = try setup([F.expense(1, on: F.date(2026, 10, 10), account: F.cardID)])
            let window = RealWindow(useCases)
            window.record(.removedAccount(try AccountUseCases(repository: repository).deleteAccount.delete(F.cardID)))
            assertCycle(window, "Delete Account Rewards Card")
        }

        @Test("W6, D198: the Edit menu names the account on every screen, and Undo still moves one step")
        func nameSaysTheAccount() throws {
            let lunch = F.expense(250, on: F.date(2026, 10, 18), account: F.cardID)
            let tea = F.expense(20, on: F.date(2026, 10, 18), account: F.cardID)
            let (repository, useCases) = try setup([lunch, tea])
            let window = RealWindow(useCases)
            window.history.setScreen(.account(F.cardID))
            window.record(try useCases.changes.remove(ids: [lunch.id]))
            window.record(try useCases.changes.remove(ids: [tea.id]))
            #expect(window.undoManager.undoActionName == "Delete Transaction in Rewards Card")
            window.history.setScreen(.account(F.savingsID))
            window.nextEvent()
            #expect(window.undoManager.undoActionName == "Delete Transaction in Rewards Card")
            #expect(window.history.undoTitle == "Delete Transaction in Rewards Card")
            window.undo()
            #expect(try repository.transactions().map(\.id) == [tea.id])
            #expect(window.undoManager.redoActionName == "Delete Transaction in Rewards Card")
            #expect(window.undoManager.undoActionName == "Delete Transaction in Rewards Card")
            #expect(window.history.redoTitle == window.undoManager.redoActionName, "Toolbar and Edit menu agree")
        }

        @Test("B2, D198: after a stale step's alert, the next Undo name still says its account")
        func nameAfterStaleAlert() throws {
            let lunch = F.expense(250, on: F.date(2026, 10, 18), account: F.cardID)
            let coffee = F.expense(90, on: F.date(2026, 10, 18))
            let (repository, useCases) = try setup([lunch, coffee])
            let window = RealWindow(useCases)
            window.history.setScreen(.account(F.cardID))
            window.record(try useCases.changes.remove(ids: [lunch.id]))
            window.history.setScreen(.account(F.savingsID))
            window.nextEvent()
            var edited = coffee
            edited.amount = 95
            window.record(try useCases.saveTransactions.save([edited]))
            #expect(window.undoManager.undoActionName == "Edit Transaction in Everyday Savings")
            edited.amount = 777
            try repository.saveTransaction(edited)
            window.undo()
            #expect(window.history.alert?.title == "Can't Undo Edit Transaction in Everyday Savings")
            window.history.dismissAlert()
            window.nextEvent()
            #expect(window.undoManager.undoActionName == "Delete Transaction in Rewards Card")
            #expect(window.history.undoTitle == "Delete Transaction in Rewards Card")
            window.undo()
            #expect(try repository.transactions().contains { $0.id == lunch.id }, "Undo still works")
        }

        @Test("D198: renaming the account keeps the name the step was recorded with, in the Edit menu too")
        func nameKeepsTheRecordedAccount() throws {
            let lunch = F.expense(250, on: F.date(2026, 10, 18), account: F.cardID)
            let tea = F.expense(20, on: F.date(2026, 10, 18), account: F.cardID)
            let (repository, useCases) = try setup([lunch, tea])
            let window = RealWindow(useCases)
            window.history.setScreen(.account(F.cardID))
            window.record(try useCases.changes.remove(ids: [lunch.id]))
            window.record(try useCases.changes.remove(ids: [tea.id]))
            window.undo()
            var card = try #require(try repository.accounts().first { $0.id == F.cardID })
            card.name = "Travel Card"
            try repository.saveAccount(card)
            window.nextEvent()
            #expect(window.undoManager.undoActionName == "Delete Transaction in Rewards Card")
            #expect(window.undoManager.redoActionName == "Delete Transaction in Rewards Card")
            window.redo()
            #expect(try repository.transactions().isEmpty)
            #expect(window.undoManager.undoActionName == "Delete Transaction in Rewards Card")
        }

        @Test("X1 on a real UndoManager: a stale step is gone from Undo and never reaches Redo")
        func staleStepIsRemoved() throws {
            let corner = F.expense(450, on: F.date(2026, 10, 18), details: "Corner Bakery")
            let tea = F.expense(20, on: F.date(2026, 10, 18))
            let (repository, useCases) = try setup([corner, tea])
            let first = RealWindow(useCases)
            let second = RealWindow(useCases)
            first.history.setScreen(.account(F.savingsID))
            first.record(try useCases.changes.remove(ids: [tea.id]))
            var edited = try #require(try repository.transactions().first { $0.id == corner.id })
            edited.amount = 500
            first.record(try useCases.saveTransactions.save([edited]))
            edited.amount = 650
            second.record(try useCases.saveTransactions.save([edited]))

            first.undo()
            #expect(try repository.transactions().first { $0.id == corner.id }?.amount == 650)
            #expect(first.history.alert?.title == "Can't Undo Edit Transaction in Everyday Savings")
            #expect(!first.undoManager.canRedo)
            #expect(first.undoManager.undoActionName == "Delete Transaction in Everyday Savings")
            #expect(second.undoManager.undoActionName == "Edit Transaction in Everyday Savings")
        }

        @Test("X6 on a real UndoManager: a stale Redo leaves no empty Undo behind")
        func staleRedoLeavesNothing() throws {
            let corner = F.expense(450, on: F.date(2026, 10, 18), details: "Corner Bakery")
            let tea = F.expense(20, on: F.date(2026, 10, 18))
            let (repository, useCases) = try setup([corner, tea])
            let first = RealWindow(useCases)
            let second = RealWindow(useCases)
            first.history.setScreen(.account(F.savingsID))
            first.record(try useCases.changes.remove(ids: [tea.id]))
            first.record(try useCases.changes.remove(ids: [corner.id]))
            first.undo()
            var edited = try #require(try repository.transactions().first { $0.id == corner.id })
            edited.amount = 475
            second.record(try useCases.saveTransactions.save([edited]))

            first.redo()
            #expect(first.history.alert?.title == "Can't Redo Delete Transaction in Everyday Savings")
            #expect(try repository.transactions().first { $0.id == corner.id }?.amount == 475)
            #expect(!first.undoManager.canRedo)
            #expect(
                first.undoManager.undoActionName == "Delete Transaction in Everyday Savings",
                "The step below, not an empty one",
            )
            first.undo()
            #expect(try repository.transactions().contains { $0.id == tea.id })
        }

        @Test("D189.1 on a real UndoManager: a stale Undo leaves the window's Redo exactly as it was")
        func staleUndoKeepsRedo() throws {
            let corner = F.expense(450, on: F.date(2026, 10, 18), details: "Corner Bakery")
            let tea = F.expense(20, on: F.date(2026, 10, 18))
            let (repository, useCases) = try setup([corner, tea])
            let first = RealWindow(useCases)
            let second = RealWindow(useCases)
            first.history.setScreen(.account(F.savingsID))
            var edited = try #require(try repository.transactions().first { $0.id == corner.id })
            edited.amount = 500
            first.record(try useCases.saveTransactions.save([edited]))
            first.record(try useCases.changes.remove(ids: [tea.id]))
            first.undo()
            edited.amount = 650
            second.record(try useCases.saveTransactions.save([edited]))

            first.undo()
            #expect(first.history.alert?.title == "Can't Undo Edit Transaction in Everyday Savings")
            #expect(!first.undoManager.canUndo)
            #expect(first.undoManager.canRedo)
            #expect(first.undoManager.redoActionName == "Delete Transaction in Everyday Savings")
            first.redo()
            #expect(!(try repository.transactions().contains { $0.id == tea.id }))
            #expect(try repository.transactions().first { $0.id == corner.id }?.amount == 650)
        }

        @Test("X8 on a real UndoManager: after a failure, the step is offered again")
        func failureKeepsTheStep() throws {
            let fake = FakeTransactionUseCases()
            let window = RealWindow(fake.useCases)
            window.record(.removed([RemovedTransaction(transaction: Transaction(type: .expense, amount: 1))]))
            fake.revertError = FakeTransactionUseCases.Failure()
            window.undo()
            #expect(window.history.alert?.title == "Couldn't Make the Change")
            #expect(window.undoManager.undoActionName == "Delete Transaction")

            fake.revertError = nil
            window.history.dismissAlert()
            window.undo()
            #expect(fake.reverted.count == 1)
            fake.revertError = FakeTransactionUseCases.Failure()
            window.redo()
            #expect(window.undoManager.redoActionName == "Delete Transaction", "A failed Redo stays on Redo")
            #expect(!window.undoManager.canUndo)
        }
    }
#endif
