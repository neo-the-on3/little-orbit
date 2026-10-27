import Foundation
import LittleOrbitDomain
import Testing

@testable import LittleOrbitFeatures

/// Tech Architect's B4 on 0d676f8 (review 5672044979): a click or key press during a batch that no command consumed,
/// such as a click on the sheet or an arrow key in another window, stayed the current event after the end, and still
/// counted as fresh. A VoiceOver or Voice Control Undo or Redo after the end, seeing it, was dropped silently. The
/// event current at the end is now recorded, and only a newer one counts. Literal times, made-up data.
@MainActor
@Suite("An event no command consumed during a batch", .timeLimit(.minutes(1)))
struct QueuedUnusedEventTests {
    /// A batch Undo from 10 s to 11 s, started by ⌘Z at 10 s. While it runs, an event at 10.6 s reaches the app and
    /// drives no command: a click pressed at 10.55 s (`isMouse`), or a key press. It's still current at the end.
    private static func endedBatch(unusedMouse isMouse: Bool) async throws -> (QueuedCommandTests.Setup, UptimeClock) {
        let updates = LedgerUpdates()
        let clock = UptimeClock(now: 10)
        clock.eventTime = 10
        clock.drive(updates)
        let setup = try await QueuedCommandTests.setup(updates: updates)
        setup.window.history.undo()
        #expect(setup.window.history.isBatchRunning)
        clock.eventTime = 10.6
        clock.isMouse = isMouse
        clock.pressTime = isMouse ? 10.55 : nil
        clock.now = 11
        await setup.window.history.batchRun?.task.value
        #expect(updates.lastBatch == 10...11)
        #expect(updates.eventTimeAtEnd == 10.6, "The event current at the end is recorded")
        return (setup, clock)
    }

    /// A VoiceOver or Voice Control Redo at 12 s: no event of its own, so it sees the unused one. Whether it ran.
    private static func accessibilityRedo(_ setup: QueuedCommandTests.Setup, _ clock: UptimeClock) async -> Bool {
        let redoNames = setup.window.undoManager.redoNames
        clock.now = 12
        setup.window.undoManager.redo()
        setup.window.settle()
        await setup.window.history.batchRun?.task.value
        return setup.window.undoManager.redoNames != redoNames
    }

    @Test("An unused click during the batch, then an Accessibility Redo after it: the Redo runs")
    func unusedClickThenAccessibilityRedo() async throws {
        let (setup, clock) = try await Self.endedBatch(unusedMouse: true)
        #expect(await Self.accessibilityRedo(setup, clock), "The click is stale, so it's no event")
    }

    @Test("An unused key press during the batch, then an Accessibility Redo after it: the Redo runs")
    func unusedKeyThenAccessibilityRedo() async throws {
        let (setup, clock) = try await Self.endedBatch(unusedMouse: false)
        #expect(await Self.accessibilityRedo(setup, clock), "The key press is stale, so it's no event")
    }

    @Test("An unused click during the batch, then a menu Redo pressed inside it and released after the end: dropped")
    func unusedClickThenQueuedMenuRedo() async throws {
        let (setup, clock) = try await Self.endedBatch(unusedMouse: true)
        let redoNames = setup.window.undoManager.redoNames
        // Pressed at 10.95 s, released at 11.4 s: its mouse-up is dispatched after the end, so it's newer.
        clock.pressTime = 10.95
        clock.eventTime = 11.4
        clock.now = 11.42
        setup.window.undoManager.redo()
        setup.window.settle()
        await setup.window.history.batchRun?.task.value
        #expect(setup.window.undoManager.redoNames == redoNames, "Nothing redone")
    }

    @Test("An unused key press during the batch, then a ⌘Z queued inside it and handled after the end: dropped")
    func unusedKeyThenQueuedUndo() async throws {
        let (setup, clock) = try await Self.endedBatch(unusedMouse: false)
        let undoNames = setup.window.undoManager.undoNames
        // A ⌘Z typed at 10.8 s: queued behind the batch, dispatched after the end, so it's the newest event.
        clock.eventTime = 10.8
        clock.now = 11.2
        setup.window.undoManager.undo()
        setup.window.settle()
        #expect(setup.window.undoManager.undoNames == undoNames, "Nothing undone")
        #expect(try setup.details(0) == "Earlier edit")
    }
}
