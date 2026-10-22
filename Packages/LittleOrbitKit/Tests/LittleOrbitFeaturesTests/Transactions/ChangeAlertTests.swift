import Foundation
import LittleOrbitDomain
import LittleOrbitFeatures
import Testing

/// The alerts after the user's own change, not an Undo or Redo (D204, #93 T16). The unreadable-accounts case
/// is `WindowUndoHistoryTests.unreadablePlace`.
@MainActor
@Suite("Alerts after a change")
struct ChangeAlertTests {
    @Test("T16: a change that can't be read back has no step, and the alert has the change's own title (D204)")
    func unreadableChange() {
        let fake = FakeTransactionUseCases()
        fake.outcomeError = FakeTransactionUseCases.Failure()
        let window = TestWindow(fake.useCases)
        window.history.record(.removed([RemovedTransaction(transaction: Transaction(type: .expense, amount: 1))]))
        #expect(!window.history.canUndo)
        #expect(window.history.alert?.title == "Couldn’t Make the Change")
        #expect(
            window.history.alert?.message == "Your change was saved, but couldn’t be read back, so it can’t be undone."
        )
    }
}
