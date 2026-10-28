import Foundation
import LittleOrbitDomain
import LittleOrbitPersistence
import Testing

@testable import LittleOrbitFeatures

/// Tester's crash report on 0d676f8 (comment 6450092506) and Tech Architect's ruling: a batch Undo still running when
/// its window had gone ended and announced into the freed test window, through the test window's unowned capture, and
/// aborted the process. Nothing in the batch's end reaches a window: a history let go of during the save, without
/// `cancelBatch`, still posts its change once and ends after the refreshes (B1, D403.1), with no one to announce to;
/// one let go of after the save is held by its run to the end, the announcement included. Made-up data.
@MainActor
@Suite("A batch whose window goes before it ends", .timeLimit(.minutes(1)))
struct BatchHistoryReleaseTests {
    typealias F = TransactionFeatureFixture  // swiftlint:disable:this type_name

    /// What the history announced, kept outside the window.
    final class Heard {
        var texts: [String] = []
    }

    /// Holds the background save until the test opens it.
    @MainActor
    final class SaveGate {
        private var held: CheckedContinuation<Void, Never>?
        private(set) var isHolding = false

        func hold() async {
            isHolding = true
            await withCheckedContinuation { held = $0 }
        }

        func open() {
            isHolding = false
            held?.resume()
            held = nil
        }
    }

    @Test("The window goes while the windows refresh: the batch still ends, and is still announced")
    func goneDuringSettle() async throws {
        let updates = LedgerUpdates()
        UptimeClock(now: 100).drive(updates)
        let sleeper = ManualSleeper()
        updates.sleep = sleeper.sleep
        let heard = Heard()
        let builds: HeldRegisterBuilds
        let register: AccountHistoryViewModel
        weak var window: TestWindow?
        weak var history: WindowUndoHistory?
        do {
            let setup = try await QueuedCommandTests.setup(updates: updates)
            (register, builds) = LedgerRefreshRegistrationTests.register(setup, updates: updates)
            setup.window.history.announce = { heard.texts.append($0) }
            window = setup.window
            history = setup.window.history
            setup.window.history.undo()
            // The refresh is counted as the change is posted, so settle() waits on its cap at once, but its build
            // runs in its own task and can start later under load (macOS CI, run 40611022307 attempt 2: 0): wait
            // for both.
            await RealTime.eventually { sleeper.waiting == [LedgerUpdates.settleLimit] && builds.started == 1 }
            try #require(sleeper.waiting == [LedgerUpdates.settleLimit], "settle() waits on its cap")
            try #require(builds.started == 1, "The batch's change started the register's refresh")
        }
        #expect(window == nil, "The window went")
        #expect(history != nil, "The run holds its history until it ends")
        #expect(updates.isBatchRunning)

        builds.finishAll()
        await RealTime.eventually { sleeper.waiting == [BatchProgress.uiTurnLength] }
        try #require(sleeper.waiting == [BatchProgress.uiTurnLength], "The refresh's end woke settle()")
        await sleeper.advance()
        await RealTime.eventually { !updates.isBatchRunning && history == nil }
        #expect(!updates.isBatchRunning, "The batch ended")
        #expect(history == nil, "The hold ended with the run")
        #expect(register.seenRevision == updates.revision)
        #expect(heard.texts.count == 1 && heard.texts.first?.hasPrefix("Undid") == true, "\(heard.texts)")
    }

    @Test("The window goes while the save runs off the main actor: installed, posted once, ended after the refresh")
    func goneDuringInstall() async throws {
        let updates = LedgerUpdates()
        UptimeClock(now: 100).drive(updates)
        let cap = ManualSleeper(holding: [LedgerUpdates.settleLimit])
        updates.sleep = cap.sleep
        // A regression fails at a `#require` below; the held cap then lets the batch run to its end (m10).
        defer { cap.release() }
        let gate = SaveGate()
        let heard = Heard()
        let rows = (0..<5).map { F.expense(Decimal(100 * ($0 + 1)), on: F.date(2026, 10, 10 + $0)) }
        let memory = try F.repository(rows)
        let useCases = TransactionUseCases(repository: memory, categoryNames: CatalogDefaultCategoryNames())
        // Another window's register, which the change refreshes.
        let feature = TransactionsFeature(
            useCases: useCases,
            locale: F.india,
            timeZone: F.zone,
            now: { F.now },
            updates: updates,
        )
        let register = feature.makeHistory(accountID: F.savingsID)
        let builds = HeldRegisterBuilds()
        register.buildContent = builds.builder
        register.appeared(in: updates)
        weak var window: TestWindow?
        weak var history: WindowUndoHistory?
        let revision: Int
        do {
            let opened = TestWindow(useCases, updates: updates)
            opened.history.setScreen(.account(F.savingsID))
            var changes = BulkEditChanges()
            changes.details = .some("Bulk")
            let request = BulkEditRequest(
                selection: rows,
                changes: changes,
                payeeName: "",
                accounts: try memory.accounts(),
                timeZoneID: F.zoneID,
                now: F.now,
            )
            let change = try await useCases.bulkEdit.apply(request, reporting: .silent)
            opened.history.record(change)
            opened.history.markBulkEdit(change)
            // The Bulk Edit's own change refreshed the register; that refresh ends before the batch.
            await RealTime.eventually { builds.started == 1 }
            builds.finishAll()
            await RealTime.eventually { updates.refreshesRunning == 0 }
            try #require(builds.started == 1 && updates.refreshesRunning == 0)
            opened.history.announce = { heard.texts.append($0) }
            memory.offMainSave = { await gate.hold() }
            window = opened
            history = opened.history
            revision = updates.revision
            opened.history.undo()
            await RealTime.eventually { gate.isHolding }
            try #require(gate.isHolding, "The save is running off the main actor")
        }
        #expect(window == nil && history == nil, "The window and its history went")
        #expect(updates.isBatchRunning)

        gate.open()
        await RealTime.eventually { builds.started == 2 }
        try #require(builds.started == 2, "The change was posted, and the other window refreshes")
        #expect(updates.revision == revision + 1, "Posted once")
        #expect(updates.isBatchRunning, "Busy until the refresh has finished")
        builds.finishAll()
        await RealTime.eventually { !updates.isBatchRunning }
        try #require(!updates.isBatchRunning, "The batch ended")
        #expect(try memory.transactions().allSatisfy { $0.details != "Bulk" }, "The Undo was installed")
        #expect(heard.texts.isEmpty, "No one to announce to: the history went")
    }
}
