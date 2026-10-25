import Foundation
import LittleOrbitDomain
import LittleOrbitFeatures
import LittleOrbitPersistence
import Testing

/// Tester's #201 Mac pass: the Edit menu names Pay, Skip and custom Pay ("Undo Pay Gym") from the undo manager ⌘Z
/// reaches, dimmed when there's nothing to undo (D285.5). The custom pay sheet's and the Scheduled alerts' controls,
/// unnamed in Tester's Mac accessibility pass at 59017dc, are named by their visible titles.
@MainActor
@Suite("Scheduled Undo menu names and button names (#201)")
struct ScheduledUndoMenuTests {
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

    private func menu(_ window: TestWindow) -> UndoMenuItems {
        UndoMenuItems(window.undoManager)
    }

    @Test("Before any step the menu reads Undo and Redo, both dimmed; with no window too")
    func plain() throws {
        let scene = try ScheduledScene()
        let (_, window) = window(scene)
        #expect(menu(window).undoTitle == "Undo")
        #expect(menu(window).redoTitle == "Redo")
        #expect(!menu(window).canUndo)
        #expect(!menu(window).canRedo)
        #expect(UndoMenuItems(nil) == menu(window))
    }

    @Test("Pay Now reaches the window's UndoManager as Pay Gym; the menu reads Undo Pay Gym, then Redo Pay Gym")
    func payNow() throws {
        let scene = try ScheduledScene()
        try scene.add(scene.item("Gym", day: 18, month: 10))
        let (list, window) = window(scene)
        list.payNow(try #require(list.overdueRows.first))
        #expect(window.undoManager.undoActionName == "Pay Gym")
        #expect(menu(window).undoTitle == "Undo Pay Gym")
        #expect(menu(window).canUndo)
        #expect(!menu(window).canRedo)
        window.history.undo()
        #expect(window.undoManager.redoActionName == "Pay Gym")
        #expect(menu(window).redoTitle == "Redo Pay Gym")
        #expect(menu(window).canRedo)
        #expect(menu(window).undoTitle == "Undo")
        #expect(!menu(window).canUndo)
        window.history.redo()
        #expect(menu(window).undoTitle == "Undo Pay Gym")
    }

    @Test("Skip reads Undo Skip Gym once confirmed")
    func skip() throws {
        let scene = try ScheduledScene()
        try scene.add(scene.item("Gym", day: 18, month: 10))
        let (list, window) = window(scene)
        list.confirmSkip(try #require(list.overdueRows.first))
        list.confirm()
        #expect(window.undoManager.undoActionName == "Skip Gym")
        #expect(menu(window).undoTitle == "Undo Skip Gym")
    }

    @Test("Custom Pay reads Undo Pay Gym")
    func customPay() throws {
        let scene = try ScheduledScene()
        try scene.add(scene.item("Gym", day: 18, month: 10))
        let (list, window) = window(scene)
        list.openCustomPay(try #require(list.overdueRows.first))
        let sheet = try #require(list.payment)
        sheet.amountText = "1350"
        #expect(sheet.record())
        #expect(menu(window).undoTitle == "Undo Pay Gym")
    }

    @Test("D285.5: the menu follows the manager ⌘Z reaches: a field's Typing, not the window's Pay Gym")
    func followsFocusedManager() throws {
        let scene = try ScheduledScene()
        try scene.add(scene.item("Gym", day: 18, month: 10))
        let (list, window) = window(scene)
        list.payNow(try #require(list.overdueRows.first))
        let field = FakeUndoManager()
        #expect(UndoMenuItems(field).undoTitle == "Undo")
        #expect(!UndoMenuItems(field).canUndo)
        field.registerStep(field, named: "Typing") {}
        #expect(UndoMenuItems(field).undoTitle == "Undo Typing")
        #expect(UndoMenuItems(field).canUndo)
        #expect(menu(window).undoTitle == "Undo Pay Gym")
    }

    @Test("The sheet's and the alerts' buttons and the checkbox are named by their visible titles")
    func buttonNames() throws {
        let scene = try ScheduledScene()
        try scene.add(scene.item("Gym", day: 18, month: 10))
        let (list, _) = window(scene)
        list.openCustomPay(try #require(list.overdueRows.first))
        let sheet = try #require(list.payment)
        #expect(sheet.cancelTitle == "Cancel")
        #expect(sheet.confirmTitle == "Record")
        #expect(sheet.okayTitle == "OK")
        #expect(sheet.changeFutureLabel == "Also change future occurrences")
        list.payment = nil
        list.confirmSkip(try #require(list.overdueRows.first))
        let confirmation = try #require(list.confirmation)
        #expect(!confirmation.confirmTitle.isEmpty)
        #expect(list.cancelTitle == "Cancel")
        #expect(list.okayTitle == "OK")
    }

    @Test("Undo of a custom Pay that changed future occurrences is stale once the old category is deleted")
    func staleAfterCategoryDeleted() throws {
        let scene = try ScheduledScene()
        let utilities = TransactionCategory(name: "Utilities", kind: .expense)
        try scene.repository.saveCategory(utilities)
        try scene.add(scene.item("Gym", day: 18, month: 10))
        let (list, window) = window(scene)
        list.openCustomPay(try #require(list.overdueRows.first))
        let sheet = try #require(list.payment)
        sheet.categoryID = utilities.id
        sheet.changesFutureOccurrences = true
        #expect(sheet.record())
        try scene.repository.deleteCategory(id: scene.housing.id, reassigningTo: nil)
        window.history.undo()
        #expect(window.history.alert?.title == "Can’t Undo Pay Gym")
        #expect(scene.recorded.count == 1)
        #expect(try scene.repository.scheduleLedger().scheduledItems.first?.categoryID == utilities.id)
    }
}
