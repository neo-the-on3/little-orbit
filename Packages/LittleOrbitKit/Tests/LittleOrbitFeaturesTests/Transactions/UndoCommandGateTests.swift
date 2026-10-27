import Foundation
import LittleOrbitDomain
import Testing

@testable import LittleOrbitFeatures

/// D407 on #286 (the Product Manager's ruling, through the Tech Architect, after Tester2 on 4839e5d): while a batch
/// runs, Edit › Undo and Redo are off, and back on, titled, as it ends. Driven here from the gate the app's
/// `NSApplication` asks (`LittleOrbitApplication.target(forAction:to:from:)`), with no AppKit. Made-up data.
@MainActor
@Suite("Edit › Undo and Redo off while a batch runs (D407)", .timeLimit(.minutes(1)))
struct UndoCommandGateTests {
    /// A gate of its own, with what it validated the Edit menu for, and the turns it asked for held.
    @MainActor
    final class Probe {
        let gate = UndoCommandGate()
        private(set) var phases: [String] = []
        private(set) var turns: [@MainActor () -> Void] = []
        var tracking = false
        /// Runs at each validation, as AppKit's would read the window's state then.
        var onRefresh: () -> Void = {}

        init() {
            gate.refreshMenu = { [weak self] phase in
                self?.phases.append(phase.description)
                self?.onRefresh()
            }
            gate.isTracking = { [weak self] in self?.tracking ?? false }
            gate.nextDefaultModeTurn = { [weak self] block in self?.turns.append(block) }
        }

        func runTurns() {
            let due = turns
            turns.removeAll()
            for turn in due {
                turn()
            }
        }

        var undoAndRedoOn: Bool {
            gate.allows(action: "undo:") && gate.allows(action: "redo:")
        }
    }

    @Test("Off from the batch's start, on at its end; the Edit menu is validated again at both")
    func offDuringBatch() {
        let probe = Probe()
        let updates = LedgerUpdates()
        updates.commandGate = probe.gate
        #expect(probe.undoAndRedoOn)
        #expect(updates.beginBatch())
        #expect(!probe.gate.allows(.undo) && !probe.gate.allows(.redo))
        #expect(!probe.gate.allows(action: "undo:") && !probe.gate.allows(action: "redo:"))
        #expect(probe.phases == ["start"])
        updates.endBatch()
        #expect(probe.undoAndRedoOn)
        #expect(probe.phases == ["start", "end"])
        #expect(probe.turns.isEmpty, "On at once")
    }

    @Test("New Transaction, and every other command, stays on during a batch (D407.3)")
    func otherCommandsStayOn() {
        let probe = Probe()
        probe.gate.batchStarted(at: 10)
        for action in ["newDocument:", "copy:", "paste:", "selectAll:", "performClose:", "undoTyping", "redo"] {
            #expect(probe.gate.allows(action: action), "\(action)")
        }
        #expect(UndoCommandGate.command(forAction: "undo:") == .undo)
        #expect(UndoCommandGate.command(forAction: "redo:") == .redo)
        #expect(UndoCommandGate.command(forAction: "newDocument:") == nil)
    }

    @Test("Ended while a menu is open: off until it closes, so an item pressed during the batch runs nothing")
    func endWhileMenuOpen() throws {
        let probe = Probe()
        probe.gate.batchStarted(at: 10)
        probe.tracking = true
        probe.gate.batchEnded(at: 11)
        #expect(!probe.gate.isBatchRunning)
        #expect(!probe.undoAndRedoOn, "The mouse-up or Return handled after the end finds Undo off")
        #expect(probe.phases == ["start", "endWhileTracking"])
        try #require(probe.turns.count == 1)
        // The menu has closed: the run loop turns in its default mode again.
        probe.tracking = false
        probe.runTurns()
        #expect(probe.undoAndRedoOn)
        #expect(probe.phases == ["start", "endWhileTracking", "afterTracking"])
    }

    @Test("A batch that starts before the open menu closes keeps Undo off")
    func nextBatchBeforeMenuCloses() {
        let probe = Probe()
        probe.gate.batchStarted(at: 10)
        probe.tracking = true
        probe.gate.batchEnded(at: 11)
        probe.gate.batchStarted(at: 10)
        probe.runTurns()
        #expect(!probe.undoAndRedoOn)
        probe.tracking = false
        probe.gate.batchEnded(at: 11)
        #expect(probe.undoAndRedoOn)
    }

