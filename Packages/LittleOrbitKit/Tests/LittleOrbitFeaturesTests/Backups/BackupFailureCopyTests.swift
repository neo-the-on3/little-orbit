import Foundation
import LittleOrbitDomain
import LittleOrbitPersistence
import Testing

@testable import LittleOrbitFeatures

#if canImport(SwiftUI)
    import SwiftUI
#endif

/// D211: every backup failure shows catalog copy, never an error's own description (Tech Architect, Product
/// Manager): a full disk while restoring, a failed export, a failed Keep cleanup, and the catch-all.
@MainActor
@Suite("Backup failures show catalog copy, never an error's own text (D211)", .timeLimit(.minutes(2)))
struct BackupFailureCopyTests {
    private let folder: URL

    init() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("d211-\(UUID().uuidString)")
    }

    private func cleanUp() {
        try? FileManager.default.removeItem(at: folder)
        try? FileManager.default.removeItem(at: URL(fileURLWithPath: folder.path + ".staging"))
    }

    /// `count` automatic backups a day apart, each of changed data, so each one is made.
    private func automaticBackups(_ count: Int, _ harness: BackupHarness) async throws {
        for index in 0..<count {
            try harness.repository.saveAccount(
                Account(
                    name: "Day \(index)",
                    type: .cash,
                    currencyCode: "INR",
                    openingBalance: 1,
                    sortOrder: Double(50 + index),
                )
            )
            harness.advance(86_400)
            _ = try #require(try await harness.service.backUpAutomaticallyIfNeeded())
        }
    }

    private func confirmRestore(_ window: BackupsWindow) async throws {
        let prompt = try #require(window.restorePrompt)
        window.restorePrompt = nil
        await window.confirmRestore(prompt)
        #expect(window.alert == nil)
        window.showAndCloseRestoreProgress()
    }

    /// A system error whose own text names the store's files, as the real ones do.
    private static let secret = NSError(
        domain: NSCocoaErrorDomain,
        code: CocoaError.fileWriteNoPermission.rawValue,
        userInfo: [NSLocalizedDescriptionKey: "SECRET “F366FE74.tmp” in the folder “Backups.staging”"],
    )

    /// The sentinel: nothing the window shows has an error's own text.
    private func expectNoRawText(_ window: BackupsWindow) {
        let shown = [window.alert?.title, window.alert?.message, window.errorMessage].compactMap(\.self).joined()
        #expect(!shown.contains("SECRET"))
        #expect(!shown.contains(Self.secret.localizedDescription))
        #expect(!shown.contains(".tmp"))
    }

    // MARK: 1. Couldn’t Restore, after the Before restore backup

    @Test("The replace failing after the Before restore backup: Couldn’t Restore with D211.1's message")
    func replaceFails() async throws {
        defer { cleanUp() }
        let harness = try BackupHarness(source: { FailingReplaceSource($0, error: Self.secret) })
        let window = harness.window()
        await window.backUpNow()
        let ledger = try harness.repository.ledgerSnapshot()
        await window.requestRestore(try #require(window.model.rows.first?.id))
        try await confirmRestore(window)
        #expect(window.alert == .restoreFailed)
        #expect(window.alert?.title == "Couldn’t Restore")
        #expect(
            window.alert?.message
                == "little-orbit couldn’t finish restoring this backup, so nothing was replaced. Your data hasn’t changed, and the Before restore backup made just now is in your list."
        )
        #expect(window.alert != .beforeRestoreFailed)
        #expect(window.errorMessage == nil)
        expectNoRawText(window)
        #expect(try harness.repository.ledgerSnapshot() == ledger)
        #expect(window.model.rows.map(\.kindText) == ["Before restore", "Manual"])
    }

    // MARK: 2. Couldn’t Back Up

    @Test("Back Up Now failing other than a full disk: Couldn’t Back Up, and no N4 line")
    func backUpFails() async throws {
        defer { cleanUp() }
        let storage = try ScriptedStorage(folder: folder)
        let harness = try BackupHarness(storage: storage)
        let window = harness.window()
        storage.writeError = Self.secret
        await window.backUpNow()
        #expect(window.alert == .backUpFailed)
        #expect(window.alert?.title == "Couldn’t Back Up")
        #expect(
            window.alert?.message
                == "little-orbit couldn’t make a backup right now. Your data hasn’t changed. Try again later."
        )
        #expect(window.errorMessage == nil)
        #expect(window.model.failureMessage == nil)
        expectNoRawText(window)
    }

    // MARK: 3. Couldn’t Delete This Backup

    @Test("A folder that can't be removed: Couldn’t Delete This Backup, and the backup stays")
    func deleteFails() async throws {
        defer { cleanUp() }
        let storage = try ScriptedStorage(folder: folder)
        let harness = try BackupHarness(storage: storage)
        let window = harness.window()
        await window.backUpNow()
        let id = try #require(window.model.rows.first?.id)
        window.requestDelete(id)
        storage.deleteError = Self.secret
        await window.confirmDelete(try #require(window.deletePrompt))
        #expect(window.alert == .deleteFailed)
        #expect(window.alert?.title == "Couldn’t Delete This Backup")
        #expect(window.alert?.message == "little-orbit couldn’t remove this backup. Try again later.")
        #expect(window.alert != .deleteWhileExporting)
        #expect(window.errorMessage == nil)
        expectNoRawText(window)
        #expect(window.model.rows.map(\.id) == [id])
    }

    // MARK: 5. Couldn’t Load Backups, in the list

    @Test("The Backups folder can't be read: Couldn’t Load Backups in the list, no alert, and Try Again reloads")
    func loadFails() async throws {
        defer { cleanUp() }
        let storage = try ScriptedStorage(folder: folder)
        let harness = try BackupHarness(storage: storage)
        let window = harness.window()
        await window.backUpNow()
        storage.listError = Self.secret
        await window.load()
        #expect(window.model.isLoadFailed)
        #expect(window.alert == nil)
        #expect(window.errorMessage == nil)
        #expect(BackupPresentation.loadFailedTitle == "Couldn’t Load Backups")
        #expect(
            BackupPresentation.loadFailedMessage
                == "little-orbit couldn’t read your backups folder. Your backups and data haven’t changed. Try again later."
        )
        #expect(BackupPresentation.tryAgain == "Try Again")
        expectNoRawText(window)

        storage.listError = nil
        await window.load()
        #expect(!window.model.isLoadFailed)
        #expect(window.model.rows.count == 1)
    }

    // MARK: 7. Not Enough Storage to Restore

    @Test("A full disk while making the Before restore backup: Not Enough Storage to Restore, and no N4 line")
    func fullDiskRestoreStored() async throws {
        defer { cleanUp() }
        let storage = try ScriptedStorage(folder: folder)
        let harness = try BackupHarness(storage: storage)
        let window = harness.window()
        await window.backUpNow()
        let ledger = try harness.repository.ledgerSnapshot()
        await window.requestRestore(try #require(window.model.rows.first?.id))
        storage.diskFull = true
        try await confirmRestore(window)
        #expect(window.alert == .notEnoughStorageToRestore)
        #expect(window.alert?.title == "Not Enough Storage to Restore")
        #expect(
            window.alert?.message
                == "little-orbit needs space to save a copy of your current data before restoring, so nothing was replaced. Free up some storage and try again. Your data hasn’t changed."
        )
        #expect(window.errorMessage == nil)
        #expect(try harness.repository.ledgerSnapshot() == ledger)
        #expect(harness.changes.replacements == 0)
        // N4 is Back Up Now's only (D62): a restore's full disk neither sets nor shows it.
        #expect(window.model.failureMessage == nil)
        #expect(try await harness.service.overview().lastFailure == nil)
    }

    @Test("A full disk while making the Before restore backup, Restore from File: the same alert")
    func fullDiskRestoreFile() async throws {
        defer { cleanUp() }
        let source = try BackupHarness()
        let exported = try await source.service.backUpNow()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
            "\(UUID().uuidString).littleorbit-backup"
        )
        defer { try? FileManager.default.removeItem(at: url) }
        try await source.exportData(exported.id).write(to: url)
        let storage = try ScriptedStorage(folder: folder)
        let harness = try BackupHarness(storage: storage)
        let window = harness.window()
        await window.load()
        await window.restoreFromFile(.file(url))
        storage.diskFull = true
        try await confirmRestore(window)
        #expect(window.alert == .notEnoughStorageToRestore)
        #expect(window.model.failureMessage == nil)
        #expect(harness.changes.replacements == 0)
    }

    @Test("A full disk on Back Up Now still shows the N4 line and no alert (D62)")
    func fullDiskBackUpNowKeepsN4() async throws {
        defer { cleanUp() }
        let storage = try ScriptedStorage(folder: folder)
        let harness = try BackupHarness(storage: storage)
        let window = harness.window()
        storage.diskFull = true
        await window.backUpNow()
        #expect(window.alert == nil)
        #expect(window.errorMessage == nil)
        #expect(window.model.failureMessage != nil)
    }

    @Test("The full-disk restore alert stays in the window the restore started in, for the screen on top after a pop")
    func fullDiskRestoreAfterPop() async throws {
        defer { cleanUp() }
        let storage = try ScriptedStorage(folder: folder)
        let harness = try BackupHarness(storage: storage)
        let window = harness.window()
        let other = BackupsWindow(model: window.model)
        await window.backUpNow()
        await window.requestRestore(try #require(window.model.rows.first?.id))
        storage.diskFull = true
        try await confirmRestore(window)
        #expect(window.alert == .notEnoughStorageToRestore)
        #expect(other.alert == nil)
        #expect(other.errorMessage == nil)
        #if canImport(SwiftUI)
            // On iPhone the restore was confirmed on the backup detail, over the list.
            let detail = BackupFlowModifier.presented(window, \BackupsWindow.alert, isActive: true)
            let list = BackupFlowModifier.presented(window, \BackupsWindow.alert, isActive: false)
            #expect(detail.wrappedValue)
            #expect(!list.wrappedValue)
            // Popped back to the list: the detail is gone, and its binding going false clears nothing it no longer
            // owns; the list, now on top, presents the same alert.
            let behind = BackupFlowModifier.presented(window, \BackupsWindow.alert, isActive: false)
            behind.wrappedValue = false
            let listOnTop = BackupFlowModifier.presented(window, \BackupsWindow.alert, isActive: true)
            #expect(listOnTop.wrappedValue)
            #expect(window.alert == .notEnoughStorageToRestore)
            #expect(!BackupFlowModifier.presented(other, \BackupsWindow.alert, isActive: true).wrappedValue)
            listOnTop.wrappedValue = false
            #expect(window.alert == nil)
        #endif
    }

    // MARK: 4. Couldn’t Export Backup

    @Test("A full disk while staging an export: Couldn’t Export Backup, and the export's lock is released")
    func exportFullDisk() async throws {
        defer { cleanUp() }
        let storage = try ScriptedStorage(folder: folder)
        let harness = try BackupHarness(storage: storage)
        let window = harness.window()
        await window.backUpNow()
        let id = try #require(window.model.rows.first?.id)
        await window.requestExport(id)
        storage.exportFolderError = BackupError.notEnoughStorage
        await window.export(try #require(window.exportPrompt))
        #expect(window.alert == .exportFailed)
        #expect(window.alert?.title == "Couldn’t Export Backup")
        #expect(
            window.alert?.message
                == "little-orbit couldn’t create the export file. Make sure there’s enough storage on this device and try again. Your backup hasn’t changed."
        )
        #expect(window.errorMessage == nil)
        #expect(window.pendingExport == nil)
        #expect(harness.service.exportCount(of: id) == 0)
    }

    @Test("A write error while writing the export file, even a POSIX one, is Couldn’t Export Backup, not a read error")
    func exportWriteError() async throws {
        defer { cleanUp() }
        let harness = try BackupHarness(archiving: FailingExportArchiving(failure: POSIXError(.ENOSPC)))
        let window = harness.window()
        await window.backUpNow()
        let id = try #require(window.model.rows.first?.id)
        await window.requestExport(id)
        await window.export(try #require(window.exportPrompt))
        #expect(window.alert == .exportFailed)
        #expect(harness.service.exportCount(of: id) == 0)

        let denied = try BackupHarness(
            archiving: FailingExportArchiving(failure: CocoaError(.fileWriteNoPermission))
        )
        let other = denied.window()
        await other.backUpNow()
        await other.requestExport(try #require(other.model.rows.first?.id))
        await other.export(try #require(other.exportPrompt))
        #expect(other.alert == .exportFailed)
    }

    @Test("A stored backup that can't be read while exporting keeps D208.2's Couldn’t Open Backup")
    func exportReadErrorKeepsD208() async throws {
        defer { cleanUp() }
        let storage = try ScriptedStorage(folder: folder)
        let harness = try BackupHarness(storage: storage)
        let window = harness.window()
        await window.backUpNow()
        await window.requestExport(try #require(window.model.rows.first?.id))
        storage.readError = BackupFileReadError(CocoaError(.fileReadNoPermission))
        await window.export(try #require(window.exportPrompt))
        #expect(window.alert == .unreadableBackup)
    }

    // MARK: 6. Couldn’t Delete Old Backups

    @Test("A Keep cleanup that fails other than reading: Couldn’t Delete Old Backups, setting unchanged")
    func cleanupFailed() async throws {
        defer { cleanUp() }
        let storage = try ScriptedStorage(folder: folder)
        let harness = try BackupHarness(storage: storage)
        harness.settings.setRetention(BackupRetention(recentAutomatic: 3, monthlyMonths: 0))
        let window = harness.window()
        try await automaticBackups(3, harness)
        await window.load()
        let before = harness.settings.retention()
        storage.readError = CocoaError(.featureUnsupported)
        await window.proposeRetention(BackupRetention(recentAutomatic: 1, monthlyMonths: 0))
        #expect(window.alert == .cleanupFailed)
        #expect(window.alert?.title == "Couldn’t Delete Old Backups")
        #expect(
            window.alert?.message
                == "little-orbit couldn’t delete your older backups. Try again later. Your setting hasn’t changed."
        )
        #expect(window.errorMessage == nil)
        #expect(harness.settings.retention() == before)
    }

    @Test("A folder that can't be removed during Keep's cleanup is silent, kept, and goes at the next cleanup")
    func cleanupDeleteFailsSilently() async throws {
        defer { cleanUp() }
        let storage = try ScriptedStorage(folder: folder)
        let harness = try BackupHarness(storage: storage)
        harness.settings.setRetention(BackupRetention(recentAutomatic: 2, monthlyMonths: 0))
        let window = harness.window()
        try await automaticBackups(2, harness)
        await window.load()
        let oldest = try #require(window.model.rows.last?.id)
        storage.deleteError = CocoaError(.fileWriteNoPermission)
        await window.proposeRetention(BackupRetention(recentAutomatic: 1, monthlyMonths: 0))
        await window.confirmPrune(try #require(window.prunePrompt))
        #expect(window.alert == nil)
        #expect(window.errorMessage == nil)
        #expect(harness.settings.retention() == BackupRetention(recentAutomatic: 1, monthlyMonths: 0))
        #expect(window.model.rows.map(\.id).contains(oldest))

        // The next cleanup, after the next automatic backup, removes it.
        storage.deleteError = nil
        try await automaticBackups(1, harness)
        await window.load()
        #expect(!window.model.rows.map(\.id).contains(oldest))
    }

    // MARK: 8. The catch-all

    @Test("Any other error is Something Went Wrong with the catalog text, never the error's own description")
    func catchAll() {
        let errors: [any Error] = [
            CocoaError(.fileWriteNoPermission, userInfo: [NSFilePathErrorKey: "/x/Backups.staging/SECRET.tmp"]),
            POSIXError(.EACCES),
            NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "SECRET internal name"]),
            CocoaError(.coderReadCorrupt),
        ]
        for error in errors {
            let feedback = BackupsViewModel.feedback(for: error)
            #expect(feedback == .error(BackupPresentation.somethingWentWrongMessage))
            #expect(
                BackupPresentation.somethingWentWrongMessage == "little-orbit couldn’t finish this. Try again later."
            )
            if case .error(let message) = feedback {
                #expect(!message.contains(error.localizedDescription))
                #expect(!message.contains("SECRET"))
            }
        }
    }

    @Test("Every backup error but the three that aren't alerts maps to its own catalog alert, never its own text")
    func noRawTextForAnyBackupError() {
        let notAlerts: [BackupError] = [.notEnoughStorage, .busy, .loadFailed]
        var alerts = 0
        for error in BackupError.allCases {
            let feedback = BackupsViewModel.feedback(for: error)
            if notAlerts.contains(error) {
                #expect(feedback == BackupFeedback.none, "\(error)")
                continue
            }
            guard case .alert(let alert) = feedback else {
                Issue.record("\(error) isn't an alert: \(feedback)")
                continue
            }
            alerts += 1
            #expect(!alert.title.isEmpty, "\(error)")
            #expect(!alert.message.contains(error.localizedDescription), "\(error)")
            #expect(!alert.message.contains("\(error)"), "\(error)")
        }
        #expect(alerts == BackupError.allCases.count - notAlerts.count)
    }

    @Test("The catch-all's title is a catalog entry, and BackupFlow has no literal for it (L73, D211.9)")
    func catchAllTitleFromCatalog() throws {
        #expect(BackupPresentation.somethingWentWrongTitle == "Something Went Wrong")
        let flow = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/LittleOrbitFeatures/Backups/Views/BackupFlow.swift")
        let source = try String(contentsOf: flow, encoding: .utf8)
        #expect(!source.contains("\"Something Went Wrong\""))
        #expect(source.contains("BackupPresentation.somethingWentWrongTitle"))
    }
}
