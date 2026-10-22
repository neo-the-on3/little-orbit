import Foundation
import LittleOrbitDomain
import LittleOrbitFeatures
import LittleOrbitPersistence
import Testing

/// Two windows on one shared Backups view model (Tech Architect: prompts, alerts and errors are per window, the
/// same as #87's B3 `AccountDeleteConfirmation`). What one window asks for or confirms never shows in the other;
/// the other sees only the shared list change.
@MainActor
@Suite("Backups windows")
struct BackupsWindowTests {
    private func twoWindows(_ harness: BackupHarness) -> (BackupsWindow, BackupsWindow) {
        let model = harness.viewModel()
        return (BackupsWindow(model: model), BackupsWindow(model: model))
    }

    @Test("A restore prompt in window A never shows in B, and confirming it in A leaks nothing into B")
    func restore() async throws {
        let harness = try BackupHarness()
        let (first, second) = twoWindows(harness)
        await first.backUpNow()
        let id = try #require(first.model.rows.first?.id)

        await first.requestRestore(id)
        let prompt = try #require(first.restorePrompt)
        #expect(second.restorePrompt == nil)

        var progressDuring: (first: Bool, second: Bool)?
        harness.changes.onReplacement {
            progressDuring = (first.isShowingRestoreProgress, second.isShowingRestoreProgress)
        }
        await first.confirmRestore(prompt)
        #expect(progressDuring?.first == true)
        #expect(progressDuring?.second == false)
        #expect(first.toast != nil)
        #expect(first.restoredMessage != nil)
        #expect(second.restorePrompt == nil)
        #expect(second.toast == nil)
        #expect(second.restoredMessage == nil)
        #expect(second.alert == nil)
        #expect(second.errorMessage == nil)
        // Only the shared list changed.
        #expect(second.model.rows.map(\.kindText) == ["Before restore", "Manual"])
    }

    @Test("A restore from a file in A shows its alert only in A")
    func restoreAlert() async throws {
        let harness = try BackupHarness()
        let (first, second) = twoWindows(harness)
        await first.restoreFromFile(.data(Data("Shopping list".utf8)))
        #expect(first.alert == .damaged)
        #expect(second.alert == nil)
        #expect(second.restorePrompt == nil)
    }

    @Test("Delete: the confirmation in A never shows in B; confirming in A only removes the row")
    func delete() async throws {
        let harness = try BackupHarness()
        let (first, second) = twoWindows(harness)
        await first.backUpNow()
        let id = try #require(first.model.rows.first?.id)
        first.requestDelete(id)
        let row = try #require(first.deletePrompt)
        #expect(second.deletePrompt == nil)
        await first.confirmDelete(row)
        #expect(second.deletePrompt == nil)
        #expect(second.model.isEmpty)
    }

    @Test("Export: the sheet and the file in A never show in B")
    func export() async throws {
        let harness = try BackupHarness()
        let (first, second) = twoWindows(harness)
        await first.backUpNow()
        await first.requestExport(try #require(first.model.rows.first?.id))
        let prompt = try #require(first.exportPrompt)
        #expect(second.exportPrompt == nil)
        await first.export(prompt)
        #expect(first.pendingExport != nil)
        #expect(second.pendingExport == nil)
        #expect(second.exportPrompt == nil)
    }

    @Test("A picked file that can't be read shows its read error, not 'Damaged' (Tech Architect N1)")
    func unreadableFile() async throws {
        let harness = try BackupHarness()
        let window = harness.window()
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("not-downloaded-\(UUID().uuidString).littleorbit-backup")
        await window.restoreFromFile(.file(missing))
        #expect(window.alert == nil)
        #expect(window.restorePrompt == nil)
        let message = try #require(window.errorMessage)
        #expect(!message.isEmpty)
    }

    @Test("A picked file is restored from where it is, read again and checked again after the warning (B1.1)")
    func restoreFromURL() async throws {
        let harness = try BackupHarness()
        let window = harness.window()
        let backup = try await harness.service.backUpNow()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("restore-\(UUID().uuidString).littleorbit-backup")
        try await harness.service.exportBackup(id: backup.id).data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        try await window.model.load()
        await window.restoreFromFile(.file(url))
        let prompt = try #require(window.restorePrompt)
        #expect(prompt.source == .file(at: url))

        // Changed after the warning: the restore refuses it and the data stays as it was.
        let ledger = try harness.repository.ledgerSnapshot()
        try Data("changed".utf8).write(to: url)
        await window.confirmRestore(prompt)
        #expect(window.alert == .damaged)
        #expect(window.toast == nil)
        #expect(try harness.repository.ledgerSnapshot() == ledger)
    }
}

/// Backups, checks and restores never read a stored folder whole: only Export does (Tech Architect B1.2).
@MainActor
@Suite("Backup memory")
struct BackupMemoryTests {
    @Test("Backing up, the cleanup and restoring a stored backup read file by file, never the whole folder")
    func noWholeFolderReads() async throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("backup-reads-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let storage = try CountingReadsStorage(folder: folder)
        let harness = try BackupHarness(storage: storage)
        harness.settings.setRetention(BackupRetention(recentAutomatic: 1, monthlyMonths: 0))
        let window = harness.window()
        await window.backUpNow()
        harness.advance(86_400)
        _ = try await harness.service.backUpAutomaticallyIfNeeded()
        harness.advance(86_400)
        _ = try await harness.service.backUpAutomaticallyIfNeeded()
        await window.load()
        await window.requestRestore(try #require(window.model.rows.last?.id))
        await window.confirmRestore(try #require(window.restorePrompt))
        #expect(window.toast != nil)
        #expect(storage.wholeReads == 0)
        #expect(storage.folderReads > 0)
    }
}

/// The real folder store, counting whole-folder reads and file-by-file readers.
final class CountingReadsStorage: BackupStorage, @unchecked Sendable {
    private let base: FileBackupStorage
    private let lock = NSLock()
    private var whole = 0
    private var folders = 0

    init(folder: URL) throws {
        base = try FileBackupStorage(folder: folder)
    }

    var wholeReads: Int { lock.withLock { whole } }
    var folderReads: Int { lock.withLock { folders } }

    func storedIDs() throws -> [UUID] { try base.storedIDs() }
    func listing(id: UUID) throws -> BackupFolderListing { try base.listing(id: id) }
    func delete(id: UUID) throws { try base.delete(id: id) }
    func loadStatus() throws -> BackupStatus { try base.loadStatus() }
    func saveStatus(_ status: BackupStatus) throws { try base.saveStatus(status) }

    func read(id: UUID) throws -> BackupSnapshotFiles {
        lock.withLock { whole += 1 }
        return try base.read(id: id)
    }

    func files(id: UUID) throws -> any BackupFileReading {
        lock.withLock { folders += 1 }
        return try base.files(id: id)
    }

    func write(_ files: BackupSnapshotFiles, id: UUID, cloningFrom earlier: UUID?) throws {
        try base.write(files, id: id, cloningFrom: earlier)
    }
}
