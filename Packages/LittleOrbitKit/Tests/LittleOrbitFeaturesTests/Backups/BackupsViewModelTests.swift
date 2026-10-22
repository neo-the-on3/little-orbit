import Foundation
import LittleOrbitDomain
import LittleOrbitFeatures
import LittleOrbitPersistence
import Testing

/// The Backups screen's flows (D63, D116.1, D116.2, D118.4, D118.5).
@MainActor
@Suite("Backups view model")
struct BackupsViewModelTests {
    @Test("Empty until the first backup, then newest first with the last-backup line")
    func listing() async throws {
        let harness = try BackupHarness()
        let model = harness.viewModel()
        model.load()
        #expect(model.isEmpty)
        #expect(model.lastBackupText == nil)
        await model.backUpNow()
        harness.advance(60)
        await model.backUpNow()
        #expect(model.rows.count == 2)
        #expect(model.rows.map { spaced($0.title) } == ["Today, 9:13 AM", "Today, 9:12 AM"])
        #expect(spaced(model.lastBackupText).hasPrefix("Last backup: Today, 9:13 AM."))
        #expect(!model.isBackingUp)
    }

    @Test("Delete asks to confirm, then App Lock, then removes the backup (D116.1)")
    func delete() async throws {
        let harness = try BackupHarness()
        let lock = RecordingAuthentication(allows: true)
        let model = harness.viewModel(authentication: lock)
        await model.backUpNow()
        let id = try #require(model.rows.first?.id)
        model.requestDelete(id)
        #expect(model.deletePrompt?.id == id)
        #expect(lock.purposes.isEmpty)
        await model.confirmDelete()
        #expect(lock.purposes == [.deleteBackup])
        #expect(model.isEmpty)
    }

    @Test("A failed or cancelled App Lock prompt changes nothing (S31, S51)")
    func lockedDelete() async throws {
        let harness = try BackupHarness()
        let lock = RecordingAuthentication(allows: false)
        let model = harness.viewModel(authentication: lock)
        await model.backUpNow()
        let id = try #require(model.rows.first?.id)
        model.requestDelete(id)
        await model.confirmDelete()
        await model.requestRestore(id)
        await model.requestExport(id)
        #expect(lock.purposes == [.deleteBackup, .restoreBackup, .exportBackup])
        #expect(model.rows.count == 1)
        #expect(model.restorePrompt == nil)
        #expect(model.exportForm == nil)
    }

