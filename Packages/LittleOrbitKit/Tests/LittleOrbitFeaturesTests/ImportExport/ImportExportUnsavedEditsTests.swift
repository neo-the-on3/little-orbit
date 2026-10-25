import Foundation
import LittleOrbitDomain
import LittleOrbitFeatures
import LittleOrbitPersistence
import Testing

/// S33: what a tapped reminder asks the CSV import and export sheets before it closes them.
@Suite("CSV import and export unsaved edits (S33)")
@MainActor
struct ImportExportUnsavedEditsTests {
    typealias F = CSVFixture  // swiftlint:disable:this type_name

    @Test("An import is unsaved from the picked file, and on the summary until Undo Import is used (D382.15)")
    func importSteps() async throws {
        let repository = try F.repository()
        let model = F.model(repository, changes: F.Changes())
        #expect(model.step == .pickFile)
        #expect(!model.hasUnsavedEdits)
        await model.open(data: try F.data("Bank Statement Debit Credit"), fileName: "Bank Statement Debit Credit.csv")
        #expect(model.step == .columns)
        #expect(model.hasUnsavedEdits)
        await model.next()
        #expect(model.step == .account)
        #expect(model.hasUnsavedEdits)
        model.targetAccountID = try F.account("Everyday Savings", in: repository).id
        await model.next()
        #expect(model.step == .review)
        #expect(model.hasUnsavedEdits)
        await model.commit()
        #expect(model.step == .summary)
        // Undo Import is offered and unused, so a tapped reminder waits (D382.15).
        #expect(model.canUndo)
        #expect(model.hasUnsavedEdits)
        model.requestUndo()
        #expect(model.hasUnsavedEdits)
        model.undo()
        #expect(model.isUndone)
        #expect(!model.hasUnsavedEdits)
    }

    @Test("An export always counts as unsaved")
    func export() throws {
        let model = CSVExportViewModel(exporting: DefaultExportTransactionsUseCase(repository: try F.repository()))
        #expect(model.hasUnsavedEdits)
        model.load()
        #expect(model.hasUnsavedEdits)
    }
}
