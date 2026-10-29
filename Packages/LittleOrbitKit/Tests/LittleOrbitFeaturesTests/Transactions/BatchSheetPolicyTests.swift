import Foundation
import LittleOrbitDomain
import LittleOrbitPersistence
import Testing

@testable import LittleOrbitFeatures

/// D401, Tech Architect's review 5664921216: the progress sheet's decision just before the main-thread save, and
/// the progress model acting on it for Apply, Undo and Redo.
@MainActor
@Suite("Batch sheet before the save", .timeLimit(.minutes(1)))
struct BatchSheetPolicyTests {
    typealias Policy = BatchSheetPolicy

    /// A clock the test moves by hand.
    final class ManualClock {
        var instant = ContinuousClock.now
        func advance(_ duration: Duration) {
            instant += duration
        }
    }

    @Test("The thresholds: a quarter of a second before the save, or 750 changed rows")
    func thresholds() {
        #expect(Policy.elapsedThatShowsSheet == .milliseconds(250))
        #expect(Policy.rowsThatShowSheet == 750)
    }

    @Test("Elapsed time alone shows the sheet: a slow build of a few rows")
    func elapsedBranch() {
        #expect(Policy.beforeSave(elapsed: .milliseconds(250), changedRows: 3, isShown: false) == .show)
        #expect(Policy.beforeSave(elapsed: .seconds(2), changedRows: 1, isShown: false) == .show)
    }

    @Test("Changed rows alone show the sheet: a quick build of a big save")
    func rowCountBranch() {
        #expect(Policy.beforeSave(elapsed: .zero, changedRows: 750, isShown: false) == .show)
        #expect(Policy.beforeSave(elapsed: .milliseconds(40), changedRows: 3_334, isShown: false) == .show)
    }

    @Test("Neither: a quick, small run shows no sheet")
    func neither() {
        #expect(Policy.beforeSave(elapsed: .milliseconds(249), changedRows: 749, isShown: false) == .skip)
        #expect(Policy.beforeSave(elapsed: .milliseconds(30), changedRows: 12, isShown: false) == .skip)
    }

    @Test("A sheet the timer already showed stays")
    func alreadyShown() {
        #expect(Policy.beforeSave(elapsed: .milliseconds(600), changedRows: 3_334, isShown: true) == .keepShown)
        #expect(Policy.beforeSave(elapsed: .milliseconds(600), changedRows: 3, isShown: true) == .keepShown)
    }

    @Test(
        "Apply, Undo and Redo: many rows put the sheet up in Saving… before the save, which waits for it",
        arguments: [
            BatchProgress.Kind.applying, .undoing, .redoing,
        ],
    )
    func showsBeforeSave(kind: BatchProgress.Kind) async {
        let clock = ManualClock()
        let progress = BatchProgress(kind: kind, total: 3_334, showAfter: nil, now: { clock.instant })
        let reporter = progress.start()
        clock.advance(.milliseconds(100))
        progress.sheetAppeared()
        await reporter.willSave(3_334)
        #expect(progress.isShown)
        #expect(progress.stage == .saving)
        #expect(progress.value == 3_334)
        progress.finish()
    }

    @Test("A build that ran a quarter of a second shows the sheet for a small save too")
    func elapsedShowsBeforeSave() async {
        let clock = ManualClock()
        let progress = BatchProgress(kind: .undoing, total: 20, showAfter: nil, now: { clock.instant })
        let reporter = progress.start()
        clock.advance(.milliseconds(300))
        progress.sheetAppeared()
        await reporter.willSave(20)
        #expect(progress.isShown)
        progress.finish()
    }

    @Test("A quick one-window Apply of a few rows shows no sheet, and the timer stops at the save")
    func quickApplyShowsNothing() async throws {
        let clock = ManualClock()
        let sleeper = ManualSleeper()
        defer { sleeper.release() }
        let progress = BatchProgress(
            kind: .applying,
            total: 40,
            showAfter: .milliseconds(30),
            now: { clock.instant },
            timerSleep: sleeper.sleep,
        )
        let reporter = progress.start()
        let timer = try #require(progress.timer)
        #expect(await sleeper.next() == .milliseconds(30))
        clock.advance(.milliseconds(20))
        await reporter.willSave(40)
        #expect(!progress.isShown)
        // The timer can't show it afterwards: it covers the build only. Its sleep ends as if its time had come.
        sleeper.release()
        await timer.value
        #expect(!progress.isShown)
        progress.finish()
    }

