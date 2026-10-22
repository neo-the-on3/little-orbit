import Foundation
import LittleOrbitDomain
import LittleOrbitFeatures
import Testing

/// Tester finding 2 on 4c8b0b3 (D208.1): the export lock lasts from Export until the save panel's `onCompletion`
/// or `onCancellation`, not just while the file is written, and every fallback cleanup releases it too.
@MainActor
@Suite("Export lock lasts until the save panel closes (D208.1)", .timeLimit(.minutes(2)))
struct BackupExportPanelLockTests {
    private struct Windows {
        let harness: BackupHarness
        let backup: BackupRecord
        let model: BackupsViewModel
        let exporting: BackupsWindow
        let deleting: BackupsWindow
    }

    /// Window A has its save panel up for `backup`; window B shows the same list.
    private func panelOpen() async throws -> Windows {
        let harness = try BackupHarness()
        let backup = try await harness.service.backUpNow()
        let model = harness.viewModel()
        let exporting = BackupsWindow(model: model)
        let deleting = BackupsWindow(model: model)
        await exporting.load()
        await exporting.requestExport(backup.id)
        await exporting.export(try #require(exporting.exportPrompt))
        #expect(exporting.isExportPresented)
        return Windows(harness: harness, backup: backup, model: model, exporting: exporting, deleting: deleting)
    }

    @Test("While A's save panel is up, B's Delete is off and the service refuses it")
    func refusedWhilePanelIsUp() async throws {
        let windows = try await panelOpen()
        #expect(windows.model.isExporting(windows.backup.id))
        #expect(!windows.model.deleteEnabled(for: windows.backup.id))
        windows.deleting.requestDelete(windows.backup.id)
        #expect(windows.deleting.deletePrompt == nil)
        await #expect(throws: BackupError.exporting) {
            try await windows.harness.service.deleteBackup(id: windows.backup.id)
        }
        windows.exporting.exportCancelled()
        #expect(windows.model.deleteEnabled(for: windows.backup.id))
    }

    @Test("B's confirmation, open before A's export, shows Can’t Delete This Backup and deletes nothing")
    func openConfirmationWhilePanelIsUp() async throws {
        let harness = try BackupHarness()
        let backup = try await harness.service.backUpNow()
        let model = harness.viewModel()
        let exporting = BackupsWindow(model: model)
        let deleting = BackupsWindow(model: model)
        await deleting.load()
        deleting.requestDelete(backup.id)
        let row = try #require(deleting.deletePrompt)
        await exporting.requestExport(backup.id)
        await exporting.export(try #require(exporting.exportPrompt))

        await deleting.confirmDelete(row)
        #expect(deleting.alert == .deleteWhileExporting)
        #expect(try await harness.service.overview().backups.map(\.id) == [backup.id])
        exporting.exportCompleted(.success(URL(fileURLWithPath: "/saved")))
        #expect(try await harness.service.overview().backups.map(\.id) == [backup.id])
        #expect(model.deleteEnabled(for: backup.id))
    }

    @Test("Saved, cancelled, the next export, or the window closing: each releases the lock once")
    func everyPathReleases() async throws {
        let saved = try await panelOpen()
        saved.exporting.exportCompleted(.success(URL(fileURLWithPath: "/saved")))
        #expect(!saved.model.isExporting(saved.backup.id))

        let failed = try await panelOpen()
        failed.exporting.exportCompleted(.failure(CocoaError(.fileWriteUnknown)))
        #expect(!failed.model.isExporting(failed.backup.id))

        // The next export replaces the first: one lock, then none.
        let again = try await panelOpen()
        await again.exporting.requestExport(again.backup.id)
        await again.exporting.export(try #require(again.exporting.exportPrompt))
        #expect(again.model.isExporting(again.backup.id))
        again.exporting.exportCancelled()
        #expect(!again.model.isExporting(again.backup.id))
        // A second callback, or a later one, changes nothing.
        again.exporting.exportCancelled()
        again.exporting.finishExport()
        #expect(!again.model.isExporting(again.backup.id))
    }

    @Test("An export that fails before the file is written, as for a backup that's gone, leaves no lock")
    func failedExportReleases() async throws {
        let harness = try BackupHarness()
        let backup = try await harness.service.backUpNow()
        let missing = UUID()
        await #expect(throws: BackupError.notFound) {
            try await harness.service.exportBackup(id: missing, named: "a.littleorbit-backup")
        }
        #expect(harness.service.exportCount(of: missing) == 0)
        try await harness.service.deleteBackup(id: backup.id)
        await #expect(throws: BackupError.notFound) {
            try await harness.service.exportBackup(id: backup.id, named: "a.littleorbit-backup")
        }
        #expect(harness.service.exportCount(of: backup.id) == 0)
    }

    @Test("Closing the window with its panel up releases the lock")
    func windowCloseReleases() async throws {
        let harness = try BackupHarness()
        let backup = try await harness.service.backUpNow()
        let model = harness.viewModel()
        var exporting: BackupsWindow? = BackupsWindow(model: model)
        await exporting?.load()
        await exporting?.requestExport(backup.id)
        if let prompt = exporting?.exportPrompt {
            await exporting?.export(prompt)
        }
        #expect(model.isExporting(backup.id))
        exporting = nil
        await pollOnMainQueue { !model.isExporting(backup.id) }
        #expect(!model.isExporting(backup.id))
        try await harness.service.deleteBackup(id: backup.id)
    }
}
