import Foundation
import LittleOrbitDomain
import LittleOrbitPersistence
import Testing

@testable import LittleOrbitFeatures

/// #285, B1 (Tech Architect's review 5667872455): a batch Undo or Redo handed off to a background save can't be
/// cancelled. Closing the window (`cancelBatch`, from the progress sheet's `onDisappear`) or clearing the history
/// during the save leaves busy on until the save ends; then the batch ends, its step goes without an alert or
/// announcement, and the change it wrote is posted once, so every window shows it. Made-up data.
@MainActor
// A guard taken out hangs a test instead of failing it, so the suite has a limit (Tech Architect n1, 5668982251).
@Suite("Cancelling a batch Undo or Redo during its background save (B1)", .timeLimit(.minutes(1)))
struct BatchCancelDuringSaveTests {
    typealias F = TransactionFeatureFixture  // swiftlint:disable:this type_name

    enum Cancel: CaseIterable, Sendable {
        /// The window closes: the sheet's `onDisappear` calls `cancelBatch()`.
        case windowCloses
        /// The history is cleared, as after the ledger is replaced.
        case historyCleared
    }

    /// The store's background save, held until the test lets it end.
    @MainActor
    final class HeldSave {
        private(set) var saves = 0
        private(set) var isSaving = false
        private var gate: CheckedContinuation<Void, Never>?

        func run() async {
            saves += 1
            isSaving = true
            await withCheckedContinuation { gate = $0 }
            isSaving = false
        }

        func started() async {
            while !isSaving {
                await Task.yield()
            }
        }

        func release() {
            gate?.resume()
            gate = nil
        }
    }

    @MainActor
    struct Setup {
        let repository: InMemoryLedgerRepository
        let updates = LedgerUpdates()
        let window: TestWindow
        let ids: Set<UUID>
        let held = HeldSave()

        /// A Bulk Edit of five rows, recorded as its step, through a store whose batch saves run off the main actor.
        init() async throws {
            let rows = (0..<5).map { F.expense(Decimal(100 * ($0 + 1)), on: F.date(2026, 10, 10 + $0)) }
            ids = Set(rows.map(\.id))
            repository = try F.repository(rows)
            repository.offMainSave = {}
            let useCases = TransactionUseCases(repository: repository, categoryNames: CatalogDefaultCategoryNames())
            window = TestWindow(useCases, updates: updates)
            window.history.setScreen(.account(F.savingsID))
            var changes = BulkEditChanges()
            changes.details = .some("Bulk")
            let request = BulkEditRequest(
                selection: try repository.transactions().filter { ids.contains($0.id) },
                changes: changes,
                payeeName: "",
                accounts: try repository.accounts(),
                timeZoneID: F.zoneID,
                now: F.now,
            )
            let change = try await useCases.bulkEdit.apply(request, reporting: .silent)
            window.history.record(change)
            window.history.markBulkEdit(change)
        }

        /// From now on each background save waits for `held.release()`.
        func holdSaves() {
            let held = held
            repository.offMainSave = { await held.run() }
        }

        func details() throws -> Set<String?> {
            Set(try repository.transactions().filter { ids.contains($0.id) }.map(\.details))
        }
    }

    /// Undoes the Bulk Edit, or undoes it and then redoes it, with the last save held; returns the run's task once
    /// its save has started.
    private static func startHeld(_ setup: Setup, undoing: Bool) async throws -> Task<Void, Never> {
        if !undoing {
            setup.window.history.undo()
            setup.window.settle()
            await setup.window.history.batchRun?.task.value
            #expect(try setup.details() == [nil])
        }
        setup.holdSaves()
        if undoing {
            setup.window.history.undo()
        } else {
            setup.window.history.redo()
        }
        setup.window.settle()
        let task = try #require(setup.window.history.batchRun?.task)
        await setup.held.started()
        return task
    }

    private static func cancel(_ setup: Setup, _ how: Cancel) {
        switch how {
        case .windowCloses:
            setup.window.history.cancelBatch()
        case .historyCleared:
            setup.window.history.clear()
        }
    }

