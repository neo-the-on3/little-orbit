import Foundation
import LittleOrbitDomain
import LittleOrbitPersistence
import Testing

@testable import LittleOrbitFeatures

/// Tech Architect on 3dc318b: Apply ends as a batch Undo or Redo does (D403, D405). Saved off the main actor, the
/// sheet goes first, then the save is installed, the step recorded and its change posted, the windows' counted
/// refreshes run, the batch ends and, last, VoiceOver hears the count. Busy is held from start to end. Made-up data.
@MainActor
@Suite("Apply ends as a batch Undo or Redo does", .timeLimit(.minutes(1)))
struct ApplyEndPathTests {
    typealias F = TransactionFeatureFixture  // swiftlint:disable:this type_name

    /// What happened, in order, with what was true then.
    final class Log {
        var entries: [String] = []
    }

    @Test("Sheet gone, then install, step and refresh, then the batch's end, then the announcement")
    func endsAfterSheetAndRefresh() async throws {
        let rows = BulkEditBatchTests.rows(BatchSheetPolicy.rowsThatShowSheet)
        let memory = try F.repository(rows)
        memory.offMainSave = {}
        let updates = LedgerUpdates()
        let useCases = TransactionUseCases(repository: memory, categoryNames: CatalogDefaultCategoryNames())
        let feature = TransactionsFeature(
            useCases: useCases,
            locale: F.india,
            timeZone: F.zone,
            now: { F.now },
            updates: updates,
        )
        let register = feature.makeHistory(accountID: try #require(rows[0].accountID))
        register.appeared(in: updates)
        let builds = HeldRegisterBuilds()
        register.buildContent = builds.builder
        let loads = register.recomputes
        let window = TestWindow(useCases, updates: updates)
        let log = Log()
        let model = feature.makeBulkEdit(rows.map(\.id))
        let instant = ContinuousClock.now
        model.progressClock = { instant }
        model.progressShowDelay = nil
        model.editsCategory = true
        model.categoryID = DefaultCategoryID.food
        model.announce = { [updates] _ in
            log.entries.append("announce busy=\(updates.isBatchRunning) refreshing=\(updates.refreshesRunning)")
        }
        let revision = memory.revision

        let applying = Task {
            await model.applyInBackground { change in
                log.entries.append(
                    "record sheet=\(model.closingProgress == nil ? "gone" : "up") busy=\(updates.isBatchRunning)"
                )
                window.history.record(change)
                window.history.markBulkEdit(change)
            }
        }
        await RealTime.until(seconds: 10) { model.closingProgress != nil }
        // Saved, and the sheet asked to close: nothing installed, nothing posted, still busy.
        try #require(model.closingProgress?.isShown == true)
        #expect(model.closeRequested)
        #expect(memory.revision == revision, "Not installed while the sheet is up")
        #expect(updates.isBatchRunning)
        #expect(log.entries.isEmpty)
        #expect(register.recomputes == loads)

        model.sheetClosed()
        await RealTime.until(seconds: 10) { builds.started == 1 }
        // The counted refresh, held: the batch hasn't ended and nothing is announced yet.
        try #require(builds.started == 1, "The counted refresh")
        #expect(updates.isBatchRunning, "Busy until the refresh has finished")
        #expect(log.entries == ["record sheet=gone busy=true"])
        builds.finishAll()
        let change = try #require(await applying.value)
        #expect(change.transactionIDs.count == rows.count)
        #expect(memory.revision != revision, "Installed once the sheet had gone")
        #expect(
            log.entries == [
                "record sheet=gone busy=true",
                "announce busy=false refreshing=0",
            ]
        )
        #expect(register.recomputes == loads + 1, "The counted refresh ran before the batch ended")
        #expect(!updates.isBatchRunning)
        let batch = try #require(updates.lastBatch)
        #expect(batch.lowerBound <= batch.upperBound)
        #expect(window.undoManager.undoNames.count == 1)
    }

    @Test("Refused: the sheet stays with its fields, the batch ends, and nothing is announced")
    func refusedKeepsSheet() async throws {
        let rows = BulkEditBatchTests.rows(6)
        let memory = try F.repository(rows)
        let updates = LedgerUpdates()
        let useCases = TransactionUseCases(repository: memory, categoryNames: CatalogDefaultCategoryNames())
        let feature = TransactionsFeature(
            useCases: useCases,
            locale: F.india,
            timeZone: F.zone,
            now: { F.now },
            updates: updates,
        )
        let model = feature.makeBulkEdit(rows.map(\.id))
        model.progressShowDelay = nil
        model.editsCategory = true
        model.categoryID = DefaultCategoryID.food
        var heard: [String] = []
        model.announce = { heard.append($0) }
        try memory.deleteTransaction(id: rows[0].id)
        var recorded = 0
        #expect(await model.applyInBackground { _ in recorded += 1 } == nil)
        #expect(model.alert != nil)
        #expect(!model.closeRequested && model.closingProgress == nil && model.progress == nil)
        #expect(!updates.isBatchRunning)
        #expect(recorded == 0 && heard.isEmpty)
    }
}
