import Foundation
import LittleOrbitDomain
import Testing

@testable import LittleOrbitFeatures

/// #293 on #201: the Mac's Edit › Undo and Redo are the app's SwiftUI items (`UndoRedoCommands`), so they follow the
/// batch gate themselves. Pressed, they run only through `UndoCommandGate.perform` (D403.1); drawn, they're dimmed
/// while it's closed, still titled for the step (D407.2); and the gate has them read again in the same turn it
/// closes or opens, through a hook the Mac app sets, with no view in the gate. The send stands in for
/// `NSApp.sendAction(undo:, to: nil, from: nil)`, which Linux has no AppKit for. Made-up data.
@MainActor
@Suite("Edit › Undo and Redo wired to the batch gate (#293)", .timeLimit(.minutes(1)))
struct UndoCommandPerformTests {
    /// A gate of its own with no Edit menu to read, and the commands it sent.
    @MainActor
    final class Sends {
        let gate = UndoCommandGate()
        private(set) var sent: [UndoCommandGate.Command] = []

        init() {
            gate.isTracking = { false }
            gate.nextDefaultModeTurn = { _ in }
        }

        func press(_ command: UndoCommandGate.Command) -> Bool {
            gate.perform(command) { command in
                sent.append(command)
                return true
            }
        }
    }

    @Test("D403.1: closed, Undo and Redo send nothing, and still nothing once the batch ends: never queued")
    func closedSendsNothing() {
        let sends = Sends()
        sends.gate.batchStarted(at: 10)
        #expect(!sends.press(.undo))
        #expect(!sends.press(.redo))
        #expect(sends.sent.isEmpty, "Closed: send is never called")
        sends.gate.batchEnded(at: 11)
        #expect(sends.sent.isEmpty, "Not queued for the end")
    }

    @Test("D403.1: open, each press sends its own command exactly once, and returns what the send did")
    func openSendsOnce() {
        let sends = Sends()
        #expect(sends.press(.undo))
        #expect(sends.sent == [.undo])
        sends.gate.batchStarted(at: 10)
        sends.gate.batchEnded(at: 11)
        #expect(sends.press(.redo))
        #expect(sends.sent == [.undo, .redo])
        let taken = sends.gate.perform(.undo) { _ in false }
        #expect(!taken, "Nothing took it")
    }

    @Test("Held by a menu opened by a press during the batch (m14): sends nothing until that menu closes")
    func heldByMenuSendsNothing() {
        let sends = Sends()
        sends.gate.holdForMenu()
        #expect(!sends.press(.undo))
        sends.gate.openAfterTracking()
        #expect(sends.press(.undo))
        #expect(sends.sent == [.undo])
    }

    // MARK: ledger.editMenu.action, once per press (Tester2 on #201)

    /// A gate whose `ledger.editMenu.action` records are kept, and a send that does what the app's `sendAction`
    /// guard does: signpost the command, sent or blocked, then run it only if allowed.
    @MainActor
    final class Traced {
        let gate = UndoCommandGate()
        private(set) var records: [String] = []

        init() {
            gate.isTracking = { false }
            gate.nextDefaultModeTurn = { _ in }
            gate.actionTrace = { [weak self] command, allowed in
                self?.records.append("\(command == .undo ? "undo" : "redo")\(allowed ? "Sent" : "Blocked")")
            }
        }

        func press(_ command: UndoCommandGate.Command) -> Bool {
            gate.perform(command) { command in
                let allowed = gate.allows(command)
                gate.actionTrace(command, allowed)
                return allowed
            }
        }
    }

    @Test("A press refused during a batch logs exactly one undoBlocked or redoBlocked record, and sends nothing")
    func refusedLogsOnce() {
        let traced = Traced()
        traced.gate.batchStarted(at: 10)
        #expect(!traced.press(.undo))
        #expect(traced.records == ["undoBlocked"])
        #expect(!traced.press(.redo))
        #expect(traced.records == ["undoBlocked", "redoBlocked"])
        traced.gate.batchEnded(at: 11)
        #expect(traced.records.count == 2, "Nothing more at the end")
    }

    @Test("A press let through logs no blocked record from perform; only the send's own sent record, once")
    func allowedLogsNoBlocked() {
        let traced = Traced()
        var plain: [String] = []
        traced.gate.actionTrace = { command, allowed in plain.append("\(command)\(allowed)") }
        _ = traced.gate.perform(.undo) { _ in true }
        #expect(plain.isEmpty, "perform logs nothing when it lets a press through")
        let both = Traced()
        #expect(both.press(.undo))
        #expect(both.records == ["undoSent"], "No double log")
    }

