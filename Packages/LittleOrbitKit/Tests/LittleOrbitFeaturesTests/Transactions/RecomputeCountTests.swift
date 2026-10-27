import Foundation
import LittleOrbitDomain
import Testing

@testable import LittleOrbitFeatures

/// Tester2's five windows at 3dc318b (comment 6448338326): every change gave each window on the edited account two
/// full `window.recompute`s, where 1f2eae8 gave one. The change started the registered history's refresh, then the
/// account's row changed with its balance and its view's `task(id: row)` loaded it again; and `makeHistory` also
/// registered the histories SwiftUI makes and drops each time the view is made again. Each window now recomputes once
/// per change. This drives the app's own calls: `makeHistory`, and what the view runs on appear, row change,
/// disappear and `onChange`. Made-up data.
@MainActor
@Suite("One full recompute per window per change", .timeLimit(.minutes(1)))
struct RecomputeCountTests {
    typealias F = TransactionFeatureFixture  // swiftlint:disable:this type_name

    /// One window's account detail: the history it keeps, and one SwiftUI made and dropped but still holds.
    @MainActor
    final class Window {
        let feature: TransactionsFeature
        private(set) var history: AccountHistoryViewModel
        /// Made again with the view, as `State(initialValue:)` does, and never shown.
        private(set) var dropped: AccountHistoryViewModel

        init(_ feature: TransactionsFeature, accountID: UUID) {
            self.feature = feature
            history = feature.makeHistory(accountID: accountID)
            dropped = feature.makeHistory(accountID: accountID)
            history.appeared(in: feature.updates)
        }

        /// Picks another account: the old detail goes and a new one appears.
        func show(_ accountID: UUID) {
            history.disappeared(from: feature.updates)
            history = feature.makeHistory(accountID: accountID)
            dropped = feature.makeHistory(accountID: accountID)
            history.appeared(in: feature.updates)
        }

        /// What the view runs after a change: its row changed (`task(id: row)`) and `onChange(of: revision)`.
        func viewUpdates() async {
            history.appeared(in: feature.updates)
            await history.refresh(after: feature.updates)
        }
    }

    @Test("Three windows on the edited account and one elsewhere, after an account switch: one recompute each")
    func oneRecomputePerWindow() async throws {
        let updates = LedgerUpdates()
        // The cap can't end the wait on its own, so the batch ends only when the refreshes wake `settle()`; a
        // regression fails at the `#require` below and releases it, rather than hanging the run (m10 on 4ea9bd6).
        let cap = ManualSleeper(holding: [LedgerUpdates.settleLimit])
        updates.sleep = cap.sleep
        defer { cap.release() }
        let setup = try await QueuedCommandTests.setup(updates: updates)
        let useCases = TransactionUseCases(repository: setup.disk, categoryNames: CatalogDefaultCategoryNames())
        let feature = TransactionsFeature(
            useCases: useCases,
            locale: F.india,
            timeZone: F.zone,
            now: { F.now },
            updates: updates,
        )
        // Each window starts on another account, then picks the edited one, as Tester2's started on All
        // Transactions.
        let edited = (0..<3).map { _ in Window(feature, accountID: F.cardID) }
        for window in edited {
            window.show(F.savingsID)
        }
        let untouched = Window(feature, accountID: F.cardID)
        let windows = edited + [untouched]
        let before = windows.map(\.history.recomputes)
        #expect(before == [1, 1, 1, 1], "Each shown history loaded once")

        // A batch Undo from the first window.
        setup.window.history.undo()
        await RealTime.eventually { !setup.window.history.isBatchRunning }
        try #require(!setup.window.history.isBatchRunning, "The windows' refreshes woke settle(), and the batch ended")
        await setup.window.history.batchRun?.task.value
        for window in windows {
            await window.viewUpdates()
        }
        await ManualSleeper.until { updates.refreshesRunning == 0 }

        let counts = zip(windows, before).map { $0.history.recomputes - $1 }
        #expect(counts == [1, 1, 1, 0], "One full recompute per edited window, none in the untouched one")
        #expect(windows.allSatisfy { $0.dropped.recomputes == 0 }, "A dropped history never refreshes")
        #expect(windows.allSatisfy { $0.history.seenRevision == updates.revision })

        // A second change, a plain one: still one each.
        updates.changed()
        for window in windows {
            await window.viewUpdates()
        }
        await ManualSleeper.until { updates.refreshesRunning == 0 }
        let again = zip(windows, before).map { $0.history.recomputes - $1 }
        #expect(again == [2, 2, 2, 1])
    }

    @Test("A history whose view went isn't refreshed; it loads once when it appears again")
    func disappearAndReappear() async throws {
        let updates = LedgerUpdates()
        let setup = try await QueuedCommandTests.setup(updates: updates)
        let useCases = TransactionUseCases(repository: setup.disk, categoryNames: CatalogDefaultCategoryNames())
        let feature = TransactionsFeature(useCases: useCases, locale: F.india, timeZone: F.zone, updates: updates)
        let window = Window(feature, accountID: F.savingsID)
        let history = window.history
        #expect(history.recomputes == 1)

        history.disappeared(from: updates)
        updates.changed()
        await ManualSleeper.until { updates.refreshesRunning == 0 }
        #expect(history.recomputes == 1, "Not refreshed while away")

        history.appeared(in: updates)
        #expect(history.recomputes == 2, "Behind, so it loads once")
        history.appeared(in: updates)
        #expect(history.recomputes == 2, "Up to date: no second load")
    }
}
