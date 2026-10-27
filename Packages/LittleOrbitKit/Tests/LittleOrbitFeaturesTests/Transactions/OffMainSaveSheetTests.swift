import Foundation
import LittleOrbitDomain
import LittleOrbitPersistence
import Testing

@testable import LittleOrbitFeatures

/// #285, B: with the save off the main actor, the progress sheet goes up once at most, whether the decision
/// before the save or the half-second timer asks first; the timer keeps running through the save; "Saving…" can
/// move; and a batch Undo holds the shared busy flag for the whole save and leaves one Undo step.
@MainActor
@Suite("Progress sheet with the save off the main actor (#285, B)")
struct OffMainSaveSheetTests {
    typealias F = TransactionFeatureFixture  // swiftlint:disable:this type_name

    /// A clock the test moves by hand, for the elapsed time the decision reads.
    final class ManualClock {
        var instant = ContinuousClock.now
    }

    @Test("Shown before the save, then the timer fires: the sheet went up once")
    func shownOnce() async throws {
        let clock = ManualClock()
        let progress = BatchProgress(
            kind: .applying,
            total: 3_334,
            showAfter: .milliseconds(60),
            now: { clock.instant },
        )
        let reporter = progress.start()
        clock.instant += .milliseconds(300)
        try #require(reporter.willSaveOffMain != nil)
        await reporter.reportSaving(3_334, offMain: true)
        #expect(progress.isShown)
        #expect(progress.stage == .saving)
        #expect(progress.savesOffMain, "The bar moves while the save runs")
        // The save is still running when the timer's half second (60 ms here) passes.
        try await Task.sleep(for: .milliseconds(150))
        #expect(progress.isShown)
        #expect(progress.timesShown == 1)
        progress.finish()
    }

    @Test("A quick, small batch skips the sheet before the save, and the timer shows it once if the save runs long")
    func timerDuringSave() async throws {
        let clock = ManualClock()
        let progress = BatchProgress(kind: .undoing, total: 20, showAfter: .milliseconds(60), now: { clock.instant })
        let reporter = progress.start()
        clock.instant += .milliseconds(10)
        await reporter.reportSaving(20, offMain: true)
        #expect(!progress.isShown, "No flash for a quick, small batch")
        #expect(progress.timesShown == 0)
        try await Task.sleep(for: .milliseconds(200))
        #expect(progress.isShown, "The timer still runs during a save off the main actor")
        #expect(progress.timesShown == 1)
        progress.finish()
    }

    @Test("The bar turns indeterminate once, at the save, and never back; the title and \"Saving…\" stay (UI Designer)")
    func indeterminateOneWay() async throws {
        let progress = BatchProgress(kind: .undoing, total: 4, showAfter: nil)
        let reporter = progress.start()
        let title = progress.title
        reporter.rowsDone(2)
        let clock = ContinuousClock()
        let start = clock.now
        while progress.done < 2, clock.now - start < .seconds(10) {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(!progress.showsIndeterminateBar, "Determinate while the rows are checked")
        #expect(progress.value == 2)
        #expect(progress.message == "Updating 4 transactions.")
        await reporter.reportSaving(4, offMain: true)
        var seen = [progress.showsIndeterminateBar]
        // A row count that arrives late, then a save that falls back to the main actor.
        reporter.rowsDone(3)
        try await Task.sleep(for: .milliseconds(50))
        seen.append(progress.showsIndeterminateBar)
        await reporter.willSave(4)
        seen.append(progress.showsIndeterminateBar)
        #expect(seen == [true, true, true], "One switch, no flicker back to determinate")
        #expect(progress.stage == .saving)
        #expect(progress.value == 4)
        #expect(progress.message == "Saving…", "VoiceOver still reads Saving…")
        #expect(progress.title == title)
        progress.finish()
    }

    @Test("No row to change: no sheet, and the timer is stopped (D402)")
    func noRows() async throws {
        let progress = BatchProgress(kind: .applying, total: 5, showAfter: .milliseconds(40))
        let reporter = progress.start()
        await reporter.reportSaving(0, offMain: true)
        try await Task.sleep(for: .milliseconds(150))
        #expect(!progress.isShown)
        #expect(progress.timesShown == 0)
        progress.finish()
    }

    @Test("The main-actor save keeps its behaviour: the bar stays full, the timer stops")
    func mainActorSave() async throws {
        let clock = ManualClock()
        let progress = BatchProgress(kind: .redoing, total: 20, showAfter: .milliseconds(40), now: { clock.instant })
        let reporter = progress.start()
        await reporter.reportSaving(20, offMain: false)
        try await Task.sleep(for: .milliseconds(150))
        #expect(!progress.savesOffMain)
        #expect(!progress.isShown, "The save cancels the timer")
        progress.finish()
    }

    @Test("A batch Undo saved off the main actor: busy for the whole save, one Undo step, then the store reverted")
    func undoHoldsBusy() async throws {
        let rows = (0..<5).map { F.expense(Decimal(100 * ($0 + 1)), on: F.date(2026, 10, 10 + $0)) }
        let repository = try F.repository(rows)
        let updates = LedgerUpdates()
        var busyDuringSave: [Bool] = []
        repository.offMainSave = {
            busyDuringSave.append(updates.isBatchRunning)
            await Task.yield()
            busyDuringSave.append(updates.isBatchRunning)
        }
        let useCases = TransactionUseCases(repository: repository, categoryNames: CatalogDefaultCategoryNames())
        let window = TestWindow(useCases, updates: updates)
        window.history.setScreen(.account(F.savingsID))
        var changes = BulkEditChanges()
        changes.categoryID = .some(DefaultCategoryID.food)
        let request = BulkEditRequest(
            selection: try repository.transactions().filter { Set(rows.map(\.id)).contains($0.id) },
            changes: changes,
            payeeName: "",
            accounts: try repository.accounts(),
            timeZoneID: F.zoneID,
            now: F.now,
        )
        let change = try await useCases.bulkEdit.apply(request, reporting: .silent)
        window.history.record(change)
        window.history.markBulkEdit(change)
        busyDuringSave = []

        window.history.undo()
        #expect(window.history.isBatchRunning)
        await window.history.batchRun?.task.value
        #expect(busyDuringSave == [true, true], "No other ledger write can start during the save")
        #expect(!updates.isBatchRunning)
        #expect(window.undoManager.undoNames.isEmpty)
        #expect(window.undoManager.redoNames.count == 1, "Exactly one step for the batch")
        #expect(window.history.alert == nil)
        let stored = try repository.transactions().filter { Set(rows.map(\.id)).contains($0.id) }
        #expect(stored.allSatisfy { $0.categoryID != DefaultCategoryID.food })
    }
}
