import Foundation
import LittleOrbitDomain
import LittleOrbitFeatures
import LittleOrbitPersistence
import Testing

/// An account-scoped step has its account in its name, so the toolbar, the Mac Edit menu, the iPadOS menu
/// bar and the shake alert always say where it happened, on every screen (D198, superseding D162's on-screen
/// rule; Tester's #87 B2). The name keeps the account's name from when the step was recorded.
@MainActor
@Suite("Undo names say the account")
struct WindowUndoTitleTests {
    typealias F = TransactionFeatureFixture  // swiftlint:disable:this type_name

    struct Setup {
        let repository: InMemoryLedgerRepository
        let useCases: TransactionUseCases
        let window: TestWindow
        let card: [Transaction]
        let savings: Transaction
        var history: WindowUndoHistory { window.history }
    }

    /// Two Rewards Card deletes recorded on its screen, the second one undone, so Redo has a step.
    private func setup() throws -> Setup {
        let card = (0..<2).map { F.expense(Decimal($0 + 1), on: F.date(2026, 10, 10 + $0), account: F.cardID) }
        let savings = F.expense(300, on: F.date(2026, 10, 12))
        let repository = try F.repository(card + [savings])
        let useCases = TransactionUseCases(repository: repository)
        let window = TestWindow(useCases)
        window.history.setScreen(.account(F.cardID))
        window.history.record(try useCases.changes.remove(ids: [card[0].id]))
        window.history.record(try useCases.changes.remove(ids: [card[1].id]))
        window.history.undo()
        return Setup(repository: repository, useCases: useCases, window: window, card: card, savings: savings)
    }

    private func expectNames(
        _ setup: Setup,
        sourceLocation: SourceLocation = #_sourceLocation,
    ) {
        let name = "Delete Transaction in Rewards Card"
        #expect(setup.history.undoTitle == name, sourceLocation: sourceLocation)
        #expect(setup.history.redoTitle == name, sourceLocation: sourceLocation)
        #expect(
            setup.window.undoManager.undoNames == [name],
            "The Edit menu says the same",
            sourceLocation: sourceLocation,
        )
        #expect(setup.window.undoManager.redoNames == [name], "Redo is kept", sourceLocation: sourceLocation)
    }

    @Test("iPad: the name is the same on the account itself and after switching to another one")
    func viewedAccountChanges() throws {
        let setup = try setup()
        expectNames(setup)
        setup.history.setScreen(.account(F.savingsID))
        expectNames(setup)
        setup.history.setScreen(.account(F.cardID))
        expectNames(setup)
        setup.history.undo()
        #expect(try setup.repository.transactions().count == 3, "Undo still moves one step")
    }

    @Test("iPhone: the name is the same on the account list and back in the account")
    func backToTheList() throws {
        let setup = try setup()
        setup.history.setScreen(.list(visible: []))
        expectNames(setup)
        setup.history.setScreen(.account(F.cardID))
        expectNames(setup)
    }

    @Test("After a stale step's alert, the next Undo step still says its account")
    func afterAlert() throws {
        let setup = try setup()
        setup.history.redo()
        setup.history.setScreen(.account(F.savingsID))
        var edited = setup.savings
        edited.amount = 350
        setup.history.record(try setup.useCases.saveTransactions.save([edited]))
        #expect(setup.history.undoTitle == "Edit Transaction in Everyday Savings")
        // Another window changes it, so its Undo is stale.
        edited.amount = 777
        try setup.repository.saveTransaction(edited)
        setup.history.undo()
        #expect(setup.history.alert?.title == "Can't Undo Edit Transaction in Everyday Savings")
        setup.history.dismissAlert()
        #expect(setup.history.undoTitle == "Delete Transaction in Rewards Card")
        #expect(setup.window.undoManager.undoNames.last == "Delete Transaction in Rewards Card")
    }

    @Test("Renaming the account later doesn't rename the step: it keeps the name it was recorded with")
    func keepsTheRecordedName() throws {
        let setup = try setup()
        var card = try #require(try setup.repository.accounts().first { $0.id == F.cardID })
        card.name = "Travel Card"
        try setup.repository.saveAccount(card)
        setup.history.setScreen(.account(F.savingsID))
        expectNames(setup)
        setup.history.redo()
        #expect(setup.history.undoTitle == "Delete Transaction in Rewards Card")
        setup.history.undo()
        #expect(setup.history.redoTitle == "Delete Transaction in Rewards Card")
        #expect(try setup.repository.transactions().count == 2, "The step still works after the rename")
    }
}