    @Test(
        "Busy stays on until the save ends; the store changes once and every window hears of it once",
        arguments: [true, false],
        Cancel.allCases,
    )
    func cancelDuringSave(undoing: Bool, how: Cancel) async throws {
        let setup = try await Setup()
        let task = try await Self.startHeld(setup, undoing: undoing)
        #expect(setup.window.history.batchProgress?.showsIndeterminateBar == true, "Handed off (D405.5)")
        let revision = setup.updates.revision
        let announced = setup.window.announcements.count

        Self.cancel(setup, how)
        #expect(setup.window.history.isBatchRunning, "Busy is held while the save runs")
        #expect(setup.updates.revision == revision)
        Self.cancel(setup, how)
        #expect(setup.window.history.isBatchRunning, "A second cancel changes nothing")

        setup.held.release()
        await task.value
        setup.window.settle()
        #expect(!setup.window.history.isBatchRunning, "Busy ends with the save")
        #expect(setup.window.history.batchProgress == nil)
        #expect(setup.held.saves == 1, "One background save")
        #expect(try setup.details() == (undoing ? [nil] : ["Bulk"]), "The store holds the revert, once")
        #expect(setup.updates.revision == revision + 1, "One change notice")
        let delta = setup.updates.delta(since: revision)
        #expect(!delta.isEverything)
        #expect(delta.transactionIDs == setup.ids, "With the step's rows")
        #expect(setup.window.undoManager.undoNames.isEmpty)
        #expect(setup.window.undoManager.redoNames.isEmpty)
        #expect(!setup.window.history.canUndo && !setup.window.history.canRedo)
        #expect(setup.window.history.alert == nil)
        #expect(setup.window.announcements.count == announced, "No announcement for a cancelled run")
    }

    @Test("A save handed off fails after the window closed: the step goes, with no alert and no change notice")
    func failedAfterCancel() async throws {
        let setup = try await Setup()
        struct SaveFailed: Error {}
        let held = setup.held
        setup.repository.offMainSave = {
            await held.run()
            throw SaveFailed()
        }
        setup.window.history.undo()
        setup.window.settle()
        let task = try #require(setup.window.history.batchRun?.task)
        await held.started()
        let revision = setup.updates.revision
        setup.window.history.cancelBatch()
        #expect(setup.window.history.isBatchRunning)
        held.release()
        await task.value
        #expect(!setup.window.history.isBatchRunning)
        #expect(try setup.details() == ["Bulk"], "Nothing was written")
        #expect(setup.updates.revision == revision)
        #expect(setup.window.undoManager.undoNames.isEmpty)
        #expect(setup.window.undoManager.redoNames.isEmpty)
        #expect(setup.window.history.alert == nil)
    }

    @Test("Cancelled before the hand-off, it still stops at once and writes nothing", arguments: Cancel.allCases)
    func cancelBeforeHandOff(how: Cancel) async throws {
        let setup = try await Setup()
        setup.holdSaves()
        let revision = setup.updates.revision
        setup.window.history.undo()
        setup.window.settle()
        let task = try #require(setup.window.history.batchRun?.task)
        Self.cancel(setup, how)
        #expect(!setup.window.history.isBatchRunning, "Nothing was handed off: busy ends now")
        await task.value
        #expect(setup.held.saves == 0)
        #expect(try setup.details() == ["Bulk"])
        #expect(setup.updates.revision == revision)
        #expect(setup.window.undoManager.undoNames.isEmpty)
        #expect(setup.window.undoManager.redoNames.isEmpty)
    }

