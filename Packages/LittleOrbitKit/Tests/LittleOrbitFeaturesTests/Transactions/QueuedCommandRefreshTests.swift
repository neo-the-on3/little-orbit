import Foundation
import LittleOrbitDomain
import Testing

@testable import LittleOrbitFeatures

/// Tester2's N5 at 1f2eae8 (comment 6445268985), D403.1 FAIL: a batch Undo or Redo ended at the install, but the
/// windows then refreshed on the main actor, with the sheet still up, for about 0.45 s more. A menu Undo or Redo
/// clicked then ran a second step once main was free: its event came after the recorded end, and busy was off. The
/// batch now ends once every window has refreshed and main is free. A click whose press began inside the batch is
/// dropped too, however late its mouse-up (`QueuedPressTimeTests`). Made-up data.
@MainActor
@Suite("Undo and Redo queued during a batch's refresh", .timeLimit(.minutes(1)))
struct QueuedCommandRefreshTests {
    /// One window's refresh after the batch's change: it starts when the change is posted, at the install (101 s),
    /// and runs until the test ends it, as `window.recompute` and the table update do. No real time: on macOS the
    /// SwiftData timing suites hold the main actor for seconds, so a timed refresh and a real-time deadline failed
    /// there (Tester2 on 0d676f8, comment 6449826260).
    @MainActor
    final class Refresh {
        private(set) var started = 0
        private(set) var isRunning = false
        private var updates: LedgerUpdates?

        func attach(to updates: LedgerUpdates) {
            self.updates = updates
            updates.onChanged { [self] in
                started += 1
                isRunning = true
                updates.refreshStarted()
            }
        }

        func finish() {
            guard isRunning else {
                return
            }
            isRunning = false
            updates?.refreshEnded()
        }
    }

    @Test("Busy and the batch's recorded end cover the windows' refresh after the install, so a click then is dropped")
    func clickDuringRefresh() async throws {
        let updates = LedgerUpdates()
        let clock = UptimeClock(now: 100)
        clock.eventTime = 100
        clock.drive(updates)
        let sleeper = ManualSleeper()
        updates.sleep = sleeper.sleep
        let setup = try await QueuedCommandTests.setup(updates: updates)
        let history = setup.window.history
        let refresh = Refresh()
        refresh.attach(to: updates)

        // The batch Undo starts at 100 s; its save is installed at 101 s, and the change goes out.
        history.undo()
        clock.now = 101
        await RealTime.eventually { refresh.started > 0 || history.batchRun == nil }
        try #require(refresh.started == 1, "One change notice")
        #expect(refresh.isRunning)
        // `settle()` waits on its cap only, for the refresh.
        await RealTime.eventually { sleeper.waiting == [LedgerUpdates.settleLimit] }
        try #require(sleeper.waiting == [LedgerUpdates.settleLimit], "settle() waits for the refresh")
        #expect(history.isBatchRunning, "Busy while the windows refresh")
        #expect(!history.canUndo && !history.canRedo)
        // The refresh ends at 101.4 s. Fails here, rather than hanging, if its end stops waking `settle()` (m6).
        clock.now = 101.4
        refresh.finish()
        await RealTime.eventually { sleeper.waiting == [BatchProgress.uiTurnLength] }
        try #require(sleeper.waiting == [BatchProgress.uiTurnLength], "The refresh's end woke settle()")
        #expect(history.isBatchRunning, "Busy until main has had its turn")
        await sleeper.advance()
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
}
