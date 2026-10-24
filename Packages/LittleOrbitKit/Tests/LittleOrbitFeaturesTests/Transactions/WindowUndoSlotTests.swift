import Foundation
import LittleOrbitDomain
import Testing

@testable import LittleOrbitFeatures

/// A window's view `init` runs on every rebuild; only the slot is made there, and the history once, on first
/// use (Tech Architect's N4 on #87).
@MainActor
@Suite("A window's undo history is made once")
struct WindowUndoSlotTests {
    @Test("The slot makes the history on first use and hands back the same one after that")
    func madeOnce() throws {
        let repository = try TransactionFeatureFixture.repository([])
        let feature = TransactionsFeature(
            useCases: TransactionUseCases(repository: repository, categoryNames: CatalogDefaultCategoryNames())
        )
        let slot = WindowUndoSlot()
        let history = slot.history(from: feature)
        #expect(slot.history(from: feature) === history)
        #expect(WindowUndoSlot().history(from: feature) !== history, "Another window gets its own")
    }
}
