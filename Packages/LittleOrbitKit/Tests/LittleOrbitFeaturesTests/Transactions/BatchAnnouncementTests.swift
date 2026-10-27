import Foundation
import LittleOrbitDomain
import LittleOrbitPersistence
import Testing

@testable import LittleOrbitFeatures

/// Tester2's N5 at c8c6594 (comment 6440723910), Tech Architect's and UI Designer's ruling: how a batch ended is
/// announced after its progress sheet has closed, for Apply, Undo and Redo alike; with no sheet, when it ends.
@MainActor
@Suite("Batch announcements after the sheet closes")
struct BatchAnnouncementTests {
    typealias F = TransactionFeatureFixture  // swiftlint:disable:this type_name

    /// What was posted, in order.
    final class Heard {
        var texts: [String] = []
    }

    @Test("No sheet: posted at once")
    func noSheet() {
        let heard = Heard()
        let progress = BatchProgress(kind: .applying, total: 3, showAfter: .seconds(60))
        progress.announceAfterSheet("Changed 3 transactions.") { heard.texts.append($0) }
        #expect(heard.texts == ["Changed 3 transactions."])
    }

    @Test("A sheet showed: held until it has closed, then posted once")
    func heldUntilClosed() async {
        let heard = Heard()
        let progress = BatchProgress(kind: .undoing, total: 3_334, showAfter: .seconds(60))
        let reporter = progress.start()
        progress.sheetAppeared()
        await reporter.willSave(3_334)
        progress.finish()
        #expect(progress.isShown)
        progress.announceAfterSheet("Undid Edit") { heard.texts.append($0) }
        #expect(heard.texts.isEmpty, "Not while the sheet is still up")
        progress.sheetClosed()
        #expect(heard.texts == ["Undid Edit"])
        progress.sheetClosed()
        #expect(heard.texts == ["Undid Edit"], "Once")
    }

    @Test("A sheet that never reports closing still gets its announcement, after a short wait")
    func fallback() async throws {
        #expect(BatchProgress.announcementFallbackDelay == .milliseconds(1_500))
        let heard = Heard()
        let progress = BatchProgress(kind: .redoing, total: 3_334, showAfter: .seconds(60))
        let reporter = progress.start()
        progress.sheetAppeared()
        await reporter.willSave(3_334)
        progress.finish()
        progress.announceAfterSheet("Redid Edit") { heard.texts.append($0) }
        let clock = ContinuousClock()
        let start = clock.now
        while heard.texts.isEmpty, clock.now - start < .seconds(10) {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(heard.texts == ["Redid Edit"])
        #expect(clock.now - start >= .milliseconds(1_400))
    }

    static func applyModel(_ repository: some LedgerRepository, rows: [Transaction], heard: Heard)
        -> BulkEditViewModel
    {
        let useCases = TransactionUseCases(repository: repository, categoryNames: CatalogDefaultCategoryNames())
        let model = BulkEditViewModel(
            loadLedger: useCases.loadLedger,
            applyBulkEdit: DefaultApplyBulkEditUseCase(repository: repository),
            transactionIDs: rows.map(\.id),
        )
        model.announce = { heard.texts.append($0) }
        // A clock that stands still, so a slow parallel run can't pass the quarter of a second that shows the sheet,
        // and a sheet timer that doesn't fire (review 5666870090). Past 750 rows the sheet still shows before the save.
        let instant = ContinuousClock.now
        model.progressClock = { instant }
        model.progressShowDelay = .seconds(60)
        model.editsCategory = true
        model.categoryID = DefaultCategoryID.food
        return model
    }

    @Test("Apply with the sheet: the count is heard only after the sheet closes, which keeps the progress drawn")
    func applyAfterSheet() async throws {
        let rows = BulkEditBatchTests.rows(BatchSheetPolicy.rowsThatShowSheet)
        let repository = try F.repository(rows)
        let heard = Heard()
        let model = Self.applyModel(repository, rows: rows, heard: heard)
        _ = try #require(await model.applyInBackground())
        #expect(heard.texts.isEmpty, "Not before the sheet closes")
        #expect(model.progress == nil)
        #expect(model.closingProgress?.isShown == true, "The progress, not the fields, while the sheet closes")
        model.sheetClosed()
        #expect(heard.texts == ["Changed 750 transactions."])
        #expect(model.closingProgress == nil)
    }

    @Test("Apply without the sheet: heard when it finishes")
    func applyWithoutSheet() async throws {
        let rows = BulkEditBatchTests.rows(4)
        let repository = try F.repository(rows)
        let heard = Heard()
        let model = Self.applyModel(repository, rows: rows, heard: heard)
        _ = try #require(await model.applyInBackground())
        #expect(heard.texts == ["Changed 4 transactions."])
        #expect(model.closingProgress == nil)
    }

    @Test("Undo and Redo with the sheet: heard only after it closes", arguments: [true, false])
    func undoRedoAfterSheet(redo: Bool) async throws {
        let count = BatchSheetPolicy.rowsThatShowSheet
        let rows = (0..<count)
            .map { F.expense(Decimal($0 + 1), on: F.date(2026, 10, 1).addingTimeInterval(Double($0) * 60)) }
        let disk = FullDiskLedgerRepository(try F.repository(rows))
        disk.hasBatchPath = true
        let useCases = TransactionUseCases(repository: disk, categoryNames: CatalogDefaultCategoryNames())
        let window = TestWindow(useCases)
        window.history.setScreen(.account(F.savingsID))
        var changes = BulkEditChanges()
        changes.details = .some("Bulk")
        let request = BulkEditRequest(
            selection: rows,
            changes: changes,
            payeeName: "",
            accounts: try disk.accounts(),
            timeZoneID: F.zoneID,
            now: F.now,
        )
        let change = try await useCases.bulkEdit.apply(request, reporting: .silent)
        window.history.record(change)
        window.history.markBulkEdit(change)
        let name = "Edit 750 Transactions in Everyday Savings"

        window.history.undo()
        await window.history.batchRun?.task.value
        if redo {
            window.history.batchSheetDismissed()
            #expect(window.announcements == ["Undid \(name)"])
            window.history.redo()
            await window.history.batchRun?.task.value
        }
        let before = window.announcements
        #expect(window.history.closingProgress?.isShown == true)
        #expect(window.history.batchProgress == nil)
        #expect(before.count == (redo ? 1 : 0), "Not before the sheet closes")
        window.history.batchSheetDismissed()
        #expect(window.announcements == before + [redo ? "Redid \(name)" : "Undid \(name)"])
        #expect(window.history.closingProgress == nil)
    }
}
