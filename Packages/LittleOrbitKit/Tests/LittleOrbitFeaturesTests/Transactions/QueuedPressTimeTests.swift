import Foundation
import LittleOrbitDomain
import Testing

@testable import LittleOrbitFeatures

/// Tester2's D403 on 3dc318b (comment 6448338326), and Tech Architect's press-time ruling with its four conditions: a
/// menu Undo or Redo pressed just before a batch's end, and released after it, still ran. A mouse command is now
/// dropped when its press fell inside the batch, however late its mouse-up is handled; a press after the end goes
/// through. The press time is `uptime − seconds since the last left mouse-down`, read while a left mouse event is
/// being dispatched (B5 on bab2ad8). Literal times, made-up data.
@MainActor
@Suite("Undo and Redo pressed during a batch", .timeLimit(.minutes(1)))
struct QueuedPressTimeTests {
    typealias Policy = QueuedCommandPolicy

    /// A batch that started at 100.0 s and ended at 101.0 s.
    static let batch: ClosedRange<TimeInterval> = 100.0...101.0

    private static func drops(
        _ event: Policy.Event?,
        press: TimeInterval?,
        batch: ClosedRange<TimeInterval>? = Self.batch,
        droppedPress: TimeInterval? = nil,
    ) -> Bool {
        Policy.dropsCommand(
            event: event,
            pressTime: press,
            lastBatch: batch,
            lastDroppedEventTime: nil,
            lastDroppedPressTime: droppedPress,
        )
    }

    @Test("Pressed before the end and released after it, its mouse-up handled later still: dropped, once per press")
    func pressInsideReleasedAfter() {
        let mouseUp = Policy.Event(time: 101.4, isMouse: true)
        #expect(Self.drops(mouseUp, press: 100.95))
        #expect(Self.drops(Policy.Event(time: 103, isMouse: true), press: 100.95), "However late it's handled")
        #expect(Self.drops(mouseUp, press: 100.0) && Self.drops(mouseUp, press: 101.0), "At the start or the end")
        #expect(!Self.drops(mouseUp, press: 100.95, droppedPress: 100.95), "Once per press")
        #expect(!Self.drops(mouseUp, press: 100.951, droppedPress: 100.95), "The same press, read a moment later")
        #expect(Self.drops(mouseUp, press: 100.5, droppedPress: 100.95), "Another press inside the batch")
    }

    @Test("A press after the end goes through, however soon; one before the start too")
    func pressOutside() {
        #expect(!Self.drops(Policy.Event(time: 101.1, isMouse: true), press: 101.001))
        #expect(!Self.drops(Policy.Event(time: 101.1, isMouse: true), press: 101.05))
        #expect(!Self.drops(Policy.Event(time: 99.95, isMouse: true), press: 99.9))
    }

    @Test("A left mouse event from before its press, as a menu opened before the batch: the press decides (B5)")
    func eventBeforePress() {
        // The mouse-down at 99.8 s opened the Edit menu; its tracking runs inside that dispatch, and Undo is chosen
        // with a press at 100.5 s, inside the batch (Tester2 on bab2ad8).
        #expect(Self.drops(Policy.Event(time: 99.8, isMouse: true), press: 100.5))
        #expect(!Self.drops(Policy.Event(time: 99.8, isMouse: true), press: 101.2), "Chosen after the end")
    }

    @Test("Key events keep the timestamp rule; no event, no batch or no press time never drops")
    func keysAndNothing() {
        #expect(Self.drops(Policy.Event(time: 100.6), press: nil))
        #expect(Self.drops(Policy.Event(time: 100.6), press: 102), "A key's own time counts, not the press")
        #expect(!Self.drops(Policy.Event(time: 101.1), press: 100.5))
        #expect(!Self.drops(nil, press: 100.5))
        #expect(!Self.drops(Policy.Event(time: 101.1, isMouse: true), press: 100.5, batch: nil))
        #expect(!Self.drops(Policy.Event(time: 101.1, isMouse: true), press: nil))
    }