    @Test("Restore: warning, then progress, then the toast and a Before restore backup (D116.2)")
    func restore() async throws {
        let harness = try BackupHarness()
        let model = harness.viewModel()
        await model.backUpNow()
        let id = try #require(model.rows.first?.id)
        await model.requestRestore(id)
        let prompt = try #require(model.restorePrompt)
        #expect(
            spaced(prompt.message)
                .hasPrefix("All data on this iPhone will be replaced with this backup (Today, 9:12 AM")
        )
        await model.confirmRestore()
        #expect(model.toast == "Backup restored · Before restore backup saved")
        #expect(spaced(model.restoredMessage).hasPrefix("Backup restored. Your previous data is saved as a Before"))
        #expect(model.restoreStep == nil)
        #expect(model.rows.map(\.kindText) == ["Before restore", "Manual"])
    }

    @Test("Cancelling the warning changes nothing")
    func cancelRestore() async throws {
        let harness = try BackupHarness()
        let model = harness.viewModel()
        await model.backUpNow()
        await model.requestRestore(try #require(model.rows.first?.id))
        model.cancelRestore()
        #expect(model.restorePrompt == nil)
        #expect(model.rows.count == 1)
    }

    @Test("An encrypted file asks for its password, and a wrong one can be retried (D118.4)")
    func passwordRetry() async throws {
        let harness = try BackupHarness()
        let model = harness.viewModel()
        let backup = try await harness.service.backUpNow()
        let export = try await harness.service.exportBackup(id: backup.id, password: "orbit-pass")

        let fileName = model.presentation.fileName(for: export.record)
        await model.restoreFromFile(export.data, fileName: fileName)
        #expect(model.passwordPrompt?.errorMessage == nil)
        #expect(model.passwordPrompt?.fileName == fileName)
        await model.submitPassword("wrong-pass")
        #expect(model.passwordPrompt?.errorMessage == "Incorrect password. Try again.")
        await model.submitPassword("still-wrong")
        #expect(model.passwordPrompt?.errorMessage == "Incorrect password. Try again.")
        await model.submitPassword("orbit-pass")
        #expect(model.passwordPrompt == nil)
        #expect(model.restorePrompt != nil)
    }

    @Test("A damaged file shows the damaged alert (S50)")
    func damaged() async throws {
        let harness = try BackupHarness()
        let model = harness.viewModel()
        await model.restoreFromFile(Data(), fileName: "notes.txt")
        #expect(model.alert == .damaged)
        #expect(model.alert?.title == "This Backup Is Damaged")
        #expect(model.restorePrompt == nil)
    }

    @Test("A newer format shows the update alert (S52)")
    func newer() async throws {
        let harness = try BackupHarness()
        let model = harness.viewModel()
        let file = Data(#"{"format":"little-orbit-backup","formatVersion":99}"#.utf8)
        await model.restoreFromFile(file, fileName: "future.littleorbit-backup")
        #expect(model.alert == .newerFormat)
        #expect(model.alert?.title == "Update little-orbit to Restore This Backup")
    }

    @Test("A full disk shows the storage message and keeps the list as it was (S58)")
    func fullDisk() async throws {
        let harness = try BackupHarness(storage: FullDiskStorage())
        let model = harness.viewModel()
        await model.backUpNow()
        #expect(model.failureMessage == harness.viewModel().presentation.notEnoughStorageMessage)
        #expect(model.isEmpty)
    }

    @Test("Export: App Lock, then the form, then the file with its name")
    func export() async throws {
        let harness = try BackupHarness()
        let lock = RecordingAuthentication(allows: true)
        let model = harness.viewModel(authentication: lock)
        await model.backUpNow()
        await model.requestExport(try #require(model.rows.first?.id))
        let form = try #require(model.exportForm)
        await model.export(form)
        #expect(lock.purposes == [.exportBackup])
        #expect(model.pendingExport?.fileName == "little-orbit 2026-10-22 0912.littleorbit-backup")
        #expect(model.pendingExport?.isEncrypted == false)
        #expect(model.exportForm == nil)
    }

    @Test("The Delete footnote names the device's biometry")
    func footnote() throws {
        let harness = try BackupHarness()
        let model = harness.viewModel(authentication: RecordingAuthentication(allows: true))
        #expect(model.deleteFootnote(for: UUID()).contains("Face ID or the app passcode"))
    }

    @Test("Back Up Now shows progress, disables Back Up Now and Restore, and announces start and finish (D179.2)")
    func progressAndAnnouncements() async throws {
        let harness = try BackupHarness()
        let probe = AnnouncementProbe()
        let model = harness.viewModel { probe.record($0) }
        probe.model = model
        await model.backUpNow()
        #expect(probe.announcements == ["Backup in progress", "Backup complete"])
        #expect(probe.busyAtStart == true)
        #expect(probe.enabledAtStart == false)
        #expect(!model.isBackingUp)
        #expect(model.actionsEnabled)
    }

    @Test("A full disk announces the not-enough-storage text")
    func failedAnnouncement() async throws {
        let harness = try BackupHarness(storage: FullDiskStorage())
        let probe = AnnouncementProbe()
        let model = harness.viewModel { probe.record($0) }
        await model.backUpNow()
        #expect(
            probe.announcements == ["Backup in progress", harness.viewModel().presentation.notEnoughStorageMessage]
        )
    }

    @Test("Rows follow the stored backup time, newest first (D179.4)")
    func rowOrder() async throws {
        let harness = try BackupHarness()
        let model = harness.viewModel()
        let first = try await harness.service.backUpNow()
        harness.advance(20)
        let second = try await harness.service.backUpNow()
        harness.advance(3_600)
        let third = try await harness.service.backUpNow()
        model.load()
        #expect(model.rows.map(\.id) == [third.id, second.id, first.id])
    }

    @Test("The restore steps read as text, not a percentage (UI Designer)")
    func restoreStepText() async throws {
        let harness = try BackupHarness()
        let model = harness.viewModel()
        #expect(model.restoreStepText == "Current data saved as a Before restore backup")
        #expect(!model.isCurrentDataSaved)
        #expect(model.restoreFraction == 0)
    }

    @Test("The detail footnote depends on the backup's kind")
    func footnoteByKind() async throws {
        let harness = try BackupHarness()
        let model = harness.viewModel()
        await model.backUpNow()
        let id = try #require(model.rows.first?.id)
        #expect(model.deleteFootnote(for: id).hasPrefix("Manual and Before restore backups stay"))
    }
}

/// Records VoiceOver announcements and what the screen showed when the backup started.
@MainActor
private final class AnnouncementProbe {
    weak var model: BackupsViewModel?
    private(set) var announcements: [String] = []
    private(set) var busyAtStart: Bool?
    private(set) var enabledAtStart: Bool?

    func record(_ text: String) {
        announcements.append(text)
        if text == BackupPresentation.backupStartedAnnouncement, let model {
            busyAtStart = model.isBackingUp
            enabledAtStart = model.actionsEnabled
        }
    }
}
