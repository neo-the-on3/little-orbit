import Foundation
import LittleOrbitDomain
import LittleOrbitPersistence
import Testing

@testable import LittleOrbitFeatures

/// D108, D381.4: the next change to data after an import ends Undo Import, whether it's a watch Pay or Skip the
/// iPhone records or an edit in another window. The import's own change and settings changes don't. The sheet
/// calls `dataChanged()` when the shared store-change signal moves; the tests call it the same way. Made-up data.
@MainActor
@Suite("Undo Import ends with the next change to data (D108, D381.4)")
struct CSVImportUndoWindowTests {
    let scene: ScheduledScene
    let pair = WatchPhoneFeatureTests.Pair()
    let inbox = InMemoryWatchRequestInboxStore()

    init() throws {
        scene = try ScheduledScene()
    }

    /// The import sheet's model as the App builds it, over the scene's store and store-change signal.
    func importModel() -> CSVImportViewModel {
        let feature = ImportExportFeature(
            useCases: ImportExportUseCases(
                importing: ImportUseCases(repository: scene.repository),
                exporting: DefaultExportTransactionsUseCase(repository: scene.repository),
                defaultCurrency: "INR",
            ),
            updates: scene.updates,
        )
        return feature.makeImport()
    }

    /// The bank statement imported into Everyday Savings, on the summary with Undo Import offered, after the
    /// sheet's call for the import's own change.
    func imported(_ fixture: String = "Bank Statement Debit Credit") async throws -> CSVImportViewModel {
        let model = importModel()
        await model.open(data: try CSVFixture.data(fixture), fileName: "statement.csv")
        await model.next()
        if model.needsTargetAccount {
            model.targetAccountID = scene.account.id
        }
        while model.step != .review, model.canGoNext {
            await model.next()
        }
        await model.commit()
        try #require(model.step == .summary)
        await model.dataChanged()
        try #require(model.canUndo)
        return model
    }

    /// The watch app and the iPhone side that records its requests, and the StreamBox row.
    @MainActor
    struct PairedWatch {
        let phone: WatchPhoneFeature
        let watch: WatchScheduledViewModel
        let rowID: UUID

        func pay() { watch.pay(rowID) }
        func skip() { watch.skip(rowID) }
    }

    /// The paired watch, showing “StreamBox” ₹1,200 due today, 20 Oct, with the iPhone side running.
    func pairedWatch() throws -> PairedWatch {
        try scene.add(scene.item("StreamBox", day: 20, month: 10))
        let useCases = DefaultWatchPhoneUseCases(
            repository: scene.repository,
            inbox: inbox,
            today: { [scene] in
                TransactionTiming.today(scene.now, timeZone: TimeZone(identifier: ScheduledScene.zone)!)
            },
        )
        let phone = WatchPhoneFeature(snapshots: useCases, requests: useCases, link: pair, updates: scene.updates)
        phone.start()
        let watch = WatchScheduledViewModel(
            useCases: DefaultWatchScheduledUseCases(
                link: pair,
                cache: InMemoryWatchScheduledCache(),
                today: { CalendarDay(year: 2026, month: 10, day: 20) },
            ),
            locale: Locale(identifier: "en_IN"),
        )
        let row = try #require(watch.rows.first { $0.title == "StreamBox" })
        return PairedWatch(phone: phone, watch: watch, rowID: row.id)
    }

    var importedCount: Int {
        (try? scene.repository.transactions().filter { $0.scheduledTemplateID == nil }.count) ?? 0
    }

    @Test("A watch Pay the iPhone records ends Undo Import; the imported rows and the payment stay")
    func watchPay() async throws {
        let paired = try pairedWatch()
        let model = try await imported()
        let rows = importedCount
        paired.pay()
        #expect(scene.recorded.count == 1)
        await model.dataChanged()
        #expect(!model.canUndo)
        #expect(model.isUndoWindowOver)
        model.requestUndo()
        model.undo()
        #expect(!model.isConfirmingUndo && !model.isUndone)
        #expect(importedCount == rows && scene.recorded.count == 1)
    }

