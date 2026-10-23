import Foundation
import LittleOrbitDomain
import LittleOrbitFeatures
import Testing

/// Tech Architect on 8a43e74: a `status.json` that can't be read was read as an empty status, and the list then
/// saved that over it, losing the N4 line, the skip-after-restore marker and what was known about damaged folders.
/// Now the read failure is thrown, nothing is saved over the file, and it reaches D211's existing copy: lowering
/// Keep shows D211.6's general message, not D208.3's, which is for a backup that can't be read (D214.5).
@MainActor
@Suite("A status.json that can't be read is never saved over (R3, D211.5)", .serialized, .timeLimit(.minutes(2)))
struct BackupStatusReadFailureTests {
    private static let marker = "restored-fingerprint"

    /// A harness with one backup and a status carrying the N4 line and the skip marker, as saved on disk.
    private func harness() async throws -> (BackupHarness, URL) {
        let harness = try BackupHarness()
        _ = try await harness.service.backUpNow()
        var status = try harness.storage.loadStatus()
        status.lastFailure = .notEnoughStorage
        status.restoredFingerprint = Self.marker
        try harness.storage.saveStatus(status)
        return (harness, harness.folder.appendingPathComponent("status.json"))
    }

    private func allowReading(_ url: URL) {
        try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
    }

    @Test("status.json it may not read: the list shows Couldn’t Load Backups, and the file's bytes are unchanged")
    func statusDenied() async throws {
        let (harness, url) = try await harness()
        let bytes = try Data(contentsOf: url)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: url.path)
        defer { allowReading(url) }
        guard !FileManager.default.isReadableFile(atPath: url.path) else {
            // Root reads it anyway; `statusNotAFile` covers the same path there.
            return
        }
        let window = harness.window()

        await window.load()
        #expect(window.model.isLoadFailed)
        await #expect(throws: BackupError.loadFailed) { try await harness.service.overview() }

        await window.backUpNow()
        #expect(window.alert == .backUpFailed)
        window.alert = nil
        // D214.5: the list couldn't be read, not a backup, so D211.6's general message, not D208.3's.
        await window.proposeRetention(BackupRetention(recentAutomatic: 1, monthlyMonths: 0))
        #expect(window.alert == .cleanupFailed)
        #expect(window.alert?.title == "Couldn’t Delete Old Backups")
        #expect(
            window.alert?.message
                == "little-orbit couldn’t delete your older backups. Try again later. Your setting hasn’t changed."
        )
        #expect(window.errorMessage == nil)

        allowReading(url)
        #expect(try Data(contentsOf: url) == bytes)
        let status = try harness.storage.loadStatus()
        #expect(status.lastFailure == .notEnoughStorage)
        #expect(status.restoredFingerprint == Self.marker)
        await window.load()
        #expect(!window.model.isLoadFailed)
    }

    @Test("status.json that can't be read as a file, even by root: the list shows Couldn’t Load Backups")
    func statusNotAFile() async throws {
        let (harness, url) = try await harness()
        try FileManager.default.removeItem(at: url)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        let window = harness.window()

        await window.load()

        #expect(window.model.isLoadFailed)
        #expect(window.alert == nil)
        #expect(window.errorMessage == nil)
        await window.backUpNow()
        #expect(window.alert == .backUpFailed)
        window.alert = nil
        await window.proposeRetention(BackupRetention(recentAutomatic: 1, monthlyMonths: 0))
        #expect(window.alert == .cleanupFailed)
        #expect(try harness.storedFiles().filter { $0 != "status.json" }.count == 1)
    }

    @Test("A full disk, then a status that can't be read: Back Up Now saves no N4 line over it")
    func fullDiskStatusUnreadable() async throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("backup-tests-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: folder)
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: folder.path + ".staging"))
        }
        let storage = try ScriptedStorage(folder: folder)
        let harness = try BackupHarness(storage: storage)
        _ = try await harness.service.backUpNow()
        var status = try storage.loadStatus()
        status.restoredFingerprint = Self.marker
        try storage.saveStatus(status)
        let bytes = try Data(contentsOf: folder.appendingPathComponent("status.json"))
        let saves = storage.statusSaves
        storage.statusErrorAfterFullDisk = BackupFileReadError(CocoaError(.fileReadNoPermission))
        storage.diskFull = true

        await #expect(throws: BackupError.notEnoughStorage) { try await harness.service.backUpNow() }

        #expect(storage.statusSaves == saves)
        #expect(try Data(contentsOf: folder.appendingPathComponent("status.json")) == bytes)
    }
}
