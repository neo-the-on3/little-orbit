import Foundation
import LittleOrbitDomain
import LittleOrbitPersistence
import Testing

@testable import LittleOrbitFeatures

/// #285: a write that lands while a Bulk Edit, or its Undo, is being built moves the store's revision, so the
/// commit checks again against the ledger as it is then (Tech Architect NB2 on 5663375395). If the edit no longer
/// fits, it's all or nothing: “Couldn’t Apply Changes” with the selection kept (D399).
@MainActor
@Suite("Bulk edit: a write lands mid-build")
struct BulkEditStaleBatchTests {
    typealias F = TransactionFeatureFixture  // swiftlint:disable:this type_name

    static let rows = BulkEditBatchTests.rows(6)

    static func newRow() -> Transaction {
        F.expense(77, on: F.date(2026, 10, 20), details: "Imported meanwhile")
    }

    @Test("An import mid-build: the commit builds again on the new ledger and applies, as a fresh Apply would")
    func importMeanwhile() async throws {
        let repository = try F.repository(Self.rows)
        let fresh = try F.repository(Self.rows)
        let added = Self.newRow()
        let request = BulkEditBatchTests.request(Self.rows, accounts: try repository.accounts())
        let reporter = LedgerBatchReporter(willSave: { _ in try? repository.saveNewTransactions([added]) })
        let change = try await DefaultApplyBulkEditUseCase(repository: repository).apply(request, reporting: reporter)
        try fresh.saveNewTransactions([added])
        #expect(change == (try DefaultApplyBulkEditUseCase(repository: fresh).apply(request)))
        #expect(try repository.transactions() == fresh.transactions())
        #expect(try repository.transactions().first { $0.id == added.id }?.categoryID == nil, "Only the selection")
    }

    @Test("A restore mid-build without a selected row: the commit checks again and writes nothing (D393)")
    func restoreMeanwhile() async throws {
        let repository = try F.repository(Self.rows)
        let restored = try F.repository(Array(Self.rows.dropFirst())).batchBase().snapshot
        let request = BulkEditBatchTests.request(Self.rows, accounts: try repository.accounts())
        let reporter = LedgerBatchReporter(willSave: { _ in try? repository.replaceLedger(with: restored) })
        await #expect(throws: BulkEditSelectionDeleted(ids: [Self.rows[0].id])) {
            try await DefaultApplyBulkEditUseCase(repository: repository).apply(request, reporting: reporter)
        }
        #expect(try repository.transactions().allSatisfy { $0.categoryID == nil })
    }

    @Test("The edit no longer fits the changed data: nothing is written, and it says the data changed (D399)")
    func noLongerFits() async throws {
        let repository = try F.repository(Self.rows)
        let deletedOnly = try F.repository(Self.rows)
        try deletedOnly.deleteCategory(id: DefaultCategoryID.food, reassigningTo: nil)
        let request = BulkEditBatchTests.request(Self.rows, accounts: try repository.accounts())
        let reporter = LedgerBatchReporter(willSave: { _ in
            try? repository.deleteCategory(id: DefaultCategoryID.food, reassigningTo: nil)
        })
        await #expect(throws: BulkEditDataChanged()) {
            try await DefaultApplyBulkEditUseCase(repository: repository).apply(request, reporting: reporter)
        }
        #expect(try repository.transactions() == deletedOnly.transactions(), "Only the delete wrote")
        #expect(try repository.transactions().allSatisfy { $0.categoryID == nil })
    }

    @Test("Undo with an import mid-build: it checks the step again, still reverts, and keeps the import")
    func undoImportMeanwhile() async throws {
        let repository = try F.repository(Self.rows)
        let useCases = TransactionUseCases(repository: repository, categoryNames: CatalogDefaultCategoryNames())
        let request = BulkEditBatchTests.request(Self.rows, accounts: try repository.accounts())
        let change = try useCases.bulkEdit.apply(request)
        let outcome = try useCases.changes.outcome(of: change)
        let added = Self.newRow()
        let reporter = LedgerBatchReporter(willSave: { _ in try? repository.saveNewTransactions([added]) })
        let result = try await useCases.changes.revert(change, expecting: outcome, reporting: reporter)
        guard case .reverted = result else {
            Issue.record("Expected the Undo to revert, got \(result)")
            return
        }
        let stored = try repository.transactions()
        #expect(stored.filter { $0.id != added.id }.allSatisfy { $0.categoryID == nil })
        #expect(stored.contains { $0.id == added.id })
    }

    @Test("Undo with a restore mid-build that changed an edited field: the step is stale and nothing is written")
    func undoRestoreMeanwhile() async throws {
        let repository = try F.repository(Self.rows)
        let useCases = TransactionUseCases(repository: repository, categoryNames: CatalogDefaultCategoryNames())
        let request = BulkEditBatchTests.request(Self.rows, accounts: try repository.accounts())
        let change = try useCases.bulkEdit.apply(request)
        let outcome = try useCases.changes.outcome(of: change)
        var restored = try repository.batchBase().snapshot
        let index = try #require(restored.transactions.firstIndex { $0.id == Self.rows[2].id })
        restored.transactions[index].categoryID = nil
        let reporter = LedgerBatchReporter(willSave: { _ in try? repository.replaceLedger(with: restored) })
        let result = try await useCases.changes.revert(change, expecting: outcome, reporting: reporter)
        guard case .stale = result else {
            Issue.record("Expected a stale step, got \(result)")
            return
        }
        #expect(try repository.transactions() == restored.transactions, "Only the restore wrote")
    }

    @Test("The sheet: “Couldn’t Apply Changes”, the D399 message, one OK, and the selection stays")
    func sheetAlert() async throws {
        let repository = try F.repository(Self.rows)
        let useCases = TransactionUseCases(repository: repository, categoryNames: CatalogDefaultCategoryNames())
        let model = BulkEditViewModel(
            loadLedger: useCases.loadLedger,
            applyBulkEdit: DataChangedBulkEdit(),
            transactionIDs: Self.rows.map(\.id),
        )
        model.editsCategory = true
        model.categoryID = DefaultCategoryID.food
        // No sheet: its timer mustn't fire on a slow run (review 5666870090).
        model.progressShowDelay = nil
        let title = model.title
        #expect(await model.applyInBackground() == nil)
        #expect(model.alert?.title == "Couldn’t Apply Changes")
        #expect(model.alert?.message == "Your data changed while the changes were being applied. Nothing was changed.")
        #expect(model.isAlertPresented)
        model.acknowledgeAlert()
        #expect(!model.isAlertPresented)
        #expect(!model.closeRequested)
        #expect(model.title == title, "The selection is kept")
        #expect(model.editsCategory && model.categoryID == DefaultCategoryID.food)
        #expect(model.errorMessage == nil)
    }
}

/// An Apply whose commit found the data changed under it (D399).
@MainActor
private struct DataChangedBulkEdit: ApplyBulkEditUseCase {
    func apply(_: BulkEditRequest) throws -> TransactionChange {
        throw BulkEditDataChanged()
    }

    func apply(_: BulkEditRequest, reporting _: LedgerBatchReporter) async throws -> TransactionChange {
        throw BulkEditDataChanged()
    }
}
