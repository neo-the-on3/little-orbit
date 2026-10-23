import Foundation
import LittleOrbitDomain
import LittleOrbitFeatures
import Testing

@testable import LittleOrbitPersistence

/// UI Designer on 66e91b3 and Product Manager's D214: one backup folder that can't be read is that backup's
/// problem, never the whole list's. Couldn’t Load Backups is only for the Backups folder or `status.json`.
/// - Listed earlier this session: it keeps its row as last read, never 'Damaged' (D208.2).
/// - Not listed this session, a relaunch included (D210): D214's unreadable row. Its own date if it can be read,
///   otherwise Unknown and last; Unknown size, no counts, "Couldn’t be read"; Restore… and Export… unavailable;
///   Delete works (D214.3).
/// - Cleanup and Keep delete nothing while any folder can't be read (D208.3).
@MainActor
@Suite("One unreadable backup folder gets its own row (D214, D208.2, D208.3)", .serialized, .timeLimit(.minutes(2)))
struct BackupUnreadableFolderTests {
    private let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("unreadable-\(UUID().uuidString)", isDirectory: true)
    private let presentation = BackupPresentation(
        locale: Locale(identifier: "en_US"),
        timeZone: TimeZone(identifier: "Asia/Kolkata") ?? .gmt,
        device: .iPhone,
    )

