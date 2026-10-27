import Foundation
import LittleOrbitDomain
import LittleOrbitPersistence
import Testing

@testable import LittleOrbitFeatures

/// D399, D404 (Tester2 on c8c6594): New Transaction can open while a batch runs, but its sheet's Save waits until
/// the batch ends, whatever the window's environment holds.
@MainActor
@Suite("Transaction form while a batch runs")
struct TransactionFormBatchWaitTests {
    typealias F = TransactionFeatureFixture  // swiftlint:disable:this type_name

    @Test("Save is off and writes nothing while a batch runs, then works")
    func saveWaits() throws {
        let repository = try F.repository()
        let updates = LedgerUpdates()
        let model = TransactionFormViewModel(
            useCases: TransactionUseCases(repository: repository, categoryNames: CatalogDefaultCategoryNames()),
            mode: .new(accountID: F.savingsID),
            locale: F.india,
            timeZone: F.zone,
            now: { F.now },
        )
        model.updates = updates
        model.press(.digit(2))
        model.press(.digit(5))
        #expect(model.canSave && !model.isWaitingForBatch)
        #expect(updates.beginBatch())
        #expect(model.isWaitingForBatch, "The sheet's Save is off")
        #expect(model.save() == nil)
        #expect(try repository.transactions().isEmpty, "Nothing written")
        updates.endBatch()
        #expect(!model.isWaitingForBatch)
        #expect(model.save() != nil)
        #expect(try repository.transactions().count == 1)
    }

    @Test("A form made by the feature shares the feature's busy flag")
    func featureWiresUpdates() throws {
        let repository = try F.repository()
        let feature = TransactionsFeature(
            useCases: TransactionUseCases(repository: repository, categoryNames: CatalogDefaultCategoryNames())
        )
        let model = feature.makeForm(.new(accountID: F.savingsID))
        #expect(feature.updates.beginBatch())
        #expect(model.isWaitingForBatch)
        feature.updates.endBatch()
    }
}
