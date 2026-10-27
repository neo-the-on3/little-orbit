import Foundation
import LittleOrbitDomain
import LittleOrbitPersistence
import Testing

@testable import LittleOrbitFeatures

/// Tester2's N5 minor findings on #286: an Apply that changes no row leaves no Undo step, and VoiceOver hears
/// when Apply finishes.
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
        #expect(heard == ["Changed 6 transactions.", "Changed 0 transactions."])
    }

    @Test("One changed row reads in the singular")
    func singular() {
        #expect(BulkEditText.appliedAnnouncement(count: 1) == "Changed 1 transaction.")
    }
}