    private func cleanUp() {
        if let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) {
            for name in names {
                try? FileManager.default.setAttributes(
                    [.posixPermissions: 0o755],
                    ofItemAtPath: folder.appendingPathComponent(name).path,
                )
            }
        }
        try? FileManager.default.removeItem(at: folder)
        try? FileManager.default.removeItem(at: URL(fileURLWithPath: folder.path + ".staging"))
    }

    /// Three automatic backups a day apart, oldest first, listed once.
    private func threeBackups(_ harness: BackupHarness) async throws -> [BackupRecord] {
        for day in 0..<3 {
            harness.advance(86_400)
            try harness.repository.saveAccount(
                Account(name: "Day \(day)", type: .cash, currencyCode: "INR", openingBalance: 1, sortOrder: 10)
            )
            _ = try await harness.service.backUpAutomaticallyIfNeeded()
        }
        let backups = try await harness.service.overview().backups
        #expect(backups.count == 3)
        return backups.reversed()
    }

    private static let unreadableMessage = "little-orbit couldn’t read this backup. Try again later."

    /// D214's row: no kind, version, size or counts, and the copy.
    private func expectUnreadableRow(_ record: BackupRecord, now: Date) {
        #expect(record.condition == .unreadable)
        #expect(!record.isRestorable)
        #expect(record.byteSize == nil)
        #expect(record.kind == nil)
        #expect(record.accountCount == nil && record.transactionCount == nil && record.attachmentCount == nil)
        let row = presentation.row(record, now: now)
        #expect(row.statusText == "Couldn’t be read")
        #expect(row.explanation == Self.unreadableMessage)
        #expect(row.sizeText == "Unknown")
        #expect(row.kindText == "Unknown")
        #expect(row.formatText == "Format unknown")
        #expect(row.countsText == nil)
        #expect(row.accountsText == nil && row.transactionsText == nil)
        #expect(row.detailAccountsText == "Unknown")
        #expect(!row.canRestore)
        #expect(row.attachmentsText == nil)
        #expect(row.accessibilityLabel.contains("Couldn’t be read"))
        #expect(!row.accessibilityLabel.contains("account"))
        #expect(!row.accessibilityLabel.contains("transaction"))
    }

    @Test("Never listed this session, with a date it can read: D214's row, sorted by that date; the others unchanged")
    func neverListedWithDate() async throws {
        defer { cleanUp() }
        let storage = try ScriptedStorage(folder: folder)
        let first = try BackupHarness(storage: storage)
        let backups = try await threeBackups(first)
        let middle = backups[1]
        storage.unreadable = [middle.id: middle.createdAt.addingTimeInterval(60)]

        // A new session over the same folders: the middle one was never listed in it.
        let harness = try BackupHarness(storage: storage)
        let window = harness.window()
        await window.load()

        #expect(!window.model.isLoadFailed)
        #expect(window.alert == nil)
        let listed = try await harness.service.overview().backups
        #expect(listed.map(\.id) == [backups[2].id, middle.id, backups[0].id])
        #expect(listed[0] == backups[2])
        #expect(listed[2] == backups[0])
        #expect(listed[1].createdAt == middle.createdAt.addingTimeInterval(60))
        expectUnreadableRow(listed[1], now: harness.now)
        #expect(window.model.rows.map(\.id) == listed.map(\.id))
        #expect(window.model.rows[1].title != "Unknown")
        #expect(window.model.rows[1].statusText == "Couldn’t be read")

        // Restore… and Export… are unavailable; Delete works with the usual confirmation.
        await window.requestRestore(middle.id)
        #expect(window.restorePrompt == nil)
        await window.requestExport(middle.id)
        #expect(window.exportPrompt == nil)
        await #expect(throws: BackupError.unreadableBackup) {
            try await harness.service.exportBackup(id: middle.id, named: "a.littleorbit-backup")
        }
        window.requestDelete(middle.id)
        let prompt = try #require(window.deletePrompt)
        await window.confirmDelete(prompt)
        #expect(window.alert == nil)
        #expect(try await harness.service.overview().backups.map(\.id) == [backups[2].id, backups[0].id])
    }

    @Test("Never listed this session, with no date it can read: Unknown, and sorted last")
    func neverListedUnknownDate() async throws {
        defer { cleanUp() }
        let storage = try ScriptedStorage(folder: folder)
        let first = try BackupHarness(storage: storage)
        let backups = try await threeBackups(first)
        storage.unreadable = [backups[2].id: Date?.none]

        let harness = try BackupHarness(storage: storage)
        let listed = try await harness.service.overview().backups

        #expect(listed.map(\.id) == [backups[1].id, backups[0].id, backups[2].id])
        #expect(listed[0] == backups[1])
        #expect(listed[1] == backups[0])
        #expect(!listed[2].isDateKnown)
        expectUnreadableRow(listed[2], now: harness.now)
        #expect(presentation.row(listed[2], now: harness.now).title == "Unknown")
    }

    @Test("Listed earlier this session, then unreadable: it keeps its row, isn't Damaged, and Restore… can't open it")
    func listedThisSession() async throws {
        defer { cleanUp() }
        let storage = try ScriptedStorage(folder: folder)
        let harness = try BackupHarness(storage: storage)
        let backups = try await threeBackups(harness)
        let window = harness.window()
        await window.load()
        storage.unreadable = [backups[1].id: Date?.none]

        await window.load()

        #expect(!window.model.isLoadFailed)
        let listed = try await harness.service.overview().backups
        #expect(listed == backups.reversed())
        await window.requestRestore(backups[1].id)
        #expect(window.restorePrompt == nil)
        #expect(window.alert == .unreadableBackup)
        #expect(try await harness.service.overview().backups[1].condition == .restorable)
    }

    @Test("A failed delete of D214's row shows Couldn’t Delete This Backup (D211.3)")
    func deleteFails() async throws {
        defer { cleanUp() }
        let storage = try ScriptedStorage(folder: folder)
        let first = try BackupHarness(storage: storage)
        let backups = try await threeBackups(first)
        storage.unreadable = [backups[0].id: Date?.none]
        let harness = try BackupHarness(storage: storage)
        let window = harness.window()
        await window.load()
        storage.deleteError = CocoaError(.fileWriteNoPermission)

        window.requestDelete(backups[0].id)
        await window.confirmDelete(try #require(window.deletePrompt))

        #expect(window.alert == .deleteFailed)
        #expect(window.model.rows.count == 3)
    }

    @Test("Keep deletes nothing while D214's row is there, and shows D208.3's Couldn’t Delete Old Backups")
    func keepDeletesNothing() async throws {
        defer { cleanUp() }
        let storage = try ScriptedStorage(folder: folder)
        let first = try BackupHarness(storage: storage)
        let backups = try await threeBackups(first)
        storage.unreadable = [backups[1].id: Date?.none]
        let harness = try BackupHarness(storage: storage)
        let window = harness.window()
        await window.load()
        let saved = harness.settings.retention()

        await window.proposeRetention(BackupRetention(recentAutomatic: 1, monthlyMonths: 0))

        #expect(window.prunePrompt == nil)
        #expect(window.alert == .cleanupBlocked)
        #expect(
            window.alert?.message
                == "little-orbit couldn’t read one of your backups, so none were deleted. Try again later. Your setting hasn’t changed."
        )
        #expect(harness.settings.retention() == saved)
        #expect(storage.deletes == 0)
        // Nor does the automatic backup's own cleanup. This session's clock starts where the first one did.
        harness.advance(5 * 86_400)
        try harness.repository.saveAccount(
            Account(name: "Later", type: .cash, currencyCode: "INR", openingBalance: 1, sortOrder: 10)
        )
        harness.settings.setRetention(BackupRetention(recentAutomatic: 1, monthlyMonths: 0))
        let made = try await harness.service.backUpAutomaticallyIfNeeded()
        #expect(made != nil)
        #expect(storage.deletes == 0)
        #expect(try await harness.service.overview().backups.count == 4)
    }

    /// The backup's folder set to mode 000. `nil` when this process can list it anyway (as root can).
    private func denyReading(_ url: URL) throws -> URL? {
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: url.path)
        if (try? FileManager.default.contentsOfDirectory(atPath: url.path)) != nil {
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
            return nil
        }
        return url
    }

    @Test("A real folder at mode 000 after a relaunch: D214's row next to two unchanged rows; Keep deletes nothing")
    func realFolderAfterRelaunch() async throws {
        let first = try BackupHarness()
        defer {
            try? FileManager.default.removeItem(at: first.folder)
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: first.folder.path + ".staging"))
        }
        let backups = try await threeBackups(first)
        guard let denied = try denyReading(first.backupFolder(backups[1].id)) else {
            return
        }
        // Read after the change of mode: where the platform has no birth time, the date can follow it.
        let created = try FileManager.default.attributesOfItem(atPath: denied.path)[.creationDate] as? Date
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: denied.path) }

        let harness = try BackupHarness(storage: FileBackupStorage(folder: first.folder))
        let window = harness.window()
        await window.load()

        #expect(!window.model.isLoadFailed)
        let listed = try await harness.service.overview().backups
        #expect(listed.count == 3)
        #expect(listed.contains(backups[0]))
        #expect(listed.contains(backups[2]))
        let bad = try #require(listed.first { $0.id != backups[0].id && $0.id != backups[2].id })
        expectUnreadableRow(bad, now: harness.now)
        if let created {
            #expect(bad.createdAt == created)
            #expect(listed.map(\.id) == [backups[2].id, bad.id, backups[0].id])
        } else {
            #expect(!bad.isDateKnown)
            #expect(listed.last?.id == bad.id)
        }

        let saved = harness.settings.retention()
        await window.proposeRetention(BackupRetention(recentAutomatic: 1, monthlyMonths: 0))
        #expect(window.alert == .cleanupBlocked)
        #expect(harness.settings.retention() == saved)
        #expect(try await harness.service.overview().backups.count == 3)
        // What was known is still there, the unreadable folder's last good read included; the row itself isn't
        // cached.
        let after = try harness.storage.loadStatus()
        #expect(after.known[backups[0].id] != nil)
        #expect(after.known[backups[1].id] == backups[1])
        #expect(after.known[bad.id] == nil)

        // Delete removes the folder, unreadable as it is.
        window.alert = nil
        window.requestDelete(bad.id)
        await window.confirmDelete(try #require(window.deletePrompt))
        #expect(window.alert == nil)
        #expect(try await harness.service.overview().backups.map(\.id) == [backups[2].id, backups[0].id])
        #expect(!FileManager.default.fileExists(atPath: denied.path))
    }

    @Test("A real folder at mode 000 listed earlier this session keeps its row (D208.2)")
    func realFolderThisSession() async throws {
        let harness = try BackupHarness()
        defer {
            try? FileManager.default.removeItem(at: harness.folder)
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: harness.folder.path + ".staging"))
        }
        let backups = try await threeBackups(harness)
        guard let denied = try denyReading(harness.backupFolder(backups[1].id)) else {
            return
        }
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: denied.path) }
        let window = harness.window()

        await window.load()

        #expect(!window.model.isLoadFailed)
        #expect(try await harness.service.overview().backups == backups.reversed())
        await window.requestRestore(backups[1].id)
        #expect(window.alert == .unreadableBackup)
        #expect(try await harness.service.overview().backups[1].condition == .restorable)
    }

    @Test("Once the folder can be read again, the next list shows it as the backup it is (D214.3, L78)")
    func recovers() async throws {
        let first = try BackupHarness()
        defer {
            try? FileManager.default.removeItem(at: first.folder)
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: first.folder.path + ".staging"))
        }
        let backups = try await threeBackups(first)
        guard let denied = try denyReading(first.backupFolder(backups[1].id)) else {
            return
        }
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: denied.path) }
        let harness = try BackupHarness(storage: FileBackupStorage(folder: first.folder))
        let window = harness.window()
        await window.load()
        #expect(window.model.rows.contains { $0.condition == .unreadable })

        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: denied.path)
        await window.load()

        #expect(try await harness.service.overview().backups == backups.reversed())
        #expect(window.model.rows.map(\.id) == backups.reversed().map(\.id))
        #expect(window.model.rows.allSatisfy { $0.condition == .restorable && $0.statusText == nil })
    }

    @Test("Recovery with the fake: the row is normal again on the next list (D214.3, L78)")
    func recoversScripted() async throws {
        defer { cleanUp() }
        let storage = try ScriptedStorage(folder: folder)
        let first = try BackupHarness(storage: storage)
        let backups = try await threeBackups(first)
        storage.unreadable = [backups[1].id: Date?.none]
        let harness = try BackupHarness(storage: storage)
        #expect(try await harness.service.overview().backups.last?.condition == .unreadable)

        storage.unreadable = [:]

        #expect(try await harness.service.overview().backups == backups.reversed())
    }
}
