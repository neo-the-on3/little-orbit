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
        let progress = BatchProgress(kind: .applying, total: 3, showAfter: nil)
        progress.announceAfterSheet("Changed 3 transactions.") { heard.texts.append($0) }
        #expect(heard.texts == ["Changed 3 transactions."])
    }

    @Test("A sheet showed: held until it has closed, then posted once")
    func heldUntilClosed() async {
        let heard = Heard()
        let progress = BatchProgress(kind: .undoing, total: 3_334, showAfter: nil)
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

    @Test("A sheet whose view went but never reports closing still gets its announcement, after a short wait")
    func fallback() async throws {
        #expect(BatchProgress.announcementFallbackDelay == .milliseconds(1_500))
        let heard = Heard()
        let sleeper = ManualSleeper()
        let progress = BatchProgress(kind: .redoing, total: 3_334, showAfter: nil)
        progress.sleep = sleeper.sleep
        let reporter = progress.start()
        progress.sheetAppeared()
        await reporter.willSave(3_334)
        progress.finish()
        progress.sheetDisappeared()
        progress.announceAfterSheet("Redid Edit") { heard.texts.append($0) }
        #expect(await sleeper.advance() == BatchProgress.uiTurnLength)
        #expect(heard.texts.isEmpty)
        #expect(await sleeper.advance() == BatchProgress.announcementFallbackDelay)
        await ManualSleeper.until { !heard.texts.isEmpty }
        #expect(heard.texts == ["Redid Edit"])
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
        // and no sheet timer at all (review 5666870090). Past 750 rows the sheet still shows before the save.
        let instant = ContinuousClock.now
        model.progressClock = { instant }
        model.progressShowDelay = nil
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

    /// The sheet's `onDismiss`, which on macOS can run as the dismissal starts (Tester2 on 8728d1f): nothing is
    /// heard, and the progress stays drawn, until the main actor's next free turn and `dismissSettle` have passed.
    private static func dismiss(_ window: TestWindow, _ sleeper: ManualSleeper, expecting text: String) async {
        let before = window.announcements
        let asked = sleeper.asked.count
        window.history.batchSheetDismissed()
        #expect(window.announcements == before, "Not as the dismissal starts")
        #expect(window.history.closingProgress?.isShown == true, "The progress stays drawn while the sheet closes")
        // The fallback's wait goes; the dismissal's turn is asked for.
        await ManualSleeper.until { sleeper.asked.count == asked + 1 && sleeper.waiting.count == 1 }
        #expect(sleeper.waiting == [BatchProgress.uiTurnLength])
        await sleeper.advance()
        #expect(await sleeper.next() == BatchProgress.dismissSettle)
        #expect(window.announcements == before, "Not before the dismissal has finished")
        await sleeper.advance()
        await ManualSleeper.until { window.announcements.count > before.count }
        #expect(window.announcements == before + [text], "Once, after the sheet has gone")
        #expect(window.history.closingProgress == nil)
    }

    /// The Undo or Redo just started: its progress waits through `sleeper`.
    private static func step(_ window: TestWindow, redo: Bool, _ sleeper: ManualSleeper) async {
        if redo {
            window.history.redo()
        } else {
            window.history.undo()
        }
        window.history.batchProgress?.sleep = sleeper.sleep
        await window.history.batchRun?.task.value
    }

    @Test(
        "Undo and Redo with the sheet: heard only after it has closed, with the save on or off the main actor",
        arguments: [true, false],
        [true, false],
    )
    func undoRedoAfterSheet(redo: Bool, offMain: Bool) async throws {
        let count = BatchSheetPolicy.rowsThatShowSheet
        let rows = (0..<count)
            .map { F.expense(Decimal($0 + 1), on: F.date(2026, 10, 1).addingTimeInterval(Double($0) * 60)) }
        let memory = try F.repository(rows)
        let disk = FullDiskLedgerRepository(memory)
        disk.hasBatchPath = true
        if offMain {
            memory.offMainSave = {}
        }
        let repository: any LedgerRepository = offMain ? memory : disk
        let useCases = TransactionUseCases(repository: repository, categoryNames: CatalogDefaultCategoryNames())
        let window = TestWindow(useCases)
        window.history.setScreen(.account(F.savingsID))
        var changes = BulkEditChanges()
        changes.details = .some("Bulk")
        let request = BulkEditRequest(
            selection: rows,
            changes: changes,
            payeeName: "",
            accounts: try repository.accounts(),
            timeZoneID: F.zoneID,
            now: F.now,
        )
        let change = try await useCases.bulkEdit.apply(request, reporting: .silent)
        window.history.record(change)
        window.history.markBulkEdit(change)
        let name = "Edit 750 Transactions in Everyday Savings"
        let sleeper = ManualSleeper()

        await Self.step(window, redo: false, sleeper)
        if redo {
            await Self.dismiss(window, sleeper, expecting: "Undid \(name)")
            await Self.step(window, redo: true, sleeper)
        }
        // The save has finished; the sheet hasn't started closing yet.
        #expect(window.history.closingProgress?.isShown == true)
        #expect(window.history.batchProgress == nil)
        #expect(window.announcements.count == (redo ? 1 : 0), "Not before the sheet closes")
        await Self.dismiss(window, sleeper, expecting: redo ? "Redid \(name)" : "Undid \(name)")
    }
}