    @Test("The save waits at most a short, bounded time for a sheet that doesn't appear (D401.4)")
    func boundedWait() async {
        #expect(BatchProgress.sheetAppearLimit + BatchProgress.sheetSettle < .milliseconds(750))
        let progress = BatchProgress(kind: .redoing, total: 3_334, showAfter: nil)
        let reporter = progress.start()
        let clock = ContinuousClock()
        let start = clock.now
        await reporter.willSave(3_334)
        #expect(progress.isShown)
        #expect(!progress.hasAppeared)
        #expect(clock.now - start >= BatchProgress.sheetAppearLimit)
        progress.finish()
    }
}

/// D402: an Apply whose plan changes no row never shows the sheet.
@MainActor
@Suite("Batch sheet for an Apply that changes nothing")
struct BatchSheetNoRowTests {
    typealias F = TransactionFeatureFixture  // swiftlint:disable:this type_name

    @Test("No changed rows: no sheet, however long it ran, and one already up closes")
    func zeroRowDecision() {
        #expect(BatchSheetPolicy.beforeSave(elapsed: .zero, changedRows: 0, isShown: false) == .none)
        #expect(BatchSheetPolicy.beforeSave(elapsed: .seconds(3), changedRows: 0, isShown: false) == .none)
        #expect(BatchSheetPolicy.beforeSave(elapsed: .seconds(3), changedRows: 0, isShown: true) == .none)
    }

    @Test("A 0-row plan stops the timer, so the sheet never shows afterwards")
    func zeroRowStopsTimer() async throws {
        let sleeper = ManualSleeper()
        defer { sleeper.release() }
        let progress = BatchProgress(
            kind: .applying,
            total: 3_334,
            showAfter: .milliseconds(30),
            timerSleep: sleeper.sleep,
        )
        let reporter = progress.start()
        let timer = try #require(progress.timer)
        #expect(await sleeper.next() == .milliseconds(30))
        await reporter.willSave(0)
        #expect(!progress.isShown)
        // Its sleep ends as if its time had come: a timer the 0-row plan left running would show the sheet now.
        sleeper.release()
        await timer.value
        #expect(!progress.isShown)
        progress.finish()
    }

    @Test("A 0-row plan closes a sheet the timer already showed")
    func zeroRowClosesSheet() async throws {
        // The timer's sleep waits for the test, so a main actor held up by other suites can't decide it (#303).
        let sleeper = ManualSleeper()
        defer { sleeper.release() }
        let progress = BatchProgress(
            kind: .applying,
            total: 3_334,
            showAfter: .milliseconds(1),
            timerSleep: sleeper.sleep,
        )
        let reporter = progress.start()
        #expect(await sleeper.advance() == .milliseconds(1))
        await progress.timer?.value
        #expect(progress.isShown)
        await reporter.willSave(0)
        #expect(!progress.isShown)
        progress.finish()
    }

    @Test("Apply reports how many rows its save changes: none for a 0-row Apply, every row otherwise")
    func applyReportsChangedRows() async throws {
        let rows = BulkEditBatchTests.rows(5)
        let repository = try F.repository(rows)
        let request = BulkEditBatchTests.request(rows, accounts: try repository.accounts())
        let counts = RowCounts()
        let reporter = LedgerBatchReporter(willSave: { counts.values.append($0) })
        _ = try await DefaultApplyBulkEditUseCase(repository: repository).apply(request, reporting: reporter)
        // The same edit again changes nothing: every row already has that category.
        _ = try await DefaultApplyBulkEditUseCase(repository: repository).apply(request, reporting: reporter)
        #expect(counts.values == [5, 0])
    }
}

/// What a reporter heard, on the main actor.
@MainActor
final class RowCounts {
    var values: [Int] = []
}
