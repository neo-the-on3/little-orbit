import Foundation
import LittleOrbitDomain
import LittleOrbitFeatures
import LittleOrbitPersistence
import Testing

/// The Scheduled form's save as one Undo step in the window's history (D351.1, D340.9, D352.2).
@MainActor
@Suite("Scheduled form save Undo (#197)")
struct ScheduledFormUndoTests {
    /// A list in a window whose Undo steps the list records.
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

    private func saveNew(_ list: ScheduledListViewModel, payee: String? = nil, category: UUID? = nil) throws {
        list.openNew()
        let form = try #require(list.form)
        form.details = "Rent"
        form.amountText = "1200"
        form.categoryID = category
        if let payee {
            form.payeeText = payee
            form.createPayee()
        }
        #expect(form.save())
        list.load()
    }

    private func livePayees(_ scene: ScheduledScene) throws -> [Payee] {
        try scene.repository.payees().filter { $0.deletedAt == nil }
    }

    @Test("D351.1: a new item is the step New Scheduled Item Rent; one Undo removes it and its new payee, Redo both")
    func newItemWithPayee() throws {
        let scene = try ScheduledScene()
        let (list, window) = window(scene)
        try saveNew(list, payee: "Gym Co")
        #expect(window.undoManager.undoActionName == "New Scheduled Item Rent")
        #expect(try livePayees(scene).map(\.name) == ["Gym Co"])
        window.history.undo()
        #expect(try scene.repository.scheduleLedger().scheduledItems.isEmpty)
        #expect(try livePayees(scene).isEmpty)
        #expect(window.undoManager.redoActionName == "New Scheduled Item Rent")
        window.history.redo()
        #expect(try scene.repository.scheduleLedger().scheduledItems.count == 1)
        #expect(try livePayees(scene).map(\.name) == ["Gym Co"])
    }

    @Test("D340.9: saving an edit is the step Edit Rent; Undo puts the old amount back")
    func editItem() throws {
        let scene = try ScheduledScene()
        let (list, window) = window(scene)
        try saveNew(list)
        let id = try #require(try scene.repository.scheduleLedger().scheduledItems.first?.id)
        list.openEditor(id)
        let form = try #require(list.form)
        form.amountText = "1500"
        #expect(form.save())
        #expect(window.undoManager.undoActionName == "Edit Rent")
        window.history.undo()
        #expect(try scene.repository.scheduleLedger().scheduledItems.first?.amount == 1200)
    }

    @Test("D352.2: after an occurrence is recorded, Undo can't undo the save and changes nothing")
    func staleAfterRecorded() throws {
        let scene = try ScheduledScene()
        let (list, window) = window(scene)
        try saveNew(list)
        let row = try #require((list.overdueRows + list.dueTodayRows).first)
        list.recordStep = { _, _, _ in }
        list.payNow(row)
        #expect(scene.recorded.count == 1)
        window.history.undo()
        #expect(window.history.alert?.title == "Can’t Undo New Scheduled Item Rent")
        #expect(try scene.repository.scheduleLedger().scheduledItems.count == 1)
        #expect(scene.recorded.count == 1)
    }

    @Test("D352.2: with nothing recorded since, Undo removes the new item with no alert")
    func cleanUndo() throws {
        let scene = try ScheduledScene()
        let (list, window) = window(scene)
        try saveNew(list)
        window.history.undo()
        #expect(window.history.alert == nil)
        #expect(try scene.repository.scheduleLedger().scheduledItems.isEmpty)
    }

    @Test("B1: Undo of an edit after its old category was deleted reads Can’t Undo Edit Rent and changes nothing")
    func undoEditStaleAfterCategoryDeleted() throws {
        let scene = try ScheduledScene()
        let utilities = TransactionCategory(name: "Utilities", kind: .expense)
        try scene.repository.saveCategory(utilities)
        let (list, window) = window(scene)
        try saveNew(list, category: scene.housing.id)
        let id = try #require(try scene.repository.scheduleLedger().scheduledItems.first?.id)
        list.openEditor(id)
        let form = try #require(list.form)
        form.categoryID = utilities.id
        #expect(form.save())
        try scene.repository.deleteCategory(id: scene.housing.id, reassigningTo: nil)
        window.history.undo()
        #expect(window.history.alert?.title == "Can’t Undo Edit Rent")
        #expect(try scene.repository.scheduleLedger().scheduledItems.first?.categoryID == utilities.id)
    }

    @Test("B1: Redo of a new item after its category was deleted reads Can’t Redo New Scheduled Item Rent")
    func redoNewStaleAfterCategoryDeleted() throws {
        let scene = try ScheduledScene()
        let (list, window) = window(scene)
        try saveNew(list, payee: "Gym Co", category: scene.housing.id)
        window.history.undo()
        try scene.repository.deleteCategory(id: scene.housing.id, reassigningTo: nil)
        window.history.redo()
        #expect(window.history.alert?.title == "Can’t Redo New Scheduled Item Rent")
        #expect(try scene.repository.scheduleLedger().scheduledItems.isEmpty)
        #expect(try livePayees(scene).isEmpty)
    }

    /// Saves a new Rent, then an edit of it to 1,500, and returns the item's ID.
    private func saveAndEdit(_ list: ScheduledListViewModel, _ scene: ScheduledScene) throws -> UUID {
        try saveNew(list, payee: "Gym Co")
        let id = try #require(try scene.repository.scheduleLedger().scheduledItems.first?.id)
        list.openEditor(id)
        let form = try #require(list.form)
        form.amountText = "1500"
        #expect(form.save())
        return id
    }

    @Test("#258: Undo of an edit after the item was deleted elsewhere is refused and dropped, as a stale step is")
    func undoEditAfterDeleteElsewhere() throws {
        let scene = try ScheduledScene()
        let (list, window) = window(scene)
        let id = try saveAndEdit(list, scene)
        try scene.useCases.manage.delete(id: id)
        let afterDelete = try scene.repository.scheduleLedger()
        window.history.undo()
        #expect(window.history.alert?.title == "Can’t Undo Edit Rent")
        #expect(window.history.alert?.message == "Rent has been deleted. Nothing was changed.")
        #expect(try scene.repository.scheduleLedger() == afterDelete)
        #expect(try livePayees(scene).map(\.name) == ["Gym Co"])
        // The step went; the one below it, the new item's save, is next.
        #expect(window.undoManager.undoActionName == "New Scheduled Item Rent")
        #expect(!window.undoManager.canRedo)
    }

    @Test("#258: Redo of an edit after the item was deleted elsewhere is refused and dropped, and nothing comes back")
    func redoEditAfterDeleteElsewhere() throws {
        let scene = try ScheduledScene()
        let (list, window) = window(scene)
        let id = try saveAndEdit(list, scene)
        window.history.undo()
        try scene.useCases.manage.delete(id: id)
        let afterDelete = try scene.repository.scheduleLedger()
        window.history.redo()
        #expect(window.history.alert?.title == "Can’t Redo Edit Rent")
        #expect(window.history.alert?.message == "Rent has been deleted. Nothing was changed.")
        #expect(try scene.repository.scheduleLedger() == afterDelete)
        #expect(try scene.repository.scheduleLedger().scheduledItems.isEmpty)
        #expect(try livePayees(scene).map(\.name) == ["Gym Co"])
        #expect(!window.undoManager.canRedo)
    }
}
