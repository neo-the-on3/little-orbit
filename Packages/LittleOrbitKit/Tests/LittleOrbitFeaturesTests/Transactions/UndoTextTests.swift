import Foundation
import LittleOrbitDomain
import Testing

@testable import LittleOrbitFeatures

/// The off-screen notice, the VoiceOver announcement and the undo failure alerts come from the String
/// Catalog, with catalog plurals for the notice (Tech Architect's N3 on #87). The English wording is unchanged.
@Suite("Undo notice, announcement and failure text")
struct UndoTextTests {
    @Test("The notice counts transactions with the singular for one")
    func noticePlurals() {
        #expect(UndoText.notice(.restored, count: 5) == "Restored 5 transactions")
        #expect(UndoText.notice(.restored, count: 1) == "Restored 1 transaction")
        #expect(UndoText.notice(.deleted, count: 2) == "Deleted 2 transactions")
        #expect(UndoText.notice(.deleted, count: 1) == "Deleted 1 transaction")
        #expect(UndoText.notice(.updated, count: 3) == "Updated 3 transactions")
        #expect(UndoText.notice(.updated, count: 1) == "Updated 1 transaction")
    }

    @Test("An account's notice, the announcements and the failure alerts keep their English wording")
    func wording() {
        #expect(UndoText.restoredAccount("Rewards Card") == "Restored Rewards Card")
        #expect(UndoText.deletedAccount("Rewards Card") == "Deleted Rewards Card")
        #expect(UndoText.undid("Delete Transaction") == "Undid Delete Transaction")
        #expect(UndoText.redid("Delete Transaction") == "Redid Delete Transaction")
        #expect(UndoText.changeFailedTitle == "Couldn’t Make the Change")
        #expect(
            UndoText.couldntUndo("Edit Transaction in Household Card")
                == "Couldn’t Undo Edit Transaction in Household Card"
        )
        #expect(
            UndoText.couldntRedo("New Transaction in Household Card")
                == "Couldn’t Redo New Transaction in Household Card"
        )
        #expect(UndoText.unreadablePlace == "Couldn’t read your accounts, so Undo may not say where this change was.")
        #expect(UndoText.unreadableChange == "Your change was saved, but couldn’t be read back, so it can’t be undone.")
        #expect(UndoText.saveFailed == "Something went wrong saving your change. Please try again.")
        #expect(UndoText.removedFromHistory == "This change was removed from Undo history.")
    }

    @Test("X8c, T16: a failure says Couldn’t Undo or Redo, a blocked step Can’t, and a change its own title")
    func failureTitlesStayApart() {
        let name = "Edit Transaction in Household Card"
        #expect(StaleText.cantUndo(name) == "Can’t Undo \(name)")
        #expect(StaleText.cantRedo(name) == "Can’t Redo \(name)")
        let titles = [
            StaleText.cantUndo(name), StaleText.cantRedo(name), UndoText.couldntUndo(name), UndoText.couldntRedo(name),
            UndoText.changeFailedTitle,
        ]
        #expect(Set(titles).count == titles.count, "Five separate strings")
        #expect(!UndoText.couldntUndo(name).contains("Make the Change"))
        #expect(!UndoText.changeFailedTitle.contains(name))
    }
}
