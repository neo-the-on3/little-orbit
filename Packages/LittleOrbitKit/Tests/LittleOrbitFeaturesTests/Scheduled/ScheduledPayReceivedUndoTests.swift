import Foundation
import LittleOrbitDomain
import LittleOrbitPersistence
import Testing

@testable import LittleOrbitFeatures

/// Tech Architect's review 5684398084 on #201: Undo and Redo of a custom Pay between currencies with "Also change
/// future occurrences" on put the schedule's amount received and its currency back with the amount, through a
/// window's history; and once To's currency has moved on, Undo is refused with the usual stale message and writes
/// nothing (#207 B1). Made-up data; today is 20 Oct 2026.
@MainActor
@Suite("Undo and Redo of a future-on custom Pay restore Received (#201, #207 B1)")
struct ScheduledPayReceivedUndoTests {
    /// Rent Share's list in a window whose Undo steps the list records, as `ScheduledPayUndoTests` makes it.
    private func window(_ scene: ScheduledScene) throws -> (ScheduledListViewModel, TestWindow) {
        try scene.addRentShare()
        let useCases = TransactionUseCases(
            repository: scene.repository,
            categoryNames: CatalogDefaultCategoryNames(),
            schedule: scene.repository,
        )
        let window = TestWindow(useCases, updates: scene.updates)
        let list = scene.feature().makeList()
        list.recordStep = { [history = window.history] change, name, subject in
            history.record(change, named: name, subject: subject)
        }
        list.load()
        return (list, window)
    }

    /// ₹2,000 received as $24, with "Also change future occurrences" on, from the Pay sheet.
    private func payWithFuture(_ list: ScheduledListViewModel) throws {
        list.openCustomPay(try #require(list.overdueRows.first))
        let sheet = try #require(list.payment)
        sheet.amountText = "2000"
        sheet.receivedText = "24"
        sheet.changesFutureOccurrences = true
        #expect(sheet.record())
    }

    private func schedule(_ scene: ScheduledScene) throws -> ScheduledItem {
        try #require(try scene.repository.scheduleLedger().scheduledItems.first)
    }

    @Test("Undo Pay Rent Share puts back ₹1,000 received as $12 in USD; Redo puts back ₹2,000 and $24")
    func undoRedoRestoresReceived() throws {
        let scene = try ScheduledScene()
        let (list, window) = try window(scene)
        try payWithFuture(list)
        #expect(window.undoManager.undoActionName == "Pay Rent Share")
        window.history.undo()
        var stored = try schedule(scene)
        #expect(stored.amount == 1_000 && stored.destinationAmount == 12 && stored.receivedCurrencyCode == "USD")
        #expect(scene.recorded.isEmpty)
        window.history.redo()
        stored = try schedule(scene)
        #expect(stored.amount == 2_000 && stored.destinationAmount == 24 && stored.receivedCurrencyCode == "USD")
        #expect(scene.recorded.first?.destinationAmount == 24)
    }

    @Test("To moved from USD to EUR since: Undo is refused as stale, with the usual message, and writes nothing")
    func undoStaleWhenToMoved() throws {
        let scene = try ScheduledScene()
        let (list, window) = try window(scene)
        try payWithFuture(list)
        var ledger = try scene.repository.scheduleLedger()
        let index = try #require(ledger.accounts.firstIndex { $0.name == "Travel Card" })
        ledger.accounts[index].currencyCode = "EUR"
        try scene.repository.replaceLedger(with: ledger)
        let before = try scene.repository.scheduleLedger()
        window.history.undo()
        #expect(window.history.alert?.title == "Can’t Undo Pay Rent Share")
        #expect(window.history.alert?.message == "Rent Share has changed since then. Nothing was changed.")
        #expect(try scene.repository.scheduleLedger() == before)
        #expect(!window.undoManager.canUndo, "A stale step is dropped (D187.5)")
    }
}
