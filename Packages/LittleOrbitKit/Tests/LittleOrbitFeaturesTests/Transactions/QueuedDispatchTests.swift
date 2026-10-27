import Foundation
import LittleOrbitDomain
import Testing

@testable import LittleOrbitFeatures

/// Tech Architect's B5 on bab2ad8, from Tester2's macOS run (comment 6452073697): an Edit menu Undo or Redo pressed
/// inside a batch, with the menu opened before it, ran an extra step once the batch ended, 0 of 3 dropped. The menu's
/// tracking runs inside the dispatch of the mouse-down that opened it, so `NSApp.currentEvent` was no newer than the
/// event current at the end, and B4's freshness check took it for an Accessibility press. A command is now decided by
/// the event being dispatched as it runs (`EventDispatch`), driven here as `LittleOrbitApplication.sendEvent` does.
/// Each test has its own `EventDispatch`. Literal times on the `systemUptime` clock, made-up data.
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

    /// `NSEvent.EventType` raw values, as AppKit's are.
    enum Kind {
        static let leftMouseDown = 1
        static let leftMouseUp = 2
        static let keyDown = 10
        static let appKitDefined = 13
    }

    static let opener = Policy.Event(time: 9.5, isMouse: true, type: Kind.leftMouseDown)

    private static func endedBatch() async throws -> Ended {
        let updates = LedgerUpdates()
        let clock = UptimeClock(now: 10)
        clock.drive(updates)
        let dispatch = EventDispatch()
        updates.dispatchingEvent = { dispatch.current }
        let setup = try await QueuedCommandTests.setup(updates: updates)
        let key = Policy.Event(time: 10, type: Kind.keyDown)
        dispatch.dispatching(EventDispatch.Entry(type: Kind.keyDown, input: key)) {
            setup.window.undoManager.undo()
        }
        #expect(setup.window.history.isBatchRunning)
        clock.now = 11
        await setup.window.history.batchRun?.task.value
        #expect(updates.lastBatch == 10...11)
        #expect(dispatch.current == nil, "Nothing is being dispatched after the batch")
        return Ended(setup: setup, clock: clock, dispatch: dispatch)
    }

    @Test("Tester2's case: a menu opened before the batch, Undo's item pressed inside it, sent after the end: dropped")
    func menuOpenedBeforePressedInside() async throws {
        let ended = try await Self.endedBatch()
        let undoNames = ended.undoNames
        // The Edit menu was opened by the mouse-down at 9.5 s; its item is pressed at 10.95 s, and the action is sent
        // at 11.4 s, still inside that mouse-down's dispatch.
        ended.clock.pressTime = 10.95
        let ran = await ended.redo(at: 11.4) { send in ended.dispatching(Kind.leftMouseDown, Self.opener, send) }
        #expect(!ran, "Dropped")
        #expect(ended.undoNames == undoNames, "Nothing redone")
        #expect(try ended.setup.details(0) == "Earlier edit")
    }

    @Test("A menu press mid-batch, its mouse-up dispatched after the end: dropped, once per press")
    func menuPressMidBatch() async throws {
        let ended = try await Self.endedBatch()
        ended.clock.pressTime = 10.5
        let mouseUp = Policy.Event(time: 10.56, isMouse: true, type: Kind.leftMouseUp)
        #expect(!(await ended.redo(at: 11.3) { send in ended.dispatching(Kind.leftMouseUp, mouseUp, send) }))
        // Another command off the same press goes through.
        #expect(await ended.redo(at: 11.35) { send in ended.dispatching(Kind.leftMouseUp, mouseUp, send) })
    }

    @Test("A ⌘Z typed inside the batch, dispatched after the end: dropped; the same key-down drops no other")
    func keyInsideBatch() async throws {
        let ended = try await Self.endedBatch()
        let undoNames = ended.undoNames
        let key = Policy.Event(time: 10.8, type: Kind.keyDown)
        ended.clock.now = 11.2
        ended.dispatching(Kind.keyDown, key) { ended.setup.window.undoManager.undo() }
        ended.setup.window.settle()
        #expect(ended.undoNames == undoNames, "Nothing undone")
        ended.dispatching(Kind.keyDown, key) { ended.setup.window.undoManager.undo() }
        ended.setup.window.settle()
        #expect(ended.undoNames.count == undoNames.count - 1, "One drop per event")
    }

    @Test("A menu press, or a ⌘⇧Z, after the end: the Redo runs once")
    func pressAfterEnd() async throws {
        let ended = try await Self.endedBatch()
        let undoNames = ended.undoNames
        ended.clock.pressTime = 11.05
        let ran = await ended.redo(at: 11.1) { send in ended.dispatching(Kind.leftMouseDown, Self.opener, send) }
        #expect(ran)
        #expect(ended.undoNames.count == undoNames.count + 1, "Exactly one step redone")

        let other = try await Self.endedBatch()
        let key = Policy.Event(time: 11.2, type: Kind.keyDown)
        #expect(await other.redo(at: 11.21) { send in other.dispatching(Kind.keyDown, key, send) })
    }

    @Test("An unused click inside the batch, then an Accessibility Redo after the end: it runs (B4)")
    func unusedClickThenAccessibility() async throws {
        let ended = try await Self.endedBatch()
        // A click on the sheet at 10.55 s, inside the batch: dispatched then, and no command.
        ended.clock.pressTime = 10.55
        ended.dispatching(Kind.leftMouseDown, Policy.Event(time: 10.55, isMouse: true, type: Kind.leftMouseDown)) {}
        #expect(await ended.redo(at: 12), "Outside any dispatch")
    }

    @Test("An unused key press inside the batch, then an Accessibility Redo after the end: it runs (B4)")
    func unusedKeyThenAccessibility() async throws {
        let ended = try await Self.endedBatch()
        ended.dispatching(Kind.keyDown, Policy.Event(time: 10.6, type: Kind.keyDown)) {}
        #expect(await ended.redo(at: 12), "Outside any dispatch")
    }

    @Test("Nested: an app-defined event inside a menu's mouse-down hides nothing; a key-down inside it is what counts")
    func nestedDispatch() async throws {
        let ended = try await Self.endedBatch()
        ended.clock.pressTime = 10.9
        let inner: (() -> Void) -> Void = { send in
            ended.dispatching(Kind.leftMouseDown, Self.opener) {
                ended.dispatching(Kind.appKitDefined, nil, send)
            }
        }
        #expect(!(await ended.redo(at: 11.3, in: inner)), "The mouse-down's press, inside the batch: dropped")

        let other = try await Self.endedBatch()
        other.clock.pressTime = 10.9
        // A key equivalent typed after the end, inside the tracking of a menu opened by that mouse-down.
        let key = Policy.Event(time: 11.25, type: Kind.keyDown)
        let keyInside: (() -> Void) -> Void = { send in
            other.dispatching(Kind.leftMouseDown, Self.opener) {
                other.dispatching(Kind.keyDown, key, send)
            }
        }
        #expect(await other.redo(at: 11.3, in: keyInside), "The key-down's own time, after the end: it runs")
    }

    @Test("The dispatch is a stack: each event is taken off as its dispatch returns, inner ones first")
    func dispatchStack() {
        let dispatch = EventDispatch()
        #expect(dispatch.current == nil)
        #expect(dispatch.outermostType == -2, "No sendEvent wrapper yet")
        dispatch.installed()
        #expect(dispatch.outermostType == -1)
        let key = Policy.Event(time: 5, type: Kind.keyDown)
        dispatch.dispatching(EventDispatch.Entry(type: Kind.leftMouseDown, input: Self.opener)) {
            #expect(dispatch.current == Self.opener)
            dispatch.dispatching(EventDispatch.Entry(type: Kind.keyDown, input: key)) {
                #expect(dispatch.current == key)
                dispatch.dispatching(EventDispatch.Entry(type: Kind.appKitDefined, input: nil)) {
                    #expect(dispatch.current == key, "Not an input event: the key-down still counts")
                }
            }
            #expect(dispatch.current == Self.opener)
            #expect(dispatch.outermostType == Kind.leftMouseDown)
        }
        #expect(dispatch.current == nil)
        #expect(dispatch.entries.isEmpty)
    }
}
