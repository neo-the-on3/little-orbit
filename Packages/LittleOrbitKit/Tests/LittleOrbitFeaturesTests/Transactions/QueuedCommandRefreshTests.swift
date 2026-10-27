import Foundation
import LittleOrbitDomain
import Testing

@testable import LittleOrbitFeatures

/// Tester2's N5 at 1f2eae8 (comment 6445268985), D403.1 FAIL: a batch Undo or Redo ended at the install, but the
/// windows then refreshed on the main actor, with the sheet still up, for about 0.45 s more. A menu Undo or Redo
/// clicked then ran a second step once main was free: its event came after the recorded end, and busy was off. The
/// batch now ends once every window has refreshed and main is free, and a mouse-up just after the end whose press
/// began inside the batch is dropped too. Made-up data.
@MainActor
@Suite("Undo and Redo queued during a batch's refresh")
struct QueuedCommandRefreshTests {
    typealias Policy = QueuedCommandPolicy

    /// A batch that started at 100.0 s and ended at 101.0 s.
    static let batch: ClosedRange<TimeInterval> = 100.0...101.0

    @Test("A mouse-up just after the end, from a press that began inside the batch, is dropped once")
    func mouseUpAfterEnd() {
        // Pressed at 100.9 s, inside the batch; the menu item's action is handled with the mouse-up at 101.1 s.
        let mouseUp = Policy.Event(time: 101.1, isMouseUp: true)
        #expect(Policy.dropsCommand(event: mouseUp, lastBatch: Self.batch, lastDroppedEventTime: nil))
        #expect(!Policy.dropsCommand(event: mouseUp, lastBatch: Self.batch, lastDroppedEventTime: 101.1), "Once")
        let atAllowance = Policy.Event(time: 101 + Policy.pressAllowance, isMouseUp: true)
        #expect(Policy.dropsCommand(event: atAllowance, lastBatch: Self.batch, lastDroppedEventTime: nil))
    }

    @Test("A key press just after the end, or a click well after it, goes through")
    func legitAfterEnd() {
        let key = Policy.Event(time: 101.1)
        #expect(!Policy.dropsCommand(event: key, lastBatch: Self.batch, lastDroppedEventTime: nil))
        let laterClick = Policy.Event(time: 101 + Policy.pressAllowance + 0.01, isMouseUp: true)
        #expect(!Policy.dropsCommand(event: laterClick, lastBatch: Self.batch, lastDroppedEventTime: nil))
        let farClick = Policy.Event(time: 250, isMouseUp: true)
        #expect(!Policy.dropsCommand(event: farClick, lastBatch: Self.batch, lastDroppedEventTime: nil))
    }

    @Test("A mouse-up from before the batch, or with no batch yet, goes through")
    func mouseUpOutside() {
        let before = Policy.Event(time: 99.9, isMouseUp: true)
        #expect(!Policy.dropsCommand(event: before, lastBatch: Self.batch, lastDroppedEventTime: nil))
        let inside = Policy.Event(time: 100.5, isMouseUp: true)
        #expect(!Policy.dropsCommand(event: inside, lastBatch: nil, lastDroppedEventTime: nil))
        #expect(!Policy.dropsCommand(event: nil, lastBatch: Self.batch, lastDroppedEventTime: nil))
    }

    /// One window's refresh after the batch's change: it starts when the change is posted, at the install (101 s),
    /// moves the clock to 101.4 s, and ends a little later, as `window.recompute` and the table update do.
    @MainActor
    final class Refresh {
        private(set) var started = 0
        var isRunning = false

        func attach(to updates: LedgerUpdates, clock: UptimeClock) {
            updates.onChanged { [self] in
                started += 1
                isRunning = true
                updates.refreshStarted()
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(120))
                    clock.now = 101.4
                    self.isRunning = false
                    updates.refreshEnded()
                }
            }
        }
    }

    @Test("Busy and the batch's recorded end cover the windows' refresh after the install, so a click then is dropped")
    func clickDuringRefresh() async throws {
        let updates = LedgerUpdates()
        let clock = UptimeClock(now: 100)
        clock.eventTime = 100
        updates.uptime = { clock.now }
        updates.currentEvent = { clock.event }
        let setup = try await QueuedCommandTests.setup(updates: updates)
        let history = setup.window.history
        let refresh = Refresh()
        refresh.attach(to: updates, clock: clock)

        // The batch Undo starts at 100 s; its save is installed at 101 s, and the change goes out.
        history.undo()
        clock.now = 101
        await ManualSleeper.until { refresh.started > 0 || history.batchRun == nil }
        try #require(refresh.started == 1, "One change notice")
        #expect(refresh.isRunning)
        #expect(history.isBatchRunning, "Busy while the windows refresh")
        #expect(!history.canUndo && !history.canRedo)
        await history.batchRun?.task.value
        #expect(!history.isBatchRunning)
        #expect(updates.lastBatch == 100...101.4, "Ends once the refresh is done, not at the install")

        // The click from 101.2 s, during the refresh, handled only now.
        let undoNames = setup.window.undoManager.undoNames
        let redoNames = setup.window.undoManager.redoNames
        clock.eventTime = 101.2
        setup.window.undoManager.undo()
        setup.window.settle()
        #expect(try setup.details(0) == "Earlier edit", "No extra step undone")
        #expect(setup.window.undoManager.undoNames == undoNames)
        #expect(setup.window.undoManager.redoNames == redoNames)

        // A fresh ⌘Z well after the end goes through.
        clock.eventTime = 103
        clock.now = 103
        history.undo()
        setup.window.settle()
        #expect(try setup.details(0) == nil)
    }

    @Test("A Redo clicked inside the batch whose action comes with a mouse-up just after the end is dropped")
    func mouseUpAfterRecordedEnd() async throws {
        let updates = LedgerUpdates()
        let clock = UptimeClock(now: 10)
        clock.eventTime = 10
        updates.uptime = { clock.now }
        updates.currentEvent = { clock.event }
        let setup = try await QueuedCommandTests.setup(updates: updates)
        let history = setup.window.history
        history.undo()
        clock.now = 11
        await history.batchRun?.task.value
        #expect(updates.lastBatch == 10...11)
        let undoNames = setup.window.undoManager.undoNames
        let redoNames = setup.window.undoManager.redoNames

        // Pressed at 10.95 s; the Redo is handled with its mouse-up, at 11.1 s, after the recorded end.
        clock.eventTime = 11.1
        clock.isMouseUp = true
        setup.window.undoManager.redo()
        setup.window.settle()
        #expect(setup.window.undoManager.redoNames == redoNames, "The batch step is still on Redo, once")
        #expect(setup.window.undoManager.undoNames == undoNames, "Nothing redone")
    }
}
