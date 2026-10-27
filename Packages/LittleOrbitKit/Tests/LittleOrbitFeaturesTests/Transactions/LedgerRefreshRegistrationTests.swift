import Foundation
import LittleOrbitDomain
import Testing

@testable import LittleOrbitFeatures

/// Tech Architect's B2 on 0389f40: a window's refresh was only counted once its view's `onChange` had run and a task
/// had hopped to `refresh(after:)`, and `settle()` guessed both landed within 50 ms. A late one let the batch end
/// before that window's refresh. Every account history its view shows is now registered with `LedgerUpdates`, which
/// starts and counts its refresh as the change is posted. Made-up data.
@MainActor
@Suite("Window refreshes started and counted as a change is posted", .timeLimit(.minutes(1)))
struct LedgerRefreshRegistrationTests {
    typealias F = TransactionFeatureFixture  // swiftlint:disable:this type_name

    /// The app's own account history for `accountID`, from `TransactionsFeature.makeHistory`, its builds held, shown
    /// as its view shows it (`appeared(in:)`).
    static func register(
        _ setup: QueuedCommandTests.Setup,
        updates: LedgerUpdates,
        accountID: UUID = F.savingsID,
    ) -> (AccountHistoryViewModel, HeldRegisterBuilds) {
        let useCases = TransactionUseCases(repository: setup.disk, categoryNames: CatalogDefaultCategoryNames())
        let feature = TransactionsFeature(
            useCases: useCases,
            locale: F.india,
            timeZone: F.zone,
            now: { F.now },
            updates: updates,
        )
        let model = feature.makeHistory(accountID: accountID)
        let builds = HeldRegisterBuilds()
        model.buildContent = builds.builder
        model.appeared(in: updates)
        return (model, builds)
    }

    @Test("A batch Undo stays busy, and its end isn't recorded, until a real register's held build finishes")
    func busyUntilRegisterBuilt() async throws {
        let updates = LedgerUpdates()
        let clock = UptimeClock(now: 100)
        updates.uptime = { clock.now }
        let setup = try await QueuedCommandTests.setup(updates: updates)
        let history = setup.window.history
        let (register, builds) = Self.register(setup, updates: updates)
        let before = register.allRows

        history.undo()
        clock.now = 101
        // No view and no `onChange` here: the change itself starts the register's refresh.
        await ManualSleeper.until { builds.started > 0 || history.batchRun == nil }
        try #require(builds.started == 1, "The change started the register's refresh")
        #expect(updates.refreshesRunning == 1)
        // Well past any short guess at when refreshes start, the batch still waits for the build.
        try await Task.sleep(for: .milliseconds(200))
        #expect(history.isBatchRunning, "Busy while the register builds")
        #expect(updates.lastBatch == nil)

        clock.now = 101.4
        builds.finishAll()
        // Fails fast, well inside the 2 s limit, if the last `refreshEnded()` stops waking `settle()` (m6).
        await RealTime.until(seconds: 1) { !history.isBatchRunning }
        try #require(!history.isBatchRunning, "The last refresh's end woke settle()")
        await history.batchRun?.task.value
        #expect(updates.refreshesRunning == 0)
        #expect(updates.lastBatch == 100...101.4, "Ends once the register has refreshed")
        #expect(register.seenRevision == updates.revision)
        #expect(register.allRows != before, "It shows the Undo")

        // The view's `onChange` for the same change then finds it up to date: no second refresh.
        await register.refresh(after: updates)
        #expect(builds.started == 1, "No double refresh")
    }

    @Test("An account the change didn't touch starts no refresh, so it holds nothing up")
    func untouchedSkipped() async throws {
        let updates = LedgerUpdates()
        let setup = try await QueuedCommandTests.setup(updates: updates)
        let history = setup.window.history
        let (card, builds) = Self.register(setup, updates: updates, accountID: F.cardID)

        history.undo()
        await history.batchRun?.task.value
        #expect(!history.isBatchRunning)
        #expect(builds.started == 0)
        #expect(card.seenRevision == updates.revision)
    }

    @Test("Registers are held weakly and can be removed")
    func weakAndRemovable() async throws {
        let updates = LedgerUpdates()
        let setup = try await QueuedCommandTests.setup(updates: updates)
        let (register, builds) = Self.register(setup, updates: updates)
        updates.remove(register)
        updates.changed()
        #expect(builds.started == 0)
        #expect(updates.refreshesRunning == 0, "A removed register isn't refreshed")

        weak var dropped: AccountHistoryViewModel?
        do {
            let (model, _) = Self.register(setup, updates: updates)
            dropped = model
        }
        #expect(dropped == nil, "The registration doesn't keep a window's history alive")
        updates.changed()
        #expect(updates.refreshesRunning == 0)
    }

    @Test("settle() waits for the last refresh to end, then one turn, with no timer")
    func settleEndsWithRefresh() async throws {
        let updates = LedgerUpdates()
        let sleeper = ManualSleeper()
        updates.sleep = sleeper.sleep
        updates.refreshStarted()
        updates.refreshStarted()
        let settle = Task { await updates.settle() }
        #expect(await sleeper.next() == LedgerUpdates.settleLimit, "Only the cap is waiting")
        updates.refreshEnded()
        #expect(sleeper.waiting == [LedgerUpdates.settleLimit], "One refresh still running")
        updates.refreshEnded()
        await ManualSleeper.until { sleeper.waiting == [BatchProgress.uiTurnLength] }
        // Without the wake-up only the cap would still wait: fail here rather than hang on `settle.value` (m6).
        try #require(sleeper.waiting == [BatchProgress.uiTurnLength], "The cap is cancelled; one turn follows")
        await sleeper.advance()
        #expect(await settle.value == false)
    }

    @Test("settle() gives up at its limit when a refresh never ends")
    func settleLimit() async {
        let updates = LedgerUpdates()
        let sleeper = ManualSleeper()
        updates.sleep = sleeper.sleep
        updates.refreshStarted()
        let settle = Task { await updates.settle() }
        #expect(await sleeper.advance() == LedgerUpdates.settleLimit)
        #expect(await sleeper.advance() == BatchProgress.uiTurnLength)
        #expect(await settle.value == true, "Reached the limit")
        #expect(updates.refreshesRunning == 1)
    }
}

/// Holds each build of a register's refresh until the test finishes it.
@MainActor
final class HeldRegisterBuilds {
    private(set) var started = 0
    private var held: [CheckedContinuation<Void, Never>] = []

    nonisolated var builder: AccountHistoryContentBuilder {
        { page, today, formatter, text in
            await self.hold()
            return AccountHistoryViewModel.content(of: page, today: today, formatter: formatter, text: text)
        }
    }

    private func hold() async {
        started += 1
        await withCheckedContinuation { held.append($0) }
    }

    /// Finishes the newest held build only.
    func finishNewest() {
        held.popLast()?.resume()
    }

    func finishAll() {
        let waiting = held
        held.removeAll()
        for continuation in waiting {
            continuation.resume()
        }
    }
}
