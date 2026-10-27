import Foundation
import Testing

@testable import LittleOrbitFeatures

/// Tester's and Tech Architect's questions on 0d676f8 (comments 6449826260 and 6450092506): whether `settle()` can
/// miss its wake-up, and whether a refresh in an unrelated window can hold a batch busy. It reads the count again in
/// the step that starts its wait, is resumed once, and waits only for the refreshes of its own change.
@MainActor
@Suite("settle() wakes once, for its own change's refreshes", .timeLimit(.minutes(1)))
struct SettleWakeUpTests {
    /// The check before `settle()` suspends. The same check again in the step that starts the wait is defensive: no
    /// suspension comes between them, so nothing can change in between, and no test can tell them apart (n3).
    @Test("The last refresh ends after settle() is called but before its task starts: it skips the wait and the cap")
    func endedBeforeSettleStarts() async throws {
        let updates = LedgerUpdates()
        let sleeper = ManualSleeper()
        updates.sleep = sleeper.sleep
        defer { sleeper.release() }
        updates.refreshStarted()
        let settle = Task { await updates.settle() }
        // In the same main-actor step: the task hasn't run yet.
        updates.refreshEnded()
        try #require(await sleeper.next() == BatchProgress.uiTurnLength, "Straight to its turn, no cap")
        await sleeper.advance()
        #expect(await settle.value == false)
    }

    @Test("The cap and the last refresh's end in the same turn: settle() is resumed once, and not at its limit")
    func capAndEndTogether() async throws {
        let updates = LedgerUpdates()
        let sleeper = ManualSleeper()
        updates.sleep = sleeper.sleep
        // A regression fails at a `#require` and returns; the sleeps then end, so nothing waits for good (m10).
        defer { sleeper.release() }
        updates.refreshStarted()
        let settle = Task { await updates.settle() }
        #expect(await sleeper.next() == LedgerUpdates.settleLimit)
        // The cap's sleep ends, and before its task can run on, the last refresh ends.
        await sleeper.advance()
        updates.refreshEnded()
        await RealTime.eventually { sleeper.waiting == [BatchProgress.uiTurnLength] }
        try #require(sleeper.waiting == [BatchProgress.uiTurnLength], "One turn: resumed once")
        await sleeper.advance()
        #expect(await settle.value == false, "Woken by the refresh's end")
        #expect(sleeper.asked == [LedgerUpdates.settleLimit, BatchProgress.uiTurnLength])
    }

    @Test("A refresh still running for an earlier change doesn't hold up a batch's settle()")
    func unrelatedRefreshDoesNotHold() async throws {
        let updates = LedgerUpdates()
        let sleeper = ManualSleeper()
        updates.sleep = sleeper.sleep
        defer { sleeper.release() }
        // Another window's refresh, after an earlier change, still running.
        updates.changed()
        let earlier = updates.revision
        updates.refreshStarted(for: earlier)
        // The batch's one change, and this window's refresh for it.
        updates.changed()
        let batch = updates.revision
        updates.refreshStarted(for: batch)
        let settle = Task { await updates.settle() }
        #expect(await sleeper.next() == LedgerUpdates.settleLimit, "Waits for the batch's own refresh")
        updates.refreshEnded(for: batch)
        await RealTime.eventually { sleeper.waiting == [BatchProgress.uiTurnLength] }
        try #require(sleeper.waiting == [BatchProgress.uiTurnLength], "The earlier change's refresh doesn't hold it")
        await sleeper.advance()
        #expect(await settle.value == false)
        #expect(updates.refreshesRunning == 1, "The earlier refresh is still counted")
        updates.refreshEnded(for: earlier)
        #expect(updates.refreshesRunning == 0)
    }
}
