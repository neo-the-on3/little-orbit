import Foundation
import LittleOrbitDomain
import LittleOrbitFeatures
import LittleOrbitPersistence
import Testing

/// Tester F3 on 318e59f: a Before restore backup that couldn't be written showed "Something Went Wrong" with the
/// system's own text, which names the uuid.tmp and Backups.staging folders. Any failure while making it, written,
/// moved or checked, is `beforeRestoreFailed` now: "Couldn’t Restore", with the data unchanged (D63, D207.1).
@MainActor
@Suite(
    "A Before restore backup that can't be written stops the restore with Couldn’t Restore (Tester F3)",
    .timeLimit(.minutes(2)),
)
struct BackupBeforeRestoreWriteTests {
    /// Where the window's list and the system text could name the store's files.
    private static let internalNames = [".tmp", "staging", "Backups", "permission"]

    /// A file exported from another store, as Restore from File picks it.
    private func pickedFile(in folder: URL) async throws -> URL {
        let source = try BackupHarness()
        let backup = try await source.service.backUpNow()
        let url = folder.appendingPathComponent("\(UUID().uuidString).littleorbit-backup")
        try await source.exportData(backup.id).write(to: url)
        return url
    }

    /// Confirms the restore `window` prompts for, and lets the progress sheet appear and close.
    private func confirm(_ window: BackupsWindow) async throws {
        let prompt = try #require(window.restorePrompt)
        window.restorePrompt = nil
        await window.confirmRestore(prompt)
        window.showAndCloseRestoreProgress()
    }

    /// "Couldn’t Restore", no "Something Went Wrong", and none of the store's names in what's shown.
    private func expectCouldntRestore(_ window: BackupsWindow) {
        #expect(window.alert == .beforeRestoreFailed)
        #expect(window.alert?.title == "Couldn’t Restore")
        #expect(window.errorMessage == nil)
        let shown = (window.alert?.title ?? "") + (window.alert?.message ?? "") + (window.errorMessage ?? "")
        for name in Self.internalNames {
            #expect(!shown.contains(name))
        }
    }

