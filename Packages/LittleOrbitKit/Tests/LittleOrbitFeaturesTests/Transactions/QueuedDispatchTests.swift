import Foundation
import LittleOrbitDomain
import Testing

@testable import LittleOrbitFeatures

/// A ⌘Z that waited in the event queue while a batch blocked the main thread, dispatched once it ended, is dropped
/// (D403, kept by D407 for this one path). It's told by the key-down being dispatched as the command runs
/// (`EventDispatch`, B5 on bab2ad8), driven here as `LittleOrbitApplication.sendEvent` does. A menu choice, by mouse
/// or keyboard, or an Accessibility action, sees no key-down and never drops: Edit › Undo and Redo are off during the
/// batch for those instead (`UndoCommandGateTests`). Each test has its own `EventDispatch`. Literal times on the
/// `systemUptime` clock, made-up data.
@MainActor
@Suite("Undo and Redo by the event being dispatched", .timeLimit(.minutes(1)))
struct QueuedDispatchTests {
    typealias Policy = QueuedCommandPolicy

    /// The window, the clock and the dispatch, after a batch Undo from 10 s to 11 s started by ⌘Z at 10 s.
    @MainActor
    struct Ended {
        let setup: QueuedCommandTests.Setup
        let clock: UptimeClock
        let dispatch: EventDispatch
        /// The run loop's next default-mode turns the dispatch asked for, held until a test runs them.
        let turns: PendingTurns

        var undoNames: [String] { setup.window.undoManager.undoNames }
        var redoNames: [String] { setup.window.undoManager.redoNames }

        /// `body` while `event` is being dispatched, as `sendEvent` runs it; `type` is its `NSEvent.EventType`.
        func dispatching(_ type: Int, _ event: Policy.Event?, _ body: () -> Void) {
            dispatch.dispatching(EventDispatch.Entry(type: type, input: event), body)
        }

        /// The window's Redo, as the Edit menu or a key equivalent sends it, then the batch it starts. Whether it ran.
        func redo(at now: TimeInterval, in dispatched: ((() -> Void) -> Void)? = nil) async -> Bool {
            let before = redoNames
            clock.now = now
            if let dispatched {
                dispatched { setup.window.undoManager.redo() }
            } else {
                setup.window.undoManager.redo()
            }
            setup.window.settle()
            await setup.window.history.batchRun?.task.value
            return redoNames != before
        }
    }

    /// The default-mode turns `EventDispatch` asks for, run when a test says no dispatch is running.
    @MainActor
    final class PendingTurns {
        private(set) var blocks: [@MainActor () -> Void] = []

        func add(_ block: @escaping @MainActor () -> Void) {
            blocks.append(block)
        }

        func runAll() {
            let due = blocks
            blocks.removeAll()
            for block in due {
                block()
            }
        }
    }

    /// `NSEvent.EventType` raw values, as AppKit's are.
    enum Kind {
        static let leftMouseDown = 1
        static let leftMouseUp = 2
        static let keyDown = 10
        static let appKitDefined = 13
    }

    static func key(_ time: TimeInterval) -> Policy.Event {
        Policy.Event(time: time, type: Kind.keyDown)
    }

    private static func endedBatch() async throws -> Ended {
        let updates = LedgerUpdates()
        let clock = UptimeClock(now: 10)
        clock.drive(updates)
        let dispatch = EventDispatch()
        let turns = PendingTurns()
        dispatch.nextTopLevelTurn = turns.add
        updates.dispatchingEvent = { dispatch.current }
        let setup = try await QueuedCommandTests.setup(updates: updates)
        dispatch.dispatching(EventDispatch.Entry(type: Kind.keyDown, input: key(10))) {
            setup.window.undoManager.undo()
        }
        #expect(setup.window.history.isBatchRunning)
        clock.now = 11
        await setup.window.history.batchRun?.task.value
        #expect(updates.lastBatch == 10...11)
        #expect(dispatch.current == nil, "Nothing is being dispatched after the batch")
        // The run loop's turn after the ⌘Z's dispatch: it finds nothing to clear.
        turns.runAll()
        #expect(turns.blocks.isEmpty)
        return Ended(setup: setup, clock: clock, dispatch: dispatch, turns: turns)
    }

