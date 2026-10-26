import Foundation
import LittleOrbitDomain
import Testing

@testable import LittleOrbitFeatures

/// #258, D389.2: one window's Edit form is open on an item another window then deletes. Save shows “Couldn’t Save
/// Changes” naming the item, writes nothing (no item, no payee created or unarchived, no Undo step), and dismissing
/// it by any route (OK, or Esc on the Mac) closes the form; the item stays deleted. Made-up data.
@MainActor
@Suite("Scheduled Edit form after a delete elsewhere (#258)")
struct ScheduledDeletedEditFormTests {
    @Test("Save after a delete elsewhere: the alert names the item, nothing is saved and OK closes the form")
    func saveAfterDeleteElsewhere() throws {
        let scene = try ScheduledScene()
        let club = Payee(name: "Fit Club")
        let archived = Payee(name: "Old Gym", isArchived: true)
        try scene.repository.savePayee(club)
        try scene.repository.savePayee(archived)
        var gym = scene.item("Gym", day: 5, month: 11)
        gym.payeeID = club.id
        try scene.add(gym)
        let feature = scene.feature()
        // Window one's Undo history, listening to the same ledger updates.
        let transactions = TransactionUseCases(
            repository: scene.repository,
            categoryNames: CatalogDefaultCategoryNames(),
        )
        let history = WindowUndoHistory(
            changes: transactions.changes,
            loadLedger: transactions.loadLedger,
            updates: scene.updates,
        )
        let windowOne = scene.list(feature, platform: .macOS)
        windowOne.load()
        windowOne.openEditor(gym.id)
        let form = try #require(windowOne.form)
        // Window two deletes it through its own use cases.
        try scene.useCases.manage.delete(id: gym.id)
        let afterDelete = try scene.repository.scheduleLedger()
        let revision = scene.updates.revision
        let payees = try scene.repository.payees()
        form.amountText = "1,500"
        // Points the edit at the archived payee: a save that went through could unarchive it.
        form.payeeID = archived.id
        #expect(!form.save())
        #expect(
            form.alert
                == CategoryAlert(title: "Couldn’t Save Changes", message: "Gym has been deleted. Nothing was changed.")
        )
        #expect(form.alertClosesForm)
        #expect(try scene.repository.scheduleLedger() == afterDelete)
        #expect(scene.updates.revision == revision)
        #expect(try scene.repository.payees() == payees)
        #expect(try scene.repository.payees().first { $0.id == archived.id }?.isArchived == true)
        #expect(!history.canUndo)
        #expect(history.undoTitle == nil)
        #expect(try scene.useCases.load.listing().item(gym.id) == nil)
        #expect(form.isAlertPresented)
        #expect(!form.closeRequested)
        // OK: the alert's dismissal.
        form.isAlertPresented = false
        #expect(form.alert == nil)
        #expect(form.closeRequested)
        windowOne.load()
        #expect(windowOne.upcomingRows.isEmpty)
    }

    @Test("Any other save failure keeps the D306 alert, and dismissing it leaves the form open")
    func otherFailureKeepsTheFormOpen() throws {
        let scene = try ScheduledScene()
        let list = scene.list(scene.feature(), platform: .macOS)
        list.load()
        list.openNew()
        let form = try #require(list.form)
        form.alert = ScheduledText.saveFailed
        #expect(!form.alertClosesForm)
        form.isAlertPresented = false
        #expect(form.alert == nil)
        #expect(!form.closeRequested)
    }

    @Test("Esc, or any dismissal other than OK, closes the form after a delete elsewhere but not after another failure")
    func anyDismissalClosesOnlyTheDeletedItemForm() throws {
        let scene = try ScheduledScene()
        let gym = scene.item("Gym", day: 5, month: 11)
        try scene.add(gym)
        let list = scene.list(scene.feature(), platform: .macOS)
        list.load()
        list.openEditor(gym.id)
        let edit = try #require(list.form)
        try scene.useCases.manage.delete(id: gym.id)
        #expect(!edit.save())
        #expect(edit.alertClosesForm)
        // Esc on the Mac, a swipe or a dismissal SwiftUI makes on its own: the binding goes false without OK running.
        #expect(edit.isAlertPresented)
        edit.isAlertPresented = false
        #expect(edit.alert == nil)
        #expect(edit.closeRequested)
        // A second dismissal (OK's and the binding's together) changes nothing.
        edit.isAlertPresented = false
        #expect(edit.closeRequested)
        #expect(try scene.useCases.load.listing().item(gym.id) == nil)

        list.openNew()
        let new = try #require(list.form)
        new.alert = ScheduledText.saveFailed
        new.isAlertPresented = false
        #expect(new.alert == nil)
        #expect(!new.closeRequested)
        // Presenting true again is not a dismissal.
        new.alert = ScheduledText.saveFailed
        new.isAlertPresented = true
        #expect(new.alert == ScheduledText.saveFailed)
        #expect(!new.closeRequested)
    }

    @Test("After the item comes back, another save failure's alert leaves the form open")
    func laterFailureAfterTheItemComesBackKeepsTheFormOpen() throws {
        let scene = try ScheduledScene()
        let gym = scene.item("Gym", day: 5, month: 11)
        try scene.add(gym)
        let list = scene.list(scene.feature(), platform: .macOS)
        list.load()
        list.openEditor(gym.id)
        let form = try #require(list.form)
        try scene.useCases.manage.delete(id: gym.id)
        form.amountText = "1,500"
        #expect(!form.save())
        #expect(form.alertClosesForm)
        // The alert is still up when the item comes back, as an Undo in another window would bring it back.
        try scene.add(gym)
        // Points the edit at a payee that isn't stored, so the next save fails another way.
        form.payeeID = UUID()
        #expect(!form.save())
        #expect(form.alert == ScheduledText.saveFailed)
        #expect(!form.alertClosesForm)
        form.isAlertPresented = false
        #expect(form.alert == nil)
        #expect(!form.closeRequested)
        #expect(form.amountText == "1,500")
        #expect(try scene.repository.scheduleLedger().scheduledItems.map(\.amount) == [1_200])
    }

    @Test("An edit of a stored item still saves, and a new item still saves as new")
    func editAndAddStillSave() throws {
        let scene = try ScheduledScene()
        let gym = scene.item("Gym", day: 5, month: 11)
        try scene.add(gym)
        let list = scene.list(scene.feature(), platform: .iOS)
        list.load()
        list.openEditor(gym.id)
        let edit = try #require(list.form)
        edit.amountText = "1,500"
        #expect(edit.save())
        #expect(edit.alert == nil)
        #expect(try scene.repository.scheduleLedger().scheduledItems.map(\.amount) == [1_500])
        list.openNew()
        let new = try #require(list.form)
        new.amountText = "900"
        new.details = "Water"
        #expect(new.save())
        let stored = try scene.repository.scheduleLedger().scheduledItems
        #expect(stored.count == 2)
        #expect(stored.contains { $0.details == "Water" && $0.amount == 900 })
    }
}
