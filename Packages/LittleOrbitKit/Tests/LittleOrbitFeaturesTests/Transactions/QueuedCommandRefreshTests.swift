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

    @Test("The allowance after the end is 0.3 s")
    func allowancePinned() {
        #expect(Policy.pressAllowance == 0.3)
    }

    @Test("A mouse-up just after the end, from a press that began inside the batch, is dropped once")
    func mouseUpAfterEnd() {
        // Pressed at 100.9 s, inside the batch, and still held at its end; the menu item's action is handled with the
        // mouse-up at 101.1 s.
        let mouseUp = Policy.Event(time: 101.1, isMouseUp: true)
        #expect(Policy.dropsCommand(event: mouseUp, lastBatch: Self.batch, heldAtEnd: true, lastDroppedEventTime: nil))
        #expect(
            !Policy.dropsCommand(event: mouseUp, lastBatch: Self.batch, heldAtEnd: true, lastDroppedEventTime: 101.1),
            "Once",
        )
        let atAllowance = Policy.Event(time: 101.3, isMouseUp: true)
        #expect(
            Policy.dropsCommand(event: atAllowance, lastBatch: Self.batch, heldAtEnd: true, lastDroppedEventTime: nil)
        )
    }

    @Test("A press started just after the end, released within 0.3 s of it, goes through")
    func pressAfterEnd() {
        // No button was held at the end, 101.0 s: pressed at 101.1 s, released at 101.25 s.
        let mouseUp = Policy.Event(time: 101.25, isMouseUp: true)
        #expect(
            !Policy.dropsCommand(event: mouseUp, lastBatch: Self.batch, heldAtEnd: false, lastDroppedEventTime: nil)
        )
    }

    @Test("A key press just after the end, or a click well after it, goes through")
    func legitAfterEnd() {
        let key = Policy.Event(time: 101.1)
        #expect(!Policy.dropsCommand(event: key, lastBatch: Self.batch, heldAtEnd: true, lastDroppedEventTime: nil))
        let laterClick = Policy.Event(time: 101.31, isMouseUp: true)
        #expect(
            !Policy.dropsCommand(event: laterClick, lastBatch: Self.batch, heldAtEnd: true, lastDroppedEventTime: nil)
        )
        let farClick = Policy.Event(time: 250, isMouseUp: true)
        #expect(
            !Policy.dropsCommand(event: farClick, lastBatch: Self.batch, heldAtEnd: true, lastDroppedEventTime: nil)
        )
    }

    @Test("A mouse-up from before the batch, or with no batch yet, goes through")
    func mouseUpOutside() {
        let before = Policy.Event(time: 99.9, isMouseUp: true)
        #expect(!Policy.dropsCommand(event: before, lastBatch: Self.batch, heldAtEnd: true, lastDroppedEventTime: nil))
        let inside = Policy.Event(time: 100.5, isMouseUp: true)
        #expect(!Policy.dropsCommand(event: inside, lastBatch: nil, heldAtEnd: true, lastDroppedEventTime: nil))
        #expect(!Policy.dropsCommand(event: nil, lastBatch: Self.batch, heldAtEnd: true, lastDroppedEventTime: nil))
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

    /// A batch Undo from 10 s to 11 s, with a mouse button held at its end or not.
    private static func endedBatch(held: Bool) async throws -> (QueuedCommandTests.Setup, UptimeClock) {
        let updates = LedgerUpdates()
        let clock = UptimeClock(now: 10)
        clock.eventTime = 10
        updates.uptime = { clock.now }
        updates.currentEvent = { clock.event }
        updates.mouseButtonHeld = { clock.buttonHeld }
        let setup = try await QueuedCommandTests.setup(updates: updates)
        let history = setup.window.history
        history.undo()
        clock.now = 11
        clock.buttonHeld = held
        await history.batchRun?.task.value
        clock.buttonHeld = false
        #expect(updates.lastBatch == 10...11)
        #expect(updates.heldAtLastEnd == held)
        return (setup, clock)
    }

    @Test("A Redo clicked inside the batch whose action comes with a mouse-up just after the end is dropped")
    func mouseUpAfterRecordedEnd() async throws {
        let (setup, clock) = try await Self.endedBatch(held: true)
        let undoNames = setup.window.undoManager.undoNames
        let redoNames = setup.window.undoManager.redoNames

        // Pressed at 10.95 s, held at the end; the Redo is handled with its mouse-up, at 11.1 s, after the end.
        clock.eventTime = 11.1
        clock.isMouseUp = true
        setup.window.undoManager.redo()
        setup.window.settle()
        #expect(setup.window.undoManager.redoNames == redoNames, "The batch step is still on Redo, once")
        #expect(setup.window.undoManager.undoNames == undoNames, "Nothing redone")
    }

    @Test("A Redo pressed just after the end, with no button held at it, goes through")
    func pressAfterRecordedEnd() async throws {
        let (setup, clock) = try await Self.endedBatch(held: false)
        let redoNames = setup.window.undoManager.redoNames
        #expect(!redoNames.isEmpty)

        // Pressed at 11.05 s, after the end; handled with its mouse-up at 11.1 s, within 0.3 s of the end.
        clock.eventTime = 11.1
        clock.isMouseUp = true
        setup.window.undoManager.redo()
        setup.window.settle()
        await setup.window.history.batchRun?.task.value
        #expect(setup.window.undoManager.redoNames != redoNames, "The Redo ran")
    }
}
