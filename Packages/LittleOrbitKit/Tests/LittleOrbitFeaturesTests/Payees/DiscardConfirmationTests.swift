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
        let closes1 = confirmation.requestDismiss(isDirty: false)
        #expect(closes1)
        #expect(!confirmation.isPresented)
        let closes2 = confirmation.requestDismiss(isDirty: true)
        #expect(!closes2)
        #expect(confirmation.isPresented)
    }

    @Test("Edit Payee has unsaved edits once the name differs, and none once it's put back")
    func payeeEditorDirtyState() throws {
        let bakery = Payee(name: "Corner Bakery")
        let setup = try PayeesViewModelTests.Setup([bakery])
        let editor = try #require(setup.model.makeEditor(for: bakery.id))
        var confirmation = DiscardConfirmation()
        let closes3 = confirmation.requestDismiss(isDirty: editor.hasUnsavedEdits)
        #expect(closes3)
        editor.name = "Corner Cafe"
        let closes4 = confirmation.requestDismiss(isDirty: editor.hasUnsavedEdits)
        #expect(!closes4)
        #expect(confirmation.isPresented)
        confirmation = DiscardConfirmation()
        editor.name = "Corner Bakery"
        let closes5 = confirmation.requestDismiss(isDirty: editor.hasUnsavedEdits)
        #expect(closes5)
        #expect(try setup.payee(bakery.id)?.name == "Corner Bakery", "Discarding saves nothing")
    }
}
