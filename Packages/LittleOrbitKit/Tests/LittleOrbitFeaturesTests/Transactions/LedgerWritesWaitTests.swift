import Foundation
import LittleOrbitDomain
import LittleOrbitPersistence
import Testing

@testable import LittleOrbitFeatures

/// D399: while a Bulk Edit, or its Undo or Redo, runs in any window, Import and Restore wait, with no extra alert.
/// Reading stays allowed: an open import sheet keeps its choices, and Back Up Now and Export… stay on.
@MainActor
@Suite("Ledger writes wait for a batch (D399)", .timeLimit(.minutes(2)))
struct LedgerWritesWaitTests {
    /// The import sheet's model on Review, with rows ready, as the App builds it over `updates`.
    static func reviewing(_ scene: ScheduledScene) async throws -> (ImportExportFeature, CSVImportViewModel) {
        let feature = ImportExportFeature(
            useCases: ImportExportUseCases(
                importing: ImportUseCases(repository: scene.repository),
                exporting: DefaultExportTransactionsUseCase(repository: scene.repository),
                defaultCurrency: "INR",
            ),
            updates: scene.updates,
        )
        let model = feature.makeImport()
        await model.open(data: try CSVFixture.data("Bank Statement Debit Credit"), fileName: "statement.csv")
        await model.next()
        if model.needsTargetAccount {
            model.targetAccountID = scene.account.id
        }
        while model.step != .review, model.canGoNext {
            await model.next()
        }
        try #require(model.canImport)
        return (feature, model)
    }

    @Test("Import… and the sheet's Import wait while a batch runs; the sheet keeps its choices")
    func importWaits() async throws {
        let scene = try ScheduledScene()
        let (feature, model) = try await Self.reviewing(scene)
        let before = try scene.repository.transactions()
        #expect(feature.importEnabled)
        #expect(scene.updates.beginBatch())
        #expect(!feature.importEnabled)
        #expect(!model.canImport)
        await model.commit()
        #expect(model.step == .review, "Nothing imported; still on Review")
        #expect(try scene.repository.transactions() == before)
        #expect(model.alert == nil, "No extra alert")
        scene.updates.endBatch()
        #expect(feature.importEnabled)
        #expect(model.canImport)
    }

    @Test("Undo Import waits while a batch runs, then works")
    func undoImportWaits() async throws {
        let scene = try ScheduledScene()
        let (_, model) = try await Self.reviewing(scene)
        await model.commit()
        try #require(model.step == .summary)
        await model.dataChanged()
        try #require(model.canUndo)
        #expect(scene.updates.beginBatch())
        #expect(model.isWaitingForBatch)
        model.requestUndo()
        #expect(!model.isConfirmingUndo)
        model.undo()
        #expect(!model.isUndone)
        scene.updates.endBatch()
        #expect(!model.isWaitingForBatch)
        #expect(model.canUndo)
        model.undo()
        #expect(model.isUndone)
    }

    @Test("Restore… and Restore from File… wait while a batch runs; Back Up Now stays on")
    func restoreWaits() async throws {
        let harness = try BackupHarness()
        let updates = LedgerUpdates()
        let window = BackupsWindow(model: harness.viewModel(), ledgerUpdates: updates)
        await window.backUpNow()
        let id = try #require(window.model.rows.first?.id)
        #expect(window.restoreEnabled)
        #expect(updates.beginBatch())
        #expect(!window.restoreEnabled)
        #expect(window.model.actionsEnabled, "Back Up Now, Export… and Delete… don't wait")
        await window.requestRestore(id)
        #expect(window.restorePrompt == nil)
        await window.restoreFromFile(.data(Data("Shopping list".utf8)))
        #expect(window.alert == nil, "No extra alert, and the file isn't read")
        updates.endBatch()
        await window.requestRestore(id)
        #expect(window.restorePrompt != nil)
    }

    @Test("A restore warning confirmed while a batch runs restores nothing")
    func confirmWaits() async throws {
        let harness = try BackupHarness()
        let updates = LedgerUpdates()
        let window = BackupsWindow(model: harness.viewModel(), ledgerUpdates: updates)
        await window.backUpNow()
        let id = try #require(window.model.rows.first?.id)
        await window.requestRestore(id)
        let prompt = try #require(window.restorePrompt)
        var replaced = false
        harness.changes.onReplacement { replaced = true }
        #expect(updates.beginBatch())
        await window.confirmRestore(prompt)
        updates.endBatch()
        #expect(!replaced)
        #expect(window.toast == nil)
        #expect(window.restoredMessage == nil)
    }
}