    @Test("Only the left button's events go by the press time; the right and other buttons' by their own time (m9)")
    func otherButtons() {
        #expect(Policy.event(at: 101.2, from: .leftMouse) == Policy.Event(time: 101.2, isMouse: true))
        let rightClick = Policy.event(at: 101.2, from: .otherMouseButton)
        #expect(rightClick == Policy.Event(time: 101.2))
        #expect(Policy.event(at: 101.2, from: .other) == Policy.Event(time: 101.2))
        #expect(!Self.drops(rightClick, press: 100.5), "A left press inside the batch isn't the right button's")
        #expect(
            Self.drops(Policy.event(at: 100.7, from: .otherMouseButton), press: nil),
            "Queued from inside the batch, by its own time",
        )
    }

    @Test("A context-menu Redo after the end, with a left press inside the batch: it runs (m9)")
    func contextMenuAfterEnd() async throws {
        let (setup, clock) = try await Self.endedBatch()
        let redoNames = setup.window.undoManager.redoNames
        // A left press in another app at 10.9 s, inside the batch; then a right-click menu's Redo at 11.6 s.
        clock.pressTime = 10.9
        let event = Policy.event(at: 11.6, from: .otherMouseButton)
        clock.eventTime = event.time
        clock.isMouse = event.isMouse
        clock.now = 11.62
        setup.window.undoManager.redo()
        setup.window.settle()
        await setup.window.history.batchRun?.task.value
        #expect(setup.window.undoManager.redoNames != redoNames, "Redone once")
    }

    @Test("The press time fails open: zero, negative, not a number, or outside launch to now gives none")
    func pressTimeFailsOpen() {
        #expect(Policy.pressTime(now: 102, secondsSince: 1.05, launch: 50) == 100.95)
        #expect(Policy.pressTime(now: 102, secondsSince: 52, launch: 50) == 50)
        for bad in [0, -1, Double.nan, .infinity, -.infinity, 52.001, 1e12] {
            #expect(Policy.pressTime(now: 102, secondsSince: bad, launch: 50) == nil, "\(bad)")
        }
        #expect(Policy.pressTime(now: 102, secondsSince: nil, launch: 50) == nil, "No source, as on iOS")
    }

    /// A batch Undo from 10 s to 11 s, started by ⌘Z at 10 s.
    private static func endedBatch() async throws -> (QueuedCommandTests.Setup, UptimeClock) {
        let updates = LedgerUpdates()
        let clock = UptimeClock(now: 10)
        clock.eventTime = 10
        clock.drive(updates)
        let setup = try await QueuedCommandTests.setup(updates: updates)
        setup.window.history.undo()
        clock.now = 11
        await setup.window.history.batchRun?.task.value
        #expect(updates.lastBatch == 10...11)
        return (setup, clock)
    }

    /// A Redo chosen from the menu: its press at `press`, handled with its mouse-up at `mouseUp`. Whether it ran.
    private static func menuRedo(
        _ setup: QueuedCommandTests.Setup,
        _ clock: UptimeClock,
        press: TimeInterval,
        mouseUp: TimeInterval,
    ) async -> Bool {
        let redoNames = setup.window.undoManager.redoNames
        clock.pressTime = press
        clock.eventTime = mouseUp
        clock.isMouse = true
        clock.now = mouseUp + 0.02
        setup.window.undoManager.redo()
        setup.window.settle()
        await setup.window.history.batchRun?.task.value
        return setup.window.undoManager.redoNames != redoNames
    }

    @Test("Pressed at 10.95 s, before the end, released at 11.4 s: dropped; the press then drops no other command")
    func menuPressBeforeEnd() async throws {
        let (setup, clock) = try await Self.endedBatch()
        let undoNames = setup.window.undoManager.undoNames
        #expect(!(await Self.menuRedo(setup, clock, press: 10.95, mouseUp: 11.4)))
        #expect(setup.window.undoManager.undoNames == undoNames, "Nothing redone")
        // A second command seen with the same press, but a newer event, as a second action off one press would be.
        #expect(await Self.menuRedo(setup, clock, press: 10.95, mouseUp: 11.45), "Once per press")
    }

    @Test("Pressed at 11.05 s, just after the end: the Redo runs once")
    func menuPressAfterEnd() async throws {
        let (setup, clock) = try await Self.endedBatch()
        let undoNames = setup.window.undoManager.undoNames
        #expect(await Self.menuRedo(setup, clock, press: 11.05, mouseUp: 11.1))
        #expect(setup.window.undoManager.undoNames.count == undoNames.count + 1, "Exactly one step redone")
    }

    @Test("A dropped menu Redo, then an Accessibility Redo after the batch, with nothing dispatched: it goes through")
    func staleMouseUpAccessibility() async throws {
        let (setup, clock) = try await Self.endedBatch()
        // A menu Redo pressed inside the batch, at 10.9 s, is dropped with its mouse-up at 11.1 s.
        #expect(!(await Self.menuRedo(setup, clock, press: 10.9, mouseUp: 11.1)))
        // Then a press in another app reads as 10.97 s, inside the batch too; a VoiceOver Redo at 12 s arrives outside
        // any dispatch, though AppKit's current event is still the old mouse-up.
        let redoNames = setup.window.undoManager.redoNames
        clock.eventTime = nil
        clock.pressTime = 10.97
        clock.now = 12
        setup.window.undoManager.redo()
        setup.window.settle()
        await setup.window.history.batchRun?.task.value
        #expect(setup.window.undoManager.redoNames != redoNames, "No event is being dispatched, so it ran")
    }

    @Test(
        "A press source that reads 0, negative, not a number or too far back never drops",
        arguments: [
            0, -0.5, Double.nan, 1e9,
        ],
    )
    func sourceFailsOpen(raw: Double) async throws {
        let (setup, clock) = try await Self.endedBatch()
        clock.rawSecondsSince = raw
        #expect(await Self.menuRedo(setup, clock, press: 10.95, mouseUp: 11.3))
    }
}
