import Foundation
import LittleOrbitDomain
import LittleOrbitFeatures
import LittleOrbitPersistence
import Testing

/// The Backups screen's flows (D63, D116.1, D116.2, D118.5, D182).
@MainActor
@Suite("Backups view model")
struct BackupsViewModelTests {
    @Test("Empty until the first backup, then newest first with the last-backup line")
    func listing() async throws {
        let harness = try BackupHarness()
        let window = harness.window()
        let model = window.model
        try await model.load()
        #expect(model.isEmpty)
        #expect(model.lastBackupText == nil)
        await window.backUpNow()
        harness.advance(60)
        await window.backUpNow()
        #expect(model.rows.count == 2)
        #expect(model.rows.map { spaced($0.title) } == ["Today, 9:13 AM", "Today, 9:12 AM"])
        #expect(spaced(model.lastBackupText).hasPrefix("Last backup: Today, 9:13 AM."))
        #expect(!model.isBackingUp)
    }

    @Test("Delete asks to confirm, then App Lock, then removes the backup (D116.1)")
    func delete() async throws {
        let harness = try BackupHarness()
        let lock = RecordingAuthentication(allows: true)
        let window = harness.window(authentication: lock)
        let model = window.model
        await window.backUpNow()
        let id = try #require(model.rows.first?.id)
        window.requestDelete(id)
        let presented = try #require(window.deletePrompt)
        #expect(presented.id == id)
        #expect(lock.purposes.isEmpty)
        await window.confirmDelete(presented)
        #expect(lock.purposes == [.deleteBackup])
        #expect(model.isEmpty)
        #expect(try harness.storedFiles().isEmpty)
    }