    @Test("A ⌘Z typed inside the batch, dispatched after the end: dropped; the same key-down drops no other")
    func keyInsideBatch() async throws {
        let ended = try await Self.endedBatch()
        let undoNames = ended.undoNames
        let key = Self.key(10.8)
        ended.clock.now = 11.2
        ended.dispatching(Kind.keyDown, key) { ended.setup.window.undoManager.undo() }
        ended.setup.window.settle()
        #expect(ended.undoNames == undoNames, "Nothing undone")
        #expect(try ended.setup.details(0) == "Earlier edit")
        ended.dispatching(Kind.keyDown, key) { ended.setup.window.undoManager.undo() }
        ended.setup.window.settle()
        #expect(ended.undoNames.count == undoNames.count - 1, "One drop per event")
    }

    @Test("A ⌘Z, or a ⇧⌘Z, after the end: the command runs once")
    func keyAfterEnd() async throws {
        let ended = try await Self.endedBatch()
        let undoNames = ended.undoNames
        ended.clock.now = 11.2
        ended.dispatching(Kind.keyDown, Self.key(11.15)) { ended.setup.window.undoManager.undo() }
        ended.setup.window.settle()
        #expect(ended.undoNames.count == undoNames.count - 1, "Exactly one step undone")
        #expect(try ended.setup.details(0) == nil)

        let other = try await Self.endedBatch()
        let redoNames = other.redoNames
        #expect(await other.redo(at: 11.21) { send in other.dispatching(Kind.keyDown, Self.key(11.2), send) })
        #expect(other.redoNames.count == redoNames.count - 1, "Exactly one step redone")
    }

    @Test("A menu item chosen with the mouse after the end, outside any key-down: it runs (D407: off during the batch)")
    func menuChoiceRuns() async throws {
        let ended = try await Self.endedBatch()
        // Sent from the menu's own tracking loop, or inside a mouse event's dispatch: no key-down either way.
        #expect(await ended.redo(at: 11.4))
        let other = try await Self.endedBatch()
        let mouseUp: (() -> Void) -> Void = { send in other.dispatching(Kind.leftMouseUp, nil, send) }
        #expect(await other.redo(at: 11.4, in: mouseUp))
    }

    @Test("An unused click inside the batch, then an Accessibility Redo after the end: it runs (B4)")
    func unusedClickThenAccessibility() async throws {
        let ended = try await Self.endedBatch()
        // A click on the sheet at 10.55 s, inside the batch: dispatched then, and no command.
        ended.dispatching(Kind.leftMouseDown, nil) {}
        #expect(await ended.redo(at: 12), "Outside any dispatch")
    }

    @Test("An unused key press inside the batch, then an Accessibility Redo after the end: it runs (B4)")
    func unusedKeyThenAccessibility() async throws {
        let ended = try await Self.endedBatch()
        ended.dispatching(Kind.keyDown, Self.key(10.6)) {}
        #expect(await ended.redo(at: 12), "Outside any dispatch")
    }

    @Test("Nested: an app-defined event inside a key-down's dispatch hides nothing")
    func nestedDispatch() async throws {
        let ended = try await Self.endedBatch()
        let inner: (() -> Void) -> Void = { send in
            ended.dispatching(Kind.keyDown, Self.key(10.9)) {
                ended.dispatching(Kind.appKitDefined, nil, send)
            }
        }
        #expect(!(await ended.redo(at: 11.3, in: inner)), "The key-down's time, inside the batch: dropped")
    }

    @Test(
        "m13: a key-down time that can't be right, never inside a batch, fails open",
        arguments: [0, -0.5, Double.nan, Double.infinity, -Double.infinity, 1e9],
    )
    func badKeyTimeFailsOpen(time: Double) async throws {
        let ended = try await Self.endedBatch()
        #expect(await ended.redo(at: 11.3) { send in ended.dispatching(Kind.keyDown, Self.key(time), send) })
        #expect(!Policy.dropsCommand(eventTime: time, lastBatch: 10...11, lastDroppedEventTime: nil))
    }

