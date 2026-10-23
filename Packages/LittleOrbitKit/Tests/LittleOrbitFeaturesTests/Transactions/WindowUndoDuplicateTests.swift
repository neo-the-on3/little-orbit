import Foundation
import LittleOrbitDomain
import LittleOrbitFeatures
import LittleOrbitPersistence
import Testing

/// A Duplicate step's name (D221): the existing shapes with "Duplicate", the same for Undo and Redo, and taken
/// whole by the alerts. Undo still removes only the copy (S29, P4). One test per row of D221.1's table.
@MainActor
@Suite("Duplicate Undo names")
struct WindowUndoDuplicateTests {
    typealias F = TransactionFeatureFixture  // swiftlint:disable:this type_name

    /// Duplicates `original` in a window on its account, then checks the Undo and Redo names, that Undo
    /// removes only the copy and Redo brings it back, and the stale alert's title.
    private func expectDuplicate(
        of original: Transaction,
        named name: String,
        sourceLocation: SourceLocation = #_sourceLocation,
    ) throws {
        let repository = try F.repository([original])
        let useCases = TransactionUseCases(repository: repository)
        let window = TestWindow(useCases)
        let history = window.history
        let before = try repository.transactions()
        window.history.setScreen(.account(try #require(original.accountID)))
        history.record(try useCases.duplicate.duplicate(id: original.id, now: F.now))
        let copy = try #require(try repository.transactions().first { $0.id != original.id })
        #expect(history.undoTitle == name, sourceLocation: sourceLocation)
        #expect(window.undoManager.undoNames == [name], "The Edit menu says the same", sourceLocation: sourceLocation)

        history.undo()
        #expect(try repository.transactions() == before, "Undo removes only the copy", sourceLocation: sourceLocation)
        #expect(history.redoTitle == name, sourceLocation: sourceLocation)
        #expect(window.undoManager.redoNames == [name], sourceLocation: sourceLocation)

        history.redo()
        #expect(try repository.transactions().contains { $0.id == copy.id }, sourceLocation: sourceLocation)
        #expect(history.undoTitle == name, "Redo keeps the name", sourceLocation: sourceLocation)

        // Another window changes the copy, so its Undo is stale.
        var edited = try #require(try repository.transactions().first { $0.id == copy.id })
        edited.amount += 1
        try repository.saveTransaction(edited)
        history.undo()
        #expect(history.alert?.title == "Can’t Undo \(name)", sourceLocation: sourceLocation)
    }

    @Test("An expense or income: \"Duplicate Transaction in Rewards Card\"")
    func transactionInAccount() throws {
        try expectDuplicate(
            of: F.expense(250, on: F.date(2026, 10, 10), account: F.cardID),
            named: "Duplicate Transaction in Rewards Card",
        )
        try expectDuplicate(
            of: F.income(900, on: F.date(2026, 10, 10)),
            named: "Duplicate Transaction in Everyday Savings",
        )
    }

    @Test("A transfer, both accounts read: \"Duplicate Transfer from Everyday Savings to Rewards Card\"")
    func transferWithBothAccounts() throws {
        try expectDuplicate(
            of: F.transfer(100, on: F.date(2026, 10, 10)),
            named: "Duplicate Transfer from Everyday Savings to Rewards Card",
        )
    }

    /// Records `change` with the fake's impact, then checks the Undo and Redo names and a failed Redo's title.
    private func expectFakeStep(
        _ change: TransactionChange,
        impact: ChangeImpact? = nil,
        named name: String,
        sourceLocation: SourceLocation = #_sourceLocation,
    ) {
        let fake = FakeTransactionUseCases()
        if let impact {
            fake.impactResult = impact
        } else {
            fake.impactError = FakeTransactionUseCases.Failure()
        }
        let window = TestWindow(fake.useCases)
        window.history.record(change)
        #expect(window.history.undoTitle == name, sourceLocation: sourceLocation)
        window.history.dismissAlert()
        window.history.undo()
        #expect(window.history.redoTitle == name, sourceLocation: sourceLocation)
        fake.revertError = FakeTransactionUseCases.Failure()
        window.history.redo()
        #expect(window.history.alert?.title == "Couldn’t Redo \(name)", sourceLocation: sourceLocation)
    }

    @Test("A transfer with only one account read: \"Duplicate Transfer in Rewards Card\"")
    func transferWithOneAccount() {
        let card = F.accounts().first { $0.id == F.cardID }!
        let id = UUID()
        let impact = ChangeImpact(accountIDs: [card.id], accounts: [card], transactionIDs: [id])
        expectFakeStep(
            .duplicated(.transfer, .added([id])),
            impact: impact,
            named: "Duplicate Transfer in Rewards Card",
        )
    }

    @Test("No account read when it's recorded: \"Duplicate Transaction\" or \"Duplicate Transfer\" (D221.3)")
    func noAccountRead() {
        expectFakeStep(.duplicated(.expense, .added([UUID()])), named: "Duplicate Transaction")
        expectFakeStep(.duplicated(.income, .added([UUID()])), named: "Duplicate Transaction")
        expectFakeStep(.duplicated(.transfer, .added([UUID()])), named: "Duplicate Transfer")
    }

    @Test("A plain add keeps its own name; only a duplicate says Duplicate")
    func plainAddUnchanged() {
        let card = F.accounts().first { $0.id == F.cardID }!
        let id = UUID()
        let impact = ChangeImpact(accountIDs: [card.id], accounts: [card], transactionIDs: [id])
        #expect(UndoActionTitle.stepName(of: .added([id]), impact: impact) == "New Transaction in Rewards Card")
        #expect(
            UndoActionTitle.stepName(of: .duplicated(.expense, .added([id])), impact: impact)
                == "Duplicate Transaction in Rewards Card"
        )
    }
}
