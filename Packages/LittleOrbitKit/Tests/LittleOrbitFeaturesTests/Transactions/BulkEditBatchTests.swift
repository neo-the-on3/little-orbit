import Foundation
import LittleOrbitDomain
import LittleOrbitPersistence
import Testing

@testable import LittleOrbitFeatures

/// #285, D398: Bulk Edit Apply off the main actor gives what Apply on it gives, shows its progress, writes once or
/// not at all, and checks again when something wrote in between (Tech Architect's ruling 4 on 6435113427).
@MainActor
@Suite("Bulk edit as a batch")
struct BulkEditBatchTests {
    typealias F = TransactionFeatureFixture  // swiftlint:disable:this type_name

    static func rows(_ count: Int) -> [Transaction] {
        (0..<count).map { F.expense(Decimal($0 + 1), on: F.date(2026, 10, 1).addingTimeInterval(Double($0) * 60)) }
    }

    static func request(_ selection: [Transaction], accounts: [Account], payee: String = "") -> BulkEditRequest {
        var changes = BulkEditChanges()
        changes.categoryID = .some(DefaultCategoryID.food)
        if !payee.isEmpty {
            changes.payeeID = .some(nil)
        }
        return BulkEditRequest(
            selection: selection,
            changes: changes,
            payeeName: payee,
            accounts: accounts,
            timeZoneID: F.zoneID,
            now: F.now,
        )
    }

    @Test("Apply off the main actor writes what Apply on it writes, and returns the same change")
    func sameAsSync() async throws {
        let rows = Self.rows(150)
        let one = try F.repository(rows)
        let two = try F.repository(rows)
        let request = Self.request(Array(rows.prefix(100)), accounts: try one.accounts())
        let sync = try DefaultApplyBulkEditUseCase(repository: one).apply(request)
        let batch = try await DefaultApplyBulkEditUseCase(repository: two).apply(request, reporting: .silent)
        #expect(batch == sync)
        #expect(try two.transactions() == one.transactions())
    }

    @Test("One write: the store's revision moves once")
    func oneWrite() async throws {
        let rows = Self.rows(10)
        let repository = try F.repository(rows)
        let revision = try #require(repository.revision)
        let request = Self.request(rows, accounts: try repository.accounts(), payee: "Corner Bakery")
        _ = try await DefaultApplyBulkEditUseCase(repository: repository).apply(request, reporting: .silent)
        #expect(repository.revision == revision + 1)
        #expect(try repository.payees().map(\.name) == ["Corner Bakery"])
    }

    @Test("A row deleted while it was built: the commit checks again, writes nothing and says so (D393)")
    func deletedMeanwhile() async throws {
        let rows = Self.rows(10)
        let repository = try F.repository(rows)
        let request = Self.request(rows, accounts: try repository.accounts())
        let reporter = LedgerBatchReporter(willSave: { _ in try? repository.deleteTransaction(id: rows[3].id) })
        await #expect(throws: BulkEditSelectionDeleted(ids: [rows[3].id])) {
            try await DefaultApplyBulkEditUseCase(repository: repository).apply(request, reporting: reporter)
        }
        #expect(try repository.transactions().allSatisfy { $0.categoryID == nil })
    }

    @Test("A field another window changed meanwhile stays, as a fresh Apply would leave it (D395)")
    func changedMeanwhile() async throws {
        let rows = Self.rows(10)
        let repository = try F.repository(rows)
        let fresh = try F.repository(rows)
        let request = Self.request(rows, accounts: try repository.accounts())
        let elsewhere: @MainActor (InMemoryLedgerRepository) throws -> Void = { store in
            var row = try #require(try store.transactions().first { $0.id == rows[2].id })
            row.details = "Changed elsewhere"
            try store.saveTransaction(row)
        }
        let reporter = LedgerBatchReporter(willSave: { _ in try? elsewhere(repository) })
        let change = try await DefaultApplyBulkEditUseCase(repository: repository).apply(request, reporting: reporter)
        try elsewhere(fresh)
        let expected = try DefaultApplyBulkEditUseCase(repository: fresh).apply(request)
        #expect(change == expected)
        #expect(try repository.transactions() == fresh.transactions())
        #expect(try repository.transactions().first { $0.id == rows[2].id }?.details == "Changed elsewhere")
    }

    @Test("Cancelled before the write, nothing is written and nothing is created")
    func cancelled() async throws {
        let rows = Self.rows(10)
        let repository = try F.repository(rows)
        let revision = repository.revision
        let request = Self.request(rows, accounts: try repository.accounts(), payee: "New Shop")
        let reporter = LedgerBatchReporter(willSave: { _ in withUnsafeCurrentTask { $0?.cancel() } })
        await #expect(throws: CancellationError.self) {
            try await DefaultApplyBulkEditUseCase(repository: repository).apply(request, reporting: reporter)
        }
        #expect(repository.revision == revision)
        #expect(try repository.payees().isEmpty)
    }

    @Test("The sheet's model: progress while it runs, then the change; writes are off in every window meanwhile")
    func model() async throws {
        let rows = Self.rows(5)
        let repository = try F.repository(rows)
        let feature = TransactionsFeature(
            useCases: TransactionUseCases(repository: repository, categoryNames: CatalogDefaultCategoryNames()),
            locale: F.india,
            timeZone: F.zone,
        )
        let model = feature.makeBulkEdit(rows.map(\.id))
        model.editsCategory = true
        model.categoryID = DefaultCategoryID.food
        let window = feature.makeUndoHistory()
        let undoManager = FakeUndoManager()
        window.attach(undoManager)
        let task = Task { await model.applyInBackground() }
        await Task.yield()
        #expect(model.isApplying)
        #expect(model.progress?.title == "Applying Changes…")
        #expect(model.progress?.message == "Updating 5 transactions.")
        #expect(window.isBatchRunning)
        let change = try #require(await task.value)
        #expect(!model.isApplying)
        #expect(!window.isBatchRunning)
        window.record(change)
        window.markBulkEdit(change)
        #expect(window.undoSteps.last?.runsInBatch == true)
        #expect(undoManager.undoNames == ["Edit 5 Transactions in Everyday Savings"])
        #expect(try repository.transactions().allSatisfy { $0.categoryID == DefaultCategoryID.food })
    }

    @Test("While another batch runs, Apply starts nothing")
    func busy() async throws {
        let rows = Self.rows(3)
        let repository = try F.repository(rows)
        let feature = TransactionsFeature(
            useCases: TransactionUseCases(repository: repository, categoryNames: CatalogDefaultCategoryNames())
        )
        let model = feature.makeBulkEdit(rows.map(\.id))
        model.editsCategory = true
        model.categoryID = DefaultCategoryID.food
        #expect(feature.updates.beginBatch())
        #expect(await model.applyInBackground() == nil)
        feature.updates.endBatch()
        #expect(try repository.transactions().allSatisfy { $0.categoryID == nil })
    }
}

