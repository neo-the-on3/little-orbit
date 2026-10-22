import Foundation
import LittleOrbitDomain
import LittleOrbitFeatures
import Testing

/// A stored backup that can't be read (D208.2), and cleanup while one can't be read (R3, D208.3).
@MainActor
@Suite("Stored backups that can't be read (D208.2, D208.3)", .timeLimit(.minutes(2)))
struct BackupD208ReadTests {
    private let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("backup-tests-\(UUID().uuidString)", isDirectory: true)

    private func automaticBackups(_ harness: BackupHarness, count: Int) async throws {
        for day in 0..<count {
            harness.advance(86_400)
            try harness.repository.saveAccount(
                Account(name: "Day \(day)", type: .cash, currencyCode: "INR", openingBalance: 1, sortOrder: 10)
            )
            _ = try await harness.service.backUpAutomaticallyIfNeeded()
        }
    }

    @Test("Restoring a stored backup that can't be read shows Couldn’t Open Backup; it stays restorable (D208.2)")
    func storedRestoreReadError() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let storage = try LockedFilesStorage(folder: folder)
        let harness = try BackupHarness(storage: storage)
        let backup = try await harness.service.backUpNow()
        let window = harness.window()
        await window.load()
        storage.lockFiles()

        await window.requestRestore(backup.id)

        #expect(window.restorePrompt == nil)
        #expect(window.alert == .unreadableBackup)
        #expect(window.alert?.title == "Couldn’t Open Backup")
        #expect(
            window.alert?.message
                == "little-orbit couldn’t read this backup. Try again later. Your data hasn’t changed."
        )
        #expect(window.errorMessage == nil)
        await #expect(throws: BackupError.unreadableBackup) {
            try await harness.service.checkBackup(.stored(backup.id))
        }
        // Never marked damaged: once it can be read again, it's restorable and checks out.
        storage.unlockFiles()
        let listed = try await harness.service.overview().backups
        #expect(listed.map(\.condition) == [.restorable])
        _ = try await harness.service.checkBackup(.stored(backup.id))
        #expect(storage.deletes == 0)
    }

    @Test("Lowering N while a backup can't be read shows Couldn’t Delete Old Backups and changes nothing (D208.3)")
    func lowerWhileUnreadable() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let storage = try LockedFilesStorage(folder: folder)
        let harness = try BackupHarness(storage: storage)
        try await automaticBackups(harness, count: 3)
        let window = harness.window()
        await window.load()
        let saved = window.model.retention
        storage.lockFiles()

        await window.proposeRetention(BackupRetention(recentAutomatic: 1, monthlyMonths: 0))

        #expect(window.prunePrompt == nil)
        #expect(window.alert == .cleanupBlocked)
        #expect(window.alert?.title == "Couldn’t Delete Old Backups")
        #expect(
            window.alert?.message
                == "little-orbit couldn’t read one of your backups, so none were deleted. Try again later. "
                + "Your setting hasn’t changed."
        )
        #expect(window.errorMessage == nil)
        #expect(harness.settings.retention() == saved)
        #expect(storage.deletes == 0)
    }

    @Test("A backup that can't be read after Delete 2 Backups? shows the same alert, with the setting kept (D208.3)")
    func confirmWhileUnreadable() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let storage = try LockedFilesStorage(folder: folder)
        let harness = try BackupHarness(storage: storage)
        try await automaticBackups(harness, count: 3)
        let window = harness.window()
        await window.load()
        let saved = window.model.retention
        await window.proposeRetention(BackupRetention(recentAutomatic: 1, monthlyMonths: 0))
        let prompt = try #require(window.prunePrompt)
        storage.lockFiles()

        await window.confirmPrune(prompt)

        #expect(window.alert == .cleanupBlocked)
        #expect(window.errorMessage == nil)
        #expect(harness.settings.retention() == saved)
        #expect(storage.deletes == 0)
        storage.unlockFiles()
        #expect(try await harness.service.overview().backups.count == 3)
    }

    @Test("Both errors are their own alerts, never Something Went Wrong (D208.2, D208.3)")
    func feedback() {
        #expect(BackupsViewModel.feedback(for: BackupError.cleanupBlocked) == .alert(.cleanupBlocked))
        #expect(BackupsViewModel.feedback(for: BackupError.unreadableBackup) == .alert(.unreadableBackup))
    }
}