    @Test("Delete Backup deletes after the dialog's binding has cleared the prompt (Tester B2)")
    func deleteAfterDismiss() async throws {
        let harness = try BackupHarness()
        let window = harness.window()
        let model = window.model
        await window.backUpNow()
        window.requestDelete(try #require(model.rows.first?.id))
        let presented = try #require(window.deletePrompt)
        // What SwiftUI does first when the dialog's button is tapped: isPresented is set to false.
        window.deletePrompt = nil
        await window.confirmDelete(presented)
        #expect(model.isEmpty)
        #expect(try harness.storedFiles().isEmpty)
    }

    @Test("A failed or cancelled App Lock prompt changes nothing (S31, S51)")
    func lockedDelete() async throws {
        let harness = try BackupHarness()
        let lock = RecordingAuthentication(allows: false)
        let window = harness.window(authentication: lock)
        let model = window.model
        await window.backUpNow()
        let id = try #require(model.rows.first?.id)
        window.requestDelete(id)
        await window.confirmDelete(try #require(window.deletePrompt))
        await window.requestRestore(id)
        await window.requestExport(id)
        #expect(lock.purposes == [.deleteBackup, .restoreBackup, .exportBackup])
        #expect(model.rows.count == 1)
        #expect(window.restorePrompt == nil)
        #expect(window.exportPrompt == nil)
    }

    @Test("Restore: warning, then progress, then the toast and a Before restore backup (D116.2)")
    func restore() async throws {
        let harness = try BackupHarness()
        let window = harness.window()
        let model = window.model
        await window.backUpNow()
        let id = try #require(model.rows.first?.id)
        await window.requestRestore(id)
        let prompt = try #require(window.restorePrompt)
        #expect(
            spaced(prompt.message)
                .hasPrefix("All data on this iPhone will be replaced with this backup (Today, 9:12 AM")
        )
        await window.confirmRestore(prompt)
        #expect(window.toast == "Backup restored · Before restore backup saved")
        #expect(spaced(window.restoredMessage).hasPrefix("Backup restored. Your previous data is saved as a Before"))
        #expect(model.restoreStep == nil)
        #expect(model.rows.map(\.kindText) == ["Before restore", "Manual"])
    }

    @Test("Restore runs after the alert's binding has cleared the prompt (Tester B1)")
    func restoreAfterDismiss() async throws {
        let harness = try BackupHarness()
        let window = harness.window()
        let model = window.model
        await window.backUpNow()
        let before = try harness.repository.ledgerSnapshot()
        try harness.repository.replaceLedger(with: LedgerSnapshot())
        await window.requestRestore(try #require(model.rows.last?.id))
        let presented = try #require(window.restorePrompt)
        // What SwiftUI does first when Restore is tapped: isPresented is set to false, which cancels.
        window.cancelRestore()
        await window.confirmRestore(presented)
        #expect(model.rows.map(\.kindText) == ["Before restore", "Manual"])
        #expect(try harness.repository.ledgerSnapshot().accounts.count == before.accounts.count)
        #expect(window.toast != nil)
    }

    @Test("Restore from File: App Lock, then the warning, then the Before restore backup, then progress (R2)")
    func restoreOrder() async throws {
        let harness = try BackupHarness()
        let lock = RecordingAuthentication(allows: true)
        let window = harness.window(authentication: lock)
        let model = window.model
        let backup = try await harness.service.backUpNow()
        let file = try await harness.exportData(backup.id)
        try await model.load()
        await window.restoreFromFile(.data(file))
        #expect(lock.purposes == [.restoreBackup])
        let prompt = try #require(window.restorePrompt)
        #expect(model.rows.count == 1)
        let probe = RestoreProbe(harness: harness)
        let before = try await harness.service.restore(prompt.source) { probe.record($0) }
        #expect(probe.steps == [.savingCurrentData, .replacingData, .finished])
        #expect(probe.backupsWhenReplacing == 2)
        #expect(before.kind == .beforeRestore)
    }

    @Test("Cancelling the warning changes nothing")
    func cancelRestore() async throws {
        let harness = try BackupHarness()
        let window = harness.window()
        let model = window.model
        await window.backUpNow()
        await window.requestRestore(try #require(model.rows.first?.id))
        window.cancelRestore()
        #expect(window.restorePrompt == nil)
        #expect(model.rows.count == 1)
    }

    @Test("A damaged file shows the damaged alert (S50)")
    func damaged() async throws {
        let harness = try BackupHarness()
        let window = harness.window()
        let model = window.model
        await window.restoreFromFile(.data(Data()))
        #expect(window.alert == .damaged)
        #expect(window.alert?.title == "This Backup Is Damaged")
        #expect(window.restorePrompt == nil)
    }

    @Test(
        "An old encrypted file is damaged, with no password prompt, and the data is unchanged (S81, R5)",
        arguments: ["helper", "fixture"],
    )
    func oldEncryptedFile(source: String) async throws {
        let harness = try BackupHarness()
        let lock = RecordingAuthentication(allows: true)
        let window = harness.window(authentication: lock)
        let model = window.model
        let backup = try await harness.service.backUpNow()
        let plain = try await harness.exportData(backup.id)
        let file = source == "fixture" ? try oldEncryptedSample() : try addingEncryptionSection(to: plain)
        let ledger = try harness.repository.ledgerSnapshot()
        try await model.load()
        await window.restoreFromFile(.data(file))
        #expect(lock.purposes == [.restoreBackup])
        #expect(window.alert == .damaged)
        #expect(window.alert?.title == "This Backup Is Damaged")
        #expect(window.restorePrompt == nil)
        #expect(model.restoreStep == nil)
        #expect(try harness.repository.ledgerSnapshot() == ledger)
        #expect(model.rows.count == 1)
    }

    @Test("A newer format shows the update alert (S52)")
    func newer() async throws {
        let harness = try BackupHarness()
        let window = harness.window()
        let model = window.model
        let backup = try await harness.service.backUpNow()
        let export = try await harness.exportData(backup.id)
        let file = try rewritingManifest(of: export) { $0["formatVersion"] = 99 }
        await window.restoreFromFile(.data(file))
        #expect(window.alert == .newerFormat)
        #expect(window.alert?.title == "Update little-orbit to Restore This Backup")
    }

    @Test("A full disk shows the storage message and keeps the list as it was (S58)")
    func fullDisk() async throws {
        let harness = try BackupHarness(storage: FullDiskStorage())
        let window = harness.window()
        let model = window.model
        await window.backUpNow()
        #expect(model.failureMessage == harness.viewModel().presentation.notEnoughStorageMessage)
        #expect(model.isEmpty)
    }

    @Test("Export: App Lock, then the sheet with the summary, then the plain file with its name (R1, S9, D186)")
    func export() async throws {
        let harness = try BackupHarness()
        let lock = RecordingAuthentication(allows: true)
        let window = harness.window(authentication: lock)
        let model = window.model
        await window.backUpNow()
        let id = try #require(model.rows.first?.id)
        await window.requestExport(id)
        let prompt = try #require(window.exportPrompt)
        #expect(prompt.record.id == id)
        let counts = try harness.repository.ledgerSnapshot()
        #expect(
            spaced(prompt.summary)
                == "Backup from Today, 9:12 AM · Manual · \(counts.accountsVisible().count) accounts · "
                + "\(counts.transactionsVisible().count) transactions"
        )
        // Export goes straight to the share sheet or save panel: no password and no extra step (D182.4).
        await window.export(prompt)
        #expect(lock.purposes == [.exportBackup])
        #expect(window.exportPrompt == nil)
        let file = try #require(window.pendingExport)
        #expect(file.fileName == "little-orbit 2026-10-22 0912.littleorbit-backup")
        // A file of its own in the staging folder, handed over by URL, never as bytes (B2).
        #expect(file.url.lastPathComponent == file.fileName)
        let staging = URL(fileURLWithPath: harness.folder.path + ".staging").standardizedFileURL.path
        #expect(file.url.deletingLastPathComponent().deletingLastPathComponent().standardizedFileURL.path == staging)
        let files = try BackupArchiveSafety.files(from: harness.archiving.entries(of: Data(contentsOf: file.url)))
        let manifest = try #require(files["manifest.json"])
        let object = try #require(JSONSerialization.jsonObject(with: manifest) as? [String: Any])
        #expect(object["encryption"] == nil)
        #expect(object["formatVersion"] as? Int == 1)
        // Saved or cancelled, the file and its folder go when the panel closes.
        window.finishExport()
        #expect(window.pendingExport == nil)
        #expect(!FileManager.default.fileExists(atPath: file.url.deletingLastPathComponent().path))
        #expect(((try? FileManager.default.contentsOfDirectory(atPath: staging)) ?? []).isEmpty)
    }

    @Test(
        "The Export summary is the selected backup's date, kind and counts, with no attachments text at 0 (S64, S76, D186)"
    )
    func exportSummaryValues() async throws {
        let repository = InMemoryLedgerRepository()
        let wallet = Account(name: "Wallet", type: .cash, currencyCode: "INR", openingBalance: 500, sortOrder: 1)
        let bank = Account(name: "Bank", type: .checking, currencyCode: "INR", openingBalance: 0, sortOrder: 2)
        try repository.saveAccount(wallet)
        try repository.saveAccount(bank)
        let spends = [120, 80, 45].map { Transaction(amount: Decimal($0), accountID: wallet.id) }
        for spend in spends {
            try repository.saveTransaction(spend)
        }
        let harness = try BackupHarness(repository: repository)
        let window = harness.window()
        let model = window.model
        // Made yesterday at 20:47, exported today.
        harness.advance(-(9 * 3_600 + 12 * 60 + 5) + 20 * 3_600 + 47 * 60 - 86_400)
        let manual = try await harness.service.backUpNow()
        harness.advance(86_400 - 60)
        try await model.load()
        await window.requestExport(manual.id)
        #expect(
            spaced(window.exportPrompt?.summary)
                == "Backup from Yesterday, 8:47 PM · Manual · 2 accounts · 3 transactions"
        )
        #expect(spaced(window.exportPrompt?.dateText) == "Yesterday, 8:47 PM")

        // The selected backup, not the newest; attachments are listed when there are any.
        window.exportPrompt = nil
        let receipt = Attachment(
            transactionID: spends[0].id,
            fileName: "receipt.jpg",
            contentType: "image/jpeg",
            byteSize: 3,
            data: Data([1, 2, 3]),
        )
        try repository.saveAttachment(receipt)
        let newer = try await harness.service.backUpNow()
        try await model.load()
        await window.requestExport(newer.id)
        let newerSummary = spaced(window.exportPrompt?.summary)
        #expect(newerSummary.hasSuffix("· Manual · 2 accounts · 3 transactions · 1 attachment"))
        window.exportPrompt = nil
        await window.requestExport(manual.id)
        let reopened = spaced(window.exportPrompt?.summary)
        #expect(reopened.hasPrefix("Backup from Yesterday, 8:47 PM"))
        #expect(!reopened.contains("attachment"))
    }

    @Test("The Delete footnote names the device's biometry")
    func footnote() throws {
        let harness = try BackupHarness()
        let window = harness.window(authentication: RecordingAuthentication(allows: true))
        let model = window.model
        #expect(model.deleteFootnote(for: UUID()).contains("Face ID or the app passcode"))
    }

    @Test("Back Up Now shows progress, disables Back Up Now and Restore, and announces start and finish (D179.2)")
    func progressAndAnnouncements() async throws {
        let harness = try BackupHarness()
        let probe = AnnouncementProbe()
        let model = harness.viewModel { probe.record($0) }
        let window = BackupsWindow(model: model)
        probe.model = model
        await window.backUpNow()
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
        let window = BackupsWindow(model: model)
        await window.backUpNow()
        #expect(
            probe.announcements == ["Backup in progress", harness.viewModel().presentation.notEnoughStorageMessage]
        )
    }