    /// `folder` read-only while `work` runs, then writable again so it can be removed.
    private func readOnly(_ folder: URL, _ work: () async throws -> Void) async throws {
        let manager = FileManager.default
        try manager.createDirectory(at: folder, withIntermediateDirectories: true)
        try manager.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder.path)
        defer { try? manager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path) }
        try await work()
    }

    private func staging(_ harness: BackupHarness) -> URL {
        URL(fileURLWithPath: harness.folder.path + ".staging", isDirectory: true)
    }

    @Test(
        "Real read-only staging folder, stored backup: Couldn’t Restore, data unchanged, nothing new listed",
        .enabled(if: geteuid() != 0, "root ignores folder permissions"),
    )
    func readOnlyStagingStored() async throws {
        let harness = try BackupHarness()
        let window = harness.window()
        await window.backUpNow()
        let ledger = try harness.repository.ledgerSnapshot()
        let listed = window.model.rows.map(\.id)
        await window.requestRestore(try #require(listed.first))
        try await readOnly(staging(harness)) {
            try await confirm(window)
        }
        expectCouldntRestore(window)
        #expect(try harness.repository.ledgerSnapshot() == ledger)
        #expect(harness.changes.replacements == 0)
        #expect(window.model.rows.map(\.id) == listed)
    }

    @Test(
        "Real read-only staging folder, Restore from File: Couldn’t Restore, data unchanged",
        .enabled(if: geteuid() != 0, "root ignores folder permissions"),
    )
    func readOnlyStagingFile() async throws {
        let picked = FileManager.default.temporaryDirectory.appendingPathComponent("picked-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: picked, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: picked) }
        let url = try await pickedFile(in: picked)
        let harness = try BackupHarness()
        let window = harness.window()
        await window.backUpNow()
        let ledger = try harness.repository.ledgerSnapshot()
        await window.restoreFromFile(.file(url))
        try await readOnly(staging(harness)) {
            try await confirm(window)
        }
        expectCouldntRestore(window)
        #expect(try harness.repository.ledgerSnapshot() == ledger)
        #expect(harness.changes.replacements == 0)
    }

    @Test(
        "Real read-only Backups folder, staging writable: the move fails, and it's Couldn’t Restore",
        .enabled(if: geteuid() != 0, "root ignores folder permissions"),
    )
    func readOnlyBackupsFolder() async throws {
        let harness = try BackupHarness()
        let window = harness.window()
        await window.backUpNow()
        let ledger = try harness.repository.ledgerSnapshot()
        await window.requestRestore(try #require(window.model.rows.first?.id))
        try await readOnly(harness.folder) {
            try await confirm(window)
        }
        expectCouldntRestore(window)
        #expect(try harness.repository.ledgerSnapshot() == ledger)
        #expect(harness.changes.replacements == 0)
    }

    @Test("A write that fails with a system error, stored and from a file, is beforeRestoreFailed in the service")
    func failingWrite() async throws {
        let picked = FileManager.default.temporaryDirectory.appendingPathComponent("picked-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: picked, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: picked) }
        let url = try await pickedFile(in: picked)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("failing-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let storage = try FailingWriteStorage(folder: folder, failure: CocoaError(.fileWriteNoPermission))
        let harness = try BackupHarness(storage: storage)
        let backup = try await harness.service.backUpNow()
        let ledger = try harness.repository.ledgerSnapshot()
        storage.failWrites()
        for source in [BackupSource.stored(backup.id), .file(at: url)] {
            await #expect(throws: BackupError.beforeRestoreFailed) {
                try await harness.service.restore(source) { _ in }
            }
        }
        #expect(try harness.repository.ledgerSnapshot() == ledger)
        #expect(harness.changes.replacements == 0)
        #expect(try await harness.service.overview().backups.map(\.id) == [backup.id])
    }

    @Test("The fake failing write in the window: Couldn’t Restore, no system text")
    func failingWriteInWindow() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("failing-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let storage = try FailingWriteStorage(
            folder: folder,
            failure: CocoaError(.fileWriteNoPermission, userInfo: [NSFilePathErrorKey: "/x/Backups.staging/A.tmp"]),
        )
        let harness = try BackupHarness(storage: storage)
        let window = harness.window()
        await window.backUpNow()
        let ledger = try harness.repository.ledgerSnapshot()
        await window.requestRestore(try #require(window.model.rows.first?.id))
        storage.failWrites()
        try await confirm(window)
        expectCouldntRestore(window)
        #expect(try harness.repository.ledgerSnapshot() == ledger)
    }

    @Test("Cancelling while the Before restore backup is written still ends with CancellationError")
    func cancellationPassesThrough() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("failing-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let storage = try FailingWriteStorage(folder: folder, failure: CancellationError())
        let harness = try BackupHarness(storage: storage)
        let backup = try await harness.service.backUpNow()
        let ledger = try harness.repository.ledgerSnapshot()
        storage.failWrites()
        await #expect(throws: CancellationError.self) {
            try await harness.service.restore(.stored(backup.id)) { _ in }
        }
        #expect(try harness.repository.ledgerSnapshot() == ledger)
    }
}

/// A real folder store whose writes fail with `failure` once `failWrites()` is called, as a read-only staging or
/// Backups folder makes them.
final class FailingWriteStorage: BackupStorage, @unchecked Sendable {
    private let base: FileBackupStorage
    private let failure: any Error
    private let lock = NSLock()
    private var failing = false

    init(folder: URL, failure: any Error) throws {
        base = try FileBackupStorage(folder: folder)
        self.failure = failure
    }

    func failWrites() {
        lock.withLock { failing = true }
    }

    func storedIDs() throws -> [UUID] { try base.storedIDs() }
    func listing(id: UUID) throws -> BackupFolderListing { try base.listing(id: id) }
    func read(id: UUID) throws -> BackupSnapshotFiles { try base.read(id: id) }
    func delete(id: UUID) throws { try base.delete(id: id) }
    func loadStatus() throws -> BackupStatus { try base.loadStatus() }
    func saveStatus(_ status: BackupStatus) throws { try base.saveStatus(status) }

    func write(_ files: BackupSnapshotFiles, id: UUID, cloningFrom earlier: UUID?) throws {
        if lock.withLock({ failing }) {
            throw failure
        }
        try base.write(files, id: id, cloningFrom: earlier)
    }
}