    @Test("m11: a dispatch whose end was skipped inside another is taken off when that one ends")
    func skippedEndNested() {
        let dispatch = EventDispatch()
        let outer = dispatch.enter(EventDispatch.Entry(type: Kind.leftMouseDown, input: nil))
        // An exception unwinds the inner dispatch without its end.
        _ = dispatch.enter(EventDispatch.Entry(type: Kind.keyDown, input: Self.key(5)))
        #expect(dispatch.current == Self.key(5))
        dispatch.leave(outer)
        #expect(dispatch.entries.isEmpty)
        #expect(dispatch.current == nil)
    }

    @Test("m11: an outermost dispatch whose end was skipped is cleared at the next top-level turn; AX then runs")
    func skippedEndOutermost() async throws {
        let ended = try await Self.endedBatch()
        // A key-down at 10.55 s, inside the batch, whose dispatch an exception unwinds without its end.
        _ = ended.dispatch.enter(EventDispatch.Entry(type: Kind.keyDown, input: Self.key(10.55)))
        #expect(ended.dispatch.current != nil, "Left behind")
        // The run loop's next default-mode turn, with no dispatch running.
        try #require(ended.turns.blocks.count == 1, "One clear asked for")
        ended.turns.runAll()
        #expect(ended.dispatch.current == nil, "Cleared")
        #expect(await ended.redo(at: 12), "An Accessibility Redo after the end runs")
    }

    @Test("m12: the first queued-command check reports an app that isn't the subclass, once, whatever launch did")
    func wiringCheckedOnFirstDecision() async throws {
        let dispatch = EventDispatch()
        var failures: [String] = []
        dispatch.wiringFailed = { failures.append($0) }
        let updates = LedgerUpdates()
        updates.dispatchingEvent = { dispatch.current }
        updates.checkDispatchWiring = { dispatch.checkWiring(appIsSubclass: false) }
        #expect(!dispatch.wiringChecked)
        #expect(!updates.dropsQueuedCommand())
        #expect(dispatch.wiringChecked && failures.count == 1, "Reported, and stopped a Debug build")
        #expect(!updates.dropsQueuedCommand())
        #expect(failures.count == 1, "Once")

        let live = EventDispatch()
        live.wiringFailed = { failures.append($0) }
        live.checkWiring(appIsSubclass: true)
        live.checkWiring(appIsSubclass: false)
        #expect(live.wiringChecked && failures.count == 1, "A live app checks once, and passes")
    }

    @Test("The dispatch is a stack: each event is taken off as its dispatch returns, inner ones first")
    func dispatchStack() {
        let dispatch = EventDispatch()
        #expect(dispatch.current == nil)
        #expect(dispatch.outermostType == -2, "No sendEvent wrapper yet")
        dispatch.reportSource(live: false)
        #expect(!dispatch.isInstalled && dispatch.outermostType == -2, "Absent at launch: still fails open")
        dispatch.reportSource(live: true)
        #expect(dispatch.isInstalled && dispatch.outermostType == -1, "Live")
        let key = Self.key(5)
        dispatch.dispatching(EventDispatch.Entry(type: Kind.leftMouseDown, input: nil)) {
            #expect(dispatch.current == nil, "A mouse event is never a key-down")
            dispatch.dispatching(EventDispatch.Entry(type: Kind.keyDown, input: key)) {
                #expect(dispatch.current == key)
                dispatch.dispatching(EventDispatch.Entry(type: Kind.appKitDefined, input: nil)) {
                    #expect(dispatch.current == key, "Not an input event: the key-down still counts")
                    #expect(dispatch.innermostType == Kind.appKitDefined)
                }
            }
            #expect(dispatch.current == nil)
            #expect(dispatch.outermostType == Kind.leftMouseDown)
        }
        #expect(dispatch.current == nil)
        #expect(dispatch.entries.isEmpty)
        #expect(dispatch.innermostType == -1)
    }
}