    @Test("D382.15: the summary keeps a tapped reminder waiting only until Undo Import ends")
    func summaryCleanOnceUndoEnds() async throws {
        let paired = try pairedWatch()
        let model = try await imported()
        #expect(model.hasUnsavedEdits)
        paired.pay()
        await model.dataChanged()
        #expect(model.isUndoWindowOver)
        #expect(!model.hasUnsavedEdits)
    }

    @Test("A watch Skip ends Undo Import, though it changes only the scheduled item")
    func watchSkip() async throws {
        let paired = try pairedWatch()
        let model = try await imported()
        let before = try scene.repository.transactions()
        let revision = scene.updates.revision
        paired.skip()
        // The iPhone applied it, so StreamBox is next due 20 Nov, but no transaction changed.
        #expect(paired.watch.rows.first?.occurrence.day == CalendarDay(year: 2026, month: 11, day: 20))
        #expect(try scene.repository.transactions() == before)
        #expect(scene.updates.revision > revision)
        await model.dataChanged()
        #expect(!model.canUndo)
    }

    @Test("A payee renamed in another window ends Undo Import, and closes an open confirmation")
    func editInAnotherWindow() async throws {
        let bakery = Payee(name: "Corner Bakery")
        try scene.repository.savePayee(bakery)
        let model = try await imported()
        model.requestUndo()
        #expect(model.isConfirmingUndo)
        let payees = PayeesFeature(
            useCases: PayeeScreenUseCases(
                load: DefaultLoadPayeesUseCase(repository: scene.repository),
                manage: CategoryUseCases(repository: scene.repository).managePayees,
            ),
            updates: scene.updates,
        )
        .makeScreen()
        payees.load()
        let editor = try #require(payees.makeEditor(for: bakery.id))
        editor.name = "Corner Bakery & Café"
        #expect(editor.save())
        await model.dataChanged()
        #expect(!model.canUndo)
        #expect(!model.isConfirmingUndo)
    }

    /// Renames a payee through the Payees screen, as an edit in another window does.
    func rename(_ id: UUID, to name: String) throws {
        let payees = PayeesFeature(
            useCases: PayeeScreenUseCases(
                load: DefaultLoadPayeesUseCase(repository: scene.repository),
                manage: CategoryUseCases(repository: scene.repository).managePayees,
            ),
            updates: scene.updates,
        )
        .makeScreen()
        payees.load()
        let editor = try #require(payees.makeEditor(for: id))
        editor.name = name
        try #require(editor.save())
    }

    @Test("A watch Skip just before Undo Import is refused, before the sheet hears the change (N1)")
    func watchSkipThenUndo() async throws {
        let paired = try pairedWatch()
        let model = try await imported()
        let rows = importedCount
        paired.skip()
        model.undo()
        #expect(!model.isUndone && model.isUndoWindowOver && !model.canUndo)
        #expect(!model.isConfirmingUndo && model.alert == nil)
        #expect(importedCount == rows)
    }

    @Test("A watch Skip just before Undo Import is chosen doesn't show the confirmation (N1)")
    func watchSkipThenRequestUndo() async throws {
        let paired = try pairedWatch()
        let model = try await imported()
        paired.skip()
        model.requestUndo()
        #expect(!model.isConfirmingUndo && model.isUndoWindowOver)
        model.undo()
        #expect(!model.isUndone && importedCount > 0)
    }

    @Test("Renaming a payee the import created, then Undo Import at once, undoes nothing (N1)")
    func createdPayeeRenameThenUndo() async throws {
        // The app's own export has a Payee column, so this import adds payees.
        let model = try await imported("Little Orbit Export")
        let created = try #require(model.receipt?.createdPayees.first)
        let rows = importedCount
        model.requestUndo()
        #expect(model.isConfirmingUndo)
        try rename(created.id, to: "Renamed Payee")
        model.undo()
        #expect(!model.isUndone && !model.isConfirmingUndo && model.alert == nil)
        #expect(importedCount == rows)
        #expect(try scene.repository.payees().first { $0.id == created.id }?.name == "Renamed Payee")
        model.requestUndo()
        #expect(!model.isConfirmingUndo)
    }

