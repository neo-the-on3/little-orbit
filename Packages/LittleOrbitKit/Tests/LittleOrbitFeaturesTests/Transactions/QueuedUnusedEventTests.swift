import Foundation
import LittleOrbitDomain
import Testing

@testable import LittleOrbitFeatures

/// Tech Architect's B4 on 0d676f8 (review 5672044979): a click or key press during a batch that no command consumed,
/// such as a click on the sheet or an arrow key in another window, stayed the current event after the end, and still
/// counted as fresh. A VoiceOver or Voice Control Undo or Redo after the end, seeing it, was dropped silently. Only the
/// key-down being dispatched as a command runs counts now (B5 on bab2ad8, D407): the unused one's dispatch ended
/// during the batch, and an Accessibility action arrives outside any. Literal times, made-up data.
@MainActor
@Suite("An event no command consumed during a batch", .timeLimit(.minutes(1)))
struct QueuedUnusedEventTests {
    /// A batch Undo from 10 s to 11 s, started by ⌘Z at 10 s. While it runs, a key-down at 10.6 s reaches the app
    /// and drives no command. Its dispatch is over by the end, though AppKit still keeps it as the current event.
    private static func endedBatch() async throws -> (QueuedCommandTests.Setup, UptimeClock) {
        let updates = LedgerUpdates()
        let clock = UptimeClock(now: 10)
        clock.eventTime = 10
        clock.drive(updates)
        let setup = try await QueuedCommandTests.setup(updates: updates)
        setup.window.history.undo()
        #expect(setup.window.history.isBatchRunning)
        clock.eventTime = 10.6
        clock.now = 11
        await setup.window.history.batchRun?.task.value
        #expect(updates.lastBatch == 10...11)
        clock.eventTime = nil
        return (setup, clock)
    }

    @Test("An unused key press during the batch, then an Accessibility Redo after it: the Redo runs")
    func unusedKeyThenAccessibilityRedo() async throws {
        let (setup, clock) = try await Self.endedBatch()
        let redoNames = setup.window.undoManager.redoNames
        clock.now = 12
        setup.window.undoManager.redo()
        setup.window.settle()
        await setup.window.history.batchRun?.task.value
        #expect(setup.window.undoManager.redoNames != redoNames, "Nothing is being dispatched")
    }

    @Test("An unused key press during the batch, then a ⌘Z queued inside it and handled after the end: dropped")
    func unusedKeyThenQueuedUndo() async throws {
        let (setup, clock) = try await Self.endedBatch()
        let undoNames = setup.window.undoManager.undoNames
        // A ⌘Z typed at 10.8 s: queued behind the batch, dispatched after the end.
        clock.eventTime = 10.8
        clock.now = 11.2
        setup.window.undoManager.undo()
        setup.window.settle()
        #expect(setup.window.undoManager.undoNames == undoNames, "Nothing undone")
        #expect(try setup.details(0) == "Earlier edit")
    }
}
