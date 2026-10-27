import Foundation
import LittleOrbitDomain
import LittleOrbitPersistence
import Testing

@testable import LittleOrbitFeatures

/// #285, D398: a Bulk Edit's Undo and Redo register the step at once, finish off the main actor, and keep Undo and
/// Redo off while they run; a failed or cancelled one writes nothing and leaves no step behind (Tech Architect's
/// ruling 3 on 6435113427).
@MainActor
@Suite("Window undo history: a Bulk Edit's Undo and Redo run as a batch")
struct WindowUndoBatchTests {
    typealias F = TransactionFeatureFixture  // swiftlint:disable:this type_name

    @MainActor
    struct Setup {
        let disk: FullDiskLedgerRepository
        let window: TestWindow
        let rows: [Transaction]
        let edited: [Transaction]
        var history: WindowUndoHistory { window.history }

        func stored() throws -> [Transaction] {
            let ids = Set(rows.map(\.id))
            return try disk.transactions().filter { ids.contains($0.id) }.sorted { $0.date < $1.date }
        }
    }

    static let name = "Edit 5 Transactions in Everyday Savings"

    /// Five expenses given a description by one Bulk Edit, recorded as the window records it.
    static func setup(updates: LedgerUpdates = LedgerUpdates()) async throws -> Setup {
        let rows = (0..<5).map { F.expense(Decimal(100 * ($0 + 1)), on: F.date(2026, 10, 10 + $0)) }
        let disk = FullDiskLedgerRepository(try F.repository(rows))
        disk.hasBatchPath = true
        let useCases = TransactionUseCases(repository: disk, categoryNames: CatalogDefaultCategoryNames())
        let window = TestWindow(useCases, updates: updates)
        window.history.setScreen(.account(F.savingsID))
        var changes = BulkEditChanges()
        changes.details = .some("Bulk")
        let request = BulkEditRequest(
            selection: rows,
            changes: changes,
            payeeName: "",
            accounts: try disk.accounts(),
            timeZoneID: F.zoneID,
            now: F.now,
        )
        let change = try await useCases.bulkEdit.apply(request, reporting: .silent)
        window.history.record(change)
        window.history.markBulkEdit(change)
        let setup = Setup(disk: disk, window: window, rows: rows, edited: [])
        return Setup(disk: disk, window: window, rows: rows, edited: try setup.stored())
    }

    func finish(_ history: WindowUndoHistory) async {
        await history.batchRun?.task.value
    }

    @Test("Undo registers the step on Redo at once, keeps Undo and Redo off while it runs, then puts the rows back")
    func undo() async throws {
        let setup = try await Self.setup()
        #expect(setup.edited.allSatisfy { $0.details == "Bulk" })
        setup.history.undo()
        #expect(setup.window.undoManager.redoNames == [Self.name], "Registered while undoing")
        #expect(setup.history.isBatchRunning)
        #expect(!setup.history.canUndo && !setup.history.canRedo)
        #expect(setup.history.batchProgress?.kind == .undoing)
        #expect(setup.history.batchProgress?.total == 5)
        await finish(setup.history)
        #expect(try setup.stored().allSatisfy { $0.details == nil })
        #expect(!setup.history.isBatchRunning)
        #expect(setup.history.batchProgress == nil)
        #expect(setup.history.canRedo)
        #expect(setup.history.redoTitle == Self.name)
        #expect(setup.window.announcements == ["Undid \(Self.name)"])
        #expect(setup.history.alert == nil)
    }

    @Test("Redo after Undo applies the edit again, through the same batch path")
    func redo() async throws {
        let setup = try await Self.setup()
        setup.history.undo()
        await finish(setup.history)
        setup.history.redo()
        #expect(setup.window.undoManager.undoNames == [Self.name])
        #expect(setup.history.batchProgress?.kind == .redoing)
        await finish(setup.history)
        #expect(try setup.stored().allSatisfy { $0.details == "Bulk" })
        #expect(setup.history.undoTitle == Self.name)
        #expect(setup.window.announcements == ["Undid \(Self.name)", "Redid \(Self.name)"])
    }

    @Test("A Cmd-Z while the batch runs applies nothing: Undo isn't queued (D398)")
    func commandWhileBusy() async throws {
        let setup = try await Self.setup()
        setup.history.undo()
        // The Edit menu's own Redo, which the toolbar state doesn't stop.
        setup.window.undoManager.redo()
        setup.window.settle()
        await finish(setup.history)
        setup.window.settle()
        #expect(try setup.stored().allSatisfy { $0.details == nil }, "Undone once, not redone")
        #expect(setup.window.undoManager.redoNames.last == Self.name)
    }

    @Test("Writes are off in another window while the batch runs, and on again after")
    func otherWindow() async throws {
        let updates = LedgerUpdates()
        let setup = try await Self.setup(updates: updates)
        let other = TestWindow(
            TransactionUseCases(repository: setup.disk, categoryNames: CatalogDefaultCategoryNames()),
            updates: updates,
        )
        setup.history.undo()
        #expect(other.history.isBatchRunning)
        await finish(setup.history)
        #expect(!other.history.isBatchRunning)
    }

    @Test("Closing the window mid-build writes nothing and leaves no step on either list")
    func cancelled() async throws {
        let setup = try await Self.setup()
        let revision = setup.disk.revision
        setup.history.undo()
        let task = setup.history.batchRun?.task
        setup.history.cancelBatch()
        await task?.value
        #expect(try setup.stored() == setup.edited, "Nothing was written")
        #expect(setup.disk.revision == revision)
        #expect(setup.window.undoManager.undoNames.isEmpty)
        #expect(setup.window.undoManager.redoNames.isEmpty)
        #expect(setup.history.alert == nil)
        #expect(!setup.history.isBatchRunning)
        #expect(setup.history.batchProgress == nil)
        #expect(!setup.history.canUndo && !setup.history.canRedo)
    }

    @Test("A failed write drops the step and says so; nothing was written (D398)")
    func failed() async throws {
        let setup = try await Self.setup()
        setup.disk.isFull = true
        setup.history.undo()
        await finish(setup.history)
        #expect(try setup.stored() == setup.edited)
        #expect(setup.window.undoManager.undoNames.isEmpty)
        #expect(setup.window.undoManager.redoNames.isEmpty)
        #expect(setup.history.alert?.title == "Couldn’t Undo \(Self.name)")
        #expect(setup.history.alert?.message == WindowUndoFailureTests.removedMessage)
        #expect(!setup.history.isBatchRunning)
    }

    @Test("A step another window made stale is removed with the stale alert; nothing is written")
    func stale() async throws {
        let setup = try await Self.setup()
        var changed = setup.edited[0]
        changed.details = "Elsewhere"
        try setup.disk.saveTransaction(changed)
        setup.history.undo()
        await finish(setup.history)
        #expect(setup.window.undoManager.redoNames.isEmpty)
        #expect(setup.history.alert?.title == "Can’t Undo \(Self.name)")
    }
}
