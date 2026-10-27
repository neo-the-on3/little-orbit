import Foundation
import LittleOrbitDomain
import LittleOrbitPersistence
import Testing

@testable import LittleOrbitFeatures

/// Tester2's N5 minor findings on #286 and D402: an Apply that changes no row writes nothing and leaves no Undo
/// step, and VoiceOver hears when Apply finishes, with its own sentence when no row changed.
@MainActor
@Suite("Bulk edit: when Apply finishes")
struct BulkEditApplyFinishTests {
    typealias F = TransactionFeatureFixture  // swiftlint:disable:this type_name

    static let rows = BulkEditBatchTests.rows(6)

    private static func model(_ repository: some LedgerRepository, heard: @escaping @MainActor (String) -> Void)
        -> BulkEditViewModel
    {
        let useCases = TransactionUseCases(repository: repository, categoryNames: CatalogDefaultCategoryNames())
        let model = BulkEditViewModel(
            loadLedger: useCases.loadLedger,
            applyBulkEdit: DefaultApplyBulkEditUseCase(repository: repository),
            transactionIDs: rows.map(\.id),
        )
        model.announce = heard
        // A clock that stands still, and no sheet timer at all: a slow parallel run mustn't show the sheet,
        // which would hold the announcement (review 5666870090).
        let instant = ContinuousClock.now
        model.progressClock = { instant }
        model.progressShowDelay = nil
        model.editsCategory = true
        model.categoryID = DefaultCategoryID.food
        return model
    }

    @Test("VoiceOver hears how many rows changed, and an Apply that changes none has nothing to undo")
    func announcesAndSkipsEmptyStep() async throws {
        let repository = try F.repository(Self.rows)
        var heard: [String] = []
        let first = try #require(await Self.model(repository) { heard.append($0) }.applyInBackground())
        #expect(!first.changesNoTransaction)
        #expect(first.transactionIDs.count == Self.rows.count)
        let again = try #require(await Self.model(repository) { heard.append($0) }.applyInBackground())
        #expect(again.changesNoTransaction, "Every row already has the category")
        #expect(heard == ["Changed 6 transactions.", "No transactions changed."])
    }

    @Test("D402: an Apply that changes no row writes nothing, leaves Undo as it was, shows nothing and says so")
    func noRowApply() async throws {
        let repository = try F.repository(Self.rows)
        let useCases = TransactionUseCases(repository: repository, categoryNames: CatalogDefaultCategoryNames())
        let updates = LedgerUpdates()
        let window = TestWindow(useCases, updates: updates)
        var heard: [String] = []
        _ = try #require(await Self.model(repository) { heard.append($0) }.applyInBackground())
        // An earlier step in this window, from the row as stored now, with the category already applied.
        var edited = try #require(try useCases.loadLedger.ledger().transactions.first { $0.id == Self.rows[0].id })
        edited.details = "Earlier edit"
        window.history.record(try useCases.saveTransactions.save([edited]))
        let undoNames = window.undoManager.undoNames
        #expect(undoNames.count == 1)
        let written = repository.revision
        let notified = updates.revision
        let ledger = try useCases.loadLedger.ledger()

        let model = Self.model(repository) { heard.append($0) }
        model.updates = updates
        let change = try #require(await model.applyInBackground())
        #expect(change.changesNoTransaction, "The sheet records no Undo step for it")
        #expect(repository.revision == written, "Nothing written")
        #expect(try useCases.loadLedger.ledger() == ledger)
        #expect(updates.revision == notified, "No ledger change posted")
        #expect(window.undoManager.undoNames == undoNames, "Undo keeps its previous item")
        #expect(model.alert == nil && model.errorMessage == nil && model.progress == nil)
        #expect(heard.last == "No transactions changed.")
        #expect(!heard.contains("Changed 0 transactions."))
    }

    @Test("The announcement: none is its own sentence; one reads in the singular; more in the plural")
    func announcementForms() {
        #expect(BulkEditText.appliedAnnouncement(count: 0) == "No transactions changed.")
        #expect(BulkEditText.appliedAnnouncement(count: 1) == "Changed 1 transaction.")
        #expect(BulkEditText.appliedAnnouncement(count: 3) == "Changed 3 transactions.")
    }
}