    @Test("The actions sent are the standard undo: and redo:, which the gate reads back")
    func actionNames() {
        #expect(UndoCommandGate.Command.undo.actionName == "undo:")
        #expect(UndoCommandGate.Command.redo.actionName == "redo:")
        for command in UndoCommandGate.Command.allCases {
            #expect(UndoCommandGate.command(forAction: command.actionName) == command)
        }
    }

    @Test(
        "Each command maps exactly to its own standard action: undo to undo:, redo to redo:, never swapped",
        arguments: [(UndoCommandGate.Command.undo, "undo:"), (.redo, "redo:")],
    )
    func commandMapsToItsAction(_ command: UndoCommandGate.Command, _ name: String) {
        #expect(command.actionName == name)
        #expect(UndoCommandGate.command(forAction: name) == command)
        #if canImport(AppKit) && os(macOS)
            // What the Buttons send with `NSApp.sendAction` (D407.6), and what the app's guards read back.
            #expect(command.action == NSSelectorFromString(name))
            #expect(NSStringFromSelector(command.action) == name)
        #endif
    }

    // MARK: D407.2, the items read again in the same turn

    @Test("D407.2: closed, both items are dimmed and still named for the step; open again, on at once")
    func itemsFollowGate() {
        let manager = FakeUndoManager()
        manager.registerStep(manager, named: "Pay Gym") {}
        let closed = UndoMenuItems(manager, gateClosed: true)
        #expect(!closed.canUndo && !closed.canRedo)
        #expect(closed.undoTitle == "Undo Pay Gym")
        let open = UndoMenuItems(manager, gateClosed: false)
        #expect(open.canUndo && !open.canRedo)
        #expect(open.undoTitle == "Undo Pay Gym")
        #expect(!UndoMenuItems(nil, gateClosed: false).canUndo, "No key window: dimmed")
    }

    @Test("The gate reads the items through the Mac app's hook as it closes and opens, in that same turn")
    func hookReadInSameTurn() {
        let gate = UndoCommandGate()
        gate.isTracking = { false }
        let manager = FakeUndoManager()
        manager.registerStep(manager, named: "Edit 5 Transactions") {}
        var read: [(closed: Bool, items: UndoMenuItems)] = []
        var outsideRefresh = 0
        gate.editMenuObserver = { closed in
            let items = UndoMenuItems(manager, gateClosed: closed)
            read.append((closed, items))
            outsideRefresh += gate.isRefreshing ? 0 : 1
            return items
        }
        gate.batchStarted(at: 10)
        #expect(read.map(\.closed) == [true])
        #expect(read.last?.items.canUndo == false, "Dimmed as the batch starts")
        gate.batchEnded(at: 11)
        #expect(read.map(\.closed) == [true, false])
        #expect(read.last?.items.canUndo == true, "On as the gate opens, before anything else runs")
        #expect(read.last?.items.undoTitle == "Undo Edit 5 Transactions")
        #expect(outsideRefresh == 0, "Read while the gate is refreshing")
        #expect(!gate.isRefreshing)
    }

    @Test("With no Edit menu observing, as off the Mac, a refresh reads nothing and still opens the gate")
    func noObserver() {
        let gate = UndoCommandGate()
        gate.isTracking = { false }
        gate.batchStarted(at: 10)
        gate.batchEnded(at: 11)
        #expect(!gate.isClosed)
    }

    // MARK: Point 1, #286's queued ⌘Z through the Button path

    @Test("A ⌘Z pressed during the batch, delivered after its end through Edit › Undo's Button: sent, then dropped")
    func buttonPathQueuedKeyDrops() async throws {
        let ended = try await QueuedDispatchTests.endedBatch()
        let sends = Sends()
        let undoNames = ended.undoNames
        let press = { (time: TimeInterval) in
            ended.dispatching(QueuedDispatchTests.Kind.keyDown, QueuedDispatchTests.key(time)) {
                _ = sends.gate.perform(.undo) { _ in
                    ended.setup.window.undoManager.undo()
                    return true
                }
            }
            ended.setup.window.settle()
        }
        ended.clock.now = 11.2
        press(10.8)
        #expect(!sends.gate.isClosed, "The gate is open: perform sends")
        #expect(ended.undoNames == undoNames, "Dropped by its key-down's time")
        #expect(try ended.setup.details(0) == "Earlier edit")
        press(11.3)
        #expect(ended.undoNames.count == undoNames.count - 1, "A ⌘Z pressed after the end undoes once")
    }
}
