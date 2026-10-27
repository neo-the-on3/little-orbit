import Foundation
import LittleOrbitDomain
import LittleOrbitPersistence
import Testing

@testable import LittleOrbitFeatures

/// D399, Tester2's N5 at 4c6a128: an Edit menu opened before a Bulk Edit Apply still shows Undo and Redo enabled
/// while it runs, since AppKit validated it before. Choosing them then reaches each window's `UndoManager`
/// directly, past the toolbar's state, and must apply nothing, in the Apply's window and in every other.
@MainActor
@Suite("Edit menu Undo and Redo while a Bulk Edit Apply runs")
struct EditMenuDuringBatchTests {
    typealias F = TransactionFeatureFixture  // swiftlint:disable:this type_name

    static let rows = BulkEditBatchTests.rows(6)

    /// Gives row `index` a description as one ordinary step in `window`.
    static func earlierEdit(_ index: Int, in window: TestWindow, _ useCases: TransactionUseCases) throws {
        var edited = try #require(try useCases.loadLedger.ledger().transactions.first { $0.id == rows[index].id })
        edited.details = "Earlier edit \(index)"
        window.history.record(try useCases.saveTransactions.save([edited]))
    }

    static func details(_ index: Int, _ useCases: TransactionUseCases) throws -> String? {
        try useCases.loadLedger.ledger().transactions.first { $0.id == rows[index].id }?.details
    }

    @Test("Undo and Redo chosen from a stale menu, in any window, apply nothing; Undo works again after")
    func staleMenuDoesNothing() async throws {
        let repository = try F.repository(Self.rows)
        let useCases = TransactionUseCases(repository: repository, categoryNames: CatalogDefaultCategoryNames())
        let updates = LedgerUpdates()
        let window = TestWindow(useCases, updates: updates)
        let other = TestWindow(useCases, updates: updates)
        try Self.earlierEdit(0, in: window, useCases)
        try Self.earlierEdit(1, in: other, useCases)

        let model = BulkEditViewModel(
            loadLedger: useCases.loadLedger,
            applyBulkEdit: DefaultApplyBulkEditUseCase(repository: repository),
            transactionIDs: Self.rows.map(\.id),
        )
        model.updates = updates
        // No sheet: its timer mustn't fire on a slow run (review 5666870090).
        model.progressShowDelay = nil
        model.editsCategory = true
        model.categoryID = DefaultCategoryID.food
        let apply = Task { await model.applyInBackground() }
        while !updates.isBatchRunning {
            await Task.yield()
        }
        // The toolbar's state is off, as the menu would be if AppKit validated it again.
        #expect(!window.history.canUndo && !other.history.canUndo)
        // The menu's own commands, which that state doesn't stop.
        window.undoManager.undo()
        other.undoManager.undo()
        window.undoManager.redo()
        window.history.undo()
        other.history.redo()
        #expect(try Self.details(0, useCases) == "Earlier edit 0", "Not undone while the Apply runs")
        #expect(try Self.details(1, useCases) == "Earlier edit 1", "Not undone in the other window either")

        let change = try #require(await apply.value)
        window.settle()
        other.settle()
        #expect(change.transactionIDs.count == Self.rows.count)
        #expect(try Self.details(0, useCases) == "Earlier edit 0")
        #expect(try Self.details(1, useCases) == "Earlier edit 1")
        #expect(window.history.alert == nil && other.history.alert == nil)
        // The earlier steps are still there: once the Apply ends, Undo works in the other window.
        #expect(other.history.canUndo)
        other.history.undo()
        #expect(try Self.details(1, useCases) == nil)
    }
}
