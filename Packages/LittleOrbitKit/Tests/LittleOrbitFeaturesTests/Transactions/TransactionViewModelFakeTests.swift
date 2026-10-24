import Foundation
import LittleOrbitDomain
import LittleOrbitFeatures
import Testing

/// The transaction view models against fake use cases, and the feature that wires them.
@MainActor
@Suite("Transactions with fake use cases")
struct TransactionViewModelFakeTests {
    typealias F = TransactionFeatureFixture  // swiftlint:disable:this type_name

    private func feature(_ fake: FakeTransactionUseCases) -> TransactionsFeature {
        TransactionsFeature(
            useCases: fake.useCases,
            locale: F.india,
            timeZone: F.zone,
            now: { F.now },
        )
    }

    @Test("History for an account the use case can't find shows it as gone")
    func missingAccount() {
        let fake = FakeTransactionUseCases()
        let history = feature(fake).makeHistory(accountID: F.savingsID)
        history.load()
        #expect(!history.accountExists)
        #expect(history.isEmpty)
    }

    @Test("A history read error shows a message")
    func historyError() {
        let fake = FakeTransactionUseCases()
        fake.historyError = FakeTransactionUseCases.Failure()
        let history = feature(fake).makeHistory(accountID: F.savingsID)
        history.load()
        #expect(history.errorMessage != nil)
    }

    @Test("Delete and Undo go through the changes use case")
    func deleteAndUndo() throws {
        let fake = FakeTransactionUseCases()
        let history = feature(fake).makeHistory(accountID: F.savingsID)
        let id = UUID()
        let change = try #require(history.delete(id: id))
        #expect(fake.removed == [[id]])
        UndoTestSupport.undo(change, useCases: fake.useCases)
        #expect(fake.reverted == [change])
    }

    @Test("A new transaction is saved through the save use case")
    func saveNew() throws {
        let fake = FakeTransactionUseCases()
        fake.contents = TransactionLedger(accounts: F.accounts())
        let form = feature(fake).makeForm(.new(accountID: F.walletID))
        form.press(.digit(5))
        #expect(form.save() != nil)
        #expect(fake.saved.count == 1)
        #expect(fake.saved.first?.first?.amount == 5)
    }

    @Test("A window's history reverts through the changes use case, and every window sees the store change")
    func featureUndoHistory() {
        let fake = FakeTransactionUseCases()
        let feature = feature(fake)
        let change = TransactionChange.removed([])
        let undoManager = FakeUndoManager()
        let history = feature.makeUndoHistory()
        history.attach(undoManager)
        history.record(change)
        history.undo()
        #expect(fake.reverted == [change])
        #expect(feature.updates.revision == 2)
        #expect(!feature.makeUndoHistory().canUndo, "A new window starts empty (W9)")
    }
}
