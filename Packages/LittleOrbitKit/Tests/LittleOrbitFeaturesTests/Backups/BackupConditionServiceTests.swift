import Foundation
import LittleOrbitDomain
import LittleOrbitFeatures
import LittleOrbitPersistence
import Testing

/// L19–L43 through the real folder store: damaged and newer-format backups, the import order, the month and the
/// settings that aren't in a backup.
@MainActor
@Suite("Backup service: damaged, newer-format and imported backups", .timeLimit(.minutes(2)))
struct BackupConditionServiceTests {
    private func rewriteManifest(_ harness: BackupHarness, _ id: UUID, _ change: (inout [String: Any]) -> Void) throws {
        let url = harness.backupFolder(id).appendingPathComponent(BackupFormat.manifestPath)
        var object = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        change(&object)
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]).write(to: url)
    }

    private func entries(_ files: BackupSnapshotFiles) -> [BackupArchiveEntry] {
        files.paths.map { BackupArchiveEntry(path: $0, kind: .file(files[$0] ?? Data())) }
    }

    /// A newer-format copy of `files`: version 2, an unknown field, and its sizes as they were.
    private func newer(_ files: BackupSnapshotFiles) throws -> BackupSnapshotFiles {
        var files = files
        let manifest = try #require(files[BackupFormat.manifestPath])
        var object = try #require(try JSONSerialization.jsonObject(with: manifest) as? [String: Any])
        object["formatVersion"] = 2
        object["somethingNew"] = ["a": 1]
        files[BackupFormat.manifestPath] = try JSONSerialization.data(withJSONObject: object)
        return files
    }

    @Test("A 1-byte change after a check lists the backup as damaged; Restore and Export are refused (L29)")
    func oneByteChange() async throws {
        let harness = try BackupHarness()
        let backup = try await harness.service.backUpNow()
        #expect(try await harness.service.overview().backups.first?.condition == .restorable)
        let url = harness.backupFolder(backup.id).appendingPathComponent(BackupFormat.sharedPath)
        var data = try Data(contentsOf: url)
        data[0] ^= 0x01
        try data.write(to: url)

        await #expect(throws: BackupError.damaged) { try await harness.contents(.stored(backup.id)) }
        let listed = try #require(try await harness.service.overview().backups.first)
        #expect(listed.id == backup.id)
        #expect(listed.kind == .manual)
        #expect(listed.createdAt == backup.createdAt)
        #expect(listed.condition == .damaged)
        await #expect(throws: BackupError.damaged) { try await harness.service.exportBackup(id: backup.id) }

        let window = harness.window()
        let model = window.model
        try await model.load()
        let row = try #require(model.rows.first)
        #expect(row.statusText == "Damaged")
        #expect(!row.canRestore)
        await window.requestRestore(backup.id)
        #expect(window.restorePrompt == nil)
        await window.requestExport(backup.id)
        #expect(window.exportPrompt == nil)
        window.requestDelete(backup.id)
        await window.confirmDelete(try #require(window.deletePrompt))
        #expect(model.rows.isEmpty)
        #expect(try harness.storedFiles().isEmpty)
    }

    @Test("A folder from a newer format is listed as such, never damaged, and isn't pruned or counted (L35, L36)")
    func newerFormatFolder() async throws {
        let harness = try BackupHarness()
        let backup = try await harness.service.backUpNow()
        try rewriteManifest(harness, backup.id) { object in
            object["formatVersion"] = 2
            object["somethingNew"] = true
            object["files"] = "not the format-1 shape"
        }
        let listed = try #require(try await harness.service.overview().backups.first)
        #expect(listed.condition == .newerFormat)
        #expect(listed.formatVersion == 2)
        #expect(listed.kind == .manual)
        #expect(listed.createdAt == backup.createdAt)
        await #expect(throws: BackupError.newerFormat) { try await harness.contents(.stored(backup.id)) }
        await #expect(throws: BackupError.newerFormat) { try await harness.service.exportBackup(id: backup.id) }
        #expect(try await harness.service.overview().backups.first?.condition == .newerFormat)

        let window = harness.window()
        let model = window.model
        try await model.load()
        let row = try #require(model.rows.first)
        #expect(row.statusText == "Made by a newer version of little-orbit.")
        #expect(row.explanation?.hasSuffix("Update little-orbit to restore it.") == true)
        #expect(!row.canRestore)
    }

    @Test("A newer-format backup can be deleted, after confirming and App Lock (L43)")
    func deleteNewerFormat() async throws {
        let harness = try BackupHarness()
        let backup = try await harness.service.backUpNow()
        try rewriteManifest(harness, backup.id) { $0["formatVersion"] = 3 }
        let lock = RecordingAuthentication(allows: true)
        let window = harness.window(authentication: lock)
        let model = window.model
        try await model.load()
        window.requestDelete(backup.id)
        await window.confirmDelete(try #require(window.deletePrompt))
        #expect(lock.purposes == [.deleteBackup])
        #expect(model.rows.isEmpty)
        #expect(try harness.storedFiles().isEmpty)
    }

    @Test("An automatic backup is cleaned up only once checked; a newer one never counts toward N (L36)")
    func newerIsNotCounted() async throws {
        let harness = try BackupHarness()
        var made: [BackupRecord] = []
        for day in 0..<3 {
            harness.advance(86_400)
            try harness.repository.saveAccount(
                Account(name: "Day \(day)", type: .cash, currencyCode: "INR", openingBalance: 1, sortOrder: 20)
            )
            made.append(try #require(try await harness.service.backUpAutomaticallyIfNeeded()))
        }
        try rewriteManifest(harness, made[2].id) { $0["formatVersion"] = 2 }
        let plan = try await harness.service.cleanupPlan(for: BackupRetention(recentAutomatic: 1, monthlyMonths: 0))
        // The newest restorable one (day 1) is the one N keeps; day 0 goes; the newer one is left alone.
        #expect(plan.backups.map(\.id) == [made[0].id])
    }

    @Test("Opening a file checks, in order, and nothing is written until all checks pass (L21, L22, L42)")
    func importWritesNothing() async throws {
        let harness = try BackupHarness()
        let backup = try await harness.service.backUpNow()
        let files = try harness.storage.read(id: backup.id)
        let before = try harness.repository.ledgerSnapshot()
        let foldersBefore = try harness.storedFiles()
        let archives: [(Data, BackupError)] = [
            (try FakeBackupArchiving.crafted(entries(try newer(files))), .newerFormat),
            (
                try FakeBackupArchiving.crafted(
                    entries(try newer(files)) + [BackupArchiveEntry(path: "../outside.json", kind: .file(Data()))]
                ),
                .newerFormat,
            ),
            (
                try FakeBackupArchiving.crafted(
                    entries(files) + [BackupArchiveEntry(path: "../outside.json", kind: .file(Data()))]
                ),
                .damaged,
            ),
            (try FakeBackupArchiving.crafted(Array(entries(files).filter { $0.path != "manifest.json" })), .damaged),
            (Data("not an archive".utf8), .damaged),
        ]
        let window = harness.window()
        let model = window.model
        try await model.load()
        for (archive, error) in archives {
            await #expect(throws: error) { try await harness.contents(.file(archive)) }
            await window.restoreFromFile(.data(archive))
            #expect(window.restorePrompt == nil)
            #expect(
                window.alert?.title
                    == (error == .newerFormat
                        ? BackupPresentation.newerFormatTitle : BackupPresentation.damagedTitle)
            )
            window.alert = nil
        }
        #expect(try harness.repository.ledgerSnapshot() == before)
        #expect(try harness.storedFiles() == foldersBefore)
        #expect(try await harness.service.overview().backups.map(\.id) == [backup.id])
        let staging = URL(fileURLWithPath: harness.folder.path + ".staging")
        #expect(((try? FileManager.default.contentsOfDirectory(atPath: staging.path)) ?? []).isEmpty)
    }

    @Test("An export, sent as base64 MIME and back, restores with the same SHA-256 (L20)")
    func mimeRoundTrip() async throws {
        let harness = try BackupHarness()
        let backup = try await harness.service.backUpNow()
        let export = try await harness.exportData(backup.id)
        let mime = export.base64EncodedString(options: [.lineLength76Characters, .endLineWithCarriageReturn])
        let received = try #require(Data(base64Encoded: mime, options: .ignoreUnknownCharacters))
        #expect(received == export)
        #if canImport(CryptoKit)
            let hashing = CryptoKitBackupHashing()
            #expect(hashing.sha256Hex(received) == hashing.sha256Hex(export))
        #endif
        let contents = try await harness.contents(.file(received))
        let stored = try await harness.contents(.stored(backup.id))
        #expect(contents == stored)
    }

    @Test("Restoring an old backup keeps Keep at 10 and 12 (L23), and no backup holds N, M or their keys (L24)")
    func settingsStay() async throws {
        let harness = try BackupHarness()
        let backup = try await harness.service.backUpNow()
        harness.settings.setRetention(BackupRetention(recentAutomatic: 10, monthlyMonths: 12))
        let contents: BackupSource = .stored(backup.id)
        _ = try await harness.service.restore(contents) { _ in }
        #expect(harness.service.retention() == BackupRetention(recentAutomatic: 10, monthlyMonths: 12))
        let window = harness.window()
        let model = window.model
        try await model.load()
        #expect(model.keepFooter.hasPrefix("little-orbit keeps your 10 most recent automatic backups"))
        #expect(model.keepFooter.contains("for 12 months"))

        let latest = try #require(try await harness.service.overview().backups.first { $0.kind == .beforeRestore })
        let files = try harness.storage.read(id: latest.id)
        let export = try await harness.exportData(latest.id)
        // Latin-1 decodes any bytes, so binary files are scanned too.
        let texts = (files.paths.compactMap { files[$0] } + [export])
            .map { String(bytes: $0, encoding: .isoLatin1) ?? "" }
        for text in texts {
            for key in [
                "backups.retention.recentAutomatic", "backups.retention.monthlyMonths", "recentAutomatic",
                "monthlyMonths", "retention",
            ] {
                #expect(!text.contains(key))
            }
        }
    }

    @Test("The manifest records the month the backup was made, in the device's time zone then (L26)")
    func monthInManifest() async throws {
        let harness = try BackupHarness()
        // 00:30 IST on 1 Nov 2026 is 19:00 UTC on 31 Oct.
        harness.clock.now = Date(timeIntervalSince1970: 1_793_473_200)
        try harness.repository.saveAccount(
            Account(name: "November", type: .cash, currencyCode: "INR", openingBalance: 1, sortOrder: 20)
        )
        let backup = try #require(try await harness.service.backUpAutomaticallyIfNeeded())
        let manifest = try #require(try harness.storage.read(id: backup.id)[BackupFormat.manifestPath])
        let object = try #require(try JSONSerialization.jsonObject(with: manifest) as? [String: Any])
        let backupSection = try #require(object["backup"] as? [String: Any])
        #expect(backupSection["month"] as? String == "2026-11")
    }
}
