import Foundation
import LittleOrbitDomain
import LittleOrbitFeatures
import Testing

/// D300.1: Cancel or a swipe down asks “Discard Changes?” only when the sheet has unsaved edits.
@MainActor
@Suite("Discard Changes? prompt")
struct DiscardConfirmationTests {
    @Test("With no edits the sheet just closes; with unsaved edits it asks first")
    func requestDismiss() {
        var confirmation = DiscardConfirmation()
        let closes1 = confirmation.requestDismiss(isDirty: false, from: .cancel)
        #expect(closes1)
        #expect(!confirmation.isPresented)
        let closes2 = confirmation.requestDismiss(isDirty: true, from: .cancel)
        #expect(!closes2)
        #expect(confirmation.isPresented)
        #expect(confirmation.isPresentedFromCancel)
        #expect(!confirmation.isPresentedFromSwipe)
    }

    @Test("Cancel and a swipe each open their own dialog, and closing one clears the prompt")
    func source() {
        var confirmation = DiscardConfirmation()
        _ = confirmation.requestDismiss(isDirty: true, from: .swipe)
        #expect(confirmation.source == .swipe)
        #expect(confirmation.isPresentedFromSwipe)
        #expect(!confirmation.isPresentedFromCancel, "The Cancel button's dialog stays closed")
        confirmation.isPresentedFromCancel = false
        #expect(confirmation.isPresentedFromSwipe, "Closing the other dialog leaves this one open")
        confirmation.isPresentedFromSwipe = false
        #expect(!confirmation.isPresented)
        _ = confirmation.requestDismiss(isDirty: true, from: .cancel)
        #expect(confirmation.isPresentedFromCancel)
        #expect(!confirmation.isPresentedFromSwipe)
        confirmation.isPresentedFromCancel = false
        #expect(confirmation.source == nil)
        let closes = confirmation.requestDismiss(isDirty: false, from: .swipe)
        #expect(closes)
        #expect(!confirmation.isPresented, "With no edits nothing opens")
    }

    @Test("Edit Payee has unsaved edits once the name differs, and none once it's put back")
    func payeeEditorDirtyState() throws {
        let bakery = Payee(name: "Corner Bakery")
        let setup = try PayeesViewModelTests.Setup([bakery])
        let editor = try #require(setup.model.makeEditor(for: bakery.id))
        var confirmation = DiscardConfirmation()
        let closes3 = confirmation.requestDismiss(isDirty: editor.hasUnsavedEdits, from: .cancel)
        #expect(closes3)
        editor.name = "Corner Cafe"
        let closes4 = confirmation.requestDismiss(isDirty: editor.hasUnsavedEdits, from: .cancel)
        #expect(!closes4)
        #expect(confirmation.isPresented)
        confirmation = DiscardConfirmation()
        editor.name = "Corner Bakery"
        let closes5 = confirmation.requestDismiss(isDirty: editor.hasUnsavedEdits, from: .cancel)
        #expect(closes5)
        #expect(try setup.payee(bakery.id)?.name == "Corner Bakery", "Discarding saves nothing")
    }
}
