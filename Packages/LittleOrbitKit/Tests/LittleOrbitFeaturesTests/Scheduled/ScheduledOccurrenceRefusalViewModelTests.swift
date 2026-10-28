import Foundation
import LittleOrbitDomain
import Testing

@testable import LittleOrbitFeatures

/// The Scheduled form's refused occurrence edits: a new Due Date the item already has an occurrence on (D381.1) and
/// "This occurrence only" for an occurrence paid or skipped in another window since the form opened (D381.2). Each
/// shows its alert with OK only, saves nothing and leaves the form open with its edits. Made-up data.
@MainActor
private struct OpenForm {
    let scene: ScheduledScene
    let list: ScheduledListViewModel
    let form: ScheduledFormViewModel
}

@MainActor
@Suite("Scheduled form: refused occurrence edits (D381.1, D381.2)")
struct ScheduledOccurrenceRefusalViewModelTests {
    private let october = CalendarDay(year: 2026, month: 10, day: 1)

    /// A manual Rent of ₹1,200, monthly on the 1st from 1 Aug 2026; today is 20 Oct, so Aug, Sep and Oct are
    /// overdue. The form is open on 1 Oct.
    private func openOctober() throws -> OpenForm {
        let scene = try ScheduledScene()
        try scene.add(scene.item("Rent", day: 1))
        let list = scene.list(scene.feature(), platform: .iOS)
        list.load()
        let row = try #require(list.overdueRows.first { $0.editOccurrence == october })
        list.openEditor(row)
        return OpenForm(scene: scene, list: list, form: try #require(list.form))
    }

    private func ledger(_ scene: ScheduledScene) throws -> [ScheduledItem] {
        try scene.repository.scheduleLedger().scheduledItems
    }

    @Test("D381.1: All future occurrences moved onto 1 Sep: “Can’t Move to 1 Sep”, nothing saved, form open")
    func cantMove() throws {
        let open = try openOctober()
        let (scene, list, form) = (open.scene, open.list, open.form)
        let before = try ledger(scene)
        form.dueDay = CalendarDay(year: 2026, month: 9, day: 1)
        #expect(!form.save())
        #expect(form.scopeQuestion != nil)
        #expect(!form.save(scope: .allFuture))
        let alert = try #require(form.alert)
        #expect(alert.title == "Can’t Move to 1 Sep")
        #expect(
            alert.message
                == "Rent already has an occurrence on 1 Sep. Pick another day, or change that occurrence first."
        )
        #expect(try ledger(scene) == before)
        #expect(!form.isFinished)
        form.isAlertPresented = false
        #expect(!form.closeRequested)
        #expect(list.form === form)
        #expect(form.dueDay == CalendarDay(year: 2026, month: 9, day: 1))
    }

    @Test("D381.2: 1 Oct skipped in another window, then This occurrence only: “Couldn’t Save Changes”, form open")
    func staleForm() throws {
        let open = try openOctober()
        let (scene, list, form) = (open.scene, open.list, open.form)
        let rent = try #require(try ledger(scene).first)
        _ = try scene.useCases.manage.skip(itemID: rent.id, occurrence: october)
        let before = try ledger(scene)
        form.amountText = "1300"
        #expect(!form.save())
        #expect(!form.save(scope: .thisOccurrence))
        let alert = try #require(form.alert)
        #expect(alert.title == "Couldn’t Save Changes")
        #expect(alert.message == "Rent has changed since then. Nothing was changed.")
        #expect(try ledger(scene) == before)
        form.isAlertPresented = false
        #expect(!form.closeRequested)
        #expect(list.form === form)
        #expect(form.amountText == "1300")
    }
}