    @Test("The import's own change doesn't end Undo Import, however often the sheet hears it; the next one does")
    func ownChangeKeepsUndo() async throws {
        let paired = try pairedWatch()
        let model = try await imported()
        await model.dataChanged()
        await model.dataChanged()
        #expect(model.canUndo)
        paired.pay()
        await model.dataChanged()
        #expect(!model.canUndo)
    }

    @Test("Undo Import still works after its own change, and its own change leaves the summary as Import Undone")
    func undoPathKeepsUndo() async throws {
        let model = try await imported()
        let revision = scene.updates.revision
        model.requestUndo()
        #expect(model.isConfirmingUndo)
        model.undo()
        #expect(model.isUndone && model.alert == nil)
        #expect(scene.updates.revision == revision + 1)
        #expect(importedCount == 0)
        await model.dataChanged()
        #expect(model.isUndone && !model.isUndoWindowOver)
        #expect(model.summaryTitle == "Import Undone")
    }

    @Test("A settings change doesn't end Undo Import, even if the sheet is asked again; a data change then does")
    func settingsKeepUndo() async throws {
        let paired = try pairedWatch()
        let model = try await imported()
        let revision = scene.updates.revision
        // Backup retention is an app setting: saving it doesn't move the store-change signal.
        let settings = MemoryBackupSettings()
        settings.setRetention(BackupRetention(recentAutomatic: 3, monthlyMonths: 0))
        #expect(scene.updates.revision == revision)
        await model.dataChanged()
        #expect(model.canUndo)
        paired.pay()
        await model.dataChanged()
        #expect(!model.canUndo)
    }

    @Test("VoiceOver focus on Undo Import moves to the summary's title when the window ends (V1)")
    func focusOnUndoMoves() async throws {
        let paired = try pairedWatch()
        let model = try await imported()
        model.isUndoFocused = true
        paired.pay()
        #expect(!model.movesFocusToSummaryTitle)
        await model.dataChanged()
        #expect(model.isUndoWindowOver && model.movesFocusToSummaryTitle)
    }

    @Test("An open confirmation moves VoiceOver focus to the summary's title when the window ends (V1)")
    func openConfirmationMoves() async throws {
        let paired = try pairedWatch()
        let model = try await imported()
        model.requestUndo()
        // VoiceOver focus is in the confirmation, not on the button.
        model.isUndoFocused = false
        paired.skip()
        await model.dataChanged()
        #expect(!model.isConfirmingUndo && model.movesFocusToSummaryTitle)
    }

    @Test("An open confirmation still moves focus when Undo is chosen in the same step as the change (V1, N1)")
    func openConfirmationSameStepMoves() async throws {
        let paired = try pairedWatch()
        let model = try await imported()
        model.requestUndo()
        paired.skip()
        model.undo()
        #expect(!model.isUndone && !model.isConfirmingUndo && model.movesFocusToSummaryTitle)
    }

    @Test("With VoiceOver focus elsewhere and no confirmation, focus stays put when the window ends (V1)")
    func focusElsewhereStays() async throws {
        let paired = try pairedWatch()
        let model = try await imported()
        model.isUndoFocused = true
        model.isUndoFocused = false
        paired.pay()
        await model.dataChanged()
        #expect(model.isUndoWindowOver && !model.canUndo)
        #expect(!model.movesFocusToSummaryTitle)
    }

    @Test("A successful Undo Import doesn't move VoiceOver focus, even from the confirmation (V1)")
    func undoDoesNotMoveFocus() async throws {
        let model = try await imported()
        model.isUndoFocused = true
        model.requestUndo()
        model.undo()
        await model.dataChanged()
        #expect(model.isUndone && !model.movesFocusToSummaryTitle)
    }
}
