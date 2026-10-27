import Foundation
import LittleOrbitDomain
import LittleOrbitPersistence
import Testing

@testable import LittleOrbitFeatures

/// Tester2's N5 at c8c6594 (comment 6440723910): an Edit › Undo clicked, or a ⌘Z pressed, while a batch Undo
/// saved waited in the event queue and undid one step more once the batch ended. A command whose event is no
/// newer than the last batch's end is dropped (Tech Architect's ruling).
@MainActor
@Suite("Undo and Redo queued during a batch")
struct QueuedCommandTests {
    typealias F = TransactionFeatureFixture  // swiftlint:disable:this type_name
    typealias Policy = QueuedCommandPolicy

    @Test("An event during the batch, or at its very end, is dropped")
    func duringBatch() {
        // A ⌘Z key press, or a menu click, at 100.6 s, during a batch that ended at 101.0 s.
        #expect(Policy.dropsCommand(eventTime: 100.6, lastBatchEnd: 101.0))
        #expect(Policy.dropsCommand(eventTime: 101.0, lastBatchEnd: 101.0))
    }

    @Test("An event after the end goes through")
    func afterBatch() {
        #expect(!Policy.dropsCommand(eventTime: 101.001, lastBatchEnd: 101.0))
        #expect(!Policy.dropsCommand(eventTime: 250, lastBatchEnd: 101.0))
    }

    @Test("No current event, or no batch yet: the command goes through")
    func noEventOrNoBatch() {
        #expect(!Policy.dropsCommand(eventTime: nil, lastBatchEnd: 101.0))
        #expect(!Policy.dropsCommand(eventTime: 100.6, lastBatchEnd: nil))
        #expect(!Policy.dropsCommand(eventTime: nil, lastBatchEnd: nil))
    }

    @Test("The batch's end is taken from the uptime clock when busy clears, and not before")
    func endRecordedWhenBusyClears() {
        let updates = LedgerUpdates()
        var now: TimeInterval = 50
        updates.uptime = { now }
        #expect(updates.lastBatchEnd == nil)
        #expect(updates.beginBatch())
        now = 51.5
        #expect(updates.lastBatchEnd == nil)
        updates.endBatch()
        #expect(updates.lastBatchEnd == 51.5)
    }

    /// An ordinary edit, then a Bulk Edit of the same rows, recorded in one window with a hand-driven clock.
    @MainActor
    struct Setup {
        let disk: FullDiskLedgerRepository
        let window: TestWindow
        let rows: [Transaction]

        func details(_ index: Int) throws -> String? {
            try disk.transactions().first { $0.id == rows[index].id }?.details
        }
    }

    static func setup(updates: LedgerUpdates) async throws -> Setup {
        let rows = (0..<5).map { F.expense(Decimal(100 * ($0 + 1)), on: F.date(2026, 10, 10 + $0)) }
        let disk = FullDiskLedgerRepository(try F.repository(rows))
        disk.hasBatchPath = true
        let useCases = TransactionUseCases(repository: disk, categoryNames: CatalogDefaultCategoryNames())
        let window = TestWindow(useCases, updates: updates)
        window.history.setScreen(.account(F.savingsID))
        var earlier = rows[0]
        earlier.details = "Earlier edit"
        window.history.record(try useCases.saveTransactions.save([earlier]))
        var changes = BulkEditChanges()
        changes.categoryID = .some(DefaultCategoryID.food)
        let request = BulkEditRequest(
            selection: try disk.transactions().filter { Set(rows.map(\.id)).contains($0.id) },
            changes: changes,
            payeeName: "",
            accounts: try disk.accounts(),
            timeZoneID: F.zoneID,
            now: F.now,
        )
        let change = try await useCases.bulkEdit.apply(request, reporting: .silent)
        window.history.record(change)
        window.history.markBulkEdit(change)
        return Setup(disk: disk, window: window, rows: rows)
    }

