import Foundation
import LittleOrbitDomain
import LittleOrbitPersistence
import Testing

@testable import LittleOrbitFeatures

/// Tester2's N5 at c8c6594 (comment 6440723910): an Edit › Undo clicked, or a ⌘Z pressed, while a batch Undo
/// saved waited in the event queue and undid one step more once the batch ended. A command whose event falls
/// inside the last batch, start to end, is dropped, and an event drops at most one command (Tech Architect's
/// rulings; review 5666694381 for the stale `NSApp.currentEvent` an Accessibility press sees).
@MainActor
@Suite("Undo and Redo queued during a batch")
struct QueuedCommandTests {
    typealias F = TransactionFeatureFixture  // swiftlint:disable:this type_name
    typealias Policy = QueuedCommandPolicy

    /// A batch that started at 100.0 s and ended at 101.0 s.
    static let batch: ClosedRange<TimeInterval> = 100.0...101.0

    @Test("An event during the batch, or at its very start or end, is dropped")
    func duringBatch() {
        // A ⌘Z key press, or a menu click, at 100.6 s, during the batch.
        #expect(Policy.dropsCommand(eventTime: 100.6, lastBatch: Self.batch, lastDroppedEventTime: nil))
        #expect(Policy.dropsCommand(eventTime: 100.0, lastBatch: Self.batch, lastDroppedEventTime: nil))
        #expect(Policy.dropsCommand(eventTime: 101.0, lastBatch: Self.batch, lastDroppedEventTime: nil))
    }

    @Test("An event after the end goes through")
    func afterBatch() {
        #expect(!Policy.dropsCommand(eventTime: 101.001, lastBatch: Self.batch, lastDroppedEventTime: nil))
        #expect(!Policy.dropsCommand(eventTime: 250, lastBatch: Self.batch, lastDroppedEventTime: nil))
    }

    @Test("An event from before the batch started goes through: the stale current event an AX press sees")
    func beforeBatch() {
        #expect(!Policy.dropsCommand(eventTime: 99.999, lastBatch: Self.batch, lastDroppedEventTime: nil))
        #expect(!Policy.dropsCommand(eventTime: 3, lastBatch: Self.batch, lastDroppedEventTime: nil))
    }

    @Test("An event that already dropped a command drops no other")
    func oneDropPerEvent() {
        #expect(!Policy.dropsCommand(eventTime: 100.6, lastBatch: Self.batch, lastDroppedEventTime: 100.6))
        #expect(Policy.dropsCommand(eventTime: 100.7, lastBatch: Self.batch, lastDroppedEventTime: 100.6))
    }

    @Test("No current event, or no batch yet: the command goes through")
    func noEventOrNoBatch() {
        #expect(!Policy.dropsCommand(eventTime: nil, lastBatch: Self.batch, lastDroppedEventTime: nil))
        #expect(!Policy.dropsCommand(eventTime: 100.6, lastBatch: nil, lastDroppedEventTime: nil))
        #expect(!Policy.dropsCommand(eventTime: nil, lastBatch: nil, lastDroppedEventTime: nil))
    }

    @Test("The batch's start and end are taken from the uptime clock when busy sets and clears")
    func batchRecordedWhenBusyChanges() {
        let updates = LedgerUpdates()
        var now: TimeInterval = 50
        updates.uptime = { now }
        #expect(updates.lastBatch == nil)
        #expect(updates.beginBatch())
        now = 51.5
        #expect(updates.lastBatch == nil)
        updates.endBatch()
        #expect(updates.lastBatch == 50...51.5)
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
        #expect(updates.lastBatch == 100...101)
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

    @Test("An AX Undo after a batch, seeing a current event from before it started, goes through")
    func staleEventBeforeBatchGoesThrough() async throws {
        let updates = LedgerUpdates()
        var now: TimeInterval = 100
        // The last real event: the click at 99.5 s that started the batch Undo. AppKit keeps it as the current
        // event, so a VoiceOver, Voice Control or AXPress Undo after the batch sees it.
        let eventTime: TimeInterval? = 99.5
        updates.uptime = { now }
        updates.currentEventTime = { eventTime }
        let setup = try await Self.setup(updates: updates)
        // The toolbar Undo of the Bulk Edit runs as a batch from 100 s to 101 s.
        setup.window.history.undo()
        #expect(setup.window.history.isBatchRunning)
        now = 101
        await setup.window.history.batchRun?.task.value
        #expect(!setup.window.history.isBatchRunning)
        #expect(updates.lastBatch == 100...101)
        #expect(try setup.details(0) == "Earlier edit")

        now = 102
        setup.window.undoManager.undo()
        setup.window.settle()
        #expect(try setup.details(0) == nil, "The earlier edit is undone")
        #expect(setup.window.undoManager.undoNames.isEmpty)
        #expect(setup.window.history.alert == nil)
    }

    @Test("An in-batch event drops one queued Undo; a second command seen with the same event goes through")
    func sameEventDropsOnce() async throws {
        let updates = LedgerUpdates()
        var now: TimeInterval = 100
        var eventTime: TimeInterval? = 99.5
        updates.uptime = { now }
        updates.currentEventTime = { eventTime }
        let setup = try await Self.setup(updates: updates)
        // The toolbar Undo of the Bulk Edit runs as a batch from 100 s to 101 s.
        setup.window.history.undo()
        #expect(setup.window.history.isBatchRunning)
        now = 101
        await setup.window.history.batchRun?.task.value
        #expect(!setup.window.history.isBatchRunning)
        let undoNames = setup.window.undoManager.undoNames

        // The Edit › Undo click from 100.6 s, queued during the batch and handled now, is dropped.
        eventTime = 100.6
        setup.window.undoManager.undo()
        setup.window.settle()
        #expect(try setup.details(0) == "Earlier edit", "The queued click undoes nothing")
        #expect(setup.window.undoManager.undoNames == undoNames)

        // An AX Undo next, with no real event since: the current event is still that click. It goes through.
        now = 102
        setup.window.undoManager.undo()
        setup.window.settle()
        #expect(try setup.details(0) == nil, "The AX Undo undoes the earlier edit")
        #expect(setup.window.undoManager.undoNames.isEmpty)
        #expect(setup.window.history.alert == nil)
    }
}
