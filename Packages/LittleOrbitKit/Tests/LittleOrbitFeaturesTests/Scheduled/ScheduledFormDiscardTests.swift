import Foundation
import LittleOrbitDomain
import Testing

@testable import LittleOrbitFeatures

/// D300.1 with D388 on the Scheduled form (#248): Cancel, Esc on the Mac or a swipe down with unsaved edits asks
/// “Discard Changes?”, and an Edit form's prompt names the item as it was saved. With nothing changed the form just
/// closes, and a tapped reminder never asks. Made-up data.
@MainActor
@Suite("Scheduled form: Discard Changes? (D300.1, D388, #248)")
struct ScheduledFormDiscardTests {
    let scene: ScheduledScene
    let rent: ScheduledItem
    let list: ScheduledListViewModel

    init() throws {
        scene = try ScheduledScene()
        rent = scene.item("Rent", day: 1)
        try scene.add(rent)
        list = scene.list(scene.feature(), platform: .iOS)
        list.load()
    }

    func editRent() throws -> ScheduledFormViewModel {
        list.openEditor(rent.id)
        return try #require(list.form)
    }

    @Test("Cancel with the amount changed asks, naming Rent; Keep Editing leaves the edit in place")
    func dirtyCancelAsks() throws {
        let form = try editRent()
        form.amountText = "26000"
        #expect(!form.requestDismiss(from: .cancel))
        #expect(form.discard.isPresentedFromCancel)
        #expect(!form.discard.isPresentedFromSwipe)
        #expect(form.discardMessage == "Your changes to Rent won’t be saved.")
        // Keep Editing closes only the prompt: the sheet and its edit stay.
        form.discard.isPresentedFromCancel = false
        #expect(!form.discard.isPresented)
        #expect(form.amountText == "26000")
        #expect(list.form === form)
        // Discard Changes closes the sheet; nothing was saved, so Rent is as it was.
        let before = list.listing.item(rent.id)
        list.form = nil
        list.load()
        #expect(list.listing.item(rent.id) == before)
        #expect(list.listing.item(rent.id)?.amount == 1_200)
    }

    @Test("Renamed but not saved, the message still names the item as it was saved")
    func savedNameInMessage() throws {
        let form = try editRent()
        form.details = "Flat Rent"
        #expect(!form.requestDismiss(from: .cancel))
        #expect(form.discardMessage == "Your changes to Rent won’t be saved.")
    }

    @Test("A swipe down with unsaved edits asks from the swipe's own dialog, with the same message")
    func swipeAsks() throws {
        let form = try editRent()
        form.note = "Landlord"
        #expect(!form.requestDismiss(from: .swipe))
        #expect(form.discard.isPresentedFromSwipe)
        #expect(!form.discard.isPresentedFromCancel)
        #expect(form.discardMessage == "Your changes to Rent won’t be saved.")
    }

    @Test("Nothing changed, or changed and put back: Cancel and a swipe close without asking")
    func cleanCloses() throws {
        let form = try editRent()
        #expect(form.requestDismiss(from: .cancel))
        #expect(form.requestDismiss(from: .swipe))
        form.note = "Landlord"
        form.note = ""
        #expect(form.requestDismiss(from: .cancel))
        #expect(!form.discard.isPresented)
    }

    @Test("A new item: empty, Cancel closes; with input, the same prompt with no message (D300 amendment)")
    func newItem() throws {
        list.openNew()
        let form = try #require(list.form)
        #expect(form.requestDismiss(from: .cancel))
        #expect(form.discardMessage == nil)
        form.amountText = "1200"
        #expect(!form.requestDismiss(from: .cancel))
        #expect(form.discard.isPresentedFromCancel)
        #expect(form.discardMessage == nil)
    }

    typealias Field = ScheduledReminderSheetTests.FormField

    @Test("Changing only one editable field makes Cancel ask (D385)", arguments: Field.allCases)
    func everyFieldAsks(_ field: Field) throws {
        let form = try editRent()
        field.change(form, scene)
        #expect(!form.requestDismiss(from: .cancel), "\(field.rawValue)")
        #expect(form.discard.isPresentedFromCancel)
    }

    @Test("A tapped reminder never asks: a form with unsaved edits just stays open (D383, D388.3)")
    func reminderTapDoesNotAsk() throws {
        let form = try editRent()
        let sheets = OpenSheets()
        sheets.opened(UUID(), hasUnsavedEdits: { form.hasUnsavedEdits }, close: { list.form = nil })
        form.amountText = "26000"
        #expect(sheets.prepareForReminder() == .underneath)
        #expect(!form.discard.isPresented)
        #expect(list.form === form)
        #expect(form.amountText == "26000")
    }

    @Test("D388.1: with no name, the message reads “Your changes won’t be saved.”")
    func messageWithoutName() {
        #expect(ScheduledText.discardMessage("") == "Your changes won’t be saved.")
        #expect(ScheduledText.discardMessage("Phone Plan") == "Your changes to Phone Plan won’t be saved.")
    }
}