    @Test("Edit › Undo or ⌘Z queued during a batch Undo is ignored after it ends; a fresh Undo then works")
    func queuedUndoIgnored() async throws {
        let updates = LedgerUpdates()
        var now: TimeInterval = 100
        var eventTime: TimeInterval? = 100
        updates.uptime = { now }
        updates.currentEventTime = { eventTime }
        let setup = try await Self.setup(updates: updates)
        let history = setup.window.history

        // The toolbar Undo at 100 s starts the batch Undo of the Bulk Edit; it ends at 101 s.
        history.undo()
        #expect(history.isBatchRunning)
        now = 101
        await history.batchRun?.task.value
        #expect(!history.isBatchRunning)
        #expect(updates.lastBatchEnd == 101)
        let undoNames = setup.window.undoManager.undoNames
        let redoNames = setup.window.undoManager.redoNames
        #expect(undoNames.count == 1, "Only the earlier edit is on Undo")
        #expect(redoNames.count == 1, "Exactly one step for the batch, now on Redo (D403)")
        let undoTitle = history.undoTitle

        // The click (or ⌘Z) from 100.6 s, handled only now: the window's own Undo, as the Edit menu sends it.
        eventTime = 100.6
        setup.window.undoManager.undo()
        setup.window.settle()
        #expect(try setup.details(0) == "Earlier edit", "No extra step undone")
        #expect(history.undoTitle == undoTitle, "Still next on Undo")
        // D403: the earlier step is still on the stack, untouched, and the batch still has exactly one step.
        #expect(setup.window.undoManager.undoNames == undoNames)
        #expect(setup.window.undoManager.redoNames == redoNames)
        #expect(history.alert == nil)

        // A fresh ⌘Z after the end goes through.
        eventTime = 102
        now = 102
        history.undo()
        setup.window.settle()
        #expect(try setup.details(0) == nil)
    }

    @Test("Undo and Redo queued during a batch Redo are ignored too, and each step stays on Undo once (D403)")
    func queuedRedoIgnored() async throws {
        let updates = LedgerUpdates()
        var now: TimeInterval = 10
        var eventTime: TimeInterval? = 10
        updates.uptime = { now }
        updates.currentEventTime = { eventTime }
        let setup = try await Self.setup(updates: updates)
        let history = setup.window.history
        // Undo both steps: the Bulk Edit (a batch, ending at 11 s), then the earlier edit at 12 s.
        history.undo()
        now = 11
        await history.batchRun?.task.value
        eventTime = 12
        now = 12
        history.undo()
        setup.window.settle()
        #expect(try setup.details(0) == nil)
        // Redo the earlier edit at 13 s, then the Bulk Edit as a batch, which ends at 14 s.
        eventTime = 13
        history.redo()
        setup.window.settle()
        #expect(try setup.details(0) == "Earlier edit")
        history.redo()
        now = 14
        await history.batchRun?.task.value
        // The Bulk Edit is back on Undo, once, above the earlier edit (D403).
        let undoNames = setup.window.undoManager.undoNames
        #expect(undoNames.count == 2)
        #expect(setup.window.undoManager.redoNames.isEmpty)
        // A Redo click queued from 13.5 s, during that batch, is handled now; nothing is left to redo, but it
        // mustn't change anything either. Then the same for an Undo queued from 13.6 s.
        eventTime = 13.5
        setup.window.undoManager.redo()
        eventTime = 13.6
        setup.window.undoManager.undo()
        setup.window.settle()
        #expect(setup.window.undoManager.undoNames == undoNames, "Both steps still on Undo, once each")
        #expect(try setup.details(0) == "Earlier edit")
        #expect(
            try setup.disk.transactions().filter { Set(setup.rows.map(\.id)).contains($0.id) }
                .allSatisfy { $0.categoryID == DefaultCategoryID.food },
            "The Bulk Edit stays applied",
        )
    }
}
