import Foundation
import LittleOrbitDomain
import LittleOrbitFeatures
import LittleOrbitPersistence
import Testing

@MainActor
@Suite("Transaction form: saving without changes")
struct TransactionFormSaveTests {
    typealias F = TransactionFeatureFixture  // swiftlint:disable:this type_name

    private func model(_ repository: InMemoryLedgerRepository, mode: TransactionFormMode) -> TransactionFormViewModel {
        TransactionFormViewModel(
            useCases: TransactionUseCases(repository: repository, categoryNames: CatalogDefaultCategoryNames()),
            mode: mode,
            locale: F.india,
            timeZone: F.zone,
            now: { F.now },
        )
    }

    @Test("B4: Save on an edit with no changes writes nothing, records no step and keeps Redo")
    func unchangedSave() throws {
        let kept = F.expense(250, on: F.date(2026, 10, 19), category: DefaultCategoryID.food)
        let other = F.expense(400, on: F.date(2026, 10, 18))
        let repository = try F.repository([kept, other])
        let window = TestWindow(
            TransactionUseCases(repository: repository, categoryNames: CatalogDefaultCategoryNames())
        )
        window.history.record(
            try TransactionUseCases(repository: repository, categoryNames: CatalogDefaultCategoryNames()).changes
                .remove(ids: [other.id])
        )
        window.history.undo()
        #expect(window.undoManager.redoNames.count == 1)
        let before = try repository.transactions()

        let model = model(repository, mode: .edit(kept.id))
        #expect(model.isUnchanged)
        #expect(model.save() == nil)
        #expect(model.errorMessage == nil)
        #expect(try repository.transactions() == before, "Nothing written")
        #expect(window.undoManager.redoNames.count == 1, "Redo isn't cleared")
        #expect(window.history.canRedo)
        #expect(!window.history.canUndo)

        model.note = "Lunch"
        #expect(!model.isUnchanged, "Any change is saved as usual")
    }
}