    @Test("Rows follow the stored backup time, newest first (D179.4)")
    func rowOrder() async throws {
        let harness = try BackupHarness()
        let window = harness.window()
        let model = window.model
        let first = try await harness.service.backUpNow()
        harness.advance(20)
        let second = try await harness.service.backUpNow()
        harness.advance(3_600)
        let third = try await harness.service.backUpNow()
        try await model.load()
        #expect(model.rows.map(\.id) == [third.id, second.id, first.id])
    }

    @Test("The restore steps read as text, not a percentage (UI Designer)")
    func restoreStepText() async throws {
        let harness = try BackupHarness()
        let window = harness.window()
        let model = window.model
        #expect(model.restoreStepText == "Current data saved as a Before restore backup")
        #expect(!model.isCurrentDataSaved)
        #expect(model.restoreFraction == 0)
    }

    @Test("The detail footnote is the same for every kind, and follows the settings (L25)")
    func footnoteByKind() async throws {
        let harness = try BackupHarness()
        harness.settings.setRetention(BackupRetention(recentAutomatic: 3, monthlyMonths: 0))
        let window = harness.window()
        let model = window.model
        await window.backUpNow()
        let id = try #require(model.rows.first?.id)
        #expect(model.deleteFootnote(for: id).hasPrefix("Any backup can be deleted."))
        #expect(model.deleteFootnote(for: id).contains("little-orbit keeps your 3 most recent automatic backups."))
    }
}

/// Records the restore steps, and how many backups exist when the data is replaced.
@MainActor
private final class RestoreProbe {
    let harness: BackupHarness
    private(set) var steps: [BackupRestoreStep] = []
    private(set) var backupsWhenReplacing: Int?

    init(harness: BackupHarness) {
        self.harness = harness
    }

    func record(_ step: BackupRestoreStep) {
        steps.append(step)
        if step == .replacingData {
            backupsWhenReplacing = try? harness.storedFiles().count
        }
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