/// The progress model and its copy (D398.3).
@MainActor
@Suite("Bulk edit progress")
struct BatchProgressTests {
    @Test("Rows done, then Saving… with the bar full")
    func phases() async {
        // A clock that stands still: the parallel suite can be slow, and a quarter of a second would show the sheet.
        let instant = ContinuousClock.now
        let progress = BatchProgress(kind: .undoing, total: 3_334, showAfter: .seconds(60), now: { instant })
        let reporter = progress.start()
        #expect(progress.title == "Undoing Changes…")
        #expect(progress.message == "Updating 3334 transactions." || progress.message == "Updating 3,334 transactions.")
        reporter.rowsDone(128)
        while progress.done < 128 {
            await Task.yield()
        }
        #expect(progress.value == 128)
        #expect(progress.stage == .updating)
        await reporter.willSave(10)
        #expect(progress.stage == .saving)
        #expect(progress.value == 3_334)
        #expect(progress.message == "Saving…")
        #expect(!progress.isShown, "Not before its delay")
        progress.finish()
    }

    @Test("One transaction reads in the singular; Redo and Apply have their own titles")
    func copy() {
        #expect(BatchProgress(kind: .redoing, total: 1).message == "Updating 1 transaction.")
        #expect(BatchProgress(kind: .redoing, total: 1).title == "Redoing Changes…")
        #expect(BatchProgress(kind: .applying, total: 2).title == "Applying Changes…")
    }

    @Test("The sheet shows only once the work has run for its delay (half a second in the app)")
    func delay() async throws {
        #expect(BatchProgress.showDelay == .milliseconds(500))
        let progress = BatchProgress(kind: .applying, total: 10, showAfter: .milliseconds(20))
        _ = progress.start()
        #expect(!progress.isShown)
        // Other tests share the main actor, so the delay is a lower bound here: wait for it, up to 10 s.
        let clock = ContinuousClock()
        let start = clock.now
        while !progress.isShown, clock.now - start < .seconds(10) {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(progress.isShown)
        #expect(clock.now - start >= .milliseconds(20))
        progress.finish()
    }

    @Test("Saving… gives the UI a turn of the run loop even before the sheet shows, so it draws first (N5)")
    func turnBeforeSave() async {
        let instant = ContinuousClock.now
        let progress = BatchProgress(kind: .applying, total: 10, showAfter: .seconds(60), now: { instant })
        let reporter = progress.start()
        let clock = ContinuousClock()
        let start = clock.now
        await reporter.willSave(10)
        #expect(clock.now - start >= BatchProgress.uiTurnLength)
        #expect(progress.stage == .saving)
        #expect(!progress.isShown)
        progress.finish()
    }
}
