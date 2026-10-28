import Foundation
import LittleOrbitDomain
import LittleOrbitPersistence
import Testing

@testable import LittleOrbitFeatures

/// #207 B1: a scheduled transfer's received amount keeps the currency it was entered in, and the store refuses an
/// item whose received currency isn't To's current one, or is From's: at save, Undo, Redo and posting, with
/// nothing written. A legacy item with a received amount and no currency is refused too. Made-up data; today is
/// 20 Oct 2026.
@MainActor
@Suite("A received amount stays in the currency it was entered in (#207 B1)")
struct ScheduledReceivedCurrencyTests {
    private let card = Account(name: "Travel Card", type: .cash, currencyCode: "USD", sortOrder: 2)

    /// A list in a window whose Undo steps the list records, as `ScheduledFormUndoTests` makes it.
    private func window(_ scene: ScheduledScene) -> (ScheduledListViewModel, TestWindow) {
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

    /// Opens a new item's form filled in as Rent Share: ₹1,000 from Everyday Savings to Travel Card, received 12.
    private func newShare(_ list: ScheduledListViewModel, _ scene: ScheduledScene) throws -> ScheduledFormViewModel {
        list.openNew()
        let form = try #require(list.form)
        form.type = .transfer
        form.details = "Rent Share"
        form.amountText = "1000"
        form.accountID = scene.account.id
        form.transferAccountID = card.id
        form.receivedText = "12"
        return form
    }

    private func moveCard(_ scene: ScheduledScene, to code: String) throws {
        var moved = try #require(try scene.repository.accounts().first { $0.id == card.id })
        moved.currencyCode = code
        try scene.repository.saveAccount(moved)
    }

    private func items(_ scene: ScheduledScene) throws -> [ScheduledItem] {
        try scene.repository.scheduleLedger().scheduledItems
    }

    /// Rent Share stored as given, past the save's checks, as a store made before them would hold it.
    private func storeDirectly(_ scene: ScheduledScene, code: String?) throws -> ScheduledItem {
        var item = scene.item("Rent Share", day: 20, month: 10)
        item.type = .transfer
        item.amount = 1_000
        item.categoryID = nil
        item.transferAccountID = card.id
        item.destinationAmount = 12
        item.receivedCurrencyCode = code
        var ledger = try scene.repository.scheduleLedger()
        ledger.scheduledItems.append(item)
        try scene.repository.replaceLedger(with: ledger)
        return item
    }

    @Test("The form stores the received amount's currency with it, To's")
    func formStoresCurrency() throws {
        let scene = try ScheduledScene()
        try scene.repository.saveAccount(card)
        let (list, _) = window(scene)
        #expect(try newShare(list, scene).save())
        let item = try #require(try items(scene).first)
        #expect(item.destinationAmount == 12 && item.receivedCurrencyCode == "USD")
    }

    @Test("Tech Architect's repro: Redo after To moved from USD to EUR is refused, writes nothing and is dropped")
    func redoAfterToMoved() throws {
        let scene = try ScheduledScene()
        try scene.repository.saveAccount(card)
        let (list, window) = window(scene)
        #expect(try newShare(list, scene).save())
        window.history.undo()
        #expect(try items(scene).isEmpty)
        try moveCard(scene, to: "EUR")
        let before = try scene.repository.scheduleLedger()
        window.history.redo()
        #expect(window.history.alert?.title == "Can’t Redo New Scheduled Item Rent Share")
        #expect(window.history.alert?.message == "Rent Share has changed since then. Nothing was changed.")
        #expect(try scene.repository.scheduleLedger() == before)
        // The refused step goes, as any stale step does (D187.5); nothing is left to redo or undo.
        #expect(!window.undoManager.canRedo)
        #expect(!window.undoManager.canUndo)
    }

    @Test("Undo of an edit that moved To away is refused once the old To's currency changed; the step below stays")
    func undoOfToMove() throws {
        let scene = try ScheduledScene()
        try scene.repository.saveAccount(card)
        let (list, window) = window(scene)
        #expect(try newShare(list, scene).save())
        let id = try #require(try items(scene).first?.id)
        list.openEditor(id)
        let edit = try #require(list.form)
        edit.transferAccountID = scene.fund.id
        #expect(edit.save())
        #expect(try items(scene).first?.destinationAmount == nil, "Into an INR fund, there's no received amount")
        try moveCard(scene, to: "EUR")
        let before = try scene.repository.scheduleLedger()
        window.history.undo()
        #expect(window.history.alert?.title == "Can’t Undo Edit Rent Share")
        #expect(window.history.alert?.message == "Rent Share has changed since then. Nothing was changed.")
        #expect(try scene.repository.scheduleLedger() == before)
        // Only the refused step went: the new item's save is next, and nothing was added to Redo.
        #expect(window.undoManager.undoActionName == "New Scheduled Item Rent Share")
        #expect(!window.undoManager.canRedo)
    }

    @Test("A stale form's Save after To moved to EUR is refused with the stale message, keeps its edits, saves nothing")
    func staleFormRefused() throws {
        let scene = try ScheduledScene()
        try scene.repository.saveAccount(card)
        let (list, window) = window(scene)
        let form = try newShare(list, scene)
        try moveCard(scene, to: "EUR")
        #expect(!form.save())
        #expect(form.alert?.title == "Couldn’t Save Changes")
        #expect(form.alert?.message == "Travel Card has changed since then. Nothing was changed.")
        #expect(try items(scene).isEmpty)
        #expect(!window.undoManager.canUndo, "No step for a refused save")
        form.isAlertPresented = false
        #expect(!form.closeRequested, "The form stays open")
        #expect(form.receivedText == "12" && form.details == "Rent Share" && form.transferAccountID == card.id)
    }

    @Test("Posting refuses a received amount stored against To's old currency, and records nothing")
    func postingRefusesMismatch() throws {
        let scene = try ScheduledScene()
        try scene.repository.saveAccount(card)
        let item = try storeDirectly(scene, code: "GBP")
        #expect(throws: LedgerValidationError.receivedCurrencyMismatch) {
            try scene.useCases.manage.payNow(itemID: item.id, occurrence: item.startDay)
        }
        #expect(scene.recorded.isEmpty)
        let ledger = try scene.repository.scheduleLedger()
        let caughtUp = LedgerBook.catchingUpScheduledItems(
            in: {
                var automatic = ledger
                automatic.scheduledItems[0].processesAutomatically = true
                return automatic
            }(),
            today: item.startDay,
            now: scene.now,
        )
        #expect(caughtUp.result.failedItemIDs == [item.id] && caughtUp.result.posted.isEmpty)
    }

    @Test("A legacy item with a received amount and no currency is refused at save and at posting")
    func legacyRefused() throws {
        let scene = try ScheduledScene()
        try scene.repository.saveAccount(card)
        let item = try storeDirectly(scene, code: nil)
        let before = try scene.repository.scheduleLedger()
        #expect(throws: LedgerValidationError.receivedCurrencyMismatch) {
            try scene.useCases.manage.update(item, payee: nil)
        }
        #expect(throws: LedgerValidationError.receivedCurrencyMismatch) {
            try scene.useCases.manage.payNow(itemID: item.id, occurrence: item.startDay)
        }
        #expect(try scene.repository.scheduleLedger() == before)
        #expect(!LedgerBook.receivedCurrencyIsCurrent(of: item, in: before))
    }
}