    @Test("On again at the end, titled for the batch at once; one Redo, then one Undo, each runs the batch once")
    func titledAtEnd() async throws {
        let probe = Probe()
        let updates = LedgerUpdates()
        updates.commandGate = probe.gate
        let clock = UptimeClock(now: 10)
        clock.drive(updates)
        let setup = try await QueuedCommandTests.setup(updates: updates)
        let history = setup.window.history
        // The app's existing names, unchanged by D407: the menu shows "Undo " and "Redo " before them.
        let bulkTitle = "Edit 5 Transactions in Everyday Savings"
        #expect(history.undoTitle.map { "Undo \($0)" } == "Undo Edit 5 Transactions in Everyday Savings")
        var atEnd: (canRedo: Bool, redoTitle: String?)?
        probe.onRefresh = {
            if !probe.gate.isBatchRunning {
                atEnd = (history.canRedo, history.redoTitle)
            }
        }

        history.undo()
        #expect(history.isBatchRunning)
        #expect(!probe.undoAndRedoOn && !history.canUndo && !history.canRedo, "Off, in the menu and the toolbar")
        clock.now = 11
        await history.batchRun?.task.value
        #expect(probe.undoAndRedoOn)
        let shown = try #require(atEnd, "Validated at the end")
        #expect(shown.canRedo, "Redo is on as the menu comes back")
        #expect(
            shown.redoTitle.map { "Redo \($0)" } == "Redo Edit 5 Transactions in Everyday Savings",
            "Titled for the batch at once",
        )
        #expect(history.undoTitle == nil || history.undoTitle != bulkTitle, "The batch is on Redo only")
        #expect(setup.window.undoManager.redoNames == [bulkTitle], "One step for the whole batch")

        clock.now = 12
        history.redo()
        #expect(!probe.undoAndRedoOn)
        clock.now = 13
        await history.batchRun?.task.value
        #expect(probe.undoAndRedoOn)
        #expect(history.undoTitle.map { "Undo \($0)" } == "Undo Edit 5 Transactions in Everyday Savings")
        #expect(history.redoTitle == nil)
        #expect(setup.window.undoManager.undoNames.count == 2, "The earlier edit, then the batch, once")
        #expect(
            try setup.disk.transactions().filter { Set(setup.rows.map(\.id)).contains($0.id) }
                .allSatisfy { $0.categoryID == DefaultCategoryID.food },
            "The Bulk Edit is applied again, all of it",
        )
    }

    // MARK: m14, a menu opened by a press made during a batch

    /// A probe after a batch from 10 s to 11 s, now at 11.5 s, with the last left press `pressedAt`.
    private static func afterBatch(pressedAt press: Double?) -> Probe {
        let probe = Probe()
        probe.gate.uptime = { 11.5 }
        probe.gate.secondsSinceLeftMouseDown = { press.map { 11.5 - $0 } }
        probe.gate.batchStarted(at: 10)
        probe.gate.batchEnded(at: 11)
        return probe
    }

    @Test("m14: a menu opened after the end by a press made during the batch holds Undo off until it closes")
    func pressInBatchHoldsMenu() throws {
        let probe = Self.afterBatch(pressedAt: 10.6)
        #expect(probe.undoAndRedoOn, "Open after the end")
        #expect(probe.gate.menuBeganTracking() == .held)
        #expect(!probe.undoAndRedoOn, "Off while that menu tracks")
        #expect(probe.phases.last == "heldByMenu")
        #expect(probe.gate.menuBeganTracking() == .held && probe.turns.count == 1, "Held once")
        probe.runTurns()
        #expect(probe.undoAndRedoOn, "On once it closes")
        #expect(probe.phases.last == "afterTracking")
    }

    @Test("m14: a press during the batch running now also holds the menu past the end")
    func pressInRunningBatchHoldsPastEnd() {
        let probe = Probe()
        probe.gate.uptime = { 10.5 }
        probe.gate.secondsSinceLeftMouseDown = { 0.2 }
        probe.gate.batchStarted(at: 10)
        #expect(probe.gate.menuBeganTracking() == .held)
        probe.gate.batchEnded(at: 11)
        #expect(!probe.undoAndRedoOn, "Still held by the open menu")
        probe.runTurns()
        #expect(probe.undoAndRedoOn)
    }

    @Test("m14: a press before the batch, or after its end, holds nothing", arguments: [9.9, 11.01, 11.4])
    func pressOutsideBatch(press: Double) {
        let probe = Self.afterBatch(pressedAt: press)
        #expect(probe.gate.menuBeganTracking() == .passed)
        #expect(probe.undoAndRedoOn && probe.turns.isEmpty)
    }

    @Test(
        "m14: a reading that can't be right holds nothing (fail open)",
        arguments: [nil, 0, -0.5, Double.nan, Double.infinity, 1e9] as [Double?],
    )
    func badReadingFailsOpen(secondsSince: Double?) {
        let probe = Self.afterBatch(pressedAt: nil)
        probe.gate.secondsSinceLeftMouseDown = { secondsSince }
        #expect(probe.gate.menuBeganTracking() == .noReading)
        #expect(probe.undoAndRedoOn)
    }

    @Test("A batch that starts with a menu open is tagged so")
    func startWhileTracking() {
        let probe = Probe()
        probe.tracking = true
        probe.gate.batchStarted(at: 10)
        #expect(probe.phases == ["startWhileTracking"])
    }
}
