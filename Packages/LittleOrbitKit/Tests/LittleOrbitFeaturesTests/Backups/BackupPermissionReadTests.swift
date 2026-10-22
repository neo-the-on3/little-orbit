import Foundation
import LittleOrbitDomain
import LittleOrbitFeatures
import Testing

/// Tester finding 1 on 4c8b0b3: a file in a stored backup that can't be read for lack of permission. Opening it
/// for reading reports Cocoa's *write* code 513 ("You don’t have permission to save the file"), with POSIX 13
/// underneath. Any error from reading a backup's files, whatever its code, is a read failure: Couldn’t Open Backup
/// on restore (D208.2), Couldn’t Delete Old Backups when N or M is lowered (D208.3), and never 'Damaged'.
@MainActor
@Suite("Backups that can't be read for lack of permission (D208.2, D208.3)", .serialized, .timeLimit(.minutes(2)))
struct BackupPermissionReadTests {
    /// Cocoa's error for `FileHandle(forReadingFrom:)` on a file it may not open, on Apple platforms.
    private static let writeCodeDenial = NSError(
        domain: NSCocoaErrorDomain,
        code: CocoaError.Code.fileWriteNoPermission.rawValue,
        userInfo: [NSUnderlyingErrorKey: NSError(domain: NSPOSIXErrorDomain, code: Int(EACCES))],
    )

    private func automaticBackups(_ harness: BackupHarness, count: Int) async throws {
        for day in 0..<count {
            harness.advance(86_400)
            try harness.repository.saveAccount(
                Account(name: "Day \(day)", type: .cash, currencyCode: "INR", openingBalance: 1, sortOrder: 10)
            )
            _ = try await harness.service.backUpAutomaticallyIfNeeded()
        }
    }

    /// `shared.json` in the backup set to mode 000. `nil` when this process can read it anyway (as root can).
    private func denyReading(_ harness: BackupHarness, _ id: UUID) throws -> URL? {
        let file = harness.backupFolder(id).appendingPathComponent("shared.json")
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: file.path)
        if FileManager.default.isReadableFile(atPath: file.path) {
            try allowReading(file)
            return nil
        }
        return file
    }

    private func allowReading(_ file: URL) throws {
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path)
    }

    @Test("Restore… on a backup with a file it may not read shows Couldn’t Open Backup; it stays restorable")
    func restoreDenied() async throws {
        let harness = try BackupHarness()
        let backup = try await harness.service.backUpNow()
        let window = harness.window()
        await window.load()
        guard let file = try denyReading(harness, backup.id) else {
            return
        }
        defer { try? allowReading(file) }

        await window.requestRestore(backup.id)

        #expect(window.restorePrompt == nil)
        #expect(window.alert == .unreadableBackup)
        #expect(window.errorMessage == nil)
        await #expect(throws: BackupError.unreadableBackup) {
            try await harness.service.checkBackup(.stored(backup.id))
        }
        #expect(try await harness.service.overview().backups.map(\.condition) == [.restorable])
        try allowReading(file)
        _ = try await harness.service.checkBackup(.stored(backup.id))
    }

    @Test("Lowering N with a file it may not read shows Couldn’t Delete Old Backups; N isn't saved")
    func lowerDenied() async throws {
        let harness = try BackupHarness()
        try await automaticBackups(harness, count: 3)
        let window = harness.window()
        await window.load()
        let saved = window.model.retention
        let oldest = try #require(try await harness.service.overview().backups.last)
        guard let file = try denyReading(harness, oldest.id) else {
            return
        }
        defer { try? allowReading(file) }

        await window.proposeRetention(BackupRetention(recentAutomatic: 1, monthlyMonths: 0))

        #expect(window.prunePrompt == nil)
        #expect(window.alert == .cleanupBlocked)
        #expect(window.errorMessage == nil)
        #expect(harness.settings.retention() == saved)
        #expect(try await harness.service.overview().backups.count == 3)
        #expect(try await harness.service.overview().backups.allSatisfy { $0.condition == .restorable })
    }

    @Test("Cocoa's write code 513 from reading a stored file, with POSIX 13 under it, is still a read failure")
    func writeCodeFromARead() async throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("backup-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        // As the file store throws it: wrapped, because it came from reading one of the backup's files.
        let storage = try LockedFilesStorage(folder: folder, failure: BackupFileReadError(Self.writeCodeDenial))
        let harness = try BackupHarness(storage: storage)
        try await automaticBackups(harness, count: 3)
        let window = harness.window()
        await window.load()
        let saved = window.model.retention
        let backup = try #require(try await harness.service.overview().backups.first)
        storage.lockFiles()

        await window.requestRestore(backup.id)
        #expect(window.alert == .unreadableBackup)
        window.alert = nil
        await window.proposeRetention(BackupRetention(recentAutomatic: 1, monthlyMonths: 0))
        #expect(window.alert == .cleanupBlocked)
        #expect(harness.settings.retention() == saved)
        #expect(storage.deletes == 0)
    }

    @Test("Plain EPERM and EACCES from a read are read failures too")
    func posixDenials() async throws {
        for code in [POSIXErrorCode.EPERM, .EACCES] {
            let folder = FileManager.default.temporaryDirectory
                .appendingPathComponent("backup-tests-\(UUID().uuidString)", isDirectory: true)
            defer { try? FileManager.default.removeItem(at: folder) }
            let storage = try LockedFilesStorage(folder: folder, failure: POSIXError(code))
            let harness = try BackupHarness(storage: storage)
            let backup = try await harness.service.backUpNow()
            storage.lockFiles()
            await #expect(throws: BackupError.unreadableBackup) {
                try await harness.service.checkBackup(.stored(backup.id))
            }
        }
    }
}