    @Test("The history goes during the save: the save ends, writes come back on, and the change is posted once")
    func historyGoesDuringSave() async throws {
        var setup: Setup? = try await Setup()
        let updates = try #require(setup?.updates)
        let held = try #require(setup?.held)
        let repository = try #require(setup?.repository)
        let ids = try #require(setup?.ids)
        let task = try await Self.startHeld(try #require(setup), undoing: true)
        let revision = updates.revision
        weak let history = setup?.window.history
        setup = nil
        #expect(history == nil)
        #expect(updates.isBatchRunning)
        held.release()
        await task.value
        #expect(!updates.isBatchRunning)
        #expect(held.saves == 1)
        #expect(Set(try repository.transactions().filter { ids.contains($0.id) }.map(\.details)) == [nil])
        #expect(updates.revision == revision + 1)
        #expect(updates.delta(since: revision).transactionIDs == ids)
    }

    @Test(
        "The window closes while the sheet of a revert that wrote closes: no wait, one change notice, no announcement",
        arguments: Cancel.allCases,
    )
    func cancelWhileSheetCloses(how: Cancel) async throws {
        let setup = try await Setup()
        // The sheet shows during the held save, as after half a second in the app.
        setup.window.history.progressShowDelay = .zero
        let task = try await Self.startHeld(setup, undoing: true)
        let sleeper = ManualSleeper()
        setup.window.history.batchProgress?.sleep = sleeper.sleep
        await ManualSleeper.until { setup.window.history.batchProgress?.isShown == true }
        try #require(setup.window.history.batchProgress?.isShown == true)
        let revision = setup.updates.revision
        let announced = setup.window.announcements.count
        setup.held.release()
        // Installed: the sheet is taken down, and the change waits until it has gone (D405 on 1f2eae8).
        await ManualSleeper.until { setup.window.history.closingProgress != nil }
        #expect(setup.window.history.batchProgress == nil)
        #expect(setup.window.history.isBatchRunning)
        #expect(setup.updates.revision == revision, "Not while the sheet is up")

        Self.cancel(setup, how)
        await ManualSleeper.until { !setup.window.history.isBatchRunning }
        #expect(!setup.window.history.isBatchRunning, "The wait for a sheet whose window went ends at once")
        // Lets a run that still waits end, so a failure above doesn't hang the test.
        setup.window.history.closingProgress?.sheetClosed()
        await task.value
        #expect(setup.updates.revision == revision + 1, "One change notice")
        #expect(try setup.details() == [nil], "The store holds the revert")
        #expect(setup.window.undoManager.undoNames.isEmpty)
        #expect(setup.window.undoManager.redoNames.isEmpty)
        #expect(setup.window.announcements.count == announced, "No announcement for a cancelled run")
        #expect(setup.window.history.closingProgress == nil)
    }

    @Test("Bulk Edit Apply is unaffected: cancelled during its save, busy holds until the write ends and it returns")
    func applyCancelledDuringSave() async throws {
        let rows = (0..<5).map { F.expense(Decimal(100 * ($0 + 1)), on: F.date(2026, 10, 10 + $0)) }
        let repository = try F.repository(rows)
        let held = HeldSave()
        repository.offMainSave = { await held.run() }
        let updates = LedgerUpdates()
        let useCases = TransactionUseCases(repository: repository, categoryNames: CatalogDefaultCategoryNames())
        let model = BulkEditViewModel(
            loadLedger: useCases.loadLedger,
            applyBulkEdit: DefaultApplyBulkEditUseCase(repository: repository),
            transactionIDs: rows.map(\.id),
        )
        model.updates = updates
        let instant = ContinuousClock.now
        model.progressClock = { instant }
        model.progressShowDelay = nil
        model.editsCategory = true
        model.categoryID = DefaultCategoryID.food
        let apply = Task { await model.applyInBackground() }
        await held.started()
        // The sheet's Cancel, or the sheet going, cancels the view's task.
        apply.cancel()
        await Task.yield()
        #expect(updates.isBatchRunning, "Busy is held while the save runs")
        held.release()
        let change = await apply.value
        #expect(change != nil, "The write happened, so the change comes back for its Undo step")
        #expect(!updates.isBatchRunning)
        #expect(held.saves == 1)
        let ids = Set(rows.map(\.id))
        #expect(
            try repository.transactions().filter { ids.contains($0.id) }
                .allSatisfy {
                    $0.categoryID == DefaultCategoryID.food
                }
        )
    }
}
